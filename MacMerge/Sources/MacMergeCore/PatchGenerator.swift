import CXDiff
import Foundation

public struct PatchGeneratorOptions: Equatable, Sendable {
    public var oldPath: String
    public var newPath: String
    public var contextLines: Int
    public var reverse: Bool
    public var maximumOutputBytes: Int

    public init(
        oldPath: String = "a/file",
        newPath: String = "b/file",
        contextLines: Int = 3,
        reverse: Bool = false,
        maximumOutputBytes: Int = 64 * 1024 * 1024
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.contextLines = contextLines
        self.reverse = reverse
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public struct PatchGeneratorAppendOptions: Equatable, Sendable {
    public var lineEnding: LineEnding
    public var maximumFileBytes: Int

    public init(
        lineEnding: LineEnding = .lf,
        maximumFileBytes: Int = 64 * 1024 * 1024
    ) {
        self.lineEnding = lineEnding
        self.maximumFileBytes = maximumFileBytes
    }
}

public enum PatchGeneratorError: Error, LocalizedError, Equatable, Sendable {
    case invalidContextLines(Int)
    case invalidMaximumOutputBytes(Int)
    case invalidMaximumFileBytes(Int)
    case invalidPath(String)
    case invalidFileURL(String)
    case notRegularFile(String)
    case changedOnDisk
    case metadataPreservationFailed(String)
    case outputTooLarge(maximumBytes: Int)
    case fileTooLarge(maximumBytes: Int)
    case secureAppendUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidContextLines(let value):
            "Patch context line count must not be negative: \(value)."
        case .invalidMaximumOutputBytes(let value):
            "Patch output byte limit must not be negative: \(value)."
        case .invalidMaximumFileBytes(let value):
            "Patch file byte limit must not be negative: \(value)."
        case .invalidPath(let path):
            "Patch path is empty or contains NUL: \(path)."
        case .invalidFileURL(let path):
            "Patch destination is not a valid absolute local file URL: \(path)."
        case .notRegularFile(let path):
            "Patch destination is not a regular file: \(path)."
        case .changedOnDisk:
            "Patch destination changed while preparing the append."
        case .metadataPreservationFailed(let path):
            "Patch destination metadata could not be preserved: \(path)."
        case .outputTooLarge(let maximumBytes):
            "Generated patch exceeds the \(maximumBytes)-byte output limit."
        case .fileTooLarge(let maximumBytes):
            "Appended patch file exceeds the \(maximumBytes)-byte file limit."
        case .secureAppendUnavailable:
            "Secure append requires identity-conditioned replacement, which is unavailable through current file primitives. No file was changed."
        }
    }
}

public enum PatchGenerator: Sendable {
    /// Composes an append without decoding or normalizing any existing bytes.
    public static func appending(
        generatedPatch: String,
        to existingData: Data,
        options: PatchGeneratorAppendOptions = PatchGeneratorAppendOptions()
    ) throws -> Data {
        try composedAppend(generatedPatch, to: existingData, options: options).data
    }

    /// Fails closed until identity-conditioned replacement is available.
    public static func append(
        generatedPatch: String,
        to fileURL: URL,
        options: PatchGeneratorAppendOptions = PatchGeneratorAppendOptions()
    ) throws -> Never {
        try validate(appendOptions: options)
        _ = try validatedLocalFileURL(fileURL)
        _ = generatedPatch
        throw PatchGeneratorError.secureAppendUnavailable
    }

    /// Generates a bounded patch, then fails closed without touching the file.
    public static func append(
        old oldText: String,
        new newText: String,
        to fileURL: URL,
        options: PatchGeneratorOptions = PatchGeneratorOptions(),
        appendOptions: PatchGeneratorAppendOptions = PatchGeneratorAppendOptions()
    ) throws -> Never {
        try append(
            generatedPatch: generate(old: oldText, new: newText, options: options),
            to: fileURL,
            options: appendOptions
        )
    }

