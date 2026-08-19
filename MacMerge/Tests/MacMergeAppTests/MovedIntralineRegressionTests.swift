import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

@MainActor
final class MovedIntralineRegressionTests: XCTestCase {
    func testRightToLeftOnlyDirectionalPairProducesConnectorWithoutChangingLookups() throws {
        let movedLeft = [
            "symmetry-duplicate-3191",
            "symmetry-unique-alpha-3192",
            "symmetry-duplicate-3191",
            "symmetry-unique-beta-3193",
            "symmetry-duplicate-3191"
        ]
        let movedRight = [
            "symmetry-duplicate-3191",
            "symmetry-unique-beta-3193",
            "symmetry-duplicate-3191",
            "symmetry-unique-alpha-3192",
            "symmetry-duplicate-3191"
        ]
        let stable = [
            "symmetry-ambiguous-stable-one-3194",
            "symmetry-ambiguous-stable-two-3195",
            "symmetry-ambiguous-stable-three-3196",
            "symmetry-ambiguous-stable-four-3197"
        ]
        let left = ["symmetry-ambiguous-root-3190"] + movedLeft + stable + ["symmetry-ambiguous-tail-3198"]
        let right = ["symmetry-ambiguous-root-3190"] + stable + movedRight + ["symmetry-ambiguous-tail-3198"]
        let result = try LineDiff.compareResult(
            left: left.joined(separator: "\n"),
            right: right.joined(separator: "\n"),
            options: LineDiffOptions(detectMovedBlocks: true)
        )

        XCTAssertFalse(
            (0..<result.movedLines.leftToRightCount).contains {
                let pair = result.movedLines.leftToRightPair(at: $0)
                return pair.leftLine == 4 && pair.rightLine == 6
            })
        XCTAssertTrue(
            (0..<result.movedLines.rightToLeftCount).contains {
                let pair = result.movedLines.rightToLeftPair(at: $0)
                return pair.leftLine == 4 && pair.rightLine == 6
            })

        let map = MovedRowMap(rows: result.rows, movedLines: result.movedLines)
        let leftStart = try XCTUnwrap(result.rows.firstIndex { $0.left?.number == 4 })
        let leftEnd = try XCTUnwrap(result.rows.firstIndex { $0.left?.number == 6 }) + 1
        let rightStart = try XCTUnwrap(result.rows.firstIndex { $0.right?.number == 6 })
        let rightEnd = try XCTUnwrap(result.rows.firstIndex { $0.right?.number == 8 }) + 1
        let leftDirectionalTarget = try XCTUnwrap(result.rows.firstIndex { $0.right?.number == 10 })

        XCTAssertTrue(
            map.blocks.contains(
                MovedRowBlock(
                    leftStartRow: UInt32(leftStart),
                    leftEndRow: UInt32(leftEnd),
                    rightStartRow: UInt32(rightStart),
                    rightEndRow: UInt32(rightEnd)
                )))
        XCTAssertEqual(map.targetRow(forLine: 4, on: .left), leftDirectionalTarget)
        XCTAssertEqual(map.targetRow(forLine: 6, on: .right), leftStart)
    }

    func testHugeSuffixOnlyDifferenceDoesNotHighlightUnverifiedPrefix() {
        let grapheme = "👨‍👩‍👧‍👦"
        let text = String(repeating: grapheme, count: 20_000) + "left"
        let other = String(repeating: grapheme, count: 20_000) + "right"

        XCTAssertTrue(intralineDifferenceRanges(in: text, comparedWith: other).isEmpty)
    }

    func testOversizedSingleGraphemeDoesNotProduceInvalidFallback() {
        let text = "a" + String(repeating: "\u{301}", count: 20_000)
        let other = "b" + String(repeating: "\u{301}", count: 20_000)

        XCTAssertTrue(intralineDifferenceRanges(in: text, comparedWith: other).isEmpty)
    }

    func testOrdinaryIntralineRangesRemainExact() {
        let text = "alpha old middle stale omega"

        XCTAssertEqual(
            intralineDifferenceRanges(in: text, comparedWith: "alpha new middle fresh omega"),
            [
                NSRange(location: 6, length: 3),
                NSRange(location: 17, length: 0),
                NSRange(location: 18, length: 4)
            ]
        )
    }

    func testChangesSeparatedByOneUnchangedGraphemeRemainSeparate() {
        XCTAssertEqual(
            intralineDifferenceRanges(in: "aXbYc", comparedWith: "aPbQc"),
            [
                NSRange(location: 1, length: 1),
                NSRange(location: 3, length: 1)
            ]
        )
    }

