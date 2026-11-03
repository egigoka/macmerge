import Foundation

/// Opaque owner-issued comparison identity. It carries no path, URL, or secret.
public struct SyncPointComparisonIdentity: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = UUID(uuidString: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid sync-point comparison identity."
            )
        }
        rawValue = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }
}

public enum SyncPointPersistenceError: Error, Equatable, LocalizedError, Sendable {
    case encodedDataTooLarge(maximumBytes: Int)
    case persistedDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case invalidComparisonIdentity(String)
    case duplicateComparisonIdentity(String)
    case unknownComparisonIdentity(String)
    case tooManyEntries(maximum: Int)
    case staleLineCount(expected: Int, actual: Int)
    case jsonNestingTooDeep(maximumDepth: Int)
    case jsonContainerTooLarge(maximumElements: Int)
    case tooManyJSONValues(maximumValues: Int)
    case jsonStringTooLarge(maximumBytes: Int)
    case jsonNumberTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .encodedDataTooLarge(let maximumBytes):
            "Sync-point persistence data exceeds the \(maximumBytes)-byte limit."
        case .persistedDataTooLarge(let maximumBytes):
            "Sync-point persistence input exceeds the \(maximumBytes)-byte limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported sync-point persistence schema version: \(version)."
        case .invalidComparisonIdentity(let value):
            "Invalid sync-point comparison identity: \(value)."
        case .duplicateComparisonIdentity(let value):
            "Duplicate sync-point comparison identity: \(value)."
        case .unknownComparisonIdentity(let value):
            "Unknown sync-point comparison identity: \(value)."
        case .tooManyEntries(let maximum):
            "Sync-point persistence exceeds the \(maximum)-entry limit."
        case .staleLineCount(let expected, let actual):
            "Sync-point remap line count \(actual) does not match stored bounds \(expected)."
        case .jsonNestingTooDeep(let maximumDepth):
            "Sync-point persistence JSON exceeds the \(maximumDepth)-level nesting limit."
        case .jsonContainerTooLarge(let maximumElements):
            "A sync-point persistence JSON container exceeds the \(maximumElements)-element limit."
        case .tooManyJSONValues(let maximumValues):
            "Sync-point persistence JSON exceeds the \(maximumValues)-value limit."
        case .jsonStringTooLarge(let maximumBytes):
            "A sync-point persistence JSON string exceeds the \(maximumBytes)-byte limit."
        case .jsonNumberTooLarge(let maximumBytes):
            "A sync-point persistence JSON number exceeds the \(maximumBytes)-byte limit."
        }
    }
}

/// One validated source edit to apply atomically right after decoding.
public struct SyncPointPersistenceEdit: Equatable, Sendable {
    public let comparisonID: SyncPointComparisonIdentity
    public let side: SynchronizationPointSide
    public let range: Range<Int>
    public let insertedLineCount: Int
    public let currentLineCount: Int

    public init(
        comparisonID: SyncPointComparisonIdentity,
        side: SynchronizationPointSide,
        range: Range<Int>,
        insertedLineCount: Int,
        currentLineCount: Int
    ) {
        self.comparisonID = comparisonID
        self.side = side
        self.range = range
        self.insertedLineCount = insertedLineCount
        self.currentLineCount = currentLineCount
    }
}

/// Receipt minted only after the store atomically publishes one validated entry.
public struct SyncPointPersistenceWriteReceipt: Equatable, Sendable {
    public let comparisonID: SyncPointComparisonIdentity
    public let anchorCount: Int
    public let leftLineCount: Int
    public let rightLineCount: Int
    public let schemaVersion: Int
}

