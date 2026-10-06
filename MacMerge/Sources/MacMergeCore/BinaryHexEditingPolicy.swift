import Foundation

public enum BinaryHexPane: Int, CaseIterable, Equatable, Hashable, Sendable {
    case left
    case middle
    case right
}

public struct BinaryHexContentIdentity: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        rawValue = UUID()
    }
}

/// Exact owner-issued state version. An owner must never reuse one `(identity, revision)` pair for
/// different bytes, persisted bytes, selection, settings, editability, or dirty state.
public struct BinaryHexContentVersion: Equatable, Hashable, Sendable {
    public let identity: BinaryHexContentIdentity
    public let revision: UInt64

    public init(identity: BinaryHexContentIdentity, revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

public enum BinaryHexSelectionSurface: String, CaseIterable, Equatable, Hashable, Sendable {
    case bytes
    case characters
}

/// Both hex-byte and character-pane selections use zero-based, half-open byte coordinates.
/// `surface` records which native pane owns focus; no text decoding is required to preserve it.
public struct BinaryHexSelection: Equatable, Hashable, Sendable {
    public let byteRange: Range<Int>
    public let surface: BinaryHexSelectionSurface

    public init(
        byteRange: Range<Int>,
        surface: BinaryHexSelectionSurface = .bytes
    ) {
        self.byteRange = byteRange
        self.surface = surface
    }

    public init(byteOffset: Int, surface: BinaryHexSelectionSurface = .bytes) {
        self.init(byteRange: byteOffset..<byteOffset, surface: surface)
    }

    public var byteCount: Int {
        guard byteRange.upperBound >= byteRange.lowerBound else { return 0 }
        let (count, overflow) = byteRange.upperBound.subtractingReportingOverflow(
            byteRange.lowerBound
        )
        return overflow ? .max : count
    }
    public var isEmpty: Bool { byteRange.isEmpty }
    public var insertionOffset: Int { byteRange.lowerBound }
}

public enum BinaryHexCharacterSet: String, CaseIterable, Equatable, Hashable, Sendable {
    case ascii
    case isoLatin1
    case windows1252
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
}

public enum BinaryHexOffsetRadix: String, CaseIterable, Equatable, Hashable, Sendable {
    case hexadecimal
    case decimal
}

public enum BinaryHexEditMode: String, CaseIterable, Equatable, Hashable, Sendable {
    case insert
    case overwrite
}

/// Settings consumed by a future native renderer. The 256-byte row ceiling deliberately matches
/// `BinaryHexPresentation`'s bounded row model without depending on its fixed ASCII formatting.
public struct BinaryHexDisplaySettings: Equatable, Hashable, Sendable {
    public static let maximumBytesPerRow = 256
    public static let `default` = BinaryHexDisplaySettings()

    public let bytesPerRow: Int
    public let byteGroupSize: Int
    public let characterSet: BinaryHexCharacterSet
    public let offsetRadix: BinaryHexOffsetRadix
    public let usesUppercaseHex: Bool
    public let showsOffsetColumn: Bool
    public let showsCharacterColumn: Bool
    public let editMode: BinaryHexEditMode

    public init(
        bytesPerRow: Int = 16,
        byteGroupSize: Int = 1,
        characterSet: BinaryHexCharacterSet = .ascii,
        offsetRadix: BinaryHexOffsetRadix = .hexadecimal,
        usesUppercaseHex: Bool = true,
        showsOffsetColumn: Bool = true,
        showsCharacterColumn: Bool = true,
        editMode: BinaryHexEditMode = .overwrite
    ) {
        self.bytesPerRow = bytesPerRow
        self.byteGroupSize = byteGroupSize
        self.characterSet = characterSet
        self.offsetRadix = offsetRadix
        self.usesUppercaseHex = usesUppercaseHex
        self.showsOffsetColumn = showsOffsetColumn
        self.showsCharacterColumn = showsCharacterColumn
        self.editMode = editMode
    }
}

/// Immutable pane state captured at a policy boundary. `data` and `persistedData` mirror
/// `BinaryFileDocument`'s current and saved bytes, while I/O remains outside this policy.
public struct BinaryHexPaneSnapshot: Equatable, Hashable, Sendable {
    public let pane: BinaryHexPane
    public let version: BinaryHexContentVersion
    public let data: Data
    public let persistedData: Data
    public let maximumByteCount: Int
    public let selection: BinaryHexSelection
    public let displaySettings: BinaryHexDisplaySettings
    public let isReadOnly: Bool
    public let isDirty: Bool

    public init(
        pane: BinaryHexPane,
        version: BinaryHexContentVersion,
        data: Data,
        persistedData: Data,
        maximumByteCount: Int = BinaryFileDocumentIO.maximumFileSize,
        selection: BinaryHexSelection = BinaryHexSelection(byteOffset: 0),
        displaySettings: BinaryHexDisplaySettings = .default,
        isReadOnly: Bool = false,
        isDirty: Bool
    ) {
        self.pane = pane
        self.version = version
        self.data = data
        self.persistedData = persistedData
        self.maximumByteCount = maximumByteCount
        self.selection = selection
        self.displaySettings = displaySettings
        self.isReadOnly = isReadOnly
        self.isDirty = isDirty
    }

    public init(
        pane: BinaryHexPane,
        version: BinaryHexContentVersion,
        document: BinaryFileDocument,
        selection: BinaryHexSelection = BinaryHexSelection(byteOffset: 0),
        displaySettings: BinaryHexDisplaySettings = .default,
        isReadOnly: Bool = false
    ) {
        self.init(
            pane: pane,
            version: version,
            data: document.data,
            persistedData: document.persistedData,
            maximumByteCount: document.maximumByteCount,
            selection: selection,
            displaySettings: displaySettings,
            isReadOnly: isReadOnly,
            isDirty: document.isDirty
        )
    }
}

public struct BinaryHexPolicyLimits: Equatable, Hashable, Sendable {
    public static let `default` = BinaryHexPolicyLimits()

    public let maximumInputBytes: Int
    public let maximumPersistedBytes: Int
    public let maximumPayloadBytes: Int
    public let maximumCharacterInputUTF8Bytes: Int
    public let maximumPatternBytes: Int
    public let maximumOutputBytes: Int
    public let maximumReplacements: Int
    public let maximumPlanBytes: Int
    public let maximumWork: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumInputBytes: Int = 64 * 1_024 * 1_024,
        maximumPersistedBytes: Int = 64 * 1_024 * 1_024,
        maximumPayloadBytes: Int = 64 * 1_024 * 1_024,
        maximumCharacterInputUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumPatternBytes: Int = 1 * 1_024 * 1_024,
        maximumOutputBytes: Int = 64 * 1_024 * 1_024,
        maximumReplacements: Int = 100_000,
        maximumPlanBytes: Int = 512 * 1_024 * 1_024,
        maximumWork: Int = 768 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 4_096
    ) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumPersistedBytes = maximumPersistedBytes
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumCharacterInputUTF8Bytes = maximumCharacterInputUTF8Bytes
        self.maximumPatternBytes = maximumPatternBytes
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumReplacements = maximumReplacements
        self.maximumPlanBytes = maximumPlanBytes
        self.maximumWork = maximumWork
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum BinaryHexPayload: Hashable, Sendable {
    case bytes(Data)
    case characters(String)

    public static func == (lhs: BinaryHexPayload, rhs: BinaryHexPayload) -> Bool {
        switch (lhs, rhs) {
        case (.bytes(let lhs), .bytes(let rhs)):
            lhs == rhs
        case (.characters(let lhs), .characters(let rhs)):
            binaryHexStringsAreScalarIdentical(lhs, rhs)
        case (.bytes, .characters), (.characters, .bytes):
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .bytes(let data):
            hasher.combine(0)
            hasher.combine(data)
        case .characters(let text):
            hasher.combine(1)
            for scalar in text.unicodeScalars { hasher.combine(scalar.value) }
        }
    }
}

public enum BinaryHexSearchPattern: Hashable, Sendable {
    case bytes(Data)
    case characters(String)

    public static func == (lhs: BinaryHexSearchPattern, rhs: BinaryHexSearchPattern) -> Bool {
        switch (lhs, rhs) {
        case (.bytes(let lhs), .bytes(let rhs)):
            lhs == rhs
        case (.characters(let lhs), .characters(let rhs)):
            binaryHexStringsAreScalarIdentical(lhs, rhs)
        case (.bytes, .characters), (.characters, .bytes):
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .bytes(let data):
            hasher.combine(0)
            hasher.combine(data)
        case .characters(let text):
            hasher.combine(1)
            for scalar in text.unicodeScalars { hasher.combine(scalar.value) }
        }
    }

    public var selectionSurface: BinaryHexSelectionSurface {
        switch self {
        case .bytes: .bytes
        case .characters: .characters
        }
    }
}

public enum BinaryHexSelectionIntent: Equatable, Hashable, Sendable {
    case set(BinaryHexSelection)
    case selectAll(surface: BinaryHexSelectionSurface)
}

public enum BinaryHexEditTarget: Equatable, Hashable, Sendable {
    case currentSelection
    case selection(BinaryHexSelection)
    case byteOffset(Int)
}

public enum BinaryHexEditIntent: Equatable, Hashable, Sendable {
    /// At an offset, inserts bytes. At a selection, replaces its complete byte range.
    case insert(payload: BinaryHexPayload, target: BinaryHexEditTarget)
    /// At an offset, replaces exactly `payload.count` bytes. At a selection, payload size must match.
    case overwrite(payload: BinaryHexPayload, target: BinaryHexEditTarget)
    case delete(selection: BinaryHexSelection? = nil)
}

public enum BinaryHexSearchDirection: String, CaseIterable, Equatable, Hashable, Sendable {
    case forward
    case backward
}

public struct BinaryHexFindIntent: Equatable, Hashable, Sendable {
    public let pattern: BinaryHexSearchPattern
    public let direction: BinaryHexSearchDirection
    /// `nil` starts after or before current selection according to `direction`.
    public let startByteOffset: Int?
    public let wraps: Bool

    public init(
        pattern: BinaryHexSearchPattern,
        direction: BinaryHexSearchDirection = .forward,
        startByteOffset: Int? = nil,
        wraps: Bool = true
    ) {
        self.pattern = pattern
        self.direction = direction
        self.startByteOffset = startByteOffset
        self.wraps = wraps
    }
}

public enum BinaryHexReplacementScope: Equatable, Hashable, Sendable {
    case currentSelection
    case first(fromByteOffset: Int? = nil, wraps: Bool = true)
    case all
}

public struct BinaryHexReplaceIntent: Equatable, Hashable, Sendable {
    public let pattern: BinaryHexSearchPattern
    public let replacement: BinaryHexPayload
    public let scope: BinaryHexReplacementScope

    public init(
        pattern: BinaryHexSearchPattern,
        replacement: BinaryHexPayload,
        scope: BinaryHexReplacementScope
    ) {
        self.pattern = pattern
        self.replacement = replacement
        self.scope = scope
    }
}

public enum BinaryHexGoToTarget: Hashable, Sendable {
    case byteOffset(Int)
    /// Zero-based row and byte column using current `bytesPerRow`.
    case row(index: Int, column: Int)
    case percent(Double)
    case end
}

public struct BinaryHexGoToIntent: Equatable, Hashable, Sendable {
    public let target: BinaryHexGoToTarget
    public let surface: BinaryHexSelectionSurface

    public init(
        target: BinaryHexGoToTarget,
        surface: BinaryHexSelectionSurface = .bytes
    ) {
        self.target = target
        self.surface = surface
    }
}

public enum BinaryHexIntent: Equatable, Hashable, Sendable {
    case selection(BinaryHexSelectionIntent)
    case edit(BinaryHexEditIntent)
    case find(BinaryHexFindIntent)
    case replace(BinaryHexReplaceIntent)
    case goTo(BinaryHexGoToIntent)
    case displaySettings(BinaryHexDisplaySettings)
}

public struct BinaryHexMutation: Equatable, Hashable, Sendable {
    public let sourceRange: Range<Int>
    public let replacementData: Data
    public let resultRange: Range<Int>

    fileprivate init(
        sourceRange: Range<Int>,
        replacementData: Data,
        resultRange: Range<Int>
    ) {
        self.sourceRange = sourceRange
        self.replacementData = replacementData
        self.resultRange = resultRange
    }
}

public enum BinaryHexNoOpReason: Equatable, Hashable, Sendable {
    case selectionUnchanged
    case emptyPayload
    case patternNotFound
    case replacementIdentical
    case destinationUnchanged
    case displaySettingsUnchanged
}

public struct BinaryHexPaneStatus: Equatable, Hashable, Sendable {
    public let pane: BinaryHexPane
    public let sourceVersion: BinaryHexContentVersion
    /// True when applying projected state requires an owner-issued successor revision.
    public let requiresNewRevision: Bool
    public let byteCount: Int
    public let byteOffset: Int
    /// Zero-based row and byte column.
    public let row: Int
    public let column: Int
    public let selection: BinaryHexSelection
    public let currentByte: UInt8?
    public let characterSet: BinaryHexCharacterSet
    public let editMode: BinaryHexEditMode
    public let isReadOnly: Bool
    public let isDirty: Bool

    public var selectedByteCount: Int { selection.byteCount }
    public var isInsertionPoint: Bool { selection.isEmpty }
}

/// State an executor must install atomically. Revision allocation remains owner-controlled.
public struct BinaryHexExecutionState: Equatable, Hashable, Sendable {
    public let data: Data
    public let persistedData: Data
    public let maximumByteCount: Int
    public let selection: BinaryHexSelection
    public let displaySettings: BinaryHexDisplaySettings
    public let isReadOnly: Bool
    public let isDirty: Bool

    fileprivate init(snapshot: BinaryHexPaneSnapshot) {
        data = snapshot.data
        persistedData = snapshot.persistedData
        maximumByteCount = snapshot.maximumByteCount
        selection = snapshot.selection
        displaySettings = snapshot.displaySettings
        isReadOnly = snapshot.isReadOnly
        isDirty = snapshot.isDirty
    }

    fileprivate init(
        source: BinaryHexPaneSnapshot,
        data: Data,
        selection: BinaryHexSelection,
        displaySettings: BinaryHexDisplaySettings,
        isDirty: Bool
    ) {
        self.data = data
        persistedData = source.persistedData
        maximumByteCount = source.maximumByteCount
        self.selection = selection
        self.displaySettings = displaySettings
        isReadOnly = source.isReadOnly
        self.isDirty = isDirty
    }
}

/// Stable, non-security identifier over exact plan inputs and outputs. CAS correctness never relies
/// on collision resistance; executors still compare complete `expectedPane` state byte-for-byte.
public struct BinaryHexPlanFingerprint: Equatable, Hashable, Sendable {
    public let low: UInt64
    public let high: UInt64

    fileprivate init(low: UInt64, high: UInt64) {
        self.low = low
        self.high = high
    }
}

public struct BinaryHexExecutionTransaction: Equatable, Hashable, Sendable {
    public let fingerprint: BinaryHexPlanFingerprint
    public let intent: BinaryHexIntent
    public let expectedPane: BinaryHexPaneSnapshot
    public let executionState: BinaryHexExecutionState
    public let mutations: [BinaryHexMutation]
    public let replacementCount: Int
    public let didWrap: Bool
    public let workUnitsConsumed: Int
    public let limits: BinaryHexPolicyLimits
    /// True exactly when owner must issue a fresh, never-reused revision before commit.
    public let requiresNewRevision: Bool

    fileprivate init(
        fingerprint: BinaryHexPlanFingerprint,
        intent: BinaryHexIntent,
        expectedPane: BinaryHexPaneSnapshot,
        executionState: BinaryHexExecutionState,
        mutations: [BinaryHexMutation],
        replacementCount: Int,
        didWrap: Bool,
        workUnitsConsumed: Int,
        limits: BinaryHexPolicyLimits,
        requiresNewRevision: Bool
    ) {
        self.fingerprint = fingerprint
        self.intent = intent
        self.expectedPane = expectedPane
        self.executionState = executionState
        self.mutations = mutations
        self.replacementCount = replacementCount
        self.didWrap = didWrap
        self.workUnitsConsumed = workUnitsConsumed
        self.limits = limits
        self.requiresNewRevision = requiresNewRevision
    }
}

public struct BinaryHexExecutionReceipt: Equatable, Hashable, Sendable {
    public let fingerprint: BinaryHexPlanFingerprint
    public let sourceVersion: BinaryHexContentVersion
    public let committedPane: BinaryHexPaneSnapshot
    public let mutationCount: Int
    public let replacementCount: Int
    public let workUnitsConsumed: Int

    /// Executor-facing initializer. Policy validates every field before returning a receipt.
    public init(
        transaction: BinaryHexExecutionTransaction,
        committedPane: BinaryHexPaneSnapshot
    ) {
        fingerprint = transaction.fingerprint
        sourceVersion = transaction.expectedPane.version
        self.committedPane = committedPane
        mutationCount = transaction.mutations.count
        replacementCount = transaction.replacementCount
        workUnitsConsumed = transaction.workUnitsConsumed
    }
}

public enum BinaryHexExecutionOutcome: Equatable, Hashable, Sendable {
    case committed(BinaryHexExecutionReceipt)
    /// Executor observed this complete live state and committed nothing.
    case notCommitted(currentPane: BinaryHexPaneSnapshot)
}

/// Atomic in-memory mutation boundary. Implementation must synchronously, without suspension:
///
/// 1. Compare complete live pane state with `transaction.expectedPane`, including exact bytes.
/// 2. On mismatch, commit nothing and return one same-isolation-turn live snapshot.
/// 3. On match, install all `executionState` fields atomically. When `requiresNewRevision` is true,
///    preserve identity and issue a never-reused revision; otherwise preserve the complete version.
/// 4. Return a receipt built from the transaction and exact committed snapshot.
///
/// All owned-state mutation must use this actor. A conforming executor performs no UI, filesystem,
/// pasteboard, text parsing, or implicit character-set detection. It enforces transaction limits,
/// checks cancellation while comparing large buffers, and never reports partial application. It may
/// throw `.cancelled` only before commit; after commit it must return the committed outcome.
public protocol BinaryHexPlanExecutor: Actor {
    func compareAndExecute(
        _ transaction: BinaryHexExecutionTransaction
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionOutcome
}

public enum BinaryHexComparisonSide: Equatable, Hashable, Sendable {
    case left
    case right
}

public enum BinaryHexPolicyError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case inputTooLarge(maximumBytes: Int)
    case persistedDataTooLarge(maximumBytes: Int)
    case invalidMaximumByteCount(Int)
    case invalidSelection(range: Range<Int>, byteCount: Int)
    case invalidDisplaySettings
    case readOnlyPane(BinaryHexPane)
    case payloadTooLarge(maximumBytes: Int)
    case characterInputTooLarge(maximumUTF8Bytes: Int)
    case characterNotRepresentable(characterSet: BinaryHexCharacterSet, scalar: UInt32)
    case emptySearchPattern
    case patternTooLarge(maximumBytes: Int)
    case invalidByteOffset(offset: Int, byteCount: Int)
    case invalidRow(index: Int, column: Int)
    case nonFinitePercent
    case percentOutsideRange(Double)
    case overwriteBeyondEnd(range: Range<Int>, byteCount: Int)
    case overwriteSelectionLengthMismatch(selectionBytes: Int, payloadBytes: Int)
    case tooManyReplacements(maximum: Int)
    case outputTooLarge(maximumBytes: Int)
    case planTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumWork: Int)
    case inconsistentDirtyState
    case contentIdentityChanged(expected: BinaryHexContentIdentity, actual: BinaryHexContentIdentity)
    case revisionChanged(expected: UInt64, actual: UInt64)
    case paneChanged(expected: BinaryHexPane, actual: BinaryHexPane)
    case contentChanged
    case persistedDataChanged
    case selectionChanged
    case displaySettingsChanged
    case readOnlyStateChanged
    case dirtyStateChanged
    case maximumByteCountChanged
    case inconsistentCommitOutcome
    case inconsistentReceipt
    case inconsistentPlan
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Binary hex policy limits are invalid."
        case .inputTooLarge(let maximumBytes):
            "Binary input exceeds the \(maximumBytes)-byte limit."
        case .persistedDataTooLarge(let maximumBytes):
            "Persisted binary input exceeds the \(maximumBytes)-byte limit."
        case .invalidMaximumByteCount(let count):
            "Binary pane maximum byte count is invalid: \(count)."
        case .invalidSelection(let range, let byteCount):
            "Byte selection \(range.lowerBound)..<\(range.upperBound) is outside the \(byteCount)-byte pane."
        case .invalidDisplaySettings:
            "Binary hex display settings are invalid."
        case .readOnlyPane(let pane):
            "Binary hex pane \(pane) is read only."
        case .payloadTooLarge(let maximumBytes):
            "Binary edit payload exceeds the \(maximumBytes)-byte limit."
        case .characterInputTooLarge(let maximumUTF8Bytes):
            "Character input exceeds the \(maximumUTF8Bytes)-byte UTF-8 limit."
        case .characterNotRepresentable(let characterSet, let scalar):
            "Unicode scalar U+\(String(scalar, radix: 16, uppercase: true)) is not representable in \(characterSet.rawValue)."
        case .emptySearchPattern:
            "Binary search pattern must not be empty."
        case .patternTooLarge(let maximumBytes):
            "Binary search pattern exceeds the \(maximumBytes)-byte limit."
        case .invalidByteOffset(let offset, let byteCount):
            "Byte offset \(offset) is outside 0...\(byteCount)."
        case .invalidRow(let index, let column):
            "Binary row destination (\(index), \(column)) is invalid."
        case .nonFinitePercent:
            "Binary Go To percentage must be finite."
        case .percentOutsideRange(let percent):
            "Binary Go To percentage \(percent) is outside 0...100."
        case .overwriteBeyondEnd(let range, let byteCount):
            "Overwrite range \(range.lowerBound)..<\(range.upperBound) exceeds the \(byteCount)-byte pane."
        case .overwriteSelectionLengthMismatch(let selectionBytes, let payloadBytes):
            "Overwrite selection has \(selectionBytes) bytes, but payload has \(payloadBytes) bytes."
        case .tooManyReplacements(let maximum):
            "Binary replacement exceeds the \(maximum)-replacement limit."
        case .outputTooLarge(let maximumBytes):
            "Binary edit output exceeds the \(maximumBytes)-byte limit."
        case .planTooLarge(let maximumBytes):
            "Binary edit plan exceeds the \(maximumBytes)-byte retained-data limit."
        case .workLimitExceeded(let maximumWork):
            "Binary hex operation exceeds the \(maximumWork)-unit work limit."
        case .inconsistentDirtyState:
            "Binary pane dirty state does not match its current and persisted bytes."
        case .contentIdentityChanged:
            "Binary hex plan belongs to another content identity."
        case .revisionChanged(let expected, let actual):
            "Binary hex plan was created for revision \(expected), not revision \(actual)."
        case .paneChanged(let expected, let actual):
            "Binary hex plan moved from pane \(expected) to pane \(actual)."
        case .contentChanged:
            "Binary pane bytes changed without a matching revision change."
        case .persistedDataChanged:
            "Binary pane persisted bytes changed without a matching revision change."
        case .selectionChanged:
            "Binary pane selection changed before plan execution."
        case .displaySettingsChanged:
            "Binary pane display settings changed before plan execution."
        case .readOnlyStateChanged:
            "Binary pane read-only state changed before plan execution."
        case .dirtyStateChanged:
            "Binary pane dirty state changed before plan execution."
        case .maximumByteCountChanged:
            "Binary pane byte limit changed before plan execution."
        case .inconsistentCommitOutcome:
            "Binary executor rejected a transaction without reporting a live-state mismatch."
        case .inconsistentReceipt:
            "Binary executor returned a receipt that does not match the planned result."
        case .inconsistentPlan:
            "Binary hex policy produced an inconsistent plan."
        case .cancelled:
            "Binary hex operation was cancelled."
        }
    }
}

