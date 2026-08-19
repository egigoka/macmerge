import AppKit
import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

#if DEBUG
    @MainActor
    final class OffscreenNavigationRegressionTests: XCTestCase {
        func testVisibleSelectionDefinesOriginWhenCursorIsOffscreen() async throws {
            let fixture = try await makeModel()
            let model = fixture.model
            let differences = fixture.differenceIDs
            let harness = makeTable(for: model)
            defer { harness.close() }

            let selectedID = differences[2]
            let selectedRow = rowIndex(of: selectedID, in: model)
            model.selectDifference(selectedID)
            update(harness, from: model)
            await drainMainQueue()

            let nextCursorID = differences[5]
            let nextCursorRow = rowIndex(of: nextCursorID, in: model)
            model.moveCursor(to: nextCursorID)
            XCTAssertEqual(model.selectedDifferenceID, selectedID)
            XCTAssertEqual(model.currentRowID, nextCursorID)
            XCTAssertTrue(harness.visibleRows.contains(selectedRow))
            XCTAssertFalse(harness.visibleRows.contains(nextCursorRow))
            XCTAssertTrue(model.canSelectNextDifference)
            model.selectNextDifference()
            assertSelection(model, is: differences[3], position: 4)

            model.selectDifference(selectedID)
            update(harness, from: model)
            await drainMainQueue()
            let previousCursorID = differences[0]
            let previousCursorRow = rowIndex(of: previousCursorID, in: model)
            model.moveCursor(to: previousCursorID)

            XCTAssertEqual(model.selectedDifferenceID, selectedID)
            XCTAssertEqual(model.currentRowID, previousCursorID)
            XCTAssertTrue(harness.visibleRows.contains(selectedRow))
            XCTAssertFalse(harness.visibleRows.contains(previousCursorRow))
            XCTAssertTrue(model.canSelectPreviousDifference)
            model.selectPreviousDifference()
            assertSelection(model, is: differences[1], position: 2)
        }

        func testOffscreenSelectionYieldsToVisibleUnchangedCursor() async throws {
            let fixture = try await makeModel()
            let model = fixture.model
            let differences = fixture.differenceIDs
            let cursorRow = try unchangedRow(
                between: differences[2],
                and: differences[3],
                in: model
            )
            let cursorID = model.rows[cursorRow].id
            let harness = makeTable(for: model)
            defer { harness.close() }

            model.selectDifference(differences[0])
            update(harness, from: model)
            model.moveCursor(to: cursorID)
            harness.scrollRowToVisible(cursorRow)
            await drainMainQueue()

            XCTAssertEqual(model.selectedDifferenceID, differences[0])
            XCTAssertEqual(model.currentRowID, cursorID)
            XCTAssertFalse(harness.visibleRows.contains(rowIndex(of: differences[0], in: model)))
            XCTAssertTrue(harness.visibleRows.contains(cursorRow))
            XCTAssertTrue(model.canSelectNextDifference)
            model.selectNextDifference()
            assertSelection(model, is: differences[3], position: 4)

            model.selectDifference(differences[5])
            update(harness, from: model)
            model.moveCursor(to: cursorID)
            harness.scrollRowToVisible(cursorRow)
            await drainMainQueue()

            XCTAssertEqual(model.selectedDifferenceID, differences[5])
            XCTAssertEqual(model.currentRowID, cursorID)
            XCTAssertFalse(harness.visibleRows.contains(rowIndex(of: differences[5], in: model)))
            XCTAssertTrue(harness.visibleRows.contains(cursorRow))
            XCTAssertTrue(model.canSelectPreviousDifference)
            model.selectPreviousDifference()
            assertSelection(model, is: differences[2], position: 3)
        }

        func testCursorEndpointsDoNotWrapToOffscreenSelection() async throws {
            let fixture = try await makeModel()
            let model = fixture.model
            let differences = fixture.differenceIDs
            let firstDifferenceRow = rowIndex(of: differences[0], in: model)
            let lastDifferenceRow = rowIndex(of: differences[5], in: model)
            let leadingRow = try XCTUnwrap(
                model.rows.indices.last { $0 < firstDifferenceRow && model.rows[$0].kind == .unchanged }
            )
            let trailingRow = try XCTUnwrap(
                model.rows.indices.first { $0 > lastDifferenceRow && model.rows[$0].kind == .unchanged }
            )
            let harness = makeTable(for: model)
            defer { harness.close() }

            model.selectDifference(differences[0])
            update(harness, from: model)
            model.moveCursor(to: model.rows[trailingRow].id)
            harness.scrollRowToVisible(trailingRow)
            await drainMainQueue()

            XCTAssertEqual(model.selectedDifferenceID, differences[0])
            XCTAssertEqual(model.currentRowID, model.rows[trailingRow].id)
            XCTAssertFalse(harness.visibleRows.contains(firstDifferenceRow))
            XCTAssertTrue(harness.visibleRows.contains(trailingRow))
            XCTAssertFalse(model.canSelectNextDifference)
            let nextRevealRevision = model.selectedDifferenceRevealRevision
            model.selectNextDifference()
            XCTAssertEqual(model.selectedDifferenceID, differences[0])
            XCTAssertEqual(model.currentRowID, model.rows[trailingRow].id)
            XCTAssertEqual(model.selectedDifferenceRevealRevision, nextRevealRevision)
            XCTAssertTrue(harness.visibleRows.contains(trailingRow))

            model.selectDifference(differences[5])
            update(harness, from: model)
            model.moveCursor(to: model.rows[leadingRow].id)
            harness.scrollRowToVisible(leadingRow)
            await drainMainQueue()

            XCTAssertEqual(model.selectedDifferenceID, differences[5])
            XCTAssertEqual(model.currentRowID, model.rows[leadingRow].id)
            XCTAssertFalse(harness.visibleRows.contains(lastDifferenceRow))
            XCTAssertTrue(harness.visibleRows.contains(leadingRow))
            XCTAssertFalse(model.canSelectPreviousDifference)
            let previousRevealRevision = model.selectedDifferenceRevealRevision
            model.selectPreviousDifference()
            XCTAssertEqual(model.selectedDifferenceID, differences[5])
            XCTAssertEqual(model.currentRowID, model.rows[leadingRow].id)
            XCTAssertEqual(model.selectedDifferenceRevealRevision, previousRevealRevision)
            XCTAssertTrue(harness.visibleRows.contains(leadingRow))
        }

        func testCurrentRowFallbackRequestsRevealAndRestoresTableSelection() async throws {
            let fixture = try await makeModel()
            let model = fixture.model
            let currentID = fixture.differenceIDs[4]
            let currentRow = rowIndex(of: currentID, in: model)

            model.selectDifference(currentID)
            model.selectDifference(nil)
            XCTAssertNil(model.selectedDifferenceID)
            XCTAssertEqual(model.currentRowID, currentID)

            let harness = makeTable(for: model)
            defer { harness.close() }
            harness.scrollRowToVisible(0)
            await drainMainQueue()
            XCTAssertFalse(harness.visibleRows.contains(currentRow))
            XCTAssertEqual(model.currentRowID, currentID)
            XCTAssertEqual(harness.selectedRow, -1)

            let revision = model.selectedDifferenceRevealRevision
            model.selectCurrentDifference()

            assertSelection(model, is: currentID, position: 5)
            XCTAssertEqual(model.selectedDifferenceRevealRevision, revision + 1)

            update(harness, from: model)

            XCTAssertTrue(harness.visibleRows.contains(currentRow))
            XCTAssertEqual(harness.selectedRowIndexes, IndexSet(integer: currentRow))
            let selectedCell = try XCTUnwrap(harness.visibleCells.first { $0.row == currentRow })
            XCTAssertTrue(selectedCell.isSelected)
            assertModifiedStatusColorContract(selectedCell, selected: true)
        }

        func testSameProductionCellReconfigurationClearsAndRestoresSelectionStatusContract() throws {
            let rows = makeRows(count: 1)
            let selectedRow = 0
            let harness = AccessibilityCommandTestHarness.Table(
                rows: rows,
                selectedDifferenceID: rows[selectedRow].id,
                leftEditable: false,
                rightEditable: false
            )
            defer { harness.close() }

            harness.scrollRowToVisible(selectedRow)
            let selectedCell = try XCTUnwrap(harness.visibleCells.first { $0.row == selectedRow })
            XCTAssertTrue(selectedCell.isSelected)
            assertModifiedStatusColorContract(selectedCell, selected: true)

            harness.update(
                selectedDifferenceID: nil,
                selectedDifferenceRevealRevision: 0
            )
            let clearedCell = try XCTUnwrap(harness.visibleCells.first { $0.row == selectedRow })
            XCTAssertEqual(clearedCell.identity, selectedCell.identity)
            XCTAssertEqual(harness.selectedRowIndexes, IndexSet())
            XCTAssertFalse(clearedCell.isSelected)
            assertModifiedStatusColorContract(clearedCell, selected: false)

            harness.update(
                selectedDifferenceID: rows[selectedRow].id,
                selectedDifferenceRevealRevision: 0
            )
            let restoredCell = try XCTUnwrap(harness.visibleCells.first { $0.row == selectedRow })
            XCTAssertEqual(restoredCell.identity, selectedCell.identity)
            XCTAssertEqual(harness.selectedRow, selectedRow)
            XCTAssertTrue(restoredCell.isSelected)
            assertModifiedStatusColorContract(restoredCell, selected: true)
        }

        private func makeTable(
            for model: ComparisonModel
        ) -> AccessibilityCommandTestHarness.Table {
            AccessibilityCommandTestHarness.Table(
                rows: model.rows,
                selectedDifferenceID: model.selectedDifferenceID,
                leftEditable: false,
                rightEditable: false,
                viewportChanged: model.updateViewport
            )
        }

        private func update(
            _ harness: AccessibilityCommandTestHarness.Table,
            from model: ComparisonModel
        ) {
            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
        }

        private func unchangedRow(
            between lowerID: DiffRow.ID,
            and upperID: DiffRow.ID,
            in model: ComparisonModel
        ) throws -> Int {
            let lower = rowIndex(of: lowerID, in: model)
            let upper = rowIndex(of: upperID, in: model)
            return try XCTUnwrap(
                model.rows.indices.first {
                    $0 > lower && $0 < upper && model.rows[$0].kind == .unchanged
                }
            )
        }

        private func rowIndex(of id: DiffRow.ID, in model: ComparisonModel) -> Int {
            model.differenceLocations[id]?.rowIndex ?? -1
        }

        private func assertSelection(
            _ model: ComparisonModel,
            is id: DiffRow.ID,
            position: Int,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(model.selectedDifferenceID, id, file: file, line: line)
            XCTAssertEqual(model.currentRowID, id, file: file, line: line)
            XCTAssertEqual(model.selectedDifferencePosition, position, file: file, line: line)
        }

        private func assertModifiedStatusColorContract(
            _ cell: AccessibilityCommandTestHarness.VisibleCellState,
            selected: Bool,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let expectedColor = selected ? NSColor.controlAccentColor : NSColor.systemOrange
            XCTAssertEqual(cell.leftStatusColor, expectedColor, file: file, line: line)
            XCTAssertEqual(cell.rightStatusColor, expectedColor, file: file, line: line)
        }

        private func makeModel() async throws -> (model: ComparisonModel, differenceIDs: [DiffRow.ID]) {
            let changedLines = Set([6, 21, 36, 51, 66, 81])
            let left = (1...90).map { line in
                changedLines.contains(line) ? "left change \(line)" : "shared \(line)"
            }.joined(separator: "\n")
            let right = (1...90).map { line in
                changedLines.contains(line) ? "right change \(line)" : "shared \(line)"
            }.joined(separator: "\n")
            let leftURL = try temporaryFile(name: "left.txt", content: left)
            let rightURL = try temporaryFile(name: "right.txt", content: right)
            let model = ComparisonModel()

            model.enqueueOpen([leftURL, rightURL])
            await waitUntilIdle(model)

            let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
            XCTAssertEqual(differenceIDs.count, changedLines.count)
            return (model, differenceIDs)
        }

        private func makeRows(count: Int) -> [DiffRow] {
            (1...count).map { line in
                DiffRow(
                    left: DiffLine(number: line, text: "left \(line)"),
                    right: DiffLine(number: line, text: "right \(line)"),
                    kind: .modified
                )
            }
        }

        private func waitUntilIdle(_ model: ComparisonModel) async {
            let idle = expectation(description: "Comparison model becomes idle")
            model.whenIdle { idle.fulfill() }
            await fulfillment(of: [idle], timeout: 5)
        }

        private func drainMainQueue() async {
            let drained = expectation(description: "Main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 1)
        }

        private func temporaryFile(name: String, content: String) throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appending(path: name)
            try Data(content.utf8).write(to: url)
            return url
        }
    }
#endif
