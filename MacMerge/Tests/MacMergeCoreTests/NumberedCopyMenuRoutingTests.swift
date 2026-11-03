import Foundation
import MacMergeCore
import XCTest

final class NumberedCopyMenuRoutingTests: XCTestCase {
    private typealias Routing = NumberedCopyMenuRouting
    private typealias RoutingError = NumberedCopyMenuRoutingError
    private typealias SideState = MergeCommandPolicy.SideState

    func testFocusedRowFallback() throws {
        let request = Routing.MenuRequest(side: .left, explicitRanges: [], focusedRow: 1)
        XCTAssertEqual(try Routing.resolveSelection(request, rowCount: 4), [1..<2])
    }

    func testMissingFocusThrowsEmptySelection() {
        let request = Routing.MenuRequest(side: .left, explicitRanges: [], focusedRow: nil)
        assertRoutingError(.workflow(.emptySelection)) {
            try Routing.resolveSelection(request, rowCount: 4)
        }
    }

    func testIndexSetPathUsesWorkflowCheck() throws {
        // Non-empty IndexSet wins over focused row.
        let resolved = try Routing.resolveSelection(
            side: .left,
            explicitSelection: IndexSet([0, 2]),
            focusedRow: 3,
            rowCount: 4
        )
        XCTAssertEqual(resolved, [0..<1, 2..<3])
        // Empty IndexSet throws instead of falling back to focused row.
        assertRoutingError(.workflow(.emptySelection)) {
            try Routing.resolveSelection(
                side: .left,
                explicitSelection: IndexSet(),
                focusedRow: 1,
                rowCount: 4
            )
        }
    }

    func testEnablementRequiresSnapshotSelectionMatch() throws {
        let snapshot = try makeSnapshot()
        let mismatched = Routing.MenuRequest(side: .left, explicitRanges: [0..<1], focusedRow: nil)
        assertRoutingError(.workflow(.selectionChanged)) {
            try Routing.enablement(for: mismatched, in: snapshot)
        }
        assertRoutingError(.workflow(.selectionChanged)) {
            try Routing.plan(mismatched, in: snapshot)
        }
    }

    func testEnablementDerivesAXLabelHint() throws {
        let snapshot = try makeSnapshot()
        let request = Routing.MenuRequest(side: .left, explicitRanges: [0..<2])
        let enablement = try Routing.enablement(for: request, in: snapshot)
        XCTAssertTrue(enablement.isEnabled)
        XCTAssertTrue(enablement.canExecute)
        XCTAssertNil(enablement.disabledReason)
        XCTAssertEqual(enablement.accessibilityLabel, "Copy left with line numbers")
        XCTAssertEqual(enablement.accessibilityHint, "Copies the selected left rows to the clipboard.")
        XCTAssertEqual(enablement.expectedSnapshot, snapshot.reference)

        let stale = try makeSnapshot(lifecycle: .loading)
        let staleRequest = Routing.MenuRequest(
            side: .right,
            explicitRanges: stale.selection.rowRanges,
            focusedRow: nil
        )
        let disabled = try Routing.enablement(for: staleRequest, in: stale)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertFalse(disabled.canExecute)
        XCTAssertEqual(disabled.disabledReason, .comparisonNotCurrent)
        XCTAssertEqual(disabled.accessibilityHint, "Unavailable while the comparison is not current.")
    }

    func testPlanPasteboardIntentCAS() throws {
        let ids = FixtureIDs()
        let snapshot = try makeSnapshot(ids: ids)
        let request = Routing.MenuRequest(side: .left, explicitRanges: [0..<2])
        let intent = try Routing.plan(request, in: snapshot)
        XCTAssertEqual(intent.payloadUTF8ByteCount, intent.payload.utf8.count)
        XCTAssertFalse(intent.payload.isEmpty)
        XCTAssertEqual(intent.expectedSnapshot, snapshot.reference)
        XCTAssertEqual(intent.requiredEffects, [.copyPayloadToOwnerTransferService])
        XCTAssertNoThrow(try intent.validateCurrentSnapshot(snapshot))

        let bumped = try makeSnapshot(ids: ids, comparisonRevision: 2)
        assertRoutingError(.workflow(.staleComparisonRevision(expected: 1, actual: 2))) {
            try intent.validateCurrentSnapshot(bumped)
        }
    }

