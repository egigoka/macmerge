import CryptoKit
import Foundation

public enum ClipboardComparisonSide: String, Equatable, Sendable {
    case left
    case right
}

public enum ClipboardSnapshotContent: Equatable, Sendable {
    case empty
    case text(String)
    case binary(Data, typeIdentifier: String?)

    public var byteCount: Int {
        switch self {
        case .empty:
            0
        case .text(let text):
            text.utf8.count
        case .binary(let data, _):
            data.count
        }
    }

    fileprivate func byteCount(notExceeding maximumBytes: Int) -> Int? {
        switch self {
        case .empty:
            return 0
        case .text(let text):
            var byteCount = 0
            for _ in text.utf8 {
                guard byteCount < maximumBytes else { return nil }
                byteCount += 1
            }
            return byteCount
        case .binary(let data, _):
            return data.count <= maximumBytes ? data.count : nil
        }
    }
}

public struct ClipboardSnapshot: Equatable, Identifiable, Sendable {
    public let content: ClipboardSnapshotContent
    public let sourceLabel: String?
    public let timestamp: Date?
    public let changeCount: Int?
    public let contentID: String
    public let stableID: String

    public var id: String { stableID }
    public var byteCount: Int { content.byteCount }

    public init(
        content: ClipboardSnapshotContent,
        sourceLabel: String? = nil,
        timestamp: Date? = nil,
        changeCount: Int? = nil,
        stableID: String? = nil,
        maximumBytes: Int = ClipboardComparisonLimits.default.maximumSnapshotBytes
    ) throws {
        precondition(maximumBytes >= 0, "Maximum snapshot size must not be negative")
        try Self.validateMetadata(
            content: content,
            sourceLabel: sourceLabel,
            timestamp: timestamp,
            changeCount: changeCount,
            stableID: stableID,
            side: nil
        )
        guard content.byteCount(notExceeding: maximumBytes) != nil else {
            throw ClipboardComparisonError.snapshotTooLarge(nil, maximumBytes: maximumBytes)
        }

        self.content = content
        self.sourceLabel = sourceLabel
        self.timestamp = timestamp
        self.changeCount = changeCount
        contentID = Self.makeContentID(for: content)
        self.stableID = stableID ?? contentID
    }

    public init(
        text: String,
        sourceLabel: String? = nil,
        timestamp: Date? = nil,
        changeCount: Int? = nil,
        stableID: String? = nil,
        maximumBytes: Int = ClipboardComparisonLimits.default.maximumSnapshotBytes
    ) throws {
        try self.init(
            content: .text(text),
            sourceLabel: sourceLabel,
            timestamp: timestamp,
            changeCount: changeCount,
            stableID: stableID,
            maximumBytes: maximumBytes
        )
    }

    public init(
        data: Data,
        typeIdentifier: String? = nil,
        sourceLabel: String? = nil,
        timestamp: Date? = nil,
        changeCount: Int? = nil,
        stableID: String? = nil,
        maximumBytes: Int = ClipboardComparisonLimits.default.maximumSnapshotBytes
    ) throws {
        try self.init(
            content: .binary(data, typeIdentifier: typeIdentifier),
            sourceLabel: sourceLabel,
            timestamp: timestamp,
            changeCount: changeCount,
            stableID: stableID,
            maximumBytes: maximumBytes
        )
    }

    private static func makeContentID(for content: ClipboardSnapshotContent) -> String {
        var hasher = SHA256()
        switch content {
        case .empty:
            updateHash(with: UInt8(0), hasher: &hasher)
        case .text(let text):
            let canonicalText = text.precomposedStringWithCanonicalMapping
            updateHash(with: UInt8(1), hasher: &hasher)
            updateHash(with: UInt64(canonicalText.utf8.count), hasher: &hasher)
            updateHash(with: canonicalText, hasher: &hasher)
        case .binary(let data, let typeIdentifier):
            updateHash(with: UInt8(2), hasher: &hasher)
            if let typeIdentifier {
                let canonicalTypeIdentifier = typeIdentifier.precomposedStringWithCanonicalMapping
                updateHash(with: UInt8(1), hasher: &hasher)
                updateHash(with: UInt64(canonicalTypeIdentifier.utf8.count), hasher: &hasher)
                updateHash(with: canonicalTypeIdentifier, hasher: &hasher)
            } else {
                updateHash(with: UInt8(0), hasher: &hasher)
            }
            hasher.update(data: data)
        }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func updateHash(with byte: UInt8, hasher: inout SHA256) {
        var byte = byte
        withUnsafeBytes(of: &byte) { hasher.update(bufferPointer: $0) }
    }

    private static func updateHash(with value: UInt64, hasher: inout SHA256) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { hasher.update(bufferPointer: $0) }
    }

