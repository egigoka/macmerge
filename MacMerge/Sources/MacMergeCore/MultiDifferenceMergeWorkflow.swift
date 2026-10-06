import Foundation

public struct MultiDifferenceMergeWorkflowComparisonIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct MultiDifferenceMergeWorkflowSourceIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct MultiDifferenceMergeWorkflowSelectionIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct MultiDifferenceMergeWorkflowPaneIdentity: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum MultiDifferenceMergeWorkflowPane: String, CaseIterable, Equatable, Hashable, Sendable {
    case left
    case right
}

/// Exact owner-issued pane revision. An owner must never reuse one identity/revision pair for
/// different text, editability, or dirty state.
public struct MultiDifferenceMergeWorkflowPaneRevision: Equatable, Hashable, Sendable {
    public let identity: MultiDifferenceMergeWorkflowPaneIdentity
    public let revision: UInt64

    public init(identity: MultiDifferenceMergeWorkflowPaneIdentity, revision: UInt64) {
        self.identity = identity
        self.revision = revision
    }
}

/// Exact identity of both source panes. `revision` must advance whenever either pane binding or any
/// source text changes.
public struct MultiDifferenceMergeWorkflowSourceReference: Equatable, Hashable, Sendable {
    public let identity: MultiDifferenceMergeWorkflowSourceIdentity
    public let revision: UInt64
    public let left: MultiDifferenceMergeWorkflowPaneRevision
    public let right: MultiDifferenceMergeWorkflowPaneRevision

    public init(
        identity: MultiDifferenceMergeWorkflowSourceIdentity,
        revision: UInt64,
        left: MultiDifferenceMergeWorkflowPaneRevision,
        right: MultiDifferenceMergeWorkflowPaneRevision
    ) {
        self.identity = identity
        self.revision = revision
        self.left = left
        self.right = right
    }

    public subscript(pane: MultiDifferenceMergeWorkflowPane) -> MultiDifferenceMergeWorkflowPaneRevision {
        switch pane {
        case .left: left
        case .right: right
        }
    }
}

/// Identity of aligned rows produced from one exact source reference.
public struct MultiDifferenceMergeWorkflowComparisonReference: Equatable, Hashable, Sendable {
    public let identity: MultiDifferenceMergeWorkflowComparisonIdentity
    public let revision: UInt64
    public let source: MultiDifferenceMergeWorkflowSourceReference

    public init(
        identity: MultiDifferenceMergeWorkflowComparisonIdentity,
        revision: UInt64,
        source: MultiDifferenceMergeWorkflowSourceReference
    ) {
        self.identity = identity
        self.revision = revision
        self.source = source
    }
}

/// Identity of one exact selection interpretation against one exact comparison.
public struct MultiDifferenceMergeWorkflowSelectionReference: Equatable, Hashable, Sendable {
    public let identity: MultiDifferenceMergeWorkflowSelectionIdentity
    public let revision: UInt64
    public let comparison: MultiDifferenceMergeWorkflowComparisonReference

    public init(
        identity: MultiDifferenceMergeWorkflowSelectionIdentity,
        revision: UInt64,
        comparison: MultiDifferenceMergeWorkflowComparisonReference
    ) {
        self.identity = identity
        self.revision = revision
        self.comparison = comparison
    }
}

public struct MultiDifferenceMergeWorkflowSnapshotReference: Equatable, Hashable, Sendable {
    public let comparison: MultiDifferenceMergeWorkflowComparisonReference
    public let selection: MultiDifferenceMergeWorkflowSelectionReference

    fileprivate init(
        comparison: MultiDifferenceMergeWorkflowComparisonReference,
        selection: MultiDifferenceMergeWorkflowSelectionReference
    ) {
        self.comparison = comparison
        self.selection = selection
    }
}

/// Public, value-only binding for every selected row and every full maximal difference group.
/// Executors must retain this grouping; replacing it with only `rowRange` loses command meaning.
public struct MultiDifferenceMergeWorkflowSelectionBinding: Equatable, Sendable {
    public struct DifferenceGroup: Equatable, Sendable {
        public let id: MultiDifferenceSelection.DifferenceRun.ID
        public let rowRange: Range<Int>
        public let selectionIntersection: Range<Int>
        public let rowIDs: [DiffRow.ID]
        public let leftSourceRowCount: Int
        public let rightSourceRowCount: Int

        fileprivate init(_ run: MultiDifferenceSelection.DifferenceRun) {
            id = run.id
            rowRange = run.rowRange
            selectionIntersection = run.selectionIntersection
            rowIDs = run.rowIDs
            leftSourceRowCount = run.leftSourceRowCount
            rightSourceRowCount = run.rightSourceRowCount
        }
    }

    public let reference: MultiDifferenceMergeWorkflowSelectionReference
    public let rowRange: Range<Int>
    public let selectedRowIDs: [DiffRow.ID]
    public let differenceGroups: [DifferenceGroup]
    public let sourceRowCount: Int

    fileprivate init(
        reference: MultiDifferenceMergeWorkflowSelectionReference,
        selection: MultiDifferenceSelection
    ) {
        self.reference = reference
        rowRange = selection.rowRange
        selectedRowIDs = selection.selectedRowIDs
        differenceGroups = selection.differenceRuns.map(DifferenceGroup.init)
        sourceRowCount = selection.sourceRowCount
    }
}

/// Immutable owner state. References provide cheap stale checks; exact retained values detect owners
/// that incorrectly reuse revisions.
public struct MultiDifferenceMergeWorkflowSnapshot: Equatable, Sendable {
    public let comparisonReference: MultiDifferenceMergeWorkflowComparisonReference
    public let selectionReference: MultiDifferenceMergeWorkflowSelectionReference
    public let source: ComparisonSnapshot
    public let comparisonRows: [DiffRow]
    public let comparisonOptions: LineDiffOptions
    public let selection: MultiDifferenceSelection
    public let left: MergeCommandPolicy.SideState
    public let right: MergeCommandPolicy.SideState
    public let comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle

    public init(
        comparisonIdentity: MultiDifferenceMergeWorkflowComparisonIdentity,
        comparisonRevision: UInt64,
        sourceIdentity: MultiDifferenceMergeWorkflowSourceIdentity,
        sourceRevision: UInt64,
        leftPaneRevision: MultiDifferenceMergeWorkflowPaneRevision,
        rightPaneRevision: MultiDifferenceMergeWorkflowPaneRevision,
        selectionIdentity: MultiDifferenceMergeWorkflowSelectionIdentity,
        selectionRevision: UInt64,
        source: ComparisonSnapshot,
        comparisonRows: [DiffRow],
        comparisonOptions: LineDiffOptions = LineDiffOptions(),
        selection: MultiDifferenceSelection,
        left: MergeCommandPolicy.SideState,
        right: MergeCommandPolicy.SideState,
        comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle = .currentSuccess
    ) {
        let sourceReference = MultiDifferenceMergeWorkflowSourceReference(
            identity: sourceIdentity,
            revision: sourceRevision,
            left: leftPaneRevision,
            right: rightPaneRevision
        )
        let comparisonReference = MultiDifferenceMergeWorkflowComparisonReference(
            identity: comparisonIdentity,
            revision: comparisonRevision,
            source: sourceReference
        )
        self.comparisonReference = comparisonReference
        selectionReference = MultiDifferenceMergeWorkflowSelectionReference(
            identity: selectionIdentity,
            revision: selectionRevision,
            comparison: comparisonReference
        )
        self.source = source
        self.comparisonRows = comparisonRows
        self.comparisonOptions = comparisonOptions
        self.selection = selection
        self.left = left
        self.right = right
        self.comparisonLifecycle = comparisonLifecycle
    }

    public var sourceReference: MultiDifferenceMergeWorkflowSourceReference {
        comparisonReference.source
    }

    public var reference: MultiDifferenceMergeWorkflowSnapshotReference {
        MultiDifferenceMergeWorkflowSnapshotReference(
            comparison: comparisonReference,
            selection: selectionReference
        )
    }

    public var selectionBinding: MultiDifferenceMergeWorkflowSelectionBinding {
        MultiDifferenceMergeWorkflowSelectionBinding(
            reference: selectionReference,
            selection: selection
        )
    }
}

public enum MultiDifferenceMergeWorkflowAdvanceIntent: String, CaseIterable, Equatable, Hashable, Sendable {
    case remain
    case advanceToNextDifference
}

public struct MultiDifferenceMergeWorkflowCommandIntent: Equatable, Sendable {
    public let direction: MergeDirection
    public let advance: MultiDifferenceMergeWorkflowAdvanceIntent

    public init(
        direction: MergeDirection,
        advance: MultiDifferenceMergeWorkflowAdvanceIntent = .remain
    ) {
        self.direction = direction
        self.advance = advance
    }

    public var copyAndAdvance: Bool { advance == .advanceToNextDifference }

    public var policyCommand: MergeCommandPolicy.Command {
        switch (direction, advance) {
        case (.leftToRight, .remain): .leftToRight
        case (.rightToLeft, .remain): .rightToLeft
        case (.leftToRight, .advanceToNextDifference): .leftToRightAndAdvance
        case (.rightToLeft, .advanceToNextDifference): .rightToLeftAndAdvance
        }
    }
}

public enum MultiDifferenceMergeWorkflowLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case comparisonRows
    case selectedRows
    case differenceGroups
    case comparisonOptionItems
    case comparisonOptionStringUTF8Bytes
    case comparisonOptionsUTF8Bytes
    case inputUTF8Bytes
    case retainedUTF8Bytes
    case mergeOperations
    case mergeOutputUTF8Bytes
    case primitiveWorkUnits
    case selectionWorkUnits
    case workUnits
    case cancellationCheckInterval
}

public struct MultiDifferenceMergeWorkflowLimits: Equatable, Sendable {
    public static let hardMaximumComparisonRows = 1_048_576
    public static let hardMaximumSelectedRows = 1_048_576
    public static let hardMaximumDifferenceGroups = 65_536
    public static let hardMaximumComparisonOptionItems = 65_536
    public static let hardMaximumComparisonOptionStringUTF8Bytes = 256 * 1_024
    public static let hardMaximumComparisonOptionsUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumInputUTF8Bytes = 512 * 1_024 * 1_024
    public static let hardMaximumRetainedUTF8Bytes = 1 * 1_024 * 1_024 * 1_024
    public static let hardMaximumMergeOperations = 1_048_576
    public static let hardMaximumMergeOutputUTF8Bytes = 512 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 42
    public static let hardMaximumCancellationCheckInterval: UInt64 = 4_096
    public static let `default` = MultiDifferenceMergeWorkflowLimits()

    public let maximumComparisonRows: Int
    public let maximumSelectedRows: Int
    public let maximumDifferenceGroups: Int
    public let maximumComparisonOptionItems: Int
    public let maximumComparisonOptionStringUTF8Bytes: Int
    public let maximumComparisonOptionsUTF8Bytes: Int
    public let maximumInputUTF8Bytes: Int
    public let maximumRetainedUTF8Bytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64
    public let selection: MultiDifferenceSelectionLimits
    public let merge: MultiDifferenceMergeOptions

    public init(
        maximumComparisonRows: Int = MultiDifferenceMergeOptions.defaultMaximumComparedRows,
        maximumSelectedRows: Int = MultiDifferenceSelectionLimits.defaultMaximumRows,
        maximumDifferenceGroups: Int = MultiDifferenceMergeOptions.defaultMaximumChangeGroups,
        maximumComparisonOptionItems: Int = 4_096,
        maximumComparisonOptionStringUTF8Bytes: Int = 64 * 1_024,
        maximumComparisonOptionsUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumInputUTF8Bytes: Int = 256 * 1_024 * 1_024,
        maximumRetainedUTF8Bytes: Int = 512 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 1_024,
        selection: MultiDifferenceSelectionLimits = .default,
        merge: MultiDifferenceMergeOptions = MultiDifferenceMergeOptions()
    ) {
        self.maximumComparisonRows = maximumComparisonRows
        self.maximumSelectedRows = maximumSelectedRows
        self.maximumDifferenceGroups = maximumDifferenceGroups
        self.maximumComparisonOptionItems = maximumComparisonOptionItems
        self.maximumComparisonOptionStringUTF8Bytes = maximumComparisonOptionStringUTF8Bytes
        self.maximumComparisonOptionsUTF8Bytes = maximumComparisonOptionsUTF8Bytes
        self.maximumInputUTF8Bytes = maximumInputUTF8Bytes
        self.maximumRetainedUTF8Bytes = maximumRetainedUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
        self.selection = selection
        self.merge = merge
    }
}

public struct MultiDifferenceMergeWorkflowCommandState: Equatable, Sendable {
    public let intent: MultiDifferenceMergeWorkflowCommandIntent
    public let expectedSnapshot: MultiDifferenceMergeWorkflowSnapshotReference
    public let selection: MultiDifferenceMergeWorkflowSelectionBinding
    public let availability: MergeCommandPolicy.Availability
    public let workUnitsConsumed: UInt64

    fileprivate init(
        intent: MultiDifferenceMergeWorkflowCommandIntent,
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        availability: MergeCommandPolicy.Availability,
        workUnitsConsumed: UInt64
    ) {
        self.intent = intent
        expectedSnapshot = snapshot.reference
        selection = snapshot.selectionBinding
        self.availability = availability
        self.workUnitsConsumed = workUnitsConsumed
    }

    public var isEnabled: Bool { availability.isEnabled }
    public var canExecute: Bool { isEnabled }
    public var disabledReason: MergeCommandPolicy.DisabledReason? { availability.disabledReason }
}

/// Exact call made to `MultiDifferenceMerge.apply`. Selection groups accompany the primitive's raw
/// range so downstream code cannot reinterpret which full differences were selected.
public struct MultiDifferenceMergeWorkflowPrimitiveInvocation: Equatable, Sendable {
    public let state: MultiDifferenceMergeState
    public let selectedAlignedRows: Range<Int>
    public let selection: MultiDifferenceMergeWorkflowSelectionBinding
    public let direction: MergeDirection
    public let options: MultiDifferenceMergeOptions

