import AppKit
import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

#if DEBUG
    @MainActor
    final class OffscreenSelectionBehaviorTests: XCTestCase {
        func testNavigationUsesVisibleSelectionAndOffscreenCursorFallback() async throws {
            let fixture = try await makeModel()
            let model = fixture.model
            let differenceIDs = fixture.differenceIDs
            let harness = AccessibilityCommandTestHarness.Table(
                rows: model.rows,
                leftEditable: false,
                rightEditable: false,
                viewportChanged: model.updateViewport
            )
            defer { harness.close() }

            model.selectDifference(differenceIDs[2])
            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
            await drainMainQueue()
            XCTAssertTrue(harness.visibleRows.contains(rowIndex(of: differenceIDs[2], in: model)))

            model.moveCursor(to: differenceIDs[0])
            model.selectNextDifference()
            assertSelection(model, is: differenceIDs[3], at: 4)
            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
            XCTAssertTrue(harness.visibleRows.contains(rowIndex(of: differenceIDs[3], in: model)))

            let cursorRow = try XCTUnwrap(
                model.rows.indices.first { row in
                    row > rowIndex(of: differenceIDs[1], in: model)
                        && row < rowIndex(of: differenceIDs[2], in: model)
                        && model.rows[row].kind == .unchanged
                })
            let cursorID = model.rows[cursorRow].id

            model.selectDifference(differenceIDs[4])
            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
            model.moveCursor(to: cursorID)
            harness.scrollRowToVisible(cursorRow)
            await drainMainQueue()
            XCTAssertFalse(harness.visibleRows.contains(rowIndex(of: differenceIDs[4], in: model)))
            XCTAssertTrue(model.canSelectNextDifference)
            XCTAssertTrue(model.canSelectPreviousDifference)

            model.selectNextDifference()
            assertSelection(model, is: differenceIDs[2], at: 3)
            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
            XCTAssertTrue(harness.visibleRows.contains(rowIndex(of: differenceIDs[2], in: model)))

            model.selectDifference(differenceIDs[4])
            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
            model.moveCursor(to: cursorID)
            harness.scrollRowToVisible(cursorRow)
            await drainMainQueue()

            model.selectPreviousDifference()
            assertSelection(model, is: differenceIDs[1], at: 2)
            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
            XCTAssertTrue(harness.visibleRows.contains(rowIndex(of: differenceIDs[1], in: model)))
        }

        func testNavigationPreservesCurrentLineFallbackAndNoWrapEndpoints() async throws {
            let fixture = try await makeModel()
            let model = fixture.model
            let differenceIDs = fixture.differenceIDs
            let cursorRow = try XCTUnwrap(
                model.rows.indices.first { row in
                    row > rowIndex(of: differenceIDs[1], in: model)
                        && row < rowIndex(of: differenceIDs[2], in: model)
                        && model.rows[row].kind == .unchanged
                })

            model.activateRow(model.rows[cursorRow].id)
            model.selectNextDifference()
            assertSelection(model, is: differenceIDs[2], at: 3)
            model.activateRow(model.rows[cursorRow].id)
            model.selectPreviousDifference()
            assertSelection(model, is: differenceIDs[1], at: 2)

            model.selectDifference(differenceIDs[0])
            model.moveCursor(to: differenceIDs[4])
            model.updateViewport(viewport(containing: differenceIDs[4], in: model))
            XCTAssertFalse(model.canSelectNextDifference)
            model.selectNextDifference()
            XCTAssertEqual(model.selectedDifferenceID, differenceIDs[0])
            XCTAssertEqual(model.currentRowID, differenceIDs[4])

            model.selectDifference(differenceIDs[4])
            model.moveCursor(to: differenceIDs[0])
            model.updateViewport(viewport(containing: differenceIDs[0], in: model))
            XCTAssertFalse(model.canSelectPreviousDifference)
            model.selectPreviousDifference()
            XCTAssertEqual(model.selectedDifferenceID, differenceIDs[4])
            XCTAssertEqual(model.currentRowID, differenceIDs[0])

            model.selectFirstDifference()
            model.updateViewport(viewport(containing: differenceIDs[0], in: model))
            XCTAssertFalse(model.canSelectPreviousDifference)
            let firstState = revealState(of: model)
            model.selectPreviousDifference()
            assertSelection(model, is: differenceIDs[0], at: 1)
            XCTAssertFalse(revealWasRequested(on: model, from: firstState))

            model.selectLastDifference()
            model.updateViewport(viewport(containing: differenceIDs[4], in: model))
            XCTAssertFalse(model.canSelectNextDifference)
            let lastState = revealState(of: model)
            model.selectNextDifference()
            assertSelection(model, is: differenceIDs[4], at: 5)
            XCTAssertFalse(revealWasRequested(on: model, from: lastState))
        }

        func testOffscreenSelectionPersistsThroughScrollingAndCellReuse() throws {
            let rows = makeRows(count: 120)
            let selectedRow = 94
            let selectedID = rows[selectedRow].id
            let harness = AccessibilityCommandTestHarness.Table(
                rows: rows,
                selectedDifferenceID: selectedID,
                leftEditable: false,
                rightEditable: false
            )
            defer { harness.close() }

            harness.scrollRowToVisible(selectedRow)
            XCTAssertEqual(harness.selectedRow, selectedRow)
            XCTAssertTrue(harness.visibleRows.contains(selectedRow))
            XCTAssertTrue(harness.isCellSelected(at: selectedRow))

            let selectedCellID = try XCTUnwrap(
                harness.visibleCells.first(where: { $0.row == selectedRow })?.identity
            )
            var reusedSelectedCell: AccessibilityCommandTestHarness.VisibleCellState?
            for targetRow in stride(from: 4, through: 114, by: 10) {
                harness.scrollRowToVisible(targetRow)
                XCTAssertFalse(harness.visibleRows.contains(selectedRow))
                XCTAssertEqual(harness.selectedRow, selectedRow)
                XCTAssertEqual(harness.selectedRowIndexes, IndexSet(integer: selectedRow))
                XCTAssertTrue(
                    harness.visibleCells.allSatisfy {
                        !$0.isSelected
                            && !$0.leftStatusColor.isVisuallyEqual(to: .controlAccentColor)
                            && !$0.rightStatusColor.isVisuallyEqual(to: .controlAccentColor)
                    })
                if let reused = harness.visibleCells.first(where: { $0.identity == selectedCellID }) {
                    reusedSelectedCell = reused
                    break
                }
            }
            let reusedCell = try XCTUnwrap(
                reusedSelectedCell,
                "Expected NSTableView to reuse the exact selected production diff cell"
            )
            XCTAssertNotEqual(reusedCell.row, selectedRow)
            XCTAssertFalse(reusedCell.isSelected)
            XCTAssertFalse(reusedCell.leftStatusColor.isVisuallyEqual(to: .controlAccentColor))
            XCTAssertFalse(reusedCell.rightStatusColor.isVisuallyEqual(to: .controlAccentColor))

            harness.scrollRowToVisible(selectedRow)

            XCTAssertTrue(harness.visibleRows.contains(selectedRow))
            XCTAssertEqual(harness.selectedRow, selectedRow)
            XCTAssertTrue(harness.isCellSelected(at: selectedRow))
        }

        func testOffscreenCurrentRevealRestoresSameSelectionWithoutAdvancing() async throws {
            let fixture = try await makeModel()
            let model = fixture.model
            let selectedID = fixture.differenceIDs[2]
            let selectedRow = try XCTUnwrap(model.differenceLocations[selectedID]?.rowIndex)
            model.selectDifference(selectedID)
            let harness = AccessibilityCommandTestHarness.Table(
                rows: model.rows,
                selectedDifferenceID: selectedID,
                leftEditable: false,
                rightEditable: false,
                viewportChanged: model.updateViewport
            )
            defer { harness.close() }

            harness.scrollRowToVisible(model.rows.count - 1)
            await drainMainQueue()
            XCTAssertFalse(harness.visibleRows.contains(selectedRow))
            XCTAssertEqual(harness.selectedRow, selectedRow)

            let revision = model.selectedDifferenceRevealRevision
            model.selectCurrentDifference()

            XCTAssertEqual(model.selectedDifferenceID, selectedID)
            XCTAssertEqual(model.selectedDifferencePosition, 3)
            XCTAssertEqual(model.selectedDifferenceRevealRevision, revision + 1)

            harness.update(
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision
            )
            XCTAssertTrue(harness.visibleRows.contains(selectedRow))
            XCTAssertEqual(harness.selectedRow, selectedRow)
            XCTAssertTrue(harness.isCellSelected(at: selectedRow))
        }

        private typealias RevealState = (selection: DiffRow.ID?, revision: Int)

        private func revealState(of model: ComparisonModel) -> RevealState {
            (model.selectedDifferenceID, model.selectedDifferenceRevealRevision)
        }

        private func revealWasRequested(on model: ComparisonModel, from previous: RevealState) -> Bool {
            previous.selection != model.selectedDifferenceID
                || previous.revision != model.selectedDifferenceRevealRevision
        }

        private func rowIndex(of id: DiffRow.ID, in model: ComparisonModel) -> Int {
            model.differenceLocations[id]?.rowIndex ?? -1
        }

        private func viewport(containing id: DiffRow.ID, in model: ComparisonModel) -> LocationViewport {
            let row = rowIndex(of: id, in: model)
            return LocationViewport(startRow: row, endRow: row + 1)
        }

        private func drainMainQueue() async {
            let drained = expectation(description: "Main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 1)
        }

        private func makeModel() async throws -> (model: ComparisonModel, differenceIDs: [DiffRow.ID]) {
            let left = (1...80).map { line in
                [7, 24, 41, 58, 75].contains(line) ? "left \(line)" : "same \(line)"
            }.joined(separator: "\n")
            let right = (1...80).map { line in
                [7, 24, 41, 58, 75].contains(line) ? "right \(line)" : "same \(line)"
            }.joined(separator: "\n")
            let leftURL = try temporaryFile(name: "left.txt", content: left)
            let rightURL = try temporaryFile(name: "right.txt", content: right)
            let model = ComparisonModel()

            model.enqueueOpen([leftURL, rightURL])
            await waitUntilIdle(model)

            let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
            XCTAssertEqual(differenceIDs.count, 5)
            return (model, differenceIDs)
        }

        private func assertSelection(
            _ model: ComparisonModel,
            is id: DiffRow.ID,
            at position: Int,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(model.selectedDifferenceID, id, file: file, line: line)
            XCTAssertEqual(model.currentRowID, id, file: file, line: line)
            XCTAssertEqual(model.selectedDifferencePosition, position, file: file, line: line)
        }

        private func makeRows(count: Int) -> [DiffRow] {
            (1...count).map { number in
                DiffRow(
                    left: DiffLine(number: number, text: "left \(number)"),
                    right: DiffLine(number: number, text: "right \(number)"),
                    kind: .modified
                )
            }
        }

        private func waitUntilIdle(_ model: ComparisonModel) async {
            let idle = expectation(description: "Comparison model becomes idle")
            model.whenIdle { idle.fulfill() }
            await fulfillment(of: [idle], timeout: 5)
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

    extension Optional where Wrapped == NSColor {
        fileprivate func isVisuallyEqual(to color: NSColor) -> Bool {
            guard let value = self else { return false }
            return value.usingColorSpace(.deviceRGB) == color.usingColorSpace(.deviceRGB)
        }
    }
#endif