    public static func generate(
        old oldText: String,
        new newText: String,
        options: PatchGeneratorOptions = PatchGeneratorOptions()
    ) throws -> String {
        guard options.contextLines >= 0 else {
            throw PatchGeneratorError.invalidContextLines(options.contextLines)
        }
        guard options.maximumOutputBytes >= 0 else {
            throw PatchGeneratorError.invalidMaximumOutputBytes(options.maximumOutputBytes)
        }
        try validate(path: options.oldPath)
        try validate(path: options.newPath)

        let oldInput = options.reverse ? newText : oldText
        let newInput = options.reverse ? oldText : newText
        let maximumInputBytes = Int(MMX_MAX_INPUT_SIZE)
        guard oldInput.utf8.count <= maximumInputBytes,
            newInput.utf8.count <= maximumInputBytes
        else {
            throw LineDiffError.inputTooLarge(maximumBytes: maximumInputBytes)
        }
        let maximumLines = Int(MMX_MAX_LINE_COUNT)
        try validateRecordCount(oldInput, maximumLines: maximumLines)
        try validateRecordCount(newInput, maximumLines: maximumLines)
        let oldPath = options.reverse ? options.newPath : options.oldPath
        let newPath = options.reverse ? options.oldPath : options.newPath
        let oldDocument = PatchDocument(oldInput)
        let newDocument = PatchDocument(newInput)
        let comparisonTexts = PatchDocument.comparisonTexts(
            old: oldDocument,
            new: newDocument
        )
        let rows = try LineDiff.compare(
            left: comparisonTexts.old,
            right: comparisonTexts.new,
            options: LineDiffOptions(
                ignoreLineEndings: false,
                lineFiltersEnabled: false,
                substitutionsEnabled: false
            )
        )
        let hunks = hunkRanges(rows: rows, contextLines: options.contextLines)
        guard !hunks.isEmpty else { return "" }

        var output = BoundedOutput(maximumBytes: options.maximumOutputBytes)
        try output.append("--- ")
        try output.append(headerPath(oldPath))
        try output.appendLF()
        try output.append("+++ ")
        try output.append(headerPath(newPath))
        try output.appendLF()

        var rowIndex = 0
        var oldLinesConsumed = 0
        var newLinesConsumed = 0
        for hunk in hunks {
            while rowIndex < hunk.lowerBound {
                let id = rows[rowIndex].id
                if id.leftNumber != nil { oldLinesConsumed += 1 }
                if id.rightNumber != nil { newLinesConsumed += 1 }
                rowIndex += 1
            }

            var oldCount = 0
            var newCount = 0
            for row in rows[hunk] {
                let id = row.id
                if id.leftNumber != nil { oldCount += 1 }
                if id.rightNumber != nil { newCount += 1 }
            }
            let oldStart = oldCount == 0 ? oldLinesConsumed : oldLinesConsumed + 1
            let newStart = newCount == 0 ? newLinesConsumed : newLinesConsumed + 1
            try output.append("@@ -")
            try output.append(range(start: oldStart, count: oldCount))
            try output.append(" +")
            try output.append(range(start: newStart, count: newCount))
            try output.append(" @@")
            try output.appendLF()

            var bodyIndex = hunk.lowerBound
            while bodyIndex < hunk.upperBound {
                if rows[bodyIndex].kind == .unchanged {
                    let row = rows[bodyIndex]
                    try append(
                        record: row.id.leftNumber.flatMap(oldDocument.record)
                            ?? row.id.rightNumber.flatMap(newDocument.record),
                        prefix: 0x20,
                        to: &output
                    )
                    bodyIndex += 1
                    continue
                }

                var changeEnd = bodyIndex + 1
                while changeEnd < hunk.upperBound, rows[changeEnd].kind != .unchanged {
                    changeEnd += 1
                }
                for row in rows[bodyIndex..<changeEnd] {
                    try append(
                        record: row.id.leftNumber.flatMap(oldDocument.record),
                        prefix: 0x2D,
                        to: &output
                    )
                }
                for row in rows[bodyIndex..<changeEnd] {
                    try append(
                        record: row.id.rightNumber.flatMap(newDocument.record),
                        prefix: 0x2B,
                        to: &output
                    )
                }
                bodyIndex = changeEnd
            }

            for row in rows[hunk] {
                let id = row.id
                if id.leftNumber != nil { oldLinesConsumed += 1 }
                if id.rightNumber != nil { newLinesConsumed += 1 }
            }
            rowIndex = hunk.upperBound
        }
        return output.string
    }

