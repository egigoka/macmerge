import CryptoKit
import Darwin
import Foundation
import zlib

public enum ArchiveFormat: String, CaseIterable, Equatable, Sendable {
    case zip
}

public enum ArchiveEntryKind: Equatable, Sendable {
    case file
    case directory
}

public struct ArchiveEntry: Equatable, Sendable {
    public let path: String
    public let kind: ArchiveEntryKind
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let crc32: UInt32

    public init(
        path: String,
        kind: ArchiveEntryKind,
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        crc32: UInt32
    ) {
        self.path = path
        self.kind = kind
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.crc32 = crc32
    }
}

public struct ArchiveInventory: Equatable, Sendable {
    public let url: URL
    public let format: ArchiveFormat
    public let entries: [ArchiveEntry]
    public let totalUncompressedSize: UInt64

    public init(url: URL, format: ArchiveFormat, entries: [ArchiveEntry]) {
        self.url = url
        self.format = format
        self.entries = entries
        totalUncompressedSize = entries.reduce(0) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            return overflow ? .max : sum
        }
    }
}

public enum ArchiveDifferenceKind: Equatable, Sendable {
    case unchanged
    case modified
    case added
    case removed
}

public struct ArchiveDifference: Equatable, Sendable {
    public let path: String
    public let kind: ArchiveDifferenceKind
    public let left: ArchiveEntry?
    public let right: ArchiveEntry?

    public init(path: String, kind: ArchiveDifferenceKind, left: ArchiveEntry?, right: ArchiveEntry?) {
        self.path = path
        self.kind = kind
        self.left = left
        self.right = right
    }
}

public struct ArchiveComparison: Equatable, Sendable {
    public let left: ArchiveInventory
    public let right: ArchiveInventory
    public let differences: [ArchiveDifference]

    public init(left: ArchiveInventory, right: ArchiveInventory, differences: [ArchiveDifference]) {
        self.left = left
        self.right = right
        self.differences = differences
    }
}

public struct ArchiveLimits: Equatable, Sendable {
    public static let `default` = ArchiveLimits()

    public let maximumArchiveBytes: UInt64
    public let maximumEntryCount: Int
    public let maximumEntryUncompressedBytes: UInt64
    public let maximumTotalUncompressedBytes: UInt64
    public let maximumCompressionRatio: UInt64
    public let maximumPathDepth: Int
    public let maximumTotalPathComponents: Int

    public init(
        maximumArchiveBytes: UInt64 = 512 * 1_024 * 1_024,
        maximumEntryCount: Int = 100_000,
        maximumEntryUncompressedBytes: UInt64 = 1_024 * 1_024 * 1_024,
        maximumTotalUncompressedBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        maximumCompressionRatio: UInt64 = 1_000,
        maximumPathDepth: Int = 128,
        maximumTotalPathComponents: Int = 1_000_000
    ) {
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumEntryCount = maximumEntryCount
        self.maximumEntryUncompressedBytes = maximumEntryUncompressedBytes
        self.maximumTotalUncompressedBytes = maximumTotalUncompressedBytes
        self.maximumCompressionRatio = maximumCompressionRatio
        self.maximumPathDepth = maximumPathDepth
        self.maximumTotalPathComponents = maximumTotalPathComponents
    }
}

public enum ArchiveError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedFormat
    case invalidArchive
    case archiveTooLarge(maximumBytes: UInt64)
    case tooManyEntries(maximum: Int)
    case entryPathTooDeep(path: String, maximumDepth: Int)
    case tooManyPathComponents(maximum: Int)
    case entryTooLarge(path: String, maximumBytes: UInt64)
    case expandedSizeTooLarge(maximumBytes: UInt64)
    case suspiciousCompressionRatio(path: String, maximumRatio: UInt64)
    case unsafeEntryPath(String)
    case duplicateEntryPath(String)
    case encryptedEntry(String)
    case unsupportedEntry(String)
    case sourceContainsUnsupportedItem(String)
    case destinationExists(String)
    case destinationInsideSource
    case invalidFileURL(String)
    case toolFailed(exitStatus: Int32)
    case extractedContentsMismatch
    case cleanupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Only ZIP archives are supported."
        case .invalidArchive:
            "The ZIP archive is invalid or uses unsupported ZIP64/multi-disk structure."
        case .archiveTooLarge(let maximumBytes):
            "Archive exceeds the current \(maximumBytes)-byte safety limit."
        case .tooManyEntries(let maximum):
            "Archive exceeds the current \(maximum)-entry safety limit."
        case .entryPathTooDeep(let path, let maximumDepth):
            "Archive entry \(path) exceeds the current \(maximumDepth)-component path-depth limit."
        case .tooManyPathComponents(let maximum):
            "Archive exceeds the current \(maximum)-path-component safety limit."
        case .entryTooLarge(let path, let maximumBytes):
            "Archive entry \(path) exceeds the current \(maximumBytes)-byte safety limit."
        case .expandedSizeTooLarge(let maximumBytes):
            "Expanded archive exceeds the current \(maximumBytes)-byte safety limit."
        case .suspiciousCompressionRatio(let path, let maximumRatio):
            "Archive entry \(path) exceeds the current \(maximumRatio):1 compression-ratio limit."
        case .unsafeEntryPath(let path):
            "Archive contains an unsafe path: \(path)"
        case .duplicateEntryPath(let path):
            "Archive contains colliding paths: \(path)"
        case .encryptedEntry(let path):
            "Encrypted archive entry is not supported: \(path)"
        case .unsupportedEntry(let path):
            "Archive contains an unsupported entry type, option, or compression method: \(path)"
        case .sourceContainsUnsupportedItem(let path):
            "Archive source contains a symbolic link or special file: \(path)"
        case .destinationExists(let path):
            "Archive destination already exists: \(path)"
        case .destinationInsideSource:
            "Archive destination must not be inside its source directory."
        case .invalidFileURL(let value):
            "Archive operation requires an absolute local file URL: \(value)"
        case .toolFailed(let exitStatus):
            "Archive codec failed with status \(exitStatus)."
        case .extractedContentsMismatch:
            "Extracted archive contents did not match the validated inventory."
        case .cleanupFailed(let path):
            "Archive operation failed and could not remove its staged item: \(path)"
        }
    }
}

public enum ArchiveIO {
    public static let supportedFormats = ArchiveFormat.allCases

    enum PublicationCheckpoint: Equatable, Sendable {
        case creation
        case extraction
    }

    @TaskLocal
    static var publicationObserver: (@Sendable (PublicationCheckpoint) throws -> Void)?

    @TaskLocal
    static var synchronizeOperation: (@Sendable (Int32) throws -> Void)?

    public static func inventory(
        of url: URL,
        limits: ArchiveLimits = .default
    ) throws -> ArchiveInventory {
        try Task.checkCancellation()
        return try withSecurityScopedAccess(to: url) {
            let archive = try ParsedZIP(url: url, limits: limits)
            return archive.inventory
        }
    }

    public static func compare(
        _ leftURL: URL,
        _ rightURL: URL,
        limits: ArchiveLimits = .default
    ) throws -> ArchiveComparison {
        try Task.checkCancellation()
        try validateLocalFileURL(leftURL)
        try validateLocalFileURL(rightURL)
        let left = try withSecurityScopedAccess(to: leftURL) {
            try comparableArchive(at: leftURL, limits: limits)
        }
        let right = try withSecurityScopedAccess(to: rightURL) {
            try comparableArchive(at: rightURL, limits: limits)
        }
        let leftEntries = Dictionary(uniqueKeysWithValues: left.entries.map { ($0.entry.path, $0) })
        let rightEntries = Dictionary(uniqueKeysWithValues: right.entries.map { ($0.entry.path, $0) })
        let paths = Set(leftEntries.keys).union(rightEntries.keys).sorted()
        var differences: [ArchiveDifference] = []
        differences.reserveCapacity(paths.count)
        for path in paths {
            try Task.checkCancellation()
            let leftEntry = leftEntries[path]
            let rightEntry = rightEntries[path]
            let kind: ArchiveDifferenceKind
            switch (leftEntry, rightEntry) {
            case (.some, .none):
                kind = .removed
            case (.none, .some):
                kind = .added
            case (.some(let leftEntry), .some(let rightEntry)):
                kind = entriesHaveSameContents(leftEntry, rightEntry) ? .unchanged : .modified
            case (.none, .none):
                preconditionFailure("Union path must exist in at least one archive")
            }
            differences.append(
                ArchiveDifference(
                    path: path,
                    kind: kind,
                    left: leftEntry?.entry,
                    right: rightEntry?.entry
                ))
        }
        return ArchiveComparison(left: left.inventory, right: right.inventory, differences: differences)
    }

