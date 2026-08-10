import CXDiff
import MacMergeCore
import XCTest

final class LineDiffTests: XCTestCase {
    func testDiffRowStorageRemainsCompact() {
        XCTAssertLessThanOrEqual(MemoryLayout<DiffRow>.stride, 40)

        let maximumLine = Int(MMX_MAX_LINE_COUNT)
        let row = DiffRow(
            left: DiffLine(number: maximumLine, text: "left"),
            right: DiffLine(number: maximumLine, text: "right"),
            kind: .modified
        )
        XCTAssertEqual(row.left, DiffLine(number: maximumLine, text: "left"))
        XCTAssertEqual(row.right, DiffLine(number: maximumLine, text: "right"))
        XCTAssertEqual(row.kind, .modified)

        let unusual = DiffRow(
            left: DiffLine(number: -1, text: "left\0text"),
            right: DiffLine(number: Int.max, text: "right"),
            kind: .added
        )
        XCTAssertEqual(unusual.left, DiffLine(number: -1, text: "left\0text"))
        XCTAssertEqual(unusual.right, DiffLine(number: Int.max, text: "right"))
        XCTAssertEqual(unusual.kind, .added)
    }

    func testUnchangedLinesRemainAligned() throws {
        let rows = try LineDiff.compare(left: "alpha\nbeta", right: "alpha\nbeta")

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .unchanged])
        XCTAssertEqual(rows.map(\.left?.number), [1, 2])
        XCTAssertEqual(rows.map(\.right?.number), [1, 2])
    }

    func testReplacementProducesModifiedRow() throws {
        let rows = try LineDiff.compare(left: "alpha\nold\nomega", right: "alpha\nnew\nomega")

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .modified, .unchanged])
        XCTAssertEqual(rows[1].left?.text, "old")
        XCTAssertEqual(rows[1].right?.text, "new")
    }

    func testInsertionPreservesSurroundingAlignment() throws {
        let rows = try LineDiff.compare(left: "alpha\nomega", right: "alpha\nbeta\nomega")

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .added, .unchanged])
        XCTAssertNil(rows[1].left)
        XCTAssertEqual(rows[1].right, DiffLine(number: 2, text: "beta"))
    }

    func testDeletionPreservesSurroundingAlignment() throws {
        let rows = try LineDiff.compare(left: "alpha\nbeta\nomega", right: "alpha\nomega")

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .removed, .unchanged])
        XCTAssertEqual(rows[1].left, DiffLine(number: 2, text: "beta"))
        XCTAssertNil(rows[1].right)
    }

    func testCRLFAndLFCompareAsEqual() throws {
        let rows = try LineDiff.compare(left: "alpha\r\nbeta\r\n", right: "alpha\nbeta\n")

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .unchanged])
    }

    func testSummaryCountsDifferenceKinds() throws {
        let rows = try LineDiff.compare(left: "one\ntwo\nthree", right: "one\nsecond\nthree\nfour")
        let summary = DiffSummary(rows: rows)

        XCTAssertEqual(summary.unchanged, 2)
        XCTAssertEqual(summary.modified, 1)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.removed, 0)
        XCTAssertEqual(summary.differences, 2)
    }

    func testLineTextEditingReplacesLineWithoutChangingCRLFPolicy() {
        let result = LineTextEditing.replacingLine(
            in: "one\r\ntwo\r\nthree",
            lineNumber: 2,
            insertionIndex: 1,
            with: "TWO"
        )

        XCTAssertEqual(result, "one\r\nTWO\r\nthree")
    }

    func testLineTextEditingInsertsMissingAlignedLine() {
        let result = LineTextEditing.replacingLine(
            in: "one\nthree",
            lineNumber: nil,
            insertionIndex: 1,
            with: "two"
        )

        XCTAssertEqual(result, "one\ntwo\nthree")
    }

    func testLineTextEditingSplitsReplacementUsingTargetLineEnding() {
        let result = LineTextEditing.replacingLine(
            in: "one\r\ntwo\r\n",
            lineNumber: 1,
            insertionIndex: 0,
            with: "ONE\nEXTRA"
        )

        XCTAssertEqual(result, "ONE\r\nEXTRA\r\ntwo\r\n")
    }

    func testLineTextEditingReturnAtLineEndCreatesBlankAlignedLine() {
        let result = LineTextEditing.replacingLine(
            in: "one\r\ntwo\r\n",
            lineNumber: 1,
            insertionIndex: 0,
            with: "one\n"
        )

        XCTAssertEqual(result, "one\r\n\r\ntwo\r\n")
    }

    func testLineTextEditingNormalizesInsertedLinesToTargetEnding() {
        let result = LineTextEditing.replacingLine(
            in: "one\r\nthree",
            lineNumber: nil,
            insertionIndex: 1,
            with: "two-a\ntwo-b"
        )

        XCTAssertEqual(result, "one\r\ntwo-a\r\ntwo-b\r\nthree")
    }

    func testWinMergeNoEOLFixtureMatchesAllAlgorithms() throws {
        let algorithms: [DiffAlgorithm] = [.default, .minimal, .patience, .histogram, .none]
        let fixtures = [
            ("a\nb\nc1", "a\nb\nc2", 3),
            ("a\nb\nc1\n", "a\nb\nc2", 3),
            ("a\nb\nc1", "a\nb\nc2\n", 3),
            ("a\nb1\nc", "a\nb2\nc", 2)
        ]

        for algorithm in algorithms {
            for fixture in fixtures {
                let rows = try LineDiff.compare(
                    left: fixture.0,
                    right: fixture.1,
                    options: LineDiffOptions(algorithm: algorithm)
                )
                let differences = rows.filter { $0.kind != .unchanged }

                XCTAssertEqual(differences.count, 1, "Algorithm: \(algorithm)")
                XCTAssertEqual(differences[0].left?.number, fixture.2)
                XCTAssertEqual(differences[0].right?.number, fixture.2)
                XCTAssertEqual(differences[0].kind, .modified)
            }
        }
    }

    func testWinMergeComparisonOptionsReachXDiff() throws {
        let fixtures: [(String, String, LineDiffOptions)] = [
            ("Alpha\n", "alpha\n", LineDiffOptions(ignoreCase: true)),
            ("build 123\n", "build 456\n", LineDiffOptions(ignoreNumbers: true)),
            ("a\n\nb\n", "a\n \nb\n", LineDiffOptions(ignoreBlankLines: true)),
            (
                "a   b\n",
                "a b\n",
                LineDiffOptions(whitespace: .ignoreChanges)
            ),
            (
                "a b\n",
                "ab\n",
                LineDiffOptions(whitespace: .ignoreAll)
            )
        ]

        for fixture in fixtures {
            let rows = try LineDiff.compare(left: fixture.0, right: fixture.1, options: fixture.2)
            XCTAssertEqual(DiffSummary(rows: rows).differences, 0)
        }
    }

    func testWinMergeLineFilterFixtures() throws {
        let options = LineDiffOptions(lineFilters: [
            LineFilterRule(pattern: #"\d{4}-\d{2}-\d{2}"#),
        ])
        let fixtures: [(String, String, Int)] = [
            ("a\n# 2023-10-09\nc", "a\n# 2023-10-08\nc", 0),
            ("a\n# 2023-10-09\n# 2023-10-09\nc", "a\n# 2023-10-08\nc", 0),
            ("a\n# 2023-10-09\nb1\nc", "a\n# 2023-10-08\nb2\nc", 1),
        ]

        for algorithm in [DiffAlgorithm.default, .minimal, .patience, .histogram] {
            for fixture in fixtures {
                var algorithmOptions = options
                algorithmOptions.algorithm = algorithm
                let rows = try LineDiff.compare(
                    left: fixture.0,
                    right: fixture.1,
                    options: algorithmOptions
                )
                XCTAssertEqual(DiffSummary(rows: rows).differences, fixture.2)
            }
        }
    }

    func testDisabledLineFiltersDoNotAffectComparison() throws {
        let options = LineDiffOptions(
            lineFiltersEnabled: false,
            lineFilters: [LineFilterRule(pattern: #"^# "#)]
        )

        let rows = try LineDiff.compare(left: "# old\n", right: "# new\n", options: options)

        XCTAssertEqual(rows.map(\.kind), [.modified])
    }

    func testLineFiltersSplitIgnoredRowsFromAdjacentRealChanges() throws {
        let rows = try LineDiff.compare(
            left: "head\n# old\n# extra\nreal-left\ntail",
            right: "head\n# new\nreal-right\ntail",
            options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: #"^# "#)])
        )

        XCTAssertEqual(rows.map(\.id), [id(1, 1), id(2, 2), id(3, nil), id(4, 3), id(5, 4)])
        XCTAssertEqual(rows.map(\.kind), [.unchanged, .unchanged, .unchanged, .modified, .unchanged])
        XCTAssertEqual(DiffSummary(rows: rows).differences, 1)
    }

    func testLineFilterMarkerCannotCollideWithFileContent() throws {
        let rows = try LineDiff.compare(
            left: "\u{E000}MACMERGE_FILTERED_LINE",
            right: "# ignored",
            options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: #"^# "#)])
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 1)
    }

    func testOneSidedLineFilterDoesNotSplitReplacement() throws {
        let options = LineDiffOptions(lineFilters: [LineFilterRule(pattern: #"^# "#)])
        let rows = try LineDiff.compare(left: "# ignored", right: "real", options: options)

        XCTAssertEqual(rows.map(\.kind), [.modified])
        let merged = try XCTUnwrap(LineMerge.applyAll(
            direction: .leftToRight,
            left: "# ignored",
            right: "real",
            options: options
        ))
        XCTAssertEqual(merged.right, "# ignored")
    }

    func testLineFiltersPreserveIgnoreBlankLines() throws {
        let rows = try LineDiff.compare(
            left: "head\n\n# old\ntail",
            right: "head\n \n# new\ntail",
            options: LineDiffOptions(
                ignoreBlankLines: true,
                lineFilters: [LineFilterRule(pattern: #"^# "#)]
            )
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 0)
    }

    func testWinMergeSubstitutionFilterFixtures() throws {
        let options = LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: #"\d{4}-\d{2}-\d{2}"#, replacement: "XXXX-XX-XX"),
        ])
        let fixtures: [(String, String, Int)] = [
            ("a\n# 2023-10-09\nc", "a\n# 2023-10-08\nc", 0),
            ("a\n# 2023-10-09\nb1\nc", "a\n# 2023-10-08\nb2\nc", 1),
        ]

        for algorithm in [DiffAlgorithm.default, .minimal, .patience, .histogram] {
            for fixture in fixtures {
                var algorithmOptions = options
                algorithmOptions.algorithm = algorithm
                let rows = try LineDiff.compare(
                    left: fixture.0,
                    right: fixture.1,
                    options: algorithmOptions
                )
                XCTAssertEqual(DiffSummary(rows: rows).differences, fixture.2)
            }
        }
    }

    func testDisabledSubstitutionsDoNotAffectComparison() throws {
        let options = LineDiffOptions(
            substitutionsEnabled: false,
            substitutions: [SubstitutionRule(pattern: #"\d+"#, replacement: "")]
        )

        let rows = try LineDiff.compare(left: "value 1\n", right: "value 2\n", options: options)

        XCTAssertEqual(rows.map(\.kind), [.modified])
    }

    func testSubstitutionFiltersUseWinMergeBackreferencesAndEscapes() throws {
        let captureRows = try LineDiff.compare(
            left: "ABC-123",
            right: "123:ABC",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: #"([A-Z]+)-(\d+)"#, replacement: #"\2:\1"#),
            ])
        )
        let escapeRows = try LineDiff.compare(
            left: "value",
            right: "A\tvalue",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: #"^(value)$"#, replacement: #"\x41\t\1"#),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: captureRows).differences, 0)
        XCTAssertEqual(DiffSummary(rows: escapeRows).differences, 0)
    }

    func testSubstitutionFiltersCanMatchAcrossLinesWithoutChangingLineCount() throws {
        let rows = try LineDiff.compare(
            left: "old\nvalue-a",
            right: "new\nvalue-b",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: #"(old|new)\nvalue-[ab]"#, replacement: #"same\nvalue"#),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 0)
    }

    func testSubstitutionAnchorsMatchEveryLineEndingStyle() throws {
        let options = LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "^value-[ab]$", replacement: "value"),
        ])

        for ending in ["\n", "\r\n", "\r"] {
            let left = "header\(ending)value-a\(ending)footer"
            let right = "header\(ending)value-b\(ending)footer"
            XCTAssertEqual(try LineDiff.compare(left: left, right: right, options: options).filter {
                $0.kind != .unchanged
            }.count, 0, ending.debugDescription)
        }
    }

    func testRawNonUTF8SubstitutionBytesCompareExactly() throws {
        let equalRows = try LineDiff.compare(
            left: "def",
            right: "ghi",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "def", replacement: #"\x01\xEF\xab\x"#),
                SubstitutionRule(pattern: "ghi", replacement: #"\x01\xEF\xab\x"#),
            ])
        )
        let differentRows = try LineDiff.compare(
            left: "def",
            right: "ghi",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "def", replacement: #"\xEF"#),
                SubstitutionRule(pattern: "ghi", replacement: #"\xEE"#),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: equalRows).differences, 0)
        XCTAssertEqual(DiffSummary(rows: differentRows).differences, 1)
    }

    func testRawByteSubstitutionDoesNotCollideWithReplacementLiteral() throws {
        let rows = try LineDiff.compare(
            left: "literal",
            right: "byte",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "literal", replacement: "\u{F0000}"),
                SubstitutionRule(pattern: "byte", replacement: #"\x80"#),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 1)
    }

    func testLaterSubstitutionsMatchRawBytesFromEarlierRules() throws {
        let rows = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "left", replacement: #"\xEF"#),
                SubstitutionRule(pattern: "right", replacement: #"\xEE"#),
                SubstitutionRule(pattern: #"\xEF"#, replacement: "same"),
                SubstitutionRule(pattern: #"\x{EE}"#, replacement: "same"),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 0)
    }

    func testRawBytePatternTranslationPreservesQuotedRegexAndEscapedPrivateScalars() throws {
        let quoted = try LineDiff.compare(
            left: #"\xEF"#,
            right: "byte",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "byte", replacement: #"\xEF"#),
                SubstitutionRule(pattern: #"\Q\xEF\E"#, replacement: "literal"),
            ])
        )
        let literalPatternScalar = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "left", replacement: #"\x80"#),
                SubstitutionRule(pattern: "right", replacement: "same"),
                SubstitutionRule(pattern: "\u{F0000}", replacement: "same"),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: literalPatternScalar).differences, 1)
        XCTAssertThrowsError(try LineDiff.compare(
            left: "\u{F0000}",
            right: "byte",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "byte", replacement: #"\x80"#),
                SubstitutionRule(pattern: #"\x{F0000}"#, replacement: "private"),
            ])
        )) { error in
            XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression(#"\x{F0000}"#))
        }
    }

    func testRawByteSubstitutionsUsePcreByteClassesAndProperties() throws {
        let byteRange = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "left", replacement: #"\x80"#),
                SubstitutionRule(pattern: "right", replacement: #"\x81"#),
                SubstitutionRule(pattern: #"[\x80-\x81]"#, replacement: "same"),
            ])
        )
        let privateUseProperty = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "left", replacement: #"\x80"#),
                SubstitutionRule(pattern: "right", replacement: "private"),
                SubstitutionRule(pattern: #"\p{Co}"#, replacement: "private"),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: byteRange).differences, 0)
        XCTAssertEqual(DiffSummary(rows: privateUseProperty).differences, 1)
    }

    func testSubstitutionEngineMatchesWinMergePcreSemantics() throws {
        let crAnchors = try LineDiff.compare(
            left: "value=left\rnext",
            right: "value=right\rnext",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: #"^value=.*$"#, replacement: "same"),
            ])
        )
        let emptyRule = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "", replacement: "same"),
            ])
        )
        let terminalEmptyMatch = try LineDiff.compare(
            left: "same",
            right: "same!",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "$", replacement: "!"),
            ])
        )
        let pcreReset = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: #"(?:left|right)\K"#, replacement: "same"),
            ])
        )
        let partialHex = try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "left", replacement: #"\x1G"#),
                SubstitutionRule(pattern: "right", replacement: #"\x01"#),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: crAnchors).differences, 0)
        XCTAssertEqual(DiffSummary(rows: emptyRule).differences, 1)
        XCTAssertEqual(DiffSummary(rows: terminalEmptyMatch).differences, 1)
        XCTAssertEqual(DiffSummary(rows: pcreReset).differences, 1)
        XCTAssertEqual(DiffSummary(rows: partialHex).differences, 0)
    }

    func testUnmatchedCaptureStopsCurrentRuleAfterEarlierMatches() throws {
        let rows = try LineDiff.compare(
            left: "a a",
            right: "x a",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: #"(a)|(b)"#, replacement: #"\2"#),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 1)
    }

    func testComparisonFiltersRejectInvalidOrStructuralReplacements() throws {
        XCTAssertThrowsError(try LineDiff.compare(
            left: "left",
            right: "right",
            options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: "[")])
        )) { error in
            XCTAssertEqual(error as? LineDiffError, .invalidRegularExpression("["))
        }
        XCTAssertThrowsError(try LineDiff.compare(
            left: "2026-08-04",
            right: "2026-08-05",
            options: LineDiffOptions(substitutions: [
                SubstitutionRule(pattern: "2026", replacement: #"2026\n"#),
            ])
        )) { error in
            XCTAssertEqual(error as? LineDiffError, .filterChangedLineStructure)
        }
    }

    func testCFamilyCommentDifferencesAreIgnored() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .cFamily)
        let singleLine = try LineDiff.compare(
            left: "a\n// left\nc",
            right: "a\n// right\nc",
            options: options
        )
        let block = try LineDiff.compare(
            left: "a\n/*\nleft\n*/\nc",
            right: "a\n/*\nright\nextra\n*/\nc",
            options: options
        )
        let inline = try LineDiff.compare(
            left: "value(); // left",
            right: "value(); // right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: singleLine).differences, 0)
        XCTAssertEqual(DiffSummary(rows: block).differences, 0)
        XCTAssertEqual(DiffSummary(rows: inline).differences, 0)
    }

    func testCFamilyCommentFilteringPreservesCodeAndQuotedDelimiters() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .cFamily)
        let code = try LineDiff.compare(
            left: "left(); // comment",
            right: "right(); // comment",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: #"let url = "https://left";"#,
            right: #"let url = "https://right";"#,
            options: options
        )
        let removed = try LineDiff.compare(
            left: "prefix/* comment */suffix",
            right: "prefixsuffix",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: code).differences, 1)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: removed).differences, 0)
    }

    func testWholeCommentLinesMatchWinMergeEolAndColumnRules() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .cFamily)
        let columnZero = try LineDiff.compare(
            left: "head\n// comment\ntail\n",
            right: "head\ntail\n",
            options: options
        )
        let indented = try LineDiff.compare(
            left: "head\n  // comment\ntail\n",
            right: "head\ntail\n",
            options: options
        )
        let unterminated = try LineDiff.compare(
            left: "head\n// comment",
            right: "head\n",
            options: options
        )
        let blankInBlock = try LineDiff.compare(
            left: "head\n/* comment\n\n*/\ntail\n",
            right: "head\n/* comment\n*/\ntail\n",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: columnZero).differences, 0)
        XCTAssertEqual(DiffSummary(rows: indented).differences, 1)
        XCTAssertEqual(DiffSummary(rows: unterminated).differences, 1)
        XCTAssertEqual(DiffSummary(rows: blankInBlock).differences, 1)
    }

    func testCommentSyntaxUsesWinMergeExtensionFamilies() {
        XCTAssertEqual(CommentSyntax(fileExtension: "CPP"), .cFamily)
        XCTAssertEqual(CommentSyntax(fileExtension: "sh"), .hashLine)
        XCTAssertEqual(CommentSyntax(fileExtension: "py"), .python)
        XCTAssertEqual(CommentSyntax(fileExtension: "sql"), .sql)
        XCTAssertEqual(CommentSyntax(fileExtension: "xml"), .markup)
        XCTAssertEqual(CommentSyntax(fileExtension: "html"), .markup)
        XCTAssertEqual(CommentSyntax(fileExtension: "m"), .matlab)
        XCTAssertEqual(CommentSyntax(fileExtension: "properties"), .properties)
        XCTAssertEqual(CommentSyntax(fileExtension: "toml"), .toml)
        XCTAssertEqual(CommentSyntax(fileExtension: "yaml"), .yaml)
        XCTAssertEqual(CommentSyntax(fileExtension: "vb"), .basic)
        XCTAssertEqual(CommentSyntax(fileExtension: "css"), .css)
        XCTAssertEqual(CommentSyntax(fileExtension: "ini"), .ini)
        XCTAssertEqual(CommentSyntax(fileExtension: "tex"), .tex)
        XCTAssertEqual(CommentSyntax(fileExtension: "vhdl"), .adaVhdl)
        XCTAssertEqual(CommentSyntax(fileExtension: "JS"), .cFamily)
        XCTAssertEqual(CommentSyntax(fileExtension: "json"), .cFamily)
        XCTAssertEqual(CommentSyntax(fileExtension: "rul"), .cFamily)
        XCTAssertEqual(CommentSyntax(fileExtension: "dcc"), .dcl)
        XCTAssertEqual(CommentSyntax(fileExtension: "rexx"), .rexx)
        XCTAssertEqual(CommentSyntax(fileExtension: "scm"), .lispSiod)
        XCTAssertEqual(CommentSyntax(fileExtension: "F90"), .fortran)
        XCTAssertEqual(CommentSyntax(fileExtension: "nsh"), .nsis)
        XCTAssertEqual(CommentSyntax(fileExtension: "rc2"), .resources)
        XCTAssertEqual(CommentSyntax(fileExtension: "vh"), .verilog)
        XCTAssertEqual(CommentSyntax(fileExtension: "cmd"), .batch)
        XCTAssertEqual(CommentSyntax(fileExtension: "pas"), .pascal)
        XCTAssertEqual(CommentSyntax(fileExtension: "lua"), .lua)
        XCTAssertEqual(CommentSyntax(fileExtension: "iss"), .innoSetup)
        XCTAssertEqual(CommentSyntax(fileExtension: "di"), .dlang)
        XCTAssertEqual(CommentSyntax(fileExtension: "GO"), .go)
        XCTAssertEqual(CommentSyntax(fileExtension: "rs"), .rust)
        XCTAssertEqual(CommentSyntax(fileExtension: "abap"), .abap)
        XCTAssertEqual(CommentSyntax(fileExtension: "au3"), .autoIt)
        XCTAssertEqual(CommentSyntax(fileExtension: "FSX"), .fsharp)
        XCTAssertNil(CommentSyntax(fileExtension: "fsi"))
        XCTAssertEqual(CommentSyntax(fileExtension: "ascx"), .asp)
        XCTAssertEqual(CommentSyntax(fileExtension: "PHP5"), .php)
        XCTAssertEqual(CommentSyntax(fileExtension: "tpl"), .smarty)
        XCTAssertNil(CommentSyntax(fileExtension: "mjs"))
        XCTAssertNil(CommentSyntax(fileExtension: "f95"))
        XCTAssertNil(CommentSyntax(fileExtension: "sv"))
        XCTAssertNil(CommentSyntax(fileExtension: "txt"))
    }

    func testHashCommentDifferencesAreIgnoredWithoutChangingQuotedHashes() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .hashLine)
        let comments = try LineDiff.compare(
            left: "value = 1 # left\n# old",
            right: "value = 1 # right\n# new",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: "value = \"#left\"",
            right: "value = \"#right\"",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
    }

    func testPythonTripleQuotedHashesRemainSignificant() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .python)
        let rows = try LineDiff.compare(
            left: "\"\"\"\n# left\n\"\"\"\nvalue = 1 # comment",
            right: "\"\"\"\n# right\n\"\"\"\nvalue = 1 # changed",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 1)
    }

    func testSQLCommentDifferencesAreIgnoredWithoutChangingQuotedDelimiters() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .sql)
        let comments = try LineDiff.compare(
            left: "SELECT 1; -- left\n/* old\ncomment */",
            right: "SELECT 1; // right\n/* new\ncomment */",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: #"SELECT '-- left';"#,
            right: #"SELECT '-- right';"#,
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
    }

    func testMarkupCommentDifferencesAreIgnoredWithoutChangingQuotedDelimiters() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .markup)
        let comments = try LineDiff.compare(
            left: "<root>\n<!-- left\nold -->\n</root>",
            right: "<root>\n<!-- right\nnew -->\n</root>",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: #"<node value="<!-- left -->"/>"#,
            right: #"<node value="<!-- right -->"/>"#,
            options: options
        )
        let prose = try LineDiff.compare(
            left: "don't <!-- left --> change",
            right: "don't <!-- right --> change",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: prose).differences, 0)
    }

    func testMatlabCommentsPreserveStringsAndTransposeOperators() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .matlab)
        let comments = try LineDiff.compare(
            left: "value = data'; % left\n%{\nold\n%}",
            right: "value = data'; % right\n%{\nnew\nextra\n%}",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: "value = '% left';",
            right: "value = '% right';",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
    }

    func testPropertiesCommentsRequireLogicalLineStart() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .properties)
        let comments = try LineDiff.compare(
            left: "  # left\n! old\nkey=value#left",
            right: "  # right\n! new\nkey=value#right",
            options: options
        )
        let continuation = try LineDiff.compare(
            left: "key=value\\\n  # left",
            right: "key=value\\\n  # right",
            options: options
        )
        let nonBreakingSpace = try LineDiff.compare(
            left: "\u{00A0}#left",
            right: "\u{00A0}#right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 1)
        XCTAssertEqual(DiffSummary(rows: continuation).differences, 1)
        XCTAssertEqual(DiffSummary(rows: nonBreakingSpace).differences, 1)
    }

    func testTomlCommentsPreserveSingleAndMultilineStrings() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .toml)
        let comments = try LineDiff.compare(
            left: "key = 1 # left",
            right: "key = 1 # right",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: "key = '# left'",
            right: "key = '# right'",
            options: options
        )
        let multiline = try LineDiff.compare(
            left: "key = \"\"\"\n# left\n\"\"\"",
            right: "key = \"\"\"\n# right\n\"\"\"",
            options: options
        )
        let escapedTriple = try LineDiff.compare(
            left: "key = \"\"\"escaped \\\"\"\" # left\nend\"\"\"",
            right: "key = \"\"\"escaped \\\"\"\" # right\nend\"\"\"",
            options: options
        )
        let fiveQuoteEnding = try LineDiff.compare(
            left: "key = \"\"\"value\"\"\"\"\" # left",
            right: "key = \"\"\"value\"\"\"\"\" # right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: multiline).differences, 1)
        XCTAssertEqual(DiffSummary(rows: escapedTriple).differences, 1)
        XCTAssertEqual(DiffSummary(rows: fiveQuoteEnding).differences, 0)
    }

    func testYamlCommentsPreserveScalarsAndUrlFragments() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .yaml)
        let comments = try LineDiff.compare(
            left: "key: value # left",
            right: "key: value # right",
            options: options
        )
        let url = try LineDiff.compare(
            left: "url: https://host/#left",
            right: "url: https://host/#right",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: "key: \"first\n# left\nlast\"",
            right: "key: \"first\n# right\nlast\"",
            options: options
        )
        let block = try LineDiff.compare(
            left: "key: |\n  # left",
            right: "key: |\n  # right",
            options: options
        )
        let plainApostrophe = try LineDiff.compare(
            left: "key: can't # left",
            right: "key: can't # right",
            options: options
        )
        let nonBreakingSpace = try LineDiff.compare(
            left: "key: value\u{00A0}#left",
            right: "key: value\u{00A0}#right",
            options: options
        )
        let trailingIndicator = try LineDiff.compare(
            left: "key: value|\n# left",
            right: "key: value|\n# right",
            options: options
        )
        let taggedBlock = try LineDiff.compare(
            left: "picture: !!binary |\n  # left",
            right: "picture: !!binary |\n  # right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: url).differences, 1)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: block).differences, 1)
        XCTAssertEqual(DiffSummary(rows: plainApostrophe).differences, 0)
        XCTAssertEqual(DiffSummary(rows: nonBreakingSpace).differences, 1)
        XCTAssertEqual(DiffSummary(rows: trailingIndicator).differences, 0)
        XCTAssertEqual(DiffSummary(rows: taggedBlock).differences, 1)
    }

    func testBasicCssIniTexAndAdaVhdlCommentFamilies() throws {
        let fixtures: [(CommentSyntax, String, String)] = [
            (.basic, "value = 1 ' left", "value = 1 ' right"),
            (.css, "value { /* left */ color: red; }", "value { /* right */ color: red; }"),
            (.ini, "  ; left", "  ; right"),
            (.tex, "value % left", "value % right"),
            (.adaVhdl, "value := 1; -- left", "value := 1; -- right"),
        ]
        for (syntax, left, right) in fixtures {
            let rows = try LineDiff.compare(
                left: left,
                right: right,
                options: LineDiffOptions(ignoreComments: true, commentSyntax: syntax)
            )
            XCTAssertEqual(DiffSummary(rows: rows).differences, 0, "Syntax: \(syntax)")
        }

        let basicString = try LineDiff.compare(
            left: #"value = "' left""#,
            right: #"value = "' right""#,
            options: LineDiffOptions(ignoreComments: true, commentSyntax: .basic)
        )
        let inlineIni = try LineDiff.compare(
            left: "value=left;still-value",
            right: "value=right;still-value",
            options: LineDiffOptions(ignoreComments: true, commentSyntax: .ini)
        )
        let texString = try LineDiff.compare(
            left: #"value = "% left""#,
            right: #"value = "% right""#,
            options: LineDiffOptions(ignoreComments: true, commentSyntax: .tex)
        )

        XCTAssertEqual(DiffSummary(rows: basicString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: inlineIni).differences, 1)
        XCTAssertEqual(DiffSummary(rows: texString).differences, 1)
    }

    func testJavaScriptJsonAndInstallShieldUseLegacyCFamilyScanner() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .cFamily)
        let jsonComment = try LineDiff.compare(
            left: #"{"value": 1} // left"#,
            right: #"{"value": 1} // right"#,
            options: options
        )
        let quoted = try LineDiff.compare(
            left: #"const value = "https://left";"#,
            right: #"const value = "https://right";"#,
            options: options
        )
        let templateLiteral = try LineDiff.compare(
            left: "const value = `https://left`;",
            right: "const value = `https://right`;",
            options: options
        )
        let continuedComment = try LineDiff.compare(
            left: "// old\\\nleft continuation\nend",
            right: "// new\\\nright continuation\nend",
            options: options
        )
        let preprocessorOverlap = try LineDiff.compare(
            left: "#/*/ left",
            right: "#/*/ right",
            options: options
        )
        let carriedQuote = try LineDiff.compare(
            left: "\"start\\\n\"# \"http://left\"",
            right: "\"start\\\n\"# \"http://right\"",
            options: options
        )
        let inheritedBlock = try LineDiff.compare(
            left: "/* comment\n*/#/*/ left",
            right: "/* comment\n*/#/*/ right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: jsonComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: templateLiteral).differences, 0)
        XCTAssertEqual(DiffSummary(rows: continuedComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: preprocessorOverlap).differences, 1)
        XCTAssertEqual(DiffSummary(rows: carriedQuote).differences, 1)
        XCTAssertEqual(DiffSummary(rows: inheritedBlock).differences, 1)
    }

    func testDclAndRexxCommentContinuationMatchesCrystalEdit() throws {
        let dcl = try LineDiff.compare(
            left: "// old\\\nleft continuation\n/* old */ end",
            right: "// new\\\nright continuation\n/* new */ end",
            options: LineDiffOptions(ignoreComments: true, commentSyntax: .dcl)
        )
        let rexx = try LineDiff.compare(
            left: "// old\\\nleft continuation\n/* old */ end",
            right: "// new\\\nright continuation\n/* new */ end",
            options: LineDiffOptions(ignoreComments: true, commentSyntax: .rexx)
        )

        XCTAssertEqual(DiffSummary(rows: dcl).differences, 1)
        XCTAssertEqual(DiffSummary(rows: rexx).differences, 0)
    }

    func testLispAndSiodCommentDelimitersMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .lispSiod)
        let comments = try LineDiff.compare(
            left: "; left\n;| old\ncomment |; value",
            right: "; right\n;| new\ncomment |; value",
            options: options
        )
        let terminalSemicolon = try LineDiff.compare(
            left: "head\n;\ntail\n",
            right: "head\ntail\n",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: "\"; left\"",
            right: "\"; right\"",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: terminalSemicolon).differences, 1)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
    }

    func testFortranCommentColumnsAndContinuationMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .fortran)
        let comments = try LineDiff.compare(
            left: "C left\nvalue = 1 ! old",
            right: "c right\nvalue = 1 ! new",
            options: options
        )
        let columnZeroCall = try LineDiff.compare(
            left: "call left",
            right: "call right",
            options: options
        )
        let indentedCall = try LineDiff.compare(
            left: " call left",
            right: " call right",
            options: options
        )
        let continuedComment = try LineDiff.compare(
            left: "! old\\\nleft continuation\nend",
            right: "! new\\\nright continuation\nend",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: columnZeroCall).differences, 0)
        XCTAssertEqual(DiffSummary(rows: indentedCall).differences, 1)
        XCTAssertEqual(DiffSummary(rows: continuedComment).differences, 0)
    }

    func testNsisResourcesAndVerilogCommentRulesMatchCrystalEdit() throws {
        let nsisOptions = LineDiffOptions(ignoreComments: true, commentSyntax: .nsis)
        let nsisSlash = try LineDiff.compare(
            left: "value // left",
            right: "value // right",
            options: nsisOptions
        )
        let nsisSemicolon = try LineDiff.compare(
            left: "value ; left",
            right: "value ; right",
            options: nsisOptions
        )
        let resourcePreprocessor = try LineDiff.compare(
            left: #"#define URL "https://left""#,
            right: #"#define URL "https://right""#,
            options: LineDiffOptions(ignoreComments: true, commentSyntax: .resources)
        )
        let verilogContinuation = try LineDiff.compare(
            left: "// old\\\nleft continuation\nend",
            right: "// new\\\nright continuation\nend",
            options: LineDiffOptions(ignoreComments: true, commentSyntax: .verilog)
        )

        XCTAssertEqual(DiffSummary(rows: nsisSlash).differences, 0)
        XCTAssertEqual(DiffSummary(rows: nsisSemicolon).differences, 1)
        XCTAssertEqual(DiffSummary(rows: resourcePreprocessor).differences, 0)
        XCTAssertEqual(DiffSummary(rows: verilogContinuation).differences, 1)
    }

    func testBatchCommentRecognitionMatchesCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .batch)
        let rem = try LineDiff.compare(
            left: "  REM left",
            right: "  rem right",
            options: options
        )
        let atRem = try LineDiff.compare(
            left: "@REM left",
            right: "@REM right",
            options: options
        )
        let doubleColon = try LineDiff.compare(
            left: "::left",
            right: "::right",
            options: options
        )
        let bareDoubleColon = try LineDiff.compare(
            left: "head\n::\ntail\n",
            right: "head\ntail\n",
            options: options
        )
        let utf16Colon = try LineDiff.compare(
            left: ":!\u{0301}left",
            right: ":!\u{0301}right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: rem).differences, 0)
        XCTAssertEqual(DiffSummary(rows: atRem).differences, 1)
        XCTAssertEqual(DiffSummary(rows: doubleColon).differences, 0)
        XCTAssertEqual(DiffSummary(rows: bareDoubleColon).differences, 1)
        XCTAssertEqual(DiffSummary(rows: utf16Colon).differences, 0)
    }

    func testPascalCommentsAndDirectivesMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .pascal)
        let comments = try LineDiff.compare(
            left: "value { old } end\n(* old *)\nvalue // old",
            right: "value { new } end\n(* new *)\nvalue // new",
            options: options
        )
        let directives = try LineDiff.compare(
            left: "{$OLD}\n(*$OLD*)",
            right: "{$NEW}\n(*$NEW*)",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: "value := '// left';",
            right: "value := '// right';",
            options: options
        )
        let continuedComment = try LineDiff.compare(
            left: "// old\\\nleft continuation\nend",
            right: "// new\\\nright continuation\nend",
            options: options
        )
        let blankInBlock = try LineDiff.compare(
            left: "head\n(* comment\n\n*)\ntail\n",
            right: "head\n(* comment\n*)\ntail\n",
            options: options
        )
        let escapedRawString = try LineDiff.compare(
            left: "'\\'''\n// left",
            right: "'\\'''\n// right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: directives).differences, 2)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: continuedComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: blankInBlock).differences, 1)
        XCTAssertEqual(DiffSummary(rows: escapedRawString).differences, 1)
    }

    func testLuaLongCommentsAndStringsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .lua)
        let comments = try LineDiff.compare(
            left: "value -- old\n--[=[ old\ncomment ]=] end",
            right: "value -- new\n--[=[ new\ncomment ]=] end",
            options: options
        )
        let longString = try LineDiff.compare(
            left: "value = [=[-- left]=]",
            right: "value = [=[-- right]=]",
            options: options
        )
        let mismatchedCloser = try LineDiff.compare(
            left: "--[=[ old\n]]\nleft hidden",
            right: "--[=[ new\n]]\nright hidden",
            options: options
        )
        let wrappedEquals = try LineDiff.compare(
            left: "--[================[ old\n]] left",
            right: "--[================[ new\n]] right",
            options: options
        )
        let combiningLineComment = try LineDiff.compare(
            left: "--\u{0301}left",
            right: "--\u{0301}right",
            options: options
        )
        let embeddedNul = try LineDiff.compare(
            left: "value\0-- left",
            right: "value\0-- right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: longString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: mismatchedCloser).differences, 0)
        XCTAssertEqual(DiffSummary(rows: wrappedEquals).differences, 1)
        XCTAssertEqual(DiffSummary(rows: combiningLineComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: embeddedNul).differences, 1)
    }

    func testInnoSetupSwitchesBetweenSetupAndPascalComments() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .innoSetup)
        let setupComment = try LineDiff.compare(
            left: "  ; left",
            right: "  ; right",
            options: options
        )
        let inlineSemicolon = try LineDiff.compare(
            left: "value ; left",
            right: "value ; right",
            options: options
        )
        let constant = try LineDiff.compare(
            left: "Source: {app}\\left",
            right: "Source: {app}\\right",
            options: options
        )
        let codeComment = try LineDiff.compare(
            left: "[Code]\nvalue := 1; // left\n{ old }",
            right: "[Code]\nvalue := 1; // right\n{ new }",
            options: options
        )
        let quotedPrefix = try LineDiff.compare(
            left: "\"value\" ; left",
            right: "\"value\" ; right",
            options: options
        )
        let preprocessor = try LineDiff.compare(
            left: "#; left",
            right: "#; right",
            options: options
        )
        let combiningComment = try LineDiff.compare(
            left: ";\u{0301}left",
            right: ";\u{0301}right",
            options: options
        )
        let embeddedNul = try LineDiff.compare(
            left: "{x\0}; left",
            right: "{x\0}; right",
            options: options
        )
        let sectionInsideComment = try LineDiff.compare(
            left: "[Code]\n(* old\n[Files]\nvalue ; left",
            right: "[Code]\n(* new\n[Files]\nvalue ; right",
            options: options
        )
        let nonBreakingSpace = try LineDiff.compare(
            left: "\u{00A0}; left",
            right: "\u{00A0}; right",
            options: options
        )
        let combinedSectionCloser = try LineDiff.compare(
            left: "[Code]\u{0301}\nvalue // left",
            right: "[Code]\u{0301}\nvalue // right",
            options: options
        )
        let nonBreakingSectionPrefix = try LineDiff.compare(
            left: "\u{00A0}[Code]\nvalue // left",
            right: "\u{00A0}[Code]\nvalue // right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: setupComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: inlineSemicolon).differences, 1)
        XCTAssertEqual(DiffSummary(rows: constant).differences, 1)
        XCTAssertEqual(DiffSummary(rows: codeComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: quotedPrefix).differences, 0)
        XCTAssertEqual(DiffSummary(rows: preprocessor).differences, 0)
        XCTAssertEqual(DiffSummary(rows: combiningComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: embeddedNul).differences, 1)
        XCTAssertEqual(DiffSummary(rows: sectionInsideComment).differences, 1)
        XCTAssertEqual(DiffSummary(rows: nonBreakingSpace).differences, 1)
        XCTAssertEqual(DiffSummary(rows: combinedSectionCloser).differences, 0)
        XCTAssertEqual(DiffSummary(rows: nonBreakingSectionPrefix).differences, 1)
    }

    func testGoCommentsAndRawStringsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .go)
        let comments = try LineDiff.compare(
            left: "value // left\n/* old\ncomment */ end",
            right: "value // right\n/* new\ncomment */ end",
            options: options
        )
        let rawString = try LineDiff.compare(
            left: "value := `https://left\n/* left */`",
            right: "value := `https://right\n/* right */`",
            options: options
        )
        let nonNested = try LineDiff.compare(
            left: "/* outer /* inner */ left",
            right: "/* outer /* inner */ right",
            options: options
        )
        let noContinuation = try LineDiff.compare(
            left: "// old\\\nleft continuation",
            right: "// new\\\nright continuation",
            options: options
        )
        let embeddedNul = try LineDiff.compare(
            left: "value\0// left",
            right: "value\0// right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: rawString).differences, 2)
        XCTAssertEqual(DiffSummary(rows: nonNested).differences, 1)
        XCTAssertEqual(DiffSummary(rows: noContinuation).differences, 1)
        XCTAssertEqual(DiffSummary(rows: embeddedNul).differences, 1)
    }

    func testRustCommentsAndRawStringsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .rust)
        let nestedComments = try LineDiff.compare(
            left: "/* outer /* old */ end */ value",
            right: "/* outer /* new */ end */ value",
            options: options
        )
        let rawString = try LineDiff.compare(
            left: "value = r#\"https://left/*x*/\"#;",
            right: "value = r#\"https://right/*y*/\"#;",
            options: options
        )
        let characterLiteral = try LineDiff.compare(
            left: "value = '// left';",
            right: "value = '// right';",
            options: options
        )
        let emptyRawString = try LineDiff.compare(
            left: "r\"\" // left\nleft hidden",
            right: "r\"\" // right\nright hidden",
            options: options
        )
        let embeddedNul = try LineDiff.compare(
            left: "/* old\0*/\nleft hidden",
            right: "/* new\0*/\nright hidden",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: nestedComments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: rawString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: characterLiteral).differences, 0)
        XCTAssertEqual(DiffSummary(rows: emptyRawString).differences, 2)
        XCTAssertEqual(DiffSummary(rows: embeddedNul).differences, 0)
    }

    func testDCommentsAndTokenStringsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .dlang)
        let comments = try LineDiff.compare(
            left: "value // left\n/+ outer /+ old +/ end +/ value",
            right: "value // right\n/+ outer /+ new +/ end +/ value",
            options: options
        )
        let tokenString = try LineDiff.compare(
            left: "value = q{https://left /+ text +/};",
            right: "value = q{https://right /+ text +/};",
            options: options
        )
        let rawQuote = try LineDiff.compare(
            left: "value = q\"[https://left/]\";",
            right: "value = q\"[https://right/]\";",
            options: options
        )
        let persistentString = try LineDiff.compare(
            left: "\"https://left\n// inside string",
            right: "\"https://right\n// inside string",
            options: options
        )
        let embeddedNul = try LineDiff.compare(
            left: "value\0/+ left +/",
            right: "value\0/+ right +/",
            options: options
        )
        let aliasedCookieByte = try LineDiff.compare(
            left: "q\"[value]\" `// left`",
            right: "q\"[value]\" `// right`",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: tokenString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: rawQuote).differences, 1)
        XCTAssertEqual(DiffSummary(rows: persistentString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: embeddedNul).differences, 1)
        XCTAssertEqual(DiffSummary(rows: aliasedCookieByte).differences, 1)
    }

    func testAbapCommentsAndTemplatesMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .abap)
        let comments = try LineDiff.compare(
            left: "* left\nvalue \" left\nvalue ## left",
            right: "* right\nvalue \" right\nvalue ## right",
            options: options
        )
        let apostrophe = try LineDiff.compare(
            left: "value = '\" left'",
            right: "value = '\" right'",
            options: options
        )
        let template = try LineDiff.compare(
            left: "value = |\" left|",
            right: "value = |\" right|",
            options: options
        )
        let templateExpression = try LineDiff.compare(
            left: "value = |{ name \" left }|",
            right: "value = |{ name \" right }|",
            options: options
        )
        let terminalQuote = try LineDiff.compare(
            left: "value \"",
            right: "other \"",
            options: options
        )
        let continuedComment = try LineDiff.compare(
            left: "* old\\\nleft continuation",
            right: "* new\\\nright continuation",
            options: options
        )
        let interpolation = try LineDiff.compare(
            left: "value = 'prefix { name 'text' \" left } suffix'",
            right: "value = 'prefix { name 'text' \" right } suffix'",
            options: options
        )
        let templateSection = try LineDiff.compare(
            left: "value = |prefix { name 'text' \" left } suffix|",
            right: "value = |prefix { name 'text' \" right } suffix|",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: apostrophe).differences, 1)
        XCTAssertEqual(DiffSummary(rows: template).differences, 1)
        XCTAssertEqual(DiffSummary(rows: templateExpression).differences, 0)
        XCTAssertEqual(DiffSummary(rows: terminalQuote).differences, 1)
        XCTAssertEqual(DiffSummary(rows: continuedComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: interpolation).differences, 0)
        XCTAssertEqual(DiffSummary(rows: templateSection).differences, 1)
    }

    func testAutoItCommentsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .autoIt)
        let lineComment = try LineDiff.compare(
            left: "value ; left",
            right: "value ; right",
            options: options
        )
        let block = try LineDiff.compare(
            left: "#cs old\nleft\n#ce value",
            right: "#cs new\nright\n#ce value",
            options: options
        )
        let longBlock = try LineDiff.compare(
            left: "  #comments-start old\nleft\n  #comments-end value",
            right: "  #comments-start new\nright\n  #comments-end value",
            options: options
        )
        let mixedCase = try LineDiff.compare(
            left: "#Cs left",
            right: "#Cs right",
            options: options
        )
        let quoted = try LineDiff.compare(
            left: "value = '; left'",
            right: "value = '; right'",
            options: options
        )
        let preprocessorComment = try LineDiff.compare(
            left: "#include \"; left\"",
            right: "#include \"; right\"",
            options: options
        )
        let variableBlock = try LineDiff.compare(
            left: "$value #cs old\nleft\n#ce",
            right: "$value #cs new\nright\n#ce",
            options: options
        )
        let concurrentVariables = try LineDiff.compare(
            left: "$@ #cs old\nleft\n#ce",
            right: "$@ #cs new\nright\n#ce",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: lineComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: block).differences, 0)
        XCTAssertEqual(DiffSummary(rows: longBlock).differences, 0)
        XCTAssertEqual(DiffSummary(rows: mixedCase).differences, 1)
        XCTAssertEqual(DiffSummary(rows: quoted).differences, 1)
        XCTAssertEqual(DiffSummary(rows: preprocessorComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: variableBlock).differences, 0)
        XCTAssertEqual(DiffSummary(rows: concurrentVariables).differences, 2)
    }

    func testFSharpCommentsAndRawStringsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .fsharp)
        let comments = try LineDiff.compare(
            left: "value // left\n(* old\ncomment *) value",
            right: "value // right\n(* new\ncomment *) value",
            options: options
        )
        let rawString = try LineDiff.compare(
            left: "value = \"\"\"https://left\n(* text *)\"\"\"",
            right: "value = \"\"\"https://right\n(* other *)\"\"\"",
            options: options
        )
        let nonNested = try LineDiff.compare(
            left: "(* outer (* inner *) left",
            right: "(* outer (* inner *) right",
            options: options
        )
        let preprocessor = try LineDiff.compare(
            left: "#define URL \"https://left\"",
            right: "#define URL \"https://right\"",
            options: options
        )
        let continuedComment = try LineDiff.compare(
            left: "// old\\\nleft continuation",
            right: "// new\\\nright continuation",
            options: options
        )
        let overlappingTriple = try LineDiff.compare(
            left: "\"\"\"\"// left",
            right: "\"\"\"\"// right",
            options: options
        )
        let guardedTriple = try LineDiff.compare(
            left: "\"\"\"\"\"// left",
            right: "\"\"\"\"\"// right",
            options: options
        )
        let preprocessorParenStar = try LineDiff.compare(
            left: "#define )* left *) value",
            right: "#define )* right *) value",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: rawString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: nonNested).differences, 1)
        XCTAssertEqual(DiffSummary(rows: preprocessor).differences, 0)
        XCTAssertEqual(DiffSummary(rows: continuedComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: overlappingTriple).differences, 0)
        XCTAssertEqual(DiffSummary(rows: guardedTriple).differences, 0)
        XCTAssertEqual(DiffSummary(rows: preprocessorParenStar).differences, 0)
    }

    func testPhpEmbeddedCommentsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .php)
        let comments = try LineDiff.compare(
            left: "<p>x</p><?php // left\n/* old */ $value; ?>",
            right: "<p>x</p><?php // right\n/* new */ $value; ?>",
            options: options
        )
        let hash = try LineDiff.compare(
            left: "<?php $value; # left ?>tail",
            right: "<?php $value; # right ?>tail",
            options: options
        )
        let blockProtectedCloser = try LineDiff.compare(
            left: "<?php /* ?> left */ $value; ?>",
            right: "<?php /* ?> right */ $value; ?>",
            options: options
        )
        let stringProtectedCloser = try LineDiff.compare(
            left: "<?php \"?> left\"; ?>",
            right: "<?php \"?> right\"; ?>",
            options: options
        )
        let htmlComment = try LineDiff.compare(
            left: "<!-- left --><p>x</p>",
            right: "<!-- right --><p>x</p>",
            options: options
        )
        let embeddedNul = try LineDiff.compare(
            left: "<?php value\0// left ?>",
            right: "<?php value\0// right ?>",
            options: options
        )
        let attributeEmbeddedOpener = try LineDiff.compare(
            left: "<div data=<?php // left ?>>",
            right: "<div data=<?php // right ?>>",
            options: options
        )
        let overlappingCloser = try LineDiff.compare(
            left: "<?># left",
            right: "<?># right",
            options: options
        )
        let lineCommentBoundary = try LineDiff.compare(
            left: "<?php // comment ?>left",
            right: "<?php // comment ?>right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: hash).differences, 0)
        XCTAssertEqual(DiffSummary(rows: blockProtectedCloser).differences, 0)
        XCTAssertEqual(DiffSummary(rows: stringProtectedCloser).differences, 1)
        XCTAssertEqual(DiffSummary(rows: htmlComment).differences, 0)
        XCTAssertEqual(DiffSummary(rows: embeddedNul).differences, 1)
        XCTAssertEqual(DiffSummary(rows: attributeEmbeddedOpener).differences, 1)
        XCTAssertEqual(DiffSummary(rows: overlappingCloser).differences, 1)
        XCTAssertEqual(DiffSummary(rows: lineCommentBoundary).differences, 1)
    }

    func testAspEmbeddedCommentsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .asp)
        let comments = try LineDiff.compare(
            left: "<% value ' left %>tail",
            right: "<% value ' right %>tail",
            options: options
        )
        let stringDoesNotProtectCloser = try LineDiff.compare(
            left: "<% value = \"%>left\" %>",
            right: "<% value = \"%>right\" %>",
            options: options
        )
        let phpStyleCloser = try LineDiff.compare(
            left: "<% value ' left ?>tail",
            right: "<% value ' right ?>tail",
            options: options
        )
        let lineCommentBoundary = try LineDiff.compare(
            left: "<% ' comment %>left",
            right: "<% ' comment %>right",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: stringDoesNotProtectCloser).differences, 1)
        XCTAssertEqual(DiffSummary(rows: phpStyleCloser).differences, 0)
        XCTAssertEqual(DiffSummary(rows: lineCommentBoundary).differences, 1)
    }

    func testSmartyEmbeddedCommentsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .smarty)
        let comments = try LineDiff.compare(
            left: "<p>{* left *}</p>",
            right: "<p>{* right *}</p>",
            options: options
        )
        let whitespaceBraces = try LineDiff.compare(
            left: "<p>{ value left }</p>",
            right: "<p>{ value right }</p>",
            options: options
        )
        let doubleQuoteProtectsCloser = try LineDiff.compare(
            left: "{\"} left\"}",
            right: "{\"} right\"}",
            options: options
        )
        let singleQuoteDoesNotProtectCloser = try LineDiff.compare(
            left: "{'} left'}",
            right: "{'} right'}",
            options: options
        )
        let hashVariable = try LineDiff.compare(
            left: "{#left#}",
            right: "{#right#}",
            options: options
        )
        let hashStateIsRecordLocal = try LineDiff.compare(
            left: "{#value\n{* left *}#}",
            right: "{#value\n{* right *}#}",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: comments).differences, 0)
        XCTAssertEqual(DiffSummary(rows: whitespaceBraces).differences, 1)
        XCTAssertEqual(DiffSummary(rows: doubleQuoteProtectsCloser).differences, 1)
        XCTAssertEqual(DiffSummary(rows: singleQuoteDoesNotProtectCloser).differences, 1)
        XCTAssertEqual(DiffSummary(rows: hashVariable).differences, 1)
        XCTAssertEqual(DiffSummary(rows: hashStateIsRecordLocal).differences, 0)
    }

    func testEmbeddedScriptAndStyleCommentsMatchCrystalEdit() throws {
        let options = LineDiffOptions(ignoreComments: true, commentSyntax: .php)
        let script = try LineDiff.compare(
            left: "<script>value(); // left\n</script>",
            right: "<script>value(); // right\n</script>",
            options: options
        )
        let style = try LineDiff.compare(
            left: "<style>value {/* left */ color:red}</style>",
            right: "<style>value {/* right */ color:red}</style>",
            options: options
        )
        let uppercaseCloser = try LineDiff.compare(
            left: "<script>// old\n</SCRIPT> left",
            right: "<script>// new\n</SCRIPT> right",
            options: options
        )
        let styleAfterNul = try LineDiff.compare(
            left: "<style>\0/* left */",
            right: "<style>\0/* right */",
            options: options
        )
        let htmlCommentClearsElement = try LineDiff.compare(
            left: "<tag <!--x -->\"<!-- left -->\"",
            right: "<tag <!--x -->\"<!-- right -->\"",
            options: options
        )
        let dottedScriptTag = try LineDiff.compare(
            left: "<script.foo>// left</script.foo>",
            right: "<script.foo>// right</script.foo>",
            options: options
        )
        let underscoredScriptTag = try LineDiff.compare(
            left: "<script_foo>// left</script_foo>",
            right: "<script_foo>// right</script_foo>",
            options: options
        )
        let scriptLineCommentBoundary = try LineDiff.compare(
            left: "<script>// comment</script>left",
            right: "<script>// comment</script>right",
            options: options
        )
        let scriptPreprocessor = try LineDiff.compare(
            left: "<script># \" // left</script>",
            right: "<script># \" // right</script>",
            options: options
        )
        let htmlMultilineString = try LineDiff.compare(
            left: "<tag value=\"\n<!-- left -->\">",
            right: "<tag value=\"\n<!-- right -->\">",
            options: options
        )
        let scriptMultilineString = try LineDiff.compare(
            left: "<script>\"\\\n// left\"</script>",
            right: "<script>\"\\\n// right\"</script>",
            options: options
        )
        let scriptSingleQuoteIsRecordLocal = try LineDiff.compare(
            left: "<script>'\\\n// left</script>",
            right: "<script>'\\\n// right</script>",
            options: options
        )
        let scriptLineCommentIsRecordLocal = try LineDiff.compare(
            left: "<script>// comment\\\nleft</script>",
            right: "<script>// comment\\\nright</script>",
            options: options
        )
        let scriptPreprocessorCarriesAfterBackslash = try LineDiff.compare(
            left: "<script># value\\\n// left</script>",
            right: "<script># value\\\n// right</script>",
            options: options
        )
        let commentActivatesPendingScript = try LineDiff.compare(
            left: "<script <!--x -->// left",
            right: "<script <!--x -->// right",
            options: options
        )
        let scriptPrecedesEmbedded = try LineDiff.compare(
            left: "<script x=<?php ?>># left</script>",
            right: "<script x=<?php ?>># right</script>",
            options: options
        )
        let nestedUnquotedScript = try LineDiff.compare(
            left: "<x <script>// left</script>",
            right: "<x <script>// right</script>",
            options: options
        )
        let scriptSpecialOpenerWins = try LineDiff.compare(
            left: "<script<!--x -->// left",
            right: "<script<!--x -->// right",
            options: options
        )
        let commentPreservesFirstToken = try LineDiff.compare(
            left: "<script>/*x*/# value // left</script>",
            right: "<script>/*x*/# value // right</script>",
            options: options
        )

        XCTAssertEqual(DiffSummary(rows: script).differences, 0)
        XCTAssertEqual(DiffSummary(rows: style).differences, 0)
        XCTAssertEqual(DiffSummary(rows: uppercaseCloser).differences, 1)
        XCTAssertEqual(DiffSummary(rows: styleAfterNul).differences, 0)
        XCTAssertEqual(DiffSummary(rows: htmlCommentClearsElement).differences, 0)
        XCTAssertEqual(DiffSummary(rows: dottedScriptTag).differences, 1)
        XCTAssertEqual(DiffSummary(rows: underscoredScriptTag).differences, 1)
        XCTAssertEqual(DiffSummary(rows: scriptLineCommentBoundary).differences, 1)
        XCTAssertEqual(DiffSummary(rows: scriptPreprocessor).differences, 0)
        XCTAssertEqual(DiffSummary(rows: htmlMultilineString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: scriptMultilineString).differences, 1)
        XCTAssertEqual(DiffSummary(rows: scriptSingleQuoteIsRecordLocal).differences, 0)
        XCTAssertEqual(DiffSummary(rows: scriptLineCommentIsRecordLocal).differences, 1)
        XCTAssertEqual(DiffSummary(rows: scriptPreprocessorCarriesAfterBackslash).differences, 1)
        XCTAssertEqual(DiffSummary(rows: commentActivatesPendingScript).differences, 0)
        XCTAssertEqual(DiffSummary(rows: scriptPrecedesEmbedded).differences, 1)
        XCTAssertEqual(DiffSummary(rows: nestedUnquotedScript).differences, 0)
        XCTAssertEqual(DiffSummary(rows: scriptSpecialOpenerWins).differences, 1)
        XCTAssertEqual(DiffSummary(rows: commentPreservesFirstToken).differences, 0)
    }

    func testIgnoreCommentsHasNoEffectWithoutSupportedSyntax() throws {
        let rows = try LineDiff.compare(
            left: "// left",
            right: "// right",
            options: LineDiffOptions(ignoreComments: true)
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 1)
    }

    func testFinalNewlineCanBeComparedOrIgnored() throws {
        let ignored = try LineDiff.compare(left: "a\nb", right: "a\nb\n")
        let compared = try LineDiff.compare(
            left: "a\nb",
            right: "a\nb\n",
            options: LineDiffOptions(ignoreLineEndings: false)
        )

        XCTAssertEqual(DiffSummary(rows: ignored).differences, 0)
        XCTAssertEqual(DiffSummary(rows: compared).differences, 1)
        XCTAssertEqual(compared.last?.kind, .modified)
    }

    func testLineEndingStylesCanBeComparedOrIgnored() throws {
        let ignored = try LineDiff.compare(left: "a\r\nb\r\n", right: "a\nb\n")
        let compared = try LineDiff.compare(
            left: "a\r\nb\r\n",
            right: "a\nb\n",
            options: LineDiffOptions(ignoreLineEndings: false)
        )

        XCTAssertEqual(DiffSummary(rows: ignored).differences, 0)
        XCTAssertEqual(DiffSummary(rows: compared).differences, 2)
    }

    func testMergeReplacesModifiedLineInEitherDirection() throws {
        let rowID = try LineDiff.compare(left: "alpha\nleft\nomega", right: "alpha\nright\nomega")[1].id
        let leftToRight = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: "alpha\nleft\nomega",
            right: "alpha\nright\nomega"
        ))
        let rightToLeft = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .rightToLeft,
            left: "alpha\nleft\nomega",
            right: "alpha\nright\nomega"
        ))

        XCTAssertEqual(leftToRight.right, leftToRight.left)
        XCTAssertEqual(rightToLeft.left, rightToLeft.right)
    }

    func testMergeInsertsMissingTargetLine() throws {
        let rowID = try LineDiff.compare(left: "alpha\nbeta\nomega", right: "alpha\nomega")[1].id
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: "alpha\nbeta\nomega",
            right: "alpha\nomega"
        ))

        XCTAssertEqual(result.right, "alpha\nbeta\nomega")
    }

    func testMergeDeletesLineWhenSourceIsMissing() throws {
        let rowID = try LineDiff.compare(left: "alpha\nbeta\nomega", right: "alpha\nomega")[1].id
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .rightToLeft,
            left: "alpha\nbeta\nomega",
            right: "alpha\nomega"
        ))

        XCTAssertEqual(result.left, "alpha\nomega")
    }

    func testMergePreservesTargetLineEndings() throws {
        let rowID = try LineDiff.compare(left: "alpha\nbeta\nomega\n", right: "alpha\r\nomega\r\n")[1].id
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: "alpha\nbeta\nomega\n",
            right: "alpha\r\nomega\r\n"
        ))

        XCTAssertEqual(result.right, "alpha\r\nbeta\r\nomega\r\n")
    }

    func testMergePreservesUntouchedMixedLineEndings() throws {
        let left = "alpha\nnew\nomega\ntail"
        let right = "alpha\r\nold\nomega\rtail"
        let rowID = try LineDiff.compare(left: left, right: right)[1].id
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: left,
            right: right
        ))

        XCTAssertEqual(result.right, "alpha\r\nnew\nomega\rtail")
    }

    func testMergeTreatsOnlyXDiffLineEndingsAsDelimiters() throws {
        let left = "header\u{2028}detail\nleft\n"
        let right = "header\u{2028}detail\nright\n"
        let rowID = try LineDiff.compare(left: left, right: right)[1].id
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: left,
            right: right
        ))

        XCTAssertEqual(result.right, left)
    }

    func testMergeInsertsBlankLineIntoEmptyTarget() throws {
        let rowID = try XCTUnwrap(LineDiff.compare(left: "\n", right: "").first?.id)
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: "\n",
            right: ""
        ))

        XCTAssertEqual(result.right, "\n")
    }

    func testMergeInsertsBlankLineAtEndOfUnterminatedTarget() throws {
        let left = "alpha\n\n"
        let right = "alpha"
        let rowID = try XCTUnwrap(LineDiff.compare(left: left, right: right).last?.id)
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: left,
            right: right
        ))

        XCTAssertEqual(result.right, left)
    }

    func testMergeAppendsContentWithoutChangingTargetFinalNewlinePolicy() throws {
        let left = "alpha\nbeta\n"
        let right = "alpha"
        let rowID = try XCTUnwrap(LineDiff.compare(left: left, right: right).last?.id)
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: left,
            right: right
        ))

        XCTAssertEqual(result.right, "alpha\nbeta")
    }

    func testMergeDeletingFinalLinePreservesMissingFinalNewline() throws {
        let left = "alpha"
        let right = "alpha\nextra"
        let rowID = try XCTUnwrap(LineDiff.compare(left: left, right: right).last?.id)
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: left,
            right: right
        ))

        XCTAssertEqual(result.right, "alpha")
    }

    func testMergeRejectsUnchangedOrMissingRows() throws {
        XCTAssertNil(try LineMerge.apply(
            rowID: DiffRow.ID(leftNumber: 1, rightNumber: 1),
            direction: .leftToRight,
            left: "same",
            right: "same"
        ))
        XCTAssertNil(try LineMerge.apply(
            rowID: DiffRow.ID(leftNumber: 9, rightNumber: 9),
            direction: .leftToRight,
            left: "left",
            right: "right"
        ))
    }

    func testMergeAllCopiesContentAndPreservesTargetLineEndings() throws {
        let leftToRight = try XCTUnwrap(LineMerge.applyAll(
            direction: .leftToRight,
            left: "alpha\nbeta\n",
            right: "old\r\ncontent\r\n"
        ))
        let rightToLeft = try XCTUnwrap(LineMerge.applyAll(
            direction: .rightToLeft,
            left: "old\r\ncontent\r\n",
            right: "alpha\nbeta\n"
        ))

        XCTAssertEqual(leftToRight.right, "alpha\r\nbeta\r\n")
        XCTAssertEqual(rightToLeft.left, "alpha\r\nbeta\r\n")
    }

    func testMergeAllPreservesTargetMixedLineEndings() throws {
        let result = try XCTUnwrap(LineMerge.applyAll(
            direction: .leftToRight,
            left: "new one\nnew two\nnew three\n",
            right: "old one\r\nold two\nold three\r"
        ))

        XCTAssertEqual(result.right, "new one\r\nnew two\nnew three\r")
    }

    func testMergeAllPreservesDifferencesIgnoredByOptions() throws {
        let options = LineDiffOptions(ignoreCase: true)
        let result = try LineMerge.applyAll(
            direction: .leftToRight,
            left: "Alpha\nchanged\n",
            right: "alpha\nold\n",
            options: options
        )

        XCTAssertEqual(result?.right, "alpha\nchanged\n")
    }

    func testStrictComparisonAlignsBareCRRecords() throws {
        let rows = try LineDiff.compare(
            left: "alpha\rleft\romega\r",
            right: "alpha\rright\romega\r",
            options: LineDiffOptions(ignoreLineEndings: false)
        )

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .modified, .unchanged])
        XCTAssertEqual(rows[1].id, DiffRow.ID(leftNumber: 2, rightNumber: 2))
    }

    func testStrictRowMergeCopiesSourceLineTerminator() throws {
        let options = LineDiffOptions(ignoreLineEndings: false)
        let left = "alpha\r\nbeta"
        let right = "alpha\nbeta\n"
        let rowID = try XCTUnwrap(LineDiff.compare(left: left, right: right, options: options).first?.id)
        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: left,
            right: right,
            options: options
        ))

        XCTAssertEqual(result.right, "alpha\r\nbeta\n")
    }

    func testStrictRowMergeKeepsSeparatorBeforeFollowingTargetLine() throws {
        let options = LineDiffOptions(ignoreLineEndings: false)
        let left = "new"
        let right = "old\nfollowing\n"
        let rowID = try XCTUnwrap(
            LineDiff.compare(left: left, right: right, options: options)
                .first(where: { $0.left?.text == "new" && $0.right?.text == "old" })?.id
        )

        let result = try XCTUnwrap(LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: left,
            right: right,
            options: options
        ))

        XCTAssertEqual(result.right, "new\nfollowing\n")
    }

    func testStrictAppendCopiesExactSourceFinalTerminator() throws {
        let options = LineDiffOptions(ignoreLineEndings: false)
        for (left, right, expected) in [
            ("base\nadded\n", "base", "base\nadded\n"),
            ("base\nadded", "base\n", "base\nadded"),
        ] {
            let rowID = try XCTUnwrap(
                LineDiff.compare(left: left, right: right, options: options)
                    .first(where: { $0.left?.text == "added" })?.id
            )
            let result = try XCTUnwrap(LineMerge.apply(
                rowID: rowID,
                direction: .leftToRight,
                left: left,
                right: right,
                options: options
            ))
            XCTAssertEqual(result.right, expected)
        }
    }

    func testStrictMergeAllCopiesSourceLineEndingsAndFinalNewline() throws {
        let options = LineDiffOptions(ignoreLineEndings: false)
        let result = try XCTUnwrap(LineMerge.applyAll(
            direction: .leftToRight,
            left: "alpha\r\nbeta",
            right: "alpha\nbeta\n",
            options: options
        ))

        XCTAssertEqual(result.right, "alpha\r\nbeta")
    }

    func testIgnoreBlankLinesHandlesCRLFAndUnterminatedContent() throws {
        let options = LineDiffOptions(ignoreBlankLines: true)
        let blank = try LineDiff.compare(left: "\r\n", right: "", options: options)
        let content = try LineDiff.compare(left: "x", right: "", options: options)

        XCTAssertEqual(DiffSummary(rows: blank).differences, 0)
        XCTAssertEqual(DiffSummary(rows: content).differences, 1)
    }

    func testIgnoreBlankLinesMatrixPreservesRealEdits() throws {
        let blankInsertions = ["\n", "\r", "\r\n", " \n", "\t\r\n", "\u{0B}\n", "\u{0C}\r\n"]
        let whitespaceModes: [WhitespaceComparison] = [.compareAll, .ignoreChanges, .ignoreAll]

        for whitespace in whitespaceModes {
            let options = LineDiffOptions(
                whitespace: whitespace,
                ignoreBlankLines: true
            )
            for blank in blankInsertions {
                let inserted = try LineDiff.compare(
                    left: "head\n\(blank)tail",
                    right: "head\ntail",
                    options: options
                )
                let realEdit = try LineDiff.compare(
                    left: "head\n\(blank)left\ntail",
                    right: "head\nright\ntail",
                    options: options
                )

                XCTAssertEqual(
                    DiffSummary(rows: inserted).differences,
                    0,
                    "Whitespace: \(whitespace), blank: \(blank.debugDescription)"
                )
                XCTAssertEqual(
                    DiffSummary(rows: realEdit).differences,
                    1,
                    "Whitespace: \(whitespace), blank: \(blank.debugDescription)"
                )
            }
        }
    }

    func testIgnoreBlankLinesFinalEOLMatrix() throws {
        let fixtures = ["", "\r\n", "1", "1\r\n", "1\r\n2\r\n3", "1\r\n2\r\n3\r\n"]

        for whitespace in [WhitespaceComparison.compareAll, .ignoreChanges, .ignoreAll] {
            let options = LineDiffOptions(
                whitespace: whitespace,
                ignoreBlankLines: true
            )
            for left in fixtures {
                for right in fixtures {
                    let rows = try LineDiff.compare(left: left, right: right, options: options)
                    if left.trimmingCharacters(in: .whitespacesAndNewlines)
                        == right.trimmingCharacters(in: .whitespacesAndNewlines) {
                        XCTAssertEqual(DiffSummary(rows: rows).differences, 0)
                    }
                }
            }
        }
    }

    func testMergeAllRejectsEqualContent() throws {
        XCTAssertNil(try LineMerge.applyAll(
            direction: .leftToRight,
            left: "same\ncontent",
            right: "same\r\ncontent"
        ))
    }

    func testComparisonHistorySupportsUndoRedoAndNewBranch() throws {
        let initial = ComparisonSnapshot(left: "left", right: "right")
        let first = ComparisonSnapshot(left: "left", right: "first")
        let second = ComparisonSnapshot(left: "second", right: "first")
        var history = ComparisonHistory(current: initial)

        XCTAssertTrue(history.commit(first))
        XCTAssertTrue(history.commit(second))
        XCTAssertEqual(history.undo(), first)
        XCTAssertEqual(history.undo(), initial)
        XCTAssertEqual(history.redo(), first)
        XCTAssertTrue(history.commit(second))
        XCTAssertFalse(history.canRedo)
    }

    func testComparisonHistoryCanCoalesceAnEditingSession() {
        let original = ComparisonSnapshot(left: "", right: "")
        var history = ComparisonHistory(current: original)

        XCTAssertTrue(history.commit(ComparisonSnapshot(left: "a", right: "")))
        XCTAssertTrue(history.replaceCurrent(ComparisonSnapshot(left: "ab", right: "")))
        XCTAssertTrue(history.replaceCurrent(ComparisonSnapshot(left: "abc", right: "")))
        XCTAssertEqual(history.undo(), original)
        XCTAssertEqual(history.redo(), ComparisonSnapshot(left: "abc", right: ""))

        XCTAssertTrue(history.replaceCurrent(original))
        history.discardRedundantUndo()
        XCTAssertFalse(history.canUndo)
    }

    func testComparisonHistoryBoundsUndoDepth() {
        var history = ComparisonHistory(
            current: ComparisonSnapshot(left: "0", right: "right"),
            capacity: 2
        )
        history.commit(ComparisonSnapshot(left: "1", right: "right"))
        history.commit(ComparisonSnapshot(left: "2", right: "right"))
        history.commit(ComparisonSnapshot(left: "3", right: "right"))

        XCTAssertEqual(history.undo()?.left, "2")
        XCTAssertEqual(history.undo()?.left, "1")
        XCTAssertNil(history.undo())
    }

    func testComparisonHistoryBoundsRetainedBytes() {
        var history = ComparisonHistory(
            current: ComparisonSnapshot(left: "0000", right: ""),
            capacity: 100,
            maximumBytes: 8
        )
        history.commit(ComparisonSnapshot(left: "1111", right: ""))
        history.commit(ComparisonSnapshot(left: "2222", right: ""))
        history.commit(ComparisonSnapshot(left: "3333", right: ""))

        XCTAssertEqual(history.undo()?.left, "2222")
        XCTAssertEqual(history.undo()?.left, "1111")
        XCTAssertNil(history.undo())
    }

    func testXDiffRejectsOversizedInputsBeforeReadingThem() {
        var result = mmx_diff_result(hunks: nil, count: 0)
        let invalidPointer = UnsafeRawPointer(bitPattern: 1)
        let oversized = Int(MMX_MAX_INPUT_SIZE) + 1

        let status = mmx_diff(
            invalidPointer,
            oversized,
            nil,
            0,
            0,
            &result
        )

        XCTAssertEqual(status, -1)
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)
    }

    func testXDiffRejectsExcessiveLineCount() {
        let input = Data(repeating: 0x0A, count: Int(MMX_MAX_LINE_COUNT) + 1)
        var result = mmx_diff_result(hunks: nil, count: 0)

        let status = input.withUnsafeBytes {
            mmx_diff($0.baseAddress, $0.count, nil, 0, 0, &result)
        }

        XCTAssertEqual(status, -1)
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)
    }

    func testXDiffRejectsCombinedAlgorithmsAndPopulatedResults() {
        var result = mmx_diff_result(hunks: nil, count: 0)
        let combined = UInt64(MMX_DIFF_PATIENCE) | UInt64(MMX_DIFF_HISTOGRAM)
        let combinedStatus = mmx_diff(nil, 0, nil, 0, combined, &result)

        XCTAssertEqual(combinedStatus, -1)
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)

        let sentinel = UnsafeMutablePointer<mmx_diff_hunk>(bitPattern: 1)
        result = mmx_diff_result(hunks: sentinel, count: 1)
        let populatedStatus = mmx_diff(nil, 0, nil, 0, 0, &result)

        XCTAssertEqual(populatedStatus, -1)
        XCTAssertEqual(result.hunks, sentinel)
        XCTAssertEqual(result.count, 1)
    }

    func testXDiffRejectsUnknownFlags() {
        var result = mmx_diff_result(hunks: nil, count: 0)
        let status = mmx_diff(nil, 0, nil, 0, UInt64(1) << 63, &result)

        XCTAssertEqual(status, -1)
        XCTAssertNil(result.hunks)
        XCTAssertEqual(result.count, 0)
    }

    func testAlgorithmsProduceExpectedAlignmentForRepeatedLines() throws {
        let left = ["A", "B", "E", "B", "F", "B", "B", "C", "F", "B", "E", "E"]
            .joined(separator: "\n")
        let right = ["E", "D", "D", "D", "E", "B", "C", "B", "B", "F", "D", "E"]
            .joined(separator: "\n")
        let expectedUnchanged: [DiffAlgorithm: [DiffRow.ID]] = [
            .default: [id(3, 5), id(4, 6), id(6, 8), id(7, 9), id(9, 10), id(12, 12)],
            .patience: [id(3, 1), id(7, 6), id(8, 7), id(9, 10), id(12, 12)],
            .histogram: [id(3, 1), id(7, 6), id(8, 7), id(10, 8), id(12, 12)],
            .none: [id(6, 6), id(12, 12)]
        ]

        for (algorithm, expected) in expectedUnchanged {
            let rows = try LineDiff.compare(
                left: left,
                right: right,
                options: LineDiffOptions(algorithm: algorithm)
            )
            XCTAssertEqual(rows.filter { $0.kind == .unchanged }.map(\.id), expected)
        }
    }

    func testMultipleHunksPreserveSingleUnchangedSeparator() throws {
        let rows = try LineDiff.compare(
            left: "head\nleft-one\nseparator\nleft-two\ntail",
            right: "head\nright-one\nseparator\nright-two\ntail"
        )

        XCTAssertEqual(rows.map(\.kind), [
            .unchanged, .modified, .unchanged, .modified, .unchanged,
        ])
        XCTAssertEqual(rows.map(\.id), [id(1, 1), id(2, 2), id(3, 3), id(4, 4), id(5, 5)])
    }

    func testAdjacentChangesRemainOneMonotonicAlignedRun() throws {
        let rows = try LineDiff.compare(
            left: "head\nleft-one\nleft-two\ntail",
            right: "head\nright-one\nright-two\ntail"
        )

        XCTAssertEqual(rows.map(\.kind), [.unchanged, .modified, .modified, .unchanged])
        XCTAssertEqual(rows.map(\.id), [id(1, 1), id(2, 2), id(3, 3), id(4, 4)])
    }

    func testOverlappingLineFiltersIgnoreLineWhenAnyRuleMatches() throws {
        let rows = try LineDiff.compare(
            left: "head\n# generated old\ntail",
            right: "head\n# generated new\ntail",
            options: LineDiffOptions(lineFilters: [
                LineFilterRule(pattern: #"^# "#),
                LineFilterRule(pattern: #"generated"#),
            ])
        )

        XCTAssertEqual(DiffSummary(rows: rows).differences, 0)
    }

    func testOverlappingSubstitutionsApplyInDeclaredOrder() throws {
        let forward = LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "build", replacement: "release"),
            SubstitutionRule(pattern: "release \\d+", replacement: "version"),
        ])
        let reverse = LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "release \\d+", replacement: "version"),
            SubstitutionRule(pattern: "build", replacement: "release"),
        ])

        XCTAssertEqual(
            DiffSummary(rows: try LineDiff.compare(
                left: "build 123",
                right: "version",
                options: forward
            )).differences,
            0
        )
        XCTAssertEqual(
            DiffSummary(rows: try LineDiff.compare(
                left: "build 123",
                right: "version",
                options: reverse
            )).differences,
            1
        )
    }

    func testXDiffRecoversFromEveryAllocationFailure() throws {
        let left = "root\nalpha\nbeta\nrepeat\ngamma\nrepeat\nomega\n"
        let right = "root\nalpha changed\nbeta\nrepeat\ndelta\nrepeat\nomega\n"
        let flags: [UInt64] = [
            0,
            UInt64(MMX_DIFF_PATIENCE),
            UInt64(MMX_DIFF_HISTOGRAM),
            UInt64(MMX_DIFF_NONE),
        ]

        for flag in flags {
            mmx_test_disable_allocation_failures()
            let allocationCount = try successfulNativeDiff(left: left, right: right, flags: flag)
            XCTAssertGreaterThan(allocationCount, 0)
            XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)

            for failedAllocation in 0..<allocationCount {
                mmx_test_fail_allocation_after(failedAllocation)
                var result = mmx_diff_result(hunks: nil, count: 0)
                let status = withNativeBuffers(left: left, right: right) { leftBuffer, rightBuffer in
                    mmx_diff(
                        leftBuffer.baseAddress,
                        leftBuffer.count,
                        rightBuffer.baseAddress,
                        rightBuffer.count,
                        flag,
                        &result
                    )
                }

                XCTAssertNotEqual(status, 0, "Flag \(flag), allocation \(failedAllocation)")
                XCTAssertNil(result.hunks)
                XCTAssertEqual(result.count, 0)
                XCTAssertEqual(
                    mmx_test_outstanding_allocation_count(),
                    0,
                    "Flag \(flag), allocation \(failedAllocation) leaked"
                )
                mmx_diff_result_free(&result)
            }

            mmx_test_disable_allocation_failures()
            _ = try successfulNativeDiff(left: left, right: right, flags: flag)
            XCTAssertEqual(mmx_test_outstanding_allocation_count(), 0)
        }
    }

    private func successfulNativeDiff(left: String, right: String, flags: UInt64) throws -> Int {
        var result = mmx_diff_result(hunks: nil, count: 0)
        let status = withNativeBuffers(left: left, right: right) { leftBuffer, rightBuffer in
            mmx_diff(
                leftBuffer.baseAddress,
                leftBuffer.count,
                rightBuffer.baseAddress,
                rightBuffer.count,
                flags,
                &result
            )
        }
        let allocationCount = Int(mmx_test_allocation_attempt_count())
        mmx_diff_result_free(&result)
        XCTAssertEqual(status, 0)
        return allocationCount
    }

    private func withNativeBuffers<Result>(
        left: String,
        right: String,
        _ body: (UnsafeRawBufferPointer, UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)
        return try leftBytes.withUnsafeBytes { leftBuffer in
            try rightBytes.withUnsafeBytes { rightBuffer in
                try body(leftBuffer, rightBuffer)
            }
        }
    }

    private func id(_ left: Int?, _ right: Int?) -> DiffRow.ID {
        DiffRow.ID(leftNumber: left, rightNumber: right)
    }
}
