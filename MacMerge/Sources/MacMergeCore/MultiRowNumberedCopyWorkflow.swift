import Foundation

public struct MultiRowNumberedCopyWorkflowSourceIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct MultiRowNumberedCopyWorkflowComparisonIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct MultiRowNumberedCopyWorkflowSelectionIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct MultiRowNumberedCopyWorkflowPaneIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum MultiRowNumberedCopyWorkflowPane: String, CaseIterable, Equatable, Hashable, Sendable {
    case left
    case right
}

public enum MultiRowNumberedCopyWorkflowSide: String, CaseIterable, Equatable, Hashable, Sendable {
    case left
    case right

    public var numberedCopySide: NumberedTextCopySide {
        switch self {
        case .left: .left
        case .right: .right
        }
    }

    public var pane: MultiRowNumberedCopyWorkflowPane {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}

public enum MultiRowNumberedCopyWorkflowCopyStyle: String, CaseIterable, Equatable, Hashable, Sendable {
    case numbered
    case selectedLines
}

public enum MultiRowNumberedCopyWorkflowOrigin: String, CaseIterable, Equatable, Hashable, Sendable {
    case rowContext
    case editMenu
}

public struct MultiRowNumberedCopyWorkflowPaneRevision: Equatable, Hashable, Sendable {
    public let identity: MultiRowNumberedCopyWorkflowPaneIdentity
    public let revision: UInt64

    public init(identity: MultiRowNumberedCopyWorkflowPaneIdentity, revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

public struct MultiRowNumberedCopyWorkflowSourceReference: Equatable, Hashable, Sendable {
    public let identity: MultiRowNumberedCopyWorkflowSourceIdentity
    public let revision: UInt64
    public let left: MultiRowNumberedCopyWorkflowPaneRevision
    public let right: MultiRowNumberedCopyWorkflowPaneRevision

    public init(
        identity: MultiRowNumberedCopyWorkflowSourceIdentity,
        revision: UInt64,
        left: MultiRowNumberedCopyWorkflowPaneRevision,
        right: MultiRowNumberedCopyWorkflowPaneRevision
    ) {
        self.identity = identity
        self.revision = revision
        self.left = left
        self.right = right
    }

    public subscript(pane: MultiRowNumberedCopyWorkflowPane) -> MultiRowNumberedCopyWorkflowPaneRevision {
        switch pane {
        case .left: left
        case .right: right
        }
    }
}

public struct MultiRowNumberedCopyWorkflowComparisonReference: Equatable, Hashable, Sendable {
    public let identity: MultiRowNumberedCopyWorkflowComparisonIdentity
    public let revision: UInt64
    public let source: MultiRowNumberedCopyWorkflowSourceReference

    public init(
        identity: MultiRowNumberedCopyWorkflowComparisonIdentity,
        revision: UInt64,
        source: MultiRowNumberedCopyWorkflowSourceReference
    ) {
        self.identity = identity
        self.revision = revision
        self.source = source
    }
}

public struct MultiRowNumberedCopyWorkflowSelectionReference: Equatable, Hashable, Sendable {
    public let identity: MultiRowNumberedCopyWorkflowSelectionIdentity
    public let revision: UInt64
    public let comparison: MultiRowNumberedCopyWorkflowComparisonReference

    public init(
        identity: MultiRowNumberedCopyWorkflowSelectionIdentity,
        revision: UInt64,
        comparison: MultiRowNumberedCopyWorkflowComparisonReference
    ) {
        self.identity = identity
        self.revision = revision
        self.comparison = comparison
    }
}

public struct MultiRowNumberedCopyWorkflowSnapshotReference: Equatable, Hashable, Sendable {
    public let comparison: MultiRowNumberedCopyWorkflowComparisonReference
    public let selection: MultiRowNumberedCopyWorkflowSelectionReference

    fileprivate init(
        comparison: MultiRowNumberedCopyWorkflowComparisonReference,
        selection: MultiRowNumberedCopyWorkflowSelectionReference
    ) {
        self.comparison = comparison
        self.selection = selection
    }
}

public struct MultiRowNumberedCopyWorkflowSelectionBinding: Equatable, Sendable {
    public let reference: MultiRowNumberedCopyWorkflowSelectionReference
    public let rowRanges: [Range<Int>]
    public let rowIDs: [DiffRow.ID]
    public let sourceRowCount: Int

    fileprivate init(
        reference: MultiRowNumberedCopyWorkflowSelectionReference,
        rowRanges: [Range<Int>],
        rowIDs: [DiffRow.ID],
        sourceRowCount: Int
    ) {
        self.reference = reference
        self.rowRanges = rowRanges
        self.rowIDs = rowIDs
        self.sourceRowCount = sourceRowCount
    }

    public var selectedRowCount: Int {
        rowRanges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }
}

public struct MultiRowNumberedCopyWorkflowSnapshot: Equatable, Sendable {
    public let comparisonReference: MultiRowNumberedCopyWorkflowComparisonReference
    public let selectionReference: MultiRowNumberedCopyWorkflowSelectionReference
    public let source: ComparisonSnapshot
    public let comparisonRows: [DiffRow]
    public let comparisonOptions: LineDiffOptions
    public let selection: MultiRowNumberedCopyWorkflowSelectionBinding
    public let left: MergeCommandPolicy.SideState
    public let right: MergeCommandPolicy.SideState
    public let comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle

    public init(
        comparisonIdentity: MultiRowNumberedCopyWorkflowComparisonIdentity,
        comparisonRevision: UInt64,
        sourceIdentity: MultiRowNumberedCopyWorkflowSourceIdentity,
        sourceRevision: UInt64,
        leftPaneRevision: MultiRowNumberedCopyWorkflowPaneRevision,
        rightPaneRevision: MultiRowNumberedCopyWorkflowPaneRevision,
        selectionIdentity: MultiRowNumberedCopyWorkflowSelectionIdentity,
        selectionRevision: UInt64,
        source: ComparisonSnapshot,
        comparisonRows: [DiffRow],
        comparisonOptions: LineDiffOptions = LineDiffOptions(),
        selectedRanges: [Range<Int>],
        left: MergeCommandPolicy.SideState,
        right: MergeCommandPolicy.SideState,
        comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle = .currentSuccess
    ) throws {
        do {
            try Task.checkCancellation()
            let sourceReference = MultiRowNumberedCopyWorkflowSourceReference(
                identity: sourceIdentity,
                revision: sourceRevision,
                left: leftPaneRevision,
                right: rightPaneRevision
            )
            let comparisonReference = MultiRowNumberedCopyWorkflowComparisonReference(
                identity: comparisonIdentity,
                revision: comparisonRevision,
                source: sourceReference
            )
            let selectionReference = MultiRowNumberedCopyWorkflowSelectionReference(
                identity: selectionIdentity,
                revision: selectionRevision,
                comparison: comparisonReference
            )
            let normalized = try MultiRowNumberedCopyWorkflow.normalizedRanges(
                selectedRanges,
                rowCount: comparisonRows.count
            )
            var rowIDs: [DiffRow.ID] = []
            rowIDs.reserveCapacity(normalized.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) })
            for range in normalized {
                for index in range {
                    try Task.checkCancellation()
                    rowIDs.append(comparisonRows[index].id)
                }
            }
            self.comparisonReference = comparisonReference
            self.selectionReference = selectionReference
            self.source = source
            self.comparisonRows = comparisonRows
            self.comparisonOptions = comparisonOptions
            self.selection = MultiRowNumberedCopyWorkflowSelectionBinding(
                reference: selectionReference,
                rowRanges: normalized,
                rowIDs: rowIDs,
                sourceRowCount: comparisonRows.count
            )
            self.left = left
            self.right = right
            self.comparisonLifecycle = comparisonLifecycle
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    public var sourceReference: MultiRowNumberedCopyWorkflowSourceReference {
        comparisonReference.source
    }

    public var reference: MultiRowNumberedCopyWorkflowSnapshotReference {
        MultiRowNumberedCopyWorkflowSnapshotReference(
            comparison: comparisonReference,
            selection: selectionReference
        )
    }
}

public struct MultiRowNumberedCopyWorkflowIntent: Equatable, Sendable {
    public let side: MultiRowNumberedCopyWorkflowSide
    public let style: MultiRowNumberedCopyWorkflowCopyStyle
    public let origin: MultiRowNumberedCopyWorkflowOrigin
    public let formatOptions: NumberedTextCopyOptions

    public init(
        side: MultiRowNumberedCopyWorkflowSide,
        style: MultiRowNumberedCopyWorkflowCopyStyle = .numbered,
        origin: MultiRowNumberedCopyWorkflowOrigin = .editMenu,
        formatOptions: NumberedTextCopyOptions = NumberedTextCopyOptions()
    ) {
        self.side = side
        self.style = style
        self.origin = origin
        self.formatOptions = formatOptions
    }
}

public enum MultiRowNumberedCopyWorkflowLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case comparisonRows
    case selectedRows
    case selectedRanges
    case comparisonOptionItems
    case comparisonOptionStringUTF8Bytes
    case comparisonOptionsUTF8Bytes
    case inputUTF8Bytes
    case retainedUTF8Bytes
    case outputUTF8Bytes
    case workUnits
    case cancellationCheckInterval
}

public struct MultiRowNumberedCopyWorkflowLimits: Equatable, Sendable {
    public static let hardMaximumComparisonRows = 1_048_576
    public static let hardMaximumSelectedRows = 1_048_576
    public static let hardMaximumSelectedRanges = 65_536
    public static let hardMaximumComparisonOptionItems = 65_536
    public static let hardMaximumComparisonOptionStringUTF8Bytes = 256 * 1_024
    public static let hardMaximumComparisonOptionsUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumInputUTF8Bytes = 512 * 1_024 * 1_024
    public static let hardMaximumRetainedUTF8Bytes = 1 * 1_024 * 1_024 * 1_024
    public static let hardMaximumOutputUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 42
    public static let hardMaximumCancellationCheckInterval: UInt64 = 4_096
    public static let `default` = MultiRowNumberedCopyWorkflowLimits()

