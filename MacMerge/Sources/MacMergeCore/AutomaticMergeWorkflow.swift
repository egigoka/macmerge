import Foundation

public struct AutomaticMergeWorkflowPaneRevision: Equatable, Hashable, Sendable {
    public let documentID: UUID
    public let revision: UInt64

    public init(documentID: UUID, revision: UInt64) {
        self.documentID = documentID
        self.revision = revision
    }
}

public struct AutomaticMergeWorkflowComparisonIdentity: RawRepresentable, Equatable, Hashable,
    Sendable
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Exact comparison generation and source revisions. Owners must never reuse a generation for
/// different source bytes, rows, options, pane state, command state, or capabilities.
public struct AutomaticMergeWorkflowComparisonReference: Equatable, Hashable, Sendable {
    public let identity: AutomaticMergeWorkflowComparisonIdentity
    public let generation: UInt64
    public let leftSource: AutomaticMergeWorkflowPaneRevision
    public let rightSource: AutomaticMergeWorkflowPaneRevision

    public init(
        identity: AutomaticMergeWorkflowComparisonIdentity,
        generation: UInt64,
        leftSource: AutomaticMergeWorkflowPaneRevision,
        rightSource: AutomaticMergeWorkflowPaneRevision
    ) {
        self.identity = identity
        self.generation = generation
        self.leftSource = leftSource
        self.rightSource = rightSource
    }
}

public struct AutomaticMergeWorkflowPaneSnapshot: Sendable {
    public let revision: AutomaticMergeWorkflowPaneRevision
    public let text: String
    public let isLoaded: Bool
    public let isEditable: Bool
    public let isReadOnly: Bool
    public let isDirty: Bool

    public init(
        revision: AutomaticMergeWorkflowPaneRevision,
        text: String,
        isLoaded: Bool = true,
        isEditable: Bool,
        isReadOnly: Bool,
        isDirty: Bool
    ) {
        self.revision = revision
        self.text = text
        self.isLoaded = isLoaded
        self.isEditable = isEditable
        self.isReadOnly = isReadOnly
        self.isDirty = isDirty
    }

    public var commandSideState: MergeCommandPolicy.SideState {
        MergeCommandPolicy.SideState(
            isLoaded: isLoaded,
            isEditable: isEditable,
            isDirty: isDirty
        )
    }
}

extension AutomaticMergeWorkflowPaneSnapshot: Equatable {
    public static func == (
        lhs: AutomaticMergeWorkflowPaneSnapshot,
        rhs: AutomaticMergeWorkflowPaneSnapshot
    ) -> Bool {
        lhs.revision == rhs.revision
            && lhs.text.utf8.elementsEqual(rhs.text.utf8)
            && lhs.isLoaded == rhs.isLoaded
            && lhs.isEditable == rhs.isEditable
            && lhs.isReadOnly == rhs.isReadOnly
            && lhs.isDirty == rhs.isDirty
    }
}

public struct AutomaticMergeWorkflowCapabilities: OptionSet, Equatable, Hashable, Sendable {
    public static let plan = AutomaticMergeWorkflowCapabilities(rawValue: 1 << 0)
    public static let stageOperations = AutomaticMergeWorkflowCapabilities(rawValue: 1 << 1)
    public static let atomicPublication = AutomaticMergeWorkflowCapabilities(rawValue: 1 << 2)
    public static let registerUndo = AutomaticMergeWorkflowCapabilities(rawValue: 1 << 3)
    public static let all: AutomaticMergeWorkflowCapabilities = [
        .plan, .stageOperations, .atomicPublication, .registerUndo
    ]

    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

/// Immutable owner state from which automatic merge is planned. Comparison rows remain bound to
/// exact pane bytes and selected comparison options, not merely to a generation number.
public struct AutomaticMergeWorkflowSnapshot: Sendable {
    public let comparison: AutomaticMergeWorkflowComparisonReference
    public let source: ComparisonSnapshot
    public let rows: [DiffRow]
    public let comparisonOptions: LineDiffOptions
    public let left: AutomaticMergeWorkflowPaneSnapshot
    public let right: AutomaticMergeWorkflowPaneSnapshot
    public let commandState: MergeCommandPolicy.State
    public let capabilities: AutomaticMergeWorkflowCapabilities
    public let conflictPolicy: AutomaticMergeWorkflowConflictPolicy

    public init(
        comparison: AutomaticMergeWorkflowComparisonReference,
        source: ComparisonSnapshot,
        rows: [DiffRow],
        comparisonOptions: LineDiffOptions = LineDiffOptions(),
        left: AutomaticMergeWorkflowPaneSnapshot,
        right: AutomaticMergeWorkflowPaneSnapshot,
        commandState: MergeCommandPolicy.State,
        capabilities: AutomaticMergeWorkflowCapabilities = .all,
        conflictPolicy: AutomaticMergeWorkflowConflictPolicy = .applyNonconflicting
    ) {
        self.comparison = comparison
        self.source = source
        self.rows = rows
        self.comparisonOptions = comparisonOptions
        self.left = left
        self.right = right
        self.commandState = commandState
        self.capabilities = capabilities
        self.conflictPolicy = conflictPolicy
    }

    public subscript(side: AutomaticMergeSide) -> AutomaticMergeWorkflowPaneSnapshot {
        switch side {
        case .left: left
        case .right: right
        }
    }

}

extension AutomaticMergeWorkflowSnapshot: Equatable {
    public static func == (
        lhs: AutomaticMergeWorkflowSnapshot,
        rhs: AutomaticMergeWorkflowSnapshot
    ) -> Bool {
        automaticMergeWorkflowSnapshotsMatch(lhs, rhs)
    }
}

/// Full-content CAS. Public reference fields diagnose ordinary staleness; exact retained state
/// detects an owner that changes contents without advancing its generation or pane revisions.
public struct AutomaticMergeWorkflowSnapshotCAS: Equatable, Sendable {
    public let comparison: AutomaticMergeWorkflowComparisonReference
    fileprivate let snapshot: AutomaticMergeWorkflowSnapshot
    fileprivate let limits: AutomaticMergeWorkflowLimits

    fileprivate init(
        snapshot: AutomaticMergeWorkflowSnapshot,
        limits: AutomaticMergeWorkflowLimits
    ) {
        comparison = snapshot.comparison
        self.snapshot = snapshot
        self.limits = limits
    }

}

public enum AutomaticMergeWorkflowConflictPolicy: String, CaseIterable, Equatable, Hashable,
    Sendable
{
    /// Any unresolved or read-only destination run keeps the plan non-executable.
    case requireConflictFree
    /// Stage every resolvable operation and retain unresolved and blocked runs in the receipt.
    case applyNonconflicting
}

public enum AutomaticMergeWorkflowLimit: String, CaseIterable, Equatable, Hashable, Sendable {
    case rows
    case runs
    case operations
    case inputUTF8Bytes
    case outputUTF8Bytes
    case retainedBytes
    case optionItems
    case optionUTF8Bytes
    case workUnits
    case comparisonLinePairs
    case cancellationCheckInterval
}

public struct AutomaticMergeWorkflowLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumRows = 1_048_576
    public static let hardMaximumRuns = 1_048_576
    public static let hardMaximumOperations = 1_048_576
    public static let hardMaximumInputUTF8Bytes = 64 * 1_024 * 1_024
    public static let hardMaximumOutputUTF8Bytes = 256 * 1_024 * 1_024
    public static let hardMaximumRetainedBytes = 512 * 1_024 * 1_024
    public static let hardMaximumOptionItems = 65_536
    public static let hardMaximumOptionUTF8Bytes = 16 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 1 << 40
    public static let hardMaximumComparisonLinePairs: UInt64 = 1 << 32
    public static let hardMaximumCancellationCheckInterval = 65_536
    public static let `default` = AutomaticMergeWorkflowLimits()

    public let maximumRows: Int
    public let maximumRuns: Int
    public let maximumOperations: Int
    public let maximumInputUTF8BytesPerPane: Int
    public let maximumOutputUTF8BytesPerPane: Int
    public let maximumRetainedBytes: Int
    public let maximumOptionItems: Int
    public let maximumOptionUTF8Bytes: Int
    public let maximumWorkUnits: UInt64
    public let maximumComparisonLinePairs: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumRows: Int = 1_048_576,
        maximumRuns: Int = 1_048_576,
        maximumOperations: Int = 1_048_576,
        maximumInputUTF8BytesPerPane: Int = 64 * 1_024 * 1_024,
        maximumOutputUTF8BytesPerPane: Int = 256 * 1_024 * 1_024,
        maximumRetainedBytes: Int = 256 * 1_024 * 1_024,
        maximumOptionItems: Int = 4_096,
        maximumOptionUTF8Bytes: Int = 1 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 2 * 1_024 * 1_024 * 1_024,
        maximumComparisonLinePairs: UInt64 = 64 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumRows = maximumRows
        self.maximumRuns = maximumRuns
        self.maximumOperations = maximumOperations
        self.maximumInputUTF8BytesPerPane = maximumInputUTF8BytesPerPane
        self.maximumOutputUTF8BytesPerPane = maximumOutputUTF8BytesPerPane
        self.maximumRetainedBytes = maximumRetainedBytes
        self.maximumOptionItems = maximumOptionItems
        self.maximumOptionUTF8Bytes = maximumOptionUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumComparisonLinePairs = maximumComparisonLinePairs
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public struct AutomaticMergeWorkflowRequest: Sendable {
    public let snapshot: AutomaticMergeWorkflowSnapshot
    public let limits: AutomaticMergeWorkflowLimits

    public init(
        snapshot: AutomaticMergeWorkflowSnapshot,
        limits: AutomaticMergeWorkflowLimits = .default
    ) {
        self.snapshot = snapshot
        self.limits = limits
    }
}

public enum AutomaticMergeWorkflowPlanDisposition: String, CaseIterable, Equatable, Hashable,
    Sendable
{
    case noChanges
    case executable
    case executableWithConflicts
    case blockedByConflicts
}

public struct AutomaticMergeWorkflowPlannedOperation: Equatable, Sendable {
    public let executionIndex: Int
    public let operation: AutomaticMergeOperation
    /// Row IDs are ordered end-to-start within the run. Executor must not derive them again.
    public let rowIDs: [DiffRow.ID]

    fileprivate init(
        executionIndex: Int,
        operation: AutomaticMergeOperation,
        rowIDs: [DiffRow.ID]
    ) {
        self.executionIndex = executionIndex
        self.operation = operation
        self.rowIDs = rowIDs
    }

    public var destination: AutomaticMergeSide { operation.destination }
}

public struct AutomaticMergeWorkflowPaneMutationIntent: Equatable, Sendable {
    public let side: AutomaticMergeSide
    public let predecessor: AutomaticMergeWorkflowPaneRevision
    public let successor: AutomaticMergeWorkflowPaneRevision
    public let successorIsDirty: Bool

    fileprivate init(
        side: AutomaticMergeSide,
        predecessor: AutomaticMergeWorkflowPaneRevision
    ) {
        self.side = side
        self.predecessor = predecessor
        successor = AutomaticMergeWorkflowPaneRevision(
            documentID: predecessor.documentID,
            revision: predecessor.revision + 1
        )
        successorIsDirty = true
    }
}

public struct AutomaticMergeWorkflowUndoIntent: Equatable, Sendable {
    public enum Grouping: String, CaseIterable, Equatable, Hashable, Sendable {
        case singleAutomaticMergeTransaction
    }

    public let grouping: Grouping
    public let changedSides: [AutomaticMergeSide]
    public let predecessorRevisions: [AutomaticMergeWorkflowPaneRevision]
    public let successorRevisions: [AutomaticMergeWorkflowPaneRevision]
    public let restoreLeftDirtyState: Bool
    public let restoreRightDirtyState: Bool

