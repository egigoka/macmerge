import CXDiff
import MacMergeCore
import XCTest

final class LineDiffTests: XCTestCase {
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

    func testCommentSyntaxUsesWinMergeExtensionFamilies() {
        XCTAssertEqual(CommentSyntax(fileExtension: "CPP"), .cFamily)
        XCTAssertEqual(CommentSyntax(fileExtension: "sh"), .hashLine)
        XCTAssertEqual(CommentSyntax(fileExtension: "py"), .python)
        XCTAssertEqual(CommentSyntax(fileExtension: "sql"), .sql)
        XCTAssertEqual(CommentSyntax(fileExtension: "xml"), .markup)
        XCTAssertEqual(CommentSyntax(fileExtension: "html"), .markup)
        XCTAssertNil(CommentSyntax(fileExtension: "m"))
        XCTAssertNil(CommentSyntax(fileExtension: "yaml"))
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
        let blankInsertions = ["\n", "\r", "\r\n", " \n", "\t\r\n"]
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