    public let maximumComparisonRows: Int
    public let maximumSelectedRows: Int
    public let maximumSelectedRanges: Int
    public let maximumComparisonOptionItems: Int
    public let maximumComparisonOptionStringUTF8Bytes: Int
    public let maximumComparisonOptionsUTF8Bytes: Int
    public let maximumInputUTF8Bytes: Int
    public let maximumRetainedUTF8Bytes: Int
    public let maximumOutputUTF8Bytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64

    public init(
        maximumComparisonRows: Int = hardMaximumComparisonRows,
        maximumSelectedRows: Int = hardMaximumSelectedRows,
        maximumSelectedRanges: Int = hardMaximumSelectedRanges,
        maximumComparisonOptionItems: Int = 4_096,
        maximumComparisonOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumComparisonOptionsUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumInputUTF8Bytes: Int = 256 * 1_024 * 1_024,
        maximumRetainedUTF8Bytes: Int = 512 * 1_024 * 1_024,
        maximumOutputUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 1_024
    ) {
        self.maximumComparisonRows = maximumComparisonRows
        self.maximumSelectedRows = maximumSelectedRows
        self.maximumSelectedRanges = maximumSelectedRanges
        self.maximumComparisonOptionItems = maximumComparisonOptionItems
        self.maximumComparisonOptionStringUTF8Bytes = maximumComparisonOptionStringUTF8Bytes
        self.maximumComparisonOptionsUTF8Bytes = maximumComparisonOptionsUTF8Bytes
        self.maximumInputUTF8Bytes = maximumInputUTF8Bytes
        self.maximumRetainedUTF8Bytes = maximumRetainedUTF8Bytes
        self.maximumOutputUTF8Bytes = maximumOutputUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum MultiRowNumberedCopyWorkflowDisabledReason: Equatable, Sendable {
    case comparisonNotCurrent
    case sourceNotLoaded(MultiRowNumberedCopyWorkflowSide)
    case emptySelection
    case noCopyableSourceLines(MultiRowNumberedCopyWorkflowSide)
}

public struct MultiRowNumberedCopyWorkflowCommandState: Equatable, Sendable {
    public let intent: MultiRowNumberedCopyWorkflowIntent
    public let expectedSnapshot: MultiRowNumberedCopyWorkflowSnapshotReference
    public let selection: MultiRowNumberedCopyWorkflowSelectionBinding
    public let isEnabled: Bool
    public let disabledReason: MultiRowNumberedCopyWorkflowDisabledReason?
    public let workUnitsConsumed: UInt64

    fileprivate init(
        intent: MultiRowNumberedCopyWorkflowIntent,
        snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        isEnabled: Bool,
        disabledReason: MultiRowNumberedCopyWorkflowDisabledReason?,
        workUnitsConsumed: UInt64
    ) {
        self.intent = intent
        expectedSnapshot = snapshot.reference
        selection = snapshot.selection
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.workUnitsConsumed = workUnitsConsumed
    }

    public var canExecute: Bool { isEnabled }
}

public enum MultiRowNumberedCopyWorkflowRequiredEffect: Equatable, Sendable {
    case copyPayloadToOwnerTransferService
}

public enum MultiRowNumberedCopyWorkflowExecutorPreflightContract: String, Equatable, Hashable, Sendable {
    case validateExactSnapshotCASAndCopyCapabilityBeforeCopy
}

public enum MultiRowNumberedCopyWorkflowExecutorCASContract: String, Equatable, Hashable, Sendable {
    case compareExactSnapshotBeforeCopy
}

public enum MultiRowNumberedCopyWorkflowExecutorCancellationContract: String, Equatable, Hashable, Sendable {
    case cancellableBeforeCopyOrCompletedFailedAfterCopyStarts
}

public struct MultiRowNumberedCopyWorkflowExecutorContract: Equatable, Hashable, Sendable {
    public static let required = MultiRowNumberedCopyWorkflowExecutorContract()

    public let preflight = MultiRowNumberedCopyWorkflowExecutorPreflightContract.validateExactSnapshotCASAndCopyCapabilityBeforeCopy
    public let compareAndSwap = MultiRowNumberedCopyWorkflowExecutorCASContract.compareExactSnapshotBeforeCopy
    public let cancellation = MultiRowNumberedCopyWorkflowExecutorCancellationContract.cancellableBeforeCopyOrCompletedFailedAfterCopyStarts

    public init() {}
}

public struct MultiRowNumberedCopyWorkflowPlanningReceipt: Equatable, Sendable {
    public let expectedSnapshot: MultiRowNumberedCopyWorkflowSnapshotReference
    public let intentSide: MultiRowNumberedCopyWorkflowSide
    public let intentStyle: MultiRowNumberedCopyWorkflowCopyStyle
    public let intentOrigin: MultiRowNumberedCopyWorkflowOrigin
    public let selection: MultiRowNumberedCopyWorkflowSelectionBinding
    public let selectedRowCount: Int
    public let selectedRangeCount: Int
    public let payloadUTF8ByteCount: Int
    public let retainedUTF8ByteEstimate: Int
    public let workflowWorkUnitsConsumed: UInt64

    fileprivate init(
        snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        intent: MultiRowNumberedCopyWorkflowIntent,
        payloadUTF8ByteCount: Int,
        retainedUTF8ByteEstimate: Int,
        workflowWorkUnitsConsumed: UInt64
    ) {
        expectedSnapshot = snapshot.reference
        intentSide = intent.side
        intentStyle = intent.style
        intentOrigin = intent.origin
        selection = snapshot.selection
        selectedRowCount = snapshot.selection.selectedRowCount
        selectedRangeCount = snapshot.selection.rowRanges.count
        self.payloadUTF8ByteCount = payloadUTF8ByteCount
        self.retainedUTF8ByteEstimate = retainedUTF8ByteEstimate
        self.workflowWorkUnitsConsumed = workflowWorkUnitsConsumed
    }
}

public struct MultiRowNumberedCopyWorkflowSnapshotCAS: Equatable, Sendable {
    public let reference: MultiRowNumberedCopyWorkflowSnapshotReference

    private let snapshot: MultiRowNumberedCopyWorkflowSnapshot

    fileprivate init(snapshot: MultiRowNumberedCopyWorkflowSnapshot) {
        reference = snapshot.reference
        self.snapshot = snapshot
    }

    public func matches(_ current: MultiRowNumberedCopyWorkflowSnapshot) throws -> Bool {
        do {
            try validate(current)
            return true
        } catch let error as MultiRowNumberedCopyWorkflowError where error.isStaleValidationFailure {
            return false
        }
    }

    public func validate(_ current: MultiRowNumberedCopyWorkflowSnapshot) throws {
        try MultiRowNumberedCopyWorkflow.validateCurrentSnapshot(current, expected: snapshot)
    }
}

public struct MultiRowNumberedCopyWorkflowPlanReference: Equatable, Hashable, Sendable {
    public let nonce: UUID
    public let snapshot: MultiRowNumberedCopyWorkflowSnapshotReference

    fileprivate init(snapshot: MultiRowNumberedCopyWorkflowSnapshotReference) {
        nonce = UUID()
        self.snapshot = snapshot
    }
}

public struct MultiRowNumberedCopyWorkflowPlan: Equatable, Sendable {
    public let reference: MultiRowNumberedCopyWorkflowPlanReference
    public let expectedSnapshotCAS: MultiRowNumberedCopyWorkflowSnapshotCAS
    public let intent: MultiRowNumberedCopyWorkflowIntent
    public let selection: MultiRowNumberedCopyWorkflowSelectionBinding
    public let payload: String
    public let receipt: MultiRowNumberedCopyWorkflowPlanningReceipt
    public let requiredEffects: [MultiRowNumberedCopyWorkflowRequiredEffect]
    public let limits: MultiRowNumberedCopyWorkflowLimits
    public let executorContract: MultiRowNumberedCopyWorkflowExecutorContract

    fileprivate init(
        expectedSnapshotCAS: MultiRowNumberedCopyWorkflowSnapshotCAS,
        intent: MultiRowNumberedCopyWorkflowIntent,
        snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        payload: String,
        receipt: MultiRowNumberedCopyWorkflowPlanningReceipt,
        limits: MultiRowNumberedCopyWorkflowLimits
    ) {
        reference = MultiRowNumberedCopyWorkflowPlanReference(snapshot: snapshot.reference)
        self.expectedSnapshotCAS = expectedSnapshotCAS
        self.intent = intent
        selection = snapshot.selection
        self.payload = payload
        self.receipt = receipt
        requiredEffects = [.copyPayloadToOwnerTransferService]
        self.limits = limits
        executorContract = .required
    }

    public var expectedSnapshot: MultiRowNumberedCopyWorkflowSnapshotReference {
        expectedSnapshotCAS.reference
    }

    public func validateCurrentSnapshot(_ snapshot: MultiRowNumberedCopyWorkflowSnapshot) throws {
        try expectedSnapshotCAS.validate(snapshot)
    }
}

public struct MultiRowNumberedCopyWorkflowCopyEvidence: Equatable, Sendable {
    public let comparedSnapshot: MultiRowNumberedCopyWorkflowSnapshotReference
    public let copiedSide: MultiRowNumberedCopyWorkflowSide
    public let copiedStyle: MultiRowNumberedCopyWorkflowCopyStyle
    public let copiedRowCount: Int
    public let copiedUTF8ByteCount: Int

    public init(
        comparedSnapshot: MultiRowNumberedCopyWorkflowSnapshotReference,
        copiedSide: MultiRowNumberedCopyWorkflowSide,
        copiedStyle: MultiRowNumberedCopyWorkflowCopyStyle,
        copiedRowCount: Int,
        copiedUTF8ByteCount: Int
    ) {
        self.comparedSnapshot = comparedSnapshot
        self.copiedSide = copiedSide
        self.copiedStyle = copiedStyle
        self.copiedRowCount = copiedRowCount
        self.copiedUTF8ByteCount = copiedUTF8ByteCount
    }
}

public struct MultiRowNumberedCopyWorkflowExecutionReceipt: Equatable, Sendable {
    public let planningReceipt: MultiRowNumberedCopyWorkflowPlanningReceipt
    public let evidence: MultiRowNumberedCopyWorkflowCopyEvidence
    public let completedEffects: [MultiRowNumberedCopyWorkflowRequiredEffect]

    fileprivate init(
        plan: MultiRowNumberedCopyWorkflowPlan,
        evidence: MultiRowNumberedCopyWorkflowCopyEvidence
    ) {
        planningReceipt = plan.receipt
        self.evidence = evidence
        completedEffects = plan.requiredEffects
    }
}

public enum MultiRowNumberedCopyWorkflowExecutionOutcome: Equatable, Sendable {
    case completed(MultiRowNumberedCopyWorkflowExecutionReceipt)
    case failed(MultiRowNumberedCopyWorkflowExecutionFailureReceipt)
}

public struct MultiRowNumberedCopyWorkflowExecutionFailureReceipt: Equatable, Sendable {
    public let planningReceipt: MultiRowNumberedCopyWorkflowPlanningReceipt
    public let failedEffect: MultiRowNumberedCopyWorkflowRequiredEffect
    public let reason: MultiRowNumberedCopyWorkflowExecutionFailureReason
    public let completedEffects: [MultiRowNumberedCopyWorkflowRequiredEffect]

    fileprivate init(
        plan: MultiRowNumberedCopyWorkflowPlan,
        reason: MultiRowNumberedCopyWorkflowExecutionFailureReason
    ) {
        planningReceipt = plan.receipt
        failedEffect = plan.requiredEffects[0]
        self.reason = reason
        completedEffects = []
    }
}

public enum MultiRowNumberedCopyWorkflowExecutionFailureReason: String, CaseIterable, Equatable, Hashable, Sendable {
    case cancelled
    case staleSnapshot
    case ownerUnavailable
    case contractUnsupported
    case rejected
}

public enum MultiRowNumberedCopyWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(MultiRowNumberedCopyWorkflowLimit)
    case tooManyComparisonRows(maximum: Int)
    case tooManySelectedRows(maximum: Int)
    case tooManySelectedRanges(maximum: Int)
    case inputTooLarge(maximumUTF8Bytes: Int)
    case retainedDataTooLarge(maximumUTF8Bytes: Int)
    case outputTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximumUnits: UInt64)
    case emptySelection
    case invalidSelectionRange(requested: Range<Int>, rowCount: Int)
    case unorderedOrOverlappingSelection(selectionIndex: Int)
    case invalidFocusedRow(Int)
    case comparisonNotCurrent
    case sourceNotLoaded(MultiRowNumberedCopyWorkflowSide)
    case noCopyableSourceLines(MultiRowNumberedCopyWorkflowSide)
    case commandDisabled(MultiRowNumberedCopyWorkflowDisabledReason)
    case numberedCopy(NumberedTextCopyError)
    case staleComparisonIdentity
    case staleComparisonRevision(expected: UInt64, actual: UInt64)
    case staleSourceIdentity
    case staleSourceRevision(expected: UInt64, actual: UInt64)
    case stalePaneIdentity(MultiRowNumberedCopyWorkflowPane)
    case stalePaneRevision(pane: MultiRowNumberedCopyWorkflowPane, expected: UInt64, actual: UInt64)
    case staleSelectionIdentity
    case staleSelectionRevision(expected: UInt64, actual: UInt64)
    case sourceContentsChanged
    case comparisonRowsChanged
    case comparisonOptionsChanged
    case selectionChanged
    case sideStateChanged(MultiRowNumberedCopyWorkflowPane)
    case comparisonLifecycleChanged
    case invalidCopyEvidence
    case invalidExecutionOutcome
    case arithmeticOverflow

