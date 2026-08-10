import Foundation
@testable import MacMerge
import MacMergeCore
import XCTest

@MainActor
final class ComparisonModelTests: XCTestCase {
    func testLocationMapCompactsRunsAndMapsFractionsToRows() {
        let rows = [
            DiffRow(left: DiffLine(number: 1, text: "same"), right: DiffLine(number: 1, text: "same"), kind: .unchanged),
            DiffRow(left: DiffLine(number: 2, text: "left"), right: DiffLine(number: 2, text: "right"), kind: .modified),
            DiffRow(left: DiffLine(number: 3, text: "left"), right: DiffLine(number: 3, text: "right"), kind: .modified),
            DiffRow(left: DiffLine(number: 4, text: "removed"), right: nil, kind: .removed),
            DiffRow(left: nil, right: DiffLine(number: 4, text: "added"), kind: .added),
            DiffRow(left: DiffLine(number: 5, text: "same"), right: DiffLine(number: 5, text: "same"), kind: .unchanged),
        ]

        let map = LocationMap(rows: rows)

        XCTAssertEqual(map.rowCount, 6)
        XCTAssertEqual(map.blocks, [
            LocationMapBlock(startRow: 1, endRow: 3, kind: .modified),
            LocationMapBlock(startRow: 3, endRow: 4, kind: .removed),
            LocationMapBlock(startRow: 4, endRow: 5, kind: .added),
        ])
        XCTAssertEqual(map.shallowStorageBytes, 3 * MemoryLayout<UInt64>.stride)
        XCTAssertEqual(map.rowIndex(at: -1), 0)
        XCTAssertEqual(map.rowIndex(at: 0.5), 3)
        XCTAssertEqual(map.rowIndex(at: 1), 5)
        XCTAssertNil(map.rowIndex(at: .nan))
        XCTAssertNil(LocationMap().rowIndex(at: 0.5))
    }

