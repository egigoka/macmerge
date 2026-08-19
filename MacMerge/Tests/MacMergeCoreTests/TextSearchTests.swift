import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class TextSearchTests: XCTestCase {
    func testLiteralSearchSupportsDirectionsWrappingCaseAndRepeatSearch() throws {
        let text = "Alpha beta alpha"
        let insensitive = TextSearchQuery(literal: "alpha", caseSensitive: false)
        let first = TextSearchMatch(range: NSRange(location: 0, length: 5))
        let last = TextSearchMatch(range: NSRange(location: 11, length: 5))

        XCTAssertEqual(
            try TextSearch.find(in: text, matching: insensitive, fromUTF16Offset: 0),
            TextSearchResult(match: first, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(in: text, matching: insensitive, fromUTF16Offset: 1),
            TextSearchResult(match: last, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: insensitive,
                direction: .backward,
                fromUTF16Offset: 11
            ),
            TextSearchResult(match: first, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(in: text, matching: insensitive, after: first),
            TextSearchResult(match: last, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: insensitive,
                direction: .backward,
                after: last
            ),
            TextSearchResult(match: first, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: insensitive,
                fromUTF16Offset: text.utf16.count,
                wrap: false
            ),
            TextSearchResult(match: nil, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: insensitive,
                fromUTF16Offset: text.utf16.count
            ),
            TextSearchResult(match: first, didWrap: true)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: insensitive,
                direction: .backward,
                fromUTF16Offset: 0
            ),
            TextSearchResult(match: last, didWrap: true)
        )

        XCTAssertEqual(
            try TextSearch.markerRanges(in: text, matching: TextSearchQuery(literal: "alpha")),
            [last.range]
        )
    }

    func testRegularExpressionSearchSupportsDirectionsAndWrapping() throws {
        let text = "a1 a22 a333"
        let query = TextSearchQuery(regularExpression: #"a\d+"#)
        let first = TextSearchMatch(range: NSRange(location: 0, length: 2))
        let middle = TextSearchMatch(range: NSRange(location: 3, length: 3))
        let last = TextSearchMatch(range: NSRange(location: 7, length: 4))

        XCTAssertEqual(
            try TextSearch.find(in: text, matching: query, fromUTF16Offset: 2),
            TextSearchResult(match: middle, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: query,
                direction: .backward,
                fromUTF16Offset: 7
            ),
            TextSearchResult(match: middle, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(in: text, matching: query, after: middle),
            TextSearchResult(match: last, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: query,
                direction: .backward,
                after: middle
            ),
            TextSearchResult(match: first, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: query,
                fromUTF16Offset: text.utf16.count
            ),
            TextSearchResult(match: first, didWrap: true)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: query,
                direction: .backward,
                fromUTF16Offset: 0,
                wrap: false
            ),
            TextSearchResult(match: nil, didWrap: false)
        )
    }

    func testCanonicalEquivalentLiteralMatchesPreserveOriginalUTF16Ranges() throws {
        let text = "Cafe\u{301} café"
        let query = TextSearchQuery(literal: "CAFÉ", caseSensitive: false)

        XCTAssertEqual(
            try TextSearch.markerRanges(in: text, matching: query),
            [NSRange(location: 0, length: 5), NSRange(location: 6, length: 4)]
        )
        XCTAssertEqual(
            try TextSearch.replaceAll(in: text, matching: query, with: "X"),
            TextReplacementResult(text: "X X", replacementCount: 2)
        )

        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: text,
                matching: TextSearchQuery(literal: "Café", caseSensitive: true)
            ),
            [NSRange(location: 0, length: 5)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: text,
                matching: TextSearchQuery(literal: "cafe", caseSensitive: false)
            ),
            []
        )
    }

    func testWholeWordUsesUnicodeLettersConnectorsAndEmojiBoundaries() throws {
        let text = "猫 猫科 _猫 猫_ ‿猫 猫‿ 😀猫😀"
        let literal = TextSearchQuery(literal: "猫", wholeWord: true)
        let regex = TextSearchQuery(regularExpression: "猫", wholeWord: true)
        let expected = [NSRange(location: 0, length: 1), NSRange(location: 19, length: 1)]

        XCTAssertEqual(try TextSearch.markerRanges(in: text, matching: literal), expected)
        XCTAssertEqual(try TextSearch.markerRanges(in: text, matching: regex), expected)

        let emojiText = "😀 x😀 😀x 😀"
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: emojiText,
                matching: TextSearchQuery(regularExpression: "😀", wholeWord: true)
            ),
            [NSRange(location: 0, length: 2), NSRange(location: 11, length: 2)]
        )

        let numberText = "猫 猫١ ١猫 猫"
        let numberExpected = [NSRange(location: 0, length: 1), NSRange(location: 8, length: 1)]
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: numberText,
                matching: TextSearchQuery(literal: "猫", wholeWord: true)
            ),
            numberExpected
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: numberText,
                matching: TextSearchQuery(regularExpression: "猫", wholeWord: true)
            ),
            numberExpected
        )
    }

    func testWholeWordExtendedModeRegexWithTrailingCommentRemainsValid() throws {
        let query = TextSearchQuery(
            regularExpression: "(?x)foo # trailing comment",
            wholeWord: true
        )

        XCTAssertEqual(
            try TextSearch.markerRanges(in: "foo foobar", matching: query),
            [NSRange(location: 0, length: 3)]
        )
    }

    func testWholeWordRegexClosesOpenQuotedLiteralBeforeBoundarySuffix() throws {
        let query = TextSearchQuery(regularExpression: #"\Qfoo"#, wholeWord: true)

        XCTAssertEqual(
            try TextSearch.markerRanges(in: "foo foobar", matching: query),
            [NSRange(location: 0, length: 3)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "foo foobar",
                matching: TextSearchQuery(
                    regularExpression: "(?x)foo # \\Q",
                    wholeWord: true
                )
            ),
            [NSRange(location: 0, length: 3)]
        )
    }

    func testUTF16RangesRejectInvalidOffsetsAndSplitGraphemes() {
        let text = "e\u{301}😀x"
        let query = TextSearchQuery(literal: "x")

        assertTextSearchError(
            .invalidUTF16Range(NSRange(location: -1, length: 0)),
            try TextSearch.find(in: text, matching: query, fromUTF16Offset: -1)
        )
        assertTextSearchError(
            .invalidUTF16Range(NSRange(location: -1, length: 1)),
            try TextSearch.find(
                in: text,
                matching: query,
                after: TextSearchMatch(range: NSRange(location: -1, length: 1))
            )
        )
        assertTextSearchError(
            .invalidUTF16Range(NSRange(location: 0, length: -1)),
            try TextSearch.replaceCurrent(
                in: text,
                match: TextSearchMatch(range: NSRange(location: 0, length: -1)),
                matching: query,
                with: "X"
            )
        )
        assertTextSearchError(
            .rangeSplitsGrapheme(NSRange(location: 1, length: 0)),
            try TextSearch.find(in: text, matching: query, fromUTF16Offset: 1)
        )
        assertTextSearchError(
            .rangeSplitsGrapheme(NSRange(location: 2, length: 1)),
            try TextSearch.replaceCurrent(
                in: text,
                match: TextSearchMatch(range: NSRange(location: 2, length: 1)),
                matching: TextSearchQuery(literal: "😀"),
                with: "X"
            )
        )
        assertTextSearchError(
            .invalidUTF16Range(NSRange(location: 6, length: 0)),
            try TextSearch.find(in: text, matching: query, fromUTF16Offset: 6)
        )
        assertTextSearchError(
            .invalidUTF16Range(NSRange(location: Int.max, length: 1)),
            try TextSearch.replaceCurrent(
                in: text,
                match: TextSearchMatch(range: NSRange(location: Int.max, length: 1)),
                matching: query,
                with: "X"
            )
        )
        assertTextSearchError(
            .invalidUTF16Range(NSRange(location: Int.max, length: 1)),
            try TextSearch.find(
                in: text,
                matching: query,
                after: TextSearchMatch(range: NSRange(location: Int.max, length: 1))
            )
        )
    }

    func testMatchesThatSplitGraphemesAreRejectedWithoutHidingLaterMatches() throws {
        let text = "e\u{301}x"

        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: text,
                matching: TextSearchQuery(regularExpression: "\u{301}x|x")
            ),
            [NSRange(location: 2, length: 1)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: text,
                matching: TextSearchQuery(literal: "\u{301}")
            ),
            []
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}",
                matching: TextSearchQuery(regularExpression: "e|e\u{301}")
            ),
            [NSRange(location: 0, length: 2)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: TextSearchQuery(
                    regularExpression: "e|e\u{301}|\u{301}x|x"
                )
            ),
            [NSRange(location: 0, length: 2), NSRange(location: 2, length: 1)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: TextSearchQuery(
                    regularExpression: "(?x)\u{301}x|x # \\G"
                )
            ),
            [NSRange(location: 2, length: 1)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: TextSearchQuery(regularExpression: "\\Gz|\u{301}x|x")
            ),
            [NSRange(location: 2, length: 1)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: TextSearchQuery(
                    regularExpression: "\u{301}x|[\\Q]\\G\\E]|x"
                )
            ),
            [NSRange(location: 2, length: 1)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: TextSearchQuery(regularExpression: "[^]\\G]|x")
            ),
            [NSRange(location: 2, length: 1)]
        )
    }

    func testZeroLengthRegexRepeatSearchAndReplacementMakeGraphemeProgress() throws {
        let text = "😀a"
        let query = TextSearchQuery(regularExpression: "")
        let ranges = [
            NSRange(location: 0, length: 0),
            NSRange(location: 2, length: 0),
            NSRange(location: 3, length: 0)
        ]

        XCTAssertEqual(try TextSearch.markerRanges(in: text, matching: query), ranges)
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: query
            ),
            [
                NSRange(location: 0, length: 0),
                NSRange(location: 2, length: 0),
                NSRange(location: 3, length: 0)
            ]
        )

        let first = TextSearchMatch(range: ranges[0])
        let second = TextSearchMatch(range: ranges[1])
        let last = TextSearchMatch(range: ranges[2])
        XCTAssertEqual(
            try TextSearch.find(in: text, matching: query, after: first),
            TextSearchResult(match: second, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(in: text, matching: query, after: last),
            TextSearchResult(match: first, didWrap: true)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: query,
                direction: .backward,
                after: last
            ),
            TextSearchResult(match: second, didWrap: false)
        )
        XCTAssertEqual(
            try TextSearch.find(
                in: text,
                matching: query,
                direction: .backward,
                after: first
            ),
            TextSearchResult(match: last, didWrap: true)
        )
        XCTAssertEqual(
            try TextSearch.replaceCurrent(in: text, match: second, matching: query, with: "X"),
            TextReplacementResult(text: "😀Xa", replacementCount: 1)
        )
        XCTAssertEqual(
            try TextSearch.replaceAll(in: text, matching: query, with: "-"),
            TextReplacementResult(text: "-😀-a-", replacementCount: 3)
        )

        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "abc",
                matching: TextSearchQuery(regularExpression: #"\G"#)
            ),
            [NSRange(location: 0, length: 0)]
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: TextSearchQuery(regularExpression: #"\G(?:e|x)"#)
            ),
            []
        )
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "e\u{301}x",
                matching: TextSearchQuery(regularExpression: "\\G(?:e|e\u{301}|x)")
            ),
            [NSRange(location: 0, length: 2), NSRange(location: 2, length: 1)]
        )
    }

    func testRegexCaptureTemplatesHandleOptionalMultiDigitAndEscapedValues() throws {
        let query = TextSearchQuery(regularExpression: #"([a-z]+)-(\d+)"#)
        let first = TextSearchMatch(range: NSRange(location: 0, length: 7))

        XCTAssertEqual(
            try TextSearch.replaceCurrent(
                in: "item-42 note-7",
                match: first,
                matching: query,
                with: #"<$2:$1:\$>"#
            ),
            TextReplacementResult(text: "<42:item:$> note-7", replacementCount: 1)
        )
        XCTAssertEqual(
            try TextSearch.replaceAll(
                in: "a ab",
                matching: TextSearchQuery(regularExpression: "(a)(b)?"),
                with: "$2[$1]"
            ),
            TextReplacementResult(text: "[a] b[a]", replacementCount: 2)
        )

        let tenCaptures = TextSearchQuery(
            regularExpression: "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)"
        )
        XCTAssertEqual(
            try TextSearch.replaceAll(in: "abcdefghij", matching: tenCaptures, with: "$10-$1"),
            TextReplacementResult(text: "j-a", replacementCount: 1)
        )
        XCTAssertEqual(
            try TextSearch.replaceAll(
                in: "a",
                matching: TextSearchQuery(regularExpression: "(a)"),
                with: "$10"
            ),
            TextReplacementResult(text: "a0", replacementCount: 1)
        )
    }

    func testReplaceCurrentRequiresExactMatchAndLiteralTemplatesStayLiteral() throws {
        let text = "foo foo"
        let query = TextSearchQuery(literal: "foo")

        XCTAssertEqual(
            try TextSearch.replaceCurrent(
                in: text,
                match: TextSearchMatch(range: NSRange(location: 4, length: 3)),
                matching: query,
                with: "$1"
            ),
            TextReplacementResult(text: "foo $1", replacementCount: 1)
        )
        XCTAssertEqual(
            try TextSearch.replaceCurrent(
                in: text,
                match: TextSearchMatch(range: NSRange(location: 0, length: 1)),
                matching: query,
                with: "X"
            ),
            TextReplacementResult(text: text, replacementCount: 0)
        )
        XCTAssertEqual(
            try TextSearch.replaceCurrent(
                in: "bar foo",
                match: TextSearchMatch(range: NSRange(location: 0, length: 3)),
                matching: query,
                with: "X"
            ),
            TextReplacementResult(text: "bar foo", replacementCount: 0)
        )
        XCTAssertEqual(
            try TextSearch.replaceAll(in: text, matching: query, with: "X"),
            TextReplacementResult(text: "X X", replacementCount: 2)
        )
    }

    func testMarkerRangesAreGloballySortedWithStableMarkerPrecedence() throws {
        let markers = [
            TextMarker(id: "long", query: TextSearchQuery(literal: "aba")),
            TextMarker(id: "short", query: TextSearchQuery(literal: "a")),
            TextMarker(id: "lookahead", query: TextSearchQuery(regularExpression: "(?=ba)"))
        ]

        XCTAssertEqual(
            try TextSearch.markerRanges(in: "ababa", markers: markers),
            [
                TextMarkerRange(markerID: "long", range: NSRange(location: 0, length: 3)),
                TextMarkerRange(markerID: "short", range: NSRange(location: 0, length: 1)),
                TextMarkerRange(markerID: "lookahead", range: NSRange(location: 1, length: 0)),
                TextMarkerRange(markerID: "short", range: NSRange(location: 2, length: 1)),
                TextMarkerRange(markerID: "lookahead", range: NSRange(location: 3, length: 0)),
                TextMarkerRange(markerID: "short", range: NSRange(location: 4, length: 1))
            ]
        )
    }

    func testInvalidRegularExpressionsFailWithoutPartialResults() {
        let invalid = TextSearchQuery(regularExpression: "[")

        assertTextSearchError(
            .invalidPattern("["),
            try TextSearch.find(in: "text", matching: invalid, fromUTF16Offset: 0)
        )
        assertTextSearchError(
            .invalidPattern("["),
            try TextSearch.replaceAll(in: "text", matching: invalid, with: "X")
        )
        assertTextSearchError(
            .invalidPattern("["),
            try TextSearch.markerRanges(
                in: "text",
                markers: [
                    TextMarker(id: "valid", query: TextSearchQuery(literal: "text")),
                    TextMarker(id: "invalid", query: invalid)
                ]
            )
        )
    }

    func testInputAndPatternUTF16LimitsAcceptExactBoundsAndRejectOneMore() throws {
        let inputLimits = limits(maximumInputUTF16Length: 4)
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "😀ab",
                matching: TextSearchQuery(literal: "ab"),
                limits: inputLimits
            ),
            [NSRange(location: 2, length: 2)]
        )
        assertTextSearchError(
            .inputTooLarge(maximumUTF16Length: 4),
            try TextSearch.markerRanges(
                in: "😀abc",
                matching: TextSearchQuery(literal: "a"),
                limits: inputLimits
            )
        )

        let patternLimits = limits(maximumPatternUTF16Length: 2)
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "😀",
                matching: TextSearchQuery(literal: "😀"),
                limits: patternLimits
            ),
            [NSRange(location: 0, length: 2)]
        )
        assertTextSearchError(
            .patternTooLarge(maximumUTF16Length: 2),
            try TextSearch.markerRanges(
                in: "😀a",
                matching: TextSearchQuery(literal: "😀a"),
                limits: patternLimits
            )
        )
    }

    func testOutputAndReplacementTemplateUTF16LimitsCoverExactExpansionAndNoOp() throws {
        let outputLimits = limits(maximumOutputUTF16Length: 4)
        XCTAssertEqual(
            try TextSearch.replaceAll(
                in: "aa",
                matching: TextSearchQuery(literal: "a"),
                with: "bb",
                limits: outputLimits
            ),
            TextReplacementResult(text: "bbbb", replacementCount: 2)
        )
        assertTextSearchError(
            .outputTooLarge(maximumUTF16Length: 4),
            try TextSearch.replaceAll(
                in: "aa",
                matching: TextSearchQuery(literal: "a"),
                with: "bbb",
                limits: outputLimits
            )
        )
        XCTAssertEqual(
            try TextSearch.replaceAll(
                in: "1234",
                matching: TextSearchQuery(literal: "z"),
                with: "x",
                limits: outputLimits
            ),
            TextReplacementResult(text: "1234", replacementCount: 0)
        )
        assertTextSearchError(
            .outputTooLarge(maximumUTF16Length: 4),
            try TextSearch.replaceAll(
                in: "12345",
                matching: TextSearchQuery(literal: "z"),
                with: "x",
                limits: outputLimits
            )
        )

        XCTAssertEqual(
            try TextSearch.replaceAll(
                in: "ab",
                matching: TextSearchQuery(literal: "a"),
                with: "😀",
                limits: limits(maximumOutputUTF16Length: 3)
            ),
            TextReplacementResult(text: "😀b", replacementCount: 1)
        )
        assertTextSearchError(
            .outputTooLarge(maximumUTF16Length: 2),
            try TextSearch.replaceAll(
                in: "ab",
                matching: TextSearchQuery(literal: "a"),
                with: "😀",
                limits: limits(maximumOutputUTF16Length: 2)
            )
        )

        let backreferenceQuery = TextSearchQuery(regularExpression: "(a+)")
        XCTAssertEqual(
            try TextSearch.replaceAll(
                in: "aaaa",
                matching: backreferenceQuery,
                with: "$1$1",
                limits: limits(maximumOutputUTF16Length: 8)
            ),
            TextReplacementResult(text: "aaaaaaaa", replacementCount: 1)
        )
        assertTextSearchError(
            .outputTooLarge(maximumUTF16Length: 7),
            try TextSearch.replaceAll(
                in: "aaaa",
                matching: backreferenceQuery,
                with: "$1$1",
                limits: limits(maximumOutputUTF16Length: 7)
            )
        )

        let templateLimits = limits(maximumReplacementTemplateUTF16Length: 2)
        XCTAssertEqual(
            try TextSearch.replaceAll(
                in: "a",
                matching: TextSearchQuery(literal: "a"),
                with: "😀",
                limits: templateLimits
            ),
            TextReplacementResult(text: "😀", replacementCount: 1)
        )
        assertTextSearchError(
            .replacementTemplateTooLarge(maximumUTF16Length: 2),
            try TextSearch.replaceAll(
                in: "a",
                matching: TextSearchQuery(literal: "a"),
                with: "😀x",
                limits: templateLimits
            )
        )
    }

    func testMatchAndStoredCaptureLimitsAcceptExactBoundsAndRejectOneMore() throws {
        let matchLimits = limits(maximumMatches: 2)
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "aa",
                matching: TextSearchQuery(literal: "a"),
                limits: matchLimits
            ).count,
            2
        )
        assertTextSearchError(
            .tooManyMatches(maximumMatches: 2),
            try TextSearch.markerRanges(
                in: "aaa",
                matching: TextSearchQuery(literal: "a"),
                limits: matchLimits
            )
        )

        let literalCaptureLimits = limits(maximumStoredCaptureRanges: 2)
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "aa",
                matching: TextSearchQuery(literal: "a"),
                limits: literalCaptureLimits
            ).count,
            2
        )
        assertTextSearchError(
            .tooManyCaptureRanges(maximumRanges: 2),
            try TextSearch.markerRanges(
                in: "aaa",
                matching: TextSearchQuery(literal: "a"),
                limits: literalCaptureLimits
            )
        )

        let exactRegexCaptureLimits = limits(maximumStoredCaptureRanges: 3)
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "ab",
                matching: TextSearchQuery(regularExpression: "(a)(b)"),
                limits: exactRegexCaptureLimits
            ),
            [NSRange(location: 0, length: 2)]
        )
        assertTextSearchError(
            .tooManyCaptureRanges(maximumRanges: 2),
            try TextSearch.markerRanges(
                in: "ab",
                matching: TextSearchQuery(regularExpression: "(a)(b)"),
                limits: literalCaptureLimits
            )
        )

        let optionalCaptureQuery = TextSearchQuery(regularExpression: "(a)(b)?")
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "a",
                matching: optionalCaptureQuery,
                limits: limits(maximumStoredCaptureRanges: 2)
            ),
            [NSRange(location: 0, length: 1)]
        )
        assertTextSearchError(
            .tooManyCaptureRanges(maximumRanges: 1),
            try TextSearch.markerRanges(
                in: "a",
                matching: optionalCaptureQuery,
                limits: limits(maximumStoredCaptureRanges: 1)
            )
        )
    }

    func testMultiMarkerLiteralCaptureLimitIsAggregate() throws {
        let markers = [
            TextMarker(id: "a", query: TextSearchQuery(literal: "a")),
            TextMarker(id: "b", query: TextSearchQuery(literal: "b"))
        ]
        let expected = [
            TextMarkerRange(markerID: "a", range: NSRange(location: 0, length: 1)),
            TextMarkerRange(markerID: "b", range: NSRange(location: 1, length: 1))
        ]

        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "ab",
                markers: markers,
                limits: limits(maximumStoredCaptureRanges: 2)
            ),
            expected
        )
        assertTextSearchError(
            .tooManyCaptureRanges(maximumRanges: 1),
            try TextSearch.markerRanges(
                in: "ab",
                markers: markers,
                limits: limits(maximumStoredCaptureRanges: 1)
            )
        )
    }

    func testMultiMarkerRegexCaptureLimitIsAggregate() throws {
        let markers = [
            TextMarker(id: "a", query: TextSearchQuery(regularExpression: "(a)")),
            TextMarker(id: "b", query: TextSearchQuery(regularExpression: "(b)"))
        ]
        let expected = [
            TextMarkerRange(markerID: "a", range: NSRange(location: 0, length: 1)),
            TextMarkerRange(markerID: "b", range: NSRange(location: 1, length: 1))
        ]

        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "ab",
                markers: markers,
                limits: limits(maximumStoredCaptureRanges: 4)
            ),
            expected
        )
        assertTextSearchError(
            .tooManyCaptureRanges(maximumRanges: 3),
            try TextSearch.markerRanges(
                in: "ab",
                markers: markers,
                limits: limits(maximumStoredCaptureRanges: 3)
            )
        )

        let zeroLengthCaptureMarkers = [
            TextMarker(id: "a", query: TextSearchQuery(regularExpression: "(a)()")),
            TextMarker(id: "b", query: TextSearchQuery(regularExpression: "(b)()"))
        ]
        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "ab",
                markers: zeroLengthCaptureMarkers,
                limits: limits(maximumStoredCaptureRanges: 6)
            ),
            expected
        )
        assertTextSearchError(
            .tooManyCaptureRanges(maximumRanges: 5),
            try TextSearch.markerRanges(
                in: "ab",
                markers: zeroLengthCaptureMarkers,
                limits: limits(maximumStoredCaptureRanges: 5)
            )
        )
    }

    func testMultiMarkerSimultaneousMatchAndCaptureExhaustionPrefersMatchError() {
        let markers = [
            TextMarker(id: "a", query: TextSearchQuery(regularExpression: "(a)")),
            TextMarker(id: "b", query: TextSearchQuery(regularExpression: "(b)"))
        ]

        assertTextSearchError(
            .tooManyMatches(maximumMatches: 1),
            try TextSearch.markerRanges(
                in: "ab",
                markers: markers,
                limits: limits(maximumMatches: 1, maximumStoredCaptureRanges: 2)
            )
        )
    }

    func testMarkerCountAndCombinedPatternLimitsAcceptExactBoundsAndRejectOneMore() throws {
        let twoMarkers = [
            TextMarker(id: "ascii", query: TextSearchQuery(literal: "ab")),
            TextMarker(id: "emoji", query: TextSearchQuery(literal: "😀"))
        ]
        let threeMarkers =
            twoMarkers + [
                TextMarker(id: "extra", query: TextSearchQuery(literal: "c"))
            ]

        let markerLimits = limits(maximumMarkers: 2)
        XCTAssertEqual(try TextSearch.markerRanges(in: "", markers: twoMarkers, limits: markerLimits), [])
        assertTextSearchError(
            .tooManyMarkers(maximumMarkers: 2),
            try TextSearch.markerRanges(in: "", markers: threeMarkers, limits: markerLimits)
        )

        let combinedLimits = limits(maximumMarkers: 3, maximumCombinedPatternUTF16Length: 4)
        XCTAssertEqual(
            try TextSearch.markerRanges(in: "", markers: twoMarkers, limits: combinedLimits),
            []
        )
        assertTextSearchError(
            .combinedPatternsTooLarge(maximumUTF16Length: 4),
            try TextSearch.markerRanges(in: "", markers: threeMarkers, limits: combinedLimits)
        )
    }

    func testRegularExpressionProgressLimitCancelsPathologicalBacktracking() throws {
        let childEnvironmentKey = "MACMERGE_TEXT_SEARCH_PATHOLOGICAL_REGEX_CHILD"
        let query = TextSearchQuery(regularExpression: "^(a+)+$")
        let limits = limits(maximumRegularExpressionProgressSteps: 1)
        let input = String(repeating: "a", count: 64) + "!"

        if ProcessInfo.processInfo.environment[childEnvironmentKey] == "1" {
            assertTextSearchError(
                .evaluationLimitExceeded(maximumProgressSteps: 1),
                try TextSearch.markerRanges(in: input, matching: query, limits: limits)
            )
            return
        }

        try assertPathologicalRegexCompletes(
            childEnvironmentKey: childEnvironmentKey,
            testName: "testRegularExpressionProgressLimitCancelsPathologicalBacktracking",
            timeout: .seconds(30)
        )

        XCTAssertEqual(
            try TextSearch.markerRanges(
                in: "aaaa",
                matching: TextSearchQuery(regularExpression: "a+"),
                limits: limits
            ),
            [NSRange(location: 0, length: 4)]
        )

        assertTextSearchError(
            .evaluationLimitExceeded(maximumProgressSteps: 2),
            try TextSearch.markerRanges(
                in: "e\u{301}e\u{301}e\u{301}",
                matching: TextSearchQuery(regularExpression: "e"),
                limits: self.limits(maximumRegularExpressionProgressSteps: 2)
            )
        )
    }

    func testSameOffsetLongerAlternativeCompilationRetriesAreBudgeted() throws {
        let childEnvironmentKey = "MACMERGE_TEXT_SEARCH_COMPILE_RETRY_CHILD"
        let combiningMark = "\u{301}"
        let pattern = "(?x)e|e\(combiningMark) # trailing comment"
        let input = "e\(combiningMark)"
        let boundarySuffix = "(?!(?:[\\s\\S]{1})\\z)"
        let firstRetryPattern = "(?:\(pattern))\(boundarySuffix)"
        let progressLimit = 2 + firstRetryPattern.utf16.count

        if ProcessInfo.processInfo.environment[childEnvironmentKey] == "1" {
            assertTextSearchError(
                .evaluationLimitExceeded(maximumProgressSteps: progressLimit),
                try TextSearch.markerRanges(
                    in: input,
                    matching: TextSearchQuery(regularExpression: pattern),
                    limits: limits(maximumRegularExpressionProgressSteps: progressLimit)
                )
            )
            return
        }

        try assertPathologicalRegexCompletes(
            childEnvironmentKey: childEnvironmentKey,
            testName: "testSameOffsetLongerAlternativeCompilationRetriesAreBudgeted",
            timeout: .seconds(30)
        )
    }

    func testRegexReplacementCumulativeTemplateWorkIsBounded() {
        assertTextSearchError(
            .evaluationLimitExceeded(maximumProgressSteps: 10_000),
            try TextSearch.replaceAll(
                in: String(repeating: "a", count: 100),
                matching: TextSearchQuery(regularExpression: "(z)?"),
                with: String(repeating: "$1", count: 100),
                limits: limits(maximumRegularExpressionProgressSteps: 10_000)
            )
        )
    }

    func testLargeRejectedAndDenseZeroLengthPatternsFinishWithinReasonableTime() throws {
        let clock = ContinuousClock()
        let maximumDuration = Duration.seconds(30)
        let oversizedPattern = String(repeating: "(?:a?)", count: 20_000)
        let rejectionStarted = clock.now
        assertTextSearchError(
            .patternTooLarge(maximumUTF16Length: 1_024),
            try TextSearch.markerRanges(
                in: "a",
                matching: TextSearchQuery(regularExpression: oversizedPattern),
                limits: limits(maximumPatternUTF16Length: 1_024)
            )
        )
        XCTAssertLessThan(rejectionStarted.duration(to: clock.now), maximumDuration)

        let graphemeCount = 10_000
        let denseInput = String(repeating: "😀", count: graphemeCount)
        let denseStarted = clock.now
        let ranges = try TextSearch.markerRanges(
            in: denseInput,
            matching: TextSearchQuery(regularExpression: ""),
            limits: limits(
                maximumInputUTF16Length: graphemeCount * 2,
                maximumMatches: graphemeCount + 1,
                maximumStoredCaptureRanges: graphemeCount + 1
            )
        )

        XCTAssertEqual(ranges.count, graphemeCount + 1)
        XCTAssertEqual(ranges.first, NSRange(location: 0, length: 0))
        XCTAssertEqual(ranges.last, NSRange(location: graphemeCount * 2, length: 0))
        XCTAssertLessThan(denseStarted.duration(to: clock.now), maximumDuration)

        let replacementStarted = clock.now
        let replacement = try TextSearch.replaceAll(
            in: denseInput,
            matching: TextSearchQuery(regularExpression: ""),
            with: "-",
            limits: limits(
                maximumInputUTF16Length: graphemeCount * 2,
                maximumOutputUTF16Length: graphemeCount * 3 + 1,
                maximumMatches: graphemeCount + 1,
                maximumStoredCaptureRanges: graphemeCount + 1
            )
        )

        XCTAssertEqual(replacement.replacementCount, graphemeCount + 1)
        XCTAssertEqual(replacement.text, String(repeating: "-😀", count: graphemeCount) + "-")
        XCTAssertLessThan(replacementStarted.duration(to: clock.now), maximumDuration)
    }

    private func assertPathologicalRegexCompletes(
        childEnvironmentKey: String,
        testName: String,
        timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMerge-TextSearchTests-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            XCTFail("Could not create subprocess diagnostics file.", file: file, line: line)
            return
        }
        let output = try FileHandle(forUpdating: outputURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xctest",
            "-XCTest",
            "\(NSStringFromClass(Self.self))/\(testName)",
            Bundle(for: Self.self).bundlePath
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [childEnvironmentKey: "1"],
            uniquingKeysWith: { _, child in child }
        )
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while process.isRunning, clock.now < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let didTimeOut = process.isRunning
        if didTimeOut {
            _ = kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()

        try output.synchronize()
        try output.seek(toOffset: 0)
        let diagnostics = String(decoding: try output.readToEnd() ?? Data(), as: UTF8.self)
        XCTAssertFalse(
            didTimeOut,
            "Pathological regular expression exceeded \(timeout) seconds.\n\(diagnostics)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            process.terminationStatus,
            0,
            "Pathological regular expression subprocess failed.\n\(diagnostics)",
            file: file,
            line: line
        )
    }

    private func limits(
        maximumInputUTF16Length: Int = 100_000,
        maximumPatternUTF16Length: Int = 100_000,
        maximumOutputUTF16Length: Int = 100_000,
        maximumMatches: Int = 100_000,
        maximumMarkers: Int = 100,
        maximumCombinedPatternUTF16Length: Int = 100_000,
        maximumReplacementTemplateUTF16Length: Int = 100_000,
        maximumStoredCaptureRanges: Int = 100_000,
        maximumRegularExpressionProgressSteps: Int = 100_000
    ) -> TextSearchLimits {
        TextSearchLimits(
            maximumInputUTF16Length: maximumInputUTF16Length,
            maximumPatternUTF16Length: maximumPatternUTF16Length,
            maximumOutputUTF16Length: maximumOutputUTF16Length,
            maximumMatches: maximumMatches,
            maximumMarkers: maximumMarkers,
            maximumCombinedPatternUTF16Length: maximumCombinedPatternUTF16Length,
            maximumReplacementTemplateUTF16Length: maximumReplacementTemplateUTF16Length,
            maximumStoredCaptureRanges: maximumStoredCaptureRanges,
            maximumRegularExpressionProgressSteps: maximumRegularExpressionProgressSteps
        )
    }

    private func assertTextSearchError<T>(
        _ expected: TextSearchError,
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? TextSearchError, expected, file: file, line: line)
        }
    }
}