    func testPureDeletionRangesRemainSelectableCaretAnchors() {
        XCTAssertEqual(
            intralineDifferenceRanges(in: "ac", comparedWith: "abc"),
            [NSRange(location: 1, length: 0)]
        )
        XCTAssertEqual(
            intralineDifferenceRanges(in: "bc", comparedWith: "abc"),
            [NSRange(location: 0, length: 0)]
        )
        XCTAssertEqual(
            intralineDifferenceRanges(in: "ab", comparedWith: "abc"),
            [NSRange(location: 2, length: 0)]
        )

        let ranges = [
            NSRange(location: 0, length: 0),
            NSRange(location: 2, length: 1),
        ]
        XCTAssertEqual(
            lineDifferenceRange(
                in: ranges,
                from: NSRange(location: 0, length: 0),
                direction: .next,
                advancesFromSelection: false
            ),
            ranges[0]
        )
    }

    func testMixedInsertionAndDeletionAnchorsFollowF4Order() throws {
        let ranges = intralineDifferenceRanges(in: "abXef", comparedWith: "aYbcdeZf")
        let expected = [
            NSRange(location: 1, length: 0),
            NSRange(location: 2, length: 1),
            NSRange(location: 4, length: 0),
        ]
        XCTAssertEqual(ranges, expected)

        var selection = NSRange(location: 0, length: 0)
        for range in expected {
            selection = try XCTUnwrap(
                lineDifferenceRange(in: ranges, from: selection, direction: .next)
            )
            XCTAssertEqual(selection, range)
        }
        XCTAssertEqual(
            lineDifferenceRange(in: ranges, from: selection, direction: .next),
            expected[0]
        )
    }