    fileprivate init(
        mutations: [AutomaticMergeWorkflowPaneMutationIntent],
        snapshot: AutomaticMergeWorkflowSnapshot
    ) {
        grouping = .singleAutomaticMergeTransaction
        changedSides = mutations.map(\.side)
        predecessorRevisions = mutations.map(\.predecessor)
        successorRevisions = mutations.map(\.successor)
        restoreLeftDirtyState = snapshot.left.isDirty
        restoreRightDirtyState = snapshot.right.isDirty
    }
}

public struct AutomaticMergeWorkflowComparisonInvalidationIntent: Equatable, Hashable, Sendable {
    public let predecessor: AutomaticMergeWorkflowComparisonReference
    public let successor: AutomaticMergeWorkflowComparisonReference
    public let lifecycle: MergeCommandPolicy.ComparisonLifecycle

    fileprivate init(
        predecessor: AutomaticMergeWorkflowComparisonReference,
        mutations: [AutomaticMergeWorkflowPaneMutationIntent]
    ) {
        var left = predecessor.leftSource
        var right = predecessor.rightSource
        for mutation in mutations {
            switch mutation.side {
            case .left: left = mutation.successor
            case .right: right = mutation.successor
            }
        }
        self.predecessor = predecessor
        successor = AutomaticMergeWorkflowComparisonReference(
            identity: predecessor.identity,
            generation: predecessor.generation + 1,
            leftSource: left,
            rightSource: right
        )
        lifecycle = .stale
    }
}

/// One atomic owner publication: both pane drafts, revisions, dirty flags, undo registration, and
/// comparison invalidation commit together or not at all.
public struct AutomaticMergeWorkflowPublicationIntent: Equatable, Sendable {
    public let paneMutations: [AutomaticMergeWorkflowPaneMutationIntent]
    public let undo: AutomaticMergeWorkflowUndoIntent
    public let comparison: AutomaticMergeWorkflowComparisonInvalidationIntent

    fileprivate init(
        mutations: [AutomaticMergeWorkflowPaneMutationIntent],
        snapshot: AutomaticMergeWorkflowSnapshot
    ) {
        paneMutations = mutations
        undo = AutomaticMergeWorkflowUndoIntent(mutations: mutations, snapshot: snapshot)
        comparison = AutomaticMergeWorkflowComparisonInvalidationIntent(
            predecessor: snapshot.comparison,
            mutations: mutations
        )
    }

    public func mutation(
        for side: AutomaticMergeSide
    ) -> AutomaticMergeWorkflowPaneMutationIntent? {
        paneMutations.first { $0.side == side }
    }
}

public struct AutomaticMergeWorkflowPlanningReceipt: Equatable, Sendable {
    public let comparison: AutomaticMergeWorkflowComparisonReference
    public let conflictPolicy: AutomaticMergeWorkflowConflictPolicy
    public let disposition: AutomaticMergeWorkflowPlanDisposition
    public let operationCount: Int
    public let unresolvedConflicts: [AutomaticMergeUnresolvedConflict]
    public let blockedConflicts: [AutomaticMergeBlockedConflict]
    public let estimatedRetainedBytes: Int
    public let workUnitsConsumed: UInt64

    fileprivate init(
        comparison: AutomaticMergeWorkflowComparisonReference,
        conflictPolicy: AutomaticMergeWorkflowConflictPolicy,
        disposition: AutomaticMergeWorkflowPlanDisposition,
        mergePlan: AutomaticMergePlan,
        estimatedRetainedBytes: Int,
        workUnitsConsumed: UInt64
    ) {
        self.comparison = comparison
        self.conflictPolicy = conflictPolicy
        self.disposition = disposition
        operationCount = mergePlan.operations.count
        unresolvedConflicts = mergePlan.unresolvedConflicts
        blockedConflicts = mergePlan.blockedConflicts
        self.estimatedRetainedBytes = estimatedRetainedBytes
        self.workUnitsConsumed = workUnitsConsumed
    }
}

public enum AutomaticMergeWorkflowSnapshotLeaseContract: String, Equatable, Hashable, Sendable {
    case validateExactComparisonPaneCommandAndCapabilityStateBeforeEveryStageAndPublication
}

public enum AutomaticMergeWorkflowOperationContract: String, Equatable, Hashable, Sendable {
    case coreComputesExactOriginalSourceRowsEndToStartInPlanOrder
}

public enum AutomaticMergeWorkflowPublicationContract: String, Equatable, Hashable, Sendable {
    case atomicallyPublishAllDraftsRevisionsDirtyUndoAndInvalidationOrPublishNothing
}

public enum AutomaticMergeWorkflowCancellationContract: String, Equatable, Hashable, Sendable {
    case cancellableBeforeEachStageAndPublicationNoncancellableAfterPublicationAuthorization
}

public enum AutomaticMergeWorkflowReceiptContract: String, Equatable, Hashable, Sendable {
    case completedOnlyWithExactAtomicSuccessorKnownRejectionDistinctFromUncertainty
}

/// Mandatory app-layer boundary. Workflow performs no document edit, undo registration, comparison
/// publication, filesystem operation, or UI operation.
public struct AutomaticMergeWorkflowExecutorContract: Equatable, Hashable, Sendable {
    public static let required = AutomaticMergeWorkflowExecutorContract()

    public let snapshotLease =
        AutomaticMergeWorkflowSnapshotLeaseContract
        .validateExactComparisonPaneCommandAndCapabilityStateBeforeEveryStageAndPublication
    public let operations =
        AutomaticMergeWorkflowOperationContract
        .coreComputesExactOriginalSourceRowsEndToStartInPlanOrder
    public let publication =
        AutomaticMergeWorkflowPublicationContract
        .atomicallyPublishAllDraftsRevisionsDirtyUndoAndInvalidationOrPublishNothing
    public let cancellation =
        AutomaticMergeWorkflowCancellationContract
        .cancellableBeforeEachStageAndPublicationNoncancellableAfterPublicationAuthorization
    public let receipts =
        AutomaticMergeWorkflowReceiptContract
        .completedOnlyWithExactAtomicSuccessorKnownRejectionDistinctFromUncertainty

    public init() {}
}

public struct AutomaticMergeWorkflowStagingProgress: Equatable, Sendable {
    public let planningReceipt: AutomaticMergeWorkflowPlanningReceipt
    public let completedOperationCount: Int
    public let draft: ComparisonSnapshot
    fileprivate let executionID: UUID

}

/// Core-issued proof that exact owner CAS and staging prefix passed immediately before one private
/// draft operation. Permit does not authorize owner-state publication.
public struct AutomaticMergeWorkflowOperationPermit: Equatable, Sendable {
    public let operation: AutomaticMergeWorkflowPlannedOperation
    public let resultingDraft: ComparisonSnapshot
    fileprivate let executionID: UUID
}

/// Core-issued one-shot authorization for an owner-controlled atomic CAS, publication, and undo
/// registration operation. Copies share one revocation gate.
public struct AutomaticMergeWorkflowPublicationPermit: Equatable, Sendable {
    fileprivate let planningReceipt: AutomaticMergeWorkflowPlanningReceipt
    public let intent: AutomaticMergeWorkflowPublicationIntent
    public let stagedDraft: ComparisonSnapshot
    fileprivate let snapshotCAS: AutomaticMergeWorkflowSnapshotCAS
    fileprivate let executionID: UUID
    fileprivate let atomicValidationMaximumWorkUnits: UInt64
    fileprivate let executionGate: AutomaticMergeWorkflowExecutionGate

    public static func == (
        lhs: AutomaticMergeWorkflowPublicationPermit,
        rhs: AutomaticMergeWorkflowPublicationPermit
    ) -> Bool {
        lhs.executionID == rhs.executionID
            && lhs.executionGate === rhs.executionGate
            && lhs.planningReceipt == rhs.planningReceipt
            && lhs.intent == rhs.intent
            && lhs.stagedDraft == rhs.stagedDraft
            && lhs.snapshotCAS == rhs.snapshotCAS
    }

    public var atomicCommitOperation: AutomaticMergeWorkflowAtomicCommitOperation {
        AutomaticMergeWorkflowAtomicCommitOperation(permit: self)
    }
}

public struct AutomaticMergeWorkflowPublishedSuccessor: Equatable, Sendable {
    public let left: AutomaticMergeWorkflowPaneSnapshot
    public let right: AutomaticMergeWorkflowPaneSnapshot
    public let comparison: AutomaticMergeWorkflowComparisonReference
    public let comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle
    public let registeredUndo: AutomaticMergeWorkflowUndoIntent

    public init(
        left: AutomaticMergeWorkflowPaneSnapshot,
        right: AutomaticMergeWorkflowPaneSnapshot,
        comparison: AutomaticMergeWorkflowComparisonReference,
        comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle,
        registeredUndo: AutomaticMergeWorkflowUndoIntent
    ) {
        self.left = left
        self.right = right
        self.comparison = comparison
        self.comparisonLifecycle = comparisonLifecycle
        self.registeredUndo = registeredUndo
    }

}

/// Receipt minted only by `AutomaticMergeWorkflowAtomicCommitOperation.compareAndCommit` after its
/// owner-isolated CAS and atomic publication closure reports an exact committed successor.
public struct AutomaticMergeWorkflowAtomicCommitReceipt: Equatable, Sendable {
    public let successor: AutomaticMergeWorkflowPublishedSuccessor
    fileprivate let executionID: UUID

}

/// Result reported by the owner's nonthrowing atomic publication closure. `.rejected` guarantees
/// that it committed no pane, revision, dirty-state, undo, or comparison change.
public enum AutomaticMergeWorkflowOwnerCommitDecision: Equatable, Sendable {
    case committed(AutomaticMergeWorkflowPublishedSuccessor)
    case rejected
    case uncertain
}

private enum AutomaticMergeWorkflowPublicationClaim {
    case claimed(UUID)
    case sealed(AutomaticMergeWorkflowExecutionOutcome)
}

/// Owner-controlled, non-cancellable CAS+commit+undo operation. It consumes the permit gate before
/// reading live owner state, so no copied permit can later enter another publication closure.
public struct AutomaticMergeWorkflowAtomicCommitOperation: Sendable {
    public let intent: AutomaticMergeWorkflowPublicationIntent
    public let stagedDraft: ComparisonSnapshot
    private let permit: AutomaticMergeWorkflowPublicationPermit

    fileprivate init(permit: AutomaticMergeWorkflowPublicationPermit) {
        intent = permit.intent
        stagedDraft = permit.stagedDraft
        self.permit = permit
    }