    @discardableResult
    public static func createZIP(
        from sourceURL: URL,
        at destinationURL: URL,
        includeParent: Bool = true,
        limits: ArchiveLimits = .default
    ) throws -> ArchiveInventory {
        try Task.checkCancellation()
        try validateLocalFileURL(sourceURL)
        try validateLocalFileURL(destinationURL)
        return try withSecurityScopedAccess(to: sourceURL) {
            try withSecurityScopedAccess(to: destinationURL) {
                let sourceName = sourceURL.lastPathComponent
                let destinationName = destinationURL.lastPathComponent
                let sourceParentFD = try openDirectory(sourceURL.deletingLastPathComponent())
                defer { Darwin.close(sourceParentFD) }
                let destinationParentFD = try openDirectory(destinationURL.deletingLastPathComponent())
                defer { Darwin.close(destinationParentFD) }
                try requireTrustedDestinationParent(destinationParentFD)
                try requireAbsent(parentFD: destinationParentFD, name: destinationName, displayPath: destinationURL.path)
                let sourceIdentity = try itemIdentity(parentFD: sourceParentFD, name: sourceName)
                if sourceIdentity.kind == .directory,
                    try hasAncestor(destinationParentFD, matching: sourceIdentity)
                {
                    throw ArchiveError.destinationInsideSource
                }
                let sourceFD = try openVerifiedItem(
                    parentFD: sourceParentFD,
                    name: sourceName,
                    expected: sourceIdentity
                )
                defer { Darwin.close(sourceFD) }

                let entries = try collectSourceEntries(
                    sourceFD: sourceFD,
                    sourceName: sourceName,
                    sourceKind: sourceIdentity.kind,
                    includeParent: includeParent,
                    limits: limits
                )
                let writer = ZIPWriter(
                    sourceFD: sourceFD,
                    destinationParentFD: destinationParentFD,
                    destinationName: destinationName,
                    destinationURL: destinationURL,
                    limits: limits
                )
                let archivedEntries = try writer.write(entries)
                return ArchiveInventory(url: destinationURL, format: .zip, entries: archivedEntries)
            }
        }
    }

    @discardableResult
    public static func extract(
        _ archiveURL: URL,
        to destinationURL: URL,
        limits: ArchiveLimits = .default
    ) throws -> ArchiveInventory {
        try Task.checkCancellation()
        try validateLocalFileURL(archiveURL)
        try validateLocalFileURL(destinationURL)
        return try withSecurityScopedAccess(to: archiveURL) {
            try withSecurityScopedAccess(to: destinationURL) {
                let parsed = try ParsedZIP(url: archiveURL, limits: limits)
                let destinationName = destinationURL.lastPathComponent
                let parentFD = try openDirectory(destinationURL.deletingLastPathComponent())
                defer { Darwin.close(parentFD) }
                try requireTrustedDestinationParent(parentFD)
                try requireAbsent(parentFD: parentFD, name: destinationName, displayPath: destinationURL.path)
                let stagedName = ".macmerge-\(UUID().uuidString).extract"
                guard Darwin.mkdirat(parentFD, stagedName, S_IRWXU) == 0 else {
                    throw currentPOSIXError()
                }
                let stagedIdentity: ItemIdentity
                do {
                    stagedIdentity = try itemIdentity(parentFD: parentFD, name: stagedName)
                } catch {
                    try performCleanup(at: destinationURL.path) {
                        try removeTree(parentFD: parentFD, name: stagedName)
                    }
                    throw error
                }
                var ownsStagedName = true
                do {
                    let stagedFD = stagedName.withCString {
                        Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                    }
                    guard stagedFD >= 0 else { throw currentPOSIXError() }
                    defer { Darwin.close(stagedFD) }
                    guard try descriptorIdentity(stagedFD) == stagedIdentity else {
                        throw ArchiveError.extractedContentsMismatch
                    }

                    try extract(parsed, to: stagedFD, limits: limits)
                    guard try itemIdentity(parentFD: parentFD, name: stagedName) == stagedIdentity else {
                        throw ArchiveError.extractedContentsMismatch
                    }
                    try publicationObserver?(.extraction)
                    try Task.checkCancellation()
                    let renamed = stagedName.withCString { stagedPath in
                        destinationName.withCString { destinationPath in
                            Darwin.renameatx_np(parentFD, stagedPath, parentFD, destinationPath, UInt32(RENAME_EXCL))
                        }
                    }
                    guard renamed == 0 else {
                        if errno == EEXIST { throw ArchiveError.destinationExists(destinationURL.path) }
                        throw currentPOSIXError()
                    }
                    ownsStagedName = false
                    guard try itemIdentity(parentFD: parentFD, name: destinationName) == stagedIdentity else {
                        throw ArchiveError.extractedContentsMismatch
                    }
                    try synchronize(parentFD)
                    return parsed.inventory
                } catch let operationError {
                    if ownsStagedName {
                        do {
                            if try itemIdentityIfPresent(parentFD: parentFD, name: stagedName) == stagedIdentity {
                                try removeTree(parentFD: parentFD, name: stagedName)
                                try synchronize(parentFD)
                            }
                        } catch {
                            throw ArchiveError.cleanupFailed(destinationURL.path)
                        }
                    }
                    throw operationError
                }
            }
        }
    }