public struct BinaryHexEditingPlan: Equatable, Hashable, Sendable {
    public let fingerprint: BinaryHexPlanFingerprint
    public let intent: BinaryHexIntent
    public let sourcePane: BinaryHexPaneSnapshot
    public let executionState: BinaryHexExecutionState
    public let mutations: [BinaryHexMutation]
    public let replacementCount: Int
    public let didWrap: Bool
    public let noOpReason: BinaryHexNoOpReason?
    public let statusBefore: BinaryHexPaneStatus
    public let statusAfter: BinaryHexPaneStatus
    public let workUnitsConsumed: Int
    public let retainedByteCount: Int

    public let limits: BinaryHexPolicyLimits

    public var resultData: Data { executionState.data }
    public var resultSelection: BinaryHexSelection { executionState.selection }
    public var resultDisplaySettings: BinaryHexDisplaySettings { executionState.displaySettings }
    public let didChangeContent: Bool
    public var didChangeSelection: Bool { sourcePane.selection != executionState.selection }
    public var didChangeDisplaySettings: Bool {
        sourcePane.displaySettings != executionState.displaySettings
    }
    public var hasEffect: Bool { statusAfter.requiresNewRevision }
    public var isNoOp: Bool { !hasEffect }

    public var transaction: BinaryHexExecutionTransaction {
        BinaryHexExecutionTransaction(
            fingerprint: fingerprint,
            intent: intent,
            expectedPane: sourcePane,
            executionState: executionState,
            mutations: mutations,
            replacementCount: replacementCount,
            didWrap: didWrap,
            workUnitsConsumed: workUnitsConsumed,
            limits: limits,
            requiresNewRevision: hasEffect
        )
    }

