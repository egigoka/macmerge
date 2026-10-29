import Foundation

/// Faithful port of WinMerge `Src/stringdiffs.cpp` (`strdiff::ComputeWordDiffs` and
/// `strdiff::Compare`), including the three-way merge from `Src/Diff3.h`.
///
/// All coordinates are WinMerge's: 0-based UTF-16 code-unit offsets (`tchar_t` is `wchar_t` in
/// WinMerge's Unicode build) with **inclusive** `end` values, so an empty side is
/// `end == begin - 1`. Use ``Difference/utf16Range(side:)`` for `NSRange` values.
///
/// Ported behavior, bug-for-bug where observable:
/// - word splitting by whitespace, end-of-line, break characters, and digit runs (when numbers are
///   ignored), walking ICU character-break (grapheme) boundaries;
/// - WinMerge's `isWordBreak`: Latin-1 units break only when listed in the break characters
///   (and only in punctuation mode, NUL always matching the C terminator), while every unit at or
///   above U+0100 that is not an uppercase/lowercase letter or decimal digit is a one-unit word
///   break in both modes (so CJK ideographs and astral scalars split per grapheme);
/// - O(NP) Wu/Manber/Myers alignment with WinMerge's `+-`/`-+` to `!` folding and its
///   ignore-whitespace/ignore-number filtering;
/// - character granularity through `ComputeByteDiff`, including its stale forward break
///   iterator after whitespace skipping, its stale trailing glyph length, and its asymmetric
///   reverse whitespace handling;
/// - adjacent-difference coalescing and the three-way `Make3wayDiff` merge with the
///   whitespace option forced to "compare all", exactly as WinMerge does.
///
/// Alignment timeout: like `stringdiffs::onp`, alignment is abandoned (falling back to WinMerge's
/// whole-line difference) when ``Options/alignmentTimeout`` (default 500 ms, WinMerge's
/// `TimeoutMilliSeconds`) has elapsed, checked every `COUNTMAX` (100 000) diagonal steps. Callers
/// that need deterministic output set the timeout to `nil` and may cap work with
/// ``Options/maximumAlignmentWorkUnits`` instead.
///
/// Documented, deliberate divergences:
/// - Grapheme boundaries come from Swift's extended grapheme clusters, adjusted for WinMerge's
///   custom ICU rule that makes halfwidth voiced sound marks U+FF9E/U+FF9F start their own
///   cluster. Swift's newer rules (for example GB9c Indic conjuncts) may still differ from the
///   ICU 63 rule set WinMerge ships.
/// - Windows `GetStringTypeW`/`iswspace`/`iswdigit`/`towlower` tables are approximated with
///   Unicode general categories, White_Space, and Swift's full lowercase mapping when it yields a
///   single BMP scalar. Simple mappings hidden by the full mapping are special-cased
///   (U+0130 -> U+0069). `iswdigit` additionally reports the Latin-1 superscripts U+00B2, U+00B3,
///   and U+00B9 (CRT `_DIGIT`/`C1_DIGIT` behavior as documented for the MSVC classification
///   tables; not re-verified on Windows by this port). Other table differences are possible.
/// - C++ undefined behavior (negative glyph lengths reaching `memcmp`) is treated as a mismatch.
public enum WinMergeStringDiffs {
    /// WinMerge's shipped `OPT_BREAK_SEPARATORS` default (`Src/OptionsInit.cpp`).
    public static let defaultBreakCharacters = ".,:;?[](){}<=>`'!\"#$%&^~\\|@+-*/"
    /// `strdiff::BreakCharDefaults`, used before options are loaded.
    public static let builtInBreakCharacters = ",.;:"
    /// `BuildWordDiffList` only aligns when both word arrays are smaller than this (Win64).
    public static let maximumAlignedWordCount = 20_480

    public enum EndOfLineMode: Int, CaseIterable, Hashable, Sendable {
        case strict = 0
        case ignore = 1
        case asSpace = 2
    }

    public enum BreakType: Int, CaseIterable, Hashable, Sendable {
        /// `breakType == 0`: whitespace only.
        case whitespace = 0
        /// `breakType == 1`: whitespace or the configured break characters.
        case whitespaceOrBreakCharacters = 1
    }

    /// `OP_TYPE` from `Src/DiffList.h`; only three-way results carry one.
    public enum Operation: Int, CaseIterable, Hashable, Sendable {
        case none = 0
        case firstOnly
        case secondOnly
        case thirdOnly
        case diff
        case trivial
    }

    /// `stringdiffs::onp` checks the clock every `COUNTMAX` steps.
    public static let alignmentClockCheckInterval = 100_000

    /// Defaults match WinMerge's shipped options (`Src/OptionsInit.cpp`): case-sensitive,
    /// strict EOL, compare all whitespace, numbers compared, `OPT_BREAK_TYPE = 1` (whitespace or
    /// punctuation), `OPT_BREAK_SEPARATORS` break characters, and `OPT_BREAK_ON_WORDS = false`
    /// (character-level `byte_level = true`).
    public struct Options: Hashable, Sendable {
        /// `TimeoutMilliSeconds` in `Src/stringdiffs.cpp`.
        public static let winMergeAlignmentTimeout: Duration = .milliseconds(500)
        /// WinMerge's shipped defaults; identical to `Options()`.
        public static let winMergeDefaults = Options()

        public let caseSensitive: Bool
        public let endOfLineMode: EndOfLineMode
        public let whitespace: WhitespaceComparison
        public let ignoreNumbers: Bool
        public let breakType: BreakType
        /// Equivalent of `strdiff::SetBreakChars`; matched per UTF-16 unit.
        public let breakCharacters: String
        /// WinMerge's `byte_level` ("character" line-difference coloring).
        public let characterLevel: Bool
        /// Wall-clock limit for alignment, checked every ``alignmentClockCheckInterval`` steps as
        /// WinMerge does; `nil` disables it.
        public let alignmentTimeout: Duration?
        /// Optional deterministic cap on alignment work (word comparisons plus diagonal steps);
        /// `nil` means no cap. Not a WinMerge setting.
        public let maximumAlignmentWorkUnits: Int?

