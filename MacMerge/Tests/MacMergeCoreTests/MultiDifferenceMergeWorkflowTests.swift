import Foundation
import MacMergeCore
import XCTest

final class MultiDifferenceMergeWorkflowTests: XCTestCase {
    private typealias Workflow = MultiDifferenceMergeWorkflow
    private typealias WorkflowError = MultiDifferenceMergeWorkflowError

    func testSelectionBindingRetainsExactSelectedRowsAndFullMaximalGroups() throws {
        let fixture = try makeFixture()
        let snapshot = fixture.snapshot
        let binding = snapshot.selectionBinding

        XCTAssertEqual(binding.reference, snapshot.selectionReference)
        XCTAssertEqual(binding.rowRange, 2..<7)
        XCTAssertEqual(
            binding.selectedRowIDs,
            [rowID(3, nil), rowID(4, 3), rowID(5, 4), rowID(6, 5), rowID(7, 6)]
        )
        XCTAssertEqual(binding.sourceRowCount, 10)
        XCTAssertEqual(binding.differenceGroups.count, 3)

        let first = binding.differenceGroups[0]
        XCTAssertEqual(first.id, snapshot.selection.differenceRuns[0].id)
        XCTAssertEqual(first.rowRange, 1..<3)
        XCTAssertEqual(first.selectionIntersection, 2..<3)
        XCTAssertEqual(first.rowIDs, [rowID(2, 2), rowID(3, nil)])
        XCTAssertEqual(first.leftSourceRowCount, 2)
        XCTAssertEqual(first.rightSourceRowCount, 1)

        let second = binding.differenceGroups[1]
        XCTAssertEqual(second.rowRange, 4..<5)
        XCTAssertEqual(second.selectionIntersection, 4..<5)
        XCTAssertEqual(second.rowIDs, [rowID(5, 4)])
        XCTAssertEqual(second.leftSourceRowCount, 1)
        XCTAssertEqual(second.rightSourceRowCount, 1)

        let third = binding.differenceGroups[2]
        XCTAssertEqual(third.rowRange, 6..<7)
        XCTAssertEqual(third.selectionIntersection, 6..<7)
        XCTAssertEqual(third.rowIDs, [rowID(7, 6)])
        XCTAssertEqual(third.leftSourceRowCount, 1)
        XCTAssertEqual(third.rightSourceRowCount, 1)
    }

    func testEveryDirectionAndAdvanceIntentMapsToExactPolicyCommand() throws {
        let snapshot = try makeFixture().snapshot
        let cases:
            [(
                MultiDifferenceMergeWorkflowCommandIntent,
                MergeCommandPolicy.Command,
                Bool
            )] = [
                (intent(.leftToRight, .remain), .leftToRight, false),
                (intent(.rightToLeft, .remain), .rightToLeft, false),
                (intent(.leftToRight, .advanceToNextDifference), .leftToRightAndAdvance, true),
                (intent(.rightToLeft, .advanceToNextDifference), .rightToLeftAndAdvance, true)
            ]

        for (commandIntent, expectedCommand, expectedAdvance) in cases {
            let state = try Workflow.commandState(for: commandIntent, in: snapshot)
            XCTAssertEqual(commandIntent.policyCommand, expectedCommand)
            XCTAssertEqual(commandIntent.copyAndAdvance, expectedAdvance)
            XCTAssertEqual(state.intent, commandIntent)
            XCTAssertEqual(state.expectedSnapshot, snapshot.reference)
            XCTAssertEqual(state.selection, snapshot.selectionBinding)
            XCTAssertEqual(state.availability, .enabled)
            XCTAssertTrue(state.isEnabled)
            XCTAssertTrue(state.canExecute)
            XCTAssertNil(state.disabledReason)
            XCTAssertGreaterThan(state.workUnitsConsumed, 0)
        }
    }

    func testPrimitiveInvocationAndResultAreExactForBothDirections() throws {
        let fixture = try makeFixture()
        let cases:
            [(
                direction: MergeDirection,
                expected: ComparisonSnapshot,
                groups: [MultiDifferenceMergeChangeGroup],
                destination: MultiDifferenceMergeWorkflowPane
            )] = [
                (
                    .leftToRight,
                    ComparisonSnapshot(
                        left: fixture.source.left,
                        right: lines(
                            "same-0", "left-a", "left-extra", "same-1", "left-b",
                            "same-2", "left-c", "same-3", "next", "tail"
                        )
                    ),
                    [
                        group(1..<3, 1..<3, 1..<2, 1..<3),
                        group(4..<5, 4..<5, 3..<4, 4..<5),
                        group(6..<7, 6..<7, 5..<6, 6..<7)
                    ],
                    .right
                ),
                (
                    .rightToLeft,
                    ComparisonSnapshot(
                        left: lines(
                            "same-0", "right-a", "same-1", "right-b", "same-2",
                            "right-c", "same-3", "next", "tail"
                        ),
                        right: fixture.source.right
                    ),
                    [
                        group(1..<3, 1..<2, 1..<3, 1..<2),
                        group(4..<5, 3..<4, 4..<5, 3..<4),
                        group(6..<7, 5..<6, 6..<7, 5..<6)
                    ],
                    .left
                )
            ]

        for testCase in cases {
            let plan = try Workflow.plan(
                intent: intent(testCase.direction, .remain),
                in: fixture.snapshot
            )
            let invocation = plan.primitiveInvocation

            XCTAssertEqual(invocation.state.source, fixture.source)
            XCTAssertEqual(invocation.state.comparisonRows, fixture.rows)
            XCTAssertEqual(invocation.state.left, fixture.snapshot.left)
            XCTAssertEqual(invocation.state.right, fixture.snapshot.right)
            XCTAssertEqual(invocation.state.comparisonLifecycle, .currentSuccess)
            XCTAssertEqual(invocation.selectedAlignedRows, 2..<7)
            XCTAssertEqual(invocation.selection, fixture.snapshot.selectionBinding)
            XCTAssertEqual(invocation.direction, testCase.direction)
            XCTAssertEqual(invocation.options.lineDiff, fixture.options)
            XCTAssertEqual(plan.mergeResult.snapshot, testCase.expected)
            XCTAssertEqual(plan.mergeResult.changedGroups, testCase.groups)
            XCTAssertEqual(plan.transaction.predecessor, fixture.source)
            XCTAssertEqual(plan.transaction.successor, testCase.expected)
            XCTAssertEqual(plan.transaction.destination, testCase.destination)
            XCTAssertEqual(plan.transaction.changedGroups, testCase.groups)
            XCTAssertEqual(plan.receipt.resultUTF8ByteCount, utf8Count(testCase.expected))
        }
    }

