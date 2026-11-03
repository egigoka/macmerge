import Foundation
import MacMergeCore
import XCTest

final class MultiDifferenceMergeExecutorTests: XCTestCase {
    private typealias Workflow = MultiDifferenceMergeWorkflow
    private typealias Capabilities = MultiDifferenceMergeExecutorCapabilities
    private typealias Owner = MultiDifferenceMergeExecutorTestOwner
    private typealias Executor = MultiDifferenceMergeExecutor<Owner>

    func testCapabilitiesCoverBothRemainAndAdvanceEffects() throws {
        let snapshot = try makeSnapshot()
        let remain = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let advance = try Workflow.plan(
            intent: commandIntent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )

        XCTAssertEqual(remain.requiredEffects.count, 2)
        XCTAssertEqual(advance.requiredEffects.count, 3)
        XCTAssertTrue(Capabilities.all.covers(remain.requiredEffects))
        XCTAssertTrue(Capabilities.all.covers(advance.requiredEffects))

        let remainOnly: Capabilities = [.commitOwnerTransaction, .publishSuccessorComparison]
        XCTAssertTrue(remainOnly.covers(remain.requiredEffects))
        XCTAssertFalse(remainOnly.covers(advance.requiredEffects))
        XCTAssertFalse(Capabilities(rawValue: 0).covers(remain.requiredEffects))
    }

    func testMissingCapabilityFailsBeforeFirstEffect() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(
            intent: commandIntent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = Owner(live: snapshot)
        let executor = Executor(
            owner: owner,
            capabilities: [.commitOwnerTransaction, .publishSuccessorComparison]
        )

        let outcome = await executor.execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .contractUnsupported)
        XCTAssertEqual(failure.failedEffect, .commitOwnerTransaction)
        XCTAssertEqual(failure.completedEffects, [])
        XCTAssertNil(failure.commitReceipt)

