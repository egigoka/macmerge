import Foundation

/// Pasteboard binding planner over `ClipboardHistory` and `ClipboardComparison`.
///
/// WinMerge gap (`ID_FILE_OPENCLIPBOARD`): snapshot, identity, comparison-input,
/// and MRU history cores exist, but `NSPasteboard`, command, and UI integration
/// remain missing. This planner is UI-independent: it maps pinned MRU text/image
/// identities to pasteboard read/write intents, projects redacted history-menu
/// rows without payload bytes, forwards selection/comparison requests with stale
/// validation, and wraps metadata-only versus opt-in secure persistence with
/// strict decoding. It never touches `NSPasteboard`, clocks, menus, or windows:
/// the AppKit layer observes the pasteboard, passes observed bytes here, applies
/// the returned plans, and executes the resulting intents against the pasteboard.
///
/// Payload bytes travel only inside read/write plans built from history entries
/// the caller already holds. Menu projections, descriptions, debug output, and
/// mirrors never contain text or image bytes.
public enum ClipboardPasteboardBindingChange: Equatable, Sendable {
    case text(String)
    case image(Data, typeIdentifier: String, pixelWidth: Int? = nil, pixelHeight: Int? = nil)

    public var byteCount: Int {
        switch self {
        case .text(let value):
            value.utf8.count
        case .image(let data, _, _, _):
            data.count
        }
    }
}

/// Caller-observed pasteboard content awaiting recording. The caller reads its
/// trusted pasteboard source, then hands the bytes here for validation/planning.
public struct ClipboardPasteboardObservedChange: Equatable, Sendable {
    public let content: ClipboardPasteboardBindingChange
    public let sourceIdentifier: String
    public let timestamp: Date
    public let pasteboardChangeCount: Int?
    public let pinned: Bool

    public init(
        content: ClipboardPasteboardBindingChange,
        sourceIdentifier: String,
        timestamp: Date,
        pasteboardChangeCount: Int? = nil,
        pinned: Bool = false
    ) {
        self.content = content
        self.sourceIdentifier = sourceIdentifier
        self.timestamp = timestamp
        self.pasteboardChangeCount = pasteboardChangeCount
        self.pinned = pinned
    }
}

public struct ClipboardPasteboardBindingLimits: Equatable, Sendable {
    public static let hardMaximumMenuItems = 1_000
    public static let hardMaximumPayloadBytes = ClipboardHistory.maximumSupportedPayloadBytes
    public static let hardMaximumWorkUnits: UInt64 = 1 << 42
    public static let hardMaximumCancellationCheckInterval: UInt64 = 4_096
    public static let `default` = ClipboardPasteboardBindingLimits()

    public let maximumMenuItems: Int
    public let maximumPayloadBytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64

    public init(
        maximumMenuItems: Int = 20,
        maximumPayloadBytes: Int = ClipboardHistory.defaultMaximumPayloadBytes,
        maximumWorkUnits: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 1_024
    ) {
        self.maximumMenuItems = maximumMenuItems
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ClipboardPasteboardBindingError: Error, LocalizedError, Equatable, Sendable {
    case cancelled
    case invalidLimit(String)
    case entryNotFound
    case payloadUnavailable
    case staleHistoryRevision(expected: UInt64, actual: UInt64)
    case staleComparisonRequest
    case selectionRequired
    case mixedPayloadKinds
    case secureSnapshotPolicyRequired
    case invalidChangeCount
    case workLimitExceeded(maximumUnits: UInt64)
    case history(ClipboardHistoryError)
    case comparison(ClipboardComparisonError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Clipboard pasteboard binding was cancelled."
        case .invalidLimit(let name):
            "Invalid clipboard pasteboard binding limit: \(name)."
        case .entryNotFound:
            "Clipboard history entry was not found."
        case .payloadUnavailable:
            "Raw clipboard payload is unavailable from metadata-only history."
        case .staleHistoryRevision(let expected, let actual):
            "Clipboard pasteboard plan expected history revision \(expected), not \(actual)."
        case .staleComparisonRequest:
            "Clipboard comparison request is stale."
        case .selectionRequired:
            "Clipboard comparison requires exactly two selected entries."
        case .mixedPayloadKinds:
            "Clipboard comparison requires two text payloads or two image payloads."
        case .secureSnapshotPolicyRequired:
            "Reading raw clipboard payloads requires explicit secure-snapshot permission."
        case .invalidChangeCount:
            "Pasteboard change count is invalid."
        case .workLimitExceeded(let maximum):
            "Clipboard pasteboard binding exceeds \(maximum) work units."
        case .history(let error):
            error.localizedDescription
        case .comparison(let error):
            error.localizedDescription
        }
    }
}

/// Redacted history-menu row. Contains identity and metadata only, never bytes.
public struct ClipboardPasteboardBindingMenuItem: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let id: ClipboardHistoryEntryID
    public let kind: ClipboardHistoryPayload.Kind
    public let byteCount: Int
    public let isPinned: Bool
    public let sourceIdentifier: String
    public let timestamp: Date
    public let hasPayload: Bool