    func testLimitValidationCoversEveryOuterAndNestedSelectionNegativeWithoutTrap() throws {
        let snapshot = try makeFixture().snapshot
        let outerCases: [(MultiDifferenceMergeWorkflowLimits, MultiDifferenceMergeWorkflowLimit)] = [
            (limits(maximumComparisonRows: -1), .comparisonRows),
            (limits(maximumSelectedRows: -1), .selectedRows),
            (limits(maximumDifferenceGroups: -1), .differenceGroups),
            (limits(maximumComparisonOptionItems: -1), .comparisonOptionItems),
            (
                limits(maximumComparisonOptionStringUTF8Bytes: -1),
                .comparisonOptionStringUTF8Bytes
            ),
            (limits(maximumComparisonOptionsUTF8Bytes: -1), .comparisonOptionsUTF8Bytes),
            (limits(maximumInputUTF8Bytes: -1), .inputUTF8Bytes),
            (limits(maximumRetainedUTF8Bytes: -1), .retainedUTF8Bytes)
        ]
        for (invalidLimits, expectedLimit) in outerCases {
            assertWorkflowError(.invalidLimit(expectedLimit)) {
                try Workflow.commandState(
                    for: self.intent(.leftToRight, .remain),
                    in: snapshot,
                    limits: invalidLimits
                )
            }
        }

        let nestedSelectionCases: [(MultiDifferenceSelectionLimits, MultiDifferenceMergeWorkflowLimit)] = [
            (MultiDifferenceSelectionLimits(maximumRows: -1), .comparisonRows),
            (MultiDifferenceSelectionLimits(maximumSelectedRows: -1), .selectedRows),
            (MultiDifferenceSelectionLimits(maximumDifferenceRows: -1), .selectedRows),
            (MultiDifferenceSelectionLimits(maximumDifferenceRuns: -1), .differenceGroups),
            (MultiDifferenceSelectionLimits(maximumWork: -1), .selectionWorkUnits)
        ]
        for (selectionLimits, expectedLimit) in nestedSelectionCases {
            assertWorkflowError(.invalidLimit(expectedLimit)) {
                try Workflow.commandState(
                    for: self.intent(.leftToRight, .remain),
                    in: snapshot,
                    limits: self.limits(selection: selectionLimits)
                )
            }
        }

        let hardWork = MultiDifferenceMergeWorkflowLimits.hardMaximumWorkUnits
        let nonnegativeNestedMergeCases:
            [(
                MultiDifferenceMergeWorkflowLimits,
                MultiDifferenceMergeWorkflowLimit
            )] = [
                (
                    limits(
                        maximumComparisonRows: 9,
                        merge: MultiDifferenceMergeOptions(maximumComparedRows: 10)
                    ),
                    .comparisonRows
                ),
                (
                    limits(
                        maximumDifferenceGroups: 2,
                        merge: MultiDifferenceMergeOptions(maximumChangeGroups: 3)
                    ),
                    .differenceGroups
                ),
                (
                    limits(
                        merge: MultiDifferenceMergeOptions(
                            maximumMergeOperations:
                                MultiDifferenceMergeWorkflowLimits.hardMaximumMergeOperations + 1
                        )
                    ),
                    .mergeOperations
                ),
                (
                    limits(
                        merge: MultiDifferenceMergeOptions(
                            maximumOutputBytes:
                                MultiDifferenceMergeWorkflowLimits.hardMaximumMergeOutputUTF8Bytes + 1
                        )
                    ),
                    .mergeOutputUTF8Bytes
                ),
                (
                    limits(
                        maximumWorkUnits: hardWork,
                        merge: MultiDifferenceMergeOptions(maximumWork: Int(hardWork) + 1)
                    ),
                    .primitiveWorkUnits
                )
            ]
        for (invalidLimits, expectedLimit) in nonnegativeNestedMergeCases {
            assertWorkflowError(.invalidLimit(expectedLimit)) {
                try Workflow.commandState(
                    for: self.intent(.leftToRight, .remain),
                    in: snapshot,
                    limits: invalidLimits
                )
            }
        }

        assertWorkflowError(.invalidLimit(.workUnits)) {
            try Workflow.commandState(
                for: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(maximumWorkUnits: hardWork + 1)
            )
        }
        assertWorkflowError(.invalidLimit(.cancellationCheckInterval)) {
            try Workflow.commandState(
                for: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(cancellationCheckInterval: 0)
            )
        }
    }

    func testEveryNestedMergeNegativeIsRejectedWithoutTrap() throws {
        let environmentKey = "MACMERGE_NESTED_MERGE_NEGATIVE"
        if let limit = ProcessInfo.processInfo.environment[environmentKey] {
            let merge: MultiDifferenceMergeOptions
            let expected: MultiDifferenceMergeWorkflowLimit
            switch limit {
            case "comparedRows":
                merge = MultiDifferenceMergeOptions(maximumComparedRows: -1)
                expected = .comparisonRows
            case "changeGroups":
                merge = MultiDifferenceMergeOptions(maximumChangeGroups: -1)
                expected = .differenceGroups
            case "mergeOperations":
                merge = MultiDifferenceMergeOptions(maximumMergeOperations: -1)
                expected = .mergeOperations
            case "outputBytes":
                merge = MultiDifferenceMergeOptions(maximumOutputBytes: -1)
                expected = .mergeOutputUTF8Bytes
            case "work":
                merge = MultiDifferenceMergeOptions(maximumWork: -1)
                expected = .primitiveWorkUnits
            default:
                return XCTFail("Unknown nested merge limit: \(limit)")
            }
            let snapshot = try makeFixture().snapshot
            assertWorkflowError(.invalidLimit(expected)) {
                try Workflow.commandState(
                    for: self.intent(.leftToRight, .remain),
                    in: snapshot,
                    limits: self.limits(merge: merge)
                )
            }
            return
        }

        let limits = [
            "comparedRows", "changeGroups", "mergeOperations", "outputBytes", "work"
        ]
        let failures = try limits.compactMap { limit -> String? in
            let status = try runCurrentTestSubprocess(
                testName:
                    "\(String(reflecting: type(of: self)))/testEveryNestedMergeNegativeIsRejectedWithoutTrap",
                environment: [environmentKey: limit]
            )
            return status == 0 ? nil : "\(limit): exit \(status)"
        }
        XCTAssertEqual(failures, [])
    }

