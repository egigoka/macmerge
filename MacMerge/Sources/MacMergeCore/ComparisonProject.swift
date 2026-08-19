import CXDiff
import Darwin
import Foundation

public enum ComparisonProjectError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidProjectFileURL(String)
    case invalidSideCount(Int)
    case invalidSideIdentity(String)
    case duplicateSideIdentity(ComparisonProject.Side.Identity)
    case invalidSideIdentities([ComparisonProject.Side.Identity])
    case invalidSidePath(ComparisonProject.Side.Identity)
    case invalidFilterReference
    case invalidRegularExpression(String)
    case regularExpressionValidationFailed
    case projectFileTooLarge(maximumBytes: Int)
    case changedWhileReading
    case changedOnDisk
    case replacementDisabled(String)
    case saveOutcomeUncertain(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported comparison project schema version: \(version)."
        case .invalidProjectFileURL(let path):
            "Invalid comparison project file URL: \(path)."
        case .invalidSideCount(let count):
            "A comparison project must contain two or three sides, not \(count)."
        case .invalidSideIdentity(let identity):
            "Invalid comparison side identity: \(identity)."
        case .duplicateSideIdentity(let identity):
            "Comparison side identity appears more than once: \(identity.rawValue)."
        case .invalidSideIdentities(let identities):
            "Invalid comparison side identities: \(identities.map(\.rawValue).joined(separator: ", "))."
        case .invalidSidePath(let identity):
            "Invalid path for comparison side: \(identity.rawValue)."
        case .invalidFilterReference:
            "Invalid comparison filter reference."
        case .invalidRegularExpression(let pattern):
            "Invalid enabled comparison regular expression: \(pattern)"
        case .regularExpressionValidationFailed:
            "An enabled comparison regular expression could not be validated."
        case .projectFileTooLarge(let maximumBytes):
            "Comparison project files are limited to \(maximumBytes) bytes."
        case .changedWhileReading:
            "The comparison project changed on disk while it was being read."
        case .changedOnDisk:
            "The comparison project changed on disk while it was being saved."
        case .replacementDisabled(let path):
            "Replacing an existing comparison project is disabled because its metadata cannot be preserved safely: \(path)."
        case .saveOutcomeUncertain(let path):
            "The comparison project was written, but its durability could not be confirmed: \(path)."
        }
    }
}