    private static func updateHash(with string: String, hasher: inout SHA256) {
        let usedContiguousStorage =
            string.utf8.withContiguousStorageIfAvailable { bytes -> Bool in
                hasher.update(bufferPointer: UnsafeRawBufferPointer(bytes))
                return true
            } ?? false
        guard !usedContiguousStorage else { return }

        var chunk: [UInt8] = []
        chunk.reserveCapacity(16 * 1_024)
        for byte in string.utf8 {
            chunk.append(byte)
            if chunk.count == chunk.capacity {
                chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            chunk.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
    }

    fileprivate static func validateMetadata(
        content: ClipboardSnapshotContent,
        sourceLabel: String?,
        timestamp: Date?,
        changeCount: Int?,
        stableID: String?,
        side: ClipboardComparisonSide?
    ) throws {
        if let sourceLabel, !isValidMetadataString(sourceLabel) {
            throw ClipboardComparisonError.invalidSourceLabel(side)
        }
        if let timestamp, !timestamp.timeIntervalSinceReferenceDate.isFinite {
            throw ClipboardComparisonError.invalidTimestamp(side)
        }
        if let changeCount, changeCount < 0 {
            throw ClipboardComparisonError.invalidChangeCount(side)
        }
        if let stableID, !isValidMetadataString(stableID) {
            throw ClipboardComparisonError.invalidStableID(side)
        }
        if case .binary(_, let typeIdentifier?) = content,
            !isValidMetadataString(typeIdentifier, allowsNUL: true)
        {
            throw ClipboardComparisonError.invalidTypeIdentifier(side)
        }
    }

    private static func isValidMetadataString(_ value: String, allowsNUL: Bool = false) -> Bool {
        var byteCount = 0
        for byte in value.utf8 {
            guard allowsNUL || byte != 0, byteCount < 1_024 else { return false }
            byteCount += 1
        }
        return byteCount > 0 && value.contains { !$0.isWhitespace }
    }
}

public struct ClipboardComparisonLimits: Equatable, Sendable {
    public static let `default` = ClipboardComparisonLimits()

    public let maximumSnapshotBytes: Int
    public let maximumCombinedBytes: Int
    public let allowsBinaryContent: Bool

    public init(
        maximumSnapshotBytes: Int = 64 * 1024 * 1024,
        maximumCombinedBytes: Int = 128 * 1024 * 1024,
        allowsBinaryContent: Bool = true
    ) {
        precondition(maximumSnapshotBytes >= 0, "Maximum snapshot size must not be negative")
        precondition(maximumCombinedBytes >= 0, "Maximum combined size must not be negative")
        self.maximumSnapshotBytes = maximumSnapshotBytes
        self.maximumCombinedBytes = maximumCombinedBytes
        self.allowsBinaryContent = allowsBinaryContent
    }
}

public enum ClipboardComparisonError: Error, LocalizedError, Equatable, Sendable {
    case emptySnapshot(ClipboardComparisonSide?)
    case snapshotTooLarge(ClipboardComparisonSide?, maximumBytes: Int)
    case combinedInputTooLarge(maximumBytes: Int)
    case mixedContentKinds
    case binaryContentNotAllowed(ClipboardComparisonSide?)
    case invalidSourceLabel(ClipboardComparisonSide?)
    case invalidTimestamp(ClipboardComparisonSide?)
    case invalidChangeCount(ClipboardComparisonSide?)
    case invalidStableID(ClipboardComparisonSide?)
    case invalidTypeIdentifier(ClipboardComparisonSide?)

    public var errorDescription: String? {
        switch self {
        case .emptySnapshot(let side):
            "\(descriptionPrefix(for: side)) is empty."
        case .snapshotTooLarge(let side, let maximumBytes):
            "\(descriptionPrefix(for: side)) exceeds the \(maximumBytes)-byte input limit."
        case .combinedInputTooLarge(let maximumBytes):
            "Clipboard comparison inputs exceed the \(maximumBytes)-byte combined limit."
        case .mixedContentKinds:
            "Clipboard comparison requires two text snapshots or two binary snapshots."
        case .binaryContentNotAllowed(let side):
            "\(descriptionPrefix(for: side)) contains binary data, which is disabled for this comparison."
        case .invalidSourceLabel(let side):
            "\(descriptionPrefix(for: side)) has an invalid source label."
        case .invalidTimestamp(let side):
            "\(descriptionPrefix(for: side)) has an invalid timestamp."
        case .invalidChangeCount(let side):
            "\(descriptionPrefix(for: side)) has an invalid change count."
        case .invalidStableID(let side):
            "\(descriptionPrefix(for: side)) has an invalid stable identifier."
        case .invalidTypeIdentifier(let side):
            "\(descriptionPrefix(for: side)) has an invalid binary type identifier."
        }
    }

    private func descriptionPrefix(for side: ClipboardComparisonSide?) -> String {
        switch side {
        case .left:
            "Left clipboard snapshot"
        case .right:
            "Right clipboard snapshot"
        case nil:
            "Clipboard snapshot"
        }
    }
}

public enum ClipboardComparisonContent: Equatable, Sendable {
    case text(String)
    case binary(Data, typeIdentifier: String?)

    public var byteCount: Int {
        switch self {
        case .text(let text):
            text.utf8.count
        case .binary(let data, _):
            data.count
        }
    }
}

public struct ClipboardComparisonInput: Equatable, Identifiable, Sendable {
    public let side: ClipboardComparisonSide
    public let sourceLabel: String
    public let timestamp: Date?
    public let changeCount: Int?
    public let stableID: String
    public let content: ClipboardComparisonContent

    public var id: String { "\(side.rawValue):\(stableID)" }
    public var byteCount: Int { content.byteCount }

    public var text: String? {
        guard case .text(let text) = content else { return nil }
        return text
    }

    public var binaryData: Data? {
        guard case .binary(let data, _) = content else { return nil }
        return data
    }

    public var binaryTypeIdentifier: String? {
        guard case .binary(_, let typeIdentifier) = content else { return nil }
        return typeIdentifier
    }

    fileprivate init(
        side: ClipboardComparisonSide,
        snapshot: ClipboardSnapshot,
        content: ClipboardComparisonContent,
        defaultSourceLabel: String
    ) {
        self.side = side
        sourceLabel = snapshot.sourceLabel ?? defaultSourceLabel
        timestamp = snapshot.timestamp
        changeCount = snapshot.changeCount
        stableID = snapshot.stableID
        self.content = content
    }
}

public struct ClipboardComparisonInputs: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case text
        case binary
    }