    func testConfiguredSizeAndCountLimitsFailAtExactPublicBoundaries() throws {
        let fixture = try makeFixture()
        let snapshot = fixture.snapshot

        assertWorkflowError(.tooManyComparisonRows(maximum: fixture.rows.count - 1)) {
            try Workflow.commandState(
                for: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(
                    maximumComparisonRows: fixture.rows.count - 1,
                    merge: MultiDifferenceMergeOptions(maximumComparedRows: fixture.rows.count - 1)
                )
            )
        }
        assertWorkflowError(.tooManySelectedRows(maximum: 4)) {
            try Workflow.commandState(
                for: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(maximumSelectedRows: 4)
            )
        }
        assertWorkflowError(.tooManyDifferenceGroups(maximum: 2)) {
            try Workflow.commandState(
                for: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(
                    maximumDifferenceGroups: 2,
                    merge: MultiDifferenceMergeOptions(maximumChangeGroups: 2)
                )
            )
        }
        assertWorkflowError(.inputTooLarge(maximumUTF8Bytes: utf8Count(fixture.source) - 1)) {
            try Workflow.commandState(
                for: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(maximumInputUTF8Bytes: utf8Count(fixture.source) - 1)
            )
        }
        assertWorkflowError(.retainedDataTooLarge(maximumUTF8Bytes: 0)) {
            try Workflow.commandState(
                for: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(maximumRetainedUTF8Bytes: 0)
            )
        }
    }

    func testRetainedSizeAndRevisionPreflightHaveStablePrecedence() throws {
        let fixture = try makeFixture()
        let baseline = try Workflow.plan(
            intent: intent(.leftToRight, .remain),
            in: fixture.snapshot
        )
        let expandedRetainedLimit = baseline.receipt.retainedUTF8ByteEstimate - 1
        let exhaustedComparison = try makeFixture(comparisonRevision: .max).snapshot

        assertWorkflowError(.retainedDataTooLarge(maximumUTF8Bytes: 0)) {
            try Workflow.plan(
                intent: self.intent(.leftToRight, .remain),
                in: exhaustedComparison,
                limits: self.limits(maximumRetainedUTF8Bytes: 0)
            )
        }
        assertWorkflowError(.comparisonRevisionExhausted) {
            try Workflow.plan(
                intent: self.intent(.leftToRight, .remain),
                in: exhaustedComparison,
                limits: self.limits(maximumRetainedUTF8Bytes: expandedRetainedLimit)
            )
        }
        assertWorkflowError(
            .retainedDataTooLarge(maximumUTF8Bytes: expandedRetainedLimit)
        ) {
            try Workflow.plan(
                intent: self.intent(.leftToRight, .remain),
                in: fixture.snapshot,
                limits: self.limits(maximumRetainedUTF8Bytes: expandedRetainedLimit)
            )
        }

        assertWorkflowError(.sourceRevisionExhausted) {
            try Workflow.plan(
                intent: self.intent(.leftToRight, .remain),
                in: try self.makeFixture(sourceRevision: .max).snapshot
            )
        }
        assertWorkflowError(.paneRevisionExhausted(.right)) {
            try Workflow.plan(
                intent: self.intent(.leftToRight, .remain),
                in: try self.makeFixture(rightPaneRevision: .max).snapshot
            )
        }
        assertWorkflowError(.paneRevisionExhausted(.left)) {
            try Workflow.plan(
                intent: self.intent(.rightToLeft, .remain),
                in: try self.makeFixture(leftPaneRevision: .max).snapshot
            )
        }
    }