    static func validateRecordCount(_ text: String, maximumLines: Int) throws {
        var lineCount = 0
        var lastByte: UInt8?
        for byte in text.utf8 {
            lastByte = byte
            if byte == 0x0A {
                lineCount += 1
                guard lineCount <= maximumLines else {
                    throw LineDiffError.tooManyLines(maximumLines: maximumLines)
                }
            }
        }
        if lastByte != nil, lastByte != 0x0A, lineCount == maximumLines {
            throw LineDiffError.tooManyLines(maximumLines: maximumLines)
        }
    }

    private static func validate(path: String) throws {
        guard !path.isEmpty,
            !path.utf8.contains(0)
        else {
            throw PatchGeneratorError.invalidPath(path)
        }
    }

    private static func validate(appendOptions: PatchGeneratorAppendOptions) throws {
        guard appendOptions.maximumFileBytes >= 0 else {
            throw PatchGeneratorError.invalidMaximumFileBytes(appendOptions.maximumFileBytes)
        }
    }

    private static func composedAppend(
        _ generatedPatch: String,
        to existingData: Data,
        options: PatchGeneratorAppendOptions
    ) throws -> (data: Data, appendedBytes: Int) {
        try validate(appendOptions: options)
        guard existingData.count <= options.maximumFileBytes else {
            throw PatchGeneratorError.fileTooLarge(maximumBytes: options.maximumFileBytes)
        }
        guard !generatedPatch.isEmpty else { return (existingData, 0) }

        var output = BoundedData(existingData, maximumBytes: options.maximumFileBytes)
        if let finalByte = existingData.last, finalByte != 0x0A, finalByte != 0x0D {
            try output.append(contentsOf: Array(options.lineEnding.rawValue.utf8))
        }
        let selectedEnding = Array(options.lineEnding.rawValue.utf8)
        for byte in generatedPatch.utf8 {
            if byte == 0x0A {
                try output.append(contentsOf: selectedEnding)
            } else {
                try output.append(byte)
            }
        }
        return (output.data, output.data.count - existingData.count)
    }

    private static func headerPath(_ path: String) -> String {
        let bytes = Array(path.utf8)
        let needsQuoting = bytes.contains {
            $0 <= 0x20 || $0 >= 0x7F || $0 == 0x22 || $0 == 0x5C
        }
        guard needsQuoting else { return path }

        var escaped: [UInt8] = [0x22]
        escaped.reserveCapacity(bytes.count + 2)
        for byte in bytes {
            switch byte {
            case 0x07: escaped.append(contentsOf: [0x5C, 0x61])
            case 0x08: escaped.append(contentsOf: [0x5C, 0x62])
            case 0x09: escaped.append(contentsOf: [0x5C, 0x74])
            case 0x0A: escaped.append(contentsOf: [0x5C, 0x6E])
            case 0x0B: escaped.append(contentsOf: [0x5C, 0x76])
            case 0x0C: escaped.append(contentsOf: [0x5C, 0x66])
            case 0x0D: escaped.append(contentsOf: [0x5C, 0x72])
            case 0x22, 0x5C:
                escaped.append(0x5C)
                escaped.append(byte)
            case 0x20...0x7E:
                escaped.append(byte)
            default:
                escaped.append(0x5C)
                escaped.append(0x30 + ((byte >> 6) & 0x07))
                escaped.append(0x30 + ((byte >> 3) & 0x07))
                escaped.append(0x30 + (byte & 0x07))
            }
        }
        escaped.append(0x22)
        return String(decoding: escaped, as: UTF8.self)
    }

