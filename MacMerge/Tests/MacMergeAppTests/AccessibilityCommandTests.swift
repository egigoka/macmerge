import AppKit
import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

#if DEBUG
    @MainActor
    final class AccessibilityCommandTests: XCTestCase {
        func testRowsExposeVoiceOverStatusLineNumbersAndSemanticSelection() throws {
            let cases: [(DiffRow, String)] = [
                (
                    DiffRow(
                        left: DiffLine(number: 10, text: "same"),
                        right: DiffLine(number: 20, text: "same"),
                        kind: .unchanged
                    ),
                    "Unchanged, left line 10, right line 20"
                ),
                (
                    DiffRow(
                        left: DiffLine(number: 11, text: "before"),
                        right: DiffLine(number: 21, text: "after"),
                        kind: .modified
                    ),
                    "Modified, left line 11, right line 21"
                ),
                (
                    DiffRow(
                        left: DiffLine(number: 12, text: "removed"),
                        right: nil,
                        kind: .removed
                    ),
                    "Removed, left line 12, no right line"
                ),
                (
                    DiffRow(
                        left: nil,
                        right: DiffLine(number: 22, text: "added"),
                        kind: .added
                    ),
                    "Added, no left line, right line 22"
                )
            ]

            for (row, expectedLabel) in cases {
                let harness = AccessibilityCommandTestHarness.Row(
                    row: row,
                    selected: row.kind == .modified
                )
                let state = harness.state

                XCTAssertEqual(state.role, .group)
                XCTAssertEqual(state.label, expectedLabel)
                XCTAssertEqual(state.isSelected, row.kind == .modified)
                XCTAssertNil(state.value)
                harness.close()
            }

            let selectedRow = AccessibilityCommandTestHarness.Row(row: cases[1].0, selected: true)
            defer { selectedRow.close() }
            XCTAssertEqual(selectedRow.state.lineNumbers, ["11", "21"])
            XCTAssertEqual(
                selectedRow.state.editors.map(\.label),
                ["Left editable line 11", "Right editable line 21"]
            )
            XCTAssertEqual(selectedRow.state.editors.map(\.role), [.textArea, .textArea])
            XCTAssertEqual(selectedRow.state.editors.map(\.value), ["before", "after"])
            XCTAssertEqual(selectedRow.state.editors.map(\.isEnabled), [true, true])
            XCTAssertEqual(selectedRow.state.editors.map(\.isValueSettable), [true, true])

            selectedRow.setSelected(false)
            XCTAssertFalse(selectedRow.state.isSelected)
        }

        func testHostedTableAndRowsExposeRolesMovedStatusAndEditorEditability() {
            let row = DiffRow(
                left: DiffLine(number: 11, text: "before"),
                right: DiffLine(number: 21, text: "after"),
                kind: .modified
            )
            let table = AccessibilityCommandTestHarness.Table(
                rows: [row],
                selectedDifferenceID: row.id,
                movedLeft: true,
                rightEditable: false
            )
            defer { table.close() }

            XCTAssertEqual(table.tableRole, .table)
            XCTAssertEqual(table.accessibilityRowRoles, [.row, .row])
            XCTAssertEqual(table.selectedAccessibilityRowCount, 1)
            XCTAssertEqual(table.selectedAccessibilityRowRoles, [.row])
            XCTAssertEqual(
                table.rowState(at: 0).label,
                "Modified, moved on left, left line 11, right line 21"
            )
            XCTAssertTrue(table.rowState(at: 0).isSelected)
            XCTAssertNil(table.rowState(at: 0).value)
            XCTAssertEqual(table.rowState(at: 0).editors.map(\.role), [.textArea, .textArea])
            XCTAssertEqual(
                table.rowState(at: 0).editors.map(\.label),
                ["Left editable line 11", "Right read-only line 21"]
            )
            XCTAssertEqual(table.rowState(at: 0).editors.map(\.isEnabled), [true, true])
            XCTAssertEqual(table.rowState(at: 0).editors.map(\.isValueSettable), [true, false])

            let rightMoved = AccessibilityCommandTestHarness.Row(
                row: row,
                selected: false,
                movedRight: true,
                leftEditable: false
            )
            defer { rightMoved.close() }
            XCTAssertEqual(
                rightMoved.state.label,
                "Modified, moved on right, left line 11, right line 21"
            )
            XCTAssertEqual(
                rightMoved.state.editors.map(\.label),
                ["Left read-only line 11", "Right editable line 21"]
            )
            XCTAssertEqual(rightMoved.state.editors.map(\.isValueSettable), [false, true])
        }

        func testReadOnlyHeaderControlExposesActionStateAndRequestedValue() {
            let editable = AccessibilityCommandTestHarness.ReadOnlyControl(
                side: .left,
                isLoaded: true,
                isEditable: true
            )
            defer { editable.close() }
            XCTAssertEqual(editable.state.role, .button)
            XCTAssertEqual(editable.state.label, "Make left file read-only")
            XCTAssertEqual(editable.state.value, "Editable")
            XCTAssertTrue(editable.state.isEnabled)
            XCTAssertTrue(editable.performAXPress())
            XCTAssertEqual(editable.requestedReadOnlyValues, [true])

            let readOnly = AccessibilityCommandTestHarness.ReadOnlyControl(
                side: .right,
                isLoaded: true,
                isEditable: false
            )
            defer { readOnly.close() }
            XCTAssertEqual(readOnly.state.role, .button)
            XCTAssertEqual(readOnly.state.label, "Make right file editable")
            XCTAssertEqual(readOnly.state.value, "Read-only")
            XCTAssertTrue(readOnly.performAXPress())
            XCTAssertEqual(readOnly.requestedReadOnlyValues, [false])

            let unloaded = AccessibilityCommandTestHarness.ReadOnlyControl(
                side: .left,
                isLoaded: false,
                isEditable: false
            )
            defer { unloaded.close() }
            XCTAssertEqual(unloaded.state.label, "No left file loaded")
            XCTAssertEqual(unloaded.state.value, "No file loaded")
            XCTAssertFalse(unloaded.state.isEnabled)
            XCTAssertFalse(unloaded.performAXPress())
            XCTAssertTrue(unloaded.requestedReadOnlyValues.isEmpty)
        }

        func testLocationPaneCommandsExposeAXActionsAndExactNavigation() {
            let rows = (1...3).map { row in
                DiffRow(
                    left: DiffLine(number: row * 10, text: "left \(row)"),
                    right: DiffLine(number: row * 20, text: "right \(row)"),
                    kind: .modified
                )
            }
            let commands = AccessibilityCommandTestHarness.LocationPaneCommands(
                rows: rows,
                currentRow: 1,
                movesCursorOnClick: true,
                detectsMovedBlocks: false
            )

            XCTAssertEqual(commands.role, .group)
            XCTAssertEqual(commands.label, "Location Pane Commands")
            XCTAssertEqual(
                commands.actionNames,
                [
                    "Go to Left Line",
                    "Go to Right Line",
                    "Go to Left...",
                    "Go to Right...",
                    "Disable Move Cursor on Click",
                    "No Moved Blocks",
                    "All Moved Blocks"
                ]
            )
            XCTAssertTrue(commands.performAction(named: "Go to Left Line"))
            XCTAssertTrue(commands.performAction(named: "Go to Right Line"))
            XCTAssertTrue(commands.performAction(named: "Disable Move Cursor on Click"))
            XCTAssertTrue(commands.performAction(named: "All Moved Blocks"))
            XCTAssertEqual(commands.goToLines.map(\.line), [20, 40])
            XCTAssertEqual(commands.goToLines.map(\.side), [.left, .right])
            XCTAssertEqual(commands.moveCursorValues, [false])
            XCTAssertEqual(commands.movedBlockValues, [true])

            let unchangedCursor = AccessibilityCommandTestHarness.LocationPaneCommands(
                rows: rows,
                currentRow: 2,
                movesCursorOnClick: true,
                detectsMovedBlocks: false
            )
            XCTAssertTrue(unchangedCursor.performAction(named: "Go to Left Line"))
            XCTAssertEqual(unchangedCursor.goToLines.map(\.line), [30])

            let inverse = AccessibilityCommandTestHarness.LocationPaneCommands(
                rows: rows,
                currentRow: 2,
                movesCursorOnClick: false,
                detectsMovedBlocks: true
            )
            XCTAssertTrue(inverse.actionNames.contains("Enable Move Cursor on Click"))
            XCTAssertTrue(inverse.performAction(named: "Enable Move Cursor on Click"))
            XCTAssertTrue(inverse.performAction(named: "No Moved Blocks"))
            XCTAssertEqual(inverse.moveCursorValues, [true])
            XCTAssertEqual(inverse.movedBlockValues, [false])

            let empty = AccessibilityCommandTestHarness.LocationPaneCommands(
                rows: [],
                movesCursorOnClick: true,
                detectsMovedBlocks: false
            )
            XCTAssertFalse(empty.performAction(named: "Go to Left Line"))
            XCTAssertFalse(empty.performAction(named: "Missing Action"))

            let missingRight = AccessibilityCommandTestHarness.LocationPaneCommands(
                rows: [
                    DiffRow(
                        left: DiffLine(number: 8, text: "left only"),
                        right: nil,
                        kind: .removed
                    )
                ],
                movesCursorOnClick: true,
                detectsMovedBlocks: false
            )
            XCTAssertTrue(missingRight.actionNames.contains("Go to Left Line"))
            XCTAssertFalse(missingRight.actionNames.contains("Go to Right Line"))
            XCTAssertTrue(missingRight.actionNames.contains("Go to Right..."))
            XCTAssertFalse(missingRight.performAction(named: "Go to Right Line"))
        }

        func testLocationSliderExposesAXStateAndNavigatesToExactCenteredRows() {
            let rows = (1...100).map { line in
                DiffRow(
                    left: DiffLine(number: line, text: "line \(line)"),
                    right: DiffLine(number: line, text: "line \(line)"),
                    kind: .unchanged
                )
            }
            var navigations: [AccessibilityCommandTestHarness.NavigationCall] = []
            let slider = AccessibilityCommandTestHarness.LocationSlider(
                rows: rows,
                viewport: LocationViewport(startRow: 40, endRow: 60),
                side: .right
            ) { row, side in
                navigations.append(.init(row: row, side: side, activatesEditor: false))
            }
            defer { slider.close() }

            XCTAssertEqual(slider.state.role, .slider)
            XCTAssertEqual(slider.state.value, 0.5)
            XCTAssertTrue(slider.state.isEnabled)
            XCTAssertTrue(slider.state.isValueSettable)
            XCTAssertTrue(slider.state.isIncrementAllowed)
            XCTAssertTrue(slider.state.isDecrementAllowed)
            XCTAssertTrue(slider.setValue(0))
            XCTAssertTrue(slider.setValue(0.25))
            XCTAssertTrue(slider.setValue(1))
            XCTAssertEqual(
                navigations,
                [
                    .init(row: 10, side: .right, activatesEditor: false),
                    .init(row: 30, side: .right, activatesEditor: false),
                    .init(row: 90, side: .right, activatesEditor: false)
                ]
            )

            navigations.removeAll()
            XCTAssertTrue(slider.increment())
            XCTAssertTrue(slider.decrement())
            XCTAssertEqual(navigations.count, 2)
            XCTAssertGreaterThan(navigations[0].row, 50)
            XCTAssertLessThan(navigations[1].row, 50)
            XCTAssertEqual(navigations.map(\.side), [.right, .right])

            let empty = AccessibilityCommandTestHarness.LocationSlider(
                rows: [],
                viewport: .empty,
                side: .left
            ) { _, _ in XCTFail("Disabled slider must not navigate") }
            defer { empty.close() }
            XCTAssertFalse(empty.state.isEnabled)
            XCTAssertFalse(empty.state.isValueSettable)
            XCTAssertFalse(empty.state.isIncrementAllowed)
            XCTAssertFalse(empty.state.isDecrementAllowed)
            XCTAssertFalse(empty.setValue(0.5))
            XCTAssertFalse(empty.increment())
            XCTAssertFalse(empty.decrement())

            let fullyVisible = AccessibilityCommandTestHarness.LocationSlider(
                rows: rows,
                viewport: LocationViewport(startRow: 0, endRow: rows.count),
                side: .left
            ) { _, _ in XCTFail("Fully visible slider must not navigate") }
            defer { fullyVisible.close() }
            XCTAssertFalse(fullyVisible.state.isEnabled)
            XCTAssertFalse(fullyVisible.state.isValueSettable)
            XCTAssertFalse(fullyVisible.increment())
            XCTAssertFalse(fullyVisible.decrement())
        }

        func testDisabledContextMenuAndToolbarAXPressPathsDoNothing() async throws {
            let emptyModel = ComparisonModel()
            let row = DiffRow(
                left: DiffLine(number: 1, text: "left"),
                right: DiffLine(number: 1, text: "right"),
                kind: .modified
            )
            let menu = AccessibilityCommandTestHarness.ContextMenu(
                row: row,
                side: .left,
                model: emptyModel
            )
            let menuItem = try XCTUnwrap(menu.item(titled: "Copy to Right"))
            XCTAssertEqual(menuItem.role, .menuItem)
            XCTAssertEqual(menuItem.label, "Copy to Right")
            XCTAssertFalse(menuItem.isEnabled)
            XCTAssertFalse(menu.performItem(titled: "Copy to Right"))
            XCTAssertFalse(menu.performItem(titled: "Copy Selected Lines to Right"))

            let toolbar = AccessibilityCommandTestHarness.CopyCommandControl(
                command: .selectedToRight,
                model: emptyModel
            )
            defer { toolbar.close() }
            XCTAssertEqual(toolbar.state.role, .button)
            XCTAssertEqual(toolbar.state.label, ComparisonCopyCommand.selectedToRight.toolbarLabel)
            XCTAssertFalse(toolbar.state.isEnabled)
            XCTAssertFalse(toolbar.performAXPress())
            XCTAssertFalse(emptyModel.isReady)
        }

        func testToolbarAXPressAdvancesExactlyOneOfThreeDifferences() async throws {
            let model = try await makeModel(
                left: "left one\nsame\nleft two\nsame\nleft three\n",
                right: "right one\nsame\nright two\nsame\nright three\n"
            )
            let initialDifferences = model.rows.filter { $0.kind != .unchanged }
            XCTAssertEqual(initialDifferences.count, 3)
            model.selectFirstDifference()
            XCTAssertEqual(model.selectedDifferenceID, initialDifferences[0].id)

            let toolbar = AccessibilityCommandTestHarness.CopyCommandControl(
                command: .selectedToRightAndAdvance,
                model: model
            )
            defer { toolbar.close() }
            XCTAssertTrue(toolbar.state.isEnabled)
            XCTAssertTrue(toolbar.performAXPress())
            await waitUntilIdle(model)

            let remainingDifferences = model.rows.filter { $0.kind != .unchanged }
            XCTAssertEqual(remainingDifferences.count, 2)
            XCTAssertEqual(model.selectedDifferenceID, remainingDifferences[0].id)
            XCTAssertEqual(remainingDifferences[0].left?.text, "left two")
            XCTAssertEqual(model.right.text, "left one\nsame\nright two\nsame\nright three\n")
        }

        func testContextMenuCopyLabelsAreAccessibleAndApplyDisplayedDirection() async throws {
            try await assertContextCopy(
                side: .left,
                title: "Copy to Right",
                expectedLeft: "left\n",
                expectedRight: "left\n"
            )
            try await assertContextCopy(
                side: .left,
                title: "Copy from Right",
                expectedLeft: "right\n",
                expectedRight: "right\n"
            )
            try await assertContextCopy(
                side: .right,
                title: "Copy to Left",
                expectedLeft: "right\n",
                expectedRight: "right\n"
            )
            try await assertContextCopy(
                side: .right,
                title: "Copy from Left",
                expectedLeft: "left\n",
                expectedRight: "left\n"
            )
        }

        func testContextMenuNumberedCopyUsesClickedSideAndDisablesMissingSide() async throws {
            let row = DiffRow(
                left: DiffLine(number: 7, text: "left value"),
                right: DiffLine(number: 12, text: "right value"),
                kind: .modified
            )
            let model = ComparisonModel()

            for (side, expected) in [
                (ComparisonSide.left, "7: left value"),
                (ComparisonSide.right, "12: right value")
            ] {
                let menu = AccessibilityCommandTestHarness.ContextMenu(
                    row: row,
                    side: side,
                    model: model
                )
                let item = try XCTUnwrap(menu.item(titled: "Copy with Line Number"))
                XCTAssertEqual(item.role, .menuItem)
                XCTAssertEqual(item.label, "Copy with Line Number")
                XCTAssertTrue(item.isEnabled)
                XCTAssertTrue(menu.performItem(titled: "Copy with Line Number"))
                let copiedText = await menu.waitForCopiedText()
                XCTAssertEqual(copiedText, expected)
            }

            let editedMenu = AccessibilityCommandTestHarness.ContextMenu(
                row: row,
                side: .left,
                model: model
            )
            editedMenu.setVisibleText("edited left value")
            XCTAssertTrue(editedMenu.performItem(titled: "Copy with Line Number"))
            let editedText = await editedMenu.waitForCopiedText()
            XCTAssertEqual(editedText, "7: edited left value")

            let missingRight = DiffRow(
                left: DiffLine(number: 8, text: "left only"),
                right: nil,
                kind: .removed
            )
            let menu = AccessibilityCommandTestHarness.ContextMenu(
                row: missingRight,
                side: .right,
                model: model
            )
            let item = try XCTUnwrap(menu.item(titled: "Copy with Line Number"))
            XCTAssertFalse(item.isEnabled)
            XCTAssertFalse(menu.performItem(titled: "Copy with Line Number"))
            XCTAssertNil(menu.copiedText)
        }

        func testToolbarAndMenuCopyCommandsMatchLabelsDirectionsAndResults() async throws {
            XCTAssertEqual(
                ComparisonCopyCommand.allCases.map(\.menuTitle),
                [
                    "Copy to Right",
                    "Copy to Left",
                    "Copy to Right and Advance",
                    "Copy to Left and Advance",
                    "Copy All to Right",
                    "Copy All to Left"
                ]
            )
            XCTAssertEqual(
                ComparisonCopyCommand.allCases.map(\.toolbarLabel),
                [
                    "Copy selected difference to right",
                    "Copy selected difference to left",
                    "Copy selected difference to right and advance",
                    "Copy selected difference to left and advance",
                    "Copy all differences to right",
                    "Copy all differences to left"
                ]
            )

            let left = "left one\nsame\nleft two\n"
            let right = "right one\nsame\nright two\n"
            try await assertCommand(
                .selectedToRight,
                expectedLeft: left,
                expectedRight: "left one\nsame\nright two\n",
                expectedDifferences: 1,
                expectsSelection: false
            )
            try await assertCommand(
                .selectedToLeft,
                expectedLeft: "right one\nsame\nleft two\n",
                expectedRight: right,
                expectedDifferences: 1,
                expectsSelection: false
            )
            try await assertCommand(
                .selectedToRightAndAdvance,
                expectedLeft: left,
                expectedRight: "left one\nsame\nright two\n",
                expectedDifferences: 1,
                expectsSelection: true
            )
            try await assertCommand(
                .selectedToLeftAndAdvance,
                expectedLeft: "right one\nsame\nleft two\n",
                expectedRight: right,
                expectedDifferences: 1,
                expectsSelection: true
            )
            try await assertCommand(
                .allToRight,
                expectedLeft: left,
                expectedRight: left,
                expectedDifferences: 0,
                expectsSelection: false
            )
            try await assertCommand(
                .allToLeft,
                expectedLeft: right,
                expectedRight: right,
                expectedDifferences: 0,
                expectsSelection: false
            )
        }

        private func assertContextCopy(
            side: ComparisonSide,
            title: String,
            expectedLeft: String,
            expectedRight: String
        ) async throws {
            let model = try await makeModel()
            let row = try XCTUnwrap(model.rows.first { $0.kind != .unchanged })
            let menu = AccessibilityCommandTestHarness.ContextMenu(row: row, side: side, model: model)
            let item = try XCTUnwrap(menu.item(titled: title))
            XCTAssertTrue(item.isEnabled)
            XCTAssertEqual(item.role, .menuItem)
            XCTAssertEqual(item.label, title)

            XCTAssertTrue(menu.performItem(titled: title))
            await waitUntilIdle(model)

            XCTAssertEqual(model.left.text, expectedLeft)
            XCTAssertEqual(model.right.text, expectedRight)
            XCTAssertEqual(model.summary.differences, 0)
        }

        private func assertCommand(
            _ command: ComparisonCopyCommand,
            expectedLeft: String,
            expectedRight: String,
            expectedDifferences: Int,
            expectsSelection: Bool
        ) async throws {
            let model = try await makeModel(
                left: "left one\nsame\nleft two\n",
                right: "right one\nsame\nright two\n"
            )
            model.selectFirstDifference()
            let control = AccessibilityCommandTestHarness.CopyCommandControl(
                command: command,
                model: model
            )
            defer { control.close() }

            XCTAssertEqual(control.state.role, .button)
            XCTAssertEqual(control.state.label, command.toolbarLabel)
            XCTAssertTrue(control.state.isEnabled)
            XCTAssertTrue(control.performAXPress())
            await waitUntilIdle(model)

            XCTAssertEqual(model.left.text, expectedLeft, command.toolbarLabel)
            XCTAssertEqual(model.right.text, expectedRight, command.toolbarLabel)
            XCTAssertEqual(model.summary.differences, expectedDifferences, command.toolbarLabel)
            XCTAssertEqual(model.selectedDifferenceID != nil, expectsSelection, command.toolbarLabel)
        }

        private func makeModel(left: String = "left\n", right: String = "right\n") async throws -> ComparisonModel {
            let leftURL = try temporaryFile(name: "left.txt", content: left)
            let rightURL = try temporaryFile(name: "right.txt", content: right)
            let model = ComparisonModel()
            model.enqueueOpen([leftURL, rightURL])
            await waitUntilIdle(model)
            return model
        }

        private func waitUntilIdle(_ model: ComparisonModel) async {
            await withCheckedContinuation { continuation in
                model.whenIdle { continuation.resume() }
            }
        }

        private func temporaryFile(name: String, content: String) throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: name)
            try Data(content.utf8).write(to: url)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            return url
        }
    }
#endif
