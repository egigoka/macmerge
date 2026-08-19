import MacMergeCore
import XCTest

private struct DetachedCoreComparisonPayload: Sendable {
    let result: LineDiffResult
    let rowIDs: [DiffRow.ID]
    let rowKinds: [DiffKind]
    let differenceRowIndices: [Int]
    let movedLines: MovedLines
    let leftToRightMovedPairs: [MovedLinePair]
    let rightToLeftMovedPairs: [MovedLinePair]
    let summary: DiffSummary
}

@MainActor
final class ComparisonIsolationTests: XCTestCase {
    func testComparisonResultAndCoreMetadataCrossDetachedTaskBoundary() async throws {
        let operation: @Sendable () async throws -> DetachedCoreComparisonPayload = {
            try Self.buildComparisonAndCoreMetadata()
        }

        let payload = try await Task.detached(operation: operation).value

        XCTAssertEqual(payload.rowIDs, [
            DiffRow.ID(leftNumber: 1, rightNumber: 1),
            DiffRow.ID(leftNumber: 2, rightNumber: nil),
            DiffRow.ID(leftNumber: 3, rightNumber: nil),
            DiffRow.ID(leftNumber: 4, rightNumber: nil),
            DiffRow.ID(leftNumber: 5, rightNumber: 2),
            DiffRow.ID(leftNumber: 6, rightNumber: 3),
            DiffRow.ID(leftNumber: 7, rightNumber: 4),
            DiffRow.ID(leftNumber: nil, rightNumber: 5),
            DiffRow.ID(leftNumber: nil, rightNumber: 6),
            DiffRow.ID(leftNumber: nil, rightNumber: 7),
            DiffRow.ID(leftNumber: 8, rightNumber: 8)
        ])
        XCTAssertEqual(payload.rowKinds, [
            .unchanged, .removed, .removed, .removed, .unchanged, .unchanged,
            .unchanged, .added, .added, .added, .unchanged
        ])
        XCTAssertEqual(payload.differenceRowIndices, [1, 2, 3, 7, 8, 9])
        XCTAssertEqual(payload.summary.unchanged, 5)
        XCTAssertEqual(payload.summary.modified, 0)
        XCTAssertEqual(payload.summary.removed, 3)
        XCTAssertEqual(payload.summary.added, 3)
        XCTAssertEqual(payload.summary.differences, 6)
        XCTAssertEqual(payload.leftToRightMovedPairs.map(\.leftLine), [2, 3, 4])
        XCTAssertEqual(payload.leftToRightMovedPairs.map(\.rightLine), [5, 6, 7])
        XCTAssertEqual(payload.rightToLeftMovedPairs.map(\.leftLine), [2, 3, 4])
        XCTAssertEqual(payload.rightToLeftMovedPairs.map(\.rightLine), [5, 6, 7])
        XCTAssertEqual(payload.movedLines.rightLine(forLeftLine: 3), 6)
        XCTAssertEqual(payload.movedLines.leftLine(forRightLine: 6), 3)
        XCTAssertEqual(payload.movedLines.shallowStorageBytes, 48)
        XCTAssertEqual(payload.result.rows.map(\.id), payload.rowIDs)
        XCTAssertEqual(payload.result.movedLines, payload.movedLines)
    }

    private nonisolated static func buildComparisonAndCoreMetadata() throws -> DetachedCoreComparisonPayload {
        let result = try LineDiff.compareResult(
            left: "head\nduplicate\nunique moved seed\nduplicate\nstable one\nstable two\nstable three\ntail",
            right: "head\nstable one\nstable two\nstable three\nduplicate\nunique moved seed\nduplicate\ntail",
            options: LineDiffOptions(detectMovedBlocks: true)
        )
        let rows = result.rows
        let movedLines = result.movedLines

        return DetachedCoreComparisonPayload(
            result: result,
            rowIDs: rows.map(\.id),
            rowKinds: rows.map(\.kind),
            differenceRowIndices: rows.indices.filter { rows[$0].kind != .unchanged },
            movedLines: movedLines,
            leftToRightMovedPairs: (0..<movedLines.leftToRightCount).map {
                movedLines.leftToRightPair(at: $0)
            },
            rightToLeftMovedPairs: (0..<movedLines.rightToLeftCount).map {
                movedLines.rightToLeftPair(at: $0)
            },
            summary: DiffSummary(rows: rows)
        )
    }
}