/// Versioned store mapping one comparison identity to its ordered sync points.
///
/// Each entry keeps the source bounds observed at save time so loads can remap
/// anchors after later edits. Decoding fails closed on null, wrong-type,
/// unknown-key, duplicate, oversized, or out-of-bounds input.
public struct SyncPointPersistence: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEntries = 256
    public static let maximumEncodedBytes = 4 * 1024 * 1024
    public static let maximumPersistedBytes = 4 * 1024 * 1024
    static let maximumJSONNestingDepth = 16
    static let maximumJSONContainerElements = 65_536
    static let maximumJSONValueCount = 1_000_000
    static let maximumJSONKeyUTF8Bytes = 64
    static let maximumJSONStringUTF8Bytes = 128
    static let maximumJSONNumberBytes = 32

    public let schemaVersion: Int
    fileprivate var storage: [SyncPointComparisonIdentity: SynchronizationPoints.PersistencePayload]

    public init() {
        schemaVersion = Self.currentSchemaVersion
        storage = [:]
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public func points(for comparisonID: SyncPointComparisonIdentity) -> SynchronizationPoints? {
        storage[comparisonID]?.synchronizationPoints
    }

    public func lineCounts(for comparisonID: SyncPointComparisonIdentity) -> (left: Int, right: Int)? {
        guard let payload = storage[comparisonID] else { return nil }
        return (payload.leftLineCount, payload.rightLineCount)
    }

    /// Validates then atomically publishes one entry, returning its write receipt.
    @discardableResult
    public mutating func set(
        _ points: SynchronizationPoints,
        for comparisonID: SyncPointComparisonIdentity,
        leftLineCount: Int,
        rightLineCount: Int
    ) throws -> SyncPointPersistenceWriteReceipt {
        let payload = try SynchronizationPoints.PersistencePayload(
            synchronizationPoints: points,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
        if storage[comparisonID] == nil, storage.count >= Self.maximumEntries {
            throw SyncPointPersistenceError.tooManyEntries(maximum: Self.maximumEntries)
        }
        storage[comparisonID] = payload
        return SyncPointPersistenceWriteReceipt(
            comparisonID: comparisonID,
            anchorCount: points.count,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount,
            schemaVersion: schemaVersion
        )
    }

    /// Removes one entry, returning its final receipt, or nil when absent.
    @discardableResult
    public mutating func remove(
        _ comparisonID: SyncPointComparisonIdentity
    ) -> SyncPointPersistenceWriteReceipt? {
        guard let payload = storage.removeValue(forKey: comparisonID) else { return nil }
        // anchorCount 0 reports post-remove state: entry no longer stored.
        return SyncPointPersistenceWriteReceipt(
            comparisonID: comparisonID,
            anchorCount: 0,
            leftLineCount: payload.leftLineCount,
            rightLineCount: payload.rightLineCount,
            schemaVersion: schemaVersion
        )
    }

    /// Atomically remaps one entry after a source edit and updates its stored bounds.
    @discardableResult
    public mutating func remap(
        _ comparisonID: SyncPointComparisonIdentity,
        afterEditing side: SynchronizationPointSide,
        replacing sourceLines: Range<Int>,
        withLineCount insertedLineCount: Int,
        currentLineCount: Int
    ) throws -> SyncPointPersistenceWriteReceipt {
        guard let payload = storage[comparisonID] else {
            throw SyncPointPersistenceError.unknownComparisonIdentity(comparisonID.rawValue.uuidString)
        }
        let storedLineCount = side == .left ? payload.leftLineCount : payload.rightLineCount
        guard currentLineCount == storedLineCount else {
            throw SyncPointPersistenceError.staleLineCount(expected: storedLineCount, actual: currentLineCount)
        }
        var points = payload.synchronizationPoints
        let resultingCount = try points.remap(
            afterEditing: side,
            replacing: sourceLines,
            withLineCount: insertedLineCount,
            currentLineCount: currentLineCount
        )
        let leftLineCount = side == .left ? resultingCount : payload.leftLineCount
        let rightLineCount = side == .right ? resultingCount : payload.rightLineCount
        let updated = try SynchronizationPoints.PersistencePayload(
            synchronizationPoints: points,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        )
        storage[comparisonID] = updated
        return SyncPointPersistenceWriteReceipt(
            comparisonID: comparisonID,
            anchorCount: points.count,
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount,
            schemaVersion: schemaVersion
        )
    }

    /// Returns compact JSON with recursively sorted object keys.
    public func encodedData() throws -> Data {
        guard storage.count <= Self.maximumEntries else {
            throw SyncPointPersistenceError.tooManyEntries(maximum: Self.maximumEntries)
        }
        try preflightEncodedSize()
        let data = try Self.makeEncoder().encode(WireStore(store: self))
        guard data.count <= Self.maximumEncodedBytes else {
            throw SyncPointPersistenceError.encodedDataTooLarge(maximumBytes: Self.maximumEncodedBytes)
        }
        return data
    }

    private func preflightEncodedSize() throws {
        var byteCount = "{\"entries\":[".utf8.count + "],\"schemaVersion\":1}".utf8.count
        var isFirstEntry = true
        for (identity, payload) in storage {
            var entryBytes = "{\"comparisonID\":\"".utf8.count + identity.rawValue.uuidString.utf8.count
            entryBytes += "\",\"leftLineCount\":".utf8.count + Self.decimalDigitCount(payload.leftLineCount)
            entryBytes += ",\"rightLineCount\":".utf8.count + Self.decimalDigitCount(payload.rightLineCount)
            entryBytes += ",\"synchronizationPoints\":{\"anchors\":[".utf8.count
            var isFirstAnchor = true
            for anchor in payload.synchronizationPoints.anchors {
                if !isFirstAnchor { entryBytes += 1 }
                isFirstAnchor = false
                entryBytes += "{\"leftSourceLine\":".utf8.count + Self.decimalDigitCount(anchor.leftSourceLine)
                entryBytes += ",\"rightSourceLine\":".utf8.count + Self.decimalDigitCount(anchor.rightSourceLine)
                entryBytes += "}".utf8.count
            }
            entryBytes += "]}}".utf8.count
            if !isFirstEntry { byteCount += 1 }
            isFirstEntry = false
            byteCount += entryBytes
            guard byteCount <= Self.maximumEncodedBytes else {
                throw SyncPointPersistenceError.encodedDataTooLarge(maximumBytes: Self.maximumEncodedBytes)
            }
        }
    }

    private static func decimalDigitCount(_ value: Int) -> Int {
        var remaining = value.magnitude
        var count = value < 0 ? 2 : 1
        while remaining >= 10 {
            remaining /= 10
            count += 1
        }
        return count
    }

    public static func decode(from data: Data) throws -> SyncPointPersistence {
        guard data.count <= maximumPersistedBytes else {
            throw SyncPointPersistenceError.persistedDataTooLarge(maximumBytes: maximumPersistedBytes)
        }
        let schemaVersion = try probeSchemaVersion(in: data)
        guard schemaVersion == currentSchemaVersion else {
            throw SyncPointPersistenceError.unsupportedSchemaVersion(schemaVersion)
        }
        try preflightJSON(data)
        let wireStore = try JSONDecoder().decode(WireStore.self, from: data)
        guard try makeEncoder().encode(wireStore) == data else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Sync-point persistence data is not canonical.")
            )
        }
        return try wireStore.decodedStore()
    }

    /// Decodes then atomically applies every edit, returning per-edit receipts and total dropped anchors.
    /// Publishes nothing when any edit fails.
    public static func decodeAndRemap(
        from data: Data,
        applying edits: [SyncPointPersistenceEdit]
    ) throws -> (store: SyncPointPersistence, receipts: [SyncPointPersistenceWriteReceipt], droppedAnchorCount: Int) {
        var store = try decode(from: data)
        var receipts: [SyncPointPersistenceWriteReceipt] = []
        receipts.reserveCapacity(edits.count)
        var droppedAnchorCount = 0
        for edit in edits {
            let anchorCountBefore = store.points(for: edit.comparisonID)?.count ?? 0
            let receipt = try store.remap(
                edit.comparisonID,
                afterEditing: edit.side,
                replacing: edit.range,
                withLineCount: edit.insertedLineCount,
                currentLineCount: edit.currentLineCount
            )
            receipts.append(receipt)
            droppedAnchorCount += max(0, anchorCountBefore - receipt.anchorCount)
        }
        return (store, receipts, droppedAnchorCount)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func probeSchemaVersion(in data: Data) throws -> Int {
        try data.withUnsafeBytes { rawBuffer in
            var scanner = SyncPointSchemaVersionScanner(bytes: rawBuffer.bindMemory(to: UInt8.self))
            return try scanner.scan()
        }
    }

    private static func preflightJSON(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            var scanner = SyncPointJSONPreflightScanner(bytes: rawBuffer.bindMemory(to: UInt8.self))
            try scanner.validate()
        }
    }

    private struct WireStore: Codable {
        let schemaVersion: Int
        let entries: [WireEntry]

        private static let keys: Set<String> = ["schemaVersion", "entries"]

        init(store: SyncPointPersistence) {
            schemaVersion = store.schemaVersion
            entries = store.storage.map { WireEntry(identity: $0.key, payload: $0.value) }
                .sorted { $0.comparisonID < $1.comparisonID }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: WireKey.self)
            try requireSyncPointExactKeys(container, expected: Self.keys)
            schemaVersion = try container.decode(Int.self, forKey: WireKey("schemaVersion"))
            guard schemaVersion == SyncPointPersistence.currentSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: WireKey("schemaVersion"),
                    in: container,
                    debugDescription: SynchronizationPointsError.unsupportedPersistenceSchemaVersion(schemaVersion)
                        .localizedDescription
                )
            }
            var decoded = try container.nestedUnkeyedContainer(forKey: WireKey("entries"))
            if let count = decoded.count, count > SyncPointPersistence.maximumEntries {
                throw DecodingError.dataCorruptedError(
                    forKey: WireKey("entries"),
                    in: container,
                    debugDescription: SyncPointPersistenceError.tooManyEntries(
                        maximum: SyncPointPersistence.maximumEntries
                    ).localizedDescription
                )
            }
            var entries: [WireEntry] = []
            if let count = decoded.count {
                entries.reserveCapacity(min(count, SyncPointPersistence.maximumEntries))
            }
            while !decoded.isAtEnd {
                guard entries.count < SyncPointPersistence.maximumEntries else {
                    throw DecodingError.dataCorruptedError(
                        forKey: WireKey("entries"),
                        in: container,
                        debugDescription: SyncPointPersistenceError.tooManyEntries(
                            maximum: SyncPointPersistence.maximumEntries
                        ).localizedDescription
                    )
                }
                entries.append(try decoded.decode(WireEntry.self))
            }
            self.entries = entries
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: WireKey.self)
            try container.encode(schemaVersion, forKey: WireKey("schemaVersion"))
            try container.encode(entries, forKey: WireKey("entries"))
        }

        func decodedStore() throws -> SyncPointPersistence {
            guard schemaVersion == SyncPointPersistence.currentSchemaVersion else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Unsupported sync-point persistence schema version.")
                )
            }
            var store = SyncPointPersistence()
            for entry in entries {
                let (identity, payload) = try entry.decodedEntry()
                guard store.storage[identity] == nil else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: [],
                            debugDescription: SyncPointPersistenceError.duplicateComparisonIdentity(
                                identity.rawValue.uuidString
                            ).localizedDescription
                        )
                    )
                }
                store.storage[identity] = payload
            }
            return store
        }
    }

    private struct WireEntry: Codable {
        let comparisonID: String
        let leftLineCount: Int
        let rightLineCount: Int
        let synchronizationPoints: SynchronizationPoints

        private static let keys: Set<String> = [
            "comparisonID", "leftLineCount", "rightLineCount", "synchronizationPoints"
        ]

        init(identity: SyncPointComparisonIdentity, payload: SynchronizationPoints.PersistencePayload) {
            comparisonID = identity.rawValue.uuidString
            leftLineCount = payload.leftLineCount
            rightLineCount = payload.rightLineCount
            synchronizationPoints = payload.synchronizationPoints
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: WireKey.self)
            try requireSyncPointExactKeys(container, expected: Self.keys)
            comparisonID = try container.decode(String.self, forKey: WireKey("comparisonID"))
            guard UUID(uuidString: comparisonID) != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: WireKey("comparisonID"),
                    in: container,
                    debugDescription: SyncPointPersistenceError.invalidComparisonIdentity(comparisonID)
                        .localizedDescription
                )
            }
            leftLineCount = try container.decode(Int.self, forKey: WireKey("leftLineCount"))
            rightLineCount = try container.decode(Int.self, forKey: WireKey("rightLineCount"))
            synchronizationPoints = try container.decode(
                SynchronizationPoints.self,
                forKey: WireKey("synchronizationPoints")
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: WireKey.self)
            try container.encode(comparisonID, forKey: WireKey("comparisonID"))
            try container.encode(leftLineCount, forKey: WireKey("leftLineCount"))
            try container.encode(rightLineCount, forKey: WireKey("rightLineCount"))
            try container.encode(synchronizationPoints, forKey: WireKey("synchronizationPoints"))
        }

        func decodedEntry() throws -> (
            SyncPointComparisonIdentity, SynchronizationPoints.PersistencePayload
        ) {
            guard let uuid = UUID(uuidString: comparisonID) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: [],
                        debugDescription: SyncPointPersistenceError.invalidComparisonIdentity(comparisonID)
                            .localizedDescription
                    )
                )
            }
            do {
                let payload = try SynchronizationPoints.PersistencePayload(
                    synchronizationPoints: synchronizationPoints,
                    leftLineCount: leftLineCount,
                    rightLineCount: rightLineCount
                )
                return (SyncPointComparisonIdentity(rawValue: uuid), payload)
            } catch let error as SynchronizationPointsError {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: error.localizedDescription)
                )
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
}