    func testLocationViewportNormalizesBounds() {
        XCTAssertEqual(LocationViewport(startRow: -5, endRow: 4), LocationViewport(startRow: 0, endRow: 4))
        XCTAssertEqual(LocationViewport(startRow: 8, endRow: 3), LocationViewport(startRow: 8, endRow: 8))
        XCTAssertEqual(LocationViewport(startRow: 3, endRow: 9).rowCount, 6)

        let viewport = LocationViewport(startRow: 450, endRow: 550)
        let position = viewport.position(totalRowCount: 1_000)
        XCTAssertEqual(position, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(viewport.centeredRow(at: position, totalRowCount: 1_000), 500)
        XCTAssertEqual(viewport.centeredRow(at: 0, totalRowCount: 1_000), 50)
        XCTAssertEqual(viewport.centeredRow(at: 1, totalRowCount: 1_000), 950)
        XCTAssertNil(viewport.centeredRow(at: .nan, totalRowCount: 1_000))
        XCTAssertNil(viewport.centeredRow(at: 0.5, totalRowCount: 0))
    }

    func testLocationMapWorstCaseStorageUsesOneWordPerRun() {
        var map = LocationMap()
        for index in 0 ..< 100_000 {
            map.append(index.isMultiple(of: 2) ? .modified : .added)
        }

        XCTAssertEqual(map.blockCount, 100_000)
        XCTAssertEqual(map.shallowStorageBytes, 100_000 * MemoryLayout<UInt64>.stride)
        XCTAssertEqual(map.block(at: 99_999), LocationMapBlock(
            startRow: 99_999,
            endRow: 100_000,
            kind: .added
        ))
    }

    func testDifferenceLocationsUseCompactCollisionSafeStorage() {
        let rows = (1...1_000).map { number in
            let omitsLeft = number.isMultiple(of: 3)
            return DiffRow(
                left: omitsLeft ? nil : DiffLine(number: number, text: "left"),
                right: !omitsLeft && number.isMultiple(of: 5)
                    ? nil
                    : DiffLine(number: number, text: "right"),
                kind: .modified
            )
        }
        let rowIndices = rows.indices.map(UInt32.init)

        let locations = DifferenceLocations(rows: rows, differenceRowIndices: rowIndices)

        for index in rows.indices {
            XCTAssertEqual(locations[rows[index].id]?.rowIndex, index)
        }
        XCTAssertNil(locations[DiffRow.ID(leftNumber: 0, rightNumber: 3)])
        XCTAssertNil(locations[DiffRow.ID(leftNumber: 1_000_001, rightNumber: 1_000_000)])
        XCTAssertLessThanOrEqual(locations.shallowStorageBytes, 16 * 1_024)

        let boundaryRows = [
            DiffRow(
                left: DiffLine(number: 1_048_576, text: "left"),
                right: nil,
                kind: .removed
            ),
            DiffRow(
                left: nil,
                right: DiffLine(number: 1_048_576, text: "right"),
                kind: .added
            ),
        ]
        let boundaryLocations = DifferenceLocations(
            rows: boundaryRows,
            differenceRowIndices: [0, 1]
        )
        XCTAssertEqual(boundaryLocations[boundaryRows[0].id]?.rowIndex, 0)
        XCTAssertEqual(boundaryLocations[boundaryRows[1].id]?.rowIndex, 1)
    }

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

        model.editLine(
            rowID: insertionRow,
            on: .left,
            replacement: "test\nkek\ntesting"
        )
        model.finishLineEditing(rowID: insertionRow, on: .left)
        await waitUntil { model.left.text == "test\nkek\ntesting" && model.isComparisonCurrent }
        model.editLine(
            rowID: insertionRow,
            on: .right,
            replacement: "test\nlol\ntesting"
        )
        model.finishLineEditing(rowID: insertionRow, on: .right)
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

        model.editLine(rowID: insertionRow, on: .left, replacement: "a")
        model.editLine(rowID: insertionRow, on: .left, replacement: "ab")
        model.editLine(rowID: insertionRow, on: .left, replacement: "abc")
        model.finishLineEditing(rowID: insertionRow, on: .left)
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

    func testLoadedDocumentLineCanBeEditedAndSaved() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "# MacMerge\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "# MacMerge Port Roadmap\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first?.id)

        model.editLine(rowID: rowID, on: .right, replacement: "# MacMerge")
        model.finishLineEditing(rowID: rowID, on: .right)
        await waitUntil { model.isComparisonCurrent && model.summary.differences == 0 }

        XCTAssertTrue(model.right.isDirty)
        let saved = await withCheckedContinuation { continuation in
            model.save(.right) { continuation.resume(returning: $0) }
        }
        await waitUntilIdle(model)
        XCTAssertTrue(saved)
        XCTAssertFalse(model.right.isDirty)
        XCTAssertEqual(try String(contentsOf: rightURL, encoding: .utf8), "# MacMerge\n")
    }

    func testIntralineDifferenceRangePreservesGraphemeBoundaries() {
        let text = "# MacMerge Port Roadmap"

        XCTAssertEqual(
            intralineDifferenceRange(in: text, comparedWith: "# MacMerge"),
            NSRange(location: 10, length: 13)
        )
        XCTAssertEqual(
            intralineDifferenceRange(in: "café noir", comparedWith: "café blanc"),
            NSRange(location: 6, length: 4)
        )
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
        XCTAssertEqual(model.locationMap.rowCount, model.rows.count)
        XCTAssertEqual(model.locationMap.blocks.map(\.kind), [.modified, .modified, .modified])

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

    func testNavigationUsesCurrentUnchangedRowWhenNoDifferenceIsSelected() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one\nsame\ntwo\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "ONE\nsame\nTWO\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let unchanged = try XCTUnwrap(model.rows.first(where: { $0.kind == .unchanged }))
        let differences = model.rows.filter { $0.kind != .unchanged }.map(\.id)

        model.activateRow(unchanged.id)
        XCTAssertNil(model.selectedDifferenceID)
        XCTAssertFalse(model.canSelectCurrentDifference)

        model.selectNextDifference()
        XCTAssertEqual(model.selectedDifferenceID, differences.last)
        model.activateRow(unchanged.id)
        model.selectPreviousDifference()
        XCTAssertEqual(model.selectedDifferenceID, differences.first)
    }