    private static func hunkRanges(rows: [DiffRow], contextLines: Int) -> [Range<Int>] {
        var hunks: [Range<Int>] = []
        for index in rows.indices where rows[index].kind != .unchanged {
            let lowerBound = index > contextLines ? index - contextLines : 0
            let linesAfter = rows.count - index - 1
            let upperBound = contextLines >= linesAfter ? rows.count : index + contextLines + 1
            if let lastIndex = hunks.indices.last, lowerBound <= hunks[lastIndex].upperBound {
                hunks[lastIndex] = hunks[lastIndex].lowerBound..<max(hunks[lastIndex].upperBound, upperBound)
            } else {
                hunks.append(lowerBound..<upperBound)
            }
        }
        return hunks
    }

    private static func range(start: Int, count: Int) -> String {
        count == 1 ? String(start) : "\(start),\(count)"
    }

    private static func append(
        record: PatchDocument.Record?,
        prefix: UInt8,
        to output: inout BoundedOutput
    ) throws {
        guard let record else { return }
        try output.append(byte: prefix)
        try output.append(record.payload)
        try output.appendLF()
        if !record.hasLineFeed {
            try output.append("\\ No newline at end of file")
            try output.appendLF()
        }
    }
}

private struct PatchDocument {
    struct Record {
        let payload: [UInt8]
        let hasLineFeed: Bool
    }

    let records: [Record]

    init(_ source: String) {
        let bytes = Array(source.utf8)
        var records: [Record] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0A {
            records.append(Record(payload: Array(bytes[start..<index]), hasLineFeed: true))
            start = index + 1
        }
        if start < bytes.count {
            records.append(Record(payload: Array(bytes[start...]), hasLineFeed: false))
        }
        self.records = records
    }

    func record(number: Int) -> Record? {
        guard number > 0, number <= records.count else { return nil }
        return records[number - 1]
    }

    static func comparisonTexts(
        old: PatchDocument,
        new: PatchDocument
    ) -> (old: String, new: String) {
        var identifiers: [[UInt8]: Int] = [:]
        return (
            comparisonText(for: old, identifiers: &identifiers),
            comparisonText(for: new, identifiers: &identifiers)
        )
    }

    private static func comparisonText(
        for document: PatchDocument,
        identifiers: inout [[UInt8]: Int]
    ) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(document.records.count * 4)
        for record in document.records {
            let identifier: Int
            if let existing = identifiers[record.payload] {
                identifier = existing
            } else {
                identifier = identifiers.count
                identifiers[record.payload] = identifier
            }
            bytes.append(contentsOf: String(identifier).utf8)
            if record.hasLineFeed { bytes.append(0x0A) }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private struct BoundedOutput {
    private var bytes: [UInt8] = []
    private let maximumBytes: Int

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        bytes.reserveCapacity(min(maximumBytes, 64 * 1024))
    }

    var string: String { String(decoding: bytes, as: UTF8.self) }

    mutating func append(_ value: String) throws {
        try reserve(value.utf8.count)
        bytes.append(contentsOf: value.utf8)
    }

    mutating func append(_ value: [UInt8]) throws {
        try reserve(value.count)
        bytes.append(contentsOf: value)
    }

    mutating func append(byte: UInt8) throws {
        try reserve(1)
        bytes.append(byte)
    }

    mutating func appendLF() throws {
        try append(byte: 0x0A)
    }

    private mutating func reserve(_ count: Int) throws {
        guard count <= maximumBytes - bytes.count else {
            throw PatchGeneratorError.outputTooLarge(maximumBytes: maximumBytes)
        }
    }
}

private struct BoundedData {
    private(set) var data: Data
    private let maximumBytes: Int

    init(_ data: Data, maximumBytes: Int) {
        self.data = data
        self.maximumBytes = maximumBytes
        self.data.reserveCapacity(min(maximumBytes, data.count + 64 * 1024))
    }

    mutating func append(_ byte: UInt8) throws {
        try reserve(1)
        data.append(byte)
    }

    mutating func append(contentsOf bytes: [UInt8]) throws {
        try reserve(bytes.count)
        data.append(contentsOf: bytes)
    }

