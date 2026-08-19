import MacMergeCore
import XCTest

final class AllAlgorithmWinMergeParityTests: XCTestCase {
    private typealias ExpectedRow = (left: Int?, right: Int?, kind: DiffKind)

    private struct AlgorithmGolden {
        let algorithm: DiffAlgorithm
        let rows: [ExpectedRow]
    }

    // No executable Windows CDiffWrapper output exists for these inputs, so this
    // suite claims bundled-native route parity only. Capture: direct C harness over
    // xdl_diff_modified from WinMerge commit 7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301,
    // Externals/xdiff tree bf7ade8ccf4199ab85649c5aac4474b14e44f55f. Flags:
    // 0, XDF_NEED_MINIMAL, XDF_PATIENCE_DIFF, XDF_HISTOGRAM_DIFF, XDF_NONE_DIFF.
    // Raw 0-based hunks, in that order:
    // default/minimal [(0,2,0,4),(4,1,6,1),(7,1,9,0),(9,2,10,1)]
    // patience [(0,2,0,0),(3,3,1,4),(8,0,7,2),(9,2,10,1)]
    // histogram [(0,2,0,0),(3,3,1,4),(8,1,7,0),(10,1,8,3)]
    // none [(0,5,0,5),(6,5,6,5)]
    func testRepeatedLineCorpusMatchesBundledWinMergeXDiff() throws {
        let left = ["A", "B", "E", "B", "F", "B", "B", "C", "F", "B", "E", "E"]
            .joined(separator: "\n")
        let right = ["E", "D", "D", "D", "E", "B", "C", "B", "B", "F", "D", "E"]
            .joined(separator: "\n")
        let greedy = [
            row(1, 1, .modified), row(2, 2, .modified), row(nil, 3, .added),
            row(nil, 4, .added), row(3, 5, .unchanged), row(4, 6, .unchanged),
            row(5, 7, .modified), row(6, 8, .unchanged), row(7, 9, .unchanged),
            row(8, nil, .removed), row(9, 10, .unchanged), row(10, 11, .modified),
            row(11, nil, .removed), row(12, 12, .unchanged)
        ]
        let goldens = [
            AlgorithmGolden(algorithm: .default, rows: greedy),
            AlgorithmGolden(algorithm: .minimal, rows: greedy),
            AlgorithmGolden(
                algorithm: .patience,
                rows: [
                    row(1, nil, .removed), row(2, nil, .removed), row(3, 1, .unchanged),
                    row(4, 2, .modified), row(5, 3, .modified), row(6, 4, .modified),
                    row(nil, 5, .added), row(7, 6, .unchanged), row(8, 7, .unchanged),
                    row(nil, 8, .added), row(nil, 9, .added), row(9, 10, .unchanged),
                    row(10, 11, .modified), row(11, nil, .removed), row(12, 12, .unchanged)
                ]),
            AlgorithmGolden(
                algorithm: .histogram,
                rows: [
                    row(1, nil, .removed), row(2, nil, .removed), row(3, 1, .unchanged),
                    row(4, 2, .modified), row(5, 3, .modified), row(6, 4, .modified),
                    row(nil, 5, .added), row(7, 6, .unchanged), row(8, 7, .unchanged),
                    row(9, nil, .removed), row(10, 8, .unchanged), row(11, 9, .modified),
                    row(nil, 10, .added), row(nil, 11, .added), row(12, 12, .unchanged)
                ]),
            AlgorithmGolden(
                algorithm: .none,
                rows: [
                    row(1, 1, .modified), row(2, 2, .modified), row(3, 3, .modified),
                    row(4, 4, .modified), row(5, 5, .modified), row(6, 6, .unchanged),
                    row(7, 7, .modified), row(8, 8, .modified), row(9, 9, .modified),
                    row(10, 10, .modified), row(11, 11, .modified), row(12, 12, .unchanged)
                ])
        ]

        try assertRows(left: left, right: right, goldens: goldens)
    }

    // Same direct bundled-native capture and source pin as above. Raw 0-based hunks:
    // default/minimal/patience/histogram [(1,3,1,0),(7,0,4,3)]
    // none [(1,6,1,6)]
    func testAmbiguousAlignmentCorpusMatchesBundledWinMergeXDiff() throws {
        let left = [
            "head", "duplicate", "unique moved seed", "duplicate",
            "stable one", "stable two", "stable three", "tail"
        ].joined(separator: "\n")
        let right = [
            "head", "stable one", "stable two", "stable three",
            "duplicate", "unique moved seed", "duplicate", "tail"
        ].joined(separator: "\n")
        let realigned = [
            row(1, 1, .unchanged), row(2, nil, .removed), row(3, nil, .removed),
            row(4, nil, .removed), row(5, 2, .unchanged), row(6, 3, .unchanged),
            row(7, 4, .unchanged), row(nil, 5, .added), row(nil, 6, .added),
            row(nil, 7, .added), row(8, 8, .unchanged)
        ]
        let goldens = [
            AlgorithmGolden(algorithm: .default, rows: realigned),
            AlgorithmGolden(algorithm: .minimal, rows: realigned),
            AlgorithmGolden(algorithm: .patience, rows: realigned),
            AlgorithmGolden(algorithm: .histogram, rows: realigned),
            AlgorithmGolden(
                algorithm: .none,
                rows: [
                    row(1, 1, .unchanged), row(2, 2, .modified), row(3, 3, .modified),
                    row(4, 4, .modified), row(5, 5, .modified), row(6, 6, .modified),
                    row(7, 7, .modified), row(8, 8, .unchanged)
                ])
        ]

        try assertRows(left: left, right: right, goldens: goldens)
    }

