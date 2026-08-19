import XCTest

@testable import MacMergeCore

final class MovedEditedSymmetryTests: XCTestCase {
    func testMovedAndEditedBlockReportsOnlyExactPairsInBothDirections() throws {
        let fixture = movedAndEditedFixture
        let result = try compare(fixture.left, fixture.right)
        let expected = [
            MovedLinePair(leftLine: 2, rightLine: 5),
            MovedLinePair(leftLine: 4, rightLine: 7)
        ]

        assertMovedPairs(result.movedLines, leftToRight: expected, rightToLeft: expected)
    }

    func testSwappingMovedAndEditedInputsMirrorsRowsAndDirectionalMappings() throws {
        let fixture = movedAndEditedFixture
        let original = try compare(fixture.left, fixture.right)
        let swapped = try compare(fixture.right, fixture.left)

        XCTAssertEqual(swapped.rows.count, original.rows.count)
        for (row, swappedRow) in zip(original.rows, swapped.rows) {
            XCTAssertEqual(swappedRow.left, row.right)
            XCTAssertEqual(swappedRow.right, row.left)
            XCTAssertEqual(swappedRow.kind, mirrored(row.kind))
        }

        XCTAssertEqual(
            leftToRightPairs(swapped.movedLines),
            rightToLeftPairs(original.movedLines).map(swappingPair)
        )
        XCTAssertEqual(
            rightToLeftPairs(swapped.movedLines),
            leftToRightPairs(original.movedLines).map(swappingPair)
        )
    }

    func testSwappingAmbiguousMovedInputsMirrorsUnequalDirectionalMappings() throws {
        let fixture = ambiguousMovedFixture
        let original = try compare(fixture.left, fixture.right)
        let swapped = try compare(fixture.right, fixture.left)
        let originalLeftToRight = leftToRightPairs(original.movedLines)
        let originalRightToLeft = rightToLeftPairs(original.movedLines)

        XCTAssertEqual(
            originalLeftToRight,
            [
                MovedLinePair(leftLine: 2, rightLine: 8),
                MovedLinePair(leftLine: 3, rightLine: 9),
                MovedLinePair(leftLine: 4, rightLine: 10),
                MovedLinePair(leftLine: 5, rightLine: 7),
                MovedLinePair(leftLine: 6, rightLine: 8)
            ]
        )
        XCTAssertEqual(
            originalRightToLeft,
            [
                MovedLinePair(leftLine: 4, rightLine: 6),
                MovedLinePair(leftLine: 5, rightLine: 7),
                MovedLinePair(leftLine: 6, rightLine: 8),
                MovedLinePair(leftLine: 3, rightLine: 9),
                MovedLinePair(leftLine: 4, rightLine: 10)
            ]
        )
        XCTAssertNotEqual(originalLeftToRight, originalRightToLeft)
        XCTAssertEqual(
            leftToRightPairs(swapped.movedLines),
            originalRightToLeft.map(swappingPair)
        )
        XCTAssertEqual(
            rightToLeftPairs(swapped.movedLines),
            originalLeftToRight.map(swappingPair)
        )
    }

    func testEditedLineInsideMovedNeighborhoodIsNotFalselyMapped() throws {
        let fixture = movedAndEditedFixture
        let original = try compare(fixture.left, fixture.right)
        let swapped = try compare(fixture.right, fixture.left)

        XCTAssertNil(original.movedLines.rightLine(forLeftLine: 3))
        XCTAssertNil(original.movedLines.leftLine(forRightLine: 6))
        XCTAssertNil(swapped.movedLines.rightLine(forLeftLine: 6))
        XCTAssertNil(swapped.movedLines.leftLine(forRightLine: 3))
    }

    func testAdjacentInsertAndDeleteStayOutsideMovedPairs() throws {
        let left = [
            "adjacent-root-4101",
            "adjacent-left-delete-4102",
            "adjacent-move-alpha-4103",
            "adjacent-move-omega-4104",
            "adjacent-stable-one-4105",
            "adjacent-stable-two-4106",
            "adjacent-stable-three-4107",
            "adjacent-tail-4108"
        ]
        let right = [
            "adjacent-root-4101",
            "adjacent-stable-one-4105",
            "adjacent-stable-two-4106",
            "adjacent-stable-three-4107",
            "adjacent-move-alpha-4103",
            "adjacent-move-omega-4104",
            "adjacent-right-insert-4109",
            "adjacent-tail-4108"
        ]
        let result = try compare(left, right)
        let expected = [
            MovedLinePair(leftLine: 3, rightLine: 5),
            MovedLinePair(leftLine: 4, rightLine: 6)
        ]

        assertMovedPairs(result.movedLines, leftToRight: expected, rightToLeft: expected)
        XCTAssertNil(result.movedLines.rightLine(forLeftLine: 2))
        XCTAssertNil(result.movedLines.leftLine(forRightLine: 7))

        let deleted = try XCTUnwrap(result.rows.first { $0.left?.number == 2 })
        XCTAssertEqual(deleted.kind, .removed)
        XCTAssertNil(deleted.right)
        let inserted = try XCTUnwrap(result.rows.first { $0.right?.number == 7 })
        XCTAssertEqual(inserted.kind, .added)
        XCTAssertNil(inserted.left)
    }

