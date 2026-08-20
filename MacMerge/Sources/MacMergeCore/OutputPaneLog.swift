import Foundation

/// Value-semantic, bounded storage for messages displayed in an output pane.
public struct OutputPaneLog: Equatable, Sendable, RandomAccessCollection {
    public struct Limits: Equatable, Sendable {
        public static let defaultMaximumEntryCount = 10_000
        public static let defaultMaximumUTF8Bytes = 8 * 1_024 * 1_024
        public static let `default` = Limits()

        public let maximumEntryCount: Int
        public let maximumUTF8Bytes: Int

        public init(
            maximumEntryCount: Int = defaultMaximumEntryCount,
            maximumUTF8Bytes: Int = defaultMaximumUTF8Bytes
        ) {
            precondition(maximumEntryCount > 0, "Output-pane entry limit must be positive")
            precondition(maximumUTF8Bytes > 0, "Output-pane byte limit must be positive")
            self.maximumEntryCount = maximumEntryCount
            self.maximumUTF8Bytes = maximumUTF8Bytes
        }
    }

    public enum Severity: String, CaseIterable, Equatable, Sendable {
        case debug
        case info
        case warning
        case error
    }

    public struct Entry: Equatable, Identifiable, Sendable {
        public struct ID: RawRepresentable, Comparable, Equatable, Hashable, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
                self.rawValue = rawValue
            }