    fileprivate init(entry: ClipboardHistory.Entry) {
        id = entry.id
        kind = entry.kind
        byteCount = entry.byteCount
        isPinned = entry.isPinned
        sourceIdentifier = entry.sourceIdentifier
        timestamp = entry.timestamp
        hasPayload = entry.payload != nil
    }

    public var description: String {
        "ClipboardPasteboardBindingMenuItem(kind: \(kind.rawValue), byteCount: \(byteCount), pinned: \(isPinned))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "id": id,
                "kind": kind.rawValue,
                "byteCount": byteCount,
                "isPinned": isPinned,
                "sourceIdentifier": sourceIdentifier,
                "timestamp": timestamp,
                "hasPayload": hasPayload,
            ],
            displayStyle: .struct
        )
    }
}

public struct ClipboardPasteboardBindingMenuProjection: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let items: [ClipboardPasteboardBindingMenuItem]
    public let historyRevision: UInt64
    public let isTruncated: Bool

    fileprivate init(
        items: [ClipboardPasteboardBindingMenuItem],
        historyRevision: UInt64,
        isTruncated: Bool
    ) {
        self.items = items
        self.historyRevision = historyRevision
        self.isTruncated = isTruncated
    }

    public var description: String {
        "ClipboardPasteboardBindingMenuProjection(itemCount: \(items.count), truncated: \(isTruncated))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "itemCount": items.count,
                "historyRevision": historyRevision,
                "isTruncated": isTruncated,
            ],
            displayStyle: .struct
        )
    }
}

/// Validated intent to record observed pasteboard bytes into history.
/// The executor applies it via `apply(to:)`; recording only ingests and
/// writes nothing to the pasteboard.
public struct ClipboardPasteboardReadPlan: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let payload: ClipboardHistoryPayload
    public let sourceIdentifier: String
    public let timestamp: Date
    public let pasteboardChangeCount: Int?
    public let pinned: Bool

    fileprivate init(
        payload: ClipboardHistoryPayload,
        sourceIdentifier: String,
        timestamp: Date,
        pasteboardChangeCount: Int?,
        pinned: Bool
    ) {
        self.payload = payload
        self.sourceIdentifier = sourceIdentifier
        self.timestamp = timestamp
        self.pasteboardChangeCount = pasteboardChangeCount
        self.pinned = pinned
    }

    public var kind: ClipboardHistoryPayload.Kind { payload.kind }
    public var byteCount: Int { payload.byteCount }

    public var description: String {
        "ClipboardPasteboardReadPlan(kind: \(kind.rawValue), byteCount: \(byteCount), pinned: \(pinned))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind.rawValue,
                "byteCount": byteCount,
                "sourceIdentifier": sourceIdentifier,
                "timestamp": timestamp,
                "pasteboardChangeCount": pasteboardChangeCount as Any,
                "pinned": pinned,
                "payload": "<redacted>",
            ],
            displayStyle: .struct
        )
    }

    /// Records the planned payload, returning the ingest receipt.
    public func apply(to history: inout ClipboardHistory) throws
        -> ClipboardPasteboardReadReceipt
    {
        do {
            let revisionBefore = history.revision
            let didChange = try history.record(
                payload,
                sourceIdentifier: sourceIdentifier,
                timestamp: timestamp,
                pinned: pinned
            )
            let entryID = try ClipboardPasteboardBinding.entryID(
                matching: payload,
                in: history
            )
            return ClipboardPasteboardReadReceipt(
                entryID: entryID,
                didChange: didChange,
                historyRevisionBefore: revisionBefore,
                historyRevisionAfter: history.revision,
                kind: payload.kind,
                byteCount: payload.byteCount
            )
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardHistoryError {
            throw ClipboardPasteboardBindingError.history(error)
        }
    }
}