    func testValidateCurrentSnapshotSelectionMismatchMapsToWorkflow() throws {
        let ids = FixtureIDs()
        let snapshot = try makeSnapshot(ids: ids)
        let request = Routing.MenuRequest(side: .left, explicitRanges: [0..<2])
        let intent = try Routing.plan(request, in: snapshot)
        let reselected = try makeSnapshot(selectedRanges: [0..<1], ids: ids)
        assertRoutingError(.workflow(.selectionChanged)) {
            try intent.validateCurrentSnapshot(reselected)
        }
    }

    func testWorkflowCancelledMapsToCancelled() async throws {
        let snapshot = try makeSnapshot()
        let request = Routing.MenuRequest(side: .left, explicitRanges: [0..<2])
        await withTaskGroup(of: RoutingError?.self) { group in
            group.cancelAll()
            group.addTask {
                do {
                    _ = try Routing.resolveSelection(request, rowCount: 4)
                    return nil
                } catch let error as RoutingError {
                    return error
                } catch {
                    return nil
                }
            }
            for await result in group {
                XCTAssertEqual(result, .cancelled)
            }
        }
        await withTaskGroup(of: RoutingError?.self) { group in
            group.cancelAll()
            group.addTask {
                do {
                    _ = try Routing.plan(request, in: snapshot)
                    return nil
                } catch let error as RoutingError {
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

    private struct FixtureIDs {
        var comparison = MultiRowNumberedCopyWorkflowComparisonIdentity()
        var source = MultiRowNumberedCopyWorkflowSourceIdentity()
        var selection = MultiRowNumberedCopyWorkflowSelectionIdentity()
        var leftPane = MultiRowNumberedCopyWorkflowPaneIdentity()
        var rightPane = MultiRowNumberedCopyWorkflowPaneIdentity()
    }

    private func makeRows(_ count: Int) -> [DiffRow] {
        (0..<count).map { index in
            DiffRow(
                left: DiffLine(number: index + 1, text: "left-\(index)"),
                right: DiffLine(number: index + 1, text: "right-\(index)"),
                kind: .unchanged
            )
        }
    }

    private func makeSnapshot(
        rows: [DiffRow]? = nil,
        selectedRanges: [Range<Int>] = [0..<2],
        lifecycle: MergeCommandPolicy.ComparisonLifecycle = .currentSuccess,
        ids: FixtureIDs = FixtureIDs(),
        comparisonRevision: UInt64 = 1
    ) throws -> MultiRowNumberedCopyWorkflowSnapshot {
        try MultiRowNumberedCopyWorkflowSnapshot(
            comparisonIdentity: ids.comparison,
            comparisonRevision: comparisonRevision,
            sourceIdentity: ids.source,
            sourceRevision: 2,
            leftPaneRevision: MultiRowNumberedCopyWorkflowPaneRevision(
                identity: ids.leftPane,
                revision: 4
            ),
            rightPaneRevision: MultiRowNumberedCopyWorkflowPaneRevision(
                identity: ids.rightPane,
                revision: 5
            ),
            selectionIdentity: ids.selection,
            selectionRevision: 3,
            source: ComparisonSnapshot(left: "left-source", right: "right-source"),
            comparisonRows: rows ?? makeRows(4),
            comparisonOptions: LineDiffOptions(),
            selectedRanges: selectedRanges,
            left: SideState(isLoaded: true, isEditable: true, isDirty: false),
            right: SideState(isLoaded: true, isEditable: true, isDirty: false),
            comparisonLifecycle: lifecycle
        )
    }

    private func assertRoutingError<T>(
        _ expected: RoutingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> T
    ) {
        do {
            _ = try body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as RoutingError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