    /// Call exactly once from `compareAndCommitAutomaticMerge`. `body` must atomically publish all
    /// pane state, undo registration, and comparison invalidation, or publish nothing.
    public func compareAndCommit<Owner: AutomaticMergeWorkflowAtomicOwner>(
        owner: isolated Owner,
        _ body: (
            isolated Owner,
            AutomaticMergeWorkflowPublicationIntent,
            ComparisonSnapshot
        ) -> AutomaticMergeWorkflowOwnerCommitDecision
    ) -> AutomaticMergeWorkflowExecutionOutcome {
        let uncertain = AutomaticMergeWorkflowExecutionOutcome.publicationUncertain(
            AutomaticMergeWorkflowPublicationUncertaintyReceipt(permit: permit)
        )
        switch permit.executionGate.claimPublication(
            id: permit.executionID,
            uncertainOutcome: uncertain
        ) {
        case .claimed(let claimID):
            let current = owner.currentAutomaticMergeSnapshot()
            do {
                _ = try AutomaticMergeWorkflow.validate(
                    current,
                    against: permit.snapshotCAS,
                    checksCancellation: false,
                    maximumWorkUnits: permit.atomicValidationMaximumWorkUnits
                )
            } catch {
                return permit.executionGate.sealPublication(
                    id: permit.executionID,
                    claimID: claimID,
                    outcome: .publicationRejected(
                        AutomaticMergeWorkflowPublicationRejectionReceipt(permit: permit)
                    ),
                    fallback: uncertain
                )
            }

            let outcome: AutomaticMergeWorkflowExecutionOutcome
            switch body(owner, intent, stagedDraft) {
            case .committed(let successor):
                guard
                    AutomaticMergeWorkflow.successorMatches(
                        predecessor: permit.snapshotCAS.snapshot,
                        stagedDraft: stagedDraft,
                        intent: intent,
                        successor: successor
                    )
                else {
                    outcome = .publicationUncertain(
                        AutomaticMergeWorkflowPublicationUncertaintyReceipt(permit: permit)
                    )
                    break
                }
                let receipt = AutomaticMergeWorkflowAtomicCommitReceipt(
                    successor: successor,
                    executionID: permit.executionID
                )
                outcome = .completed(
                    AutomaticMergeWorkflowSuccessReceipt(
                        permit: permit,
                        atomicCommit: receipt
                    )
                )
            case .rejected:
                outcome = .publicationRejected(
                    AutomaticMergeWorkflowPublicationRejectionReceipt(permit: permit)
                )
            case .uncertain:
                outcome = .publicationUncertain(
                    AutomaticMergeWorkflowPublicationUncertaintyReceipt(permit: permit)
                )
            }
            return permit.executionGate.sealPublication(
                id: permit.executionID,
                claimID: claimID,
                outcome: outcome,
                fallback: uncertain
            )
        case .sealed(let outcome):
            return outcome
        }
    }
}

public struct AutomaticMergeWorkflowSuccessReceipt: Equatable, Sendable {
    public let planningReceipt: AutomaticMergeWorkflowPlanningReceipt
    public let atomicCommit: AutomaticMergeWorkflowAtomicCommitReceipt
    public let predecessor: AutomaticMergeWorkflowComparisonReference
    public let successor: AutomaticMergeWorkflowComparisonReference
    public let paneMutations: [AutomaticMergeWorkflowPaneMutationIntent]
    public let undo: AutomaticMergeWorkflowUndoIntent

    fileprivate init(
        permit: AutomaticMergeWorkflowPublicationPermit,
        atomicCommit: AutomaticMergeWorkflowAtomicCommitReceipt
    ) {
        planningReceipt = permit.planningReceipt
        self.atomicCommit = atomicCommit
        predecessor = permit.snapshotCAS.comparison
        let successor = atomicCommit.successor
        self.successor = successor.comparison
        paneMutations = permit.intent.paneMutations
        undo = successor.registeredUndo
    }
}

public enum AutomaticMergeWorkflowFailureReason: String, CaseIterable, Equatable, Hashable,
    Sendable
{
    case cancelled
    case staleSnapshot
    case commandDisabled
    case capabilityUnavailable
    case operationRejected
    case stagingFailed
    case contractUnsupported
}

public struct AutomaticMergeWorkflowFailureReceipt: Equatable, Sendable {
    public let planningReceipt: AutomaticMergeWorkflowPlanningReceipt
    public let completedStagingOperationCount: Int
    public let reason: AutomaticMergeWorkflowFailureReason
    /// Failure receipts prove owner publication was never attempted.
    public let publicationAttempted: Bool

    fileprivate init(
        plan: AutomaticMergeWorkflowPlan,
        completedStagingOperationCount: Int,
        reason: AutomaticMergeWorkflowFailureReason
    ) {
        planningReceipt = plan.receipt
        self.completedStagingOperationCount = completedStagingOperationCount
        self.reason = reason
        publicationAttempted = false
    }
}

public struct AutomaticMergeWorkflowPublicationUncertaintyReceipt: Equatable, Sendable {
    public let planningReceipt: AutomaticMergeWorkflowPlanningReceipt
    public let publicationIntent: AutomaticMergeWorkflowPublicationIntent
    /// Required atomic owner CAS means all publication fields may have committed, or none did. A
    /// conforming executor can never report a known partial owner-state publication.
    public let atomicPublicationMayHaveCommitted: Bool

    fileprivate init(
        permit: AutomaticMergeWorkflowPublicationPermit
    ) {
        planningReceipt = permit.planningReceipt
        publicationIntent = permit.intent
        atomicPublicationMayHaveCommitted = true
    }
}

public struct AutomaticMergeWorkflowPublicationRejectionReceipt: Equatable, Sendable {
    public let planningReceipt: AutomaticMergeWorkflowPlanningReceipt
    public let publicationIntent: AutomaticMergeWorkflowPublicationIntent
    public let atomicPublicationCommitted: Bool

    fileprivate init(permit: AutomaticMergeWorkflowPublicationPermit) {
        planningReceipt = permit.planningReceipt
        publicationIntent = permit.intent
        atomicPublicationCommitted = false
    }
}

public enum AutomaticMergeWorkflowExecutionOutcome: Equatable, Sendable {
    case completed(AutomaticMergeWorkflowSuccessReceipt)
    case failed(AutomaticMergeWorkflowFailureReceipt)
    case publicationRejected(AutomaticMergeWorkflowPublicationRejectionReceipt)
    case publicationUncertain(AutomaticMergeWorkflowPublicationUncertaintyReceipt)
}

private final class AutomaticMergeWorkflowExecutionGate: @unchecked Sendable {
    private enum State {
        case ready
        case staging(id: UUID, nextOperation: Int)
        case authorizingOperation(id: UUID, operationIndex: Int)
        case operationAuthorized(id: UUID, operationIndex: Int)
        case authorizingPublication(id: UUID, completedOperationCount: Int)
        case publicationAuthorized(id: UUID)
        case publicationClaimed(id: UUID, claimID: UUID)
        case publicationSealed(id: UUID, outcome: AutomaticMergeWorkflowExecutionOutcome)
        case finished(id: UUID)
    }

    private let lock = NSLock()
    private var state: State = .ready
    private var workUnitsConsumed: UInt64 = 0

    func begin(planningWorkUnits: UInt64) throws -> UUID {
        lock.lock()
        defer { lock.unlock() }
        guard case .ready = state else {
            throw AutomaticMergeWorkflowError.planAlreadyConsumed
        }
        let id = UUID()
        workUnitsConsumed = planningWorkUnits
        state = .staging(id: id, nextOperation: 0)
        return id
    }

    func beginOperation(id: UUID, operationIndex: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .staging(let currentID, let nextOperation) = state,
            currentID == id,
            nextOperation == operationIndex
        else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        state = .authorizingOperation(id: id, operationIndex: operationIndex)
    }

    func consumeWork(
        id: UUID,
        operationIndex: Int,
        amount: UInt64,
        maximum: UInt64
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .authorizingOperation(let currentID, let currentOperation) = state,
            currentID == id,
            currentOperation == operationIndex
        else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        guard workUnitsConsumed <= maximum, amount <= maximum - workUnitsConsumed else {
            throw AutomaticMergeWorkflowError.workLimitExceeded(maximumUnits: maximum)
        }
        workUnitsConsumed += amount
    }

    func consumePublicationWork(id: UUID, amount: UInt64, maximum: UInt64) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .authorizingPublication(let currentID, _) = state, currentID == id else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        guard workUnitsConsumed <= maximum, amount <= maximum - workUnitsConsumed else {
            throw AutomaticMergeWorkflowError.workLimitExceeded(maximumUnits: maximum)
        }
        workUnitsConsumed += amount
    }

    func remainingWork(id: UUID, maximum: UInt64) throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let matches =
            switch state {
            case .authorizingOperation(let currentID, _),
                .authorizingPublication(let currentID, _):
                currentID == id
            case .ready, .staging, .operationAuthorized, .publicationAuthorized,
                .publicationClaimed, .publicationSealed, .finished:
                false
            }
        guard matches, workUnitsConsumed <= maximum else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        return maximum - workUnitsConsumed
    }

    func authorizeOperation(id: UUID, operationIndex: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .authorizingOperation(let currentID, let currentOperation) = state,
            currentID == id,
            currentOperation == operationIndex
        else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        state = .operationAuthorized(id: id, operationIndex: operationIndex)
    }

    func completeOperation(id: UUID, operationIndex: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .operationAuthorized(let currentID, let nextOperation) = state,
            currentID == id,
            nextOperation == operationIndex
        else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        state = .staging(id: id, nextOperation: operationIndex + 1)
    }

    func beginPublication(id: UUID, operationCount: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .staging(let currentID, let nextOperation) = state,
            currentID == id,
            nextOperation == operationCount
        else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        state = .authorizingPublication(id: id, completedOperationCount: operationCount)
    }

    func authorizePublication(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .authorizingPublication(let currentID, _) = state, currentID == id else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
        state = .publicationAuthorized(id: id)
    }

    func claimPublication(
        id: UUID,
        uncertainOutcome: AutomaticMergeWorkflowExecutionOutcome
    ) -> AutomaticMergeWorkflowPublicationClaim {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .publicationAuthorized(let currentID) where currentID == id:
            let claimID = UUID()
            state = .publicationClaimed(id: id, claimID: claimID)
            return .claimed(claimID)
        case .publicationClaimed(let currentID, _) where currentID == id:
            state = .publicationSealed(id: id, outcome: uncertainOutcome)
            return .sealed(uncertainOutcome)
        case .publicationSealed(let currentID, let outcome) where currentID == id:
            return .sealed(outcome)
        default:
            state = .publicationSealed(id: id, outcome: uncertainOutcome)
            return .sealed(uncertainOutcome)
        }
    }

    func sealPublication(
        id: UUID,
        claimID: UUID,
        outcome: AutomaticMergeWorkflowExecutionOutcome,
        fallback: AutomaticMergeWorkflowExecutionOutcome
    ) -> AutomaticMergeWorkflowExecutionOutcome {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .publicationClaimed(let currentID, let currentClaimID)
        where currentID == id && currentClaimID == claimID:
            state = .publicationSealed(id: id, outcome: outcome)
            return outcome
        case .publicationSealed(let currentID, let sealedOutcome) where currentID == id:
            return sealedOutcome
        default:
            state = .publicationSealed(id: id, outcome: fallback)
            return fallback
        }
    }

    func validatesStaging(id: UUID, nextOperation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .staging(let currentID, let currentOperation) = state else {
            return false
        }
        return currentID == id && currentOperation == nextOperation
    }

    func isOperationAuthorized(id: UUID, operationIndex: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .operationAuthorized(let currentID, let currentOperation) = state else {
            return false
        }
        return currentID == id && currentOperation == operationIndex
    }

    func failBeforePublication(id: UUID, completedOperationCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let matches =
            switch state {
            case .staging(let currentID, let nextOperation):
                currentID == id && nextOperation == completedOperationCount
            case .authorizingOperation(let currentID, let operationIndex),
                .operationAuthorized(let currentID, let operationIndex):
                currentID == id && operationIndex == completedOperationCount
            case .authorizingPublication(let currentID, let operationCount):
                currentID == id && operationCount == completedOperationCount
            case .ready, .publicationAuthorized, .publicationClaimed, .publicationSealed, .finished:
                false
            }
        guard matches else {
            return false
        }
        state = .finished(id: id)
        return true
    }
}