    fileprivate init(
        fingerprint: BinaryHexPlanFingerprint,
        intent: BinaryHexIntent,
        sourcePane: BinaryHexPaneSnapshot,
        executionState: BinaryHexExecutionState,
        mutations: [BinaryHexMutation],
        replacementCount: Int,
        didWrap: Bool,
        noOpReason: BinaryHexNoOpReason?,
        statusBefore: BinaryHexPaneStatus,
        statusAfter: BinaryHexPaneStatus,
        didChangeContent: Bool,
        workUnitsConsumed: Int,
        retainedByteCount: Int,
        limits: BinaryHexPolicyLimits
    ) {
        self.fingerprint = fingerprint
        self.intent = intent
        self.sourcePane = sourcePane
        self.executionState = executionState
        self.mutations = mutations
        self.replacementCount = replacementCount
        self.didWrap = didWrap
        self.noOpReason = noOpReason
        self.statusBefore = statusBefore
        self.statusAfter = statusAfter
        self.didChangeContent = didChangeContent
        self.workUnitsConsumed = workUnitsConsumed
        self.retainedByteCount = retainedByteCount
        self.limits = limits
    }

    /// Executes one synchronous actor-isolated CAS and validates exact committed state.
    public func execute<Executor: BinaryHexPlanExecutor>(
        on executor: isolated Executor
    ) throws(BinaryHexPolicyError) -> BinaryHexExecutionReceipt {
        try binaryHexCheckCancellation()
        let outcome = try executor.compareAndExecute(transaction)
        switch outcome {
        case .notCommitted(let currentPane):
            try validateConflict(currentPane)
            throw BinaryHexPolicyError.inconsistentCommitOutcome
        case .committed(let receipt):
            try validate(receipt)
            return receipt
        }
    }

    private func validateConflict(
        _ current: BinaryHexPaneSnapshot
    ) throws(BinaryHexPolicyError) {
        guard current.pane == sourcePane.pane else {
            throw BinaryHexPolicyError.paneChanged(expected: sourcePane.pane, actual: current.pane)
        }
        guard current.version.identity == sourcePane.version.identity else {
            throw BinaryHexPolicyError.contentIdentityChanged(
                expected: sourcePane.version.identity,
                actual: current.version.identity
            )
        }
        guard current.version.revision == sourcePane.version.revision else {
            throw BinaryHexPolicyError.revisionChanged(
                expected: sourcePane.version.revision,
                actual: current.version.revision
            )
        }
        var work = BinaryHexWorkBudget(limits: limits)
        guard try binaryHexDataAreEqual(current.data, sourcePane.data, work: &work) else {
            throw BinaryHexPolicyError.contentChanged
        }
        guard
            try binaryHexDataAreEqual(
                current.persistedData,
                sourcePane.persistedData,
                work: &work
            )
        else {
            throw BinaryHexPolicyError.persistedDataChanged
        }
        guard current.selection == sourcePane.selection else {
            throw BinaryHexPolicyError.selectionChanged
        }
        guard current.displaySettings == sourcePane.displaySettings else {
            throw BinaryHexPolicyError.displaySettingsChanged
        }
        guard current.isReadOnly == sourcePane.isReadOnly else {
            throw BinaryHexPolicyError.readOnlyStateChanged
        }
        guard current.isDirty == sourcePane.isDirty else {
            throw BinaryHexPolicyError.dirtyStateChanged
        }
        guard current.maximumByteCount == sourcePane.maximumByteCount else {
            throw BinaryHexPolicyError.maximumByteCountChanged
        }
    }

