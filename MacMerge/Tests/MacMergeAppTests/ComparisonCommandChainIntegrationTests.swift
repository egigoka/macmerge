import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

@MainActor
final class ComparisonCommandChainIntegrationTests: XCTestCase {
    func testDifferenceCommandChainMatchesCoreAndSavesExactBytes() async throws {
        let fixture = try makeFixture(
            left: "alpha\r\nleft one\r\nsame\rleft two\r\nsame again\r\nleft three",
            right: "alpha\nright one\nsame\nright two\nsame again\nright three\n"
        )
        let model = ComparisonModel()
        model.enqueueOpen([fixture.leftURL, fixture.rightURL])
        assertCommandsDisabledWhileWorking(model)

        let saveFailure = expectation(description: "Busy side save reports failure")
        let saveAllFailure = expectation(description: "Busy save-all reports failure")
        var saveFailureResults: [Bool] = []
        model.save(.left) {
            saveFailureResults.append($0)
            saveFailure.fulfill()
        }
        model.saveAllChanges {
            saveFailureResults.append($0)
            saveAllFailure.fulfill()
        }
        await fulfillment(of: [saveFailure, saveAllFailure], timeout: 1)
        XCTAssertEqual(saveFailureResults, [false, false])
        await waitUntilIdle(model)

        let original = Snapshot(left: fixture.left, right: fixture.right)
        try assertMatchesCore(model, snapshot: original)
        let originalDifferenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(originalDifferenceIDs.count, 3)
        XCTAssertTrue(model.canRefresh)
        XCTAssertTrue(model.canNavigateDifferences)
        XCTAssertTrue(model.canSelectPreviousDifference)
        XCTAssertTrue(model.canSelectNextDifference)
        XCTAssertFalse(model.canSelectCurrentDifference)
        XCTAssertFalse(model.canMergeCurrentDifference)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertFalse(model.hasUnsavedChanges)

        model.selectDifference(originalDifferenceIDs[1])
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[1])
        XCTAssertEqual(model.selectedDifferencePosition, 2)
        XCTAssertTrue(model.hasSelectedDifference)
        XCTAssertTrue(model.canSelectCurrentDifference)
        XCTAssertTrue(model.canMergeCurrentDifference)

