import Foundation

/// Mutation executor binding `MultiDifferenceMergeWorkflowPlan` to atomic publication.
///
/// A plan already binds the expanded difference groups, validated source/comparison/
/// selection identities, direction, and copy-and-advance intent: the executor never
/// reinterprets groups, reorders effects, or forges selection state. It enforces
/// `MultiDifferenceMergeWorkflowExecutorContract.required` by validating exact snapshot
/// state plus every effect capability before the first effect, committing through the
/// owner's atomic compare-and-swap, then publishing the successor comparison and
/// optional advance navigation in plan order. Both directions and both advance intents
/// flow through the same effect loop: remain plans publish two effects, copy-and-advance
/// plans publish three. The executor performs no editor work, command routing, text
/// mutation, or UI work; all mutation stays inside owner isolation.
public struct MultiDifferenceMergeExecutorCapabilities: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Atomic owner transaction commit (`commitOwnerTransaction`).
    public static let commitOwnerTransaction = Self(rawValue: 1 << 0)
    /// Atomic successor source/comparison/options publication (`publishSuccessorComparison`).
    public static let publishSuccessorComparison = Self(rawValue: 1 << 1)
    /// Advance navigation publication (`publishNavigation`).
    public static let publishNavigation = Self(rawValue: 1 << 2)

    /// Every effect the workflow can plan.
    public static let all: Self = [
        .commitOwnerTransaction, .publishSuccessorComparison, .publishNavigation
    ]

    /// Returns true when every effect in `effects` has a matching capability.
    public func covers(_ effects: [MultiDifferenceMergeWorkflowRequiredEffect]) -> Bool {
        effects.allSatisfy { effect in
            switch effect {
            case .commitOwnerTransaction:
                contains(.commitOwnerTransaction)
            case .publishSuccessorComparison:
                contains(.publishSuccessorComparison)
            case .publishNavigation:
                contains(.publishNavigation)
            }
        }
    }
}

/// Owner-side mutation surface for `MultiDifferenceMergeExecutor`.
///
/// `commitMultiDifferenceMergePlan` must run `plan.commit(to:)` in one isolation turn
/// (typically `try plan.commit(to: self)`); publication methods must compare their exact
/// intent expectations and either publish atomically and return evidence, or throw
/// without mutating. Throw `CancellationError` (or
/// `MultiDifferenceMergeWorkflowError.cancelled`) only when cancellation prevented
/// publication; any other throw reports a known non-commit, which the executor records
/// as a failed effect without hiding the committed prefix.
public protocol MultiDifferenceMergeExecutorOwner: MultiDifferenceMergeWorkflowAtomicCommitOwner {
    /// Live snapshot for pre-commit exact stale validation. Non-throwing by design:
    /// staleness is reported by the executor comparing against the plan.
    func currentMultiDifferenceMergeSnapshot() -> MultiDifferenceMergeWorkflowSnapshot

    /// One atomic owner transaction. Must call `plan.commit(to:)` without suspension.
    func commitMultiDifferenceMergePlan(
        _ plan: MultiDifferenceMergeWorkflowPlan
    ) throws -> MultiDifferenceMergeWorkflowCommitReceipt

    /// Atomically publishes the successor comparison or throws without mutating.
    func publishMultiDifferenceMergeSuccessorComparison(
        _ intent: MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent
    ) throws -> MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence

    /// Publishes advance navigation after the successor comparison, or throws without mutating.
    func publishMultiDifferenceMergeNavigation(
        _ intent: MultiDifferenceMergeWorkflowNavigationIntent
    ) throws -> MultiDifferenceMergeWorkflowNavigationPublicationEvidence
}

