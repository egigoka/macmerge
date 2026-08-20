import Darwin
import Foundation

public enum RecentComparisonPairStoreLoadOutcome: Equatable, Sendable {
    case missing
    case loaded(RecentComparisonPairs)
    case malformed
    case unsupportedSchemaVersion(Int)
}

public enum RecentComparisonPairStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidStoreURL(String)
    case invalidStoreFile(String)
    case fileTooLarge(maximumBytes: Int)
    case encodedDataTooLarge(maximumBytes: Int)
    case changedWhileReading
    case changedOnDisk
    case saveOutcomeUncertain(String)
    case clearOutcomeUncertain(String)

    public var errorDescription: String? {
        switch self {
        case .invalidStoreURL(let value):
            "Invalid recent comparison store URL: \(value)."
        case .invalidStoreFile(let path):
            "Recent comparison store is not a regular file: \(path)."
        case .fileTooLarge(let maximumBytes):
            "Recent comparison store is limited to \(maximumBytes) bytes."
        case .encodedDataTooLarge(let maximumBytes):
            "Recent comparison history cannot exceed \(maximumBytes) encoded bytes."
        case .changedWhileReading:
            "Recent comparison store changed while it was being read."
        case .changedOnDisk:
            "Recent comparison store changed while it was being saved."
        case .saveOutcomeUncertain(let path):
            "Recent comparison history was written, but its durability could not be confirmed: \(path)."
        case .clearOutcomeUncertain(let path):
            "Recent comparison history was removed, but its durability could not be confirmed: \(path)."
        }
    }
}

/// Bounded, versioned persistence for recent comparison pairs.
///
/// Stored identities are canonical file URL strings. This store deliberately
/// does not create or resolve security-scoped bookmarks.
public struct RecentComparisonPairStore: Sendable {
    public typealias LoadOutcome = RecentComparisonPairStoreLoadOutcome

    public static let currentSchemaVersion = 1
    public static let maximumFileSize = 1 * 1024 * 1024

    private static let readChunkSize = 64 * 1024
    private static let accessLock = NSLock()

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> LoadOutcome {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }

        try validateStoreURL()
        guard let directoryDescriptor = try openParentDirectory(createIfNeeded: false) else {
            return .missing
        }
        defer { Darwin.close(directoryDescriptor) }
        guard let data = try readData(in: directoryDescriptor) else { return .missing }

        let schemaVersion: Int
        do {
            schemaVersion = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            return .malformed
        }
        guard schemaVersion == Self.currentSchemaVersion else {
            return .unsupportedSchemaVersion(schemaVersion)
        }