        public init(
            caseSensitive: Bool = true,
            endOfLineMode: EndOfLineMode = .strict,
            whitespace: WhitespaceComparison = .compareAll,
            ignoreNumbers: Bool = false,
            breakType: BreakType = .whitespaceOrBreakCharacters,
            breakCharacters: String = WinMergeStringDiffs.defaultBreakCharacters,
            characterLevel: Bool = true,
            alignmentTimeout: Duration? = Options.winMergeAlignmentTimeout,
            maximumAlignmentWorkUnits: Int? = nil
        ) {
            self.caseSensitive = caseSensitive
            self.endOfLineMode = endOfLineMode
            self.whitespace = whitespace
            self.ignoreNumbers = ignoreNumbers
            self.breakType = breakType
            self.breakCharacters = breakCharacters
            self.characterLevel = characterLevel
            self.alignmentTimeout = alignmentTimeout
            self.maximumAlignmentWorkUnits = maximumAlignmentWorkUnits.map { max(0, $0) }
        }

        /// Maps MacMerge's intra-line preferences onto WinMerge's `ComputeWordDiffs` arguments.
        /// `IntraLineDifferenceOptions.punctuation` has no WinMerge counterpart and is ignored.
        ///
        /// MacMerge stores an empty `wordBreakCharacters` preference by default, while WinMerge's
        /// `OPT_BREAK_SEPARATORS` defaults to ``WinMergeStringDiffs/defaultBreakCharacters``. This
        /// adapter treats an empty preference as unset and substitutes the WinMerge list; the
        /// preference default itself is left to its owning workflow.
        public init(
            _ options: IntraLineDifferenceOptions,
            endOfLineMode: EndOfLineMode = .strict,
            alignmentTimeout: Duration? = Options.winMergeAlignmentTimeout,
            maximumAlignmentWorkUnits: Int? = nil
        ) {
            self.init(
                caseSensitive: !options.ignoreCase,
                endOfLineMode: endOfLineMode,
                whitespace: options.whitespace,
                ignoreNumbers: options.ignoreNumbers,
                breakType: options.wordBreakMode == .whitespace
                    ? .whitespace : .whitespaceOrBreakCharacters,
                breakCharacters: options.wordBreakCharacters.isEmpty
                    ? WinMergeStringDiffs.defaultBreakCharacters : options.wordBreakCharacters,
                characterLevel: options.granularity == .character,
                alignmentTimeout: alignmentTimeout,
                maximumAlignmentWorkUnits: maximumAlignmentWorkUnits
            )
        }
    }

    /// One `strdiff::wdiff`. `begin`/`end` always hold three entries; for two-way results only
    /// indices 0 and 1 are meaningful (index 2 keeps the C++ constructor default `0...0`), and
    /// ``paneCount`` is 2.
    public struct Difference: Hashable, Sendable {
        public let begin: [Int]
        public let end: [Int]
        /// `nil` mirrors WinMerge's `op == -1` (two-way results and three-way results where a pane
        /// was empty).
        public let operation: Operation?
        /// Number of compared strings (2 or 3) that produced this difference.
        public let paneCount: Int

        public init(begin: [Int], end: [Int], operation: Operation?, paneCount: Int = 3) {
            precondition(begin.count == 3 && end.count == 3)
            precondition(paneCount == 2 || paneCount == 3)
            self.begin = begin
            self.end = end
            self.operation = operation
            self.paneCount = paneCount
        }

        /// Half-open UTF-16 range for `side`, or `nil` when `side` is not a compared pane or
        /// WinMerge marks that side absent (negative begin). An empty side yields a zero-length
        /// insertion point.
        public func utf16Range(side: Int) -> NSRange? {
            guard side >= 0, side < paneCount, begin[side] >= 0 else { return nil }
            return NSRange(location: begin[side], length: max(0, end[side] - begin[side] + 1))
        }
    }

    // MARK: Public entry points

    public static func computeWordDiffs(
        _ first: String,
        _ second: String,
        options: Options = Options()
    ) -> [Difference] {
        computeWordDiffs(utf16: [Array(first.utf16), Array(second.utf16)], options: options)
    }

    /// Two or three strings, as `ComputeWordDiffs(nFiles, str, ...)`.
    public static func computeWordDiffs(
        _ strings: [String],
        options: Options = Options()
    ) -> [Difference] {
        computeWordDiffs(utf16: strings.map { Array($0.utf16) }, options: options)
    }

    /// Raw UTF-16 entry point, allowing lone surrogates and embedded NULs exactly as WinMerge
    /// receives them.
    public static func computeWordDiffs(
        utf16 strings: [[UInt16]],
        options: Options = Options()
    ) -> [Difference] {
        precondition(strings.count == 2 || strings.count == 3, "WinMerge compares 2 or 3 strings")
        let context = Context(options: options)
        if strings.count == 2 {
            return context.diffs(strings[0], strings[1], whitespace: options.whitespace)
        }
        let s0 = strings[0]
        let s1 = strings[1]
        let s2 = strings[2]
        if s0.isEmpty {
            return context.diffs(s1, s2, whitespace: options.whitespace).map {
                Difference(
                    begin: [0, $0.begin[0], $0.begin[1]],
                    end: [-1, $0.end[0], $0.end[1]],
                    operation: $0.operation
                )
            }
        }
        if s1.isEmpty {
            return context.diffs(s0, s2, whitespace: options.whitespace).map {
                Difference(
                    begin: [$0.begin[0], 0, $0.begin[1]],
                    end: [$0.end[0], -1, $0.end[1]],
                    operation: $0.operation
                )
            }
        }
        if s2.isEmpty {
            return context.diffs(s0, s1, whitespace: options.whitespace).map {
                Difference(
                    begin: [$0.begin[0], $0.begin[1], 0],
                    end: [$0.end[0], $0.end[1], -1],
                    operation: $0.operation
                )
            }
        }
        // WinMerge passes whitespace = 0 for both pairwise runs of a full three-way compare.
        let diffs10 = context.diffs(s1, s0, whitespace: .compareAll)
        let diffs12 = context.diffs(s1, s2, whitespace: .compareAll)
        return make3wayDiff(diffs10: diffs10, diffs12: diffs12) { candidate in
            comp02(candidate, s0, s2, caseSensitive: options.caseSensitive)
        }
    }