/// Validated intent for the executor to write one retained entry back to the
/// pasteboard. Carries the payload bytes the caller already holds via history.
public struct ClipboardPasteboardWritePlan: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let entryID: ClipboardHistoryEntryID
    public let expectedRevision: UInt64
    public let payload: ClipboardHistoryPayload
    public let sourceIdentifier: String

    fileprivate init(
        entryID: ClipboardHistoryEntryID,
        expectedRevision: UInt64,
        payload: ClipboardHistoryPayload,
        sourceIdentifier: String
    ) {
        self.entryID = entryID
        self.expectedRevision = expectedRevision
        self.payload = payload
        self.sourceIdentifier = sourceIdentifier
    }

    public var kind: ClipboardHistoryPayload.Kind { payload.kind }
    public var byteCount: Int { payload.byteCount }
    public var text: String? { payload.text }
    public var imageData: Data? { payload.imageData }
    public var imageMetadata: ClipboardHistoryImageMetadata? { payload.imageMetadata }

    public var description: String {
        "ClipboardPasteboardWritePlan(kind: \(kind.rawValue), byteCount: \(byteCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "entryID": entryID,
                "expectedRevision": expectedRevision,
                "kind": kind.rawValue,
                "byteCount": byteCount,
                "sourceIdentifier": sourceIdentifier,
                "payload": "<redacted>",
            ],
            displayStyle: .struct
        )
    }

    /// Rejects writes against a history that moved on or lost the payload.
    public func validate(in history: ClipboardHistory) throws {
        do {
            try Task.checkCancellation()
            guard history.revision == expectedRevision else {
                throw ClipboardPasteboardBindingError.staleHistoryRevision(
                    expected: expectedRevision,
                    actual: history.revision
                )
            }
            guard let entry = history.entries.first(where: { $0.id == entryID }) else {
                throw ClipboardPasteboardBindingError.entryNotFound
            }
            guard entry.kind == payload.kind, entry.byteCount == payload.byteCount,
                entry.imageMetadata == payload.imageMetadata,
                let entryPayload = entry.payload
            else {
                throw ClipboardPasteboardBindingError.staleHistoryRevision(
                    expected: expectedRevision,
                    actual: history.revision
                )
            }
            guard entryPayload == payload else {
                throw ClipboardPasteboardBindingError.staleHistoryRevision(
                    expected: expectedRevision,
                    actual: history.revision
                )
            }
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardPasteboardBindingError {
            throw error
        } catch {
            throw error
        }
    }

    /// Attests the executor completed the pasteboard write for this plan.
    public func attestWritten() throws -> ClipboardPasteboardWriteReceipt {
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        }
        return ClipboardPasteboardWriteReceipt(
            entryID: entryID,
            historyRevision: expectedRevision,
            kind: payload.kind,
            byteCount: payload.byteCount
        )
    }
}

/// Validated selection comparison: the history comparison request plus the
/// snapshot inputs a comparison engine consumes.
public struct ClipboardPasteboardComparisonPlan: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let request: ClipboardHistoryComparisonRequest
    public let inputs: ClipboardComparisonInputs

    fileprivate init(
        request: ClipboardHistoryComparisonRequest,
        inputs: ClipboardComparisonInputs
    ) {
        self.request = request
        self.inputs = inputs
    }

    public var description: String {
        "ClipboardPasteboardComparisonPlan(kind: \(inputs.kind))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": "\(inputs.kind)",
                "historyRevision": request.historyRevision,
                "payloads": "<redacted>",
            ],
            displayStyle: .struct
        )
    }

    public func validate(in history: ClipboardHistory) throws {
        do {
            try history.validate(request)
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardHistoryError {
            if error == .staleComparisonRequest {
                throw ClipboardPasteboardBindingError.staleComparisonRequest
            }
            throw ClipboardPasteboardBindingError.history(error)
        }
    }
}