/// Complete plan with deterministic operation order. Its only executable state transition is one
/// atomic publication after all operations are staged in private drafts.
public struct AutomaticMergeWorkflowPlan: Sendable {
    public let snapshotCAS: AutomaticMergeWorkflowSnapshotCAS
    public let source: ComparisonSnapshot
    public let comparisonRows: [DiffRow]
    public let comparisonOptions: LineDiffOptions
    public let automaticPlan: AutomaticMergePlan
    public let operations: [AutomaticMergeWorkflowPlannedOperation]
    public let conflictPolicy: AutomaticMergeWorkflowConflictPolicy
    public let disposition: AutomaticMergeWorkflowPlanDisposition
    public let publicationIntent: AutomaticMergeWorkflowPublicationIntent?
    public let receipt: AutomaticMergeWorkflowPlanningReceipt
    public let limits: AutomaticMergeWorkflowLimits
    public let executorContract: AutomaticMergeWorkflowExecutorContract
    fileprivate let executionGate = AutomaticMergeWorkflowExecutionGate()

    fileprivate init(
        snapshot: AutomaticMergeWorkflowSnapshot,
        automaticPlan: AutomaticMergePlan,
        operations: [AutomaticMergeWorkflowPlannedOperation],
        conflictPolicy: AutomaticMergeWorkflowConflictPolicy,
        disposition: AutomaticMergeWorkflowPlanDisposition,
        publicationIntent: AutomaticMergeWorkflowPublicationIntent?,
        receipt: AutomaticMergeWorkflowPlanningReceipt,
        limits: AutomaticMergeWorkflowLimits
    ) {
        snapshotCAS = AutomaticMergeWorkflowSnapshotCAS(snapshot: snapshot, limits: limits)
        source = snapshot.source
        comparisonRows = snapshot.rows
        comparisonOptions = snapshot.comparisonOptions
        self.automaticPlan = automaticPlan
        self.operations = operations
        self.conflictPolicy = conflictPolicy
        self.disposition = disposition
        self.publicationIntent = publicationIntent
        self.receipt = receipt
        self.limits = limits
        executorContract = .required
    }

    public var isExecutable: Bool {
        disposition == .executable || disposition == .executableWithConflicts
    }

    public func initialStagingProgress() throws -> AutomaticMergeWorkflowStagingProgress {
        guard isExecutable else {
            throw AutomaticMergeWorkflowError.planNotExecutable(disposition)
        }
        let executionID = try executionGate.begin(planningWorkUnits: receipt.workUnitsConsumed)
        return AutomaticMergeWorkflowStagingProgress(
            planningReceipt: receipt,
            completedOperationCount: 0,
            draft: source,
            executionID: executionID
        )
    }

    /// Reads live owner state under isolation, then computes next private draft. Private staging may
    /// be discarded freely and is not publication.
    public func authorizeNextOperation<Owner: AutomaticMergeWorkflowAtomicOwner>(
        in progress: AutomaticMergeWorkflowStagingProgress,
        owner: isolated Owner
    ) throws -> AutomaticMergeWorkflowOperationPermit {
        try validateProgress(progress, requireComplete: false)
        do {
            try executionGate.beginOperation(
                id: progress.executionID,
                operationIndex: progress.completedOperationCount
            )
            let remainingWork = try executionGate.remainingWork(
                id: progress.executionID,
                maximum: limits.maximumWorkUnits
            )
            let validationWork = try AutomaticMergeWorkflow.validate(
                owner.currentAutomaticMergeSnapshot(),
                against: snapshotCAS,
                checksCancellation: true,
                maximumWorkUnits: remainingWork
            )
            try executionGate.consumeWork(
                id: progress.executionID,
                operationIndex: progress.completedOperationCount,
                amount: validationWork,
                maximum: limits.maximumWorkUnits
            )
            try Task.checkCancellation()
            let operation = operations[progress.completedOperationCount]
            let resultingDraft = try apply(
                operation,
                to: progress.draft,
                executionID: progress.executionID
            )
            try executionGate.authorizeOperation(
                id: progress.executionID,
                operationIndex: operation.executionIndex
            )
            return AutomaticMergeWorkflowOperationPermit(
                operation: operation,
                resultingDraft: resultingDraft,
                executionID: progress.executionID
            )
        } catch is CancellationError {
            throw AutomaticMergeWorkflowError.cancelled
        }
    }

    /// Records the core-computed private draft carried by `permit`; never mutates owner state.
    public func executorAttestedStaged(
        permit: AutomaticMergeWorkflowOperationPermit
    ) throws -> AutomaticMergeWorkflowStagingProgress {
        guard
            executionGate.isOperationAuthorized(
                id: permit.executionID,
                operationIndex: permit.operation.executionIndex
            ),
            operations.indices.contains(permit.operation.executionIndex)
        else {
            throw AutomaticMergeWorkflowError.invalidExecutionProof
        }
        try executionGate.completeOperation(
            id: permit.executionID,
            operationIndex: permit.operation.executionIndex
        )
        return AutomaticMergeWorkflowStagingProgress(
            planningReceipt: receipt,
            completedOperationCount: permit.operation.executionIndex + 1,
            draft: permit.resultingDraft,
            executionID: permit.executionID
        )
    }

    /// Last cancellable core boundary. Reads live owner state under isolation and issues one-shot
    /// authorization for immediate all-or-nothing owner publication without suspension.
    public func authorizePublication<Owner: AutomaticMergeWorkflowAtomicOwner>(
        of progress: AutomaticMergeWorkflowStagingProgress,
        owner: isolated Owner
    ) throws -> AutomaticMergeWorkflowPublicationPermit {
        try validateProgress(progress, requireComplete: true)
        guard let publicationIntent else {
            throw AutomaticMergeWorkflowError.planNotExecutable(disposition)
        }
        let validationWork: UInt64
        do {
            try executionGate.beginPublication(
                id: progress.executionID,
                operationCount: operations.count
            )
            let remainingWork = try executionGate.remainingWork(
                id: progress.executionID,
                maximum: limits.maximumWorkUnits
            )
            let successorValidationWork = try AutomaticMergeWorkflow.successorValidationWork(
                snapshotCAS.snapshot,
                stagedDraft: progress.draft,
                intent: publicationIntent
            )
            guard successorValidationWork <= remainingWork else {
                throw AutomaticMergeWorkflowError.workLimitExceeded(
                    maximumUnits: limits.maximumWorkUnits
                )
            }
            let publicationValidationBudget = (remainingWork - successorValidationWork) / 2
            validationWork = try AutomaticMergeWorkflow.validate(
                owner.currentAutomaticMergeSnapshot(),
                against: snapshotCAS,
                checksCancellation: true,
                maximumWorkUnits: publicationValidationBudget
            )
            try executionGate.consumePublicationWork(
                id: progress.executionID,
                amount: try AutomaticMergeWorkflow.checkedAdd(
                    try AutomaticMergeWorkflow.checkedMultiply(validationWork, 2),
                    successorValidationWork
                ),
                maximum: limits.maximumWorkUnits
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw AutomaticMergeWorkflowError.cancelled
        }
        try executionGate.authorizePublication(id: progress.executionID)
        return AutomaticMergeWorkflowPublicationPermit(
            planningReceipt: receipt,
            intent: publicationIntent,
            stagedDraft: progress.draft,
            snapshotCAS: snapshotCAS,
            executionID: progress.executionID,
            atomicValidationMaximumWorkUnits: validationWork,
            executionGate: executionGate
        )
    }

    fileprivate func validateProgress(
        _ progress: AutomaticMergeWorkflowStagingProgress,
        requireComplete: Bool
    ) throws {
        guard isExecutable,
            executionGate.validatesStaging(
                id: progress.executionID,
                nextOperation: progress.completedOperationCount
            ),
            progress.completedOperationCount >= 0,
            progress.completedOperationCount <= operations.count,
            requireComplete
                ? progress.completedOperationCount == operations.count
                : progress.completedOperationCount < operations.count
        else {
            throw AutomaticMergeWorkflowError.invalidStagingProgress
        }
    }

    private func apply(
        _ planned: AutomaticMergeWorkflowPlannedOperation,
        to predecessor: ComparisonSnapshot,
        executionID: UUID
    ) throws -> ComparisonSnapshot {
        var current = predecessor
        for (rowIndex, rowID) in planned.rowIDs.enumerated() {
            do {
                try Task.checkCancellation()
                let remainingWork = try executionGate.remainingWork(
                    id: executionID,
                    maximum: limits.maximumWorkUnits
                )
                let preflight = try AutomaticMergeWorkflow.preflightComparison(
                    current,
                    options: comparisonOptions,
                    limits: limits,
                    maximumWorkUnits: remainingWork
                )
                let comparisonWork = try AutomaticMergeWorkflow.comparisonWork(
                    snapshot: current,
                    lineCounts: preflight.lineCounts,
                    options: comparisonOptions
                )
                try executionGate.consumeWork(
                    id: executionID,
                    operationIndex: planned.executionIndex,
                    amount: try AutomaticMergeWorkflow.checkedAdd(
                        comparisonWork,
                        preflight.workUnitsConsumed
                    ),
                    maximum: limits.maximumWorkUnits
                )
                let merged = try LineMerge.apply(
                    rowID: rowID,
                    direction: planned.operation.direction,
                    left: current.left,
                    right: current.right,
                    options: comparisonOptions
                )
                try Task.checkCancellation()
                guard let merged else {
                    throw AutomaticMergeWorkflowError.operationRejected(
                        planned.executionIndex
                    )
                }
                current = ComparisonSnapshot(left: merged.left, right: merged.right)
                guard current.left.utf8.count <= limits.maximumOutputUTF8BytesPerPane,
                    current.right.utf8.count <= limits.maximumOutputUTF8BytesPerPane
                else {
                    throw AutomaticMergeWorkflowError.outputTooLarge(
                        maximumUTF8Bytes: limits.maximumOutputUTF8BytesPerPane
                    )
                }
                let hasRemainingMerge =
                    rowIndex + 1 < planned.rowIDs.count
                    || planned.executionIndex + 1 < operations.count
                if hasRemainingMerge {
                    guard
                        current.left.utf8.count
                            <= AutomaticMergeWorkflowLimits.hardMaximumInputUTF8Bytes,
                        current.right.utf8.count
                            <= AutomaticMergeWorkflowLimits.hardMaximumInputUTF8Bytes
                    else {
                        throw AutomaticMergeWorkflowError.outputTooLarge(
                            maximumUTF8Bytes:
                                AutomaticMergeWorkflowLimits.hardMaximumInputUTF8Bytes
                        )
                    }
                }
            } catch is CancellationError {
                throw AutomaticMergeWorkflowError.cancelled
            } catch let error as LineDiffError {
                throw AutomaticMergeWorkflowError.lineDiff(error)
            }
        }
        guard current != predecessor else {
            throw AutomaticMergeWorkflowError.operationProducedNoChange(
                planned.executionIndex
            )
        }
        return current
    }
}

/// Pre-authorization failure seal. Post-authorization outcomes are sealed only inside the atomic
/// owner operation.
public enum AutomaticMergeWorkflowExecutionOutcomeFactory: Sendable {
    public static func failedBeforePublication(
        plan: AutomaticMergeWorkflowPlan,
        progress: AutomaticMergeWorkflowStagingProgress,
        reason: AutomaticMergeWorkflowFailureReason
    ) throws -> AutomaticMergeWorkflowExecutionOutcome {
        guard
            plan.executionGate.failBeforePublication(
                id: progress.executionID,
                completedOperationCount: progress.completedOperationCount
            )
        else {
            throw AutomaticMergeWorkflowError.invalidExecutionProof
        }
        return .failed(
            AutomaticMergeWorkflowFailureReceipt(
                plan: plan,
                completedStagingOperationCount: progress.completedOperationCount,
                reason: reason
            )
        )
    }

}

/// Exclusive owner of all comparison and pane state. Every plan authorization and final commit must
/// run synchronously in one actor isolation turn so snapshots cannot change after validation.
public protocol AutomaticMergeWorkflowAtomicOwner: Actor {
    func currentAutomaticMergeSnapshot() -> AutomaticMergeWorkflowSnapshot

