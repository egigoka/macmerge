import Foundation
import MacMergeCore
import XCTest

final class WinMergeStringDiffsTests: XCTestCase {
    private typealias Diffs = WinMergeStringDiffs
    private typealias Options = WinMergeStringDiffs.Options

    private static let wordLevel = Options(
        breakType: .whitespace,
        characterLevel: false,
        alignmentTimeout: nil
    )

    // MARK: WinMerge GoogleTest parity

    func testWinMergeGoogleTestWordDiffCases() {
        // 111 ComputeWordDiffs calls in Testing/GoogleTest/StringDiffs/*.cpp, minus the FIXME'd
        // IgnoreAllWhitespace5 and 4 calls that only appear in comments. Update if upstream changes.
        XCTAssertEqual(WinMergeStringDiffsGoogleTestFixtures.wordDiffCases.count, 106)
        let names = WinMergeStringDiffsGoogleTestFixtures.wordDiffCases.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "fixture names must identify one call")
        for testCase in WinMergeStringDiffsGoogleTestFixtures.wordDiffCases {
            let diffs = Diffs.computeWordDiffs(
                testCase.first,
                testCase.second,
                options: testCase.options
            )
            XCTAssertEqual(diffs.count, testCase.count, testCase.name)
            for expected in testCase.expected {
                guard diffs.indices.contains(expected.index) else {
                    XCTFail("\(testCase.name): missing diff \(expected.index)")
                    continue
                }
                let diff = diffs[expected.index]
                let label = "\(testCase.name)[\(expected.index)]"
                if let value = expected.begin0 { XCTAssertEqual(diff.begin[0], value, label) }
                if let value = expected.end0 { XCTAssertEqual(diff.end[0], value, label) }
                if let value = expected.begin1 { XCTAssertEqual(diff.begin[1], value, label) }
                if let value = expected.end1 { XCTAssertEqual(diff.end[1], value, label) }
            }
        }
    }

    func testWinMergeGoogleTestCompareCases() {
        // Every strdiff::Compare EXPECT in Testing/GoogleTest/StringDiffs/*.cpp, in source order.
        XCTAssertEqual(WinMergeStringDiffsGoogleTestFixtures.compareCases.count, 57)
        for testCase in WinMergeStringDiffsGoogleTestFixtures.compareCases {
            let result = Diffs.compare(
                testCase.first,
                testCase.second,
                caseSensitive: testCase.caseSensitive,
                endOfLineMode: testCase.endOfLineMode,
                whitespace: testCase.whitespace,
                ignoreNumbers: testCase.ignoreNumbers
            )
            XCTAssertEqual(
                result,
                testCase.expected,
                "Compare(\(testCase.first.debugDescription), \(testCase.second.debugDescription))"
            )
        }
    }

    // MARK: Defaults and adapter

    func testDefaultOptionsMatchWinMergeShippedOptions() {
        for options in [Options(), Options.winMergeDefaults] {
            assertWinMergeShippedDefaults(options)
        }
    }

    private func assertWinMergeShippedDefaults(
        _ options: Options,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(options.caseSensitive, file: file, line: line)
        XCTAssertEqual(options.endOfLineMode, .strict, file: file, line: line)
        XCTAssertEqual(options.whitespace, .compareAll, file: file, line: line)
        XCTAssertFalse(options.ignoreNumbers, file: file, line: line)
        XCTAssertEqual(options.breakType, .whitespaceOrBreakCharacters, file: file, line: line)
        XCTAssertEqual(options.breakCharacters, Diffs.defaultBreakCharacters, file: file, line: line)
        XCTAssertTrue(options.characterLevel, file: file, line: line)
        XCTAssertEqual(options.alignmentTimeout, .milliseconds(500), file: file, line: line)
        XCTAssertNil(options.maximumAlignmentWorkUnits, file: file, line: line)
    }

    func testDefaultOptionsProduceCharacterRangesSplitOnPunctuation() {
        // OPT_BREAK_TYPE = 1 splits "a.b" into "a", ".", "b": two diffs around the equal ".".
        // A whitespace-only split would give one word and one diff [0, 2].
        let diffs = Diffs.computeWordDiffs("a.b", "x.y")
        XCTAssertEqual(diffs.map(\.begin), [[0, 0, 0], [2, 2, 0]])
        XCTAssertEqual(diffs.map(\.end), [[0, 0, 0], [2, 2, 0]])

        let whitespaceOnly = Diffs.computeWordDiffs(
            "a.b",
            "x.y",
            options: Options(breakType: .whitespace, alignmentTimeout: nil)
        )
        XCTAssertEqual(whitespaceOnly.map(\.begin), [[0, 0, 0]])
        XCTAssertEqual(whitespaceOnly.map(\.end), [[2, 2, 0]])
    }

    func testAdapterMapsEmptyBreakCharactersToWinMergeDefault() {
        let empty = Options(
            IntraLineDifferenceOptions(wordBreakMode: .whitespaceOrCustomCharacters)
        )
        XCTAssertEqual(empty.breakCharacters, Diffs.defaultBreakCharacters)
        XCTAssertEqual(empty.breakType, .whitespaceOrBreakCharacters)
        XCTAssertFalse(empty.characterLevel)

        let custom = Options(
            IntraLineDifferenceOptions(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters,
                wordBreakCharacters: ";",
                whitespace: .ignoreAll,
                ignoreCase: true,
                ignoreNumbers: true
            )
        )
        XCTAssertEqual(custom.breakCharacters, ";")
        XCTAssertTrue(custom.characterLevel)
        XCTAssertFalse(custom.caseSensitive)
        XCTAssertEqual(custom.whitespace, .ignoreAll)
        XCTAssertTrue(custom.ignoreNumbers)

        // With MacMerge's default (empty) preference, punctuation still breaks words.
        let diffs = Diffs.computeWordDiffs("a.b", "a.c", options: empty)
        XCTAssertEqual(diffs.map(\.begin), [[2, 2, 0]])
        XCTAssertEqual(diffs.map(\.end), [[2, 2, 0]])
    }

    // MARK: Alignment timeout

    func testLongFullyDifferentLineKeepsPerWordDiffs() {
        let first = (0..<2000).map { "a\($0)" }.joined(separator: " ")
        let second = (0..<2000).map { "b\($0)" }.joined(separator: " ")
        let diffs = Diffs.computeWordDiffs(first, second, options: Self.wordLevel)
        XCTAssertEqual(diffs.count, 2000)
        XCTAssertEqual(diffs.first?.utf16Range(side: 0), NSRange(location: 0, length: 2))
        XCTAssertEqual(diffs.first?.utf16Range(side: 1), NSRange(location: 0, length: 2))
    }

    func testWorkUnitCapFallsBackToWholeLineDifference() {
        let first = (0..<200).map { "a\($0)" }.joined(separator: " ")
        let second = (0..<200).map { "b\($0)" }.joined(separator: " ")
        let options = Options(
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil,
            maximumAlignmentWorkUnits: 10
        )
        let diffs = Diffs.computeWordDiffs(first, second, options: options)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs.first?.utf16Range(side: 0), NSRange(location: 0, length: first.utf16.count))
        XCTAssertEqual(
            diffs.first?.utf16Range(side: 1),
            NSRange(location: 0, length: second.utf16.count)
        )
    }

    // MARK: Ranges

    func testTwoWayResultHasNoThirdSideRange() {
        let diffs = Diffs.computeWordDiffs("abc def", "abc xyz", options: Self.wordLevel)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].paneCount, 2)
        XCTAssertEqual(diffs[0].utf16Range(side: 0), NSRange(location: 4, length: 3))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 4, length: 3))
        XCTAssertNil(diffs[0].utf16Range(side: 2))
        XCTAssertNil(diffs[0].utf16Range(side: -1))
    }

    func testInsertionReportsZeroLengthSide() {
        let diffs = Diffs.computeWordDiffs("abc ghi", "abc def ghi", options: Self.wordLevel)
        XCTAssertEqual(diffs.map(\.begin), [[4, 4, 0]])
        XCTAssertEqual(diffs.map(\.end), [[3, 7, 0]])
        XCTAssertEqual(diffs[0].utf16Range(side: 0), NSRange(location: 4, length: 0))
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 4, length: 4))
    }

    // MARK: Modes

    func testCaseInsensitiveUsesSimpleLowercaseForDottedCapitalI() {
        let insensitive = Options(caseSensitive: false, alignmentTimeout: nil)
        XCTAssertTrue(Diffs.computeWordDiffs("\u{130}x", "ix", options: insensitive).isEmpty)
        XCTAssertEqual(Diffs.computeWordDiffs("\u{130}x", "ix", options: Options()).count, 1)
    }

    func testIgnoreNumbersTreatsLatin1SuperscriptsAsDigits() {
        let options = Options(
            ignoreNumbers: true,
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil
        )
        XCTAssertTrue(Diffs.computeWordDiffs("x \u{B2} y", "x 7 y", options: options).isEmpty)
        XCTAssertTrue(Diffs.computeWordDiffs("x\u{B3}", "x\u{B9}", options: options).isEmpty)
        XCTAssertEqual(Diffs.computeWordDiffs("x \u{B2} y", "x 7 y", options: Self.wordLevel).count, 1)
    }

    func testIgnoreNumbersSkipsDigitRunsInsideWords() {
        let options = Options(
            ignoreNumbers: true,
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil
        )
        XCTAssertTrue(Diffs.computeWordDiffs("abc 123 def", "abc 4567 def", options: options).isEmpty)
        XCTAssertTrue(Diffs.computeWordDiffs("v12", "v345", options: options).isEmpty)
    }

    func testEndOfLineModes() {
        let strict = Options(breakType: .whitespace, characterLevel: false, alignmentTimeout: nil)
        let strictDiffs = Diffs.computeWordDiffs("abc\r\n", "abc\n", options: strict)
        XCTAssertEqual(strictDiffs.map(\.begin), [[3, 3, 0]])
        XCTAssertEqual(strictDiffs.map(\.end), [[4, 3, 0]])

        let ignore = Options(
            endOfLineMode: .ignore,
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil
        )
        XCTAssertTrue(Diffs.computeWordDiffs("abc\r\n", "abc\n", options: ignore).isEmpty)

        let asSpace = Options(
            endOfLineMode: .asSpace,
            breakType: .whitespace,
            characterLevel: false,
            alignmentTimeout: nil
        )
        XCTAssertTrue(Diffs.computeWordDiffs("abc\r\ndef", "abc\ndef", options: asSpace).isEmpty)
        XCTAssertTrue(Diffs.computeWordDiffs("abc\r\ndef", "abc def", options: asSpace).isEmpty)
        XCTAssertEqual(Diffs.computeWordDiffs("abc\r\ndef", "abc def", options: strict).count, 1)
    }

    func testWhitespaceModes() {
        func options(_ whitespace: WhitespaceComparison) -> Options {
            Options(
                whitespace: whitespace,
                breakType: .whitespace,
                characterLevel: false,
                alignmentTimeout: nil
            )
        }
        let compareAll = Diffs.computeWordDiffs("a  b", "a b", options: options(.compareAll))
        XCTAssertEqual(compareAll.map(\.begin), [[1, 1, 0]])
        XCTAssertEqual(compareAll.map(\.end), [[2, 1, 0]])
        XCTAssertTrue(Diffs.computeWordDiffs("a  b", "a\tb", options: options(.ignoreChanges)).isEmpty)
        // "a", " ", "b" against "ab": the change and the two deletions coalesce into one diff.
        let joined = Diffs.computeWordDiffs("a b", "ab", options: options(.ignoreChanges))
        XCTAssertEqual(joined.map(\.begin), [[0, 0, 0]])
        XCTAssertEqual(joined.map(\.end), [[2, 1, 0]])
        XCTAssertTrue(Diffs.computeWordDiffs("a b ", "a  b", options: options(.ignoreAll)).isEmpty)
    }

    // MARK: Three-way

    func testThreeWayOperations() {
        let options = Self.wordLevel
        let firstOnly = Diffs.computeWordDiffs(["abc def ghi", "abc xyz ghi", "abc xyz ghi"], options: options)
        XCTAssertEqual(firstOnly, [Diffs.Difference(begin: [4, 4, 4], end: [6, 6, 6], operation: .firstOnly)])

        let thirdOnly = Diffs.computeWordDiffs(["abc xyz ghi", "abc xyz ghi", "abc def ghi"], options: options)
        XCTAssertEqual(thirdOnly, [Diffs.Difference(begin: [4, 4, 4], end: [6, 6, 6], operation: .thirdOnly)])

        let secondOnly = Diffs.computeWordDiffs(["abc def ghi", "abc xyz ghi", "abc def ghi"], options: options)
        XCTAssertEqual(secondOnly, [Diffs.Difference(begin: [4, 4, 4], end: [6, 6, 6], operation: .secondOnly)])

        let conflict = Diffs.computeWordDiffs(["abc def ghi", "abc xyz ghi", "abc uvw ghi"], options: options)
        XCTAssertEqual(conflict, [Diffs.Difference(begin: [4, 4, 4], end: [6, 6, 6], operation: .diff)])
        XCTAssertEqual(conflict[0].paneCount, 3)
        XCTAssertEqual(conflict[0].utf16Range(side: 2), NSRange(location: 4, length: 3))
    }

    func testThreeWayWithEmptyMiddlePaneComparesOuterPanes() {
        let diffs = Diffs.computeWordDiffs(["abc", "", "abd"], options: Self.wordLevel)
        XCTAssertEqual(diffs, [Diffs.Difference(begin: [0, 0, 0], end: [2, -1, 2], operation: nil)])
        XCTAssertEqual(diffs[0].utf16Range(side: 1), NSRange(location: 0, length: 0))
    }

    // MARK: Workflow entry point

    func testWorkflowWinMergeRangePairs() {
        let wordPairs = IntraLineDifferenceWorkflow.winMergeRangePairs(
            source: "let value = 1",
            comparison: "let total = 1"
        )
        XCTAssertEqual(
            wordPairs,
            [
                IntraLineDifferenceRangePair(
                    ordinal: 0,
                    kind: .replace,
                    sourceUTF16Range: NSRange(location: 4, length: 5),
                    comparisonUTF16Range: NSRange(location: 4, length: 5)
                )
            ]
        )

        let characterPairs = IntraLineDifferenceWorkflow.winMergeRangePairs(
            source: "foo.bar",
            comparison: "foo.baz",
            options: IntraLineDifferenceOptions(
                granularity: .character,
                wordBreakMode: .whitespaceOrCustomCharacters
            )
        )
        XCTAssertEqual(characterPairs.map(\.sourceUTF16Range), [NSRange(location: 6, length: 1)])
        XCTAssertEqual(characterPairs.map(\.kind), [.replace])

        let inserted = IntraLineDifferenceWorkflow.winMergeRangePairs(
            source: "abc",
            comparison: "abc def"
        )
        XCTAssertEqual(inserted.map(\.kind), [.insert])
        XCTAssertEqual(inserted.map(\.sourceUTF16Range), [NSRange(location: 3, length: 0)])
        XCTAssertEqual(inserted.map(\.comparisonUTF16Range), [NSRange(location: 3, length: 4)])

        let ghost = IntraLineDifferenceWorkflow.winMergeRangePairs(source: nil, comparison: "abc")
        XCTAssertEqual(
            ghost,
            [
                IntraLineDifferenceRangePair(
                    ordinal: 0,
                    kind: .insert,
                    sourceUTF16Range: nil,
                    comparisonUTF16Range: NSRange(location: 0, length: 3)
                )
            ]
        )
    }
}
