import Foundation
@testable import MacMerge
import MacMergeCore
import XCTest

final class IntralineUnicodeTests: XCTestCase {
    func testCombiningMarkDifferenceCoversWholeGrapheme() {
        let text = "Cafe\u{301} noir"
        let ranges = intralineDifferenceRanges(in: text, comparedWith: "Cafe noir")

        XCTAssertEqual(ranges, [NSRange(location: 3, length: 2)])
        assertValidUTF16GraphemeRanges(ranges, in: text)
        XCTAssertEqual(
            intralineDifferenceRanges(in: "Caf\u{E9} noir", comparedWith: text),
            [],
            "Canonically equivalent graphemes should not differ"
        )
    }

    func testEmojiDifferenceCoversWholeJoinedCluster() {
        let text = "A👨‍👩‍👧‍👦BC"
        let ranges = intralineDifferenceRanges(in: text, comparedWith: "A👩‍👩‍👧‍👦BC")

        XCTAssertEqual(ranges, [NSRange(location: 1, length: 11)])
        assertValidUTF16GraphemeRanges(ranges, in: text)
        XCTAssertEqual((text as NSString).substring(with: ranges[0]), "👨‍👩‍👧‍👦")
    }

    func testTabAndWideSupplementaryGlyphUseUTF16Ranges() {
        let text = "A\tBC𠮷DE"
        let ranges = intralineDifferenceRanges(in: text, comparedWith: "A BC吉DE")

        XCTAssertEqual(ranges, [
            NSRange(location: 1, length: 1),
            NSRange(location: 4, length: 2),
        ])
        assertValidUTF16GraphemeRanges(ranges, in: text)
        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["\t", "𠮷"])
    }

    func testLegacyCodePageDecodedTextProducesUnicodeRanges() throws {
        let text = try TextFileCodec.decode(
            Data([0x41, 0x80, 0x42, 0x43, 0x8A, 0x44]),
            assuming: .windows1252
        ).text
        let other = try TextFileCodec.decode(
            Data([0x41, 0xA3, 0x42, 0x43, 0x8E, 0x44]),
            assuming: .windows1252
        ).text

        XCTAssertEqual(text, "A€BCŠD")
        XCTAssertEqual(other, "A£BCŽD")
        let ranges = intralineDifferenceRanges(in: text, comparedWith: other)
        XCTAssertEqual(ranges, [
            NSRange(location: 1, length: 1),
            NSRange(location: 4, length: 1),
        ])
        assertValidUTF16GraphemeRanges(ranges, in: text)
    }

    func testUnicodeDifferenceTraversalCyclesInBothDirections() throws {
        let text = "A👨‍👩‍👧‍👦BCe\u{301}DE𠮷F"
        let ranges = intralineDifferenceRanges(
            in: text,
            comparedWith: "A👩‍👩‍👧‍👦BCeDE吉F"
        )
        XCTAssertEqual(ranges, [
            NSRange(location: 1, length: 11),
            NSRange(location: 14, length: 2),
            NSRange(location: 18, length: 2),
        ])
        assertValidUTF16GraphemeRanges(ranges, in: text)

        var selection = ranges[0]
        for expected in [ranges[1], ranges[2], ranges[0]] {
            selection = try XCTUnwrap(
                lineDifferenceRange(in: ranges, from: selection, direction: .next)
            )
            XCTAssertEqual(selection, expected)
        }

        for expected in [ranges[2], ranges[1], ranges[0]] {
            selection = try XCTUnwrap(
                lineDifferenceRange(in: ranges, from: selection, direction: .previous)
            )
            XCTAssertEqual(selection, expected)
        }
        XCTAssertNil(
            lineDifferenceRange(in: [], from: NSRange(location: 0, length: 0), direction: .next)
        )
    }

    private func assertValidUTF16GraphemeRanges(
        _ ranges: [NSRange],
        in text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var boundaries: Set<Int> = [0]
        var utf16Offset = 0
        for character in text {
            utf16Offset += String(character).utf16.count
            boundaries.insert(utf16Offset)
        }

        for range in ranges {
            XCTAssertGreaterThanOrEqual(range.location, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(range.length, 0, file: file, line: line)
            guard range.location >= 0, range.length >= 0 else { continue }

            let upperBound = NSMaxRange(range)
            XCTAssertLessThanOrEqual(upperBound, text.utf16.count, file: file, line: line)
            XCTAssertTrue(boundaries.contains(range.location), file: file, line: line)
            XCTAssertTrue(boundaries.contains(upperBound), file: file, line: line)
            XCTAssertNotNil(Range(range, in: text), file: file, line: line)
        }
    }
}
