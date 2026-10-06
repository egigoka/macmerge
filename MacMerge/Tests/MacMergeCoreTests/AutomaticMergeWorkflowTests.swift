import Foundation
import MacMergeCore
import XCTest

final class AutomaticMergeWorkflowTests: XCTestCase {
    private typealias WorkflowError = AutomaticMergeWorkflowError

    func testAutomaticMergeClassifiesEveryRowAndRunWithExactConflicts() throws {
        let unchanged = row(1, "same", 1, "same", .unchanged)
        let leftOnly = row(2, "left", nil, nil, .removed)
        let rightOnly = row(nil, nil, 2, "right", .added)
        let modified = row(3, "left-modified", 3, "right-modified", .modified)
        let inconsistent = row(4, "left-invalid", 4, "right-invalid", .removed)
        let rows = [
            unchanged,
            leftOnly,
            row(3, "left-second", nil, nil, .removed),
            unchanged,
            rightOnly,
            unchanged,
            modified,
            unchanged,
            row(5, "left-mixed", nil, nil, .removed),
            row(nil, nil, 5, "right-mixed", .added),
            unchanged,
            inconsistent
        ]

        XCTAssertEqual(AutomaticMerge.classify(unchanged), .insignificant)
        XCTAssertEqual(AutomaticMerge.classify(leftOnly), .leftOnly)
        XCTAssertEqual(AutomaticMerge.classify(rightOnly), .rightOnly)
        XCTAssertEqual(AutomaticMerge.classify(modified), .modifiedPair)
        XCTAssertEqual(AutomaticMerge.classify(inconsistent), .inconsistent)

        let plan = try AutomaticMerge.plan(
            rows: rows,
            editability: AutomaticMergeEditability(left: true, right: true)
        )
        XCTAssertEqual(
            plan.runs,
            [
                AutomaticMergeRun(rowRange: 1..<3, classification: .leftOnly),
                AutomaticMergeRun(rowRange: 4..<5, classification: .rightOnly),
                AutomaticMergeRun(rowRange: 6..<7, classification: .modifiedPair),
                AutomaticMergeRun(rowRange: 8..<10, classification: .mixedDirections),
                AutomaticMergeRun(rowRange: 11..<12, classification: .inconsistent)
            ]
        )
        XCTAssertEqual(
            plan.operations,
            [
                AutomaticMergeOperation(rowRange: 1..<3, direction: .leftToRight),
                AutomaticMergeOperation(rowRange: 4..<5, direction: .rightToLeft)
            ]
        )
        XCTAssertEqual(
            plan.unresolvedConflicts,
            [
                AutomaticMergeUnresolvedConflict(
                    run: plan.runs[2],
                    reason: .modifiedPair
                ),
                AutomaticMergeUnresolvedConflict(
                    run: plan.runs[3],
                    reason: .mixedDirections
                ),
                AutomaticMergeUnresolvedConflict(
                    run: plan.runs[4],
                    reason: .inconsistentRows
                )
            ]
        )
        XCTAssertEqual(plan.runs.count, 5)
        XCTAssertEqual(plan.operations.count, 2)
        XCTAssertEqual(plan.unresolvedConflicts.count, 3)
        XCTAssertTrue(plan.blockedConflicts.isEmpty)
        XCTAssertTrue(plan.hasConflicts)
    }

    func testAutomaticMergeReadOnlyDestinationsProduceExactBlockedRuns() throws {
        let rows = [
            row(1, "left", nil, nil, .removed),
            row(2, "same", 1, "same", .unchanged),
            row(nil, nil, 2, "right", .added)
        ]
        let plan = try AutomaticMerge.plan(
            rows: rows,
            editability: AutomaticMergeEditability(left: false, right: false)
        )

        XCTAssertTrue(plan.operations.isEmpty)
        XCTAssertTrue(plan.unresolvedConflicts.isEmpty)
        XCTAssertEqual(
            plan.blockedConflicts,
            [
                AutomaticMergeBlockedConflict(
                    run: AutomaticMergeRun(rowRange: 0..<1, classification: .leftOnly),
                    direction: .leftToRight,
                    destination: .right
                ),
                AutomaticMergeBlockedConflict(
                    run: AutomaticMergeRun(rowRange: 2..<3, classification: .rightOnly),
                    direction: .rightToLeft,
                    destination: .left
                )
            ]
        )
        XCTAssertEqual(plan.blockedConflicts.count, 2)
        XCTAssertTrue(plan.hasConflicts)
    }

    func testEveryWorkflowDispositionAndConflictPolicyIsExact() throws {
        let noChanges = try makeWorkflowFixture(left: "same", right: "same")
        let executable = try makeWorkflowFixture(
            left: lines("top", "left-only", "tail"),
            right: lines("top", "tail")
        )
        let conflicted = try makeWorkflowFixture(
            left: lines("left-only", "same", "left-modified"),
            right: lines("same", "right-modified")
        )
        let conflictFreeRequired = replacing(
            conflicted.snapshot,
            conflictPolicy: .requireConflictFree
        )
        let blocked = try makeWorkflowFixture(
            left: "left-modified",
            right: "right-modified"
        )

        let noChangesPlan = try AutomaticMergeWorkflow.plan(
            AutomaticMergeWorkflowRequest(snapshot: noChanges.snapshot)
        )
        XCTAssertEqual(noChangesPlan.disposition, .noChanges)
        XCTAssertFalse(noChangesPlan.isExecutable)
        XCTAssertTrue(noChangesPlan.operations.isEmpty)
        XCTAssertTrue(noChangesPlan.automaticPlan.runs.isEmpty)
        XCTAssertNil(noChangesPlan.publicationIntent)
        XCTAssertEqual(noChangesPlan.receipt.operationCount, 0)

        let executablePlan = try AutomaticMergeWorkflow.plan(
            AutomaticMergeWorkflowRequest(snapshot: executable.snapshot)
        )
        XCTAssertEqual(executablePlan.disposition, .executable)
        XCTAssertTrue(executablePlan.isExecutable)
        XCTAssertEqual(executablePlan.operations.count, 1)
        XCTAssertTrue(executablePlan.receipt.unresolvedConflicts.isEmpty)
        XCTAssertTrue(executablePlan.receipt.blockedConflicts.isEmpty)

        let conflictedPlan = try AutomaticMergeWorkflow.plan(
            AutomaticMergeWorkflowRequest(snapshot: conflicted.snapshot)
        )
        XCTAssertEqual(conflictedPlan.disposition, .executableWithConflicts)
        XCTAssertTrue(conflictedPlan.isExecutable)
        XCTAssertEqual(conflictedPlan.operations.count, 1)
        XCTAssertEqual(conflictedPlan.receipt.unresolvedConflicts.count, 1)
        XCTAssertEqual(conflictedPlan.receipt.unresolvedConflicts[0].run.rowRange, 2..<3)
        XCTAssertEqual(conflictedPlan.receipt.unresolvedConflicts[0].reason, .modifiedPair)

        let conflictFreePlan = try AutomaticMergeWorkflow.plan(
            AutomaticMergeWorkflowRequest(snapshot: conflictFreeRequired)
        )
        XCTAssertEqual(conflictFreePlan.disposition, .blockedByConflicts)
        XCTAssertFalse(conflictFreePlan.isExecutable)
        XCTAssertEqual(conflictFreePlan.operations.count, 1)
        XCTAssertNil(conflictFreePlan.publicationIntent)

        let blockedPlan = try AutomaticMergeWorkflow.plan(
            AutomaticMergeWorkflowRequest(snapshot: blocked.snapshot)
        )
        XCTAssertEqual(blockedPlan.disposition, .blockedByConflicts)
        XCTAssertFalse(blockedPlan.isExecutable)
        XCTAssertTrue(blockedPlan.operations.isEmpty)
        XCTAssertEqual(blockedPlan.receipt.unresolvedConflicts.count, 1)
        XCTAssertNil(blockedPlan.publicationIntent)

        for plan in [noChangesPlan, conflictFreePlan, blockedPlan] {
            assertWorkflowError(.planNotExecutable(plan.disposition)) {
                try plan.initialStagingProgress()
            }
        }
    }