private struct SyncPointSchemaVersionScanner {
    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func scan() throws -> Int {
        skipWhitespace()
        guard consume(0x7B) else { throw malformedJSON() }
        skipWhitespace()
        guard !consume(0x7D) else { throw malformedJSON() }
        var schemaVersion: Int?
        while true {
            guard currentByte == 0x22 else { throw malformedJSON() }
            let isSchemaVersion = try parseKey(matching: "schemaVersion")
            skipWhitespace()
            guard consume(0x3A) else { throw malformedJSON() }
            skipWhitespace()
            if isSchemaVersion {
                guard schemaVersion == nil else { throw malformedJSON() }
                schemaVersion = try parseInteger()
            } else {
                try skipValue(depth: 1)
            }
            skipWhitespace()
            if consume(0x7D) { break }
            guard consume(0x2C) else { throw malformedJSON() }
            skipWhitespace()
        }
        skipWhitespace()
        guard index == bytes.count, let version = schemaVersion else { throw malformedJSON() }
        return version
    }

    private mutating func parseKey(matching expected: String) throws -> Bool {
        guard consume(0x22) else { throw malformedJSON() }
        let expectedBytes = Array(expected.utf8)
        var expectedIndex = 0
        var matches = true
        while let byte = currentByte {
            switch byte {
            case 0x22:
                index += 1
                return matches && expectedIndex == expectedBytes.count
            case 0x00...0x1F:
                throw malformedJSON()
            case 0x5C:
                index += 1
                let scalar = try parseEscapedScalar()
                if matches {
                    guard scalar <= 0x7F,
                        expectedIndex < expectedBytes.count,
                        expectedBytes[expectedIndex] == UInt8(scalar)
                    else {
                        matches = false
                        continue
                    }
                    expectedIndex += 1
                }
            default:
                if matches {
                    guard expectedIndex < expectedBytes.count,
                        expectedBytes[expectedIndex] == byte
                    else {
                        matches = false
                        index += 1
                        continue
                    }
                    expectedIndex += 1
                }
                index += 1
            }
        }
        throw malformedJSON()
    }