    /// Invoke `operation.compareAndCommit(owner:_:)` in this isolation turn. Its closure performs
    /// one atomic publication including undo; live CAS read and receipt minting remain core-owned.
    func compareAndCommitAutomaticMerge(
        _ operation: AutomaticMergeWorkflowAtomicCommitOperation
    ) -> AutomaticMergeWorkflowExecutionOutcome
}

public protocol AutomaticMergeWorkflowPlanExecutor: Sendable {
    /// Executor calls plan authorization methods while `owner` is isolated, retains only
    /// core-computed private drafts, then invokes owner CAS at most once.
    func execute<Owner: AutomaticMergeWorkflowAtomicOwner>(
        _ plan: AutomaticMergeWorkflowPlan,
        owner: isolated Owner
    ) async throws -> AutomaticMergeWorkflowExecutionOutcome
}

public enum AutomaticMergeWorkflowError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(AutomaticMergeWorkflowLimit)
    case invalidCapabilities(UInt8)
    case missingCapability(AutomaticMergeWorkflowCapabilities)
    case paneNotLoaded(AutomaticMergeSide)
    case paneIdentityCollision
    case inconsistentEditability(AutomaticMergeSide)
    case comparisonSourceRevisionMismatch(AutomaticMergeSide)
    case comparisonSourceTextMismatch(AutomaticMergeSide)
    case commandPaneStateMismatch(AutomaticMergeSide)
    case commandLayoutNotTwoWay
    case commandComparisonNotCurrent(MergeCommandPolicy.ComparisonLifecycle)
    case commandDifferenceStateMismatch
    case commandDisabled(
        command: MergeCommandPolicy.Command,
        reason: MergeCommandPolicy.DisabledReason
    )
    case inputTooLarge(side: AutomaticMergeSide, maximumUTF8Bytes: Int)
    case tooManyRows(maximum: Int)
    case tooManyOperations(maximum: Int)
    case tooManyOptionItems(maximum: Int)
    case optionsTooLarge(maximumUTF8Bytes: Int)
    case retainedDataTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumUnits: UInt64)
    case comparisonWorkLimitExceeded(maximumLinePairs: UInt64)
    case comparisonRowsDoNotMatchSource
    case successorComparisonGenerationExhausted
    case successorPaneRevisionExhausted(AutomaticMergeSide)
    case staleComparisonIdentity(
        expected: AutomaticMergeWorkflowComparisonIdentity,
        actual: AutomaticMergeWorkflowComparisonIdentity
    )
    case staleComparisonGeneration(expected: UInt64, actual: UInt64)
    case stalePaneRevision(
        side: AutomaticMergeSide,
        expected: AutomaticMergeWorkflowPaneRevision,
        actual: AutomaticMergeWorkflowPaneRevision
    )
    case snapshotContentsChanged
    case planNotExecutable(AutomaticMergeWorkflowPlanDisposition)
    case planAlreadyConsumed
    case invalidStagingProgress
    case invalidExecutionProof
    case operationRejected(Int)
    case operationProducedNoChange(Int)
    case outputTooLarge(maximumUTF8Bytes: Int)
    case automaticMerge(AutomaticMergeError)
    case lineDiff(LineDiffError)
    case arithmeticOverflow

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Automatic merge workflow was cancelled."
        case .invalidLimit(let limit):
            "Invalid automatic merge workflow limit: \(limit.rawValue)."
        case .invalidCapabilities(let rawValue):
            "Automatic merge capabilities contain unsupported bits: \(rawValue)."
        case .missingCapability(let capability):
            "Automatic merge lacks required capability bits: \(capability.rawValue)."
        case .paneNotLoaded(let side):
            "Automatic merge \(Self.describe(side)) pane is not loaded."
        case .paneIdentityCollision:
            "Automatic merge panes must belong to distinct document owners."
        case .inconsistentEditability(let side):
            "Automatic merge \(Self.describe(side)) pane editability and read-only state conflict."
        case .comparisonSourceRevisionMismatch(let side):
            "Automatic merge comparison does not identify the current \(Self.describe(side)) pane revision."
        case .comparisonSourceTextMismatch(let side):
            "Automatic merge comparison source bytes do not match the \(Self.describe(side)) pane."
        case .commandPaneStateMismatch(let side):
            "Automatic merge command state does not match the \(Self.describe(side)) pane."
        case .commandLayoutNotTwoWay:
            "This automatic merge workflow requires a two-way command layout."
        case .commandComparisonNotCurrent(let lifecycle):
            "Automatic merge requires a current successful comparison, not \(lifecycle)."
        case .commandDifferenceStateMismatch:
            "Automatic merge command difference state does not match comparison rows."
        case .commandDisabled(let command, let reason):
            "Automatic merge command \(command) is disabled: \(reason)."
        case .inputTooLarge(let side, let maximum):
            "Automatic merge \(Self.describe(side)) input exceeds \(maximum) UTF-8 bytes."
        case .tooManyRows(let maximum):
            "Automatic merge workflow exceeds the \(maximum)-row limit."
        case .tooManyOperations(let maximum):
            "Automatic merge workflow exceeds the \(maximum)-operation limit."
        case .tooManyOptionItems(let maximum):
            "Automatic merge comparison exceeds the \(maximum)-option-item limit."
        case .optionsTooLarge(let maximum):
            "Automatic merge comparison options exceed \(maximum) UTF-8 bytes."
        case .retainedDataTooLarge(let maximum):
            "Automatic merge plan exceeds the \(maximum)-byte retained-data limit."
        case .workLimitExceeded(let maximum):
            "Automatic merge planning exceeds the \(maximum)-unit work limit."
        case .comparisonWorkLimitExceeded(let maximum):
            "Automatic merge comparison exceeds the \(maximum)-line-pair work envelope."
        case .comparisonRowsDoNotMatchSource:
            "Automatic merge rows do not match the exact source bytes and comparison options."
        case .successorComparisonGenerationExhausted:
            "Automatic merge cannot advance the maximum comparison generation."
        case .successorPaneRevisionExhausted(let side):
            "Automatic merge cannot advance the maximum \(Self.describe(side)) pane revision."
        case .staleComparisonIdentity:
            "Automatic merge plan belongs to another comparison."
        case .staleComparisonGeneration(let expected, let actual):
            "Automatic merge expected comparison generation \(expected), not \(actual)."
        case .stalePaneRevision(let side, let expected, let actual):
            "Automatic merge expected \(Self.describe(side)) pane revision \(expected.revision), not \(actual.revision)."
        case .snapshotContentsChanged:
            "Automatic merge owner state changed without advancing its bound revisions."
        case .planNotExecutable(let disposition):
            "Automatic merge plan is not executable: \(disposition.rawValue)."
        case .planAlreadyConsumed:
            "Automatic merge plan is single-use and has already started or finished."
        case .invalidStagingProgress:
            "Automatic merge staging progress is stale, forged, or out of order."
        case .invalidExecutionProof:
            "Automatic merge execution proof does not belong to this plan."
        case .operationRejected(let index):
            "Automatic merge primitive rejected staging operation \(index)."
        case .operationProducedNoChange(let index):
            "Automatic merge staging operation \(index) produced no destination change."
        case .outputTooLarge(let maximum):
            "Automatic merge staged output exceeds \(maximum) UTF-8 bytes per pane."
        case .automaticMerge(let error):
            error.localizedDescription
        case .lineDiff(let error):
            error.localizedDescription
        case .arithmeticOverflow:
            "Automatic merge workflow size calculation overflowed."
        }
    }

    private static func describe(_ side: AutomaticMergeSide) -> String {
        switch side {
        case .left: "left"
        case .right: "right"
        }
    }
}

public enum AutomaticMergeWorkflow: Sendable {
    public static func plan(
        _ request: AutomaticMergeWorkflowRequest
    ) throws -> AutomaticMergeWorkflowPlan {
        do {
            return try makePlan(request)
        } catch is CancellationError {
            throw AutomaticMergeWorkflowError.cancelled
        } catch let error as AutomaticMergeWorkflowError {
            throw error
        } catch let error as AutomaticMergeError {
            throw AutomaticMergeWorkflowError.automaticMerge(error)
        } catch let error as LineDiffError {
            throw AutomaticMergeWorkflowError.lineDiff(error)
        }
    }

    fileprivate static func validate(
        _ current: AutomaticMergeWorkflowSnapshot,
        against expected: AutomaticMergeWorkflowSnapshotCAS,
        checksCancellation: Bool,
        maximumWorkUnits: UInt64? = nil
    ) throws -> UInt64 {
        do {
            if checksCancellation { try Task.checkCancellation() }
            guard current.comparison.identity == expected.comparison.identity else {
                throw AutomaticMergeWorkflowError.staleComparisonIdentity(
                    expected: expected.comparison.identity,
                    actual: current.comparison.identity
                )
            }
            guard current.comparison.generation == expected.comparison.generation else {
                throw AutomaticMergeWorkflowError.staleComparisonGeneration(
                    expected: expected.comparison.generation,
                    actual: current.comparison.generation
                )
            }
            for side in [AutomaticMergeSide.left, .right] {
                let actual = current[side].revision
                let planned = expected.snapshot[side].revision
                guard actual == planned else {
                    throw AutomaticMergeWorkflowError.stalePaneRevision(
                        side: side,
                        expected: planned,
                        actual: actual
                    )
                }
            }
            var work = AutomaticMergeWorkflowWorkBudget(limits: expected.limits)
            work.maximumWorkUnits = maximumWorkUnits ?? expected.limits.maximumWorkUnits
            work.checksCancellation = checksCancellation
            guard
                try automaticMergeWorkflowSnapshotsMatch(
                    current,
                    expected.snapshot,
                    work: &work
                )
            else {
                throw AutomaticMergeWorkflowError.snapshotContentsChanged
            }
            try work.checkpoint(force: true)
            return work.consumed
        } catch is CancellationError {
            throw AutomaticMergeWorkflowError.cancelled
        }
    }

