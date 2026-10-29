import Foundation
import MacMergeCore
import XCTest

/// Edge-case coverage for `SelectedFilePairTextOpenBatch` beyond the main behavior tests.
final class SelectedFilePairTextOpenBatchCoverageTests: XCTestCase {
    private typealias Batch = SelectedFilePairTextOpenBatch

    private var workspace: URL!
    private var leftRoot: URL { workspace.appendingPathComponent("left", isDirectory: true) }
    private var rightRoot: URL { workspace.appendingPathComponent("right", isDirectory: true) }

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectedFilePairTextOpenBatchCoverageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: leftRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rightRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
    }

    // MARK: - Limits

    func testLimitsClampToAtLeastOneAndToHardMaximums() {
        let floor = Batch.Limits(maximumSelectedResults: 0, maximumOpenedPairs: -5, sniffByteCount: 0)
        XCTAssertEqual(floor.maximumSelectedResults, 1)
        XCTAssertEqual(floor.maximumOpenedPairs, 1)
        XCTAssertEqual(floor.sniffByteCount, 1)

        let ceiling = Batch.Limits(
            maximumSelectedResults: .max,
            maximumOpenedPairs: .max,
            sniffByteCount: .max
        )
        XCTAssertEqual(ceiling.maximumSelectedResults, Batch.Limits.hardMaximumSelectedResults)
        XCTAssertEqual(ceiling.maximumOpenedPairs, Batch.Limits.hardMaximumOpenedPairs)
        XCTAssertEqual(ceiling.sniffByteCount, Batch.Limits.hardMaximumSniffByteCount)

        XCTAssertEqual(Batch.Limits.default.maximumSelectedResults, 10_000)
        XCTAssertEqual(Batch.Limits.default.maximumOpenedPairs, 32)
        XCTAssertEqual(Batch.Limits.default.sniffByteCount, 8 * 1_024)
    }

    func testSelectionAtExactlyTheMaximumIsAccepted() throws {
        try writeBoth("a.txt", "a")
        try writeBoth("b.txt", "b")
        let results = makeResults([both("a.txt"), both("b.txt")], selectAll: true)

        let plan = try Batch.plan(results: results, limits: Batch.Limits(maximumSelectedResults: 2))

        XCTAssertEqual(plan.pairs.count, 2)
    }

    func testTooLargeSelectionThrowsEvenWhenIDsAreStale() {
        let results = makeResults([], selectAll: false)
        let stale = Set((0..<3).map { DirectoryResult.ID(leftRelativePath: "g\($0)", rightRelativePath: "g\($0)") })

        XCTAssertThrowsError(
            try Batch.plan(
                results: results,
                selectedIDs: stale,
                limits: Batch.Limits(maximumSelectedResults: 2)
            )
        ) { error in
            XCTAssertEqual(error as? Batch.Error, .selectionTooLarge(count: 3, maximum: 2))
        }
    }

    func testEmptyExplicitSelectionThrowsEvenWhenResultsHaveASelection() {
        let results = makeResults([both("a.txt")], selectAll: true)

        XCTAssertThrowsError(try Batch.plan(results: results, selectedIDs: [])) { error in
            XCTAssertEqual(error as? Batch.Error, .emptySelection)
        }
    }

    // MARK: - Selection source

    func testExplicitSelectedIDsOverrideTheResultsSelection() throws {
        try writeBoth("a.txt", "a")
        try writeBoth("b.txt", "b")
        let a = both("a.txt")
        let b = both("b.txt")
        var results = makeResults([a, b], selectAll: false)
        results.setSelection([a.id])

        let plan = try Batch.plan(results: results, selectedIDs: [b.id])

        XCTAssertEqual(plan.pairs.map(\.resultIDs), [[b.id]])
        XCTAssertEqual(plan.selectedCount, 1)
    }

    func testOnlyStaleSelectionsProduceAnEmptyPlan() throws {
        let results = makeResults([both("a.txt")], selectAll: false)
        let stale = DirectoryResult.ID(leftRelativePath: "gone", rightRelativePath: "gone")

        let plan = try Batch.plan(results: results, selectedIDs: [stale])

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.rejections.map(\.reason), [.noLongerInResults])
        XCTAssertEqual(plan.rejections.map(\.resultID), [stale])
        XCTAssertEqual(plan.selectedCount, 1)
    }

    func testHiddenSelectionsAreOrderedByRelativePath() throws {
        let results = makeResults([both("a.txt")], selectAll: false)
        let ids = ["z", "b", "m"].map { DirectoryResult.ID(leftRelativePath: $0, rightRelativePath: $0) }

        let plan = try Batch.plan(results: results, selectedIDs: Set(ids))

        XCTAssertEqual(plan.rejections.map(\.relativePath), ["b", "m", "z"])
    }

    // MARK: - Combine rule

    func testTwoLeftOnlyRowsAreNotCombined() throws {
        try write("a.txt", "a", root: leftRoot)
        try write("b.txt", "b", root: leftRoot)
        let a = DirectoryResult(left: file("a.txt"), right: nil, status: .leftOnly)
        let b = DirectoryResult(left: file("b.txt"), right: nil, status: .leftOnly)
        let results = makeResults([a, b], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.rejections.map(\.reason), [.missingSide(.right), .missingSide(.right)])
    }

    func testOneSidedFolderIsNotCombinedWithOneSidedFile() throws {
        try write("new.txt", "n", root: rightRoot)
        let folder = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "old", kind: .directory),
            right: nil,
            status: .leftOnly
        )
        let rightOnly = DirectoryResult(left: nil, right: file("new.txt"), status: .rightOnly)
        let results = makeResults([folder, rightOnly], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.isEmpty)
        let reasons = Dictionary(uniqueKeysWithValues: plan.rejections.map { ($0.resultID, $0.reason) })
        XCTAssertEqual(reasons[folder.id], .missingSide(.right))
        XCTAssertEqual(reasons[rightOnly.id], .missingSide(.left))
    }

    func testOneSidedRowsAreNotCombinedWhenAThirdSelectedRowIsHidden() throws {
        try write("old.txt", "o", root: leftRoot)
        try write("new.txt", "n", root: rightRoot)
        try writeBoth("same.txt", "s")
        let leftOnly = DirectoryResult(left: file("old.txt"), right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: file("new.txt"), status: .rightOnly)
        let hidden = both("same.txt", status: .identical)
        var results = makeResults([leftOnly, rightOnly, hidden], selectAll: true)
        results.filter = DirectoryResultFilter(statuses: [.leftOnly, .rightOnly])

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.selectedCount, 3)
        XCTAssertEqual(plan.rejections.count, 3)
        XCTAssertEqual(plan.rejections.last?.reason, .notVisible)
        XCTAssertEqual(plan.rejections.last?.resultID, hidden.id)
        XCTAssertEqual(
            Set(plan.rejections.prefix(2).map(\.reason)),
            [.missingSide(.left), .missingSide(.right)]
        )
    }

    func testOneSidedRowsAreNotCombinedWhenOneOfTwoSelectedRowsIsHidden() throws {
        try write("old.txt", "o", root: leftRoot)
        try write("new.txt", "n", root: rightRoot)
        let leftOnly = DirectoryResult(left: file("old.txt"), right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: file("new.txt"), status: .rightOnly)
        var results = makeResults([leftOnly, rightOnly], selectAll: true)
        results.filter = DirectoryResultFilter(statuses: [.leftOnly])

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.selectedCount, 2)
        XCTAssertEqual(plan.rejections.map(\.resultID), [leftOnly.id, rightOnly.id])
        XCTAssertEqual(plan.rejections.map(\.reason), [.missingSide(.right), .notVisible])
    }

    func testCombinedPairRejectedOnRightSideNamesTheRightSideForBothRows() throws {
        try write("old.txt", "old", root: leftRoot)
        try write("new.bin", Data([0x00, 0x01]), root: rightRoot)
        let leftOnly = DirectoryResult(left: file("old.txt"), right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: file("new.bin"), status: .rightOnly)
        let results = makeResults([leftOnly, rightOnly], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.rejections.map(\.reason), [.nonText(.right), .nonText(.right)])
        XCTAssertEqual(Set(plan.rejections.map(\.resultID)), [leftOnly.id, rightOnly.id])
    }

    func testCombinedPairWithMissingFileIsUnavailableForBothRows() throws {
        try write("old.txt", "old", root: leftRoot)
        let leftOnly = DirectoryResult(left: file("old.txt"), right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: file("vanished.txt"), status: .rightOnly)
        let results = makeResults([leftOnly, rightOnly], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.rejections.map(\.reason), [.unavailable, .unavailable])
        XCTAssertEqual(plan.selectedCount, plan.rejections.count)
    }

    func testCombinedPairURLsPointIntoTheirOwnRoots() throws {
        try write("old.txt", "old", root: leftRoot)
        try write("new.txt", "new", root: rightRoot)
        let leftOnly = DirectoryResult(left: file("old.txt"), right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: file("new.txt"), status: .rightOnly)
        let results = makeResults([leftOnly, rightOnly], selectAll: true)

        let pair = try XCTUnwrap(try Batch.plan(results: results).pairs.first)

        XCTAssertEqual(pair.leftURL.standardizedFileURL.path, leftRoot.appendingPathComponent("old.txt").standardizedFileURL.path)
        XCTAssertEqual(pair.rightURL.standardizedFileURL.path, rightRoot.appendingPathComponent("new.txt").standardizedFileURL.path)
    }

    // MARK: - Content sniffing

    func testNestedRelativePathsBuildFileURLsBeneathTheRoots() throws {
        try FileManager.default.createDirectory(
            at: leftRoot.appendingPathComponent("sub/dir"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rightRoot.appendingPathComponent("sub/dir"),
            withIntermediateDirectories: true
        )
        try writeBoth("sub/dir/a.txt", "a")
        let results = makeResults([both("sub/dir/a.txt")], selectAll: true)

        let pair = try XCTUnwrap(try Batch.plan(results: results).pairs.first)

        XCTAssertEqual(
            pair.leftURL.standardizedFileURL.path,
            leftRoot.appendingPathComponent("sub/dir/a.txt").standardizedFileURL.path
        )
        XCTAssertEqual(
            pair.rightURL.standardizedFileURL.path,
            rightRoot.appendingPathComponent("sub/dir/a.txt").standardizedFileURL.path
        )
        XCTAssertEqual(pair.displayName, "sub/dir/a.txt")
    }

    func testOnlyTheConfiguredSniffWindowIsInspected() throws {
        try write("late.txt", Data("abcdefgh".utf8) + Data([0x00]), root: leftRoot)
        try write("late.txt", "abcdefgh", root: rightRoot)
        let results = makeResults([both("late.txt")], selectAll: true)

        let narrow = try Batch.plan(results: results, limits: Batch.Limits(sniffByteCount: 4))
        let wide = try Batch.plan(results: results, limits: Batch.Limits(sniffByteCount: 64))

        XCTAssertEqual(narrow.pairs.count, 1)
        XCTAssertEqual(wide.rejections.map(\.reason), [.nonText(.left)])
    }

    func testEmptyAndUTF16FilesAreAcceptedAndUTF32LittleEndianIsRejected() throws {
        try writeBoth("empty.txt", "")
        try write("wide16.txt", Data([0xFF, 0xFE, 0x41, 0x00, 0x0A, 0x00]), root: leftRoot)
        try write("wide16.txt", Data([0xFE, 0xFF, 0x00, 0x41, 0x00, 0x0A]), root: rightRoot)
        try write("wide32.txt", "x", root: leftRoot)
        try write("wide32.txt", Data([0xFF, 0xFE, 0x00, 0x00, 0x41, 0, 0, 0]), root: rightRoot)
        let results = makeResults(
            [both("empty.txt"), both("wide16.txt"), both("wide32.txt")],
            selectAll: true
        )

        let plan = try Batch.plan(results: results)

        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["empty.txt", "wide16.txt"])
        XCTAssertEqual(plan.rejections.map(\.reason), [.unsupportedEncoding(.right)])
    }

    func testLeftSideIsReportedFirstWhenBothSidesAreBinary() throws {
        try write("both.bin", Data([0x00]), root: leftRoot)
        try write("both.bin", Data([0x00]), root: rightRoot)
        let results = makeResults([both("both.bin")], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertEqual(plan.rejections.map(\.reason), [.nonText(.left)])
    }

    func testRightRootSwappedForSymbolicLinkAfterScanStillReadsPinnedRoot() throws {
        try writeBoth("a.txt", "a")
        let results = makeResults([both("a.txt")], selectAll: true)
        let elsewhere = workspace.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try write("a.txt", Data([0x00]), root: elsewhere)
        try FileManager.default.moveItem(at: rightRoot, to: workspace.appendingPathComponent("moved-right"))
        try FileManager.default.createSymbolicLink(at: rightRoot, withDestinationURL: elsewhere)

        let plan = try Batch.plan(results: results)

        XCTAssertEqual(plan.pairs.count, 1)
        XCTAssertTrue(plan.rejections.isEmpty)
    }

    // MARK: - Open limit

    func testRowsBeyondTheOpenLimitAreNotSniffed() throws {
        try writeBoth("a.txt", "a")
        try write("b.bin", Data([0x00]), root: leftRoot)
        try write("b.bin", Data([0x00]), root: rightRoot)
        let results = makeResults([both("a.txt"), both("b.bin")], selectAll: true)

        let plan = try Batch.plan(results: results, limits: Batch.Limits(maximumOpenedPairs: 1))

        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["a.txt"])
        // A binary row past the limit reports the limit, proving it was never sniffed.
        XCTAssertEqual(plan.rejections.map(\.reason), [.openLimitReached])
    }

    func testRejectedRowsDoNotConsumeTheOpenLimit() throws {
        try write("a.bin", Data([0x00]), root: leftRoot)
        try write("a.bin", "", root: rightRoot)
        try writeBoth("b.txt", "b")
        try writeBoth("c.txt", "c")
        let folder = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "a-dir", kind: .directory),
            right: DirectoryEntryMetadata(relativePath: "a-dir", kind: .directory),
            status: .identical
        )
        let results = makeResults([folder, both("a.bin"), both("b.txt"), both("c.txt")], selectAll: true)

        let plan = try Batch.plan(results: results, limits: Batch.Limits(maximumOpenedPairs: 1))

        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["b.txt"])
        XCTAssertEqual(plan.rejections.map(\.relativePath), ["a-dir", "a.bin", "c.txt"])
        XCTAssertEqual(plan.rejections.map(\.reason), [.folder, .nonText(.left), .openLimitReached])
        XCTAssertEqual(plan.selectedCount, plan.pairs.count + plan.rejections.count)
    }

    // MARK: - Cancellation

    func testCancellationBetweenVisibleRowsStopsBeforeLaterRows() throws {
        try writeBoth("a.txt", "a")
        // b.bin is binary, so planning it would add a rejection instead of throwing.
        try write("b.bin", Data([0x00, 0x01]), root: leftRoot)
        try write("b.bin", Data([0x00, 0x01]), root: rightRoot)
        let results = makeResults([both("a.txt"), both("b.bin")], selectAll: true)

        // Checks: after visibleResults, before row a.txt, before row b.bin.
        let uncancelled = CoverageCallCounter()
        let plan = try Batch.plan(
            results: results,
            isCancelled: {
                _ = uncancelled.increment()
                return false
            })
        XCTAssertEqual(plan.rejections.map(\.reason), [.nonText(.left)])
        XCTAssertEqual(uncancelled.value, 3)

        let counter = CoverageCallCounter()
        XCTAssertThrowsError(
            try Batch.plan(results: results, isCancelled: { counter.increment() > 2 })
        ) { error in
            XCTAssertEqual(error as? Batch.Error, .cancelled)
        }
        XCTAssertEqual(counter.value, 3, "Cancelled on the check before b.bin, after a.txt was planned")
    }

    func testUncancelledCheckIsConsultedAndPlanCompletes() throws {
        try writeBoth("a.txt", "a")
        let results = makeResults([both("a.txt")], selectAll: true)
        let counter = CoverageCallCounter()

        let plan = try Batch.plan(
            results: results,
            isCancelled: {
                _ = counter.increment()
                return false
            })

        XCTAssertEqual(plan.pairs.count, 1)
        XCTAssertGreaterThan(counter.value, 0)
    }

    // MARK: - Text

    func testErrorDescriptions() {
        XCTAssertEqual(Batch.Error.emptySelection.errorDescription, "Select one or more file pairs to open.")
        XCTAssertEqual(
            Batch.Error.selectionTooLarge(count: 12, maximum: 10).errorDescription,
            "12 items are selected. Select at most 10 items to open."
        )
        XCTAssertEqual(
            Batch.Error.cancelled.errorDescription,
            "Opening the selected file pairs was canceled."
        )
    }

    func testRejectionSummariesAreDistinctAndNonEmpty() {
        let reasons = Self.allRejectionReasons
        reasons.forEach(Self.requireListed)
        let summaries = reasons.map(\.summary)

        XCTAssertTrue(summaries.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(summaries).count, reasons.count)
        XCTAssertEqual(Batch.RejectionReason.nonText(.right).summary, "right file is binary")
        XCTAssertEqual(Batch.RejectionReason.missingSide(.left).summary, "no left file")
    }

    // MARK: - Helpers

    private static let allRejectionReasons: [Batch.RejectionReason] = [
        .missingSide(.left), .missingSide(.right), .folder, .notRegularFile, .typeMismatch,
        .notVisible, .noLongerInResults, .unavailable, .nonText(.left), .nonText(.right),
        .unsupportedEncoding(.left), .unsupportedEncoding(.right), .openLimitReached
    ]

    /// Exhaustive on purpose: a new `RejectionReason` case breaks the build here until it is added
    /// to `allRejectionReasons`.
    private static func requireListed(_ reason: Batch.RejectionReason) {
        switch reason {
        case .missingSide, .folder, .notRegularFile, .typeMismatch, .notVisible,
            .noLongerInResults, .unavailable, .nonText, .unsupportedEncoding, .openLimitReached:
            break
        }
    }

    private func file(_ path: String) -> DirectoryEntryMetadata {
        DirectoryEntryMetadata(relativePath: path, kind: .file)
    }

    private func both(
        _ path: String,
        status: DirectoryComparisonStatus = .different
    ) -> DirectoryResult {
        DirectoryResult(left: file(path), right: file(path), status: status)
    }

    private func makeResults(_ rows: [DirectoryResult], selectAll: Bool) -> DirectoryResults {
        DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: rows,
            selectedIDs: selectAll ? Set(rows.map(\.id)) : []
        )
    }

    private func writeBoth(_ path: String, _ text: String) throws {
        try write(path, text, root: leftRoot)
        try write(path, text, root: rightRoot)
    }

    private func write(_ path: String, _ text: String, root: URL) throws {
        try write(path, Data(text.utf8), root: root)
    }

    private func write(_ path: String, _ data: Data, root: URL) throws {
        try data.write(to: root.appendingPathComponent(path))
    }
}

private final class CoverageCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
