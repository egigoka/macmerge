import MacMergeCore
import XCTest

@testable import MacMerge

/// App-side agreement between `ComparisonCopyCommand` and the Core toolbar layout, so the
/// toolbar titles and the CopyCommandControl AX fixture labels cannot drift apart.
final class ToolbarCommandLayoutAppTests: XCTestCase {
    /// Literal toolbar titles; `toolbarLabel` reads `ToolbarCommandLayout.copyTitle`, so only a
    /// literal golden catches a changed title.
    private static let copyTitleGolden: [ComparisonCopyCommand: String] = [
        .selectedToRight: "Copy selected difference to right",
        .selectedToLeft: "Copy selected difference to left",
        .selectedToRightAndAdvance: "Copy selected difference to right and advance",
        .selectedToLeftAndAdvance: "Copy selected difference to left and advance",
        .allToRight: "Copy all differences to right",
        .allToLeft: "Copy all differences to left"
    ]

    func testCopyCommandToolbarLabelsMatchLiteralGolden() throws {
        let layout = ToolbarCommandLayout.make(state: .freshWindow)
        XCTAssertEqual(Set(Self.copyTitleGolden.keys), Set(ComparisonCopyCommand.allCases))
        for command in ComparisonCopyCommand.allCases {
            let golden = try XCTUnwrap(Self.copyTitleGolden[command])
            XCTAssertEqual(command.toolbarLabel, golden, "\(command)")
            XCTAssertEqual(layout.control(for: command.toolbarCommand)?.title, golden, "\(command)")
        }
    }

    @MainActor
    func testCopyCommandControlFixtureUsesGoldenLabels() throws {
        let model = ComparisonModel()
        for command in ComparisonCopyCommand.allCases {
            let control = AccessibilityCommandTestHarness.CopyCommandControl(
                command: command, model: model)
            defer { control.close() }
            XCTAssertEqual(control.state.label, Self.copyTitleGolden[command], "\(command)")
        }
    }

    func testCopyCommandsMapToDistinctToolbarCommands() {
        let commands = ComparisonCopyCommand.allCases.map(\.toolbarCommand)
        XCTAssertEqual(Set(commands).count, ComparisonCopyCommand.allCases.count)
        XCTAssertEqual(
            Set(commands),
            [
                .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance,
                .copyAllToRight, .copyAllToLeft
            ])
    }

    func testCopyAllCommandsRouteThroughConfirmationActions() {
        let layout = ToolbarCommandLayout.make(state: .freshWindow)
        XCTAssertEqual(
            layout.control(for: ComparisonCopyCommand.allToRight.toolbarCommand)?.primaryAction,
            .requestCopyAllToRight)
        XCTAssertEqual(
            layout.control(for: ComparisonCopyCommand.allToLeft.toolbarCommand)?.primaryAction,
            .requestCopyAllToLeft)
    }
}

/// Toolbar gates read from `ComparisonModel` through `ToolbarCommandLayout.State(model:...)`,
/// the initializer `ComparisonToolbar` uses. Each field is compared with its own model source,
/// using fixtures where left and right differ, so a swapped or mis-mapped field fails.
@MainActor
final class ToolbarCommandLayoutStateMappingTests: XCTestCase {
    func testEmptyModelMapsToFreshWindow() {
        let state = ToolbarCommandLayout.State(model: ComparisonModel(), canUndo: false, canRedo: false)
        XCTAssertEqual(state, .freshWindow)
    }

    func testUndoRedoPassThroughUnchanged() {
        let model = ComparisonModel()
        let undoOnly = ToolbarCommandLayout.State(model: model, canUndo: true, canRedo: false)
        XCTAssertTrue(undoOnly.canUndo)
        XCTAssertFalse(undoOnly.canRedo)
        let redoOnly = ToolbarCommandLayout.State(model: model, canUndo: false, canRedo: true)
        XCTAssertFalse(redoOnly.canUndo)
        XCTAssertTrue(redoOnly.canRedo)
    }

