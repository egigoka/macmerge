import Foundation
@testable import MacMerge
import MacMergeCore
import XCTest

@MainActor
final class ComparisonModelTests: XCTestCase {
    func testNewComparisonCreatesTwoEditableUntitledBuffers() async {
        let model = ComparisonModel()

        model.createEmptyComparison()
        model.editText("left\n", on: .left)
        model.editText("right\n", on: .right)
        await waitUntil { model.summary.differences == 1 }

        XCTAssertTrue(model.isReady)
        XCTAssertTrue(model.hasScratchpad)
        XCTAssertEqual(model.left.displayName, "Untitled Left")
        XCTAssertEqual(model.right.displayName, "Untitled Right")
        XCTAssertEqual(model.summary.differences, 1)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testUntitledBufferSavesToChosenDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "saved.txt")
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText("saved text\n", on: .left)

        let saved = await withCheckedContinuation { continuation in
            model.save(.left, scratchpadDestination: destination) { continuation.resume(returning: $0) }
        }
        await waitUntilIdle(model)

        XCTAssertTrue(saved)
        XCTAssertEqual(model.left.url, destination)
        XCTAssertFalse(model.left.isDirty)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "saved text\n")
    }

    func testAlignedScratchpadRowsEditMergeAndUndoThroughSharedModel() async throws {
        let model = ComparisonModel()
        let insertionRow = DiffRow.ID(leftNumber: nil, rightNumber: nil)
        model.createEmptyComparison()

        model.editScratchpadLine(
            rowID: insertionRow,
            on: .left,
            replacement: "test\nkek\ntesting"
        )
        model.finishScratchpadLineEditing(rowID: insertionRow, on: .left)
        await waitUntil { model.left.text == "test\nkek\ntesting" && model.isComparisonCurrent }
        model.editScratchpadLine(
            rowID: insertionRow,
            on: .right,
            replacement: "test\nlol\ntesting"
        )
        model.finishScratchpadLineEditing(rowID: insertionRow, on: .right)
        await waitUntil { model.summary.differences == 1 && model.isComparisonCurrent }

        XCTAssertEqual(model.rows.map(\.kind), [.unchanged, .modified, .unchanged])
        XCTAssertEqual(model.summary.differences, 1)
        let changedID = try XCTUnwrap(model.rows.first(where: { $0.kind == .modified })?.id)

        model.selectDifference(changedID)
        model.mergeSelectedDifference(direction: .leftToRight, advance: false)
        await waitUntilIdle(model)

        XCTAssertEqual(model.right.text, model.left.text)
        XCTAssertEqual(model.summary.differences, 0)
        XCTAssertTrue(model.canUndo)

        model.undo()
        await waitUntilIdle(model)

        XCTAssertEqual(model.right.text, "test\nlol\ntesting")
        XCTAssertEqual(model.summary.differences, 1)
    }

    func testScratchpadRowTypingCoalescesIntoOneUndoStep() async {
        let model = ComparisonModel()
        let insertionRow = DiffRow.ID(leftNumber: nil, rightNumber: nil)
        model.createEmptyComparison()

        model.editScratchpadLine(rowID: insertionRow, on: .left, replacement: "a")
        model.editScratchpadLine(rowID: insertionRow, on: .left, replacement: "ab")
        model.editScratchpadLine(rowID: insertionRow, on: .left, replacement: "abc")
        model.finishScratchpadLineEditing(rowID: insertionRow, on: .left)
        await waitUntil { model.isComparisonCurrent && model.left.text == "abc" }

        model.undo()
        await waitUntil { !model.isWorking && model.isComparisonCurrent }

        XCTAssertEqual(model.left.text, "")
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(model.canRedo)
    }

    func testTwoFileOpenCommitsBothDocumentsTogether() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "left\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "right\n")
        let model = ComparisonModel()

        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.url, leftURL)
        XCTAssertEqual(model.right.url, rightURL)
        XCTAssertTrue(model.isReady)
    }

    func testTwoFileOpenFailurePreservesExistingComparison() async throws {
        let originalLeft = try temporaryFile(name: "original-left.txt", content: "left\n")
        let originalRight = try temporaryFile(name: "original-right.txt", content: "right\n")
        let replacement = try temporaryFile(name: "replacement.txt", content: "replacement\n")
        let missing = replacement.deletingLastPathComponent().appending(path: "missing.txt")
        let model = ComparisonModel()
        model.enqueueOpen([originalLeft, originalRight])
        await waitUntilIdle(model)

        model.enqueueOpen([replacement, missing])
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.url, originalLeft)
        XCTAssertEqual(model.right.url, originalRight)
        XCTAssertTrue(model.isReady)
    }

    func testExplicitSideOpenRunsAfterPreviouslyQueuedPair() async throws {
        let pairLeft = try temporaryFile(name: "pair-left.txt", content: "pair left\n")
        let pairRight = try temporaryFile(name: "pair-right.txt", content: "pair right\n")
        let importedRight = try temporaryFile(name: "imported-right.txt", content: "imported right\n")
        let model = ComparisonModel()

        model.enqueueOpen([pairLeft, pairRight])
        model.enqueueOpen(importedRight, into: .right)
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.url, pairLeft)
        XCTAssertEqual(model.right.url, importedRight)
        XCTAssertTrue(model.isReady)
    }

    func testDiscardReplacementBypassesDirtyGuard() async throws {
        let original = try temporaryFile(name: "original.txt", content: "original\n")
        let edited = try temporaryFile(name: "edited.txt", content: "edited\n")
        let replacement = try temporaryFile(name: "replacement.txt", content: "replacement\n")
        let model = ComparisonModel()
        model.enqueueOpen([original, edited])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first(where: { $0.kind != .unchanged })?.id)
        model.merge(rowID: rowID, direction: .rightToLeft)
        await waitUntilIdle(model)
        XCTAssertTrue(model.left.isDirty)

        model.enqueueReplacingOpen(replacement, into: .left)
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.url, replacement)
        XCTAssertEqual(model.left.text, "replacement\n")
        XCTAssertFalse(model.left.isDirty)
    }

    func testAmbiguousEncodingCanBeSelectedAndRetried() async throws {
        let url = try temporaryFile(
            name: "jis.txt",
            data: Data([0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42])
        )
        let model = ComparisonModel()

        model.enqueueOpen(url, into: .left)
        await waitUntilIdle(model)

        XCTAssertEqual(model.pendingEncodingSelection?.candidates, [.utf8, .iso2022JP])
        model.selectPendingEncoding(.iso2022JP)
        await waitUntilIdle(model)

        XCTAssertNil(model.pendingEncodingSelection)
        XCTAssertEqual(model.left.text, "あ")
        XCTAssertEqual(model.left.document?.encoding, .iso2022JP)
    }

    func testDifferenceNavigationSelectsFirstAndLast() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one\nsame\ntwo\nsame\nthree\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "ONE\nsame\nTWO\nsame\nTHREE\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(differenceIDs.count, 3)

        model.selectLastDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs.last)
        model.selectFirstDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs.first)
    }

    func testSelectedCopyAndAdvanceSelectsFollowingDifference() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one\nsame\ntwo\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "ONE\nsame\nTWO\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        model.selectFirstDifference()

        model.mergeSelectedDifference(direction: .leftToRight, advance: true)
        await waitUntilIdle(model)

        XCTAssertEqual(model.summary.differences, 1)
        XCTAssertEqual(model.selectedDifferenceID, model.rows.first(where: { $0.kind != .unchanged })?.id)
    }

    func testSelectedCopyAndAdvanceStopsAfterLastDifference() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one\nsame\ntwo\nsame\nthree\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "ONE\nsame\nTWO\nsame\nTHREE\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        model.selectLastDifference()

        model.mergeSelectedDifference(direction: .leftToRight, advance: true)
        await waitUntilIdle(model)

        let remainingIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)
        XCTAssertEqual(remainingIDs.count, 2)
        XCTAssertNil(model.selectedDifferenceID)
    }

    func testDifferenceNavigationStopsAtEndpoints() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one\nsame\ntwo\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "ONE\nsame\nTWO\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let differenceIDs = model.rows.filter { $0.kind != .unchanged }.map(\.id)

        model.selectFirstDifference()
        XCTAssertFalse(model.canSelectPreviousDifference)
        model.selectPreviousDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs.first)

        model.selectLastDifference()
        XCTAssertFalse(model.canSelectNextDifference)
        model.selectNextDifference()
        XCTAssertEqual(model.selectedDifferenceID, differenceIDs.last)
    }

    func testSaveAllCompletionCanAcceptPendingExternalOpen() async throws {
        let originalLeft = try temporaryFile(name: "original-left.txt", content: "left\n")
        let originalRight = try temporaryFile(name: "original-right.txt", content: "right\n")
        let replacementLeft = try temporaryFile(name: "replacement-left.txt", content: "new left\n")
        let replacementRight = try temporaryFile(name: "replacement-right.txt", content: "new right\n")
        let model = ComparisonModel()
        model.enqueueOpen([originalLeft, originalRight])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first(where: { $0.kind != .unchanged })?.id)
        model.merge(rowID: rowID, direction: .leftToRight)
        await waitUntilIdle(model)

        model.enqueueOpen([replacementLeft, replacementRight])
        XCTAssertNotNil(model.pendingExternalOpenURLs)
        let saved = await withCheckedContinuation { continuation in
            model.saveAllChanges { saved in
                if saved {
                    model.acceptPendingExternalOpen()
                }
                continuation.resume(returning: saved)
            }
        }
        await waitUntilIdle(model)

        XCTAssertTrue(saved)
        XCTAssertEqual(model.left.url, replacementLeft)
        XCTAssertEqual(model.right.url, replacementRight)
    }

    func testCanonicalizingSaveAllAcceptsPendingExternalOpenAfterRecompare() async throws {
        let originalLeft = try temporaryFile(name: "original-left.txt", content: "ｱ")
        let originalRight = try temporaryFile(
            name: "original-right.txt",
            data: Data([0x1B, 0x24, 0x42, 0x25, 0x24, 0x1B, 0x28, 0x42])
        )
        let replacementLeft = try temporaryFile(name: "replacement-left.txt", content: "new left\n")
        let replacementRight = try temporaryFile(name: "replacement-right.txt", content: "new right\n")
        let model = ComparisonModel()
        model.enqueueOpen([originalLeft, originalRight])
        await waitUntilIdle(model)
        model.selectPendingEncoding(.iso2022JP)
        await waitUntilIdle(model)
        model.selectFirstDifference()
        model.mergeSelectedDifference(direction: .leftToRight, advance: false)
        await waitUntilIdle(model)
        XCTAssertTrue(model.right.isDirty)

        model.enqueueOpen([replacementLeft, replacementRight])
        XCTAssertNotNil(model.pendingExternalOpenURLs)
        let saved = await withCheckedContinuation { continuation in
            model.saveAllChanges { saved in
                if saved {
                    model.acceptPendingExternalOpen()
                }
                continuation.resume(returning: saved)
            }
        }
        await waitUntilIdle(model)

        XCTAssertTrue(saved)
        XCTAssertEqual(model.left.url, replacementLeft)
        XCTAssertEqual(model.right.url, replacementRight)
    }

    func testReloadFromDiskReadsBothCleanFiles() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "old left\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "old right\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        try Data("new left\n".utf8).write(to: leftURL)
        try Data("new right\n".utf8).write(to: rightURL)

        model.reloadFromDisk()
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.text, "new left\n")
        XCTAssertEqual(model.right.text, "new right\n")
    }

    func testReloadPreservesScratchpadSideIdentity() async throws {
        let rightURL = try temporaryFile(name: "right.txt", content: "old right\n")
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText("scratchpad left\n", on: .left)
        model.enqueueReplacingOpen(rightURL, into: .right)
        await waitUntilIdle(model)
        try Data("new right\n".utf8).write(to: rightURL)

        model.reloadFromDisk()
        await waitUntilIdle(model)

        XCTAssertTrue(model.left.isUntitled)
        XCTAssertEqual(model.left.text, "scratchpad left\n")
        XCTAssertEqual(model.right.url, rightURL)
        XCTAssertEqual(model.right.text, "new right\n")
    }

    func testSaveAllRejectsSameScratchpadDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "same.txt")
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText("left\n", on: .left)
        model.editText("right\n", on: .right)

        let saved = await withCheckedContinuation { continuation in
            model.saveAllChanges(
                scratchpadDestinations: [.left: destination, .right: destination]
            ) { continuation.resume(returning: $0) }
        }

        XCTAssertFalse(saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNotNil(model.errorMessage)
    }

    func testScratchpadSaveRejectsOtherLoadedDocumentDestination() async throws {
        let rightURL = try temporaryFile(name: "right.txt", content: "right\n")
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText("left\n", on: .left)
        model.enqueueReplacingOpen(rightURL, into: .right)
        await waitUntilIdle(model)

        let saved = await withCheckedContinuation { continuation in
            model.save(.left, scratchpadDestination: rightURL) {
                continuation.resume(returning: $0)
            }
        }

        XCTAssertFalse(saved)
        XCTAssertEqual(try String(contentsOf: rightURL, encoding: .utf8), "right\n")
        XCTAssertTrue(model.left.isUntitled)
    }

    func testSaveAllRejectsScratchpadAliasOfLoadedDocument() async throws {
        let rightURL = try temporaryFile(name: "right.txt", content: "right\n")
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText("left\n", on: .left)
        model.enqueueReplacingOpen(rightURL, into: .right)
        await waitUntilIdle(model)

        let saved = await withCheckedContinuation { continuation in
            model.saveAllChanges(scratchpadDestinations: [.left: rightURL]) {
                continuation.resume(returning: $0)
            }
        }

        XCTAssertFalse(saved)
        XCTAssertEqual(try String(contentsOf: rightURL, encoding: .utf8), "right\n")
        XCTAssertTrue(model.left.isUntitled)
    }

    func testScratchpadSavePreservesUndoHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "left.txt")
        let insertionRow = DiffRow.ID(leftNumber: nil, rightNumber: nil)
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editScratchpadLine(rowID: insertionRow, on: .left, replacement: "draft")
        model.finishScratchpadLineEditing(rowID: insertionRow, on: .left)
        await waitUntil { model.isComparisonCurrent && model.left.text == "draft" }

        let saved = await withCheckedContinuation { continuation in
            model.save(.left, scratchpadDestination: destination) {
                continuation.resume(returning: $0)
            }
        }
        await waitUntilIdle(model)

        XCTAssertTrue(saved)
        XCTAssertTrue(model.canUndo)
        model.undo()
        await waitUntilIdle(model)
        XCTAssertEqual(model.left.text, "")
        XCTAssertTrue(model.left.isDirty)
    }

    func testDiscardAndReloadRecoversDirtyFileChangedOnDisk() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "left\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "right\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first(where: { $0.kind != .unchanged })?.id)
        model.merge(rowID: rowID, direction: .leftToRight)
        await waitUntilIdle(model)
        try Data("external\n".utf8).write(to: rightURL)

        model.discardChangesAndReloadFromDisk()
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.text, "left\n")
        XCTAssertEqual(model.right.text, "external\n")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testFailedDiscardReloadKeepsComparisonCoherent() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "left\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "right\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first(where: { $0.kind != .unchanged })?.id)
        model.merge(rowID: rowID, direction: .leftToRight)
        await waitUntilIdle(model)
        let textBeforeReload = (model.left.text, model.right.text)
        let rowsBeforeReload = model.rows
        let summaryBeforeReload = model.summary
        try FileManager.default.removeItem(at: rightURL)

        model.discardChangesAndReloadFromDisk()
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.text, textBeforeReload.0)
        XCTAssertEqual(model.right.text, textBeforeReload.1)
        XCTAssertEqual(model.rows, rowsBeforeReload)
        XCTAssertEqual(model.summary, summaryBeforeReload)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.canUndo)
    }

    func testSaveRecomputesComparisonAfterLegacyCanonicalization() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "ｱ")
        let rightURL = try temporaryFile(
            name: "right.txt",
            data: Data([0x1B, 0x24, 0x42, 0x25, 0x24, 0x1B, 0x28, 0x42])
        )
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        model.selectPendingEncoding(.iso2022JP)
        await waitUntilIdle(model)
        model.selectFirstDifference()
        model.mergeSelectedDifference(direction: .leftToRight, advance: false)
        await waitUntilIdle(model)
        XCTAssertEqual(model.right.text, "ｱ")

        let saved = await withCheckedContinuation { continuation in
            model.save(.right) { continuation.resume(returning: $0) }
        }
        await waitUntilIdle(model)

        XCTAssertTrue(saved)
        XCTAssertEqual(model.right.text, "ア")
        XCTAssertEqual(model.summary.differences, 1)
        XCTAssertFalse(model.canUndo)
    }

    private func waitUntilIdle(_ model: ComparisonModel) async {
        await withCheckedContinuation { continuation in
            model.whenIdle {
                continuation.resume()
            }
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }

    private func temporaryFile(name: String, content: String) throws -> URL {
        try temporaryFile(name: name, data: Data(content.utf8))
    }

    private func temporaryFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}
