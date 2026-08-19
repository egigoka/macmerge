import Foundation
import XCTest

@testable import MacMergeCore

final class DifferenceDetailTests: XCTestCase {
    func testLargeEmptyHighlightRangesProduceNoExcessRangesOrFragments() {
        let text = String(repeating: "abcdef", count: 100_000)
        let side = DifferenceDetailSide(
            line: DiffLine(number: 1, text: text),
            highlightRanges: []
        )

        XCTAssertEqual(side.highlightRanges, [])
        XCTAssertEqual(
            side.fragments,
            [
                DifferenceDetailTextFragment(
                    text: text,
                    utf16Range: NSRange(location: 0, length: text.utf16.count),
                    isHighlighted: false
                )
            ]
        )
    }

    func testAbsentStateForMissingOrInvalidSelection() {
        let row = makeRow(left: "same", right: "same", kind: .unchanged)
        let otherRow = DiffRow(
            left: DiffLine(number: 2, text: "other"),
            right: DiffLine(number: 2, text: "other"),
            kind: .unchanged
        )

        for detail in [
            DifferenceDetail(row: nil),
            DifferenceDetail(rows: [row], selectedRowIndex: nil),
            DifferenceDetail(rows: [row], selectedRowIndex: -1),
            DifferenceDetail(rows: [row], selectedRowIndex: 1),
            DifferenceDetail(rows: [row], selectedRowIndex: Int.min),
            DifferenceDetail(rows: [row], selectedRowIndex: Int.max),
            DifferenceDetail(
                rows: [row],
                selectedRowIndex: nil,
                selectedRowID: row.id
            ),
            DifferenceDetail(
                rows: [row],
                selectedRowIndex: Int.max,
                selectedRowID: row.id
            ),
            DifferenceDetail(
                rows: [row, otherRow],
                selectedRowIndex: 0,
                selectedRowID: otherRow.id
            )
        ] {
            XCTAssertEqual(detail.state, .absent)
            XCTAssertNil(detail.source)
            XCTAssertNil(detail.left)
            XCTAssertNil(detail.right)
            XCTAssertNil(detail.leftMovedLinePair)
            XCTAssertNil(detail.rightMovedLinePair)
        }
    }

    func testUnchangedStatePreservesBothUnhighlightedSides() throws {
        let row = makeRow(left: "same", right: "same", kind: .unchanged)
        let detail = DifferenceDetail(row: row, rowIndex: 7)

        XCTAssertEqual(detail.state, .noDetail(.unchanged))
        XCTAssertEqual(detail.source, DifferenceDetailSource(rowIndex: 7, row: row))
        XCTAssertEqual(try XCTUnwrap(detail.left).text, "same")
        XCTAssertEqual(try XCTUnwrap(detail.right).text, "same")
        XCTAssertTrue(try XCTUnwrap(detail.left).highlightRanges.isEmpty)
        XCTAssertTrue(try XCTUnwrap(detail.right).highlightRanges.isEmpty)
    }

    func testUnpairedStatesPreserveOnlyPresentSide() throws {
        let removed = DifferenceDetail(row: makeRow(left: "old", right: nil, kind: .removed))
        XCTAssertEqual(removed.state, .noDetail(.unpaired))
        XCTAssertEqual(try XCTUnwrap(removed.left).text, "old")
        XCTAssertNil(removed.right)

        let added = DifferenceDetail(row: makeRow(left: nil, right: "new", kind: .added))
        XCTAssertEqual(added.state, .noDetail(.unpaired))
        XCTAssertNil(added.left)
        XCTAssertEqual(try XCTUnwrap(added.right).text, "new")

        let incompleteModified = DifferenceDetail(
            row: makeRow(left: "old", right: nil, kind: .modified)
        )
        XCTAssertEqual(incompleteModified.state, .noDetail(.unpaired))
        XCTAssertEqual(try XCTUnwrap(incompleteModified.left).text, "old")
        XCTAssertNil(incompleteModified.right)
    }