    fileprivate init(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        direction: MergeDirection,
        options: MultiDifferenceMergeOptions
    ) {
        state = MultiDifferenceMergeState(
            source: snapshot.source,
            comparisonRows: snapshot.comparisonRows,
            left: snapshot.left,
            right: snapshot.right,
            comparisonLifecycle: snapshot.comparisonLifecycle
        )
        selectedAlignedRows = snapshot.selection.rowRange
        selection = snapshot.selectionBinding
        self.direction = direction
        self.options = MultiDifferenceMergeOptions(
            lineDiff: snapshot.comparisonOptions,
            maximumComparedRows: options.maximumComparedRows,
            maximumChangeGroups: options.maximumChangeGroups,
            maximumMergeOperations: options.maximumMergeOperations,
            maximumOutputBytes: options.maximumOutputBytes,
            maximumWork: options.maximumWork
        )
    }
}

public enum MultiDifferenceMergeWorkflowUndoIntent: String, CaseIterable, Equatable, Hashable, Sendable {
    case recordExactPredecessorComparison
}

public enum MultiDifferenceMergeWorkflowDirtyIntent: String, CaseIterable, Equatable, Hashable, Sendable {
    case markDestinationDirty
}

public struct MultiDifferenceMergeWorkflowSuccessorDifferenceTarget: Equatable, Sendable {
    public struct ID: Equatable, Hashable, Sendable {
        public let comparison: MultiDifferenceMergeWorkflowComparisonReference
        public let firstRowID: DiffRow.ID
        public let lastRowID: DiffRow.ID

        fileprivate init(
            comparison: MultiDifferenceMergeWorkflowComparisonReference,
            firstRowID: DiffRow.ID,
            lastRowID: DiffRow.ID
        ) {
            self.comparison = comparison
            self.firstRowID = firstRowID
            self.lastRowID = lastRowID
        }
    }

    public let id: ID
    public let comparison: MultiDifferenceMergeWorkflowComparisonReference
    public let rowRange: Range<Int>
    public let rowIDs: [DiffRow.ID]

    fileprivate init(
        comparison: MultiDifferenceMergeWorkflowComparisonReference,
        rowRange: Range<Int>,
        rowIDs: [DiffRow.ID]
    ) {
        precondition(!rowIDs.isEmpty)
        id = ID(
            comparison: comparison,
            firstRowID: rowIDs[0],
            lastRowID: rowIDs[rowIDs.count - 1]
        )
        self.comparison = comparison
        self.rowRange = rowRange
        self.rowIDs = rowIDs
    }
}

/// Exact comparison value and generation an executor must publish after owner commit.
public struct MultiDifferenceMergeWorkflowSuccessorComparison: Equatable, Sendable {
    public let reference: MultiDifferenceMergeWorkflowComparisonReference
    public let source: ComparisonSnapshot
    public let rows: [DiffRow]
    public let options: LineDiffOptions
    public let optionsGeneration: MultiDifferenceMergeWorkflowComparisonReference

    fileprivate init(
        reference: MultiDifferenceMergeWorkflowComparisonReference,
        source: ComparisonSnapshot,
        rows: [DiffRow],
        options: LineDiffOptions
    ) {
        self.reference = reference
        self.source = source
        self.rows = rows
        self.options = options
        optionsGeneration = reference
    }
}

/// Publication CAS input. The owner must still hold this exact committed source and invalidated
/// comparison/options generation before replacing it with `successor`.
public struct MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent: Equatable, Sendable {
    public let expectedSource: MultiDifferenceMergeWorkflowSourceReference
    public let expectedSourceContents: ComparisonSnapshot
    public let expectedInvalidatedComparison: MultiDifferenceMergeWorkflowComparisonReference
    public let expectedComparisonOptions: LineDiffOptions
    public let expectedComparisonOptionsGeneration: MultiDifferenceMergeWorkflowComparisonReference
    public let successor: MultiDifferenceMergeWorkflowSuccessorComparison

    fileprivate init(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        successor: MultiDifferenceMergeWorkflowSuccessorComparison
    ) {
        expectedSource = successor.reference.source
        expectedSourceContents = successor.source
        expectedInvalidatedComparison = snapshot.comparisonReference
        expectedComparisonOptions = snapshot.comparisonOptions
        expectedComparisonOptionsGeneration = snapshot.comparisonReference
        self.successor = successor
    }
}

public enum MultiDifferenceMergeWorkflowSuccessorSelectionIntent: Equatable, Sendable {
    case clear(comparison: MultiDifferenceMergeWorkflowComparisonReference)
    case selectResolvedNextDifference(
        comparison: MultiDifferenceMergeWorkflowComparisonReference,
        target: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?,
        wraps: Bool
    )
}

public enum MultiDifferenceMergeWorkflowNavigationIntent: Equatable, Sendable {
    case none
    case publishResolvedNextDifference(
        comparison: MultiDifferenceMergeWorkflowComparisonReference,
        target: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?,
        wraps: Bool
    )
}

public struct MultiDifferenceMergeWorkflowTransactionIdentity: Equatable, Hashable, Sendable {
    public let nonce: UUID
    public let snapshot: MultiDifferenceMergeWorkflowSnapshotReference
    public let command: MergeCommandPolicy.Command

    fileprivate init(
        nonce: UUID,
        snapshot: MultiDifferenceMergeWorkflowSnapshotReference,
        command: MergeCommandPolicy.Command
    ) {
        self.nonce = nonce
        self.snapshot = snapshot
        self.command = command
    }
}

public struct MultiDifferenceMergeWorkflowPlanReference: Equatable, Hashable, Sendable {
    public let transaction: MultiDifferenceMergeWorkflowTransactionIdentity
    public let successorSource: MultiDifferenceMergeWorkflowSourceReference
    public let successorDestination: MultiDifferenceMergeWorkflowPaneRevision
    public let successorComparison: MultiDifferenceMergeWorkflowComparisonReference
    public let successorNavigationTarget: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget.ID?

    fileprivate init(transaction: MultiDifferenceMergeWorkflowTransaction) {
        self.transaction = transaction.id
        successorSource = transaction.successorSource
        successorDestination = transaction.successorDestinationRevision
        successorComparison = transaction.successorComparison.reference
        successorNavigationTarget = transaction.successorNavigationTarget?.id
    }
}

public struct MultiDifferenceMergeWorkflowTransaction: Equatable, Sendable {
    public let id: MultiDifferenceMergeWorkflowTransactionIdentity
    public let expectedState: MultiDifferenceMergeWorkflowSnapshot
    public let expectedSnapshot: MultiDifferenceMergeWorkflowSnapshotReference
    public let expectedSource: MultiDifferenceMergeWorkflowSourceReference
    public let successorSource: MultiDifferenceMergeWorkflowSourceReference
    public let destination: MultiDifferenceMergeWorkflowPane
    public let expectedDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision
    public let successorDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision
    public let expectedDestinationState: MergeCommandPolicy.SideState
    public let successorDestinationState: MergeCommandPolicy.SideState
    public let predecessor: ComparisonSnapshot
    public let successor: ComparisonSnapshot
    public let successorComparison: MultiDifferenceMergeWorkflowSuccessorComparison
    public let successorComparisonPublication: MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent
    public let successorNavigationTarget: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?
    public let direction: MergeDirection
    public let selection: MultiDifferenceMergeWorkflowSelectionBinding
    public let changedGroups: [MultiDifferenceMergeChangeGroup]
    public let undoIntent: MultiDifferenceMergeWorkflowUndoIntent
    public let dirtyIntent: MultiDifferenceMergeWorkflowDirtyIntent
    public let successorSelectionIntent: MultiDifferenceMergeWorkflowSuccessorSelectionIntent
    public let navigationIntent: MultiDifferenceMergeWorkflowNavigationIntent

    fileprivate init(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        result: MultiDifferenceMergeResult,
        intent: MultiDifferenceMergeWorkflowCommandIntent,
        successorComparison: MultiDifferenceMergeWorkflowSuccessorComparison,
        successorNavigationTarget: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?,
        successorDestination: MultiDifferenceMergeWorkflowPaneRevision
    ) {
        let destination: MultiDifferenceMergeWorkflowPane = intent.direction == .leftToRight ? .right : .left
        id = MultiDifferenceMergeWorkflowTransactionIdentity(
            nonce: UUID(),
            snapshot: snapshot.reference,
            command: intent.policyCommand
        )
        expectedState = snapshot
        expectedSnapshot = snapshot.reference
        expectedSource = snapshot.sourceReference
        successorSource = successorComparison.reference.source
        self.destination = destination
        expectedDestinationRevision = snapshot.sourceReference[destination]
        successorDestinationRevision = successorDestination
        expectedDestinationState = destination == .left ? snapshot.left : snapshot.right
        successorDestinationState = MergeCommandPolicy.SideState(
            isLoaded: expectedDestinationState.isLoaded,
            isEditable: expectedDestinationState.isEditable,
            isDirty: true
        )
        predecessor = snapshot.source
        successor = result.snapshot
        self.successorComparison = successorComparison
        successorComparisonPublication = MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent(
            snapshot: snapshot,
            successor: successorComparison
        )
        self.successorNavigationTarget = successorNavigationTarget
        direction = intent.direction
        selection = snapshot.selectionBinding
        changedGroups = result.changedGroups
        undoIntent = .recordExactPredecessorComparison
        dirtyIntent = .markDestinationDirty
        switch intent.advance {
        case .remain:
            successorSelectionIntent = .clear(comparison: successorComparison.reference)
            navigationIntent = .none
        case .advanceToNextDifference:
            successorSelectionIntent = .selectResolvedNextDifference(
                comparison: successorComparison.reference,
                target: successorNavigationTarget,
                wraps: false
            )
            navigationIntent = .publishResolvedNextDifference(
                comparison: successorComparison.reference,
                target: successorNavigationTarget,
                wraps: false
            )
        }
    }
}

public enum MultiDifferenceMergeWorkflowRequiredEffect: Equatable, Sendable {
    /// One owner-isolated CAS commits destination text/revision, undo, dirty state, successor
    /// selection intent, and comparison invalidation. It is never split into smaller effects.
    case commitOwnerTransaction
    case publishSuccessorComparison(MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent)
    case publishNavigation(MultiDifferenceMergeWorkflowNavigationIntent)
}

public enum MultiDifferenceMergeWorkflowExecutorPreflightContract: String, Equatable, Hashable, Sendable {
    case validateExactSnapshotCASAndAllEffectCapabilitiesBeforeFirstEffect
}

public enum MultiDifferenceMergeWorkflowExecutorCASContract: String, Equatable, Hashable, Sendable {
    case atomicExactSnapshotAndDestinationPaneRevisionCompareAndSwap
}

public enum MultiDifferenceMergeWorkflowExecutorMutationContract: String, Equatable, Hashable, Sendable {
    case commitExactTextRevisionUndoDirtySelectionAndInvalidationInOneOwnerTransaction
}

public enum MultiDifferenceMergeWorkflowExecutorPublicationContract: String, Equatable, Hashable, Sendable {
    case atomicSourceComparisonAndOptionsCASThenNavigationInPlanOrder
}

public enum MultiDifferenceMergeWorkflowExecutorCancellationContract: String, Equatable, Hashable, Sendable {
    case cancellableBeforeCommitOrCompletedFailedOrUncertainAfterCommitStarts
}

public enum MultiDifferenceMergeWorkflowExecutorOutcomeContract: String, Equatable, Hashable, Sendable {
    case neverReportNoMutationAfterCommitStartsAndNeverHidePartialPublication
}

/// Mandatory app-layer boundary. This workflow performs no UI work and no live text mutation.
public struct MultiDifferenceMergeWorkflowExecutorContract: Equatable, Hashable, Sendable {
    public static let required = MultiDifferenceMergeWorkflowExecutorContract()

    public let preflight = MultiDifferenceMergeWorkflowExecutorPreflightContract.validateExactSnapshotCASAndAllEffectCapabilitiesBeforeFirstEffect
    public let compareAndSwap = MultiDifferenceMergeWorkflowExecutorCASContract.atomicExactSnapshotAndDestinationPaneRevisionCompareAndSwap
    public let mutation =
        MultiDifferenceMergeWorkflowExecutorMutationContract.commitExactTextRevisionUndoDirtySelectionAndInvalidationInOneOwnerTransaction
    public let publication = MultiDifferenceMergeWorkflowExecutorPublicationContract.atomicSourceComparisonAndOptionsCASThenNavigationInPlanOrder
    public let cancellation = MultiDifferenceMergeWorkflowExecutorCancellationContract.cancellableBeforeCommitOrCompletedFailedOrUncertainAfterCommitStarts
    public let outcome = MultiDifferenceMergeWorkflowExecutorOutcomeContract.neverReportNoMutationAfterCommitStartsAndNeverHidePartialPublication

    public init() {}
}

public struct MultiDifferenceMergeWorkflowPlanningReceipt: Equatable, Sendable {
    public let expectedSnapshot: MultiDifferenceMergeWorkflowSnapshotReference
    public let intent: MultiDifferenceMergeWorkflowCommandIntent
    public let selection: MultiDifferenceMergeWorkflowSelectionBinding
    public let destination: MultiDifferenceMergeWorkflowPane
    public let expectedDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision
    public let successorDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision
    public let successorSource: MultiDifferenceMergeWorkflowSourceReference
    public let successorComparison: MultiDifferenceMergeWorkflowSuccessorComparison
    public let successorNavigationTarget: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?
    public let successorSelectionIntent: MultiDifferenceMergeWorkflowSuccessorSelectionIntent
    public let navigationIntent: MultiDifferenceMergeWorkflowNavigationIntent
    public let changedGroups: [MultiDifferenceMergeChangeGroup]
    public let resultUTF8ByteCount: Int
    public let retainedUTF8ByteEstimate: Int
    public let workflowWorkUnitsConsumed: UInt64
    public let primitiveMaximumWork: Int