    /// Port of `strdiff::Compare`. Returns the sign of `second.compare(first)` after WinMerge's
    /// normalization (-1, 0, or 1).
    public static func compare(
        _ first: String,
        _ second: String,
        caseSensitive: Bool = true,
        endOfLineMode: EndOfLineMode = .strict,
        whitespace: WhitespaceComparison = .compareAll,
        ignoreNumbers: Bool = false
    ) -> Int {
        var s1 = Array(first.utf16)
        var s2 = Array(second.utf16)
        if !(caseSensitive && endOfLineMode == .strict && whitespace == .compareAll
            && !ignoreNumbers)
        {
            func normalize(_ s: inout [UInt16]) {
                if !caseSensitive { s = s.map(Unit.toLower) }
                switch endOfLineMode {
                case .strict: break
                case .ignore: s = replaceChars(s, [Unit.cr, Unit.lf], with: [Unit.lf])
                case .asSpace:
                    s = replaceSubsequence(s, [Unit.cr, Unit.lf], with: [Unit.space])
                    s = replaceChars(s, [Unit.cr, Unit.lf], with: [Unit.space])
                }
                switch whitespace {
                case .compareAll: break
                case .ignoreChanges: s = replaceChars(s, [Unit.space, Unit.tab], with: [Unit.space])
                case .ignoreAll: s = replaceChars(s, [Unit.space, Unit.tab], with: [])
                }
                if ignoreNumbers { s = replaceChars(s, Array(0x30...0x39), with: []) }
            }
            normalize(&s1)
            normalize(&s2)
        }
        if s2.lexicographicallyPrecedes(s1) { return -1 }
        if s1.lexicographicallyPrecedes(s2) { return 1 }
        return 0
    }

    // MARK: Three-way merge (Src/Diff3.h, has_trivial_diffs == false)

    static func make3wayDiff(
        diffs10: [Difference],
        diffs12: [Difference],
        comp02: (Difference) -> Bool
    ) -> [Difference] {
        struct Element {
            var begin = [0, 0, 0]
            var end = [0, 0, 0]
            init() {}
            init(_ diff: Difference) {
                begin = diff.begin
                end = diff.end
            }
        }
        let diff10count = diffs10.count
        let diff12count = diffs12.count
        var diff10i = 0
        var diff12i = 0
        var dr10first = Element()
        var dr10last = Element()
        var dr12first = Element()
        var dr12last = Element()
        var linelast0 = 0
        var linelast1 = 0
        var linelast2 = 0
        var result: [(begin: [Int], end: [Int], op: Operation)] = []

        while true {
            let firstDiffBlockIsDiff12: Bool
            if diff10i >= diff10count {
                if diff12i >= diff12count { break }
                dr12first = Element(diffs12[diff12i])
                dr12last = dr12first
                firstDiffBlockIsDiff12 = true
            } else if diff12i >= diff12count {
                dr10first = Element(diffs10[diff10i])
                dr10last = dr10first
                firstDiffBlockIsDiff12 = false
            } else {
                dr10first = Element(diffs10[diff10i])
                dr10last = dr10first
                dr12first = Element(diffs12[diff12i])
                dr12last = dr12first
                firstDiffBlockIsDiff12 = dr12first.begin[0] <= dr10first.begin[0]
            }
            var lastDiffBlockIsDiff12 = firstDiffBlockIsDiff12

            var diff10itmp = diff10i
            var diff12itmp = diff12i
            while diff10itmp < diff10count, diff12itmp < diff12count {
                let dr10 = Element(diffs10[diff10itmp])
                let dr12 = Element(diffs12[diff12itmp])
                if dr10.end[0] == dr12.end[0] {
                    diff10itmp += 1
                    lastDiffBlockIsDiff12 = true
                    dr10last = dr10
                    dr12last = dr12
                    break
                }
                if lastDiffBlockIsDiff12 {
                    if max(dr12.begin[0], dr12.end[0]) < dr10.begin[0] { break }
                } else {
                    if max(dr10.begin[0], dr10.end[0]) < dr12.begin[0] { break }
                }
                if dr12.end[0] > dr10.end[0] {
                    diff10itmp += 1
                    lastDiffBlockIsDiff12 = true
                } else {
                    diff12itmp += 1
                    lastDiffBlockIsDiff12 = false
                }
                dr10last = dr10
                dr12last = dr12
            }
            if lastDiffBlockIsDiff12 {
                diff12itmp += 1
            } else {
                diff10itmp += 1
            }

            var dr3 = Element()
            if firstDiffBlockIsDiff12 {
                dr3.begin[1] = dr12first.begin[0]
                dr3.begin[2] = dr12first.begin[1]
                if diff10itmp == diff10i {
                    dr3.begin[0] = dr3.begin[1] - linelast1 + linelast0
                } else {
                    dr3.begin[0] = dr3.begin[1] - dr10first.begin[0] + dr10first.begin[1]
                }
            } else {
                dr3.begin[0] = dr10first.begin[1]
                dr3.begin[1] = dr10first.begin[0]
                if diff12itmp == diff12i {
                    dr3.begin[2] = dr3.begin[1] - linelast1 + linelast2
                } else {
                    dr3.begin[2] = dr3.begin[1] - dr12first.begin[0] + dr12first.begin[1]
                }
            }
            if lastDiffBlockIsDiff12 {
                dr3.end[1] = dr12last.end[0]
                dr3.end[2] = dr12last.end[1]
                if diff10itmp == diff10i {
                    dr3.end[0] = dr3.end[1] - linelast1 + linelast0
                } else {
                    dr3.end[0] = dr3.end[1] - dr10last.end[0] + dr10last.end[1]
                }
            } else {
                dr3.end[0] = dr10last.end[1]
                dr3.end[1] = dr10last.end[0]
                if diff12itmp == diff12i {
                    dr3.end[2] = dr3.end[1] - linelast1 + linelast2
                } else {
                    dr3.end[2] = dr3.end[1] - dr12last.end[0] + dr12last.end[1]
                }
            }
            linelast0 = dr3.end[0] + 1
            linelast1 = dr3.end[1] + 1
            linelast2 = dr3.end[2] + 1

            let op: Operation
            if diff10i == diff10itmp {
                op = .thirdOnly
            } else if diff12i == diff12itmp {
                op = .firstOnly
            } else if !comp02(Difference(begin: dr3.begin, end: dr3.end, operation: nil)) {
                op = .diff
            } else {
                op = .secondOnly
            }
            diff10i = diff10itmp
            diff12i = diff12itmp
            result.append((dr3.begin, dr3.end, op))
        }

        if result.count > 1 {
            for i in 0..<(result.count - 1) {
                for j in 0..<3 where result[i].end[j] >= result[i + 1].begin[j] {
                    result[i].end[j] = result[i + 1].begin[j] - 1
                }
            }
        }
        return result.map { Difference(begin: $0.begin, end: $0.end, operation: $0.op) }
    }