public struct ComparisonProject: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumFileSize = 4 * 1024 * 1024

    public enum Mode: String, Codable, CaseIterable, Sendable {
        case automatic
        case text
        case table
        case binary
        case image
        case webpage
        case folder
    }

    public struct Side: Codable, Equatable, Sendable {
        public enum Identity: String, Codable, CaseIterable, Sendable {
            case left
            case middle
            case right

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let rawValue = try container.decode(String.self)
                guard let identity = Self(rawValue: rawValue) else {
                    throw ComparisonProjectError.invalidSideIdentity(rawValue)
                }
                self = identity
            }
        }

        public let identity: Identity
        public let path: URL
        public let readOnly: Bool

        public init(identity: Identity, path: URL, readOnly: Bool = false) throws {
            guard ComparisonProject.isValidFileURL(path) else {
                throw ComparisonProjectError.invalidSidePath(identity)
            }
            self.identity = identity
            self.path = path
            self.readOnly = readOnly
        }

        private enum CodingKeys: String, CodingKey {
            case identity
            case path
            case readOnly
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identity = try container.decode(Identity.self, forKey: .identity)
            let encodedPath = try container.decode(String.self, forKey: .path)
            guard ComparisonProject.isValidEncodedPath(encodedPath) else {
                throw ComparisonProjectError.invalidSidePath(identity)
            }
            path = Self.decodePath(encodedPath)
            guard ComparisonProject.isValidFileURL(path) else {
                throw ComparisonProjectError.invalidSidePath(identity)
            }
            readOnly = try container.decode(Bool.self, forKey: .readOnly)
        }

        public func encode(to encoder: Encoder) throws {
            guard ComparisonProject.isValidFileURL(path) else {
                throw ComparisonProjectError.invalidSidePath(identity)
            }
            let encodedPath = Self.encodePath(path)
            guard ComparisonProject.isValidEncodedPath(encodedPath) else {
                throw ComparisonProjectError.invalidSidePath(identity)
            }
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identity, forKey: .identity)
            try container.encode(encodedPath, forKey: .path)
            try container.encode(readOnly, forKey: .readOnly)
        }

        fileprivate static func decodePath(_ path: String) -> URL {
            guard !path.hasPrefix("/") else {
                return URL(fileURLWithPath: path)
            }
            return URL(fileURLWithPath: path, relativeTo: ComparisonProject.relativePathBase)
        }

        fileprivate static func encodePath(_ url: URL) -> String {
            guard ComparisonProject.isPortableRelativeURL(url) else { return url.path }
            let path = url.relativePath
            guard path != ".", !path.hasSuffix("/"), path.split(separator: "/").allSatisfy({ !$0.isEmpty }) else {
                return ""
            }
            return path
        }
    }

    public enum FilterReference: Codable, Equatable, Sendable {
        case named(String)
        case file(URL)

        private enum Kind: String, Codable {
            case named
            case file
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case name
            case path
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .named:
                guard !container.contains(.path) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                let name = try container.decode(String.self, forKey: .name)
                guard ComparisonProject.isValidFilterName(name) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                self = .named(name)
            case .file:
                guard !container.contains(.name) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                let path = try container.decode(String.self, forKey: .path)
                guard ComparisonProject.isValidEncodedPath(path) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                let url = Side.decodePath(path)
                guard ComparisonProject.isValidFileURL(url) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                self = .file(url)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .named(let name):
                guard ComparisonProject.isValidFilterName(name) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                try container.encode(Kind.named, forKey: .kind)
                try container.encode(name, forKey: .name)
            case .file(let url):
                guard ComparisonProject.isValidFileURL(url) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                let path = Side.encodePath(url)
                guard ComparisonProject.isValidEncodedPath(path) else {
                    throw ComparisonProjectError.invalidFilterReference
                }
                try container.encode(Kind.file, forKey: .kind)
                try container.encode(path, forKey: .path)
            }
        }
    }

    public let schemaVersion: Int
    public let mode: Mode
    public let sides: [Side]
    public let recursive: Bool
    public let filter: FilterReference?
    public let lineDiffOptions: LineDiffOptions

    public var isThreeWay: Bool { sides.count == 3 }

    public init(
        mode: Mode = .automatic,
        sides: [Side],
        recursive: Bool = false,
        filter: FilterReference? = nil,
        lineDiffOptions: LineDiffOptions = LineDiffOptions()
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.mode = mode
        self.sides = sides
        self.recursive = recursive
        self.filter = filter
        self.lineDiffOptions = lineDiffOptions
        try validate()
    }

    public init(
        left: URL,
        right: URL,
        leftReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        mode: Mode = .automatic,
        recursive: Bool = false,
        filter: FilterReference? = nil,
        lineDiffOptions: LineDiffOptions = LineDiffOptions()
    ) throws {
        try self.init(
            mode: mode,
            sides: [
                try Side(identity: .left, path: left, readOnly: leftReadOnly),
                try Side(identity: .right, path: right, readOnly: rightReadOnly)
            ],
            recursive: recursive,
            filter: filter,
            lineDiffOptions: lineDiffOptions
        )
    }

    public init(
        left: URL,
        middle: URL,
        right: URL,
        leftReadOnly: Bool = false,
        middleReadOnly: Bool = false,
        rightReadOnly: Bool = false,
        mode: Mode = .automatic,
        recursive: Bool = false,
        filter: FilterReference? = nil,
        lineDiffOptions: LineDiffOptions = LineDiffOptions()
    ) throws {
        try self.init(
            mode: mode,
            sides: [
                try Side(identity: .left, path: left, readOnly: leftReadOnly),
                try Side(identity: .middle, path: middle, readOnly: middleReadOnly),
                try Side(identity: .right, path: right, readOnly: rightReadOnly)
            ],
            recursive: recursive,
            filter: filter,
            lineDiffOptions: lineDiffOptions
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case sides
        case recursive
        case filter
        case lineDiffOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ComparisonProjectError.unsupportedSchemaVersion(schemaVersion)
        }
        mode = try container.decode(Mode.self, forKey: .mode)
        sides = try container.decode([Side].self, forKey: .sides)
        recursive = try container.decode(Bool.self, forKey: .recursive)
        filter = try container.decodeIfPresent(FilterReference.self, forKey: .filter)
        lineDiffOptions = try container.decode(LineDiffOptions.self, forKey: .lineDiffOptions)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(mode, forKey: .mode)
        try container.encode(canonicalSides, forKey: .sides)
        try container.encode(recursive, forKey: .recursive)
        try container.encodeIfPresent(filter, forKey: .filter)
        try container.encode(lineDiffOptions, forKey: .lineDiffOptions)
    }

    public func side(_ identity: Side.Identity) -> Side? {
        sides.first { $0.identity == identity }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ComparisonProjectError.unsupportedSchemaVersion(schemaVersion)
        }
        guard sides.count == 2 || sides.count == 3 else {
            throw ComparisonProjectError.invalidSideCount(sides.count)
        }

        var seen = Set<Side.Identity>()
        for side in sides {
            guard seen.insert(side.identity).inserted else {
                throw ComparisonProjectError.duplicateSideIdentity(side.identity)
            }
            guard Self.isValidFileURL(side.path) else {
                throw ComparisonProjectError.invalidSidePath(side.identity)
            }
        }

        let identities = Set(sides.map(\.identity))
        let expected: Set<Side.Identity> =
            sides.count == 2
            ? [.left, .right]
            : [.left, .middle, .right]
        guard identities == expected else {
            throw ComparisonProjectError.invalidSideIdentities(canonicalSides.map(\.identity))
        }

        switch filter {
        case .named(let name):
            guard Self.isValidFilterName(name) else {
                throw ComparisonProjectError.invalidFilterReference
            }
        case .file(let url):
            guard Self.isValidFileURL(url) else {
                throw ComparisonProjectError.invalidFilterReference
            }
        case nil:
            break
        }

        if lineDiffOptions.lineFiltersEnabled {
            for rule in lineDiffOptions.lineFilters {
                try Self.validateRegularExpression(
                    rule.pattern,
                    caseSensitive: rule.caseSensitive,
                    use: .lineFilter
                )
            }
        }
        if lineDiffOptions.substitutionsEnabled {
            for rule in lineDiffOptions.substitutions {
                guard !rule.pattern.isEmpty else {
                    throw ComparisonProjectError.invalidRegularExpression(rule.pattern)
                }
                try Self.validateRegularExpression(
                    rule.pattern,
                    caseSensitive: rule.caseSensitive,
                    use: .substitution
                )
            }
        }
    }

    public static func load(from projectFileURL: URL) throws -> ComparisonProject {
        let fileURL = try validatedProjectFileURL(projectFileURL)
        let data = try readBoundedData(from: fileURL)
        let project = try JSONDecoder().decode(ComparisonProject.self, from: data)
        return try project.resolvingPaths(relativeTo: fileURL)
    }

    public func encodedData(relativeTo projectFileURL: URL) throws -> Data {
        let fileURL = try Self.validatedProjectFileURL(projectFileURL)
        let portableProject = try portable(relativeTo: fileURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(portableProject)
        data.append(0x0A)
        guard data.count <= Self.maximumFileSize else {
            throw ComparisonProjectError.projectFileTooLarge(maximumBytes: Self.maximumFileSize)
        }
        return data
    }

    public func save(to projectFileURL: URL) throws {
        try save(
            to: projectFileURL,
            beforeExclusiveRename: nil,
            afterInitialPublishValidation: nil,
            afterRecoveryOwnershipObservation: nil
        )
    }

    // Synchronous callbacks make filesystem races deterministic in tests.
    func save(
        to projectFileURL: URL,
        beforeExclusiveRename: @escaping () throws -> Void
    ) throws {
        try save(
            to: projectFileURL,
            beforeExclusiveRename: beforeExclusiveRename,
            afterInitialPublishValidation: nil,
            afterRecoveryOwnershipObservation: nil
        )
    }

    func save(
        to projectFileURL: URL,
        afterInitialPublishValidation: (() throws -> Void)?,
        afterRecoveryOwnershipObservation: (() throws -> Void)?
    ) throws {
        try save(
            to: projectFileURL,
            beforeExclusiveRename: nil,
            afterInitialPublishValidation: afterInitialPublishValidation,
            afterRecoveryOwnershipObservation: afterRecoveryOwnershipObservation
        )
    }

    private func save(
        to projectFileURL: URL,
        beforeExclusiveRename: (() throws -> Void)?,
        afterInitialPublishValidation: (() throws -> Void)?,
        afterRecoveryOwnershipObservation: (() throws -> Void)?
    ) throws {
        let fileURL = try Self.validatedProjectFileURL(projectFileURL)
        try Self.atomicWrite(
            encodedData(relativeTo: fileURL),
            to: fileURL,
            beforeExclusiveRename: beforeExclusiveRename,
            afterInitialPublishValidation: afterInitialPublishValidation,
            afterRecoveryOwnershipObservation: afterRecoveryOwnershipObservation
        )
    }

    private static let relativePathBase = URL(
        fileURLWithPath: "/.macmerge-comparison-project-relative-path/",
        isDirectory: true
    )

    private var canonicalSides: [Side] {
        sides.sorted { $0.identity.sortOrder < $1.identity.sortOrder }
    }

    private func resolvingPaths(relativeTo projectFileURL: URL) throws -> ComparisonProject {
        let directoryURL = projectFileURL.deletingLastPathComponent()
        let resolvedSides = try sides.map {
            try Side(identity: $0.identity, path: Self.resolve($0.path, relativeTo: directoryURL), readOnly: $0.readOnly)
        }
        let resolvedFilter: FilterReference?
        if case .file(let url) = filter {
            resolvedFilter = .file(Self.resolve(url, relativeTo: directoryURL))
        } else {
            resolvedFilter = filter
        }
        return try ComparisonProject(
            mode: mode,
            sides: resolvedSides,
            recursive: recursive,
            filter: resolvedFilter,
            lineDiffOptions: lineDiffOptions
        )
    }

    private func portable(relativeTo projectFileURL: URL) throws -> ComparisonProject {
        try validate()
        let directoryURL = projectFileURL.deletingLastPathComponent()
        let portableSides = try canonicalSides.map { side in
            let path = Self.resolve(side.path, relativeTo: directoryURL)
            return try Side(identity: side.identity, path: path, readOnly: side.readOnly)
        }
        let portableFilter: FilterReference?
        if case .file(let url) = filter {
            portableFilter = .file(Self.resolve(url, relativeTo: directoryURL))
        } else {
            portableFilter = filter
        }
        return try ComparisonProject(
            mode: mode,
            sides: portableSides,
            recursive: recursive,
            filter: portableFilter,
            lineDiffOptions: lineDiffOptions
        )
    }

    private static func resolve(_ url: URL, relativeTo directoryURL: URL) -> URL {
        guard isPortableRelativeURL(url) else { return url }
        return directoryURL.appendingPathComponent(url.relativePath)
    }

    private static func readBoundedData(from url: URL) throws -> Data {
        let (directoryFD, name) = try openParentDirectory(of: url)
        defer { Darwin.close(directoryFD) }
        let fileDescriptor = name.withCString {
            Darwin.openat(directoryFD, $0, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        }
        guard fileDescriptor >= 0 else { throw currentPOSIXError() }
        let handle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        let initialIdentity = try descriptorIdentity(handle.fileDescriptor, path: url.path)
        guard initialIdentity.size >= 0, initialIdentity.size <= off_t(maximumFileSize) else {
            throw ComparisonProjectError.projectFileTooLarge(maximumBytes: maximumFileSize)
        }

        var data = Data()
        while data.count <= maximumFileSize {
            let remaining = maximumFileSize + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(64 * 1024, remaining)), !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        guard data.count <= maximumFileSize else {
            throw ComparisonProjectError.projectFileTooLarge(maximumBytes: maximumFileSize)
        }
        let finalIdentity = try descriptorIdentity(handle.fileDescriptor, path: url.path)
        guard data.count == Int(initialIdentity.size), finalIdentity == initialIdentity else {
            throw ComparisonProjectError.changedWhileReading
        }
        let pathIdentity: FileIdentity?
        do {
            pathIdentity = try fileIdentity(directoryFD: directoryFD, name: name)
        } catch {
            throw ComparisonProjectError.changedWhileReading
        }
        guard pathIdentity == finalIdentity else {
            throw ComparisonProjectError.changedWhileReading
        }
        return data
    }

    private static func atomicWrite(
        _ data: Data,
        to url: URL,
        beforeExclusiveRename: (() throws -> Void)?,
        afterInitialPublishValidation: (() throws -> Void)?,
        afterRecoveryOwnershipObservation: (() throws -> Void)?
    ) throws {
        let (directoryFD, name) = try openParentDirectory(of: url)
        defer { Darwin.close(directoryFD) }
        let pinnedDirectoryIdentity = try directoryIdentity(directoryFD, path: url.path)
        do {
            guard try fileIdentity(directoryFD: directoryFD, name: name) == nil else {
                throw ComparisonProjectError.replacementDisabled(url.path)
            }
        } catch ComparisonProjectError.invalidProjectFileURL {
            throw ComparisonProjectError.replacementDisabled(url.path)
        }
        let stagedName = ".macmerge-project-\(UUID().uuidString).tmp"
        let stagedFD = stagedName.withCString {
            Darwin.openat(
                directoryFD,
                $0,
                O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard stagedFD >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(stagedFD) }

        let stagedIdentity = try descriptorIdentity(stagedFD, path: url.path)

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    stagedFD,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw currentPOSIXError() }
                offset += written
            }
        }
        try fullySynchronize(stagedFD)
        let writtenIdentity = try descriptorIdentity(stagedFD, path: url.path)
        guard writtenIdentity.device == stagedIdentity.device,
            writtenIdentity.inode == stagedIdentity.inode,
            writtenIdentity.links == 1,
            writtenIdentity.size == off_t(data.count),
            try fileIdentity(directoryFD: directoryFD, name: stagedName) == writtenIdentity,
            try fileIdentity(directoryFD: directoryFD, name: name) == nil
        else {
            throw ComparisonProjectError.changedOnDisk
        }
        try beforeExclusiveRename?()
        do {
            guard
                try descriptorContains(
                    data,
                    descriptor: stagedFD,
                    expectedIdentity: writtenIdentity,
                    path: url.path
                ),
                try fileIdentity(directoryFD: directoryFD, name: stagedName) == writtenIdentity,
                try fileIdentity(directoryFD: directoryFD, name: name) == nil
            else {
                throw ComparisonProjectError.changedOnDisk
            }
        } catch {
            throw ComparisonProjectError.changedOnDisk
        }
        let renamed = stagedName.withCString { stagedPath in
            name.withCString { targetPath in
                Darwin.renameatx_np(directoryFD, stagedPath, directoryFD, targetPath, UInt32(RENAME_EXCL))
            }
        }
        guard renamed == 0 else {
            if errno == EEXIST { throw ComparisonProjectError.changedOnDisk }
            throw currentPOSIXError()
        }

        do {
            let publishedIdentity = try descriptorIdentity(stagedFD, path: url.path)
            guard publishedIdentity.device == writtenIdentity.device,
                publishedIdentity.inode == writtenIdentity.inode,
                publishedIdentity.links == 1,
                publishedIdentity.size == writtenIdentity.size,
                try fileIdentity(directoryFD: directoryFD, name: name) == publishedIdentity,
                try fileIdentity(directoryFD: directoryFD, name: stagedName) == nil
            else {
                throw ComparisonProjectError.saveOutcomeUncertain(url.path)
            }
            try afterInitialPublishValidation?()
            try fullySynchronize(directoryFD)
            guard
                try descriptorContains(
                    data,
                    descriptor: stagedFD,
                    expectedIdentity: publishedIdentity,
                    path: url.path
                ),
                try fileIdentity(directoryFD: directoryFD, name: name) == publishedIdentity,
                try directoryIdentity(directoryFD, path: url.path) == pinnedDirectoryIdentity
            else {
                throw ComparisonProjectError.saveOutcomeUncertain(url.path)
            }
            let (requestedDirectoryFD, requestedName) = try openParentDirectory(of: url)
            defer { Darwin.close(requestedDirectoryFD) }
            guard requestedName == name,
                try directoryIdentity(requestedDirectoryFD, path: url.path) == pinnedDirectoryIdentity,
                try fileIdentity(directoryFD: requestedDirectoryFD, name: requestedName) == publishedIdentity
            else {
                throw ComparisonProjectError.saveOutcomeUncertain(url.path)
            }
        } catch {
            guard let publishedIdentity = try? descriptorIdentity(stagedFD, path: url.path),
                publishedIdentity.device == writtenIdentity.device,
                publishedIdentity.inode == writtenIdentity.inode,
                publishedIdentity.size == writtenIdentity.size,
                (try? fileIdentity(directoryFD: directoryFD, name: name)) == publishedIdentity,
                (try? fileIdentity(directoryFD: directoryFD, name: stagedName)) == nil
            else {
                throw ComparisonProjectError.saveOutcomeUncertain(url.path)
            }
            do {
                try afterRecoveryOwnershipObservation?()
            } catch {
                throw ComparisonProjectError.saveOutcomeUncertain(url.path)
            }
            throw ComparisonProjectError.saveOutcomeUncertain(url.path)
        }
    }

    private static func descriptorContains(
        _ expectedData: Data,
        descriptor: Int32,
        expectedIdentity: FileIdentity,
        path: String
    ) throws -> Bool {
        let initialIdentity = try descriptorIdentity(descriptor, path: path)
        guard initialIdentity == expectedIdentity,
            initialIdentity.links == 1,
            initialIdentity.size == off_t(expectedData.count)
        else { return false }

        var actualData = Data(count: expectedData.count)
        let readComplete = actualData.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.pread(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset,
                    off_t(offset)
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard readComplete,
            actualData == expectedData,
            try descriptorIdentity(descriptor, path: path) == initialIdentity
        else { return false }
        return true
    }

    private static func fileIdentity(directoryFD: Int32, name: String) throws -> FileIdentity? {
        var information = stat()
        let result = name.withCString {
            Darwin.fstatat(directoryFD, $0, &information, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            guard information.st_mode & S_IFMT == S_IFREG else {
                throw ComparisonProjectError.invalidProjectFileURL(name)
            }
            return FileIdentity(information)
        }
        if errno == ENOENT { return nil }
        throw currentPOSIXError()
    }

    private static func descriptorIdentity(_ descriptor: Int32, path: String) throws -> FileIdentity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw currentPOSIXError() }
        guard information.st_mode & S_IFMT == S_IFREG else {
            throw ComparisonProjectError.invalidProjectFileURL(path)
        }
        return FileIdentity(information)
    }

    private static func directoryIdentity(
        _ descriptor: Int32,
        path: String
    ) throws -> DirectoryIdentity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw currentPOSIXError() }
        guard information.st_mode & S_IFMT == S_IFDIR else {
            throw ComparisonProjectError.invalidProjectFileURL(path)
        }
        return DirectoryIdentity(information)
    }

    private static func openParentDirectory(of url: URL) throws -> (descriptor: Int32, name: String) {
        let components = url.pathComponents
        guard components.first == "/", components.count > 1,
              let name = components.last, name != ".", name != ".." else {
            throw ComparisonProjectError.invalidProjectFileURL(url.absoluteString)
        }

        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw currentPOSIXError() }
        do {
            for component in components.dropFirst().dropLast() {
                if component == "." { continue }
                let next = component.withCString {
                    Darwin.openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                }
                guard next >= 0 else { throw currentPOSIXError() }
                Darwin.close(descriptor)
                descriptor = next
            }
            return (descriptor, name)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func fullySynchronize(_ descriptor: Int32) throws {
        while Darwin.fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw currentPOSIXError()
        }
        while Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
            if errno == EINTR { continue }
            throw currentPOSIXError()
        }
    }

    private enum RegularExpressionUse {
        case lineFilter
        case substitution
    }

    private static func validateRegularExpression(
        _ pattern: String,
        caseSensitive: Bool,
        use: RegularExpressionUse
    ) throws {
        let bytes = Array(pattern.utf8)
        let status: Int32
        switch use {
        case .lineFilter:
            var filter: UnsafeMutableRawPointer?
            status = bytes.withUnsafeBytes {
                mmx_line_filter_create($0.baseAddress, $0.count, caseSensitive ? 1 : 0, &filter)
            }
            if let filter { mmx_line_filter_free(filter) }
        case .substitution:
            var result = mmx_bytes_result(bytes: nil, size: 0)
            status = bytes.withUnsafeBytes {
                mmx_regex_substitute(nil, 0, $0.baseAddress, $0.count, nil, 0, caseSensitive ? 1 : 0, 0, &result)
            }
            mmx_bytes_result_free(&result)
        }
        guard status == 0 else {
            if status == 1 { throw ComparisonProjectError.invalidRegularExpression(pattern) }
            throw ComparisonProjectError.regularExpressionValidationFailed
        }
    }

    private static func currentPOSIXError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private static func validatedProjectFileURL(_ url: URL) throws -> URL {
        guard isValidFileURL(url), url.baseURL == nil, !url.hasDirectoryPath,
              url.lastPathComponent != ".", url.lastPathComponent != ".." else {
            throw ComparisonProjectError.invalidProjectFileURL(url.absoluteString)
        }
        return url
    }

    private static func isValidFileURL(_ url: URL) -> Bool {
        guard url.isFileURL, url.query == nil, url.fragment == nil else { return false }
        if isPortableRelativeURL(url) {
            let path = url.relativePath
            return isValidEncodedPath(path) && !path.hasPrefix("/") && path != "." && !path.hasSuffix("/")
        }
        guard url.baseURL == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "file",
              components.host == "",
              components.user == nil,
              components.password == nil,
              components.port == nil else {
            return false
        }
        return url.path.hasPrefix("/") && isValidEncodedPath(url.path)
    }

    private static func isValidFilterName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !name.utf8.contains(0)
    }

    private static func isPortableRelativeURL(_ url: URL) -> Bool {
        url.baseURL == relativePathBase
    }

    private static func isValidEncodedPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("//"), !path.utf8.contains(0) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if path.hasPrefix("/") {
            return components.first?.isEmpty == true && components.dropFirst().allSatisfy { !$0.isEmpty }
        }
        return components.allSatisfy { !$0.isEmpty }
    }
}

private struct FileIdentity: Equatable {
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
}

private struct DirectoryIdentity: Equatable {
    let device: dev_t
    let inode: ino_t

    init(_ information: stat) {
        device = information.st_dev
        inode = information.st_ino
    }
}

public typealias ComparisonMode = ComparisonProject.Mode
public typealias ComparisonProjectSide = ComparisonProject.Side
public typealias ComparisonSideIdentity = ComparisonProject.Side.Identity
public typealias ComparisonFilterReference = ComparisonProject.FilterReference

extension ComparisonProject.Side.Identity {
    fileprivate var sortOrder: Int {
        switch self {
        case .left: 0
        case .middle: 1
        case .right: 2
        }
    }
}