        let state = await owner.state()
        XCTAssertEqual(state.commitRequests, 0)
        XCTAssertEqual(state.compareRequests, 0)
        XCTAssertEqual(state.publishComparisonCalls, 0)
    }

    func testRemainCompletesBothDirectionsWithBoundGroups() async throws {
        for direction in [MergeDirection.leftToRight, MergeDirection.rightToLeft] {
            let snapshot = try makeSnapshot()
            let plan = try Workflow.plan(intent: commandIntent(direction, .remain), in: snapshot)
            XCTAssertEqual(plan.primitiveInvocation.selection, snapshot.selectionBinding)

            let owner = Owner(live: snapshot)
            let outcome = await Executor(owner: owner).execute(plan)
            guard case .completed(let receipt) = outcome else {
                XCTFail("Expected completed execution for \(direction)")
                return
            }
            XCTAssertEqual(receipt.planningReceipt, plan.receipt)
            XCTAssertEqual(receipt.commitReceipt.planReference, plan.reference)
            XCTAssertEqual(receipt.commitReceipt.transaction.selection, snapshot.selectionBinding)
            XCTAssertEqual(
                receipt.commitReceipt.transaction.selection.differenceGroups.count,
                snapshot.selection.differenceRuns.count
            )
            XCTAssertEqual(receipt.publicationReceipts.count, 1)
            XCTAssertEqual(receipt.completedEffects, plan.requiredEffects)

            let state = await owner.state()
            XCTAssertEqual(state.source, plan.transaction.successor)
            XCTAssertEqual(state.sourceReference, plan.transaction.successorSource)
            XCTAssertEqual(state.commitRequests, 1)
            XCTAssertEqual(state.publishComparisonCalls, 1)
            XCTAssertEqual(state.publishNavigationCalls, 0)
        }
    }

    func testAdvanceCompletesBothDirectionsWithNavigation() async throws {
        for direction in [MergeDirection.leftToRight, MergeDirection.rightToLeft] {
            let snapshot = try makeSnapshot()
            let plan = try Workflow.plan(
                intent: commandIntent(direction, .advanceToNextDifference),
                in: snapshot
            )
            let owner = Owner(live: snapshot)
            let outcome = await Executor(owner: owner).execute(plan)
            guard case .completed(let receipt) = outcome else {
                XCTFail("Expected completed execution for \(direction)")
                return
            }
            XCTAssertEqual(receipt.publicationReceipts.count, 2)
            XCTAssertEqual(receipt.completedEffects, plan.requiredEffects)
            XCTAssertEqual(receipt.publicationReceipts[1].effect, plan.requiredEffects[2])
            guard case .navigation(let evidence) = receipt.publicationReceipts[1].evidence else {
                XCTFail("Expected navigation evidence for \(direction)")
                return
            }
            XCTAssertEqual(evidence.publishedTarget, plan.transaction.successorNavigationTarget)
            XCTAssertEqual(evidence.publishedComparison, plan.transaction.successorComparison.reference)

            let state = await owner.state()
            XCTAssertEqual(state.publishComparisonCalls, 1)
            XCTAssertEqual(state.publishNavigationCalls, 1)
        }
    }

    func testStaleSnapshotFailsWithoutCommit() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let stale = try makeSnapshot()
        let owner = Owner(live: stale)

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .staleSnapshot)
        XCTAssertEqual(failure.failedEffect, .commitOwnerTransaction)
        XCTAssertEqual(failure.completedEffects, [])
        XCTAssertNil(failure.commitReceipt)

        let state = await owner.state()
        XCTAssertEqual(state.commitRequests, 0)
        XCTAssertEqual(state.compareRequests, 0)
    }

    func testPreCancelledTaskFailsWithoutCommit() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(live: snapshot)
        let executor = Executor(owner: owner)

        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return await executor.execute(plan)
        }
        let outcome = await task.value
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .cancelled)
        XCTAssertEqual(failure.completedEffects, [])

        let state = await owner.state()
        XCTAssertEqual(state.commitRequests, 0)
    }

    func testCommitCancellationFailsAsCancelled() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(live: snapshot, behavior: Owner.Behavior(commitCancellation: true))

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .cancelled)
        XCTAssertEqual(failure.failedEffect, .commitOwnerTransaction)
        XCTAssertNil(failure.commitReceipt)

        let state = await owner.state()
        XCTAssertEqual(state.commitRequests, 1)
    }

    func testOwnerRejectedMatchingTransactionFailsAsRejected() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(live: snapshot, behavior: Owner.Behavior(rejectMatchingTransaction: true))

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .rejected)
        XCTAssertEqual(failure.failedEffect, .commitOwnerTransaction)
        XCTAssertNil(failure.commitReceipt)
    }

    func testCommitUncertaintyBecomesUncertainWithUnknownState() async throws {
        for behavior in [
            Owner.Behavior(commitUncertainOutcome: true),
            Owner.Behavior(commitUnknownThrow: true)
        ] {
            let snapshot = try makeSnapshot()
            let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
            let owner = Owner(live: snapshot, behavior: behavior)

            let outcome = await Executor(owner: owner).execute(plan)
            guard case .uncertain(let receipt) = outcome else {
                XCTFail("Expected uncertain execution")
                return
            }
            XCTAssertEqual(receipt.reason, .commitStateUnknown)
            XCTAssertEqual(receipt.completedEffects, [])
            XCTAssertEqual(receipt.uncertainEffects, [.commitOwnerTransaction])
            XCTAssertNil(receipt.commitReceipt)
        }
    }

    func testSuccessorPublicationFailureKeepsCommittedPrefix() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(live: snapshot, behavior: Owner.Behavior(publishComparisonFailure: true))

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .successorComparisonPublicationFailed)
        XCTAssertEqual(failure.failedEffect, plan.requiredEffects[1])
        XCTAssertEqual(failure.completedEffects, [.commitOwnerTransaction])
        XCTAssertEqual(failure.publicationReceipts, [])
        XCTAssertEqual(failure.commitReceipt?.planReference, plan.reference)
    }

    func testNavigationPublicationFailureKeepsCommittedPrefix() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(
            intent: commandIntent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = Owner(live: snapshot, behavior: Owner.Behavior(publishNavigationFailure: true))

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .navigationPublicationFailed)
        XCTAssertEqual(failure.failedEffect, plan.requiredEffects[2])
        XCTAssertEqual(failure.completedEffects, Array(plan.requiredEffects.prefix(2)))
        XCTAssertEqual(failure.publicationReceipts.count, 1)
        XCTAssertEqual(failure.commitReceipt?.planReference, plan.reference)
    }

    func testCorruptComparisonEvidenceBecomesPublicationUnknown() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(live: snapshot, behavior: Owner.Behavior(corruptComparisonEvidence: true))

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .uncertain(let receipt) = outcome else {
            XCTFail("Expected uncertain execution")
            return
        }
        XCTAssertEqual(receipt.reason, .publicationStateUnknown)
        XCTAssertEqual(receipt.completedEffects, [.commitOwnerTransaction])
        XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[1]])
        XCTAssertEqual(receipt.publicationReceipts, [])
        XCTAssertEqual(receipt.commitReceipt?.planReference, plan.reference)
    }

    func testCorruptNavigationEvidenceBecomesPublicationUnknown() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(
            intent: commandIntent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = Owner(live: snapshot, behavior: Owner.Behavior(corruptNavigationEvidence: true))

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .uncertain(let receipt) = outcome else {
            XCTFail("Expected uncertain execution")
            return
        }
        XCTAssertEqual(receipt.reason, .publicationStateUnknown)
        XCTAssertEqual(receipt.completedEffects, Array(plan.requiredEffects.prefix(2)))
        XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[2]])
        XCTAssertEqual(receipt.publicationReceipts.count, 1)
    }

    func testCancellationDuringPublicationBecomesUncertain() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(
            live: snapshot,
            behavior: Owner.Behavior(publishComparisonCancellation: true)
        )

        let outcome = await Executor(owner: owner).execute(plan)
        guard case .uncertain(let receipt) = outcome else {
            XCTFail("Expected uncertain execution")
            return
        }
        XCTAssertEqual(receipt.reason, .cancellationObservedAfterEffectBegan)
        XCTAssertEqual(receipt.completedEffects, [.commitOwnerTransaction])
        XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[1]])
        XCTAssertEqual(receipt.commitReceipt?.planReference, plan.reference)
    }

    func testMalformedEffectsFailsAsContractUnsupported() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        XCTAssertEqual(plan.requiredEffects.count, 2)
        let owner = Owner(live: snapshot)
        let executor = Executor(owner: owner, capabilities: Capabilities(rawValue: 0))
        let outcome = await executor.execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .contractUnsupported)
        XCTAssertEqual(failure.failedEffect, .commitOwnerTransaction)
        XCTAssertEqual(failure.completedEffects, [])
        XCTAssertNil(failure.commitReceipt)
        let state = await owner.state()
        XCTAssertEqual(state.commitRequests, 0)
        XCTAssertEqual(state.compareRequests, 0)
    }

    func testConcurrentMutationRaceFailsAsStaleSnapshot() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(live: snapshot, behavior: Owner.Behavior(raceMutateBeforeCommit: true))
        let outcome = await Executor(owner: owner).execute(plan)
        guard case .failed(let failure) = outcome else {
            XCTFail("Expected failed execution")
            return
        }
        XCTAssertEqual(failure.reason, .staleSnapshot)
        XCTAssertEqual(failure.failedEffect, .commitOwnerTransaction)
        XCTAssertEqual(failure.completedEffects, [])
        XCTAssertNil(failure.commitReceipt)
        let state = await owner.state()
        XCTAssertEqual(state.commitRequests, 1)
        XCTAssertEqual(state.compareRequests, 1)
    }

    func testSecondExecuteOfSamePlanFailsWithoutSecondMutation() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: commandIntent(.leftToRight, .remain), in: snapshot)
        let owner = Owner(live: snapshot)
        let executor = Executor(owner: owner)
        let first = await executor.execute(plan)
        guard case .completed = first else {
            XCTFail("Expected completed first execution")
            return
        }
        let second = await executor.execute(plan)
        guard case .failed(let failure) = second else {
            XCTFail("Expected failed second execution")
            return
        }
        XCTAssertEqual(failure.reason, .staleSnapshot)
        XCTAssertEqual(failure.failedEffect, .commitOwnerTransaction)
        XCTAssertEqual(failure.completedEffects, [])
        XCTAssertNil(failure.commitReceipt)
        let state = await owner.state()
        XCTAssertEqual(state.commitRequests, 1)
        XCTAssertEqual(state.compareRequests, 1)
        XCTAssertEqual(state.source, plan.transaction.successor)
    }

    func testNavigationCancellationAfterCommitBecomesUncertain() async throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(
            intent: commandIntent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = Owner(
            live: snapshot,
            behavior: Owner.Behavior(cancelTaskAfterComparisonPublication: true)
        )
        let executor = Executor(owner: owner)
        let task = Task.detached { await executor.execute(plan) }
        let outcome = await task.value
        guard case .uncertain(let receipt) = outcome else {
            XCTFail("Expected uncertain execution")
            return
        }
        XCTAssertEqual(receipt.reason, .cancellationObservedAfterEffectBegan)
        XCTAssertEqual(receipt.completedEffects, Array(plan.requiredEffects.prefix(2)))
        XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[2]])
        XCTAssertEqual(receipt.commitReceipt?.planReference, plan.reference)
        XCTAssertEqual(receipt.publicationReceipts.count, 1)
    }

    private func commandIntent(
        _ direction: MergeDirection,
        _ advance: MultiDifferenceMergeWorkflowAdvanceIntent
    ) -> MultiDifferenceMergeWorkflowCommandIntent {
        MultiDifferenceMergeWorkflowCommandIntent(direction: direction, advance: advance)
    }

    private func makeSnapshot() throws -> MultiDifferenceMergeWorkflowSnapshot {
        let source = ComparisonSnapshot(
            left: joinedLines(
                "same-0", "left-a", "left-extra", "same-1", "left-b", "same-2",
                "left-c", "same-3", "next", "tail"
            ),
            right: joinedLines(
                "same-0", "right-a", "same-1", "right-b", "same-2", "right-c",
                "same-3", "next", "tail"
            )
        )
        let options = LineDiffOptions(
            algorithm: .minimal,
            ignoreLineEndings: false,
            lineFilters: [LineFilterRule(pattern: "DO-NOT-MATCH")],
            substitutions: [SubstitutionRule(pattern: "NEVER", replacement: "MATCH")]
        )
        let rows = try LineDiff.compare(left: source.left, right: source.right, options: options)
        let selection = try MultiDifferenceSelection(rows: rows, rowRange: 2..<7)
        return MultiDifferenceMergeWorkflowSnapshot(
            comparisonIdentity: MultiDifferenceMergeWorkflowComparisonIdentity(),
            comparisonRevision: 40,
            sourceIdentity: MultiDifferenceMergeWorkflowSourceIdentity(),
            sourceRevision: 50,
            leftPaneRevision: MultiDifferenceMergeWorkflowPaneRevision(
                identity: MultiDifferenceMergeWorkflowPaneIdentity(),
                revision: 60
            ),
            rightPaneRevision: MultiDifferenceMergeWorkflowPaneRevision(
                identity: MultiDifferenceMergeWorkflowPaneIdentity(),
                revision: 70
            ),
            selectionIdentity: MultiDifferenceMergeWorkflowSelectionIdentity(),
            selectionRevision: 80,
            source: source,
            comparisonRows: rows,
            comparisonOptions: options,
            selection: selection,
            left: MergeCommandPolicy.SideState(isLoaded: true, isEditable: true, isDirty: false),
            right: MergeCommandPolicy.SideState(isLoaded: true, isEditable: true, isDirty: false),
            comparisonLifecycle: .currentSuccess
        )
    }

    private func joinedLines(_ values: String...) -> String {
        values.joined(separator: "\n")
    }
}