    /// `Comp02Functor`: does the merged block hold identical text on panes 0 and 2?
    private static func comp02(
        _ diff: Difference,
        _ s0: [UInt16],
        _ s2: [UInt16],
        caseSensitive: Bool
    ) -> Bool {
        let wlen0 = diff.end[0] - diff.begin[0] + 1
        let wlen2 = diff.end[2] - diff.begin[2] + 1
        guard wlen0 == wlen2 else { return false }
        guard wlen0 > 0 else { return true }
        for i in 0..<wlen0 {
            let c0 = Unit.at(s0, diff.begin[0] + i)
            let c2 = Unit.at(s2, diff.begin[2] + i)
            if caseSensitive {
                if c0 != c2 { return false }
            } else {
                // `_wcsnicmp` stops at the first shared NUL terminator.
                let l0 = Unit.toLower(c0)
                let l2 = Unit.toLower(c2)
                if l0 != l2 { return false }
                if l0 == 0 { return true }
            }
        }
        return true
    }

    private static func replaceChars(
        _ s: [UInt16],
        _ chars: [UInt16],
        with replacement: [UInt16]
    ) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(s.count)
        var inRun = false
        for unit in s {
            if chars.contains(unit) {
                if !inRun { out.append(contentsOf: replacement) }
                inRun = true
            } else {
                out.append(unit)
                inRun = false
            }
        }
        return out
    }

    private static func replaceSubsequence(
        _ s: [UInt16],
        _ pattern: [UInt16],
        with replacement: [UInt16]
    ) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if i + pattern.count <= s.count, s[i..<(i + pattern.count)].elementsEqual(pattern) {
                out.append(contentsOf: replacement)
                i += pattern.count
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return out
    }
}

// MARK: - stringdiffs worker

extension WinMergeStringDiffs {
    fileprivate enum WordKind: Equatable {
        case word, space, eol, breakChar, number
    }

    fileprivate struct Word {
        let start: Int
        let end: Int
        let kind: WordKind
        let hash: UInt32
        var length: Int { end + 1 - start }
    }

    /// `wdiff` while it is still being built (two meaningful sides).
    fileprivate struct WorkingDiff {
        var begin: (Int, Int)
        var end: (Int, Int)

        init(_ s1: Int, _ e1: Int, _ s2: Int, _ e2: Int) {
            begin = (s1, s2)
            end = (s1 > e1 ? s1 - 1 : e1, s2 > e2 ? s2 - 1 : e2)
        }
    }

    fileprivate struct Context {
        let options: Options
        let breakUnits: Set<UInt16>

        init(options: Options) {
            self.options = options
            breakUnits = Set(options.breakCharacters.utf16)
        }

        func diffs(
            _ str1: [UInt16],
            _ str2: [UInt16],
            whitespace: WhitespaceComparison
        ) -> [Difference] {
            var worker = Worker(
                str1: str1,
                str2: str2,
                options: options,
                whitespace: whitespace,
                breakUnits: breakUnits
            )
            worker.buildWordDiffList()
            if options.characterLevel { worker.wordLevelToByteLevel() }
            return worker.populateDiffs()
        }
    }

