import Foundation
import MacMergeCore
import XCTest

final class SelectedFilePairTextOpenBatchTests: XCTestCase {
    private typealias Batch = SelectedFilePairTextOpenBatch

    private var workspace: URL!
    private var leftRoot: URL { workspace.appendingPathComponent("left", isDirectory: true) }
    private var rightRoot: URL { workspace.appendingPathComponent("right", isDirectory: true) }

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectedFilePairTextOpenBatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: leftRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rightRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
    }

    // MARK: - classify

    func testClassifyTreatsPlainAndEmptyContentAsText() {
        XCTAssertEqual(Batch.classify(prefix: Data()), .text)
        XCTAssertEqual(Batch.classify(prefix: Data("hello\nworld".utf8)), .text)
        XCTAssertEqual(Batch.classify(prefix: Data([0xEF, 0xBB, 0xBF]) + Data("bom".utf8)), .text)
    }

    func testClassifyAcceptsUTF16ByteOrderMarksDespiteNULBytes() {
        XCTAssertEqual(Batch.classify(prefix: Data([0xFF, 0xFE, 0x41, 0x00])), .text)
        XCTAssertEqual(Batch.classify(prefix: Data([0xFE, 0xFF, 0x00, 0x41])), .text)
    }

    func testClassifyRejectsNULWithoutByteOrderMarkAsBinary() {
        XCTAssertEqual(Batch.classify(prefix: Data([0x41, 0x00, 0x42])), .binary)
    }

    func testClassifyReportsUTF32ByteOrderMarksAsUnsupported() {
        XCTAssertEqual(Batch.classify(prefix: Data([0xFF, 0xFE, 0x00, 0x00, 0x41, 0, 0, 0])), .unsupportedEncoding)
        XCTAssertEqual(Batch.classify(prefix: Data([0x00, 0x00, 0xFE, 0xFF, 0, 0, 0, 0x41])), .unsupportedEncoding)
    }

    // MARK: - plan

    func testEveryBothSidedTextRowBecomesItsOwnPairInVisibleOrder() throws {
        // Deliberate deviation from WinMerge AreItemsOpenable, which refuses two both-sided rows.
        try writeBoth("b.txt", "b")
        try writeBoth("a.txt", "a")
        let results = makeResults([both("b.txt"), both("a.txt")], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["a.txt", "b.txt"])
        XCTAssertEqual(plan.pairs.map(\.status), [.different, .different])
        XCTAssertEqual(plan.pairs[0].leftURL.lastPathComponent, "a.txt")
        XCTAssertTrue(plan.rejections.isEmpty)
        XCTAssertEqual(plan.selectedCount, 2)
    }

    func testOneLeftOnlyAndOneRightOnlyFileAreCombined() throws {
        try write("old.txt", "old", root: leftRoot)
        try write("new.txt", "new", root: rightRoot)
        let leftOnly = DirectoryResult(left: file("old.txt"), right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: file("new.txt"), status: .rightOnly)
        let results = makeResults([leftOnly, rightOnly], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertEqual(plan.pairs.count, 1)
        XCTAssertEqual(plan.pairs[0].leftRelativePath, "old.txt")
        XCTAssertEqual(plan.pairs[0].rightRelativePath, "new.txt")
        XCTAssertEqual(plan.pairs[0].displayName, "old.txt ↔ new.txt")
        XCTAssertEqual(Set(plan.pairs[0].resultIDs), [leftOnly.id, rightOnly.id])
        XCTAssertNil(plan.pairs[0].status)
        XCTAssertTrue(plan.rejections.isEmpty)
    }

    func testRejectedCombinedPairAccountsForBothSelectedRows() throws {
        try write("old.bin", Data([0x41, 0x00]), root: leftRoot)
        try write("new.txt", "new", root: rightRoot)
        let leftOnly = DirectoryResult(left: file("old.bin"), right: nil, status: .leftOnly)
        let rightOnly = DirectoryResult(left: nil, right: file("new.txt"), status: .rightOnly)
        let results = makeResults([leftOnly, rightOnly], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.pairs.isEmpty)
        XCTAssertEqual(plan.rejections.count, 2)
        XCTAssertEqual(Set(plan.rejections.map(\.resultID)), [leftOnly.id, rightOnly.id])
        XCTAssertEqual(Set(plan.rejections.map(\.relativePath)), ["old.bin", "new.txt"])
        XCTAssertTrue(plan.rejections.allSatisfy { $0.reason == .nonText(.left) })
        XCTAssertEqual(plan.selectedCount, plan.rejections.count)
    }

    func testOneSidedRowIsNotCombinedWithBothSidedRow() throws {
        // WinMerge GetOpenTwoItems would combine these; this batch rejects the one-sided row.
        try writeBoth("same.txt", "x")
        try write("extra.txt", "y", root: leftRoot)
        let leftOnly = DirectoryResult(left: file("extra.txt"), right: nil, status: .leftOnly)
        let results = makeResults([both("same.txt"), leftOnly], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["same.txt"])
        XCTAssertEqual(plan.rejections.map(\.reason), [.missingSide(.right)])
        XCTAssertEqual(plan.rejections.map(\.resultID), [leftOnly.id])
    }

    func testStructuralRejections() throws {
        let folder = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "dir", kind: .directory),
            right: DirectoryEntryMetadata(relativePath: "dir", kind: .directory),
            status: .identical
        )
        let mismatch = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "mix", kind: .file),
            right: DirectoryEntryMetadata(relativePath: "mix", kind: .directory),
            status: .typeMismatch
        )
        let link = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "link", kind: .symbolicLink),
            right: DirectoryEntryMetadata(relativePath: "link", kind: .symbolicLink),
            status: .identical
        )
        let special = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "special", kind: .other),
            right: DirectoryEntryMetadata(relativePath: "special", kind: .other),
            status: .identical
        )
        let fileVersusLink = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "file-vs-link", kind: .file),
            right: DirectoryEntryMetadata(relativePath: "file-vs-link", kind: .symbolicLink),
            status: .typeMismatch
        )
        let rightOnly = DirectoryResult(left: nil, right: file("r.txt"), status: .rightOnly)
        let missing = both("missing.txt")
        let results = makeResults(
            [folder, mismatch, link, special, fileVersusLink, rightOnly, missing],
            selectAll: true
        )

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.pairs.isEmpty)
        let reasons = Dictionary(uniqueKeysWithValues: plan.rejections.map { ($0.relativePath, $0.reason) })
        XCTAssertEqual(reasons["dir"], .folder)
        XCTAssertEqual(reasons["mix"], .typeMismatch)
        XCTAssertEqual(reasons["link"], .notRegularFile)
        XCTAssertEqual(reasons["special"], .notRegularFile)
        XCTAssertEqual(reasons["file-vs-link"], .typeMismatch)
        XCTAssertEqual(reasons["r.txt"], .missingSide(.left))
        XCTAssertEqual(reasons["missing.txt"], .unavailable)
    }

    func testContentRejectionsNameTheSide() throws {
        try write("bin.txt", "text", root: leftRoot)
        try write("bin.txt", Data([0x00, 0x01]), root: rightRoot)
        try write("wide.txt", Data([0x00, 0x00, 0xFE, 0xFF]), root: leftRoot)
        try write("wide.txt", "text", root: rightRoot)
        let results = makeResults([both("bin.txt"), both("wide.txt")], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertTrue(plan.pairs.isEmpty)
        XCTAssertEqual(plan.rejections.map(\.reason), [.nonText(.right), .unsupportedEncoding(.left)])
    }

    func testSymbolicLinkSwappedInAfterScanIsUnavailable() throws {
        try write("real.txt", "secret", root: workspace)
        try FileManager.default.createSymbolicLink(
            at: leftRoot.appendingPathComponent("swap.txt"),
            withDestinationURL: workspace.appendingPathComponent("real.txt")
        )
        try write("swap.txt", "text", root: rightRoot)
        let results = makeResults([both("swap.txt")], selectAll: true)

        let plan = try Batch.plan(results: results)

        XCTAssertEqual(plan.rejections.map(\.reason), [.unavailable])
    }

    func testSniffUsesRootsPinnedWhenResultsWereCreated() throws {
        try writeBoth("a.txt", "a")
        let results = makeResults([both("a.txt")], selectAll: true)
        // Replace the left root with a symbolic link to a different folder after the scan.
        let elsewhere = workspace.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try write("a.txt", Data([0x00]), root: elsewhere)
        try FileManager.default.moveItem(at: leftRoot, to: workspace.appendingPathComponent("moved"))
        try FileManager.default.createSymbolicLink(at: leftRoot, withDestinationURL: elsewhere)

        let plan = try Batch.plan(results: results)

        // The pinned root still reads the original text file, not the binary replacement.
        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["a.txt"])
        XCTAssertTrue(plan.rejections.isEmpty)
    }

    func testOpenLimitReachedAppliesAfterEarlierRowsInVisibleOrder() throws {
        for name in ["a.txt", "b.txt", "c.txt"] {
            try writeBoth(name, name)
        }
        let results = makeResults([both("c.txt"), both("a.txt"), both("b.txt")], selectAll: true)

        let plan = try Batch.plan(
            results: results,
            limits: Batch.Limits(maximumOpenedPairs: 2)
        )

        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["a.txt", "b.txt"])
        XCTAssertEqual(plan.rejections.map(\.relativePath), ["c.txt"])
        XCTAssertEqual(plan.rejections.map(\.reason), [.openLimitReached])
    }

    func testHiddenAndStaleSelectionsAreRejectedAfterVisibleRows() throws {
        try writeBoth("shown.txt", "x")
        try writeBoth("hidden.txt", "y")
        var results = makeResults(
            [both("shown.txt", status: .different), both("hidden.txt", status: .identical)],
            selectAll: false
        )
        results.filter = DirectoryResultFilter(statuses: [.different])
        let stale = DirectoryResult.ID(leftRelativePath: "gone.txt", rightRelativePath: "gone.txt")
        let hidden = DirectoryResult.ID(leftRelativePath: "hidden.txt", rightRelativePath: "hidden.txt")
        let shown = DirectoryResult.ID(leftRelativePath: "shown.txt", rightRelativePath: "shown.txt")

        let plan = try Batch.plan(results: results, selectedIDs: [stale, hidden, shown])

        XCTAssertEqual(plan.pairs.map(\.leftRelativePath), ["shown.txt"])
        XCTAssertEqual(plan.rejections.map(\.relativePath), ["gone.txt", "hidden.txt"])
        XCTAssertEqual(plan.rejections.map(\.reason), [.noLongerInResults, .notVisible])
        XCTAssertEqual(plan.selectedCount, 3)
    }

    func testEmptyAndTooLargeSelectionsThrowBeforeAnyPlanningWork() {
        let results = makeResults([both("a.txt"), both("b.txt")], selectAll: false)
        // The first cancellation check precedes all row and file work, so zero calls proves the
        // refusal happened before it.
        let counter = CallCounter()
        let isCancelled: Batch.CancellationCheck = {
            _ = counter.increment()
            return false
        }

        XCTAssertThrowsError(try Batch.plan(results: results, isCancelled: isCancelled)) { error in
            XCTAssertEqual(error as? Batch.Error, .emptySelection)
        }
        let ids = Set(results.results.map(\.id))
        XCTAssertThrowsError(
            try Batch.plan(
                results: results,
                selectedIDs: ids,
                limits: Batch.Limits(maximumSelectedResults: 1),
                isCancelled: isCancelled
            )
        ) { error in
            XCTAssertEqual(error as? Batch.Error, .selectionTooLarge(count: 2, maximum: 1))
        }
        XCTAssertEqual(counter.value, 0)
    }

    func testCancellationStopsPlanning() throws {
        try writeBoth("a.txt", "a")
        let results = makeResults([both("a.txt")], selectAll: true)

        XCTAssertThrowsError(try Batch.plan(results: results, isCancelled: { true })) { error in
            XCTAssertEqual(error as? Batch.Error, .cancelled)
        }
    }

    func testCancellationIsCheckedWhileRejectingManyHiddenSelections() throws {
        let results = makeResults([both("a.txt")], selectAll: false)
        let stale = Set(
            (0..<1_000).map {
                DirectoryResult.ID(leftRelativePath: "gone-\($0)", rightRelativePath: "gone-\($0)")
            })
        // Checks: after visibleResults, before the hidden loop, then at offsets 0, 256, 512, 768.
        let uncancelled = CallCounter()
        let plan = try Batch.plan(
            results: results, selectedIDs: stale,
            isCancelled: {
                _ = uncancelled.increment()
                return false
            })
        XCTAssertEqual(plan.rejections.count, 1_000)
        XCTAssertEqual(uncancelled.value, 6)

        // Cancelling on the last check (offset 768) needs the repeated in-loop checks.
        let counter = CallCounter()
        XCTAssertThrowsError(
            try Batch.plan(
                results: results, selectedIDs: stale,
                isCancelled: {
                    counter.increment() > 5
                })
        ) { error in
            XCTAssertEqual(error as? Batch.Error, .cancelled)
        }
        XCTAssertEqual(counter.value, 6)
    }

    // MARK: - Helpers

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

private final class CallCounter: @unchecked Sendable {
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