    func testStaleComparisonDisablesLineDifferenceEnableAndAction() async throws {
        let model = await makeCurrentModel(left: "ac\n", right: "abc\n")
        let row = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        model.activateRow(row.id)
        model.activateSide(.left)
        XCTAssertTrue(model.canSelectLineDifference)

        model.editLine(rowID: row.id, on: .left, replacement: "aC")
        let revealRevision = model.selectedDifferenceRevealRevision
        let selectionRevision = model.lineDifferenceSelectionRevision

        XCTAssertFalse(model.isComparisonCurrent)
        XCTAssertFalse(model.canSelectLineDifference)
        model.selectLineDifference()
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision)
    }

    func testMovedNavigationRequestsTargetEditorFocusAndRejectsStaleAction() async throws {
        let left = "head\nduplicate\nunique moved seed\nduplicate\nstable one\nstable two\nstable three\ntail"
        let right = "head\nstable one\nstable two\nstable three\nduplicate\nunique moved seed\nduplicate\ntail"
        var options = LineDiffOptions()
        options.detectMovedBlocks = true
        let model = await makeCurrentModel(left: left, right: right, options: options)
        let source = try XCTUnwrap(model.rows.first { $0.left?.number == 2 })
        let target = try XCTUnwrap(model.rows.first { $0.right?.number == 5 })
        let focusRevision = model.paneFocusRevision

        XCTAssertTrue(model.canGoToMovedLine(source.id, .left))
        model.goToMovedLine(source.id, .left)

        XCTAssertEqual(model.currentRowID, target.id)
        XCTAssertEqual(model.selectedDifferenceID, target.id)
        XCTAssertEqual(model.activeSide, .right)
        XCTAssertEqual(model.paneFocusRevision, focusRevision + 1)

        model.activateRow(source.id)
        model.activateSide(.left)
        model.editLine(rowID: source.id, on: .left, replacement: "duplicate edited")
        let staleRowID = model.currentRowID
        let staleSide = model.activeSide
        let staleFocusRevision = model.paneFocusRevision

        XCTAssertFalse(model.isComparisonCurrent)
        XCTAssertFalse(model.canGoToMovedLine(source.id, .left))
        model.goToMovedLine(source.id, .left)
        XCTAssertEqual(model.currentRowID, staleRowID)
        XCTAssertEqual(model.activeSide, staleSide)
        XCTAssertEqual(model.paneFocusRevision, staleFocusRevision)
    }

    func testReusedTextCellResetsSelectionBeforeNextLineDifference() {
        let ranges = [
            NSRange(location: 2, length: 1),
            NSRange(location: 6, length: 1),
        ]
        let editor = AccessibilityCommandTestHarness.LineDifferenceEditor(
            text: "abXcdeY",
            ranges: ranges
        )
        defer { editor.close() }

        editor.select(.next)
        editor.select(.next)
        XCTAssertEqual(editor.selectedRange, ranges[1])

        editor.reuse(text: "abXcdeY", ranges: ranges)
        XCTAssertEqual(editor.selectedRange, NSRange(location: 0, length: 0))
        editor.select(.next)
        XCTAssertEqual(editor.selectedRange, ranges[0])
    }

    func testUpdateRejectsDeferredF4AfterDirectEditorActivation() async throws {
        let model = await makeCurrentModel(left: "abXef\n", right: "aYbcdeZf\n")
        let row = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        model.activateRow(row.id)
        model.activateSide(.right)
        model.selectLineDifference()
        let generationBeforeRowActivation = model.focusGeneration
        model.activateRow(row.id)
        XCTAssertGreaterThan(model.focusGeneration, generationBeforeRowActivation)
        XCTAssertNil(model.focusRequest)

        model.selectLineDifference()
        let generationBeforeSideActivation = model.focusGeneration
        model.activateSide(.left)
        XCTAssertGreaterThan(model.focusGeneration, generationBeforeSideActivation)
        XCTAssertNil(model.focusRequest)

        model.activateSide(.right)
        model.selectLineDifference()
        let staleRequest = try XCTUnwrap(model.focusRequest)
        XCTAssertEqual(staleRequest.action, .selectLineDifference(
            rowID: row.id,
            side: .right,
            direction: .next
        ))

        let table = ComparisonUpdateTestHarness(model: model)
        defer { table.close() }
        let generationBeforeEditorActivation = model.focusGeneration
        XCTAssertTrue(table.beginEditing(rowID: row.id, on: .left))
        XCTAssertGreaterThan(model.focusGeneration, generationBeforeEditorActivation)
        XCTAssertNil(model.focusRequest)
        XCTAssertTrue(table.isEditorFocused(rowID: row.id, on: .left))
        let rightSelection = table.selectedRange(rowID: row.id, on: .right)

        table.update(focusRequest: staleRequest)
        await drainMainQueue()

        XCTAssertTrue(table.isEditorFocused(rowID: row.id, on: .left))
        XCTAssertEqual(table.selectedRange(rowID: row.id, on: .right), rightSelection)
    }

    func testLineDifferenceGenerationRejectsReplacementWithRepeatedRowID() {
        let original = DiffRow(
            left: DiffLine(number: 1, text: "before OLD value"),
            right: DiffLine(number: 1, text: "before NEW value"),
            kind: .modified
        )
        let replacement = DiffRow(
            left: DiffLine(number: 1, text: "replacement OLD value"),
            right: DiffLine(number: 1, text: "replacement NEW value"),
            kind: .modified
        )
        XCTAssertEqual(original.id, replacement.id)
        let table = AccessibilityCommandTestHarness.Table(rows: [original])
        defer { table.close() }
        let staleCallback = table.captureLineDifferenceSelection(rowID: original.id)

        table.reuseRows([replacement], advanceRevision: false)
        table.advanceLineDifferenceSelectionRequest()

        XCTAssertFalse(staleCallback())
    }

    func testPaneFocusGenerationRejectsReplacementWithRepeatedRowID() {
        let original = DiffRow(
            left: DiffLine(number: 1, text: "original left"),
            right: DiffLine(number: 1, text: "original right"),
            kind: .modified
        )
        let replacement = DiffRow(
            left: DiffLine(number: 1, text: "replacement left"),
            right: DiffLine(number: 1, text: "replacement right"),
            kind: .modified
        )
        XCTAssertEqual(original.id, replacement.id)
        let table = AccessibilityCommandTestHarness.Table(rows: [original])
        defer { table.close() }
        let staleCallback = table.capturePaneFocus(rowID: original.id)

        table.reuseRows([replacement], advanceRevision: false)
        table.advancePaneFocusRequest()

        XCTAssertFalse(staleCallback())
    }

    func testReloadInvalidatesQueuedFocusAcrossRepeatedRowIDAndFailure() async throws {
        let model = try await makeEnqueuedModel(
            left: "before OLD value\n",
            right: "before NEW value\n"
        )
        let originalRow = try XCTUnwrap(model.rows.first { $0.kind == .modified })
        model.activateRow(originalRow.id)
        model.activateSide(.left)
        model.selectLineDifference()
        let staleRequest = try XCTUnwrap(model.focusRequest)
        let table = ComparisonUpdateTestHarness(model: model)
        defer { table.close() }
        let selectionBeforeReload = table.selectedRange(rowID: originalRow.id, on: .left)
        table.update(focusRequest: staleRequest)

        let leftURL = try XCTUnwrap(model.left.url)
        let rightURL = try XCTUnwrap(model.right.url)
        try Data("replacement OLD value\n".utf8).write(to: leftURL)
        try Data("replacement NEW value\n".utf8).write(to: rightURL)
        let generationBeforeReload = model.focusGeneration
        model.reloadFromDisk()
        XCTAssertGreaterThan(model.focusGeneration, generationBeforeReload)
        XCTAssertNil(model.focusRequest)
        model.continueEditing(on: .left, lineNumber: 1)
        let generationDuringReload = model.focusGeneration

        await waitUntil { !model.isWorking && model.isComparisonCurrent }

        XCTAssertGreaterThan(model.focusGeneration, generationDuringReload)
        XCTAssertNil(model.focusRequest)
        XCTAssertEqual(model.rows.first?.id, originalRow.id)
        XCTAssertEqual(table.selectedRange(rowID: originalRow.id, on: .left), selectionBeforeReload)

        model.activateRow(originalRow.id)
        model.activateSide(.left)
        model.selectLineDifference()
        try FileManager.default.removeItem(at: rightURL)
        model.reloadFromDisk()
        model.continueEditing(on: .left, lineNumber: 1)
        let generationDuringFailedReload = model.focusGeneration

        await waitUntil { !model.isWorking }

        XCTAssertGreaterThan(model.focusGeneration, generationDuringFailedReload)
        XCTAssertNil(model.focusRequest)
        XCTAssertNotNil(model.errorMessage)
    }

    func testNewlineReloadRemainsUndoableAndRedoableThroughComparisonCommand() async throws {
        let originalLeft = "alpha\nomega\n"
        let editedLeft = "alpha\n\nomega\n"
        let right = "alpha changed\nomega\n"
        let model = try await makeEnqueuedModel(
            left: originalLeft,
            right: right
        )
        let row = try XCTUnwrap(model.rows.first { $0.left?.number == 1 })
        let oldRowsRevision = model.rowsRevision
        let table = ComparisonUpdateTestHarness(model: model)
        defer { table.close() }

        XCTAssertTrue(table.beginEditing(rowID: row.id, on: .left))
        table.insertNewline(
            rowID: row.id,
            on: .left,
            selectedRange: NSRange(location: 5, length: 0)
        )

        XCTAssertEqual(model.left.text, editedLeft)
        XCTAssertTrue(model.canUndo)
        await waitUntil {
            model.isComparisonCurrent && model.rowsRevision > oldRowsRevision
        }
        table.update()
        await drainMainQueue()
        let continuationRow = try XCTUnwrap(model.rows.first { $0.left?.number == 2 })
        XCTAssertTrue(table.isEditorFocused(rowID: continuationRow.id, on: .left))
        XCTAssertFalse(table.focusedTextView?.undoManager?.canUndo == true)

        XCTAssertTrue(ComparisonUndoRouter.canUndo(
            model: model,
            focusedTextView: table.focusedTextView
        ))
        ComparisonUndoRouter.undo(model: model, focusedTextView: table.focusedTextView)
        await waitUntil { model.isComparisonCurrent && model.left.text == originalLeft }
        XCTAssertEqual(model.left.text, originalLeft)
        XCTAssertEqual(model.right.text, right)
        XCTAssertTrue(model.canRedo)

        table.update()
        XCTAssertTrue(ComparisonUndoRouter.canRedo(
            model: model,
            focusedTextView: table.focusedTextView
        ))
        ComparisonUndoRouter.redo(model: model, focusedTextView: table.focusedTextView)
        await waitUntil { model.isComparisonCurrent && model.left.text == editedLeft }
        XCTAssertEqual(model.left.text, editedLeft)
        XCTAssertEqual(model.right.text, right)
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
    }

    func testCRLFContinuationCountsAsOneLogicalNewline() {
        let editor = AccessibilityCommandTestHarness.LineDifferenceEditor(
            text: "first\r\nsecond",
            ranges: []
        )
        defer { editor.close() }
        editor.setSelectedRange(NSRange(location: 7, length: 0))

        editor.insertNewline()

        XCTAssertEqual(editor.continuationOffsets, [2])
    }

    func testContinuationDoesNotCountUnsupportedUnicodeLineSeparator() {
        let editor = AccessibilityCommandTestHarness.LineDifferenceEditor(
            text: "first\u{2028}second",
            ranges: []
        )
        defer { editor.close() }
        editor.setSelectedRange(NSRange(location: 6, length: 0))

        editor.insertNewline()

        XCTAssertEqual(editor.continuationOffsets, [1])
    }

    private func makeCurrentModel(
        left: String,
        right: String,
        options: LineDiffOptions = LineDiffOptions()
    ) async -> ComparisonModel {
        let model = ComparisonModel()
        model.setOptions(options)
        model.createEmptyComparison()
        model.editText(left, on: .left)
        model.editText(right, on: .right)
        model.refresh()
        let idle = expectation(description: "Comparison model becomes idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: 5)
        XCTAssertTrue(model.isComparisonCurrent)
        return model
    }

    private func makeEnqueuedModel(left: String, right: String) async throws -> ComparisonModel {
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
        let idle = expectation(description: "Enqueued comparison becomes idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: 5)
        XCTAssertTrue(model.isComparisonCurrent)
        return model
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

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