    fileprivate init(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        intent: MultiDifferenceMergeWorkflowCommandIntent,
        transaction: MultiDifferenceMergeWorkflowTransaction,
        resultUTF8ByteCount: Int,
        retainedUTF8ByteEstimate: Int,
        workflowWorkUnitsConsumed: UInt64,
        primitiveMaximumWork: Int
    ) {
        expectedSnapshot = snapshot.reference
        self.intent = intent
        selection = snapshot.selectionBinding
        destination = transaction.destination
        expectedDestinationRevision = transaction.expectedDestinationRevision
        successorDestinationRevision = transaction.successorDestinationRevision
        successorSource = transaction.successorSource
        successorComparison = transaction.successorComparison
        successorNavigationTarget = transaction.successorNavigationTarget
        successorSelectionIntent = transaction.successorSelectionIntent
        navigationIntent = transaction.navigationIntent
        changedGroups = transaction.changedGroups
        self.resultUTF8ByteCount = resultUTF8ByteCount
        self.retainedUTF8ByteEstimate = retainedUTF8ByteEstimate
        self.workflowWorkUnitsConsumed = workflowWorkUnitsConsumed
        self.primitiveMaximumWork = primitiveMaximumWork
    }
}

public struct MultiDifferenceMergeWorkflowSnapshotCAS: Equatable, Sendable {
    public let reference: MultiDifferenceMergeWorkflowSnapshotReference

    private let snapshot: MultiDifferenceMergeWorkflowSnapshot

    fileprivate init(snapshot: MultiDifferenceMergeWorkflowSnapshot) {
        reference = snapshot.reference
        self.snapshot = snapshot
    }

    public func matches(_ current: MultiDifferenceMergeWorkflowSnapshot) throws -> Bool {
        do {
            try validate(current)
            return true
        } catch let error as MultiDifferenceMergeWorkflowError where error.isStaleValidationFailure {
            return false
        }
    }

    public func validate(_ current: MultiDifferenceMergeWorkflowSnapshot) throws {
        try MultiDifferenceMergeWorkflow.validateCurrentSnapshot(
            current,
            expected: snapshot
        )
    }
}

public struct MultiDifferenceMergeWorkflowPlan: Equatable, Sendable {
    public let reference: MultiDifferenceMergeWorkflowPlanReference
    public let expectedSnapshotCAS: MultiDifferenceMergeWorkflowSnapshotCAS
    public let primitiveInvocation: MultiDifferenceMergeWorkflowPrimitiveInvocation
    public let mergeResult: MultiDifferenceMergeResult
    public let transaction: MultiDifferenceMergeWorkflowTransaction
    public let receipt: MultiDifferenceMergeWorkflowPlanningReceipt
    public let requiredEffects: [MultiDifferenceMergeWorkflowRequiredEffect]
    public let limits: MultiDifferenceMergeWorkflowLimits
    public let executorContract: MultiDifferenceMergeWorkflowExecutorContract

    fileprivate init(
        expectedSnapshotCAS: MultiDifferenceMergeWorkflowSnapshotCAS,
        primitiveInvocation: MultiDifferenceMergeWorkflowPrimitiveInvocation,
        mergeResult: MultiDifferenceMergeResult,
        transaction: MultiDifferenceMergeWorkflowTransaction,
        receipt: MultiDifferenceMergeWorkflowPlanningReceipt,
        requiredEffects: [MultiDifferenceMergeWorkflowRequiredEffect],
        limits: MultiDifferenceMergeWorkflowLimits
    ) {
        reference = MultiDifferenceMergeWorkflowPlanReference(transaction: transaction)
        self.expectedSnapshotCAS = expectedSnapshotCAS
        self.primitiveInvocation = primitiveInvocation
        self.mergeResult = mergeResult
        self.transaction = transaction
        self.receipt = receipt
        self.requiredEffects = requiredEffects
        self.limits = limits
        executorContract = .required
    }

    public var expectedSnapshot: MultiDifferenceMergeWorkflowSnapshotReference {
        expectedSnapshotCAS.reference
    }

    public func validateCurrentSnapshot(_ snapshot: MultiDifferenceMergeWorkflowSnapshot) throws {
        try expectedSnapshotCAS.validate(snapshot)
    }

    /// Performs one synchronous actor-isolated owner CAS. Owner must compare every expected value,
    /// apply all transaction fields without suspension, and never reuse `transaction.id`.
    public func commit<Owner: MultiDifferenceMergeWorkflowAtomicCommitOwner>(
        to owner: isolated Owner
    ) throws -> MultiDifferenceMergeWorkflowCommitReceipt {
        do {
            try Task<Never, Never>.checkCancellation()
        } catch is CancellationError {
            throw MultiDifferenceMergeWorkflowError.cancelled
        }
        switch owner.compareAndCommit(transaction) {
        case .committed(let evidence):
            do {
                try MultiDifferenceMergeWorkflow.validate(
                    evidence: evidence,
                    transaction: transaction
                )
            } catch {
                throw MultiDifferenceMergeWorkflowError.commitUncertain
            }
            return MultiDifferenceMergeWorkflowCommitReceipt(
                planningReceipt: receipt,
                planReference: reference,
                transaction: transaction,
                evidence: evidence
            )
        case .notCommitted(let currentSnapshot):
            do {
                try validateCurrentSnapshot(currentSnapshot)
            } catch let error as MultiDifferenceMergeWorkflowError where error.isStaleValidationFailure {
                throw error
            }
            throw MultiDifferenceMergeWorkflowError.ownerRejectedMatchingTransaction
        case .commitUncertain:
            throw MultiDifferenceMergeWorkflowError.commitUncertain
        }
    }
}

public struct MultiDifferenceMergeWorkflowOwnerCommitEvidence: Equatable, Sendable {
    public let transactionID: MultiDifferenceMergeWorkflowTransactionIdentity
    public let comparedExpectedState: MultiDifferenceMergeWorkflowSnapshot
    public let comparedDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision
    public let successorSource: MultiDifferenceMergeWorkflowSourceReference
    public let successorDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision
    public let committedSuccessor: ComparisonSnapshot
    public let destinationState: MergeCommandPolicy.SideState
    public let recordedUndoPredecessor: ComparisonSnapshot
    public let committedSelectionIntent: MultiDifferenceMergeWorkflowSuccessorSelectionIntent
    public let invalidatedComparison: MultiDifferenceMergeWorkflowComparisonReference

    public init(
        transactionID: MultiDifferenceMergeWorkflowTransactionIdentity,
        comparedExpectedState: MultiDifferenceMergeWorkflowSnapshot,
        comparedDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision,
        successorSource: MultiDifferenceMergeWorkflowSourceReference,
        successorDestinationRevision: MultiDifferenceMergeWorkflowPaneRevision,
        committedSuccessor: ComparisonSnapshot,
        destinationState: MergeCommandPolicy.SideState,
        recordedUndoPredecessor: ComparisonSnapshot,
        committedSelectionIntent: MultiDifferenceMergeWorkflowSuccessorSelectionIntent,
        invalidatedComparison: MultiDifferenceMergeWorkflowComparisonReference
    ) {
        self.transactionID = transactionID
        self.comparedExpectedState = comparedExpectedState
        self.comparedDestinationRevision = comparedDestinationRevision
        self.successorSource = successorSource
        self.successorDestinationRevision = successorDestinationRevision
        self.committedSuccessor = committedSuccessor
        self.destinationState = destinationState
        self.recordedUndoPredecessor = recordedUndoPredecessor
        self.committedSelectionIntent = committedSelectionIntent
        self.invalidatedComparison = invalidatedComparison
    }
}

public enum MultiDifferenceMergeWorkflowAtomicCommitOutcome: Equatable, Sendable {
    case committed(MultiDifferenceMergeWorkflowOwnerCommitEvidence)
    case notCommitted(currentSnapshot: MultiDifferenceMergeWorkflowSnapshot)
    case commitUncertain
}

/// Exclusive owner of both panes, history, dirty state, selection, and comparison publication state.
/// `compareAndCommit` compares exact transaction expectations and commits all owner mutations in one
/// synchronous isolation turn, or commits nothing.
public protocol MultiDifferenceMergeWorkflowAtomicCommitOwner: Actor {
    func compareAndCommit(
        _ transaction: MultiDifferenceMergeWorkflowTransaction
    ) -> MultiDifferenceMergeWorkflowAtomicCommitOutcome
}

public struct MultiDifferenceMergeWorkflowCommitReceipt: Equatable, Sendable {
    public let planReference: MultiDifferenceMergeWorkflowPlanReference
    public let planningReceipt: MultiDifferenceMergeWorkflowPlanningReceipt
    public let transaction: MultiDifferenceMergeWorkflowTransaction
    public let evidence: MultiDifferenceMergeWorkflowOwnerCommitEvidence

    fileprivate init(
        planningReceipt: MultiDifferenceMergeWorkflowPlanningReceipt,
        planReference: MultiDifferenceMergeWorkflowPlanReference,
        transaction: MultiDifferenceMergeWorkflowTransaction,
        evidence: MultiDifferenceMergeWorkflowOwnerCommitEvidence
    ) {
        self.planReference = planReference
        self.planningReceipt = planningReceipt
        self.transaction = transaction
        self.evidence = evidence
    }
}

public struct MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence: Equatable, Sendable {
    public let comparedSource: MultiDifferenceMergeWorkflowSourceReference
    public let comparedSourceContents: ComparisonSnapshot
    public let comparedInvalidatedComparison: MultiDifferenceMergeWorkflowComparisonReference
    public let comparedComparisonOptions: LineDiffOptions
    public let comparedComparisonOptionsGeneration: MultiDifferenceMergeWorkflowComparisonReference
    public let publishedComparison: MultiDifferenceMergeWorkflowSuccessorComparison

    public init(
        comparedSource: MultiDifferenceMergeWorkflowSourceReference,
        comparedSourceContents: ComparisonSnapshot,
        comparedInvalidatedComparison: MultiDifferenceMergeWorkflowComparisonReference,
        comparedComparisonOptions: LineDiffOptions,
        comparedComparisonOptionsGeneration: MultiDifferenceMergeWorkflowComparisonReference,
        publishedComparison: MultiDifferenceMergeWorkflowSuccessorComparison
    ) {
        self.comparedSource = comparedSource
        self.comparedSourceContents = comparedSourceContents
        self.comparedInvalidatedComparison = comparedInvalidatedComparison
        self.comparedComparisonOptions = comparedComparisonOptions
        self.comparedComparisonOptionsGeneration = comparedComparisonOptionsGeneration
        self.publishedComparison = publishedComparison
    }
}

public struct MultiDifferenceMergeWorkflowNavigationPublicationEvidence: Equatable, Sendable {
    public let intent: MultiDifferenceMergeWorkflowNavigationIntent
    public let publishedComparison: MultiDifferenceMergeWorkflowComparisonReference
    public let publishedTarget: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?

    public init(
        intent: MultiDifferenceMergeWorkflowNavigationIntent,
        publishedComparison: MultiDifferenceMergeWorkflowComparisonReference,
        publishedTarget: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?
    ) {
        self.intent = intent
        self.publishedComparison = publishedComparison
        self.publishedTarget = publishedTarget
    }
}

public enum MultiDifferenceMergeWorkflowPublicationEvidence: Equatable, Sendable {
    case successorComparison(MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence)
    case navigation(MultiDifferenceMergeWorkflowNavigationPublicationEvidence)
}

public struct MultiDifferenceMergeWorkflowPublicationReceipt: Equatable, Sendable {
    fileprivate let planReference: MultiDifferenceMergeWorkflowPlanReference
    fileprivate let effectIndex: Int
    public let effect: MultiDifferenceMergeWorkflowRequiredEffect
    public let evidence: MultiDifferenceMergeWorkflowPublicationEvidence

    private init(
        planReference: MultiDifferenceMergeWorkflowPlanReference,
        effectIndex: Int,
        effect: MultiDifferenceMergeWorkflowRequiredEffect,
        evidence: MultiDifferenceMergeWorkflowPublicationEvidence
    ) {
        self.planReference = planReference
        self.effectIndex = effectIndex
        self.effect = effect
        self.evidence = evidence
    }

