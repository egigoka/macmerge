import XCTest

@testable import MacMergeCore

final class NumberedTextCopyTests: XCTestCase {
    func testFormatsChosenSideAcrossSparseSelectedRangesAndMissingRows() throws {
        let rows = [
            row(left: (1, "left one"), right: (10, "right ten"), kind: .modified),
            row(left: (2, "left two"), right: nil, kind: .removed),
            row(left: nil, right: (11, "right eleven"), kind: .added),
            row(left: (3, "left three"), right: (12, "right twelve"), kind: .unchanged)
        ]

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1, 2..<4],
                side: .left
            ),
            "1: left one\n-: \n3: left three"
        )
        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<2, 3..<4],
                side: .right
            ),
            "10: right ten\n -: \n12: right twelve"
        )
    }

    func testAdjacentRangesRetainSelectionOrderWithoutDuplicateRows() throws {
        let rows = (1...4).map { number in
            row(left: (number, "L\(number)"), right: (number, "R\(number)"))
        }

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<2, 2..<3, 3..<4],
                side: .left,
                options: NumberedTextCopyOptions(numberSeparator: "|")
            ),
            "1|L1\n2|L2\n3|L3\n4|L4"
        )
    }

    func testSelectionAndOptionValidationReturnsSpecificErrors() throws {
        let rows = [row(left: (1, "one"), right: (1, "one"))]
        assertNumberedError(.emptySelection) {
            try NumberedTextCopy.format(rows: rows, selectedRanges: [], side: .left)
        }
        for range in [-1..<0, 0..<0, 1..<2] {
            assertNumberedError(
                .invalidSelectionRange(
                    selectionIndex: 0,
                    lowerBound: range.lowerBound,
                    upperBound: range.upperBound,
                    rowCount: 1
                )
            ) {
                try NumberedTextCopy.format(rows: rows, selectedRanges: [range], side: .left)
            }
        }

        let threeRows = (1...3).map { row(left: ($0, ""), right: ($0, "")) }
        assertNumberedError(.unorderedOrOverlappingSelection(selectionIndex: 1)) {
            try NumberedTextCopy.format(
                rows: threeRows,
                selectedRanges: [1..<3, 0..<1],
                side: .left
            )
        }
        assertNumberedError(.unorderedOrOverlappingSelection(selectionIndex: 1)) {
            try NumberedTextCopy.format(
                rows: threeRows,
                selectedRanges: [0..<2, 1..<3],
                side: .left
            )
        }

        assertNumberedError(.invalidMinimumLineNumberWidth(-1)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(minimumLineNumberWidth: -1)
            )
        }
        assertNumberedError(.invalidMaximumRows(0)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(maximumRows: 0)
            )
        }
        assertNumberedError(.invalidMaximumOutputBytes(Int.min)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(maximumOutputBytes: Int.min)
            )
        }
    }

    func testSelectedRowLimitAcceptsExactAndRejectsOneMore() throws {
        let rows = (1...3).map { row(left: ($0, ""), right: ($0, "")) }
        let options = NumberedTextCopyOptions(maximumRows: 2)

        XCTAssertNoThrow(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1, 2..<3],
                side: .left,
                options: options
            )
        )
        assertNumberedError(.tooManyRows(maximumRows: 2)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<3],
                side: .left,
                options: options
            )
        }
    }

    func testMissingMarkerUsesGraphemeWidthAndBothAlignmentDirections() throws {
        let family = "👨‍👩‍👧‍👦"
        let rows = [
            row(left: nil, right: (1, "unused"), kind: .added),
            row(left: (100, "hundred"), right: (2, "unused"), kind: .modified)
        ]

        let rightAligned = NumberedTextCopyOptions(
            numberSeparator: "|",
            missingLineNumber: family,
            numberAlignment: .right,
            paddingCharacter: "·"
        )
        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<2],
                side: .left,
                options: rightAligned
            ),
            "··\(family)|\n100|hundred"
        )

        var leftAligned = rightAligned
        leftAligned.numberAlignment = .left
        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<2],
                side: .left,
                options: leftAligned
            ),
            "\(family)··|\n100|hundred"
        )
    }

    func testRepeatedMultigraphemeMissingMarkerKeepsCachedWidthAndBytesExact() throws {
        let marker = "e\u{301}👨‍👩‍👧‍👦"
        let rows = [
            row(left: nil, right: (1, "unused"), kind: .added),
            row(left: nil, right: (2, "unused"), kind: .added),
            row(left: (123, "present"), right: (3, "unused"), kind: .modified),
            row(left: nil, right: (4, "unused"), kind: .added)
        ]
        let expected = "·\(marker)|\n·\(marker)|\n123|present\n·\(marker)|"
        let options = NumberedTextCopyOptions(
            numberSeparator: "|",
            missingLineNumber: marker,
            paddingCharacter: "·",
            maximumOutputBytes: expected.utf8.count
        )

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<2, 2..<4],
                side: .left,
                options: options
            ),
            expected
        )

        var oneByteShort = options
        oneByteShort.maximumOutputBytes -= 1
        assertNumberedError(.outputTooLarge(maximumBytes: expected.utf8.count - 1)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<4],
                side: .left,
                options: oneByteShort
            )
        }
    }

    func testMixedLineEndingsAndFinalSeparatorRemainExact() throws {
        let rows = [
            row(left: (1, "a\r"), right: nil),
            row(left: (2, "b\n"), right: nil),
            row(left: (3, "c\r\n"), right: nil),
            row(left: (4, ""), right: nil)
        ]
        let options = NumberedTextCopyOptions(
            numberSeparator: ":",
            rowSeparator: "\r\n",
            includesTrailingRowSeparator: true
        )

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<4],
                side: .left,
                options: options
            ),
            "1:a\r\r\n2:b\n\r\n3:c\r\n\r\n4:\r\n"
        )
    }

    func testComparedMixedEOLInputUsesConfiguredRowAndFinalSeparators() throws {
        let rows = try LineDiff.compare(
            left: "alpha\r\nbeta\rgamma\n",
            right: "alpha\r\nbeta\rgamma\n"
        )

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<rows.count],
                side: .left
            ),
            "1: alpha\n2: beta\n3: gamma"
        )
        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<rows.count],
                side: .left,
                options: NumberedTextCopyOptions(
                    rowSeparator: "\r\n",
                    includesTrailingRowSeparator: true
                )
            ),
            "1: alpha\r\n2: beta\r\n3: gamma\r\n"
        )
    }

    func testComparedMixedEOLInputWithoutFinalNewlineDoesNotGainOne() throws {
        let rows = try LineDiff.compare(
            left: "alpha\r\nbeta\rgamma\nlast",
            right: "alpha\r\nbeta\rgamma\nlast"
        )

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<rows.count],
                side: .left,
                options: NumberedTextCopyOptions(rowSeparator: "\r\n")
            ),
            "1: alpha\r\n2: beta\r\n3: gamma\r\n4: last"
        )
    }

    func testIntegerBoundaryLineNumbersDetermineWidthWithoutOverflow() throws {
        let rows = [
            row(left: (Int.min, "minimum"), right: nil),
            row(left: (Int.max, "maximum"), right: nil)
        ]
        let minimum = String(Int.min)
        let maximum = String(Int.max)

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<2],
                side: .left,
                options: NumberedTextCopyOptions(numberSeparator: "|")
            ),
            "\(minimum)|minimum\n \(maximum)|maximum"
        )
    }

    func testUTF8OutputLimitAcceptsExactBytesAndRejectsOneByteLess() throws {
        let rows = [row(left: (1, "é"), right: nil)]
        let expected = "1: é"
        XCTAssertEqual(expected.utf8.count, 5)

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(maximumOutputBytes: 5)
            ),
            expected
        )
        assertNumberedError(.outputTooLarge(maximumBytes: 4)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(maximumOutputBytes: 4)
            )
        }
    }

    func testMultibytePaddingUsesByteLimitRatherThanCharacterCount() throws {
        let padding: Character = "🧑🏽‍💻"
        let paddingByteCount = String(padding).utf8.count
        let exactByteCount = paddingByteCount + 1
        let rows = [row(left: (1, ""), right: nil)]
        let options = NumberedTextCopyOptions(
            numberSeparator: "",
            minimumLineNumberWidth: 2,
            paddingCharacter: padding,
            maximumOutputBytes: exactByteCount
        )

        let output = try NumberedTextCopy.format(
            rows: rows,
            selectedRanges: [0..<1],
            side: .left,
            options: options
        )
        XCTAssertEqual(output, "\(padding)1")
        XCTAssertEqual(output.utf8.count, exactByteCount)

        var tooSmall = options
        tooSmall.maximumOutputBytes = exactByteCount - 1
        assertNumberedError(.outputTooLarge(maximumBytes: exactByteCount - 1)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: tooSmall
            )
        }
    }

    func testPaddingThatResegmentsWithNumberIsRejected() throws {
        let rows = [row(left: (1, ""), right: nil)]

        for alignment in [
            NumberedTextCopyNumberAlignment.left,
            NumberedTextCopyNumberAlignment.right
        ] {
            for padding in [Character("\u{0301}"), "🇺"] {
                assertNumberedError(.unstablePaddingCharacter) {
                    try NumberedTextCopy.format(
                        rows: rows,
                        selectedRanges: [0..<1],
                        side: .left,
                        options: NumberedTextCopyOptions(
                            numberSeparator: "",
                            minimumLineNumberWidth: 3,
                            numberAlignment: alignment,
                            paddingCharacter: padding
                        )
                    )
                }
            }
        }
    }

    func testStablePaddingThatResegmentsWithMissingMarkerIsRejected() throws {
        let rows = [row(left: nil, right: (1, "unused"), kind: .added)]

        assertNumberedError(.unstablePaddingCharacter) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(
                    numberSeparator: "",
                    missingLineNumber: "\u{0301}",
                    minimumLineNumberWidth: 2,
                    paddingCharacter: "a"
                )
            )
        }
    }

    func testStableRegionalIndicatorPairPaddingPreservesRenderedWidth() throws {
        let rows = [row(left: (1, ""), right: nil)]

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(
                    numberSeparator: "",
                    minimumLineNumberWidth: 3,
                    paddingCharacter: "🇺🇸"
                )
            ),
            "🇺🇸🇺🇸1"
        )
    }

    func testOversizedPaddingCharacterIsRejectedBeforeRepetition() throws {
        let padding = Character("a" + String(repeating: "\u{0301}", count: 17_000))
        let rows = [row(left: (1, ""), right: nil)]

        assertNumberedError(
            .paddingCharacterTooLarge(
                maximumUTF8Bytes: NumberedTextCopy.maximumPaddingUTF8Bytes,
                maximumUTF16CodeUnits: NumberedTextCopy.maximumPaddingUTF16CodeUnits
            )
        ) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(
                    numberSeparator: "",
                    minimumLineNumberWidth: 2,
                    paddingCharacter: padding
                )
            )
        }
    }

    func testOversizedUnbrokenGraphemeIsRejectedBeforeSegmentation() throws {
        let marker = "a" + String(repeating: "\u{0301}", count: 17_000)
        let rows = [row(left: nil, right: (1, "unused"), kind: .added)]

        assertNumberedError(
            .graphemeSegmentationTooComplex(maximumUnbrokenBytes: 16 * 1_024)
        ) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(missingLineNumber: marker)
            )
        }
    }

    func testOversizedPrependBaseExtendGraphemeIsRejectedBeforeSegmentation() throws {
        let prepend = "\u{0600}"
        let marker =
            String(
                repeating: prepend,
                count: NumberedTextCopy.maximumChunkBytes / prepend.utf8.count
            ) + "a\u{0301}"
        let rows = [row(left: nil, right: (1, "unused"), kind: .added)]

        XCTAssertGreaterThan(marker.utf8.count, NumberedTextCopy.maximumChunkBytes)
        assertNumberedError(
            .graphemeSegmentationTooComplex(maximumUnbrokenBytes: 16 * 1_024)
        ) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(missingLineNumber: marker)
            )
        }
    }

    func testRepeatedControlGraphemesDoNotTripUnbrokenLimit() throws {
        let rows = [row(left: nil, right: (1, "unused"), kind: .added)]
        let scalarCount = NumberedTextCopy.maximumChunkBytes + 1
        let markers = [
            String(repeating: "\u{200B}", count: scalarCount),
            String(repeating: "\u{0000}", count: scalarCount),
            String(repeating: "\r", count: scalarCount),
            String(repeating: "\n", count: scalarCount),
            String(repeating: "\r\n", count: scalarCount)
        ]

        for marker in markers {
            XCTAssertGreaterThan(marker.utf8.count, NumberedTextCopy.maximumChunkBytes)
            XCTAssertEqual(
                try NumberedTextCopy.format(
                    rows: rows,
                    selectedRanges: [0..<1],
                    side: .left,
                    options: NumberedTextCopyOptions(
                        numberSeparator: "",
                        missingLineNumber: marker
                    )
                ),
                marker
            )
        }
    }

    func testNeighboringZWJRegionalIndicatorAndExtendClustersRemainBounded() throws {
        let rows = [
            row(left: nil, right: (1, "unused"), kind: .added),
            row(left: (1, ""), right: (2, "unused"))
        ]
        for unit in ["👩‍💻", "🇺🇸", "a\u{0301}"] {
            let unitCount = NumberedTextCopy.maximumChunkBytes / unit.utf8.count + 1
            let marker = String(repeating: unit, count: unitCount)
            let expected = marker + "\n" + String(repeating: " ", count: unitCount - 1) + "1"

            XCTAssertGreaterThan(marker.utf8.count, NumberedTextCopy.maximumChunkBytes)
            XCTAssertEqual(marker.count, unitCount)
            XCTAssertEqual(
                try NumberedTextCopy.format(
                    rows: rows,
                    selectedRanges: [0..<2],
                    side: .left,
                    options: NumberedTextCopyOptions(
                        numberSeparator: "",
                        missingLineNumber: marker
                    )
                ),
                expected
            )
        }
    }

    func testOversizedZWJGraphemeIsRejectedBeforeSegmentation() throws {
        let marker = "👩" + String(repeating: "\u{200D}👩", count: 3_000)
        let rows = [row(left: nil, right: (1, "unused"), kind: .added)]

        XCTAssertGreaterThan(marker.utf8.count, NumberedTextCopy.maximumChunkBytes)
        assertNumberedError(
            .graphemeSegmentationTooComplex(maximumUnbrokenBytes: 16 * 1_024)
        ) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(missingLineNumber: marker)
            )
        }
    }

    func testIndependentNonASCIIGraphemesDoNotTripUnbrokenLimit() throws {
        let marker = String(repeating: "é", count: 9_000)
        let rows = [row(left: nil, right: (1, "unused"), kind: .added)]

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(
                    numberSeparator: "",
                    missingLineNumber: marker
                )
            ),
            marker
        )
    }

    func testIndependentModifierSymbolsDoNotTripUnbrokenLimit() throws {
        let marker = String(repeating: "^", count: NumberedTextCopy.maximumChunkBytes + 1)
        let rows = [row(left: nil, right: (1, "unused"), kind: .added)]

        XCTAssertEqual(
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(
                    numberSeparator: "",
                    missingLineNumber: marker
                )
            ),
            marker
        )
    }

    func testExtremeWidthRejectsBeforeAttemptingAllocation() throws {
        let rows = [row(left: (1, ""), right: nil)]
        assertNumberedError(.outputTooLarge(maximumBytes: 1)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(
                    numberSeparator: "",
                    minimumLineNumberWidth: Int.max,
                    maximumOutputBytes: 1
                )
            )
        }
    }

    func testMultibytePaddingByteMultiplicationOverflowIsRejected() throws {
        let rows = [row(left: (1, ""), right: nil)]
        assertNumberedError(.outputTooLarge(maximumBytes: Int.max)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: NumberedTextCopyOptions(
                    numberSeparator: "",
                    minimumLineNumberWidth: Int.max,
                    paddingCharacter: "é",
                    maximumOutputBytes: Int.max
                )
            )
        }
    }

    func testPaddingBeyondChunkBoundaryCompletesWithinOutputBound() throws {
        XCTAssertEqual(
            NumberedTextCopyOptions.defaultMaximumOutputBytes,
            64 * 1024 * 1024
        )

        let maximumBytes = NumberedTextCopy.maximumChunkBytes + 2
        let rows = [row(left: (1, ""), right: nil)]
        let options = NumberedTextCopyOptions(
            numberSeparator: "",
            minimumLineNumberWidth: maximumBytes,
            maximumOutputBytes: maximumBytes
        )

        let output = try NumberedTextCopy.format(
            rows: rows,
            selectedRanges: [0..<1],
            side: .left,
            options: options
        )
        XCTAssertEqual(output.utf8.count, maximumBytes)
        XCTAssertEqual(output.first, " ")
        XCTAssertEqual(output.last, "1")
        XCTAssertEqual(
            String(output.prefix(NumberedTextCopy.maximumChunkBytes)),
            String(repeating: " ", count: NumberedTextCopy.maximumChunkBytes)
        )
        XCTAssertEqual(String(output.suffix(2)), " 1")

        var oneByteShort = options
        oneByteShort.maximumOutputBytes = maximumBytes - 1
        assertNumberedError(.outputTooLarge(maximumBytes: maximumBytes - 1)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left,
                options: oneByteShort
            )
        }
    }

    func testLateOutputOverflowIsRejectedDuringPreflight() throws {
        let oversizedTail = String(repeating: "x", count: 1_000_000)
        let rows = [
            row(left: (1, "first"), right: nil),
            row(left: (2, oversizedTail), right: nil)
        ]
        assertNumberedError(.outputTooLarge(maximumBytes: 16)) {
            try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<2],
                side: .left,
                options: NumberedTextCopyOptions(maximumOutputBytes: 16)
            )
        }
    }

    func testSourceBackedOverflowIsRejectedBeforeTextMaterialization() async throws {
        let text = String(repeating: "x", count: 1_000_000)
        let rows = try LineDiff.compare(left: text, right: text)
        XCTAssertTrue(try XCTUnwrap(rows.first).usesSourceTextStorage)

        let task = Task {
            try NumberedTextCopy.$progressObserver.withValue({ progress in
                if progress.phase == .sourceByteEmission {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }) {
                try NumberedTextCopy.format(
                    rows: rows,
                    selectedRanges: [0..<1],
                    side: .left,
                    options: NumberedTextCopyOptions(
                        numberSeparator: "",
                        maximumOutputBytes: 1
                    )
                )
            }
        }

        do {
            _ = try await task.value
            XCTFail("Oversized source-backed text unexpectedly formatted")
        } catch let error as NumberedTextCopyError {
            XCTAssertEqual(error, .outputTooLarge(maximumBytes: 1))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAlreadyCancelledTaskStopsBeforeFormatting() async {
        let rows = [row(left: (1, "one"), right: nil)]
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try NumberedTextCopy.format(
                rows: rows,
                selectedRanges: [0..<1],
                side: .left
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled formatting unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationInterruptsFormattingAfterKnownInFlightProgress() async {
        let rowCount = 2_048
        let rows = (1...rowCount).map { row(left: ($0, "value-\($0)"), right: nil) }
        let task = Task {
            try NumberedTextCopy.$progressObserver.withValue({ progress in
                if progress == .init(phase: .lineNumberWidth, completedUnitCount: 1_024) {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }) {
                try NumberedTextCopy.format(
                    rows: rows,
                    selectedRanges: [0..<rows.count],
                    side: .left,
                    options: NumberedTextCopyOptions(maximumRows: rowCount)
                )
            }
        }

        do {
            _ = try await task.value
            XCTFail("Cancelled in-flight formatting unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationAtEveryFormattingPhaseCheckpoint() async throws {
        let sourceRows = try LineDiff.compare(left: "source", right: "source")
        let ownedRows = [row(left: (1, "owned"), right: nil)]
        let fixtures: [(NumberedTextCopy.Phase, [DiffRow], NumberedTextCopyOptions)] = [
            (.lineNumberWidth, ownedRows, NumberedTextCopyOptions()),
            (.graphemeSegmentation, ownedRows, NumberedTextCopyOptions()),
            (.outputPreflight, ownedRows, NumberedTextCopyOptions()),
            (.sourceBytePreflight, sourceRows, NumberedTextCopyOptions()),
            (.outputAssembly, ownedRows, NumberedTextCopyOptions()),
            (.sourceByteEmission, sourceRows, NumberedTextCopyOptions()),
            (
                .paddingChunk,
                ownedRows,
                NumberedTextCopyOptions(minimumLineNumberWidth: 2)
            )
        ]

        for (phase, rows, options) in fixtures {
            let task = Task {
                try NumberedTextCopy.$progressObserver.withValue({ progress in
                    if progress.phase == phase {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }) {
                    try NumberedTextCopy.format(
                        rows: rows,
                        selectedRanges: [0..<1],
                        side: .left,
                        options: options
                    )
                }
            }

            do {
                _ = try await task.value
                XCTFail("Expected cancellation at \(phase)")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error at \(phase): \(error)")
            }
        }
    }

    private func row(
        left: (Int, String)?,
        right: (Int, String)?,
        kind: DiffKind = .unchanged
    ) -> DiffRow {
        DiffRow(
            left: left.map { DiffLine(number: $0.0, text: $0.1) },
            right: right.map { DiffLine(number: $0.0, text: $0.1) },
            kind: kind
        )
    }

    private func assertNumberedError<T>(
        _ expected: NumberedTextCopyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? NumberedTextCopyError, expected, file: file, line: line)
        }
    }
}