    fileprivate struct Worker {
        let str1: [UInt16]
        let str2: [UInt16]
        let options: Options
        let whitespace: WhitespaceComparison
        let breakUnits: Set<UInt16>
        var words1: [Word] = []
        var words2: [Word] = []
        var wdiffs: [WorkingDiff] = []

        init(
            str1: [UInt16],
            str2: [UInt16],
            options: Options,
            whitespace: WhitespaceComparison,
            breakUnits: Set<UInt16>
        ) {
            self.str1 = str1
            self.str2 = str2
            self.options = options
            self.whitespace = whitespace
            self.breakUnits = breakUnits
        }

        // MARK: BuildWordDiffList

        mutating func buildWordDiffList() {
            words1 = buildWordsArray(str1)
            words2 = buildWordsArray(str2)
            var succeeded = false
            if words1.count < WinMergeStringDiffs.maximumAlignedWordCount,
                words2.count < WinMergeStringDiffs.maximumAlignedWordCount
            {
                succeeded = buildWordDiffListDP()
            }
            if !succeeded {
                wdiffs = [
                    WorkingDiff(
                        words1[0].start,
                        words1[words1.count - 1].end,
                        words2[0].start,
                        words2[words2.count - 1].end
                    )
                ]
            }
        }

        private mutating func buildWordDiffListDP() -> Bool {
            guard let edscript = onp() else { return false }
            let ignoreAllSpace = whitespace == .ignoreAll
            let ignoreSomeSpace = whitespace != .compareAll
            var collected: [WorkingDiff] = []
            var i = 1
            var j = 1
            for op in edscript {
                switch op {
                case .delete:
                    if ignoreAllSpace, words1[i].kind == .space {
                        i += 1
                        continue
                    }
                    if options.ignoreNumbers, words1[i].kind == .number {
                        i += 1
                        continue
                    }
                    let s2 = words2[j - 1].end + 1
                    collected.append(WorkingDiff(words1[i].start, words1[i].end, s2, s2 - 1))
                    i += 1
                case .insert:
                    if ignoreAllSpace, words2[j].kind == .space {
                        j += 1
                        continue
                    }
                    if options.ignoreNumbers, words2[j].kind == .number {
                        j += 1
                        continue
                    }
                    let s1 = words1[i - 1].end + 1
                    collected.append(WorkingDiff(s1, s1 - 1, words2[j].start, words2[j].end))
                    j += 1
                case .change:
                    if ignoreSomeSpace, words1[i].kind == .space, words2[j].kind == .space {
                        i += 1
                        j += 1
                        continue
                    }
                    if options.ignoreNumbers, words1[i].kind == .number,
                        words2[j].kind == .number
                    {
                        i += 1
                        j += 1
                        continue
                    }
                    collected.append(
                        WorkingDiff(words1[i].start, words1[i].end, words2[j].start, words2[j].end)
                    )
                    i += 1
                    j += 1
                case .equal:
                    i += 1
                    j += 1
                }
            }
            wdiffs = collected
            return true
        }

        // MARK: BuildWordsArray

        private func buildWordsArray(_ str: [UInt16]) -> [Word] {
            var words = [Word(start: 0, end: -1, kind: .word, hash: 0)]
            guard !str.isEmpty else { return words }
            var iterator = CharacterBreakIterator(text: str)
            let length = str.count
            var i = 0
            var begin = 0
            var breakType = WordKind.word
            var previousBreakType = WordKind.word
            while i < length {
                breakType = .word
                let ch = str[i]
                if ch == Unit.cr || ch == Unit.lf {
                    breakType = options.endOfLineMode == .asSpace ? .space : .eol
                } else if Unit.isSafeWhitespace(ch) {
                    breakType = .space
                } else if isWordBreak(ch) {
                    breakType = .breakChar
                } else if options.ignoreNumbers, Unit.isDigit(ch) {
                    breakType = .number
                }
                if i > 0,
                    breakType != previousBreakType || breakType == .breakChar
                        || (previousBreakType == .eol && !(str[i - 1] == Unit.cr && ch == Unit.lf))
                {
                    words.append(
                        Word(
                            start: begin,
                            end: i - 1,
                            kind: previousBreakType,
                            hash: hash(str, begin, i - 1)
                        )
                    )
                    begin = i
                }
                if options.endOfLineMode == .asSpace, breakType == .space {
                    while i < length {
                        let ch2 = str[i]
                        if ch2 != Unit.cr, ch2 != Unit.lf, !Unit.isSafeWhitespace(ch2) { break }
                        i += 1
                    }
                    _ = iterator.preceding(i)
                } else {
                    i = iterator.next()
                }
                previousBreakType = breakType
            }
            words.append(Word(start: begin, end: i - 1, kind: breakType, hash: hash(str, begin, i - 1)))
            return words
        }

        private func isWordBreak(_ ch: UInt16) -> Bool {
            if ch & 0xFF00 == 0 {
                guard options.breakType != .whitespace else { return false }
                // `tcschr` also matches the terminating NUL.
                return ch == 0 || breakUnits.contains(ch)
            }
            return !Unit.isCasedLetterOrDigit(ch)
        }

        /// diffutils `HASH` accumulated as `h += HASH(h, c)` in 32-bit unsigned arithmetic.
        private func hash(_ str: [UInt16], _ begin: Int, _ end: Int) -> UInt32 {
            var h: UInt32 = 0
            guard begin <= end else { return h }
            for index in begin...end {
                var ch = str[index]
                if !options.caseSensitive { ch = Unit.toLower(ch) }
                h = h &+ (UInt32(ch) &+ ((h << 7) | (h >> 25)))
            }
            return h
        }

        // MARK: AreWordsSame

        private func areWordsSame(_ word1: Word, _ word2: Word) -> Bool {
            if whitespace != .compareAll, word1.kind == .space, word2.kind == .space {
                return true
            }
            if options.ignoreNumbers, Unit.isDigit(Unit.at(str1, word1.start)),
                Unit.isDigit(Unit.at(str2, word2.start))
            {
                return true
            }
            switch options.endOfLineMode {
            case .strict:
                break
            case .ignore:
                if word1.kind == .eol, word2.kind == .eol { return true }
            case .asSpace:
                if word1.kind == .space, word2.kind == .space {
                    func folded(_ s: [UInt16], _ word: Word) -> [UInt16] {
                        let slice = Array(s[word.start...word.end])
                        let replaced = WinMergeStringDiffs.replaceSubsequence(
                            slice,
                            [Unit.cr, Unit.lf],
                            with: [Unit.space]
                        )
                        return WinMergeStringDiffs.replaceChars(
                            replaced,
                            [Unit.cr, Unit.lf],
                            with: [Unit.space]
                        )
                    }
                    return folded(str1, word1) == folded(str2, word2)
                }
            }
            guard word1.hash == word2.hash else { return false }
            let length = word1.length
            guard length == word2.length else { return false }
            for offset in 0..<length {
                let ch1 = str1[word1.start + offset]
                let ch2 = str2[word2.start + offset]
                if options.caseSensitive {
                    if ch1 != ch2 { return false }
                } else if Unit.toLower(ch1) != Unit.toLower(ch2) {
                    return false
                }
            }
            return true
        }

        // MARK: onp

        enum EditOperation {
            case equal, insert, delete, change
        }

        private struct EditScriptElement {
            let op: UInt8
            let neq: Int
            let pk: Int
            let pi: Int
        }

        /// An O(NP) Sequence Comparison Algorithm (Wu, Manber, Myers), as in `stringdiffs::onp`.
        /// Returns `nil` where WinMerge would time out.
        private func onp() -> [EditOperation]? {
            let plus = UInt8(ascii: "+")
            let minus = UInt8(ascii: "-")
            var m = words1.count - 1
            var n = words2.count - 1
            let exchanged = m > n
            if exchanged { swap(&m, &n) }
            let offset = m + 1
            let size = (m + 1) + 1 + (n + 1)
            var fp = [Int](repeating: -1, count: size)
            var es = [[EditScriptElement]](repeating: [], count: size)
            let delta = n - m
            let budget = options.maximumAlignmentWorkUnits
            var work = 0
            let clock = ContinuousClock()
            let start = clock.now
            var count = 0

            func snake(_ k: Int, _ startY: Int) -> Int {
                var y = startY
                var x = y - k
                while x < m, y < n {
                    work += 1
                    let same =
                        exchanged
                        ? areWordsSame(words1[y + 1], words2[x + 1])
                        : areWordsSame(words1[x + 1], words2[y + 1])
                    guard same else { break }
                    x += 1
                    y += 1
                }
                return y
            }

            func step(_ k: Int) {
                let index = k + offset
                fp[index] = snake(k, max(fp[index - 1] + 1, fp[index + 1]))
                let element: EditScriptElement
                if fp[index - 1] + 1 > fp[index + 1] {
                    element = EditScriptElement(
                        op: plus,
                        neq: fp[index] - (fp[index - 1] + 1),
                        pk: k - 1,
                        pi: es[index - 1].count - 1
                    )
                } else {
                    element = EditScriptElement(
                        op: minus,
                        neq: fp[index] - fp[index + 1],
                        pk: k + 1,
                        pi: es[index + 1].count - 1
                    )
                }
                es[index].append(element)
                work += 1
                count += 1
            }

            var p = -1
            repeat {
                p += 1
                var k = -p
                while k <= delta - 1 {
                    step(k)
                    k += 1
                }
                k = delta + p
                while k >= delta + 1 {
                    step(k)
                    k -= 1
                }
                step(delta)
                if let budget, work > budget { return nil }
                if count > WinMergeStringDiffs.alignmentClockCheckInterval {
                    count = 0
                    if let timeout = options.alignmentTimeout, clock.now - start > timeout {
                        return nil
                    }
                }
            } while fp[delta + offset] != n

            var ses: [UInt8] = []
            var k = delta
            var i = es[delta + offset].count - 1
            while i >= 0 {
                let element = es[k + offset][i]
                ses.append(contentsOf: repeatElement(UInt8(ascii: "="), count: max(0, element.neq)))
                ses.append(element.op)
                i = element.pi
                k = element.pk
            }
            ses.reverse()

            var edscript: [EditOperation] = []
            edscript.reserveCapacity(ses.count)
            var index = 1
            while index < ses.count {
                let ch = ses[index]
                let isPlus = ch == plus
                if isPlus || ch == minus {
                    let opposite = isPlus ? minus : plus
                    if index != ses.count - 1, ses[index + 1] == opposite {
                        index += 1
                        edscript.append(.change)
                    } else {
                        edscript.append(exchanged == isPlus ? .delete : .insert)
                    }
                } else {
                    edscript.append(.equal)
                }
                index += 1
            }
            return edscript
        }

        // MARK: PopulateDiffs

        func populateDiffs() -> [Difference] {
            var pending = wdiffs
            var result: [Difference] = []
            result.reserveCapacity(pending.count)
            for i in pending.indices {
                if i + 1 < pending.count,
                    pending[i].end.0 + 1 == pending[i + 1].begin.0,
                    pending[i].end.1 + 1 == pending[i + 1].begin.1
                {
                    pending[i + 1].begin = pending[i].begin
                    continue
                }
                let diff = pending[i]
                result.append(
                    Difference(
                        begin: [diff.begin.0, diff.begin.1, 0],
                        end: [diff.end.0, diff.end.1, 0],
                        operation: nil,
                        paneCount: 2
                    )
                )
            }
            return result
        }

        // MARK: wordLevelToByteLevel

        mutating func wordLevelToByteLevel() {
            for index in wdiffs.indices {
                var diff = wdiffs[index]
                let sub1 = Worker.substring(str1, diff.begin.0, diff.end.0)
                let sub2 = Worker.substring(str2, diff.begin.1, diff.end.1)
                let byteDiff = Worker.computeByteDiff(
                    sub1,
                    sub2,
                    caseSensitive: options.caseSensitive,
                    whitespace: whitespace
                )
                if byteDiff.begin.0 == -1 {
                    diff.end.0 = diff.begin.0 - 1
                } else {
                    diff.end.0 = diff.begin.0 + byteDiff.end.0
                    diff.begin.0 += byteDiff.begin.0
                }
                if byteDiff.begin.1 == -1 {
                    diff.end.1 = diff.begin.1 - 1
                } else {
                    diff.end.1 = diff.begin.1 + byteDiff.end.1
                    diff.begin.1 += byteDiff.begin.1
                }
                wdiffs[index] = diff
            }
        }

        private static func substring(_ s: [UInt16], _ begin: Int, _ end: Int) -> [UInt16] {
            let lower = min(max(0, begin), s.count)
            let upper = min(max(lower, end + 1), s.count)
            return Array(s[lower..<upper])
        }

        // MARK: ComputeByteDiff (equal == false)

        static func computeByteDiff(
            _ s1: [UInt16],
            _ s2: [UInt16],
            caseSensitive: Bool,
            whitespace: WhitespaceComparison
        ) -> (begin: (Int, Int), end: (Int, Int)) {
            let xwhite: Int
            switch whitespace {
            case .compareAll: xwhite = 0
            case .ignoreChanges: xwhite = 1
            case .ignoreAll: xwhite = 2
            }
            let len1 = s1.count
            let len2 = s2.count
            if len1 == 0 || len2 == 0 {
                if len1 == len2 { return ((-1, -1), (-1, -1)) }
                return ((0, 0), (len1 - 1, len2 - 1))
            }
            let boundaries1 = CharacterBreakIterator.boundaries(of: s1)
            let boundaries2 = CharacterBreakIterator.boundaries(of: s2)
            var begin1 = CharacterBreakIterator(boundaries: boundaries1)
            var begin2 = CharacterBreakIterator(boundaries: boundaries2)
            var end1 = CharacterBreakIterator(boundaries: boundaries1)
            var end2 = CharacterBreakIterator(boundaries: boundaries2)

            func white(_ s: [UInt16], _ index: Int) -> Bool {
                Unit.isSafeWhitespace(Unit.at(s, index))
            }
            func matchChar(_ p1: Int, _ p2: Int, _ length: Int) -> Bool {
                guard length >= 0 else { return false }
                for offset in 0..<length {
                    let c1 = Unit.at(s1, p1 + offset)
                    let c2 = Unit.at(s2, p2 + offset)
                    if caseSensitive ? c1 != c2 : Unit.toLower(c1) != Unit.toLower(c2) {
                        return false
                    }
                }
                return true
            }
            func advanceOverWhitespace(_ p: inout Int, _ end: Int, _ s: [UInt16]) {
                while p <= end, white(s, p) { p += 1 }
            }

            var py1 = 0
            var py2 = 0
            var pen1 = end1.preceding(len1)
            var pen2 = end2.preceding(len2)
            var glyphLengthZ1 = len1 - pen1
            var glyphLengthZ2 = len2 - pen2

            if xwhite != 0 {
                while py1 < pen1, white(s1, py1) { py1 = begin1.next() }
                while py2 < pen2, white(s2, py2) { py2 = begin2.next() }
                // WinMerge's "mismatched broken multibyte ends" guard compares the two NUL
                // terminators, so trailing whitespace is always trimmed.
                while pen1 > py1, white(s1, pen1) { pen1 = end1.previous() }
                while pen2 > py2, white(s2, pen2) { pen2 = end2.previous() }
            }
            if (py1 == pen1 && white(s1, pen1)) || (py2 == pen2 && white(s2, pen2)) {
                return ((0, 0), (len1 - 1, len2 - 1))
            }

            while true {
                if py1 > pen1 || py2 > pen2 { break }
                if xwhite != 0, py1 < pen1, white(s1, py1) {
                    if xwhite == 1, !white(s2, py2) { break }
                    advanceOverWhitespace(&py1, pen1, s1)
                    advanceOverWhitespace(&py2, pen2, s2)
                    continue
                }
                if xwhite != 0, py2 < pen2, white(s2, py2) {
                    if xwhite == 1, !white(s1, py1) { break }
                    advanceOverWhitespace(&py1, pen1, s1)
                    advanceOverWhitespace(&py2, pen2, s2)
                    continue
                }
                // The forward iterators are not resynchronized after whitespace skipping.
                let py1next = begin1.next()
                let py2next = begin2.next()
                let glyphLengthY1 = py1next - py1
                let glyphLengthY2 = py2next - py2
                if glyphLengthY1 != glyphLengthY2 || !matchChar(py1, py2, glyphLengthY1) { break }
                py1 = py1next
                py2 = py2next
            }

            var begin = (py1, py2)
            var pz1 = pen1
            var pz2 = pen2
            while true {
                if pz1 < py1, pz2 < py2 {
                    begin = (-1, -1)
                    break
                }
                if pz1 < py1 || pz2 < py2 { break }
                if xwhite != 0, pz1 > py1, white(s1, pz1) {
                    if xwhite == 1, !white(s2, pz2) { break }
                    while pz1 > py1, white(s1, pz1) { pz1 = end1.previous() }
                    while pz2 > py2, white(s2, pz2) { pz2 = end2.previous() }
                    continue
                }
                if xwhite != 0, pz2 > py2, white(s2, pz2) {
                    if xwhite == 1 { break }
                    while pz2 > py2, white(s2, pz2) { pz2 = end2.previous() }
                    continue
                }
                if glyphLengthZ1 != glyphLengthZ2 || !matchChar(pz1, pz2, glyphLengthZ1) { break }
                let pz1next = pz1
                let pz2next = pz2
                pz1 = pz1 > 0 ? end1.preceding(pz1) : pz1 - 1
                pz2 = pz2 > 0 ? end2.preceding(pz2) : pz2 - 1
                glyphLengthZ1 = pz1next - pz1
                glyphLengthZ2 = pz2next - pz2
            }

            let end = (pz1 + glyphLengthZ1 - 1, pz2 + glyphLengthZ2 - 1)
            if begin.0 == end.0 + 1, begin.1 == end.1 + 1 {
                begin.0 = -1
            }
            return (begin, end)
        }
    }