    private mutating func parseEscapedScalar() throws -> UInt32 {
        guard let escaped = currentByte else { throw malformedJSON() }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            return UInt32(escaped)
        case 0x62:
            return 0x08
        case 0x66:
            return 0x0C
        case 0x6E:
            return 0x0A
        case 0x72:
            return 0x0D
        case 0x74:
            return 0x09
        case 0x75:
            return try parseUnicodeScalar()
        default:
            throw malformedJSON()
        }
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(0x5C), consume(0x75) else { throw malformedJSON() }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw malformedJSON() }
            return 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else { throw malformedJSON() }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else { throw malformedJSON() }
            value = value * 16 + UInt16(digit)
            index += 1
        }
        return value
    }

    private mutating func parseInteger() throws -> Int {
        let start = index
        if consume(0x2D) {}
        guard let first = currentByte else { throw malformedJSON() }
        if first == 0x30 {
            index += 1
        } else {
            guard (0x31...0x39).contains(first) else { throw malformedJSON() }
            repeat { index += 1 } while currentByte.map({ (0x30...0x39).contains($0) }) == true
        }
        guard index - start <= SyncPointPersistence.maximumJSONNumberBytes,
            let value = Int(String(decoding: bytes[start..<index], as: UTF8.self))
        else {
            throw SyncPointPersistenceError.jsonNumberTooLarge(
                maximumBytes: SyncPointPersistence.maximumJSONNumberBytes
            )
        }
        return value
    }

    private mutating func skipValue(depth: Int) throws {
        guard depth <= SyncPointPersistence.maximumJSONNestingDepth * 4 else {
            throw SyncPointPersistenceError.jsonNestingTooDeep(
                maximumDepth: SyncPointPersistence.maximumJSONNestingDepth
            )
        }
        guard let byte = currentByte else { throw malformedJSON() }
        switch byte {
        case 0x7B:
            index += 1
            skipWhitespace()
            if consume(0x7D) { return }
            while true {
                guard currentByte == 0x22 else { throw malformedJSON() }
                try skipString()
                skipWhitespace()
                guard consume(0x3A) else { throw malformedJSON() }
                skipWhitespace()
                try skipValue(depth: depth + 1)
                skipWhitespace()
                if consume(0x7D) { return }
                guard consume(0x2C) else { throw malformedJSON() }
                skipWhitespace()
            }
        case 0x5B:
            index += 1
            skipWhitespace()
            if consume(0x5D) { return }
            while true {
                try skipValue(depth: depth + 1)
                skipWhitespace()
                if consume(0x5D) { return }
                guard consume(0x2C) else { throw malformedJSON() }
                skipWhitespace()
            }
        case 0x22:
            try skipString()
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            skipNumber()
        default:
            throw malformedJSON()
        }
    }

    private mutating func skipString() throws {
        guard consume(0x22) else { throw malformedJSON() }
        while let byte = currentByte {
            index += 1
            switch byte {
            case 0x22:
                return
            case 0x5C:
                guard currentByte != nil else { throw malformedJSON() }
                index += 1
            default:
                break
            }
        }
        throw malformedJSON()
    }

    private mutating func skipNumber() {
        _ = consume(0x2D)
        while let byte = currentByte,
            byte == 0x2B || byte == 0x2D || byte == 0x2E || (0x30...0x39).contains(byte) || byte == 0x45
                || byte == 0x65
        {
            index += 1
        }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else { throw malformedJSON() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformedJSON() }
            index += 1
        }
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func malformedJSON() -> DecodingError {
        .dataCorrupted(
            .init(
                codingPath: [],
                debugDescription: "Sync-point persistence data is not valid JSON."
            )
        )
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }
}

