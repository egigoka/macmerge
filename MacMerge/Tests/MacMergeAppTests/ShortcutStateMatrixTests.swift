import AppKit
import Foundation
import MacMergeCore
import XCTest
@testable import MacMerge

/// Exercises command eligibility and action contracts consumed by `WinMergeCommands`.
/// `WinMergeCommands` is private and exposes no rendered menu seam to the test target,
/// so key-equivalent registration and process dispatch remain installed-app UI coverage.
/// The Open panel and dirty-new alert also remain installed-app UI coverage.
@MainActor
final class ZShortcutStateMatrixTests: XCTestCase {
    func testCommandEligibilityMatrixIncludesEmptyState() {
        let empty = ComparisonModel()
        assertEnabled([.newComparison, .openComparison, .toggleMergeMode], on: empty, state: "empty")
    }

    func testCommandEligibilityMatrixIncludesLoadedWithoutDifferencesState() async throws {
        let disabled = try await makeModel(left: "same\n", right: "same\n")
        assertEnabled(
            [.newComparison, .openComparison, .refresh, .changePane, .alternateChangePane, .toggleMergeMode],
            on: disabled,
            state: "loaded without differences"
        )
    }

    func testCommandEligibilityMatrixIncludesSelectedDirtyAndLoadingStates() async throws {
        let selected = try await makeModel(
            left: "left one\nsame\nleft two\nsame\nleft three\n",
            right: "right one\nsame\nright two\nsame\nright three\n"
        )
        let differenceIDs = selected.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(differenceIDs.count, 3)
        selected.selectDifference(differenceIDs[1])
        assertEnabled(
            [
                .newComparison,
                .openComparison,
                .selectLineDifference,
                .selectPreviousLineDifference,
                .refresh,
                .changePane,
                .alternateChangePane,
                .previousDifference,
                .nextDifference,
                .toggleMergeMode
            ],
            on: selected,
            state: "selected"
        )

        selected.selectFirstDifference()
        ComparisonCopyCommand.selectedToRight.perform(on: selected)
        await waitUntilIdle(selected)
        selected.selectFirstDifference()
        assertEnabled(
            [
                .newComparison,
                .openComparison,
                .save,
                .undo,
                .selectLineDifference,
                .selectPreviousLineDifference,
                .refresh,
                .changePane,
                .alternateChangePane,
                .nextDifference,
                .toggleMergeMode
            ],
            on: selected,
            state: "dirty"
        )

        selected.refresh()
        XCTAssertTrue(selected.isWorking)
        assertEnabled([.toggleMergeMode], on: selected, state: "loading")
        await waitUntilIdle(selected)
    }

    func testCommandEligibilityMatrixIncludesTextFocusedRedoState() {
        let model = ComparisonModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { close(window) }
        let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.insertText("editor edit", replacementRange: NSRange(location: 0, length: 0))
        textView.undoManager?.undo()
        XCTAssertTrue(textView.undoManager?.canRedo == true)

        assertEnabled(
            [.newComparison, .openComparison, .redo, .toggleMergeMode],
            on: model,
            focusedTextView: textView,
            state: "text-focused with editor redo available"
        )
    }