    // MARK: ICU character-break iterator emulation

    /// Emulates the `ICUBreakIterator` wrapper's character iterator: `next()` maps DONE to the
    /// text length, `preceding()` maps DONE to 0, and `previous()` returns raw DONE (-1).
    fileprivate struct CharacterBreakIterator {
        let boundaries: [Int]
        private(set) var position = 0

        init(text: [UInt16]) {
            self.init(boundaries: CharacterBreakIterator.boundaries(of: text))
        }

        init(boundaries: [Int]) {
            self.boundaries = boundaries
        }

        private var length: Int { boundaries.last ?? 0 }

        mutating func next() -> Int {
            guard position < length else { return length }
            position = firstBoundary(after: position) ?? length
            return position
        }

        mutating func previous() -> Int {
            guard position > 0 else { return -1 }
            position = lastBoundary(before: position) ?? 0
            return position
        }

        mutating func preceding(_ offset: Int) -> Int {
            position = lastBoundary(before: offset) ?? 0
            return position
        }

        private func firstBoundary(after value: Int) -> Int? {
            var low = 0
            var high = boundaries.count
            while low < high {
                let mid = (low + high) / 2
                if boundaries[mid] <= value { low = mid + 1 } else { high = mid }
            }
            return low < boundaries.count ? boundaries[low] : nil
        }

        private func lastBoundary(before value: Int) -> Int? {
            var low = 0
            var high = boundaries.count
            while low < high {
                let mid = (low + high) / 2
                if boundaries[mid] < value { low = mid + 1 } else { high = mid }
            }
            return low > 0 ? boundaries[low - 1] : nil
        }

        /// Grapheme boundaries (including 0 and the length) in UTF-16 units, with WinMerge's
        /// custom rule that U+FF9E/U+FF9F never extend the preceding cluster.
        static func boundaries(of text: [UInt16]) -> [Int] {
            var result = [0]
            guard !text.isEmpty else { return result }
            // Lone surrogates decode to U+FFFD, which keeps the one-unit width.
            let string = String(decoding: text, as: UTF16.self)
            var position = 0
            for character in string {
                var clusterStart = position
                for scalar in character.unicodeScalars {
                    let width = scalar.value > 0xFFFF ? 2 : 1
                    if scalar.value == 0xFF9E || scalar.value == 0xFF9F, position > clusterStart {
                        result.append(position)
                        clusterStart = position
                    }
                    position += width
                }
                result.append(position)
            }
            return result
        }
    }