    func testLoadedPairWithDirtyLeftMapsEachFieldFromItsOwnSource() async throws {
        let model = ComparisonModel()
        model.enqueueOpen([
            try temporaryFile(name: "left.txt", content: "same\nleft\nsame\n"),
            try temporaryFile(name: "right.txt", content: "same\nright\nsame\n")
        ])
        await waitUntilIdle(model)
        assertMapping(model)

        let difference = try XCTUnwrap(model.rows.first { $0.left?.text == "left" })
        model.selectDifference(difference.id)
        assertMapping(model)

        model.editText("edited\n", on: .left)
        await waitUntilIdle(model)
        XCTAssertTrue(model.left.isDirty)
        XCTAssertFalse(model.right.isDirty)
        let state = assertMapping(model)
        XCTAssertTrue(state.hasUnsavedChanges)
        XCTAssertNotEqual(state.canSaveLeft, state.canSaveRight)
    }

    @discardableResult
    private func assertMapping(
        _ model: ComparisonModel, file: StaticString = #filePath, line: UInt = #line
    ) -> ToolbarCommandLayout.State {
        let state = ToolbarCommandLayout.State(model: model, canUndo: false, canRedo: false)
        let expected: [(String, Bool, Bool)] = [
            ("isWorking", state.isWorking, model.isWorking),
            ("isLeftLoaded", state.isLeftLoaded, model.left.isLoaded),
            ("isRightLoaded", state.isRightLoaded, model.right.isLoaded),
            ("canSaveLeft", state.canSaveLeft, ComparisonSaveCommand.left.isEnabled(on: model)),
            ("canSaveRight", state.canSaveRight, ComparisonSaveCommand.right.isEnabled(on: model)),
            ("hasUnsavedChanges", state.hasUnsavedChanges, model.left.isDirty || model.right.isDirty),
            ("canSelectLineDifference", state.canSelectLineDifference, model.canSelectLineDifference),
            ("hasNavigableDifferences", state.hasNavigableDifferences, model.canNavigateDifferences),
            ("canSelectNextDifference", state.canSelectNextDifference, model.canSelectNextDifference),
            (
                "canSelectPreviousDifference", state.canSelectPreviousDifference,
                model.canSelectPreviousDifference
            ),
            (
                "canSelectCurrentDifference", state.canSelectCurrentDifference,
                model.canSelectCurrentDifference
            ),
            (
                "canCopyToRight", state.canCopyToRight,
                ComparisonCopyCommand.selectedToRight.isEnabled(on: model)
            ),
            (
                "canCopyToLeft", state.canCopyToLeft,
                ComparisonCopyCommand.selectedToLeft.isEnabled(on: model)
            ),
            (
                "canCopyToRightAndAdvance", state.canCopyToRightAndAdvance,
                ComparisonCopyCommand.selectedToRightAndAdvance.isEnabled(on: model)
            ),
            (
                "canCopyToLeftAndAdvance", state.canCopyToLeftAndAdvance,
                ComparisonCopyCommand.selectedToLeftAndAdvance.isEnabled(on: model)
            ),
            (
                "canCopyAllToRight", state.canCopyAllToRight,
                ComparisonCopyCommand.allToRight.isEnabled(on: model)
            ),
            (
                "canCopyAllToLeft", state.canCopyAllToLeft,
                ComparisonCopyCommand.allToLeft.isEnabled(on: model)
            ),
            ("canRefresh", state.canRefresh, model.canRefresh)
        ]
        for (name, actual, source) in expected {
            XCTAssertEqual(actual, source, name, file: file, line: line)
        }
        XCTAssertEqual(
            state.implementedNewCommands, ToolbarNewSplitButtonPlan.currentlyImplementedCommands,
            file: file, line: line)
        return state
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

    private func waitUntilIdle(_ model: ComparisonModel) async {
        await withCheckedContinuation { continuation in
            model.whenIdle { continuation.resume() }
        }
    }
}