    private func reserve(_ count: Int) throws {
        guard count <= maximumBytes - data.count else {
            throw PatchGeneratorError.fileTooLarge(maximumBytes: maximumBytes)
        }
    }
}

private struct PatchAppendFileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let links: nlink_t
    let owner: uid_t
    let group: gid_t
    let size: off_t
    let flags: UInt32
    let generation: UInt32
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init(_ information: stat) {
        device = information.st_dev
        inode = information.st_ino
        mode = information.st_mode
        links = information.st_nlink
        owner = information.st_uid
        group = information.st_gid
        size = information.st_size
        flags = information.st_flags
        generation = information.st_gen
        modifiedSeconds = information.st_mtimespec.tv_sec
        modifiedNanoseconds = information.st_mtimespec.tv_nsec
        changedSeconds = information.st_ctimespec.tv_sec
        changedNanoseconds = information.st_ctimespec.tv_nsec
    }

    func hasMetadataCopied(from source: PatchAppendFileIdentity) -> Bool {
        mode == source.mode
            && owner == source.owner
            && group == source.group
            && flags == source.flags
    }
}

private struct PatchAppendDirectoryIdentity: Equatable {
    let device: dev_t
    let inode: ino_t

    init(_ information: stat) {
        device = information.st_dev
        inode = information.st_ino
    }
}

private struct PatchAppendStableReference: Sendable {
    var storage = [UInt8](repeating: 0, count: 80)
}

private struct PatchAppendStableReferenceAPI: @unchecked Sendable {
    typealias MakeReference = @convention(c) (
        UnsafePointer<UInt8>?,
        UInt32,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<UInt8>?
    ) -> OSStatus
    typealias ResolveReference = @convention(c) (
        UnsafeRawPointer?,
        UnsafeMutablePointer<UInt8>?,
        UInt32
    ) -> OSStatus
    typealias DeleteReference = @convention(c) (UnsafeRawPointer?) -> Int16

    static let shared: PatchAppendStableReferenceAPI? = {
        guard let handle = Darwin.dlopen(
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            RTLD_LAZY | RTLD_LOCAL
        ) else { return nil }
        guard let makeReference = Darwin.dlsym(handle, "FSPathMakeRefWithOptions"),
            let resolveReference = Darwin.dlsym(handle, "FSRefMakePath"),
            let deleteReference = Darwin.dlsym(handle, "FSDeleteObject")
        else {
            Darwin.dlclose(handle)
            return nil
        }
        return PatchAppendStableReferenceAPI(
            handle: handle,
            makeReference: unsafeBitCast(makeReference, to: MakeReference.self),
            resolveReference: unsafeBitCast(resolveReference, to: ResolveReference.self),
            deleteReference: unsafeBitCast(deleteReference, to: DeleteReference.self)
        )
    }()

    private let handle: UnsafeMutableRawPointer
    private let makeReference: MakeReference
    private let resolveReference: ResolveReference
    private let deleteReference: DeleteReference

    func makeReference(to url: URL) -> PatchAppendStableReference? {
        var reference = PatchAppendStableReference()
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return OSStatus(-1) }
            return reference.storage.withUnsafeMutableBytes { storage in
                makeReference(
                    UnsafeRawPointer(path).assumingMemoryBound(to: UInt8.self),
                    1,
                    storage.baseAddress,
                    nil
                )
            }
        }
        return status == 0 ? reference : nil
    }

    func resolve(_ reference: PatchAppendStableReference) -> URL? {
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        let status = reference.storage.withUnsafeBytes { storage in
            path.withUnsafeMutableBufferPointer { pathBuffer in
                resolveReference(
                    storage.baseAddress,
                    UnsafeMutableRawPointer(pathBuffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
                    UInt32(pathBuffer.count)
                )
            }
        }
        guard status == 0, let pathStart = path.withUnsafeBufferPointer({ $0.baseAddress }) else {
            return nil
        }
        return URL(
            fileURLWithFileSystemRepresentation: pathStart,
            isDirectory: false,
            relativeTo: nil
        )
    }

    func delete(_ reference: PatchAppendStableReference) -> OSStatus {
        reference.storage.withUnsafeBytes { storage in
            OSStatus(deleteReference(storage.baseAddress))
        }
    }
}

