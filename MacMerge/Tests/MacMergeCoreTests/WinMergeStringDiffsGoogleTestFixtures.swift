import MacMergeCore

// Cases transcribed mechanically from WinMerge's GoogleTest suite in
// Testing/GoogleTest/StringDiffs/*.cpp (stringdiffs_test, _adds, _bugs, _bytelevel).
// Each case keeps the C++ arguments of `strdiff::ComputeWordDiffs` and the break characters set
// by `strdiff::Init()` (",.;:") or `strdiff::SetBreakChars`. Expectations are WinMerge's own
// `EXPECT_EQ` values; checks guarded by `diffs.size() >= n` beyond the asserted count are
// unreachable in WinMerge and omitted, as is IgnoreAllWhitespace5 (its expectation is
// commented out as FIXME upstream).
struct WinMergeStringDiffsGoogleTestCase {
    struct Expected {
        let index: Int
        let begin0: Int?
        let end0: Int?
        let begin1: Int?
        let end1: Int?
    }

    let name: String
    let first: String
    let second: String
    let options: WinMergeStringDiffs.Options
    let count: Int
    let expected: [Expected]
}

struct WinMergeStringDiffsGoogleTestCompareCase {
    let first: String
    let second: String
    let caseSensitive: Bool
    let endOfLineMode: WinMergeStringDiffs.EndOfLineMode
    let whitespace: WhitespaceComparison
    let ignoreNumbers: Bool
    let expected: Int
}

private func makeCase(
    _ name: String,
    _ first: String,
    _ second: String,
    caseSensitive: Bool,
    eol: WinMergeStringDiffs.EndOfLineMode,
    whitespace: WhitespaceComparison,
    ignoreNumbers: Bool,
    breakType: WinMergeStringDiffs.BreakType,
    characterLevel: Bool,
    breakCharacters: String,
    count: Int,
    expected: [WinMergeStringDiffsGoogleTestCase.Expected]
) -> WinMergeStringDiffsGoogleTestCase {
    WinMergeStringDiffsGoogleTestCase(
        name: name,
        first: first,
        second: second,
        options: WinMergeStringDiffs.Options(
            caseSensitive: caseSensitive,
            endOfLineMode: eol,
            whitespace: whitespace,
            ignoreNumbers: ignoreNumbers,
            breakType: breakType,
            breakCharacters: breakCharacters,
            characterLevel: characterLevel,
            alignmentTimeout: nil
        ),
        count: count,
        expected: expected
    )
}

private func makeExpected(
    _ index: Int,
    _ begin0: Int?,
    _ end0: Int?,
    _ begin1: Int?,
    _ end1: Int?
) -> WinMergeStringDiffsGoogleTestCase.Expected {
    WinMergeStringDiffsGoogleTestCase.Expected(
        index: index,
        begin0: begin0,
        end0: end0,
        begin1: begin1,
        end1: end1
    )
}

private func makeCompareCase(
    _ first: String,
    _ second: String,
    _ caseSensitive: Bool,
    _ endOfLineMode: WinMergeStringDiffs.EndOfLineMode,
    _ whitespace: WhitespaceComparison,
    _ ignoreNumbers: Bool,
    _ expected: Int
) -> WinMergeStringDiffsGoogleTestCompareCase {
    WinMergeStringDiffsGoogleTestCompareCase(
        first: first,
        second: second,
        caseSensitive: caseSensitive,
        endOfLineMode: endOfLineMode,
        whitespace: whitespace,
        ignoreNumbers: ignoreNumbers,
        expected: expected
    )
}