        do {
            let wireStore = try JSONDecoder().decode(WireStore.self, from: data)
            guard try Self.makeEncoder().encode(wireStore) == data else { return .malformed }
            return .loaded(wireStore.history)
        } catch {
            return .malformed
        }
    }

    public func save(_ history: RecentComparisonPairs) throws {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }

        try validateStoreURL()
        let wireStore = WireStore(history: history)
        let encoder = Self.makeEncoder()
        try preflightEncodedSize(of: wireStore, encoder: encoder)
        let data = try encoder.encode(wireStore)
        guard data.count <= Self.maximumFileSize else {
            throw RecentComparisonPairStoreError.encodedDataTooLarge(
                maximumBytes: Self.maximumFileSize
            )
        }

        guard let directoryDescriptor = try openParentDirectory(createIfNeeded: true) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { Darwin.close(directoryDescriptor) }
        let original = try fileSnapshot(in: directoryDescriptor)
        let stagingName = ".\(storeFileName).\(UUID().uuidString).tmp"
        let stagingDescriptor = stagingName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard stagingDescriptor >= 0 else { throw currentPOSIXError() }

        var renamed = false
        defer {
            Darwin.close(stagingDescriptor)
            if !renamed {
                _ = stagingName.withCString {
                    Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }

        try write(data, to: stagingDescriptor)
        try synchronizeFile(stagingDescriptor)
        let staged = try descriptorSnapshot(stagingDescriptor, path: fileURL.path)
        guard staged.type == S_IFREG,
            staged.links == 1,
            staged.size == off_t(data.count),
            try namedSnapshot(stagingName, in: directoryDescriptor) == staged,
            try fileSnapshot(in: directoryDescriptor) == original
        else {
            throw RecentComparisonPairStoreError.changedOnDisk
        }

        let renameResult = stagingName.withCString { source in
            storeFileName.withCString { destination in
                Darwin.renameat(directoryDescriptor, source, directoryDescriptor, destination)
            }
        }
        guard renameResult == 0 else { throw currentPOSIXError() }
        renamed = true

        let published = try descriptorSnapshot(stagingDescriptor, path: fileURL.path)
        guard Self.sameFile(staged, published),
            try namedSnapshot(storeFileName, in: directoryDescriptor) == published
        else {
            throw RecentComparisonPairStoreError.saveOutcomeUncertain(fileURL.path)
        }
        do {
            try synchronizeDirectory(directoryDescriptor)
        } catch {
            throw RecentComparisonPairStoreError.saveOutcomeUncertain(fileURL.path)
        }
    }

    public func clear() throws {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }

        try validateStoreURL()
        guard let directoryDescriptor = try openParentDirectory(createIfNeeded: false) else {
            return
        }
        defer { Darwin.close(directoryDescriptor) }
        guard try fileSnapshot(in: directoryDescriptor) != nil else { return }

        let result = storeFileName.withCString {
            Darwin.unlinkat(directoryDescriptor, $0, 0)
        }
        if result != 0 {
            if errno == ENOENT { return }
            throw currentPOSIXError()
        }
        do {
            try synchronizeDirectory(directoryDescriptor)
        } catch {
            throw RecentComparisonPairStoreError.clearOutcomeUncertain(fileURL.path)
        }
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct WireStore: Codable {
        let schemaVersion: Int
        let history: RecentComparisonPairs

        private static let keys: Set<String> = ["schemaVersion", "capacity", "pairs"]

        init(history: RecentComparisonPairs) {
            schemaVersion = RecentComparisonPairStore.currentSchemaVersion
            self.history = history
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: WireKey.self)
            try requireExactKeys(container, expected: Self.keys)
            schemaVersion = try container.decode(Int.self, forKey: WireKey("schemaVersion"))
            guard schemaVersion == RecentComparisonPairStore.currentSchemaVersion else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unsupported schema version.")
                )
            }

            let capacity = try container.decode(Int.self, forKey: WireKey("capacity"))
            guard capacity > 0, capacity <= RecentComparisonPairs.maximumCapacity else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid history capacity.")
                )
            }

            var pairsContainer = try container.nestedUnkeyedContainer(forKey: WireKey("pairs"))
            var pairs: [RecentComparisonPair] = []
            pairs.reserveCapacity(Swift.min(pairsContainer.count ?? capacity, capacity))
            var seen: Set<RecentComparisonPair> = []
            while !pairsContainer.isAtEnd {
                guard pairs.count < capacity,
                    pairs.count < RecentComparisonPairs.maximumCapacity
                else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: pairsContainer.codingPath, debugDescription: "History is not bounded.")
                    )
                }
                let pair = try pairsContainer.decode(WirePair.self).pair
                guard seen.insert(pair).inserted else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: pairsContainer.codingPath, debugDescription: "Duplicate history pair.")
                    )
                }
                pairs.append(pair)
            }
            history = RecentComparisonPairs(pairs, capacity: capacity)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: WireKey.self)
            try container.encode(schemaVersion, forKey: WireKey("schemaVersion"))
            try container.encode(history.capacity, forKey: WireKey("capacity"))
            try container.encode(wirePairs(), forKey: WireKey("pairs"))
        }

        func withEmptyPaths() -> WireStore {
            WireStore(
                schemaVersion: schemaVersion,
                history: history,
                emptyPaths: true
            )
        }

        private init(
            schemaVersion: Int,
            history: RecentComparisonPairs,
            emptyPaths: Bool
        ) {
            self.schemaVersion = schemaVersion
            self.history = history
            self.emptyPaths = emptyPaths
        }

        private var emptyPaths = false

        private func wirePairs() -> [WirePair] {
            history.pairs.map { emptyPaths ? WirePair(emptyPair: $0) : WirePair($0) }
        }
    }

    private struct WirePair: Codable {
        let left: String
        let right: String
        let kind: RecentComparisonPair.Kind

        private static let keys: Set<String> = ["left", "right", "kind"]

        init(_ pair: RecentComparisonPair) {
            left = pair.left.absoluteString
            right = pair.right.absoluteString
            kind = pair.kind
        }

        init(emptyPair pair: RecentComparisonPair) {
            left = ""
            right = ""
            kind = pair.kind
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: WireKey.self)
            try requireExactKeys(container, expected: Self.keys)
            left = try container.decode(String.self, forKey: WireKey("left"))
            right = try container.decode(String.self, forKey: WireKey("right"))
            kind = try container.decode(RecentComparisonPair.Kind.self, forKey: WireKey("kind"))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: WireKey.self)
            try container.encode(left, forKey: WireKey("left"))
            try container.encode(right, forKey: WireKey("right"))
            try container.encode(kind, forKey: WireKey("kind"))
        }

        var pair: RecentComparisonPair {
            get throws {
                guard let leftURL = URL(string: left), let rightURL = URL(string: right) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: [], debugDescription: "Invalid comparison pair URL.")
                    )
                }
                let pair: RecentComparisonPair
                do {
                    pair = try RecentComparisonPair(left: leftURL, right: rightURL, kind: kind)
                } catch {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: [], debugDescription: "Invalid comparison pair URL.")
                    )
                }
                guard pair.left.absoluteString == left, pair.right.absoluteString == right else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: [], debugDescription: "Comparison pair URL is not canonical.")
                    )
                }
                return pair
            }
        }
    }

    private struct WireKey: CodingKey, Hashable {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private struct FileSnapshot: Equatable {
        let device: dev_t
        let inode: ino_t
        let type: mode_t
        let permissions: mode_t
        let links: nlink_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            type = status.st_mode & S_IFMT
            permissions = status.st_mode & ~S_IFMT
            links = status.st_nlink
            size = status.st_size
            modifiedSeconds = status.st_mtimespec.tv_sec
            modifiedNanoseconds = status.st_mtimespec.tv_nsec
            changedSeconds = status.st_ctimespec.tv_sec
            changedNanoseconds = status.st_ctimespec.tv_nsec
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func preflightEncodedSize(of store: WireStore, encoder: JSONEncoder) throws {
        var byteCount = try encoder.encode(store.withEmptyPaths()).count
        for pair in store.history {
            byteCount += try Self.escapedJSONStringByteCount(
                pair.left.absoluteString,
                remaining: Self.maximumFileSize - byteCount
            )
            byteCount += try Self.escapedJSONStringByteCount(
                pair.right.absoluteString,
                remaining: Self.maximumFileSize - byteCount
            )
        }
    }

    private static func escapedJSONStringByteCount(_ value: String, remaining: Int) throws -> Int {
        guard remaining >= 0 else {
            throw RecentComparisonPairStoreError.encodedDataTooLarge(maximumBytes: maximumFileSize)
        }
        var count = 0
        for scalar in value.unicodeScalars {
            let added: Int
            switch scalar.value {
            case 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x22, 0x5C:
                added = 2
            case 0x00...0x1F:
                added = 6
            case 0x20...0x7F:
                added = 1
            case 0x80...0x7FF:
                added = 2
            case 0x800...0xFFFF:
                added = 3
            default:
                added = 4
            }
            guard count <= remaining, added <= remaining - count else {
                throw RecentComparisonPairStoreError.encodedDataTooLarge(
                    maximumBytes: maximumFileSize
                )
            }
            count += added
        }
        return count
    }

    private func readData(in directoryDescriptor: Int32) throws -> Data? {
        guard let pathSnapshot = try fileSnapshot(in: directoryDescriptor) else { return nil }
        guard pathSnapshot.size >= 0, pathSnapshot.size <= off_t(Self.maximumFileSize) else {
            throw RecentComparisonPairStoreError.fileTooLarge(maximumBytes: Self.maximumFileSize)
        }

        let descriptor = storeFileName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
            )
        }
        if descriptor < 0, errno == ENOENT { return nil }
        if descriptor < 0, errno == ELOOP {
            throw RecentComparisonPairStoreError.invalidStoreFile(fileURL.path)
        }
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(descriptor) }

        let initial = try descriptorSnapshot(descriptor, path: fileURL.path)
        guard initial == pathSnapshot else {
            throw RecentComparisonPairStoreError.changedWhileReading
        }

        var data = Data()
        data.reserveCapacity(Int(initial.size))
        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        while data.count <= Self.maximumFileSize {
            let remaining = Self.maximumFileSize + 1 - data.count
            let count = Darwin.read(descriptor, &buffer, Swift.min(buffer.count, remaining))
            if count == 0 { break }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw currentPOSIXError() }
            data.append(contentsOf: buffer.prefix(count))
        }

        let final = try descriptorSnapshot(descriptor, path: fileURL.path)
        guard final == initial,
            try namedSnapshot(storeFileName, in: directoryDescriptor) == final,
            data.count == Int(final.size)
        else {
            throw RecentComparisonPairStoreError.changedWhileReading
        }
        guard data.count <= Self.maximumFileSize else {
            throw RecentComparisonPairStoreError.fileTooLarge(maximumBytes: Self.maximumFileSize)
        }
        return data
    }

    private func fileSnapshot(in directoryDescriptor: Int32) throws -> FileSnapshot? {
        guard let snapshot = try namedSnapshot(storeFileName, in: directoryDescriptor) else {
            return nil
        }
        guard snapshot.type == S_IFREG else {
            throw RecentComparisonPairStoreError.invalidStoreFile(fileURL.path)
        }
        return snapshot
    }

    private func namedSnapshot(
        _ name: String,
        in directoryDescriptor: Int32
    ) throws -> FileSnapshot? {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(directoryDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 { return FileSnapshot(status) }
        if errno == ENOENT { return nil }
        throw currentPOSIXError()
    }

    private func descriptorSnapshot(_ descriptor: Int32, path: String) throws -> FileSnapshot {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { throw currentPOSIXError() }
        let snapshot = FileSnapshot(status)
        guard snapshot.type == S_IFREG else {
            throw RecentComparisonPairStoreError.invalidStoreFile(path)
        }
        return snapshot
    }

    private func openParentDirectory(createIfNeeded: Bool) throws -> Int32? {
        let components = fileURL.pathComponents
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw currentPOSIXError() }
        var descriptorIsOwned = true
        defer {
            if descriptorIsOwned { Darwin.close(descriptor) }
        }

        for component in components.dropFirst().dropLast() {
            let name = String(component)
            var next = name.withCString {
                Darwin.openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            if next < 0, errno == ENOENT, createIfNeeded {
                let creationResult = name.withCString {
                    Darwin.mkdirat(descriptor, $0, S_IRWXU)
                }
                guard creationResult == 0 || errno == EEXIST else { throw currentPOSIXError() }
                try synchronizeDirectory(descriptor)
                next = name.withCString {
                    Darwin.openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
            }
            if next < 0, errno == ENOENT, !createIfNeeded { return nil }
            guard next >= 0 else {
                if errno == ELOOP || errno == ENOTDIR {
                    throw RecentComparisonPairStoreError.invalidStoreURL(fileURL.absoluteString)
                }
                throw currentPOSIXError()
            }
            Darwin.close(descriptor)
            descriptor = next
        }
        descriptorIsOwned = false
        return descriptor
    }

    private func validateStoreURL() throws {
        let name = storeFileName
        guard fileURL.isFileURL,
            fileURL.baseURL == nil,
            fileURL.query == nil,
            fileURL.fragment == nil,
            let components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "file",
            components.host?.isEmpty != false
                || components.host?.caseInsensitiveCompare("localhost") == .orderedSame,
            components.user == nil,
            components.password == nil,
            components.port == nil,
            fileURL.path.hasPrefix("/"),
            fileURL.path == fileURL.standardizedFileURL.path,
            !fileURL.hasDirectoryPath,
            !fileURL.path.utf8.contains(0),
            fileURL.pathComponents.count > 1,
            !name.isEmpty,
            name != ".",
            name != "..",
            name.utf8.count <= 200,
            !name.utf8.contains(0),
            !name.utf8.contains(UInt8(ascii: "/"))
        else {
            throw RecentComparisonPairStoreError.invalidStoreURL(fileURL.absoluteString)
        }
    }

    private var storeFileName: String {
        fileURL.lastPathComponent
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw currentPOSIXError() }
                offset += count
            }
        }
    }

    private static func sameFile(_ lhs: FileSnapshot, _ rhs: FileSnapshot) -> Bool {
        lhs.device == rhs.device
            && lhs.inode == rhs.inode
            && lhs.type == rhs.type
            && lhs.permissions == rhs.permissions
            && lhs.links == rhs.links
            && lhs.size == rhs.size
    }

    private func synchronizeFile(_ descriptor: Int32) throws {
        while Darwin.fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw currentPOSIXError()
        }
        while Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
            if errno == EINTR { continue }
            throw currentPOSIXError()
        }
    }

    private func synchronizeDirectory(_ descriptor: Int32) throws {
        while Darwin.fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw currentPOSIXError()
        }
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno)!)
    }
}

private func requireExactKeys<Value>(
    _ container: KeyedDecodingContainer<Value>,
    expected: Set<String>
) throws where Value: CodingKey {
    let actual = Set(container.allKeys.map(\.stringValue))
    guard actual == expected else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: container.codingPath, debugDescription: "Unexpected JSON object keys.")
        )
    }
}