private func validatedLocalFileURL(_ url: URL) throws -> URL {
    guard url.isFileURL,
        url.baseURL == nil,
        url.query == nil,
        url.fragment == nil,
        !url.hasDirectoryPath,
        url.path.hasPrefix("/"),
        !url.path.hasPrefix("//"),
        !url.path.utf8.contains(0),
        url.lastPathComponent != ".",
        url.lastPathComponent != ".."
    else {
        throw PatchGeneratorError.invalidFileURL(url.absoluteString)
    }
    let components = url.path.split(separator: "/", omittingEmptySubsequences: false)
    guard components.first?.isEmpty == true,
        components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else {
        throw PatchGeneratorError.invalidFileURL(url.absoluteString)
    }
    return url
}

private func openParentDirectory(of url: URL) throws -> (descriptor: Int32, name: String) {
    let components = url.pathComponents
    guard components.first == "/", components.count > 1,
        let name = components.last, name != ".", name != ".."
    else {
        throw PatchGeneratorError.invalidFileURL(url.absoluteString)
    }

    var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw appendPOSIXError() }
    do {
        for component in components.dropFirst().dropLast() {
            let next = component.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard next >= 0 else { throw appendPOSIXError() }
            Darwin.close(descriptor)
            descriptor = next
        }
        return (descriptor, name)
    } catch {
        Darwin.close(descriptor)
        throw error
    }
}

private func appendFileIdentity(_ descriptor: Int32, path: String) throws -> PatchAppendFileIdentity {
    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else { throw appendPOSIXError() }
    guard information.st_mode & S_IFMT == S_IFREG else {
        throw PatchGeneratorError.notRegularFile(path)
    }
    return PatchAppendFileIdentity(information)
}

private func appendPathIdentity(
    directoryFD: Int32,
    name: String
) throws -> PatchAppendFileIdentity {
    var information = stat()
    let result = name.withCString {
        Darwin.fstatat(directoryFD, $0, &information, AT_SYMLINK_NOFOLLOW)
    }
    guard result == 0 else { throw appendPOSIXError() }
    guard information.st_mode & S_IFMT == S_IFREG else {
        throw PatchGeneratorError.notRegularFile(name)
    }
    return PatchAppendFileIdentity(information)
}

private func appendDirectoryIdentity(
    _ descriptor: Int32,
    path: String
) throws -> PatchAppendDirectoryIdentity {
    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else { throw appendPOSIXError() }
    guard information.st_mode & S_IFMT == S_IFDIR else {
        throw PatchGeneratorError.invalidFileURL(path)
    }
    return PatchAppendDirectoryIdentity(information)
}

private func appendVerifiedData(
    from descriptor: Int32,
    expectedIdentity: PatchAppendFileIdentity,
    maximumBytes: Int
) throws -> Data {
    guard try appendFileIdentity(descriptor, path: "") == expectedIdentity else {
        throw PatchGeneratorError.changedOnDisk
    }
    var data = Data()
    let chunkSize = 64 * 1024
    var offset: off_t = 0
    while data.count <= maximumBytes {
        let remaining = maximumBytes + 1 - data.count
        var chunk = Data(count: min(chunkSize, remaining))
        let count = chunk.withUnsafeMutableBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            while true {
                let result = Darwin.pread(descriptor, baseAddress, buffer.count, offset)
                if result < 0, errno == EINTR { continue }
                return result
            }
        }
        guard count >= 0 else { throw appendPOSIXError() }
        guard count > 0 else { break }
        chunk.count = count
        data.append(chunk)
        offset += off_t(count)
    }
    guard data.count <= maximumBytes else {
        throw PatchGeneratorError.fileTooLarge(maximumBytes: maximumBytes)
    }
    guard data.count == Int(expectedIdentity.size),
        try appendFileIdentity(descriptor, path: "") == expectedIdentity
    else {
        throw PatchGeneratorError.changedOnDisk
    }
    return data
}

