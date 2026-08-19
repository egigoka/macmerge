import MacMergeCore
import XCTest

final class TableComparisonTests: XCTestCase {
    func testCSVParsingPreservesValuesAndSourceMetadata() throws {
        let input = "name,note\r\n\"one\",\"line 1\nline 2\"\n"

        let table = try DelimitedTableParser.parse(input)

        XCTAssertEqual(table.delimiter, ",")
        XCTAssertEqual(table.quote, "\"")
        XCTAssertEqual(table.sourceUTF8ByteCount, input.utf8.count)
        XCTAssertEqual(table.totalCellCount, 4)
        XCTAssertEqual(
            table.rows.map(\.values),
            [
                ["name", "note"],
                ["one", "line 1\nline 2"]
            ])
        XCTAssertEqual(table.rows.map(\.index), [0, 1])
        XCTAssertEqual(table.rows.map(\.sourceLine), [1, 2])
        XCTAssertEqual(table.rows.map(\.terminator), [.carriageReturnLineFeed, .lineFeed])
        XCTAssertEqual(table.rows[0].sourceUTF8Range, 0..<9)
        XCTAssertEqual(table.rows[1].sourceUTF8Range, 11..<32)
        XCTAssertEqual(table.rows[0].cells.map(\.sourceUTF8Range), [0..<4, 5..<9])
        XCTAssertEqual(table.rows[1].cells.map(\.sourceUTF8Range), [11..<16, 17..<32])
        XCTAssertEqual(
            table.rows[1].cells[1].sourceLocation,
            DelimitedTableSourceLocation(line: 2, column: 7, utf8Offset: 17)
        )
        XCTAssertEqual(table.rows[1].cells.map(\.wasQuoted), [true, true])
    }

    func testUTF8SourceRangesAndOffsetsCountBytesNotCharacters() throws {
        let input = "é,界\r\n\"🙂\",e\u{301}\n"

        let table = try DelimitedTableParser.parse(input)

        XCTAssertEqual(table.sourceUTF8ByteCount, 19)
        XCTAssertEqual(table.rows.map(\.values), [["é", "界"], ["🙂", "e\u{301}"]])
        XCTAssertEqual(table.rows.map(\.sourceUTF8Range), [0..<6, 8..<18])
        XCTAssertEqual(table.rows.map(\.sourceLine), [1, 2])
        XCTAssertEqual(table.rows.map(\.terminator), [.carriageReturnLineFeed, .lineFeed])
        XCTAssertEqual(table.rows[0].cells.map(\.sourceUTF8Range), [0..<2, 3..<6])
        XCTAssertEqual(table.rows[1].cells.map(\.sourceUTF8Range), [8..<14, 15..<18])
        XCTAssertEqual(
            table.rows[0].cells.map(\.sourceLocation),
            [
                DelimitedTableSourceLocation(line: 1, column: 1, utf8Offset: 0),
                DelimitedTableSourceLocation(line: 1, column: 3, utf8Offset: 3)
            ]
        )
        XCTAssertEqual(
            table.rows[1].cells.map(\.sourceLocation),
            [
                DelimitedTableSourceLocation(line: 2, column: 1, utf8Offset: 8),
                DelimitedTableSourceLocation(line: 2, column: 5, utf8Offset: 15)
            ]
        )
    }

    func testTSVAndCustomDelimiterQuoteParsing() throws {
        let tsv = try DelimitedTableParser.parse(
            "alpha\t\"beta\tgamma\"\nleft\tright",
            options: .tabSeparated
        )
        let custom = try DelimitedTableParser.parse(
            "a|'b|c'|'d''e'",
            delimiter: "|",
            quote: "'"
        )
        let quotingDisabled = try DelimitedTableParser.parse(
            "a;\"b;c",
            delimiter: ";",
            quote: nil
        )

        XCTAssertEqual(tsv.delimiter, "\t")
        XCTAssertEqual(
            tsv.rows.map(\.values),
            [
                ["alpha", "beta\tgamma"],
                ["left", "right"]
            ])
        XCTAssertEqual(custom.rows.map(\.values), [["a", "b|c", "d'e"]])
        XCTAssertEqual(custom.rows[0].cells.map(\.wasQuoted), [false, true, true])
        XCTAssertEqual(quotingDisabled.rows.map(\.values), [["a", "\"b", "c"]])
        XCTAssertNil(quotingDisabled.quote)
    }