    func testModifiedStateHighlightsExactReplacement() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "abc", right: "axc", kind: .modified)
        )

        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(try XCTUnwrap(detail.left).highlightRanges, [NSRange(location: 1, length: 1)])
        XCTAssertEqual(try XCTUnwrap(detail.right).highlightRanges, [NSRange(location: 1, length: 1)])
        XCTAssertEqual(try XCTUnwrap(detail.left).fragments.map(\.text).joined(), "abc")
        XCTAssertEqual(try XCTUnwrap(detail.right).fragments.map(\.text).joined(), "axc")
    }

    func testModifiedEqualTextReportsNoIntralineDifference() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "identical", right: "identical", kind: .modified)
        )

        XCTAssertEqual(detail.state, .noDetail(.noIntralineDifference))
        XCTAssertTrue(try XCTUnwrap(detail.left).highlightRanges.isEmpty)
        XCTAssertTrue(try XCTUnwrap(detail.right).highlightRanges.isEmpty)
    }

    func testFragmentsReconstructTextAndRetainUTF16Ranges() {
        let side = DifferenceDetailSide(
            line: DiffLine(number: 1, text: "abcdefghij"),
            highlightRanges: [NSRange(location: 6, length: 2), NSRange(location: 1, length: 3)]
        )

        XCTAssertEqual(side.fragments.map(\.text).joined(), side.text)
        XCTAssertEqual(
            side.fragments,
            [
                DifferenceDetailTextFragment(
                    text: "a",
                    utf16Range: NSRange(location: 0, length: 1),
                    isHighlighted: false
                ),
                DifferenceDetailTextFragment(
                    text: "bcd",
                    utf16Range: NSRange(location: 1, length: 3),
                    isHighlighted: true
                ),
                DifferenceDetailTextFragment(
                    text: "ef",
                    utf16Range: NSRange(location: 4, length: 2),
                    isHighlighted: false
                ),
                DifferenceDetailTextFragment(
                    text: "gh",
                    utf16Range: NSRange(location: 6, length: 2),
                    isHighlighted: true
                ),
                DifferenceDetailTextFragment(
                    text: "ij",
                    utf16Range: NSRange(location: 8, length: 2),
                    isHighlighted: false
                )
            ]
        )
    }

    func testUTF16RangeExpandsToWholeGrapheme() throws {
        let grapheme = "👨‍👩‍👧‍👦"
        let text = "A\(grapheme)B"
        let graphemeRange = (text as NSString).range(of: grapheme)
        let side = DifferenceDetailSide(
            line: DiffLine(number: 1, text: text),
            highlightRanges: [NSRange(location: graphemeRange.location + 1, length: 1)]
        )

        XCTAssertEqual(side.highlightRanges, [graphemeRange])
        let highlighted = try XCTUnwrap(side.fragments.first(where: \.isHighlighted))
        XCTAssertEqual(highlighted.text, grapheme)
        XCTAssertEqual(side.fragments.map(\.text).joined(), text)
    }

    func testOverlappingAndAdjacentRangesMerge() {
        let side = DifferenceDetailSide(
            line: DiffLine(number: 1, text: "abcdefghij"),
            highlightRanges: [
                NSRange(location: 7, length: 2),
                NSRange(location: 2, length: 3),
                NSRange(location: 4, length: 3)
            ]
        )

        XCTAssertEqual(side.highlightRanges, [NSRange(location: 2, length: 7)])
        XCTAssertEqual(side.fragments.filter(\.isHighlighted).map(\.text), ["cdefghi"])
        XCTAssertEqual(side.fragments.map(\.text).joined(), side.text)
    }

    func testInvalidRangesProduceNoHighlights() {
        let text = "safe"
        let side = DifferenceDetailSide(
            line: DiffLine(number: 1, text: text),
            highlightRanges: [
                NSRange(location: -1, length: 1),
                NSRange(location: 0, length: -1),
                NSRange(location: NSNotFound, length: 0),
                NSRange(location: 1, length: Int.max),
                NSRange(location: 5, length: 0),
                NSRange(location: 3, length: 2)
            ]
        )

        XCTAssertTrue(side.highlightRanges.isEmpty)
        XCTAssertEqual(
            side.fragments,
            [
                DifferenceDetailTextFragment(
                    text: text,
                    utf16Range: NSRange(location: 0, length: 4),
                    isHighlighted: false
                )
            ]
        )
        XCTAssertFalse(side.fragments.contains(where: \.isHighlighted))
    }

    func testMalformedRangesCannotIntersectOrMergeWithValidRange() {
        let side = DifferenceDetailSide(
            line: DiffLine(number: 1, text: "safe"),
            highlightRanges: [
                NSRange(location: -1, length: 3),
                NSRange(location: 2, length: -1),
                NSRange(location: 1, length: Int.max),
                NSRange(location: Int.max, length: 1),
                NSRange(location: 1, length: 2)
            ]
        )

        XCTAssertEqual(side.highlightRanges, [NSRange(location: 1, length: 2)])
        XCTAssertEqual(side.fragments.map(\.text), ["s", "af", "e"])
        XCTAssertEqual(side.fragments.map(\.isHighlighted), [false, true, false])
        XCTAssertEqual(side.fragments.map(\.text).joined(), side.text)
    }

    func testDeletionCreatesZeroLengthAnchorOnRight() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "abc", right: "ac", kind: .modified)
        )
        let left = try XCTUnwrap(detail.left)
        let right = try XCTUnwrap(detail.right)

        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(left.highlightRanges, [NSRange(location: 1, length: 1)])
        XCTAssertEqual(right.highlightRanges, [NSRange(location: 1, length: 0)])
        XCTAssertEqual(right.fragments.filter(\.isHighlighted).map(\.text), [""])
        XCTAssertEqual(right.fragments.map(\.text).joined(), right.text)
    }

    func testInsertionCreatesZeroLengthAnchorOnLeft() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "ac", right: "abc", kind: .modified)
        )
        let left = try XCTUnwrap(detail.left)
        let right = try XCTUnwrap(detail.right)

        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(left.highlightRanges, [NSRange(location: 1, length: 0)])
        XCTAssertEqual(right.highlightRanges, [NSRange(location: 1, length: 1)])
        XCTAssertEqual(left.fragments.filter(\.isHighlighted).map(\.text), [""])
        XCTAssertEqual(left.fragments.map(\.text).joined(), left.text)
    }

    func testCanonicalComposedAndDecomposedCodeUnitsExpandToWholeGrapheme() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "xéy", right: "xe\u{301}y", kind: .modified)
        )
        let left = try XCTUnwrap(detail.left)
        let right = try XCTUnwrap(detail.right)

        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(left.highlightRanges, [NSRange(location: 1, length: 1)])
        XCTAssertEqual(right.highlightRanges, [NSRange(location: 1, length: 2)])
        XCTAssertEqual(left.fragments.filter(\.isHighlighted).map(\.text), ["é"])
        XCTAssertEqual(right.fragments.filter(\.isHighlighted).map(\.text), ["e\u{301}"])
        XCTAssertEqual(Array(left.text.utf8), Array("xéy".utf8))
        XCTAssertEqual(Array(right.text.utf8), Array("xe\u{301}y".utf8))
        XCTAssertEqual(left.fragments.map(\.text).joined(), left.text)
        XCTAssertEqual(right.fragments.map(\.text).joined(), right.text)
    }

    func testEqualCodeUnitsFromDifferentGraphemesCannotSuppressHighlights() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "a\u{301}b", right: "ac\u{301}", kind: .modified)
        )
        let left = try XCTUnwrap(detail.left)
        let right = try XCTUnwrap(detail.right)

        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(left.highlightRanges, [NSRange(location: 0, length: 3)])
        XCTAssertEqual(right.highlightRanges, [NSRange(location: 1, length: 2)])
        assertValidHighlightRanges(left)
        assertValidHighlightRanges(right)
    }

    func testRepeatedGraphemeTieUsesOneAlignedEditScript() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "aba", right: "baa", kind: .modified)
        )

        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(
            try XCTUnwrap(detail.left).highlightRanges,
            [NSRange(location: 0, length: 1)]
        )
        XCTAssertEqual(
            try XCTUnwrap(detail.right).highlightRanges,
            [NSRange(location: 2, length: 1)]
        )
        XCTAssertEqual(
            try XCTUnwrap(detail.left).fragments.filter(\.isHighlighted).map(\.text),
            ["a"]
        )
        XCTAssertEqual(
            try XCTUnwrap(detail.right).fragments.filter(\.isHighlighted).map(\.text),
            ["a"]
        )
        XCTAssertEqual(try XCTUnwrap(detail.left).fragments.map(\.text).joined(), "aba")
        XCTAssertEqual(try XCTUnwrap(detail.right).fragments.map(\.text).joined(), "baa")
    }

    func testSharedSurrogateHalvesDoNotPairAcrossDifferentGraphemes() throws {
        let detail = DifferenceDetail(
            row: makeRow(left: "😀😁", right: "😁😂", kind: .modified)
        )
        let left = try XCTUnwrap(detail.left)
        let right = try XCTUnwrap(detail.right)

        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(
            left.highlightRanges,
            [NSRange(location: 0, length: 2), NSRange(location: 4, length: 0)]
        )
        XCTAssertEqual(
            right.highlightRanges,
            [NSRange(location: 0, length: 0), NSRange(location: 2, length: 2)]
        )
        XCTAssertEqual(left.fragments.map(\.text), ["😀", "😁", ""])
        XCTAssertEqual(left.fragments.map(\.isHighlighted), [true, false, true])
        XCTAssertEqual(right.fragments.map(\.text), ["", "😁", "😂"])
        XCTAssertEqual(right.fragments.map(\.isHighlighted), [true, false, true])
    }

    func testResultInitializerPreservesMovedLinePartnerMetadata() throws {
        let comparison = try LineDiff.compareResult(
            left: "head\nmove seed\nstable one\nstable two\nstable three\ntail",
            right: "head\nstable one\nstable two\nstable three\nmove seed\ntail",
            options: LineDiffOptions(detectMovedBlocks: true)
        )
        let result = LineDiffResult(
            rows: comparison.rows,
            movedLines: comparison.movedLines,
            movedLineAnalysisStatus: comparison.movedLineAnalysisStatus
        )
        let removedID = DiffRow.ID(leftNumber: 2, rightNumber: nil)
        let addedID = DiffRow.ID(leftNumber: nil, rightNumber: 5)
        let removedIndex = try XCTUnwrap(result.rows.firstIndex { $0.id == removedID })
        let addedIndex = try XCTUnwrap(result.rows.firstIndex { $0.id == addedID })

        let removed = DifferenceDetail(
            result: result,
            selectedRowIndex: removedIndex,
            selectedRowID: removedID
        )
        let added = DifferenceDetail(
            result: result,
            selectedRowIndex: addedIndex,
            selectedRowID: addedID
        )

        XCTAssertEqual(result.movedLineAnalysisStatus, .available)
        XCTAssertEqual(removed.source?.id, removedID)
        XCTAssertEqual(removed.leftMovedLinePair, MovedLinePair(leftLine: 2, rightLine: 5))
        XCTAssertNil(removed.rightMovedLinePair)
        XCTAssertEqual(added.source?.id, addedID)
        XCTAssertNil(added.leftMovedLinePair)
        XCTAssertEqual(added.rightMovedLinePair, MovedLinePair(leftLine: 2, rightLine: 5))
    }

    func testAsymmetricMovedMapsUseOppositeDirectionFallbacks() {
        let leftToRight = [MovedLinePair(leftLine: 4, rightLine: 8)]
        let rightToLeft = [MovedLinePair(leftLine: 2, rightLine: 6)]

        let leftFallback = DifferenceDetail.resolveMovedLinePairs(
            rowID: DiffRow.ID(leftNumber: 2, rightNumber: nil),
            leftPair: nil,
            rightPair: nil,
            leftToRightCount: leftToRight.count,
            leftToRightPair: { leftToRight[$0] },
            rightToLeftCount: rightToLeft.count,
            rightToLeftPair: { rightToLeft[$0] }
        )
        let rightFallback = DifferenceDetail.resolveMovedLinePairs(
            rowID: DiffRow.ID(leftNumber: nil, rightNumber: 8),
            leftPair: nil,
            rightPair: nil,
            leftToRightCount: leftToRight.count,
            leftToRightPair: { leftToRight[$0] },
            rightToLeftCount: rightToLeft.count,
            rightToLeftPair: { rightToLeft[$0] }
        )

        XCTAssertEqual(leftFallback.left, MovedLinePair(leftLine: 2, rightLine: 6))
        XCTAssertNil(leftFallback.right)
        XCTAssertNil(rightFallback.left)
        XCTAssertEqual(rightFallback.right, MovedLinePair(leftLine: 4, rightLine: 8))
    }

    func testSourceBackedRowsPreserveOriginalByteSpellings() throws {
        let rows = try LineDiff.compare(left: "é", right: "e\u{301}")
        let detail = DifferenceDetail(rows: rows, selectedRowIndex: 0)

        XCTAssertTrue(try XCTUnwrap(rows.first).usesSourceTextStorage)
        XCTAssertEqual(Array(try XCTUnwrap(detail.source?.leftLine).text.utf8), Array("é".utf8))
        XCTAssertEqual(
            Array(try XCTUnwrap(detail.source?.rightLine).text.utf8),
            Array("e\u{301}".utf8)
        )
        XCTAssertEqual(Array(try XCTUnwrap(detail.left).text.utf8), Array("é".utf8))
        XCTAssertEqual(Array(try XCTUnwrap(detail.right).text.utf8), Array("e\u{301}".utf8))
    }

    func testExactComparisonLimitsStillProduceDetail() throws {
        let prefix = String(repeating: "🇺🇸", count: 2_047)
        let leftText = prefix + "🇺🇸"
        let rightText = prefix + "🇨🇦"

        XCTAssertEqual(leftText.utf8.count, 16_384)
        XCTAssertEqual(leftText.utf16.count, 8_192)
        XCTAssertEqual(leftText.count, 2_048)

        let detail = DifferenceDetail(
            row: makeRow(left: leftText, right: rightText, kind: .modified)
        )
        XCTAssertEqual(detail.state, .detail)
        XCTAssertEqual(
            try XCTUnwrap(detail.left).highlightRanges,
            [NSRange(location: 8_188, length: 4)]
        )
        XCTAssertEqual(
            try XCTUnwrap(detail.right).highlightRanges,
            [NSRange(location: 8_188, length: 4)]
        )
    }

    func testEachExceededComparisonLimitSuppressesDetail() throws {
        let characterLimitExceeded = String(repeating: "a", count: 2_049)
        XCTAssertEqual(characterLimitExceeded.utf8.count, 2_049)
        XCTAssertEqual(characterLimitExceeded.utf16.count, 2_049)
        XCTAssertEqual(characterLimitExceeded.count, 2_049)

        let fourCodeUnitGrapheme = "a\u{0301}\u{0302}\u{0303}"
        let fiveCodeUnitGrapheme = fourCodeUnitGrapheme + "\u{0304}"
        let utf16LimitExceeded = String(repeating: fourCodeUnitGrapheme, count: 2_047)
            + fiveCodeUnitGrapheme
        XCTAssertLessThanOrEqual(utf16LimitExceeded.utf8.count, 16_384)
        XCTAssertEqual(utf16LimitExceeded.utf16.count, 8_193)
        XCTAssertEqual(utf16LimitExceeded.count, 2_048)

        let highUTF8Grapheme = "a\u{20DD}\u{20DE}\u{20DF}"
        let utf8LimitExceeded = String(repeating: highUTF8Grapheme, count: 1_639)
        XCTAssertEqual(utf8LimitExceeded.utf8.count, 16_390)
        XCTAssertLessThanOrEqual(utf8LimitExceeded.utf16.count, 8_192)
        XCTAssertLessThanOrEqual(utf8LimitExceeded.count, 2_048)

        for text in [characterLimitExceeded, utf16LimitExceeded, utf8LimitExceeded] {
            let detail = DifferenceDetail(
                row: makeRow(left: text, right: "different", kind: .modified)
            )
            XCTAssertEqual(detail.state, .noDetail(.comparisonLimitExceeded))
            XCTAssertTrue(try XCTUnwrap(detail.left).highlightRanges.isEmpty)
            XCTAssertTrue(try XCTUnwrap(detail.right).highlightRanges.isEmpty)
        }
    }

    private func makeRow(left: String?, right: String?, kind: DiffKind) -> DiffRow {
        DiffRow(
            left: left.map { DiffLine(number: 1, text: $0) },
            right: right.map { DiffLine(number: 1, text: $0) },
            kind: kind
        )
    }

    private func assertValidHighlightRanges(
        _ side: DifferenceDetailSide,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var previousEnd = -1
        let boundaries = Set(
            side.text.indices.map { side.text.utf16.distance(from: side.text.startIndex, to: $0) }
                + [side.text.utf16.count]
        )
        for range in side.highlightRanges {
            XCTAssertGreaterThan(range.location, previousEnd, file: file, line: line)
            XCTAssertGreaterThanOrEqual(range.length, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(
                range.location + range.length,
                side.text.utf16.count,
                file: file,
                line: line
            )
            XCTAssertTrue(boundaries.contains(range.location), file: file, line: line)
            XCTAssertTrue(
                boundaries.contains(range.location + range.length),
                file: file,
                line: line
            )
            previousEnd = range.location + range.length
        }
    }
}
