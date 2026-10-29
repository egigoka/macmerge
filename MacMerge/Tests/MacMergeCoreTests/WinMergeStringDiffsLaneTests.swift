import Foundation
import MacMergeCore
import XCTest

/// Edge cases and bounds for ``WinMergeStringDiffs`` beyond the GoogleTest parity fixtures.
final class WinMergeStringDiffsLaneTests: XCTestCase {
    private typealias Diffs = WinMergeStringDiffs
    private typealias Options = WinMergeStringDiffs.Options

    private static let wordLevel = Options(
        breakType: .whitespace,
        characterLevel: false,
        alignmentTimeout: nil
    )

    // MARK: Constants

    func testPublishedWinMergeConstants() {
        XCTAssertEqual(Diffs.defaultBreakCharacters, ".,:;?[](){}<=>`'!\"#$%&^~\\|@+-*/")
        XCTAssertEqual(Diffs.builtInBreakCharacters, ",.;:")
        XCTAssertEqual(Diffs.maximumAlignedWordCount, 20_480)
        XCTAssertEqual(Diffs.alignmentClockCheckInterval, 100_000)
        XCTAssertEqual(Options.winMergeAlignmentTimeout, .milliseconds(500))
        XCTAssertEqual(Diffs.Operation.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(Diffs.EndOfLineMode.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(Diffs.BreakType.allCases.map(\.rawValue), [0, 1])
    }

    func testNegativeWorkUnitCapClampsToZero() {
        XCTAssertEqual(Options(maximumAlignmentWorkUnits: -5).maximumAlignmentWorkUnits, 0)
        XCTAssertEqual(Options(maximumAlignmentWorkUnits: 7).maximumAlignmentWorkUnits, 7)
    }

    func testAdapterPassesThroughEndOfLineAndBudgets() {
        let options = Options(
            IntraLineDifferenceOptions(wordBreakMode: .whitespace),
            endOfLineMode: .asSpace,
            alignmentTimeout: nil,
            maximumAlignmentWorkUnits: 42
        )
        XCTAssertEqual(options.breakType, .whitespace)
        XCTAssertEqual(options.endOfLineMode, .asSpace)
        XCTAssertNil(options.alignmentTimeout)
        XCTAssertEqual(options.maximumAlignmentWorkUnits, 42)
        XCTAssertTrue(options.caseSensitive)
    }

    // MARK: Trivial inputs

    func testIdenticalAndEmptyInputsHaveNoDiffs() {
        XCTAssertTrue(Diffs.computeWordDiffs("", "").isEmpty)
        XCTAssertTrue(Diffs.computeWordDiffs("same text", "same text").isEmpty)
        XCTAssertTrue(Diffs.computeWordDiffs("same text", "same text", options: Self.wordLevel).isEmpty)
        XCTAssertTrue(Diffs.computeWordDiffs(["x y", "x y", "x y"], options: Self.wordLevel).isEmpty)
    }

    func testEmptyFirstSideIsZeroLengthInsertionPoint() {
        let diffs = Diffs.computeWordDiffs("", "abc", options: Self.wordLevel)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].utf16Range(side: 0), NSRange(location: 0, length: 0))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 0, length: 3))
        XCTAssertNil(diffs[0].operation)
        XCTAssertEqual(diffs[0].paneCount, 2)
    }

    func testDeletionReportsZeroLengthSecondSide() {
        let diffs = Diffs.computeWordDiffs("abc def ghi", "abc ghi", options: Self.wordLevel)
        XCTAssertEqual(diffs.map(\.begin), [[4, 4, 0]])
        XCTAssertEqual(diffs.map(\.end), [[7, 3, 0]])
        XCTAssertEqual(diffs[0].utf16Range(side: 0), NSRange(location: 4, length: 4))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 4, length: 0))
    }

    // MARK: Difference ranges

    func testDifferenceRangeBounds() {
        let diff = Diffs.Difference(begin: [-1, 2, 5], end: [-1, 4, 4], operation: .diff)
        XCTAssertEqual(diff.paneCount, 3)
        XCTAssertNil(diff.utf16Range(side: 0), "negative begin marks an absent side")
        XCTAssertEqual(diff.utf16Range(side: 1), NSRange(location: 2, length: 3))
        XCTAssertEqual(diff.utf16Range(side: 2), NSRange(location: 5, length: 0))
        XCTAssertNil(diff.utf16Range(side: 3))
        XCTAssertNil(diff.utf16Range(side: -1))

        let twoWay = Diffs.Difference(begin: [0, 0, 0], end: [0, 0, 0], operation: nil, paneCount: 2)
        XCTAssertNil(twoWay.utf16Range(side: 2))
    }

    // MARK: Break characters

    func testNonLatin1UncasedUnitsBreakEvenInWhitespaceMode() {
        // isWordBreak: units >= U+0100 that are not upper/lowercase letters or digits always break.
        let cjk = Diffs.computeWordDiffs("日本語", "日本人", options: Self.wordLevel)
        XCTAssertEqual(cjk.map(\.begin), [[2, 2, 0]])
        XCTAssertEqual(cjk.map(\.end), [[2, 2, 0]])

        // Cased letters above U+00FF (U+0100 Ā) do not break.
        let cased = Diffs.computeWordDiffs("\u{100}\u{100}a", "\u{100}\u{100}b", options: Self.wordLevel)
        XCTAssertEqual(cased.map(\.begin), [[0, 0, 0]])
        XCTAssertEqual(cased.map(\.end), [[2, 2, 0]])
    }

    func testNulAlwaysBreaksInPunctuationMode() {
        // tcschr(BreakChars, 0) matches the terminator, so NUL breaks even with no break chars.
        let punctuation = Options(
            breakType: .whitespaceOrBreakCharacters,
            breakCharacters: "",
            characterLevel: false,
            alignmentTimeout: nil
        )
        let split = Diffs.computeWordDiffs("a\u{0}b", "a\u{0}c", options: punctuation)
        XCTAssertEqual(split.map(\.begin), [[2, 2, 0]])
        XCTAssertEqual(split.map(\.end), [[2, 2, 0]])

        // Whitespace-only mode never consults the break list for Latin-1 units.
        let whole = Diffs.computeWordDiffs("a\u{0}b", "a\u{0}c", options: Self.wordLevel)
        XCTAssertEqual(whole.map(\.begin), [[0, 0, 0]])
        XCTAssertEqual(whole.map(\.end), [[2, 2, 0]])
    }

    func testBreakTypeWhitespaceKeepsPunctuationInsideWord() {
        let diffs = Diffs.computeWordDiffs("a.b", "a.c", options: Self.wordLevel)
        XCTAssertEqual(diffs.map(\.begin), [[0, 0, 0]])
        XCTAssertEqual(diffs.map(\.end), [[2, 2, 0]])
    }

    func testCustomBreakCharactersReplaceDefaultList() {
        let semicolonOnly = Options(
            breakType: .whitespaceOrBreakCharacters,
            breakCharacters: ";",
            characterLevel: false,
            alignmentTimeout: nil
        )
        let split = Diffs.computeWordDiffs("a;b", "a;c", options: semicolonOnly)
        XCTAssertEqual(split.map(\.begin), [[2, 2, 0]])
        XCTAssertEqual(split.map(\.end), [[2, 2, 0]])

        // "." is not in the custom list, so "a.b" stays one word.
        let whole = Diffs.computeWordDiffs("a.b", "a.c", options: semicolonOnly)
        XCTAssertEqual(whole.map(\.begin), [[0, 0, 0]])
        XCTAssertEqual(whole.map(\.end), [[2, 2, 0]])
    }

    // MARK: Case and numbers

    func testCaseInsensitiveGreekAndAscii() {
        let insensitive = Options(caseSensitive: false, alignmentTimeout: nil)
        XCTAssertTrue(Diffs.computeWordDiffs("ΑΒΓ Hello", "αβγ hELLO", options: insensitive).isEmpty)
        XCTAssertEqual(Diffs.computeWordDiffs("ΑΒΓ", "αβγ", options: Options()).count, 1)
    }

    func testNumbersCountWhenNotIgnored() {
        let inWord = Diffs.computeWordDiffs("v12", "v345", options: Self.wordLevel)
        XCTAssertEqual(inWord.map(\.begin), [[0, 0, 0]])
        XCTAssertEqual(inWord.map(\.end), [[2, 3, 0]])
        let standalone = Diffs.computeWordDiffs("abc 123 def", "abc 4567 def", options: Self.wordLevel)
        XCTAssertEqual(standalone.map(\.begin), [[4, 4, 0]])
        XCTAssertEqual(standalone.map(\.end), [[6, 7, 0]])
    }

    // MARK: UTF-16 handling

    func testCharacterLevelKeepsSurrogatePairTogether() {
        let diffs = Diffs.computeWordDiffs("a\u{1F600}", "a\u{1F601}")
        XCTAssertEqual(diffs.count, 1)
        let range = diffs[0].utf16Range(side: 0)
        XCTAssertEqual(range, NSRange(location: 1, length: 2))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 1, length: 2))
    }

    func testRawLoneSurrogatesAreOneUnitWords() {
        // A lone surrogate (>= U+0100, not a cased letter or digit) is a one-unit break word in
        // both break modes, so only that unit differs at word and character level.
        let first: [UInt16] = [0x61, 0xD800]
        let second: [UInt16] = [0x61, 0xDC00]
        for options in [Options(alignmentTimeout: nil), Self.wordLevel] {
            let diffs = Diffs.computeWordDiffs(utf16: [first, second], options: options)
            XCTAssertEqual(diffs.map(\.begin), [[1, 1, 0]], "characterLevel \(options.characterLevel)")
            XCTAssertEqual(diffs.map(\.end), [[1, 1, 0]], "characterLevel \(options.characterLevel)")
        }
    }

    // MARK: Alignment bounds

    /// `BuildWordDiffList` aligns only while `m_words.size() < 20480`, and `BuildWordsArray`
    /// prepends a dummy word, so 20_479 real words is the first count that falls back.
    func testWordCountCapBoundaryCountsDummyWord() {
        // "a " x 10_239 is 20_478 real words (+ dummy = 20_479): still aligned.
        let aligned = Diffs.computeWordDiffs(
            String(repeating: "a ", count: 10_239),
            String(repeating: "a ", count: 5_000) + "b " + String(repeating: "a ", count: 5_238),
            options: Self.wordLevel
        )
        XCTAssertEqual(aligned.map(\.begin), [[10_000, 10_000, 0]])
        XCTAssertEqual(aligned.map(\.end), [[10_000, 10_000, 0]])

        // One more word: 20_479 real words (+ dummy = 20_480) reaches the cap.
        let first = String(repeating: "a ", count: 10_239) + "a"
        let second = String(repeating: "a ", count: 5_000) + "b " + String(repeating: "a ", count: 5_238) + "a"
        let fallback = Diffs.computeWordDiffs(first, second, options: Self.wordLevel)
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback[0].utf16Range(side: 0), NSRange(location: 0, length: first.utf16.count))
        XCTAssertEqual(fallback[0].utf16Range(side: 1), NSRange(location: 0, length: second.utf16.count))
    }

    func testBelowWordCountCapAlignsSingleWord() {
        let first = String(repeating: "a ", count: 5_000)
        var secondWords = Array(repeating: "a", count: 5_000)
        secondWords[2_500] = "b"
        let second = secondWords.joined(separator: " ") + " "
        let diffs = Diffs.computeWordDiffs(first, second, options: Self.wordLevel)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].utf16Range(side: 0), NSRange(location: 5_000, length: 1))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 5_000, length: 1))
    }

    func testElapsedAlignmentTimeoutFallsBackToWholeLine() {
        // 500 fully different words need ~250_000 diagonal steps, so the clock is checked after
        // COUNTMAX (100_000) steps; a zero timeout has elapsed by then.
        let first = (0..<500).map { "a\($0)" }.joined(separator: " ")
        let second = (0..<500).map { "b\($0)" }.joined(separator: " ")
        let options = Options(breakType: .whitespace, characterLevel: false, alignmentTimeout: .zero)
        let diffs = Diffs.computeWordDiffs(first, second, options: options)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].utf16Range(side: 0), NSRange(location: 0, length: first.utf16.count))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 0, length: second.utf16.count))

        // Small inputs never reach a clock check, so even a zero timeout aligns them.
        let small = Diffs.computeWordDiffs("one two", "one three", options: options)
        XCTAssertEqual(small.map(\.begin), [[4, 4, 0]])
        XCTAssertEqual(small.map(\.end), [[6, 8, 0]])
    }

    func testZeroWorkUnitCapStillReturnsWholeLine() {
        let options = Options(
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil,
            maximumAlignmentWorkUnits: 0
        )
        let diffs = Diffs.computeWordDiffs("one two", "one three", options: options)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].utf16Range(side: 0), NSRange(location: 0, length: 7))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 0, length: 9))
    }

    // MARK: Three-way

    func testThreeWayWithEmptyFirstOrThirdPane() {
        let emptyFirst = Diffs.computeWordDiffs(["", "abc", "abd"], options: Self.wordLevel)
        XCTAssertEqual(emptyFirst, [Diffs.Difference(begin: [0, 0, 0], end: [-1, 2, 2], operation: nil)])
        XCTAssertEqual(emptyFirst[0].utf16Range(side: 0), NSRange(location: 0, length: 0))
        XCTAssertEqual(emptyFirst[0].utf16Range(side: 2), NSRange(location: 0, length: 3))

        let emptyThird = Diffs.computeWordDiffs(["abc", "abd", ""], options: Self.wordLevel)
        XCTAssertEqual(emptyThird, [Diffs.Difference(begin: [0, 0, 0], end: [2, 2, -1], operation: nil)])
        XCTAssertEqual(emptyThird[0].utf16Range(side: 2), NSRange(location: 0, length: 0))
    }

    func testThreeWayCaseInsensitiveOuterPanesMatch() {
        // Middle differs; outer panes differ only by case, so with case folding it is secondOnly.
        let insensitive = Options(
            caseSensitive: false,
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil
        )
        let diffs = Diffs.computeWordDiffs(["abc DEF ghi", "abc xyz ghi", "abc def ghi"], options: insensitive)
        XCTAssertEqual(diffs.map(\.operation), [.secondOnly])
        let sensitive = Diffs.computeWordDiffs(["abc DEF ghi", "abc xyz ghi", "abc def ghi"], options: Self.wordLevel)
        XCTAssertEqual(sensitive.map(\.operation), [.diff])
    }

    func testFullThreeWayForcesCompareAllWhitespace() {
        // stringdiffs.cpp passes whitespace 0 to both pairwise runs of a full three-way compare.
        let ignoreChanges = Options(
            whitespace: .ignoreChanges,
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil
        )
        let full = Diffs.computeWordDiffs(["a  b", "a b", "a b"], options: ignoreChanges)
        XCTAssertEqual(full, [Diffs.Difference(begin: [1, 1, 1], end: [2, 1, 1], operation: .firstOnly)])

        // The empty-pane paths keep the caller's whitespace option.
        XCTAssertTrue(Diffs.computeWordDiffs(["", "a  b", "a b"], options: ignoreChanges).isEmpty)
        let compareAll = Diffs.computeWordDiffs(["", "a  b", "a b"], options: Self.wordLevel)
        XCTAssertEqual(compareAll, [Diffs.Difference(begin: [0, 1, 1], end: [-1, 2, 1], operation: nil)])
    }

    func testThreeWayCharacterLevelNarrowsBothPairs() {
        let diffs = Diffs.computeWordDiffs(
            ["abc def", "abc dxf", "abc dxf"],
            options: Options(alignmentTimeout: nil)
        )
        XCTAssertEqual(diffs, [Diffs.Difference(begin: [5, 5, 5], end: [5, 5, 5], operation: .firstOnly)])
    }

    // MARK: Compare

    func testCompareSignsAndNormalization() {
        XCTAssertEqual(Diffs.compare("abc", "abc"), 0)
        XCTAssertEqual(Diffs.compare("a", "b"), 1)
        XCTAssertEqual(Diffs.compare("b", "a"), -1)
        XCTAssertEqual(Diffs.compare("ABC", "abc", caseSensitive: false), 0)
        XCTAssertNotEqual(Diffs.compare("ABC", "abc"), 0)
        XCTAssertEqual(Diffs.compare("a  b", "a\tb", whitespace: .ignoreChanges), 0)
        XCTAssertEqual(Diffs.compare("a b", "ab", whitespace: .ignoreAll), 0)
        XCTAssertEqual(Diffs.compare("x\r\n", "x\n", endOfLineMode: .ignore), 0)
        XCTAssertNotEqual(Diffs.compare("x\r\n", "x\n"), 0)
    }

    // MARK: Workflow adapter

    func testWorkflowDeleteAndMissingSides() {
        let deleted = IntraLineDifferenceWorkflow.winMergeRangePairs(source: "abc def", comparison: "abc")
        XCTAssertEqual(deleted.map(\.kind), [.delete])
        XCTAssertEqual(deleted.map(\.sourceUTF16Range), [NSRange(location: 3, length: 4)])
        XCTAssertEqual(deleted.map(\.comparisonUTF16Range), [NSRange(location: 3, length: 0)])

        let missingComparison = IntraLineDifferenceWorkflow.winMergeRangePairs(source: "abc", comparison: nil)
        XCTAssertEqual(missingComparison.map(\.kind), [.delete])
        XCTAssertEqual(missingComparison.map(\.sourceUTF16Range), [NSRange(location: 0, length: 3)])
        XCTAssertEqual(missingComparison.map(\.comparisonUTF16Range), [nil])

        XCTAssertTrue(IntraLineDifferenceWorkflow.winMergeRangePairs(source: nil, comparison: nil).isEmpty)
        XCTAssertTrue(IntraLineDifferenceWorkflow.winMergeRangePairs(source: "x", comparison: "x").isEmpty)
    }

    func testWorkflowOrdinalsAreSequential() {
        let pairs = IntraLineDifferenceWorkflow.winMergeRangePairs(
            source: "one two three four",
            comparison: "ONE two THREE four"
        )
        XCTAssertEqual(pairs.map(\.ordinal), [0, 1])
        XCTAssertEqual(pairs.map(\.sourceUTF16Range), [NSRange(location: 0, length: 3), NSRange(location: 8, length: 5)])

        let ignoringCase = IntraLineDifferenceWorkflow.winMergeRangePairs(
            source: "one two three four",
            comparison: "ONE two THREE four",
            options: IntraLineDifferenceOptions(ignoreCase: true)
        )
        XCTAssertTrue(ignoringCase.isEmpty)
    }

    func testWorkflowDocumentedDefaults() {
        // IntraLineDifferenceOptions.punctuation has no WinMerge counterpart; the adapter drops it.
        XCTAssertEqual(
            Options(IntraLineDifferenceOptions(punctuation: .ignoreAll)),
            Options(IntraLineDifferenceOptions())
        )
        // winMergeRangePairs defaults to strict EOL, so CRLF vs LF is a difference.
        let strict = IntraLineDifferenceWorkflow.winMergeRangePairs(source: "abc\r\n", comparison: "abc\n")
        XCTAssertEqual(strict.map(\.sourceUTF16Range), [NSRange(location: 3, length: 2)])
        XCTAssertEqual(strict.map(\.comparisonUTF16Range), [NSRange(location: 3, length: 1)])
        XCTAssertTrue(
            IntraLineDifferenceWorkflow.winMergeRangePairs(
                source: "abc\r\n",
                comparison: "abc\n",
                endOfLineMode: .ignore
            ).isEmpty
        )
    }
}
