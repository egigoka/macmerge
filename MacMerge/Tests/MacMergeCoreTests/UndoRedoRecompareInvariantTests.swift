@testable import MacMergeCore
import XCTest

final class UndoRedoRecompareInvariantTests: XCTestCase {
    func testHistoryPreservesCanonicallyEquivalentByteChangesAcrossUndoRedo() throws {
        let nfc = "\u{00E9}"
        let nfd = "\u{0065}\u{0301}"
        let before = ComparisonSnapshot(left: "caf\(nfc)", right: "stable")
        let after = ComparisonSnapshot(left: "caf\(nfd)", right: "stable")

        XCTAssertEqual(before.left, after.left)
        XCTAssertNotEqual(Array(before.left.utf8), Array(after.left.utf8))

        var history = ComparisonHistory(current: before)
        XCTAssertTrue(history.commit(after))
        assertSnapshotBytesEqual(history.current, after, "commit", file: #filePath, line: #line)

        let undone = try XCTUnwrap(history.undo())
        assertSnapshotBytesEqual(undone, before, "undo", file: #filePath, line: #line)

        let redone = try XCTUnwrap(history.redo())
        assertSnapshotBytesEqual(redone, after, "redo", file: #filePath, line: #line)
    }

    func testRowMergeUndoRedoRecompareRestoresExactResultsInBothDirections() throws {
        let before = ComparisonSnapshot(
            left: "alpha\r\nleft-selected\nstable\runrelated-left\r\nomega",
            right: "alpha\nright-selected\r\nstable\r\nunrelated-right\nomega"
        )
        try assertRowMergeUndoRedoRecomparison(
            before: before,
            options: LineDiffOptions(algorithm: .histogram),
            kind: .modified,
            selectedLeft: "left-selected",
            selectedRight: "right-selected"
        )
    }

    func testRemovedRowMergeUndoRedoRecompareRestoresExactResultsInBothDirections() throws {
        let before = ComparisonSnapshot(
            left: "alpha\r\nleft-only\nstable\runrelated-left\r\nomega",
            right: "alpha\nstable\r\nunrelated-right\nomega"
        )
        try assertRowMergeUndoRedoRecomparison(
            before: before,
            options: LineDiffOptions(algorithm: .histogram),
            kind: .removed,
            selectedLeft: "left-only",
            selectedRight: nil
        )
    }

    func testAddedRowMergeUndoRedoRecompareRestoresExactResultsInBothDirections() throws {
        let before = ComparisonSnapshot(
            left: "alpha\r\nstable\runrelated-left\r\nomega",
            right: "alpha\nright-only\r\nstable\r\nunrelated-right\nomega"
        )
        try assertRowMergeUndoRedoRecomparison(
            before: before,
            options: LineDiffOptions(algorithm: .histogram),
            kind: .added,
            selectedLeft: nil,
            selectedRight: "right-only"
        )
    }

    private func assertRowMergeUndoRedoRecomparison(
        before: ComparisonSnapshot,
        options: LineDiffOptions,
        kind: DiffKind,
        selectedLeft: String?,
        selectedRight: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let beforeRows = try rows(for: before, options: options)
        let selectedRow = try XCTUnwrap(beforeRows.first {
            $0.kind == kind
                && $0.left?.text == selectedLeft
                && $0.right?.text == selectedRight
        }, file: file, line: line)

        XCTAssertEqual(DiffSummary(rows: beforeRows).differences, 2, file: file, line: line)

        for direction in [MergeDirection.leftToRight, .rightToLeft] {
            let context = "\(kind) row merge, \(direction)"
            let result = try XCTUnwrap(LineMerge.apply(
                rowID: selectedRow.id,
                direction: direction,
                left: before.left,
                right: before.right,
                options: options
            ), context, file: file, line: line)
            let after = ComparisonSnapshot(left: result.left, right: result.right)
            let afterRows = try rows(for: after, options: options)

            XCTAssertEqual(DiffSummary(rows: afterRows).differences, 1, context, file: file, line: line)
            try assertUndoRedoRecomparison(
                before: before,
                beforeRows: beforeRows,
                after: after,
                afterRows: afterRows,
                options: options,
                context: context,
                file: file,
                line: line
            )
        }
    }

    func testMergeAllUndoRedoRecompareRestoresExactResultsInBothDirections() throws {
        let before = ComparisonSnapshot(
            left: "alpha\r\nleft-modified\nleft-only\rstable\r\nomega",
            right: "alpha\nright-modified\r\nstable\nright-only\r\nomega\n"
        )
        let options = LineDiffOptions(algorithm: .minimal)
        let beforeRows = try rows(for: before, options: options)

        XCTAssertGreaterThan(DiffSummary(rows: beforeRows).differences, 0)

        for direction in [MergeDirection.leftToRight, .rightToLeft] {
            let context = "merge all, \(direction)"
            let result = try XCTUnwrap(LineMerge.applyAll(
                direction: direction,
                left: before.left,
                right: before.right,
                options: options
            ), context)
            let after = ComparisonSnapshot(left: result.left, right: result.right)
            let afterRows = try rows(for: after, options: options)

            XCTAssertEqual(DiffSummary(rows: afterRows).differences, 0, context)
            try assertUndoRedoRecomparison(
                before: before,
                beforeRows: beforeRows,
                after: after,
                afterRows: afterRows,
                options: options,
                context: context
            )
        }
    }

    private func assertUndoRedoRecomparison(
        before: ComparisonSnapshot,
        beforeRows: [DiffRow],
        after: ComparisonSnapshot,
        afterRows: [DiffRow],
        options: LineDiffOptions,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var history = ComparisonHistory(current: before)
        XCTAssertTrue(history.commit(after), context, file: file, line: line)

        let undone = try XCTUnwrap(history.undo(), "\(context): undo snapshot", file: file, line: line)
        assertSnapshotBytesEqual(undone, before, "\(context): undo", file: file, line: line)
        XCTAssertEqual(
            exactRows(try rows(for: undone, options: options)),
            exactRows(beforeRows),
            "\(context): undo recomparison",
            file: file,
            line: line
        )

        let redone = try XCTUnwrap(history.redo(), "\(context): redo snapshot", file: file, line: line)
        assertSnapshotBytesEqual(redone, after, "\(context): redo", file: file, line: line)
        XCTAssertEqual(
            exactRows(try rows(for: redone, options: options)),
            exactRows(afterRows),
            "\(context): redo recomparison",
            file: file,
            line: line
        )
    }

    private func rows(
        for snapshot: ComparisonSnapshot,
        options: LineDiffOptions
    ) throws -> [DiffRow] {
        try LineDiff.compare(left: snapshot.left, right: snapshot.right, options: options)
    }

    private func assertSnapshotBytesEqual(
        _ actual: ComparisonSnapshot,
        _ expected: ComparisonSnapshot,
        _ context: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(Array(actual.left.utf8), Array(expected.left.utf8), "\(context): left", file: file, line: line)
        XCTAssertEqual(Array(actual.right.utf8), Array(expected.right.utf8), "\(context): right", file: file, line: line)
    }

    private func exactRows(_ rows: [DiffRow]) -> [ExactRow] {
        rows.map {
            ExactRow(
                kind: $0.kind,
                leftNumber: $0.left?.number,
                leftBytes: $0.left.map { Array($0.text.utf8) },
                rightNumber: $0.right?.number,
                rightBytes: $0.right.map { Array($0.text.utf8) }
            )
        }
    }

    private struct ExactRow: Equatable {
        let kind: DiffKind
        let leftNumber: Int?
        let leftBytes: [UInt8]?
        let rightNumber: Int?
        let rightBytes: [UInt8]?
    }
}