    func testCurrentDifferenceRequestsRevealWithoutChangingSelection() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "ONE\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        model.selectFirstDifference()
        let selected = model.selectedDifferenceID
        let revision = model.selectedDifferenceRevealRevision

        model.selectCurrentDifference()

        XCTAssertEqual(model.selectedDifferenceID, selected)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revision + 1)
    }

    func testSelectLineDifferenceRequestsRevealAndTextSelection() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "MacMerge\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "MacMerge Port\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        model.selectFirstDifference()
        model.activateSide(.right)
        let revealRevision = model.selectedDifferenceRevealRevision
        let selectionRevision = model.lineDifferenceSelectionRevision

        model.selectLineDifference()

        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 1)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision + 1)
    }

    func testChangePaneTogglesSideAndRequestsFocus() {
        let model = ComparisonModel()
        model.createEmptyComparison()
        let revision = model.paneFocusRevision

        model.changePane()

        XCTAssertEqual(model.activeSide, .right)
        XCTAssertEqual(model.paneFocusRevision, revision + 1)
        model.changePane()
        XCTAssertEqual(model.activeSide, .left)
        XCTAssertEqual(model.paneFocusRevision, revision + 2)
    }

    func testMergeModePersistsAndMapsNavigationArrows() async throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let leftURL = try temporaryFile(name: "left.txt", content: "one\nsame\ntwo\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "ONE\nsame\nTWO\n")
        let model = ComparisonModel(userDefaults: userDefaults)
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let first = try XCTUnwrap(model.rows.first(where: { $0.kind != .unchanged })?.id)
        model.selectDifference(first)

        model.setMergeMode(true)
        let handled = model.handleMergeModeKey(125, rowID: first)

        XCTAssertTrue(handled)
        XCTAssertNotEqual(model.selectedDifferenceID, first)
        XCTAssertTrue(ComparisonModel(userDefaults: userDefaults).isMergeMode)
        model.setMergeMode(false)
    }

    func testMergeModeIgnoresUnmappedKeys() {
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.setMergeMode(true)

        XCTAssertFalse(model.handleMergeModeKey(
            0,
            rowID: DiffRow.ID(leftNumber: nil, rightNumber: nil)
        ))
    }

    func testRefreshRecomparesMemoryWithoutReadingChangedDiskFile() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "two\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first?.id)
        model.editLine(rowID: rowID, on: .right, replacement: "one")
        model.finishLineEditing(rowID: rowID, on: .right)
        await waitUntil { model.isComparisonCurrent && model.summary.differences == 0 }
        try Data("changed on disk\n".utf8).write(to: rightURL)

        model.refresh()
        await waitUntilIdle(model)

        XCTAssertEqual(model.right.text, "one\n")
        XCTAssertTrue(model.right.isDirty)
        XCTAssertEqual(model.summary.differences, 0)
    }

    func testComparisonOptionsRecompareCurrentBuffers() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "MacMerge\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "MACMERGE\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        XCTAssertEqual(model.summary.differences, 1)
        var options = model.options
        options.ignoreCase = true

        model.setOptions(options)
        await waitUntilIdle(model)

        XCTAssertEqual(model.summary.differences, 0)
    }

    func testIgnoreCommentsUsesLoadedFileExtension() async throws {
        let leftURL = try temporaryFile(name: "left.cpp", content: "value(); // left\n")
        let rightURL = try temporaryFile(name: "right.cpp", content: "value(); // right\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        XCTAssertEqual(model.summary.differences, 1)
        var options = model.options
        options.ignoreComments = true

        model.setOptions(options)
        await waitUntilIdle(model)

        XCTAssertEqual(model.summary.differences, 0)
    }

    func testIgnoreCommentsUsesLoadedSQLFileExtension() async throws {
        let leftURL = try temporaryFile(name: "left.sql", content: "SELECT 1; -- left\n")
        let rightURL = try temporaryFile(name: "right.sql", content: "SELECT 1; -- right\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        XCTAssertEqual(model.summary.differences, 1)
        var options = model.options
        options.ignoreComments = true

        model.setOptions(options)
        await waitUntilIdle(model)

        XCTAssertEqual(model.summary.differences, 0)
    }

    func testComparisonOptionsPersistAcrossModels() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let model = ComparisonModel(userDefaults: userDefaults)
        let options = LineDiffOptions(
            algorithm: .histogram,
            whitespace: .ignoreChanges,
            ignoreCase: true,
            ignoreNumbers: true,
            ignoreBlankLines: true,
            ignoreComments: true,
            ignoreLineEndings: false,
            indentHeuristic: true,
            lineFiltersEnabled: false,
            lineFilters: [LineFilterRule(pattern: "^generated:", caseSensitive: false)],
            substitutionsEnabled: false,
            substitutions: [
                SubstitutionRule(pattern: "version \\d+", replacement: "version", caseSensitive: false)
            ]
        )

        model.setOptions(options)

        XCTAssertEqual(ComparisonModel(userDefaults: userDefaults).options, options)
    }

    func testMalformedPersistedComparisonOptionsUseDefaults() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(Data("not json".utf8), forKey: "comparisonOptions.v1")

        XCTAssertEqual(ComparisonModel(userDefaults: userDefaults).options, LineDiffOptions())
    }

    func testLegacyComparisonOptionsDefaultFilterEnableFlags() throws {
        let json = """
        {
          "algorithm": "default",
          "whitespace": "compareAll",
          "ignoreCase": false,
          "ignoreNumbers": false,
          "ignoreBlankLines": false,
          "ignoreLineEndings": true,
          "indentHeuristic": false,
          "lineFilters": [{"pattern": "^# ", "caseSensitive": true}],
          "substitutions": [{"pattern": "\\\\d+", "replacement": "", "caseSensitive": true}]
        }
        """

        let options = try JSONDecoder().decode(LineDiffOptions.self, from: Data(json.utf8))

        XCTAssertTrue(options.lineFiltersEnabled)
        XCTAssertTrue(options.substitutionsEnabled)
        XCTAssertFalse(options.ignoreComments)
    }

    func testResetComparisonOptionsPersistsDefaults() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let model = ComparisonModel(userDefaults: userDefaults)
        model.setOptions(LineDiffOptions(algorithm: .patience, ignoreCase: true))

        model.resetOptions()

        XCTAssertEqual(model.options, LineDiffOptions())
        XCTAssertEqual(ComparisonModel(userDefaults: userDefaults).options, LineDiffOptions())
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
        model.editLine(rowID: insertionRow, on: .left, replacement: "draft")
        model.finishLineEditing(rowID: insertionRow, on: .left)
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

    func testDocumentSaveAsChangesIdentityAndPreservesUndoHistory() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "left\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "right\n")
        let destination = leftURL.deletingLastPathComponent().appending(path: "left-copy.txt")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first(where: { $0.kind != .unchanged })?.id)
        model.merge(rowID: rowID, direction: .rightToLeft)
        await waitUntilIdle(model)

        let saved = await withCheckedContinuation { continuation in
            model.saveAs(.left, destination: destination) {
                continuation.resume(returning: $0)
            }
        }
        await waitUntilIdle(model)

        XCTAssertTrue(saved)
        XCTAssertEqual(model.left.url, destination)
        XCTAssertEqual(try String(contentsOf: leftURL, encoding: .utf8), "left\n")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "right\n")
        XCTAssertTrue(model.canUndo)
    }

    func testDocumentSaveAsRejectsOtherPaneDestination() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "left\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "right\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)

        let saved = await withCheckedContinuation { continuation in
            model.saveAs(.left, destination: rightURL) {
                continuation.resume(returning: $0)
            }
        }

        XCTAssertFalse(saved)
        XCTAssertEqual(model.left.url, leftURL)
        XCTAssertEqual(try String(contentsOf: rightURL, encoding: .utf8), "right\n")
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
