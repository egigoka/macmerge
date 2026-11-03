import Foundation
import MacMergeCore
import XCTest

final class SelectedLinesCopyWorkflowTests: XCTestCase {
    func testAliasResolvesDirectionAndAdvanceBothWays() {
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyToRight.direction, .leftToRight)
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyToRightAndAdvance.direction, .leftToRight)
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyFromLeft.direction, .leftToRight)
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyToLeft.direction, .rightToLeft)
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyToLeftAndAdvance.direction, .rightToLeft)
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyFromRight.direction, .rightToLeft)

        XCTAssertTrue(SelectedLinesCopyWorkflowAlias.copyToRightAndAdvance.advancesSelection)
        XCTAssertTrue(SelectedLinesCopyWorkflowAlias.copyToLeftAndAdvance.advancesSelection)
        XCTAssertFalse(SelectedLinesCopyWorkflowAlias.copyToRight.advancesSelection)
        XCTAssertFalse(SelectedLinesCopyWorkflowAlias.copyToLeft.advancesSelection)
        XCTAssertFalse(SelectedLinesCopyWorkflowAlias.copyFromLeft.advancesSelection)
        XCTAssertFalse(SelectedLinesCopyWorkflowAlias.copyFromRight.advancesSelection)

        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyToRightAndAdvance.workflowIntent.advance,
            .advanceToNextDifference
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyToLeftAndAdvance.workflowIntent.advance,
            .advanceToNextDifference
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyToRight.workflowIntent,
            MultiDifferenceMergeWorkflowCommandIntent(direction: .leftToRight, advance: .remain)
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyFromRight.workflowIntent,
            MultiDifferenceMergeWorkflowCommandIntent(direction: .rightToLeft, advance: .remain)
        )
    }

    func testAliasCanonicalizesCopyFromAndKeepsWinMergeCommandIDs() {
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyFromLeft.canonicalAlias,
            .copyToRight
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyFromRight.canonicalAlias,
            .copyToLeft
        )
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyToRight.canonicalAlias, .copyToRight)
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyToRightAndAdvance.canonicalAlias,
            .copyToRightAndAdvance
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyToRight.winMergeCommandID,
            "ID_L2R"
        )
        XCTAssertEqual(SelectedLinesCopyWorkflowAlias.copyToLeft.winMergeCommandID, "ID_R2L")
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyToRightAndAdvance.winMergeCommandID,
            "ID_L2RNEXT"
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyToLeftAndAdvance.winMergeCommandID,
            "ID_R2LNEXT"
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyFromLeft.winMergeCommandID,
            "ID_COPY_FROM_LEFT"
        )
        XCTAssertEqual(
            SelectedLinesCopyWorkflowAlias.copyFromRight.winMergeCommandID,
            "ID_COPY_FROM_RIGHT"
        )
    }

    func testExpansionWidensSingleLineToMaximalGroup() throws {
        let fixture = try makeFixture()
        let expansion = try SelectedLinesCopyWorkflow.expansion(
            in: fixture.snapshot,
            selectedAlignedRows: 2..<3
        )
        XCTAssertEqual(expansion.selectedAlignedRows, 2..<3)
        XCTAssertEqual(expansion.expandedGroups, [1..<3])
        XCTAssertEqual(expansion.expectedComparison, fixture.snapshot.comparisonReference)
    }

    func testExpansionSpanningUnchangedGapReturnsGroupsInOrder() throws {
        let fixture = try makeFixture()
        let expansion = try SelectedLinesCopyWorkflow.expansion(
            in: fixture.snapshot,
            selectedAlignedRows: 2..<7
        )
        XCTAssertEqual(expansion.expandedGroups, [1..<3, 4..<5, 6..<7])
        let plan = try SelectedLinesCopyWorkflow.plan(
            for: .copyToRight,
            in: fixture.snapshot,
            selectedAlignedRows: 2..<7
        )
        XCTAssertEqual(plan.direction, .leftToRight)
        XCTAssertEqual(plan.expansion, expansion)
        XCTAssertEqual(plan.expectedSnapshot, fixture.snapshot.reference)
    }

    func testExpansionRejectsEmptyOutOfBoundsAndCleanSelections() throws {
        let fixture = try makeFixture()
        assertSelectedLinesError(.emptySelection) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 3..<3
            )
        }
        assertSelectedLinesError(
            .selectionOutOfBounds(
                requested: 0..<(fixture.rows.count + 1),
                rowCount: fixture.rows.count
            )
        ) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 0..<(fixture.rows.count + 1)
            )
        }
        let clean = try XCTUnwrap(
            fixture.rows.indices.first(where: { fixture.rows[$0].kind == .unchanged })
        )
        assertSelectedLinesError(.noSignificantDifferences) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: clean..<(clean + 1)
            )
        }
    }

    func testExpansionRejectsStaleComparisonIdentitySourceAndRevision() throws {
        let fixture = try makeFixture()
        let otherIdentity = MultiDifferenceMergeWorkflowComparisonReference(
            identity: MultiDifferenceMergeWorkflowComparisonIdentity(),
            revision: fixture.snapshot.comparisonReference.revision,
            source: fixture.snapshot.comparisonReference.source
        )
        assertSelectedLinesError(.staleComparisonIdentity) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                expectedComparison: otherIdentity
            )
        }
        var tamperedSource = fixture.snapshot.comparisonReference.source
        tamperedSource = MultiDifferenceMergeWorkflowSourceReference(
            identity: MultiDifferenceMergeWorkflowSourceIdentity(),
            revision: tamperedSource.revision,
            left: tamperedSource.left,
            right: tamperedSource.right
        )
        let tampered = MultiDifferenceMergeWorkflowComparisonReference(
            identity: fixture.snapshot.comparisonReference.identity,
            revision: fixture.snapshot.comparisonReference.revision,
            source: tamperedSource
        )
        assertSelectedLinesError(.staleComparisonIdentity) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                expectedComparison: tampered
            )
        }
        let revised = MultiDifferenceMergeWorkflowComparisonReference(
            identity: fixture.snapshot.comparisonReference.identity,
            revision: fixture.snapshot.comparisonReference.revision + 1,
            source: fixture.snapshot.comparisonReference.source
        )
        assertSelectedLinesError(
            .staleComparisonRevision(
                expected: revised.revision,
                actual: fixture.snapshot.comparisonReference.revision
            )
        ) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                expectedComparison: revised
            )
        }
    }

    func testExpansionRejectsRowIdentityMismatch() throws {
        let fixture = try makeFixture()
        var ids = fixture.rows[2..<3].map(\.id)
        ids[0] = DiffRow.ID(leftNumber: 999_001, rightNumber: 999_002)
        assertSelectedLinesError(.rowIdentityMismatch) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                selectedRowIDs: ids
            )
        }
    }

    func testPlanFailsClosedWhenSnapshotSelectionDrifted() throws {
        let fixture = try makeFixture()
        assertSelectedLinesError(.selectionChanged) {
            try SelectedLinesCopyWorkflow.plan(
                for: .copyToRight,
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3
            )
        }
        let drifted = try makeFixture(selectionRange: 1..<7)
        assertSelectedLinesError(.selectionChanged) {
            try SelectedLinesCopyWorkflow.plan(
                for: .copyToRight,
                in: drifted.snapshot,
                selectedAlignedRows: 2..<7
            )
        }
    }

    func testPlanRejectsConfiguredSizeAndLimitBoundaries() throws {
        let fixture = try makeFixture()
        assertSelectedLinesError(.tooManySelectedLines(maximum: 1)) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<7,
                limits: SelectedLinesCopyWorkflowLimits(maximumSelectedLines: 1)
            )
        }
        assertSelectedLinesError(.tooManyDifferenceGroups(maximum: 0)) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<7,
                limits: SelectedLinesCopyWorkflowLimits(maximumDifferenceGroups: 0)
            )
        }
        assertSelectedLinesError(
            .tooManyComparisonRows(maximum: fixture.rows.count - 1)
        ) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                limits: SelectedLinesCopyWorkflowLimits(
                    maximumComparisonRows: fixture.rows.count - 1
                )
            )
        }
        assertSelectedLinesError(.invalidLimit("selectedLines")) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                limits: SelectedLinesCopyWorkflowLimits(maximumSelectedLines: -1)
            )
        }
        assertSelectedLinesError(.invalidLimit("workUnits")) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                limits: SelectedLinesCopyWorkflowLimits(
                    maximumWorkUnits: SelectedLinesCopyWorkflowLimits.hardMaximumWorkUnits + 1
                )
            )
        }
        assertSelectedLinesError(.invalidLimit("cancellationCheckInterval")) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                limits: SelectedLinesCopyWorkflowLimits(cancellationCheckInterval: 0)
            )
        }
    }

    func testPlanEnforcesWorkBudget() throws {
        let fixture = try makeFixture()
        assertSelectedLinesError(.workLimitExceeded(maximumUnits: 0)) {
            try SelectedLinesCopyWorkflow.expansion(
                in: fixture.snapshot,
                selectedAlignedRows: 2..<3,
                limits: SelectedLinesCopyWorkflowLimits(maximumWorkUnits: 0)
            )
        }
    }

    func testPreCancelledExpansionReportsCancelled() async {
        let snapshot: MultiDifferenceMergeWorkflowSnapshot
        do {
            snapshot = try makeFixture().snapshot
        } catch {
            return XCTFail("Fixture failed: \(error)")
        }
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SelectedLinesCopyWorkflow.expansion(
                in: snapshot,
                selectedAlignedRows: 2..<3
            )
        }
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled expansion unexpectedly succeeded")
        } catch let error as SelectedLinesCopyWorkflowError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAtomicReceiptChainsPlanningCommitAndPublication() async throws {
        let fixture = try makeFixture()
        let plan = try SelectedLinesCopyWorkflow.plan(
            for: .copyToRightAndAdvance,
            in: fixture.snapshot,
            selectedAlignedRows: 2..<7
        )
        XCTAssertEqual(plan.underlying.receipt.intent.advance, .advanceToNextDifference)
        let owner = SelectedLinesCopyTestOwner(snapshot: fixture.snapshot)
        let commitReceipt = try await owner.commit(plan.underlying)
        let publicationIntent = plan.underlying.transaction.successorComparisonPublication
        let comparisonReceipt =
            try MultiDifferenceMergeWorkflowPublicationReceipt
            .executorAttestedSuccessorComparisonPublished(
                plan: plan.underlying,
                commitReceipt: commitReceipt,
                evidence: MultiDifferenceMergeWorkflowSuccessorComparisonPublicationEvidence(
                    comparedSource: publicationIntent.expectedSource,
                    comparedSourceContents: publicationIntent.expectedSourceContents,
                    comparedInvalidatedComparison:
                        publicationIntent.expectedInvalidatedComparison,
                    comparedComparisonOptions: publicationIntent.expectedComparisonOptions,
                    comparedComparisonOptionsGeneration:
                        publicationIntent.expectedComparisonOptionsGeneration,
                    publishedComparison: publicationIntent.successor
                )
            )
        let navigationReceipt =
            try MultiDifferenceMergeWorkflowPublicationReceipt
            .executorAttestedNavigationPublished(
                plan: plan.underlying,
                after: comparisonReceipt,
                evidence: MultiDifferenceMergeWorkflowNavigationPublicationEvidence(
                    intent: plan.underlying.transaction.navigationIntent,
                    publishedComparison: plan.underlying.transaction.successorComparison.reference,
                    publishedTarget: plan.underlying.transaction.successorNavigationTarget
                )
            )
        let atomic = try SelectedLinesCopyWorkflowAtomicReceipt.attestCompleted(
            plan: plan,
            commitReceipt: commitReceipt,
            publicationReceipts: [comparisonReceipt, navigationReceipt]
        )
        XCTAssertEqual(atomic.planningReceipt, plan.underlying.receipt)
        XCTAssertEqual(atomic.commitReceipt, commitReceipt)
        XCTAssertEqual(atomic.publicationReceipts, [comparisonReceipt, navigationReceipt])
        XCTAssertEqual(atomic.completedEffects, plan.underlying.requiredEffects)
        XCTAssertEqual(atomic.alias, .copyToRightAndAdvance)
        XCTAssertEqual(atomic.expansion, plan.expansion)
    }

    func testAtomicReceiptRejectsForeignCommitReceipt() async throws {
        let fixture = try makeFixture()
        let plan = try SelectedLinesCopyWorkflow.plan(
            for: .copyToRight,
            in: fixture.snapshot,
            selectedAlignedRows: 2..<7
        )
        let other = try SelectedLinesCopyWorkflow.plan(
            for: .copyToRight,
            in: fixture.snapshot,
            selectedAlignedRows: 2..<7
        )
        let owner = SelectedLinesCopyTestOwner(snapshot: fixture.snapshot)
        let foreignCommit = try await owner.commit(other.underlying)
        XCTAssertThrowsError(
            try SelectedLinesCopyWorkflowAtomicReceipt.attestCompleted(
                plan: plan,
                commitReceipt: foreignCommit,
                publicationReceipts: []
            )
        ) { error in
            XCTAssertEqual(
                error as? SelectedLinesCopyWorkflowError,
                .workflow(.invalidCommitReceipt)
            )
        }
    }

    private struct Fixture {
        let source: ComparisonSnapshot
        let rows: [DiffRow]
        let snapshot: MultiDifferenceMergeWorkflowSnapshot
    }

    private func makeFixture(
        comparisonRevision: UInt64 = 40,
        selectionRange: Range<Int> = 2..<7
    ) throws -> Fixture {
        let source = ComparisonSnapshot(
            left: lines(
                "same-0", "left-a", "left-extra", "same-1", "left-b", "same-2",
                "left-c", "same-3", "next", "tail"
            ),
            right: lines(
                "same-0", "right-a", "same-1", "right-b", "same-2", "right-c",
                "same-3", "next", "tail"
            )
        )
        let rows = try LineDiff.compare(
            left: source.left,
            right: source.right,
            options: LineDiffOptions()
        )
        let selection = try MultiDifferenceSelection(rows: rows, rowRange: selectionRange)
        let leftPane = MultiDifferenceMergeWorkflowPaneRevision(
            identity: paneIdentity(1),
            revision: 60
        )
        let rightPane = MultiDifferenceMergeWorkflowPaneRevision(
            identity: paneIdentity(2),
            revision: 70
        )
        let snapshot = MultiDifferenceMergeWorkflowSnapshot(
            comparisonIdentity: comparisonIdentity(1),
            comparisonRevision: comparisonRevision,
            sourceIdentity: sourceIdentity(1),
            sourceRevision: 50,
            leftPaneRevision: leftPane,
            rightPaneRevision: rightPane,
            selectionIdentity: selectionIdentity(1),
            selectionRevision: 80,
            source: source,
            comparisonRows: rows,
            comparisonOptions: LineDiffOptions(),
            selection: selection,
            left: MergeCommandPolicy.SideState(isLoaded: true, isEditable: true, isDirty: false),
            right: MergeCommandPolicy.SideState(isLoaded: true, isEditable: true, isDirty: false),
            comparisonLifecycle: .currentSuccess
        )
        return Fixture(source: source, rows: rows, snapshot: snapshot)
    }

    private func assertSelectedLinesError(
        _ expected: SelectedLinesCopyWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> some Any
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? SelectedLinesCopyWorkflowError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private actor SelectedLinesCopyTestOwner: MultiDifferenceMergeWorkflowAtomicCommitOwner {
    private var current: MultiDifferenceMergeWorkflowSnapshot

    init(snapshot: MultiDifferenceMergeWorkflowSnapshot) {
        current = snapshot
    }

    func commit(
        _ plan: MultiDifferenceMergeWorkflowPlan
    ) throws -> MultiDifferenceMergeWorkflowCommitReceipt {
        try plan.commit(to: self)
    }

    func compareAndCommit(
        _ transaction: MultiDifferenceMergeWorkflowTransaction
    ) -> MultiDifferenceMergeWorkflowAtomicCommitOutcome {
        guard current == transaction.expectedState else {
            return .notCommitted(currentSnapshot: current)
        }
        let compared = current
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
            left: transaction.expectedState.left,
            right: transaction.expectedState.right,
            comparisonLifecycle: .stale
        )
        return .committed(
            MultiDifferenceMergeWorkflowOwnerCommitEvidence(
                transactionID: transaction.id,
                comparedExpectedState: compared,
                comparedDestinationRevision: transaction.expectedDestinationRevision,
                successorSource: transaction.successorSource,
                successorDestinationRevision: transaction.successorDestinationRevision,
                committedSuccessor: transaction.successor,
                destinationState: transaction.successorDestinationState,
                recordedUndoPredecessor: transaction.predecessor,
                committedSelectionIntent: transaction.successorSelectionIntent,
                invalidatedComparison: transaction.expectedState.comparisonReference
            )
        )
    }
}

private func lines(_ values: String...) -> String {
    values.joined(separator: "\n")
}

private func comparisonIdentity(
    _ value: UInt8
) -> MultiDifferenceMergeWorkflowComparisonIdentity {
    MultiDifferenceMergeWorkflowComparisonIdentity(rawValue: fixedUUID(value))
}

private func sourceIdentity(
    _ value: UInt8
) -> MultiDifferenceMergeWorkflowSourceIdentity {
    MultiDifferenceMergeWorkflowSourceIdentity(rawValue: fixedUUID(value &+ 32))
}

private func selectionIdentity(
    _ value: UInt8
) -> MultiDifferenceMergeWorkflowSelectionIdentity {
    MultiDifferenceMergeWorkflowSelectionIdentity(rawValue: fixedUUID(value &+ 64))
}

private func paneIdentity(
    _ value: UInt8
) -> MultiDifferenceMergeWorkflowPaneIdentity {
    MultiDifferenceMergeWorkflowPaneIdentity(rawValue: fixedUUID(value &+ 96))
}

private func fixedUUID(_ value: UInt8) -> UUID {
    UUID(
        uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        )
    )
}
