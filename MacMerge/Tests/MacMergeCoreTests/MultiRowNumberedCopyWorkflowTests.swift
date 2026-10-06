import Foundation
import MacMergeCore
import XCTest

final class MultiRowNumberedCopyWorkflowTests: XCTestCase {
    private typealias Workflow = MultiRowNumberedCopyWorkflow
    private typealias WorkflowError = MultiRowNumberedCopyWorkflowError
    private typealias Limits = MultiRowNumberedCopyWorkflowLimits

    func testExpandedRangesPassesThroughOrderedRanges() throws {
        XCTAssertEqual(try Workflow.expandedRanges([0..<1, 1..<3], rowCount: 4), [0..<1, 1..<3])
        XCTAssertEqual(try Workflow.expandedRanges([0..<4], rowCount: 4), [0..<4])
    }

    func testExpandedRangesCoalescesIndexSetSelection() throws {
        XCTAssertEqual(
            try Workflow.expandedRanges(IndexSet([0, 1, 3]), rowCount: 4),
            [0..<2, 3..<4]
        )
        XCTAssertEqual(
            try Workflow.expandedRanges(IndexSet(integersIn: 0..<3), rowCount: 4),
            [0..<3]
        )
    }

    func testRowContextSelectionResolvesRangesAndIndexSet() throws {
        XCTAssertEqual(
            try Workflow.resolveRowContextSelection(explicitRanges: [0..<1, 2..<3], rowCount: 4),
            [0..<1, 2..<3]
        )
        XCTAssertEqual(
            try Workflow.resolveRowContextSelection(explicitSelection: IndexSet([0, 2]), rowCount: 4),
            [0..<1, 2..<3]
        )
    }

    func testEditMenuSelectionPrefersExplicitOverFocusedRow() throws {
        XCTAssertEqual(
            try Workflow.resolveEditMenuSelection(explicitRanges: [1..<3], focusedRow: 0, rowCount: 4),
            [1..<3]
        )
        XCTAssertEqual(
            try Workflow.resolveEditMenuSelection(
                explicitSelection: IndexSet([0, 2]),
                focusedRow: 3,
                rowCount: 4
            ),
            [0..<1, 2..<3]
        )
    }

    func testCommandStateEnabledForBothSides() throws {
        let snapshot = try makeSnapshot()
        let leftIntent = WorkflowIntent(side: .left)
        XCTAssertEqual(leftIntent.style, .numbered)
        XCTAssertEqual(leftIntent.origin, .editMenu)
        XCTAssertEqual(WorkflowSide.left.pane, .left)
        XCTAssertEqual(WorkflowSide.left.numberedCopySide, .left)
        XCTAssertEqual(WorkflowSide.right.numberedCopySide, .right)

        let left = try Workflow.commandState(for: leftIntent, in: snapshot)
        XCTAssertTrue(left.isEnabled)
        XCTAssertTrue(left.canExecute)
        XCTAssertNil(left.disabledReason)
        XCTAssertEqual(left.expectedSnapshot, snapshot.reference)
        XCTAssertEqual(left.selection, snapshot.selection)
        XCTAssertGreaterThan(left.workUnitsConsumed, 0)

        let right = try Workflow.commandState(for: WorkflowIntent(side: .right), in: snapshot)
        XCTAssertTrue(right.isEnabled)
        XCTAssertNil(right.disabledReason)
    }

    func testCommandStateDisabledWhenComparisonNotCurrent() throws {
        let snapshot = try makeSnapshot(lifecycle: .loading)
        for side in [WorkflowSide.left, WorkflowSide.right] {
            let state = try Workflow.commandState(for: WorkflowIntent(side: side), in: snapshot)
            XCTAssertFalse(state.isEnabled)
            XCTAssertFalse(state.canExecute)
            XCTAssertEqual(state.disabledReason, .comparisonNotCurrent)
        }
    }