    private static func makePlan(
        _ request: AutomaticMergeWorkflowRequest
    ) throws -> AutomaticMergeWorkflowPlan {
        try Task.checkCancellation()
        try validate(request.limits)
        var work = AutomaticMergeWorkflowWorkBudget(limits: request.limits)
        let sourceLineCounts = try validate(
            request.snapshot,
            limits: request.limits,
            work: &work
        )

        let sourceRowUpperBound = try checkedAdd(
            Int(sourceLineCounts[0]),
            Int(sourceLineCounts[1])
        )
        guard sourceRowUpperBound <= request.limits.maximumRows else {
            throw AutomaticMergeWorkflowError.tooManyRows(
                maximum: request.limits.maximumRows
            )
        }
        try work.consume(
            try comparisonWork(
                snapshot: request.snapshot.source,
                lineCounts: sourceLineCounts,
                options: request.snapshot.comparisonOptions
            )
        )
        try work.checkpoint(force: true)

        let recomputedRows = try LineDiff.compare(
            left: request.snapshot.source.left,
            right: request.snapshot.source.right,
            options: request.snapshot.comparisonOptions
        )
        guard recomputedRows.count <= request.limits.maximumRows else {
            throw AutomaticMergeWorkflowError.tooManyRows(
                maximum: request.limits.maximumRows
            )
        }
        guard
            try automaticMergeWorkflowRowsMatch(
                request.snapshot.rows,
                recomputedRows,
                work: &work
            )
        else {
            throw AutomaticMergeWorkflowError.comparisonRowsDoNotMatchSource
        }

        try work.consume(UInt64(recomputedRows.count))
        try work.checkpoint(force: true)
        let mergePlan = try AutomaticMerge.plan(
            rows: recomputedRows,
            editability: AutomaticMergeEditability(
                left: request.snapshot.left.isEditable,
                right: request.snapshot.right.isEditable
            ),
            limits: AutomaticMergeLimits(
                maximumRows: request.limits.maximumRows,
                maximumRuns: request.limits.maximumRuns
            )
        )
        guard mergePlan.operations.count <= request.limits.maximumOperations else {
            throw AutomaticMergeWorkflowError.tooManyOperations(
                maximum: request.limits.maximumOperations
            )
        }
        try work.consume(UInt64(mergePlan.runs.count))
        try work.consume(UInt64(mergePlan.operations.count))
        try validateCommands(for: mergePlan, snapshot: request.snapshot, work: &work)

        let hasConflicts = mergePlan.hasConflicts
        let disposition: AutomaticMergeWorkflowPlanDisposition
        if mergePlan.operations.isEmpty {
            disposition = hasConflicts ? .blockedByConflicts : .noChanges
        } else if hasConflicts, request.snapshot.conflictPolicy == .requireConflictFree {
            disposition = .blockedByConflicts
        } else if hasConflicts {
            disposition = .executableWithConflicts
        } else {
            disposition = .executable
        }
        let isExecutable =
            disposition == .executable || disposition == .executableWithConflicts
        if isExecutable {
            let missing = AutomaticMergeWorkflowCapabilities.all.subtracting(
                request.snapshot.capabilities
            )
            guard missing.isEmpty else {
                throw AutomaticMergeWorkflowError.missingCapability(missing)
            }
            guard request.snapshot.comparison.generation < UInt64.max else {
                throw AutomaticMergeWorkflowError.successorComparisonGenerationExhausted
            }
        }

        var executionOperations: [AutomaticMergeWorkflowPlannedOperation] = []
        executionOperations.reserveCapacity(mergePlan.operations.count)
        var plannedRowCount = 0
        var changesLeft = false
        var changesRight = false
        for operation in mergePlan.operations.reversed() {
            try work.consume(1)
            var rowIDs: [DiffRow.ID] = []
            rowIDs.reserveCapacity(operation.rowRange.count)
            var rowIndex = operation.rowRange.upperBound
            while rowIndex > operation.rowRange.lowerBound {
                try work.consume(1)
                rowIndex -= 1
                rowIDs.append(recomputedRows[rowIndex].id)
                plannedRowCount = try checkedAdd(plannedRowCount, 1)
            }
            switch operation.destination {
            case .left: changesLeft = true
            case .right: changesRight = true
            }
            executionOperations.append(
                AutomaticMergeWorkflowPlannedOperation(
                    executionIndex: executionOperations.count,
                    operation: operation,
                    rowIDs: rowIDs
                )
            )
        }
        var changedSides: [AutomaticMergeSide] = []
        if changesLeft { changedSides.append(.left) }
        if changesRight { changedSides.append(.right) }
        var mutations: [AutomaticMergeWorkflowPaneMutationIntent] = []
        if isExecutable {
            mutations.reserveCapacity(changedSides.count)
            for side in changedSides {
                guard request.snapshot[side].revision.revision < UInt64.max else {
                    throw AutomaticMergeWorkflowError.successorPaneRevisionExhausted(side)
                }
                mutations.append(
                    AutomaticMergeWorkflowPaneMutationIntent(
                        side: side,
                        predecessor: request.snapshot[side].revision
                    )
                )
            }
        }
        let publicationIntent =
            isExecutable
            ? AutomaticMergeWorkflowPublicationIntent(
                mutations: mutations,
                snapshot: request.snapshot
            )
            : nil
        let retained = try retainedByteEstimate(
            snapshot: request.snapshot,
            operationCount: executionOperations.count,
            plannedRowCount: plannedRowCount,
            optionBytes: try optionByteCount(
                request.snapshot.comparisonOptions,
                work: &work
            ),
            optionItemCount: try checkedAdd(
                request.snapshot.comparisonOptions.lineFilters.count,
                request.snapshot.comparisonOptions.substitutions.count
            )
        )
        guard retained <= request.limits.maximumRetainedBytes else {
            throw AutomaticMergeWorkflowError.retainedDataTooLarge(
                maximumBytes: request.limits.maximumRetainedBytes
            )
        }
        try work.checkpoint(force: true)
        let receipt = AutomaticMergeWorkflowPlanningReceipt(
            comparison: request.snapshot.comparison,
            conflictPolicy: request.snapshot.conflictPolicy,
            disposition: disposition,
            mergePlan: mergePlan,
            estimatedRetainedBytes: retained,
            workUnitsConsumed: work.consumed
        )
        return AutomaticMergeWorkflowPlan(
            snapshot: request.snapshot,
            automaticPlan: mergePlan,
            operations: executionOperations,
            conflictPolicy: request.snapshot.conflictPolicy,
            disposition: disposition,
            publicationIntent: publicationIntent,
            receipt: receipt,
            limits: request.limits
        )
    }

    private static func validate(
        _ limits: AutomaticMergeWorkflowLimits
    ) throws {
        let integerLimits: [(AutomaticMergeWorkflowLimit, Int, Int, Bool)] = [
            (.rows, limits.maximumRows, AutomaticMergeWorkflowLimits.hardMaximumRows, true),
            (.runs, limits.maximumRuns, AutomaticMergeWorkflowLimits.hardMaximumRuns, true),
            (
                .operations,
                limits.maximumOperations,
                AutomaticMergeWorkflowLimits.hardMaximumOperations,
                true
            ),
            (
                .inputUTF8Bytes,
                limits.maximumInputUTF8BytesPerPane,
                AutomaticMergeWorkflowLimits.hardMaximumInputUTF8Bytes,
                false
            ),
            (
                .outputUTF8Bytes,
                limits.maximumOutputUTF8BytesPerPane,
                AutomaticMergeWorkflowLimits.hardMaximumOutputUTF8Bytes,
                false
            ),
            (
                .retainedBytes,
                limits.maximumRetainedBytes,
                AutomaticMergeWorkflowLimits.hardMaximumRetainedBytes,
                false
            ),
            (
                .optionItems,
                limits.maximumOptionItems,
                AutomaticMergeWorkflowLimits.hardMaximumOptionItems,
                true
            ),
            (
                .optionUTF8Bytes,
                limits.maximumOptionUTF8Bytes,
                AutomaticMergeWorkflowLimits.hardMaximumOptionUTF8Bytes,
                true
            ),
            (
                .cancellationCheckInterval,
                limits.cancellationCheckInterval,
                AutomaticMergeWorkflowLimits.hardMaximumCancellationCheckInterval,
                false
            )
        ]
        for (name, value, maximum, permitsZero) in integerLimits {
            guard value >= (permitsZero ? 0 : 1), value <= maximum else {
                throw AutomaticMergeWorkflowError.invalidLimit(name)
            }
        }
        guard limits.maximumOutputUTF8BytesPerPane >= limits.maximumInputUTF8BytesPerPane else {
            throw AutomaticMergeWorkflowError.invalidLimit(.outputUTF8Bytes)
        }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= AutomaticMergeWorkflowLimits.hardMaximumWorkUnits
        else {
            throw AutomaticMergeWorkflowError.invalidLimit(.workUnits)
        }
        guard limits.maximumComparisonLinePairs > 0,
            limits.maximumComparisonLinePairs
                <= AutomaticMergeWorkflowLimits.hardMaximumComparisonLinePairs
        else {
            throw AutomaticMergeWorkflowError.invalidLimit(.comparisonLinePairs)
        }
    }

    private static func validate(
        _ snapshot: AutomaticMergeWorkflowSnapshot,
        limits: AutomaticMergeWorkflowLimits,
        work: inout AutomaticMergeWorkflowWorkBudget
    ) throws -> [UInt64] {
        let unknownCapabilities =
            snapshot.capabilities.rawValue
            & ~AutomaticMergeWorkflowCapabilities.all.rawValue
        guard unknownCapabilities == 0 else {
            throw AutomaticMergeWorkflowError.invalidCapabilities(snapshot.capabilities.rawValue)
        }
        guard snapshot.capabilities.contains(.plan) else {
            throw AutomaticMergeWorkflowError.missingCapability(.plan)
        }
        guard snapshot.rows.count <= limits.maximumRows else {
            throw AutomaticMergeWorkflowError.tooManyRows(maximum: limits.maximumRows)
        }
        guard snapshot.left.revision.documentID != snapshot.right.revision.documentID else {
            throw AutomaticMergeWorkflowError.paneIdentityCollision
        }
        guard case .twoWay = snapshot.commandState.layout else {
            throw AutomaticMergeWorkflowError.commandLayoutNotTwoWay
        }
        guard snapshot.commandState.comparisonLifecycle == .currentSuccess else {
            throw AutomaticMergeWorkflowError.commandComparisonNotCurrent(
                snapshot.commandState.comparisonLifecycle
            )
        }

        let sides:
            [(
                AutomaticMergeSide, AutomaticMergeWorkflowPaneSnapshot, String,
                AutomaticMergeWorkflowPaneRevision
            )] = [
                (.left, snapshot.left, snapshot.source.left, snapshot.comparison.leftSource),
                (.right, snapshot.right, snapshot.source.right, snapshot.comparison.rightSource)
            ]
        var lineCounts: [UInt64] = []
        for (side, pane, sourceText, sourceRevision) in sides {
            try work.checkpoint()
            guard pane.isLoaded else { throw AutomaticMergeWorkflowError.paneNotLoaded(side) }
            guard !(pane.isEditable && pane.isReadOnly) else {
                throw AutomaticMergeWorkflowError.inconsistentEditability(side)
            }
            guard pane.revision == sourceRevision else {
                throw AutomaticMergeWorkflowError.comparisonSourceRevisionMismatch(side)
            }
            guard try automaticMergeWorkflowStringsMatch(pane.text, sourceText, work: &work) else {
                throw AutomaticMergeWorkflowError.comparisonSourceTextMismatch(side)
            }
            let byteCount = pane.text.utf8.count
            guard byteCount <= limits.maximumInputUTF8BytesPerPane else {
                throw AutomaticMergeWorkflowError.inputTooLarge(
                    side: side,
                    maximumUTF8Bytes: limits.maximumInputUTF8BytesPerPane
                )
            }
            lineCounts.append(try automaticMergeWorkflowLineCount(pane.text, work: &work))
            let commandSide = side == .left ? snapshot.commandState.left : snapshot.commandState.right
            guard commandSide == pane.commandSideState else {
                throw AutomaticMergeWorkflowError.commandPaneStateMismatch(side)
            }
        }
        let linePairs = lineCounts[0].multipliedReportingOverflow(by: lineCounts[1])
        guard !linePairs.overflow, linePairs.partialValue <= limits.maximumComparisonLinePairs else {
            throw AutomaticMergeWorkflowError.comparisonWorkLimitExceeded(
                maximumLinePairs: limits.maximumComparisonLinePairs
            )
        }
        var hasDifferences = false
        for row in snapshot.rows {
            try work.consume(1)
            if row.kind != .unchanged {
                hasDifferences = true
                break
            }
        }
        guard snapshot.commandState.hasSignificantDifferences == hasDifferences else {
            throw AutomaticMergeWorkflowError.commandDifferenceStateMismatch
        }
        try validateOptions(snapshot.comparisonOptions, limits: limits, work: &work)
        return lineCounts
    }