    private func validate(
        _ receipt: BinaryHexExecutionReceipt
    ) throws(BinaryHexPolicyError) {
        guard receipt.fingerprint == fingerprint,
            receipt.sourceVersion == sourcePane.version,
            receipt.mutationCount == mutations.count,
            receipt.replacementCount == replacementCount,
            receipt.workUnitsConsumed == workUnitsConsumed
        else {
            throw BinaryHexPolicyError.inconsistentReceipt
        }
        let committed = receipt.committedPane
        guard committed.pane == sourcePane.pane,
            committed.version.identity == sourcePane.version.identity,
            committed.version.revision == sourcePane.version.revision || hasEffect,
            committed.version.revision != sourcePane.version.revision || !hasEffect,
            BinaryHexExecutionState(snapshot: committed) == executionState
        else {
            throw BinaryHexPolicyError.inconsistentReceipt
        }
    }
}

/// UI-independent planner for byte-native hex panes. It does not load, save, parse structured
/// binary formats, inspect pasteboards, or choose encodings heuristically.
public enum BinaryHexEditingPolicy: Sendable {
    public static func plan(
        _ intent: BinaryHexIntent,
        in pane: BinaryHexPaneSnapshot,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexEditingPlan {
        try validate(limits)
        var work = BinaryHexWorkBudget(limits: limits)
        try work.checkCancellation()
        try validate(pane, work: &work)

        let draft: BinaryHexDraft
        switch intent {
        case .selection(let selection):
            draft = try selectionDraft(selection, pane: pane)
        case .edit(let edit):
            guard !pane.isReadOnly else { throw BinaryHexPolicyError.readOnlyPane(pane.pane) }
            draft = try editDraft(edit, pane: pane, limits: limits, work: &work)
        case .find(let find):
            draft = try findDraft(find, pane: pane, limits: limits, work: &work)
        case .replace(let replace):
            guard !pane.isReadOnly else { throw BinaryHexPolicyError.readOnlyPane(pane.pane) }
            draft = try replaceDraft(replace, pane: pane, limits: limits, work: &work)
        case .goTo(let goTo):
            draft = try goToDraft(goTo, pane: pane)
        case .displaySettings(let settings):
            try validate(settings)
            draft = BinaryHexDraft(
                data: pane.data,
                selection: pane.selection,
                displaySettings: settings,
                mutations: [],
                replacementCount: 0,
                didWrap: false,
                noOpReason: settings == pane.displaySettings ? .displaySettingsUnchanged : nil
            )
        }

        try validate(draft.selection, byteCount: draft.data.count)
        try validate(draft.displaySettings)
        let contentChanged = try !binaryHexDataAreEqual(draft.data, pane.data, work: &work)
        if contentChanged {
            let maximumOutputBytes = min(pane.maximumByteCount, limits.maximumOutputBytes)
            guard draft.data.count <= maximumOutputBytes else {
                throw BinaryHexPolicyError.outputTooLarge(maximumBytes: maximumOutputBytes)
            }
        }
        let isDirty = try !binaryHexDataAreEqual(draft.data, pane.persistedData, work: &work)
        let executionState = BinaryHexExecutionState(
            source: pane,
            data: draft.data,
            selection: draft.selection,
            displaySettings: draft.displaySettings,
            isDirty: isDirty
        )
        let retainedByteCount = try retainedBytes(
            intent: intent,
            source: pane,
            executionState: executionState,
            mutations: draft.mutations,
            maximum: limits.maximumPlanBytes,
            work: &work
        )
        let fingerprint = try fingerprint(
            intent: intent,
            source: pane,
            executionState: executionState,
            mutations: draft.mutations,
            replacementCount: draft.replacementCount,
            didWrap: draft.didWrap,
            limits: limits,
            work: &work
        )
        let statusBefore = status(
            pane: pane.pane,
            version: pane.version,
            state: BinaryHexExecutionState(snapshot: pane),
            requiresNewRevision: false
        )
        let statusAfter = status(
            pane: pane.pane,
            version: pane.version,
            state: executionState,
            requiresNewRevision: contentChanged
                || executionState.selection != pane.selection
                || executionState.displaySettings != pane.displaySettings
                || executionState.isDirty != pane.isDirty
        )
        try work.checkCancellation()
        return BinaryHexEditingPlan(
            fingerprint: fingerprint,
            intent: intent,
            sourcePane: pane,
            executionState: executionState,
            mutations: draft.mutations,
            replacementCount: draft.replacementCount,
            didWrap: draft.didWrap,
            noOpReason: draft.noOpReason,
            statusBefore: statusBefore,
            statusAfter: statusAfter,
            didChangeContent: contentChanged,
            workUnitsConsumed: work.consumed,
            retainedByteCount: retainedByteCount,
            limits: limits
        )
    }

    public static func status(
        for pane: BinaryHexPaneSnapshot,
        limits: BinaryHexPolicyLimits = .default
    ) throws(BinaryHexPolicyError) -> BinaryHexPaneStatus {
        try validate(limits)
        var work = BinaryHexWorkBudget(limits: limits)
        try validate(pane, work: &work)
        try work.checkCancellation()
        return status(
            pane: pane.pane,
            version: pane.version,
            state: BinaryHexExecutionState(snapshot: pane),
            requiresNewRevision: false
        )
    }

    /// Maps an aligned comparison location back to one source without treating alignment gaps as
    /// bytes. End-of-comparison maps to source EOF. This is the only comparison-coordinate bridge.
    public static func selection(
        atAlignedOffset offset: Int,
        side: BinaryHexComparisonSide,
        in comparison: BinaryComparisonResult,
        surface: BinaryHexSelectionSurface = .bytes
    ) throws(BinaryHexPolicyError) -> BinaryHexSelection {
        guard offset >= 0, offset <= comparison.alignedByteCount else {
            throw BinaryHexPolicyError.invalidByteOffset(
                offset: offset,
                byteCount: comparison.alignedByteCount
            )
        }
        if offset == comparison.alignedByteCount {
            let sourceCount = side == .left ? comparison.leftData.count : comparison.rightData.count
            return BinaryHexSelection(byteOffset: sourceCount, surface: surface)
        }
        guard let offsets = comparison.sourceOffsets(atAlignedOffset: offset) else {
            throw BinaryHexPolicyError.inconsistentPlan
        }
        let sourceOffset = side == .left ? offsets.left : offsets.right
        return BinaryHexSelection(byteOffset: sourceOffset, surface: surface)
    }

    private static func selectionDraft(
        _ intent: BinaryHexSelectionIntent,
        pane: BinaryHexPaneSnapshot
    ) throws(BinaryHexPolicyError) -> BinaryHexDraft {
        let selection: BinaryHexSelection
        switch intent {
        case .set(let requested):
            selection = requested
        case .selectAll(let surface):
            selection = BinaryHexSelection(byteRange: 0..<pane.data.count, surface: surface)
        }
        try validate(selection, byteCount: pane.data.count)
        return BinaryHexDraft(
            data: pane.data,
            selection: selection,
            displaySettings: pane.displaySettings,
            mutations: [],
            replacementCount: 0,
            didWrap: false,
            noOpReason: selection == pane.selection ? .selectionUnchanged : nil
        )
    }

    private static func editDraft(
        _ intent: BinaryHexEditIntent,
        pane: BinaryHexPaneSnapshot,
        limits: BinaryHexPolicyLimits,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> BinaryHexDraft {
        let sourceRange: Range<Int>
        let replacement: Data
        let resultSurface: BinaryHexSelectionSurface
        switch intent {
        case .insert(let payload, let target):
            replacement = try encoded(payload, settings: pane.displaySettings, limits: limits, work: &work)
            let resolved = try editTarget(target, pane: pane)
            sourceRange = resolved.selection?.byteRange ?? resolved.offset..<resolved.offset
            resultSurface = payload.surface
        case .overwrite(let payload, let target):
            replacement = try encoded(payload, settings: pane.displaySettings, limits: limits, work: &work)
            let resolved = try editTarget(target, pane: pane)
            if let selection = resolved.selection, !selection.isEmpty {
                guard selection.byteCount == replacement.count else {
                    throw BinaryHexPolicyError.overwriteSelectionLengthMismatch(
                        selectionBytes: selection.byteCount,
                        payloadBytes: replacement.count
                    )
                }
                sourceRange = selection.byteRange
            } else {
                let (upperBound, overflow) = resolved.offset.addingReportingOverflow(replacement.count)
                guard !overflow, upperBound <= pane.data.count else {
                    let reportedUpperBound = overflow ? Int.max : upperBound
                    throw BinaryHexPolicyError.overwriteBeyondEnd(
                        range: resolved.offset..<reportedUpperBound,
                        byteCount: pane.data.count
                    )
                }
                sourceRange = resolved.offset..<upperBound
            }
            resultSurface = payload.surface
        case .delete(let explicitSelection):
            let selection = explicitSelection ?? pane.selection
            try validate(selection, byteCount: pane.data.count)
            sourceRange = selection.byteRange
            replacement = Data()
            resultSurface = selection.surface
        }

        let mutation = try mutation(
            sourceRange: sourceRange,
            replacement: replacement,
            cumulativeDelta: 0
        )
        let outputCount = try outputByteCount(
            sourceCount: pane.data.count,
            mutations: [mutation],
            maximum: min(pane.maximumByteCount, limits.maximumOutputBytes),
            work: &work
        )
        let output = try apply([mutation], to: pane.data, outputCount: outputCount, work: &work)
        let selection = BinaryHexSelection(
            byteRange: mutation.resultRange.upperBound..<mutation.resultRange.upperBound,
            surface: resultSurface
        )
        let contentChanged = try !binaryHexDataAreEqual(output, pane.data, work: &work)
        let noOpReason: BinaryHexNoOpReason?
        if contentChanged || selection != pane.selection {
            noOpReason = nil
        } else if replacement.isEmpty && sourceRange.isEmpty {
            noOpReason = .emptyPayload
        } else {
            noOpReason = .replacementIdentical
        }
        return BinaryHexDraft(
            data: contentChanged ? output : pane.data,
            selection: selection,
            displaySettings: pane.displaySettings,
            mutations: [mutation],
            replacementCount: 1,
            didWrap: false,
            noOpReason: noOpReason
        )
    }

    private static func findDraft(
        _ intent: BinaryHexFindIntent,
        pane: BinaryHexPaneSnapshot,
        limits: BinaryHexPolicyLimits,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> BinaryHexDraft {
        let pattern = try encoded(intent.pattern, settings: pane.displaySettings, limits: limits, work: &work)
        let start = try searchStart(
            intent.startByteOffset,
            direction: intent.direction,
            selection: pane.selection,
            byteCount: pane.data.count
        )
        let result = try find(
            pattern,
            in: pane.data,
            direction: intent.direction,
            start: start,
            wraps: intent.wraps,
            work: &work
        )
        let selection =
            result.range.map {
                BinaryHexSelection(byteRange: $0, surface: intent.pattern.selectionSurface)
            } ?? pane.selection
        return BinaryHexDraft(
            data: pane.data,
            selection: selection,
            displaySettings: pane.displaySettings,
            mutations: [],
            replacementCount: 0,
            didWrap: result.didWrap,
            noOpReason: result.range == nil
                ? .patternNotFound
                : (selection == pane.selection ? .selectionUnchanged : nil)
        )
    }

    private static func replaceDraft(
        _ intent: BinaryHexReplaceIntent,
        pane: BinaryHexPaneSnapshot,
        limits: BinaryHexPolicyLimits,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> BinaryHexDraft {
        let pattern = try encoded(intent.pattern, settings: pane.displaySettings, limits: limits, work: &work)
        let replacement = try encoded(intent.replacement, settings: pane.displaySettings, limits: limits, work: &work)
        let ranges: [Range<Int>]
        let didWrap: Bool
        switch intent.scope {
        case .currentSelection:
            let range = pane.selection.byteRange
            guard try binaryHexRange(range, in: pane.data, equals: pattern, work: &work) else {
                ranges = []
                didWrap = false
                break
            }
            ranges = [range]
            didWrap = false
        case .first(let requestedOffset, let wraps):
            let start = try searchStart(
                requestedOffset,
                direction: .forward,
                selection: pane.selection,
                byteCount: pane.data.count
            )
            let result = try find(
                pattern,
                in: pane.data,
                direction: .forward,
                start: start,
                wraps: wraps,
                work: &work
            )
            ranges = result.range.map { [$0] } ?? []
            didWrap = result.didWrap
        case .all:
            ranges = try allNonoverlappingMatches(
                pattern,
                in: pane.data,
                maximumMatches: limits.maximumReplacements,
                work: &work
            )
            didWrap = false
        }

        guard !ranges.isEmpty else {
            return BinaryHexDraft(
                data: pane.data,
                selection: pane.selection,
                displaySettings: pane.displaySettings,
                mutations: [],
                replacementCount: 0,
                didWrap: didWrap,
                noOpReason: .patternNotFound
            )
        }
        guard ranges.count <= limits.maximumReplacements else {
            throw BinaryHexPolicyError.tooManyReplacements(maximum: limits.maximumReplacements)
        }
        var mutations: [BinaryHexMutation] = []
        mutations.reserveCapacity(ranges.count)
        var cumulativeDelta = 0
        for range in ranges {
            try work.consume(1)
            let next = try mutation(
                sourceRange: range,
                replacement: replacement,
                cumulativeDelta: cumulativeDelta
            )
            mutations.append(next)
            let (delta, deltaOverflow) = replacement.count.subtractingReportingOverflow(range.count)
            let (nextDelta, cumulativeOverflow) = cumulativeDelta.addingReportingOverflow(delta)
            guard !deltaOverflow, !cumulativeOverflow else {
                throw BinaryHexPolicyError.inconsistentPlan
            }
            cumulativeDelta = nextDelta
        }
        let outputCount = try outputByteCount(
            sourceCount: pane.data.count,
            mutations: mutations,
            maximum: min(pane.maximumByteCount, limits.maximumOutputBytes),
            work: &work
        )
        let output = try apply(mutations, to: pane.data, outputCount: outputCount, work: &work)
        let contentChanged = try !binaryHexDataAreEqual(output, pane.data, work: &work)
        let finalRange = mutations.last?.resultRange ?? pane.selection.byteRange
        let selection = BinaryHexSelection(
            byteRange: finalRange,
            surface: intent.replacement.surface
        )
        return BinaryHexDraft(
            data: contentChanged ? output : pane.data,
            selection: selection,
            displaySettings: pane.displaySettings,
            mutations: mutations,
            replacementCount: mutations.count,
            didWrap: didWrap,
            noOpReason: contentChanged || selection != pane.selection ? nil : .replacementIdentical
        )
    }

    private static func goToDraft(
        _ intent: BinaryHexGoToIntent,
        pane: BinaryHexPaneSnapshot
    ) throws(BinaryHexPolicyError) -> BinaryHexDraft {
        let offset: Int
        switch intent.target {
        case .byteOffset(let requested):
            offset = try validOffset(requested, byteCount: pane.data.count)
        case .row(let index, let column):
            guard index >= 0,
                column >= 0,
                column < pane.displaySettings.bytesPerRow
            else {
                throw BinaryHexPolicyError.invalidRow(index: index, column: column)
            }
            let (rowOffset, multiplicationOverflow) = index.multipliedReportingOverflow(
                by: pane.displaySettings.bytesPerRow
            )
            let (requested, additionOverflow) = rowOffset.addingReportingOverflow(column)
            guard !multiplicationOverflow, !additionOverflow, requested <= pane.data.count else {
                throw BinaryHexPolicyError.invalidRow(index: index, column: column)
            }
            offset = requested
        case .percent(let percent):
            guard percent.isFinite else { throw BinaryHexPolicyError.nonFinitePercent }
            guard (0...100).contains(percent) else {
                throw BinaryHexPolicyError.percentOutsideRange(percent)
            }
            if percent == 0 {
                offset = 0
            } else if percent == 100 {
                offset = pane.data.count
            } else {
                let rounded = (Double(pane.data.count) * percent / 100).rounded()
                offset = rounded >= Double(pane.data.count) ? pane.data.count : Int(rounded)
            }
        case .end:
            offset = pane.data.count
        }
        let selection = BinaryHexSelection(byteOffset: offset, surface: intent.surface)
        return BinaryHexDraft(
            data: pane.data,
            selection: selection,
            displaySettings: pane.displaySettings,
            mutations: [],
            replacementCount: 0,
            didWrap: false,
            noOpReason: selection == pane.selection ? .destinationUnchanged : nil
        )
    }

    private static func validate(
        _ limits: BinaryHexPolicyLimits
    ) throws(BinaryHexPolicyError) {
        guard limits.maximumInputBytes >= 0,
            limits.maximumPersistedBytes >= 0,
            limits.maximumPayloadBytes >= 0,
            limits.maximumCharacterInputUTF8Bytes >= 0,
            limits.maximumPatternBytes > 0,
            limits.maximumOutputBytes >= 0,
            limits.maximumReplacements > 0,
            limits.maximumPlanBytes >= 0,
            limits.maximumWork >= 0,
            limits.cancellationCheckInterval > 0
        else {
            throw BinaryHexPolicyError.invalidLimits
        }
    }

    private static func validate(
        _ pane: BinaryHexPaneSnapshot,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        guard pane.maximumByteCount >= 0 else {
            throw BinaryHexPolicyError.invalidMaximumByteCount(pane.maximumByteCount)
        }
        guard pane.data.count <= work.limits.maximumInputBytes else {
            throw BinaryHexPolicyError.inputTooLarge(maximumBytes: work.limits.maximumInputBytes)
        }
        guard pane.persistedData.count <= work.limits.maximumPersistedBytes else {
            throw BinaryHexPolicyError.persistedDataTooLarge(
                maximumBytes: work.limits.maximumPersistedBytes
            )
        }
        guard pane.data.count <= pane.maximumByteCount,
            pane.persistedData.count <= pane.maximumByteCount
        else {
            throw BinaryHexPolicyError.invalidMaximumByteCount(pane.maximumByteCount)
        }
        try validate(pane.selection, byteCount: pane.data.count)
        try validate(pane.displaySettings)
        let actualDirty = try !binaryHexDataAreEqual(pane.data, pane.persistedData, work: &work)
        guard actualDirty == pane.isDirty else {
            throw BinaryHexPolicyError.inconsistentDirtyState
        }
    }

    private static func validate(
        _ settings: BinaryHexDisplaySettings
    ) throws(BinaryHexPolicyError) {
        guard settings.bytesPerRow > 0,
            settings.bytesPerRow <= BinaryHexDisplaySettings.maximumBytesPerRow,
            settings.byteGroupSize > 0,
            settings.byteGroupSize <= settings.bytesPerRow,
            settings.bytesPerRow.isMultiple(of: settings.byteGroupSize)
        else {
            throw BinaryHexPolicyError.invalidDisplaySettings
        }
    }

    private static func validate(
        _ selection: BinaryHexSelection,
        byteCount: Int
    ) throws(BinaryHexPolicyError) {
        let range = selection.byteRange
        guard range.lowerBound >= 0,
            range.upperBound >= range.lowerBound,
            range.upperBound <= byteCount
        else {
            throw BinaryHexPolicyError.invalidSelection(range: range, byteCount: byteCount)
        }
    }

    private static func validOffset(
        _ offset: Int,
        byteCount: Int
    ) throws(BinaryHexPolicyError) -> Int {
        guard offset >= 0, offset <= byteCount else {
            throw BinaryHexPolicyError.invalidByteOffset(offset: offset, byteCount: byteCount)
        }
        return offset
    }

    private static func editTarget(
        _ target: BinaryHexEditTarget,
        pane: BinaryHexPaneSnapshot
    ) throws(BinaryHexPolicyError) -> (selection: BinaryHexSelection?, offset: Int) {
        switch target {
        case .currentSelection:
            try validate(pane.selection, byteCount: pane.data.count)
            return (pane.selection, pane.selection.byteRange.lowerBound)
        case .selection(let selection):
            try validate(selection, byteCount: pane.data.count)
            return (selection, selection.byteRange.lowerBound)
        case .byteOffset(let offset):
            return (nil, try validOffset(offset, byteCount: pane.data.count))
        }
    }

    private static func searchStart(
        _ requested: Int?,
        direction: BinaryHexSearchDirection,
        selection: BinaryHexSelection,
        byteCount: Int
    ) throws(BinaryHexPolicyError) -> Int {
        if let requested { return try validOffset(requested, byteCount: byteCount) }
        return direction == .forward ? selection.byteRange.upperBound : selection.byteRange.lowerBound
    }

    private static func encoded(
        _ payload: BinaryHexPayload,
        settings: BinaryHexDisplaySettings,
        limits: BinaryHexPolicyLimits,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> Data {
        let data: Data
        switch payload {
        case .bytes(let value):
            guard value.count <= limits.maximumPayloadBytes else {
                throw BinaryHexPolicyError.payloadTooLarge(maximumBytes: limits.maximumPayloadBytes)
            }
            try work.consume(value.count)
            data = value
        case .characters(let text):
            data = try encode(
                text,
                characterSet: settings.characterSet,
                maximumInputUTF8Bytes: limits.maximumCharacterInputUTF8Bytes,
                maximumOutputBytes: limits.maximumPayloadBytes,
                work: &work
            )
        }
        return data
    }

    private static func encoded(
        _ pattern: BinaryHexSearchPattern,
        settings: BinaryHexDisplaySettings,
        limits: BinaryHexPolicyLimits,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> Data {
        let data: Data
        switch pattern {
        case .bytes(let value):
            guard !value.isEmpty else { throw BinaryHexPolicyError.emptySearchPattern }
            guard value.count <= limits.maximumPatternBytes else {
                throw BinaryHexPolicyError.patternTooLarge(
                    maximumBytes: limits.maximumPatternBytes
                )
            }
            try work.consume(value.count)
            data = value
        case .characters(let text):
            do {
                data = try encode(
                    text,
                    characterSet: settings.characterSet,
                    maximumInputUTF8Bytes: limits.maximumCharacterInputUTF8Bytes,
                    maximumOutputBytes: limits.maximumPatternBytes,
                    work: &work
                )
            } catch BinaryHexPolicyError.payloadTooLarge {
                throw BinaryHexPolicyError.patternTooLarge(
                    maximumBytes: limits.maximumPatternBytes
                )
            }
        }
        guard !data.isEmpty else { throw BinaryHexPolicyError.emptySearchPattern }
        guard data.count <= limits.maximumPatternBytes else {
            throw BinaryHexPolicyError.patternTooLarge(maximumBytes: limits.maximumPatternBytes)
        }
        return data
    }

    private static func encode(
        _ text: String,
        characterSet: BinaryHexCharacterSet,
        maximumInputUTF8Bytes: Int,
        maximumOutputBytes: Int,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> Data {
        var output = Data()
        output.reserveCapacity(min(maximumOutputBytes, 4_096))
        var inputUTF8Bytes = 0

        func checkedAppend(_ bytes: [UInt8]) throws(BinaryHexPolicyError) {
            guard bytes.count <= maximumOutputBytes - output.count else {
                throw BinaryHexPolicyError.payloadTooLarge(maximumBytes: maximumOutputBytes)
            }
            try work.consume(bytes.count)
            output.append(contentsOf: bytes)
        }

        for scalar in text.unicodeScalars {
            let utf8Bytes = binaryHexUTF8Bytes(scalar.value)
            guard utf8Bytes.count <= maximumInputUTF8Bytes - inputUTF8Bytes else {
                throw BinaryHexPolicyError.characterInputTooLarge(
                    maximumUTF8Bytes: maximumInputUTF8Bytes
                )
            }
            inputUTF8Bytes += utf8Bytes.count
            try work.consume(utf8Bytes.count)

            let encoded: [UInt8]
            switch characterSet {
            case .ascii:
                guard scalar.value <= 0x7F else {
                    throw BinaryHexPolicyError.characterNotRepresentable(
                        characterSet: characterSet,
                        scalar: scalar.value
                    )
                }
                encoded = [UInt8(scalar.value)]
            case .isoLatin1:
                guard scalar.value <= 0xFF else {
                    throw BinaryHexPolicyError.characterNotRepresentable(
                        characterSet: characterSet,
                        scalar: scalar.value
                    )
                }
                encoded = [UInt8(scalar.value)]
            case .windows1252:
                guard let byte = binaryHexWindows1252Byte(scalar.value) else {
                    throw BinaryHexPolicyError.characterNotRepresentable(
                        characterSet: characterSet,
                        scalar: scalar.value
                    )
                }
                encoded = [byte]
            case .utf8:
                encoded = utf8Bytes
            case .utf16LittleEndian, .utf16BigEndian:
                let units = binaryHexUTF16Units(scalar.value)
                encoded = units.flatMap { unit in
                    let low = UInt8(truncatingIfNeeded: unit)
                    let high = UInt8(truncatingIfNeeded: unit >> 8)
                    return characterSet == .utf16LittleEndian ? [low, high] : [high, low]
                }
            }
            try checkedAppend(encoded)
        }
        try work.checkCancellation()
        return output
    }

    private static func mutation(
        sourceRange: Range<Int>,
        replacement: Data,
        cumulativeDelta: Int
    ) throws(BinaryHexPolicyError) -> BinaryHexMutation {
        let (resultStart, startOverflow) = sourceRange.lowerBound.addingReportingOverflow(
            cumulativeDelta
        )
        let (resultEnd, endOverflow) = resultStart.addingReportingOverflow(replacement.count)
        guard !startOverflow, !endOverflow, resultStart >= 0 else {
            throw BinaryHexPolicyError.inconsistentPlan
        }
        return BinaryHexMutation(
            sourceRange: sourceRange,
            replacementData: replacement,
            resultRange: resultStart..<resultEnd
        )
    }

    private static func outputByteCount(
        sourceCount: Int,
        mutations: [BinaryHexMutation],
        maximum: Int,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> Int {
        var count = sourceCount
        var previousUpperBound = 0
        for mutation in mutations {
            try work.consume(1)
            guard mutation.sourceRange.lowerBound >= previousUpperBound else {
                throw BinaryHexPolicyError.inconsistentPlan
            }
            let (withoutSource, removalOverflow) = count.subtractingReportingOverflow(
                mutation.sourceRange.count
            )
            let (next, additionOverflow) = withoutSource.addingReportingOverflow(
                mutation.replacementData.count
            )
            guard !removalOverflow, !additionOverflow, next >= 0 else {
                throw BinaryHexPolicyError.inconsistentPlan
            }
            count = next
            previousUpperBound = mutation.sourceRange.upperBound
        }
        guard count <= maximum else {
            throw BinaryHexPolicyError.outputTooLarge(maximumBytes: maximum)
        }
        return count
    }

    private static func apply(
        _ mutations: [BinaryHexMutation],
        to source: Data,
        outputCount: Int,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> Data {
        guard !mutations.isEmpty else { return source }
        var output = Data()
        output.reserveCapacity(outputCount)
        var cursor = 0
        for mutation in mutations {
            try work.consume(1)
            guard mutation.sourceRange.lowerBound >= cursor,
                mutation.sourceRange.upperBound <= source.count
            else {
                throw BinaryHexPolicyError.inconsistentPlan
            }
            try append(
                source,
                range: cursor..<mutation.sourceRange.lowerBound,
                to: &output,
                work: &work
            )
            try append(
                mutation.replacementData,
                range: 0..<mutation.replacementData.count,
                to: &output,
                work: &work
            )
            cursor = mutation.sourceRange.upperBound
        }
        try append(source, range: cursor..<source.count, to: &output, work: &work)
        guard output.count == outputCount else { throw BinaryHexPolicyError.inconsistentPlan }
        return output
    }

    private static func append(
        _ source: Data,
        range: Range<Int>,
        to output: inout Data,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        var offset = range.lowerBound
        while offset < range.upperBound {
            let count = min(64 * 1_024, range.upperBound - offset)
            try work.consume(count)
            let end = offset + count
            let lowerIndex = source.index(source.startIndex, offsetBy: offset)
            let upperIndex = source.index(source.startIndex, offsetBy: end)
            output.append(contentsOf: source[lowerIndex..<upperIndex])
            offset = end
        }
    }

    private static func find(
        _ pattern: Data,
        in source: Data,
        direction: BinaryHexSearchDirection,
        start: Int,
        wraps: Bool,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> (range: Range<Int>?, didWrap: Bool) {
        let prepared = try preparedPattern(pattern, work: &work)
        guard prepared.bytes.count <= source.count else { return (nil, false) }
        switch direction {
        case .forward:
            var first: Range<Int>?
            var primary: Range<Int>?
            try enumerateMatches(prepared, in: source, work: &work) { range in
                if first == nil { first = range }
                guard range.lowerBound < start else {
                    primary = range
                    return false
                }
                return true
            }
            if let primary { return (primary, false) }
            return wraps ? (first, first != nil) : (nil, false)
        case .backward:
            var last: Range<Int>?
            var primary: Range<Int>?
            try enumerateMatches(prepared, in: source, work: &work) { range in
                if range.upperBound <= start {
                    primary = range
                    return true
                }
                guard primary == nil else { return false }
                last = range
                return true
            }
            if let primary { return (primary, false) }
            return wraps ? (last, last != nil) : (nil, false)
        }
    }

    private static func allNonoverlappingMatches(
        _ pattern: Data,
        in source: Data,
        maximumMatches: Int,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> [Range<Int>] {
        let prepared = try preparedPattern(pattern, work: &work)
        guard prepared.bytes.count <= source.count else { return [] }
        var matches: [Range<Int>] = []
        matches.reserveCapacity(min(maximumMatches, 1_024))
        var nextAllowedOffset = 0
        try enumerateMatches(prepared, in: source, work: &work) {
            (range: Range<Int>) throws(BinaryHexPolicyError) -> Bool in
            guard range.lowerBound >= nextAllowedOffset else { return true }
            guard matches.count < maximumMatches else {
                throw BinaryHexPolicyError.tooManyReplacements(maximum: maximumMatches)
            }
            matches.append(range)
            nextAllowedOffset = range.upperBound
            return true
        }
        return matches
    }

    private static func preparedPattern(
        _ pattern: Data,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> BinaryHexPreparedPattern {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(pattern.count)
        for byte in pattern {
            try work.consume(1)
            bytes.append(byte)
        }
        try work.consume(bytes.count)
        var prefix = [Int](repeating: 0, count: bytes.count)
        var matched = 0
        if bytes.count > 1 {
            for index in 1..<bytes.count {
                try work.consume(1)
                while matched > 0, bytes[index] != bytes[matched] {
                    matched = prefix[matched - 1]
                    try work.consume(1)
                }
                if bytes[index] == bytes[matched] { matched += 1 }
                prefix[index] = matched
            }
        }
        return BinaryHexPreparedPattern(bytes: bytes, prefix: prefix)
    }

    private static func enumerateMatches(
        _ pattern: BinaryHexPreparedPattern,
        in source: Data,
        work: inout BinaryHexWorkBudget,
        body: (Range<Int>) throws(BinaryHexPolicyError) -> Bool
    ) throws(BinaryHexPolicyError) {
        var matched = 0
        var offset = 0
        for byte in source {
            try work.consume(1)
            while matched > 0, byte != pattern.bytes[matched] {
                matched = pattern.prefix[matched - 1]
                try work.consume(1)
            }
            if byte == pattern.bytes[matched] { matched += 1 }
            if matched == pattern.bytes.count {
                let end = offset + 1
                guard try body((end - pattern.bytes.count)..<end) else { return }
                matched = pattern.prefix[matched - 1]
            }
            offset += 1
        }
    }

    private static func retainedBytes(
        intent: BinaryHexIntent,
        source: BinaryHexPaneSnapshot,
        executionState: BinaryHexExecutionState,
        mutations: [BinaryHexMutation],
        maximum: Int,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> Int {
        var count = 0
        func add(_ value: Int) throws(BinaryHexPolicyError) {
            guard value >= 0, value <= maximum - count else {
                throw BinaryHexPolicyError.planTooLarge(maximumBytes: maximum)
            }
            count += value
        }

        try add(binaryHexRetainedByteCount(of: intent, work: &work))
        for value in [
            source.data.count,
            source.persistedData.count,
            executionState.data.count,
            executionState.persistedData.count
        ] {
            try work.consume(1)
            try add(value)
        }
        for mutation in mutations {
            try work.consume(1)
            try add(mutation.replacementData.count)
        }
        return count
    }

    private static func status(
        pane: BinaryHexPane,
        version: BinaryHexContentVersion,
        state: BinaryHexExecutionState,
        requiresNewRevision: Bool
    ) -> BinaryHexPaneStatus {
        let offset = state.selection.byteRange.lowerBound
        let bytesPerRow = state.displaySettings.bytesPerRow
        let currentByte: UInt8?
        if offset < state.data.count {
            currentByte = binaryHexByte(state.data, at: offset)
        } else {
            currentByte = nil
        }
        return BinaryHexPaneStatus(
            pane: pane,
            sourceVersion: version,
            requiresNewRevision: requiresNewRevision,
            byteCount: state.data.count,
            byteOffset: offset,
            row: offset / bytesPerRow,
            column: offset % bytesPerRow,
            selection: state.selection,
            currentByte: currentByte,
            characterSet: state.displaySettings.characterSet,
            editMode: state.displaySettings.editMode,
            isReadOnly: state.isReadOnly,
            isDirty: state.isDirty
        )
    }

    private static func fingerprint(
        intent: BinaryHexIntent,
        source: BinaryHexPaneSnapshot,
        executionState: BinaryHexExecutionState,
        mutations: [BinaryHexMutation],
        replacementCount: Int,
        didWrap: Bool,
        limits: BinaryHexPolicyLimits,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) -> BinaryHexPlanFingerprint {
        var writer = BinaryHexFingerprintWriter()
        writer.add(limits)
        try writer.add(intent, work: &work)
        try writer.add(source, work: &work)
        try writer.add(executionState, work: &work)
        writer.add(mutations.count)
        for mutation in mutations {
            try work.consume(1)
            writer.add(mutation.sourceRange)
            try writer.add(mutation.replacementData, work: &work)
            writer.add(mutation.resultRange)
        }
        writer.add(replacementCount)
        writer.add(didWrap)
        return writer.finalize()
    }
}

private struct BinaryHexDraft {
    let data: Data
    let selection: BinaryHexSelection
    let displaySettings: BinaryHexDisplaySettings
    let mutations: [BinaryHexMutation]
    let replacementCount: Int
    let didWrap: Bool
    let noOpReason: BinaryHexNoOpReason?
}

private struct BinaryHexPreparedPattern {
    let bytes: [UInt8]
    let prefix: [Int]
}

private struct BinaryHexWorkBudget {
    let limits: BinaryHexPolicyLimits
    private(set) var consumed = 0
    private var uncheckedWork = 0

    init(limits: BinaryHexPolicyLimits) {
        self.limits = limits
    }

    mutating func consume(_ amount: Int) throws(BinaryHexPolicyError) {
        guard amount >= 0, amount <= limits.maximumWork - consumed else {
            try checkCancellation()
            throw BinaryHexPolicyError.workLimitExceeded(maximumWork: limits.maximumWork)
        }
        consumed += amount
        let distance = limits.cancellationCheckInterval - uncheckedWork
        if amount >= distance {
            uncheckedWork = (amount - distance) % limits.cancellationCheckInterval
            try checkCancellation()
        } else {
            uncheckedWork += amount
        }
    }

    func checkCancellation() throws(BinaryHexPolicyError) {
        try binaryHexCheckCancellation()
    }
}

private struct BinaryHexFingerprintWriter {
    private var low: UInt64 = 0xCBF2_9CE4_8422_2325
    private var high: UInt64 = 0x8422_2325_CBF2_9CE4

    mutating func add(_ byte: UInt8) {
        low = (low ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        high ^= UInt64(byte) &+ 0x9E37_79B9_7F4A_7C15 &+ (high << 6) &+ (high >> 2)
    }

    mutating func add(_ value: Bool) { add(value ? 1 : 0) }

    mutating func add(_ value: Int) { add(UInt64(bitPattern: Int64(value))) }

    mutating func add(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            add(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    mutating func add(_ range: Range<Int>) {
        add(range.lowerBound)
        add(range.upperBound)
    }

    mutating func add(
        _ data: Data,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        add(data.count)
        for byte in data {
            try work.consume(1)
            add(byte)
        }
    }

    mutating func add(
        _ text: String,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        var count = 0
        for scalar in text.unicodeScalars {
            try work.consume(1)
            add(UInt64(scalar.value))
            count += 1
        }
        add(count)
    }

    mutating func add(_ selection: BinaryHexSelection) {
        add(selection.byteRange)
        add(selection.surface == .bytes ? 0 : 1)
    }

    mutating func add(_ settings: BinaryHexDisplaySettings) {
        add(settings.bytesPerRow)
        add(settings.byteGroupSize)
        add(BinaryHexCharacterSet.allCases.firstIndex(of: settings.characterSet) ?? -1)
        add(settings.offsetRadix == .hexadecimal ? 0 : 1)
        add(settings.usesUppercaseHex)
        add(settings.showsOffsetColumn)
        add(settings.showsCharacterColumn)
        add(settings.editMode == .insert ? 0 : 1)
    }

    mutating func add(_ limits: BinaryHexPolicyLimits) {
        add(limits.maximumInputBytes)
        add(limits.maximumPersistedBytes)
        add(limits.maximumPayloadBytes)
        add(limits.maximumCharacterInputUTF8Bytes)
        add(limits.maximumPatternBytes)
        add(limits.maximumOutputBytes)
        add(limits.maximumReplacements)
        add(limits.maximumPlanBytes)
        add(limits.maximumWork)
        add(limits.cancellationCheckInterval)
    }

    mutating func add(
        _ payload: BinaryHexPayload,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        switch payload {
        case .bytes(let data):
            add(0)
            try add(data, work: &work)
        case .characters(let text):
            add(1)
            try add(text, work: &work)
        }
    }

    mutating func add(
        _ pattern: BinaryHexSearchPattern,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        switch pattern {
        case .bytes(let data):
            add(0)
            try add(data, work: &work)
        case .characters(let text):
            add(1)
            try add(text, work: &work)
        }
    }

    mutating func add(_ target: BinaryHexEditTarget) {
        switch target {
        case .currentSelection:
            add(0)
        case .selection(let selection):
            add(1)
            add(selection)
        case .byteOffset(let offset):
            add(2)
            add(offset)
        }
    }

    mutating func add(
        _ intent: BinaryHexIntent,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        switch intent {
        case .selection(let value):
            add(0)
            switch value {
            case .set(let selection):
                add(0)
                add(selection)
            case .selectAll(let surface):
                add(1)
                add(surface == .bytes ? 0 : 1)
            }
        case .edit(let value):
            add(1)
            switch value {
            case .insert(let payload, let target):
                add(0)
                try add(payload, work: &work)
                add(target)
            case .overwrite(let payload, let target):
                add(1)
                try add(payload, work: &work)
                add(target)
            case .delete(let selection):
                add(2)
                add(selection != nil)
                if let selection { add(selection) }
            }
        case .find(let value):
            add(2)
            try add(value.pattern, work: &work)
            add(value.direction == .forward ? 0 : 1)
            add(value.startByteOffset != nil)
            if let offset = value.startByteOffset { add(offset) }
            add(value.wraps)
        case .replace(let value):
            add(3)
            try add(value.pattern, work: &work)
            try add(value.replacement, work: &work)
            switch value.scope {
            case .currentSelection:
                add(0)
            case .first(let offset, let wraps):
                add(1)
                add(offset != nil)
                if let offset { add(offset) }
                add(wraps)
            case .all:
                add(2)
            }
        case .goTo(let value):
            add(4)
            switch value.target {
            case .byteOffset(let offset):
                add(0)
                add(offset)
            case .row(let index, let column):
                add(1)
                add(index)
                add(column)
            case .percent(let percent):
                add(2)
                add(percent == 0 ? 0 : percent.bitPattern)
            case .end:
                add(3)
            }
            add(value.surface == .bytes ? 0 : 1)
        case .displaySettings(let settings):
            add(5)
            add(settings)
        }
    }

    mutating func add(
        _ snapshot: BinaryHexPaneSnapshot,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        add(snapshot.pane.rawValue)
        try add(snapshot.version.identity.rawValue.uuidString, work: &work)
        add(snapshot.version.revision)
        try add(snapshot.data, work: &work)
        try add(snapshot.persistedData, work: &work)
        add(snapshot.maximumByteCount)
        add(snapshot.selection)
        add(snapshot.displaySettings)
        add(snapshot.isReadOnly)
        add(snapshot.isDirty)
    }

    mutating func add(
        _ state: BinaryHexExecutionState,
        work: inout BinaryHexWorkBudget
    ) throws(BinaryHexPolicyError) {
        try add(state.data, work: &work)
        try add(state.persistedData, work: &work)
        add(state.maximumByteCount)
        add(state.selection)
        add(state.displaySettings)
        add(state.isReadOnly)
        add(state.isDirty)
    }

    func finalize() -> BinaryHexPlanFingerprint {
        BinaryHexPlanFingerprint(low: low, high: high)
    }
}

extension BinaryHexPayload {
    fileprivate var surface: BinaryHexSelectionSurface {
        switch self {
        case .bytes: .bytes
        case .characters: .characters
        }
    }
}

private func binaryHexDataAreEqual(
    _ left: Data,
    _ right: Data,
    work: inout BinaryHexWorkBudget
) throws(BinaryHexPolicyError) -> Bool {
    guard left.count == right.count else { return false }
    var leftIterator = left.makeIterator()
    var rightIterator = right.makeIterator()
    while let leftByte = leftIterator.next() {
        try work.consume(1)
        guard leftByte == rightIterator.next() else { return false }
    }
    return rightIterator.next() == nil
}

private func binaryHexRange(
    _ range: Range<Int>,
    in source: Data,
    equals pattern: Data,
    work: inout BinaryHexWorkBudget
) throws(BinaryHexPolicyError) -> Bool {
    guard range.lowerBound >= 0,
        range.upperBound <= source.count,
        range.count == pattern.count
    else { return false }
    var patternIterator = pattern.makeIterator()
    for offset in range {
        try work.consume(1)
        guard binaryHexByte(source, at: offset) == patternIterator.next() else { return false }
    }
    return patternIterator.next() == nil
}

private func binaryHexByte(_ data: Data, at offset: Int) -> UInt8 {
    data[data.index(data.startIndex, offsetBy: offset)]
}

private func binaryHexStringsAreScalarIdentical(_ left: String, _ right: String) -> Bool {
    left.unicodeScalars.elementsEqual(right.unicodeScalars)
}

private func binaryHexRetainedByteCount(
    of intent: BinaryHexIntent,
    work: inout BinaryHexWorkBudget
) throws(BinaryHexPolicyError) -> Int {
    func textUTF8Count(_ text: String) throws(BinaryHexPolicyError) -> Int {
        var count = 0
        for _ in text.utf8 {
            try work.consume(1)
            let (next, overflow) = count.addingReportingOverflow(1)
            if overflow { return .max }
            count = next
        }
        return count
    }

    func payloadCount(_ payload: BinaryHexPayload) throws(BinaryHexPolicyError) -> Int {
        switch payload {
        case .bytes(let data): data.count
        case .characters(let text): try textUTF8Count(text)
        }
    }

    func patternCount(_ pattern: BinaryHexSearchPattern) throws(BinaryHexPolicyError) -> Int {
        switch pattern {
        case .bytes(let data): data.count
        case .characters(let text): try textUTF8Count(text)
        }
    }

    switch intent {
    case .selection, .goTo, .displaySettings:
        return 0
    case .edit(let edit):
        switch edit {
        case .insert(let payload, _), .overwrite(let payload, _):
            return try payloadCount(payload)
        case .delete:
            return 0
        }
    case .find(let find):
        return try patternCount(find.pattern)
    case .replace(let replace):
        let (count, overflow) = try patternCount(replace.pattern).addingReportingOverflow(
            payloadCount(replace.replacement)
        )
        return overflow ? .max : count
    }
}

private func binaryHexUTF8Bytes(_ value: UInt32) -> [UInt8] {
    switch value {
    case 0...0x7F:
        [UInt8(value)]
    case 0x80...0x7FF:
        [0xC0 | UInt8(value >> 6), 0x80 | UInt8(value & 0x3F)]
    case 0x800...0xFFFF:
        [
            0xE0 | UInt8(value >> 12),
            0x80 | UInt8((value >> 6) & 0x3F),
            0x80 | UInt8(value & 0x3F)
        ]
    default:
        [
            0xF0 | UInt8(value >> 18),
            0x80 | UInt8((value >> 12) & 0x3F),
            0x80 | UInt8((value >> 6) & 0x3F),
            0x80 | UInt8(value & 0x3F)
        ]
    }
}

private func binaryHexUTF16Units(_ value: UInt32) -> [UInt16] {
    guard value > 0xFFFF else { return [UInt16(value)] }
    let supplementary = value - 0x1_0000
    return [
        UInt16(0xD800 + (supplementary >> 10)),
        UInt16(0xDC00 + (supplementary & 0x3FF))
    ]
}

private func binaryHexWindows1252Byte(_ value: UInt32) -> UInt8? {
    if value <= 0x7F || (0xA0...0xFF).contains(value) { return UInt8(value) }
    return switch value {
    case 0x20AC: 0x80
    case 0x201A: 0x82
    case 0x0192: 0x83
    case 0x201E: 0x84
    case 0x2026: 0x85
    case 0x2020: 0x86
    case 0x2021: 0x87
    case 0x02C6: 0x88
    case 0x2030: 0x89
    case 0x0160: 0x8A
    case 0x2039: 0x8B
    case 0x0152: 0x8C
    case 0x017D: 0x8E
    case 0x2018: 0x91
    case 0x2019: 0x92
    case 0x201C: 0x93
    case 0x201D: 0x94
    case 0x2022: 0x95
    case 0x2013: 0x96
    case 0x2014: 0x97
    case 0x02DC: 0x98
    case 0x2122: 0x99
    case 0x0161: 0x9A
    case 0x203A: 0x9B
    case 0x0153: 0x9C
    case 0x017E: 0x9E
    case 0x0178: 0x9F
    default: nil
    }
}

private func binaryHexCheckCancellation() throws(BinaryHexPolicyError) {
    do {
        try Task<Never, Never>.checkCancellation()
    } catch {
        throw BinaryHexPolicyError.cancelled
    }
}