private func appendDescriptorContains(
    _ expectedData: Data,
    descriptor: Int32,
    expectedIdentity: PatchAppendFileIdentity,
    maximumBytes: Int
) throws -> Bool {
    guard expectedData.count <= maximumBytes,
        try appendFileIdentity(descriptor, path: "") == expectedIdentity,
        expectedIdentity.size == off_t(expectedData.count)
    else { return false }
    return try appendVerifiedData(
        from: descriptor,
        expectedIdentity: expectedIdentity,
        maximumBytes: maximumBytes
    ) == expectedData
}

private func appendWrite(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
        var offset = 0
        while offset < buffer.count {
            let written = Darwin.write(
                descriptor,
                baseAddress.advanced(by: offset),
                buffer.count - offset
            )
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw appendPOSIXError() }
            offset += written
        }
    }
}

private func appendCopyMetadata(
    from sourceFD: Int32,
    identity sourceIdentity: PatchAppendFileIdentity,
    to destinationFD: Int32,
    destinationPath: String
) throws {
    guard Darwin.fcopyfile(
        sourceFD,
        destinationFD,
        nil,
        copyfile_flags_t(COPYFILE_METADATA)
    ) == 0,
        Darwin.fchmod(destinationFD, sourceIdentity.mode & mode_t(0o7777)) == 0
    else {
        throw PatchGeneratorError.metadataPreservationFailed(destinationPath)
    }
    let destinationIdentity = try appendFileIdentity(destinationFD, path: destinationPath)
    guard destinationIdentity.hasMetadataCopied(from: sourceIdentity) else {
        throw PatchGeneratorError.metadataPreservationFailed(destinationPath)
    }
}

private func appendFullySynchronize(_ descriptor: Int32) throws {
    while Darwin.fsync(descriptor) != 0 {
        if errno == EINTR { continue }
        throw appendPOSIXError()
    }
    while Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
        if errno == EINTR { continue }
        throw appendPOSIXError()
    }
}

private func appendRequestedPathMatches(
    _ url: URL,
    expectedName: String,
    expectedDirectoryIdentity: PatchAppendDirectoryIdentity,
    expectedFileIdentity: PatchAppendFileIdentity
) throws -> Bool {
    let (directoryFD, name) = try openParentDirectory(of: url)
    defer { Darwin.close(directoryFD) }
    guard name == expectedName else { return false }
    let currentDirectoryIdentity = try appendDirectoryIdentity(directoryFD, path: url.path)
    guard currentDirectoryIdentity == expectedDirectoryIdentity else { return false }
    let currentFileIdentity = try appendPathIdentity(directoryFD: directoryFD, name: name)
    return currentFileIdentity == expectedFileIdentity
}

private func appendReferenceMatches(
    _ reference: PatchAppendStableReference,
    using referenceAPI: PatchAppendStableReferenceAPI,
    expectedURL: URL,
    expectedIdentity: PatchAppendFileIdentity
) -> Bool {
    guard let resolvedURL = referenceAPI.resolve(reference),
        resolvedURL.standardizedFileURL == expectedURL.standardizedFileURL
    else { return false }
    let descriptor = Darwin.open(
        resolvedURL.path,
        O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
    )
    guard descriptor >= 0 else { return false }
    defer { Darwin.close(descriptor) }
    return (try? appendFileIdentity(descriptor, path: resolvedURL.path)) == expectedIdentity
}

private func appendRemoveReference(
    _ reference: PatchAppendStableReference,
    using referenceAPI: PatchAppendStableReferenceAPI,
    expectedURL: URL,
    expectedIdentity: PatchAppendFileIdentity
) -> Bool {
    guard appendReferenceMatches(
        reference,
        using: referenceAPI,
        expectedURL: expectedURL,
        expectedIdentity: expectedIdentity
    ) else { return false }
    return referenceAPI.delete(reference) == 0
}

private func appendPOSIXError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
}