    // MARK: Windows CRT / Win32 character classification approximations

    fileprivate enum Unit {
        static let tab: UInt16 = 0x09
        static let lf: UInt16 = 0x0A
        static let cr: UInt16 = 0x0D
        static let space: UInt16 = 0x20

        static func at(_ s: [UInt16], _ index: Int) -> UInt16 {
            index >= 0 && index < s.count ? s[index] : 0
        }

        static func scalar(_ unit: UInt16) -> Unicode.Scalar? {
            Unicode.Scalar(UInt32(unit))
        }

        /// `iswspace` (C1_SPACE).
        static func isSpace(_ unit: UInt16) -> Bool {
            switch unit {
            case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F,
                0x205F, 0x3000:
                true
            default:
                false
            }
        }

        /// `isSafeWhitespace`: whitespace that is not CR or LF.
        static func isSafeWhitespace(_ unit: UInt16) -> Bool {
            isSpace(unit) && unit != cr && unit != lf
        }

        /// `iswdigit` (C1_DIGIT), approximated as decimal digits plus the Latin-1 superscript
        /// digits that the Windows tables classify as digits.
        static func isDigit(_ unit: UInt16) -> Bool {
            if unit >= 0x30 && unit <= 0x39 { return true }
            if unit == 0xB2 || unit == 0xB3 || unit == 0xB9 { return true }
            guard unit >= 0x80, let scalar = scalar(unit) else { return false }
            return scalar.properties.generalCategory == .decimalNumber
        }

        /// `GetStringTypeW(CT_CTYPE1)` has `C1_UPPER | C1_LOWER | C1_DIGIT`.
        static func isCasedLetterOrDigit(_ unit: UInt16) -> Bool {
            guard let scalar = scalar(unit) else { return false }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .decimalNumber:
                return true
            default:
                return false
            }
        }