    func testCommandStateDisabledWhenSourceNotLoaded() throws {
        let unloaded = SideState(isLoaded: false, isEditable: true, isDirty: false)
        let snapshot = try makeSnapshot(left: unloaded)
        let left = try Workflow.commandState(for: WorkflowIntent(side: .left), in: snapshot)
        XCTAssertFalse(left.isEnabled)
        XCTAssertEqual(left.disabledReason, .sourceNotLoaded(.left))

        let right = try Workflow.commandState(for: WorkflowIntent(side: .right), in: snapshot)
        XCTAssertTrue(right.isEnabled)
    }

    func testCommandStateDisabledWhenSideHasNoCopyableLines() throws {
        let leftMissing = try makeSnapshot(rows: makeRows(3, missingSide: .left))
        let leftState = try Workflow.commandState(for: WorkflowIntent(side: .left), in: leftMissing)
        XCTAssertFalse(leftState.isEnabled)
        XCTAssertEqual(leftState.disabledReason, .noCopyableSourceLines(.left))
        let rightState = try Workflow.commandState(for: WorkflowIntent(side: .right), in: leftMissing)
        XCTAssertTrue(rightState.isEnabled)

        let rightMissing = try makeSnapshot(rows: makeRows(3, missingSide: .right))
        let disabled = try Workflow.commandState(for: WorkflowIntent(side: .right), in: rightMissing)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(disabled.disabledReason, .noCopyableSourceLines(.right))
    }

    func testEditMenuSelectionFallsBackToFocusedRowFromEmptyRanges() throws {
        XCTAssertEqual(
            try Workflow.resolveEditMenuSelection(explicitRanges: [], focusedRow: 1, rowCount: 4),
            [1..<2]
        )
        XCTAssertEqual(
            try Workflow.resolveEditMenuSelection(explicitRanges: [], focusedRow: 0, rowCount: 1),
            [0..<1]
        )
    }

    func testEditMenuSelectionWithEmptyIndexSetThrowsInsteadOfFallingBack() {
        assertWorkflowError(.emptySelection) {
            try Workflow.resolveEditMenuSelection(
                explicitSelection: IndexSet(),
                focusedRow: 1,
                rowCount: 4
            )
        }
    }

    func testEditMenuSelectionRejectsMissingFocusAndOutOfBoundsFocus() {
        assertWorkflowError(.emptySelection) {
            try Workflow.resolveEditMenuSelection(explicitRanges: [], focusedRow: nil, rowCount: 4)
        }
        assertWorkflowError(.invalidFocusedRow(99)) {
            try Workflow.resolveEditMenuSelection(explicitRanges: [], focusedRow: 99, rowCount: 4)
        }
        assertWorkflowError(.invalidFocusedRow(-1)) {
            try Workflow.resolveEditMenuSelection(explicitRanges: [], focusedRow: -1, rowCount: 4)
        }
        assertWorkflowError(.invalidFocusedRow(0)) {
            try Workflow.resolveEditMenuSelection(explicitRanges: [], focusedRow: 0, rowCount: 0)
        }
    }

    func testExpandedRangesEnforcesMaximumSelectedRanges() throws {
        let limits = Limits(maximumSelectedRanges: 1)
        assertWorkflowError(.tooManySelectedRanges(maximum: 1)) {
            try Workflow.expandedRanges([0..<1, 2..<3], rowCount: 4, limits: limits)
        }
        assertWorkflowError(.tooManySelectedRanges(maximum: 1)) {
            try Workflow.expandedRanges(IndexSet([0, 2]), rowCount: 4, limits: limits)
        }
        XCTAssertEqual(
            try Workflow.expandedRanges([0..<2], rowCount: 4, limits: limits),
            [0..<2]
        )
    }

    func testPlanEnforcesSelectedRowsBoundary() throws {
        let snapshot = try makeSnapshot(selectedRanges: [0..<2])
        let exact = Limits(maximumSelectedRows: 2)
        let state = try Workflow.commandState(for: WorkflowIntent(side: .left), in: snapshot, limits: exact)
        XCTAssertTrue(state.isEnabled)
        assertWorkflowError(.tooManySelectedRows(maximum: 1)) {
            try Workflow.commandState(
                for: WorkflowIntent(side: .left),
                in: snapshot,
                limits: Limits(maximumSelectedRows: 1)
            )
        }
        assertWorkflowError(.tooManySelectedRows(maximum: 1)) {
            try Workflow.plan(
                intent: WorkflowIntent(side: .left),
                in: snapshot,
                limits: Limits(maximumSelectedRows: 1)
            )
        }
    }