    func testRegressionOnlyDestinationEditabilityControlsPropagation() throws {
        let intoRight = try makeWorkflowFixture(
            left: lines("top", "left-only", "tail"),
            right: lines("top", "tail"),
            leftEditable: false,
            leftReadOnly: true,
            rightEditable: true,
            rightReadOnly: false
        )
        let intoLeft = try makeWorkflowFixture(
            left: lines("top", "tail"),
            right: lines("top", "right-only", "tail"),
            leftEditable: true,
            leftReadOnly: false,
            rightEditable: false,
            rightReadOnly: true
        )

        let rightPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: intoRight.snapshot))
        XCTAssertEqual(rightPlan.disposition, .executable)
        XCTAssertEqual(rightPlan.operations.map(\.operation.direction), [.leftToRight])
        XCTAssertEqual(rightPlan.publicationIntent?.paneMutations.map(\.side), [.right])

        let leftPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: intoLeft.snapshot))
        XCTAssertEqual(leftPlan.disposition, .executable)
        XCTAssertEqual(leftPlan.operations.map(\.operation.direction), [.rightToLeft])
        XCTAssertEqual(leftPlan.publicationIntent?.paneMutations.map(\.side), [.left])

        for isReadOnly in [false, true] {
            let readOnlyDestination = replacingPane(
                intoRight.snapshot.right,
                isEditable: false,
                isReadOnly: isReadOnly
            )
            let blocked = replacing(intoRight.snapshot, right: readOnlyDestination)
            let blockedWithMatchingCommand = replacing(
                blocked,
                commandState: commandState(
                    left: blocked.left,
                    right: blocked.right,
                    hasDifferences: true
                )
            )
            let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: blockedWithMatchingCommand))
            XCTAssertEqual(plan.disposition, .blockedByConflicts)
            XCTAssertTrue(plan.operations.isEmpty)
            XCTAssertEqual(plan.receipt.blockedConflicts.count, 1)
            XCTAssertEqual(plan.receipt.blockedConflicts[0].destination, .right)
            XCTAssertEqual(plan.receipt.blockedConflicts[0].direction, .leftToRight)
        }
    }

    func testSnapshotBindingRejectsEveryLoadEditabilityRevisionTextAndCommandMismatch() throws {
        let fixture = try makeWorkflowFixture()
        let snapshot = fixture.snapshot
        let collidingRight = replacingPane(
            snapshot.right,
            revision: AutomaticMergeWorkflowPaneRevision(
                documentID: snapshot.left.revision.documentID,
                revision: snapshot.right.revision.revision
            )
        )
        let unloadedLeft = replacingPane(snapshot.left, isLoaded: false)
        let inconsistentRight = replacingPane(
            snapshot.right,
            isEditable: true,
            isReadOnly: true
        )
        let mismatchedLeftRevision = AutomaticMergeWorkflowComparisonReference(
            identity: snapshot.comparison.identity,
            generation: snapshot.comparison.generation,
            leftSource: AutomaticMergeWorkflowPaneRevision(
                documentID: snapshot.left.revision.documentID,
                revision: snapshot.left.revision.revision + 1
            ),
            rightSource: snapshot.comparison.rightSource
        )
        let canonicallyEquivalentPane = replacingPane(
            snapshot.left,
            text: "caf\u{0065}\u{0301}"
        )
        let canonicallyEquivalentSource = ComparisonSnapshot(
            left: "caf\u{00E9}",
            right: snapshot.source.right
        )
        let canonicalRows = try LineDiff.compare(
            left: canonicallyEquivalentSource.left,
            right: canonicallyEquivalentSource.right,
            options: snapshot.comparisonOptions
        )
        let canonicalMismatch = replacing(
            snapshot,
            source: canonicallyEquivalentSource,
            rows: canonicalRows,
            left: canonicallyEquivalentPane
        )
        let commandMismatch = MergeCommandPolicy.State(
            left: MergeCommandPolicy.SideState(
                isLoaded: true,
                isEditable: false,
                isDirty: snapshot.left.isDirty
            ),
            right: snapshot.commandState.right,
            hasSelection: false,
            hasSignificantDifferences: true
        )
        let threeWay = MergeCommandPolicy.State(
            left: snapshot.commandState.left,
            right: snapshot.commandState.right,
            layout: .threeWay(
                middle: MergeCommandPolicy.SideState(
                    isLoaded: true,
                    isEditable: true,
                    isDirty: false
                ),
                autoMergeDestination: .middle,
                isAutoMergeEligible: true
            ),
            hasSelection: false,
            hasSignificantDifferences: true
        )
        let staleCommand = MergeCommandPolicy.State(
            left: snapshot.commandState.left,
            right: snapshot.commandState.right,
            comparisonLifecycle: .stale,
            hasSelection: false,
            hasSignificantDifferences: true
        )
        let noDifferencesCommand = MergeCommandPolicy.State(
            left: snapshot.commandState.left,
            right: snapshot.commandState.right,
            hasSelection: false,
            hasSignificantDifferences: false
        )
        let cases: [(AutomaticMergeWorkflowSnapshot, WorkflowError)] = [
            (replacing(snapshot, right: collidingRight), .paneIdentityCollision),
            (replacing(snapshot, left: unloadedLeft), .paneNotLoaded(.left)),
            (replacing(snapshot, right: inconsistentRight), .inconsistentEditability(.right)),
            (
                replacing(snapshot, comparison: mismatchedLeftRevision),
                .comparisonSourceRevisionMismatch(.left)
            ),
            (canonicalMismatch, .comparisonSourceTextMismatch(.left)),
            (replacing(snapshot, commandState: commandMismatch), .commandPaneStateMismatch(.left)),
            (replacing(snapshot, commandState: threeWay), .commandLayoutNotTwoWay),
            (
                replacing(snapshot, commandState: staleCommand),
                .commandComparisonNotCurrent(.stale)
            ),
            (
                replacing(snapshot, commandState: noDifferencesCommand),
                .commandDifferenceStateMismatch
            ),
            (
                replacing(
                    snapshot,
                    capabilities: AutomaticMergeWorkflowCapabilities(rawValue: 0x8F)
                ),
                .invalidCapabilities(0x8F)
            ),
            (
                replacing(
                    snapshot,
                    capabilities: AutomaticMergeWorkflowCapabilities.all.subtracting(.plan)
                ),
                .missingCapability(.plan)
            )
        ]

        XCTAssertEqual(canonicallyEquivalentPane.text, canonicallyEquivalentSource.left)
        XCTAssertEqual(Array(canonicallyEquivalentPane.text.utf8).count, 6)
        XCTAssertEqual(Array(canonicallyEquivalentSource.left.utf8).count, 5)
        XCTAssertNotEqual(
            Array(canonicallyEquivalentPane.text.utf8),
            Array(canonicallyEquivalentSource.left.utf8)
        )
        for (invalid, expected) in cases {
            assertWorkflowError(expected) {
                try AutomaticMergeWorkflow.plan(.init(snapshot: invalid))
            }
        }
    }

    func testSnapshotCASAcceptsIndependentExactRebuildAndRejectsEveryRetainedStateMutation() async throws {
        let fixture = try makeWorkflowFixture()
        let expected = fixture.snapshot
        let rebuiltFixture = try makeWorkflowFixture(
            left: expected.source.left,
            right: expected.source.right,
            options: expected.comparisonOptions,
            leftDirty: expected.left.isDirty,
            rightDirty: expected.right.isDirty,
            conflictPolicy: expected.conflictPolicy
        )
        XCTAssertEqual(expected, rebuiltFixture.snapshot)

        let exactPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: expected))
        let exactOwner = AutomaticMergeWorkflowTestOwner(snapshot: rebuiltFixture.snapshot)
        let exactProgress = try exactPlan.initialStagingProgress()
        _ = try await exactOwner.authorizeNext(exactPlan, progress: exactProgress)
        let exactState = await exactOwner.state()
        XCTAssertEqual(exactState.snapshotReadCount, 1)

        var changedRows = expected.rows
        changedRows[0] = DiffRow(
            left: DiffLine(number: 1, text: "changed-row"),
            right: DiffLine(number: 1, text: "changed-row"),
            kind: .unchanged
        )
        let changedOptions = LineDiffOptions(
            algorithm: .minimal,
            lineFilters: [LineFilterRule(pattern: "never-match")]
        )
        let commandWithSelection = MergeCommandPolicy.State(
            left: expected.commandState.left,
            right: expected.commandState.right,
            hasSelection: true,
            hasSignificantDifferences: true
        )
        let changedComparisonSource = AutomaticMergeWorkflowComparisonReference(
            identity: expected.comparison.identity,
            generation: expected.comparison.generation,
            leftSource: AutomaticMergeWorkflowPaneRevision(
                documentID: expected.left.revision.documentID,
                revision: expected.left.revision.revision + 1
            ),
            rightSource: expected.comparison.rightSource
        )
        let mutations = [
            replacing(
                expected,
                source: ComparisonSnapshot(
                    left: expected.source.left + "!",
                    right: expected.source.right
                )
            ),
            replacing(expected, rows: changedRows),
            replacing(expected, comparisonOptions: changedOptions),
            replacing(expected, left: replacingPane(expected.left, text: expected.left.text + "!")),
            replacing(expected, left: replacingPane(expected.left, isLoaded: false)),
            replacing(expected, left: replacingPane(expected.left, isEditable: false)),
            replacing(expected, left: replacingPane(expected.left, isReadOnly: true)),
            replacing(expected, left: replacingPane(expected.left, isDirty: !expected.left.isDirty)),
            replacing(expected, right: replacingPane(expected.right, text: expected.right.text + "!")),
            replacing(expected, commandState: commandWithSelection),
            replacing(expected, capabilities: [.plan, .stageOperations]),
            replacing(expected, conflictPolicy: .requireConflictFree),
            replacing(expected, comparison: changedComparisonSource)
        ]
        XCTAssertEqual(mutations.count, 13)
        for mutation in mutations {
            let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: expected))
            let owner = AutomaticMergeWorkflowTestOwner(snapshot: mutation)
            let progress = try plan.initialStagingProgress()
            await assertAsyncWorkflowError(.snapshotContentsChanged) {
                try await owner.authorizeNext(plan, progress: progress)
            }
        }
    }

    func testSnapshotCASReportsIdentityGenerationAndPaneRevisionStalenessExactly() async throws {
        let fixture = try makeWorkflowFixture()
        let expected = fixture.snapshot
        let otherIdentity = AutomaticMergeWorkflowComparisonReference(
            identity: AutomaticMergeWorkflowComparisonIdentity(rawValue: fixedUUID(99)),
            generation: expected.comparison.generation,
            leftSource: expected.comparison.leftSource,
            rightSource: expected.comparison.rightSource
        )
        let nextGeneration = AutomaticMergeWorkflowComparisonReference(
            identity: expected.comparison.identity,
            generation: expected.comparison.generation + 1,
            leftSource: expected.comparison.leftSource,
            rightSource: expected.comparison.rightSource
        )
        let nextLeftRevision = AutomaticMergeWorkflowPaneRevision(
            documentID: expected.left.revision.documentID,
            revision: expected.left.revision.revision + 1
        )
        let nextRightRevision = AutomaticMergeWorkflowPaneRevision(
            documentID: expected.right.revision.documentID,
            revision: expected.right.revision.revision + 1
        )
        let cases: [(AutomaticMergeWorkflowSnapshot, WorkflowError)] = [
            (
                replacing(expected, comparison: otherIdentity),
                .staleComparisonIdentity(
                    expected: expected.comparison.identity,
                    actual: otherIdentity.identity
                )
            ),
            (
                replacing(expected, comparison: nextGeneration),
                .staleComparisonGeneration(
                    expected: expected.comparison.generation,
                    actual: nextGeneration.generation
                )
            ),
            (
                replacing(expected, left: replacingPane(expected.left, revision: nextLeftRevision)),
                .stalePaneRevision(
                    side: .left,
                    expected: expected.left.revision,
                    actual: nextLeftRevision
                )
            ),
            (
                replacing(expected, right: replacingPane(expected.right, revision: nextRightRevision)),
                .stalePaneRevision(
                    side: .right,
                    expected: expected.right.revision,
                    actual: nextRightRevision
                )
            )
        ]

        XCTAssertEqual(cases.count, 4)
        for (stale, expectedError) in cases {
            let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: expected))
            let owner = AutomaticMergeWorkflowTestOwner(snapshot: stale)
            let progress = try plan.initialStagingProgress()
            await assertAsyncWorkflowError(expectedError) {
                try await owner.authorizeNext(plan, progress: progress)
            }
            let state = await owner.state()
            XCTAssertEqual(state.snapshotReadCount, 1)
            XCTAssertEqual(state.publicationBodyCount, 0)
            XCTAssertNil(state.publishedSuccessor)
        }
    }

    func testRegressionStagingUsesDeterministicBottomUpOperationsAndRows() async throws {
        let fixture = try makeWorkflowFixture(leftDirty: true, rightDirty: false)
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))

        XCTAssertEqual(plan.automaticPlan.operations.count, 2)
        XCTAssertEqual(plan.operations.count, 2)
        XCTAssertEqual(plan.operations.map(\.executionIndex), [0, 1])
        XCTAssertEqual(plan.operations.map(\.operation.rowRange), [4..<6, 1..<3])
        XCTAssertEqual(plan.operations.map(\.operation.direction), [.rightToLeft, .leftToRight])
        XCTAssertEqual(
            plan.operations[0].rowIDs,
            [
                DiffRow.ID(leftNumber: nil, rightNumber: 4),
                DiffRow.ID(leftNumber: nil, rightNumber: 3)
            ]
        )
        XCTAssertEqual(
            plan.operations[1].rowIDs,
            [
                DiffRow.ID(leftNumber: 3, rightNumber: nil),
                DiffRow.ID(leftNumber: 2, rightNumber: nil)
            ]
        )

        let owner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        var progress = try plan.initialStagingProgress()
        let firstPermit = try await owner.authorizeNext(plan, progress: progress)
        XCTAssertEqual(firstPermit.operation, plan.operations[0])
        XCTAssertEqual(
            firstPermit.resultingDraft,
            ComparisonSnapshot(
                left: lines(
                    "top", "left-1", "left-2", "shared", "right-1", "right-2", "tail"
                ),
                right: fixture.snapshot.source.right
            )
        )
        progress = try plan.executorAttestedStaged(permit: firstPermit)
        XCTAssertEqual(progress.completedOperationCount, 1)

        let privateState = await owner.state()
        XCTAssertEqual(privateState.snapshotReadCount, 1)
        XCTAssertEqual(privateState.publicationBodyCount, 0)
        XCTAssertNil(privateState.publishedSuccessor)

        let secondPermit = try await owner.authorizeNext(plan, progress: progress)
        XCTAssertEqual(secondPermit.operation, plan.operations[1])
        XCTAssertEqual(secondPermit.resultingDraft.left, secondPermit.resultingDraft.right)
        XCTAssertEqual(
            secondPermit.resultingDraft.left,
            lines("top", "left-1", "left-2", "shared", "right-1", "right-2", "tail")
        )
        progress = try plan.executorAttestedStaged(permit: secondPermit)
        XCTAssertEqual(progress.completedOperationCount, 2)
        XCTAssertEqual(progress.draft, secondPermit.resultingDraft)
    }

    func testRegressionCopiedOperationPermitAndPlanReplayAreOneShot() async throws {
        let fixture = try makeWorkflowFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let initial = try plan.initialStagingProgress()
        let permit = try await owner.authorizeNext(plan, progress: initial)
        let copiedPermit = permit

        let progress = try plan.executorAttestedStaged(permit: permit)
        XCTAssertEqual(progress.completedOperationCount, 1)
        assertWorkflowError(.invalidExecutionProof) {
            try plan.executorAttestedStaged(permit: copiedPermit)
        }
        assertWorkflowError(.planAlreadyConsumed) {
            try plan.initialStagingProgress()
        }

        let otherPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        assertWorkflowError(.invalidExecutionProof) {
            try otherPlan.executorAttestedStaged(permit: copiedPermit)
        }
    }

    func testActorReadsLiveSnapshotBeforeEveryStageAndPublicationBoundary() async throws {
        let fixture = try makeWorkflowFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        var progress = try plan.initialStagingProgress()

        for expectedReadCount in 1...plan.operations.count {
            let permit = try await owner.authorizeNext(plan, progress: progress)
            progress = try plan.executorAttestedStaged(permit: permit)
            let state = await owner.state()
            XCTAssertEqual(state.snapshotReadCount, expectedReadCount)
            XCTAssertNil(state.publishedSuccessor)
        }

        _ = try await owner.authorizePublication(plan, progress: progress)
        let authorizedState = await owner.state()
        XCTAssertEqual(authorizedState.snapshotReadCount, plan.operations.count + 1)
        XCTAssertEqual(authorizedState.publicationBodyCount, 0)
        XCTAssertNil(authorizedState.publishedSuccessor)

        let stalePlan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let staleOwner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let staleProgress = try stalePlan.initialStagingProgress()
        let nextGeneration = AutomaticMergeWorkflowComparisonReference(
            identity: fixture.snapshot.comparison.identity,
            generation: fixture.snapshot.comparison.generation + 1,
            leftSource: fixture.snapshot.comparison.leftSource,
            rightSource: fixture.snapshot.comparison.rightSource
        )
        await staleOwner.replaceSnapshot(
            replacing(fixture.snapshot, comparison: nextGeneration)
        )
        await assertAsyncWorkflowError(
            .staleComparisonGeneration(
                expected: fixture.snapshot.comparison.generation,
                actual: nextGeneration.generation
            )
        ) {
            try await staleOwner.authorizeNext(stalePlan, progress: staleProgress)
        }
    }

    func testAtomicCommitOwnsExactCASSuccessorDirtyUndoAndReceipt() async throws {
        let fixture = try makeWorkflowFixture(leftDirty: true, rightDirty: false)
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let intent = try XCTUnwrap(plan.publicationIntent)
        let owner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let staged = try await stage(plan, owner: owner)
        let permit = try await owner.authorizePublication(plan, progress: staged)

        XCTAssertEqual(intent.paneMutations.map(\.side), [.left, .right])
        XCTAssertEqual(
            intent.paneMutations.map(\.predecessor),
            [
                fixture.snapshot.left.revision, fixture.snapshot.right.revision
            ])
        XCTAssertEqual(intent.paneMutations.map(\.successor.revision), [11, 21])
        XCTAssertEqual(intent.paneMutations.map(\.successorIsDirty), [true, true])
        XCTAssertEqual(intent.undo.grouping, .singleAutomaticMergeTransaction)
        XCTAssertEqual(intent.undo.changedSides, [.left, .right])
        XCTAssertEqual(
            intent.undo.predecessorRevisions,
            [
                fixture.snapshot.left.revision, fixture.snapshot.right.revision
            ])
        XCTAssertEqual(intent.undo.successorRevisions, intent.paneMutations.map(\.successor))
        XCTAssertTrue(intent.undo.restoreLeftDirtyState)
        XCTAssertFalse(intent.undo.restoreRightDirtyState)
        XCTAssertEqual(intent.comparison.predecessor, fixture.snapshot.comparison)
        XCTAssertEqual(intent.comparison.successor.generation, 31)
        XCTAssertEqual(intent.comparison.successor.leftSource.revision, 11)
        XCTAssertEqual(intent.comparison.successor.rightSource.revision, 21)
        XCTAssertEqual(intent.comparison.lifecycle, .stale)

        let outcome = await owner.commit(permit.atomicCommitOperation)
        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed outcome")
        }
        let state = await owner.state()
        let successor = try XCTUnwrap(state.publishedSuccessor)

        XCTAssertEqual(state.snapshotReadCount, plan.operations.count + 2)
        XCTAssertEqual(state.publicationBodyCount, 1)
        XCTAssertEqual(state.atomicPublicationCount, 1)
        XCTAssertEqual(state.undoRegistrationCount, 1)
        XCTAssertEqual(successor.left.text, staged.draft.left)
        XCTAssertEqual(successor.right.text, staged.draft.right)
        XCTAssertEqual(successor.left.revision.revision, 11)
        XCTAssertEqual(successor.right.revision.revision, 21)
        XCTAssertTrue(successor.left.isDirty)
        XCTAssertTrue(successor.right.isDirty)
        XCTAssertEqual(successor.registeredUndo, intent.undo)
        XCTAssertEqual(successor.comparison, intent.comparison.successor)
        XCTAssertEqual(successor.comparisonLifecycle, .stale)

        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        XCTAssertEqual(receipt.atomicCommit.successor, successor)
        XCTAssertEqual(receipt.predecessor, fixture.snapshot.comparison)
        XCTAssertEqual(receipt.successor, intent.comparison.successor)
        XCTAssertEqual(receipt.paneMutations, intent.paneMutations)
        XCTAssertEqual(receipt.undo, intent.undo)
    }

    func testCopiedPublicationPermitReplaysOneSealedOutcomeWithoutSecondCAS() async throws {
        let fixture = try makeWorkflowFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let staged = try await stage(plan, owner: owner)
        let permit = try await owner.authorizePublication(plan, progress: staged)
        let copiedPermit = permit

        let first = await owner.commit(permit.atomicCommitOperation)
        let replay = await owner.commit(copiedPermit.atomicCommitOperation)
        XCTAssertEqual(replay, first)
        let state = await owner.state()
        XCTAssertEqual(state.publicationBodyCount, 1)
        XCTAssertEqual(state.atomicPublicationCount, 1)
        XCTAssertEqual(state.undoRegistrationCount, 1)
        XCTAssertEqual(state.snapshotReadCount, plan.operations.count + 2)
    }

    func testKnownCASAndOwnerRejectionsRemainDistinctFromUncertainty() async throws {
        let fixture = try makeWorkflowFixture()

        let stalePlan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let staleOwner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let staleStaged = try await stage(stalePlan, owner: staleOwner)
        let stalePermit = try await staleOwner.authorizePublication(
            stalePlan,
            progress: staleStaged
        )
        let staleComparison = AutomaticMergeWorkflowComparisonReference(
            identity: fixture.snapshot.comparison.identity,
            generation: fixture.snapshot.comparison.generation + 1,
            leftSource: fixture.snapshot.comparison.leftSource,
            rightSource: fixture.snapshot.comparison.rightSource
        )
        await staleOwner.replaceSnapshot(
            replacing(fixture.snapshot, comparison: staleComparison)
        )
        let staleOutcome = await staleOwner.commit(stalePermit.atomicCommitOperation)
        guard case .publicationRejected(let staleReceipt) = staleOutcome else {
            return XCTFail("Expected stale CAS rejection")
        }
        XCTAssertFalse(staleReceipt.atomicPublicationCommitted)
        let staleState = await staleOwner.state()
        XCTAssertEqual(staleState.publicationBodyCount, 0)
        XCTAssertEqual(staleState.atomicPublicationCount, 0)

        let rejectedPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let rejectedOwner = AutomaticMergeWorkflowTestOwner(
            snapshot: fixture.snapshot,
            decision: .rejected
        )
        let rejectedStaged = try await stage(rejectedPlan, owner: rejectedOwner)
        let rejectedPermit = try await rejectedOwner.authorizePublication(
            rejectedPlan,
            progress: rejectedStaged
        )
        let rejectedOutcome = await rejectedOwner.commit(rejectedPermit.atomicCommitOperation)
        guard case .publicationRejected(let rejectedReceipt) = rejectedOutcome else {
            return XCTFail("Expected owner rejection")
        }
        XCTAssertFalse(rejectedReceipt.atomicPublicationCommitted)
        let rejectedState = await rejectedOwner.state()
        XCTAssertEqual(rejectedState.publicationBodyCount, 1)
        XCTAssertEqual(rejectedState.atomicPublicationCount, 0)
        XCTAssertNil(rejectedState.publishedSuccessor)

        for decision in [
            AutomaticMergeWorkflowTestOwner.Decision.uncertain,
            .invalidCommittedSuccessor
        ] {
            let uncertainPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
            let uncertainOwner = AutomaticMergeWorkflowTestOwner(
                snapshot: fixture.snapshot,
                decision: decision
            )
            let uncertainStaged = try await stage(uncertainPlan, owner: uncertainOwner)
            let uncertainPermit = try await uncertainOwner.authorizePublication(
                uncertainPlan,
                progress: uncertainStaged
            )
            let outcome = await uncertainOwner.commit(uncertainPermit.atomicCommitOperation)
            guard case .publicationUncertain(let receipt) = outcome else {
                return XCTFail("Expected uncertainty for \(decision)")
            }
            XCTAssertTrue(receipt.atomicPublicationMayHaveCommitted)
            XCTAssertEqual(receipt.planningReceipt, uncertainPlan.receipt)
            XCTAssertEqual(receipt.publicationIntent, uncertainPlan.publicationIntent)
        }
    }

    func testFailureAndUncertaintyReceiptsCannotClaimPartialSuccess() async throws {
        let fixture = try makeWorkflowFixture()
        XCTAssertEqual(AutomaticMergeWorkflowFailureReason.allCases.count, 7)

        for reason in AutomaticMergeWorkflowFailureReason.allCases {
            let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
            let progress = try plan.initialStagingProgress()
            let outcome =
                try AutomaticMergeWorkflowExecutionOutcomeFactory
                .failedBeforePublication(plan: plan, progress: progress, reason: reason)
            guard case .failed(let receipt) = outcome else {
                return XCTFail("Expected pre-publication failure")
            }
            XCTAssertEqual(receipt.planningReceipt, plan.receipt)
            XCTAssertEqual(receipt.completedStagingOperationCount, 0)
            XCTAssertEqual(receipt.reason, reason)
            XCTAssertFalse(receipt.publicationAttempted)
            assertWorkflowError(.planAlreadyConsumed) {
                try plan.initialStagingProgress()
            }
        }

        let partialPlan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let partialOwner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        var partialProgress = try partialPlan.initialStagingProgress()
        let permit = try await partialOwner.authorizeNext(
            partialPlan,
            progress: partialProgress
        )
        partialProgress = try partialPlan.executorAttestedStaged(permit: permit)
        let failed = try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
            plan: partialPlan,
            progress: partialProgress,
            reason: .stagingFailed
        )
        guard case .failed(let partialReceipt) = failed else {
            return XCTFail("Expected staged-prefix failure")
        }
        XCTAssertEqual(partialReceipt.completedStagingOperationCount, 1)
        XCTAssertFalse(partialReceipt.publicationAttempted)
        let partialState = await partialOwner.state()
        XCTAssertEqual(partialState.atomicPublicationCount, 0)
        XCTAssertEqual(partialState.undoRegistrationCount, 0)
        XCTAssertNil(partialState.publishedSuccessor)
    }

    func testRowRunOperationInputRetainedAndWorkLimitsAreExact() throws {
        let fixture = try makeWorkflowFixture()
        let baseline = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let inputBytes = max(
            fixture.snapshot.source.left.utf8.count,
            fixture.snapshot.source.right.utf8.count
        )

        let exact = try AutomaticMergeWorkflow.plan(
            .init(
                snapshot: fixture.snapshot,
                limits: workflowLimits(
                    maximumRows: 10,
                    maximumRuns: 2,
                    maximumOperations: 2,
                    maximumInputUTF8BytesPerPane: inputBytes,
                    maximumRetainedBytes: baseline.receipt.estimatedRetainedBytes,
                    maximumWorkUnits: baseline.receipt.workUnitsConsumed
                )
            )
        )
        XCTAssertEqual(exact.automaticPlan.runs.count, 2)
        XCTAssertEqual(exact.operations.count, 2)
        XCTAssertEqual(exact.receipt.estimatedRetainedBytes, baseline.receipt.estimatedRetainedBytes)
        XCTAssertEqual(exact.receipt.workUnitsConsumed, baseline.receipt.workUnitsConsumed)

        let failures: [(AutomaticMergeWorkflowLimits, WorkflowError)] = [
            (workflowLimits(maximumRows: 9), .tooManyRows(maximum: 9)),
            (
                workflowLimits(maximumRuns: 1),
                .automaticMerge(.tooManyRuns(maximum: 1))
            ),
            (
                workflowLimits(maximumOperations: 1),
                .tooManyOperations(maximum: 1)
            ),
            (
                workflowLimits(maximumInputUTF8BytesPerPane: inputBytes - 1),
                .inputTooLarge(side: .right, maximumUTF8Bytes: inputBytes - 1)
            ),
            (
                workflowLimits(
                    maximumRetainedBytes: baseline.receipt.estimatedRetainedBytes - 1
                ),
                .retainedDataTooLarge(
                    maximumBytes: baseline.receipt.estimatedRetainedBytes - 1
                )
            ),
            (
                workflowLimits(maximumWorkUnits: baseline.receipt.workUnitsConsumed - 1),
                .workLimitExceeded(maximumUnits: baseline.receipt.workUnitsConsumed - 1)
            )
        ]
        XCTAssertEqual(failures.count, 6)
        for (limits, expectedError) in failures {
            assertWorkflowError(expectedError) {
                try AutomaticMergeWorkflow.plan(
                    AutomaticMergeWorkflowRequest(snapshot: fixture.snapshot, limits: limits)
                )
            }
        }
    }

    func testOutputLimitAcceptsExactBytesAndRejectsOneByteUnderDuringPrivateStaging() async throws {
        let fixture = try makeWorkflowFixture()
        let merged = lines(
            "top", "left-1", "left-2", "shared", "right-1", "right-2", "tail"
        )
        let exactBytes = merged.utf8.count

        let exactPlan = try AutomaticMergeWorkflow.plan(
            .init(
                snapshot: fixture.snapshot,
                limits: workflowLimits(
                    maximumInputUTF8BytesPerPane: max(
                        fixture.snapshot.source.left.utf8.count,
                        fixture.snapshot.source.right.utf8.count
                    ),
                    maximumOutputUTF8BytesPerPane: exactBytes
                )
            )
        )
        let exactOwner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let exactProgress = try await stage(exactPlan, owner: exactOwner)
        XCTAssertEqual(exactProgress.draft.left.utf8.count, exactBytes)
        XCTAssertEqual(exactProgress.draft.right.utf8.count, exactBytes)

        let shortPlan = try AutomaticMergeWorkflow.plan(
            .init(
                snapshot: fixture.snapshot,
                limits: workflowLimits(
                    maximumInputUTF8BytesPerPane: max(
                        fixture.snapshot.source.left.utf8.count,
                        fixture.snapshot.source.right.utf8.count
                    ),
                    maximumOutputUTF8BytesPerPane: exactBytes - 1
                )
            )
        )
        let shortOwner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let shortProgress = try shortPlan.initialStagingProgress()
        await assertAsyncWorkflowError(.outputTooLarge(maximumUTF8Bytes: exactBytes - 1)) {
            try await shortOwner.authorizeNext(shortPlan, progress: shortProgress)
        }
        let shortState = await shortOwner.state()
        XCTAssertEqual(shortState.atomicPublicationCount, 0)
        XCTAssertNil(shortState.publishedSuccessor)
    }

    func testPlanningAndStagingWorkLimitsRejectBeforePrimitivePublication() async throws {
        let fixture = try makeWorkflowFixture()
        let baseline = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let planningWork = baseline.receipt.workUnitsConsumed
        let plan = try AutomaticMergeWorkflow.plan(
            .init(
                snapshot: fixture.snapshot,
                limits: workflowLimits(maximumWorkUnits: planningWork)
            )
        )
        XCTAssertEqual(plan.receipt.workUnitsConsumed, planningWork)
        let owner = AutomaticMergeWorkflowTestOwner(snapshot: fixture.snapshot)
        let progress = try plan.initialStagingProgress()

        await assertAsyncWorkflowError(.workLimitExceeded(maximumUnits: 0)) {
            try await owner.authorizeNext(plan, progress: progress)
        }
        let outcome = try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
            plan: plan,
            progress: progress,
            reason: .stagingFailed
        )
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected staging failure")
        }
        XCTAssertEqual(receipt.completedStagingOperationCount, 0)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublicationCount, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testCancellationBeforePlanningAndPrimitiveAuthorizationIsTypedAndAtomic() async throws {
        let fixture = try makeWorkflowFixture()
        let snapshot = fixture.snapshot
        let planningError = await Task.detached { () -> WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try AutomaticMergeWorkflow.plan(.init(snapshot: snapshot))
                return nil
            } catch let error as WorkflowError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(planningError, .cancelled)

        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: snapshot))
        let owner = AutomaticMergeWorkflowTestOwner(snapshot: snapshot)
        let progress = try plan.initialStagingProgress()
        let stagingError = await Task.detached { () -> WorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await owner.authorizeNext(plan, progress: progress)
                return nil
            } catch let error as WorkflowError {
                return error
            } catch {
                return nil
            }
        }.value
        XCTAssertEqual(stagingError, .cancelled)

        let outcome = try AutomaticMergeWorkflowExecutionOutcomeFactory.failedBeforePublication(
            plan: plan,
            progress: progress,
            reason: .cancelled
        )
        guard case .failed(let receipt) = outcome else {
            return XCTFail("Expected cancellation failure")
        }
        XCTAssertEqual(receipt.completedStagingOperationCount, 0)
        XCTAssertEqual(receipt.reason, .cancelled)
        XCTAssertFalse(receipt.publicationAttempted)
        let state = await owner.state()
        XCTAssertEqual(state.publicationBodyCount, 0)
        XCTAssertEqual(state.atomicPublicationCount, 0)
        XCTAssertNil(state.publishedSuccessor)
    }

    func testCancellationAfterPublicationAuthorizationCannotRewriteCommittedOutcome() async throws {
        let fixture = try makeWorkflowFixture()
        let plan = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let owner = AutomaticMergeWorkflowTestOwner(
            snapshot: fixture.snapshot,
            decision: .committedAndCancel
        )
        let progress = try await stage(plan, owner: owner)
        let permit = try await owner.authorizePublication(plan, progress: progress)
        let task = Task { await owner.commit(permit.atomicCommitOperation) }
        let outcome = await task.value

        XCTAssertTrue(task.isCancelled)
        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected non-cancellable committed outcome")
        }
        XCTAssertEqual(receipt.successor, plan.publicationIntent?.comparison.successor)
        let state = await owner.state()
        XCTAssertEqual(state.atomicPublicationCount, 1)
        XCTAssertEqual(state.undoRegistrationCount, 1)
    }

    func testPlanningReceiptsAreDeterministicAndRenderWithoutRetainedSecrets() throws {
        let secret = "automatic-merge-secret-canary"
        let fixture = try makeWorkflowFixture(
            left: lines(secret, "same", "left-modified"),
            right: lines("same", "right-modified")
        )
        let first = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))
        let second = try AutomaticMergeWorkflow.plan(.init(snapshot: fixture.snapshot))

        XCTAssertEqual(first.snapshotCAS, second.snapshotCAS)
        XCTAssertEqual(first.source, second.source)
        XCTAssertEqual(first.comparisonRows, second.comparisonRows)
        XCTAssertEqual(first.comparisonOptions, second.comparisonOptions)
        XCTAssertEqual(first.automaticPlan, second.automaticPlan)
        XCTAssertEqual(first.operations, second.operations)
        XCTAssertEqual(first.disposition, second.disposition)
        XCTAssertEqual(first.publicationIntent, second.publicationIntent)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.limits, second.limits)
        XCTAssertEqual(first.executorContract, second.executorContract)
        XCTAssertEqual(first.receipt.operationCount, 1)
        XCTAssertEqual(first.receipt.unresolvedConflicts.count, 1)
        XCTAssertEqual(first.receipt.blockedConflicts.count, 0)

        let firstRenderings = receiptRenderings(first.receipt)
        let secondRenderings = receiptRenderings(second.receipt)
        XCTAssertEqual(firstRenderings, secondRenderings)
        XCTAssertEqual(firstRenderings.count, 4)
        for rendering in firstRenderings {
            XCTAssertFalse(rendering.contains(secret), rendering)
        }
    }

    func testExecutorContractPinsPriorReviewAtomicityAndCancellationRegressions() {
        let contract = AutomaticMergeWorkflowExecutorContract.required
        XCTAssertEqual(
            contract.snapshotLease,
            .validateExactComparisonPaneCommandAndCapabilityStateBeforeEveryStageAndPublication
        )
        XCTAssertEqual(
            contract.operations,
            .coreComputesExactOriginalSourceRowsEndToStartInPlanOrder
        )
        XCTAssertEqual(
            contract.publication,
            .atomicallyPublishAllDraftsRevisionsDirtyUndoAndInvalidationOrPublishNothing
        )
        XCTAssertEqual(
            contract.cancellation,
            .cancellableBeforeEachStageAndPublicationNoncancellableAfterPublicationAuthorization
        )
        XCTAssertEqual(
            contract.receipts,
            .completedOnlyWithExactAtomicSuccessorKnownRejectionDistinctFromUncertainty
        )
    }

    private func stage(
        _ plan: AutomaticMergeWorkflowPlan,
        owner: AutomaticMergeWorkflowTestOwner
    ) async throws -> AutomaticMergeWorkflowStagingProgress {
        var progress = try plan.initialStagingProgress()
        for _ in plan.operations {
            let permit = try await owner.authorizeNext(plan, progress: progress)
            progress = try plan.executorAttestedStaged(permit: permit)
        }
        return progress
    }

    private func assertWorkflowError<T>(
        _ expected: WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? WorkflowError, expected, file: file, line: line)
        }
    }

    private func assertAsyncWorkflowError<T>(
        _ expected: WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as WorkflowError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private struct AutomaticMergeWorkflowFixture: Sendable {
    let snapshot: AutomaticMergeWorkflowSnapshot
}

private func makeWorkflowFixture(
    left: String = lines("top", "left-1", "left-2", "shared", "tail"),
    right: String = lines("top", "shared", "right-1", "right-2", "tail"),
    options: LineDiffOptions = LineDiffOptions(),
    leftEditable: Bool = true,
    leftReadOnly: Bool = false,
    leftDirty: Bool = false,
    rightEditable: Bool = true,
    rightReadOnly: Bool = false,
    rightDirty: Bool = false,
    conflictPolicy: AutomaticMergeWorkflowConflictPolicy = .applyNonconflicting
) throws -> AutomaticMergeWorkflowFixture {
    let leftRevision = AutomaticMergeWorkflowPaneRevision(
        documentID: fixedUUID(1),
        revision: 10
    )
    let rightRevision = AutomaticMergeWorkflowPaneRevision(
        documentID: fixedUUID(2),
        revision: 20
    )
    let leftPane = AutomaticMergeWorkflowPaneSnapshot(
        revision: leftRevision,
        text: left,
        isEditable: leftEditable,
        isReadOnly: leftReadOnly,
        isDirty: leftDirty
    )
    let rightPane = AutomaticMergeWorkflowPaneSnapshot(
        revision: rightRevision,
        text: right,
        isEditable: rightEditable,
        isReadOnly: rightReadOnly,
        isDirty: rightDirty
    )
    let rows = try LineDiff.compare(left: left, right: right, options: options)
    let snapshot = AutomaticMergeWorkflowSnapshot(
        comparison: AutomaticMergeWorkflowComparisonReference(
            identity: AutomaticMergeWorkflowComparisonIdentity(rawValue: fixedUUID(3)),
            generation: 30,
            leftSource: leftRevision,
            rightSource: rightRevision
        ),
        source: ComparisonSnapshot(left: left, right: right),
        rows: rows,
        comparisonOptions: options,
        left: leftPane,
        right: rightPane,
        commandState: commandState(
            left: leftPane,
            right: rightPane,
            hasDifferences: rows.contains { $0.kind != .unchanged }
        ),
        conflictPolicy: conflictPolicy
    )
    return AutomaticMergeWorkflowFixture(snapshot: snapshot)
}

private func replacing(
    _ snapshot: AutomaticMergeWorkflowSnapshot,
    comparison: AutomaticMergeWorkflowComparisonReference? = nil,
    source: ComparisonSnapshot? = nil,
    rows: [DiffRow]? = nil,
    comparisonOptions: LineDiffOptions? = nil,
    left: AutomaticMergeWorkflowPaneSnapshot? = nil,
    right: AutomaticMergeWorkflowPaneSnapshot? = nil,
    commandState: MergeCommandPolicy.State? = nil,
    capabilities: AutomaticMergeWorkflowCapabilities? = nil,
    conflictPolicy: AutomaticMergeWorkflowConflictPolicy? = nil
) -> AutomaticMergeWorkflowSnapshot {
    AutomaticMergeWorkflowSnapshot(
        comparison: comparison ?? snapshot.comparison,
        source: source ?? snapshot.source,
        rows: rows ?? snapshot.rows,
        comparisonOptions: comparisonOptions ?? snapshot.comparisonOptions,
        left: left ?? snapshot.left,
        right: right ?? snapshot.right,
        commandState: commandState ?? snapshot.commandState,
        capabilities: capabilities ?? snapshot.capabilities,
        conflictPolicy: conflictPolicy ?? snapshot.conflictPolicy
    )
}

private func replacingPane(
    _ pane: AutomaticMergeWorkflowPaneSnapshot,
    revision: AutomaticMergeWorkflowPaneRevision? = nil,
    text: String? = nil,
    isLoaded: Bool? = nil,
    isEditable: Bool? = nil,
    isReadOnly: Bool? = nil,
    isDirty: Bool? = nil
) -> AutomaticMergeWorkflowPaneSnapshot {
    AutomaticMergeWorkflowPaneSnapshot(
        revision: revision ?? pane.revision,
        text: text ?? pane.text,
        isLoaded: isLoaded ?? pane.isLoaded,
        isEditable: isEditable ?? pane.isEditable,
        isReadOnly: isReadOnly ?? pane.isReadOnly,
        isDirty: isDirty ?? pane.isDirty
    )
}

private func commandState(
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

private func workflowLimits(
    _ base: AutomaticMergeWorkflowLimits = .default,
    maximumRows: Int? = nil,
    maximumRuns: Int? = nil,
    maximumOperations: Int? = nil,
    maximumInputUTF8BytesPerPane: Int? = nil,
    maximumOutputUTF8BytesPerPane: Int? = nil,
    maximumRetainedBytes: Int? = nil,
    maximumOptionItems: Int? = nil,
    maximumOptionUTF8Bytes: Int? = nil,
    maximumWorkUnits: UInt64? = nil,
    maximumComparisonLinePairs: UInt64? = nil,
    cancellationCheckInterval: Int? = nil
) -> AutomaticMergeWorkflowLimits {
    AutomaticMergeWorkflowLimits(
        maximumRows: maximumRows ?? base.maximumRows,
        maximumRuns: maximumRuns ?? base.maximumRuns,
        maximumOperations: maximumOperations ?? base.maximumOperations,
        maximumInputUTF8BytesPerPane:
            maximumInputUTF8BytesPerPane ?? base.maximumInputUTF8BytesPerPane,
        maximumOutputUTF8BytesPerPane:
            maximumOutputUTF8BytesPerPane ?? base.maximumOutputUTF8BytesPerPane,
        maximumRetainedBytes: maximumRetainedBytes ?? base.maximumRetainedBytes,
        maximumOptionItems: maximumOptionItems ?? base.maximumOptionItems,
        maximumOptionUTF8Bytes: maximumOptionUTF8Bytes ?? base.maximumOptionUTF8Bytes,
        maximumWorkUnits: maximumWorkUnits ?? base.maximumWorkUnits,
        maximumComparisonLinePairs:
            maximumComparisonLinePairs ?? base.maximumComparisonLinePairs,
        cancellationCheckInterval: cancellationCheckInterval ?? base.cancellationCheckInterval
    )
}

private struct AutomaticMergeWorkflowTestOwnerState: Sendable {
    let current: AutomaticMergeWorkflowSnapshot
    let publishedSuccessor: AutomaticMergeWorkflowPublishedSuccessor?
    let snapshotReadCount: Int
    let publicationBodyCount: Int
    let atomicPublicationCount: Int
    let undoRegistrationCount: Int
}

private actor AutomaticMergeWorkflowTestOwner: AutomaticMergeWorkflowAtomicOwner {
    enum Decision: Equatable, Sendable {
        case committed
        case committedAndCancel
        case rejected
        case uncertain
        case invalidCommittedSuccessor
    }

    private var current: AutomaticMergeWorkflowSnapshot
    private var publishedSuccessor: AutomaticMergeWorkflowPublishedSuccessor?
    private var snapshotReadCount = 0
    private var publicationBodyCount = 0
    private var atomicPublicationCount = 0
    private var undoRegistrationCount = 0
    private let decision: Decision

    init(
        snapshot: AutomaticMergeWorkflowSnapshot,
        decision: Decision = .committed
    ) {
        current = snapshot
        self.decision = decision
    }

    func currentAutomaticMergeSnapshot() -> AutomaticMergeWorkflowSnapshot {
        snapshotReadCount += 1
        return current
    }

    func authorizeNext(
        _ plan: AutomaticMergeWorkflowPlan,
        progress: AutomaticMergeWorkflowStagingProgress
    ) throws -> AutomaticMergeWorkflowOperationPermit {
        try plan.authorizeNextOperation(in: progress, owner: self)
    }

    func authorizePublication(
        _ plan: AutomaticMergeWorkflowPlan,
        progress: AutomaticMergeWorkflowStagingProgress
    ) throws -> AutomaticMergeWorkflowPublicationPermit {
        try plan.authorizePublication(of: progress, owner: self)
    }

    func compareAndCommitAutomaticMerge(
        _ operation: AutomaticMergeWorkflowAtomicCommitOperation
    ) -> AutomaticMergeWorkflowExecutionOutcome {
        operation.compareAndCommit(owner: self) { owner, intent, draft in
            owner.publicationBodyCount += 1
            switch owner.decision {
            case .committed, .committedAndCancel:
                if owner.decision == .committedAndCancel {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                let successor = owner.makeSuccessor(intent: intent, draft: draft)
                owner.publish(successor, draft: draft)
                return .committed(successor)
            case .rejected:
                return .rejected
            case .uncertain:
                return .uncertain
            case .invalidCommittedSuccessor:
                let valid = owner.makeSuccessor(intent: intent, draft: draft)
                let invalid = AutomaticMergeWorkflowPublishedSuccessor(
                    left: valid.left,
                    right: valid.right,
                    comparison: valid.comparison,
                    comparisonLifecycle: .currentSuccess,
                    registeredUndo: valid.registeredUndo
                )
                owner.publishedSuccessor = invalid
                owner.atomicPublicationCount += 1
                owner.undoRegistrationCount += 1
                return .committed(invalid)
            }
        }
    }

    func commit(
        _ operation: AutomaticMergeWorkflowAtomicCommitOperation
    ) -> AutomaticMergeWorkflowExecutionOutcome {
        compareAndCommitAutomaticMerge(operation)
    }

    func replaceSnapshot(_ snapshot: AutomaticMergeWorkflowSnapshot) {
        current = snapshot
    }

    func state() -> AutomaticMergeWorkflowTestOwnerState {
        AutomaticMergeWorkflowTestOwnerState(
            current: current,
            publishedSuccessor: publishedSuccessor,
            snapshotReadCount: snapshotReadCount,
            publicationBodyCount: publicationBodyCount,
            atomicPublicationCount: atomicPublicationCount,
            undoRegistrationCount: undoRegistrationCount
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

    private func publish(
        _ successor: AutomaticMergeWorkflowPublishedSuccessor,
        draft: ComparisonSnapshot
    ) {
        publishedSuccessor = successor
        atomicPublicationCount += 1
        undoRegistrationCount += 1
        current = AutomaticMergeWorkflowSnapshot(
            comparison: successor.comparison,
            source: draft,
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

private func row(
    _ leftNumber: Int?,
    _ leftText: String?,
    _ rightNumber: Int?,
    _ rightText: String?,
    _ kind: DiffKind
) -> DiffRow {
    DiffRow(
        left: leftNumber.flatMap { number in
            leftText.map { DiffLine(number: number, text: $0) }
        },
        right: rightNumber.flatMap { number in
            rightText.map { DiffLine(number: number, text: $0) }
        },
        kind: kind
    )
}

private func lines(_ values: String...) -> String {
    values.joined(separator: "\n")
}

private func fixedUUID(_ value: UInt8) -> UUID {
    UUID(
        uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
}

private func receiptRenderings(_ value: AutomaticMergeWorkflowPlanningReceipt) -> [String] {
    var dumped = ""
    dump(value, to: &dumped)
    let mirrored = Mirror(reflecting: value).children.map { child in
        "\(child.label ?? "_")=\(String(reflecting: child.value))"
    }.joined(separator: ",")
    return [String(describing: value), String(reflecting: value), mirrored, dumped]
}
