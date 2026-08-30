import CryptoKit
import Foundation

public struct ClipboardHistoryDigest:
    RawRepresentable, Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isCanonical(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public init(validating rawValue: String) throws {
        guard Self.isCanonical(rawValue) else {
            throw ClipboardHistoryError.invalidDigest
        }
        self.rawValue = rawValue
    }

    fileprivate init(bytes: [UInt8]) {
        rawValue = "sha256:" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { "ClipboardHistoryDigest(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["value": "<redacted>"])
    }

    private static func isCanonical(_ value: String) -> Bool {
        let bytes = value.utf8
        guard bytes.count == 71, value.hasPrefix("sha256:") else { return false }
        return bytes.dropFirst(7).allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

private struct ClipboardHistoryFingerprint: Equatable, Hashable, Sendable {
    let bytes: [UInt8]
}

public struct ClipboardHistoryImageMetadata:
    Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
    public let typeIdentifier: String
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public var description: String {
        if let pixelWidth, let pixelHeight {
            return "\(typeIdentifier), \(pixelWidth)x\(pixelHeight)"
        }
        return typeIdentifier
    }

    public var debugDescription: String { description }

    fileprivate init(typeIdentifier: String, pixelWidth: Int?, pixelHeight: Int?) {
        self.typeIdentifier = typeIdentifier
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Validated clipboard payload. It performs no pasteboard access or image decoding.
public struct ClipboardHistoryPayload:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public enum Kind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case text
        case image
    }

    fileprivate enum Storage: Equatable, Sendable {
        case text(String)
        case image(Data)
    }

    public let kind: Kind
    public let digest: ClipboardHistoryDigest
    fileprivate let fingerprint: ClipboardHistoryFingerprint
    public let byteCount: Int
    public let imageMetadata: ClipboardHistoryImageMetadata?
    fileprivate let storage: Storage

    public var text: String? {
        guard case .text(let value) = storage else { return nil }
        return value
    }

    public var imageData: Data? {
        guard case .image(let value) = storage else { return nil }
        return value
    }

    public var description: String {
        "ClipboardHistoryPayload(kind: \(kind.rawValue), byteCount: \(byteCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind.rawValue,
                "byteCount": byteCount,
                "imageMetadata": imageMetadata as Any,
                "payload": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public init(
        text: String,
        maximumBytes: Int = ClipboardHistory.maximumSupportedPayloadBytes
    ) throws {
        guard maximumBytes > 0,
            maximumBytes <= ClipboardHistory.maximumSupportedPayloadBytes
        else {
            throw ClipboardHistoryError.invalidLimits
        }
        var budget = ClipboardHistoryWorkBudget(
            maximumWork: ClipboardHistory.maximumSupportedWork
        )
        try self.init(text: text, maximumBytes: maximumBytes, budget: &budget)
    }

    fileprivate init(
        text: String,
        maximumBytes: Int,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        guard maximumBytes > 0,
            maximumBytes <= ClipboardHistory.maximumSupportedPayloadBytes
        else {
            throw ClipboardHistoryError.invalidLimits
        }
        let result = try Self.fingerprint(text: text, maximumBytes: maximumBytes, budget: &budget)
        kind = .text
        fingerprint = result.fingerprint
        digest = ClipboardHistoryDigest(bytes: result.fingerprint.bytes)
        byteCount = result.byteCount
        imageMetadata = nil
        storage = .text(text)
    }

    public init(
        imageData: Data,
        typeIdentifier: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        maximumBytes: Int = ClipboardHistory.maximumSupportedPayloadBytes
    ) throws {
        guard maximumBytes > 0,
            maximumBytes <= ClipboardHistory.maximumSupportedPayloadBytes
        else {
            throw ClipboardHistoryError.invalidLimits
        }
        guard !imageData.isEmpty else { throw ClipboardHistoryError.emptyPayload }
        guard imageData.count <= maximumBytes else {
            throw ClipboardHistoryError.payloadTooLarge(maximumBytes: maximumBytes)
        }
        try Self.validateTypeIdentifier(
            typeIdentifier,
            maximumBytes: ClipboardHistory.maximumSupportedTypeIdentifierBytes
        )
        try Self.validateDimensions(width: pixelWidth, height: pixelHeight)

        var budget = ClipboardHistoryWorkBudget(
            maximumWork: ClipboardHistory.maximumSupportedWork
        )
        try self.init(
            imageData: imageData,
            typeIdentifier: typeIdentifier,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            maximumBytes: maximumBytes,
            budget: &budget
        )
    }

    fileprivate init(
        imageData: Data,
        typeIdentifier: String,
        pixelWidth: Int?,
        pixelHeight: Int?,
        maximumBytes: Int,
        budget: inout ClipboardHistoryWorkBudget,
        copyImageData: Bool = true
    ) throws {
        guard maximumBytes > 0,
            maximumBytes <= ClipboardHistory.maximumSupportedPayloadBytes
        else {
            throw ClipboardHistoryError.invalidLimits
        }
        guard !imageData.isEmpty else { throw ClipboardHistoryError.emptyPayload }
        guard imageData.count <= maximumBytes else {
            throw ClipboardHistoryError.payloadTooLarge(maximumBytes: maximumBytes)
        }
        try Self.validateTypeIdentifier(
            typeIdentifier,
            maximumBytes: ClipboardHistory.maximumSupportedTypeIdentifierBytes
        )
        try Self.validateDimensions(width: pixelWidth, height: pixelHeight)
        let ownedData = copyImageData ? try Self.copy(imageData, budget: &budget) : imageData
        let fingerprint = try Self.fingerprint(
            imageData: ownedData,
            typeIdentifier: typeIdentifier,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            budget: &budget
        )
        kind = .image
        self.fingerprint = fingerprint
        digest = ClipboardHistoryDigest(bytes: fingerprint.bytes)
        byteCount = ownedData.count
        imageMetadata = ClipboardHistoryImageMetadata(
            typeIdentifier: typeIdentifier,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        storage = .image(ownedData)
    }

    public static func text(
        _ value: String,
        maximumBytes: Int = ClipboardHistory.maximumSupportedPayloadBytes
    ) throws -> ClipboardHistoryPayload {
        try ClipboardHistoryPayload(text: value, maximumBytes: maximumBytes)
    }

    public static func image(
        _ data: Data,
        typeIdentifier: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        maximumBytes: Int = ClipboardHistory.maximumSupportedPayloadBytes
    ) throws -> ClipboardHistoryPayload {
        try ClipboardHistoryPayload(
            imageData: data,
            typeIdentifier: typeIdentifier,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            maximumBytes: maximumBytes
        )
    }

    fileprivate static func validateTypeIdentifier(
        _ value: String,
        maximumBytes: Int
    ) throws {
        var byteCount = 0
        for byte in value.utf8 {
            guard byteCount < maximumBytes, (0x21...0x7E).contains(byte) else {
                throw ClipboardHistoryError.invalidImageTypeIdentifier
            }
            byteCount += 1
        }
        guard byteCount > 0 else { throw ClipboardHistoryError.invalidImageTypeIdentifier }
    }

    fileprivate static func validateDimensions(width: Int?, height: Int?) throws {
        switch (width, height) {
        case (nil, nil):
            return
        case (.some(let width), .some(let height)):
            guard width > 0, height > 0,
                width <= ClipboardHistory.maximumImageDimension,
                height <= ClipboardHistory.maximumImageDimension
            else {
                throw ClipboardHistoryError.invalidImageDimensions
            }
            let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
            guard !overflow, pixelCount <= ClipboardHistory.maximumImagePixelCount else {
                throw ClipboardHistoryError.invalidImageDimensions
            }
        default:
            throw ClipboardHistoryError.invalidImageDimensions
        }
    }

    private static func fingerprint(
        text: String,
        maximumBytes: Int,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> (fingerprint: ClipboardHistoryFingerprint, byteCount: Int) {
        var hasher = SHA256()
        updateDomain(.text, hasher: &hasher)
        var chunk: [UInt8] = []
        chunk.reserveCapacity(16 * 1_024)
        var byteCount = 0
        for byte in text.utf8 {
            guard byteCount < maximumBytes else {
                throw ClipboardHistoryError.payloadTooLarge(maximumBytes: maximumBytes)
            }
            chunk.append(byte)
            byteCount += 1
            if chunk.count == chunk.capacity {
                try budget.charge(chunk.count)
                chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
                chunk.removeAll(keepingCapacity: true)
            }
        }
        guard byteCount > 0 else { throw ClipboardHistoryError.emptyPayload }
        if !chunk.isEmpty {
            try budget.charge(chunk.count)
            chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
        return (finalize(hasher), byteCount)
    }

    private static func fingerprint(
        imageData: Data,
        typeIdentifier: String,
        pixelWidth: Int?,
        pixelHeight: Int?,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> ClipboardHistoryFingerprint {
        var hasher = SHA256()
        updateDomain(.image, hasher: &hasher)
        try update(typeIdentifier.utf8, hasher: &hasher, budget: &budget)
        update(pixelWidth, hasher: &hasher)
        update(pixelHeight, hasher: &hasher)
        try imageData.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let end = Swift.min(offset + 16 * 1_024, bytes.count)
                try budget.charge(end - offset)
                hasher.update(
                    bufferPointer: UnsafeRawBufferPointer(rebasing: bytes[offset..<end])
                )
                offset = end
            }
        }
        return finalize(hasher)
    }

    private static func copy(
        _ data: Data,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Data {
        try Task.checkCancellation()
        try budget.ensureCanCharge(data.count)
        var result = Data()
        result.reserveCapacity(data.count)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let end = Swift.min(offset + 16 * 1_024, bytes.count)
                try budget.charge(end - offset)
                result.append(contentsOf: bytes[offset..<end])
                offset = end
            }
        }
        return result
    }

    private static func update<Bytes>(
        _ bytes: Bytes,
        hasher: inout SHA256,
        budget: inout ClipboardHistoryWorkBudget
    ) throws where Bytes: Collection, Bytes.Element == UInt8 {
        var count = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &count) { hasher.update(bufferPointer: $0) }
        var chunk: [UInt8] = []
        chunk.reserveCapacity(4 * 1_024)
        for byte in bytes {
            chunk.append(byte)
            if chunk.count == chunk.capacity {
                try budget.charge(chunk.count)
                chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            try budget.charge(chunk.count)
            chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
    }

    private static func update(_ value: Int?, hasher: inout SHA256) {
        var encoded = UInt64(value ?? 0).bigEndian
        withUnsafeBytes(of: &encoded) { hasher.update(bufferPointer: $0) }
    }

    private static func updateDomain(_ kind: Kind, hasher: inout SHA256) {
        var domain: UInt8 = kind == .text ? 1 : 2
        withUnsafeBytes(of: &domain) { hasher.update(bufferPointer: $0) }
    }

    private static func finalize(_ hasher: SHA256) -> ClipboardHistoryFingerprint {
        ClipboardHistoryFingerprint(bytes: Array(hasher.finalize()))
    }

    fileprivate func hasSameContent(
        as other: ClipboardHistoryPayload,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Bool {
        guard kind == other.kind, fingerprint == other.fingerprint, byteCount == other.byteCount,
            imageMetadata == other.imageMetadata
        else {
            return false
        }
        switch (storage, other.storage) {
        case (.text(let left), .text(let right)):
            var leftIterator = left.utf8.makeIterator()
            var rightIterator = right.utf8.makeIterator()
            while let leftByte = leftIterator.next() {
                try budget.charge(1)
                guard leftByte == rightIterator.next() else { return false }
            }
            return rightIterator.next() == nil
        case (.image(let left), .image(let right)):
            return try ClipboardHistory.equal(left, right, budget: &budget)
        default:
            return false
        }
    }
}

public struct ClipboardHistoryEntryID:
    RawRepresentable, Equatable, Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let rawValue: String

    public init() {
        rawValue = UUID().uuidString.lowercased()
    }

    public init?(rawValue: String) {
        guard rawValue.utf8.count == 36, rawValue == rawValue.lowercased(),
            let value = UUID(uuidString: rawValue),
            value.uuidString.lowercased() == rawValue
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    fileprivate init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    public var description: String { rawValue }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["identifier": rawValue])
    }
}

/// Immutable payload-bearing request captured from two selected history entries.
public struct ClipboardHistoryComparisonRequest:
    Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public struct Input:
        Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public let id: ClipboardHistoryEntryID
        public let sourceIdentifier: String
        public let timestamp: Date
        public let payload: ClipboardHistoryPayload

        public var kind: ClipboardHistoryPayload.Kind { payload.kind }
        public var byteCount: Int { payload.byteCount }

        public var description: String {
            "ClipboardHistoryComparisonRequest.Input(kind: \(kind.rawValue), byteCount: \(byteCount))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "id": id,
                    "sourceIdentifier": sourceIdentifier,
                    "timestamp": timestamp,
                    "kind": kind.rawValue,
                    "byteCount": byteCount,
                    "payload": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate init(entry: ClipboardHistory.Entry, payload: ClipboardHistoryPayload) {
            id = entry.id
            sourceIdentifier = entry.sourceIdentifier
            timestamp = entry.timestamp
            self.payload = payload
        }

        fileprivate func matches(
            _ entry: ClipboardHistory.Entry,
            budget: inout ClipboardHistoryWorkBudget
        ) throws -> Bool {
            guard id == entry.id, sourceIdentifier == entry.sourceIdentifier,
                timestamp == entry.timestamp, byteCount == entry.byteCount,
                payload.imageMetadata == entry.imageMetadata, let entryPayload = entry.payload
            else {
                return false
            }
            return try payload.hasSameContent(as: entryPayload, budget: &budget)
        }
    }

    public let left: Input
    public let right: Input
    public let kind: ClipboardHistoryPayload.Kind
    public let historyRevision: UInt64

    public var description: String {
        "ClipboardHistoryComparisonRequest(kind: \(kind.rawValue))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind.rawValue,
                "historyRevision": historyRevision,
                "left": left.description,
                "right": right.description,
                "payloads": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    fileprivate init(left: Input, right: Input, historyRevision: UInt64) {
        self.left = left
        self.right = right
        kind = left.kind
        self.historyRevision = historyRevision
    }

    public func isStale(in history: ClipboardHistory) throws -> Bool {
        try !history.isCurrent(self)
    }
}

/// Value-semantic, bounded pinned-first MRU clipboard history.
///
/// Callers supply source identifiers and timestamps after reading their trusted clipboard source.
/// This type never accesses a pasteboard, clock, UI framework, filesystem, or image decoder.
public struct ClipboardHistory:
    Equatable, Sendable, RandomAccessCollection, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public static let currentSchemaVersion = 2
    public static let defaultMaximumEntries = 50
    public static let maximumSupportedEntries = 1_000
    public static let defaultMaximumPayloadBytes = 32 * 1_024 * 1_024
    public static let maximumSupportedPayloadBytes = 128 * 1_024 * 1_024
    public static let defaultMaximumRetainedPayloadBytes = 64 * 1_024 * 1_024
    public static let maximumSupportedRetainedPayloadBytes = 256 * 1_024 * 1_024
    public static let defaultMaximumSourceIdentifierBytes = 1_024
    public static let maximumSupportedSourceIdentifierBytes = 16 * 1_024
    public static let defaultMaximumTypeIdentifierBytes = 512
    public static let maximumSupportedTypeIdentifierBytes = 4 * 1_024
    public static let defaultMaximumWork = 1 * 1_024 * 1_024 * 1_024
    public static let maximumSupportedWork = 4 * 1_024 * 1_024 * 1_024
    public static let defaultMaximumPersistenceBytes = 96 * 1_024 * 1_024
    public static let maximumSupportedPersistenceBytes = 384 * 1_024 * 1_024
    public static let maximumImageDimension = 1_000_000
    public static let maximumImagePixelCount = 1_000_000_000
    public static let maximumSelectionCount = 2

    public typealias Index = Int

    public enum PersistencePolicy: String, Codable, CaseIterable, Equatable, Sendable {
        /// Persists metadata, ordering, pinning, and selection without text or image bytes.
        case metadataOnly

        /// Allows plaintext payload bytes in output intended for caller-protected storage.
        /// This policy provides no encryption and must also be supplied when decoding such data.
        case secureSnapshot
    }

    public struct Limits: Equatable, Sendable {
        public static let `default` = Limits(
            uncheckedMaximumEntries: ClipboardHistory.defaultMaximumEntries,
            maximumPayloadBytes: ClipboardHistory.defaultMaximumPayloadBytes,
            maximumRetainedPayloadBytes: ClipboardHistory.defaultMaximumRetainedPayloadBytes,
            maximumSourceIdentifierBytes: ClipboardHistory.defaultMaximumSourceIdentifierBytes,
            maximumTypeIdentifierBytes: ClipboardHistory.defaultMaximumTypeIdentifierBytes,
            maximumWork: ClipboardHistory.defaultMaximumWork,
            maximumPersistenceBytes: ClipboardHistory.defaultMaximumPersistenceBytes
        )

        public let maximumEntries: Int
        public let maximumPayloadBytes: Int
        public let maximumRetainedPayloadBytes: Int
        public let maximumSourceIdentifierBytes: Int
        public let maximumTypeIdentifierBytes: Int
        public let maximumWork: Int
        public let maximumPersistenceBytes: Int

        public init(
            maximumEntries: Int = ClipboardHistory.defaultMaximumEntries,
            maximumPayloadBytes: Int = ClipboardHistory.defaultMaximumPayloadBytes,
            maximumRetainedPayloadBytes: Int = ClipboardHistory.defaultMaximumRetainedPayloadBytes,
            maximumSourceIdentifierBytes: Int = ClipboardHistory.defaultMaximumSourceIdentifierBytes,
            maximumTypeIdentifierBytes: Int = ClipboardHistory.defaultMaximumTypeIdentifierBytes,
            maximumWork: Int = ClipboardHistory.defaultMaximumWork,
            maximumPersistenceBytes: Int = ClipboardHistory.defaultMaximumPersistenceBytes
        ) throws {
            guard
                Self.isValid(
                    maximumEntries: maximumEntries,
                    maximumPayloadBytes: maximumPayloadBytes,
                    maximumRetainedPayloadBytes: maximumRetainedPayloadBytes,
                    maximumSourceIdentifierBytes: maximumSourceIdentifierBytes,
                    maximumTypeIdentifierBytes: maximumTypeIdentifierBytes,
                    maximumWork: maximumWork,
                    maximumPersistenceBytes: maximumPersistenceBytes
                )
            else {
                throw ClipboardHistoryError.invalidLimits
            }
            self.maximumEntries = maximumEntries
            self.maximumPayloadBytes = maximumPayloadBytes
            self.maximumRetainedPayloadBytes = maximumRetainedPayloadBytes
            self.maximumSourceIdentifierBytes = maximumSourceIdentifierBytes
            self.maximumTypeIdentifierBytes = maximumTypeIdentifierBytes
            self.maximumWork = maximumWork
            self.maximumPersistenceBytes = maximumPersistenceBytes
        }

        private init(
            uncheckedMaximumEntries maximumEntries: Int,
            maximumPayloadBytes: Int,
            maximumRetainedPayloadBytes: Int,
            maximumSourceIdentifierBytes: Int,
            maximumTypeIdentifierBytes: Int,
            maximumWork: Int,
            maximumPersistenceBytes: Int
        ) {
            self.maximumEntries = maximumEntries
            self.maximumPayloadBytes = maximumPayloadBytes
            self.maximumRetainedPayloadBytes = maximumRetainedPayloadBytes
            self.maximumSourceIdentifierBytes = maximumSourceIdentifierBytes
            self.maximumTypeIdentifierBytes = maximumTypeIdentifierBytes
            self.maximumWork = maximumWork
            self.maximumPersistenceBytes = maximumPersistenceBytes
        }

        fileprivate init(validating wire: ClipboardHistoryWireLimits) throws {
            try self.init(
                maximumEntries: wire.maximumEntries,
                maximumPayloadBytes: wire.maximumPayloadBytes,
                maximumRetainedPayloadBytes: wire.maximumRetainedPayloadBytes,
                maximumSourceIdentifierBytes: wire.maximumSourceIdentifierBytes,
                maximumTypeIdentifierBytes: wire.maximumTypeIdentifierBytes,
                maximumWork: wire.maximumWork,
                maximumPersistenceBytes: wire.maximumPersistenceBytes
            )
        }

        fileprivate func permits(_ other: Limits) -> Bool {
            other.maximumEntries <= maximumEntries
                && other.maximumPayloadBytes <= maximumPayloadBytes
                && other.maximumRetainedPayloadBytes <= maximumRetainedPayloadBytes
                && other.maximumSourceIdentifierBytes <= maximumSourceIdentifierBytes
                && other.maximumTypeIdentifierBytes <= maximumTypeIdentifierBytes
                && other.maximumWork <= maximumWork
                && other.maximumPersistenceBytes <= maximumPersistenceBytes
        }

        private static func isValid(
            maximumEntries: Int,
            maximumPayloadBytes: Int,
            maximumRetainedPayloadBytes: Int,
            maximumSourceIdentifierBytes: Int,
            maximumTypeIdentifierBytes: Int,
            maximumWork: Int,
            maximumPersistenceBytes: Int
        ) -> Bool {
            maximumEntries > 0
                && maximumEntries <= ClipboardHistory.maximumSupportedEntries
                && maximumPayloadBytes > 0
                && maximumPayloadBytes <= ClipboardHistory.maximumSupportedPayloadBytes
                && maximumRetainedPayloadBytes >= maximumPayloadBytes
                && maximumRetainedPayloadBytes
                    <= ClipboardHistory.maximumSupportedRetainedPayloadBytes
                && maximumSourceIdentifierBytes > 0
                && maximumSourceIdentifierBytes
                    <= ClipboardHistory.maximumSupportedSourceIdentifierBytes
                && maximumTypeIdentifierBytes > 0
                && maximumTypeIdentifierBytes
                    <= ClipboardHistory.maximumSupportedTypeIdentifierBytes
                && maximumWork > 0
                && maximumWork <= ClipboardHistory.maximumSupportedWork
                && maximumPersistenceBytes > 0
                && maximumPersistenceBytes
                    <= ClipboardHistory.maximumSupportedPersistenceBytes
                && maximumPersistenceBytes <= maximumWork / 8
        }
    }

    public struct Entry:
        Identifiable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public typealias ID = ClipboardHistoryEntryID

        public let id: ID
        public let kind: ClipboardHistoryPayload.Kind
        public let byteCount: Int
        public let imageMetadata: ClipboardHistoryImageMetadata?
        public let sourceIdentifier: String
        public let timestamp: Date
        public let isPinned: Bool
        public let payload: ClipboardHistoryPayload?
        fileprivate let recency: UInt64

        public var hasPayload: Bool { payload != nil }

        public var description: String {
            "ClipboardHistory.Entry(id: \(id), kind: \(kind.rawValue), byteCount: \(byteCount), pinned: \(isPinned))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "id": id,
                    "kind": kind.rawValue,
                    "byteCount": byteCount,
                    "imageMetadata": imageMetadata as Any,
                    "sourceIdentifier": sourceIdentifier,
                    "timestamp": timestamp,
                    "isPinned": isPinned,
                    "hasPayload": hasPayload,
                    "payload": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        fileprivate init(
            payload: ClipboardHistoryPayload?,
            id: ID,
            kind: ClipboardHistoryPayload.Kind,
            byteCount: Int,
            imageMetadata: ClipboardHistoryImageMetadata?,
            sourceIdentifier: String,
            timestamp: Date,
            isPinned: Bool,
            recency: UInt64
        ) {
            self.id = id
            self.kind = kind
            self.byteCount = byteCount
            self.imageMetadata = imageMetadata
            self.sourceIdentifier = sourceIdentifier
            self.timestamp = timestamp
            self.isPinned = isPinned
            self.payload = payload
            self.recency = recency
        }

        fileprivate init(
            payload: ClipboardHistoryPayload,
            id: ID,
            sourceIdentifier: String,
            timestamp: Date,
            isPinned: Bool,
            recency: UInt64
        ) {
            self.init(
                payload: payload,
                id: id,
                kind: payload.kind,
                byteCount: payload.byteCount,
                imageMetadata: payload.imageMetadata,
                sourceIdentifier: sourceIdentifier,
                timestamp: timestamp,
                isPinned: isPinned,
                recency: recency
            )
        }

        fileprivate func replacing(isPinned: Bool) -> Entry {
            Entry(
                payload: payload,
                id: id,
                kind: kind,
                byteCount: byteCount,
                imageMetadata: imageMetadata,
                sourceIdentifier: sourceIdentifier,
                timestamp: timestamp,
                isPinned: isPinned,
                recency: recency
            )
        }
    }

    public let limits: Limits
    public private(set) var entries: [Entry]
    public private(set) var selectedIDs: [Entry.ID]
    public private(set) var retainedPayloadByteCount: Int
    public private(set) var revision: UInt64

    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }
    public var latest: Entry? { entries.max { $0.recency < $1.recency } }
    public var selectedEntries: [Entry] {
        selectedIDs.compactMap { id in entries.first { $0.id == id } }
    }

    public subscript(position: Int) -> Entry { entries[position] }

    public var description: String {
        "ClipboardHistory(entryCount: \(entries.count), selectedCount: \(selectedIDs.count), retainedPayloadByteCount: \(retainedPayloadByteCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "limits": limits,
                "entryCount": entries.count,
                "selectedCount": selectedIDs.count,
                "retainedPayloadByteCount": retainedPayloadByteCount,
                "revision": revision,
                "entries": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public init(limits: Limits = .default) {
        self.limits = limits
        entries = []
        selectedIDs = []
        retainedPayloadByteCount = 0
        revision = 0
    }

    /// Records or promotes a payload. Pinned entries remain before unpinned entries.
    /// Duplicate payloads retain an existing pin unless explicitly pinned again.
    @discardableResult
    public mutating func record(
        _ payload: ClipboardHistoryPayload,
        sourceIdentifier: String,
        timestamp: Date,
        pinned: Bool = false
    ) throws -> Bool {
        try Task.checkCancellation()
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        return try record(
            payload,
            sourceIdentifier: sourceIdentifier,
            timestamp: timestamp,
            pinned: pinned,
            budget: &budget
        )
    }

    private mutating func record(
        _ payload: ClipboardHistoryPayload,
        sourceIdentifier: String,
        timestamp: Date,
        pinned: Bool,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Bool {
        try validate(payload: payload, budget: &budget)
        try Self.validateSourceIdentifier(
            sourceIdentifier,
            maximumBytes: limits.maximumSourceIdentifierBytes,
            budget: &budget
        )
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw ClipboardHistoryError.invalidTimestamp
        }

        let existingIndex = try index(of: payload, budget: &budget)
        let id = try existingIndex.map { entries[$0].id } ?? uniqueID(budget: &budget)
        let effectivePinned = pinned || existingIndex.map { entries[$0].isPinned } == true

        var candidateEntries = entries
        var candidateSelection = selectedIDs
        var candidateBytes = retainedPayloadByteCount
        if let existingIndex {
            if let oldPayload = candidateEntries[existingIndex].payload {
                candidateBytes -= oldPayload.byteCount
            }
            candidateEntries.remove(at: existingIndex)
        }

        let firstUnpinned = try Self.firstUnpinnedIndex(
            in: candidateEntries,
            budget: &budget
        )
        let insertionIndex = effectivePinned ? 0 : firstUnpinned
        if let existingIndex {
            let existing = entries[existingIndex]
            let isUnchanged =
                existingIndex == insertionIndex
                && existing.id == latest?.id
                && existing.sourceIdentifier == sourceIdentifier
                && existing.timestamp == timestamp
                && existing.isPinned == effectivePinned
            if isUnchanged { return false }
        }
        let nextRevision = try advancedRevision()
        let newEntry = Entry(
            payload: payload,
            id: id,
            sourceIdentifier: sourceIdentifier,
            timestamp: timestamp,
            isPinned: effectivePinned,
            recency: nextRevision
        )
        candidateEntries.insert(newEntry, at: insertionIndex)
        candidateBytes = try Self.addingPayloadBytes(candidateBytes, payload.byteCount)

        while candidateEntries.count > limits.maximumEntries
            || candidateBytes > limits.maximumRetainedPayloadBytes
        {
            guard
                let evictionIndex = try Self.lastEvictableIndex(
                    in: candidateEntries,
                    excluding: id,
                    budget: &budget
                )
            else {
                throw ClipboardHistoryError.pinnedEntriesPreventEviction
            }
            let evicted = candidateEntries.remove(at: evictionIndex)
            if let evictedPayload = evicted.payload {
                candidateBytes -= evictedPayload.byteCount
            }
            candidateSelection.removeAll { $0 == evicted.id }
        }

        entries = candidateEntries
        selectedIDs = candidateSelection
        retainedPayloadByteCount = candidateBytes
        revision = nextRevision
        return true
    }

    @discardableResult
    public mutating func recordText(
        _ text: String,
        sourceIdentifier: String,
        timestamp: Date,
        pinned: Bool = false
    ) throws -> Bool {
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        let payload = try ClipboardHistoryPayload(
            text: text,
            maximumBytes: limits.maximumPayloadBytes,
            budget: &budget
        )
        return try record(
            payload,
            sourceIdentifier: sourceIdentifier,
            timestamp: timestamp,
            pinned: pinned,
            budget: &budget
        )
    }

    @discardableResult
    public mutating func recordImage(
        _ data: Data,
        typeIdentifier: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        sourceIdentifier: String,
        timestamp: Date,
        pinned: Bool = false
    ) throws -> Bool {
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        let payload = try ClipboardHistoryPayload(
            imageData: data,
            typeIdentifier: typeIdentifier,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            maximumBytes: limits.maximumPayloadBytes,
            budget: &budget
        )
        return try record(
            payload,
            sourceIdentifier: sourceIdentifier,
            timestamp: timestamp,
            pinned: pinned,
            budget: &budget
        )
    }

    @discardableResult
    public mutating func setPinned(_ pinned: Bool, for id: Entry.ID) throws -> Bool {
        try Task.checkCancellation()
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        guard let index = try index(of: id, budget: &budget) else { return false }
        let entry = entries[index]
        guard entry.isPinned != pinned else { return false }

        var candidate = entries
        candidate.remove(at: index)
        let insertionIndex = try Self.insertionIndex(
            for: entry.recency,
            pinned: pinned,
            in: candidate,
            budget: &budget
        )
        candidate.insert(entry.replacing(isPinned: pinned), at: insertionIndex)
        let nextRevision = try advancedRevision()
        entries = candidate
        revision = nextRevision
        return true
    }

    @discardableResult
    public mutating func remove(_ id: Entry.ID) throws -> Bool {
        try Task.checkCancellation()
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        guard let index = try index(of: id, budget: &budget) else { return false }
        let nextRevision = try advancedRevision()
        let removed = entries.remove(at: index)
        if let payload = removed.payload {
            retainedPayloadByteCount -= payload.byteCount
        }
        selectedIDs.removeAll { $0 == id }
        revision = nextRevision
        return true
    }

    /// Clears all entries, including pinned entries, and clears selection.
    @discardableResult
    public mutating func clear() throws -> Bool {
        try Task.checkCancellation()
        guard !entries.isEmpty || !selectedIDs.isEmpty else { return false }
        let nextRevision = try advancedRevision()
        entries.removeAll(keepingCapacity: true)
        selectedIDs.removeAll(keepingCapacity: true)
        retainedPayloadByteCount = 0
        revision = nextRevision
        return true
    }

    /// Clears only unpinned entries and any selection referencing them.
    @discardableResult
    public mutating func clearUnpinned() throws -> Int {
        try Task.checkCancellation()
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        var retained: [Entry] = []
        retained.reserveCapacity(entries.count)
        var removedIDs: Set<Entry.ID> = []
        var retainedBytes = 0
        for entry in entries {
            try budget.charge(1)
            if entry.isPinned {
                retained.append(entry)
                if let payload = entry.payload {
                    retainedBytes = try Self.addingPayloadBytes(retainedBytes, payload.byteCount)
                }
            } else {
                removedIDs.insert(entry.id)
            }
        }
        guard !removedIDs.isEmpty else { return 0 }
        let nextRevision = try advancedRevision()
        entries = retained
        selectedIDs.removeAll { removedIDs.contains($0) }
        retainedPayloadByteCount = retainedBytes
        revision = nextRevision
        return removedIDs.count
    }

    /// Replaces selection unless `extendingSelection` is true. At most two entries may be selected.
    @discardableResult
    public mutating func select(
        _ id: Entry.ID,
        extendingSelection: Bool = false
    ) throws -> Bool {
        try Task.checkCancellation()
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        guard try index(of: id, budget: &budget) != nil else {
            throw ClipboardHistoryError.entryNotFound
        }
        var candidate = extendingSelection ? selectedIDs : []
        if candidate.contains(id) {
            return extendingSelection ? false : candidate != selectedIDs
        }
        guard candidate.count < Self.maximumSelectionCount else {
            throw ClipboardHistoryError.selectionLimitExceeded(
                maximumCount: Self.maximumSelectionCount
            )
        }
        candidate.append(id)
        guard candidate != selectedIDs else { return false }
        let nextRevision = try advancedRevision()
        selectedIDs = candidate
        revision = nextRevision
        return true
    }

    @discardableResult
    public mutating func setSelection(_ ids: [Entry.ID]) throws -> Bool {
        try Task.checkCancellation()
        guard ids.count <= Self.maximumSelectionCount else {
            throw ClipboardHistoryError.selectionLimitExceeded(
                maximumCount: Self.maximumSelectionCount
            )
        }
        guard Set(ids).count == ids.count else {
            throw ClipboardHistoryError.duplicateSelection
        }
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        for id in ids where try index(of: id, budget: &budget) == nil {
            throw ClipboardHistoryError.entryNotFound
        }
        guard ids != selectedIDs else { return false }
        let nextRevision = try advancedRevision()
        selectedIDs = ids
        revision = nextRevision
        return true
    }

    @discardableResult
    public mutating func toggleSelection(_ id: Entry.ID) throws -> Bool {
        if let selectedIndex = selectedIDs.firstIndex(of: id) {
            var candidate = selectedIDs
            candidate.remove(at: selectedIndex)
            return try setSelection(candidate)
        }
        return try select(id, extendingSelection: true)
    }

    @discardableResult
    public mutating func clearSelection() throws -> Bool {
        try Task.checkCancellation()
        guard !selectedIDs.isEmpty else { return false }
        let nextRevision = try advancedRevision()
        selectedIDs.removeAll(keepingCapacity: true)
        revision = nextRevision
        return true
    }

    public func comparisonRequest() throws -> ClipboardHistoryComparisonRequest {
        try Task.checkCancellation()
        guard selectedIDs.count == Self.maximumSelectionCount else {
            throw ClipboardHistoryError.comparisonSelectionRequired
        }
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        guard let leftEntry = try entry(for: selectedIDs[0], budget: &budget),
            let rightEntry = try entry(for: selectedIDs[1], budget: &budget)
        else {
            throw ClipboardHistoryError.staleComparisonRequest
        }
        guard leftEntry.kind == rightEntry.kind else {
            throw ClipboardHistoryError.mixedPayloadKinds
        }
        guard let leftPayload = leftEntry.payload, let rightPayload = rightEntry.payload else {
            throw ClipboardHistoryError.payloadUnavailable
        }
        return ClipboardHistoryComparisonRequest(
            left: .init(entry: leftEntry, payload: leftPayload),
            right: .init(entry: rightEntry, payload: rightPayload),
            historyRevision: revision
        )
    }

    public func isCurrent(_ request: ClipboardHistoryComparisonRequest) throws -> Bool {
        try Task.checkCancellation()
        guard request.historyRevision == revision else { return false }
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        guard let left = try entry(for: request.left.id, budget: &budget),
            let right = try entry(for: request.right.id, budget: &budget)
        else {
            return false
        }
        return try request.left.matches(left, budget: &budget)
            && request.right.matches(right, budget: &budget)
    }

    public func validate(_ request: ClipboardHistoryComparisonRequest) throws {
        guard try isCurrent(request) else {
            throw ClipboardHistoryError.staleComparisonRequest
        }
    }

    /// Returns compact canonical JSON. Raw payloads are omitted unless explicitly permitted.
    public func encodedData(policy: PersistencePolicy = .metadataOnly) throws -> Data {
        var budget = ClipboardHistoryWorkBudget(maximumWork: limits.maximumWork)
        return try encodedData(policy: policy, budget: &budget)
    }

    /// Strictly accepts canonical schema data. Secure snapshots require explicit read permission.
    public static func decode(
        from data: Data,
        policy: PersistencePolicy = .metadataOnly,
        limits callerLimits: Limits = .default
    ) throws -> ClipboardHistory {
        guard data.count <= callerLimits.maximumPersistenceBytes else {
            throw ClipboardHistoryError.persistenceDataTooLarge(
                maximumBytes: callerLimits.maximumPersistenceBytes
            )
        }
        do {
            let preflight = try data.withUnsafeBytes { rawBuffer in
                var scanner = ClipboardHistoryJSONScanner(
                    bytes: rawBuffer.bindMemory(to: UInt8.self)
                )
                return try scanner.validate()
            }
            guard preflight.schemaVersion == Self.currentSchemaVersion else {
                throw ClipboardHistoryError.unsupportedSchemaVersion(preflight.schemaVersion)
            }
            guard preflight.persistencePolicy != .secureSnapshot || policy == .secureSnapshot else {
                throw ClipboardHistoryError.secureSnapshotPolicyRequired
            }
            let preflightLimits = try Limits(validating: preflight.limits)
            guard callerLimits.permits(preflightLimits) else {
                throw ClipboardHistoryError.decodedLimitsExceedCallerLimits
            }
            guard data.count <= preflightLimits.maximumPersistenceBytes else {
                throw ClipboardHistoryError.persistenceDataTooLarge(
                    maximumBytes: preflightLimits.maximumPersistenceBytes
                )
            }
            var budget = ClipboardHistoryWorkBudget(maximumWork: preflightLimits.maximumWork)
            let wire = try data.withUnsafeBytes { rawBuffer in
                var parser = ClipboardHistoryCanonicalParser(
                    bytes: rawBuffer.bindMemory(to: UInt8.self),
                    budget: budget,
                    limits: preflightLimits
                )
                let wire = try parser.parse()
                budget = parser.budget
                return wire
            }
            let limits = try Limits(validating: wire.limits)
            guard data.count <= limits.maximumPersistenceBytes else {
                throw ClipboardHistoryError.persistenceDataTooLarge(
                    maximumBytes: limits.maximumPersistenceBytes
                )
            }
            guard wire.persistencePolicy == preflight.persistencePolicy else {
                throw ClipboardHistoryError.nonCanonicalPersistence
            }
            guard limits == preflightLimits else {
                throw ClipboardHistoryError.nonCanonicalPersistence
            }
            guard wire.entries.count <= limits.maximumEntries else {
                throw ClipboardHistoryError.nonCanonicalPersistence
            }

            var entries: [Entry] = []
            entries.reserveCapacity(wire.entries.count)
            var ids: Set<Entry.ID> = []
            var payloadIndicesByFingerprint: [ClipboardHistoryFingerprint: [Int]] = [:]
            var encounteredUnpinned = false
            var previousPinnedRecency: UInt64?
            var previousUnpinnedRecency: UInt64?
            var recencies: Set<UInt64> = []
            var retainedBytes = 0
            for wireEntry in wire.entries {
                try budget.charge(1)
                let entry = try wireEntry.entry(
                    policy: wire.persistencePolicy,
                    limits: limits,
                    budget: &budget
                )
                guard ids.insert(entry.id).inserted else {
                    throw ClipboardHistoryError.duplicateEntry
                }
                guard entry.recency > 0, entry.recency <= wire.revision,
                    recencies.insert(entry.recency).inserted
                else {
                    throw ClipboardHistoryError.nonCanonicalPersistence
                }
                if entry.isPinned {
                    guard !encounteredUnpinned else {
                        throw ClipboardHistoryError.nonCanonicalPersistence
                    }
                    if let previousPinnedRecency, entry.recency >= previousPinnedRecency {
                        throw ClipboardHistoryError.nonCanonicalPersistence
                    }
                    previousPinnedRecency = entry.recency
                } else {
                    encounteredUnpinned = true
                    if let previousUnpinnedRecency, entry.recency >= previousUnpinnedRecency {
                        throw ClipboardHistoryError.nonCanonicalPersistence
                    }
                    previousUnpinnedRecency = entry.recency
                }
                if let payload = entry.payload {
                    for existingIndex in payloadIndicesByFingerprint[payload.fingerprint] ?? [] {
                        try budget.charge(1)
                        guard let existingPayload = entries[existingIndex].payload else {
                            throw ClipboardHistoryError.nonCanonicalPersistence
                        }
                        if try payload.hasSameContent(as: existingPayload, budget: &budget) {
                            throw ClipboardHistoryError.duplicateEntry
                        }
                    }
                    payloadIndicesByFingerprint[payload.fingerprint, default: []].append(
                        entries.count
                    )
                    retainedBytes = try addingPayloadBytes(retainedBytes, payload.byteCount)
                    guard retainedBytes <= limits.maximumRetainedPayloadBytes else {
                        throw ClipboardHistoryError.retainedPayloadLimitExceeded(
                            maximumBytes: limits.maximumRetainedPayloadBytes
                        )
                    }
                }
                entries.append(entry)
            }

            guard wire.selection.count <= Self.maximumSelectionCount else {
                throw ClipboardHistoryError.selectionLimitExceeded(
                    maximumCount: Self.maximumSelectionCount
                )
            }
            var selectedIDs: [Entry.ID] = []
            var selectedSet: Set<Entry.ID> = []
            for wireID in wire.selection {
                let id = try wireID.id()
                guard selectedSet.insert(id).inserted else {
                    throw ClipboardHistoryError.duplicateSelection
                }
                guard ids.contains(id) else { throw ClipboardHistoryError.entryNotFound }
                selectedIDs.append(id)
            }

            var result = ClipboardHistory(limits: limits)
            result.entries = entries
            result.selectedIDs = selectedIDs
            result.retainedPayloadByteCount = retainedBytes
            result.revision = wire.revision
            guard
                try result.hasCanonicalEncoding(
                    policy: wire.persistencePolicy,
                    matching: data,
                    budget: &budget
                )
            else {
                throw ClipboardHistoryError.nonCanonicalPersistence
            }
            return result
        } catch let error as ClipboardHistoryError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ClipboardHistoryError.malformedPersistence
        }
    }

    private func encodedData(
        policy: PersistencePolicy,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Data {
        try Task.checkCancellation()
        if policy == .secureSnapshot, entries.contains(where: { $0.payload == nil }) {
            throw ClipboardHistoryError.payloadUnavailable
        }
        var writer = ClipboardHistoryCanonicalWriter(
            maximumBytes: limits.maximumPersistenceBytes
        )
        return try writer.encode(self, policy: policy, budget: &budget)
    }

    private func hasCanonicalEncoding(
        policy: PersistencePolicy,
        matching data: Data,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Bool {
        try data.withUnsafeBytes { rawBuffer in
            var writer = ClipboardHistoryCanonicalWriter(
                maximumBytes: limits.maximumPersistenceBytes,
                comparingWith: rawBuffer.bindMemory(to: UInt8.self)
            )
            return try writer.matches(self, policy: policy, budget: &budget)
        }
    }

    private func validate(
        payload: ClipboardHistoryPayload,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        guard payload.byteCount > 0 else { throw ClipboardHistoryError.emptyPayload }
        guard payload.byteCount <= limits.maximumPayloadBytes else {
            throw ClipboardHistoryError.payloadTooLarge(
                maximumBytes: limits.maximumPayloadBytes
            )
        }
        switch payload.kind {
        case .text:
            guard payload.text != nil, payload.imageMetadata == nil else {
                throw ClipboardHistoryError.invalidPayloadKind
            }
        case .image:
            guard payload.imageData != nil, let metadata = payload.imageMetadata else {
                throw ClipboardHistoryError.invalidPayloadKind
            }
            try ClipboardHistoryPayload.validateTypeIdentifier(
                metadata.typeIdentifier,
                maximumBytes: limits.maximumTypeIdentifierBytes
            )
            try ClipboardHistoryPayload.validateDimensions(
                width: metadata.pixelWidth,
                height: metadata.pixelHeight
            )
        }
        try budget.charge(1)
    }

    fileprivate static func validateSourceIdentifier(
        _ value: String,
        maximumBytes: Int,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        var byteCount = 0
        for byte in value.utf8 {
            guard byteCount < maximumBytes else {
                throw ClipboardHistoryError.invalidSourceIdentifier
            }
            byteCount += 1
            try budget.charge(1)
            if byte == 0 { throw ClipboardHistoryError.invalidSourceIdentifier }
        }
        guard byteCount > 0, value.contains(where: { !$0.isWhitespace }),
            value.unicodeScalars.allSatisfy({ scalar in
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    return false
                default:
                    return true
                }
            })
        else {
            throw ClipboardHistoryError.invalidSourceIdentifier
        }
        try budget.charge(byteCount * 2)
    }

    private func index(
        of id: Entry.ID,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Int? {
        for index in entries.indices {
            try budget.charge(1)
            if entries[index].id == id { return index }
        }
        return nil
    }

    private func index(
        of payload: ClipboardHistoryPayload,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Int? {
        for index in entries.indices {
            try budget.charge(1)
            guard let existing = entries[index].payload else { continue }
            if try existing.hasSameContent(as: payload, budget: &budget) { return index }
        }
        return nil
    }

    private func uniqueID(
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Entry.ID {
        while true {
            let candidate = Entry.ID()
            if try index(of: candidate, budget: &budget) == nil { return candidate }
        }
    }

    private func entry(
        for id: Entry.ID,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Entry? {
        guard let index = try index(of: id, budget: &budget) else { return nil }
        return entries[index]
    }

    private static func firstUnpinnedIndex(
        in entries: [Entry],
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Int {
        for index in entries.indices {
            try budget.charge(1)
            if !entries[index].isPinned { return index }
        }
        return entries.endIndex
    }

    private static func insertionIndex(
        for recency: UInt64,
        pinned: Bool,
        in entries: [Entry],
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Int {
        for index in entries.indices {
            try budget.charge(1)
            let entry = entries[index]
            if pinned {
                if !entry.isPinned || entry.recency < recency { return index }
            } else if !entry.isPinned, entry.recency < recency {
                return index
            }
        }
        return entries.endIndex
    }

    private static func lastEvictableIndex(
        in entries: [Entry],
        excluding id: Entry.ID,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Int? {
        for index in entries.indices.reversed() {
            try budget.charge(1)
            if !entries[index].isPinned, entries[index].id != id { return index }
        }
        return nil
    }

    fileprivate static func addingPayloadBytes(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow, result >= 0 else {
            throw ClipboardHistoryError.retainedPayloadLimitExceeded(
                maximumBytes: Self.maximumSupportedRetainedPayloadBytes
            )
        }
        return result
    }

    fileprivate static func equal(
        _ left: Data,
        _ right: Data,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        return try left.withUnsafeBytes { leftBytes in
            try right.withUnsafeBytes { rightBytes in
                var offset = 0
                while offset < leftBytes.count {
                    let end = Swift.min(offset + 16 * 1_024, leftBytes.count)
                    try budget.charge(end - offset)
                    guard leftBytes[offset..<end].elementsEqual(rightBytes[offset..<end]) else {
                        return false
                    }
                    offset = end
                }
                return true
            }
        }
    }

    private func advancedRevision() throws -> UInt64 {
        guard revision < .max else { throw ClipboardHistoryError.revisionSpaceExhausted }
        return revision + 1
    }
}

public typealias ClipboardHistoryEntry = ClipboardHistory.Entry
public typealias ClipboardHistoryPersistencePolicy = ClipboardHistory.PersistencePolicy

public enum ClipboardHistoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case emptyPayload
    case payloadTooLarge(maximumBytes: Int)
    case retainedPayloadLimitExceeded(maximumBytes: Int)
    case invalidPayloadKind
    case invalidImageTypeIdentifier
    case invalidImageDimensions
    case invalidDigest
    case invalidSourceIdentifier
    case invalidTimestamp
    case pinnedEntriesPreventEviction
    case entryNotFound
    case selectionLimitExceeded(maximumCount: Int)
    case duplicateSelection
    case comparisonSelectionRequired
    case mixedPayloadKinds
    case payloadUnavailable
    case staleComparisonRequest
    case revisionSpaceExhausted
    case workLimitExceeded(maximumWork: Int)
    case persistenceDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case malformedPersistence
    case unknownPersistenceKey
    case duplicatePersistenceKey
    case duplicateEntry
    case nonCanonicalPersistence
    case secureSnapshotPolicyRequired
    case decodedLimitsExceedCallerLimits

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Clipboard history limits are invalid."
        case .emptyPayload:
            "Clipboard history cannot retain an empty payload."
        case .payloadTooLarge(let maximumBytes):
            "Clipboard payload exceeds the \(maximumBytes)-byte limit."
        case .retainedPayloadLimitExceeded(let maximumBytes):
            "Clipboard history exceeds the \(maximumBytes)-byte retained-payload limit."
        case .invalidPayloadKind:
            "Clipboard payload storage does not match its declared kind."
        case .invalidImageTypeIdentifier:
            "Clipboard image type identifier is invalid."
        case .invalidImageDimensions:
            "Clipboard image dimensions are invalid or exceed supported bounds."
        case .invalidDigest:
            "Clipboard payload digest is not canonical SHA-256."
        case .invalidSourceIdentifier:
            "Clipboard source identifier is invalid."
        case .invalidTimestamp:
            "Clipboard timestamp must be finite."
        case .pinnedEntriesPreventEviction:
            "Pinned clipboard entries prevent bounded retention of the new payload."
        case .entryNotFound:
            "Clipboard history entry was not found."
        case .selectionLimitExceeded(let maximumCount):
            "Clipboard selection exceeds the \(maximumCount)-entry limit."
        case .duplicateSelection:
            "Clipboard selection contains a duplicate entry."
        case .comparisonSelectionRequired:
            "Clipboard comparison requires exactly two selected entries."
        case .mixedPayloadKinds:
            "Clipboard comparison requires two text payloads or two image payloads."
        case .payloadUnavailable:
            "Raw clipboard payload is unavailable from metadata-only history."
        case .staleComparisonRequest:
            "Clipboard comparison request is stale."
        case .revisionSpaceExhausted:
            "Clipboard history revision space is exhausted."
        case .workLimitExceeded(let maximumWork):
            "Clipboard history operation exceeds the \(maximumWork)-unit work limit."
        case .persistenceDataTooLarge(let maximumBytes):
            "Clipboard history persistence exceeds the \(maximumBytes)-byte limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported clipboard history schema version: \(version)."
        case .malformedPersistence:
            "Clipboard history persistence is malformed."
        case .unknownPersistenceKey:
            "Clipboard history persistence contains an unknown key."
        case .duplicatePersistenceKey:
            "Clipboard history persistence contains a duplicate key."
        case .duplicateEntry:
            "Clipboard history persistence contains a duplicate entry."
        case .nonCanonicalPersistence:
            "Clipboard history persistence is not in canonical form."
        case .secureSnapshotPolicyRequired:
            "Reading raw clipboard payloads requires explicit secure-snapshot permission."
        case .decodedLimitsExceedCallerLimits:
            "Clipboard history persistence limits exceed caller-supplied decode limits."
        }
    }
}

private struct ClipboardHistoryWorkBudget {
    let maximumWork: Int
    private var completedWork = 0
    private var nextCancellationCheck = 0

    init(maximumWork: Int) {
        self.maximumWork = maximumWork
    }

    mutating func charge(_ amount: Int) throws {
        try ensureCanCharge(amount)
        completedWork += amount
        if completedWork >= nextCancellationCheck {
            try Task.checkCancellation()
            nextCancellationCheck = completedWork + 4 * 1_024
        }
    }

    func ensureCanCharge(_ amount: Int) throws {
        guard amount >= 0, completedWork <= maximumWork,
            amount <= maximumWork - completedWork
        else {
            throw ClipboardHistoryError.workLimitExceeded(maximumWork: maximumWork)
        }
    }
}

private struct ClipboardHistoryCanonicalWriter {
    private let maximumBytes: Int
    private let comparisonBytes: UnsafeBufferPointer<UInt8>?
    private var data = Data()
    private var outputCount = 0
    private var comparisonMatches = true

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        comparisonBytes = nil
        data.reserveCapacity(Swift.min(maximumBytes, 16 * 1_024))
    }

    init(maximumBytes: Int, comparingWith bytes: UnsafeBufferPointer<UInt8>) {
        self.maximumBytes = maximumBytes
        comparisonBytes = bytes
    }

    mutating func encode(
        _ history: ClipboardHistory,
        policy: ClipboardHistory.PersistencePolicy,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Data {
        try write(history, policy: policy, budget: &budget)
        return data
    }

    mutating func matches(
        _ history: ClipboardHistory,
        policy: ClipboardHistory.PersistencePolicy,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> Bool {
        try write(history, policy: policy, budget: &budget)
        return comparisonMatches && outputCount == comparisonBytes?.count
    }

    private mutating func write(
        _ history: ClipboardHistory,
        policy: ClipboardHistory.PersistencePolicy,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        try append("{\"entries\":[", budget: &budget)
        for (index, entry) in history.entries.enumerated() {
            if index > 0 { try append(",", budget: &budget) }
            try encode(entry, policy: policy, budget: &budget)
        }
        try append("],\"limits\":{", budget: &budget)
        try append(
            "\"maximumEntries\":\(history.limits.maximumEntries),"
                + "\"maximumPayloadBytes\":\(history.limits.maximumPayloadBytes),"
                + "\"maximumPersistenceBytes\":\(history.limits.maximumPersistenceBytes),"
                + "\"maximumRetainedPayloadBytes\":\(history.limits.maximumRetainedPayloadBytes),"
                + "\"maximumSourceIdentifierBytes\":\(history.limits.maximumSourceIdentifierBytes),"
                + "\"maximumTypeIdentifierBytes\":\(history.limits.maximumTypeIdentifierBytes),"
                + "\"maximumWork\":\(history.limits.maximumWork)},",
            budget: &budget
        )
        try append("\"persistencePolicy\":", budget: &budget)
        try appendJSONString(policy.rawValue, budget: &budget)
        try append(",\"revision\":\(history.revision)", budget: &budget)
        try append(",\"schemaVersion\":\(ClipboardHistory.currentSchemaVersion)", budget: &budget)
        try append(",\"selection\":[", budget: &budget)
        for (index, id) in history.selectedIDs.enumerated() {
            if index > 0 { try append(",", budget: &budget) }
            try appendJSONString(id.rawValue, budget: &budget)
        }
        try append("]}", budget: &budget)
        try Task.checkCancellation()
    }

    private mutating func encode(
        _ entry: ClipboardHistory.Entry,
        policy: ClipboardHistory.PersistencePolicy,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        try append("{\"byteCount\":\(entry.byteCount),\"id\":", budget: &budget)
        try appendJSONString(entry.id.rawValue, budget: &budget)
        try append(",\"kind\":", budget: &budget)
        try appendJSONString(entry.kind.rawValue, budget: &budget)
        if policy == .secureSnapshot {
            guard let payload = entry.payload else {
                throw ClipboardHistoryError.payloadUnavailable
            }
            try append(",\"payload\":", budget: &budget)
            switch payload.storage {
            case .text(let text):
                try appendJSONString(text, budget: &budget)
            case .image(let imageData):
                try appendBase64JSONString(imageData, budget: &budget)
            }
        }
        if entry.kind == .image {
            guard let metadata = entry.imageMetadata else {
                throw ClipboardHistoryError.invalidPayloadKind
            }
            try append(",\"pixelHeight\":", budget: &budget)
            try appendOptionalInteger(metadata.pixelHeight, budget: &budget)
            try append(",\"pixelWidth\":", budget: &budget)
            try appendOptionalInteger(metadata.pixelWidth, budget: &budget)
        }
        try append(",\"pinned\":\(entry.isPinned ? "true" : "false")", budget: &budget)
        try append(",\"recency\":\(entry.recency)", budget: &budget)
        try append(",\"sourceIdentifier\":", budget: &budget)
        try appendJSONString(entry.sourceIdentifier, budget: &budget)
        try append(",\"timestamp\":", budget: &budget)
        try appendJSONString(Self.timestampString(entry.timestamp), budget: &budget)
        if entry.kind == .image {
            try append(",\"typeIdentifier\":", budget: &budget)
            try appendJSONString(entry.imageMetadata!.typeIdentifier, budget: &budget)
        }
        try append("}", budget: &budget)
    }

    private mutating func appendOptionalInteger(
        _ value: Int?,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        if let value {
            try append(String(value), budget: &budget)
        } else {
            try append("null", budget: &budget)
        }
    }

    private mutating func appendJSONString(
        _ value: String,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        try appendByte(0x22, budget: &budget)
        var unescaped: [UInt8] = []
        unescaped.reserveCapacity(4 * 1_024)

        func flushUnescaped() throws {
            guard !unescaped.isEmpty else { return }
            try appendBytes(unescaped, budget: &budget)
            unescaped.removeAll(keepingCapacity: true)
        }

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08:
                try flushUnescaped()
                try append("\\b", budget: &budget)
            case 0x09:
                try flushUnescaped()
                try append("\\t", budget: &budget)
            case 0x0A:
                try flushUnescaped()
                try append("\\n", budget: &budget)
            case 0x0C:
                try flushUnescaped()
                try append("\\f", budget: &budget)
            case 0x0D:
                try flushUnescaped()
                try append("\\r", budget: &budget)
            case 0x22:
                try flushUnescaped()
                try append("\\\"", budget: &budget)
            case 0x5C:
                try flushUnescaped()
                try append("\\\\", budget: &budget)
            case 0x00...0x1F:
                try flushUnescaped()
                let hex = String(scalar.value, radix: 16, uppercase: false)
                try append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex, budget: &budget)
            default:
                unescaped.append(contentsOf: String(scalar).utf8)
                if unescaped.count >= 4 * 1_024 { try flushUnescaped() }
            }
        }
        try flushUnescaped()
        try appendByte(0x22, budget: &budget)
    }

    private mutating func appendBase64JSONString(
        _ value: Data,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        try appendByte(0x22, budget: &budget)
        try value.withUnsafeBytes { bytes in
            var output: [UInt8] = []
            output.reserveCapacity(16 * 1_024)
            var index = 0
            while index + 2 < bytes.count {
                let first = bytes[index]
                let second = bytes[index + 1]
                let third = bytes[index + 2]
                output.append(alphabet[Int(first >> 2)])
                output.append(alphabet[Int(((first & 0x03) << 4) | (second >> 4))])
                output.append(alphabet[Int(((second & 0x0F) << 2) | (third >> 6))])
                output.append(alphabet[Int(third & 0x3F)])
                index += 3
                if output.count >= 16 * 1_024 {
                    try appendBytes(output, budget: &budget)
                    output.removeAll(keepingCapacity: true)
                }
            }
            if index < bytes.count {
                let first = bytes[index]
                output.append(alphabet[Int(first >> 2)])
                if index + 1 < bytes.count {
                    let second = bytes[index + 1]
                    output.append(alphabet[Int(((first & 0x03) << 4) | (second >> 4))])
                    output.append(alphabet[Int((second & 0x0F) << 2)])
                    output.append(0x3D)
                } else {
                    output.append(alphabet[Int((first & 0x03) << 4)])
                    output.append(0x3D)
                    output.append(0x3D)
                }
            }
            if !output.isEmpty { try appendBytes(output, budget: &budget) }
        }
        try appendByte(0x22, budget: &budget)
    }

    private mutating func append(
        _ value: String,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        try appendBytes(value.utf8, budget: &budget)
    }

    private mutating func appendByte(
        _ byte: UInt8,
        budget: inout ClipboardHistoryWorkBudget
    ) throws {
        guard outputCount < maximumBytes else {
            throw ClipboardHistoryError.persistenceDataTooLarge(maximumBytes: maximumBytes)
        }
        try budget.charge(comparisonBytes == nil ? 1 : 2)
        if let comparisonBytes {
            if outputCount >= comparisonBytes.count || comparisonBytes[outputCount] != byte {
                comparisonMatches = false
            }
        } else {
            data.append(byte)
        }
        outputCount += 1
    }

    private mutating func appendBytes<Bytes>(
        _ bytes: Bytes,
        budget: inout ClipboardHistoryWorkBudget
    ) throws where Bytes: Collection, Bytes.Element == UInt8 {
        let count = bytes.count
        guard count <= maximumBytes, outputCount <= maximumBytes - count else {
            throw ClipboardHistoryError.persistenceDataTooLarge(maximumBytes: maximumBytes)
        }
        try budget.charge(comparisonBytes == nil ? count : count * 2)
        if let comparisonBytes {
            if outputCount <= comparisonBytes.count,
                count <= comparisonBytes.count - outputCount
            {
                if comparisonMatches,
                    !comparisonBytes[outputCount..<(outputCount + count)].elementsEqual(bytes)
                {
                    comparisonMatches = false
                }
            } else {
                comparisonMatches = false
            }
            outputCount += count
        } else {
            data.append(contentsOf: bytes)
            outputCount += count
        }
    }

    fileprivate static func timestampString(_ date: Date) -> String {
        let value =
            date.timeIntervalSinceReferenceDate == 0
            ? UInt64(0)
            : date.timeIntervalSinceReferenceDate.bitPattern
        let hex = String(value, radix: 16, uppercase: false)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    fileprivate static func timestamp(from value: String) throws -> Date {
        guard value.utf8.count == 16,
            value.utf8.allSatisfy({
                (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
            }),
            let bits = UInt64(value, radix: 16)
        else {
            throw ClipboardHistoryError.invalidTimestamp
        }
        let interval = Double(bitPattern: bits)
        guard interval.isFinite, !(interval == 0 && bits != 0) else {
            throw ClipboardHistoryError.invalidTimestamp
        }
        return Date(timeIntervalSinceReferenceDate: interval)
    }
}

private struct ClipboardHistoryWireHistory: Decodable {
    let entries: [ClipboardHistoryWireEntry]
    let limits: ClipboardHistoryWireLimits
    let persistencePolicy: ClipboardHistory.PersistencePolicy
    let revision: UInt64
    let schemaVersion: Int
    let selection: [ClipboardHistoryWireID]

    init(
        entries: [ClipboardHistoryWireEntry],
        limits: ClipboardHistoryWireLimits,
        persistencePolicy: ClipboardHistory.PersistencePolicy,
        revision: UInt64,
        schemaVersion: Int,
        selection: [ClipboardHistoryWireID]
    ) {
        self.entries = entries
        self.limits = limits
        self.persistencePolicy = persistencePolicy
        self.revision = revision
        self.schemaVersion = schemaVersion
        self.selection = selection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ClipboardHistoryCodingKey.self)
        try clipboardRequireExactKeys(
            container,
            expected: [
                "entries", "limits", "persistencePolicy", "revision", "schemaVersion",
                "selection"
            ]
        )
        limits = try container.decode(ClipboardHistoryWireLimits.self, forKey: .init("limits"))
        let validatedLimits = try ClipboardHistory.Limits(validating: limits)
        persistencePolicy = try container.decode(
            ClipboardHistory.PersistencePolicy.self,
            forKey: .init("persistencePolicy")
        )
        revision = try container.decode(UInt64.self, forKey: .init("revision"))
        schemaVersion = try container.decode(Int.self, forKey: .init("schemaVersion"))

        var entriesContainer = try container.nestedUnkeyedContainer(forKey: .init("entries"))
        if let count = entriesContainer.count, count > validatedLimits.maximumEntries {
            throw ClipboardHistoryError.nonCanonicalPersistence
        }
        var entries: [ClipboardHistoryWireEntry] = []
        entries.reserveCapacity(entriesContainer.count ?? 0)
        while !entriesContainer.isAtEnd {
            guard entries.count < validatedLimits.maximumEntries else {
                throw ClipboardHistoryError.nonCanonicalPersistence
            }
            entries.append(try entriesContainer.decode(ClipboardHistoryWireEntry.self))
        }
        self.entries = entries

        var selectionContainer = try container.nestedUnkeyedContainer(forKey: .init("selection"))
        if let count = selectionContainer.count,
            count > ClipboardHistory.maximumSelectionCount
        {
            throw ClipboardHistoryError.selectionLimitExceeded(
                maximumCount: ClipboardHistory.maximumSelectionCount
            )
        }
        var selection: [ClipboardHistoryWireID] = []
        while !selectionContainer.isAtEnd {
            guard selection.count < ClipboardHistory.maximumSelectionCount else {
                throw ClipboardHistoryError.selectionLimitExceeded(
                    maximumCount: ClipboardHistory.maximumSelectionCount
                )
            }
            selection.append(try selectionContainer.decode(ClipboardHistoryWireID.self))
        }
        self.selection = selection
    }
}

private struct ClipboardHistoryWireLimits: Decodable {
    let maximumEntries: Int
    let maximumPayloadBytes: Int
    let maximumRetainedPayloadBytes: Int
    let maximumSourceIdentifierBytes: Int
    let maximumTypeIdentifierBytes: Int
    let maximumWork: Int
    let maximumPersistenceBytes: Int

    init(
        maximumEntries: Int,
        maximumPayloadBytes: Int,
        maximumRetainedPayloadBytes: Int,
        maximumSourceIdentifierBytes: Int,
        maximumTypeIdentifierBytes: Int,
        maximumWork: Int,
        maximumPersistenceBytes: Int
    ) {
        self.maximumEntries = maximumEntries
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumRetainedPayloadBytes = maximumRetainedPayloadBytes
        self.maximumSourceIdentifierBytes = maximumSourceIdentifierBytes
        self.maximumTypeIdentifierBytes = maximumTypeIdentifierBytes
        self.maximumWork = maximumWork
        self.maximumPersistenceBytes = maximumPersistenceBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ClipboardHistoryCodingKey.self)
        try clipboardRequireExactKeys(
            container,
            expected: [
                "maximumEntries", "maximumPayloadBytes", "maximumPersistenceBytes",
                "maximumRetainedPayloadBytes", "maximumSourceIdentifierBytes",
                "maximumTypeIdentifierBytes", "maximumWork"
            ]
        )
        maximumEntries = try container.decode(Int.self, forKey: .init("maximumEntries"))
        maximumPayloadBytes = try container.decode(
            Int.self,
            forKey: .init("maximumPayloadBytes")
        )
        maximumRetainedPayloadBytes = try container.decode(
            Int.self,
            forKey: .init("maximumRetainedPayloadBytes")
        )
        maximumSourceIdentifierBytes = try container.decode(
            Int.self,
            forKey: .init("maximumSourceIdentifierBytes")
        )
        maximumTypeIdentifierBytes = try container.decode(
            Int.self,
            forKey: .init("maximumTypeIdentifierBytes")
        )
        maximumWork = try container.decode(Int.self, forKey: .init("maximumWork"))
        maximumPersistenceBytes = try container.decode(
            Int.self,
            forKey: .init("maximumPersistenceBytes")
        )
    }
}

private struct ClipboardHistoryWireEntry: Decodable {
    let byteCount: Int
    let id: String
    let kind: ClipboardHistoryPayload.Kind
    let pixelHeight: Int?
    let pixelWidth: Int?
    let pinned: Bool
    let recency: UInt64
    let payload: String?
    let imagePayload: Data?
    let sourceIdentifier: String
    let timestamp: String
    let typeIdentifier: String?
    let hasPayload: Bool

    init(
        byteCount: Int,
        id: String,
        kind: ClipboardHistoryPayload.Kind,
        pixelHeight: Int?,
        pixelWidth: Int?,
        pinned: Bool,
        recency: UInt64,
        payload: String?,
        imagePayload: Data?,
        sourceIdentifier: String,
        timestamp: String,
        typeIdentifier: String?,
        hasPayload: Bool
    ) {
        self.byteCount = byteCount
        self.id = id
        self.kind = kind
        self.pixelHeight = pixelHeight
        self.pixelWidth = pixelWidth
        self.pinned = pinned
        self.recency = recency
        self.payload = payload
        self.imagePayload = imagePayload
        self.sourceIdentifier = sourceIdentifier
        self.timestamp = timestamp
        self.typeIdentifier = typeIdentifier
        self.hasPayload = hasPayload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ClipboardHistoryCodingKey.self)
        kind = try container.decode(
            ClipboardHistoryPayload.Kind.self,
            forKey: .init("kind")
        )
        hasPayload = container.contains(.init("payload"))
        var expected: Set<String> = [
            "byteCount", "id", "kind", "pinned", "recency", "sourceIdentifier", "timestamp"
        ]
        if kind == .image {
            expected.formUnion(["pixelHeight", "pixelWidth", "typeIdentifier"])
        }
        if hasPayload { expected.insert("payload") }
        try clipboardRequireExactKeys(container, expected: expected)

        byteCount = try container.decode(Int.self, forKey: .init("byteCount"))
        id = try container.decode(String.self, forKey: .init("id"))
        pinned = try container.decode(Bool.self, forKey: .init("pinned"))
        recency = try container.decode(UInt64.self, forKey: .init("recency"))
        payload =
            hasPayload
            ? try container.decode(String.self, forKey: .init("payload"))
            : nil
        imagePayload = nil
        sourceIdentifier = try container.decode(
            String.self,
            forKey: .init("sourceIdentifier")
        )
        timestamp = try container.decode(String.self, forKey: .init("timestamp"))
        if kind == .image {
            pixelHeight = try container.decodeIfPresent(Int.self, forKey: .init("pixelHeight"))
            pixelWidth = try container.decodeIfPresent(Int.self, forKey: .init("pixelWidth"))
            typeIdentifier = try container.decode(String.self, forKey: .init("typeIdentifier"))
        } else {
            pixelHeight = nil
            pixelWidth = nil
            typeIdentifier = nil
        }
    }

    func entry(
        policy: ClipboardHistory.PersistencePolicy,
        limits: ClipboardHistory.Limits,
        budget: inout ClipboardHistoryWorkBudget
    ) throws -> ClipboardHistory.Entry {
        guard hasPayload == (policy == .secureSnapshot) else {
            throw ClipboardHistoryError.nonCanonicalPersistence
        }
        guard byteCount > 0, byteCount <= limits.maximumPayloadBytes else {
            throw ClipboardHistoryError.payloadTooLarge(
                maximumBytes: limits.maximumPayloadBytes
            )
        }
        guard let id = ClipboardHistoryEntryID(rawValue: id) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        try ClipboardHistory.validateSourceIdentifier(
            sourceIdentifier,
            maximumBytes: limits.maximumSourceIdentifierBytes,
            budget: &budget
        )
        let timestamp = try ClipboardHistoryCanonicalWriter.timestamp(from: timestamp)
        let metadata: ClipboardHistoryImageMetadata?
        if kind == .image {
            guard let typeIdentifier else {
                throw ClipboardHistoryError.invalidImageTypeIdentifier
            }
            try ClipboardHistoryPayload.validateTypeIdentifier(
                typeIdentifier,
                maximumBytes: limits.maximumTypeIdentifierBytes
            )
            try ClipboardHistoryPayload.validateDimensions(
                width: pixelWidth,
                height: pixelHeight
            )
            metadata = ClipboardHistoryImageMetadata(
                typeIdentifier: typeIdentifier,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        } else {
            metadata = nil
        }

        let decodedPayload: ClipboardHistoryPayload?
        if let payload {
            switch kind {
            case .text:
                decodedPayload = try ClipboardHistoryPayload(
                    text: payload,
                    maximumBytes: limits.maximumPayloadBytes,
                    budget: &budget
                )
            case .image:
                guard let imagePayload else {
                    throw ClipboardHistoryError.malformedPersistence
                }
                decodedPayload = try ClipboardHistoryPayload(
                    imageData: imagePayload,
                    typeIdentifier: typeIdentifier!,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    maximumBytes: limits.maximumPayloadBytes,
                    budget: &budget,
                    copyImageData: false
                )
            }
            guard decodedPayload?.byteCount == byteCount,
                decodedPayload?.imageMetadata == metadata
            else {
                throw ClipboardHistoryError.nonCanonicalPersistence
            }
        } else {
            guard imagePayload == nil else {
                throw ClipboardHistoryError.nonCanonicalPersistence
            }
            decodedPayload = nil
        }
        return ClipboardHistory.Entry(
            payload: decodedPayload,
            id: id,
            kind: kind,
            byteCount: byteCount,
            imageMetadata: metadata,
            sourceIdentifier: sourceIdentifier,
            timestamp: timestamp,
            isPinned: pinned,
            recency: recency
        )
    }
}

private struct ClipboardHistoryWireID: Decodable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func id() throws -> ClipboardHistoryEntryID {
        guard let id = ClipboardHistoryEntryID(rawValue: rawValue) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        return id
    }
}

private struct ClipboardHistoryCodingKey: CodingKey, Hashable {
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

private func clipboardRequireExactKeys<Value>(
    _ container: KeyedDecodingContainer<Value>,
    expected: Set<String>
) throws where Value: CodingKey {
    let actual = Set(container.allKeys.map(\.stringValue))
    guard actual.subtracting(expected).isEmpty else {
        throw ClipboardHistoryError.unknownPersistenceKey
    }
    guard actual == expected else { throw ClipboardHistoryError.malformedPersistence }
}

private struct ClipboardHistoryCanonicalParser {
    private let bytes: UnsafeBufferPointer<UInt8>
    private let limits: ClipboardHistory.Limits
    private var index = 0
    private var retainedPayloadBytes = 0
    var budget: ClipboardHistoryWorkBudget

    init(
        bytes: UnsafeBufferPointer<UInt8>,
        budget: ClipboardHistoryWorkBudget,
        limits: ClipboardHistory.Limits
    ) {
        self.bytes = bytes
        self.budget = budget
        self.limits = limits
    }

    mutating func parse() throws -> ClipboardHistoryWireHistory {
        try consume("{\"entries\":[")
        var entries: [ClipboardHistoryWireEntry] = []
        entries.reserveCapacity(Swift.min(ClipboardHistory.maximumSupportedEntries, 64))
        if !hasPrefix("]") {
            while true {
                guard entries.count < limits.maximumEntries else {
                    throw ClipboardHistoryError.malformedPersistence
                }
                entries.append(try parseEntry())
                if try consumeIfPresent("]") { break }
                try consume(",")
            }
        } else {
            try consume("]")
        }
        try consume(",\"limits\":{")
        let limits = try parseLimits()
        try consume(",\"persistencePolicy\":")
        let rawPolicy = try parseString(maximumBytes: 32)
        guard let policy = ClipboardHistory.PersistencePolicy(rawValue: rawPolicy) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        try consume(",\"revision\":")
        let revision = try parseUInt64()
        try consume(",\"schemaVersion\":")
        let schemaVersion = try parseInt()
        try consume(",\"selection\":[")
        var selection: [ClipboardHistoryWireID] = []
        if !hasPrefix("]") {
            while true {
                guard selection.count < ClipboardHistory.maximumSelectionCount else {
                    throw ClipboardHistoryError.selectionLimitExceeded(
                        maximumCount: ClipboardHistory.maximumSelectionCount
                    )
                }
                selection.append(try parseID())
                if try consumeIfPresent("]") { break }
                try consume(",")
            }
        } else {
            try consume("]")
        }
        try consume("}")
        guard index == bytes.count else { throw ClipboardHistoryError.malformedPersistence }
        return ClipboardHistoryWireHistory(
            entries: entries,
            limits: limits,
            persistencePolicy: policy,
            revision: revision,
            schemaVersion: schemaVersion,
            selection: selection
        )
    }

    private mutating func parseEntry() throws -> ClipboardHistoryWireEntry {
        try consume("{\"byteCount\":")
        let byteCount = try parseInt()
        guard byteCount > 0, byteCount <= limits.maximumPayloadBytes else {
            throw ClipboardHistoryError.payloadTooLarge(
                maximumBytes: limits.maximumPayloadBytes
            )
        }
        try consume(",\"id\":")
        let id = try parseString(maximumBytes: 36)
        try consume(",\"kind\":")
        let rawKind = try parseString(maximumBytes: 16)
        guard let kind = ClipboardHistoryPayload.Kind(rawValue: rawKind) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        let payload: String?
        let imagePayload: Data?
        if try consumeIfPresent(",\"payload\":") {
            switch kind {
            case .text:
                let maximumRemainingBytes =
                    limits.maximumRetainedPayloadBytes
                    - retainedPayloadBytes
                payload = try parseString(
                    maximumBytes: Swift.min(limits.maximumPayloadBytes, maximumRemainingBytes)
                )
                imagePayload = nil
                retainedPayloadBytes = try ClipboardHistory.addingPayloadBytes(
                    retainedPayloadBytes,
                    payload!.utf8.count
                )
            case .image:
                let maximumRemainingBytes =
                    limits.maximumRetainedPayloadBytes
                    - retainedPayloadBytes
                guard byteCount <= maximumRemainingBytes else {
                    throw ClipboardHistoryError.retainedPayloadLimitExceeded(
                        maximumBytes: limits.maximumRetainedPayloadBytes
                    )
                }
                retainedPayloadBytes = try ClipboardHistory.addingPayloadBytes(
                    retainedPayloadBytes,
                    byteCount
                )
                payload = ""
                imagePayload = try parseBase64Data(
                    maximumOutputBytes: byteCount
                )
                guard imagePayload!.count == byteCount else {
                    throw ClipboardHistoryError.nonCanonicalPersistence
                }
            }
            guard retainedPayloadBytes <= limits.maximumRetainedPayloadBytes else {
                throw ClipboardHistoryError.retainedPayloadLimitExceeded(
                    maximumBytes: limits.maximumRetainedPayloadBytes
                )
            }
        } else {
            payload = nil
            imagePayload = nil
        }
        let pixelHeight: Int?
        let pixelWidth: Int?
        if kind == .image {
            try consume(",\"pixelHeight\":")
            pixelHeight = try parseOptionalInt()
            try consume(",\"pixelWidth\":")
            pixelWidth = try parseOptionalInt()
        } else {
            pixelHeight = nil
            pixelWidth = nil
        }
        try consume(",\"pinned\":")
        let pinned = try parseBoolean()
        try consume(",\"recency\":")
        let recency = try parseUInt64()
        try consume(",\"sourceIdentifier\":")
        let sourceIdentifier = try parseString(
            maximumBytes: limits.maximumSourceIdentifierBytes
        )
        try consume(",\"timestamp\":")
        let timestamp = try parseString(maximumBytes: 16)
        let typeIdentifier: String?
        if kind == .image {
            try consume(",\"typeIdentifier\":")
            typeIdentifier = try parseString(
                maximumBytes: limits.maximumTypeIdentifierBytes
            )
        } else {
            typeIdentifier = nil
        }
        try consume("}")
        return ClipboardHistoryWireEntry(
            byteCount: byteCount,
            id: id,
            kind: kind,
            pixelHeight: pixelHeight,
            pixelWidth: pixelWidth,
            pinned: pinned,
            recency: recency,
            payload: payload,
            imagePayload: imagePayload,
            sourceIdentifier: sourceIdentifier,
            timestamp: timestamp,
            typeIdentifier: typeIdentifier,
            hasPayload: payload != nil
        )
    }

    private mutating func parseLimits() throws -> ClipboardHistoryWireLimits {
        try consume("\"maximumEntries\":")
        let maximumEntries = try parseInt()
        try consume(",\"maximumPayloadBytes\":")
        let maximumPayloadBytes = try parseInt()
        try consume(",\"maximumPersistenceBytes\":")
        let maximumPersistenceBytes = try parseInt()
        try consume(",\"maximumRetainedPayloadBytes\":")
        let maximumRetainedPayloadBytes = try parseInt()
        try consume(",\"maximumSourceIdentifierBytes\":")
        let maximumSourceIdentifierBytes = try parseInt()
        try consume(",\"maximumTypeIdentifierBytes\":")
        let maximumTypeIdentifierBytes = try parseInt()
        try consume(",\"maximumWork\":")
        let maximumWork = try parseInt()
        try consume("}")
        return ClipboardHistoryWireLimits(
            maximumEntries: maximumEntries,
            maximumPayloadBytes: maximumPayloadBytes,
            maximumRetainedPayloadBytes: maximumRetainedPayloadBytes,
            maximumSourceIdentifierBytes: maximumSourceIdentifierBytes,
            maximumTypeIdentifierBytes: maximumTypeIdentifierBytes,
            maximumWork: maximumWork,
            maximumPersistenceBytes: maximumPersistenceBytes
        )
    }

    private mutating func parseID() throws -> ClipboardHistoryWireID {
        ClipboardHistoryWireID(rawValue: try parseString(maximumBytes: 36))
    }

    private mutating func parseString(maximumBytes: Int) throws -> String {
        try consumeByte(0x22)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(Swift.min(bytes.count - index, 4 * 1_024))
        while let byte = currentByte {
            switch byte {
            case 0x22:
                try advance()
                guard let value = String(bytes: decoded, encoding: .utf8) else {
                    throw ClipboardHistoryError.malformedPersistence
                }
                return value
            case 0x00...0x1F:
                throw ClipboardHistoryError.malformedPersistence
            case 0x5C:
                try advance()
                try parseEscape(into: &decoded)
            case 0x20...0x7F:
                decoded.append(byte)
                try advance()
            default:
                try appendRawUTF8Scalar(into: &decoded)
            }
            guard decoded.count <= maximumBytes else {
                throw ClipboardHistoryError.malformedPersistence
            }
        }
        throw ClipboardHistoryError.malformedPersistence
    }

    private mutating func parseBase64Data(maximumOutputBytes: Int) throws -> Data {
        try consumeByte(0x22)
        var output = Data()
        var quartet: [UInt8] = []
        quartet.reserveCapacity(4)
        var completed = false
        while let byte = currentByte, byte != 0x22 {
            guard !completed,
                ClipboardHistoryBase64.isAlphabet(byte) || byte == 0x3D
            else {
                throw ClipboardHistoryError.malformedPersistence
            }
            quartet.append(byte)
            try advance()
            if quartet.count == 4 {
                completed = try ClipboardHistoryBase64.decodeQuartet(
                    quartet,
                    into: &output,
                    maximumOutputBytes: maximumOutputBytes
                )
                quartet.removeAll(keepingCapacity: true)
            }
        }
        guard quartet.isEmpty else { throw ClipboardHistoryError.malformedPersistence }
        try consumeByte(0x22)
        return output
    }

    private mutating func parseEscape(into decoded: inout [UInt8]) throws {
        guard let escaped = currentByte else {
            throw ClipboardHistoryError.malformedPersistence
        }
        try advance()
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            decoded.append(escaped)
        case 0x62:
            decoded.append(0x08)
        case 0x66:
            decoded.append(0x0C)
        case 0x6E:
            decoded.append(0x0A)
        case 0x72:
            decoded.append(0x0D)
        case 0x74:
            decoded.append(0x09)
        case 0x75:
            let first = try parseHexQuad()
            let scalar: UInt32
            if (0xD800...0xDBFF).contains(first) {
                try consume("\\u")
                let second = try parseHexQuad()
                guard (0xDC00...0xDFFF).contains(second) else {
                    throw ClipboardHistoryError.malformedPersistence
                }
                scalar =
                    0x10000
                    + (UInt32(first - 0xD800) << 10)
                    + UInt32(second - 0xDC00)
            } else {
                guard !(0xDC00...0xDFFF).contains(first) else {
                    throw ClipboardHistoryError.malformedPersistence
                }
                scalar = UInt32(first)
            }
            guard let unicodeScalar = Unicode.Scalar(scalar) else {
                throw ClipboardHistoryError.malformedPersistence
            }
            decoded.append(contentsOf: String(unicodeScalar).utf8)
        default:
            throw ClipboardHistoryError.malformedPersistence
        }
    }

    private mutating func appendRawUTF8Scalar(into decoded: inout [UInt8]) throws {
        guard let first = currentByte else {
            throw ClipboardHistoryError.malformedPersistence
        }
        let length: Int
        switch first {
        case 0xC2...0xDF: length = 2
        case 0xE0...0xEF: length = 3
        case 0xF0...0xF4: length = 4
        default: throw ClipboardHistoryError.malformedPersistence
        }
        guard index <= bytes.count - length else {
            throw ClipboardHistoryError.malformedPersistence
        }
        let scalarBytes = bytes[index..<(index + length)]
        guard Self.isValidUTF8Scalar(scalarBytes) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        decoded.append(contentsOf: scalarBytes)
        for _ in 0..<length { try advance() }
    }

    private static func isValidUTF8Scalar(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        guard let first = bytes.first else { return false }
        let continuation: (UInt8) -> Bool = { (0x80...0xBF).contains($0) }
        switch first {
        case 0xC2...0xDF:
            return bytes.count == 2 && continuation(bytes[bytes.startIndex + 1])
        case 0xE0:
            return bytes.count == 3
                && (0xA0...0xBF).contains(bytes[bytes.startIndex + 1])
                && continuation(bytes[bytes.startIndex + 2])
        case 0xE1...0xEC, 0xEE...0xEF:
            return bytes.count == 3
                && continuation(bytes[bytes.startIndex + 1])
                && continuation(bytes[bytes.startIndex + 2])
        case 0xED:
            return bytes.count == 3
                && (0x80...0x9F).contains(bytes[bytes.startIndex + 1])
                && continuation(bytes[bytes.startIndex + 2])
        case 0xF0:
            return bytes.count == 4
                && (0x90...0xBF).contains(bytes[bytes.startIndex + 1])
                && continuation(bytes[bytes.startIndex + 2])
                && continuation(bytes[bytes.startIndex + 3])
        case 0xF1...0xF3:
            return bytes.count == 4
                && continuation(bytes[bytes.startIndex + 1])
                && continuation(bytes[bytes.startIndex + 2])
                && continuation(bytes[bytes.startIndex + 3])
        case 0xF4:
            return bytes.count == 4
                && (0x80...0x8F).contains(bytes[bytes.startIndex + 1])
                && continuation(bytes[bytes.startIndex + 2])
                && continuation(bytes[bytes.startIndex + 3])
        default:
            return false
        }
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw ClipboardHistoryError.malformedPersistence
            }
            value = value * 16 + UInt16(digit)
            try advance()
        }
        return value
    }

    private mutating func parseInt() throws -> Int {
        let value = try parseCanonicalIntegerBytes()
        guard let result = Int(value) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        return result
    }

    private mutating func parseUInt64() throws -> UInt64 {
        let value = try parseCanonicalIntegerBytes()
        guard let result = UInt64(value) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        return result
    }

    private mutating func parseCanonicalIntegerBytes() throws -> String {
        let start = index
        if currentByte == 0x2D { try advance() }
        guard let first = currentByte else {
            throw ClipboardHistoryError.malformedPersistence
        }
        if first == 0x30 {
            try advance()
            guard currentByte.map({ !(0x30...0x39).contains($0) }) ?? true else {
                throw ClipboardHistoryError.malformedPersistence
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw ClipboardHistoryError.malformedPersistence
            }
            repeat {
                guard index - start < 32 else {
                    throw ClipboardHistoryError.malformedPersistence
                }
                try advance()
            } while currentByte.map({ (0x30...0x39).contains($0) }) == true
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func parseOptionalInt() throws -> Int? {
        if try consumeIfPresent("null") { return nil }
        return try parseInt()
    }

    private mutating func parseBoolean() throws -> Bool {
        if try consumeIfPresent("true") { return true }
        if try consumeIfPresent("false") { return false }
        throw ClipboardHistoryError.malformedPersistence
    }

    private mutating func consume(_ value: StaticString) throws {
        guard hasPrefix(value) else { throw ClipboardHistoryError.malformedPersistence }
        for _ in 0..<value.utf8CodeUnitCount { try advance() }
    }

    private mutating func consumeIfPresent(_ value: StaticString) throws -> Bool {
        guard hasPrefix(value) else { return false }
        for _ in 0..<value.utf8CodeUnitCount { try advance() }
        return true
    }

    private func hasPrefix(_ value: StaticString) -> Bool {
        value.withUTF8Buffer { expected in
            guard index <= bytes.count - expected.count else { return false }
            return bytes[index..<(index + expected.count)].elementsEqual(expected)
        }
    }

    private mutating func consumeByte(_ byte: UInt8) throws {
        guard currentByte == byte else { throw ClipboardHistoryError.malformedPersistence }
        try advance()
    }

    private mutating func advance() throws {
        guard index < bytes.count else { throw ClipboardHistoryError.malformedPersistence }
        index += 1
        try budget.charge(1)
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
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

private enum ClipboardHistoryBase64 {
    static func decodeQuartet(
        _ bytes: [UInt8],
        into output: inout Data,
        maximumOutputBytes: Int
    ) throws -> Bool {
        guard bytes.count == 4, let a = decoded(bytes[0]), let b = decoded(bytes[1]) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        try append((a << 2) | (b >> 4), to: &output, maximum: maximumOutputBytes)
        if bytes[2] == 0x3D {
            guard bytes[3] == 0x3D, b & 0x0F == 0 else {
                throw ClipboardHistoryError.malformedPersistence
            }
            return true
        }
        guard let c = decoded(bytes[2]) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        try append(
            ((b & 0x0F) << 4) | (c >> 2),
            to: &output,
            maximum: maximumOutputBytes
        )
        if bytes[3] == 0x3D {
            guard c & 0x03 == 0 else {
                throw ClipboardHistoryError.malformedPersistence
            }
            return true
        }
        guard let d = decoded(bytes[3]) else {
            throw ClipboardHistoryError.malformedPersistence
        }
        try append(
            ((c & 0x03) << 6) | d,
            to: &output,
            maximum: maximumOutputBytes
        )
        return false
    }

    static func isAlphabet(_ byte: UInt8) -> Bool { decoded(byte) != nil }

    private static func append(_ byte: UInt8, to data: inout Data, maximum: Int) throws {
        guard data.count < maximum else {
            throw ClipboardHistoryError.payloadTooLarge(maximumBytes: maximum)
        }
        data.append(byte)
    }

    private static func decoded(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x41...0x5A: byte - 0x41
        case 0x61...0x7A: byte - 0x61 + 26
        case 0x30...0x39: byte - 0x30 + 52
        case 0x2B: 62
        case 0x2F: 63
        default: nil
        }
    }
}

/// Syntax and duplicate-key preflight before Decodable allocations.
private struct ClipboardHistoryJSONScanner {
    struct Result {
        let schemaVersion: Int
        let persistencePolicy: ClipboardHistory.PersistencePolicy
        let limits: ClipboardHistoryWireLimits
    }

    private static let maximumDepth = 8
    private static let maximumObjectMembers = 32
    private static let maximumArrayElements = ClipboardHistory.maximumSupportedEntries + 16
    private static let maximumValues = ClipboardHistory.maximumSupportedEntries * 16 + 128
    private static let maximumKeyBytes = 64
    private static let maximumNumberBytes = 32
    private static let rootKeys: Set<String> = [
        "entries", "limits", "persistencePolicy", "revision", "schemaVersion", "selection"
    ]
    private static let entryKeys: Set<String> = [
        "byteCount", "id", "kind", "payload", "pixelHeight", "pixelWidth", "pinned",
        "recency", "sourceIdentifier", "timestamp", "typeIdentifier"
    ]
    private static let textEntryKeys = entryKeys.subtracting([
        "pixelHeight", "pixelWidth", "typeIdentifier"
    ])

    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0
    private var lastCancellationIndex = 0
    private var valueCount = 0
    private var persistencePolicy: ClipboardHistory.PersistencePolicy?
    private var maximumEntries: Int?
    private var maximumPayloadBytes: Int?
    private var maximumRetainedPayloadBytes: Int?
    private var maximumSourceIdentifierBytes: Int?
    private var maximumTypeIdentifierBytes: Int?
    private var maximumWork: Int?
    private var maximumPersistenceBytes: Int?
    private var containsPayloadKey = false

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func validate() throws -> Result {
        guard bytes.count <= ClipboardHistory.maximumSupportedWork else {
            throw ClipboardHistoryError.workLimitExceeded(
                maximumWork: ClipboardHistory.maximumSupportedWork
            )
        }
        try checkCancellation(force: true)
        try skipWhitespace()
        let version = try parseObject(depth: 1, capturesSchemaVersion: true)
        try skipWhitespace()
        guard index == bytes.count, let version, let persistencePolicy,
            let maximumEntries, let maximumPayloadBytes, let maximumRetainedPayloadBytes,
            let maximumSourceIdentifierBytes, let maximumTypeIdentifierBytes,
            let maximumWork, let maximumPersistenceBytes
        else {
            throw malformed()
        }
        guard persistencePolicy == .secureSnapshot || !containsPayloadKey else {
            throw ClipboardHistoryError.nonCanonicalPersistence
        }
        try checkCancellation(force: true)
        return Result(
            schemaVersion: version,
            persistencePolicy: persistencePolicy,
            limits: ClipboardHistoryWireLimits(
                maximumEntries: maximumEntries,
                maximumPayloadBytes: maximumPayloadBytes,
                maximumRetainedPayloadBytes: maximumRetainedPayloadBytes,
                maximumSourceIdentifierBytes: maximumSourceIdentifierBytes,
                maximumTypeIdentifierBytes: maximumTypeIdentifierBytes,
                maximumWork: maximumWork,
                maximumPersistenceBytes: maximumPersistenceBytes
            )
        )
    }

    private mutating func parseValue(depth: Int) throws {
        guard valueCount < Self.maximumValues else { throw malformed() }
        valueCount += 1
        try checkCancellation(force: false)
        guard let byte = currentByte else { throw malformed() }
        switch byte {
        case 0x7B:
            _ = try parseObject(depth: depth + 1, capturesSchemaVersion: false)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            try parseString()
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            _ = try parseInteger(allowsFraction: true)
        default:
            throw malformed()
        }
    }

    private mutating func parseObject(
        depth: Int,
        capturesSchemaVersion: Bool
    ) throws -> Int? {
        guard depth <= Self.maximumDepth else { throw malformed() }
        try consume(0x7B)
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return nil }
        var keys: Set<String> = []
        var memberCount = 0
        var schemaVersion: Int?
        var entryKind: ClipboardHistoryPayload.Kind?
        while true {
            guard memberCount < Self.maximumObjectMembers else { throw malformed() }
            memberCount += 1
            let key = try parseASCIIKey()
            guard keys.insert(key).inserted else {
                throw ClipboardHistoryError.duplicatePersistenceKey
            }
            let knownKeys = capturesSchemaVersion ? Self.rootKeys : Self.entryKeys
            guard knownKeys.contains(key) else {
                throw ClipboardHistoryError.unknownPersistenceKey
            }
            if key == "payload" { containsPayloadKey = true }
            try skipWhitespace()
            try consume(0x3A)
            try skipWhitespace()
            if capturesSchemaVersion, key == "schemaVersion" {
                guard schemaVersion == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                schemaVersion = try parseInteger(allowsFraction: false)
            } else if capturesSchemaVersion, key == "persistencePolicy" {
                guard persistencePolicy == nil,
                    let policy = ClipboardHistory.PersistencePolicy(
                        rawValue: try parseCanonicalASCIIString(maximumBytes: 32)
                    )
                else {
                    throw malformed()
                }
                persistencePolicy = policy
            } else if capturesSchemaVersion, key == "limits" {
                try parseLimitsObject(depth: depth + 1)
            } else if !capturesSchemaVersion, key == "kind" {
                entryKind = try parseEntryKind()
            } else {
                try parseValue(depth: depth)
            }
            try skipWhitespace()
            if consumeIfPresent(0x7D) {
                if entryKind == .text,
                    !keys.subtracting(Self.textEntryKeys).isEmpty
                {
                    throw ClipboardHistoryError.unknownPersistenceKey
                }
                return schemaVersion
            }
            try consume(0x2C)
            try skipWhitespace()
        }
    }

    private mutating func parseLimitsObject(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw malformed() }
        try consume(0x7B)
        try skipWhitespace()
        guard !consumeIfPresent(0x7D) else { throw malformed() }
        var keys: Set<String> = []
        var memberCount = 0
        while true {
            guard memberCount < Self.maximumObjectMembers else { throw malformed() }
            memberCount += 1
            let key = try parseASCIIKey()
            guard keys.insert(key).inserted else {
                throw ClipboardHistoryError.duplicatePersistenceKey
            }
            if key == "payload" { containsPayloadKey = true }
            try skipWhitespace()
            try consume(0x3A)
            try skipWhitespace()
            switch key {
            case "maximumEntries":
                guard maximumEntries == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                maximumEntries = try parseInteger(allowsFraction: false)
            case "maximumPayloadBytes":
                guard maximumPayloadBytes == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                maximumPayloadBytes = try parseInteger(allowsFraction: false)
            case "maximumRetainedPayloadBytes":
                guard maximumRetainedPayloadBytes == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                maximumRetainedPayloadBytes = try parseInteger(allowsFraction: false)
            case "maximumSourceIdentifierBytes":
                guard maximumSourceIdentifierBytes == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                maximumSourceIdentifierBytes = try parseInteger(allowsFraction: false)
            case "maximumTypeIdentifierBytes":
                guard maximumTypeIdentifierBytes == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                maximumTypeIdentifierBytes = try parseInteger(allowsFraction: false)
            case "maximumWork":
                guard maximumWork == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                maximumWork = try parseInteger(allowsFraction: false)
            case "maximumPersistenceBytes":
                guard maximumPersistenceBytes == nil else {
                    throw ClipboardHistoryError.duplicatePersistenceKey
                }
                maximumPersistenceBytes = try parseInteger(allowsFraction: false)
            default:
                throw ClipboardHistoryError.unknownPersistenceKey
            }
            try skipWhitespace()
            if consumeIfPresent(0x7D) { return }
            try consume(0x2C)
            try skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw malformed() }
        try consume(0x5B)
        try skipWhitespace()
        if consumeIfPresent(0x5D) { return }
        var count = 0
        while true {
            guard count < Self.maximumArrayElements else { throw malformed() }
            count += 1
            try parseValue(depth: depth)
            try skipWhitespace()
            if consumeIfPresent(0x5D) { return }
            try consume(0x2C)
            try skipWhitespace()
        }
    }

    private mutating func parseASCIIKey() throws -> String {
        try consume(0x22)
        let start = index
        while let byte = currentByte, byte != 0x22 {
            guard (0x20...0x7E).contains(byte), byte != 0x5C,
                index - start < Self.maximumKeyBytes
            else {
                throw malformed()
            }
            index += 1
        }
        guard consumeIfPresent(0x22), index - start - 1 > 0 else { throw malformed() }
        return String(decoding: bytes[start..<(index - 1)], as: UTF8.self)
    }

    private mutating func parseCanonicalASCIIString(maximumBytes: Int) throws -> String {
        try consume(0x22)
        let start = index
        while let byte = currentByte, byte != 0x22 {
            guard (0x20...0x7E).contains(byte), byte != 0x5C,
                index - start < maximumBytes
            else {
                throw malformed()
            }
            index += 1
        }
        guard consumeIfPresent(0x22) else { throw malformed() }
        return String(decoding: bytes[start..<(index - 1)], as: UTF8.self)
    }

    private mutating func parseEntryKind() throws -> ClipboardHistoryPayload.Kind? {
        let kind: ClipboardHistoryPayload.Kind?
        if hasPrefix(#""text""#) {
            kind = .text
        } else if hasPrefix(#""image""#) {
            kind = .image
        } else {
            kind = nil
        }
        try parseString()
        return kind
    }

    private mutating func parseString() throws {
        try consume(0x22)
        while let byte = currentByte {
            try checkCancellation(force: false)
            switch byte {
            case 0x22:
                index += 1
                return
            case 0x00...0x1F:
                throw malformed()
            case 0x5C:
                index += 1
                guard let escaped = currentByte else { throw malformed() }
                index += 1
                switch escaped {
                case 0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
                    break
                case 0x75:
                    for _ in 0..<4 {
                        guard let hex = currentByte, Self.isHex(hex) else {
                            throw malformed()
                        }
                        index += 1
                    }
                default:
                    throw malformed()
                }
            default:
                index += 1
            }
        }
        throw malformed()
    }

    private mutating func parseInteger(allowsFraction: Bool) throws -> Int {
        let start = index
        _ = consumeIfPresent(0x2D)
        guard let first = currentByte else { throw malformed() }
        if first == 0x30 {
            index += 1
            if currentByte.map({ (0x30...0x39).contains($0) }) == true { throw malformed() }
        } else {
            guard (0x31...0x39).contains(first) else { throw malformed() }
            try consumeDigits(numberStart: start)
        }
        if allowsFraction, consumeIfPresent(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformed()
            }
            try consumeDigits(numberStart: start)
        }
        if allowsFraction, consumeIfPresent(0x65) || consumeIfPresent(0x45) {
            _ = consumeIfPresent(0x2B) || consumeIfPresent(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformed()
            }
            try consumeDigits(numberStart: start)
        }
        guard index - start <= Self.maximumNumberBytes else { throw malformed() }
        if allowsFraction { return 0 }
        guard let value = Int(String(decoding: bytes[start..<index], as: UTF8.self)) else {
            throw malformed()
        }
        return value
    }

    private mutating func consumeDigits(numberStart: Int) throws {
        repeat {
            guard index - numberStart < Self.maximumNumberBytes else { throw malformed() }
            index += 1
            try checkCancellation(force: false)
        } while currentByte.map { (0x30...0x39).contains($0) } == true
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard index <= bytes.count - literalBytes.count else { throw malformed() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformed() }
            index += 1
        }
    }

    private func hasPrefix(_ literal: StaticString) -> Bool {
        literal.withUTF8Buffer { literalBytes in
            guard index <= bytes.count - literalBytes.count else { return false }
            return bytes[index..<(index + literalBytes.count)].elementsEqual(literalBytes)
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
            try checkCancellation(force: false)
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard consumeIfPresent(byte) else { throw malformed() }
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private mutating func checkCancellation(force: Bool) throws {
        guard force || index - lastCancellationIndex >= 4 * 1_024 else { return }
        try Task.checkCancellation()
        lastCancellationIndex = index
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x46).contains(byte)
            || (0x61...0x66).contains(byte)
    }

    private func malformed() -> ClipboardHistoryError {
        .malformedPersistence
    }
}