    static func performCleanup(at path: String, _ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            throw ArchiveError.cleanupFailed(path)
        }
    }

    private static func comparableArchive(at url: URL, limits: ArchiveLimits) throws -> ComparableArchive {
        let parsed = try ParsedZIP(url: url, limits: limits)
        var entries: [ComparableEntry] = []
        entries.reserveCapacity(parsed.parsedEntries.count)
        for entry in parsed.parsedEntries {
            try Task.checkCancellation()
            let digest = entry.entry.kind == .file ? try digest(entry, in: parsed.data, limits: limits) : nil
            entries.append(ComparableEntry(entry: entry.entry, digest: digest))
        }
        return ComparableArchive(inventory: parsed.inventory, entries: entries)
    }

    private static func entriesHaveSameContents(_ left: ComparableEntry, _ right: ComparableEntry) -> Bool {
        guard left.entry.kind == right.entry.kind,
            left.entry.uncompressedSize == right.entry.uncompressedSize
        else {
            return false
        }
        guard left.entry.kind == .file else { return true }
        return left.digest == right.digest
    }

    private static func digest(
        _ entry: ParsedEntry,
        in archive: Data,
        limits: ArchiveLimits
    ) throws -> SHA256.Digest {
        var hasher = SHA256()
        _ = try decode(entry, in: archive, limits: limits) { bytes in
            hasher.update(data: bytes)
        }
        return hasher.finalize()
    }

    private static func extract(_ archive: ParsedZIP, to rootFD: Int32, limits: ArchiveLimits) throws {
        for parsed in archive.parsedEntries {
            try Task.checkCancellation()
            let components = parsed.entry.path.split(separator: "/").map(String.init)
            let parentComponents = Array(components.dropLast())
            let parentFD = try createDirectories(rootFD: rootFD, components: parentComponents)
            defer { if parentFD != rootFD { Darwin.close(parentFD) } }
            let name = components.last!
            if parsed.entry.kind == .directory {
                let result = name.withCString { Darwin.mkdirat(parentFD, $0, S_IRWXU) }
                if result != 0 && errno != EEXIST { throw currentPOSIXError() }
                let directoryFD = name.withCString {
                    Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                guard directoryFD >= 0 else { throw ArchiveError.extractedContentsMismatch }
                defer { Darwin.close(directoryFD) }
                try synchronize(directoryFD)
                try synchronize(parentFD)
                continue
            }

            let outputFD = name.withCString {
                Darwin.openat(
                    parentFD,
                    $0,
                    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                    S_IRUSR | S_IWUSR
                )
            }
            guard outputFD >= 0 else { throw currentPOSIXError() }
            defer { Darwin.close(outputFD) }
            _ = try decode(parsed, in: archive.data, limits: limits) { bytes in
                try writeAll(bytes, to: outputFD)
            }
            try synchronize(outputFD)
            try synchronize(parentFD)
        }
        try synchronize(rootFD)
    }

    private static func decode(
        _ parsed: ParsedEntry,
        in archive: Data,
        limits: ArchiveLimits,
        consume: (Data) throws -> Void
    ) throws -> UInt64 {
        let compressed = archive[parsed.dataRange]
        var checksum = UInt32(crc32(0, nil, 0))
        var produced: UInt64 = 0
        func consumeChecked(_ data: Data) throws {
            try Task.checkCancellation()
            guard !data.isEmpty else { return }
            let (next, overflow) = produced.addingReportingOverflow(UInt64(data.count))
            guard !overflow,
                next <= parsed.entry.uncompressedSize,
                next <= limits.maximumEntryUncompressedBytes
            else {
                throw ArchiveError.entryTooLarge(
                    path: parsed.entry.path,
                    maximumBytes: limits.maximumEntryUncompressedBytes
                )
            }
            checksum = data.withUnsafeBytes { buffer in
                UInt32(crc32(uLong(checksum), buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
            }
            produced = next
            try consume(data)
        }

        switch parsed.method {
        case 0:
            var offset = compressed.startIndex
            while offset < compressed.endIndex {
                try Task.checkCancellation()
                let end = min(offset + 64 * 1_024, compressed.endIndex)
                try consumeChecked(Data(compressed[offset..<end]))
                offset = end
            }
        case 8:
            try inflate(compressed, consume: consumeChecked)
        default:
            throw ArchiveError.unsupportedEntry(parsed.entry.path)
        }
        guard produced == parsed.entry.uncompressedSize, checksum == parsed.entry.crc32 else {
            throw ArchiveError.invalidArchive
        }
        return produced
    }

    private static func inflate(
        _ compressed: Data.SubSequence,
        consume: (Data) throws -> Void
    ) throws {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ArchiveError.toolFailed(exitStatus: -1)
        }
        defer { inflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: 64 * 1_024)
        try compressed.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            while true {
                try Task.checkCancellation()
                let status = output.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(buffer.count)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let count = output.count - Int(stream.avail_out)
                if count > 0 { try consume(Data(output[0..<count])) }
                if status == Z_STREAM_END { break }
                guard status == Z_OK, stream.avail_in > 0 || count > 0 else {
                    throw ArchiveError.invalidArchive
                }
            }
            guard stream.avail_in == 0 else { throw ArchiveError.invalidArchive }
        }
    }

    private static func createDirectories(rootFD: Int32, components: [String]) throws -> Int32 {
        var currentFD = rootFD
        for component in components {
            try Task.checkCancellation()
            let result = component.withCString { Darwin.mkdirat(currentFD, $0, S_IRWXU) }
            if result != 0 && errno != EEXIST {
                if currentFD != rootFD { Darwin.close(currentFD) }
                throw currentPOSIXError()
            }
            let nextFD = component.withCString {
                Darwin.openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard nextFD >= 0 else {
                if currentFD != rootFD { Darwin.close(currentFD) }
                throw ArchiveError.extractedContentsMismatch
            }
            try synchronize(currentFD)
            if currentFD != rootFD { Darwin.close(currentFD) }
            currentFD = nextFD
        }
        return currentFD
    }

    private static func collectSourceEntries(
        sourceFD: Int32,
        sourceName: String,
        sourceKind: ArchiveEntryKind,
        includeParent: Bool,
        limits: ArchiveLimits
    ) throws -> [SourceEntry] {
        let prefix = includeParent ? try validatedPath(sourceName, isDirectory: sourceKind == .directory) : ""
        var entries: [SourceEntry] = []
        var totalSize: UInt64 = 0
        var totalPathComponents = 0
        var pendingNameCount = 0
        if sourceKind == .file {
            let path = prefix.isEmpty ? try validatedPath(sourceName, isDirectory: false) : prefix
            let entry = SourceEntry(
                path: path,
                kind: .file,
                relativeComponents: [],
                identity: try descriptorIdentity(sourceFD),
                size: try descriptorSize(sourceFD)
            )
            try validateSourceLimits(
                entry,
                totalSize: &totalSize,
                totalPathComponents: &totalPathComponents,
                limits: limits
            )
            entries.append(entry)
        } else {
            if !prefix.isEmpty {
                let entry = SourceEntry(
                    path: prefix,
                    kind: .directory,
                    relativeComponents: [],
                    identity: try descriptorIdentity(sourceFD),
                    size: 0
                )
                try validateSourceLimits(
                    entry,
                    totalSize: &totalSize,
                    totalPathComponents: &totalPathComponents,
                    limits: limits
                )
                entries.append(entry)
            }
            try collectDirectory(
                directoryFD: sourceFD,
                prefix: prefix,
                relativeComponents: [],
                entries: &entries,
                totalSize: &totalSize,
                totalPathComponents: &totalPathComponents,
                pendingNameCount: &pendingNameCount,
                limits: limits
            )
        }
        guard entries.count <= limits.maximumEntryCount else {
            throw ArchiveError.tooManyEntries(maximum: limits.maximumEntryCount)
        }
        return entries.sorted { $0.path < $1.path }
    }

    private static func collectDirectory(
        directoryFD: Int32,
        prefix: String,
        relativeComponents: [String],
        entries: inout [SourceEntry],
        totalSize: inout UInt64,
        totalPathComponents: inout Int,
        pendingNameCount: inout Int,
        limits: ArchiveLimits
    ) throws {
        let duplicate = Darwin.dup(directoryFD)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            throw currentPOSIXError()
        }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let item = readdir(stream) else {
                if errno != 0 { throw currentPOSIXError() }
                break
            }
            let name = withUnsafePointer(to: &item.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." {
                let (nextPending, overflow) = pendingNameCount.addingReportingOverflow(1)
                guard !overflow,
                    nextPending <= limits.maximumEntryCount - min(entries.count, limits.maximumEntryCount)
                else {
                    throw ArchiveError.tooManyEntries(maximum: limits.maximumEntryCount)
                }
                pendingNameCount = nextPending
                names.append(name)
            }
        }
        for name in names.sorted() {
            try Task.checkCancellation()
            pendingNameCount -= 1
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            let identity = try itemIdentity(parentFD: directoryFD, name: name)
            guard identity.kind == .file || identity.kind == .directory else {
                throw ArchiveError.sourceContainsUnsupportedItem(path)
            }
            let descriptor = try openVerifiedItem(parentFD: directoryFD, name: name, expected: identity)
            var ownsDescriptor = true
            defer { if ownsDescriptor { Darwin.close(descriptor) } }
            if identity.kind == .directory {
                let entry = SourceEntry(
                    path: try validatedPath(path, isDirectory: true),
                    kind: .directory,
                    relativeComponents: relativeComponents + [name],
                    identity: identity,
                    size: 0
                )
                try validateSourceLimits(
                    entry,
                    totalSize: &totalSize,
                    totalPathComponents: &totalPathComponents,
                    limits: limits
                )
                entries.append(entry)
                try collectDirectory(
                    directoryFD: descriptor,
                    prefix: path,
                    relativeComponents: relativeComponents + [name],
                    entries: &entries,
                    totalSize: &totalSize,
                    totalPathComponents: &totalPathComponents,
                    pendingNameCount: &pendingNameCount,
                    limits: limits
                )
            } else {
                let size = try descriptorSize(descriptor)
                Darwin.close(descriptor)
                ownsDescriptor = false
                let entry = SourceEntry(
                    path: try validatedPath(path, isDirectory: false),
                    kind: .file,
                    relativeComponents: relativeComponents + [name],
                    identity: identity,
                    size: size
                )
                try validateSourceLimits(
                    entry,
                    totalSize: &totalSize,
                    totalPathComponents: &totalPathComponents,
                    limits: limits
                )
                entries.append(entry)
            }
            guard entries.count <= limits.maximumEntryCount else {
                throw ArchiveError.tooManyEntries(maximum: limits.maximumEntryCount)
            }
        }
    }

    private static func validateSourceLimits(
        _ entry: SourceEntry,
        totalSize: inout UInt64,
        totalPathComponents: inout Int,
        limits: ArchiveLimits
    ) throws {
        let depth = entry.path.split(separator: "/").count
        guard depth <= limits.maximumPathDepth else {
            throw ArchiveError.entryPathTooDeep(path: entry.path, maximumDepth: limits.maximumPathDepth)
        }
        let (nextComponents, componentOverflow) = totalPathComponents.addingReportingOverflow(depth)
        guard !componentOverflow, nextComponents <= limits.maximumTotalPathComponents else {
            throw ArchiveError.tooManyPathComponents(maximum: limits.maximumTotalPathComponents)
        }
        guard entry.size <= limits.maximumEntryUncompressedBytes else {
            throw ArchiveError.entryTooLarge(path: entry.path, maximumBytes: limits.maximumEntryUncompressedBytes)
        }
        let (nextSize, sizeOverflow) = totalSize.addingReportingOverflow(entry.size)
        guard !sizeOverflow, nextSize <= limits.maximumTotalUncompressedBytes else {
            throw ArchiveError.expandedSizeTooLarge(maximumBytes: limits.maximumTotalUncompressedBytes)
        }
        totalPathComponents = nextComponents
        totalSize = nextSize
    }

    private static func requireAbsent(parentFD: Int32, name: String, displayPath: String) throws {
        var information = stat()
        let result = name.withCString { Darwin.fstatat(parentFD, $0, &information, AT_SYMLINK_NOFOLLOW) }
        if result == 0 || errno != ENOENT { throw ArchiveError.destinationExists(displayPath) }
    }

    private static func hasAncestor(_ directoryFD: Int32, matching identity: ItemIdentity) throws -> Bool {
        var current = Darwin.dup(directoryFD)
        guard current >= 0 else { throw currentPOSIXError() }
        var ownsCurrent = true
        defer { if ownsCurrent { Darwin.close(current) } }
        while true {
            let currentIdentity = try descriptorIdentity(current)
            if currentIdentity.sameNode(as: identity) {
                Darwin.close(current)
                ownsCurrent = false
                return true
            }
            let parent = Darwin.openat(current, "..", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard parent >= 0 else {
                Darwin.close(current)
                throw currentPOSIXError()
            }
            let parentIdentity = try descriptorIdentity(parent)
            Darwin.close(current)
            if parentIdentity.sameNode(as: currentIdentity) {
                Darwin.close(parent)
                ownsCurrent = false
                return false
            }
            current = parent
        }
    }

    private static func openDirectory(_ url: URL) throws -> Int32 {
        try openPinnedDirectory(url)
    }

    private static func requireTrustedDestinationParent(_ descriptor: Int32) throws {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw currentPOSIXError() }
        let writableByOthers = information.st_mode & (S_IWGRP | S_IWOTH) != 0
        let sticky = information.st_mode & S_ISVTX != 0
        let trustedStickyOwner = information.st_uid == 0 || information.st_uid == Darwin.geteuid()
        guard !writableByOthers || sticky && trustedStickyOwner else {
            throw CocoaError(.fileWriteNoPermission)
        }
        guard let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else { return }
        defer { _ = Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        guard Darwin.acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) != 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private static func openVerifiedItem(
        parentFD: Int32,
        name: String,
        expected: ItemIdentity
    ) throws -> Int32 {
        let flags =
            expected.kind == .directory
            ? O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            : O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        let descriptor = name.withCString { Darwin.openat(parentFD, $0, flags) }
        guard descriptor >= 0 else { throw currentPOSIXError() }
        do {
            guard try descriptorIdentity(descriptor) == expected else {
                throw ArchiveError.sourceContainsUnsupportedItem(name)
            }
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    private static func itemIdentity(parentFD: Int32, name: String) throws -> ItemIdentity {
        var information = stat()
        guard name.withCString({ Darwin.fstatat(parentFD, $0, &information, AT_SYMLINK_NOFOLLOW) }) == 0 else {
            throw currentPOSIXError()
        }
        return try ItemIdentity(information, path: name)
    }

    private static func itemIdentityIfPresent(parentFD: Int32, name: String) throws -> ItemIdentity? {
        var information = stat()
        let result = name.withCString { Darwin.fstatat(parentFD, $0, &information, AT_SYMLINK_NOFOLLOW) }
        if result == 0 { return try ItemIdentity(information, path: name) }
        if errno == ENOENT { return nil }
        throw currentPOSIXError()
    }

    private static func descriptorIdentity(_ descriptor: Int32) throws -> ItemIdentity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw currentPOSIXError() }
        return try ItemIdentity(information, path: "")
    }

    private static func descriptorSize(_ descriptor: Int32) throws -> UInt64 {
        let identity = try descriptorIdentity(descriptor)
        guard identity.kind == .file else { throw ArchiveError.sourceContainsUnsupportedItem("") }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw currentPOSIXError() }
        return UInt64(max(0, information.st_size))
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                guard written > 0 else { throw currentPOSIXError() }
                offset += written
            }
        }
    }

    private static func removeTree(parentFD: Int32, name: String) throws {
        let descriptor = name.withCString {
            Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return }
            guard name.withCString({ Darwin.unlinkat(parentFD, $0, 0) }) == 0 else {
                throw currentPOSIXError()
            }
            return
        }
        defer { Darwin.close(descriptor) }
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw currentPOSIXError() }
        guard let stream = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw currentPOSIXError()
        }
        defer { closedir(stream) }
        while true {
            errno = 0
            guard let item = readdir(stream) else {
                if errno != 0 { throw currentPOSIXError() }
                break
            }
            let child = withUnsafePointer(to: &item.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if child != "." && child != ".." { try removeTree(parentFD: descriptor, name: child) }
        }
        guard name.withCString({ Darwin.unlinkat(parentFD, $0, AT_REMOVEDIR) }) == 0 else {
            throw currentPOSIXError()
        }
    }

    fileprivate static func validatedPath(_ rawPath: String, isDirectory: Bool) throws -> String {
        guard !rawPath.isEmpty,
            !rawPath.hasPrefix("/"),
            !rawPath.contains("\\"),
            !rawPath.unicodeScalars.contains(where: { $0.value == 0 })
        else {
            throw ArchiveError.unsafeEntryPath(rawPath)
        }
        var path = rawPath
        if isDirectory && path.hasSuffix("/") { path.removeLast() }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }),
            path.utf8.count <= 4_096
        else {
            throw ArchiveError.unsafeEntryPath(rawPath)
        }
        return components.joined(separator: "/")
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) throws -> T {
        try validateLocalFileURL(url)
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    private static func validateLocalFileURL(_ url: URL) throws {
        let host = url.host?.lowercased()
        let components = url.pathComponents
        guard url.isFileURL,
            host == nil || host == "" || host == "localhost",
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.query == nil,
            url.fragment == nil,
            components.first == "/",
            components.count > 1,
            components.dropFirst().allSatisfy({
                !$0.isEmpty
                    && !$0.contains("/")
                    && !$0.unicodeScalars.contains(where: { $0.value == 0 })
            })
        else {
            throw ArchiveError.invalidFileURL(url.absoluteString)
        }
    }

    private static func currentPOSIXError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private struct ItemIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let kind: ArchiveEntryKind

    init(_ information: stat, path: String) throws {
        device = information.st_dev
        inode = information.st_ino
        switch information.st_mode & S_IFMT {
        case S_IFREG:
            kind = .file
        case S_IFDIR:
            kind = .directory
        default:
            throw ArchiveError.sourceContainsUnsupportedItem(path)
        }
    }

    func sameNode(as other: ItemIdentity) -> Bool {
        device == other.device && inode == other.inode
    }
}