    /// Call only after exact successor comparison publication completes.
    public static func executorAttestedSuccessorComparisonPublished(
        plan: MultiDifferenceMergeWorkflowPlan,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt,
        evidence: MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence
    ) throws -> MultiDifferenceMergeWorkflowPublicationReceipt {
        try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.validate(
            commitReceipt: commitReceipt,
            for: plan
        )
        guard plan.requiredEffects.indices.contains(1),
            case .publishSuccessorComparison(let intent) = plan.requiredEffects[1]
        else {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        guard
            evidence.comparedSource == intent.expectedSource,
            MultiDifferenceMergeWorkflow.snapshotsExactlyEqual(
                evidence.comparedSourceContents,
                intent.expectedSourceContents
            ),
            evidence.comparedInvalidatedComparison == intent.expectedInvalidatedComparison,
            MultiDifferenceMergeWorkflow.comparisonOptionsExactlyEqual(
                evidence.comparedComparisonOptions,
                intent.expectedComparisonOptions
            ),
            evidence.comparedComparisonOptionsGeneration == intent.expectedComparisonOptionsGeneration,
            MultiDifferenceMergeWorkflow.successorComparisonsExactlyEqual(
                evidence.publishedComparison,
                intent.successor
            )
        else {
            throw MultiDifferenceMergeWorkflowError.publicationUncertain
        }
        return MultiDifferenceMergeWorkflowPublicationReceipt(
            planReference: plan.reference,
            effectIndex: 1,
            effect: plan.requiredEffects[1],
            evidence: .successorComparison(evidence)
        )
    }

    /// Call only after navigation publication completes after successor comparison publication.
    public static func executorAttestedNavigationPublished(
        plan: MultiDifferenceMergeWorkflowPlan,
        after comparisonReceipt: MultiDifferenceMergeWorkflowPublicationReceipt,
        evidence: MultiDifferenceMergeWorkflowNavigationPublicationEvidence
    ) throws -> MultiDifferenceMergeWorkflowPublicationReceipt {
        try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.validate(
            publicationReceipts: [comparisonReceipt],
            for: plan
        )
        guard plan.requiredEffects.indices.contains(2),
            case .publishNavigation(let intent) = plan.requiredEffects[2]
        else {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        guard evidence.intent == intent,
            evidence.publishedComparison == plan.transaction.successorComparison.reference,
            MultiDifferenceMergeWorkflow.successorTargetsExactlyEqual(
                evidence.publishedTarget,
                plan.transaction.successorNavigationTarget
            )
        else {
            throw MultiDifferenceMergeWorkflowError.publicationUncertain
        }
        return MultiDifferenceMergeWorkflowPublicationReceipt(
            planReference: plan.reference,
            effectIndex: 2,
            effect: plan.requiredEffects[2],
            evidence: .navigation(evidence)
        )
    }
}

public enum MultiDifferenceMergeWorkflowExecutionFailureReason: String, CaseIterable, Equatable, Hashable, Sendable {
    case cancelled
    case staleSnapshot
    case destinationCompareAndSwapRejected
    case ownerUnavailable
    case successorComparisonPublicationFailed
    case navigationPublicationFailed
    case contractUnsupported
    case rejected
}

public enum MultiDifferenceMergeWorkflowExecutionUncertaintyReason: String, CaseIterable, Equatable, Hashable, Sendable {
    case commitStateUnknown
    case publicationStateUnknown
    case cancellationObservedAfterEffectBegan
}

public struct MultiDifferenceMergeWorkflowExecutionReceipt: Equatable, Sendable {
    public let planningReceipt: MultiDifferenceMergeWorkflowPlanningReceipt
    public let commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt
    public let publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    public let completedEffects: [MultiDifferenceMergeWorkflowRequiredEffect]

    fileprivate init(
        plan: MultiDifferenceMergeWorkflowPlan,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    ) {
        planningReceipt = plan.receipt
        self.commitReceipt = commitReceipt
        self.publicationReceipts = publicationReceipts
        completedEffects = plan.requiredEffects
    }
}

public struct MultiDifferenceMergeWorkflowExecutionFailureReceipt: Equatable, Sendable {
    public let planningReceipt: MultiDifferenceMergeWorkflowPlanningReceipt
    public let commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt?
    public let publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    public let completedEffects: [MultiDifferenceMergeWorkflowRequiredEffect]
    public let failedEffect: MultiDifferenceMergeWorkflowRequiredEffect
    public let reason: MultiDifferenceMergeWorkflowExecutionFailureReason
    public let unattemptedEffects: [MultiDifferenceMergeWorkflowRequiredEffect]

    fileprivate init(
        plan: MultiDifferenceMergeWorkflowPlan,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt?,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt],
        completedEffectCount: Int,
        reason: MultiDifferenceMergeWorkflowExecutionFailureReason
    ) {
        planningReceipt = plan.receipt
        self.commitReceipt = commitReceipt
        self.publicationReceipts = publicationReceipts
        completedEffects = Array(plan.requiredEffects.prefix(completedEffectCount))
        failedEffect = plan.requiredEffects[completedEffectCount]
        self.reason = reason
        unattemptedEffects = Array(plan.requiredEffects.dropFirst(completedEffectCount + 1))
    }
}

public struct MultiDifferenceMergeWorkflowExecutionUncertaintyReceipt: Equatable, Sendable {
    public let planningReceipt: MultiDifferenceMergeWorkflowPlanningReceipt
    public let commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt?
    public let publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    public let completedEffects: [MultiDifferenceMergeWorkflowRequiredEffect]
    public let uncertainEffects: [MultiDifferenceMergeWorkflowRequiredEffect]
    public let unattemptedEffects: [MultiDifferenceMergeWorkflowRequiredEffect]
    public let reason: MultiDifferenceMergeWorkflowExecutionUncertaintyReason

    fileprivate init(
        plan: MultiDifferenceMergeWorkflowPlan,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt?,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt],
        completedEffectCount: Int,
        lastUncertainEffectIndex: Int,
        reason: MultiDifferenceMergeWorkflowExecutionUncertaintyReason
    ) {
        planningReceipt = plan.receipt
        self.commitReceipt = commitReceipt
        self.publicationReceipts = publicationReceipts
        completedEffects = Array(plan.requiredEffects.prefix(completedEffectCount))
        uncertainEffects = Array(plan.requiredEffects[completedEffectCount...lastUncertainEffectIndex])
        unattemptedEffects = Array(plan.requiredEffects.dropFirst(lastUncertainEffectIndex + 1))
        self.reason = reason
    }
}

public enum MultiDifferenceMergeWorkflowExecutionOutcome: Equatable, Sendable {
    case completed(MultiDifferenceMergeWorkflowExecutionReceipt)
    case failed(MultiDifferenceMergeWorkflowExecutionFailureReceipt)
    case uncertain(MultiDifferenceMergeWorkflowExecutionUncertaintyReceipt)
}