    private static func validateOptions(
        _ options: LineDiffOptions,
        limits: AutomaticMergeWorkflowLimits,
        work: inout AutomaticMergeWorkflowWorkBudget
    ) throws {
        let itemCount = try checkedAdd(
            options.lineFilters.count,
            options.substitutions.count
        )
        guard itemCount <= limits.maximumOptionItems else {
            throw AutomaticMergeWorkflowError.tooManyOptionItems(
                maximum: limits.maximumOptionItems
            )
        }
        var bytes = 0
        for rule in options.lineFilters {
            try work.checkpoint()
            bytes = try checkedAdd(bytes, rule.pattern.utf8.count)
        }
        for rule in options.substitutions {
            try work.checkpoint()
            bytes = try checkedAdd(bytes, rule.pattern.utf8.count)
            bytes = try checkedAdd(bytes, rule.replacement.utf8.count)
        }
        guard bytes <= limits.maximumOptionUTF8Bytes else {
            throw AutomaticMergeWorkflowError.optionsTooLarge(
                maximumUTF8Bytes: limits.maximumOptionUTF8Bytes
            )
        }
        try work.consume(UInt64(bytes))
    }

    private static func validateCommands(
        for mergePlan: AutomaticMergePlan,
        snapshot: AutomaticMergeWorkflowSnapshot,
        work: inout AutomaticMergeWorkflowWorkBudget
    ) throws {
        let states = MergeCommandPolicy.evaluate(snapshot.commandState)
        var copiesLeft = false
        var copiesRight = false
        for operation in mergePlan.operations {
            try work.consume(1)
            switch operation.direction {
            case .leftToRight: copiesRight = true
            case .rightToLeft: copiesLeft = true
            }
        }
        var commands: [MergeCommandPolicy.Command] = []
        if copiesLeft { commands.append(.copyAllToLeft) }
        if copiesRight { commands.append(.copyAllToRight) }
        for command in commands {
            if case .disabled(let reason) = states[command] {
                throw AutomaticMergeWorkflowError.commandDisabled(
                    command: command,
                    reason: reason
                )
            }
        }
    }

    private static func retainedByteEstimate(
        snapshot: AutomaticMergeWorkflowSnapshot,
        operationCount: Int,
        plannedRowCount: Int,
        optionBytes: Int,
        optionItemCount: Int
    ) throws -> Int {
        let sourceBytes = try checkedAdd(
            snapshot.source.left.utf8.count,
            snapshot.source.right.utf8.count
        )
        var result = try checkedMultiply(sourceBytes, 3)
        result = try checkedAdd(result, try checkedMultiply(snapshot.rows.count, 64))
        result = try checkedAdd(result, try checkedMultiply(operationCount, 64))
        result = try checkedAdd(result, try checkedMultiply(plannedRowCount, 32))
        result = try checkedAdd(result, optionBytes)
        result = try checkedAdd(result, try checkedMultiply(optionItemCount, 64))
        return result
    }

    private static func optionByteCount(
        _ options: LineDiffOptions,
        work: inout AutomaticMergeWorkflowWorkBudget
    ) throws -> Int {
        var bytes = 0
        for rule in options.lineFilters {
            try work.consume(1)
            bytes = try checkedAdd(bytes, rule.pattern.utf8.count)
        }
        for rule in options.substitutions {
            try work.consume(1)
            bytes = try checkedAdd(bytes, rule.pattern.utf8.count)
            bytes = try checkedAdd(bytes, rule.replacement.utf8.count)
        }
        return bytes
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw AutomaticMergeWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw AutomaticMergeWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    fileprivate static func preflightComparison(
        _ snapshot: ComparisonSnapshot,
        options: LineDiffOptions,
        limits: AutomaticMergeWorkflowLimits,
        maximumWorkUnits: UInt64
    ) throws -> (lineCounts: [UInt64], workUnitsConsumed: UInt64) {
        let sides = [
            (AutomaticMergeSide.left, snapshot.left),
            (AutomaticMergeSide.right, snapshot.right)
        ]
        var work = AutomaticMergeWorkflowWorkBudget(limits: limits)
        work.maximumWorkUnits = maximumWorkUnits
        var lineCounts: [UInt64] = []
        lineCounts.reserveCapacity(sides.count)
        for (side, text) in sides {
            guard text.utf8.count <= AutomaticMergeWorkflowLimits.hardMaximumInputUTF8Bytes else {
                throw AutomaticMergeWorkflowError.inputTooLarge(
                    side: side,
                    maximumUTF8Bytes: AutomaticMergeWorkflowLimits.hardMaximumInputUTF8Bytes
                )
            }
            lineCounts.append(try automaticMergeWorkflowLineCount(text, work: &work))
        }
        let rowUpperBound = try checkedAdd(Int(lineCounts[0]), Int(lineCounts[1]))
        guard rowUpperBound <= limits.maximumRows else {
            throw AutomaticMergeWorkflowError.tooManyRows(maximum: limits.maximumRows)
        }
        let linePairs = lineCounts[0].multipliedReportingOverflow(by: lineCounts[1])
        guard !linePairs.overflow, linePairs.partialValue <= limits.maximumComparisonLinePairs else {
            throw AutomaticMergeWorkflowError.comparisonWorkLimitExceeded(
                maximumLinePairs: limits.maximumComparisonLinePairs
            )
        }
        _ = try comparisonWork(snapshot: snapshot, lineCounts: lineCounts, options: options)
        try work.checkpoint(force: true)
        return (lineCounts, work.consumed)
    }

    fileprivate static func comparisonWork(
        snapshot: ComparisonSnapshot,
        lineCounts: [UInt64],
        options: LineDiffOptions
    ) throws -> UInt64 {
        guard lineCounts.count == 2 else {
            throw AutomaticMergeWorkflowError.arithmeticOverflow
        }
        let byteCounts = [snapshot.left.utf8.count, snapshot.right.utf8.count]
        let byteCount = UInt64(byteCounts[0]).addingReportingOverflow(UInt64(byteCounts[1]))
        guard !byteCount.overflow else {
            throw AutomaticMergeWorkflowError.arithmeticOverflow
        }
        let maximumNativeBytes = AutomaticMergeWorkflowLimits.hardMaximumInputUTF8Bytes
        let activeFilterCount = options.lineFiltersEnabled ? options.lineFilters.count : 0
        let activeSubstitutions =
            options.substitutionsEnabled
            ? options.substitutions.lazy.filter { !$0.pattern.isEmpty }
            : []
        let prefixesContent =
            options.ignoreComments && options.commentSyntax != nil
            || activeFilterCount > 0
            || !activeSubstitutions.isEmpty
        var transformWork = try checkedMultiply(
            UInt64(activeFilterCount),
            byteCount.partialValue
        )
        for index in byteCounts.indices {
            let lineCount = Int(lineCounts[index])
            let primaryBytes =
                options.ignoreLineEndings
                ? try checkedAdd(byteCounts[index], lineCount)
                : byteCounts[index]
            guard primaryBytes <= maximumNativeBytes else {
                throw AutomaticMergeWorkflowError.lineDiff(
                    .inputTooLarge(maximumBytes: maximumNativeBytes)
                )
            }
            var transformedBytes = try checkedAdd(
                byteCounts[index],
                prefixesContent ? checkedMultiply(lineCount, 64) : 0
            )
            for substitution in activeSubstitutions {
                let outputBytes = min(
                    try maximumSubstitutionOutputByteCount(
                        inputBytes: transformedBytes,
                        replacementBytes: substitution.replacement.utf8.count
                    ),
                    maximumNativeBytes
                )
                transformWork = try checkedAdd(
                    transformWork,
                    try checkedMultiply(UInt64(transformedBytes), UInt64(outputBytes))
                )
                transformedBytes = outputBytes
            }
            if prefixesContent {
                transformedBytes = try checkedAdd(
                    transformedBytes,
                    try checkedMultiply(lineCount, 2)
                )
            }
            if options.ignoreLineEndings {
                transformedBytes = try checkedAdd(transformedBytes, lineCount)
            }
            guard transformedBytes <= maximumNativeBytes else {
                throw AutomaticMergeWorkflowError.lineDiff(
                    .inputTooLarge(maximumBytes: maximumNativeBytes)
                )
            }
        }
        let linePairs = lineCounts[0].multipliedReportingOverflow(by: lineCounts[1])
        guard !linePairs.overflow else {
            throw AutomaticMergeWorkflowError.arithmeticOverflow
        }
        let comparisonMultiplier: UInt64 = comparisonTransformIsActive(options) ? 2 : 1
        let comparisonCost = linePairs.partialValue.multipliedReportingOverflow(
            by: comparisonMultiplier
        )
        guard !comparisonCost.overflow else {
            throw AutomaticMergeWorkflowError.arithmeticOverflow
        }
        return try checkedAdd(
            try checkedAdd(byteCount.partialValue, comparisonCost.partialValue),
            transformWork
        )
    }

    private static func maximumSubstitutionOutputByteCount(
        inputBytes: Int,
        replacementBytes: Int
    ) throws -> Int {
        try checkedAdd(
            inputBytes,
            checkedMultiply(try checkedAdd(inputBytes, 1), replacementBytes)
        )
    }

    fileprivate static func checkedAdd(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw AutomaticMergeWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    fileprivate static func checkedMultiply(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw AutomaticMergeWorkflowError.arithmeticOverflow }
        return result.partialValue
    }

    fileprivate static func successorValidationWork(
        _ predecessor: AutomaticMergeWorkflowSnapshot,
        stagedDraft: ComparisonSnapshot,
        intent: AutomaticMergeWorkflowPublicationIntent
    ) throws -> UInt64 {
        var result = try checkedAdd(
            UInt64(stagedDraft.left.utf8.count),
            UInt64(stagedDraft.right.utf8.count)
        )
        for side in [AutomaticMergeSide.left, .right] where intent.mutation(for: side) == nil {
            result = try checkedAdd(result, UInt64(predecessor[side].text.utf8.count))
        }
        return result
    }

    fileprivate static func successorMatches(
        predecessor: AutomaticMergeWorkflowSnapshot,
        stagedDraft: ComparisonSnapshot,
        intent: AutomaticMergeWorkflowPublicationIntent,
        successor: AutomaticMergeWorkflowPublishedSuccessor
    ) -> Bool {
        guard successor.comparison == intent.comparison.successor,
            successor.comparisonLifecycle == .stale,
            successor.registeredUndo == intent.undo
        else {
            return false
        }
        for side in [AutomaticMergeSide.left, .right] {
            let previousPane = predecessor[side]
            let published = side == .left ? successor.left : successor.right
            let expectedText = side == .left ? stagedDraft.left : stagedDraft.right
            guard published.text.utf8.elementsEqual(expectedText.utf8),
                published.isLoaded == previousPane.isLoaded,
                published.isEditable == previousPane.isEditable,
                published.isReadOnly == previousPane.isReadOnly
            else {
                return false
            }
            if let mutation = intent.mutation(for: side) {
                guard published.revision == mutation.successor,
                    published.isDirty == mutation.successorIsDirty
                else {
                    return false
                }
            } else {
                guard published.revision == previousPane.revision,
                    published.isDirty == previousPane.isDirty,
                    published.text.utf8.elementsEqual(previousPane.text.utf8)
                else {
                    return false
                }
            }
        }
        return true
    }

    private static func comparisonTransformIsActive(_ options: LineDiffOptions) -> Bool {
        options.ignoreBlankLines
            || options.ignoreComments && options.commentSyntax != nil
            || options.lineFiltersEnabled && !options.lineFilters.isEmpty
            || options.substitutionsEnabled
                && options.substitutions.contains { !$0.pattern.isEmpty }
    }
}

private struct AutomaticMergeWorkflowWorkBudget {
    let limits: AutomaticMergeWorkflowLimits
    var maximumWorkUnits: UInt64
    private(set) var consumed: UInt64 = 0
    private var sinceCancellationCheck: UInt64 = 0
    var checksCancellation = true