private func descriptorIdentity(_ descriptor: Int32) throws -> ItemIdentity {
    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else { throw currentPOSIXError() }
    return try ItemIdentity(information, path: "")
}

private func itemIdentity(parentFD: Int32, name: String) throws -> ItemIdentity {
    var information = stat()
    guard name.withCString({ Darwin.fstatat(parentFD, $0, &information, AT_SYMLINK_NOFOLLOW) }) == 0 else {
        throw currentPOSIXError()
    }
    return try ItemIdentity(information, path: name)
}

private func itemIdentityIfPresent(parentFD: Int32, name: String) throws -> ItemIdentity? {
    var information = stat()
    let result = name.withCString { Darwin.fstatat(parentFD, $0, &information, AT_SYMLINK_NOFOLLOW) }
    if result == 0 { return try ItemIdentity(information, path: name) }
    if errno == ENOENT { return nil }
    throw currentPOSIXError()
}

private func currentPOSIXError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
}

private func synchronize(_ descriptor: Int32) throws {
    if let operation = ArchiveIO.synchronizeOperation {
        try operation(descriptor)
        return
    }
    while Darwin.fsync(descriptor) != 0 {
        if errno == EINTR { continue }
        throw currentPOSIXError()
    }
}

private func openPinnedDirectory(_ url: URL) throws -> Int32 {
    var canonicalPath = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard url.path.withCString({ Darwin.realpath($0, &canonicalPath) }) != nil else {
        throw currentPOSIXError()
    }
    let bytes = canonicalPath.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    let components = String(decoding: bytes, as: UTF8.self).split(separator: "/").map(String.init)
    var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard current >= 0 else { throw currentPOSIXError() }
    for component in components {
        let next = component.withCString {
            Darwin.openat(current, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        Darwin.close(current)
        guard next >= 0 else { throw currentPOSIXError() }
        current = next
    }
    return current
}

private struct SourceEntry {
    let path: String
    let kind: ArchiveEntryKind
    let relativeComponents: [String]
    let identity: ItemIdentity
    let size: UInt64
}

private struct ParsedEntry {
    let entry: ArchiveEntry
    let method: UInt16
    let dataRange: Range<Data.Index>
}

private struct ComparableEntry {
    let entry: ArchiveEntry
    let digest: SHA256.Digest?
}

private struct ComparableArchive {
    let inventory: ArchiveInventory
    let entries: [ComparableEntry]
}

private struct ParsedZIP {
    let inventory: ArchiveInventory
    let parsedEntries: [ParsedEntry]
    let data: Data

    init(url: URL, limits: ArchiveLimits) throws {
        data = try Self.readArchive(url: url, maximumBytes: limits.maximumArchiveBytes)
        parsedEntries = try ZIPInventoryReader(data: data, limits: limits).read()
        inventory = ArchiveInventory(url: url, format: .zip, entries: parsedEntries.map(\.entry))
    }

    private static func readArchive(url: URL, maximumBytes: UInt64) throws -> Data {
        let resolved = try validatedHostName(url.lastPathComponent)
        let parentFD = try openPinnedDirectory(url.deletingLastPathComponent())
        defer { Darwin.close(parentFD) }
        let descriptor = resolved.withCString {
            Darwin.openat(parentFD, $0, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG else {
            throw ArchiveError.unsupportedFormat
        }
        guard UInt64(max(0, information.st_size)) <= maximumBytes else {
            throw ArchiveError.archiveTooLarge(maximumBytes: maximumBytes)
        }
        var data = Data()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            guard UInt64(data.count) <= maximumBytes,
                UInt64(chunk.count) <= maximumBytes - UInt64(data.count)
            else {
                throw ArchiveError.archiveTooLarge(maximumBytes: maximumBytes)
            }
            data.append(chunk)
        }
        return data
    }

    private static func validatedHostName(_ name: String) throws -> String {
        guard !name.isEmpty,
            name != ".",
            name != "..",
            !name.contains("/"),
            !name.unicodeScalars.contains(where: { $0.value == 0 })
        else {
            throw ArchiveError.unsupportedFormat
        }
        return name
    }
}

private struct ZIPInventoryReader {
    let data: Data
    let limits: ArchiveLimits

    func read() throws -> [ParsedEntry] {
        var match: [ParsedEntry]?
        var lastError: Error = ArchiveError.unsupportedFormat
        for end in try endOfCentralDirectoryCandidates() {
            let entries: [ParsedEntry]
            do {
                entries = try read(end: end)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                continue
            }
            guard match == nil else { throw ArchiveError.invalidArchive }
            match = entries
        }
        guard let match else { throw lastError }
        return match
    }

    private func read(end: EndOfCentralDirectory) throws -> [ParsedEntry] {
        guard end.diskNumber == 0,
            end.centralDirectoryDisk == 0,
            end.entriesOnDisk == end.entryCount,
            end.entryCount != UInt16.max,
            end.centralDirectorySize != UInt32.max,
            end.centralDirectoryOffset != UInt32.max
        else {
            throw ArchiveError.invalidArchive
        }
        guard Int(end.entryCount) <= limits.maximumEntryCount else {
            throw ArchiveError.tooManyEntries(maximum: limits.maximumEntryCount)
        }
        let directoryOffset = Int(end.centralDirectoryOffset)
        let directorySize = Int(end.centralDirectorySize)
        guard directoryOffset <= data.count,
            directorySize <= data.count - directoryOffset,
            directoryOffset + directorySize == end.offset
        else {
            throw ArchiveError.invalidArchive
        }

        var offset = directoryOffset
        var entries: [ParsedEntry] = []
        var collisionKinds: [String: ArchiveEntryKind] = [:]
        var directorySpellings: [String: String] = [:]
        var totalSize: UInt64 = 0
        var totalPathComponents = 0
        var localRanges: [Range<Int>] = []
        entries.reserveCapacity(Int(end.entryCount))

        for _ in 0..<end.entryCount {
            try Task.checkCancellation()
            guard try uint32(at: offset) == 0x0201_4B50 else { throw ArchiveError.invalidArchive }
            let versionMadeBy = try uint16(at: offset + 4)
            let flags = try uint16(at: offset + 8)
            let method = try uint16(at: offset + 10)
            let crc = try uint32(at: offset + 16)
            let compressedSize = try uint32(at: offset + 20)
            let uncompressedSize = try uint32(at: offset + 24)
            let nameLength = Int(try uint16(at: offset + 28))
            let extraLength = Int(try uint16(at: offset + 30))
            let commentLength = Int(try uint16(at: offset + 32))
            let diskStart = try uint16(at: offset + 34)
            let externalAttributes = try uint32(at: offset + 38)
            let localOffset = try uint32(at: offset + 42)
            guard compressedSize != UInt32.max,
                uncompressedSize != UInt32.max,
                localOffset != UInt32.max,
                diskStart == 0,
                extraLength == 0
            else {
                throw ArchiveError.invalidArchive
            }
            let variableLength = nameLength + extraLength + commentLength
            guard offset + 46 <= data.count, variableLength <= data.count - (offset + 46) else {
                throw ArchiveError.invalidArchive
            }
            let nameBytes = Array(data[(offset + 46)..<(offset + 46 + nameLength)])
            let rawName = try decodeName(nameBytes, flags: flags)
            let entry = try validatedEntry(
                rawName: rawName,
                versionMadeBy: versionMadeBy,
                flags: flags,
                method: method,
                crc: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                externalAttributes: externalAttributes
            )
            try validateLimits(
                entry,
                totalSize: &totalSize,
                totalPathComponents: &totalPathComponents
            )
            try validateCollision(entry, collisionKinds: &collisionKinds)
            try validateDirectorySpellings(entry, spellings: &directorySpellings)
            let local = try validateLocalHeader(
                at: Int(localOffset),
                centralDirectoryOffset: directoryOffset,
                expectedName: nameBytes,
                flags: flags,
                method: method,
                crc: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            )
            localRanges.append(local.fullRange)
            entries.append(ParsedEntry(entry: entry, method: method, dataRange: local.dataRange))
            offset += 46 + variableLength
        }
        guard offset == directoryOffset + directorySize else { throw ArchiveError.invalidArchive }
        try validateHierarchy(collisionKinds)
        let sortedRanges = localRanges.sorted { $0.lowerBound < $1.lowerBound }
        if sortedRanges.count > 1 {
            for index in 1..<sortedRanges.count where sortedRanges[index - 1].overlaps(sortedRanges[index]) {
                throw ArchiveError.invalidArchive
            }
        }
        return entries.sorted { $0.entry.path < $1.entry.path }
    }

    private func endOfCentralDirectoryCandidates() throws -> [EndOfCentralDirectory] {
        guard data.count >= 22 else { throw ArchiveError.unsupportedFormat }
        let lowerBound = max(0, data.count - 22 - Int(UInt16.max))
        var candidates: [EndOfCentralDirectory] = []
        for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
            try Task.checkCancellation()
            guard try uint32(at: offset) == 0x0605_4B50 else { continue }
            let commentLength = Int(try uint16(at: offset + 20))
            guard offset + 22 + commentLength == data.count else { continue }
            let candidate = EndOfCentralDirectory(
                offset: offset,
                diskNumber: try uint16(at: offset + 4),
                centralDirectoryDisk: try uint16(at: offset + 6),
                entriesOnDisk: try uint16(at: offset + 8),
                entryCount: try uint16(at: offset + 10),
                centralDirectorySize: try uint32(at: offset + 12),
                centralDirectoryOffset: try uint32(at: offset + 16)
            )
            let directoryOffset = Int(candidate.centralDirectoryOffset)
            let directorySize = Int(candidate.centralDirectorySize)
            guard candidate.diskNumber == 0,
                candidate.centralDirectoryDisk == 0,
                candidate.entriesOnDisk == candidate.entryCount,
                candidate.entryCount != UInt16.max,
                candidate.centralDirectorySize != UInt32.max,
                candidate.centralDirectoryOffset != UInt32.max,
                directoryOffset <= data.count,
                directorySize <= data.count - directoryOffset,
                directoryOffset + directorySize == candidate.offset,
                candidate.entryCount == 0 || (try? uint32(at: directoryOffset)) == 0x0201_4B50
            else {
                continue
            }
            candidates.append(candidate)
        }
        guard !candidates.isEmpty else { throw ArchiveError.unsupportedFormat }
        return candidates
    }

    private func validatedEntry(
        rawName: String,
        versionMadeBy: UInt16,
        flags: UInt16,
        method: UInt16,
        crc: UInt32,
        compressedSize: UInt32,
        uncompressedSize: UInt32,
        externalAttributes: UInt32
    ) throws -> ArchiveEntry {
        if flags & 0x0001 != 0 || flags & 0x0040 != 0 { throw ArchiveError.encryptedEntry(rawName) }
        guard method == 0 || method == 8 else { throw ArchiveError.unsupportedEntry(rawName) }
        let allowedFlags: UInt16 = method == 8 ? 0x0806 : 0x0800
        guard flags & ~allowedFlags == 0 else { throw ArchiveError.unsupportedEntry(rawName) }
        if method == 0 && compressedSize != uncompressedSize { throw ArchiveError.invalidArchive }
        let hostSystem = UInt8(versionMadeBy >> 8)
        let unixMode = mode_t(externalAttributes >> 16)
        let unixType = unixMode & S_IFMT
        let usesUnixAttributes = hostSystem == 3 || hostSystem == 19
        let directoryByDOSAttributes = externalAttributes & 0x10 != 0
        if usesUnixAttributes {
            guard unixType == 0 || unixType == S_IFREG || unixType == S_IFDIR else {
                throw ArchiveError.unsupportedEntry(rawName)
            }
            if unixType == S_IFREG && directoryByDOSAttributes {
                throw ArchiveError.invalidArchive
            }
        }
        let directoryByAttributes =
            usesUnixAttributes && unixType == S_IFDIR
            || directoryByDOSAttributes
        let directoryByName = rawName.hasSuffix("/")
        if usesUnixAttributes && unixType == S_IFREG && directoryByName {
            throw ArchiveError.invalidArchive
        }
        let kind: ArchiveEntryKind = directoryByAttributes || directoryByName ? .directory : .file
        let path = try ArchiveIO.validatedPath(rawName, isDirectory: kind == .directory)
        if kind == .directory && (compressedSize != 0 || uncompressedSize != 0 || crc != 0) {
            throw ArchiveError.invalidArchive
        }
        return ArchiveEntry(
            path: path,
            kind: kind,
            compressedSize: UInt64(compressedSize),
            uncompressedSize: UInt64(uncompressedSize),
            crc32: crc
        )
    }

    private func validateCollision(
        _ entry: ArchiveEntry,
        collisionKinds: inout [String: ArchiveEntryKind]
    ) throws {
        let key = collisionKey(entry.path)
        guard collisionKinds[key] == nil else { throw ArchiveError.duplicateEntryPath(entry.path) }
        collisionKinds[key] = entry.kind
    }

    private func validateHierarchy(_ collisionKinds: [String: ArchiveEntryKind]) throws {
        for key in collisionKinds.keys {
            let components = key.split(separator: "/")
            guard components.count > 1 else { continue }
            for parentCount in 1..<components.count {
                let parent = components.prefix(parentCount).joined(separator: "/")
                if collisionKinds[parent] == .file {
                    throw ArchiveError.duplicateEntryPath(key)
                }
            }
        }
    }

    private func validateDirectorySpellings(
        _ entry: ArchiveEntry,
        spellings: inout [String: String]
    ) throws {
        let components = entry.path.split(separator: "/").map(String.init)
        let directoryCount = entry.kind == .directory ? components.count : max(0, components.count - 1)
        guard directoryCount > 0 else { return }
        for count in 1...directoryCount {
            let spelling = components.prefix(count).joined(separator: "/")
            let key = collisionKey(spelling)
            if let existing = spellings[key], existing != spelling {
                throw ArchiveError.duplicateEntryPath(entry.path)
            }
            spellings[key] = spelling
        }
    }

    private func validateLimits(
        _ entry: ArchiveEntry,
        totalSize: inout UInt64,
        totalPathComponents: inout Int
    ) throws {
        let depth = entry.path.split(separator: "/").count
        guard depth <= limits.maximumPathDepth else {
            throw ArchiveError.entryPathTooDeep(path: entry.path, maximumDepth: limits.maximumPathDepth)
        }
        let (nextComponents, componentOverflow) = totalPathComponents.addingReportingOverflow(depth)
        guard !componentOverflow, nextComponents <= limits.maximumTotalPathComponents else {
            throw ArchiveError.tooManyPathComponents(maximum: limits.maximumTotalPathComponents)
        }
        guard entry.uncompressedSize <= limits.maximumEntryUncompressedBytes else {
            throw ArchiveError.entryTooLarge(path: entry.path, maximumBytes: limits.maximumEntryUncompressedBytes)
        }
        let (nextTotal, overflow) = totalSize.addingReportingOverflow(entry.uncompressedSize)
        guard !overflow, nextTotal <= limits.maximumTotalUncompressedBytes else {
            throw ArchiveError.expandedSizeTooLarge(maximumBytes: limits.maximumTotalUncompressedBytes)
        }
        totalPathComponents = nextComponents
        totalSize = nextTotal
        if entry.uncompressedSize > 0 {
            guard entry.compressedSize > 0 else {
                throw ArchiveError.suspiciousCompressionRatio(path: entry.path, maximumRatio: limits.maximumCompressionRatio)
            }
            let (maximumExpanded, ratioOverflow) = entry.compressedSize.multipliedReportingOverflow(
                by: limits.maximumCompressionRatio
            )
            guard ratioOverflow || entry.uncompressedSize <= maximumExpanded else {
                throw ArchiveError.suspiciousCompressionRatio(path: entry.path, maximumRatio: limits.maximumCompressionRatio)
            }
        }
    }

    private func validateLocalHeader(
        at offset: Int,
        centralDirectoryOffset: Int,
        expectedName: [UInt8],
        flags: UInt16,
        method: UInt16,
        crc: UInt32,
        compressedSize: UInt32,
        uncompressedSize: UInt32
    ) throws -> LocalEntryRange {
        guard offset >= 0,
            offset + 30 <= centralDirectoryOffset,
            try uint32(at: offset) == 0x0403_4B50,
            try uint16(at: offset + 6) == flags,
            try uint16(at: offset + 8) == method,
            try uint32(at: offset + 14) == crc,
            try uint32(at: offset + 18) == compressedSize,
            try uint32(at: offset + 22) == uncompressedSize
        else {
            throw ArchiveError.invalidArchive
        }
        let nameLength = Int(try uint16(at: offset + 26))
        let extraLength = Int(try uint16(at: offset + 28))
        guard extraLength == 0 else { throw ArchiveError.invalidArchive }
        let dataOffset = offset + 30 + nameLength
        let dataEnd = UInt64(dataOffset) + UInt64(compressedSize)
        guard dataOffset <= centralDirectoryOffset,
            dataEnd <= UInt64(centralDirectoryOffset),
            Array(data[(offset + 30)..<(offset + 30 + nameLength)]) == expectedName
        else {
            throw ArchiveError.invalidArchive
        }
        return LocalEntryRange(
            fullRange: offset..<Int(dataEnd),
            dataRange: dataOffset..<Int(dataEnd)
        )
    }

    private func decodeName(_ bytes: [UInt8], flags: UInt16) throws -> String {
        guard !bytes.isEmpty else { throw ArchiveError.invalidArchive }
        if flags & 0x0800 != 0 {
            guard let name = String(bytes: bytes, encoding: .utf8) else { throw ArchiveError.invalidArchive }
            return name
        }
        guard bytes.allSatisfy({ $0 < 0x80 }) else { throw ArchiveError.unsupportedEntry("<non-UTF-8 name>") }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw ArchiveError.invalidArchive }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw ArchiveError.invalidArchive }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

private final class ZIPWriter {
    let sourceFD: Int32
    let destinationParentFD: Int32
    let destinationName: String
    let destinationURL: URL
    let limits: ArchiveLimits

    init(
        sourceFD: Int32,
        destinationParentFD: Int32,
        destinationName: String,
        destinationURL: URL,
        limits: ArchiveLimits
    ) {
        self.sourceFD = sourceFD
        self.destinationParentFD = destinationParentFD
        self.destinationName = destinationName
        self.destinationURL = destinationURL
        self.limits = limits
    }

    func write(_ entries: [SourceEntry]) throws -> [ArchiveEntry] {
        try Task.checkCancellation()
        guard entries.count < Int(UInt16.max) else {
            throw ArchiveError.tooManyEntries(maximum: min(limits.maximumEntryCount, Int(UInt16.max) - 1))
        }
        try preflightArchiveSize(entries)
        let stagedName = ".macmerge-\(UUID().uuidString).zip"
        let descriptor = stagedName.withCString {
            Darwin.openat(
                destinationParentFD,
                $0,
                O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else { throw currentPOSIXError() }
        let stagedIdentity: ItemIdentity
        do {
            stagedIdentity = try descriptorIdentity(descriptor)
        } catch {
            Darwin.close(descriptor)
            try ArchiveIO.performCleanup(at: destinationURL.path) {
                guard stagedName.withCString({ Darwin.unlinkat(destinationParentFD, $0, 0) }) == 0 else {
                    throw currentPOSIXError()
                }
                try synchronize(destinationParentFD)
            }
            throw error
        }
        var ownsStagedName = true
        var descriptorIsOpen = true
        do {
            var records: [CentralRecord] = []
            var offset: UInt64 = 0
            for source in entries {
                try Task.checkCancellation()
                let name = Data((source.kind == .directory ? source.path + "/" : source.path).utf8)
                guard name.count <= Int(UInt16.max) else { throw ArchiveError.unsafeEntryPath(source.path) }
                guard offset <= UInt64(UInt32.max) else {
                    throw ArchiveError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
                }
                let localOffset = UInt32(offset)
                let fingerprint = try fingerprint(source)
                let checksum = fingerprint.crc32
                var local = Data()
                local.appendLittleEndian(UInt32(0x0403_4B50))
                local.appendLittleEndian(UInt16(20))
                local.appendLittleEndian(UInt16(0x0800))
                local.appendLittleEndian(UInt16(0))
                local.appendLittleEndian(UInt16(0))
                local.appendLittleEndian(UInt16(0x0021))
                local.appendLittleEndian(checksum)
                local.appendLittleEndian(UInt32(source.size))
                local.appendLittleEndian(UInt32(source.size))
                local.appendLittleEndian(UInt16(name.count))
                local.appendLittleEndian(UInt16(0))
                local.append(name)
                try write(local, descriptor: descriptor, offset: &offset)
                try writeSource(source, fingerprint: fingerprint, descriptor: descriptor, offset: &offset)
                records.append(
                    CentralRecord(
                        name: name,
                        kind: source.kind,
                        crc: checksum,
                        size: UInt32(source.size),
                        localOffset: localOffset
                    ))
            }

            guard offset <= UInt64(UInt32.max) else {
                throw ArchiveError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
            }
            let centralOffset = UInt32(offset)
            for record in records {
                try Task.checkCancellation()
                var central = Data()
                central.appendLittleEndian(UInt32(0x0201_4B50))
                central.appendLittleEndian(UInt16(3 << 8 | 20))
                central.appendLittleEndian(UInt16(20))
                central.appendLittleEndian(UInt16(0x0800))
                central.appendLittleEndian(UInt16(0))
                central.appendLittleEndian(UInt16(0))
                central.appendLittleEndian(UInt16(0x0021))
                central.appendLittleEndian(record.crc)
                central.appendLittleEndian(record.size)
                central.appendLittleEndian(record.size)
                central.appendLittleEndian(UInt16(record.name.count))
                central.appendLittleEndian(UInt16(0))
                central.appendLittleEndian(UInt16(0))
                central.appendLittleEndian(UInt16(0))
                central.appendLittleEndian(UInt16(0))
                let mode: UInt32 =
                    record.kind == .directory ? UInt32(S_IFDIR | 0o700) : UInt32(S_IFREG | 0o600)
                central.appendLittleEndian(mode << 16)
                central.appendLittleEndian(record.localOffset)
                central.append(record.name)
                try write(central, descriptor: descriptor, offset: &offset)
            }
            guard offset <= UInt64(UInt32.max) else {
                throw ArchiveError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
            }
            let centralSize = UInt32(offset) - centralOffset
            var end = Data()
            end.appendLittleEndian(UInt32(0x0605_4B50))
            end.appendLittleEndian(UInt16(0))
            end.appendLittleEndian(UInt16(0))
            end.appendLittleEndian(UInt16(records.count))
            end.appendLittleEndian(UInt16(records.count))
            end.appendLittleEndian(centralSize)
            end.appendLittleEndian(centralOffset)
            end.appendLittleEndian(UInt16(0))
            try write(end, descriptor: descriptor, offset: &offset)
            try synchronize(descriptor)

            guard try itemIdentity(parentFD: destinationParentFD, name: stagedName) == stagedIdentity else {
                throw ArchiveError.invalidArchive
            }
            let data = try readArchive(descriptor: descriptor, maximumBytes: limits.maximumArchiveBytes)
            let parsed = try ZIPInventoryReader(data: data, limits: limits).read()
            let archivedEntries = parsed.map(\.entry)
            Darwin.close(descriptor)
            descriptorIsOpen = false

            try ArchiveIO.publicationObserver?(.creation)
            try Task.checkCancellation()
            let renamed = stagedName.withCString { stagedPath in
                destinationName.withCString { destinationPath in
                    Darwin.renameatx_np(
                        destinationParentFD,
                        stagedPath,
                        destinationParentFD,
                        destinationPath,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard renamed == 0 else {
                if errno == EEXIST { throw ArchiveError.destinationExists(destinationURL.path) }
                throw currentPOSIXError()
            }
            ownsStagedName = false
            guard try itemIdentity(parentFD: destinationParentFD, name: destinationName) == stagedIdentity else {
                throw ArchiveError.invalidArchive
            }
            try synchronize(destinationParentFD)
            return archivedEntries
        } catch let operationError {
            if descriptorIsOpen { Darwin.close(descriptor) }
            if ownsStagedName {
                do {
                    let identity = try itemIdentityIfPresent(parentFD: destinationParentFD, name: stagedName)
                    if identity == stagedIdentity {
                        guard stagedName.withCString({ Darwin.unlinkat(destinationParentFD, $0, 0) }) == 0 else {
                            throw currentPOSIXError()
                        }
                        try synchronize(destinationParentFD)
                    }
                } catch {
                    throw ArchiveError.cleanupFailed(destinationURL.path)
                }
            }
            throw operationError
        }
    }

    private func preflightArchiveSize(_ entries: [SourceEntry]) throws {
        var total: UInt64 = 22
        guard total <= limits.maximumArchiveBytes else {
            throw ArchiveError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
        }
        for entry in entries {
            try Task.checkCancellation()
            let nameBytes = UInt64((entry.kind == .directory ? entry.path + "/" : entry.path).utf8.count)
            guard entry.size <= UInt64(UInt32.max), nameBytes <= UInt64(UInt16.max) else {
                throw ArchiveError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
            }
            let (entryBytes, entryOverflow) = nameBytes.multipliedReportingOverflow(by: 2)
            let (withHeaders, headerOverflow) = entryBytes.addingReportingOverflow(76)
            let (withPayload, payloadOverflow) = withHeaders.addingReportingOverflow(entry.size)
            let (next, totalOverflow) = total.addingReportingOverflow(withPayload)
            guard !entryOverflow,
                !headerOverflow,
                !payloadOverflow,
                !totalOverflow,
                next <= limits.maximumArchiveBytes,
                next <= UInt64(UInt32.max)
            else {
                throw ArchiveError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
            }
            total = next
        }
    }

    private func fingerprint(_ source: SourceEntry) throws -> SourceFingerprint {
        guard source.kind == .file else { return SourceFingerprint(crc32: 0, sha256: SHA256.hash(data: Data())) }
        guard source.size <= UInt64(UInt32.max), source.size <= limits.maximumEntryUncompressedBytes else {
            throw ArchiveError.entryTooLarge(path: source.path, maximumBytes: limits.maximumEntryUncompressedBytes)
        }
        let descriptor = try openSource(source)
        defer { Darwin.close(descriptor) }
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw currentPOSIXError() }
        let handle = FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
        var checksum = UInt32(crc32(0, nil, 0))
        var hasher = SHA256()
        var count: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            count += UInt64(chunk.count)
            guard count <= source.size else {
                throw ArchiveError.sourceContainsUnsupportedItem(source.path)
            }
            checksum = chunk.withUnsafeBytes { buffer in
                UInt32(crc32(uLong(checksum), buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
            }
            hasher.update(data: chunk)
        }
        guard count == source.size else {
            throw ArchiveError.sourceContainsUnsupportedItem(source.path)
        }
        return SourceFingerprint(crc32: checksum, sha256: hasher.finalize())
    }

    private func writeSource(
        _ source: SourceEntry,
        fingerprint expectedFingerprint: SourceFingerprint,
        descriptor: Int32,
        offset: inout UInt64
    ) throws {
        guard source.kind == .file else { return }
        let sourceDescriptor = try openSource(source)
        defer { Darwin.close(sourceDescriptor) }
        let duplicate = Darwin.dup(sourceDescriptor)
        guard duplicate >= 0 else { throw currentPOSIXError() }
        let handle = FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
        var checksum = UInt32(crc32(0, nil, 0))
        var hasher = SHA256()
        var count: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            count += UInt64(chunk.count)
            guard count <= source.size else { throw ArchiveError.sourceContainsUnsupportedItem(source.path) }
            checksum = chunk.withUnsafeBytes { buffer in
                UInt32(crc32(uLong(checksum), buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
            }
            hasher.update(data: chunk)
            try write(chunk, descriptor: descriptor, offset: &offset)
        }
        guard count == source.size,
            checksum == expectedFingerprint.crc32,
            hasher.finalize() == expectedFingerprint.sha256
        else {
            throw ArchiveError.sourceContainsUnsupportedItem(source.path)
        }
    }

    private func openSource(_ source: SourceEntry) throws -> Int32 {
        var current = Darwin.dup(sourceFD)
        guard current >= 0 else { throw currentPOSIXError() }
        if source.relativeComponents.isEmpty {
            guard try descriptorIdentity(current) == source.identity else {
                Darwin.close(current)
                throw ArchiveError.sourceContainsUnsupportedItem(source.path)
            }
            if source.kind == .file, Darwin.lseek(current, 0, SEEK_SET) != 0 {
                Darwin.close(current)
                throw currentPOSIXError()
            }
            return current
        }
        for (index, component) in source.relativeComponents.enumerated() {
            try Task.checkCancellation()
            let isLast = index == source.relativeComponents.count - 1
            let flags =
                isLast && source.kind == .file
                ? O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
                : O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            let next = component.withCString { Darwin.openat(current, $0, flags) }
            Darwin.close(current)
            guard next >= 0 else { throw currentPOSIXError() }
            current = next
        }
        guard try descriptorIdentity(current) == source.identity else {
            Darwin.close(current)
            throw ArchiveError.sourceContainsUnsupportedItem(source.path)
        }
        if source.kind == .file, Darwin.lseek(current, 0, SEEK_SET) != 0 {
            Darwin.close(current)
            throw currentPOSIXError()
        }
        return current
    }

    private func readArchive(descriptor: Int32, maximumBytes: UInt64) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else { throw currentPOSIXError() }
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw currentPOSIXError() }
        let handle = FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
        var data = Data()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            guard UInt64(data.count) <= maximumBytes,
                UInt64(chunk.count) <= maximumBytes - UInt64(data.count)
            else {
                throw ArchiveError.archiveTooLarge(maximumBytes: maximumBytes)
            }
            data.append(chunk)
        }
        return data
    }

    private func write(_ data: Data, descriptor: Int32, offset: inout UInt64) throws {
        let (next, overflow) = offset.addingReportingOverflow(UInt64(data.count))
        guard !overflow, next <= limits.maximumArchiveBytes else {
            throw ArchiveError.archiveTooLarge(maximumBytes: limits.maximumArchiveBytes)
        }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                try Task.checkCancellation()
                let result = Darwin.write(descriptor, base.advanced(by: written), buffer.count - written)
                guard result > 0 else { throw currentPOSIXError() }
                written += result
            }
        }
        offset = next
    }

    private func currentPOSIXError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private struct CentralRecord {
    let name: Data
    let kind: ArchiveEntryKind
    let crc: UInt32
    let size: UInt32
    let localOffset: UInt32
}

private struct SourceFingerprint {
    let crc32: UInt32
    let sha256: SHA256.Digest
}

private struct LocalEntryRange {
    let fullRange: Range<Int>
    let dataRange: Range<Int>
}

private struct EndOfCentralDirectory {
    let offset: Int
    let diskNumber: UInt16
    let centralDirectoryDisk: UInt16
    let entriesOnDisk: UInt16
    let entryCount: UInt16
    let centralDirectorySize: UInt32
    let centralDirectoryOffset: UInt32
}

extension Data {
    fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private func collisionKey(_ path: String) -> String {
    let hfsPlusFiltered = String(path.unicodeScalars.filter { scalar in
        switch scalar.value {
        case 0x200C...0x200F, 0x202A...0x202E, 0x206A...0x206F, 0xFEFF:
            false
        default:
            true
        }
    })
    return hfsPlusFiltered.precomposedStringWithCanonicalMapping.folding(
        options: [.caseInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
    )
}
