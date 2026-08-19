@testable import MacMergeCore
import XCTest

final class MovedEditedParityTests: XCTestCase {
    func testBundledWinMergeMovedScreenshotHasExactRowsAndDirectionalRanges() throws {
        // Bundled fixture Docs/Manual/English/screenshots/moved-01.png shows a gray
        // spacer opposite the yellow, empty right line 3. Compare_files.xml:242-266
        // identifies `a` and `c` as moved and explains that moved detection separates
        // the final differences.
        let result = try compare(
            left: ["a", "i", "b", "h", "c"],
            right: ["c", "i", "", "b", "p", "a"]
        )

        assertRows(
            result.rows,
            ids: [id(1, 1), id(2, 2), id(nil, 3), id(3, 4), id(4, 5), id(5, 6)],
            kinds: [.modified, .unchanged, .added, .unchanged, .modified, .modified],
            leftTexts: ["a", "i", nil, "b", "h", "c"],
            rightTexts: ["c", "i", "", "b", "p", "a"]
        )
        assertMovedLines(
            result.movedLines,
            leftToRight: [MovedLinePair(leftLine: 1, rightLine: 6), MovedLinePair(leftLine: 5, rightLine: 1)],
            rightToLeft: [MovedLinePair(leftLine: 5, rightLine: 1), MovedLinePair(leftLine: 1, rightLine: 6)]
        )
    }

    func testBundledWinMergeMovedScreenshotSwappedOrientationMirrorsMappings() throws {
        let result = try compare(
            left: ["c", "i", "", "b", "p", "a"],
            right: ["a", "i", "b", "h", "c"]
        )

        assertRows(
            result.rows,
            ids: [id(1, 1), id(2, 2), id(3, nil), id(4, 3), id(5, 4), id(6, 5)],
            kinds: [.modified, .unchanged, .removed, .unchanged, .modified, .modified],
            leftTexts: ["c", "i", "", "b", "p", "a"],
            rightTexts: ["a", "i", nil, "b", "h", "c"]
        )
        assertMovedLines(
            result.movedLines,
            leftToRight: [MovedLinePair(leftLine: 1, rightLine: 5), MovedLinePair(leftLine: 6, rightLine: 1)],
            rightToLeft: [MovedLinePair(leftLine: 6, rightLine: 1), MovedLinePair(leftLine: 1, rightLine: 5)]
        )
    }

    func testMovedAndEditedBlockMapsOnlyExactSubranges() throws {
        // WinMerge Src/MovedBlocks.cpp:105-118 groups altered equivalent lines, while
        // :130-178 and :248-296 extend a move only through equal groups. An edited
        // middle line therefore interrupts, rather than joins, exact moved ranges.
        let result = try compare(
            left: [
                "head", "moved opening", "old edited detail", "moved closing",
                "stable one", "stable two", "stable three", "tail",
            ],
            right: [
                "head", "stable one", "stable two", "stable three",
                "moved opening", "new edited detail", "moved closing", "tail",
            ]
        )

        assertRows(
            result.rows,
            ids: [
                id(1, 1), id(2, nil), id(3, nil), id(4, nil), id(5, 2), id(6, 3),
                id(7, 4), id(nil, 5), id(nil, 6), id(nil, 7), id(8, 8),
            ],
            kinds: [
                .unchanged, .removed, .removed, .removed, .unchanged, .unchanged,
                .unchanged, .added, .added, .added, .unchanged,
            ],
            leftTexts: [
                "head", "moved opening", "old edited detail", "moved closing",
                "stable one", "stable two", "stable three", nil, nil, nil, "tail",
            ],
            rightTexts: [
                "head", nil, nil, nil, "stable one", "stable two", "stable three",
                "moved opening", "new edited detail", "moved closing", "tail",
            ]
        )
        assertMovedLines(
            result.movedLines,
            leftToRight: [MovedLinePair(leftLine: 2, rightLine: 5), MovedLinePair(leftLine: 4, rightLine: 7)],
            rightToLeft: [MovedLinePair(leftLine: 2, rightLine: 5), MovedLinePair(leftLine: 4, rightLine: 7)]
        )
    }

    func testMovedRangeKeepsAdjacentDeleteAndInsertRowsSeparate() throws {
        // WinMerge Src/MovedBlocks.cpp:183-236 and :301-355 split prefixes and suffixes
        // around a moved range into ordinary diff chunks. These adjacent unequal lines
        // must remain delete/insert rows and must not enlarge either directional range.
        let result = try compare(
            left: [
                "head", "moved one", "moved two", "left deleted neighbor",
                "stable one", "stable two", "stable three", "tail",
            ],
            right: [
                "head", "stable one", "stable two", "stable three",
                "right inserted neighbor", "moved one", "moved two", "tail",
            ]
        )

        assertRows(
            result.rows,
            ids: [
                id(1, 1), id(2, nil), id(3, nil), id(4, nil), id(5, 2), id(6, 3),
                id(7, 4), id(nil, 5), id(nil, 6), id(nil, 7), id(8, 8),
            ],
            kinds: [
                .unchanged, .removed, .removed, .removed, .unchanged, .unchanged,
                .unchanged, .added, .added, .added, .unchanged,
            ],
            leftTexts: [
                "head", "moved one", "moved two", "left deleted neighbor",
                "stable one", "stable two", "stable three", nil, nil, nil, "tail",
            ],
            rightTexts: [
                "head", nil, nil, nil, "stable one", "stable two", "stable three",
                "right inserted neighbor", "moved one", "moved two", "tail",
            ]
        )
        assertMovedLines(
            result.movedLines,
            leftToRight: [MovedLinePair(leftLine: 2, rightLine: 6), MovedLinePair(leftLine: 3, rightLine: 7)],
            rightToLeft: [MovedLinePair(leftLine: 2, rightLine: 6), MovedLinePair(leftLine: 3, rightLine: 7)]
        )
    }

    private func compare(left: [String], right: [String]) throws -> LineDiffResult {
        try LineDiff.compareResult(
            left: left.joined(separator: "\n"),
            right: right.joined(separator: "\n"),
            options: LineDiffOptions(detectMovedBlocks: true)
        )
    }

    private func assertRows(
        _ rows: [DiffRow],
        ids: [DiffRow.ID],
        kinds: [DiffKind],
        leftTexts: [String?],
        rightTexts: [String?],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(rows.map(\.id), ids, file: file, line: line)
        XCTAssertEqual(rows.map(\.kind), kinds, file: file, line: line)
        XCTAssertEqual(rows.map(\.left?.text), leftTexts, file: file, line: line)
        XCTAssertEqual(rows.map(\.right?.text), rightTexts, file: file, line: line)
    }

    private func assertMovedLines(
        _ movedLines: MovedLines,
        leftToRight: [MovedLinePair],
        rightToLeft: [MovedLinePair],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualLeftToRight = (0..<movedLines.leftToRightCount).map {
            movedLines.leftToRightPair(at: $0)
        }
        let actualRightToLeft = (0..<movedLines.rightToLeftCount).map {
            movedLines.rightToLeftPair(at: $0)
        }
        XCTAssertEqual(actualLeftToRight, leftToRight, file: file, line: line)
        XCTAssertEqual(actualRightToLeft, rightToLeft, file: file, line: line)
    }

    private func id(_ left: Int?, _ right: Int?) -> DiffRow.ID {
        DiffRow.ID(leftNumber: left, rightNumber: right)
    }
}
