import MacMergeCore
import Testing

@Suite("ConflictFileParser")
struct ConflictFileParserTests {
    @Test("Normal text and marker-like text are rejected")
    func rejectsTextWithoutAValidOpeningMarker() {
        let inputs = [
            "",
            "plain text\nwith no conflict\n",
            " <<<<<<< indented\n=======\n>>>>>>> incoming\n",
            "<<<<<<<missing-space\n=======\n>>>>>>> incoming\n",
            "=======\n>>>>>>> incoming\n"
        ]

        for input in inputs {
            expectError(.noConflictMarkers, parsing: input)
        }
    }

    @Test("Two-way conflicts split current and incoming text")
    func parsesTwoWayConflict() throws {
        let input = document([
            "shared before",
            "<<<<<<< current.txt",
            "current line",
            "=======",
            "incoming line",
            ">>>>>>> incoming.txt",
            "shared after"
        ])

        let result = try ConflictFileParser.parse(input)

        #expect(result.currentText == document(["shared before", "current line", "shared after"]))
        #expect(result.baseText == nil)
        #expect(result.incomingText == document(["shared before", "incoming line", "shared after"]))
        #expect(result.isThreeWay == false)
        #expect(
            result.conflicts == [
                ConflictFileConflict(
                    sourceLineRange: 2...6,
                    markerWidth: 7,
                    currentLabel: "current.txt",
                    baseLabel: nil,
                    incomingLabel: "incoming.txt"
                )
            ])
    }

    @Test("Diff3 conflicts split all three revisions")
    func parsesDiff3Conflict() throws {
        let input = document([
            "shared before",
            "<<<<<<< HEAD",
            "current line",
            "||||||| merge-base",
            "base line",
            "=======",
            "incoming line",
            ">>>>>>> topic",
            "shared after"
        ])

        let result = try ConflictFileParser.parse(input)

        #expect(result.currentText == document(["shared before", "current line", "shared after"]))
        #expect(result.baseText == document(["shared before", "base line", "shared after"]))
        #expect(result.incomingText == document(["shared before", "incoming line", "shared after"]))
        #expect(result.isThreeWay)
        #expect(
            result.conflicts == [
                ConflictFileConflict(
                    sourceLineRange: 2...8,
                    markerWidth: 7,
                    currentLabel: "HEAD",
                    baseLabel: "merge-base",
                    incomingLabel: "topic"
                )
            ])
    }

    @Test("Labels retain whitespace after their required delimiter")
    func preservesLabelsAndWhitespace() throws {
        let input = document([
            "<<<<<<<   current label \t",
            "  current body  ",
            "||||||| ",
            "\tbase body",
            "=======",
            "incoming body\t ",
            ">>>>>>> incoming label  \t"
        ])

        let result = try ConflictFileParser.parse(input)

        #expect(result.currentText == "  current body  \n")
        #expect(result.baseText == "\tbase body\n")
        #expect(result.incomingText == "incoming body\t \n")
        #expect(result.conflicts.first?.currentLabel == "  current label \t")
        #expect(result.conflicts.first?.baseLabel == "")
        #expect(result.conflicts.first?.incomingLabel == "incoming label  \t")

        let bareBaseMarker = document([
            "<<<<<<< current",
            "current body",
            "|||||||",
            "base body",
            "=======",
            "incoming body",
            ">>>>>>> incoming"
        ])
        #expect(try ConflictFileParser.parse(bareBaseMarker).conflicts.first?.baseLabel == nil)
    }

    @Test("Marker widths 1, 6, 7, and custom widths are accepted")
    func acceptsSupportedMarkerWidths() throws {
        for width in [1, 6, 7, 19] {
            let current = String(repeating: "<", count: width)
            let separator = String(repeating: "=", count: width)
            let incoming = String(repeating: ">", count: width)
            let input = document([current, "ours", separator, "theirs", incoming], terminating: false)

            let result = try ConflictFileParser.parse(input)

            #expect(result.currentText == "ours\n")
            #expect(result.incomingText == "theirs\n")
            #expect(result.conflicts.count == 1)
            #expect(result.conflicts.first?.markerWidth == width)
            #expect(result.conflicts.first?.sourceLineRange == 1...5)
        }
    }

    @Test("Wrong-width marker runs remain body text")
    func treatsWrongWidthMarkerRunsAsBody() throws {
        let input = document([
            "<<<<<<< ours",
            "current",
            "|||||| base-looking",
            "======",
            "=======",
            "incoming",
            ">>>>>>>> closing-looking",
            ">>>>>>> theirs"
        ])

        let result = try ConflictFileParser.parse(input)

        #expect(
            result.currentText
                == document([
                    "current",
                    "|||||| base-looking",
                    "======"
                ]))
        #expect(result.incomingText == document(["incoming", ">>>>>>>> closing-looking"]))
        #expect(result.conflicts.first?.sourceLineRange == 1...8)
    }

    @Test("Multiple diff3 conflicts preserve common text and ranges")
    func parsesMultipleConflicts() throws {
        let input = document([
            "before",
            "<<<<<<< first-current",
            "current one",
            "||||||| first-base",
            "base one",
            "=======",
            "incoming one",
            ">>>>>>> first-incoming",
            "between",
            "<<<<<<< second-current",
            "current two",
            "||||||| second-base",
            "base two",
            "=======",
            "incoming two",
            ">>>>>>> second-incoming",
            "after"
        ])

        let result = try ConflictFileParser.parse(input)

        #expect(result.currentText == document(["before", "current one", "between", "current two", "after"]))
        #expect(result.baseText == document(["before", "base one", "between", "base two", "after"]))
        #expect(result.incomingText == document(["before", "incoming one", "between", "incoming two", "after"]))
        #expect(result.conflicts.map(\.sourceLineRange) == [2...8, 10...16])
        #expect(result.conflicts.map(\.currentLabel) == ["first-current", "second-current"])
        #expect(result.conflicts.map(\.baseLabel) == ["first-base", "second-base"])
        #expect(result.conflicts.map(\.incomingLabel) == ["first-incoming", "second-incoming"])
    }

    @Test("Two-way followed by diff3 is rejected")
    func rejectsTwoWayThenDiff3() {
        let input = document([
            "<<<<<<< first",
            "current one",
            "=======",
            "incoming one",
            ">>>>>>> first",
            "<<<<<<< second",
            "current two",
            "||||||| base",
            "base two",
            "=======",
            "incoming two",
            ">>>>>>> second"
        ])

        expectError(.mixedConflictStyles(line: 8), parsing: input)
    }

    @Test("Diff3 followed by two-way is rejected")
    func rejectsDiff3ThenTwoWay() {
        let input = document([
            "<<<<<<< first",
            "current one",
            "||||||| base",
            "base one",
            "=======",
            "incoming one",
            ">>>>>>> first",
            "<<<<<<< second",
            "current two",
            "=======",
            "incoming two",
            ">>>>>>> second"
        ])

        expectError(.mixedConflictStyles(line: 10), parsing: input)
    }

    @Test("Malformed matching-width markers are rejected")
    func rejectsMalformedMarkers() {
        let cases: [(String, ConflictFileParserError)] = [
            (
                document(["<<<<<<< ours", "current", "======= label", "incoming", ">>>>>>> theirs"]),
                .malformedMarker(line: 3)
            ),
            (
                document(["<<<<<<< ours", "current", "|||||||base", "base", "=======", "incoming", ">>>>>>> theirs"]),
                .malformedMarker(line: 3)
            ),
            (
                document(["<<<<<<< ours", "current", "=======", "incoming", ">>>>>>>theirs"]),
                .malformedMarker(line: 5)
            ),
            (
                document(["<<<<<<< bad\0label", "current", "=======", "incoming", ">>>>>>> theirs"]),
                .malformedMarker(line: 1)
            )
        ]

        for (input, error) in cases {
            expectError(error, parsing: input)
        }
    }

    @Test("Nested conflicts are rejected in either side")
    func rejectsNestedConflicts() {
        let cases = [
            document(["<<<<<<< outer", "current", "<<<<<<< inner", "=======", ">>>>>>> inner", "=======", ">>>>>>> outer"]),
            document(["<<<<<<< outer", "=======", "incoming", "<<<<<<< inner", "=======", ">>>>>>> inner", ">>>>>>> outer"])
        ]

        expectError(.nestedConflict(line: 3), parsing: cases[0])
        expectError(.nestedConflict(line: 4), parsing: cases[1])
    }

    @Test("Duplicate separators and base markers are rejected")
    func rejectsDuplicateSectionMarkers() {
        let duplicateSeparator = document([
            "<<<<<<< ours",
            "current",
            "=======",
            "=======",
            "incoming",
            ">>>>>>> theirs"
        ])
        let duplicateBase = document([
            "<<<<<<< ours",
            "||||||| base-one",
            "||||||| base-two",
            "=======",
            "incoming",
            ">>>>>>> theirs"
        ])

        expectError(.unexpectedMarker(kind: .separator, line: 4), parsing: duplicateSeparator)
        expectError(.unexpectedMarker(kind: .base, line: 3), parsing: duplicateBase)
    }

    @Test("Out-of-order and unterminated conflicts are rejected")
    func rejectsOutOfOrderAndUnterminatedConflicts() {
        let prematureClose = document(["<<<<<<< ours", "current", ">>>>>>> theirs"])
        let baseWithoutSeparator = document([
            "<<<<<<< ours",
            "||||||| base",
            "base body",
            ">>>>>>> theirs"
        ])
        let unterminated = document(["before", "<<<<<<< ours", "current"])

        expectError(.unexpectedMarker(kind: .incoming, line: 3), parsing: prematureClose)
        expectError(.unexpectedMarker(kind: .incoming, line: 4), parsing: baseWithoutSeparator)
        expectError(.unterminatedConflict(startLine: 2), parsing: unterminated)
    }

    @Test("LF, CR, and CRLF records are preserved exactly")
    func preservesUniformLineEndings() throws {
        for lineEnding in ["\n", "\r", "\r\n"] {
            let input = document(
                ["before", "<<<<<<< ours", "current", "=======", "incoming", ">>>>>>> theirs", "after"],
                eol: lineEnding
            )

            let result = try ConflictFileParser.parse(input)

            #expect(result.currentText == document(["before", "current", "after"], eol: lineEnding))
            #expect(result.incomingText == document(["before", "incoming", "after"], eol: lineEnding))
            #expect(result.conflicts.first?.sourceLineRange == 2...6)
        }
    }

    @Test("Mixed line endings remain attached to retained records")
    func preservesMixedLineEndings() throws {
        let input = "before\r\n<<<<<<< ours\ncurrent\r=======\r\nincoming\n>>>>>>> theirs\rafter"

        let result = try ConflictFileParser.parse(input)

        #expect(result.currentText == "before\r\ncurrent\rafter")
        #expect(result.incomingText == "before\r\nincoming\nafter")
        #expect(result.conflicts.first?.sourceLineRange == 2...6)
    }

    @Test("Closing-marker termination does not create an output newline")
    func preservesFinalNewlineSemanticsAndRanges() throws {
        for markerHasNewline in [false, true] {
            let input = document(
                ["<<<<<<<", "current", "=======", "incoming", ">>>>>>>"],
                terminating: markerHasNewline
            )

            let result = try ConflictFileParser.parse(input)

            #expect(result.currentText == "current\n")
            #expect(result.incomingText == "incoming\n")
            #expect(result.conflicts.first?.sourceLineRange == 1...5)
        }

        let unterminatedTail = document(
            ["<<<<<<<", "current", "=======", "incoming", ">>>>>>>", "tail"],
            terminating: false
        )
        let terminatedTail = unterminatedTail + "\n"

        #expect(try ConflictFileParser.parse(unterminatedTail).currentText == "current\ntail")
        #expect(try ConflictFileParser.parse(unterminatedTail).incomingText == "incoming\ntail")
        #expect(try ConflictFileParser.parse(terminatedTail).currentText == "current\ntail\n")
        #expect(try ConflictFileParser.parse(terminatedTail).incomingText == "incoming\ntail\n")
        #expect(try ConflictFileParser.parse(terminatedTail).conflicts.first?.sourceLineRange == 1...5)
    }

    @Test("Input byte limit accepts exact UTF-8 size and rejects one byte less")
    func enforcesInputByteLimit() throws {
        let input = document(["< ours", "é", "=", "incoming", "> theirs"], terminating: false)
        let exactSize = input.utf8.count

        _ = try ConflictFileParser.parse(input, limits: limits(maximumInputBytes: exactSize))
        expectError(
            .inputTooLarge(maximumBytes: exactSize - 1),
            parsing: input,
            limits: limits(maximumInputBytes: exactSize - 1)
        )
    }

    @Test("Line limit accepts exact count and rejects the next line")
    func enforcesLineCountLimit() throws {
        let input = document(["<", "current", "=", "incoming", ">"], terminating: false)

        _ = try ConflictFileParser.parse(input, limits: limits(maximumLineCount: 5))
        expectError(
            .tooManyLines(maximum: 4),
            parsing: input,
            limits: limits(maximumLineCount: 4)
        )
    }

    @Test("Conflict limit accepts exact count and rejects another opening marker")
    func enforcesConflictCountLimit() throws {
        let input = document([
            "< first",
            "current one",
            "=",
            "incoming one",
            "> first",
            "< second",
            "current two",
            "=",
            "incoming two",
            "> second"
        ])

        _ = try ConflictFileParser.parse(input, limits: limits(maximumConflictCount: 2))
        expectError(
            .tooManyConflicts(maximum: 1),
            parsing: input,
            limits: limits(maximumConflictCount: 1)
        )
        expectError(
            .tooManyConflicts(maximum: 0),
            parsing: input,
            limits: limits(maximumConflictCount: 0)
        )
    }

    @Test("Marker limit accepts exact count and rejects the next marker")
    func enforcesMarkerCountLimit() throws {
        let input = document(["<", "current", "=", "incoming", ">"])

        _ = try ConflictFileParser.parse(input, limits: limits(maximumMarkerCount: 3))
        expectError(
            .tooManyMarkers(maximum: 2),
            parsing: input,
            limits: limits(maximumMarkerCount: 2)
        )
        expectError(
            .tooManyMarkers(maximum: 0),
            parsing: input,
            limits: limits(maximumMarkerCount: 0)
        )
    }

    @Test("Marker-width limit accepts exact width and rejects a wider opener")
    func enforcesMarkerWidthLimit() throws {
        let widthSix = document(["<<<<<<", "current", "======", "incoming", ">>>>>>"])
        let widthSeven = document(["<<<<<<<", "current", "=======", "incoming", ">>>>>>>"])

        _ = try ConflictFileParser.parse(widthSix, limits: limits(maximumMarkerWidth: 6))
        expectError(
            .markerTooWide(line: 1, maximum: 6),
            parsing: widthSeven,
            limits: limits(maximumMarkerWidth: 6)
        )
    }

    @Test("Label-byte limit is UTF-8 based and checked on every labeled marker")
    func enforcesMarkerLabelByteLimit() throws {
        let exact = document([
            "<<<<<<< é",
            "current",
            "||||||| é",
            "base",
            "=======",
            "incoming",
            ">>>>>>> é"
        ])

        let result = try ConflictFileParser.parse(exact, limits: limits(maximumLabelBytes: 2))
        #expect(result.conflicts.first?.currentLabel == "é")
        #expect(result.conflicts.first?.baseLabel == "é")
        #expect(result.conflicts.first?.incomingLabel == "é")

        let oversizedLabels: [(String, Int)] = [
            (document(["<<<<<<< é", "current", "=======", "incoming", ">>>>>>> o"]), 1),
            (document(["<<<<<<< o", "current", "||||||| é", "base", "=======", "incoming", ">>>>>>> i"]), 3),
            (document(["<<<<<<< o", "current", "=======", "incoming", ">>>>>>> é"]), 5)
        ]
        for (input, line) in oversizedLabels {
            expectError(
                .markerLabelTooLong(line: line, maximumBytes: 1),
                parsing: input,
                limits: limits(maximumLabelBytes: 1)
            )
        }
    }

    private func expectError(
        _ expected: ConflictFileParserError,
        parsing input: String,
        limits: ConflictFileParserLimits = .default
    ) {
        #expect(throws: expected) {
            _ = try ConflictFileParser.parse(input, limits: limits)
        }
    }

    private func document(
        _ lines: [String],
        eol: String = "\n",
        terminating: Bool = true
    ) -> String {
        lines.joined(separator: eol) + (terminating ? eol : "")
    }

    private func limits(
        maximumInputBytes: Int = 1_000_000,
        maximumLineCount: Int = 1_000,
        maximumConflictCount: Int = 100,
        maximumMarkerCount: Int = 400,
        maximumMarkerWidth: Int = 1_024,
        maximumLabelBytes: Int = 1_000
    ) -> ConflictFileParserLimits {
        ConflictFileParserLimits(
            maximumInputBytes: maximumInputBytes,
            maximumLineCount: maximumLineCount,
            maximumConflictCount: maximumConflictCount,
            maximumMarkerCount: maximumMarkerCount,
            maximumMarkerWidth: maximumMarkerWidth,
            maximumLabelBytes: maximumLabelBytes
        )
    }
}