public struct ClipboardPasteboardReadReceipt: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let entryID: ClipboardHistoryEntryID
    public let didChange: Bool
    public let historyRevisionBefore: UInt64
    public let historyRevisionAfter: UInt64
    public let kind: ClipboardHistoryPayload.Kind
    public let byteCount: Int

    fileprivate init(
        entryID: ClipboardHistoryEntryID,
        didChange: Bool,
        historyRevisionBefore: UInt64,
        historyRevisionAfter: UInt64,
        kind: ClipboardHistoryPayload.Kind,
        byteCount: Int
    ) {
        self.entryID = entryID
        self.didChange = didChange
        self.historyRevisionBefore = historyRevisionBefore
        self.historyRevisionAfter = historyRevisionAfter
        self.kind = kind
        self.byteCount = byteCount
    }

    public var description: String {
        "ClipboardPasteboardReadReceipt(kind: \(kind.rawValue), byteCount: \(byteCount), didChange: \(didChange))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "entryID": entryID,
                "didChange": didChange,
                "historyRevisionBefore": historyRevisionBefore,
                "historyRevisionAfter": historyRevisionAfter,
                "kind": kind.rawValue,
                "byteCount": byteCount,
            ],
            displayStyle: .struct
        )
    }
}

public struct ClipboardPasteboardWriteReceipt: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let entryID: ClipboardHistoryEntryID
    public let historyRevision: UInt64
    public let kind: ClipboardHistoryPayload.Kind
    public let byteCount: Int

    fileprivate init(
        entryID: ClipboardHistoryEntryID,
        historyRevision: UInt64,
        kind: ClipboardHistoryPayload.Kind,
        byteCount: Int
    ) {
        self.entryID = entryID
        self.historyRevision = historyRevision
        self.kind = kind
        self.byteCount = byteCount
    }

    public var description: String {
        "ClipboardPasteboardWriteReceipt(kind: \(kind.rawValue), byteCount: \(byteCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "entryID": entryID,
                "historyRevision": historyRevision,
                "kind": kind.rawValue,
                "byteCount": byteCount,
            ],
            displayStyle: .struct
        )
    }
}

public struct ClipboardPasteboardPersistenceReceipt: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let policy: ClipboardHistory.PersistencePolicy
    public let byteCount: Int
    public let historyRevision: UInt64

    fileprivate init(
        policy: ClipboardHistory.PersistencePolicy,
        byteCount: Int,
        historyRevision: UInt64
    ) {
        self.policy = policy
        self.byteCount = byteCount
        self.historyRevision = historyRevision
    }

    public var description: String {
        "ClipboardPasteboardPersistenceReceipt(policy: \(policy.rawValue), byteCount: \(byteCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "policy": policy.rawValue,
                "byteCount": byteCount,
                "historyRevision": historyRevision,
            ],
            displayStyle: .struct
        )
    }
}

public enum ClipboardPasteboardBinding: Sendable {
    /// Redacted pinned-first MRU projection for history menus. Never contains bytes.
    public static func menuProjection(
        of history: ClipboardHistory,
        limits: ClipboardPasteboardBindingLimits = .default
    ) throws -> ClipboardPasteboardBindingMenuProjection {
        var work = try WorkBudget(limits: limits)
        try work.checkCancellation()
        var items: [ClipboardPasteboardBindingMenuItem] = []
        items.reserveCapacity(min(history.entries.count, limits.maximumMenuItems))
        var truncated = false
        for entry in history.entries {
            try work.consume()
            if items.count >= limits.maximumMenuItems {
                truncated = true
                break
            }
            items.append(ClipboardPasteboardBindingMenuItem(entry: entry))
        }
        try work.finish()
        return ClipboardPasteboardBindingMenuProjection(
            items: items,
            historyRevision: history.revision,
            isTruncated: truncated
        )
    }