    func testMovedPairsRespectOptionTransformsInBothOrientations() throws {
        let fixtures: [(String, String, String, LineDiffOptions)] = [
            (
                "case",
                "OPTION-CASE-MOVED-5201",
                "option-case-moved-5201",
                LineDiffOptions(ignoreCase: true, detectMovedBlocks: true)
            ),
            (
                "numbers",
                "option-number-moved-5202-build-100",
                "option-number-moved-5202-build-900",
                LineDiffOptions(ignoreNumbers: true, detectMovedBlocks: true)
            ),
            (
                "whitespace",
                "option whitespace   moved 5203",
                "option whitespace moved 5203",
                LineDiffOptions(
                    whitespace: .ignoreChanges,
                    detectMovedBlocks: true
                )
            ),
            (
                "comments",
                "option-comment-moved-5204 /* left detail */",
                "option-comment-moved-5204 /* right detail */",
                LineDiffOptions(
                    ignoreComments: true,
                    detectMovedBlocks: true,
                    commentSyntax: .cFamily
                )
            ),
            (
                "line filter",
                "generated-side-left-moved-5205",
                "generated-side-right-moved-5205",
                LineDiffOptions(
                    detectMovedBlocks: true,
                    lineFilters: [LineFilterRule(pattern: "^generated-side-")]
                )
            ),
            (
                "substitution",
                "option-left-token-moved-5206",
                "option-right-token-moved-5206",
                LineDiffOptions(
                    detectMovedBlocks: true,
                    substitutions: [
                        SubstitutionRule(pattern: "(?:left|right)-token", replacement: "same-token")
                    ]
                )
            )
        ]

        for (name, leftMoved, rightMoved, options) in fixtures {
            let left = optionFixture(moved: leftMoved)
            let right = optionFixture(moved: rightMoved, swapped: true)
            let original = try LineDiff.compareResult(
                left: left.joined(separator: "\n"),
                right: right.joined(separator: "\n"),
                options: options
            )
            let swapped = try LineDiff.compareResult(
                left: right.joined(separator: "\n"),
                right: left.joined(separator: "\n"),
                options: options
            )

            assertMovedPairs(
                original.movedLines,
                leftToRight: [MovedLinePair(leftLine: 2, rightLine: 5)],
                rightToLeft: [MovedLinePair(leftLine: 2, rightLine: 5)],
                name
            )
            assertMovedPairs(
                swapped.movedLines,
                leftToRight: [MovedLinePair(leftLine: 5, rightLine: 2)],
                rightToLeft: [MovedLinePair(leftLine: 5, rightLine: 2)],
                name
            )
        }
    }

    private var movedAndEditedFixture: (left: [String], right: [String]) {
        (
            left: [
                "symmetry-root-3101",
                "symmetry-move-opening-3102",
                "symmetry-left-edited-detail-3103",
                "symmetry-move-closing-3104",
                "symmetry-stable-one-3105",
                "symmetry-stable-two-3106",
                "symmetry-stable-three-3107",
                "symmetry-tail-3108"
            ],
            right: [
                "symmetry-root-3101",
                "symmetry-stable-one-3105",
                "symmetry-stable-two-3106",
                "symmetry-stable-three-3107",
                "symmetry-move-opening-3102",
                "symmetry-right-edited-detail-3109",
                "symmetry-move-closing-3104",
                "symmetry-tail-3108"
            ]
        )
    }

    private var ambiguousMovedFixture: (left: [String], right: [String]) {
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
        return (
            left: ["symmetry-ambiguous-root-3190"] + movedLeft + stable + ["symmetry-ambiguous-tail-3198"],
            right: ["symmetry-ambiguous-root-3190"] + stable + movedRight + ["symmetry-ambiguous-tail-3198"]
        )
    }

    private func optionFixture(moved: String, swapped: Bool = false) -> [String] {
        let stable = [
            "option-stable-one-5291",
            "option-stable-two-5292",
            "option-stable-three-5293"
        ]
        if swapped {
            return ["option-root-5290"] + stable + [moved, "option-tail-5299"]
        }
        return ["option-root-5290", moved] + stable + ["option-tail-5299"]
    }

    private func compare(_ left: [String], _ right: [String]) throws -> LineDiffResult {
        try LineDiff.compareResult(
            left: left.joined(separator: "\n"),
            right: right.joined(separator: "\n"),
            options: LineDiffOptions(detectMovedBlocks: true)
        )
    }

    private func assertMovedPairs(
        _ movedLines: MovedLines,
        leftToRight: [MovedLinePair],
        rightToLeft: [MovedLinePair],
        _ context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(leftToRightPairs(movedLines), leftToRight, context, file: file, line: line)
        XCTAssertEqual(rightToLeftPairs(movedLines), rightToLeft, context, file: file, line: line)
    }

    private func leftToRightPairs(_ movedLines: MovedLines) -> [MovedLinePair] {
        (0..<movedLines.leftToRightCount).map { movedLines.leftToRightPair(at: $0) }
    }

    private func rightToLeftPairs(_ movedLines: MovedLines) -> [MovedLinePair] {
        (0..<movedLines.rightToLeftCount).map { movedLines.rightToLeftPair(at: $0) }
    }

    private func swappingPair(_ pair: MovedLinePair) -> MovedLinePair {
        MovedLinePair(leftLine: pair.rightLine, rightLine: pair.leftLine)
    }

    private func mirrored(_ kind: DiffKind) -> DiffKind {
        switch kind {
        case .unchanged: .unchanged
        case .modified: .modified
        case .removed: .added
        case .added: .removed
        }
    }
}