private struct SyncPointJSONPreflightScanner {
    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0
    private var valueCount = 0
    private var totalStringByteCount = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw malformedJSON() }
    }

    private mutating func parseValue(depth: Int) throws {
        guard valueCount < SyncPointPersistence.maximumJSONValueCount else {
            throw SyncPointPersistenceError.tooManyJSONValues(
                maximumValues: SyncPointPersistence.maximumJSONValueCount
            )
        }
        valueCount += 1
        guard let byte = currentByte else { throw malformedJSON() }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(
                maximumBytes: SyncPointPersistence.maximumJSONStringUTF8Bytes,
                capture: false
            )
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw malformedJSON()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }

        var elementCount = 0
        var keys: Set<String> = []
        while true {
            try incrementContainerCount(&elementCount)
            guard currentByte == 0x22 else { throw malformedJSON() }
            let key = try parseString(
                maximumBytes: SyncPointPersistence.maximumJSONKeyUTF8Bytes,
                capture: true
            )
            guard keys.insert(key).inserted else { throw malformedJSON() }
            skipWhitespace()
            guard consume(0x3A) else { throw malformedJSON() }
            skipWhitespace()
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw malformedJSON() }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        try validateDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }

        var elementCount = 0
        while true {
            try incrementContainerCount(&elementCount)
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw malformedJSON() }
            skipWhitespace()
        }
    }

    private mutating func parseString(maximumBytes: Int, capture: Bool) throws -> String {
        guard consume(0x22) else { throw malformedJSON() }
        var decodedBytes: [UInt8] = []
        if capture { decodedBytes.reserveCapacity(min(maximumBytes, 32)) }
        var byteCount = 0

        while let byte = currentByte {
            switch byte {
            case 0x22:
                index += 1
                return capture ? String(decoding: decodedBytes, as: UTF8.self) : ""
            case 0x00...0x1F:
                throw malformedJSON()
            case 0x5C:
                index += 1
                try parseEscape(
                    byteCount: &byteCount,
                    decodedBytes: &decodedBytes,
                    maximumBytes: maximumBytes,
                    capture: capture
                )
            case 0x00...0x7F:
                try accountStringBytes(1, byteCount: &byteCount, maximumBytes: maximumBytes)
                index += 1
                if capture { decodedBytes.append(byte) }
            default:
                let length = try rawUTF8ScalarLength()
                try accountStringBytes(
                    length,
                    byteCount: &byteCount,
                    maximumBytes: maximumBytes
                )
                if capture { decodedBytes.append(contentsOf: bytes[index..<(index + length)]) }
                index += length
            }
        }
        throw malformedJSON()
    }

    private mutating func parseEscape(
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        capture: Bool
    ) throws {
        guard let escaped = currentByte else { throw malformedJSON() }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            try appendEscapedByte(
                escaped,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        case 0x62:
            try appendEscapedByte(0x08, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x66:
            try appendEscapedByte(0x0C, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x6E:
            try appendEscapedByte(0x0A, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x72:
            try appendEscapedByte(0x0D, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x74:
            try appendEscapedByte(0x09, byteCount: &byteCount, decodedBytes: &decodedBytes, maximumBytes: maximumBytes, capture: capture)
        case 0x75:
            let scalar = try parseUnicodeScalar()
            try appendEscapedScalar(
                scalar,
                byteCount: &byteCount,
                decodedBytes: &decodedBytes,
                maximumBytes: maximumBytes,
                capture: capture
            )
        default:
            throw malformedJSON()
        }
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(0x5C), consume(0x75) else {
                throw malformedJSON()
            }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw malformedJSON()
            }
            return 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else {
            throw malformedJSON()
        }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw malformedJSON()
            }
            value = value * 16 + UInt16(digit)
            index += 1
        }
        return value
    }

    private mutating func appendEscapedByte(
        _ byte: UInt8,
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        capture: Bool
    ) throws {
        try accountStringBytes(1, byteCount: &byteCount, maximumBytes: maximumBytes)
        if capture { decodedBytes.append(byte) }
    }

    private mutating func appendEscapedScalar(
        _ scalar: UInt32,
        byteCount: inout Int,
        decodedBytes: inout [UInt8],
        maximumBytes: Int,
        capture: Bool
    ) throws {
        let length: Int
        switch scalar {
        case 0...0x7F: length = 1
        case 0x80...0x7FF: length = 2
        case 0x800...0xFFFF: length = 3
        default: length = 4
        }
        try accountStringBytes(length, byteCount: &byteCount, maximumBytes: maximumBytes)
        guard capture else { return }
        switch length {
        case 1:
            decodedBytes.append(UInt8(scalar))
        case 2:
            decodedBytes.append(0xC0 | UInt8(scalar >> 6))
            decodedBytes.append(0x80 | UInt8(scalar & 0x3F))
        case 3:
            decodedBytes.append(0xE0 | UInt8(scalar >> 12))
            decodedBytes.append(0x80 | UInt8((scalar >> 6) & 0x3F))
            decodedBytes.append(0x80 | UInt8(scalar & 0x3F))
        default:
            decodedBytes.append(0xF0 | UInt8(scalar >> 18))
            decodedBytes.append(0x80 | UInt8((scalar >> 12) & 0x3F))
            decodedBytes.append(0x80 | UInt8((scalar >> 6) & 0x3F))
            decodedBytes.append(0x80 | UInt8(scalar & 0x3F))
        }
    }

    private mutating func accountStringBytes(
        _ addedCount: Int,
        byteCount: inout Int,
        maximumBytes: Int
    ) throws {
        guard byteCount <= maximumBytes - addedCount,
            totalStringByteCount <= SyncPointPersistence.maximumEncodedBytes - addedCount
        else {
            throw SyncPointPersistenceError.jsonStringTooLarge(
                maximumBytes: maximumBytes
            )
        }
        byteCount += addedCount
        totalStringByteCount += addedCount
    }

    private func rawUTF8ScalarLength() throws -> Int {
        guard let first = currentByte else { throw malformedJSON() }
        let length: Int
        let secondRange: ClosedRange<UInt8>
        switch first {
        case 0xC2...0xDF:
            length = 2
            secondRange = 0x80...0xBF
        case 0xE0:
            length = 3
            secondRange = 0xA0...0xBF
        case 0xE1...0xEC, 0xEE...0xEF:
            length = 3
            secondRange = 0x80...0xBF
        case 0xED:
            length = 3
            secondRange = 0x80...0x9F
        case 0xF0:
            length = 4
            secondRange = 0x90...0xBF
        case 0xF1...0xF3:
            length = 4
            secondRange = 0x80...0xBF
        case 0xF4:
            length = 4
            secondRange = 0x80...0x8F
        default:
            throw malformedJSON()
        }
        guard index <= bytes.count - length,
            secondRange.contains(bytes[index + 1])
        else {
            throw malformedJSON()
        }
        for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
            throw malformedJSON()
        }
        return length
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = consume(0x2D)
        guard let first = currentByte else { throw malformedJSON() }
        if first == 0x30 {
            index += 1
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw malformedJSON()
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw malformedJSON()
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformedJSON()
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        if consume(0x65) || consume(0x45) {
            _ = consume(0x2B) || consume(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformedJSON()
            }
            repeat { index += 1 } while currentByte.map { (0x30...0x39).contains($0) } == true
        }
        guard index - start <= SyncPointPersistence.maximumJSONNumberBytes else {
            throw SyncPointPersistenceError.jsonNumberTooLarge(
                maximumBytes: SyncPointPersistence.maximumJSONNumberBytes
            )
        }
    }

    private mutating func validateDepth(_ depth: Int) throws {
        guard depth <= SyncPointPersistence.maximumJSONNestingDepth else {
            throw SyncPointPersistenceError.jsonNestingTooDeep(
                maximumDepth: SyncPointPersistence.maximumJSONNestingDepth
            )
        }
    }

    private mutating func incrementContainerCount(_ count: inout Int) throws {
        guard count < SyncPointPersistence.maximumJSONContainerElements else {
            throw SyncPointPersistenceError.jsonContainerTooLarge(
                maximumElements: SyncPointPersistence.maximumJSONContainerElements
            )
        }
        count += 1
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
        }
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else { throw malformedJSON() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformedJSON() }
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func malformedJSON() -> DecodingError {
        .dataCorrupted(
            .init(
                codingPath: [],
                debugDescription: "Sync-point persistence data is not valid JSON."
            ))
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            byte - 0x30
        case 0x41...0x46:
            byte - 0x41 + 10
        case 0x61...0x66:
            byte - 0x61 + 10
        default:
            nil
        }
    }
}

private func requireSyncPointExactKeys<Value>(
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