    func testSnapshotRejectsOutOfBoundsAndEmptyRanges() {
        assertWorkflowError(.invalidSelectionRange(requested: 0..<0, rowCount: 4)) {
            try Workflow.expandedRanges([0..<0], rowCount: 4)
        }
        assertWorkflowError(.invalidSelectionRange(requested: -1..<2, rowCount: 4)) {
            try Workflow.expandedRanges([-1..<2], rowCount: 4)
        }
        assertWorkflowError(.invalidSelectionRange(requested: 2..<99, rowCount: 4)) {
            try Workflow.expandedRanges([2..<99], rowCount: 4)
        }
        assertWorkflowError(.invalidSelectionRange(requested: 4..<5, rowCount: 4)) {
            try makeSnapshot(selectedRanges: [4..<5])
        }
    }

    func testSnapshotRejectsUnorderedOrOverlappingRanges() throws {
        assertWorkflowError(.unorderedOrOverlappingSelection(selectionIndex: 1)) {
            try Workflow.expandedRanges([2..<3, 0..<1], rowCount: 4)
        }
        assertWorkflowError(.unorderedOrOverlappingSelection(selectionIndex: 1)) {
            try Workflow.expandedRanges([0..<2, 1..<3], rowCount: 4)
        }
        XCTAssertEqual(try Workflow.expandedRanges([0..<1, 1..<2], rowCount: 4), [0..<1, 1..<2])
    }

    func testEmptySelectionThrowsFromEveryEntryPoint() {
        assertWorkflowError(.emptySelection) {
            try Workflow.expandedRanges([], rowCount: 4)
        }
        assertWorkflowError(.emptySelection) {
            try Workflow.expandedRanges(IndexSet(), rowCount: 4)
        }
        assertWorkflowError(.emptySelection) {
            try Workflow.resolveRowContextSelection(explicitRanges: [], rowCount: 4)
        }
        assertWorkflowError(.emptySelection) {
            try makeSnapshot(selectedRanges: [])
        }
    }

    func testSnapshotCASMatchesCurrentAndDetectsStaleChanges() throws {
        let ids = FixtureIDs()
        let base = try makeSnapshot(ids: ids)
        let plan = try Workflow.plan(intent: WorkflowIntent(side: .left), in: base)
        XCTAssertEqual(plan.expectedSnapshot, base.reference)
        XCTAssertTrue(try plan.expectedSnapshotCAS.matches(base))
        try plan.validateCurrentSnapshot(base)

        let bumped = try makeSnapshot(ids: ids, comparisonRevision: 2)
        XCTAssertFalse(try plan.expectedSnapshotCAS.matches(bumped))
        assertWorkflowError(.staleComparisonRevision(expected: 1, actual: 2)) {
            try plan.validateCurrentSnapshot(bumped)
        }

        let mutated = try makeSnapshot(rows: makeRows(4, textSuffix: "-changed"), ids: ids)
        XCTAssertFalse(try plan.expectedSnapshotCAS.matches(mutated))
        assertWorkflowError(.comparisonRowsChanged) {
            try plan.validateCurrentSnapshot(mutated)
        }
    }

    func testPlanValidatesSelectionLifecycleSideStateAndPaneIdentities() throws {
        var ids = FixtureIDs()
        let base = try makeSnapshot(ids: ids)
        let plan = try Workflow.plan(intent: WorkflowIntent(side: .left), in: base)

        let reselected = try makeSnapshot(selectedRanges: [0..<1], ids: ids)
        assertWorkflowError(.selectionChanged) {
            try plan.validateCurrentSnapshot(reselected)
        }

        let staleLifecycle = try makeSnapshot(lifecycle: .stale, ids: ids)
        assertWorkflowError(.comparisonLifecycleChanged) {
            try plan.validateCurrentSnapshot(staleLifecycle)
        }

        let dirtyLeft = try makeSnapshot(
            left: SideState(isLoaded: true, isEditable: true, isDirty: true),
            ids: ids
        )
        assertWorkflowError(.sideStateChanged(.left)) {
            try plan.validateCurrentSnapshot(dirtyLeft)
        }

        ids.rightPane = ids.leftPane
        assertWorkflowError(.stalePaneIdentity(.left)) {
            try Workflow.plan(intent: WorkflowIntent(side: .left), in: try makeSnapshot(ids: ids))
        }
    }