    public let left: ClipboardComparisonInput
    public let right: ClipboardComparisonInput
    public let kind: Kind

    public init(
        left: ClipboardSnapshot,
        right: ClipboardSnapshot,
        limits: ClipboardComparisonLimits = .default
    ) throws {
        try self.init(
            left: left,
            right: right,
            leftDefaultSourceLabel: ClipboardComparisonSide.left.defaultSourceLabel,
            rightDefaultSourceLabel: ClipboardComparisonSide.right.defaultSourceLabel,
            limits: limits
        )
    }

    private init(
        left: ClipboardSnapshot,
        right: ClipboardSnapshot,
        leftDefaultSourceLabel: String,
        rightDefaultSourceLabel: String,
        limits: ClipboardComparisonLimits
    ) throws {
        let leftContent = try Self.validate(left, side: .left, limits: limits)
        let rightContent = try Self.validate(right, side: .right, limits: limits)
        let (combinedBytes, overflow) = left.byteCount.addingReportingOverflow(right.byteCount)
        guard !overflow, combinedBytes <= limits.maximumCombinedBytes else {
            throw ClipboardComparisonError.combinedInputTooLarge(maximumBytes: limits.maximumCombinedBytes)
        }

        switch (leftContent, rightContent) {
        case (.text, .text):
            kind = .text
        case (.binary, .binary):
            kind = .binary
        default:
            throw ClipboardComparisonError.mixedContentKinds
        }
        self.left = ClipboardComparisonInput(
            side: .left,
            snapshot: left,
            content: leftContent,
            defaultSourceLabel: leftDefaultSourceLabel
        )
        self.right = ClipboardComparisonInput(
            side: .right,
            snapshot: right,
            content: rightContent,
            defaultSourceLabel: rightDefaultSourceLabel
        )
    }

    public init(
        previous: ClipboardSnapshot,
        latest: ClipboardSnapshot,
        limits: ClipboardComparisonLimits = .default
    ) throws {
        try self.init(
            left: previous,
            right: latest,
            leftDefaultSourceLabel: "Clipboard (Previous)",
            rightDefaultSourceLabel: "Clipboard (Latest)",
            limits: limits
        )
    }

    public var textValues: (left: String, right: String)? {
        guard let left = left.text, let right = right.text else { return nil }
        return (left, right)
    }

    public var binaryValues: (left: Data, right: Data)? {
        guard let left = left.binaryData, let right = right.binaryData else { return nil }
        return (left, right)
    }

    private static func validate(
        _ snapshot: ClipboardSnapshot,
        side: ClipboardComparisonSide,
        limits: ClipboardComparisonLimits
    ) throws -> ClipboardComparisonContent {
        try validateMetadata(snapshot, side: side)
        guard snapshot.byteCount > 0 else {
            throw ClipboardComparisonError.emptySnapshot(side)
        }
        guard snapshot.byteCount <= limits.maximumSnapshotBytes else {
            throw ClipboardComparisonError.snapshotTooLarge(side, maximumBytes: limits.maximumSnapshotBytes)
        }

        switch snapshot.content {
        case .empty:
            throw ClipboardComparisonError.emptySnapshot(side)
        case .text(let text):
            return .text(text)
        case .binary(let data, let typeIdentifier):
            guard limits.allowsBinaryContent else {
                throw ClipboardComparisonError.binaryContentNotAllowed(side)
            }
            return .binary(data, typeIdentifier: typeIdentifier)
        }
    }