    func testEscapedQuotesDecodeWithoutDroppingQuoteMetadata() throws {
        let table = try DelimitedTableParser.parse("\"a \"\"quoted\"\" value\",\"x\"\"y\"")

        XCTAssertEqual(table.rows.map(\.values), [["a \"quoted\" value", "x\"y"]])
        XCTAssertEqual(table.rows[0].cells.map(\.wasQuoted), [true, true])
        XCTAssertEqual(table.rows[0].cells.map(\.index), [0, 1])
    }

    func testQuotedCellsPreserveCRLFCRAndLF() throws {
        let table = try DelimitedTableParser.parse("\"a\r\nb\rc\nd\",z")

        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0].values, ["a\r\nb\rc\nd", "z"])
        XCTAssertEqual(table.rows[0].sourceLine, 1)
        XCTAssertEqual(table.rows[0].terminator, .none)
        XCTAssertEqual(
            table.rows[0].cells[1].sourceLocation,
            DelimitedTableSourceLocation(line: 4, column: 4, utf8Offset: 11)
        )
    }

    func testEmptyInputBlankRowsAndTrailingCellsAreDistinct() throws {
        let empty = try DelimitedTableParser.parse("")
        let table = try DelimitedTableParser.parse(",\n,,\n\nlast,\n")

        XCTAssertTrue(empty.rows.isEmpty)
        XCTAssertEqual(empty.totalCellCount, 0)
        XCTAssertEqual(
            table.rows.map(\.values),
            [
                ["", ""],
                ["", "", ""],
                [""],
                ["last", ""]
            ])
        XCTAssertEqual(table.rows.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(table.rows.map(\.sourceLine), [1, 2, 3, 4])
        XCTAssertEqual(
            table.rows.map(\.terminator),
            [
                .lineFeed,
                .lineFeed,
                .lineFeed,
                .lineFeed
            ])
        XCTAssertEqual(table.totalCellCount, 8)
    }

    func testLargeFirstCellDoesNotAffectFollowingNarrowCells() throws {
        let largeCell = String(repeating: "x", count: 2 * 1_024 * 1_024)
        let table = try DelimitedTableParser.parse("\(largeCell),a,b,c")
        let secondCellStart = largeCell.utf8.count + 1

        XCTAssertEqual(table.rows[0].values, [largeCell, "a", "b", "c"])
        XCTAssertEqual(
            table.rows[0].cells.map(\.sourceUTF8Range),
            [
                0..<largeCell.utf8.count,
                secondCellStart..<(secondCellStart + 1),
                (secondCellStart + 2)..<(secondCellStart + 3),
                (secondCellStart + 4)..<(secondCellStart + 5)
            ]
        )
    }

    func testWideFirstRowDoesNotAffectFollowingNarrowRows() throws {
        let wideRow = (0..<8_192).map(String.init).joined(separator: ",")
        let table = try DelimitedTableParser.parse("\(wideRow)\nnarrow\ntail")

        XCTAssertEqual(table.rows.map(\.cells.count), [8_192, 1, 1])
        XCTAssertEqual(table.rows[1].values, ["narrow"])
        XCTAssertEqual(table.rows[2].values, ["tail"])
        XCTAssertLessThan(table.rows[1].cells.capacity, table.rows[0].cells.count)
        XCTAssertLessThan(table.rows[2].cells.capacity, table.rows[0].cells.count)
    }

    func testRowTerminatorsRecognizeCRLFCRAndLFWithoutExtraTerminalRow() throws {
        let table = try DelimitedTableParser.parse("cr\rlinefeed\ncrlf\r\nnone")

        XCTAssertEqual(table.rows.map(\.values), [["cr"], ["linefeed"], ["crlf"], ["none"]])
        XCTAssertEqual(table.rows.map(\.sourceLine), [1, 2, 3, 4])
        XCTAssertEqual(
            table.rows.map(\.terminator),
            [
                .carriageReturn,
                .lineFeed,
                .carriageReturnLineFeed,
                .none
            ])
    }

    func testIllegalQuoteFormsReportExactLocations() {
        assertParseError(
            .unexpectedQuote(DelimitedTableSourceLocation(line: 1, column: 2, utf8Offset: 1))
        ) {
            _ = try DelimitedTableParser.parse("a\"b,c")
        }
        assertParseError(
            .unexpectedCharacterAfterClosingQuote(
                DelimitedTableSourceLocation(line: 1, column: 4, utf8Offset: 3)
            )
        ) {
            _ = try DelimitedTableParser.parse("\"a\"x,b")
        }
        assertParseError(
            .newlineInQuotedCell(
                DelimitedTableSourceLocation(line: 1, column: 3, utf8Offset: 2)
            )
        ) {
            _ = try DelimitedTableParser.parse(
                "\"a\nb\",c",
                delimiter: ",",
                allowsNewlinesInQuotedCells: false
            )
        }
        assertParseError(
            .unterminatedQuotedCell(
                DelimitedTableSourceLocation(line: 1, column: 1, utf8Offset: 0)
            )
        ) {
            _ = try DelimitedTableParser.parse("\"a,b")
        }
    }

    func testDelimiterAndQuoteValidationRejectsStructuralAndMultiscalarCharacters() {
        let multiscalarCharacter: Character = "e\u{301}"

        for delimiter: Character in ["\0", "\r", "\n", multiscalarCharacter] {
            assertParseError(.invalidDelimiter) {
                _ = try DelimitedTableParser.parse("value", delimiter: delimiter)
            }
        }
        for quote: Character in ["\0", "\r", "\n", multiscalarCharacter] {
            assertParseError(.invalidQuote) {
                _ = try DelimitedTableParser.parse("value", delimiter: ",", quote: quote)
            }
        }
        assertParseError(.delimiterMatchesQuote) {
            _ = try DelimitedTableParser.parse("value", delimiter: "|", quote: "|")
        }
    }

    func testDefaultCapsAreStableAndFinite() {
        let parsing = DelimitedTableLimits.default
        XCTAssertEqual(parsing.maximumInputBytes, 64 * 1_024 * 1_024)
        XCTAssertEqual(parsing.maximumRows, 1_048_576)
        XCTAssertEqual(parsing.maximumColumnsPerRow, 16_384)
        XCTAssertEqual(parsing.maximumTotalCells, 1_048_576)
        XCTAssertEqual(parsing.maximumCellBytes, 16 * 1_024 * 1_024)
        XCTAssertEqual(DelimitedTableParsingOptions.commaSeparated.limits, parsing)
        XCTAssertEqual(DelimitedTableParsingOptions.tabSeparated.limits, parsing)

        let comparison = TableComparisonOptions.default
        XCTAssertEqual(comparison.maximumExactEditDistance, 2_048)
        XCTAssertEqual(comparison.maximumAlignmentWork, 16 * 1_024 * 1_024)
        XCTAssertEqual(comparison.maximumComparedRows, 2_097_152)
        XCTAssertEqual(comparison.maximumComparedCells, 2_097_152)
    }

    func testParserRejectsEveryInvalidLimit() {
        let invalidLimits = [
            DelimitedTableLimits(maximumInputBytes: -1),
            DelimitedTableLimits(maximumRows: 0),
            DelimitedTableLimits(maximumColumnsPerRow: 0),
            DelimitedTableLimits(maximumTotalCells: 0),
            DelimitedTableLimits(maximumCellBytes: -1)
        ]

        for limits in invalidLimits {
            assertParseError(.invalidLimits) {
                _ = try DelimitedTableParser.parse("value", delimiter: ",", limits: limits)
            }
        }
    }

    func testParserAcceptsEveryCapAtItsBoundary() throws {
        let limits = DelimitedTableLimits(
            maximumInputBytes: 3,
            maximumRows: 1,
            maximumColumnsPerRow: 2,
            maximumTotalCells: 2,
            maximumCellBytes: 2
        )

        let table = try DelimitedTableParser.parse("é,", delimiter: ",", limits: limits)

        XCTAssertEqual(table.sourceUTF8ByteCount, 3)
        XCTAssertEqual(table.rows.map(\.values), [["é", ""]])
        XCTAssertEqual(table.totalCellCount, 2)
    }

    func testInputByteLimitUsesUTF8LengthForMultibyteScalars() throws {
        let input = "🙂"

        assertParseError(.inputTooLarge(maximumBytes: 3)) {
            _ = try DelimitedTableParser.parse(
                input,
                delimiter: ",",
                limits: DelimitedTableLimits(maximumInputBytes: 3)
            )
        }

        let table = try DelimitedTableParser.parse(
            input,
            delimiter: ",",
            limits: DelimitedTableLimits(maximumInputBytes: 4)
        )
        XCTAssertEqual(table.sourceUTF8ByteCount, 4)
        XCTAssertEqual(table.rows[0].cells[0].sourceUTF8Range, 0..<4)
    }

    func testParserRejectsInputRowColumnTotalCellAndCellByteOverages() {
        assertParseError(.inputTooLarge(maximumBytes: 2)) {
            _ = try DelimitedTableParser.parse(
                "abc",
                delimiter: ",",
                limits: DelimitedTableLimits(maximumInputBytes: 2)
            )
        }
        assertParseError(.tooManyRows(maximumRows: 1)) {
            _ = try DelimitedTableParser.parse(
                "a\nb",
                delimiter: ",",
                limits: DelimitedTableLimits(maximumRows: 1)
            )
        }
        assertParseError(.tooManyColumns(rowIndex: 0, maximumColumns: 1)) {
            _ = try DelimitedTableParser.parse(
                "a,b",
                delimiter: ",",
                limits: DelimitedTableLimits(maximumColumnsPerRow: 1)
            )
        }
        assertParseError(.tooManyCells(maximumCells: 1)) {
            _ = try DelimitedTableParser.parse(
                "a\nb",
                delimiter: ",",
                limits: DelimitedTableLimits(maximumTotalCells: 1)
            )
        }
        assertParseError(.cellTooLarge(rowIndex: 0, columnIndex: 0, maximumBytes: 1)) {
            _ = try DelimitedTableParser.parse(
                "é",
                delimiter: ",",
                limits: DelimitedTableLimits(maximumCellBytes: 1)
            )
        }
    }

    func testEqualComparisonPreservesRowsCellsAndSummary() throws {
        let input = "a,b\nc,d"

        let result = try TableComparison.compare(left: input, right: input)

        XCTAssertTrue(result.isEqual)
        XCTAssertEqual(result.alignment, .exact)
        XCTAssertEqual(result.rows.map(\.status), [.equal, .equal])
        XCTAssertTrue(result.rows.flatMap(\.cells).allSatisfy { $0.status == .equal })
        XCTAssertEqual(result.summary.equal, 2)
        XCTAssertEqual(result.summary.modified, 0)
        XCTAssertEqual(result.summary.removed, 0)
        XCTAssertEqual(result.summary.added, 0)
        XCTAssertEqual(result.summary.differences, 0)
        assertStableIndicesAndReconstruction(result)
    }

    func testMixedAlignmentClassifiesAddedRemovedModifiedAndEqualRows() throws {
        let left = "head\nremove\nanchor-1\nold,keep\nanchor-2\ntail"
        let right = "head\nanchor-1\nnew,keep,extra\nanchor-2\nadd\ntail"

        let result = try TableComparison.compare(left: left, right: right)

        XCTAssertEqual(result.alignment, .exact)
        XCTAssertEqual(
            result.rows.map(\.status),
            [
                .equal,
                .removed,
                .equal,
                .modified,
                .equal,
                .added,
                .equal
            ])
        XCTAssertEqual(result.rows.map(\.leftIndex), [0, 1, 2, 3, 4, nil, 5])
        XCTAssertEqual(result.rows.map(\.rightIndex), [0, nil, 1, 2, 3, 4, 5])
        XCTAssertEqual(result.rows[1].cells.map(\.status), [.removed])
        XCTAssertEqual(result.rows[3].cells.map(\.status), [.modified, .equal, .added])
        XCTAssertEqual(result.rows[5].cells.map(\.status), [.added])
        XCTAssertEqual(result.summary.equal, 4)
        XCTAssertEqual(result.summary.modified, 1)
        XCTAssertEqual(result.summary.removed, 1)
        XCTAssertEqual(result.summary.added, 1)
        XCTAssertEqual(result.summary.differences, 3)
        XCTAssertFalse(result.isEqual)
        assertStableIndicesAndReconstruction(result)
    }

    func testDuplicateRowsHaveDeterministicAlignmentAndStableSourceIndices() throws {
        let left = "head\nduplicate\npivot\nduplicate\ntail"
        let right = "head\nduplicate\nduplicate\npivot\nduplicate\ntail"
        let expected = try TableComparison.compare(left: left, right: right)

        XCTAssertEqual(expected.rows.map(\.status), [.equal, .equal, .added, .equal, .equal, .equal])
        XCTAssertEqual(expected.rows.filter { $0.status == .added }.first?.right?.values, ["duplicate"])
        XCTAssertEqual(
            expected.rows.filter { $0.status == .equal }.compactMap(\.left?.values),
            [
                ["head"],
                ["duplicate"],
                ["pivot"],
                ["duplicate"],
                ["tail"]
            ])
        assertStableIndicesAndReconstruction(expected)

        for _ in 0..<20 {
            XCTAssertEqual(try TableComparison.compare(left: left, right: right), expected)
        }
    }

    func testSmallExactAlignmentsMatchIndependentLCSMinimalityOracle() throws {
        let inputs = rowSequences(maximumLength: 4)

        for left in inputs {
            for right in inputs {
                let result = try TableComparison.compare(
                    left: left.joined(separator: "\n"),
                    right: right.joined(separator: "\n")
                )
                let longestCommonSubsequenceCount = longestCommonSubsequenceLength(left, right)
                let equalCount = result.rows.count { $0.status == .equal }
                let reportedDistance = result.rows.reduce(into: 0) { distance, row in
                    switch row.status {
                    case .equal:
                        break
                    case .modified:
                        distance += 2
                    case .removed, .added:
                        distance += 1
                    }
                }
                let context = "left=\(left) right=\(right) rows=\(result.rows)"

                XCTAssertEqual(result.alignment, .exact, context)
                XCTAssertEqual(equalCount, longestCommonSubsequenceCount, context)
                XCTAssertEqual(
                    reportedDistance,
                    left.count + right.count - (2 * longestCommonSubsequenceCount),
                    context
                )
                assertComparisonInvariants(result)
            }
        }
    }

    func testComparisonRejectsEveryInvalidLimit() throws {
        let table = try DelimitedTableParser.parse("value")
        let invalidOptions = [
            TableComparisonOptions(maximumExactEditDistance: -1),
            TableComparisonOptions(maximumAlignmentWork: -1),
            TableComparisonOptions(maximumComparedRows: -1),
            TableComparisonOptions(maximumComparedCells: -1)
        ]

        for options in invalidOptions {
            assertComparisonError(.invalidLimits) {
                _ = try TableComparison.compare(left: table, right: table, options: options)
            }
        }
    }

    func testComparisonRowAndCellCapsAcceptBoundaryAndRejectOverage() throws {
        let left = try DelimitedTableParser.parse("a,b")
        let right = try DelimitedTableParser.parse("a,b")
        let boundaryOptions = TableComparisonOptions(
            maximumComparedRows: 2,
            maximumComparedCells: 4
        )

        XCTAssertTrue(
            try TableComparison.compare(
                left: left,
                right: right,
                options: boundaryOptions
            ).isEqual)
        assertComparisonError(.tooManyRows(maximumRows: 1)) {
            _ = try TableComparison.compare(
                left: left,
                right: right,
                options: TableComparisonOptions(maximumComparedRows: 1)
            )
        }
        assertComparisonError(.tooManyCells(maximumCells: 3)) {
            _ = try TableComparison.compare(
                left: left,
                right: right,
                options: TableComparisonOptions(maximumComparedCells: 3)
            )
        }

        let empty = try DelimitedTableParser.parse("")
        let zeroLimits = TableComparisonOptions(
            maximumExactEditDistance: 0,
            maximumAlignmentWork: 0,
            maximumComparedRows: 0,
            maximumComparedCells: 0
        )
        XCTAssertTrue(
            try TableComparison.compare(
                left: empty,
                right: empty,
                options: zeroLimits
            ).isEqual)
    }

    func testExactDistanceAndAlignmentWorkBoundariesAreIndependent() throws {
        let left = try DelimitedTableParser.parse("left")
        let right = try DelimitedTableParser.parse("right")

        XCTAssertEqual(
            try TableComparison.compare(
                left: left,
                right: right,
                options: TableComparisonOptions(
                    maximumExactEditDistance: 2,
                    maximumAlignmentWork: 8
                )
            ).alignment, .exact)
        XCTAssertEqual(
            try TableComparison.compare(
                left: left,
                right: right,
                options: TableComparisonOptions(
                    maximumExactEditDistance: 1,
                    maximumAlignmentWork: 100
                )
            ).alignment, .boundedFallback)
        XCTAssertEqual(
            try TableComparison.compare(
                left: left,
                right: right,
                options: TableComparisonOptions(
                    maximumExactEditDistance: 100,
                    maximumAlignmentWork: 7
                )
            ).alignment, .boundedFallback)
    }

    func testWideEqualRowHonorsAlignmentWorkBound() throws {
        let wideRow = (0..<4_096).map { "value-\($0)" }.joined(separator: ",")
        let left = try DelimitedTableParser.parse("left\n\(wideRow)\nleft-tail")
        let right = try DelimitedTableParser.parse("right\n\(wideRow)\nright-tail")
        let exact = try TableComparison.compare(
            left: left,
            right: right,
            options: TableComparisonOptions(
                maximumExactEditDistance: 4,
                maximumAlignmentWork: 100_000
            )
        )
        let bounded = try TableComparison.compare(
            left: left,
            right: right,
            options: TableComparisonOptions(
                maximumExactEditDistance: 4,
                maximumAlignmentWork: 32
            )
        )

        XCTAssertEqual(exact.alignment, .exact)
        XCTAssertEqual(exact.rows.map(\.status), [.modified, .equal, .modified])
        XCTAssertEqual(exact.rows[1].cells.count, 4_096)
        XCTAssertEqual(exact.rows[1].cells.first?.left?.value, "value-0")
        XCTAssertEqual(exact.rows[1].cells.last?.right?.value, "value-4095")
        XCTAssertTrue(exact.rows[1].cells.allSatisfy { $0.status == .equal })
        XCTAssertEqual(bounded.alignment, .boundedFallback)
        XCTAssertEqual(bounded.rows.map(\.status), [.modified, .equal, .modified])
        assertStableIndicesAndReconstruction(exact)
        assertStableIndicesAndReconstruction(bounded)
    }

    func testCommonPrefixAndSuffixConsumeAlignmentWork() throws {
        let left = try DelimitedTableParser.parse("prefix\nleft\nsuffix")
        let right = try DelimitedTableParser.parse("prefix\nright\nsuffix")

        let bounded = try TableComparison.compare(
            left: left,
            right: right,
            options: TableComparisonOptions(
                maximumExactEditDistance: 4,
                maximumAlignmentWork: 23
            )
        )
        let exact = try TableComparison.compare(
            left: left,
            right: right,
            options: TableComparisonOptions(
                maximumExactEditDistance: 4,
                maximumAlignmentWork: 24
            )
        )

        XCTAssertEqual(bounded.alignment, .boundedFallback)
        XCTAssertEqual(exact.alignment, .exact)
        XCTAssertEqual(bounded.rows.map(\.status), [.equal, .modified, .equal])
        XCTAssertEqual(exact.rows.map(\.status), [.equal, .modified, .equal])
        assertComparisonInvariants(bounded)
        assertComparisonInvariants(exact)
    }

    func testCanonicalEquivalentShiftedRowsAlignExactly() throws {
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"
        let result = try TableComparison.compare(
            left: "head\n\(composed)\ntail",
            right: "inserted\nhead\n\(decomposed)\ntail"
        )

        XCTAssertEqual(result.alignment, .exact)
        XCTAssertEqual(result.rows.map(\.status), [.added, .equal, .equal, .equal])
        XCTAssertEqual(result.rows[2].left?.values, [composed])
        XCTAssertEqual(result.rows[2].right?.values, [decomposed])
        assertComparisonInvariants(result)
    }

    func testPreCancelledParseAndComparisonFailForEmptyAndNonemptyInputs() async throws {
        for input in ["", "a,b"] {
            let parseError = await Task { () -> DelimitedTableParseError? in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try DelimitedTableParser.parse(input)
                    return nil
                } catch {
                    return error as? DelimitedTableParseError
                }
            }.value
            XCTAssertEqual(parseError, .cancelled, "input=\(input.debugDescription)")
        }

        for input in ["", "value"] {
            let table = try DelimitedTableParser.parse(input)
            let comparisonError = await Task { () -> TableComparisonError? in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try TableComparison.compare(left: table, right: table)
                    return nil
                } catch {
                    return error as? TableComparisonError
                }
            }.value
            XCTAssertEqual(comparisonError, .cancelled, "input=\(input.debugDescription)")
        }
    }

    private func rowSequences(maximumLength: Int) -> [[String]] {
        var sequences: [[String]] = [[]]
        for length in 1...maximumLength {
            for bits in 0..<(1 << length) {
                sequences.append((0..<length).map { bits & (1 << $0) == 0 ? "a" : "b" })
            }
        }
        return sequences
    }

    private func longestCommonSubsequenceLength(_ left: [String], _ right: [String]) -> Int {
        var previous = [Int](repeating: 0, count: right.count + 1)
        for leftValue in left {
            var current = [Int](repeating: 0, count: right.count + 1)
            for (rightIndex, rightValue) in right.enumerated() {
                if leftValue == rightValue {
                    current[rightIndex + 1] = previous[rightIndex] + 1
                } else {
                    current[rightIndex + 1] = max(previous[rightIndex + 1], current[rightIndex])
                }
            }
            previous = current
        }
        return previous[right.count]
    }

    private func assertStableIndicesAndReconstruction(
        _ result: TableComparisonResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.rows.map(\.index), Array(result.rows.indices), file: file, line: line)
        XCTAssertEqual(
            result.rows.compactMap(\.leftIndex),
            Array(result.left.rows.indices),
            file: file,
            line: line
        )
        XCTAssertEqual(
            result.rows.compactMap(\.rightIndex),
            Array(result.right.rows.indices),
            file: file,
            line: line
        )
        XCTAssertEqual(
            result.rows.compactMap(\.left?.values),
            result.left.rows.map(\.values),
            file: file,
            line: line
        )
        XCTAssertEqual(
            result.rows.compactMap(\.right?.values),
            result.right.rows.map(\.values),
            file: file,
            line: line
        )
        for row in result.rows {
            XCTAssertEqual(row.cells.map(\.index), Array(row.cells.indices), file: file, line: line)
            XCTAssertEqual(
                row.cells.compactMap(\.leftIndex),
                Array(row.left?.cells.indices ?? 0..<0),
                file: file,
                line: line
            )
            XCTAssertEqual(
                row.cells.compactMap(\.rightIndex),
                Array(row.right?.cells.indices ?? 0..<0),
                file: file,
                line: line
            )
            switch row.status {
            case .equal:
                XCTAssertNotNil(row.leftIndex, file: file, line: line)
                XCTAssertNotNil(row.rightIndex, file: file, line: line)
                XCTAssertNotNil(row.left, file: file, line: line)
                XCTAssertNotNil(row.right, file: file, line: line)
                XCTAssertEqual(row.left?.values, row.right?.values, file: file, line: line)
                XCTAssertTrue(row.cells.allSatisfy { $0.status == .equal }, file: file, line: line)
            case .modified:
                XCTAssertNotNil(row.leftIndex, file: file, line: line)
                XCTAssertNotNil(row.rightIndex, file: file, line: line)
                XCTAssertNotNil(row.left, file: file, line: line)
                XCTAssertNotNil(row.right, file: file, line: line)
                XCTAssertNotEqual(row.left?.values, row.right?.values, file: file, line: line)
            case .removed:
                XCTAssertNotNil(row.leftIndex, file: file, line: line)
                XCTAssertNil(row.rightIndex, file: file, line: line)
                XCTAssertNotNil(row.left, file: file, line: line)
                XCTAssertNil(row.right, file: file, line: line)
                XCTAssertTrue(row.cells.allSatisfy { $0.status == .removed }, file: file, line: line)
            case .added:
                XCTAssertNil(row.leftIndex, file: file, line: line)
                XCTAssertNotNil(row.rightIndex, file: file, line: line)
                XCTAssertNil(row.left, file: file, line: line)
                XCTAssertNotNil(row.right, file: file, line: line)
                XCTAssertTrue(row.cells.allSatisfy { $0.status == .added }, file: file, line: line)
            }
            for cell in row.cells {
                switch cell.status {
                case .equal:
                    XCTAssertNotNil(cell.leftIndex, file: file, line: line)
                    XCTAssertNotNil(cell.rightIndex, file: file, line: line)
                    XCTAssertNotNil(cell.left, file: file, line: line)
                    XCTAssertNotNil(cell.right, file: file, line: line)
                    XCTAssertEqual(cell.left?.value, cell.right?.value, file: file, line: line)
                case .modified:
                    XCTAssertNotNil(cell.leftIndex, file: file, line: line)
                    XCTAssertNotNil(cell.rightIndex, file: file, line: line)
                    XCTAssertNotNil(cell.left, file: file, line: line)
                    XCTAssertNotNil(cell.right, file: file, line: line)
                    XCTAssertNotEqual(cell.left?.value, cell.right?.value, file: file, line: line)
                case .removed:
                    XCTAssertNotNil(cell.leftIndex, file: file, line: line)
                    XCTAssertNil(cell.rightIndex, file: file, line: line)
                    XCTAssertNotNil(cell.left, file: file, line: line)
                    XCTAssertNil(cell.right, file: file, line: line)
                case .added:
                    XCTAssertNil(cell.leftIndex, file: file, line: line)
                    XCTAssertNotNil(cell.rightIndex, file: file, line: line)
                    XCTAssertNil(cell.left, file: file, line: line)
                    XCTAssertNotNil(cell.right, file: file, line: line)
                }
            }
        }
    }

    private func assertComparisonInvariants(
        _ result: TableComparisonResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertStableIndicesAndReconstruction(result, file: file, line: line)
        XCTAssertEqual(result.summary, TableComparisonSummary(rows: result.rows), file: file, line: line)
        XCTAssertEqual(result.isEqual, result.rows.allSatisfy { $0.status == .equal }, file: file, line: line)
    }

    private func assertParseError(
        _ expected: DelimitedTableParseError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? DelimitedTableParseError, expected, file: file, line: line)
        }
    }

    private func assertComparisonError(
        _ expected: TableComparisonError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? TableComparisonError, expected, file: file, line: line)
        }
    }
}