    // Git t/t4071-diff-minimal.sh was checked, but its 2025 cleanup optimization is absent
    // from this pinned WinMerge xdiff and does not distinguish default from minimal here.
    // This deterministic corpus instead crosses xdiffi.c's 256-edit heuristic: default
    // Myers stops early while XDF_NEED_MINIMAL completes the search. Same direct capture
    // and source pin as above; no Windows CDiffWrapper evidence. left = L000...L329;
    // right uses 22-line blocks in
    // order [12,13,14,11,9,7,10,4,5,8,2,0,1,6,3]. Raw 0-based hunks:
    // default [(0,88,0,154),(132,44,198,0),(198,132,220,110)]
    // minimal/patience/histogram [(0,264,0,0),(330,0,66,264)]
    // none [(0,330,0,330)]
    func testMinimalHeuristicCorpusMatchesBundledWinMergeXDiff() throws {
        let leftLines = (0..<330).map(numberedLine)
        let blockOrder = [12, 13, 14, 11, 9, 7, 10, 4, 5, 8, 2, 0, 1, 6, 3]
        let rightLines = blockOrder.flatMap { block in
            (block * 22..<(block + 1) * 22).map(numberedLine)
        }
        let defaultRows = rows(
            leftCount: 330,
            rightCount: 330,
            hunks: [(0, 88, 0, 154), (132, 44, 198, 0), (198, 132, 220, 110)]
        )
        let minimalRows = rows(
            leftCount: 330,
            rightCount: 330,
            hunks: [(0, 264, 0, 0), (330, 0, 66, 264)]
        )
        let goldens = [
            AlgorithmGolden(algorithm: .default, rows: defaultRows),
            AlgorithmGolden(algorithm: .minimal, rows: minimalRows),
            AlgorithmGolden(algorithm: .patience, rows: minimalRows),
            AlgorithmGolden(algorithm: .histogram, rows: minimalRows),
            AlgorithmGolden(
                algorithm: .none,
                rows: rows(leftCount: 330, rightCount: 330, hunks: [(0, 330, 0, 330)])
            )
        ]

        XCTAssertNotEqual(
            defaultRows.map { DiffRow.ID(leftNumber: $0.left, rightNumber: $0.right) },
            minimalRows.map { DiffRow.ID(leftNumber: $0.left, rightNumber: $0.right) }
        )
        try assertRows(
            left: leftLines.joined(separator: "\n") + "\n",
            right: rightLines.joined(separator: "\n") + "\n",
            goldens: goldens
        )
    }

    private func assertRows(
        left: String,
        right: String,
        goldens: [AlgorithmGolden],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            goldens.map(\.algorithm),
            [.default, .minimal, .patience, .histogram, .none],
            file: file,
            line: line
        )
        for golden in goldens {
            let rows = try LineDiff.compare(
                left: left,
                right: right,
                options: LineDiffOptions(algorithm: golden.algorithm)
            )
            let context = "Algorithm: \(golden.algorithm)"
            XCTAssertEqual(
                rows.map(\.id),
                golden.rows.map { DiffRow.ID(leftNumber: $0.left, rightNumber: $0.right) },
                context,
                file: file,
                line: line
            )
            XCTAssertEqual(
                rows.map(\.kind),
                golden.rows.map(\.kind),
                context,
                file: file,
                line: line
            )
        }
    }

    private func row(_ left: Int?, _ right: Int?, _ kind: DiffKind) -> ExpectedRow {
        (left, right, kind)
    }

    private func numberedLine(_ number: Int) -> String {
        String(format: "L%06d", number)
    }

    private func rows(
        leftCount: Int,
        rightCount: Int,
        hunks: [(leftStart: Int, leftCount: Int, rightStart: Int, rightCount: Int)]
    ) -> [ExpectedRow] {
        var rows: [ExpectedRow] = []
        var leftIndex = 0
        var rightIndex = 0
        for hunk in hunks {
            while leftIndex < hunk.leftStart {
                rows.append(row(leftIndex + 1, rightIndex + 1, .unchanged))
                leftIndex += 1
                rightIndex += 1
            }
            while leftIndex < hunk.leftStart + hunk.leftCount || rightIndex < hunk.rightStart + hunk.rightCount {
                if leftIndex < hunk.leftStart + hunk.leftCount,
                    rightIndex < hunk.rightStart + hunk.rightCount
                {
                    rows.append(row(leftIndex + 1, rightIndex + 1, .modified))
                    leftIndex += 1
                    rightIndex += 1
                } else if leftIndex < hunk.leftStart + hunk.leftCount {
                    rows.append(row(leftIndex + 1, nil, .removed))
                    leftIndex += 1
                } else {
                    rows.append(row(nil, rightIndex + 1, .added))
                    rightIndex += 1
                }
            }
        }
        while leftIndex < leftCount {
            rows.append(row(leftIndex + 1, rightIndex + 1, .unchanged))
            leftIndex += 1
            rightIndex += 1
        }
        XCTAssertEqual(rightIndex, rightCount)
        return rows
    }
}
