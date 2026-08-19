import AppKit
import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

@MainActor
final class CommandRoutingRegressionTests: XCTestCase {
    func testWindowAndTextFocusChangesInvalidateCommandRouting() {
        let model = ComparisonModel()
        let delegate = ApplicationDelegate(
            model: model,
            sessionStore: ComparisonSessionStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
            )
        )
        let notifications = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSText.didBeginEditingNotification,
            NSText.didChangeNotification,
            NSText.didEndEditingNotification
        ]
        for (index, name) in notifications.enumerated() {
            NotificationCenter.default.post(name: name, object: nil)
            XCTAssertEqual(model.commandRoutingRevision, index + 1)
        }
        _ = delegate
    }

    func testConfigurationReportMapsRuntimeMetadataOptionsAndRedactsPrivateValues() throws {
        let privateRoot = "/Users/private-user"
        let metadata = MacMergeConfigurationMetadata(
            appName: "MacMerge",
            appVersion: "1.2.3",
            buildVersion: "45",
            operatingSystem: "macOS 15.0 at \(privateRoot)",
            architecture: "arm64",
            localeIdentifier: "en_US",
            sandboxState: .enabled,
            redactionRoots: [privateRoot],
            usernames: ["private-user"]
        )
        let options = LineDiffOptions(
            algorithm: .histogram,
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true,
            ignoreBlankLines: true,
            ignoreComments: true,
            ignoreLineEndings: false,
            indentHeuristic: true,
            detectMovedBlocks: true,
            lineFiltersEnabled: false,
            lineFilters: [LineFilterRule(pattern: "secret")],
            substitutionsEnabled: true,
            substitutions: [
                SubstitutionRule(pattern: "before", replacement: "after")
            ]
        )

        let report = try MacMergeConfigurationReporter.build(
            metadata: metadata,
            options: options
        )

        XCTAssertTrue(report.hasPrefix("MacMerge Configuration Report\n"))
        XCTAssertTrue(report.contains("Version: 1.2.3\n"))
        XCTAssertTrue(report.contains("Build: 45\n"))
        XCTAssertTrue(report.contains("Operating System: macOS 15.0 at <home>\n"))
        XCTAssertTrue(report.contains("Architecture: arm64\n"))
        XCTAssertTrue(report.contains("Locale: en_US\n"))
        XCTAssertTrue(report.contains("Sandbox: enabled\n"))
        XCTAssertTrue(
            report.contains(
                "Maximum text file bytes per side: \(TextFileDocumentIO.maximumFileSize)\n"
            )
        )
        XCTAssertTrue(report.contains("Algorithm: histogram\n"))
        XCTAssertTrue(report.contains("Detect moved blocks: enabled\n"))
        XCTAssertTrue(report.contains("Ignore line endings: disabled\n"))
        XCTAssertTrue(report.contains("Line filters: disabled (1)\n"))
        XCTAssertTrue(report.contains("Substitutions: enabled (1)\n"))
        XCTAssertTrue(report.contains("Whitespace: ignoreChanges\n"))
        XCTAssertFalse(report.contains(privateRoot))
        XCTAssertFalse(report.contains("private-user"))
        XCTAssertFalse(report.contains("secret"))
        XCTAssertFalse(report.contains("before"))
    }

    func testClipboardTextWriterUsesRequestedPasteboard() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("MacMergeTests.\(UUID().uuidString)")
        )
        pasteboard.setString("old", forType: .string)

        try ClipboardTextWriter.write("new", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "new")
    }

    func testFocusedTextViewUndoRedoTakesPriorityBeforeComparisonFallback() async throws {
        let model = try await makeDirtyModel()
        let dirtyRight = model.right.text
        let originalRight = "right one\nsame\nright two\n"
        XCTAssertTrue(model.canUndo)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { close(window) }

        let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)

        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertTrue(window.firstResponder === textView)
        textView.insertText("editor edit", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertTrue(ComparisonUndoRouter.canUndo(model: model, in: window))
        ComparisonUndoRouter.undo(model: model, in: window)
        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(model.right.text, dirtyRight)
        XCTAssertTrue(model.canUndo, "Focused editor undo must not consume comparison history")

        XCTAssertTrue(ComparisonUndoRouter.canRedo(model: model, in: window))
        ComparisonUndoRouter.redo(model: model, in: window)
        XCTAssertEqual(textView.string, "editor edit")
        XCTAssertEqual(model.right.text, dirtyRight)

        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertNil(ComparisonUndoRouter.focusedEditableTextView(in: window))
        ComparisonUndoRouter.undo(model: model, in: window)
        await waitUntilIdle(model)
        XCTAssertEqual(model.right.text, originalRight)
        XCTAssertEqual(textView.string, "editor edit")

        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertNil(ComparisonUndoRouter.focusedEditableTextView(in: window))
        XCTAssertTrue(ComparisonUndoRouter.canRedo(model: model, in: window))
        ComparisonUndoRouter.redo(model: model, in: window)
        await waitUntilIdle(model)
        XCTAssertEqual(model.right.text, dirtyRight)
        XCTAssertEqual(textView.string, "editor edit")
    }

    func testProductionCommandPredicatesCoverEmptySelectedAndLoadingStates() async throws {
        let empty = ComparisonModel()
        XCTAssertTrue(empty.canCreateEmptyComparison)
        XCTAssertFalse(empty.canRefresh)
        XCTAssertFalse(empty.canSelectLineDifference)
        XCTAssertFalse(empty.canSelectNextDifference)
        XCTAssertFalse(empty.canSelectPreviousDifference)
        XCTAssertFalse(ComparisonUndoRouter.canUndo(model: empty, focusedTextView: nil))
        XCTAssertFalse(ComparisonUndoRouter.canRedo(model: empty, focusedTextView: nil))

        let selected = try await makeSelectedModel()
        XCTAssertTrue(selected.canCreateEmptyComparison)
        XCTAssertTrue(selected.canRefresh)
        XCTAssertTrue(selected.canSelectLineDifference)
        XCTAssertTrue(selected.canSelectNextDifference)
        XCTAssertTrue(selected.canSelectPreviousDifference)

        selected.refresh()
        XCTAssertTrue(selected.isWorking)
        XCTAssertFalse(selected.canCreateEmptyComparison)
        XCTAssertFalse(selected.canRefresh)
        XCTAssertFalse(selected.canSelectLineDifference)
        XCTAssertFalse(selected.canSelectNextDifference)
        XCTAssertFalse(selected.canSelectPreviousDifference)
        await waitUntilIdle(selected)
    }

    func testProductionPolicyStateIsTwoWayAndCarriesPaneEditability() async throws {
        let empty = ComparisonModel()
        let emptyState = empty.mergeCommandState()
        XCTAssertFalse(emptyState.isThreeWay)
        XCTAssertFalse(emptyState.isAutoMergeEligible)
        XCTAssertFalse(emptyState.left.isEditable)
        XCTAssertFalse(emptyState.right.isEditable)
        XCTAssertEqual(
            MergeCommandPolicy.evaluate(emptyState).autoMerge,
            .disabled(.autoMergeUnavailable)
        )

        let loaded = try await makeModel(left: "left\n", right: "right\n")
        let loadedState = loaded.mergeCommandState()
        XCTAssertFalse(loadedState.isThreeWay)
        XCTAssertTrue(loadedState.left.isEditable)
        XCTAssertTrue(loadedState.right.isEditable)

        loaded.setEditable(false, on: .right)
        let readOnlyState = loaded.mergeCommandState()
        XCTAssertTrue(readOnlyState.left.isEditable)
        XCTAssertFalse(readOnlyState.right.isEditable)
    }

    func testReadOnlyCommandsToggleOnlyRequestedLoadedPaneAndRejectLoading() async throws {
        let empty = ComparisonModel()
        XCTAssertEqual(
            ComparisonReadOnlyCommand.allCases.map(\.menuTitle),
            ["Left Read-Only", "Right Read-Only"]
        )
        XCTAssertFalse(ComparisonReadOnlyCommand.left.isEnabled(on: empty))
        ComparisonReadOnlyCommand.left.perform(on: empty)
        XCTAssertFalse(empty.left.isEditable)

        let model = try await makeModel(left: "left\n", right: "right\n")
        XCTAssertTrue(ComparisonReadOnlyCommand.right.isEnabled(on: model))
        XCTAssertFalse(ComparisonReadOnlyCommand.right.isOn(on: model))

        ComparisonReadOnlyCommand.right.perform(on: model)

        XCTAssertTrue(model.left.isEditable)
        XCTAssertFalse(model.right.isEditable)
        XCTAssertTrue(ComparisonReadOnlyCommand.right.isOn(on: model))
        model.selectFirstDifference()
        XCTAssertFalse(ComparisonCopyCommand.selectedToRight.isEnabled(on: model))
        XCTAssertTrue(ComparisonCopyCommand.selectedToLeft.isEnabled(on: model))

        model.refresh()
        XCTAssertTrue(model.isWorking)
        XCTAssertFalse(ComparisonReadOnlyCommand.right.isEnabled(on: model))
        ComparisonReadOnlyCommand.right.perform(on: model)
        XCTAssertFalse(model.right.isEditable)
        await waitUntilIdle(model)

        model.reloadFromDisk()
        await waitUntilIdle(model)
        XCTAssertFalse(model.right.isEditable)

        let destination = try XCTUnwrap(model.right.url)
            .deletingLastPathComponent()
            .appending(path: "right-copy.txt")
        let savedAs = await withCheckedContinuation { continuation in
            model.saveAs(.right, destination: destination) {
                continuation.resume(returning: $0)
            }
        }
        await waitUntilIdle(model)
        XCTAssertTrue(savedAs)
        XCTAssertEqual(model.right.url, destination)
        XCTAssertFalse(model.right.isEditable)

        ComparisonReadOnlyCommand.right.setReadOnly(false, on: model)
        XCTAssertTrue(model.right.isEditable)
        XCTAssertFalse(ComparisonReadOnlyCommand.right.isOn(on: model))

        ComparisonReadOnlyCommand.left.perform(on: model)
        XCTAssertFalse(model.left.isEditable)
        XCTAssertTrue(model.right.isEditable)
        XCTAssertTrue(ComparisonReadOnlyCommand.left.isOn(on: model))
        XCTAssertFalse(ComparisonReadOnlyCommand.right.isOn(on: model))
    }

    func testSaveAllRejectsDirtyReadOnlyPaneWithoutWritingIt() async throws {
        let model = try await makeDirtyModel()
        let rightURL = try XCTUnwrap(model.right.url)
        let leftURL = try XCTUnwrap(model.left.url)
        let rightDiskText = try String(contentsOf: rightURL, encoding: .utf8)
        let leftDiskText = try String(contentsOf: leftURL, encoding: .utf8)
        let rightDirtyText = model.right.text
        model.editText("dirty left\n", on: .left)
        await waitUntilIdle(model)
        let leftDirtyText = model.left.text
        XCTAssertNotEqual(rightDirtyText, rightDiskText)
        XCTAssertNotEqual(leftDirtyText, leftDiskText)
        model.setEditable(false, on: .right)

        let saved = await withCheckedContinuation { continuation in
            model.saveAllChanges { continuation.resume(returning: $0) }
        }

        XCTAssertFalse(saved)
        XCTAssertFalse(model.right.isEditable)
        XCTAssertTrue(model.left.isDirty)
        XCTAssertTrue(model.right.isDirty)
        XCTAssertEqual(model.left.text, leftDirtyText)
        XCTAssertEqual(model.right.text, rightDirtyText)
        XCTAssertEqual(try String(contentsOf: leftURL, encoding: .utf8), leftDiskText)
        XCTAssertEqual(try String(contentsOf: rightURL, encoding: .utf8), rightDiskText)
        XCTAssertEqual(
            model.errorMessage,
            "Make the right file editable before saving its changes."
        )
    }

    func testSaveReloadableChangesReportsDirtyReadOnlyPaneWithoutWritingIt() async throws {
        let model = try await makeDirtyModel()
        let rightURL = try XCTUnwrap(model.right.url)
        let diskText = try String(contentsOf: rightURL, encoding: .utf8)
        model.setEditable(false, on: .right)

        let saved = await withCheckedContinuation { continuation in
            model.saveReloadableChanges { continuation.resume(returning: $0) }
        }

        XCTAssertFalse(saved)
        XCTAssertEqual(
            model.errorMessage,
            "Make the right file editable before saving its changes."
        )
        XCTAssertTrue(model.right.isDirty)
        XCTAssertEqual(try String(contentsOf: rightURL, encoding: .utf8), diskText)
    }

    func testSaveCommandWrappersGuardEnablementAndExecutionDuringLoading() async throws {
        let model = try await makeDirtyModel()
        XCTAssertFalse(ComparisonSaveCommand.left.isEnabled(on: model))
        XCTAssertTrue(ComparisonSaveCommand.right.isEnabled(on: model))

        model.refresh()
        XCTAssertTrue(model.isWorking)
        XCTAssertFalse(ComparisonSaveCommand.left.isEnabled(on: model))
        XCTAssertFalse(ComparisonSaveCommand.right.isEnabled(on: model))

        let saveResult = await withCheckedContinuation { continuation in
            ComparisonSaveCommand.right.perform(on: model) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertFalse(saveResult)
        XCTAssertTrue(model.right.isDirty)
        await waitUntilIdle(model)

        XCTAssertTrue(ComparisonSaveCommand.right.isEnabled(on: model))
        let enabledSaveResult = await withCheckedContinuation { continuation in
            ComparisonSaveCommand.right.perform(on: model) {
                continuation.resume(returning: $0)
            }
        }
        await waitUntilIdle(model)
        XCTAssertTrue(enabledSaveResult)
        XCTAssertFalse(model.right.isDirty)
    }

    func testSaveCommandWrapperRejectsReadOnlyPaneWithoutExecuting() async throws {
        let model = try await makeDirtyModel()
        model.setEditable(false, on: .right)
        XCTAssertFalse(ComparisonSaveCommand.right.isEnabled(on: model))

        let saveResult = await withCheckedContinuation { continuation in
            ComparisonSaveCommand.right.perform(on: model) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertFalse(saveResult)
        XCTAssertTrue(model.right.isDirty)
        XCTAssertFalse(model.isWorking)
    }

    func testDifferenceSelectionAndPaneActionsUpdateModelState() async throws {
        let model = try await makeSelectedModel()
        let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs[1])

        let lineSelectionRevision = model.lineDifferenceSelectionRevision
        model.selectLineDifference()
        XCTAssertEqual(model.lineDifferenceSelectionRevision, lineSelectionRevision + 1)
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .next)
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs[1])

        model.selectNextDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs[2])

        model.selectPreviousDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs[1])

        let paneFocusRevision = model.paneFocusRevision
        model.changePane()
        XCTAssertEqual(model.activeSide, .right)
        XCTAssertEqual(model.paneFocusRevision, paneFocusRevision + 1)
        XCTAssertEqual(
            model.focusRequest?.action,
            .focusEditor(rowID: differenceIDs[1], side: .right, centersRow: false)
        )
    }

    func testOpenReplacementInvalidatesFocusAtStartCommitAndFailure() async throws {
        let model = try await makeModel(
            left: "before OLD value\n",
            right: "before NEW value\n"
        )
        let originalRow = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        let replacement = try temporaryFile(name: "replacement.txt", content: "after OLD value\n")

        requestLineDifferenceFocus(on: model, rowID: originalRow.id)
        let staleOpenRequest = try XCTUnwrap(model.focusRequest)
        let table = ComparisonUpdateTestHarness(model: model)
        defer { table.close() }
        let selectionBeforeOpen = table.selectedRange(rowID: originalRow.id, on: .left)
        table.update(focusRequest: staleOpenRequest)
        let generationBeforeOpen = model.focusGeneration
        model.enqueueReplacingOpen(replacement, into: .left)
        XCTAssertGreaterThan(model.focusGeneration, generationBeforeOpen)
        XCTAssertNil(model.focusRequest)
        model.continueEditing(on: .left, lineNumber: 1)
        let generationDuringOpen = model.focusGeneration

        await waitUntilIdle(model)

        XCTAssertGreaterThan(model.focusGeneration, generationDuringOpen)
        XCTAssertNil(model.focusRequest)
        let replacementRow = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        XCTAssertEqual(replacementRow.id, originalRow.id)
        XCTAssertEqual(table.selectedRange(rowID: originalRow.id, on: .left), selectionBeforeOpen)

        requestLineDifferenceFocus(on: model, rowID: replacementRow.id)
        let staleFailedOpenRequest = try XCTUnwrap(model.focusRequest)
        table.update(focusRequest: staleFailedOpenRequest)
        let selectionBeforeFailedOpen = table.selectedRange(rowID: originalRow.id, on: .left)
        let missing = replacement.deletingLastPathComponent().appending(path: "missing.txt")
        model.enqueueReplacingOpen(missing, into: .left)
        model.continueEditing(on: .left, lineNumber: 1)
        let generationDuringFailedOpen = model.focusGeneration

        await waitUntilIdle(model)

        XCTAssertGreaterThan(model.focusGeneration, generationDuringFailedOpen)
        XCTAssertNil(model.focusRequest)
        XCTAssertEqual(model.left.url, replacement)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(
            table.selectedRange(rowID: originalRow.id, on: .left),
            selectionBeforeFailedOpen
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

    private func makeSelectedModel() async throws -> ComparisonModel {
        let model = try await makeModel(
            left: "left one\nsame\nleft two\nsame\nleft three\n",
            right: "right one\nsame\nright two\nsame\nright three\n"
        )
        let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(differenceIDs.count, 3)
        model.selectDifference(differenceIDs[1])
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
        return model
    }

    private func requestLineDifferenceFocus(on model: ComparisonModel, rowID: DiffRow.ID) {
        model.activateRow(rowID)
        model.activateSide(.left)
        model.selectLineDifference()
        XCTAssertNotNil(model.focusRequest)
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

    private func close(_ window: NSWindow) {
        window.makeFirstResponder(nil)
        window.contentView = nil
        window.close()
    }

    private func waitUntilIdle(_ model: ComparisonModel) async {
        await withCheckedContinuation { continuation in
            model.whenIdle { continuation.resume() }
        }
    }
}