/// Seals plan-bound receipts and rejects any outcome that could silently omit a committed prefix.
public enum MultiDifferenceMergeWorkflowExecutionOutcomeFactory: Sendable {
    public static func completed(
        plan: MultiDifferenceMergeWorkflowPlan,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    ) throws -> MultiDifferenceMergeWorkflowExecutionOutcome {
        try validate(commitReceipt: commitReceipt, for: plan)
        try validate(publicationReceipts: publicationReceipts, for: plan)
        guard publicationReceipts.count == plan.requiredEffects.count - 1 else {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        return .completed(
            MultiDifferenceMergeWorkflowExecutionReceipt(
                plan: plan,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts
            )
        )
    }

    public static func failed(
        plan: MultiDifferenceMergeWorkflowPlan,
        completedEffectCount: Int = 0,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt? = nil,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt] = [],
        reason: MultiDifferenceMergeWorkflowExecutionFailureReason
    ) throws -> MultiDifferenceMergeWorkflowExecutionOutcome {
        if completedEffectCount > 0,
            reason == .cancelled || reason == .contractUnsupported || reason == .rejected
        {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        guard plan.requiredEffects.indices.contains(completedEffectCount),
            try validCommitEvidence(
                completedEffectCount: completedEffectCount,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts,
                plan: plan
            ),
            isValid(reason: reason, for: plan.requiredEffects[completedEffectCount])
        else {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        return .failed(
            MultiDifferenceMergeWorkflowExecutionFailureReceipt(
                plan: plan,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts,
                completedEffectCount: completedEffectCount,
                reason: reason
            )
        )
    }

    public static func uncertain(
        plan: MultiDifferenceMergeWorkflowPlan,
        completedEffectCount: Int = 0,
        uncertainEffectIndices: [Int],
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt? = nil,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt] = [],
        reason: MultiDifferenceMergeWorkflowExecutionUncertaintyReason
    ) throws -> MultiDifferenceMergeWorkflowExecutionOutcome {
        guard uncertainEffectIndices.count <= plan.requiredEffects.count else {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        let indices = uncertainEffectIndices.sorted()
        guard completedEffectCount >= 0,
            completedEffectCount < plan.requiredEffects.count,
            !indices.isEmpty,
            Set(indices).count == indices.count,
            indices.allSatisfy(plan.requiredEffects.indices.contains),
            indices.first == completedEffectCount,
            let lastIndex = indices.last,
            indices == Array(completedEffectCount...lastIndex),
            try validCommitEvidence(
                completedEffectCount: completedEffectCount,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts,
                plan: plan
            )
        else {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        if completedEffectCount == 0, reason == .publicationStateUnknown {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        if completedEffectCount > 0, reason == .commitStateUnknown {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        if completedEffectCount == 0,
            reason == .commitStateUnknown,
            uncertainEffectIndices != [0]
        {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        if uncertainEffectIndices != [completedEffectCount] {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        return .uncertain(
            MultiDifferenceMergeWorkflowExecutionUncertaintyReceipt(
                plan: plan,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts,
                completedEffectCount: completedEffectCount,
                lastUncertainEffectIndex: lastIndex,
                reason: reason
            )
        )
    }

    private static func validCommitEvidence(
        completedEffectCount: Int,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt?,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt],
        plan: MultiDifferenceMergeWorkflowPlan
    ) throws -> Bool {
        if completedEffectCount == 0 {
            return commitReceipt == nil && publicationReceipts.isEmpty
        }
        guard let commitReceipt else { return false }
        try validate(commitReceipt: commitReceipt, for: plan)
        try validate(publicationReceipts: publicationReceipts, for: plan)
        return publicationReceipts.count == completedEffectCount - 1
    }

    fileprivate static func validate(
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt,
        for plan: MultiDifferenceMergeWorkflowPlan
    ) throws {
        guard commitReceipt.planReference == plan.reference,
            commitReceipt.evidence.transactionID == plan.transaction.id,
            commitReceipt.evidence.comparedDestinationRevision
                == plan.transaction.expectedDestinationRevision,
            commitReceipt.evidence.successorSource == plan.transaction.successorSource,
            commitReceipt.evidence.successorDestinationRevision
                == plan.transaction.successorDestinationRevision,
            commitReceipt.evidence.destinationState == plan.transaction.successorDestinationState,
            commitReceipt.evidence.committedSelectionIntent == plan.transaction.successorSelectionIntent,
            commitReceipt.evidence.invalidatedComparison == plan.transaction.expectedState.comparisonReference
        else {
            throw MultiDifferenceMergeWorkflowError.invalidCommitReceipt
        }
        do {
            try MultiDifferenceMergeWorkflow.validateCurrentSnapshot(
                commitReceipt.evidence.comparedExpectedState,
                expected: plan.transaction.expectedState
            )
        } catch {
            throw MultiDifferenceMergeWorkflowError.invalidCommitReceipt
        }
        guard
            MultiDifferenceMergeWorkflow.snapshotsExactlyEqual(
                commitReceipt.evidence.committedSuccessor,
                plan.transaction.successor
            ),
            MultiDifferenceMergeWorkflow.snapshotsExactlyEqual(
                commitReceipt.evidence.recordedUndoPredecessor,
                plan.transaction.predecessor
            )
        else {
            throw MultiDifferenceMergeWorkflowError.invalidCommitReceipt
        }
    }

    fileprivate static func validate(
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt],
        for plan: MultiDifferenceMergeWorkflowPlan
    ) throws {
        guard publicationReceipts.count <= plan.requiredEffects.count - 1 else {
            throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
        }
        for (offset, receipt) in publicationReceipts.enumerated() {
            let effectIndex = offset + 1
            guard receipt.planReference == plan.reference,
                receipt.effectIndex == effectIndex,
                receipt.effect == plan.requiredEffects[effectIndex]
            else {
                throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
            }
            switch (receipt.effect, receipt.evidence) {
            case (.publishSuccessorComparison(let intent), .successorComparison(let evidence)):
                guard evidence.comparedSource == intent.expectedSource,
                    MultiDifferenceMergeWorkflow.snapshotsExactlyEqual(
                        evidence.comparedSourceContents,
                        intent.expectedSourceContents
                    ),
                    evidence.comparedInvalidatedComparison == intent.expectedInvalidatedComparison,
                    MultiDifferenceMergeWorkflow.comparisonOptionsExactlyEqual(
                        evidence.comparedComparisonOptions,
                        intent.expectedComparisonOptions
                    ),
                    evidence.comparedComparisonOptionsGeneration
                        == intent.expectedComparisonOptionsGeneration,
                    MultiDifferenceMergeWorkflow.successorComparisonsExactlyEqual(
                        evidence.publishedComparison,
                        intent.successor
                    )
                else {
                    throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
                }
            case (
                .publishNavigation(let intent),
                .navigation(let evidence)
            )
            where evidence.intent == intent
                && evidence.publishedComparison == plan.transaction.successorComparison.reference
                && MultiDifferenceMergeWorkflow.successorTargetsExactlyEqual(
                    evidence.publishedTarget,
                    plan.transaction.successorNavigationTarget
                ):
                break
            default:
                throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
            }
        }
    }

    private static func isValid(
        reason: MultiDifferenceMergeWorkflowExecutionFailureReason,
        for effect: MultiDifferenceMergeWorkflowRequiredEffect
    ) -> Bool {
        switch (reason, effect) {
        case (.cancelled, .commitOwnerTransaction),
            (.contractUnsupported, .commitOwnerTransaction),
            (.rejected, .commitOwnerTransaction):
            true
        case (.staleSnapshot, .commitOwnerTransaction),
            (.destinationCompareAndSwapRejected, .commitOwnerTransaction),
            (.ownerUnavailable, .commitOwnerTransaction),
            (.successorComparisonPublicationFailed, .publishSuccessorComparison),
            (.navigationPublicationFailed, .publishNavigation):
            true
        default:
            false
        }
    }
}

/// Side-effect implementation supplied by app/owner layer. It must enforce `executorContract`,
/// acquire current state under owner isolation, and use `plan.commit(to:)` for owner mutation.
public protocol MultiDifferenceMergeWorkflowPlanExecutor: Sendable {
    func execute(_ plan: MultiDifferenceMergeWorkflowPlan) async -> MultiDifferenceMergeWorkflowExecutionOutcome
}

public enum MultiDifferenceMergeWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(MultiDifferenceMergeWorkflowLimit)
    case tooManyComparisonRows(maximum: Int)
    case tooManySelectedRows(maximum: Int)
    case tooManyDifferenceGroups(maximum: Int)
    case inputTooLarge(maximumUTF8Bytes: Int)
    case retainedDataTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximumUnits: UInt64)
    case selection(MultiDifferenceSelectionError)
    case commandDisabled(command: MergeCommandPolicy.Command, reason: MergeCommandPolicy.DisabledReason)
    case merge(MultiDifferenceMergeError)
    case lineDiff(LineDiffError)
    case primitiveNoChange(MultiDifferenceMergeNoOpReason)
    case primitiveChangedUnexpectedGroups(expected: [Range<Int>], actual: [Range<Int>])
    case primitiveMutatedSourcePane(MultiDifferenceMergeWorkflowPane)
    case primitiveDidNotMutateDestination(MultiDifferenceMergeWorkflowPane)
    case primitiveContractViolation
    case paneIdentityCollision
    case comparisonRevisionExhausted
    case sourceRevisionExhausted
    case paneRevisionExhausted(MultiDifferenceMergeWorkflowPane)
    case staleComparisonIdentity
    case staleComparisonRevision(expected: UInt64, actual: UInt64)
    case staleSourceIdentity
    case staleSourceRevision(expected: UInt64, actual: UInt64)
    case stalePaneIdentity(MultiDifferenceMergeWorkflowPane)
    case stalePaneRevision(pane: MultiDifferenceMergeWorkflowPane, expected: UInt64, actual: UInt64)
    case staleSelectionIdentity
    case staleSelectionRevision(expected: UInt64, actual: UInt64)
    case sourceContentsChanged
    case comparisonRowsChanged
    case comparisonOptionsChanged
    case selectionChanged
    case sideStateChanged(MultiDifferenceMergeWorkflowPane)
    case comparisonLifecycleChanged
    case invalidCommitReceipt
    case invalidOwnerCommitEvidence
    case ownerRejectedMatchingTransaction
    case commitUncertain
    case publicationUncertain
    case invalidExecutionOutcome
    case arithmeticOverflow

    fileprivate var isStaleValidationFailure: Bool {
        switch self {
        case .staleComparisonIdentity, .staleComparisonRevision, .staleSourceIdentity,
            .staleSourceRevision, .stalePaneIdentity, .stalePaneRevision,
            .staleSelectionIdentity, .staleSelectionRevision, .sourceContentsChanged,
            .comparisonRowsChanged, .comparisonOptionsChanged, .selectionChanged, .sideStateChanged,
            .comparisonLifecycleChanged:
            true
        default:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Multi-difference merge workflow was cancelled."
        case .invalidLimit(let limit):
            "Invalid multi-difference merge workflow limit: \(limit.rawValue)."
        case .tooManyComparisonRows(let maximum):
            "Comparison exceeds the \(maximum)-row workflow limit."
        case .tooManySelectedRows(let maximum):
            "Selection exceeds the \(maximum)-row workflow limit."
        case .tooManyDifferenceGroups(let maximum):
            "Selection exceeds the \(maximum)-difference-group workflow limit."
        case .inputTooLarge(let maximum):
            "Multi-difference merge input exceeds \(maximum) UTF-8 bytes."
        case .retainedDataTooLarge(let maximum):
            "Multi-difference merge plan exceeds \(maximum) retained UTF-8 bytes."
        case .workLimitExceeded(let maximum):
            "Multi-difference merge workflow exceeds \(maximum) work units."
        case .selection(let error):
            error.localizedDescription
        case .commandDisabled(let command, _):
            "Multi-difference merge command is disabled: \(String(describing: command))."
        case .merge(let error):
            error.localizedDescription
        case .lineDiff(.invalidRegularExpression):
            "Invalid comparison filter regular expression: <redacted>"
        case .lineDiff(let error):
            error.localizedDescription
        case .primitiveNoChange:
            "Multi-difference merge primitive produced no mutation."
        case .primitiveChangedUnexpectedGroups:
            "Multi-difference merge primitive changed groups outside the exact selection binding."
        case .primitiveMutatedSourcePane(let pane):
            "Multi-difference merge primitive mutated the \(pane.rawValue) source pane."
        case .primitiveDidNotMutateDestination(let pane):
            "Multi-difference merge primitive did not mutate the \(pane.rawValue) destination pane."
        case .primitiveContractViolation:
            "Multi-difference merge primitive threw an undocumented error."
        case .paneIdentityCollision:
            "Multi-difference merge requires distinct left and right pane identities."
        case .comparisonRevisionExhausted:
            "Multi-difference merge comparison revision cannot advance."
        case .sourceRevisionExhausted:
            "Multi-difference merge source revision cannot advance."
        case .paneRevisionExhausted(let pane):
            "Multi-difference merge \(pane.rawValue) pane revision cannot advance."
        case .staleComparisonIdentity:
            "Multi-difference merge plan belongs to another comparison."
        case .staleComparisonRevision(let expected, let actual):
            "Multi-difference merge expected comparison revision \(expected), not \(actual)."
        case .staleSourceIdentity:
            "Multi-difference merge plan belongs to another source set."
        case .staleSourceRevision(let expected, let actual):
            "Multi-difference merge expected source revision \(expected), not \(actual)."
        case .stalePaneIdentity(let pane):
            "Multi-difference merge plan belongs to another \(pane.rawValue) pane."
        case .stalePaneRevision(let pane, let expected, let actual):
            "Multi-difference merge expected \(pane.rawValue) pane revision \(expected), not \(actual)."
        case .staleSelectionIdentity:
            "Multi-difference merge plan belongs to another selection."
        case .staleSelectionRevision(let expected, let actual):
            "Multi-difference merge expected selection revision \(expected), not \(actual)."
        case .sourceContentsChanged:
            "Multi-difference merge source changed without advancing its revision."
        case .comparisonRowsChanged:
            "Multi-difference merge rows changed without advancing comparison revision."
        case .comparisonOptionsChanged:
            "Multi-difference merge options changed without advancing comparison revision."
        case .selectionChanged:
            "Multi-difference merge selection changed without advancing selection revision."
        case .sideStateChanged(let pane):
            "Multi-difference merge \(pane.rawValue) side state changed without advancing pane revision."
        case .comparisonLifecycleChanged:
            "Multi-difference merge lifecycle changed without advancing comparison revision."
        case .invalidCommitReceipt:
            "Multi-difference merge commit receipt does not belong to this plan."
        case .invalidOwnerCommitEvidence:
            "Multi-difference merge owner commit evidence contradicts the planned transaction."
        case .ownerRejectedMatchingTransaction:
            "Multi-difference merge owner rejected a transaction without reporting stale state."
        case .commitUncertain:
            "Multi-difference merge owner could not determine whether its transaction committed."
        case .publicationUncertain:
            "Multi-difference merge executor evidence cannot prove exact publication after commit."
        case .invalidExecutionOutcome:
            "Multi-difference merge execution outcome contradicts required effect order."
        case .arithmeticOverflow:
            "Multi-difference merge size calculation overflowed."
        }
    }
}

/// UI-independent planner for selected multi-difference copy commands.
public enum MultiDifferenceMergeWorkflow: Sendable {
    public static func commandState(
        for intent: MultiDifferenceMergeWorkflowCommandIntent,
        in snapshot: MultiDifferenceMergeWorkflowSnapshot,
        limits: MultiDifferenceMergeWorkflowLimits = .default
    ) throws -> MultiDifferenceMergeWorkflowCommandState {
        do {
            var work = try WorkBudget(limits: limits)
            _ = try validateForPlanning(snapshot, limits: limits, work: &work)
            let hasSignificantDifferences = try containsSignificantDifference(
                snapshot.comparisonRows,
                work: &work
            )
            let policyState = MergeCommandPolicy.State(
                left: snapshot.left,
                right: snapshot.right,
                comparisonLifecycle: snapshot.comparisonLifecycle,
                hasSelection: snapshot.selection.hasSignificantDifferences,
                hasSignificantDifferences: hasSignificantDifferences
            )
            let availability = MergeCommandPolicy.evaluate(policyState)[intent.policyCommand]
            try work.finish()
            return MultiDifferenceMergeWorkflowCommandState(
                intent: intent,
                snapshot: snapshot,
                availability: availability,
                workUnitsConsumed: work.consumed
            )
        } catch is CancellationError {
            throw MultiDifferenceMergeWorkflowError.cancelled
        }
    }

    /// Fully preflights one immutable transaction. No mutation or publication occurs here.
    public static func plan(
        intent: MultiDifferenceMergeWorkflowCommandIntent,
        in snapshot: MultiDifferenceMergeWorkflowSnapshot,
        limits: MultiDifferenceMergeWorkflowLimits = .default
    ) throws -> MultiDifferenceMergeWorkflowPlan {
        do {
            var work = try WorkBudget(limits: limits)
            let retainedByteBaseEstimate = try validateForPlanning(
                snapshot,
                limits: limits,
                work: &work
            )
            let state = try commandStateWithoutRevalidation(intent: intent, snapshot: snapshot, work: &work)
            guard state.availability.isEnabled else {
                throw MultiDifferenceMergeWorkflowError.commandDisabled(
                    command: intent.policyCommand,
                    reason: state.availability.disabledReason!
                )
            }

            let revisions = try successorRevisions(snapshot: snapshot, direction: intent.direction)
            let successorComparisonReference = try successorComparisonReference(
                snapshot: snapshot,
                source: revisions.source
            )
            let expectedResult = try expectedPrimitiveResult(
                snapshot: snapshot,
                direction: intent.direction,
                work: &work
            )
            let expectedSuccessorRows = try successorComparisonRows(
                source: expectedResult.snapshot,
                options: snapshot.comparisonOptions
            )
            try work.consume(UInt64(expectedResult.snapshot.left.utf8.count))
            try work.consume(UInt64(expectedResult.snapshot.right.utf8.count))
            try work.consume(UInt64(expectedSuccessorRows.count))
            let expectedSuccessorComparison = MultiDifferenceMergeWorkflowSuccessorComparison(
                reference: successorComparisonReference,
                source: expectedResult.snapshot,
                rows: expectedSuccessorRows,
                options: snapshot.comparisonOptions
            )
            let expectedSuccessorNavigationTarget =
                intent.advance == .advanceToNextDifference
                ? try resolvedSuccessorNavigationTarget(
                    comparison: expectedSuccessorComparison,
                    changedGroups: expectedResult.changedGroups,
                    direction: intent.direction,
                    work: &work
                )
                : nil
            let expectedResultByteCount = try utf8ByteCount(of: expectedResult.snapshot)
            let retainedByteEstimate = try checkedAdd(
                retainedByteBaseEstimate,
                try checkedAdd(
                    expectedResultByteCount,
                    try checkedAdd(
                        expectedResultByteCount,
                        try checkedAdd(
                            try checkedMultiply(expectedResult.changedGroups.count, 128),
                            try successorComparisonRetainedByteEstimate(
                                rows: expectedSuccessorRows,
                                work: &work
                            )
                        )
                    )
                )
            )
            guard retainedByteEstimate <= limits.maximumRetainedUTF8Bytes else {
                throw MultiDifferenceMergeWorkflowError.retainedDataTooLarge(
                    maximumUTF8Bytes: limits.maximumRetainedUTF8Bytes
                )
            }

            let invocation = MultiDifferenceMergeWorkflowPrimitiveInvocation(
                snapshot: snapshot,
                direction: intent.direction,
                options: limits.merge
            )
            let outcome: MultiDifferenceMergeOutcome
            do {
                outcome = try MultiDifferenceMerge.apply(
                    state: invocation.state,
                    selectedAlignedRows: invocation.selectedAlignedRows,
                    direction: invocation.direction,
                    options: invocation.options
                )
            } catch let error as MultiDifferenceMergeError {
                throw MultiDifferenceMergeWorkflowError.merge(error)
            } catch let error as LineDiffError {
                throw MultiDifferenceMergeWorkflowError.lineDiff(error)
            } catch is CancellationError {
                throw MultiDifferenceMergeWorkflowError.cancelled
            } catch {
                throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
            }
            try work.checkCancellation()

            guard case .merged(let result) = outcome else {
                guard case .noChange(let reason) = outcome else {
                    throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
                }
                throw MultiDifferenceMergeWorkflowError.primitiveNoChange(reason)
            }
            try validate(
                result: result,
                snapshot: snapshot,
                direction: intent.direction,
                expectedResult: expectedResult,
                work: &work
            )

            let transaction = MultiDifferenceMergeWorkflowTransaction(
                snapshot: snapshot,
                result: result,
                intent: intent,
                successorComparison: expectedSuccessorComparison,
                successorNavigationTarget: expectedSuccessorNavigationTarget,
                successorDestination: revisions.destination
            )
            let resultByteCount = try utf8ByteCount(of: result.snapshot)
            try work.consume(UInt64(resultByteCount))
            try work.consume(UInt64(result.changedGroups.count))
            try work.finish()

            let receipt = MultiDifferenceMergeWorkflowPlanningReceipt(
                snapshot: snapshot,
                intent: intent,
                transaction: transaction,
                resultUTF8ByteCount: resultByteCount,
                retainedUTF8ByteEstimate: retainedByteEstimate,
                workflowWorkUnitsConsumed: work.consumed,
                primitiveMaximumWork: limits.merge.maximumWork
            )
            var effects: [MultiDifferenceMergeWorkflowRequiredEffect] = [
                .commitOwnerTransaction,
                .publishSuccessorComparison(transaction.successorComparisonPublication)
            ]
            if case .none = transaction.navigationIntent {
                // No navigation publication follows a non-advancing copy.
            } else {
                effects.append(.publishNavigation(transaction.navigationIntent))
            }
            return MultiDifferenceMergeWorkflowPlan(
                expectedSnapshotCAS: MultiDifferenceMergeWorkflowSnapshotCAS(
                    snapshot: snapshot
                ),
                primitiveInvocation: invocation,
                mergeResult: result,
                transaction: transaction,
                receipt: receipt,
                requiredEffects: effects,
                limits: limits
            )
        } catch is CancellationError {
            throw MultiDifferenceMergeWorkflowError.cancelled
        }
    }

    fileprivate static func validateCurrentSnapshot(
        _ current: MultiDifferenceMergeWorkflowSnapshot,
        expected: MultiDifferenceMergeWorkflowSnapshot
    ) throws {
        do {
            try validateReferences(current, expected: expected)
            guard current.left == expected.left else {
                throw MultiDifferenceMergeWorkflowError.sideStateChanged(.left)
            }
            guard current.right == expected.right else {
                throw MultiDifferenceMergeWorkflowError.sideStateChanged(.right)
            }
            guard current.comparisonLifecycle == expected.comparisonLifecycle else {
                throw MultiDifferenceMergeWorkflowError.comparisonLifecycleChanged
            }
            guard
                comparisonOptionsExactlyEqual(
                    current.comparisonOptions,
                    expected.comparisonOptions
                )
            else {
                throw MultiDifferenceMergeWorkflowError.comparisonOptionsChanged
            }
            guard snapshotsExactlyEqual(current.source, expected.source) else {
                throw MultiDifferenceMergeWorkflowError.sourceContentsChanged
            }
            guard rowsExactlyEqual(current.comparisonRows, expected.comparisonRows) else {
                throw MultiDifferenceMergeWorkflowError.comparisonRowsChanged
            }
            guard current.selection == expected.selection,
                current.selectionBinding == expected.selectionBinding
            else {
                throw MultiDifferenceMergeWorkflowError.selectionChanged
            }
        } catch is CancellationError {
            throw MultiDifferenceMergeWorkflowError.cancelled
        }
    }

    private static func validateReferences(
        _ current: MultiDifferenceMergeWorkflowSnapshot,
        expected: MultiDifferenceMergeWorkflowSnapshot
    ) throws {
        let currentComparison = current.comparisonReference
        let expectedComparison = expected.comparisonReference
        guard currentComparison.identity == expectedComparison.identity else {
            throw MultiDifferenceMergeWorkflowError.staleComparisonIdentity
        }
        guard currentComparison.revision == expectedComparison.revision else {
            throw MultiDifferenceMergeWorkflowError.staleComparisonRevision(
                expected: expectedComparison.revision,
                actual: currentComparison.revision
            )
        }
        let currentSource = current.sourceReference
        let expectedSource = expected.sourceReference
        guard currentSource.identity == expectedSource.identity else {
            throw MultiDifferenceMergeWorkflowError.staleSourceIdentity
        }
        guard currentSource.revision == expectedSource.revision else {
            throw MultiDifferenceMergeWorkflowError.staleSourceRevision(
                expected: expectedSource.revision,
                actual: currentSource.revision
            )
        }
        for pane in MultiDifferenceMergeWorkflowPane.allCases {
            guard currentSource[pane].identity == expectedSource[pane].identity else {
                throw MultiDifferenceMergeWorkflowError.stalePaneIdentity(pane)
            }
            guard currentSource[pane].revision == expectedSource[pane].revision else {
                throw MultiDifferenceMergeWorkflowError.stalePaneRevision(
                    pane: pane,
                    expected: expectedSource[pane].revision,
                    actual: currentSource[pane].revision
                )
            }
        }
        guard current.selectionReference.identity == expected.selectionReference.identity else {
            throw MultiDifferenceMergeWorkflowError.staleSelectionIdentity
        }
        guard current.selectionReference.revision == expected.selectionReference.revision else {
            throw MultiDifferenceMergeWorkflowError.staleSelectionRevision(
                expected: expected.selectionReference.revision,
                actual: current.selectionReference.revision
            )
        }
    }

    private static func commandStateWithoutRevalidation(
        intent: MultiDifferenceMergeWorkflowCommandIntent,
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        work: inout WorkBudget
    ) throws -> MultiDifferenceMergeWorkflowCommandState {
        let hasSignificantDifferences = try containsSignificantDifference(
            snapshot.comparisonRows,
            work: &work
        )
        let policyState = MergeCommandPolicy.State(
            left: snapshot.left,
            right: snapshot.right,
            comparisonLifecycle: snapshot.comparisonLifecycle,
            hasSelection: snapshot.selection.hasSignificantDifferences,
            hasSignificantDifferences: hasSignificantDifferences
        )
        return MultiDifferenceMergeWorkflowCommandState(
            intent: intent,
            snapshot: snapshot,
            availability: MergeCommandPolicy.evaluate(policyState)[intent.policyCommand],
            workUnitsConsumed: work.consumed
        )
    }

    private static func validateForPlanning(
        _ snapshot: MultiDifferenceMergeWorkflowSnapshot,
        limits: MultiDifferenceMergeWorkflowLimits,
        work: inout WorkBudget
    ) throws -> Int {
        try validate(limits)
        try work.checkCancellation()
        guard snapshot.comparisonRows.count <= limits.maximumComparisonRows else {
            throw MultiDifferenceMergeWorkflowError.tooManyComparisonRows(
                maximum: limits.maximumComparisonRows
            )
        }
        guard snapshot.selection.rowRange.count <= limits.maximumSelectedRows else {
            throw MultiDifferenceMergeWorkflowError.tooManySelectedRows(
                maximum: limits.maximumSelectedRows
            )
        }
        guard snapshot.selection.differenceRuns.count <= limits.maximumDifferenceGroups else {
            throw MultiDifferenceMergeWorkflowError.tooManyDifferenceGroups(
                maximum: limits.maximumDifferenceGroups
            )
        }
        guard snapshot.sourceReference.left.identity != snapshot.sourceReference.right.identity else {
            throw MultiDifferenceMergeWorkflowError.paneIdentityCollision
        }
        let optionBytes = try validateComparisonOptions(
            snapshot.comparisonOptions,
            limits: limits,
            work: &work
        )
        let inputBytes = try utf8ByteCount(of: snapshot.source)
        guard inputBytes <= limits.maximumInputUTF8Bytes else {
            throw MultiDifferenceMergeWorkflowError.inputTooLarge(
                maximumUTF8Bytes: limits.maximumInputUTF8Bytes
            )
        }
        let retainedRowTextBytes = try rowTextUTF8ByteCount(
            snapshot.comparisonRows,
            work: &work
        )
        guard retainedRowTextBytes <= limits.maximumRetainedUTF8Bytes else {
            throw MultiDifferenceMergeWorkflowError.retainedDataTooLarge(
                maximumUTF8Bytes: limits.maximumRetainedUTF8Bytes
            )
        }
        try work.consume(UInt64(inputBytes))
        try work.consume(UInt64(retainedRowTextBytes))
        try work.consume(UInt64(snapshot.comparisonRows.count))
        try work.consume(UInt64(snapshot.selection.selectedRowIDs.count))
        try work.consume(UInt64(snapshot.selection.differenceRuns.count))
        var differenceRowIDCount = 0
        for run in snapshot.selection.differenceRuns {
            differenceRowIDCount = try checkedAdd(differenceRowIDCount, run.rowIDs.count)
        }
        try work.consume(UInt64(differenceRowIDCount))
        do {
            try snapshot.selection.validate(
                in: snapshot.comparisonRows,
                limits: limits.selection
            )
        } catch let error as MultiDifferenceSelectionError {
            throw MultiDifferenceMergeWorkflowError.selection(error)
        } catch is CancellationError {
            throw MultiDifferenceMergeWorkflowError.cancelled
        }
        let retainedByteBaseEstimate = try retainedByteBaseEstimate(
            snapshot: snapshot,
            inputBytes: inputBytes,
            rowTextBytes: retainedRowTextBytes,
            optionBytes: optionBytes,
            work: &work
        )
        guard retainedByteBaseEstimate <= limits.maximumRetainedUTF8Bytes else {
            throw MultiDifferenceMergeWorkflowError.retainedDataTooLarge(
                maximumUTF8Bytes: limits.maximumRetainedUTF8Bytes
            )
        }
        return retainedByteBaseEstimate
    }

    private static func validate(_ limits: MultiDifferenceMergeWorkflowLimits) throws {
        guard (0...MultiDifferenceMergeWorkflowLimits.hardMaximumComparisonRows).contains(limits.maximumComparisonRows) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonRows)
        }
        guard (0...MultiDifferenceMergeWorkflowLimits.hardMaximumSelectedRows).contains(limits.maximumSelectedRows) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.selectedRows)
        }
        guard (0...MultiDifferenceMergeWorkflowLimits.hardMaximumDifferenceGroups).contains(limits.maximumDifferenceGroups) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.differenceGroups)
        }
        guard (0...MultiDifferenceMergeWorkflowLimits.hardMaximumComparisonOptionItems).contains(limits.maximumComparisonOptionItems) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonOptionItems)
        }
        guard
            (0...MultiDifferenceMergeWorkflowLimits.hardMaximumComparisonOptionStringUTF8Bytes).contains(
                limits.maximumComparisonOptionStringUTF8Bytes
            )
        else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonOptionStringUTF8Bytes)
        }
        guard (0...MultiDifferenceMergeWorkflowLimits.hardMaximumComparisonOptionsUTF8Bytes).contains(limits.maximumComparisonOptionsUTF8Bytes) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonOptionsUTF8Bytes)
        }
        guard (0...MultiDifferenceMergeWorkflowLimits.hardMaximumInputUTF8Bytes).contains(limits.maximumInputUTF8Bytes) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.inputUTF8Bytes)
        }
        guard (0...MultiDifferenceMergeWorkflowLimits.hardMaximumRetainedUTF8Bytes).contains(limits.maximumRetainedUTF8Bytes) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.retainedUTF8Bytes)
        }
        guard limits.selection.maximumRows >= 0 else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonRows)
        }
        guard limits.selection.maximumSelectedRows >= 0 else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.selectedRows)
        }
        guard limits.selection.maximumDifferenceRows >= 0 else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.selectedRows)
        }
        guard limits.selection.maximumDifferenceRuns >= 0 else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.differenceGroups)
        }
        guard limits.selection.maximumWork >= 0,
            UInt64(limits.selection.maximumWork) <= limits.maximumWorkUnits
        else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.selectionWorkUnits)
        }
        guard limits.merge.maximumComparedRows >= 0,
            limits.merge.maximumComparedRows <= limits.maximumComparisonRows
        else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonRows)
        }
        guard limits.merge.maximumChangeGroups >= 0,
            limits.merge.maximumChangeGroups <= limits.maximumDifferenceGroups
        else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.differenceGroups)
        }
        guard limits.merge.maximumMergeOperations >= 0,
            limits.merge.maximumMergeOperations <= MultiDifferenceMergeWorkflowLimits.hardMaximumMergeOperations
        else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.mergeOperations)
        }
        guard limits.merge.maximumOutputBytes >= 0,
            limits.merge.maximumOutputBytes <= MultiDifferenceMergeWorkflowLimits.hardMaximumMergeOutputUTF8Bytes
        else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.mergeOutputUTF8Bytes)
        }
        guard limits.merge.maximumWork >= 0,
            UInt64(limits.merge.maximumWork) <= limits.maximumWorkUnits
        else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.primitiveWorkUnits)
        }
        guard limits.maximumWorkUnits <= MultiDifferenceMergeWorkflowLimits.hardMaximumWorkUnits else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.workUnits)
        }
        guard (1...MultiDifferenceMergeWorkflowLimits.hardMaximumCancellationCheckInterval).contains(limits.cancellationCheckInterval) else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.cancellationCheckInterval)
        }
    }

    private static func validate(
        result: MultiDifferenceMergeResult,
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        direction: MergeDirection,
        expectedResult: MultiDifferenceMergeResult,
        work: inout WorkBudget
    ) throws {
        let expectedGroups = expectedResult.changedGroups.map(\.alignedRowRange)
        let actualGroups = result.changedGroups.map(\.alignedRowRange)
        guard expectedResult.changedGroups == result.changedGroups else {
            throw MultiDifferenceMergeWorkflowError.primitiveChangedUnexpectedGroups(
                expected: expectedGroups,
                actual: actualGroups
            )
        }
        switch direction {
        case .leftToRight:
            guard try stringsExactlyEqual(result.snapshot.left, snapshot.source.left, work: &work) else {
                throw MultiDifferenceMergeWorkflowError.primitiveMutatedSourcePane(.left)
            }
            guard try !stringsExactlyEqual(result.snapshot.right, snapshot.source.right, work: &work) else {
                throw MultiDifferenceMergeWorkflowError.primitiveDidNotMutateDestination(.right)
            }
        case .rightToLeft:
            guard try stringsExactlyEqual(result.snapshot.right, snapshot.source.right, work: &work) else {
                throw MultiDifferenceMergeWorkflowError.primitiveMutatedSourcePane(.right)
            }
            guard try !stringsExactlyEqual(result.snapshot.left, snapshot.source.left, work: &work) else {
                throw MultiDifferenceMergeWorkflowError.primitiveDidNotMutateDestination(.left)
            }
        }
        guard try snapshotsExactlyEqual(result.snapshot, expectedResult.snapshot, work: &work) else {
            throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
        }
    }

    private static func expectedPrimitiveResult(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        direction: MergeDirection,
        work: inout WorkBudget
    ) throws -> MultiDifferenceMergeResult {
        let changedGroups = try expectedChangeGroups(
            snapshot: snapshot,
            direction: direction,
            work: &work
        )
        var expectedSnapshot = snapshot.source
        for group in snapshot.selection.differenceRuns.reversed() {
            for rowID in group.rowIDs.reversed() {
                let operationWork = try checkedAdd(
                    try checkedAdd(
                        expectedSnapshot.left.utf8.count,
                        expectedSnapshot.right.utf8.count
                    ),
                    snapshot.comparisonRows.count
                )
                try work.consume(UInt64(operationWork))
                let merged: LineMergeResult
                do {
                    guard
                        let value = try LineMerge.apply(
                            rowID: rowID,
                            direction: direction,
                            left: expectedSnapshot.left,
                            right: expectedSnapshot.right,
                            options: snapshot.comparisonOptions
                        )
                    else {
                        throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
                    }
                    merged = value
                } catch let error as MultiDifferenceMergeWorkflowError {
                    throw error
                } catch let error as LineDiffError {
                    throw MultiDifferenceMergeWorkflowError.lineDiff(error)
                } catch is CancellationError {
                    throw MultiDifferenceMergeWorkflowError.cancelled
                } catch {
                    throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
                }
                expectedSnapshot = ComparisonSnapshot(left: merged.left, right: merged.right)
            }
        }
        return MultiDifferenceMergeResult(
            snapshot: expectedSnapshot,
            changedGroups: changedGroups
        )
    }

    private static func expectedChangeGroups(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        direction: MergeDirection,
        work: inout WorkBudget
    ) throws -> [MultiDifferenceMergeChangeGroup] {
        var leftPrefixes = Array(repeating: 0, count: snapshot.comparisonRows.count + 1)
        var rightPrefixes = Array(repeating: 0, count: snapshot.comparisonRows.count + 1)
        for index in snapshot.comparisonRows.indices {
            try work.consume()
            let row = snapshot.comparisonRows[index]
            leftPrefixes[index + 1] = leftPrefixes[index] + (row.left == nil ? 0 : 1)
            rightPrefixes[index + 1] = rightPrefixes[index] + (row.right == nil ? 0 : 1)
        }

        var result: [MultiDifferenceMergeChangeGroup] = []
        result.reserveCapacity(snapshot.selection.differenceRuns.count)
        var precedingDestinationDelta = 0
        for group in snapshot.selection.differenceRuns {
            try work.consume()
            guard snapshot.comparisonRows.indices.contains(group.rowRange.lowerBound),
                group.rowRange.upperBound <= snapshot.comparisonRows.count,
                group.rowIDs == snapshot.comparisonRows[group.rowRange].map(\.id),
                group.leftSourceRowCount
                    == leftPrefixes[group.rowRange.upperBound] - leftPrefixes[group.rowRange.lowerBound],
                group.rightSourceRowCount
                    == rightPrefixes[group.rowRange.upperBound] - rightPrefixes[group.rowRange.lowerBound]
            else {
                throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
            }
            let leftRange =
                leftPrefixes[group.rowRange.lowerBound]..<leftPrefixes[group.rowRange.upperBound]
            let rightRange =
                rightPrefixes[group.rowRange.lowerBound]..<rightPrefixes[group.rowRange.upperBound]
            let sourceRange = direction == .leftToRight ? leftRange : rightRange
            let destinationRange = direction == .leftToRight ? rightRange : leftRange
            let resultLowerBound = try checkedAdd(
                destinationRange.lowerBound,
                precedingDestinationDelta
            )
            let resultUpperBound = try checkedAdd(resultLowerBound, sourceRange.count)
            result.append(
                MultiDifferenceMergeChangeGroup(
                    alignedRowRange: group.rowRange,
                    sourceLineRange: sourceRange,
                    destinationLineRange: destinationRange,
                    resultDestinationLineRange: resultLowerBound..<resultUpperBound
                )
            )
            let (nextDelta, deltaOverflow) = precedingDestinationDelta.addingReportingOverflow(
                sourceRange.count - destinationRange.count
            )
            guard !deltaOverflow else {
                throw MultiDifferenceMergeWorkflowError.arithmeticOverflow
            }
            precedingDestinationDelta = nextDelta
        }
        return result
    }

    private static func successorComparisonRows(
        source: ComparisonSnapshot,
        options: LineDiffOptions
    ) throws -> [DiffRow] {
        do {
            return try LineDiff.compare(
                left: source.left,
                right: source.right,
                options: options
            )
        } catch let error as LineDiffError {
            throw MultiDifferenceMergeWorkflowError.lineDiff(error)
        } catch is CancellationError {
            throw MultiDifferenceMergeWorkflowError.cancelled
        } catch {
            throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
        }
    }

    private static func resolvedSuccessorNavigationTarget(
        comparison: MultiDifferenceMergeWorkflowSuccessorComparison,
        changedGroups: [MultiDifferenceMergeChangeGroup],
        direction: MergeDirection,
        work: inout WorkBudget
    ) throws -> MultiDifferenceMergeWorkflowSuccessorDifferenceTarget? {
        guard let lastChangedGroup = changedGroups.last else {
            throw MultiDifferenceMergeWorkflowError.primitiveContractViolation
        }
        let leftBoundary =
            direction == .leftToRight
            ? lastChangedGroup.sourceLineRange.upperBound
            : lastChangedGroup.resultDestinationLineRange.upperBound
        let rightBoundary =
            direction == .leftToRight
            ? lastChangedGroup.resultDestinationLineRange.upperBound
            : lastChangedGroup.sourceLineRange.upperBound
        var lowerBound = comparison.rows.count
        for index in comparison.rows.indices {
            try work.consume()
            let row = comparison.rows[index]
            let isAfterMergedGroups =
                (row.left?.number ?? leftBoundary + 1) > leftBoundary
                && (row.right?.number ?? rightBoundary + 1) > rightBoundary
            if isAfterMergedGroups, row.kind != .unchanged {
                lowerBound = index
                break
            }
        }
        guard lowerBound < comparison.rows.count else { return nil }
        var upperBound = lowerBound + 1
        while upperBound < comparison.rows.count, comparison.rows[upperBound].kind != .unchanged {
            try work.consume()
            upperBound += 1
        }
        let rowRange = lowerBound..<upperBound
        return MultiDifferenceMergeWorkflowSuccessorDifferenceTarget(
            comparison: comparison.reference,
            rowRange: rowRange,
            rowIDs: comparison.rows[rowRange].map(\.id)
        )
    }

    fileprivate static func validate(
        evidence: MultiDifferenceMergeWorkflowOwnerCommitEvidence,
        transaction: MultiDifferenceMergeWorkflowTransaction
    ) throws {
        guard evidence.transactionID == transaction.id,
            evidence.comparedDestinationRevision == transaction.expectedDestinationRevision,
            evidence.successorSource == transaction.successorSource,
            evidence.successorDestinationRevision == transaction.successorDestinationRevision,
            evidence.destinationState == transaction.successorDestinationState,
            evidence.committedSelectionIntent == transaction.successorSelectionIntent,
            evidence.invalidatedComparison == transaction.expectedState.comparisonReference
        else {
            throw MultiDifferenceMergeWorkflowError.invalidOwnerCommitEvidence
        }
        do {
            try validateCurrentSnapshot(
                evidence.comparedExpectedState,
                expected: transaction.expectedState
            )
        } catch {
            throw MultiDifferenceMergeWorkflowError.invalidOwnerCommitEvidence
        }
        guard snapshotsExactlyEqual(evidence.committedSuccessor, transaction.successor),
            snapshotsExactlyEqual(evidence.recordedUndoPredecessor, transaction.predecessor)
        else {
            throw MultiDifferenceMergeWorkflowError.invalidOwnerCommitEvidence
        }
    }

    private static func containsSignificantDifference(
        _ rows: [DiffRow],
        work: inout WorkBudget
    ) throws -> Bool {
        for row in rows {
            try work.consume()
            if row.kind != .unchanged { return true }
        }
        return false
    }

    private static func validateComparisonOptions(
        _ options: LineDiffOptions,
        limits: MultiDifferenceMergeWorkflowLimits,
        work: inout WorkBudget
    ) throws -> Int {
        let itemCount = try checkedAdd(options.lineFilters.count, options.substitutions.count)
        guard itemCount <= limits.maximumComparisonOptionItems else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonOptionItems)
        }
        var bytes = 0
        for filter in options.lineFilters {
            try work.consume()
            let count = filter.pattern.utf8.count
            guard count <= limits.maximumComparisonOptionStringUTF8Bytes else {
                throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonOptionStringUTF8Bytes)
            }
            bytes = try checkedAdd(bytes, count)
        }
        for substitution in options.substitutions {
            try work.consume()
            let patternBytes = substitution.pattern.utf8.count
            let replacementBytes = substitution.replacement.utf8.count
            guard patternBytes <= limits.maximumComparisonOptionStringUTF8Bytes,
                replacementBytes <= limits.maximumComparisonOptionStringUTF8Bytes
            else {
                throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonOptionStringUTF8Bytes)
            }
            bytes = try checkedAdd(bytes, patternBytes)
            bytes = try checkedAdd(bytes, replacementBytes)
        }
        guard bytes <= limits.maximumComparisonOptionsUTF8Bytes else {
            throw MultiDifferenceMergeWorkflowError.invalidLimit(.comparisonOptionsUTF8Bytes)
        }
        try work.consume(UInt64(bytes))
        return bytes
    }

    private static func rowTextUTF8ByteCount(
        _ rows: [DiffRow],
        work: inout WorkBudget
    ) throws -> Int {
        var bytes = 0
        for row in rows {
            try work.consume()
            if let left = row.left { bytes = try checkedAdd(bytes, left.text.utf8.count) }
            if let right = row.right { bytes = try checkedAdd(bytes, right.text.utf8.count) }
        }
        return bytes
    }

    private static func successorRevisions(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        direction: MergeDirection
    ) throws -> (
        source: MultiDifferenceMergeWorkflowSourceReference,
        destination: MultiDifferenceMergeWorkflowPaneRevision
    ) {
        let destination: MultiDifferenceMergeWorkflowPane = direction == .leftToRight ? .right : .left
        let expectedDestination = snapshot.sourceReference[destination]
        let (destinationRevision, destinationOverflow) = expectedDestination.revision.addingReportingOverflow(1)
        guard !destinationOverflow else {
            throw MultiDifferenceMergeWorkflowError.paneRevisionExhausted(destination)
        }
        let successorDestination = MultiDifferenceMergeWorkflowPaneRevision(
            identity: expectedDestination.identity,
            revision: destinationRevision
        )
        let (sourceRevision, sourceOverflow) = snapshot.sourceReference.revision.addingReportingOverflow(1)
        guard !sourceOverflow else {
            throw MultiDifferenceMergeWorkflowError.sourceRevisionExhausted
        }
        let left = destination == .left ? successorDestination : snapshot.sourceReference.left
        let right = destination == .right ? successorDestination : snapshot.sourceReference.right
        return (
            MultiDifferenceMergeWorkflowSourceReference(
                identity: snapshot.sourceReference.identity,
                revision: sourceRevision,
                left: left,
                right: right
            ),
            successorDestination
        )
    }

    private static func successorComparisonReference(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        source: MultiDifferenceMergeWorkflowSourceReference
    ) throws -> MultiDifferenceMergeWorkflowComparisonReference {
        let (revision, overflow) = snapshot.comparisonReference.revision.addingReportingOverflow(1)
        guard !overflow else {
            throw MultiDifferenceMergeWorkflowError.comparisonRevisionExhausted
        }
        return MultiDifferenceMergeWorkflowComparisonReference(
            identity: snapshot.comparisonReference.identity,
            revision: revision,
            source: source
        )
    }

    private static func retainedByteBaseEstimate(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        inputBytes: Int,
        rowTextBytes: Int,
        optionBytes: Int,
        work: inout WorkBudget
    ) throws -> Int {
        var total = try checkedAdd(inputBytes, rowTextBytes)
        total = try checkedAdd(total, try checkedMultiply(optionBytes, 4))
        let optionItems = try checkedAdd(
            snapshot.comparisonOptions.lineFilters.count,
            snapshot.comparisonOptions.substitutions.count
        )
        total = try checkedAdd(total, try checkedMultiply(optionItems, 512))
        total = try checkedAdd(total, try checkedMultiply(snapshot.comparisonRows.count, 192))
        var differenceRowIDCount = 0
        for run in snapshot.selection.differenceRuns {
            try work.consume()
            differenceRowIDCount = try checkedAdd(differenceRowIDCount, run.rowIDs.count)
        }
        let retainedSelectionIDs = try checkedAdd(
            snapshot.selection.selectedRowIDs.count,
            differenceRowIDCount
        )
        total = try checkedAdd(
            total,
            try checkedMultiply(retainedSelectionIDs, 32)
        )
        total = try checkedAdd(
            total,
            try checkedMultiply(snapshot.selection.differenceRuns.count, 256)
        )
        return total
    }

    private static func successorComparisonRetainedByteEstimate(
        rows: [DiffRow],
        work: inout WorkBudget
    ) throws -> Int {
        try checkedAdd(
            try rowTextUTF8ByteCount(rows, work: &work),
            try checkedMultiply(rows.count, 192)
        )
    }

    private static func utf8ByteCount(of snapshot: ComparisonSnapshot) throws -> Int {
        try checkedAdd(snapshot.left.utf8.count, snapshot.right.utf8.count)
    }

    fileprivate static func successorComparisonsExactlyEqual(
        _ left: MultiDifferenceMergeWorkflowSuccessorComparison,
        _ right: MultiDifferenceMergeWorkflowSuccessorComparison
    ) -> Bool {
        left.reference == right.reference
            && left.optionsGeneration == right.optionsGeneration
            && snapshotsExactlyEqual(left.source, right.source)
            && rowsExactlyEqual(left.rows, right.rows)
            && comparisonOptionsExactlyEqual(left.options, right.options)
    }

    fileprivate static func successorTargetsExactlyEqual(
        _ left: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?,
        _ right: MultiDifferenceMergeWorkflowSuccessorDifferenceTarget?
    ) -> Bool {
        switch (left, right) {
        case (nil, nil):
            true
        case (.some(let left), .some(let right)):
            left.id == right.id
                && left.comparison == right.comparison
                && left.rowRange == right.rowRange
                && left.rowIDs == right.rowIDs
        default:
            false
        }
    }

    fileprivate static func comparisonOptionsExactlyEqual(
        _ left: LineDiffOptions,
        _ right: LineDiffOptions
    ) -> Bool {
        guard left.algorithm == right.algorithm,
            left.whitespace == right.whitespace,
            left.ignoreCase == right.ignoreCase,
            left.ignoreNumbers == right.ignoreNumbers,
            left.ignoreBlankLines == right.ignoreBlankLines,
            left.ignoreComments == right.ignoreComments,
            left.ignoreLineEndings == right.ignoreLineEndings,
            left.indentHeuristic == right.indentHeuristic,
            left.detectMovedBlocks == right.detectMovedBlocks,
            left.lineFiltersEnabled == right.lineFiltersEnabled,
            left.substitutionsEnabled == right.substitutionsEnabled,
            left.commentSyntax == right.commentSyntax,
            left.lineFilters.count == right.lineFilters.count,
            left.substitutions.count == right.substitutions.count
        else {
            return false
        }
        for index in left.lineFilters.indices {
            let leftRule = left.lineFilters[index]
            let rightRule = right.lineFilters[index]
            guard leftRule.caseSensitive == rightRule.caseSensitive,
                stringsExactlyEqual(leftRule.pattern, rightRule.pattern)
            else {
                return false
            }
        }
        for index in left.substitutions.indices {
            let leftRule = left.substitutions[index]
            let rightRule = right.substitutions[index]
            guard leftRule.caseSensitive == rightRule.caseSensitive,
                stringsExactlyEqual(leftRule.pattern, rightRule.pattern),
                stringsExactlyEqual(leftRule.replacement, rightRule.replacement)
            else {
                return false
            }
        }
        return true
    }

    fileprivate static func snapshotsExactlyEqual(
        _ left: ComparisonSnapshot,
        _ right: ComparisonSnapshot
    ) -> Bool {
        stringsExactlyEqual(left.left, right.left)
            && stringsExactlyEqual(left.right, right.right)
    }

    private static func rowsExactlyEqual(_ left: [DiffRow], _ right: [DiffRow]) -> Bool {
        guard left.count == right.count else { return false }
        for index in left.indices {
            let leftRow = left[index]
            let rightRow = right[index]
            guard leftRow.id == rightRow.id,
                leftRow.kind == rightRow.kind,
                leftRow.hasEqualSourceRecords == rightRow.hasEqualSourceRecords,
                linesExactlyEqual(leftRow.left, rightRow.left),
                linesExactlyEqual(leftRow.right, rightRow.right)
            else {
                return false
            }
        }
        return true
    }

    private static func linesExactlyEqual(_ left: DiffLine?, _ right: DiffLine?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return true
        case (.some(let left), .some(let right)):
            return left.number == right.number && stringsExactlyEqual(left.text, right.text)
        default:
            return false
        }
    }

    private static func stringsExactlyEqual(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    private static func snapshotsExactlyEqual(
        _ left: ComparisonSnapshot,
        _ right: ComparisonSnapshot,
        work: inout WorkBudget
    ) throws -> Bool {
        try stringsExactlyEqual(left.left, right.left, work: &work)
            && stringsExactlyEqual(left.right, right.right, work: &work)
    }

    private static func stringsExactlyEqual(
        _ left: String,
        _ right: String,
        work: inout WorkBudget
    ) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var pendingWork: UInt64 = 0
        while true {
            let leftByte = leftIterator.next()
            let rightByte = rightIterator.next()
            guard leftByte == rightByte else {
                try work.consume(pendingWork)
                return false
            }
            guard leftByte != nil else {
                try work.consume(pendingWork)
                return true
            }
            pendingWork += 1
            if pendingWork >= work.cancellationCheckInterval {
                try work.consume(pendingWork)
                pendingWork = 0
            }
        }
    }

    private static func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow, result >= 0 else {
            throw MultiDifferenceMergeWorkflowError.arithmeticOverflow
        }
        return result
    }

    private static func checkedMultiply(_ left: Int, _ right: Int) throws -> Int {
        let (result, overflow) = left.multipliedReportingOverflow(by: right)
        guard !overflow, result >= 0 else {
            throw MultiDifferenceMergeWorkflowError.arithmeticOverflow
        }
        return result
    }

    private struct WorkBudget {
        let maximum: UInt64
        let cancellationCheckInterval: UInt64
        private(set) var consumed: UInt64 = 0
        private var unitsSinceCancellationCheck: UInt64 = 0

        init(limits: MultiDifferenceMergeWorkflowLimits) throws {
            try MultiDifferenceMergeWorkflow.validate(limits)
            maximum = limits.maximumWorkUnits
            cancellationCheckInterval = limits.cancellationCheckInterval
            try Task<Never, Never>.checkCancellation()
        }

        mutating func consume(_ amount: UInt64 = 1) throws {
            guard amount <= maximum - consumed else {
                throw MultiDifferenceMergeWorkflowError.workLimitExceeded(maximumUnits: maximum)
            }
            consumed += amount
            let unitsUntilCancellationCheck = cancellationCheckInterval - unitsSinceCancellationCheck
            if amount >= unitsUntilCancellationCheck {
                try Task<Never, Never>.checkCancellation()
                unitsSinceCancellationCheck = (amount - unitsUntilCancellationCheck) % cancellationCheckInterval
            } else {
                unitsSinceCancellationCheck += amount
            }
        }

        mutating func checkCancellation() throws {
            try Task<Never, Never>.checkCancellation()
            unitsSinceCancellationCheck = 0
        }

        mutating func finish() throws {
            try checkCancellation()
        }
    }
}