    init(limits: AutomaticMergeWorkflowLimits) {
        self.limits = limits
        maximumWorkUnits = limits.maximumWorkUnits
    }

    mutating func consume(_ amount: UInt64) throws {
        guard consumed <= maximumWorkUnits, amount <= maximumWorkUnits - consumed else {
            throw AutomaticMergeWorkflowError.workLimitExceeded(
                maximumUnits: maximumWorkUnits
            )
        }
        consumed += amount
        let interval = UInt64(limits.cancellationCheckInterval)
        if amount >= interval || sinceCancellationCheck >= interval - amount {
            try checkpoint(force: true)
        } else {
            sinceCancellationCheck += amount
        }
    }

    mutating func checkpoint(force: Bool = false) throws {
        guard checksCancellation else { return }
        guard force || sinceCancellationCheck >= UInt64(limits.cancellationCheckInterval) else {
            return
        }
        try Task.checkCancellation()
        sinceCancellationCheck = 0
    }
}

private func automaticMergeWorkflowSnapshotsMatch(
    _ lhs: AutomaticMergeWorkflowSnapshot,
    _ rhs: AutomaticMergeWorkflowSnapshot
) -> Bool {
    lhs.comparison == rhs.comparison
        && lhs.source == rhs.source
        && automaticMergeWorkflowRowsMatchUnbounded(lhs.rows, rhs.rows)
        && automaticMergeWorkflowOptionsMatch(lhs.comparisonOptions, rhs.comparisonOptions)
        && lhs.left == rhs.left
        && lhs.right == rhs.right
        && lhs.commandState == rhs.commandState
        && lhs.capabilities == rhs.capabilities
        && lhs.conflictPolicy == rhs.conflictPolicy
}

private func automaticMergeWorkflowSnapshotsMatch(
    _ lhs: AutomaticMergeWorkflowSnapshot,
    _ rhs: AutomaticMergeWorkflowSnapshot,
    work: inout AutomaticMergeWorkflowWorkBudget
) throws -> Bool {
    guard lhs.comparison == rhs.comparison,
        try automaticMergeWorkflowStringsMatch(lhs.source.left, rhs.source.left, work: &work),
        try automaticMergeWorkflowStringsMatch(lhs.source.right, rhs.source.right, work: &work),
        try automaticMergeWorkflowRowsMatch(lhs.rows, rhs.rows, work: &work),
        try automaticMergeWorkflowOptionsMatch(lhs.comparisonOptions, rhs.comparisonOptions, work: &work),
        lhs.left.revision == rhs.left.revision,
        try automaticMergeWorkflowStringsMatch(lhs.left.text, rhs.left.text, work: &work),
        lhs.left.isLoaded == rhs.left.isLoaded,
        lhs.left.isEditable == rhs.left.isEditable,
        lhs.left.isReadOnly == rhs.left.isReadOnly,
        lhs.left.isDirty == rhs.left.isDirty,
        lhs.right.revision == rhs.right.revision,
        try automaticMergeWorkflowStringsMatch(lhs.right.text, rhs.right.text, work: &work),
        lhs.right.isLoaded == rhs.right.isLoaded,
        lhs.right.isEditable == rhs.right.isEditable,
        lhs.right.isReadOnly == rhs.right.isReadOnly,
        lhs.right.isDirty == rhs.right.isDirty,
        lhs.commandState == rhs.commandState,
        lhs.capabilities == rhs.capabilities,
        lhs.conflictPolicy == rhs.conflictPolicy
    else {
        return false
    }
    return true
}

private func automaticMergeWorkflowRowsMatchUnbounded(
    _ lhs: [DiffRow],
    _ rhs: [DiffRow]
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for index in lhs.indices {
        guard automaticMergeWorkflowRowsMatch(lhs[index], rhs[index]) else { return false }
    }
    return true
}

private func automaticMergeWorkflowRowsMatch(
    _ lhs: [DiffRow],
    _ rhs: [DiffRow],
    work: inout AutomaticMergeWorkflowWorkBudget
) throws -> Bool {
    guard lhs.count == rhs.count else { return false }
    for index in lhs.indices {
        try work.checkpoint()
        try work.consume(1)
        let left = lhs[index]
        let right = rhs[index]
        guard left.kind == right.kind,
            left.hasEqualSourceRecords == right.hasEqualSourceRecords,
            try automaticMergeWorkflowLinesMatch(left.left, right.left, work: &work),
            try automaticMergeWorkflowLinesMatch(left.right, right.right, work: &work)
        else {
            return false
        }
    }
    return true
}

private func automaticMergeWorkflowRowsMatch(_ lhs: DiffRow, _ rhs: DiffRow) -> Bool {
    lhs.kind == rhs.kind
        && lhs.hasEqualSourceRecords == rhs.hasEqualSourceRecords
        && automaticMergeWorkflowLinesMatchUnbounded(lhs.left, rhs.left)
        && automaticMergeWorkflowLinesMatchUnbounded(lhs.right, rhs.right)
}

private func automaticMergeWorkflowLinesMatchUnbounded(
    _ lhs: DiffLine?,
    _ rhs: DiffLine?
) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (.some(let lhs), .some(let rhs)):
        return lhs.number == rhs.number && lhs.text.utf8.elementsEqual(rhs.text.utf8)
    default:
        return false
    }
}

private func automaticMergeWorkflowLinesMatch(
    _ lhs: DiffLine?,
    _ rhs: DiffLine?,
    work: inout AutomaticMergeWorkflowWorkBudget
) throws -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (.some(let lhs), .some(let rhs)):
        guard lhs.number == rhs.number else { return false }
        return try automaticMergeWorkflowStringsMatch(lhs.text, rhs.text, work: &work)
    default:
        return false
    }
}

private func automaticMergeWorkflowStringsMatch(
    _ lhs: String,
    _ rhs: String,
    work: inout AutomaticMergeWorkflowWorkBudget
) throws -> Bool {
    var left = lhs.utf8.makeIterator()
    var right = rhs.utf8.makeIterator()
    var pending: UInt64 = 0
    while true {
        let leftByte = left.next()
        let rightByte = right.next()
        pending += 1
        if pending == 64 * 1_024 {
            try work.consume(pending)
            pending = 0
        }
        guard leftByte == rightByte else {
            try work.consume(pending)
            return false
        }
        guard leftByte != nil else {
            try work.consume(pending)
            return true
        }
    }
}

private func automaticMergeWorkflowLineCount(
    _ text: String,
    work: inout AutomaticMergeWorkflowWorkBudget
) throws -> UInt64 {
    if text.isEmpty { return 0 }
    var count: UInt64 = 0
    var pending: UInt64 = 0
    var previousWasCR = false
    var endedWithTerminator = false
    for byte in text.utf8 {
        pending += 1
        if pending == 64 * 1_024 {
            try work.consume(pending)
            pending = 0
        }
        if byte == 0x0A {
            if !previousWasCR { count += 1 }
            endedWithTerminator = true
        } else if byte == 0x0D {
            count += 1
            endedWithTerminator = true
        } else {
            endedWithTerminator = false
        }
        previousWasCR = byte == 0x0D
    }
    try work.consume(pending)
    return count + (endedWithTerminator ? 0 : 1)
}

private func automaticMergeWorkflowOptionsMatch(
    _ lhs: LineDiffOptions,
    _ rhs: LineDiffOptions
) -> Bool {
    guard lhs.algorithm == rhs.algorithm,
        lhs.whitespace == rhs.whitespace,
        lhs.ignoreCase == rhs.ignoreCase,
        lhs.ignoreNumbers == rhs.ignoreNumbers,
        lhs.ignoreBlankLines == rhs.ignoreBlankLines,
        lhs.ignoreComments == rhs.ignoreComments,
        lhs.ignoreLineEndings == rhs.ignoreLineEndings,
        lhs.indentHeuristic == rhs.indentHeuristic,
        lhs.detectMovedBlocks == rhs.detectMovedBlocks,
        lhs.lineFiltersEnabled == rhs.lineFiltersEnabled,
        lhs.substitutionsEnabled == rhs.substitutionsEnabled,
        lhs.commentSyntax == rhs.commentSyntax,
        lhs.lineFilters.count == rhs.lineFilters.count,
        lhs.substitutions.count == rhs.substitutions.count
    else {
        return false
    }
    for index in lhs.lineFilters.indices {
        guard lhs.lineFilters[index].caseSensitive == rhs.lineFilters[index].caseSensitive,
            lhs.lineFilters[index].pattern.utf8.elementsEqual(
                rhs.lineFilters[index].pattern.utf8
            )
        else {
            return false
        }
    }
    for index in lhs.substitutions.indices {
        guard lhs.substitutions[index].caseSensitive == rhs.substitutions[index].caseSensitive,
            lhs.substitutions[index].pattern.utf8.elementsEqual(
                rhs.substitutions[index].pattern.utf8
            ),
            lhs.substitutions[index].replacement.utf8.elementsEqual(
                rhs.substitutions[index].replacement.utf8
            )
        else {
            return false
        }
    }
    return true
}

private func automaticMergeWorkflowOptionsMatch(
    _ lhs: LineDiffOptions,
    _ rhs: LineDiffOptions,
    work: inout AutomaticMergeWorkflowWorkBudget
) throws -> Bool {
    guard lhs.algorithm == rhs.algorithm,
        lhs.whitespace == rhs.whitespace,
        lhs.ignoreCase == rhs.ignoreCase,
        lhs.ignoreNumbers == rhs.ignoreNumbers,
        lhs.ignoreBlankLines == rhs.ignoreBlankLines,
        lhs.ignoreComments == rhs.ignoreComments,
        lhs.ignoreLineEndings == rhs.ignoreLineEndings,
        lhs.indentHeuristic == rhs.indentHeuristic,
        lhs.detectMovedBlocks == rhs.detectMovedBlocks,
        lhs.lineFiltersEnabled == rhs.lineFiltersEnabled,
        lhs.substitutionsEnabled == rhs.substitutionsEnabled,
        lhs.commentSyntax == rhs.commentSyntax,
        lhs.lineFilters.count == rhs.lineFilters.count,
        lhs.substitutions.count == rhs.substitutions.count
    else {
        return false
    }
    for index in lhs.lineFilters.indices {
        try work.checkpoint()
        guard lhs.lineFilters[index].caseSensitive == rhs.lineFilters[index].caseSensitive,
            try automaticMergeWorkflowStringsMatch(
                lhs.lineFilters[index].pattern,
                rhs.lineFilters[index].pattern,
                work: &work
            )
        else {
            return false
        }
    }
    for index in lhs.substitutions.indices {
        try work.checkpoint()
        guard lhs.substitutions[index].caseSensitive == rhs.substitutions[index].caseSensitive,
            try automaticMergeWorkflowStringsMatch(
                lhs.substitutions[index].pattern,
                rhs.substitutions[index].pattern,
                work: &work
            ),
            try automaticMergeWorkflowStringsMatch(
                lhs.substitutions[index].replacement,
                rhs.substitutions[index].replacement,
                work: &work
            )
        else {
            return false
        }
    }
    return true
}
