@testable import MacMergeCore
import XCTest

final class AdversarialDiffShapeTests: XCTestCase {
    func testLargeRepeatedRunKeepsUniqueInsertionSeparate() throws {
        let repeatedLineCount = 4_096
        let leftLines = ["head"]
            + Array(repeating: "same repeated payload", count: repeatedLineCount)
            + ["tail"]
        var rightLines = leftLines
        rightLines.insert("unique insertion", at: repeatedLineCount / 2 + 1)

        let rows = try LineDiff.compare(
            left: leftLines.joined(separator: "\n"),
            right: rightLines.joined(separator: "\n")
        )

        assertValidAlignment(rows, leftLines: leftLines, rightLines: rightLines)
        let summary = DiffSummary(rows: rows)
        XCTAssertEqual(summary.unchanged, leftLines.count)
        XCTAssertEqual(summary.modified, 0)
        XCTAssertEqual(summary.removed, 0)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(rows.filter { $0.kind != .unchanged }.map(\.right?.text), ["unique insertion"])
    }

    func testDuplicateInsertionDoesNotConsumeUniqueAnchor() throws {
        let leftLines = ["head", "duplicate", "pivot", "duplicate", "tail"]
        let rightLines = ["head", "duplicate", "duplicate", "pivot", "duplicate", "tail"]

        let rows = try LineDiff.compare(
            left: leftLines.joined(separator: "\n"),
            right: rightLines.joined(separator: "\n")
        )

        assertValidAlignment(rows, leftLines: leftLines, rightLines: rightLines)
        XCTAssertEqual(rows.filter { $0.kind == .unchanged }.map(\.left?.text), leftLines)
        let changes = rows.filter { $0.kind != .unchanged }
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, .added)
        XCTAssertNil(changes.first?.left)
        XCTAssertEqual(changes.first?.right?.text, "duplicate")
    }

    func testReorderedBlocksRetainOneEquivalentLongestAlignment() throws {
        let leftLines = ["start", "A1", "A2", "middle", "B1", "B2", "end"]
        let rightLines = ["start", "B1", "B2", "middle", "A1", "A2", "end"]

        let rows = try LineDiff.compare(
            left: leftLines.joined(separator: "\n"),
            right: rightLines.joined(separator: "\n"),
            options: LineDiffOptions(algorithm: .minimal)
        )

        assertValidAlignment(rows, leftLines: leftLines, rightLines: rightLines)
        let unchanged = rows.filter { $0.kind == .unchanged }.compactMap { $0.left?.text }
        XCTAssertTrue(
            unchanged == ["start", "A1", "A2", "end"]
                || unchanged == ["start", "B1", "B2", "end"],
            "Unexpected equivalent alignment: \(unchanged)"
        )
        let summary = DiffSummary(rows: rows)
        XCTAssertEqual(summary.unchanged, 4)
        XCTAssertEqual(summary.removed, 3)
        XCTAssertEqual(summary.added, 3)
        XCTAssertEqual(summary.modified, 0)
    }

    func testLowHashBucketCollisionChainStillComparesFullLines() throws {
        let bucketBits = 8
        let collidingLines = makeLowBucketCollisions(count: 65, bits: bucketBits)
        XCTAssertEqual(collidingLines.count, 65)
        guard collidingLines.count == 65 else { return }
        XCTAssertEqual(Set(collidingLines.map { xdiffBucket(for: $0, bits: bucketBits) }).count, 1)
        XCTAssertEqual(Set(collidingLines).count, collidingLines.count)

        let leftLines = ["head"] + Array(collidingLines.prefix(64)) + ["tail"]
        var rightLines = leftLines
        rightLines[33] = collidingLines[64]

        let rows = try LineDiff.compare(
            left: leftLines.joined(separator: "\n") + "\n",
            right: rightLines.joined(separator: "\n") + "\n"
        )

        assertValidAlignment(rows, leftLines: leftLines, rightLines: rightLines)
        let changes = rows.filter { $0.kind != .unchanged }
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, .modified)
        XCTAssertEqual(changes.first?.left?.text, leftLines[33])
        XCTAssertEqual(changes.first?.right?.text, rightLines[33])
    }

    private func assertValidAlignment(
        _ rows: [DiffRow],
        leftLines: [String],
        rightLines: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let alignedLeft = rows.compactMap(\.left)
        let alignedRight = rows.compactMap(\.right)

        XCTAssertEqual(alignedLeft.map(\.text), leftLines, file: file, line: line)
        XCTAssertEqual(alignedRight.map(\.text), rightLines, file: file, line: line)
        XCTAssertEqual(alignedLeft.map(\.number), leftLines.indices.map { $0 + 1 }, file: file, line: line)
        XCTAssertEqual(alignedRight.map(\.number), rightLines.indices.map { $0 + 1 }, file: file, line: line)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rows.count, max(leftLines.count, rightLines.count), file: file, line: line)
        XCTAssertLessThanOrEqual(rows.count, leftLines.count + rightLines.count, file: file, line: line)

        for row in rows {
            switch row.kind {
            case .unchanged:
                XCTAssertNotNil(row.left, file: file, line: line)
                XCTAssertNotNil(row.right, file: file, line: line)
                XCTAssertEqual(row.left?.text, row.right?.text, file: file, line: line)
            case .modified:
                XCTAssertNotNil(row.left, file: file, line: line)
                XCTAssertNotNil(row.right, file: file, line: line)
                XCTAssertNotEqual(row.left?.text, row.right?.text, file: file, line: line)
            case .removed:
                XCTAssertNotNil(row.left, file: file, line: line)
                XCTAssertNil(row.right, file: file, line: line)
            case .added:
                XCTAssertNil(row.left, file: file, line: line)
                XCTAssertNotNil(row.right, file: file, line: line)
            }
        }
    }

    private func makeLowBucketCollisions(count: Int, bits: Int) -> [String] {
        var lines: [String] = []
        var candidate = 0
        let targetBucket = xdiffBucket(for: "collision-candidate-0-common-suffix", bits: bits)

        while lines.count < count, candidate < 100_000 {
            let line = "collision-candidate-\(candidate)-common-suffix"
            if xdiffBucket(for: line, bits: bits) == targetBucket {
                lines.append(line)
            }
            candidate += 1
        }
        return lines
    }

    private func xdiffBucket(for line: String, bits: Int) -> UInt {
        var hash: UInt = 5_381
        for byte in line.utf8 {
            hash = (hash &+ (hash << 5)) ^ UInt(byte)
        }
        hash = (hash &+ (hash << 5)) ^ UInt(UInt8(ascii: "\n"))
        return (hash &+ (hash >> bits)) & ((1 << bits) - 1)
    }
}
