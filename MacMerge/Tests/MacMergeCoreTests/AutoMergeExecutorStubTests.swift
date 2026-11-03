import Foundation
import MacMergeCore
import XCTest

final class AutoMergeExecutorStubTests: XCTestCase {
    func testStubStagesOperationsInPlanOrderAndCommitsOnce() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        XCTAssertEqual(plan.operations.count, 2)
        XCTAssertEqual(plan.operations.map(\.executionIndex), [0, 1])
        let intent = try XCTUnwrap(plan.publicationIntent)
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)

        let outcome = try await owner.runStub(plan)
        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed outcome, got \(outcome)")
        }

        let merged = stubLines("top", "left-1", "left-2", "shared", "right-1", "right-2", "tail")
        let state = await owner.state()
        let successor = try XCTUnwrap(state.publishedSuccessor)
        XCTAssertEqual(successor.left.text, merged)
        XCTAssertEqual(successor.right.text, merged)
        XCTAssertEqual(state.snapshotReads, plan.operations.count + 2)
        XCTAssertEqual(state.publicationBodies, 1)
        XCTAssertEqual(state.atomicPublications, 1)
        XCTAssertEqual(state.undoRegistrations, 1)
        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        XCTAssertEqual(receipt.predecessor, fixture.snapshot.comparison)
        XCTAssertEqual(receipt.successor, intent.comparison.successor)
        XCTAssertEqual(receipt.paneMutations, intent.paneMutations)
        XCTAssertEqual(receipt.undo, intent.undo)
    }

    func testStubFailsBeforePublicationOnStaleSnapshot() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        await owner.replaceSnapshot(
            stubReplacing(
                fixture.snapshot,
                left: stubReplacingPane(fixture.snapshot.left, text: fixture.snapshot.left.text + "!")
            )
        )

        let outcome = try await owner.runStub(plan)
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected pre-publication failure, got \(outcome)")
        }
        XCTAssertEqual(receipt.reason, .staleSnapshot)
        XCTAssertEqual(receipt.completedStagingOperationCount, 0)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.publicationBodies, 0)
        XCTAssertEqual(state.atomicPublications, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testStubReportsOwnerRejectionAsKnownNoCommit() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot, decision: .rejected)

        let outcome = try await owner.runStub(plan)
        guard case .publicationRejected(let receipt) = outcome else {
            return XCTFail("Expected owner rejection, got \(outcome)")
        }
        XCTAssertFalse(receipt.atomicPublicationCommitted)
        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        let state = await owner.state()
        XCTAssertEqual(state.publicationBodies, 1)
        XCTAssertEqual(state.atomicPublications, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testStubReportsOwnerUncertaintyAsMayHaveCommitted() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot, decision: .uncertain)

        let outcome = try await owner.runStub(plan)
        guard case .publicationUncertain(let receipt) = outcome else {
            return XCTFail("Expected uncertainty, got \(outcome)")
        }
        XCTAssertTrue(receipt.atomicPublicationMayHaveCommitted)
        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        XCTAssertEqual(receipt.publicationIntent, try XCTUnwrap(plan.publicationIntent))
    }

    func testStubReportsMismatchedSuccessorAsUncertainty() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot, decision: .invalidSuccessor)

        let outcome = try await owner.runStub(plan)
        guard case .publicationUncertain(let receipt) = outcome else {
            return XCTFail("Expected uncertainty for mismatched successor, got \(outcome)")
        }
        XCTAssertTrue(receipt.atomicPublicationMayHaveCommitted)
        let state = await owner.state()
        XCTAssertEqual(state.publicationBodies, 1)
    }

    func testStubMapsStagingCancellationToCancelledFailure() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        await owner.cancelOnFirstSnapshotRead()

        let outcome = try await Task { try await owner.runStub(plan) }.value
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected cancellation failure, got \(outcome)")
        }
        XCTAssertEqual(receipt.reason, .cancelled)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublications, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testStubIgnoresCancellationAfterPublicationAuthorization() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot, decision: .cancelDuringCommit)

        let outcome = try await Task { try await owner.runStub(plan) }.value
        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected non-cancellable committed outcome, got \(outcome)")
        }
        XCTAssertEqual(receipt.successor, plan.publicationIntent?.comparison.successor)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublications, 1)
        XCTAssertEqual(state.undoRegistrations, 1)
    }

    func testStubMapsStagingOverflowToStagingFailed() async throws {
        let fixture = try makeStubFixture()
        let merged = stubLines("top", "left-1", "left-2", "shared", "right-1", "right-2", "tail")
        let sourceBytes = max(
            fixture.snapshot.source.left.utf8.count,
            fixture.snapshot.source.right.utf8.count
        )
        let plan = try AutomaticMergeWorkflow.plan(
            .init(
                snapshot: fixture.snapshot,
                limits: AutomaticMergeWorkflowLimits(
                    maximumInputUTF8BytesPerPane: sourceBytes,
                    maximumOutputUTF8BytesPerPane: merged.utf8.count - 1
                )
            )
        )
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)

        let outcome = try await owner.runStub(plan)
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected staging failure, got \(outcome)")
        }
        XCTAssertEqual(receipt.reason, .stagingFailed)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublications, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testStubSurfacesContractViolationsAsThrows() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        guard case .completed = try await owner.runStub(plan) else {
            return XCTFail("Expected first execution to complete")
        }
        do {
            _ = try await owner.runStub(plan)
            XCTFail("Expected planAlreadyConsumed on plan reuse")
        } catch let error as AutomaticMergeWorkflowError {
            XCTAssertEqual(error, .planAlreadyConsumed)
        }

        let blocked = try makeStubFixture(left: "left-modified", right: "right-modified")
        let blockedPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: blocked.snapshot))
        XCTAssertEqual(blockedPlan.disposition, .blockedByConflicts)
        let blockedOwner = StubExecutorTestOwner(snapshot: blocked.snapshot)
        do {
            _ = try await blockedOwner.runStub(blockedPlan)
            XCTFail("Expected planNotExecutable for blocked plan")
        } catch let error as AutomaticMergeWorkflowError {
            XCTAssertEqual(error, .planNotExecutable(blockedPlan.disposition))
        }
    }

    func testStubAuthorizesOperationsInPlanOrder() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        var progress = try plan.initialStagingProgress()
        for _ in plan.operations {
            let permit = try await owner.authorizeNext(plan, progress: progress)
            progress = try plan.executorAttestedStaged(permit: permit)
        }
        let indices = await owner.authorizedIndices()
        XCTAssertEqual(indices, [0, 1])
        XCTAssertEqual(progress.completedOperationCount, 2)
    }

    func testStubFailsMidStagingOnStaleText() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        let stale = stubReplacing(
            fixture.snapshot,
            left: stubReplacingPane(fixture.snapshot.left, text: fixture.snapshot.left.text + "!")
        )
        await owner.replaceSnapshotAfterReads(stale, after: 2)
        let outcome = try await owner.runStub(plan)
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected mid-staging stale failure, got \(outcome)")
        }
        XCTAssertEqual(receipt.reason, .staleSnapshot)
        XCTAssertEqual(receipt.completedStagingOperationCount, 1)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublications, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testStubFailsMidStagingOnIdentityGenerationAndRevisionStaleness() async throws {
        let fixture = try makeStubFixture()
        let otherIdentity = AutomaticMergeWorkflowComparisonReference(
            identity: AutomaticMergeWorkflowComparisonIdentity(rawValue: stubFixedUUID(99)),
            generation: fixture.snapshot.comparison.generation,
            leftSource: fixture.snapshot.comparison.leftSource,
            rightSource: fixture.snapshot.comparison.rightSource
        )
        let nextGeneration = AutomaticMergeWorkflowComparisonReference(
            identity: fixture.snapshot.comparison.identity,
            generation: fixture.snapshot.comparison.generation + 1,
            leftSource: fixture.snapshot.comparison.leftSource,
            rightSource: fixture.snapshot.comparison.rightSource
        )
        let nextLeft = AutomaticMergeWorkflowPaneRevision(
            documentID: fixture.snapshot.left.revision.documentID,
            revision: fixture.snapshot.left.revision.revision + 1
        )
        let nextRight = AutomaticMergeWorkflowPaneRevision(
            documentID: fixture.snapshot.right.revision.documentID,
            revision: fixture.snapshot.right.revision.revision + 1
        )
        let variants: [AutomaticMergeWorkflowSnapshot] = [
            stubReplacing(fixture.snapshot, comparison: otherIdentity),
            stubReplacing(fixture.snapshot, comparison: nextGeneration),
            stubReplacing(fixture.snapshot, left: stubReplacingPane(fixture.snapshot.left, revision: nextLeft)),
            stubReplacing(fixture.snapshot, right: stubReplacingPane(fixture.snapshot.right, revision: nextRight))
        ]
        XCTAssertEqual(variants.count, 4)
        for stale in variants {
            let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
            let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
            await owner.replaceSnapshotAfterReads(stale, after: 2)
            let outcome = try await owner.runStub(plan)
            guard case .failed(let receipt) = outcome else {
                return XCTFail("Expected mid-staging stale failure, got \(outcome)")
            }
            XCTAssertEqual(receipt.reason, .staleSnapshot)
            XCTAssertEqual(receipt.completedStagingOperationCount, 1)
            XCTAssertFalse(receipt.publicationAttempted)
        }
    }

    func testStubCancelsOnLastReadBeforePublication() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        await owner.cancelOnSnapshotRead(plan.operations.count + 1)
        let outcome = try await Task { try await owner.runStub(plan) }.value
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected cancellation failure, got \(outcome)")
        }
        XCTAssertEqual(receipt.reason, .cancelled)
        XCTAssertEqual(receipt.completedStagingOperationCount, plan.operations.count)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublications, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testStubMapsOperationRejectedToKnownFailure() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let progress = try plan.initialStagingProgress()
        let outcome = try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
            plan: plan,
            progress: progress,
            reason: .operationRejected
        )
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected operationRejected failure")
        }
        XCTAssertEqual(receipt.reason, .operationRejected)
        XCTAssertEqual(receipt.completedStagingOperationCount, 0)
        XCTAssertFalse(receipt.publicationAttempted)
        XCTAssertEqual(
            AutomaticMergeWorkflowError.operationRejected(0),
            AutomaticMergeWorkflowError.operationRejected(0)
        )
    }

    func testStubMapsCommandDisabledToKnownFailure() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let progress = try plan.initialStagingProgress()
        let outcome = try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
            plan: plan,
            progress: progress,
            reason: .commandDisabled
        )
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected commandDisabled failure")
        }
        XCTAssertEqual(receipt.reason, .commandDisabled)
        XCTAssertEqual(receipt.completedStagingOperationCount, 0)
        XCTAssertFalse(receipt.publicationAttempted)
        XCTAssertEqual(
            AutomaticMergeWorkflowError.commandDisabled(command: .copyAllToRight, reason: .noSignificantDifferences),
            AutomaticMergeWorkflowError.commandDisabled(command: .copyAllToRight, reason: .noSignificantDifferences)
        )
    }

    func testStubMapsCapabilityUnavailableToKnownFailure() async throws {
        let fixture = try makeStubFixture()
        let stripped = stubReplacing(fixture.snapshot, capabilities: [.plan])
        XCTAssertThrowsError(try AutomaticMergeWorkflow.plan(.init(snapshot: stripped))) { error in
            XCTAssertEqual(
                error as? AutomaticMergeWorkflowError,
                .missingCapability(AutomaticMergeWorkflowCapabilities.all.subtracting(.plan))
            )
        }
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let progress = try plan.initialStagingProgress()
        let outcome = try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
            plan: plan,
            progress: progress,
            reason: .capabilityUnavailable
        )
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected capabilityUnavailable failure")
        }
        XCTAssertEqual(receipt.reason, .capabilityUnavailable)
        XCTAssertEqual(receipt.completedStagingOperationCount, 0)
        XCTAssertFalse(receipt.publicationAttempted)
    }

    func testStubMapsWorkLimitExceededToStagingFailed() async throws {
        let fixture = try makeStubFixture()
        let baseline = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let plan = try AutomaticMergeWorkflow.plan(
            .init(
                snapshot: fixture.snapshot,
                limits: AutomaticMergeWorkflowLimits(maximumWorkUnits: baseline.receipt.workUnitsConsumed)
            )
        )
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        let outcome = try await owner.runStub(plan)
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected staging failure, got \(outcome)")
        }
        XCTAssertEqual(receipt.reason, .stagingFailed)
        XCTAssertEqual(receipt.completedStagingOperationCount, 0)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublications, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testStubMapsContractUnsupportedToKnownFailure() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        guard case .completed = try await owner.runStub(plan) else {
            return XCTFail("Expected completion")
        }
        do {
            _ = try await owner.runStub(plan)
            XCTFail("Expected planAlreadyConsumed")
        } catch let error as AutomaticMergeWorkflowError {
            XCTAssertEqual(error, .planAlreadyConsumed)
        }
        let fresh = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let progress = try fresh.initialStagingProgress()
        let outcome = try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
            plan: fresh,
            progress: progress,
            reason: .contractUnsupported
        )
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected contractUnsupported failure")
        }
        XCTAssertEqual(receipt.reason, .contractUnsupported)
        XCTAssertFalse(receipt.publicationAttempted)
    }

    func testStubCopiedPermitReplaysSealedOutcome() async throws {
        let fixture = try makeStubFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = StubExecutorTestOwner(snapshot: fixture.snapshot)
        var progress = try plan.initialStagingProgress()
        for _ in plan.operations {
            let permit = try await owner.authorizeNext(plan, progress: progress)
            progress = try plan.executorAttestedStaged(permit: permit)
        }
        let permit = try await owner.authorizePublication(plan, progress: progress)
        let copied = permit
        let first = await owner.commit(permit.atomicCommitOperation)
        let second = await owner.commit(copied.atomicCommitOperation)
        XCTAssertEqual(second, first)
        guard case .completed = first else {
            return XCTFail("Expected completed outcome")
        }
        let state = await owner.state()
        XCTAssertEqual(state.publicationBodies, 1)
        XCTAssertEqual(state.atomicPublications, 1)
        XCTAssertEqual(state.snapshotReads, plan.operations.count + 2)
    }
}