    fileprivate static func validateMetadata(
        _ snapshot: ClipboardSnapshot,
        side: ClipboardComparisonSide?
    ) throws {
        try ClipboardSnapshot.validateMetadata(
            content: snapshot.content,
            sourceLabel: snapshot.sourceLabel,
            timestamp: snapshot.timestamp,
            changeCount: snapshot.changeCount,
            stableID: snapshot.stableID,
            side: side
        )
    }
}

public enum ClipboardComparison {
    public static func inputs(
        left: ClipboardSnapshot,
        right: ClipboardSnapshot,
        limits: ClipboardComparisonLimits = .default
    ) throws -> ClipboardComparisonInputs {
        try ClipboardComparisonInputs(left: left, right: right, limits: limits)
    }

    public static func inputs(
        previous: ClipboardSnapshot,
        latest: ClipboardSnapshot,
        limits: ClipboardComparisonLimits = .default
    ) throws -> ClipboardComparisonInputs {
        try ClipboardComparisonInputs(previous: previous, latest: latest, limits: limits)
    }
}

public struct ClipboardSnapshotHistory: Sendable {
    public let capacity: Int
    public let maximumBytes: Int
    public private(set) var snapshots: [ClipboardSnapshot]
    public private(set) var retainedByteCount: Int

    public var latest: ClipboardSnapshot? { snapshots.first }
    public var count: Int { snapshots.count }
    public var isEmpty: Bool { snapshots.isEmpty }

    public init(capacity: Int = 20, maximumBytes: Int = 128 * 1024 * 1024) {
        precondition(capacity > 0, "Clipboard history capacity must be positive")
        precondition(maximumBytes > 0, "Clipboard history byte limit must be positive")
        self.capacity = capacity
        self.maximumBytes = maximumBytes
        snapshots = []
        retainedByteCount = 0
    }

    public subscript(index: Int) -> ClipboardSnapshot {
        snapshots[index]
    }

    public func comparisonInputs(
        limits: ClipboardComparisonLimits = .default
    ) throws -> ClipboardComparisonInputs? {
        guard snapshots.count >= 2 else { return nil }
        return try ClipboardComparisonInputs(
            previous: snapshots[1],
            latest: snapshots[0],
            limits: limits
        )
    }

    @discardableResult
    public mutating func record(_ snapshot: ClipboardSnapshot) throws -> Bool {
        try ClipboardComparisonInputs.validateMetadata(snapshot, side: nil)
        guard snapshot.byteCount > 0 else {
            throw ClipboardComparisonError.emptySnapshot(nil)
        }
        guard snapshot.byteCount <= maximumBytes else {
            throw ClipboardComparisonError.snapshotTooLarge(nil, maximumBytes: maximumBytes)
        }

        let unchangedLatest = snapshots.first == snapshot
        var removedCount = 0
        for index in snapshots.indices.reversed()
        where snapshots[index].stableID == snapshot.stableID
            || snapshots[index].contentID == snapshot.contentID
        {
            removeSnapshot(at: index)
            removedCount += 1
        }

        while snapshots.count >= capacity
            || retainedByteCount > maximumBytes - snapshot.byteCount
        {
            removeSnapshot(at: snapshots.index(before: snapshots.endIndex))
        }
        let (newRetainedByteCount, overflow) = retainedByteCount.addingReportingOverflow(snapshot.byteCount)
        guard !overflow, newRetainedByteCount <= maximumBytes else {
            throw ClipboardComparisonError.combinedInputTooLarge(maximumBytes: maximumBytes)
        }
        snapshots.insert(snapshot, at: 0)
        retainedByteCount = newRetainedByteCount
        return !unchangedLatest || removedCount != 1
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        snapshots.removeAll(keepingCapacity: keepingCapacity)
        retainedByteCount = 0
    }

    private mutating func removeSnapshot(at index: Int) {
        let removedByteCount = snapshots.remove(at: index).byteCount
        let (newRetainedByteCount, underflow) = retainedByteCount.subtractingReportingOverflow(removedByteCount)
        precondition(!underflow && newRetainedByteCount >= 0, "Clipboard history byte count is inconsistent")
        retainedByteCount = newRetainedByteCount
    }
}

extension ClipboardComparisonSide {
    fileprivate var defaultSourceLabel: String {
        switch self {
        case .left:
            "Clipboard (Left)"
        case .right:
            "Clipboard (Right)"
        }
    }
}