    func testTransactionBindsPaneComparisonAndOptionsPublicationCASExactly() throws {
        let snapshot = try makeFixture().snapshot
        let plan = try Workflow.plan(
            intent: intent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let transaction = plan.transaction
        let publication = transaction.successorComparisonPublication

        XCTAssertEqual(transaction.expectedState, snapshot)
        XCTAssertEqual(transaction.expectedSnapshot, snapshot.reference)
        XCTAssertEqual(transaction.expectedSource, snapshot.sourceReference)
        XCTAssertEqual(transaction.destination, .right)
        XCTAssertEqual(transaction.expectedDestinationRevision, snapshot.sourceReference.right)
        XCTAssertEqual(transaction.successorDestinationRevision.identity, snapshot.sourceReference.right.identity)
        XCTAssertEqual(
            transaction.successorDestinationRevision.revision,
            snapshot.sourceReference.right.revision + 1
        )
        XCTAssertEqual(transaction.successorSource.revision, snapshot.sourceReference.revision + 1)
        XCTAssertEqual(transaction.successorSource.left, snapshot.sourceReference.left)
        XCTAssertEqual(transaction.successorSource.right, transaction.successorDestinationRevision)
        XCTAssertEqual(transaction.expectedDestinationState, snapshot.right)
        XCTAssertEqual(
            transaction.successorDestinationState,
            MergeCommandPolicy.SideState(isLoaded: true, isEditable: true, isDirty: true)
        )
        XCTAssertEqual(publication.expectedSource, transaction.successorSource)
        XCTAssertEqual(publication.expectedSourceContents, transaction.successor)
        XCTAssertEqual(publication.expectedInvalidatedComparison, snapshot.comparisonReference)
        XCTAssertEqual(publication.expectedComparisonOptions, snapshot.comparisonOptions)
        XCTAssertEqual(
            publication.expectedComparisonOptionsGeneration,
            snapshot.comparisonReference
        )
        XCTAssertEqual(publication.successor, transaction.successorComparison)
        XCTAssertEqual(transaction.successorComparison.options, snapshot.comparisonOptions)
        XCTAssertEqual(
            transaction.successorComparison.optionsGeneration,
            transaction.successorComparison.reference
        )
        XCTAssertEqual(
            plan.requiredEffects,
            [
                .commitOwnerTransaction,
                .publishSuccessorComparison(publication),
                .publishNavigation(transaction.navigationIntent)
            ]
        )
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(
            plan.executorContract.preflight,
            .validateExactSnapshotCASAndAllEffectCapabilitiesBeforeFirstEffect
        )
        XCTAssertEqual(
            plan.executorContract.compareAndSwap,
            .atomicExactSnapshotAndDestinationPaneRevisionCompareAndSwap
        )
        XCTAssertEqual(
            plan.executorContract.mutation,
            .commitExactTextRevisionUndoDirtySelectionAndInvalidationInOneOwnerTransaction
        )
        XCTAssertEqual(
            plan.executorContract.publication,
            .atomicSourceComparisonAndOptionsCASThenNavigationInPlanOrder
        )
    }

    func testActorOwnerCommitsEntireTransactionAtomically() async throws {
        let snapshot = try makeFixture().snapshot
        let plan = try Workflow.plan(
            intent: intent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = MergeWorkflowTestOwner(snapshot: snapshot)

        let receipt = try await owner.commit(plan)
        let state = await owner.state()

        XCTAssertEqual(receipt.planReference, plan.reference)
        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        XCTAssertEqual(receipt.transaction, plan.transaction)
        XCTAssertEqual(receipt.evidence.transactionID, plan.transaction.id)
        XCTAssertEqual(state.compareCount, 1)
        XCTAssertEqual(state.commitCount, 1)
        XCTAssertEqual(state.source, plan.transaction.successor)
        XCTAssertEqual(state.sourceReference, plan.transaction.successorSource)
        XCTAssertEqual(state.leftState, plan.transaction.expectedState.left)
        XCTAssertEqual(state.rightState, plan.transaction.successorDestinationState)
        XCTAssertEqual(state.undoPredecessors, [plan.transaction.predecessor])
        XCTAssertEqual(state.selectionIntent, plan.transaction.successorSelectionIntent)
        XCTAssertEqual(
            state.invalidatedComparison,
            plan.transaction.expectedState.comparisonReference
        )
        XCTAssertEqual(state.consumedTransactions, [plan.transaction.id])
    }

    func testCommittedButInvalidOwnerEvidenceBecomesCommitUncertainty() async throws {
        let snapshot = try makeFixture().snapshot
        let plan = try Workflow.plan(intent: intent(.leftToRight, .remain), in: snapshot)
        let owner = MergeWorkflowTestOwner(snapshot: snapshot, evidenceMode: .invalidSuccessor)

        await assertAsyncWorkflowError(.commitUncertain) {
            try await owner.commit(plan)
        }

        let state = await owner.state()
        XCTAssertEqual(state.commitCount, 1, "Invalid evidence cannot prove rollback")
        XCTAssertEqual(state.source, plan.transaction.successor)
    }

    func testActualComparisonAndNavigationEvidenceCompleteEffectsInOrder() async throws {
        let snapshot = try makeFixture().snapshot
        let plan = try Workflow.plan(
            intent: intent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = MergeWorkflowTestOwner(snapshot: snapshot)
        let commitReceipt = try await owner.commit(plan)
        let publicationIntent = plan.transaction.successorComparisonPublication
        let comparisonEvidence = MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence(
            comparedSource: publicationIntent.expectedSource,
            comparedSourceContents: publicationIntent.expectedSourceContents,
            comparedInvalidatedComparison: publicationIntent.expectedInvalidatedComparison,
            comparedComparisonOptions: publicationIntent.expectedComparisonOptions,
            comparedComparisonOptionsGeneration:
                publicationIntent.expectedComparisonOptionsGeneration,
            publishedComparison: publicationIntent.successor
        )
        let comparisonReceipt =
            try MultiDifferenceMergeWorkflowPublicationReceipt
            .executorAttestedSuccessorComparisonPublished(
                plan: plan,
                commitReceipt: commitReceipt,
                evidence: comparisonEvidence
            )
        let navigationEvidence = MultiDifferenceMergeWorkflowNavigationPublicationEvidence(
            intent: plan.transaction.navigationIntent,
            publishedComparison: plan.transaction.successorComparison.reference,
            publishedTarget: plan.transaction.successorNavigationTarget
        )
        let navigationReceipt =
            try MultiDifferenceMergeWorkflowPublicationReceipt
            .executorAttestedNavigationPublished(
                plan: plan,
                after: comparisonReceipt,
                evidence: navigationEvidence
            )
        let outcome = try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.completed(
            plan: plan,
            commitReceipt: commitReceipt,
            publicationReceipts: [comparisonReceipt, navigationReceipt]
        )

        guard case .completed(let execution) = outcome else {
            return XCTFail("Expected completed execution")
        }
        XCTAssertEqual(execution.planningReceipt, plan.receipt)
        XCTAssertEqual(execution.commitReceipt, commitReceipt)
        XCTAssertEqual(execution.publicationReceipts, [comparisonReceipt, navigationReceipt])
        XCTAssertEqual(execution.completedEffects, plan.requiredEffects)
        XCTAssertEqual(comparisonReceipt.effect, plan.requiredEffects[1])
        XCTAssertEqual(comparisonReceipt.evidence, .successorComparison(comparisonEvidence))
        XCTAssertEqual(navigationReceipt.effect, plan.requiredEffects[2])
        XCTAssertEqual(navigationReceipt.evidence, .navigation(navigationEvidence))

        let wrongOptionsGeneration = MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence(
            comparedSource: publicationIntent.expectedSource,
            comparedSourceContents: publicationIntent.expectedSourceContents,
            comparedInvalidatedComparison: publicationIntent.expectedInvalidatedComparison,
            comparedComparisonOptions: publicationIntent.expectedComparisonOptions,
            comparedComparisonOptionsGeneration: plan.transaction.successorComparison.reference,
            publishedComparison: publicationIntent.successor
        )
        assertWorkflowError(.publicationUncertain) {
            try MultiDifferenceMergeWorkflowPublicationReceipt
                .executorAttestedSuccessorComparisonPublished(
                    plan: plan,
                    commitReceipt: commitReceipt,
                    evidence: wrongOptionsGeneration
                )
        }
    }

    func testSuccessorNavigationTargetUsesResolvedSuccessorIdentityAfterDeletion() throws {
        let environmentKey = "MACMERGE_SUCCESSOR_TARGET_CHILD"
        guard ProcessInfo.processInfo.environment[environmentKey] == "1" else {
            let status = try runCurrentTestSubprocess(
                testName:
                    "\(String(reflecting: type(of: self)))/testSuccessorNavigationTargetUsesResolvedSuccessorIdentityAfterDeletion",
                environment: [environmentKey: "1"]
            )
            return XCTAssertEqual(status, 0)
        }

        let plan = try Workflow.plan(
            intent: intent(.rightToLeft, .advanceToNextDifference),
            in: try makeFixture(
                nextLeft: "left-next",
                nextRight: "right-next"
            ).snapshot
        )
        let target = try XCTUnwrap(plan.transaction.successorNavigationTarget)

        XCTAssertEqual(target.comparison, plan.transaction.successorComparison.reference)
        XCTAssertEqual(target.rowRange, 7..<8)
        XCTAssertEqual(target.rowIDs, [rowID(8, 8)])
        XCTAssertEqual(target.id.comparison, plan.transaction.successorComparison.reference)
        XCTAssertEqual(target.id.firstRowID, rowID(8, 8))
        XCTAssertEqual(target.id.lastRowID, rowID(8, 8))
        XCTAssertNotEqual(target.rowIDs, [rowID(9, 8)], "Predecessor identity is stale")
        XCTAssertEqual(plan.reference.successorNavigationTarget, target.id)
        XCTAssertEqual(
            plan.transaction.successorSelectionIntent,
            .selectResolvedNextDifference(
                comparison: plan.transaction.successorComparison.reference,
                target: target,
                wraps: false
            )
        )
        XCTAssertEqual(
            plan.transaction.navigationIntent,
            .publishResolvedNextDifference(
                comparison: plan.transaction.successorComparison.reference,
                target: target,
                wraps: false
            )
        )
    }

    func testExactSnapshotCASRejectsEveryStaleReferenceAndRetainedValue() throws {
        let fixture = try makeFixture()
        let plan = try Workflow.plan(intent: intent(.leftToRight, .remain), in: fixture.snapshot)

        let staleCases: [(MultiDifferenceMergeWorkflowSnapshot, WorkflowError)] = [
            (
                try makeFixture(
                    comparisonIdentity: comparisonIdentity(99)
                ).snapshot,
                .staleComparisonIdentity
            ),
            (
                try makeFixture(comparisonRevision: 41).snapshot,
                .staleComparisonRevision(expected: 40, actual: 41)
            ),
            (
                try makeFixture(sourceIdentity: sourceIdentity(99)).snapshot,
                .staleSourceIdentity
            ),
            (
                try makeFixture(sourceRevision: 51).snapshot,
                .staleSourceRevision(expected: 50, actual: 51)
            ),
            (
                try makeFixture(leftPaneIdentity: paneIdentity(99)).snapshot,
                .stalePaneIdentity(.left)
            ),
            (
                try makeFixture(rightPaneRevision: 71).snapshot,
                .stalePaneRevision(pane: .right, expected: 70, actual: 71)
            ),
            (
                try makeFixture(selectionIdentity: selectionIdentity(99)).snapshot,
                .staleSelectionIdentity
            ),
            (
                try makeFixture(selectionRevision: 81).snapshot,
                .staleSelectionRevision(expected: 80, actual: 81)
            ),
            (
                try makeFixture(
                    source: ComparisonSnapshot(
                        left: fixture.source.left + "\nchanged",
                        right: fixture.source.right
                    ),
                    rows: fixture.rows,
                    selection: fixture.snapshot.selection
                ).snapshot,
                .sourceContentsChanged
            ),
            (
                try makeFixture(options: LineDiffOptions(ignoreCase: true)).snapshot,
                .comparisonOptionsChanged
            ),
            (
                try makeFixture(selectionRange: 1..<7).snapshot,
                .selectionChanged
            ),
            (
                try makeFixture(
                    left: MergeCommandPolicy.SideState(
                        isLoaded: true,
                        isEditable: true,
                        isDirty: true
                    )
                ).snapshot,
                .sideStateChanged(.left)
            ),
            (
                try makeFixture(comparisonLifecycle: .stale).snapshot,
                .comparisonLifecycleChanged
            )
        ]

        for (current, expectedError) in staleCases {
            XCTAssertFalse(try plan.expectedSnapshotCAS.matches(current))
            assertWorkflowError(expectedError) {
                try plan.validateCurrentSnapshot(current)
            }
        }
        XCTAssertTrue(try plan.expectedSnapshotCAS.matches(fixture.snapshot))
        XCTAssertNoThrow(try plan.validateCurrentSnapshot(fixture.snapshot))

        var changedRows = fixture.rows
        changedRows[9] = DiffRow(
            left: DiffLine(number: 10, text: "changed-tail"),
            right: DiffLine(number: 9, text: "tail"),
            kind: .modified
        )
        let changedRowsSnapshot = try makeFixture(
            rows: changedRows,
            selection: fixture.snapshot.selection
        ).snapshot
        assertWorkflowError(.comparisonRowsChanged) {
            try plan.validateCurrentSnapshot(changedRowsSnapshot)
        }
    }

    func testReplayAndCrossPlanReceiptsCannotBeReused() async throws {
        let snapshot = try makeFixture().snapshot
        let firstPlan = try Workflow.plan(
            intent: intent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let secondPlan = try Workflow.plan(
            intent: intent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = MergeWorkflowTestOwner(snapshot: snapshot)
        let firstReceipt = try await owner.commit(firstPlan)

        await assertAsyncWorkflowError(
            .staleSourceRevision(
                expected: snapshot.sourceReference.revision,
                actual: firstPlan.transaction.successorSource.revision
            )
        ) {
            try await owner.commit(firstPlan)
        }
        XCTAssertNotEqual(firstPlan.transaction.id.nonce, secondPlan.transaction.id.nonce)
        XCTAssertNotEqual(firstPlan.reference, secondPlan.reference)

        let intent = secondPlan.transaction.successorComparisonPublication
        let evidence = MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence(
            comparedSource: intent.expectedSource,
            comparedSourceContents: intent.expectedSourceContents,
            comparedInvalidatedComparison: intent.expectedInvalidatedComparison,
            comparedComparisonOptions: intent.expectedComparisonOptions,
            comparedComparisonOptionsGeneration: intent.expectedComparisonOptionsGeneration,
            publishedComparison: intent.successor
        )
        assertWorkflowError(.invalidCommitReceipt) {
            try MultiDifferenceMergeWorkflowPublicationReceipt
                .executorAttestedSuccessorComparisonPublished(
                    plan: secondPlan,
                    commitReceipt: firstReceipt,
                    evidence: evidence
                )
        }
    }

    func testPostCommitFailureCannotHideCompletedPrefixAndUncertaintyStaysExact() async throws {
        let snapshot = try makeFixture().snapshot
        let plan = try Workflow.plan(
            intent: intent(.leftToRight, .advanceToNextDifference),
            in: snapshot
        )
        let owner = MergeWorkflowTestOwner(snapshot: snapshot)
        let commitReceipt = try await owner.commit(plan)

        assertWorkflowError(.invalidExecutionOutcome) {
            try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.failed(
                plan: plan,
                completedEffectCount: 1,
                commitReceipt: commitReceipt,
                reason: .cancelled
            )
        }
        let uncertain = try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.uncertain(
            plan: plan,
            completedEffectCount: 1,
            uncertainEffectIndices: [1],
            commitReceipt: commitReceipt,
            reason: .publicationStateUnknown
        )
        guard case .uncertain(let receipt) = uncertain else {
            return XCTFail("Expected uncertain execution")
        }
        XCTAssertEqual(receipt.completedEffects, [.commitOwnerTransaction])
        XCTAssertEqual(receipt.uncertainEffects, [plan.requiredEffects[1]])
        XCTAssertEqual(receipt.unattemptedEffects, [plan.requiredEffects[2]])
        XCTAssertEqual(receipt.reason, .publicationStateUnknown)
        XCTAssertEqual(receipt.commitReceipt, commitReceipt)
    }

    func testWorkLimitIsExactAndPublicWorkObservesPreCancellation() async throws {
        let snapshot = try makeFixture().snapshot
        let baseline = try Workflow.plan(intent: intent(.leftToRight, .remain), in: snapshot)
        let consumed = baseline.receipt.workflowWorkUnitsConsumed
        XCTAssertGreaterThan(consumed, 0)

        let exact = try Workflow.plan(
            intent: intent(.leftToRight, .remain),
            in: snapshot,
            limits: limits(
                maximumWorkUnits: consumed,
                selection: MultiDifferenceSelectionLimits(maximumWork: Int(consumed)),
                merge: MultiDifferenceMergeOptions(maximumWork: Int(consumed))
            )
        )
        XCTAssertEqual(exact.receipt.workflowWorkUnitsConsumed, consumed)
        assertWorkflowError(.workLimitExceeded(maximumUnits: consumed - 1)) {
            try Workflow.plan(
                intent: self.intent(.leftToRight, .remain),
                in: snapshot,
                limits: self.limits(
                    maximumWorkUnits: consumed - 1,
                    selection: MultiDifferenceSelectionLimits(maximumWork: Int(consumed - 1)),
                    merge: MultiDifferenceMergeOptions(maximumWork: Int(consumed - 1))
                )
            )
        }

        await assertPreCancelled {
            try Workflow.commandState(
                for: MultiDifferenceMergeWorkflowCommandIntent(
                    direction: .leftToRight,
                    advance: .remain
                ),
                in: snapshot
            )
        }
        await assertPreCancelled {
            try Workflow.plan(
                intent: MultiDifferenceMergeWorkflowCommandIntent(
                    direction: .leftToRight,
                    advance: .remain
                ),
                in: snapshot
            )
        }

        let owner = MergeWorkflowTestOwner(snapshot: snapshot)
        await assertPreCancelled {
            try await owner.commit(baseline)
        }
        let ownerState = await owner.state()
        XCTAssertEqual(ownerState.compareCount, 0)
    }

    func testPlanningReceiptsAreDeterministicExceptTransactionNonce() throws {
        let snapshot = try makeFixture().snapshot
        let first = try Workflow.plan(intent: intent(.leftToRight, .remain), in: snapshot)
        let second = try Workflow.plan(intent: intent(.leftToRight, .remain), in: snapshot)

        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.primitiveInvocation, second.primitiveInvocation)
        XCTAssertEqual(first.mergeResult, second.mergeResult)
        XCTAssertEqual(first.requiredEffects, second.requiredEffects)
        XCTAssertEqual(first.limits, second.limits)
        XCTAssertNotEqual(first.transaction.id.nonce, second.transaction.id.nonce)
        XCTAssertEqual(first.receipt.resultUTF8ByteCount, utf8Count(first.mergeResult.snapshot))
        XCTAssertGreaterThanOrEqual(
            first.receipt.retainedUTF8ByteEstimate,
            first.receipt.resultUTF8ByteCount
        )
    }

    func testPublicPlanningReceiptRenderingsRedactRetainedContents() throws {
        let secret = "merge-workflow-secret-canary"
        let source = ComparisonSnapshot(
            left: lines(
                "same-0", "left-a", "left-extra", "same-1", secret, "same-2",
                "left-c", "same-3", "next", "tail"
            ),
            right: lines(
                "same-0", "right-a", "same-1", "right-b", "same-2", "right-c",
                "same-3", "next", "tail"
            )
        )
        let snapshot = try makeFixture(source: source).snapshot
        let receipt = try Workflow.plan(
            intent: intent(.leftToRight, .remain),
            in: snapshot
        ).receipt

        let renderings = [
            String(describing: receipt),
            String(reflecting: receipt),
            mirrorRendering(receipt),
            dumpRendering(receipt)
        ]
        for rendering in renderings {
            XCTAssertEqual(
                [rendering.contains(secret), rendering.contains("<redacted>")],
                [false, true]
            )
        }
    }

    private struct Fixture {
        let source: ComparisonSnapshot
        let rows: [DiffRow]
        let options: LineDiffOptions
        let snapshot: MultiDifferenceMergeWorkflowSnapshot
    }

    private func makeFixture(
        comparisonIdentity: MultiDifferenceMergeWorkflowComparisonIdentity = comparisonIdentity(1),
        comparisonRevision: UInt64 = 40,
        sourceIdentity: MultiDifferenceMergeWorkflowSourceIdentity = sourceIdentity(1),
        sourceRevision: UInt64 = 50,
        leftPaneIdentity: MultiDifferenceMergeWorkflowPaneIdentity = paneIdentity(1),
        leftPaneRevision: UInt64 = 60,
        rightPaneIdentity: MultiDifferenceMergeWorkflowPaneIdentity = paneIdentity(2),
        rightPaneRevision: UInt64 = 70,
        selectionIdentity: MultiDifferenceMergeWorkflowSelectionIdentity = selectionIdentity(1),
        selectionRevision: UInt64 = 80,
        source suppliedSource: ComparisonSnapshot? = nil,
        rows suppliedRows: [DiffRow]? = nil,
        options: LineDiffOptions? = nil,
        selectionRange: Range<Int> = 2..<7,
        selection suppliedSelection: MultiDifferenceSelection? = nil,
        left: MergeCommandPolicy.SideState = MergeCommandPolicy.SideState(
            isLoaded: true,
            isEditable: true,
            isDirty: false
        ),
        right: MergeCommandPolicy.SideState = MergeCommandPolicy.SideState(
            isLoaded: true,
            isEditable: true,
            isDirty: false
        ),
        comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle = .currentSuccess,
        nextLeft: String = "next",
        nextRight: String = "next"
    ) throws -> Fixture {
        let source =
            suppliedSource
            ?? ComparisonSnapshot(
                left: lines(
                    "same-0", "left-a", "left-extra", "same-1", "left-b", "same-2",
                    "left-c", "same-3", nextLeft, "tail"
                ),
                right: lines(
                    "same-0", "right-a", "same-1", "right-b", "same-2", "right-c",
                    "same-3", nextRight, "tail"
                )
            )
        let options =
            options
            ?? LineDiffOptions(
                algorithm: .minimal,
                ignoreLineEndings: false,
                lineFilters: [LineFilterRule(pattern: "DO-NOT-MATCH")],
                substitutions: [SubstitutionRule(pattern: "NEVER", replacement: "MATCH")]
            )
        let rows =
            try suppliedRows
            ?? LineDiff.compare(
                left: source.left,
                right: source.right,
                options: options
            )
        let selection =
            try suppliedSelection
            ?? MultiDifferenceSelection(
                rows: rows,
                rowRange: selectionRange
            )
        let snapshot = MultiDifferenceMergeWorkflowSnapshot(
            comparisonIdentity: comparisonIdentity,
            comparisonRevision: comparisonRevision,
            sourceIdentity: sourceIdentity,
            sourceRevision: sourceRevision,
            leftPaneRevision: MultiDifferenceMergeWorkflowPaneRevision(
                identity: leftPaneIdentity,
                revision: leftPaneRevision
            ),
            rightPaneRevision: MultiDifferenceMergeWorkflowPaneRevision(
                identity: rightPaneIdentity,
                revision: rightPaneRevision
            ),
            selectionIdentity: selectionIdentity,
            selectionRevision: selectionRevision,
            source: source,
            comparisonRows: rows,
            comparisonOptions: options,
            selection: selection,
            left: left,
            right: right,
            comparisonLifecycle: comparisonLifecycle
        )
        return Fixture(source: source, rows: rows, options: options, snapshot: snapshot)
    }

    private func limits(
        _ base: MultiDifferenceMergeWorkflowLimits = .default,
        maximumComparisonRows: Int? = nil,
        maximumSelectedRows: Int? = nil,
        maximumDifferenceGroups: Int? = nil,
        maximumComparisonOptionItems: Int? = nil,
        maximumComparisonOptionStringUTF8Bytes: Int? = nil,
        maximumComparisonOptionsUTF8Bytes: Int? = nil,
        maximumInputUTF8Bytes: Int? = nil,
        maximumRetainedUTF8Bytes: Int? = nil,
        maximumWorkUnits: UInt64? = nil,
        cancellationCheckInterval: UInt64? = nil,
        selection: MultiDifferenceSelectionLimits? = nil,
        merge: MultiDifferenceMergeOptions? = nil
    ) -> MultiDifferenceMergeWorkflowLimits {
        MultiDifferenceMergeWorkflowLimits(
            maximumComparisonRows: maximumComparisonRows ?? base.maximumComparisonRows,
            maximumSelectedRows: maximumSelectedRows ?? base.maximumSelectedRows,
            maximumDifferenceGroups: maximumDifferenceGroups ?? base.maximumDifferenceGroups,
            maximumComparisonOptionItems:
                maximumComparisonOptionItems ?? base.maximumComparisonOptionItems,
            maximumComparisonOptionStringUTF8Bytes:
                maximumComparisonOptionStringUTF8Bytes
                ?? base.maximumComparisonOptionStringUTF8Bytes,
            maximumComparisonOptionsUTF8Bytes:
                maximumComparisonOptionsUTF8Bytes ?? base.maximumComparisonOptionsUTF8Bytes,
            maximumInputUTF8Bytes: maximumInputUTF8Bytes ?? base.maximumInputUTF8Bytes,
            maximumRetainedUTF8Bytes:
                maximumRetainedUTF8Bytes ?? base.maximumRetainedUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits ?? base.maximumWorkUnits,
            cancellationCheckInterval:
                cancellationCheckInterval ?? base.cancellationCheckInterval,
            selection: selection ?? base.selection,
            merge: merge ?? base.merge
        )
    }

    private func intent(
        _ direction: MergeDirection,
        _ advance: MultiDifferenceMergeWorkflowAdvanceIntent
    ) -> MultiDifferenceMergeWorkflowCommandIntent {
        MultiDifferenceMergeWorkflowCommandIntent(direction: direction, advance: advance)
    }

    private func group(
        _ aligned: Range<Int>,
        _ source: Range<Int>,
        _ destination: Range<Int>,
        _ result: Range<Int>
    ) -> MultiDifferenceMergeChangeGroup {
        MultiDifferenceMergeChangeGroup(
            alignedRowRange: aligned,
            sourceLineRange: source,
            destinationLineRange: destination,
            resultDestinationLineRange: result
        )
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

    private func assertPreCancelled<T: Sendable>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @Sendable () async throws -> T
    ) async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await operation()
        }
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled operation unexpectedly succeeded", file: file, line: line)
        } catch let error as WorkflowError {
            XCTAssertEqual(error, .cancelled, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func runCurrentTestSubprocess(
        testName: String,
        environment additions: [String: String]
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["-XCTest", testName, Bundle(for: Self.self).bundleURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

private struct MergeWorkflowOwnerState: Sendable {
    let source: ComparisonSnapshot
    let sourceReference: MultiDifferenceMergeWorkflowSourceReference
    let leftState: MergeCommandPolicy.SideState
    let rightState: MergeCommandPolicy.SideState
    let undoPredecessors: [ComparisonSnapshot]
    let selectionIntent: MultiDifferenceMergeWorkflowSuccessorSelectionIntent?
    let invalidatedComparison: MultiDifferenceMergeWorkflowComparisonReference?
    let consumedTransactions: [MultiDifferenceMergeWorkflowTransactionIdentity]
    let compareCount: Int
    let commitCount: Int
}

private actor MergeWorkflowTestOwner: MultiDifferenceMergeWorkflowAtomicCommitOwner {
    enum EvidenceMode: Sendable {
        case valid
        case invalidSuccessor
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
    private var compareCount = 0
    private var commitCount = 0
    private let evidenceMode: EvidenceMode

    init(
        snapshot: MultiDifferenceMergeWorkflowSnapshot,
        evidenceMode: EvidenceMode = .valid
    ) {
        current = snapshot
        source = snapshot.source
        sourceReference = snapshot.sourceReference
        leftState = snapshot.left
        rightState = snapshot.right
        self.evidenceMode = evidenceMode
    }

    func commit(
        _ plan: MultiDifferenceMergeWorkflowPlan
    ) throws -> MultiDifferenceMergeWorkflowCommitReceipt {
        try plan.commit(to: self)
    }

    func compareAndCommit(
        _ transaction: MultiDifferenceMergeWorkflowTransaction
    ) -> MultiDifferenceMergeWorkflowAtomicCommitOutcome {
        compareCount += 1
        guard current == transaction.expectedState,
            sourceReference == transaction.expectedSource,
            sourceReference[transaction.destination] == transaction.expectedDestinationRevision,
            !consumedTransactions.contains(transaction.id)
        else {
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
        commitCount += 1

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
            committedSuccessor: evidenceMode == .valid
                ? transaction.successor
                : transaction.predecessor,
            destinationState: transaction.successorDestinationState,
            recordedUndoPredecessor: transaction.predecessor,
            committedSelectionIntent: transaction.successorSelectionIntent,
            invalidatedComparison: transaction.expectedState.comparisonReference
        )
        return .committed(evidence)
    }

    func state() -> MergeWorkflowOwnerState {
        MergeWorkflowOwnerState(
            source: source,
            sourceReference: sourceReference,
            leftState: leftState,
            rightState: rightState,
            undoPredecessors: undoPredecessors,
            selectionIntent: selectionIntent,
            invalidatedComparison: invalidatedComparison,
            consumedTransactions: consumedTransactions,
            compareCount: compareCount,
            commitCount: commitCount
        )
    }
}

private func lines(_ values: String...) -> String {
    values.joined(separator: "\n")
}

private func rowID(_ left: Int?, _ right: Int?) -> DiffRow.ID {
    DiffRow.ID(leftNumber: left, rightNumber: right)
}

private func utf8Count(_ snapshot: ComparisonSnapshot) -> Int {
    snapshot.left.utf8.count + snapshot.right.utf8.count
}

private func comparisonIdentity(_ value: UInt8) -> MultiDifferenceMergeWorkflowComparisonIdentity {
    MultiDifferenceMergeWorkflowComparisonIdentity(rawValue: fixedUUID(value))
}

private func sourceIdentity(_ value: UInt8) -> MultiDifferenceMergeWorkflowSourceIdentity {
    MultiDifferenceMergeWorkflowSourceIdentity(rawValue: fixedUUID(value &+ 32))
}

private func selectionIdentity(_ value: UInt8) -> MultiDifferenceMergeWorkflowSelectionIdentity {
    MultiDifferenceMergeWorkflowSelectionIdentity(rawValue: fixedUUID(value &+ 64))
}

private func paneIdentity(_ value: UInt8) -> MultiDifferenceMergeWorkflowPaneIdentity {
    MultiDifferenceMergeWorkflowPaneIdentity(rawValue: fixedUUID(value &+ 96))
}

private func fixedUUID(_ value: UInt8) -> UUID {
    UUID(
        uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
}

private func mirrorRendering(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    return mirror.children.map { child in
        "\(child.label ?? "_")=\(String(reflecting: child.value))"
    }.joined(separator: ",")
}

private func dumpRendering(_ value: Any) -> String {
    var output = ""
    dump(value, to: &output)
    return output
}