    func testPlanReceiptCapturesIntentSelectionAndCosts() throws {
        let snapshot = try makeSnapshot(selectedRanges: [0..<2])
        let intent = WorkflowIntent(side: .left, style: .numbered, origin: .rowContext)
        let plan = try Workflow.plan(intent: intent, in: snapshot)

        XCTAssertEqual(plan.receipt.intentSide, .left)
        XCTAssertEqual(plan.receipt.intentStyle, .numbered)
        XCTAssertEqual(plan.receipt.intentOrigin, .rowContext)
        XCTAssertEqual(plan.receipt.selectedRowCount, 2)
        XCTAssertEqual(plan.receipt.selectedRangeCount, 1)
        XCTAssertEqual(plan.receipt.selection, snapshot.selection)
        XCTAssertEqual(plan.receipt.expectedSnapshot, snapshot.reference)
        XCTAssertEqual(plan.receipt.payloadUTF8ByteCount, plan.payload.utf8.count)
        XCTAssertGreaterThanOrEqual(plan.receipt.retainedUTF8ByteEstimate, plan.receipt.payloadUTF8ByteCount)
        XCTAssertGreaterThan(plan.receipt.workflowWorkUnitsConsumed, 0)
        XCTAssertFalse(plan.payload.isEmpty)
        XCTAssertEqual(plan.requiredEffects, [.copyPayloadToOwnerTransferService])
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.limits, Limits())
        XCTAssertEqual(plan.selection, snapshot.selection)
        XCTAssertEqual(plan.intent, intent)
        XCTAssertEqual(plan.reference.snapshot, snapshot.reference)
    }

    func testPlanSelectedLinesPayloadJoinsSourceText() throws {
        let rows = [
            DiffRow(left: DiffLine(number: 1, text: "L0"), right: DiffLine(number: 1, text: "R0"), kind: .unchanged),
            DiffRow(left: DiffLine(number: 2, text: "L1"), right: DiffLine(number: 2, text: "R1"), kind: .unchanged),
            DiffRow(left: DiffLine(number: 3, text: "L2"), right: DiffLine(number: 3, text: "R2"), kind: .unchanged)
        ]
        let snapshot = try makeSnapshot(rows: rows, selectedRanges: [0..<2])
        let lines = try Workflow.plan(
            intent: WorkflowIntent(side: .left, style: .selectedLines),
            in: snapshot
        )
        XCTAssertEqual(lines.payload, "L0\nL1")
        XCTAssertEqual(lines.receipt.selectedRowCount, 2)

        let numbered = try Workflow.plan(intent: WorkflowIntent(side: .left), in: snapshot)
        XCTAssertFalse(numbered.payload.isEmpty)
        XCTAssertNotEqual(numbered.payload, lines.payload)
    }

    func testExecutorAttestedCopiedCompletesAndRejectsMismatchedEvidence() throws {
        let snapshot = try makeSnapshot()
        let intent = WorkflowIntent(side: .left, style: .numbered)
        let plan = try Workflow.plan(intent: intent, in: snapshot)
        let evidence = WorkflowCopyEvidence(
            comparedSnapshot: plan.expectedSnapshot,
            copiedSide: .left,
            copiedStyle: .numbered,
            copiedRowCount: plan.receipt.selectedRowCount,
            copiedUTF8ByteCount: plan.receipt.payloadUTF8ByteCount
        )
        let outcome = try Workflow.executorAttestedCopied(plan: plan, evidence: evidence)
        guard case .completed(let receipt) = outcome else {
            return XCTFail("Expected completed outcome")
        }
        XCTAssertEqual(receipt.planningReceipt, plan.receipt)
        XCTAssertEqual(receipt.evidence, evidence)
        XCTAssertEqual(receipt.completedEffects, plan.requiredEffects)
        XCTAssertEqual(receipt.evidence.copiedRowCount, 2)
        XCTAssertEqual(receipt.evidence.copiedSide, .left)

        let wrongSide = WorkflowCopyEvidence(
            comparedSnapshot: plan.expectedSnapshot,
            copiedSide: .right,
            copiedStyle: .numbered,
            copiedRowCount: plan.receipt.selectedRowCount,
            copiedUTF8ByteCount: plan.receipt.payloadUTF8ByteCount
        )
        assertWorkflowError(.invalidCopyEvidence) {
            try Workflow.executorAttestedCopied(plan: plan, evidence: wrongSide)
        }
        let wrongBytes = WorkflowCopyEvidence(
            comparedSnapshot: plan.expectedSnapshot,
            copiedSide: .left,
            copiedStyle: .numbered,
            copiedRowCount: plan.receipt.selectedRowCount,
            copiedUTF8ByteCount: plan.receipt.payloadUTF8ByteCount + 1
        )
        assertWorkflowError(.invalidCopyEvidence) {
            try Workflow.executorAttestedCopied(plan: plan, evidence: wrongBytes)
        }
        let wrongSnapshot = WorkflowCopyEvidence(
            comparedSnapshot: try makeSnapshot().reference,
            copiedSide: .left,
            copiedStyle: .numbered,
            copiedRowCount: plan.receipt.selectedRowCount,
            copiedUTF8ByteCount: plan.receipt.payloadUTF8ByteCount
        )
        assertWorkflowError(.invalidCopyEvidence) {
            try Workflow.executorAttestedCopied(plan: plan, evidence: wrongSnapshot)
        }
    }

    func testFailedOutcomeCarriesReasonAndEmptyCompletedEffects() throws {
        let snapshot = try makeSnapshot()
        let plan = try Workflow.plan(intent: WorkflowIntent(side: .right), in: snapshot)
        for reason in WorkflowFailureReason.allCases {
            let outcome = Workflow.failed(plan: plan, reason: reason)
            guard case .failed(let receipt) = outcome else {
                return XCTFail("Expected failed outcome for \(reason)")
            }
            XCTAssertEqual(receipt.planningReceipt, plan.receipt)
            XCTAssertEqual(receipt.reason, reason)
            XCTAssertEqual(receipt.failedEffect, .copyPayloadToOwnerTransferService)
            XCTAssertEqual(receipt.completedEffects, [])
        }
        XCTAssertEqual(WorkflowFailureReason.allCases.count, 5)
    }

    func testRedactedDescriptionsHideContents() throws {
        let secret = "ZebraQuagga42"
        let rows = [
            DiffRow(
                left: DiffLine(number: 1, text: secret),
                right: DiffLine(number: 1, text: secret),
                kind: .unchanged
            ),
            DiffRow(
                left: DiffLine(number: 2, text: secret),
                right: DiffLine(number: 2, text: secret),
                kind: .unchanged
            )
        ]
        let source = ComparisonSnapshot(left: secret, right: secret)
        let snapshot = try makeSnapshot(rows: rows, selectedRanges: [0..<2], source: source)
        let plan = try Workflow.plan(intent: WorkflowIntent(side: .left), in: snapshot)
        let values: [Any] = [
            snapshot,
            snapshot.selection,
            plan,
            plan.receipt,
            plan.expectedSnapshotCAS,
            Limits()
        ]
        for value in values {
            let rendered = [String(describing: value), String(reflecting: value)]
            XCTAssertTrue(rendered.allSatisfy { $0.contains("<redacted>") }, "\(type(of: value))")
            XCTAssertFalse(rendered.joined().contains(secret), "\(type(of: value)) leaked contents")
        }
        let effect = String(describing: WorkflowRequiredEffect.copyPayloadToOwnerTransferService)
        XCTAssertTrue(effect.contains("<redacted>"))
        XCTAssertFalse(plan.payload.isEmpty)
    }

    func testExpandedRangesMapsCancellationToWorkflowCancelled() async {
        await withTaskGroup(of: WorkflowError?.self) { group in
            group.cancelAll()
            group.addTask {
                do {
                    _ = try Workflow.expandedRanges([0..<1], rowCount: 2)
                    return nil
                } catch let error as WorkflowError {
                    return error
                } catch {
                    return nil
                }
            }
            for await result in group {
                XCTAssertEqual(result, .cancelled)
            }
        }
    }

    func testPlanMapsCancellationToWorkflowCancelled() async throws {
        let snapshot = try makeSnapshot()
        let intent = WorkflowIntent(side: .left)
        await withTaskGroup(of: WorkflowError?.self) { group in
            group.cancelAll()
            group.addTask {
                do {
                    _ = try Workflow.plan(intent: intent, in: snapshot)
                    return nil
                } catch let error as WorkflowError {
                    return error
                } catch {
                    return nil
                }
            }
            for await result in group {
                XCTAssertEqual(result, .cancelled)
            }
        }
    }

    func testInvalidLimitsAndWorkOutputBoundaries() throws {
        let badLimits: [(Limits, WorkflowLimit)] = [
            (Limits(maximumComparisonRows: -1), .comparisonRows),
            (Limits(maximumSelectedRows: -1), .selectedRows),
            (Limits(maximumSelectedRanges: -1), .selectedRanges),
            (Limits(maximumComparisonOptionItems: -1), .comparisonOptionItems),
            (Limits(maximumComparisonOptionStringUTF8Bytes: -1), .comparisonOptionStringUTF8Bytes),
            (Limits(maximumComparisonOptionsUTF8Bytes: -1), .comparisonOptionsUTF8Bytes),
            (Limits(maximumInputUTF8Bytes: -1), .inputUTF8Bytes),
            (Limits(maximumRetainedUTF8Bytes: -1), .retainedUTF8Bytes),
            (Limits(maximumOutputUTF8Bytes: -1), .outputUTF8Bytes),
            (Limits(maximumWorkUnits: Limits.hardMaximumWorkUnits + 1), .workUnits),
            (Limits(cancellationCheckInterval: 0), .cancellationCheckInterval)
        ]
        for (limits, limit) in badLimits {
            assertWorkflowError(.invalidLimit(limit)) {
                try Workflow.expandedRanges([0..<1], rowCount: 2, limits: limits)
            }
        }

        let snapshot = try makeSnapshot(rows: makeRows(3), selectedRanges: [0..<2])
        assertWorkflowError(.tooManyComparisonRows(maximum: 2)) {
            try Workflow.commandState(
                for: WorkflowIntent(side: .left),
                in: snapshot,
                limits: Limits(maximumComparisonRows: 2)
            )
        }
        assertWorkflowError(.inputTooLarge(maximumUTF8Bytes: 1)) {
            try Workflow.commandState(
                for: WorkflowIntent(side: .left),
                in: snapshot,
                limits: Limits(maximumInputUTF8Bytes: 1)
            )
        }
        assertWorkflowError(.retainedDataTooLarge(maximumUTF8Bytes: 1)) {
            try Workflow.commandState(
                for: WorkflowIntent(side: .left),
                in: snapshot,
                limits: Limits(maximumRetainedUTF8Bytes: 1)
            )
        }
        assertWorkflowError(.workLimitExceeded(maximumUnits: 0)) {
            try Workflow.commandState(
                for: WorkflowIntent(side: .left),
                in: snapshot,
                limits: Limits(maximumWorkUnits: 0)
            )
        }
        assertWorkflowError(.outputTooLarge(maximumUTF8Bytes: 1)) {
            try Workflow.plan(
                intent: WorkflowIntent(side: .left),
                in: snapshot,
                limits: Limits(maximumOutputUTF8Bytes: 1)
            )
        }
        let manyFilters = LineDiffOptions(
            lineFilters: [LineFilterRule(pattern: "a"), LineFilterRule(pattern: "b")]
        )
        let filtered = try makeSnapshot(rows: makeRows(3), selectedRanges: [0..<2], options: manyFilters)
        assertWorkflowError(.invalidLimit(.comparisonOptionItems)) {
            try Workflow.commandState(
                for: WorkflowIntent(side: .left),
                in: filtered,
                limits: Limits(maximumComparisonOptionItems: 1)
            )
        }
        let longPattern = LineDiffOptions(lineFilters: [LineFilterRule(pattern: "ab")])
        let patterned = try makeSnapshot(rows: makeRows(3), selectedRanges: [0..<2], options: longPattern)
        assertWorkflowError(.invalidLimit(.comparisonOptionStringUTF8Bytes)) {
            try Workflow.commandState(
                for: WorkflowIntent(side: .left),
                in: patterned,
                limits: Limits(maximumComparisonOptionStringUTF8Bytes: 1)
            )
        }
    }

    private typealias WorkflowIntent = MultiRowNumberedCopyWorkflowIntent
    private typealias WorkflowSide = MultiRowNumberedCopyWorkflowSide
    private typealias WorkflowLimit = MultiRowNumberedCopyWorkflowLimit
    private typealias WorkflowFailureReason = MultiRowNumberedCopyWorkflowExecutionFailureReason
    private typealias WorkflowRequiredEffect = MultiRowNumberedCopyWorkflowRequiredEffect
    private typealias WorkflowCopyEvidence = MultiRowNumberedCopyWorkflowCopyEvidence
    private typealias SideState = MergeCommandPolicy.SideState

    private struct FixtureIDs {
        var comparison = MultiRowNumberedCopyWorkflowComparisonIdentity()
        var source = MultiRowNumberedCopyWorkflowSourceIdentity()
        var selection = MultiRowNumberedCopyWorkflowSelectionIdentity()
        var leftPane = MultiRowNumberedCopyWorkflowPaneIdentity()
        var rightPane = MultiRowNumberedCopyWorkflowPaneIdentity()
    }

    private func makeRows(
        _ count: Int,
        missingSide: WorkflowSide? = nil,
        textSuffix: String = ""
    ) -> [DiffRow] {
        (0..<count).map { index in
            let leftText = "left-\(index)\(textSuffix)"
            let rightText = "right-\(index)\(textSuffix)"
            let left = missingSide == .left ? nil : DiffLine(number: index + 1, text: leftText)
            let right = missingSide == .right ? nil : DiffLine(number: index + 1, text: rightText)
            let kind: DiffKind = left == nil ? .added : (right == nil ? .removed : .unchanged)
            return DiffRow(left: left, right: right, kind: kind)
        }
    }

    private func makeSnapshot(
        rows: [DiffRow]? = nil,
        selectedRanges: [Range<Int>] = [0..<2],
        left: SideState = SideState(isLoaded: true, isEditable: true, isDirty: false),
        right: SideState = SideState(isLoaded: true, isEditable: true, isDirty: false),
        lifecycle: MergeCommandPolicy.ComparisonLifecycle = .currentSuccess,
        source: ComparisonSnapshot = ComparisonSnapshot(left: "left-source", right: "right-source"),
        options: LineDiffOptions = LineDiffOptions(),
        ids: FixtureIDs = FixtureIDs(),
        comparisonRevision: UInt64 = 1,
        sourceRevision: UInt64 = 2,
        selectionRevision: UInt64 = 3,
        leftPaneRevision: UInt64 = 4,
        rightPaneRevision: UInt64 = 5
    ) throws -> MultiRowNumberedCopyWorkflowSnapshot {
        let rows = rows ?? makeRows(4)
        return try MultiRowNumberedCopyWorkflowSnapshot(
            comparisonIdentity: ids.comparison,
            comparisonRevision: comparisonRevision,
            sourceIdentity: ids.source,
            sourceRevision: sourceRevision,
            leftPaneRevision: MultiRowNumberedCopyWorkflowPaneRevision(
                identity: ids.leftPane,
                revision: leftPaneRevision
            ),
            rightPaneRevision: MultiRowNumberedCopyWorkflowPaneRevision(
                identity: ids.rightPane,
                revision: rightPaneRevision
            ),
            selectionIdentity: ids.selection,
            selectionRevision: selectionRevision,
            source: source,
            comparisonRows: rows,
            comparisonOptions: options,
            selectedRanges: selectedRanges,
            left: left,
            right: right,
            comparisonLifecycle: lifecycle
        )
    }

    private func assertWorkflowError<T>(
        _ expected: WorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> T
    ) {
        do {
            _ = try body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as WorkflowError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