enum WinMergeStringDiffsGoogleTestFixtures {
    static let wordDiffCases: [WinMergeStringDiffsGoogleTestCase] = [
        makeCase(
            "stringdiffs_test/EmptyBoth",
            "",
            "",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/EmptyFirst",
            "",
            "abcde",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/EmptySecond",
            "abcde",
            "",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/Default1",
            "abcde",
            "abcde",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/DefaultDiffererentLen",
            "abcdef",
            "abcde",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/DefaultWhitespaceEnd",
            "abcde ",
            "abcde",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/Caseignore1",
            "abcde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/CaseignoreCase1",
            "aBcde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreWhitespace1",
            "aBcde ",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreWhitespace2",
            "aBcde",
            " abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreWhitespace3",
            "abcde abcde",
            "abcde abcde",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreWhitespace4",
            " abcde abcde",
            "  abcde abcde",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreWhitespace5",
            " abcde abcde",
            "\u{9}abcde abcde",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreWhitespace6",
            " abcde abcde",
            "abcde\u{9}abcde",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreWhitespace7",
            "abcde abcde",
            "abcde\u{9}abcde",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreAllWhitespace1",
            "abcde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .ignoreAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreAllWhitespace2",
            " abcde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .ignoreAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreAllWhitespace3",
            "\u{9}abcde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .ignoreAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreAllWhitespace4",
            " abcde",
            "  abcde",
            caseSensitive: true, eol: .strict, whitespace: .ignoreAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreAllWhitespace6",
            "abcde abcde",
            "abcde\u{9}abcde",
            caseSensitive: true, eol: .strict, whitespace: .ignoreAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreAllWhitespace7",
            "abcde\u{9}abcde",
            "abcde\u{9}abcde",
            caseSensitive: true, eol: .strict, whitespace: .ignoreAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/WordBreak2Words1",
            "aBcde fghij",
            "abcde fghij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 4, 0, 4)]
        ),
        makeCase(
            "stringdiffs_test/WordBreak2Words2",
            "abcde fghij",
            "abcde fGhij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/WordBreak2Words3",
            "abcde fghij",
            "ABcde fGhij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/WordBreak3Words1",
            "abcde fgHIj klmno",
            "abcde fghij klmno",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/WordBreak3Words2",
            "abcde fghij klmno",
            "abcde fGHij klmno",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/WordBreak3Words3",
            "abcDE fGHij klmno",
            "abcde fghij klmno",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/WordBreak3Words4",
            "abcde fghij klmno",
            "abcDE fGHij klmno",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/WordBreak3Words5",
            "abcde fghij KLmno",
            "abcDE fghij klmno",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 12, 16, 12, 16)]
        ),
        makeCase(
            "stringdiffs_test/PunctBreak2Words1",
            "abcde,fghij",
            "ABcde,fghij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 4, 0, 4)]
        ),
        makeCase(
            "stringdiffs_test/PunctBreak2Words2",
            "Abcde,fghij",
            "abcde,fghij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 4, 0, 4)]
        ),
        makeCase(
            "stringdiffs_test/PunctBreak2Words3",
            "Abcde,fghij",
            "abcde,fGHij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/PunctBreak3Words1",
            "Abcde,fghij,klmno",
            "abcde,fghij,klmno",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 4, 0, 4)]
        ),
        makeCase(
            "stringdiffs_test/PunctBreak3Words2",
            "Abcde,fghij,klmno",
            "abcde,fGHij,klmno",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 6, 10, 6, 10)]
        ),
        makeCase(
            "stringdiffs_test/PunctBreak3Words3",
            "Abcde,fghij,klmno",
            "abcde,fGHij,klmNO",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 6, 10, 6, 10), makeExpected(2, 12, 16, 12, 16)]
        ),
        makeCase(
            "stringdiffs_test/PunctBreak3Words4",
            "Abcde,fghij,klmno",
            "abcde,fghij,klmNO",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 0, 4, 0, 4), makeExpected(1, 12, 16, 12, 16)]
        ),
        makeCase(
            "stringdiffs_test/CustomPunct1",
            "Abcde:fghij",
            "abcde:fghij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: "",
            count: 1, expected: [makeExpected(0, 0, 10, 0, 10)]
        ),
        makeCase(
            "stringdiffs_test/CustomPunct2",
            "Abcde,fghij",
            "abcde,fghij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: "",
            count: 1, expected: [makeExpected(0, 0, 10, 0, 10)]
        ),
        makeCase(
            "stringdiffs_test/CustomPunctBreak1",
            "Abcde:fghij",
            "abcde:fghij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ":",
            count: 1, expected: [makeExpected(0, 0, 4, 0, 4)]
        ),
        makeCase(
            "stringdiffs_test/CustomPunctBreak2",
            "Abcde,fghij",
            "abcde,fghij",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ";",
            count: 1, expected: [makeExpected(0, 0, 10, 0, 10)]
        ),
        makeCase(
            "stringdiffs_test/ByteLevel1",
            "abcde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/ByteLevel2",
            "aBcde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 1, 1, 1, 1)]
        ),
        makeCase(
            "stringdiffs_test/ByteLevel3",
            "aBCde",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 1, 2, 1, 2)]
        ),
        makeCase(
            "stringdiffs_test/ByteLevel4",
            "aBcde",
            "abCde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 1, 2, 1, 2)]
        ),
        makeCase(
            "stringdiffs_test/ByteLevel5",
            "aBcDe",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 1, 3, nil, nil)]
        ),
        makeCase(
            "stringdiffs_test/ByteLevel6",
            "aBcde",
            "abcDe",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 1, 3, 1, 3)]
        ),
        makeCase(
            "stringdiffs_test/ByteLevel7",
            "aBcdE",
            "abcde",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 1, 4, 1, 4)]
        ),
        makeCase(
            "stringdiffs_test/ByteLevel8",
            "aBcde",
            "abcdE",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 1, 4, 1, 4)]
        ),
        makeCase(
            "stringdiffs_test/IgnoreEOL1",
            "abc\u{D}\u{A}",
            "abc\u{A}",
            caseSensitive: true, eol: .ignore, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreEOL2",
            "abc\u{D}\u{A}",
            "abc\u{D}",
            caseSensitive: true, eol: .ignore, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreEOL3",
            "abc\u{D}\u{A}\u{D}\u{A}",
            "abc\u{A}\u{A}",
            caseSensitive: true, eol: .ignore, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreEOL4",
            "abc\u{D}\u{D}",
            "abc\u{A}\u{A}",
            caseSensitive: true, eol: .ignore, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreEOL5#1",
            "abc\u{D}\u{A}def\u{D}\u{A}",
            "abc\u{A}def\u{A}",
            caseSensitive: true, eol: .ignore, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreEOL5#2",
            "  abc  \u{D}\u{A}def\u{D}\u{A}  ",
            "  abc  \u{A}def\u{A}  ",
            caseSensitive: true, eol: .ignore, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreLineBreaks#1",
            "abc\u{D}\u{A}def\u{D}\u{A}",
            "abc\u{A}def\u{A}",
            caseSensitive: true, eol: .asSpace, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreLineBreaks#2",
            "  abc  \u{D}\u{A}def\u{D}\u{A}  ",
            "  abc  \u{A}def\u{A}  ",
            caseSensitive: true, eol: .asSpace, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreLineBreaks#3",
            "  abc  \u{D}\u{A}def\u{D}\u{A}  ",
            "  abc   def   ",
            caseSensitive: true, eol: .asSpace, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreLineBreaks#4",
            "  abc   def   ",
            "  abc  \u{A}def\u{A}  ",
            caseSensitive: true, eol: .asSpace, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreLineBreaks#5",
            "  abc   def   ",
            "  abc\u{A}def\u{A}  ",
            caseSensitive: true, eol: .asSpace, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreNumbers#1",
            "ab 1",
            "ab 2",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 3, 3, 3, 3)]
        ),
        makeCase(
            "stringdiffs_test/IgnoreNumbers#2",
            "ab 1",
            "ab 2",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: true, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreNumbers#3",
            "ab 1234",
            "ab 2",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: true, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 0, expected: []
        ),
        makeCase(
            "stringdiffs_test/IgnoreNumbers#4",
            "ab 12 34",
            "ab 2",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: true, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 5, 5, 4, 3)]
        ),
        makeCase(
            "stringdiffs_test/IgnoreNumbers#5",
            "ab 12 34",
            "ab 2 c",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: true, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 6, 7, 5, 5)]
        ),
        makeCase(
            "stringdiffs_test/IgnoreNumbers#6",
            "ab  12 34",
            "aB 2 c",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: true, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 7, 8, 5, 5)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddBeginFirst1",
            "abcdefgh",
            "1abcdefgh",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 7, 0, 8)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddBeginFirst2",
            "1abcdefgh",
            "abcdefgh",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 8, 0, 7)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddBeginFirstChar1",
            "abcdefgh",
            "1abcdefgh",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, -1, 0, 0)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddBeginFirstChar2",
            "1abcdefgh",
            "abcdefgh",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 0, 0, -1)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddEndFirst1",
            "abcdefgh",
            "abcdefgh1",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 7, 0, 8)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddEndFirst2",
            "abcdefgh1",
            "abcdefgh",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 8, 0, 7)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddEndFirstChar1",
            "abcdefgh",
            "abcdefgh1",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 8, 7, 8, 8)]
        ),
        makeCase(
            "stringdiffs_test_adds/AddEndFirstChar2",
            "abcdefgh1",
            "abcdefgh",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 8, 8, 8, 7)]
        ),
        makeCase(
            "stringdiffs_test_adds/ExchangeString1a",
            "N2130   _RobOk=_INT B_AND 512                   ;Roboter bereit",
            "N2040   _RobOk=_INT B_AND 'B1000000000'          ;Roboter bereit",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ".,;:()[]{}!@#\"$%^&*~+-=<>'/\\|",
            count: 2, expected: [makeExpected(0, 2, 3, 2, 3), makeExpected(1, 26, 28, 26, 38)]
        ),
        makeCase(
            "stringdiffs_test_adds/ExchangeString1b",
            "N2040   _RobOk=_INT B_AND 'B1000000000'          ;Roboter bereit",
            "N2130   _RobOk=_INT B_AND 512                   ;Roboter bereit",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ".,;:()[]{}!@#\"$%^&*~+-=<>'/\\|",
            count: 2, expected: [makeExpected(0, 2, 3, 2, 3), makeExpected(1, 26, 38, 26, 28)]
        ),
        makeCase(
            "stringdiffs_test_adds/ExchangeString2a",
            "N1960 IF(R2941==2) OR (R2941==203))",
            "N1830 IF((R2941==2)   OR (R2941==3)    ",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ".,;:()[]{}!@#\"$%^&*~+-=<>'/\\|",
            count: 4, expected: [makeExpected(0, 2, 3, 2, 3), makeExpected(1, 9, 8, 9, 9), makeExpected(2, 30, 31, 33, 32), makeExpected(3, 34, 34, 35, 38)]
        ),
        makeCase(
            "stringdiffs_test_adds/ExchangeString2b",
            "N1830 IF((R2941==2)   OR (R2941==3)    ",
            "N1960 IF(R2941==2) OR (R2941==203))",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ".,;:()[]{}!@#\"$%^&*~+-=<>'/\\|",
            count: 4, expected: [makeExpected(0, 2, 3, 2, 3), makeExpected(1, 9, 9, 9, 8), makeExpected(2, 33, 32, 30, 31), makeExpected(3, 35, 38, 34, 34)]
        ),
        makeCase(
            "stringdiffs_test_adds/RunThird",
            "(sizeof *new);",
            "sizeof(*newob));",
            caseSensitive: false, eol: .strict, whitespace: .ignoreChanges,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ".,;:()[]{}!@#\"$%^&*~+-=<>'/\\|",
            count: 1, expected: [makeExpected(0, 0, 11, 0, 13)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_1685466_1",
            "if (EnumResourceLanguages(hinstLang, RT_VERSION, MAKEINTRESOURCE(VS_VERSION_INFO), (ENUMRESLANGPROC)FindNextResLang, (LPARAM)&wLangID) == 0)",
            "if (EnumResourceLanguages(hinstLang, RT_VERSION, MAKEINTRESOURCE(VS_VERSION_INFO), FindNextResLang, (LPARAM)&wLangID) == 0)",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 83, 99, 83, 82)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_1685466_2",
            "if (EnumResourceLanguages(hinstLang, RT_VERSION, MAKEINTRESOURCE(VS_VERSION_INFO), (ENUMRESLANGPROC)FindNextResLang, (LPARAM)&wLangID) == 0)",
            "if (EnumResourceLanguages(hinstLang, RT_VERSION, MAKEINTRESOURCE(VS_VERSION_INFO), FindNextResLang, (LPARAM)&wLangID) == 0)",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 83, 114, 83, 97)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_1939279_1",
            "[overlay_oid_origin, overlay_oid_target], [nil, nil]",
            "[overlay_oid_origin, overlay_oid_target, origin_file_name, target_file_name], [nil, nil, \"origin.txt\"), \"target.txt\"]",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 39, 39, 39, 38)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_1939279_2",
            "[overlay_oid_origin, overlay_oid_target], [nil, nil]",
            "[overlay_oid_origin, overlay_oid_target, origin_file_name, target_file_name], [nil, nil, \"origin.txt\"), \"target.txt\"]",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 21, 39, 21, 38)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2022935",
            "N42=Import",
            "N42=Importuj",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 10, 9, 10, 11)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2638045",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php4",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 46, 0, 47)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2638045_2",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php4",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, 46, 0, 47)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2638045_3",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php4",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 47, 46, 47, 47)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2638045_4",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php",
            "LIB_PHP4_DIR=$(RPM_NAME)-$(RPM_VER)/usr/lib/php4",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: "/",
            count: 1, expected: [makeExpected(0, 44, 46, 44, 47)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2779834_1",
            "if (nDiff < m_diffs.size())",
            "if(nDiff < (int) m_diffs.size())",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 0, 1, 0, 7)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2779834_2",
            "if (nDiff < m_diffs.size())",
            "if(nDiff < (int) m_diffs.size())",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 2, 1, 2, 7)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2783185_1",
            "const string ManualFolder = \"Manual\";",
            "private const string ManualFolder = \"Manual\";",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, -1, 0, 7)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2783185_2",
            "const string ManualFolder = \"Manual\";",
            "private const string ManualFolder = \"Manual\";",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 1, expected: [makeExpected(0, 0, -1, 0, 7)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2791879_1",
            "abc def ghi jkl mno",
            "abc defx ghi jklx mno",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 7, 6, 7, 7), makeExpected(1, 15, 14, 16, 16)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2791879_2",
            "abc def ghi jkl mno",
            "abc defx ghi jklx mno",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 2, expected: [makeExpected(0, 4, 6, 4, 7), makeExpected(1, 12, 14, 13, 16)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2793479_1",
            "static int iTranslateBytesToBC (TCHAR* pd, BYTE* src, int srclen);",
            "static int iTranslateBytesToBC(TCHAR* pd, const BYTE* src, int srclen);",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: "() ",
            count: 2, expected: [makeExpected(0, 30, 30, 30, 29), makeExpected(1, 43, 42, 42, 47)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2793479_2",
            "static int iTranslateBytesToBC (TCHAR* pd, BYTE* src, int srclen);",
            "static int iTranslateBytesToBC(TCHAR* pd, const BYTE* src, int srclen);",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: "() ",
            count: 2, expected: [makeExpected(0, 30, 30, 30, 29), makeExpected(1, 43, 42, 42, 47)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2797067_1",
            "abc def ghi jkl mno pqr stu vwx yz",
            "abc def 123 ghi jkl mno pqr stu 456 vw x yz",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 8, 7, 8, 11), makeExpected(1, 28, 30, 32, 34), makeExpected(2, 32, 31, 36, 40)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2797067_2",
            "abc def ghi jkl mno pqr stu vwx yz",
            "abc def 123 ghi jkl mno pqr stu 456 vw x yz",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 8, 7, 8, 11), makeExpected(1, 28, 30, 32, 34), makeExpected(2, 32, 31, 36, 40)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2797067_3",
            "abc def ghi jkl mno pqr stu vwx yzr",
            "abc def 123ghi jkl mno pqr stu 456vwx yzrr",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: true, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 8, 7, 8, 10), makeExpected(1, 28, 27, 31, 33), makeExpected(2, 35, 34, 41, 41)]
        ),
        makeCase(
            "stringdiffs_test_bugs/Bug_2797067_4",
            "abc def ghi jkl mno pqr stu vwx yzr",
            "abc def 123ghi jkl mno pqr stu 456vwx yzrr",
            caseSensitive: false, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespace,
            characterLevel: false, breakCharacters: ",.;:",
            count: 3, expected: [makeExpected(0, 8, 10, 8, 13), makeExpected(1, 28, 30, 31, 36), makeExpected(2, 32, 34, 38, 41)]
        ),
        makeCase(
            "stringdiffs_test_bytelevel/ByteLevel19b3",
            "\u{9}\u{9}\u{9}\u{9}wsprintf(buf, _T(left=  %s,   %d,%d, right=  %s,   %d,%d ),",
            "\u{9}\u{9}\u{9}\u{9}\u{9}if (len2 < 50)",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ",;",
            count: 4, expected: []
        ),
        makeCase(
            "stringdiffs_test_bytelevel/ByteLevel19b2",
            "\u{9}while (1)",
            "\u{9}for (;;)",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ",;",
            count: 2, expected: [makeExpected(0, 1, 5, 1, 3), makeExpected(1, 7, 8, 5, 7)]
        ),
        makeCase(
            "stringdiffs_test_bytelevel/ByteLevel19b1",
            "abcdef,abccef,abcdef,",
            "abcdef,abcdef,abcdef,",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ",",
            count: 1, expected: [makeExpected(0, 10, 10, 10, 10)]
        ),
        makeCase(
            "stringdiffs_test_bytelevel/ByteLevel20c",
            "",
            "\u{9}\u{9}// remove empty records on both side",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ".,;:()[]{}!@#\"$%^&*~+-=<>'/\\|",
            count: 1, expected: [makeExpected(0, 0, -1, 0, 37)]
        ),
        makeCase(
            "stringdiffs_test_bytelevel/ByteLevel20a",
            ",;+ der abcdef,der,Thomas,abcdef,abcdef,;",
            ",;+ der abcdef,Thomas,accdgf,abcdef,-+",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ".,;:()[]{}!@#\"$%^&*~+-=<>'/\\|",
            count: 3, expected: [makeExpected(0, 15, 18, 15, 14), makeExpected(1, 27, 30, 23, 26), makeExpected(2, 40, 40, 36, 37)]
        ),
        makeCase(
            "stringdiffs_test_bytelevel/ByteLevel19a",
            "abcdef,abcdef,abcdef,",
            "abcdef,abccef,abcdef,",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: false, breakCharacters: ",",
            count: 1, expected: [makeExpected(0, 7, 12, 7, 12)]
        ),
        makeCase(
            "stringdiffs_test_bytelevel/ByteLevel19b",
            "abcdef,abccef,abcdef,",
            "abcdef,abcdef,abcdef,",
            caseSensitive: true, eol: .strict, whitespace: .compareAll,
            ignoreNumbers: false, breakType: .whitespaceOrBreakCharacters,
            characterLevel: true, breakCharacters: ",",
            count: 1, expected: [makeExpected(0, 10, 10, 10, 10)]
        )
    ]

    static let compareCases: [WinMergeStringDiffsGoogleTestCompareCase] = [
        makeCompareCase("abc", "abc", false, .strict, .compareAll, false, 0),
        makeCompareCase("ABC", "abc", false, .strict, .compareAll, false, 0),
        makeCompareCase("abc", "ABC", false, .strict, .compareAll, false, 0),
        makeCompareCase("aBC", "Bcd", false, .strict, .compareAll, false, 1),
        makeCompareCase("Bcd", "aBC", false, .strict, .compareAll, false, -1),
        makeCompareCase("abc def", "abc def", true, .strict, .ignoreChanges, false, 0),
        makeCompareCase("abc  def", "abc def", true, .strict, .ignoreChanges, false, 0),
        makeCompareCase("abc def", "abc  def", true, .strict, .ignoreChanges, false, 0),
        makeCompareCase("abc \u{9}def", "abc def", true, .strict, .ignoreChanges, false, 0),
        makeCompareCase("abc def", "abc \u{9}def", true, .strict, .ignoreChanges, false, 0),
        makeCompareCase("abc def", "abcdef", true, .strict, .ignoreChanges, false, 1),
        makeCompareCase("abcdef", "abc def", true, .strict, .ignoreChanges, false, -1),
        makeCompareCase("abc def", "abc def", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abc  def", "abc def", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abc def", "abc  def", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abc \u{9}def", "abc def", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abc def", "abc \u{9}def", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abc def", "abcdef", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abcdef", "abc def", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abc\u{9}def", "abcdef", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abcdef", "abc\u{9}def", true, .strict, .ignoreAll, false, 0),
        makeCompareCase("abcde", "abcdef", true, .strict, .ignoreAll, false, 1),
        makeCompareCase("abcdef", "abcde", true, .strict, .ignoreAll, false, -1),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{D}\u{A}", true, .ignore, .compareAll, false, 0),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{D}", true, .ignore, .compareAll, false, 0),
        makeCompareCase("abc\u{D}", "abc\u{D}\u{A}", true, .ignore, .compareAll, false, 0),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{A}", true, .ignore, .compareAll, false, 0),
        makeCompareCase("abc\u{A}", "abc\u{D}\u{A}", true, .ignore, .compareAll, false, 0),
        makeCompareCase("abc\u{A}", "abc\u{D}", true, .ignore, .compareAll, false, 0),
        makeCompareCase("abc\u{D}", "abc\u{A}", true, .ignore, .compareAll, false, 0),
        makeCompareCase("abc\u{D}\u{0}", "abc\u{D}\u{A}", true, .ignore, .compareAll, false, -1),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{D}\u{0}", true, .ignore, .compareAll, false, 1),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{D}\u{A}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{D}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{D}", "abc\u{D}\u{A}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{A}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{A}", "abc\u{D}\u{A}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{A}", "abc\u{D}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{D}", "abc\u{A}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{D}\u{0}", "abc\u{D}\u{A}", true, .asSpace, .compareAll, false, -1),
        makeCompareCase("abc\u{D}\u{A}", "abc\u{D}\u{0}", true, .asSpace, .compareAll, false, 1),
        makeCompareCase("abc\u{D}\u{A}", "abc ", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc ", "abc\u{D}", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc ", "abc ", true, .asSpace, .compareAll, false, 0),
        makeCompareCase("abc\u{D}\u{A}", "abc  ", true, .asSpace, .ignoreChanges, false, 0),
        makeCompareCase("abc  ", "abc\u{D}\u{A}", true, .asSpace, .ignoreChanges, false, 0),
        makeCompareCase("abc", "abc\u{D}\u{A}", true, .asSpace, .ignoreAll, false, 0),
        makeCompareCase("1a", "2a", true, .strict, .compareAll, true, 0),
        makeCompareCase("a123", "a234", true, .strict, .compareAll, true, 0),
        makeCompareCase("a", "123a", true, .strict, .compareAll, true, 0),
        makeCompareCase("123a", "a", true, .strict, .compareAll, true, 0),
        makeCompareCase("123", "", true, .strict, .compareAll, true, 0),
        makeCompareCase("", "123", true, .strict, .compareAll, true, 0),
        makeCompareCase("123a", "123b", true, .strict, .compareAll, true, 1),
        makeCompareCase("123b", "123a", true, .strict, .compareAll, true, -1),
        makeCompareCase("a123", "b123", true, .strict, .compareAll, true, 1),
        makeCompareCase("b123", "a123", true, .strict, .compareAll, true, -1)
    ]
}
