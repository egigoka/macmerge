@testable import MacMergeCore
import XCTest

final class IndentHeuristicParityTests: XCTestCase {
    // Reconstructed from Git's t4061-diff-indent.sh fixtures for WinMerge's vendored xdiff engine.
    func testRepeatedBlankBlockUsesWinMergeIndentAlignment() throws {
        let left = ["1", "2", "a", "", "b", "3", "4"].joined(separator: "\n")
        let right = ["1", "2", "a", "", "b", "a", "", "b", "3", "4"]
            .joined(separator: "\n")

        let withoutHeuristic = try LineDiff.compare(
            left: left,
            right: right,
            options: LineDiffOptions(indentHeuristic: false)
        )
        let withHeuristic = try LineDiff.compare(
            left: left,
            right: right,
            options: LineDiffOptions(indentHeuristic: true)
        )

        assertRows(withoutHeuristic, [
            (1, 1, .unchanged),
            (2, 2, .unchanged),
            (3, 3, .unchanged),
            (4, 4, .unchanged),
            (5, 5, .unchanged),
            (nil, 6, .added),
            (nil, 7, .added),
            (nil, 8, .added),
            (6, 9, .unchanged),
            (7, 10, .unchanged),
        ])
        assertRows(withHeuristic, [
            (1, 1, .unchanged),
            (2, 2, .unchanged),
            (3, 3, .unchanged),
            (4, 4, .unchanged),
            (nil, 5, .added),
            (nil, 6, .added),
            (nil, 7, .added),
            (5, 8, .unchanged),
            (6, 9, .unchanged),
            (7, 10, .unchanged),
        ])
    }

    func testRepeatedFunctionHeaderUsesWinMergeIndentAlignment() throws {
        let left = [
            "1", "2", "/* function */", "foo() {", "    foo", "}", "", "3", "4",
        ].joined(separator: "\n")
        let right = [
            "1", "2", "/* function */", "bar() {", "    foo", "}", "",
            "/* function */", "foo() {", "    foo", "}", "", "3", "4",
        ].joined(separator: "\n")

        let withoutHeuristic = try LineDiff.compare(
            left: left,
            right: right,
            options: LineDiffOptions(indentHeuristic: false)
        )
        let withHeuristic = try LineDiff.compare(
            left: left,
            right: right,
            options: LineDiffOptions(indentHeuristic: true)
        )

        assertRows(withoutHeuristic, [
            (1, 1, .unchanged),
            (2, 2, .unchanged),
            (3, 3, .unchanged),
            (nil, 4, .added),
            (nil, 5, .added),
            (nil, 6, .added),
            (nil, 7, .added),
            (nil, 8, .added),
            (4, 9, .unchanged),
            (5, 10, .unchanged),
            (6, 11, .unchanged),
            (7, 12, .unchanged),
            (8, 13, .unchanged),
            (9, 14, .unchanged),
        ])
        assertRows(withHeuristic, [
            (1, 1, .unchanged),
            (2, 2, .unchanged),
            (nil, 3, .added),
            (nil, 4, .added),
            (nil, 5, .added),
            (nil, 6, .added),
            (nil, 7, .added),
            (3, 8, .unchanged),
            (4, 9, .unchanged),
            (5, 10, .unchanged),
            (6, 11, .unchanged),
            (7, 12, .unchanged),
            (8, 13, .unchanged),
            (9, 14, .unchanged),
        ])
    }

    func testIndentAlignmentIsStableAcrossWinMergeXDiffAlgorithms() throws {
        let left = ["1", "2", "a", "", "b", "3", "4"].joined(separator: "\n")
        let right = ["1", "2", "a", "", "b", "a", "", "b", "3", "4"]
            .joined(separator: "\n")
        let expected: [(Int?, Int?, DiffKind)] = [
            (1, 1, .unchanged),
            (2, 2, .unchanged),
            (3, 3, .unchanged),
            (4, 4, .unchanged),
            (nil, 5, .added),
            (nil, 6, .added),
            (nil, 7, .added),
            (5, 8, .unchanged),
            (6, 9, .unchanged),
            (7, 10, .unchanged),
        ]

        for algorithm in [DiffAlgorithm.default, .patience, .histogram] {
            let rows = try LineDiff.compare(
                left: left,
                right: right,
                options: LineDiffOptions(algorithm: algorithm, indentHeuristic: true)
            )

            assertRows(rows, expected, message: "Algorithm: \(algorithm)")
        }
    }

    private func assertRows(
        _ rows: [DiffRow],
        _ expected: [(Int?, Int?, DiffKind)],
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            rows.map(\.id),
            expected.map { DiffRow.ID(leftNumber: $0.0, rightNumber: $0.1) },
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(rows.map(\.kind), expected.map { $0.2 }, message, file: file, line: line)
    }
}