    fileprivate var isStaleValidationFailure: Bool {
        switch self {
        case .staleComparisonIdentity, .staleComparisonRevision, .staleSourceIdentity,
            .staleSourceRevision, .stalePaneIdentity, .stalePaneRevision,
            .staleSelectionIdentity, .staleSelectionRevision, .sourceContentsChanged,
            .comparisonRowsChanged, .comparisonOptionsChanged, .selectionChanged,
            .sideStateChanged, .comparisonLifecycleChanged:
            true
        default:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Multi-row numbered copy was cancelled."
        case .invalidLimit(let limit):
            "Invalid multi-row numbered copy limit: \(limit.rawValue)."
        case .tooManyComparisonRows(let maximum):
            "Comparison exceeds the \(maximum)-row copy limit."
        case .tooManySelectedRows(let maximum):
            "Selection exceeds the \(maximum)-row copy limit."
        case .tooManySelectedRanges(let maximum):
            "Selection exceeds the \(maximum)-range copy limit."
        case .inputTooLarge(let maximum):
            "Multi-row numbered copy input exceeds \(maximum) UTF-8 bytes."
        case .retainedDataTooLarge(let maximum):
            "Multi-row numbered copy plan exceeds \(maximum) retained UTF-8 bytes."
        case .outputTooLarge(let maximum):
            "Multi-row numbered copy output exceeds \(maximum) UTF-8 bytes."
        case .workLimitExceeded(let maximum):
            "Multi-row numbered copy exceeds \(maximum) work units."
        case .emptySelection:
            "Multi-row numbered copy requires at least one selected row."
        case .invalidSelectionRange(let requested, let rowCount):
            "Selected row range \(requested.lowerBound)..<\(requested.upperBound) is outside 0..<\(rowCount) or empty."
        case .unorderedOrOverlappingSelection(let index):
            "Selected row range \(index) is out of order or overlaps the previous range."
        case .invalidFocusedRow(let row):
            "Focused copy row \(row) is outside the comparison rows."
        case .comparisonNotCurrent:
            "Multi-row numbered copy requires a current successful comparison."
        case .sourceNotLoaded(let side):
            "Multi-row numbered copy source is not loaded: \(side.rawValue)."
        case .noCopyableSourceLines(let side):
            "Multi-row numbered copy selection has no \(side.rawValue) source lines."
        case .commandDisabled(let reason):
            "Multi-row numbered copy command is disabled: \(String(describing: reason))."
        case .numberedCopy(let error):
            error.localizedDescription
        case .staleComparisonIdentity:
            "Numbered copy plan belongs to another comparison."
        case .staleComparisonRevision(let expected, let actual):
            "Numbered copy expected comparison revision \(expected), not \(actual)."
        case .staleSourceIdentity:
            "Numbered copy plan belongs to another source set."
        case .staleSourceRevision(let expected, let actual):
            "Numbered copy expected source revision \(expected), not \(actual)."
        case .stalePaneIdentity(let pane):
            "Numbered copy plan belongs to another \(pane.rawValue) pane."
        case .stalePaneRevision(let pane, let expected, let actual):
            "Numbered copy expected \(pane.rawValue) pane revision \(expected), not \(actual)."
        case .staleSelectionIdentity:
            "Numbered copy plan belongs to another selection."
        case .staleSelectionRevision(let expected, let actual):
            "Numbered copy expected selection revision \(expected), not \(actual)."
        case .sourceContentsChanged:
            "Numbered copy source changed without advancing its revision."
        case .comparisonRowsChanged:
            "Numbered copy rows changed without advancing comparison revision."
        case .comparisonOptionsChanged:
            "Numbered copy options changed without advancing comparison revision."
        case .selectionChanged:
            "Numbered copy selection changed without advancing selection revision."
        case .sideStateChanged(let pane):
            "Numbered copy \(pane.rawValue) side state changed without advancing pane revision."
        case .comparisonLifecycleChanged:
            "Numbered copy lifecycle changed without advancing comparison revision."
        case .invalidCopyEvidence:
            "Numbered copy evidence does not belong to this plan."
        case .invalidExecutionOutcome:
            "Numbered copy execution outcome contradicts the required copy effect."
        case .arithmeticOverflow:
            "Multi-row numbered copy size calculation overflowed."
        }
    }
}

public enum MultiRowNumberedCopyWorkflow: Sendable {
    public static func expandedRanges(
        _ ranges: [Range<Int>],
        rowCount: Int,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> [Range<Int>] {
        do {
            try Task.checkCancellation()
            try validate(limits)
            guard ranges.count <= limits.maximumSelectedRanges else {
                throw MultiRowNumberedCopyWorkflowError.tooManySelectedRanges(
                    maximum: limits.maximumSelectedRanges
                )
            }
            return try normalizedRanges(ranges, rowCount: rowCount)
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    public static func expandedRanges(
        _ selection: IndexSet,
        rowCount: Int,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> [Range<Int>] {
        do {
            try Task.checkCancellation()
            try validate(limits)
            var ranges: [Range<Int>] = []
            ranges.reserveCapacity(min(selection.rangeView.count, limits.maximumSelectedRanges))
            for range in selection.rangeView {
                if ranges.count.isMultiple(of: 1_024) {
                    try Task.checkCancellation()
                }
                guard ranges.count < limits.maximumSelectedRanges else {
                    throw MultiRowNumberedCopyWorkflowError.tooManySelectedRanges(
                        maximum: limits.maximumSelectedRanges
                    )
                }
                ranges.append(range.lowerBound..<range.upperBound)
            }
            return try normalizedRanges(ranges, rowCount: rowCount)
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    public static func resolveRowContextSelection(
        explicitRanges: [Range<Int>],
        rowCount: Int,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> [Range<Int>] {
        try expandedRanges(explicitRanges, rowCount: rowCount, limits: limits)
    }

    public static func resolveRowContextSelection(
        explicitSelection: IndexSet,
        rowCount: Int,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> [Range<Int>] {
        try expandedRanges(explicitSelection, rowCount: rowCount, limits: limits)
    }

    public static func resolveEditMenuSelection(
        explicitRanges: [Range<Int>],
        focusedRow: Int?,
        rowCount: Int,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> [Range<Int>] {
        do {
            try Task.checkCancellation()
            try validate(limits)
            if !explicitRanges.isEmpty {
                return try normalizedRanges(explicitRanges, rowCount: rowCount)
            }
            guard let focusedRow else {
                throw MultiRowNumberedCopyWorkflowError.emptySelection
            }
            guard rowCount > 0, (0..<rowCount).contains(focusedRow) else {
                throw MultiRowNumberedCopyWorkflowError.invalidFocusedRow(focusedRow)
            }
            return [focusedRow..<(focusedRow + 1)]
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    public static func resolveEditMenuSelection(
        explicitSelection: IndexSet,
        focusedRow: Int?,
        rowCount: Int,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> [Range<Int>] {
        do {
            try Task.checkCancellation()
            let explicit = try expandedRanges(explicitSelection, rowCount: rowCount, limits: limits)
            if !explicit.isEmpty {
                return explicit
            }
            guard let focusedRow else {
                throw MultiRowNumberedCopyWorkflowError.emptySelection
            }
            guard rowCount > 0, (0..<rowCount).contains(focusedRow) else {
                throw MultiRowNumberedCopyWorkflowError.invalidFocusedRow(focusedRow)
            }
            return [focusedRow..<(focusedRow + 1)]
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    public static func commandState(
        for intent: MultiRowNumberedCopyWorkflowIntent,
        in snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> MultiRowNumberedCopyWorkflowCommandState {
        do {
            var work = try WorkBudget(limits: limits)
            _ = try validateForPlanning(snapshot, limits: limits, work: &work)
            if let disabled = disabledReason(for: intent.side, in: snapshot) {
                try work.finish()
                return MultiRowNumberedCopyWorkflowCommandState(
                    intent: intent,
                    snapshot: snapshot,
                    isEnabled: false,
                    disabledReason: disabled,
                    workUnitsConsumed: work.consumed
                )
            }
            guard try hasCopyableSourceLines(for: intent.side, in: snapshot, work: &work) else {
                try work.finish()
                return MultiRowNumberedCopyWorkflowCommandState(
                    intent: intent,
                    snapshot: snapshot,
                    isEnabled: false,
                    disabledReason: .noCopyableSourceLines(intent.side),
                    workUnitsConsumed: work.consumed
                )
            }
            try work.finish()
            return MultiRowNumberedCopyWorkflowCommandState(
                intent: intent,
                snapshot: snapshot,
                isEnabled: true,
                disabledReason: nil,
                workUnitsConsumed: work.consumed
            )
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    public static func plan(
        intent: MultiRowNumberedCopyWorkflowIntent,
        in snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        limits: MultiRowNumberedCopyWorkflowLimits = .default
    ) throws -> MultiRowNumberedCopyWorkflowPlan {
        do {
            var work = try WorkBudget(limits: limits)
            let retainedBaseEstimate = try validateForPlanning(snapshot, limits: limits, work: &work)
            let state = try commandStateWithoutRevalidation(intent: intent, snapshot: snapshot, work: &work)
            guard state.isEnabled else {
                throw MultiRowNumberedCopyWorkflowError.commandDisabled(
                    state.disabledReason ?? .emptySelection
                )
            }
            let payload: String
            switch intent.style {
            case .numbered:
                payload = try numberedPayload(
                    snapshot: snapshot,
                    intent: intent,
                    work: &work
                )
            case .selectedLines:
                payload = try selectedLinesPayload(
                    snapshot: snapshot,
                    intent: intent,
                    limits: limits,
                    work: &work
                )
            }
            let payloadBytes = payload.utf8.count
            guard payloadBytes <= limits.maximumOutputUTF8Bytes else {
                throw MultiRowNumberedCopyWorkflowError.outputTooLarge(
                    maximumUTF8Bytes: limits.maximumOutputUTF8Bytes
                )
            }
            try work.consume(UInt64(payloadBytes))
            try work.finish()
            let retainedEstimate = try checkedAdd(retainedBaseEstimate, payloadBytes)
            guard retainedEstimate <= limits.maximumRetainedUTF8Bytes else {
                throw MultiRowNumberedCopyWorkflowError.retainedDataTooLarge(
                    maximumUTF8Bytes: limits.maximumRetainedUTF8Bytes
                )
            }
            let receipt = MultiRowNumberedCopyWorkflowPlanningReceipt(
                snapshot: snapshot,
                intent: intent,
                payloadUTF8ByteCount: payloadBytes,
                retainedUTF8ByteEstimate: retainedEstimate,
                workflowWorkUnitsConsumed: work.consumed
            )
            return MultiRowNumberedCopyWorkflowPlan(
                expectedSnapshotCAS: MultiRowNumberedCopyWorkflowSnapshotCAS(snapshot: snapshot),
                intent: intent,
                snapshot: snapshot,
                payload: payload,
                receipt: receipt,
                limits: limits
            )
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    public static func executorAttestedCopied(
        plan: MultiRowNumberedCopyWorkflowPlan,
        evidence: MultiRowNumberedCopyWorkflowCopyEvidence
    ) throws -> MultiRowNumberedCopyWorkflowExecutionOutcome {
        guard evidence.comparedSnapshot == plan.expectedSnapshot,
            evidence.copiedSide == plan.intent.side,
            evidence.copiedStyle == plan.intent.style,
            evidence.copiedRowCount == plan.receipt.selectedRowCount,
            evidence.copiedUTF8ByteCount == plan.receipt.payloadUTF8ByteCount
        else {
            throw MultiRowNumberedCopyWorkflowError.invalidCopyEvidence
        }
        return .completed(
            MultiRowNumberedCopyWorkflowExecutionReceipt(plan: plan, evidence: evidence)
        )
    }

    public static func failed(
        plan: MultiRowNumberedCopyWorkflowPlan,
        reason: MultiRowNumberedCopyWorkflowExecutionFailureReason
    ) -> MultiRowNumberedCopyWorkflowExecutionOutcome {
        .failed(
            MultiRowNumberedCopyWorkflowExecutionFailureReceipt(plan: plan, reason: reason)
        )
    }

    fileprivate static func normalizedRanges(
        _ ranges: [Range<Int>],
        rowCount: Int
    ) throws -> [Range<Int>] {
        guard !ranges.isEmpty else {
            throw MultiRowNumberedCopyWorkflowError.emptySelection
        }
        var previousUpperBound: Int?
        for (index, range) in ranges.enumerated() {
            if index.isMultiple(of: 1_024) {
                try Task.checkCancellation()
            }
            guard range.lowerBound >= 0,
                range.lowerBound < range.upperBound,
                range.upperBound <= rowCount
            else {
                throw MultiRowNumberedCopyWorkflowError.invalidSelectionRange(
                    requested: range,
                    rowCount: rowCount
                )
            }
            if let previousUpperBound, range.lowerBound < previousUpperBound {
                throw MultiRowNumberedCopyWorkflowError.unorderedOrOverlappingSelection(
                    selectionIndex: index
                )
            }
            previousUpperBound = range.upperBound
        }
        return ranges
    }

    fileprivate static func validateCurrentSnapshot(
        _ current: MultiRowNumberedCopyWorkflowSnapshot,
        expected: MultiRowNumberedCopyWorkflowSnapshot
    ) throws {
        do {
            try validateReferences(current, expected: expected)
            guard current.left == expected.left else {
                throw MultiRowNumberedCopyWorkflowError.sideStateChanged(.left)
            }
            guard current.right == expected.right else {
                throw MultiRowNumberedCopyWorkflowError.sideStateChanged(.right)
            }
            guard current.comparisonLifecycle == expected.comparisonLifecycle else {
                throw MultiRowNumberedCopyWorkflowError.comparisonLifecycleChanged
            }
            guard current.comparisonOptions == expected.comparisonOptions else {
                throw MultiRowNumberedCopyWorkflowError.comparisonOptionsChanged
            }
            guard current.source == expected.source else {
                throw MultiRowNumberedCopyWorkflowError.sourceContentsChanged
            }
            guard current.comparisonRows == expected.comparisonRows else {
                throw MultiRowNumberedCopyWorkflowError.comparisonRowsChanged
            }
            guard current.selection == expected.selection else {
                throw MultiRowNumberedCopyWorkflowError.selectionChanged
            }
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    private static func validateReferences(
        _ current: MultiRowNumberedCopyWorkflowSnapshot,
        expected: MultiRowNumberedCopyWorkflowSnapshot
    ) throws {
        let currentComparison = current.comparisonReference
        let expectedComparison = expected.comparisonReference
        guard currentComparison.identity == expectedComparison.identity else {
            throw MultiRowNumberedCopyWorkflowError.staleComparisonIdentity
        }
        guard currentComparison.revision == expectedComparison.revision else {
            throw MultiRowNumberedCopyWorkflowError.staleComparisonRevision(
                expected: expectedComparison.revision,
                actual: currentComparison.revision
            )
        }
        let currentSource = current.sourceReference
        let expectedSource = expected.sourceReference
        guard currentSource.identity == expectedSource.identity else {
            throw MultiRowNumberedCopyWorkflowError.staleSourceIdentity
        }
        guard currentSource.revision == expectedSource.revision else {
            throw MultiRowNumberedCopyWorkflowError.staleSourceRevision(
                expected: expectedSource.revision,
                actual: currentSource.revision
            )
        }
        for pane in [MultiRowNumberedCopyWorkflowPane.left, MultiRowNumberedCopyWorkflowPane.right] {
            guard currentSource[pane].identity == expectedSource[pane].identity else {
                throw MultiRowNumberedCopyWorkflowError.stalePaneIdentity(pane)
            }
            guard currentSource[pane].revision == expectedSource[pane].revision else {
                throw MultiRowNumberedCopyWorkflowError.stalePaneRevision(
                    pane: pane,
                    expected: expectedSource[pane].revision,
                    actual: currentSource[pane].revision
                )
            }
        }
        guard current.selectionReference.identity == expected.selectionReference.identity else {
            throw MultiRowNumberedCopyWorkflowError.staleSelectionIdentity
        }
        guard current.selectionReference.revision == expected.selectionReference.revision else {
            throw MultiRowNumberedCopyWorkflowError.staleSelectionRevision(
                expected: expected.selectionReference.revision,
                actual: current.selectionReference.revision
            )
        }
    }

    private static func commandStateWithoutRevalidation(
        intent: MultiRowNumberedCopyWorkflowIntent,
        snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        work: inout WorkBudget
    ) throws -> MultiRowNumberedCopyWorkflowCommandState {
        if let disabled = disabledReason(for: intent.side, in: snapshot) {
            return MultiRowNumberedCopyWorkflowCommandState(
                intent: intent,
                snapshot: snapshot,
                isEnabled: false,
                disabledReason: disabled,
                workUnitsConsumed: work.consumed
            )
        }
        guard try hasCopyableSourceLines(for: intent.side, in: snapshot, work: &work) else {
            return MultiRowNumberedCopyWorkflowCommandState(
                intent: intent,
                snapshot: snapshot,
                isEnabled: false,
                disabledReason: .noCopyableSourceLines(intent.side),
                workUnitsConsumed: work.consumed
            )
        }
        return MultiRowNumberedCopyWorkflowCommandState(
            intent: intent,
            snapshot: snapshot,
            isEnabled: true,
            disabledReason: nil,
            workUnitsConsumed: work.consumed
        )
    }

    private static func disabledReason(
        for side: MultiRowNumberedCopyWorkflowSide,
        in snapshot: MultiRowNumberedCopyWorkflowSnapshot
    ) -> MultiRowNumberedCopyWorkflowDisabledReason? {
        guard snapshot.comparisonLifecycle == .currentSuccess else {
            return .comparisonNotCurrent
        }
        switch side {
        case .left:
            guard snapshot.left.isLoaded else { return .sourceNotLoaded(side) }
        case .right:
            guard snapshot.right.isLoaded else { return .sourceNotLoaded(side) }
        }
        guard !snapshot.selection.rowRanges.isEmpty, snapshot.selection.selectedRowCount > 0 else {
            return .emptySelection
        }
        return nil
    }

    private static func hasCopyableSourceLines(
        for side: MultiRowNumberedCopyWorkflowSide,
        in snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        work: inout WorkBudget
    ) throws -> Bool {
        for range in snapshot.selection.rowRanges {
            for index in range {
                try work.consume(1)
                let row = snapshot.comparisonRows[index]
                switch side {
                case .left:
                    if row.left != nil { return true }
                case .right:
                    if row.right != nil { return true }
                }
            }
        }
        return false
    }

    private static func numberedPayload(
        snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        intent: MultiRowNumberedCopyWorkflowIntent,
        work: inout WorkBudget
    ) throws -> String {
        try work.checkCancellation()
        guard intent.formatOptions.maximumRows > 0,
            intent.formatOptions.maximumRows <= MultiRowNumberedCopyWorkflowLimits.hardMaximumSelectedRows
        else {
            throw MultiRowNumberedCopyWorkflowError.numberedCopy(
                .invalidMaximumRows(intent.formatOptions.maximumRows)
            )
        }
        guard intent.formatOptions.maximumOutputBytes > 0,
            intent.formatOptions.maximumOutputBytes <= MultiRowNumberedCopyWorkflowLimits.hardMaximumOutputUTF8Bytes
        else {
            throw MultiRowNumberedCopyWorkflowError.numberedCopy(
                .invalidMaximumOutputBytes(intent.formatOptions.maximumOutputBytes)
            )
        }
        do {
            let formatted = try NumberedTextCopy.format(
                rows: snapshot.comparisonRows,
                selectedRanges: snapshot.selection.rowRanges,
                side: intent.side.numberedCopySide,
                options: intent.formatOptions
            )
            try work.consume(UInt64(formatted.utf8.count))
            try work.checkCancellation()
            return formatted
        } catch let error as NumberedTextCopyError {
            throw MultiRowNumberedCopyWorkflowError.numberedCopy(error)
        } catch is CancellationError {
            throw MultiRowNumberedCopyWorkflowError.cancelled
        }
    }

    private static func selectedLinesPayload(
        snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        intent: MultiRowNumberedCopyWorkflowIntent,
        limits: MultiRowNumberedCopyWorkflowLimits,
        work: inout WorkBudget
    ) throws -> String {
        try work.checkCancellation()
        let separator = intent.formatOptions.rowSeparator
        let separatorBytes = separator.utf8.count
        var byteCount = 0
        var parts: [String] = []
        parts.reserveCapacity(snapshot.selection.selectedRowCount)
        var isFirstRow = true
        for range in snapshot.selection.rowRanges {
            for index in range {
                try work.consume(1)
                if !isFirstRow {
                    byteCount = try checkedAdd(byteCount, separatorBytes)
                    guard byteCount <= limits.maximumOutputUTF8Bytes else {
                        throw MultiRowNumberedCopyWorkflowError.outputTooLarge(
                            maximumUTF8Bytes: limits.maximumOutputUTF8Bytes
                        )
                    }
                    guard byteCount <= intent.formatOptions.maximumOutputBytes else {
                        throw MultiRowNumberedCopyWorkflowError.numberedCopy(
                            .outputTooLarge(maximumBytes: intent.formatOptions.maximumOutputBytes)
                        )
                    }
                }
                let row = snapshot.comparisonRows[index]
                let line: DiffLine?
                switch intent.side {
                case .left: line = row.left
                case .right: line = row.right
                }
                let text = line?.text ?? ""
                let textBytes = text.utf8.count
                byteCount = try checkedAdd(byteCount, textBytes)
                guard byteCount <= limits.maximumOutputUTF8Bytes else {
                    throw MultiRowNumberedCopyWorkflowError.outputTooLarge(
                        maximumUTF8Bytes: limits.maximumOutputUTF8Bytes
                    )
                }
                guard byteCount <= intent.formatOptions.maximumOutputBytes else {
                    throw MultiRowNumberedCopyWorkflowError.numberedCopy(
                        .outputTooLarge(maximumBytes: intent.formatOptions.maximumOutputBytes)
                    )
                }
                parts.append(text)
                isFirstRow = false
            }
        }
        try work.checkCancellation()
        var output = parts.joined(separator: separator)
        if intent.formatOptions.includesTrailingRowSeparator, !parts.isEmpty {
            byteCount = try checkedAdd(byteCount, separatorBytes)
            guard byteCount <= limits.maximumOutputUTF8Bytes else {
                throw MultiRowNumberedCopyWorkflowError.outputTooLarge(
                    maximumUTF8Bytes: limits.maximumOutputUTF8Bytes
                )
            }
            output.append(separator)
        }
        try work.consume(UInt64(byteCount))
        return output
    }

    private static func validateForPlanning(
        _ snapshot: MultiRowNumberedCopyWorkflowSnapshot,
        limits: MultiRowNumberedCopyWorkflowLimits,
        work: inout WorkBudget
    ) throws -> Int {
        try validate(limits)
        try work.checkCancellation()
        guard snapshot.comparisonRows.count <= limits.maximumComparisonRows else {
            throw MultiRowNumberedCopyWorkflowError.tooManyComparisonRows(
                maximum: limits.maximumComparisonRows
            )
        }
        guard snapshot.selection.rowRanges.count <= limits.maximumSelectedRanges else {
            throw MultiRowNumberedCopyWorkflowError.tooManySelectedRanges(
                maximum: limits.maximumSelectedRanges
            )
        }
        guard snapshot.selection.selectedRowCount <= limits.maximumSelectedRows else {
            throw MultiRowNumberedCopyWorkflowError.tooManySelectedRows(
                maximum: limits.maximumSelectedRows
            )
        }
        guard snapshot.sourceReference.left.identity != snapshot.sourceReference.right.identity else {
            throw MultiRowNumberedCopyWorkflowError.stalePaneIdentity(.left)
        }
        let optionBytes = try validateComparisonOptions(
            snapshot.comparisonOptions,
            limits: limits,
            work: &work
        )
        let inputBytes = try utf8ByteCount(of: snapshot.source)
        guard inputBytes <= limits.maximumInputUTF8Bytes else {
            throw MultiRowNumberedCopyWorkflowError.inputTooLarge(
                maximumUTF8Bytes: limits.maximumInputUTF8Bytes
            )
        }
        let retainedRowTextBytes = try rowTextUTF8ByteCount(snapshot.comparisonRows, work: &work)
        guard retainedRowTextBytes <= limits.maximumRetainedUTF8Bytes else {
            throw MultiRowNumberedCopyWorkflowError.retainedDataTooLarge(
                maximumUTF8Bytes: limits.maximumRetainedUTF8Bytes
            )
        }
        try work.consume(UInt64(inputBytes))
        try work.consume(UInt64(retainedRowTextBytes))
        try work.consume(UInt64(snapshot.comparisonRows.count))
        try work.consume(UInt64(snapshot.selection.selectedRowCount))
        let retainedBaseEstimate = try checkedAdd(
            try checkedAdd(inputBytes, retainedRowTextBytes),
            optionBytes
        )
        guard retainedBaseEstimate <= limits.maximumRetainedUTF8Bytes else {
            throw MultiRowNumberedCopyWorkflowError.retainedDataTooLarge(
                maximumUTF8Bytes: limits.maximumRetainedUTF8Bytes
            )
        }
        _ = try normalizedRanges(snapshot.selection.rowRanges, rowCount: snapshot.comparisonRows.count)
        guard snapshot.selection.rowIDs.count == snapshot.selection.selectedRowCount else {
            throw MultiRowNumberedCopyWorkflowError.selectionChanged
        }
        var offset = 0
        for range in snapshot.selection.rowRanges {
            for index in range {
                try work.consume(1)
                guard snapshot.comparisonRows[index].id == snapshot.selection.rowIDs[offset] else {
                    throw MultiRowNumberedCopyWorkflowError.selectionChanged
                }
                offset += 1
            }
        }
        guard snapshot.selection.sourceRowCount == snapshot.comparisonRows.count else {
            throw MultiRowNumberedCopyWorkflowError.selectionChanged
        }
        return retainedBaseEstimate
    }

    private static func validate(_ limits: MultiRowNumberedCopyWorkflowLimits) throws {
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumComparisonRows).contains(limits.maximumComparisonRows) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonRows)
        }
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumSelectedRows).contains(limits.maximumSelectedRows) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.selectedRows)
        }
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumSelectedRanges).contains(limits.maximumSelectedRanges) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.selectedRanges)
        }
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumComparisonOptionItems).contains(limits.maximumComparisonOptionItems) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonOptionItems)
        }
        guard
            (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumComparisonOptionStringUTF8Bytes).contains(
                limits.maximumComparisonOptionStringUTF8Bytes
            )
        else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonOptionStringUTF8Bytes)
        }
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumComparisonOptionsUTF8Bytes).contains(limits.maximumComparisonOptionsUTF8Bytes) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonOptionsUTF8Bytes)
        }
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumInputUTF8Bytes).contains(limits.maximumInputUTF8Bytes) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.inputUTF8Bytes)
        }
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumRetainedUTF8Bytes).contains(limits.maximumRetainedUTF8Bytes) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.retainedUTF8Bytes)
        }
        guard (0...MultiRowNumberedCopyWorkflowLimits.hardMaximumOutputUTF8Bytes).contains(limits.maximumOutputUTF8Bytes) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.outputUTF8Bytes)
        }
        guard limits.maximumWorkUnits <= MultiRowNumberedCopyWorkflowLimits.hardMaximumWorkUnits else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.workUnits)
        }
        guard (1...MultiRowNumberedCopyWorkflowLimits.hardMaximumCancellationCheckInterval).contains(limits.cancellationCheckInterval) else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.cancellationCheckInterval)
        }
    }

    private static func validateComparisonOptions(
        _ options: LineDiffOptions,
        limits: MultiRowNumberedCopyWorkflowLimits,
        work: inout WorkBudget
    ) throws -> Int {
        guard options.lineFilters.count <= limits.maximumComparisonOptionItems,
            options.substitutions.count <= limits.maximumComparisonOptionItems
        else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonOptionItems)
        }
        var byteCount = 0
        for rule in options.lineFilters {
            try work.consume(1)
            let bytes = rule.pattern.utf8.count
            guard bytes <= limits.maximumComparisonOptionStringUTF8Bytes else {
                throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonOptionStringUTF8Bytes)
            }
            byteCount = try checkedAdd(byteCount, bytes)
        }
        for rule in options.substitutions {
            try work.consume(1)
            let bytes = try checkedAdd(rule.pattern.utf8.count, rule.replacement.utf8.count)
            guard bytes <= limits.maximumComparisonOptionStringUTF8Bytes else {
                throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonOptionStringUTF8Bytes)
            }
            byteCount = try checkedAdd(byteCount, bytes)
        }
        guard byteCount <= limits.maximumComparisonOptionsUTF8Bytes else {
            throw MultiRowNumberedCopyWorkflowError.invalidLimit(.comparisonOptionsUTF8Bytes)
        }
        return byteCount
    }

    private static func utf8ByteCount(of snapshot: ComparisonSnapshot) throws -> Int {
        let leftCount = snapshot.left.utf8.count
        let rightCount = snapshot.right.utf8.count
        let (total, overflow) = leftCount.addingReportingOverflow(rightCount)
        guard !overflow else {
            throw MultiRowNumberedCopyWorkflowError.arithmeticOverflow
        }
        return total
    }

    private static func rowTextUTF8ByteCount(
        _ rows: [DiffRow],
        work: inout WorkBudget
    ) throws -> Int {
        var total = 0
        for row in rows {
            try work.consume(1)
            let leftBytes = row.left?.text.utf8.count ?? 0
            let rightBytes = row.right?.text.utf8.count ?? 0
            total = try checkedAdd(total, try checkedAdd(leftBytes, rightBytes))
        }
        return total
    }

    private static func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow else {
            throw MultiRowNumberedCopyWorkflowError.arithmeticOverflow
        }
        return result
    }

    private struct WorkBudget {
        let maximumWork: UInt64
        let checkInterval: UInt64
        private(set) var consumed: UInt64 = 0
        private var unitsSinceCheck: UInt64 = 0

        init(limits: MultiRowNumberedCopyWorkflowLimits) throws {
            guard limits.maximumWorkUnits <= MultiRowNumberedCopyWorkflowLimits.hardMaximumWorkUnits else {
                throw MultiRowNumberedCopyWorkflowError.invalidLimit(.workUnits)
            }
            maximumWork = limits.maximumWorkUnits
            checkInterval = limits.cancellationCheckInterval
        }

        mutating func consume(_ units: UInt64 = 1) throws {
            let (next, overflow) = consumed.addingReportingOverflow(units)
            guard !overflow, next <= maximumWork else {
                throw MultiRowNumberedCopyWorkflowError.workLimitExceeded(maximumUnits: maximumWork)
            }
            consumed = next
            unitsSinceCheck += units
            if unitsSinceCheck >= checkInterval {
                try checkCancellation()
            }
        }

        mutating func checkCancellation() throws {
            do {
                try Task.checkCancellation()
            } catch is CancellationError {
                throw MultiRowNumberedCopyWorkflowError.cancelled
            }
            unitsSinceCheck = 0
        }

        mutating func finish() throws {
            try checkCancellation()
        }
    }
}