        /// `towlower`: Swift's full lowercase mapping when it is a single BMP scalar, plus simple
        /// mappings the full mapping hides (U+0130 -> U+0069); other units are unchanged.
        static func toLower(_ unit: UInt16) -> UInt16 {
            if unit < 0x80 {
                return unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit
            }
            if unit == 0x130 { return 0x69 }
            guard let scalar = scalar(unit) else { return unit }
            let mapped = scalar.properties.lowercaseMapping.unicodeScalars
            guard mapped.count == 1, let lower = mapped.first, lower.value <= 0xFFFF else {
                return unit
            }
            return UInt16(lower.value)
        }
    }
}

// MARK: - Intra-line workflow entry point

extension IntraLineDifferenceWorkflow {
    /// WinMerge-faithful intra-line ranges: runs ``WinMergeStringDiffs/computeWordDiffs(_:_:options:)``
    /// with ``WinMergeStringDiffs/Options/init(_:endOfLineMode:alignmentTimeout:maximumAlignmentWorkUnits:)``
    /// and reports each `wdiff` as a range pair in UTF-16 coordinates.
    ///
    /// This is the WinMerge-parity alternative to ``plan(_:options:limits:)``, which keeps its own
    /// bounded aligner, budgets, and receipts. A missing side is compared as an empty string, as
    /// WinMerge does for a ghost line, and reports a `nil` range.
    public static func winMergeRangePairs(
        source: String?,
        comparison: String?,
        options: IntraLineDifferenceOptions = .default,
        endOfLineMode: WinMergeStringDiffs.EndOfLineMode = .strict,
        alignmentTimeout: Duration? = WinMergeStringDiffs.Options.winMergeAlignmentTimeout
    ) -> [IntraLineDifferenceRangePair] {
        let diffs = WinMergeStringDiffs.computeWordDiffs(
            source ?? "",
            comparison ?? "",
            options: WinMergeStringDiffs.Options(
                options,
                endOfLineMode: endOfLineMode,
                alignmentTimeout: alignmentTimeout
            )
        )
        return diffs.enumerated().map { ordinal, diff in
            let sourceRange = source == nil ? nil : diff.utf16Range(side: 0)
            let comparisonRange = comparison == nil ? nil : diff.utf16Range(side: 1)
            let kind: IntraLineDifferenceChangeKind
            if source == nil || sourceRange?.length == 0 {
                kind = .insert
            } else if comparison == nil || comparisonRange?.length == 0 {
                kind = .delete
            } else {
                kind = .replace
            }
            return IntraLineDifferenceRangePair(
                ordinal: ordinal,
                kind: kind,
                sourceUTF16Range: sourceRange,
                comparisonUTF16Range: comparisonRange
            )
        }
    }
}