private actor StubExecutorTestOwner: AutomaticMergeWorkflowAtomicOwner {
    enum Decision: Sendable {
        case committed
        case rejected
        case uncertain
        case invalidSuccessor
        case cancelDuringCommit
    }

    struct State: Sendable {
        let publishedSuccessor: AutomaticMergeWorkflowPublishedSuccessor?
        let snapshotReads: Int
        let publicationBodies: Int
        let atomicPublications: Int
        let undoRegistrations: Int
    }

    private var current: AutomaticMergeWorkflowSnapshot
    private let decision: Decision
    private var cancelOnReadNumber: Int?
    private var replacementAfterReads: (Int, AutomaticMergeWorkflowSnapshot)?
    private var authorizedExecutionIndices: [Int] = []
    private var publishedSuccessor: AutomaticMergeWorkflowPublishedSuccessor?
    private var snapshotReads = 0
    private var publicationBodies = 0
    private var atomicPublications = 0
    private var undoRegistrations = 0

    init(snapshot: AutomaticMergeWorkflowSnapshot, decision: Decision = .committed) {
        current = snapshot
        self.decision = decision
    }

    func currentAutomaticMergeSnapshot() -> AutomaticMergeWorkflowSnapshot {
        snapshotReads += 1
        if let cancel = cancelOnReadNumber, snapshotReads == cancel {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        if let replacement = replacementAfterReads, snapshotReads >= replacement.0 {
            return replacement.1
        }
        return current
    }

    func compareAndCommitAutomaticMerge(
        _ operation: AutomaticMergeWorkflowAtomicCommitOperation
    ) -> AutomaticMergeWorkflowExecutionOutcome {
        operation.compareAndCommit(owner: self) { owner, intent, draft in
            owner.publicationBodies += 1
            switch owner.decision {
            case .committed:
                let successor = owner.makeSuccessor(intent: intent, draft: draft)
                owner.publish(successor)
                return .committed(successor)
            case .cancelDuringCommit:
                withUnsafeCurrentTask { $0?.cancel() }
                let successor = owner.makeSuccessor(intent: intent, draft: draft)
                owner.publish(successor)
                return .committed(successor)
            case .rejected:
                return .rejected
            case .uncertain:
                return .uncertain
            case .invalidSuccessor:
                let valid = owner.makeSuccessor(intent: intent, draft: draft)
                let invalid = AutomaticMergeWorkflowPublishedSuccessor(
                    left: valid.left,
                    right: valid.right,
                    comparison: valid.comparison,
                    comparisonLifecycle: .currentSuccess,
                    registeredUndo: valid.registeredUndo
                )
                owner.publishedSuccessor = invalid
                owner.atomicPublications += 1
                owner.undoRegistrations += 1
                return .committed(invalid)
            }
        }
    }

    func runStub(
        _ plan: AutomaticMergeWorkflowPlan
    ) async throws -> AutomaticMergeWorkflowExecutionOutcome {
        try await AutomaticMergeWorkflowStubExecutor().execute(plan, owner: self)
    }

    func authorizeNext(
        _ plan: AutomaticMergeWorkflowPlan,
        progress: AutomaticMergeWorkflowStagingProgress
    ) throws -> AutomaticMergeWorkflowOperationPermit {
        let permit = try plan.authorizeNextOperation(in: progress, owner: self)
        authorizedExecutionIndices.append(permit.operation.executionIndex)
        return permit
    }

    func authorizePublication(
        _ plan: AutomaticMergeWorkflowPlan,
        progress: AutomaticMergeWorkflowStagingProgress
    ) throws -> AutomaticMergeWorkflowPublicationPermit {
        try plan.authorizePublication(of: progress, owner: self)
    }

    func commit(
        _ operation: AutomaticMergeWorkflowAtomicCommitOperation
    ) -> AutomaticMergeWorkflowExecutionOutcome {
        compareAndCommitAutomaticMerge(operation)
    }

    func replaceSnapshot(_ snapshot: AutomaticMergeWorkflowSnapshot) {
        current = snapshot
    }

    func replaceSnapshotAfterReads(_ snapshot: AutomaticMergeWorkflowSnapshot, after: Int) {
        replacementAfterReads = (after, snapshot)
    }

    func cancelOnFirstSnapshotRead() {
        cancelOnReadNumber = 1
    }

    func cancelOnSnapshotRead(_ number: Int) {
        cancelOnReadNumber = number
    }

    func authorizedIndices() -> [Int] {
        authorizedExecutionIndices
    }

    func state() -> State {
        State(
            publishedSuccessor: publishedSuccessor,
            snapshotReads: snapshotReads,
            publicationBodies: publicationBodies,
            atomicPublications: atomicPublications,
            undoRegistrations: undoRegistrations
        )
    }

    private func makeSuccessor(
        intent: AutomaticMergeWorkflowPublicationIntent,
        draft: ComparisonSnapshot
    ) -> AutomaticMergeWorkflowPublishedSuccessor {
        AutomaticMergeWorkflowPublishedSuccessor(
            left: successorPane(side: .left, intent: intent, draft: draft),
            right: successorPane(side: .right, intent: intent, draft: draft),
            comparison: intent.comparison.successor,
            comparisonLifecycle: intent.comparison.lifecycle,
            registeredUndo: intent.undo
        )
    }

    private func successorPane(
        side: AutomaticMergeSide,
        intent: AutomaticMergeWorkflowPublicationIntent,
        draft: ComparisonSnapshot
    ) -> AutomaticMergeWorkflowPaneSnapshot {
        let predecessor = current[side]
        let text = side == .left ? draft.left : draft.right
        guard let mutation = intent.mutation(for: side) else { return predecessor }
        return AutomaticMergeWorkflowPaneSnapshot(
            revision: mutation.successor,
            text: text,
            isLoaded: predecessor.isLoaded,
            isEditable: predecessor.isEditable,
            isReadOnly: predecessor.isReadOnly,
            isDirty: mutation.successorIsDirty
        )
    }

    private func publish(_ successor: AutomaticMergeWorkflowPublishedSuccessor) {
        publishedSuccessor = successor
        atomicPublications += 1
        undoRegistrations += 1
        current = AutomaticMergeWorkflowSnapshot(
            comparison: successor.comparison,
            source: ComparisonSnapshot(left: successor.left.text, right: successor.right.text),
            rows: current.rows,
            comparisonOptions: current.comparisonOptions,
            left: successor.left,
            right: successor.right,
            commandState: MergeCommandPolicy.State(
                left: successor.left.commandSideState,
                right: successor.right.commandSideState,
                comparisonLifecycle: successor.comparisonLifecycle,
                hasSelection: false,
                hasSignificantDifferences: current.commandState.hasSignificantDifferences
            ),
            capabilities: current.capabilities,
            conflictPolicy: current.conflictPolicy
        )
    }
}

private struct StubExecutorFixture: Sendable {
    let snapshot: AutomaticMergeWorkflowSnapshot
}

private func makeStubFixture(
    left: String = stubLines("top", "left-1", "left-2", "shared", "tail"),
    right: String = stubLines("top", "shared", "right-1", "right-2", "tail")
) throws -> StubExecutorFixture {
    let leftRevision = AutomaticMergeWorkflowPaneRevision(
        documentID: stubFixedUUID(1),
        revision: 10
    )
    let rightRevision = AutomaticMergeWorkflowPaneRevision(
        documentID: stubFixedUUID(2),
        revision: 20
    )
    let leftPane = AutomaticMergeWorkflowPaneSnapshot(
        revision: leftRevision,
        text: left,
        isEditable: true,
        isReadOnly: false,
        isDirty: false
    )
    let rightPane = AutomaticMergeWorkflowPaneSnapshot(
        revision: rightRevision,
        text: right,
        isEditable: true,
        isReadOnly: false,
        isDirty: false
    )
    let rows = try LineDiff.compare(left: left, right: right, options: LineDiffOptions())
    let snapshot = AutomaticMergeWorkflowSnapshot(
        comparison: AutomaticMergeWorkflowComparisonReference(
            identity: AutomaticMergeWorkflowComparisonIdentity(rawValue: stubFixedUUID(3)),
            generation: 30,
            leftSource: leftRevision,
            rightSource: rightRevision
        ),
        source: ComparisonSnapshot(left: left, right: right),
        rows: rows,
        comparisonOptions: LineDiffOptions(),
        left: leftPane,
        right: rightPane,
        commandState: stubCommandState(
            left: leftPane,
            right: rightPane,
            hasDifferences: rows.contains { $0.kind != .unchanged }
        )
    )
    return StubExecutorFixture(snapshot: snapshot)
}

private func stubReplacing(
    _ snapshot: AutomaticMergeWorkflowSnapshot,
    comparison: AutomaticMergeWorkflowComparisonReference? = nil,
    left: AutomaticMergeWorkflowPaneSnapshot? = nil,
    right: AutomaticMergeWorkflowPaneSnapshot? = nil,
    commandState: MergeCommandPolicy.State? = nil,
    capabilities: AutomaticMergeWorkflowCapabilities? = nil
) -> AutomaticMergeWorkflowSnapshot {
    AutomaticMergeWorkflowSnapshot(
        comparison: comparison ?? snapshot.comparison,
        source: snapshot.source,
        rows: snapshot.rows,
        comparisonOptions: snapshot.comparisonOptions,
        left: left ?? snapshot.left,
        right: right ?? snapshot.right,
        commandState: commandState ?? snapshot.commandState,
        capabilities: capabilities ?? snapshot.capabilities,
        conflictPolicy: snapshot.conflictPolicy
    )
}

private func stubReplacingPane(
    _ pane: AutomaticMergeWorkflowPaneSnapshot,
    revision: AutomaticMergeWorkflowPaneRevision? = nil,
    text: String? = nil
) -> AutomaticMergeWorkflowPaneSnapshot {
    AutomaticMergeWorkflowPaneSnapshot(
        revision: revision ?? pane.revision,
        text: text ?? pane.text,
        isLoaded: pane.isLoaded,
        isEditable: pane.isEditable,
        isReadOnly: pane.isReadOnly,
        isDirty: pane.isDirty
    )
}

private func stubCommandState(
    left: AutomaticMergeWorkflowPaneSnapshot,
    right: AutomaticMergeWorkflowPaneSnapshot,
    hasDifferences: Bool
) -> MergeCommandPolicy.State {
    MergeCommandPolicy.State(
        left: left.commandSideState,
        right: right.commandSideState,
        hasSelection: false,
        hasSignificantDifferences: hasDifferences
    )
}

private func stubFixedUUID(_ value: UInt8) -> UUID {
    UUID(
        uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
}

private func stubLines(_ values: String...) -> String {
    values.joined(separator: "\n")
}
