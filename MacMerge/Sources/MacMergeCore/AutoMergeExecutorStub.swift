import Foundation

/// UI-independent automatic-merge executor stub.
///
/// Drives an already-planned `AutomaticMergeWorkflowPlan` through phased execution while holding
/// exact owner isolation: initial staging, one `authorizeNextOperation` plus `executorAttestedStaged`
/// per operation in plan order, one `authorizePublication`, then one owner-controlled
/// `compareAndCommitAutomaticMerge`. Staging order and end-to-start row application stay core-computed;
/// the executor retains only core-issued private drafts and never derives row identities itself.
/// Editable-state policy and exact comparison/pane/command/capability CAS are revalidated by the core
/// before every stage and publication. The publication permit authorizes one atomic owner commit of all
/// pane drafts, revisions, dirty flags, undo registration, and comparison invalidation; copied permits
/// share one revocation gate, and rejection stays distinct from uncertainty. Work, byte, row, run,
/// operation, and retained limits are core-enforced, cancellation is honored before each stage and
/// publication, and the handoff after publication authorization performs no suspension. All receipts
/// stay core-minted: planning, success, pre-publication failure (which proves publication was never
/// attempted), rejection (known no-commit), and uncertainty (may-have-committed).
/// The executor performs no command routing, editor mutation, UI, filesystem, pasteboard, network,
/// or process work. Command, editor, and app executor adoption remain missing; a future owner layer
/// supplies `AutomaticMergeWorkflowAtomicOwner` and enforces
/// `AutomaticMergeWorkflowExecutorContract.required`.
public struct AutomaticMergeWorkflowStubExecutor: AutomaticMergeWorkflowPlanExecutor {
    public init() {}

    public func execute<Owner: AutomaticMergeWorkflowAtomicOwner>(
        _ plan: AutomaticMergeWorkflowPlan,
        owner: isolated Owner
    ) async throws -> AutomaticMergeWorkflowExecutionOutcome {
        var progress = try plan.initialStagingProgress()
        for _ in plan.operations {
            if Task.isCancelled {
                return try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
                    plan: plan,
                    progress: progress,
                    reason: .cancelled
                )
            }
            do {
                let permit = try plan.authorizeNextOperation(in: progress, owner: owner)
                progress = try plan.executorAttestedStaged(permit: permit)
            } catch {
                return try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
                    plan: plan,
                    progress: progress,
                    reason: Self.failureReason(for: error)
                )
            }
        }
        if Task.isCancelled {
            return try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
                plan: plan,
                progress: progress,
                reason: .cancelled
            )
        }
        do {
            let permit = try plan.authorizePublication(of: progress, owner: owner)
            return owner.compareAndCommitAutomaticMerge(permit.atomicCommitOperation)
        } catch {
            return try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
                plan: plan,
                progress: progress,
                reason: Self.failureReason(for: error)
            )
        }
    }

    private static func failureReason(for error: Error) -> AutomaticMergeWorkflowFailureReason {
        if error is CancellationError {
            return .cancelled
        }
        guard let workflowError = error as? AutomaticMergeWorkflowError else {
            return .stagingFailed
        }
        switch workflowError {
        case .cancelled:
            return .cancelled
        case .staleComparisonIdentity, .staleComparisonGeneration, .stalePaneRevision,
            .snapshotContentsChanged:
            return .staleSnapshot
        case .commandDisabled:
            return .commandDisabled
        case .missingCapability, .invalidCapabilities:
            return .capabilityUnavailable
        case .operationRejected:
            return .operationRejected
        case .planNotExecutable, .planAlreadyConsumed, .invalidStagingProgress,
            .invalidExecutionProof:
            return .contractUnsupported
        default:
            return .stagingFailed
        }
    }
}