/// Source-only mutation executor. Conforms to `MultiDifferenceMergeWorkflowPlanExecutor`.
public struct MultiDifferenceMergeExecutor<Owner: MultiDifferenceMergeExecutorOwner>:
    MultiDifferenceMergeWorkflowPlanExecutor, Sendable
{
    public let owner: Owner
    public let capabilities: MultiDifferenceMergeExecutorCapabilities
    public let executorContract = MultiDifferenceMergeWorkflowExecutorContract.required

    public init(owner: Owner, capabilities: MultiDifferenceMergeExecutorCapabilities = .all) {
        self.owner = owner
        self.capabilities = capabilities
    }

    public func execute(
        _ plan: MultiDifferenceMergeWorkflowPlan
    ) async -> MultiDifferenceMergeWorkflowExecutionOutcome {
        if Task.isCancelled {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .cancelled)
        }
        guard Self.isSupportedShape(plan.requiredEffects) else {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .contractUnsupported)
        }
        guard capabilities.covers(plan.requiredEffects) else {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .contractUnsupported)
        }
        let current = await owner.currentMultiDifferenceMergeSnapshot()
        do {
            try plan.validateCurrentSnapshot(current)
        } catch is CancellationError {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .cancelled)
        } catch let error as MultiDifferenceMergeWorkflowError where error == .cancelled {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .cancelled)
        } catch {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .staleSnapshot)
        }
        if Task.isCancelled {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .cancelled)
        }
        let commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt
        do {
            commitReceipt = try await owner.commitMultiDifferenceMergePlan(plan)
        } catch is CancellationError {
            return sealedFailed(plan: plan, completedEffectCount: 0, reason: .cancelled)
        } catch let error as MultiDifferenceMergeWorkflowError {
            switch error {
            case .cancelled:
                return sealedFailed(plan: plan, completedEffectCount: 0, reason: .cancelled)
            case .commitUncertain:
                return sealedUncertain(
                    plan: plan,
                    completedEffectCount: 0,
                    uncertainEffectIndices: [0],
                    reason: .commitStateUnknown
                )
            case .ownerRejectedMatchingTransaction:
                return sealedFailed(plan: plan, completedEffectCount: 0, reason: .rejected)
            case .staleComparisonIdentity, .staleComparisonRevision, .staleSourceIdentity,
                .staleSourceRevision, .stalePaneIdentity, .stalePaneRevision,
                .staleSelectionIdentity, .staleSelectionRevision, .sourceContentsChanged,
                .comparisonRowsChanged, .comparisonOptionsChanged, .selectionChanged,
                .sideStateChanged, .comparisonLifecycleChanged:
                return sealedFailed(plan: plan, completedEffectCount: 0, reason: .staleSnapshot)
            default:
                return sealedUncertain(
                    plan: plan,
                    completedEffectCount: 0,
                    uncertainEffectIndices: [0],
                    reason: .commitStateUnknown
                )
            }
        } catch {
            return sealedUncertain(
                plan: plan,
                completedEffectCount: 0,
                uncertainEffectIndices: [0],
                reason: .commitStateUnknown
            )
        }
        var publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt] = []
        for effectIndex in 1..<plan.requiredEffects.count {
            if Task.isCancelled {
                return sealedUncertain(
                    plan: plan,
                    completedEffectCount: effectIndex,
                    uncertainEffectIndices: [effectIndex],
                    commitReceipt: commitReceipt,
                    publicationReceipts: publicationReceipts,
                    reason: .cancellationObservedAfterEffectBegan
                )
            }
            switch plan.requiredEffects[effectIndex] {
            case .commitOwnerTransaction:
                preconditionFailure(
                    "MultiDifferenceMergeExecutor encountered commitOwnerTransaction after plan shape validation"
                )
            case .publishSuccessorComparison(let intent):
                let evidence: MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence
                do {
                    evidence = try await owner.publishMultiDifferenceMergeSuccessorComparison(intent)
                } catch is CancellationError {
                    return sealedUncertain(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        uncertainEffectIndices: [effectIndex],
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .cancellationObservedAfterEffectBegan
                    )
                } catch let error as MultiDifferenceMergeWorkflowError where error == .cancelled {
                    return sealedUncertain(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        uncertainEffectIndices: [effectIndex],
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .cancellationObservedAfterEffectBegan
                    )
                } catch {
                    return sealedFailed(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .successorComparisonPublicationFailed
                    )
                }
                do {
                    publicationReceipts.append(
                        try MultiDifferenceMergeWorkflowPublicationReceipt
                            .executorAttestedSuccessorComparisonPublished(
                                plan: plan,
                                commitReceipt: commitReceipt,
                                evidence: evidence
                            )
                    )
                } catch {
                    return sealedUncertain(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        uncertainEffectIndices: [effectIndex],
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .publicationStateUnknown
                    )
                }
            case .publishNavigation(let intent):
                guard let comparisonReceipt = publicationReceipts.first else {
                    preconditionFailure(
                        "MultiDifferenceMergeExecutor encountered publishNavigation before publishSuccessorComparison"
                    )
                }
                let evidence: MultiDifferenceMergeWorkflowNavigationPublicationEvidence
                do {
                    evidence = try await owner.publishMultiDifferenceMergeNavigation(intent)
                } catch is CancellationError {
                    return sealedUncertain(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        uncertainEffectIndices: [effectIndex],
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .cancellationObservedAfterEffectBegan
                    )
                } catch let error as MultiDifferenceMergeWorkflowError where error == .cancelled {
                    return sealedUncertain(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        uncertainEffectIndices: [effectIndex],
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .cancellationObservedAfterEffectBegan
                    )
                } catch {
                    return sealedFailed(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .navigationPublicationFailed
                    )
                }
                do {
                    publicationReceipts.append(
                        try MultiDifferenceMergeWorkflowPublicationReceipt
                            .executorAttestedNavigationPublished(
                                plan: plan,
                                after: comparisonReceipt,
                                evidence: evidence
                            )
                    )
                } catch {
                    return sealedUncertain(
                        plan: plan,
                        completedEffectCount: effectIndex,
                        uncertainEffectIndices: [effectIndex],
                        commitReceipt: commitReceipt,
                        publicationReceipts: publicationReceipts,
                        reason: .publicationStateUnknown
                    )
                }
            }
        }
        do {
            return try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.completed(
                plan: plan,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts
            )
        } catch {
            preconditionFailure(
                "MultiDifferenceMergeExecutor misbound completed receipts: \(error)"
            )
        }
    }

    /// Core-built shapes only: commit, then successor comparison, then optional navigation.
    private static func isSupportedShape(
        _ effects: [MultiDifferenceMergeWorkflowRequiredEffect]
    ) -> Bool {
        guard case .commitOwnerTransaction? = effects.first else { return false }
        let tail = Array(effects.dropFirst())
        guard tail.count == 1 || tail.count == 2 else { return false }
        guard case .publishSuccessorComparison = tail[0] else { return false }
        if tail.count == 2 {
            guard case .publishNavigation = tail[1] else { return false }
        }
        return true
    }

    private func sealedFailed(
        plan: MultiDifferenceMergeWorkflowPlan,
        completedEffectCount: Int,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt? = nil,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt] = [],
        reason: MultiDifferenceMergeWorkflowExecutionFailureReason
    ) -> MultiDifferenceMergeWorkflowExecutionOutcome {
        do {
            return try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.failed(
                plan: plan,
                completedEffectCount: completedEffectCount,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts,
                reason: reason
            )
        } catch {
            preconditionFailure(
                "MultiDifferenceMergeExecutor misbound failure outcome: \(error)"
            )
        }
    }

    private func sealedUncertain(
        plan: MultiDifferenceMergeWorkflowPlan,
        completedEffectCount: Int,
        uncertainEffectIndices: [Int],
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt? = nil,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt] = [],
        reason: MultiDifferenceMergeWorkflowExecutionUncertaintyReason
    ) -> MultiDifferenceMergeWorkflowExecutionOutcome {
        do {
            return try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.uncertain(
                plan: plan,
                completedEffectCount: completedEffectCount,
                uncertainEffectIndices: uncertainEffectIndices,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts,
                reason: reason
            )
        } catch {
            preconditionFailure(
                "MultiDifferenceMergeExecutor misbound uncertainty outcome: \(error)"
            )
        }
    }
}