        model.selectFirstDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[0])
        XCTAssertEqual(model.selectedDifferencePosition, 1)
        XCTAssertFalse(model.canSelectPreviousDifference)
        XCTAssertTrue(model.canSelectNextDifference)
        model.selectPreviousDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[0])

        model.selectLastDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[2])
        XCTAssertEqual(model.selectedDifferencePosition, 3)
        XCTAssertTrue(model.canSelectPreviousDifference)
        XCTAssertFalse(model.canSelectNextDifference)
        model.selectNextDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[2])

        model.selectPreviousDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[1])
        XCTAssertEqual(model.selectedDifferencePosition, 2)
        model.selectNextDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[2])
        XCTAssertEqual(model.selectedDifferencePosition, 3)
        model.selectPreviousDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[1])
        XCTAssertEqual(model.selectedDifferencePosition, 2)

        model.selectDifference(nil)
        XCTAssertFalse(model.hasSelectedDifference)
        XCTAssertTrue(model.canSelectCurrentDifference)
        XCTAssertEqual(model.currentRowID, originalDifferenceIDs[1])
        let revealRevision = model.selectedDifferenceRevealRevision
        model.selectCurrentDifference()
        XCTAssertEqual(model.selectedDifferenceID, originalDifferenceIDs[1])
        XCTAssertEqual(model.selectedDifferencePosition, 2)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 1)

        let copied = try coreMerge(
            original,
            rowID: originalDifferenceIDs[1],
            direction: .leftToRight
        )
        model.mergeSelectedDifference(direction: .leftToRight, advance: false)
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        try assertMatchesCore(model, snapshot: copied)
        XCTAssertEqual(model.summary.differences, 2)
        XCTAssertFalse(model.hasSelectedDifference)
        XCTAssertFalse(model.canMergeCurrentDifference)
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertTrue(model.hasUnsavedChanges)

        model.undo()
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        try assertMatchesCore(model, snapshot: original)
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(model.canRedo)
        XCTAssertFalse(model.hasUnsavedChanges)

        model.redo()
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        try assertMatchesCore(model, snapshot: copied)
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertTrue(model.hasUnsavedChanges)

        model.selectFirstDifference()
        let refreshedSelection = model.selectedDifferenceID
        let refreshRowsRevision = model.rowsRevision
        model.refresh()
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        try assertMatchesCore(model, snapshot: copied)
        XCTAssertEqual(model.rowsRevision, refreshRowsRevision + 1)
        XCTAssertEqual(model.selectedDifferenceID, refreshedSelection)
        XCTAssertEqual(model.selectedDifferencePosition, 1)
        XCTAssertTrue(model.canRefresh)

        let advanceRowID = try XCTUnwrap(model.selectedDifferenceID)
        let copiedAndAdvanced = try coreMerge(
            copied,
            rowID: advanceRowID,
            direction: .leftToRight
        )
        model.mergeSelectedDifference(direction: .leftToRight, advance: true)
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        try assertMatchesCore(model, snapshot: copiedAndAdvanced)
        XCTAssertEqual(model.summary.differences, 1)
        XCTAssertEqual(model.selectedDifferencePosition, 1)
        XCTAssertTrue(model.hasSelectedDifference)
        XCTAssertTrue(model.canMergeCurrentDifference)
        XCTAssertFalse(model.canSelectPreviousDifference)
        XCTAssertFalse(model.canSelectNextDifference)

        let copiedAll = try coreMergeAll(copiedAndAdvanced, direction: .rightToLeft)
        model.mergeAll(direction: .rightToLeft)
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        try assertMatchesCore(model, snapshot: copiedAll)
        XCTAssertEqual(model.summary.differences, 0)
        XCTAssertFalse(model.canNavigateDifferences)
        XCTAssertFalse(model.canSelectPreviousDifference)
        XCTAssertFalse(model.canSelectNextDifference)
        XCTAssertFalse(model.canSelectCurrentDifference)
        XCTAssertFalse(model.canMergeCurrentDifference)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.canUndo)

        let saveCompleted = expectation(description: "All changes save")
        var saved = false
        model.saveAllChanges {
            saved = $0
            saveCompleted.fulfill()
        }
        assertCommandsDisabledWhileWorking(model)
        await fulfillment(of: [saveCompleted], timeout: 5)
        XCTAssertTrue(saved)

        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.isWorking)
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertEqual(try Data(contentsOf: fixture.leftURL), Data(copiedAll.left.utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.rightURL), Data(copiedAll.right.utf8))
        try assertMatchesCore(model, snapshot: copiedAll)
    }

    func testOppositeCopyDirectionAndCopyAllMatchCore() async throws {
        let fixture = try makeFixture(
            left: "left one\nsame\nleft two\n",
            right: "right one\nsame\nright two\n"
        )
        let original = Snapshot(left: fixture.left, right: fixture.right)
        let model = ComparisonModel()
        model.enqueueOpen([fixture.leftURL, fixture.rightURL])
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(differenceIDs.count, 2)
        model.selectDifference(differenceIDs[0])
        let copiedRightToLeft = try coreMerge(
            original,
            rowID: differenceIDs[0],
            direction: .rightToLeft
        )

        model.mergeSelectedDifference(direction: .rightToLeft, advance: false)
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)
        try assertMatchesCore(model, snapshot: copiedRightToLeft)

        let copiedAllLeftToRight = try coreMergeAll(
            copiedRightToLeft,
            direction: .leftToRight
        )
        model.mergeAll(direction: .leftToRight)
        assertCommandsDisabledWhileWorking(model)
        await waitUntilIdle(model)

        try assertMatchesCore(model, snapshot: copiedAllLeftToRight)
        XCTAssertEqual(model.left.text, model.right.text)
    }

    private func assertMatchesCore(
        _ model: ComparisonModel,
        snapshot: Snapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let coreRows = try LineDiff.compare(
            left: snapshot.left,
            right: snapshot.right,
            options: model.options
        )
        XCTAssertEqual(model.left.text, snapshot.left, file: file, line: line)
        XCTAssertEqual(model.right.text, snapshot.right, file: file, line: line)
        XCTAssertEqual(model.rows, coreRows, file: file, line: line)
        XCTAssertEqual(model.summary, DiffSummary(rows: coreRows), file: file, line: line)
        XCTAssertTrue(model.isComparisonCurrent, file: file, line: line)
        XCTAssertFalse(model.comparisonFailed, file: file, line: line)
        XCTAssertFalse(model.isWorking, file: file, line: line)
    }

    private func assertCommandsDisabledWhileWorking(
        _ model: ComparisonModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(model.isWorking, file: file, line: line)
        XCTAssertFalse(model.canRefresh, file: file, line: line)
        XCTAssertFalse(model.canNavigateDifferences, file: file, line: line)
        XCTAssertFalse(model.canSelectPreviousDifference, file: file, line: line)
        XCTAssertFalse(model.canSelectNextDifference, file: file, line: line)
        XCTAssertFalse(model.canSelectCurrentDifference, file: file, line: line)
        XCTAssertFalse(model.canMergeCurrentDifference, file: file, line: line)
        XCTAssertFalse(model.canUndo, file: file, line: line)
        XCTAssertFalse(model.canRedo, file: file, line: line)
        XCTAssertFalse(model.canReloadFromDisk, file: file, line: line)
        XCTAssertFalse(model.canCreateEmptyComparison, file: file, line: line)
    }

    private func coreMerge(
        _ snapshot: Snapshot,
        rowID: DiffRow.ID,
        direction: MergeDirection
    ) throws -> Snapshot {
        let result = try XCTUnwrap(
            LineMerge.apply(
                rowID: rowID,
                direction: direction,
                left: snapshot.left,
                right: snapshot.right
            )
        )
        return Snapshot(left: result.left, right: result.right)
    }

    private func coreMergeAll(
        _ snapshot: Snapshot,
        direction: MergeDirection
    ) throws -> Snapshot {
        let result = try XCTUnwrap(
            LineMerge.applyAll(
                direction: direction,
                left: snapshot.left,
                right: snapshot.right
            )
        )
        return Snapshot(left: result.left, right: result.right)
    }

    private func waitUntilIdle(_ model: ComparisonModel, timeout: TimeInterval = 5) async {
        let idle = expectation(description: "Comparison model becomes idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: timeout)
    }

    private func makeFixture(left: String, right: String) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let leftURL = directory.appending(path: "left.txt")
        let rightURL = directory.appending(path: "right.txt")
        try Data(left.utf8).write(to: leftURL)
        try Data(right.utf8).write(to: rightURL)
        return Fixture(leftURL: leftURL, rightURL: rightURL, left: left, right: right)
    }

    private struct Snapshot {
        let left: String
        let right: String
    }

    private struct Fixture {
        let leftURL: URL
        let rightURL: URL
        let left: String
        let right: String
    }
}
