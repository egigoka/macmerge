import AppKit
import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

@MainActor
final class ComparisonModelTests: XCTestCase {
    func testSecurityScopedBookmarksPersistAcrossStores() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let url = URL(filePath: "/tmp/MacMerge/bookmarked.txt")
        var createdURLs: [URL] = []

        let firstStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: {
                createdURLs.append($0)
                return Data($0.path.utf8)
            },
            resolveBookmark: { _ in
                XCTFail("New bookmarks should not be resolved")
                return .init(url: url, isStale: false)
            }
        )
        try firstStore.persistAccess(to: url)

        let secondStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in
                XCTFail("Persisted bookmark should be reused")
                return Data()
            },
            resolveBookmark: {
                SecurityScopedBookmarkStore.Resolution(
                    url: URL(filePath: String(decoding: $0, as: UTF8.self)),
                    isStale: false
                )
            }
        )

        XCTAssertEqual(secondStore.resolveAccess(to: url), url)
        XCTAssertEqual(createdURLs, [url])
    }

    func testSecurityScopedBookmarksRefreshStaleResolvedURL() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let originalURL = URL(filePath: "/tmp/MacMerge/original.txt")
        let movedURL = URL(filePath: "/tmp/MacMerge/moved.txt")
        let initialStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in Data("old".utf8) },
            resolveBookmark: { _ in
                XCTFail("No bookmark should exist yet")
                return .init(url: originalURL, isStale: false)
            }
        )
        try initialStore.persistAccess(to: originalURL)

        let refreshingStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { Data("fresh:\($0.path)".utf8) },
            resolveBookmark: { _ in .init(url: movedURL, isStale: true) }
        )
        XCTAssertEqual(refreshingStore.resolveAccess(to: originalURL), movedURL)

        let verifyingStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in
                XCTFail("Refreshed bookmark should be reused")
                return Data()
            },
            resolveBookmark: {
                XCTAssertEqual(String(decoding: $0, as: UTF8.self), "fresh:\(movedURL.path)")
                return .init(url: movedURL, isStale: false)
            }
        )
        XCTAssertEqual(verifyingStore.resolveAccess(to: movedURL), movedURL)
    }

    func testSecurityScopedBookmarksAliasMovedResolutionWithoutDiscardingOriginal() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let original = URL(filePath: "/tmp/MacMerge/original.txt")
        let moved = URL(filePath: "/tmp/MacMerge/moved.txt")
        let initial = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in Data("bookmark".utf8) },
            resolveBookmark: { _ in .init(url: original, isStale: false) }
        )
        try initial.persistAccess(to: original)
        let resolving = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in
                XCTFail("Non-stale alias must reuse bookmark")
                return Data()
            },
            resolveBookmark: { _ in .init(url: moved, isStale: false) }
        )

        XCTAssertEqual(resolving.resolveAccess(to: original), moved)
        XCTAssertTrue(resolving.hasPersistedAccess(to: original))
        XCTAssertTrue(resolving.hasPersistedAccess(to: moved))
    }

    func testSecurityScopedBookmarksPreserveInvalidDataUntilExplicitReplacement() throws {
        struct InvalidBookmark: Error {}

        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let url = URL(filePath: "/tmp/MacMerge/recovered.txt")
        let initialStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in Data("invalid".utf8) },
            resolveBookmark: { _ in
                XCTFail("No bookmark should exist yet")
                return .init(url: url, isStale: false)
            }
        )
        try initialStore.persistAccess(to: url)

        let recoveringStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in
                XCTFail("Resolution must not replace invalid data")
                return Data()
            },
            resolveBookmark: { _ in throw InvalidBookmark() }
        )
        XCTAssertEqual(recoveringStore.resolveAccess(to: url), url)
        XCTAssertFalse(recoveringStore.hasPersistedAccess(to: url))

        let replacingStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { Data("valid:\($0.path)".utf8) },
            resolveBookmark: { _ in throw InvalidBookmark() }
        )
        try replacingStore.persistAccess(to: url)

        let verifyingStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in
                XCTFail("Replacement bookmark should be reused")
                return Data()
            },
            resolveBookmark: {
                XCTAssertEqual(String(decoding: $0, as: UTF8.self), "valid:\(url.path)")
                return .init(url: url, isStale: false)
            }
        )
        XCTAssertEqual(verifyingStore.resolveAccess(to: url), url)
    }

    func testFailedBookmarkReplacementClearsStaleMappingForReusedPath() throws {
        struct BookmarkFailure: Error {}

        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let reused = URL(filePath: "/tmp/MacMerge/reused.txt")
        let movedOldFile = URL(filePath: "/tmp/MacMerge/moved-old.txt")
        let initial = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in Data("old".utf8) },
            resolveBookmark: { _ in .init(url: reused, isStale: false) }
        )
        try initial.persistAccess(to: reused)
        let replacement = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in throw BookmarkFailure() },
            resolveBookmark: { _ in .init(url: movedOldFile, isStale: false) }
        )

        XCTAssertThrowsError(try replacement.persistAccess(to: reused))

        let verifying = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in Data() },
            resolveBookmark: { _ in
                XCTFail("Stale mapping must be removed")
                return .init(url: movedOldFile, isStale: false)
            }
        )
        XCTAssertEqual(verifying.resolveAccess(to: reused), reused)
        XCTAssertFalse(verifying.hasPersistedAccess(to: reused))
    }

    func testLocationMapCompactsRunsAndMapsFractionsToRows() {
        let rows = [
            DiffRow(left: DiffLine(number: 1, text: "same"), right: DiffLine(number: 1, text: "same"), kind: .unchanged),
            DiffRow(left: DiffLine(number: 2, text: "left"), right: DiffLine(number: 2, text: "right"), kind: .modified),
            DiffRow(left: DiffLine(number: 3, text: "left"), right: DiffLine(number: 3, text: "right"), kind: .modified),
            DiffRow(left: DiffLine(number: 4, text: "removed"), right: nil, kind: .removed),
            DiffRow(left: nil, right: DiffLine(number: 4, text: "added"), kind: .added),
            DiffRow(left: DiffLine(number: 5, text: "same"), right: DiffLine(number: 5, text: "same"), kind: .unchanged)
        ]

        let map = LocationMap(rows: rows)

        XCTAssertEqual(map.rowCount, 6)
        XCTAssertEqual(
            map.blocks,
            [
                LocationMapBlock(startRow: 1, endRow: 3, kind: .modified),
                LocationMapBlock(startRow: 3, endRow: 4, kind: .removed),
                LocationMapBlock(startRow: 4, endRow: 5, kind: .added)
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

    func testLocationPanePreferencesPersistAndClampWidth() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let model = ComparisonModel(userDefaults: userDefaults)

        XCTAssertTrue(model.isLocationPaneVisible)
        XCTAssertEqual(model.locationPaneWidth, 92)
        XCTAssertTrue(model.locationPaneMovesCursorOnClick)

        model.setLocationPaneVisible(false)
        model.setLocationPaneWidth(500)
        model.setLocationPaneMovesCursorOnClick(false)

        let restored = ComparisonModel(userDefaults: userDefaults)
        XCTAssertFalse(restored.isLocationPaneVisible)
        XCTAssertEqual(restored.locationPaneWidth, ComparisonModel.maximumLocationPaneWidth)
        XCTAssertFalse(restored.locationPaneMovesCursorOnClick)

        restored.setLocationPaneWidth(1)
        XCTAssertEqual(restored.locationPaneWidth, ComparisonModel.minimumLocationPaneWidth)
        XCTAssertEqual(ComparisonModel.clampedLocationPaneWidth(120), 120)
        XCTAssertEqual(ComparisonModel.clampedLocationPaneWidth(.nan), 92)
    }

    func testPerformanceRunCanForceLocationPaneVisible() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(false, forKey: "locationPane.visible")

        let model = ComparisonModel(
            userDefaults: userDefaults,
            forceLocationPaneVisible: true
        )

        XCTAssertTrue(model.isLocationPaneVisible)
    }

    func testLocationPaneMovedBlockCommandPersistsComparisonOption() throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let model = ComparisonModel(userDefaults: userDefaults)

        model.setDetectMovedBlocks(true)

        XCTAssertTrue(model.options.detectMovedBlocks)
        XCTAssertTrue(ComparisonModel(userDefaults: userDefaults).options.detectMovedBlocks)
    }

    func testLocationMapWorstCaseStorageUsesOneWordPerRun() {
        var map = LocationMap()
        for index in 0..<100_000 {
            map.append(index.isMultiple(of: 2) ? .modified : .added)
        }

        XCTAssertEqual(map.blockCount, 100_000)
        XCTAssertEqual(map.shallowStorageBytes, 100_000 * MemoryLayout<UInt64>.stride)
        XCTAssertEqual(
            map.block(at: 99_999),
            LocationMapBlock(
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
            )
        ]
        let boundaryLocations = DifferenceLocations(
            rows: boundaryRows,
            differenceRowIndices: [0, 1]
        )
        XCTAssertEqual(boundaryLocations[boundaryRows[0].id]?.rowIndex, 0)
        XCTAssertEqual(boundaryLocations[boundaryRows[1].id]?.rowIndex, 1)
    }

    func testMovedRowMapCompactsBlocksAndMapsBothDirections() throws {
        let result = try LineDiff.compareResult(
            left: "head\nduplicate\nunique moved seed\nduplicate\nstable one\nstable two\nstable three\ntail",
            right: "head\nstable one\nstable two\nstable three\nduplicate\nunique moved seed\nduplicate\ntail",
            options: LineDiffOptions(detectMovedBlocks: true)
        )
        let map = MovedRowMap(rows: result.rows, movedLines: result.movedLines)
        let leftSourceRow = try XCTUnwrap(result.rows.firstIndex { $0.left?.number == 2 })
        let rightTargetRow = try XCTUnwrap(result.rows.firstIndex { $0.right?.number == 5 })

        XCTAssertEqual(map.blockCount, 1)
        XCTAssertEqual(map.targetRow(forLine: 2, on: .left), rightTargetRow)
        XCTAssertEqual(map.targetRow(forLine: 5, on: .right), leftSourceRow)
        XCTAssertTrue(map.isMoved(line: 3, on: .left))
        XCTAssertTrue(map.isMoved(line: 6, on: .right))
        XCTAssertNil(map.targetRow(forLine: 1, on: .left))
        XCTAssertEqual(map.shallowStorageBytes, 64)
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

    func testUndoRouterPrefersFocusedEditorThenFallsBackToComparisonHistory() async {
        let model = ComparisonModel()
        let insertionRow = DiffRow.ID(leftNumber: nil, rightNumber: nil)
        model.createEmptyComparison()
        model.editLine(rowID: insertionRow, on: .left, replacement: "model edit")
        model.finishLineEditing(rowID: insertionRow, on: .left)
        await waitUntil { model.isComparisonCurrent }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)
        defer {
            window.makeFirstResponder(nil)
            textView.undoManager?.removeAllActions()
            textView.removeFromSuperview()
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.insertText("editor edit", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertTrue(ComparisonUndoRouter.canUndo(model: model, focusedTextView: textView))
        ComparisonUndoRouter.undo(model: model, focusedTextView: textView)

        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(model.left.text, "model edit")
        XCTAssertTrue(ComparisonUndoRouter.canRedo(model: model, focusedTextView: textView))

        ComparisonUndoRouter.undo(model: model, focusedTextView: nil)
        await waitUntil { model.isComparisonCurrent }

        XCTAssertEqual(model.left.text, "")
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
        XCTAssertEqual(
            intralineDifferenceRanges(in: "one SAME three SAME", comparedWith: "one same three same"),
            [NSRange(location: 4, length: 4), NSRange(location: 15, length: 4)]
        )
    }

    func testLineDifferenceRangeTraversesAndWrapsBothDirections() {
        let ranges = [NSRange(location: 4, length: 4), NSRange(location: 15, length: 4)]

        XCTAssertEqual(
            lineDifferenceRange(in: ranges, from: ranges[0], direction: .next),
            ranges[1]
        )
        XCTAssertEqual(
            lineDifferenceRange(in: ranges, from: ranges[1], direction: .next),
            ranges[0]
        )
        XCTAssertEqual(
            lineDifferenceRange(in: ranges, from: ranges[0], direction: .previous),
            ranges[1]
        )
        XCTAssertEqual(
            lineDifferenceRange(in: ranges, from: NSRange(location: 14, length: 0), direction: .previous),
            ranges[0]
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
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .next)
    }

    func testSelectPreviousLineDifferenceRequestsReverseSelection() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "one SAME three SAME\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "one same three same\n")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        model.selectFirstDifference()
        let revealRevision = model.selectedDifferenceRevealRevision
        let selectionRevision = model.lineDifferenceSelectionRevision

        model.selectPreviousLineDifference()

        XCTAssertEqual(model.selectedDifferenceRevealRevision, revealRevision + 1)
        XCTAssertEqual(model.lineDifferenceSelectionRevision, selectionRevision + 1)
        XCTAssertEqual(model.lineDifferenceSelectionDirection, .previous)
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

        XCTAssertFalse(
            model.handleMergeModeKey(
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
            detectMovedBlocks: true,
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
        XCTAssertFalse(options.detectMovedBlocks)
    }

    func testMovedLineNavigationTargetsOtherSide() async throws {
        let leftURL = try temporaryFile(
            name: "left.txt",
            content: "head\nduplicate\nunique moved seed\nduplicate\nstable one\nstable two\nstable three\ntail"
        )
        let rightURL = try temporaryFile(
            name: "right.txt",
            content: "head\nstable one\nstable two\nstable three\nduplicate\nunique moved seed\nduplicate\ntail"
        )
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        XCTAssertTrue(model.movedRows.isEmpty)
        var options = model.options
        options.detectMovedBlocks = true
        model.setOptions(options)
        await waitUntilIdle(model)
        let source = try XCTUnwrap(model.rows.first { $0.left?.number == 2 })
        let target = try XCTUnwrap(model.rows.first { $0.right?.number == 5 })

        XCTAssertTrue(model.canGoToMovedLine(source.id, .left))
        model.goToMovedLine(source.id, .left)

        XCTAssertEqual(model.currentRowID, target.id)
        XCTAssertEqual(model.selectedDifferenceID, target.id)
        XCTAssertEqual(model.activeSide, .right)
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

    func testSessionStateRestoresFilesSelectionLayoutAndIndependentReadOnlySides() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "same\nleft\ntail\n")
        let rightURL = try temporaryFile(name: "right.txt", content: "same\nright\ntail\n")
        let source = ComparisonModel()
        source.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(source)
        source.selectFirstDifference()
        source.activateSide(.right)
        source.setEditable(false, on: .left)
        source.setLocationPaneVisible(false)
        source.setLocationPaneWidth(140)
        let frame = try ComparisonSessionState.WindowFrame(
            x: 10,
            y: 20,
            width: 800,
            height: 600
        )
        let capturedState = try await source.sessionState(windowFrame: frame)
        let state = try XCTUnwrap(capturedState)

        let restored = ComparisonModel()
        restored.restoreSession(state)
        await waitUntilIdle(restored)

        XCTAssertEqual(restored.left.url, leftURL)
        XCTAssertEqual(restored.right.url, rightURL)
        XCTAssertFalse(restored.left.isEditable)
        XCTAssertTrue(restored.right.isEditable)
        XCTAssertEqual(restored.activeSide, .right)
        XCTAssertFalse(restored.isLocationPaneVisible)
        XCTAssertEqual(restored.locationPaneWidth, 140)
        XCTAssertEqual(restored.selectedDifferenceID, restored.rows[1].id)
        XCTAssertFalse(restored.hasUnsavedChanges)
    }

    func testNonemptyScratchpadsRestoreAndRecaptureExactlyAcrossTwoLaunches() async throws {
        let original = ComparisonModel()
        original.createEmptyComparison()
        original.editText("left\nnotes", on: .left)
        original.editText("right\r\nnotes", on: .right)
        let leftDestination = try temporaryFile(name: "left.txt", content: "")
        let rightDestination = try temporaryFile(name: "right.txt", content: "")
        await withCheckedContinuation { continuation in
            original.saveAllChanges(
                scratchpadDestinations: [.left: leftDestination, .right: rightDestination]
            ) { _ in continuation.resume() }
        }
        await waitUntilIdle(original)
        let capturedFirstState = try await original.sessionState(windowFrame: sessionFrame())
        let firstState = try XCTUnwrap(capturedFirstState)

        let firstRestore = ComparisonModel()
        firstRestore.restoreSession(firstState)
        await waitUntilIdle(firstRestore)
        let capturedSecondState = try await firstRestore.sessionState(windowFrame: sessionFrame())
        let secondState = try XCTUnwrap(capturedSecondState)

        let secondRestore = ComparisonModel()
        secondRestore.restoreSession(secondState)
        await waitUntilIdle(secondRestore)
        XCTAssertEqual(secondRestore.left.text, firstRestore.left.text)
        XCTAssertEqual(secondRestore.right.text, firstRestore.right.text)
        XCTAssertFalse(secondRestore.hasUnsavedChanges)
    }

    func testSessionStatePreservesExplicitLegacyEncoding() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "left")
        let rightURL = try temporaryFile(
            name: "right.txt",
            data: Data([0x1B, 0x24, 0x42, 0x25, 0x24, 0x1B, 0x28, 0x42])
        )
        let source = ComparisonModel()
        source.enqueueOpen(leftURL, into: .left)
        source.load(rightURL, into: .right, assuming: .iso2022JP)
        await waitUntilIdle(source)
        let capturedState = try await source.sessionState(windowFrame: try sessionFrame())
        let state = try XCTUnwrap(capturedState)
        XCTAssertEqual(state.rightEncoding, .iso2022JP)

        let restored = ComparisonModel()
        restored.restoreSession(state)
        await waitUntilIdle(restored)

        XCTAssertEqual(restored.right.document?.encoding, .iso2022JP)
        XCTAssertEqual(restored.right.text, source.right.text)
    }

    func testSessionRestoreDerivesCommentSyntaxFromRestoredFileURLs() async throws {
        let leftURL = try temporaryFile(name: "left.c", content: "value // left\n")
        let rightURL = try temporaryFile(name: "right.c", content: "value // right\n")
        let state = try ComparisonSessionState(
            left: .file(leftURL),
            right: .file(rightURL),
            windowFrame: try sessionFrame()
        )
        let model = ComparisonModel()
        var options = model.options
        options.ignoreComments = true
        model.setOptions(options)

        model.restoreSession(state)
        await waitUntilIdle(model)

        XCTAssertEqual(model.summary.differences, 0)
        XCTAssertEqual(model.rows.map(\.kind), [.unchanged])
    }

    func testFailedSessionRestoreDoesNotPartiallyPublishOneSide() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let state = try ComparisonSessionState(
            left: .scratchpad("left"),
            right: .file(missing),
            leftReadOnly: true,
            rightReadOnly: true,
            windowFrame: ComparisonSessionState.WindowFrame(
                x: 10,
                y: 20,
                width: 800,
                height: 600
            )
        )
        let model = ComparisonModel()

        model.restoreSession(state)
        await waitUntilIdle(model)

        XCTAssertFalse(model.left.isLoaded)
        XCTAssertFalse(model.right.isLoaded)
        XCTAssertNotNil(model.errorMessage)
    }

    func testSessionRestoreDiffFailureDoesNotPublishLoadedSides() async throws {
        let tooManyLines = String(repeating: "\n", count: 1_048_577)
        let state = try ComparisonSessionState(
            left: .scratchpad(tooManyLines),
            right: .scratchpad("right"),
            windowFrame: try sessionFrame()
        )
        let model = ComparisonModel()
        var result: SessionRestoreResult?

        model.restoreSession(state) { result = $0 }
        await waitUntilIdle(model)

        XCTAssertEqual(result, .failed)
        XCTAssertFalse(model.left.isLoaded)
        XCTAssertFalse(model.right.isLoaded)
        XCTAssertNotNil(model.errorMessage)
    }

    func testExplicitOpenCancelsInFlightSessionRestoreWithoutPublishingSavedPeer() async throws {
        let state = try ComparisonSessionState(
            left: .scratchpad(String(repeating: "left\n", count: 500_000)),
            right: .scratchpad("saved right"),
            windowFrame: try sessionFrame()
        )
        let explicit = try temporaryFile(name: "explicit.txt", content: "explicit")
        let model = ComparisonModel()
        var results: [SessionRestoreResult] = []

        model.restoreSession(state) { results.append($0) }
        model.enqueueOpen(explicit, into: .left)
        await waitUntilIdle(model)

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(results, [.cancelled])
        XCTAssertEqual(model.left.url, explicit)
        XCTAssertFalse(model.right.isLoaded)
        XCTAssertEqual(model.left.text, "explicit")
    }

    func testSessionStateRejectsDirtyOrPartiallyLoadedModel() async throws {
        let frame = try sessionFrame()
        let model = ComparisonModel()
        let emptyState = try await model.sessionState(windowFrame: frame)
        XCTAssertNil(emptyState)

        model.createEmptyComparison()
        model.editText("dirty", on: .left)
        let dirtyState = try await model.sessionState(windowFrame: frame)
        XCTAssertNil(dirtyState)
    }

    func testSessionPersistenceLockBlocksEditsUntilReleased() async throws {
        let leftURL = try temporaryFile(name: "left.txt", content: "left")
        let rightURL = try temporaryFile(name: "right.txt", content: "right")
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)

        XCTAssertTrue(model.lockSessionPersistence())
        model.editText("changed", on: .left)
        XCTAssertEqual(model.left.text, "left")
        XCTAssertFalse(model.canSetEditable(on: .left))

        model.unlockSessionPersistence()
        model.editText("changed", on: .left)
        XCTAssertEqual(model.left.text, "changed")
    }

    func testExplicitOpenDoesNotFollowOldBookmarkResolution() async throws {
        let suiteName = "MacMergeTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { userDefaults.removePersistentDomain(forName: suiteName) }
        let original = try temporaryFile(name: "original.txt", content: "original")
        let moved = try temporaryFile(name: "moved.txt", content: "moved")
        let right = try temporaryFile(name: "right.txt", content: "right")
        let bookmarkStore = SecurityScopedBookmarkStore(
            userDefaults: userDefaults,
            createBookmark: { _ in Data("bookmark".utf8) },
            resolveBookmark: { _ in .init(url: moved, isStale: false) }
        )
        try bookmarkStore.persistAccess(to: original)
        let model = ComparisonModel(bookmarkStore: bookmarkStore)

        model.enqueueOpen([original, right])
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.url, original)
        XCTAssertEqual(model.left.text, "original")
    }

    private func sessionFrame() throws -> ComparisonSessionState.WindowFrame {
        try ComparisonSessionState.WindowFrame(
            x: 10,
            y: 20,
            width: 800,
            height: 600
        )
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