    /// Whether an observed pasteboard change count is new work. The executor
    /// tracks the last ingested `pasteboardChangeCount` and skips repeats.
    /// A missing observed count always records.
    public static func shouldRecord(
        observedChangeCount: Int?,
        lastSeenChangeCount: Int?
    ) throws -> Bool {
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        }
        guard let observed = observedChangeCount else { return true }
        guard observed >= 0 else {
            throw ClipboardPasteboardBindingError.invalidChangeCount
        }
        guard let lastSeen = lastSeenChangeCount else { return true }
        return observed != lastSeen
    }

    /// Validates observed pasteboard bytes into a recordable plan.
    public static func readPlan(
        for observed: ClipboardPasteboardObservedChange,
        limits: ClipboardPasteboardBindingLimits = .default
    ) throws -> ClipboardPasteboardReadPlan {
        var work = try WorkBudget(limits: limits)
        try work.checkCancellation()
        if let changeCount = observed.pasteboardChangeCount, changeCount < 0 {
            throw ClipboardPasteboardBindingError.invalidChangeCount
        }
        guard observed.timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw ClipboardPasteboardBindingError.history(.invalidTimestamp)
        }
        let payload: ClipboardHistoryPayload
        do {
            switch observed.content {
            case .text(let value):
                payload = try ClipboardHistoryPayload(
                    text: value,
                    maximumBytes: limits.maximumPayloadBytes
                )
            case .image(let data, let typeIdentifier, let pixelWidth, let pixelHeight):
                payload = try ClipboardHistoryPayload(
                    imageData: data,
                    typeIdentifier: typeIdentifier,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    maximumBytes: limits.maximumPayloadBytes
                )
            }
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardHistoryError {
            throw ClipboardPasteboardBindingError.history(error)
        }
        try work.consume(UInt64(max(payload.byteCount, 1)))
        try work.finish()
        return ClipboardPasteboardReadPlan(
            payload: payload,
            sourceIdentifier: observed.sourceIdentifier,
            timestamp: observed.timestamp,
            pasteboardChangeCount: observed.pasteboardChangeCount,
            pinned: observed.pinned
        )
    }

    /// Plans writing one retained entry back to the pasteboard. Fails closed
    /// when the entry holds metadata only.
    public static func writePlan(
        for id: ClipboardHistoryEntryID,
        in history: ClipboardHistory,
        limits: ClipboardPasteboardBindingLimits = .default
    ) throws -> ClipboardPasteboardWritePlan {
        var work = try WorkBudget(limits: limits)
        try work.checkCancellation()
        guard let entry = history.entries.first(where: { $0.id == id }) else {
            throw ClipboardPasteboardBindingError.entryNotFound
        }
        try work.consume()
        guard let payload = entry.payload else {
            throw ClipboardPasteboardBindingError.payloadUnavailable
        }
        try work.consume(UInt64(max(payload.byteCount, 1)))
        try work.finish()
        return ClipboardPasteboardWritePlan(
            entryID: entry.id,
            expectedRevision: history.revision,
            payload: payload,
            sourceIdentifier: entry.sourceIdentifier
        )
    }

    public static func validate(
        _ plan: ClipboardPasteboardWritePlan,
        in history: ClipboardHistory
    ) throws {
        try plan.validate(in: history)
    }

    /// Builds the comparison request for the current two-entry selection and
    /// maps its payloads to snapshot comparison inputs.
    public static func comparisonPlan(
        in history: ClipboardHistory,
        limits: ClipboardPasteboardBindingLimits = .default,
        comparisonLimits: ClipboardComparisonLimits = .default
    ) throws -> ClipboardPasteboardComparisonPlan {
        var work = try WorkBudget(limits: limits)
        try work.checkCancellation()
        let request: ClipboardHistoryComparisonRequest
        do {
            request = try history.comparisonRequest()
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardHistoryError {
            switch error {
            case .comparisonSelectionRequired:
                throw ClipboardPasteboardBindingError.selectionRequired
            case .mixedPayloadKinds:
                throw ClipboardPasteboardBindingError.mixedPayloadKinds
            case .payloadUnavailable:
                throw ClipboardPasteboardBindingError.payloadUnavailable
            case .staleComparisonRequest:
                throw ClipboardPasteboardBindingError.staleComparisonRequest
            default:
                throw ClipboardPasteboardBindingError.history(error)
            }
        }
        try work.consume(UInt64(max(request.left.byteCount, 1)))
        try work.consume(UInt64(max(request.right.byteCount, 1)))
        let inputs = try comparisonInputs(for: request, limits: comparisonLimits)
        try work.finish()
        return ClipboardPasteboardComparisonPlan(request: request, inputs: inputs)
    }

    public static func validateComparison(
        _ plan: ClipboardPasteboardComparisonPlan,
        in history: ClipboardHistory
    ) throws {
        try plan.validate(in: history)
    }

    /// Encodes history with the caller's persistence policy. Secure snapshots
    /// carry plaintext bytes for caller-protected storage only.
    public static func encode(
        _ history: ClipboardHistory,
        policy: ClipboardHistory.PersistencePolicy = .metadataOnly
    ) throws -> (Data, ClipboardPasteboardPersistenceReceipt) {
        do {
            try Task.checkCancellation()
            let data = try history.encodedData(policy: policy)
            return (
                data,
                ClipboardPasteboardPersistenceReceipt(
                    policy: policy,
                    byteCount: data.count,
                    historyRevision: history.revision
                )
            )
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardHistoryError {
            throw ClipboardPasteboardBindingError.history(error)
        }
    }

    /// Strictly decodes canonical history data. Payload-bearing data requires
    /// explicit `.secureSnapshot` permission and caller limits that permit the
    /// embedded limits.
    public static func decode(
        from data: Data,
        policy: ClipboardHistory.PersistencePolicy = .metadataOnly,
        callerLimits: ClipboardHistory.Limits = .default
    ) throws -> ClipboardHistory {
        do {
            try Task.checkCancellation()
            return try ClipboardHistory.decode(
                from: data,
                policy: policy,
                limits: callerLimits
            )
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardHistoryError {
            if error == .secureSnapshotPolicyRequired {
                throw ClipboardPasteboardBindingError.secureSnapshotPolicyRequired
            }
            throw ClipboardPasteboardBindingError.history(error)
        }
    }

    private static func comparisonInputs(
        for request: ClipboardHistoryComparisonRequest,
        limits: ClipboardComparisonLimits
    ) throws -> ClipboardComparisonInputs {
        do {
            let left = try snapshot(
                for: request.left.payload,
                sourceLabel: request.left.sourceIdentifier,
                timestamp: request.left.timestamp,
                stableID: request.left.id.rawValue,
                maximumBytes: limits.maximumSnapshotBytes
            )
            let right = try snapshot(
                for: request.right.payload,
                sourceLabel: request.right.sourceIdentifier,
                timestamp: request.right.timestamp,
                stableID: request.right.id.rawValue,
                maximumBytes: limits.maximumSnapshotBytes
            )
            return try ClipboardComparisonInputs(left: left, right: right, limits: limits)
        } catch is CancellationError {
            throw ClipboardPasteboardBindingError.cancelled
        } catch let error as ClipboardComparisonError {
            switch error {
            case .mixedContentKinds:
                throw ClipboardPasteboardBindingError.mixedPayloadKinds
            case .emptySnapshot:
                throw ClipboardPasteboardBindingError.payloadUnavailable
            default:
                throw ClipboardPasteboardBindingError.comparison(error)
            }
        } catch let error as ClipboardPasteboardBindingError {
            throw error
        }
    }

    private static func snapshot(
        for payload: ClipboardHistoryPayload,
        sourceLabel: String,
        timestamp: Date,
        stableID: String,
        maximumBytes: Int
    ) throws -> ClipboardSnapshot {
        switch payload.kind {
        case .text:
            guard let text = payload.text else {
                throw ClipboardPasteboardBindingError.payloadUnavailable
            }
            return try ClipboardSnapshot(
                text: text,
                sourceLabel: sourceLabel,
                timestamp: timestamp,
                stableID: stableID,
                maximumBytes: maximumBytes
            )
        case .image:
            guard let data = payload.imageData else {
                throw ClipboardPasteboardBindingError.payloadUnavailable
            }
            return try ClipboardSnapshot(
                data: data,
                typeIdentifier: payload.imageMetadata?.typeIdentifier,
                sourceLabel: sourceLabel,
                timestamp: timestamp,
                stableID: stableID,
                maximumBytes: maximumBytes
            )
        }
    }

    fileprivate static func entryID(
        matching payload: ClipboardHistoryPayload,
        in history: ClipboardHistory
    ) throws -> ClipboardHistoryEntryID {
        try Task.checkCancellation()
        for entry in history.entries {
            if entry.payload == payload { return entry.id }
        }
        throw ClipboardPasteboardBindingError.entryNotFound
    }

    private struct WorkBudget {
        let maximum: UInt64
        let cancellationCheckInterval: UInt64
        private(set) var consumed: UInt64 = 0
        private var unitsSinceCancellationCheck: UInt64 = 0

        init(limits: ClipboardPasteboardBindingLimits) throws {
            try ClipboardPasteboardBinding.validate(limits)
            maximum = limits.maximumWorkUnits
            cancellationCheckInterval = limits.cancellationCheckInterval
            do {
                try Task.checkCancellation()
            } catch is CancellationError {
                throw ClipboardPasteboardBindingError.cancelled
            }
        }

        mutating func consume(_ amount: UInt64 = 1) throws {
            guard amount <= maximum - consumed else {
                throw ClipboardPasteboardBindingError.workLimitExceeded(maximumUnits: maximum)
            }
            consumed += amount
            let unitsUntilCheck = cancellationCheckInterval - unitsSinceCancellationCheck
            if amount >= unitsUntilCheck {
                do {
                    try Task.checkCancellation()
                } catch is CancellationError {
                    throw ClipboardPasteboardBindingError.cancelled
                }
                unitsSinceCancellationCheck =
                    (amount - unitsUntilCheck) % cancellationCheckInterval
            } else {
                unitsSinceCancellationCheck += amount
            }
        }

        mutating func checkCancellation() throws {
            do {
                try Task.checkCancellation()
            } catch is CancellationError {
                throw ClipboardPasteboardBindingError.cancelled
            }
            unitsSinceCancellationCheck = 0
        }

        mutating func finish() throws {
            try checkCancellation()
        }
    }

    fileprivate static func validate(_ limits: ClipboardPasteboardBindingLimits) throws {
        guard (1...hardMaximumMenuItems).contains(limits.maximumMenuItems) else {
            throw ClipboardPasteboardBindingError.invalidLimit("menuItems")
        }
        guard (1...hardMaximumPayloadBytes).contains(limits.maximumPayloadBytes) else {
            throw ClipboardPasteboardBindingError.invalidLimit("payloadBytes")
        }
        guard limits.maximumWorkUnits > 0, limits.maximumWorkUnits <= hardMaximumWorkUnits else {
            throw ClipboardPasteboardBindingError.invalidLimit("workUnits")
        }
        guard (1...hardMaximumCancellationCheckInterval).contains(limits.cancellationCheckInterval)
        else {
            throw ClipboardPasteboardBindingError.invalidLimit("cancellationCheckInterval")
        }
    }
}

extension ClipboardPasteboardBinding {
    fileprivate static let hardMaximumMenuItems =
        ClipboardPasteboardBindingLimits.hardMaximumMenuItems
    fileprivate static let hardMaximumPayloadBytes =
        ClipboardPasteboardBindingLimits.hardMaximumPayloadBytes
    fileprivate static let hardMaximumWorkUnits =
        ClipboardPasteboardBindingLimits.hardMaximumWorkUnits
    fileprivate static let hardMaximumCancellationCheckInterval =
        ClipboardPasteboardBindingLimits.hardMaximumCancellationCheckInterval
}

extension ClipboardPasteboardBindingLimits: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "ClipboardPasteboardBindingLimits(menuItems: \(maximumMenuItems), payloadBytes: \(maximumPayloadBytes))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "maximumMenuItems": maximumMenuItems,
                "maximumPayloadBytes": maximumPayloadBytes,
                "maximumWorkUnits": maximumWorkUnits,
                "cancellationCheckInterval": cancellationCheckInterval,
            ],
            displayStyle: .struct
        )
    }
}

extension ClipboardPasteboardBindingChange: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        switch self {
        case .text:
            "ClipboardPasteboardBindingChange(text, <redacted>)"
        case .image:
            "ClipboardPasteboardBindingChange(image, <redacted>)"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["content": "<redacted>"])
    }
}

extension ClipboardPasteboardObservedChange: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "ClipboardPasteboardObservedChange(pinned: \(pinned))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "sourceIdentifier": sourceIdentifier,
                "timestamp": timestamp,
                "pasteboardChangeCount": pasteboardChangeCount as Any,
                "pinned": pinned,
                "content": "<redacted>",
            ],
            displayStyle: .struct
        )
    }
}