extension MultiRowNumberedCopyWorkflowLimits: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "MultiRowNumberedCopyWorkflowLimits(comparisonRows: \(maximumComparisonRows), selectedRows: \(maximumSelectedRows), outputBytes: \(maximumOutputUTF8Bytes), workUnits: \(maximumWorkUnits), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "maximumComparisonRows": maximumComparisonRows,
                "maximumSelectedRows": maximumSelectedRows,
                "maximumSelectedRanges": maximumSelectedRanges,
                "maximumOutputUTF8Bytes": maximumOutputUTF8Bytes,
                "maximumWorkUnits": maximumWorkUnits,
                "cancellationCheckInterval": cancellationCheckInterval,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiRowNumberedCopyWorkflowSnapshot: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "MultiRowNumberedCopyWorkflowSnapshot(comparisonRows: \(comparisonRows.count), selectedRows: \(selection.selectedRowCount), ranges: \(selection.rowRanges.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "comparisonReference": comparisonReference,
                "selectionReference": selectionReference,
                "comparisonRowCount": comparisonRows.count,
                "selectedRowCount": selection.selectedRowCount,
                "selectedRangeCount": selection.rowRanges.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiRowNumberedCopyWorkflowSelectionBinding: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "MultiRowNumberedCopyWorkflowSelectionBinding(rows: \(selectedRowCount), ranges: \(rowRanges.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "selectedRowCount": selectedRowCount,
                "selectedRangeCount": rowRanges.count,
                "sourceRowCount": sourceRowCount,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiRowNumberedCopyWorkflowPlanningReceipt: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "MultiRowNumberedCopyWorkflowPlanningReceipt(side: \(intentSide.rawValue), style: \(intentStyle.rawValue), origin: \(intentOrigin.rawValue), rows: \(selectedRowCount), payloadBytes: \(payloadUTF8ByteCount), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "expectedSnapshot": expectedSnapshot,
                "intentSide": intentSide,
                "intentStyle": intentStyle,
                "intentOrigin": intentOrigin,
                "selectedRowCount": selectedRowCount,
                "selectedRangeCount": selectedRangeCount,
                "payloadUTF8ByteCount": payloadUTF8ByteCount,
                "retainedUTF8ByteEstimate": retainedUTF8ByteEstimate,
                "workflowWorkUnitsConsumed": workflowWorkUnitsConsumed,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiRowNumberedCopyWorkflowSnapshotCAS: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "MultiRowNumberedCopyWorkflowSnapshotCAS(contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["reference": reference, "contents": "<redacted>"],
            displayStyle: .struct
        )
    }
}

extension MultiRowNumberedCopyWorkflowPlan: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "MultiRowNumberedCopyWorkflowPlan(side: \(intent.side.rawValue), style: \(intent.style.rawValue), rows: \(selection.selectedRowCount), payloadBytes: \(receipt.payloadUTF8ByteCount), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "expectedSnapshot": expectedSnapshot,
                "intentSide": intent.side,
                "intentStyle": intent.style,
                "selectedRowCount": selection.selectedRowCount,
                "payloadUTF8ByteCount": receipt.payloadUTF8ByteCount,
                "requiredEffectCount": requiredEffects.count,
                "executorContract": executorContract,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiRowNumberedCopyWorkflowRequiredEffect: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "MultiRowNumberedCopyWorkflowRequiredEffect(copyPayloadToOwnerTransferService, payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["effect": "copyPayloadToOwnerTransferService", "payload": "<redacted>"], displayStyle: .enum)
    }
}