extension MultiDifferenceMergeWorkflowLimits: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowLimits(comparisonRows: \(maximumComparisonRows), selectedRows: \(maximumSelectedRows), differenceGroups: \(maximumDifferenceGroups), workUnits: \(maximumWorkUnits), comparisonOptions: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "maximumComparisonRows": maximumComparisonRows,
                "maximumSelectedRows": maximumSelectedRows,
                "maximumDifferenceGroups": maximumDifferenceGroups,
                "maximumWorkUnits": maximumWorkUnits,
                "cancellationCheckInterval": cancellationCheckInterval,
                "comparisonOptions": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowSnapshot: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowSnapshot(comparisonRows: \(comparisonRows.count), selectedRows: \(selection.rowRange.count), differenceGroups: \(selection.differenceRuns.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "comparisonReference": comparisonReference,
                "selectionReference": selectionReference,
                "comparisonRowCount": comparisonRows.count,
                "selectedRowCount": selection.rowRange.count,
                "differenceGroupCount": selection.differenceRuns.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowPrimitiveInvocation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowPrimitiveInvocation(direction: \(multiDifferenceMergeWorkflowDirectionName(direction)), selectedRows: \(selectedAlignedRows.count), differenceGroups: \(selection.differenceGroups.count), comparisonRows: \(state.comparisonRows.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "direction": multiDifferenceMergeWorkflowDirectionName(direction),
                "selectedRowCount": selectedAlignedRows.count,
                "differenceGroupCount": selection.differenceGroups.count,
                "comparisonRowCount": state.comparisonRows.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowSuccessorComparison: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowSuccessorComparison(rows: \(rows.count), lineFilters: \(options.lineFilters.count), substitutions: \(options.substitutions.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "rowCount": rows.count,
                "lineFilterCount": options.lineFilters.count,
                "substitutionCount": options.substitutions.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent(rows: \(successor.rows.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "expectedSource": expectedSource,
                "expectedInvalidatedComparison": expectedInvalidatedComparison,
                "expectedComparisonOptionsGeneration": expectedComparisonOptionsGeneration,
                "successorReference": successor.reference,
                "successorRowCount": successor.rows.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowTransaction: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowTransaction(direction: \(multiDifferenceMergeWorkflowDirectionName(direction)), destination: \(destination.rawValue), selectedRows: \(selection.rowRange.count), changedGroups: \(changedGroups.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "direction": multiDifferenceMergeWorkflowDirectionName(direction),
                "destination": destination,
                "expectedSnapshot": expectedSnapshot,
                "selectedRowCount": selection.rowRange.count,
                "differenceGroupCount": selection.differenceGroups.count,
                "changedGroupCount": changedGroups.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowRequiredEffect: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowRequiredEffect(\(multiDifferenceMergeWorkflowEffectName(self)), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "effect": multiDifferenceMergeWorkflowEffectName(self),
                "payload": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

extension MultiDifferenceMergeWorkflowPlanningReceipt: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowPlanningReceipt(direction: \(multiDifferenceMergeWorkflowDirectionName(intent.direction)), advance: \(intent.advance.rawValue), destination: \(destination.rawValue), changedGroups: \(changedGroups.count), resultBytes: \(resultUTF8ByteCount), retainedBytes: \(retainedUTF8ByteEstimate), workUnits: \(workflowWorkUnitsConsumed), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "expectedSnapshot": expectedSnapshot,
                "direction": multiDifferenceMergeWorkflowDirectionName(intent.direction),
                "advance": intent.advance,
                "destination": destination,
                "selectedRowCount": selection.rowRange.count,
                "differenceGroupCount": selection.differenceGroups.count,
                "changedGroupCount": changedGroups.count,
                "resultUTF8ByteCount": resultUTF8ByteCount,
                "retainedUTF8ByteEstimate": retainedUTF8ByteEstimate,
                "workflowWorkUnitsConsumed": workflowWorkUnitsConsumed,
                "primitiveMaximumWork": primitiveMaximumWork,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowSnapshotCAS: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowSnapshotCAS(contents: <redacted>)"
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

extension MultiDifferenceMergeWorkflowPlan: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowPlan(direction: \(multiDifferenceMergeWorkflowDirectionName(transaction.direction)), effects: \(requiredEffects.count), changedGroups: \(transaction.changedGroups.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "reference": reference,
                "expectedSnapshot": expectedSnapshot,
                "direction": multiDifferenceMergeWorkflowDirectionName(transaction.direction),
                "requiredEffectCount": requiredEffects.count,
                "changedGroupCount": transaction.changedGroups.count,
                "executorContract": executorContract,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowOwnerCommitEvidence: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowOwnerCommitEvidence(status: committed, comparisonRows: \(comparedExpectedState.comparisonRows.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": "committed",
                "comparedSnapshot": comparedExpectedState.reference,
                "comparedDestinationRevision": comparedDestinationRevision,
                "successorSource": successorSource,
                "successorDestinationRevision": successorDestinationRevision,
                "comparisonRowCount": comparedExpectedState.comparisonRows.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowAtomicCommitOutcome: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowAtomicCommitOutcome(status: \(multiDifferenceMergeWorkflowAtomicCommitStatus(self)), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": multiDifferenceMergeWorkflowAtomicCommitStatus(self),
                "payload": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

extension MultiDifferenceMergeWorkflowCommitReceipt: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowCommitReceipt(status: committed, changedGroups: \(transaction.changedGroups.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": "committed",
                "planReference": planReference,
                "direction": multiDifferenceMergeWorkflowDirectionName(transaction.direction),
                "changedGroupCount": transaction.changedGroups.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence(status: published, rows: \(publishedComparison.rows.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": "published",
                "comparedSource": comparedSource,
                "comparedInvalidatedComparison": comparedInvalidatedComparison,
                "comparedComparisonOptionsGeneration": comparedComparisonOptionsGeneration,
                "publishedComparisonReference": publishedComparison.reference,
                "publishedRowCount": publishedComparison.rows.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowNavigationPublicationEvidence: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowNavigationPublicationEvidence(status: published, target: \(publishedTarget == nil ? "none" : "resolved"), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": "published",
                "publishedComparison": publishedComparison,
                "target": publishedTarget == nil ? "none" : "resolved",
                "payload": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowPublicationEvidence: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowPublicationEvidence(status: \(multiDifferenceMergeWorkflowPublicationStatus(self)), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": multiDifferenceMergeWorkflowPublicationStatus(self),
                "payload": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

extension MultiDifferenceMergeWorkflowPublicationReceipt: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowPublicationReceipt(effectIndex: \(effectIndex), effect: \(multiDifferenceMergeWorkflowEffectName(effect)), status: published, payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "effectIndex": effectIndex,
                "effect": multiDifferenceMergeWorkflowEffectName(effect),
                "status": "published",
                "payload": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowExecutionReceipt: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowExecutionReceipt(status: completed, completedEffects: \(completedEffects.count), publications: \(publicationReceipts.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": "completed",
                "completedEffectCount": completedEffects.count,
                "publicationCount": publicationReceipts.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowExecutionFailureReceipt: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowExecutionFailureReceipt(status: failed, reason: \(reason.rawValue), failedEffect: \(multiDifferenceMergeWorkflowEffectName(failedEffect)), completedEffects: \(completedEffects.count), unattemptedEffects: \(unattemptedEffects.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": "failed",
                "reason": reason,
                "failedEffect": multiDifferenceMergeWorkflowEffectName(failedEffect),
                "completedEffectCount": completedEffects.count,
                "unattemptedEffectCount": unattemptedEffects.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowExecutionUncertaintyReceipt: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "MultiDifferenceMergeWorkflowExecutionUncertaintyReceipt(status: uncertain, reason: \(reason.rawValue), completedEffects: \(completedEffects.count), uncertainEffects: \(uncertainEffects.count), unattemptedEffects: \(unattemptedEffects.count), contents: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": "uncertain",
                "reason": reason,
                "completedEffectCount": completedEffects.count,
                "uncertainEffectCount": uncertainEffects.count,
                "unattemptedEffectCount": unattemptedEffects.count,
                "contents": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

extension MultiDifferenceMergeWorkflowExecutionOutcome: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        switch self {
        case .completed(let receipt):
            "MultiDifferenceMergeWorkflowExecutionOutcome(status: completed, completedEffects: \(receipt.completedEffects.count), contents: <redacted>)"
        case .failed(let receipt):
            "MultiDifferenceMergeWorkflowExecutionOutcome(status: failed, reason: \(receipt.reason.rawValue), completedEffects: \(receipt.completedEffects.count), contents: <redacted>)"
        case .uncertain(let receipt):
            "MultiDifferenceMergeWorkflowExecutionOutcome(status: uncertain, reason: \(receipt.reason.rawValue), completedEffects: \(receipt.completedEffects.count), contents: <redacted>)"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "status": multiDifferenceMergeWorkflowExecutionStatus(self),
                "details": multiDifferenceMergeWorkflowExecutionDetails(self),
                "contents": "<redacted>"
            ],
            displayStyle: .enum
        )
    }
}

extension MultiDifferenceMergeWorkflowError: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        errorDescription ?? "Multi-difference merge workflow failed."
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["message": description, "details": "<redacted>"],
            displayStyle: .enum
        )
    }
}

private func multiDifferenceMergeWorkflowDirectionName(_ direction: MergeDirection) -> String {
    switch direction {
    case .leftToRight:
        "leftToRight"
    case .rightToLeft:
        "rightToLeft"
    }
}

private func multiDifferenceMergeWorkflowEffectName(
    _ effect: MultiDifferenceMergeWorkflowRequiredEffect
) -> String {
    switch effect {
    case .commitOwnerTransaction:
        "commitOwnerTransaction"
    case .publishSuccessorComparison:
        "publishSuccessorComparison"
    case .publishNavigation:
        "publishNavigation"
    }
}

private func multiDifferenceMergeWorkflowAtomicCommitStatus(
    _ outcome: MultiDifferenceMergeWorkflowAtomicCommitOutcome
) -> String {
    switch outcome {
    case .committed:
        "committed"
    case .notCommitted:
        "notCommitted"
    case .commitUncertain:
        "commitUncertain"
    }
}

private func multiDifferenceMergeWorkflowPublicationStatus(
    _ evidence: MultiDifferenceMergeWorkflowPublicationEvidence
) -> String {
    switch evidence {
    case .successorComparison:
        "successorComparisonPublished"
    case .navigation:
        "navigationPublished"
    }
}

private func multiDifferenceMergeWorkflowExecutionStatus(
    _ outcome: MultiDifferenceMergeWorkflowExecutionOutcome
) -> String {
    switch outcome {
    case .completed:
        "completed"
    case .failed:
        "failed"
    case .uncertain:
        "uncertain"
    }
}

private func multiDifferenceMergeWorkflowExecutionDetails(
    _ outcome: MultiDifferenceMergeWorkflowExecutionOutcome
) -> String {
    switch outcome {
    case .completed(let receipt):
        "completedEffects: \(receipt.completedEffects.count)"
    case .failed(let receipt):
        "reason: \(receipt.reason.rawValue), completedEffects: \(receipt.completedEffects.count)"
    case .uncertain(let receipt):
        "reason: \(receipt.reason.rawValue), completedEffects: \(receipt.completedEffects.count)"
    }
}