private actor MultiDifferenceMergeExecutorTestOwner: MultiDifferenceMergeExecutorOwner {
    struct Behavior: Sendable {
        var commitCancellation = false
        var commitUnknownThrow = false
        var commitUncertainOutcome = false
        var rejectMatchingTransaction = false
        var raceMutateBeforeCommit = false
        var cancelTaskAfterComparisonPublication = false
        var publishComparisonCancellation = false
        var publishComparisonFailure = false
        var corruptComparisonEvidence = false
        var publishNavigationCancellation = false
        var publishNavigationFailure = false
        var corruptNavigationEvidence = false
    }

    struct State: Sendable {
        var commitRequests = 0
        var compareRequests = 0
        var publishComparisonCalls = 0
        var publishNavigationCalls = 0
        var source: ComparisonSnapshot
        var sourceReference: MultiDifferenceMergeWorkflowSourceReference
    }

    enum StubError: Error, Sendable {
        case boom
    }

    private var current: MultiDifferenceMergeWorkflowSnapshot
    private var source: ComparisonSnapshot
    private var sourceReference: MultiDifferenceMergeWorkflowSourceReference
    private var leftState: MergeCommandPolicy.SideState
    private var rightState: MergeCommandPolicy.SideState
    private var undoPredecessors: [ComparisonSnapshot] = []
    private var selectionIntent: MultiDifferenceMergeWorkflowSuccessorSelectionIntent?
    private var invalidatedComparison: MultiDifferenceMergeWorkflowComparisonReference?
    private var consumedTransactions: [MultiDifferenceMergeWorkflowTransactionIdentity] = []
    private var commitRequests = 0
    private var compareRequests = 0
    private var publishComparisonCalls = 0
    private var publishNavigationCalls = 0
    private let behavior: Behavior

    init(live: MultiDifferenceMergeWorkflowSnapshot, behavior: Behavior = Behavior()) {
        current = live
        source = live.source
        sourceReference = live.sourceReference
        leftState = live.left
        rightState = live.right
        self.behavior = behavior
    }

    func currentMultiDifferenceMergeSnapshot() -> MultiDifferenceMergeWorkflowSnapshot {
        current
    }

    func commitMultiDifferenceMergePlan(
        _ plan: MultiDifferenceMergeWorkflowPlan
    ) throws -> MultiDifferenceMergeWorkflowCommitReceipt {
        commitRequests += 1
        if behavior.raceMutateBeforeCommit {
            current = MultiDifferenceMergeWorkflowSnapshot(
                comparisonIdentity: current.comparisonReference.identity,
                comparisonRevision: current.comparisonReference.revision,
                sourceIdentity: current.sourceReference.identity,
                sourceRevision: current.sourceReference.revision,
                leftPaneRevision: current.sourceReference.left,
                rightPaneRevision: current.sourceReference.right,
                selectionIdentity: current.selectionReference.identity,
                selectionRevision: current.selectionReference.revision,
                source: current.source,
                comparisonRows: current.comparisonRows,
                comparisonOptions: current.comparisonOptions,
                selection: current.selection,
                left: current.left,
                right: current.right,
                comparisonLifecycle: .stale
            )
        }
        if behavior.commitCancellation {
            throw CancellationError()
        }
        if behavior.commitUnknownThrow {
            throw StubError.boom
        }
        return try plan.commit(to: self)
    }

    func publishMultiDifferenceMergeSuccessorComparison(
        _ intent: MultiDifferenceMergeWorkflowSuccessorComparisonPublicationIntent
    ) throws -> MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence {
        publishComparisonCalls += 1
        if behavior.cancelTaskAfterComparisonPublication {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        if behavior.publishComparisonCancellation {
            throw CancellationError()
        }
        if behavior.publishComparisonFailure {
            throw StubError.boom
        }
        if behavior.corruptComparisonEvidence {
            return MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence(
                comparedSource: intent.expectedSource,
                comparedSourceContents: ComparisonSnapshot(left: "corrupt", right: "corrupt"),
                comparedInvalidatedComparison: intent.expectedInvalidatedComparison,
                comparedComparisonOptions: intent.expectedComparisonOptions,
                comparedComparisonOptionsGeneration: intent.expectedComparisonOptionsGeneration,
                publishedComparison: intent.successor
            )
        }
        return MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence(
            comparedSource: intent.expectedSource,
            comparedSourceContents: intent.expectedSourceContents,
            comparedInvalidatedComparison: intent.expectedInvalidatedComparison,
            comparedComparisonOptions: intent.expectedComparisonOptions,
            comparedComparisonOptionsGeneration: intent.expectedComparisonOptionsGeneration,
            publishedComparison: intent.successor
        )
    }

    func publishMultiDifferenceMergeNavigation(
        _ intent: MultiDifferenceMergeWorkflowNavigationIntent
    ) throws -> MultiDifferenceMergeWorkflowNavigationPublicationEvidence {
        publishNavigationCalls += 1
        if behavior.publishNavigationCancellation {
            throw CancellationError()
        }
        if behavior.publishNavigationFailure {
            throw StubError.boom
        }
        switch intent {
        case .none:
            throw StubError.boom
        case .publishResolvedNextDifference(let comparison, let target, _):
            if behavior.corruptNavigationEvidence {
                return MultiDifferenceMergeWorkflowNavigationPublicationEvidence(
                    intent: .none,
                    publishedComparison: comparison,
                    publishedTarget: target
                )
            }
            return MultiDifferenceMergeWorkflowNavigationPublicationEvidence(
                intent: intent,
                publishedComparison: comparison,
                publishedTarget: target
            )
        }
    }

    func compareAndCommit(
        _ transaction: MultiDifferenceMergeWorkflowTransaction
    ) -> MultiDifferenceMergeWorkflowAtomicCommitOutcome {
        compareRequests += 1
        if behavior.commitUncertainOutcome {
            return .commitUncertain
        }
        let matches =
            current == transaction.expectedState
            && sourceReference == transaction.expectedSource
            && sourceReference[transaction.destination] == transaction.expectedDestinationRevision
            && !consumedTransactions.contains(transaction.id)
        guard matches, !behavior.rejectMatchingTransaction else {
            return .notCommitted(currentSnapshot: current)
        }

        let comparedState = current
        source = transaction.successor
        sourceReference = transaction.successorSource
        switch transaction.destination {
        case .left:
            leftState = transaction.successorDestinationState
        case .right:
            rightState = transaction.successorDestinationState
        }
        undoPredecessors.append(transaction.predecessor)
        selectionIntent = transaction.successorSelectionIntent
        invalidatedComparison = transaction.expectedState.comparisonReference
        consumedTransactions.append(transaction.id)

        current = MultiDifferenceMergeWorkflowSnapshot(
            comparisonIdentity: transaction.expectedState.comparisonReference.identity,
            comparisonRevision: transaction.expectedState.comparisonReference.revision,
            sourceIdentity: transaction.successorSource.identity,
            sourceRevision: transaction.successorSource.revision,
            leftPaneRevision: transaction.successorSource.left,
            rightPaneRevision: transaction.successorSource.right,
            selectionIdentity: transaction.expectedState.selectionReference.identity,
            selectionRevision: transaction.expectedState.selectionReference.revision,
            source: transaction.successor,
            comparisonRows: transaction.expectedState.comparisonRows,
            comparisonOptions: transaction.expectedState.comparisonOptions,
            selection: transaction.expectedState.selection,
            left: leftState,
            right: rightState,
            comparisonLifecycle: .stale
        )

        let evidence = MultiDifferenceMergeWorkflowOwnerCommitEvidence(
            transactionID: transaction.id,
            comparedExpectedState: comparedState,
            comparedDestinationRevision: transaction.expectedDestinationRevision,
            successorSource: transaction.successorSource,
            successorDestinationRevision: transaction.successorDestinationRevision,
            committedSuccessor: transaction.successor,
            destinationState: transaction.successorDestinationState,
            recordedUndoPredecessor: transaction.predecessor,
            committedSelectionIntent: transaction.successorSelectionIntent,
            invalidatedComparison: transaction.expectedState.comparisonReference
        )
        return .committed(evidence)
    }

    func state() -> State {
        State(
            commitRequests: commitRequests,
            compareRequests: compareRequests,
            publishComparisonCalls: publishComparisonCalls,
            publishNavigationCalls: publishNavigationCalls,
            source: source,
            sourceReference: sourceReference
        )
    }
}