    func testDisabledCommandActionsLeaveNoDifferenceStateUnchanged() async throws {
        let model = try await makeModel(left: "same\n", right: "same\n")
        let revealRevision = model.selectedDifferenceRevealRevision
        let lineSelectionRevision = model.lineDifferenceSelectionRevision

        model.selectLineDifference()
        model.selectPreviousLineDifference()
        model.selectPreviousDifference()
        model.selectNextDifference()
        ComparisonUndoRouter.undo(model: model, focusedTextView: nil)
        ComparisonUndoRouter.redo(model: model, focusedTextView: nil)

        XCTAssertNil(model.selectedDifferenceID)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, lineSelectionRevision)
        XCTAssertEqual(model.left.text, "same\n")
        XCTAssertEqual(model.right.text, "same\n")
        XCTAssertFalse(model.isWorking)
    }

    func testLoadingRejectsDisabledCommandActionsWhileMergeModeToggleRemainsAvailable() async throws {
        let model = try await makeDirtyModel()
        model.selectFirstDifference()
        let left = model.left.text
        let right = model.right.text
        let selection = model.selectedDifferenceID
        let activeSide = model.activeSide
        let paneFocusRevision = model.paneFocusRevision
        let revealRevision = model.selectedDifferenceRevealRevision
        let lineSelectionRevision = model.lineDifferenceSelectionRevision

        model.refresh()
        XCTAssertTrue(model.isWorking)
        model.setMergeMode(true)
        XCTAssertTrue(model.isMergeMode, "Merge-mode toggle remains available during comparison work")

        model.createEmptyComparison()
        model.selectLineDifference()
        model.selectPreviousLineDifference()
        model.selectPreviousDifference()
        model.selectNextDifference()
        model.changePane()
        model.refresh()
        ComparisonUndoRouter.undo(model: model, focusedTextView: nil)
        ComparisonUndoRouter.redo(model: model, focusedTextView: nil)
        let saved = await withCheckedContinuation { continuation in
            model.saveAllChanges { continuation.resume(returning: $0) }
        }

        XCTAssertFalse(saved)
        XCTAssertEqual(model.left.text, left)
        XCTAssertEqual(model.right.text, right)
        XCTAssertEqual(model.selectedDifferenceID, selection)
        XCTAssertEqual(model.activeSide, activeSide)
        XCTAssertEqual(model.paneFocusRevision, paneFocusRevision)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, lineSelectionRevision)
        XCTAssertTrue(model.isMergeMode)

        await waitUntilIdle(model)
    }

    func testSelectedCommandActionsProduceExpectedResults() async throws {
        let model = try await makeModel(
            left: "one SAME three SAME\nstable\nleft tail\n",
            right: "one same three same\nstable\nright tail\n"
        )
        let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(differenceIDs.count, 2)
        model.selectDifference(differenceIDs[1])

        let revealRevision = model.selectedDifferenceRevealRevision
        let lineSelectionRevision = model.lineDifferenceSelectionRevision
        model.selectLineDifference()
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .next)
        model.selectPreviousLineDifference()
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .previous)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 2)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, lineSelectionRevision + 2)

        model.selectPreviousDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs[0])
        model.selectNextDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs[1])

        let rowsRevision = model.rowsRevision
        model.refresh()
        await waitUntilIdle(model)
        XCTAssertEqual(model.rowsRevision, rowsRevision + 1)
        XCTAssertEqual(model.selectedDifferencePosition, 2)

        let paneFocusRevision = model.paneFocusRevision
        model.changePane()
        XCTAssertEqual(model.activeSide, .right)
        model.changePane()
        XCTAssertEqual(model.activeSide, .left, "Two-pane change action toggles back to the first pane")
        XCTAssertEqual(model.paneFocusRevision, paneFocusRevision + 2)

        model.setMergeMode(true)
        XCTAssertTrue(model.isMergeMode)
        model.setMergeMode(false)
        XCTAssertFalse(model.isMergeMode)
    }

    func testComparisonHistoryUndoRedoAndSaveActionContracts() async throws {
        let model = try await makeDirtyModel()
        let dirtyRight = model.right.text
        let originalRight = "right one\nsame\nright two\n"

        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(ComparisonUndoRouter.canUndo(model: model, focusedTextView: nil))
        ComparisonUndoRouter.undo(model: model, focusedTextView: nil)
        await waitUntilIdle(model)

        XCTAssertEqual(model.right.text, originalRight)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(ComparisonUndoRouter.canRedo(model: model, focusedTextView: nil))
        ComparisonUndoRouter.redo(model: model, focusedTextView: nil)
        await waitUntilIdle(model)

        XCTAssertEqual(model.right.text, dirtyRight)
        XCTAssertTrue(model.hasUnsavedChanges)

        let saved = await withCheckedContinuation { continuation in
            model.saveAllChanges { continuation.resume(returning: $0) }
        }
        await waitUntilIdle(model)

        XCTAssertTrue(saved)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.hasPendingSaveWarning)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(model.right.url), encoding: .utf8), dirtyRight)
    }

    func testUndoRedoAndNewComparisonInvalidatePendingFocusRequests() async throws {
        let model = try await makeDirtyModel()
        let dirtyRow = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        requestLineDifferenceFocus(on: model, rowID: dirtyRow.id)
        let generationBeforeUndo = model.focusGeneration

        model.undo()

        XCTAssertGreaterThan(model.focusGeneration, generationBeforeUndo)
        XCTAssertNil(model.focusRequest)
        await waitUntilIdle(model)

        let originalRow = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        requestLineDifferenceFocus(on: model, rowID: originalRow.id)
        let generationBeforeRedo = model.focusGeneration

        model.redo()

        XCTAssertGreaterThan(model.focusGeneration, generationBeforeRedo)
        XCTAssertNil(model.focusRequest)
        await waitUntilIdle(model)

        let redoneRow = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        requestLineDifferenceFocus(on: model, rowID: redoneRow.id)
        let generationBeforeNewComparison = model.focusGeneration

        model.createEmptyComparison()

        XCTAssertGreaterThan(model.focusGeneration, generationBeforeNewComparison)
        XCTAssertNil(model.focusRequest)
    }

    func testNoArgumentUndoRouterUsesKeyWindowForUndoAndRedo() async throws {
        let model = try await makeDirtyModel()
        let modelLeft = model.left.text
        let modelRight = model.right.text
        XCTAssertTrue(model.canUndo)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let previousKeyWindow = NSApplication.shared.keyWindow
        defer {
            close(window)
            previousKeyWindow?.makeKeyAndOrderFront(nil)
        }
        let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        guard window.isKeyWindow else {
            throw XCTSkip("Test host could not make AppKit window key.")
        }
        XCTAssertTrue(window.makeFirstResponder(textView))

        XCTAssertFalse(
            ComparisonUndoRouter.canUndo(model: model),
            "Focused editor state overrides available comparison history"
        )
        textView.insertText("editor edit", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(ComparisonUndoRouter.canUndo(model: model))
        XCTAssertFalse(ComparisonUndoRouter.canRedo(model: model))

        ComparisonUndoRouter.undo(model: model)
        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(model.left.text, modelLeft)
        XCTAssertEqual(model.right.text, modelRight)
        XCTAssertTrue(model.canUndo, "Comparison history remains untouched")
        XCTAssertTrue(ComparisonUndoRouter.canRedo(model: model))

        ComparisonUndoRouter.redo(model: model)
        XCTAssertEqual(textView.string, "editor edit")
        XCTAssertEqual(model.left.text, modelLeft)
        XCTAssertEqual(model.right.text, modelRight)
        XCTAssertFalse(ComparisonUndoRouter.canRedo(model: model))
    }

    func testNoArgumentUndoRouterDoesNotMutateComparisonFromNoncomparisonKeyWindow() async throws {
        let model = try await makeDirtyModel()
        let dirtyLeft = model.left.text
        let dirtyRight = model.right.text
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let previousKeyWindow = NSApplication.shared.keyWindow
        defer {
            close(window)
            previousKeyWindow?.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        guard window.isKeyWindow else {
            throw XCTSkip("Test host could not make AppKit window key.")
        }
        XCTAssertTrue(model.canUndo)

        XCTAssertFalse(ComparisonUndoRouter.canUndo(model: model))
        ComparisonUndoRouter.undo(model: model)
        XCTAssertEqual(model.left.text, dirtyLeft)
        XCTAssertEqual(model.right.text, dirtyRight)

        model.undo()
        await waitUntilIdle(model)
        let undoneLeft = model.left.text
        let undoneRight = model.right.text
        XCTAssertTrue(model.canRedo)
        XCTAssertFalse(ComparisonUndoRouter.canRedo(model: model))
        ComparisonUndoRouter.redo(model: model)
        XCTAssertEqual(model.left.text, undoneLeft)
        XCTAssertEqual(model.right.text, undoneRight)
    }

    func testNewComparisonActionCreatesEmptyComparisonAtModelSeam() async throws {
        let model = try await makeModel(left: "left\n", right: "right\n")
        XCTAssertTrue(model.canCreateEmptyComparison)

        model.createEmptyComparison()

        XCTAssertTrue(model.isReady)
        XCTAssertTrue(model.hasScratchpad)
        XCTAssertEqual(model.left.text, "")
        XCTAssertEqual(model.right.text, "")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    private func assertEnabled(
        _ expected: Set<CommandAction>,
        on model: ComparisonModel,
        focusedTextView: NSTextView? = nil,
        state: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            enabledCommands(on: model, focusedTextView: focusedTextView),
            expected,
            state,
            file: file,
            line: line
        )
    }

    private func enabledCommands(
        on model: ComparisonModel,
        focusedTextView: NSTextView?
    ) -> Set<CommandAction> {
        Set(
            CommandAction.allCases.filter { command in
                switch command {
                case .newComparison:
                    model.canCreateEmptyComparison
                case .openComparison:
                    !model.isWorking
                case .save:
                    model.hasUnsavedChanges && !model.isWorking
                case .undo:
                    ComparisonUndoRouter.canUndo(model: model, focusedTextView: focusedTextView)
                case .redo:
                    ComparisonUndoRouter.canRedo(model: model, focusedTextView: focusedTextView)
                case .selectLineDifference, .selectPreviousLineDifference:
                    model.canSelectLineDifference
                case .refresh:
                    model.canRefresh
                case .changePane, .alternateChangePane:
                    model.isReady && !model.isWorking
                case .previousDifference:
                    model.canSelectPreviousDifference
                case .nextDifference:
                    model.canSelectNextDifference
                case .toggleMergeMode:
                    true
                }
            }
        )
    }

    private func makeDirtyModel() async throws -> ComparisonModel {
        let model = try await makeModel(
            left: "left one\nsame\nleft two\n",
            right: "right one\nsame\nright two\n"
        )
        model.selectFirstDifference()
        ComparisonCopyCommand.selectedToRight.perform(on: model)
        await waitUntilIdle(model)
        XCTAssertTrue(model.hasUnsavedChanges)
        return model
    }

    private func makeModel(left: String, right: String) async throws -> ComparisonModel {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let leftURL = directory.appending(path: "left.txt")
        let rightURL = directory.appending(path: "right.txt")
        try Data(left.utf8).write(to: leftURL)
        try Data(right.utf8).write(to: rightURL)

        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        XCTAssertTrue(model.isReady)
        XCTAssertTrue(model.isComparisonCurrent)
        return model
    }

    private func requestLineDifferenceFocus(on model: ComparisonModel, rowID: DiffRow.ID) {
        model.activateRow(rowID)
        model.activateSide(.left)
        model.selectLineDifference()
        XCTAssertNotNil(model.focusRequest)
    }

    private func close(_ window: NSWindow) {
        window.makeFirstResponder(nil)
        window.contentView?.subviews.forEach { view in
            (view as? NSTextView)?.undoManager?.removeAllActions()
            view.removeFromSuperview()
        }
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    private func waitUntilIdle(_ model: ComparisonModel) async {
        await withCheckedContinuation { continuation in
            model.whenIdle { continuation.resume() }
        }
    }
}

private enum CommandAction: CaseIterable {
    case newComparison
    case openComparison
    case save
    case undo
    case redo
    case selectLineDifference
    case selectPreviousLineDifference
    case refresh
    case changePane
    case alternateChangePane
    case previousDifference
    case nextDifference
    case toggleMergeMode
}