            public static func < (left: ID, right: ID) -> Bool {
                left.rawValue < right.rawValue
            }
        }

        public let id: ID
        public let severity: Severity
        public let timestamp: Date
        public let text: String
        public let utf8ByteCount: Int
        public let wasSanitized: Bool

        fileprivate init(
            id: ID,
            severity: Severity,
            timestamp: Date,
            text: String,
            utf8ByteCount: Int,
            wasSanitized: Bool
        ) {
            self.id = id
            self.severity = severity
            self.timestamp = timestamp
            self.text = text
            self.utf8ByteCount = utf8ByteCount
            self.wasSanitized = wasSanitized
        }
    }

    public struct AppendResult: Equatable, Sendable {
        public let entry: Entry
        public let evictedIDs: [Entry.ID]
        public let evictedUTF8ByteCount: Int

        public var evictedEntryCount: Int { evictedIDs.count }

        fileprivate init(
            entry: Entry,
            evictedIDs: [Entry.ID],
            evictedUTF8ByteCount: Int
        ) {
            self.entry = entry
            self.evictedIDs = evictedIDs
            self.evictedUTF8ByteCount = evictedUTF8ByteCount
        }
    }

    public typealias Index = Int

    public let limits: Limits
    public private(set) var entries: [Entry]
    public private(set) var selectedIDs: Set<Entry.ID>
    public private(set) var retainedUTF8ByteCount: Int

    private var nextID: UInt64?

    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }
    public var selectedEntries: [Entry] {
        entries.filter { selectedIDs.contains($0.id) }
    }

    public subscript(position: Int) -> Entry {
        entries[position]
    }

    public init(limits: Limits = .default) {
        self.limits = limits
        entries = []
        selectedIDs = []
        retainedUTF8ByteCount = 0
        nextID = 1
    }

    /// Sanitizes and appends one message, evicting oldest entries first.
    ///
    /// The byte budget counts sanitized message text only. Rejected appends do not
    /// consume an identifier, evict entries, or otherwise mutate the log.
    @discardableResult
    public mutating func append(
        severity: Severity,
        timestamp: Date,
        text: String
    ) throws -> AppendResult {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw OutputPaneLogError.invalidTimestamp
        }
        guard let nextID else {
            throw OutputPaneLogError.identifierSpaceExhausted
        }

        let sanitized = try Self.sanitize(text, maximumUTF8Bytes: limits.maximumUTF8Bytes)
        let entry = Entry(
            id: Entry.ID(rawValue: nextID),
            severity: severity,
            timestamp: timestamp,
            text: sanitized.text,
            utf8ByteCount: sanitized.utf8ByteCount,
            wasSanitized: sanitized.wasChanged
        )

        let availableBytes = limits.maximumUTF8Bytes - entry.utf8ByteCount
        var firstRetainedIndex = 0
        var remainingBytes = retainedUTF8ByteCount
        while entries.count - firstRetainedIndex >= limits.maximumEntryCount
            || remainingBytes > availableBytes
        {
            remainingBytes -= entries[firstRetainedIndex].utf8ByteCount
            firstRetainedIndex += 1
        }

        let evictedUTF8ByteCount = retainedUTF8ByteCount - remainingBytes
        let evictedEntries = entries[..<firstRetainedIndex]
        let evictedIDs = evictedEntries.map(\.id)
        for id in evictedIDs {
            selectedIDs.remove(id)
        }
        if firstRetainedIndex > 0 {
            entries.removeFirst(firstRetainedIndex)
        }

        entries.append(entry)
        retainedUTF8ByteCount = remainingBytes + entry.utf8ByteCount
        self.nextID = nextID == .max ? nil : nextID + 1
        return AppendResult(
            entry: entry,
            evictedIDs: evictedIDs,
            evictedUTF8ByteCount: evictedUTF8ByteCount
        )
    }

    /// Replaces selection with a retained entry, or extends selection when requested.
    @discardableResult
    public mutating func select(_ id: Entry.ID, extendingSelection: Bool = false) -> Bool {
        guard entries.contains(where: { $0.id == id }) else { return false }
        let previousSelection = selectedIDs
        if !extendingSelection {
            selectedIDs.removeAll(keepingCapacity: true)
        }
        selectedIDs.insert(id)
        return selectedIDs != previousSelection
    }

    @discardableResult
    public mutating func setSelection(_ ids: Set<Entry.ID>) -> Bool {
        let retainedIDs = Set(entries.map(\.id))
        let selection = ids.intersection(retainedIDs)
        guard selection != selectedIDs else { return false }
        selectedIDs = selection
        return true
    }

    @discardableResult
    public mutating func toggleSelection(_ id: Entry.ID) -> Bool {
        guard entries.contains(where: { $0.id == id }) else { return false }
        if selectedIDs.remove(id) == nil {
            selectedIDs.insert(id)
        }
        return true
    }

    @discardableResult
    public mutating func selectAll() -> Bool {
        setSelection(Set(entries.map(\.id)))
    }

    @discardableResult
    public mutating func clearSelection() -> Bool {
        guard !selectedIDs.isEmpty else { return false }
        selectedIDs.removeAll(keepingCapacity: true)
        return true
    }

    /// Returns selected message text in retained order, separated by line feeds.
    public func copySelection() -> String? {
        let selectedText = entries.lazy
            .filter { selectedIDs.contains($0.id) }
            .map(\.text)
        guard let first = selectedText.first else { return nil }

        var result = first
        for text in selectedText.dropFirst() {
            result.append("\n")
            result.append(text)
        }
        return result
    }

    public func copyEntry(_ id: Entry.ID) -> String? {
        entries.first { $0.id == id }?.text
    }

    /// Clears retained messages and selection without reusing issued identifiers.
    @discardableResult
    public mutating func clear() -> Bool {
        guard !entries.isEmpty || !selectedIDs.isEmpty else { return false }
        entries.removeAll(keepingCapacity: true)
        selectedIDs.removeAll(keepingCapacity: true)
        retainedUTF8ByteCount = 0
        return true
    }

    private static func sanitize(
        _ text: String,
        maximumUTF8Bytes: Int
    ) throws -> (text: String, utf8ByteCount: Int, wasChanged: Bool) {
        guard text.utf8.count <= maximumUTF8Bytes else {
            throw OutputPaneLogError.entryTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
        }

        var result = ""
        result.reserveCapacity(text.utf8.count)
        var byteCount = 0
        var wasChanged = false

        for scalar in text.unicodeScalars {
            if isUnsafe(scalar.value) {
                let escaped = escapedUnsafeScalar(scalar.value)
                let addedBytes = escaped.utf8.count
                guard addedBytes <= maximumUTF8Bytes,
                    byteCount <= maximumUTF8Bytes - addedBytes
                else {
                    throw OutputPaneLogError.entryTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
                }
                result.append(escaped)
                byteCount += addedBytes
                wasChanged = true
            } else {
                let addedBytes = utf8ByteCount(of: scalar.value)
                guard byteCount <= maximumUTF8Bytes - addedBytes else {
                    throw OutputPaneLogError.entryTooLarge(maximumUTF8Bytes: maximumUTF8Bytes)
                }
                result.unicodeScalars.append(scalar)
                byteCount += addedBytes
            }
        }
        return (result, byteCount, wasChanged)
    }

    private static func isUnsafe(_ value: UInt32) -> Bool {
        value <= 0x1F
            || (0x7F...0x9F).contains(value)
            || value == 0x061C
            || (0x200E...0x200F).contains(value)
            || (0x2028...0x202E).contains(value)
            || (0x2066...0x206F).contains(value)
    }

    private static func escapedUnsafeScalar(_ value: UInt32) -> String {
        switch value {
        case 0x09: "\\t"
        case 0x0A: "\\n"
        case 0x0D: "\\r"
        default: "\\u{" + String(value, radix: 16, uppercase: true) + "}"
        }
    }

    private static func utf8ByteCount(of value: UInt32) -> Int {
        switch value {
        case ...0x7F: 1
        case ...0x7FF: 2
        case ...0xFFFF: 3
        default: 4
        }
    }
}

public enum OutputPaneLogError: Error, LocalizedError, Equatable, Sendable {
    case invalidTimestamp
    case entryTooLarge(maximumUTF8Bytes: Int)
    case identifierSpaceExhausted

    public var errorDescription: String? {
        switch self {
        case .invalidTimestamp:
            "Output-pane timestamp must be finite."
        case .entryTooLarge(let maximumUTF8Bytes):
            "Output-pane entry exceeds the \(maximumUTF8Bytes)-byte sanitized UTF-8 limit."
        case .identifierSpaceExhausted:
            "Output-pane entry identifier space is exhausted."
        }
    }
}
