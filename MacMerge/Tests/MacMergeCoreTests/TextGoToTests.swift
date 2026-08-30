import Foundation
import XCTest

@testable import MacMergeCore

final class TextGoToTests: XCTestCase {
    private let identity = TextGoToDocumentIdentity(
        rawValue: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    )

    func testRequestRejectsChangedIdentityAndRevisionBeforeDocumentMetadata() throws {
        let otherIdentity = TextGoToDocumentIdentity(
            rawValue: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!
        )
        let document = makeDocument(
            "text",
            revision: 9,
            differences: [TextGoToDifference(selectionRange: NSRange(location: -1, length: 0))]
        )

        assertGoToError(.documentIdentityChanged(expected: otherIdentity, actual: identity)) {
            try TextGoTo.resolve(
                TextGoToRequest(
                    documentIdentity: otherIdentity,
                    documentRevision: 9,
                    target: .difference(1)
                ),
                in: document
            )
        }
        assertGoToError(.documentRevisionChanged(expected: 8, actual: 9)) {
            try TextGoTo.resolve(
                TextGoToRequest(
                    documentIdentity: self.identity,
                    documentRevision: 8,
                    target: .difference(1)
                ),
                in: document
            )
        }

        let maximumRevisionDocument = makeDocument("", revision: .max)
        let resolution = try TextGoTo.resolve(
            TextGoToRequest(document: maximumRevisionDocument, target: .line(TextPosition(line: 1))),
            in: maximumRevisionDocument
        )
        XCTAssertEqual(resolution.documentIdentity, identity)
        XCTAssertEqual(resolution.documentRevision, .max)
    }

    func testLineTargetUsesOnlyCRLFCRAndLFAsCanonicalLineBreaks() throws {
        let text = "A\r\nB\rC\nD\u{2028}E\u{2029}F\r\n"
        let document = makeDocument(text, revision: 11)
        let expected = [
            location(line: 1, column: 2, utf16Column: 2, offset: 1),
            location(line: 2, column: 2, utf16Column: 2, offset: 4),
            location(line: 3, column: 2, utf16Column: 2, offset: 6),
            location(line: 4, column: 6, utf16Column: 6, offset: 12),
            location(line: 5, column: 1, utf16Column: 1, offset: 14)
        ]

        for expectedLocation in expected {
            let requested = expectedLocation.position
            let resolution = try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .line(requested)),
                in: document
            )
            XCTAssertEqual(resolution.target, .line(requested: requested))
            XCTAssertEqual(resolution.selectionRange, NSRange(location: expectedLocation.utf16Offset, length: 0))
            XCTAssertEqual(resolution.selectionStart, expectedLocation)
            XCTAssertEqual(resolution.selectionEnd, expectedLocation)
            XCTAssertEqual(resolution.position, requested)
            XCTAssertTrue(resolution.isInsertionPoint)
        }

        for offset in [2, 13] {
            assertGoToError(.navigation(.offsetSplitsCharacter(offset))) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .utf16Offset(offset)),
                    in: document
                )
            }
        }
    }

    func testPercentTargetRoundsAcrossFirstAndLastLineInclusively() throws {
        let document = makeDocument("1\n2\n3\n4\n5")
        let cases: [(Double, Int, Int)] = [
            (0, 1, 0),
            (12.49, 1, 0),
            (12.5, 2, 2),
            (37.5, 3, 4),
            (50, 3, 4),
            (87.5, 5, 8),
            (100, 5, 8)
        ]

        for (percent, line, offset) in cases {
            let resolution = try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .percent(percent)),
                in: document
            )
            XCTAssertEqual(
                resolution.target,
                .percent(requested: percent, resolvedLine: line)
            )
            XCTAssertEqual(resolution.selectionRange, NSRange(location: offset, length: 0))
            XCTAssertEqual(
                resolution.selectionStart,
                location(line: line, column: 1, utf16Column: 1, offset: offset)
            )
        }
    }

    func testDifferenceTargetPreservesRangeAndMapsBothEndpoints() throws {
        let document = makeDocument(
            "A\r\nB",
            revision: 12,
            differences: [
                TextGoToDifference(selectionRange: NSRange(location: 1, length: 2))
            ]
        )

        let resolution = try TextGoTo.resolve(
            TextGoToRequest(document: document, target: .difference(1)),
            in: document
        )

        XCTAssertEqual(resolution.documentIdentity, identity)
        XCTAssertEqual(resolution.documentRevision, 12)
        XCTAssertEqual(resolution.target, .difference(index: 1))
        XCTAssertEqual(resolution.selectionRange, NSRange(location: 1, length: 2))
        XCTAssertEqual(
            resolution.selectionStart,
            location(line: 1, column: 2, utf16Column: 2, offset: 1)
        )
        XCTAssertEqual(
            resolution.selectionEnd,
            location(line: 2, column: 1, utf16Column: 1, offset: 3)
        )
        XCTAssertFalse(resolution.isInsertionPoint)
        XCTAssertEqual(resolution.position, TextPosition(line: 1, column: 2))
    }

    func testBookmarkTargetRequiresCurrentBookmarkAndResolvesItsLine() throws {
        let bookmarks = try LineBookmarks(lines: [2, 4])
        let document = makeDocument("one\ntwo\nthree\nfour", bookmarks: bookmarks)

        let resolution = try TextGoTo.resolve(
            TextGoToRequest(document: document, target: .bookmark(line: 4)),
            in: document
        )

        XCTAssertEqual(resolution.target, .bookmark(line: 4))
        XCTAssertEqual(resolution.selectionRange, NSRange(location: 14, length: 0))
        XCTAssertEqual(
            resolution.selectionStart,
            location(line: 4, column: 1, utf16Column: 1, offset: 14)
        )

        assertGoToError(.lineIsNotBookmarked(3)) {
            try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .bookmark(line: 3)),
                in: document
            )
        }
    }

    func testUTF16OffsetTargetMapsCanonicalLineEndpoints() throws {
        let document = makeDocument("ab\r\nc\rd\n")
        let cases = [
            location(line: 1, column: 1, utf16Column: 1, offset: 0),
            location(line: 1, column: 3, utf16Column: 3, offset: 2),
            location(line: 2, column: 1, utf16Column: 1, offset: 4),
            location(line: 2, column: 2, utf16Column: 2, offset: 5),
            location(line: 3, column: 1, utf16Column: 1, offset: 6),
            location(line: 4, column: 1, utf16Column: 1, offset: 8)
        ]

        for expected in cases {
            let resolution = try TextGoTo.resolve(
                TextGoToRequest(
                    document: document,
                    target: .utf16Offset(expected.utf16Offset)
                ),
                in: document
            )
            XCTAssertEqual(resolution.target, .utf16Offset(expected.utf16Offset))
            XCTAssertEqual(resolution.selectionStart, expected)
            XCTAssertEqual(resolution.selectionEnd, expected)
        }
    }

    func testUnicodeColumnsUseExtendedGraphemeBoundaries() throws {
        let text = "A🇺🇸👩🏽‍💻e\u{301}Z"
        let document = makeDocument(text)
        let expected = [
            location(line: 1, column: 1, utf16Column: 1, offset: 0),
            location(line: 1, column: 2, utf16Column: 2, offset: 1),
            location(line: 1, column: 3, utf16Column: 6, offset: 5),
            location(line: 1, column: 4, utf16Column: 13, offset: 12),
            location(line: 1, column: 5, utf16Column: 15, offset: 14),
            location(line: 1, column: 6, utf16Column: 16, offset: 15)
        ]

        for expectedLocation in expected {
            XCTAssertEqual(
                try TextGoTo.resolve(
                    TextGoToRequest(
                        document: document,
                        target: .line(expectedLocation.position)
                    ),
                    in: document
                ).selectionStart,
                expectedLocation
            )
            XCTAssertEqual(
                try TextGoTo.resolve(
                    TextGoToRequest(
                        document: document,
                        target: .utf16Offset(expectedLocation.utf16Offset)
                    ),
                    in: document
                ).selectionStart,
                expectedLocation
            )
        }

        let splitOffsets = [2, 3, 4, 6, 7, 8, 9, 10, 11, 13]
        for offset in splitOffsets {
            assertGoToError(.navigation(.offsetSplitsCharacter(offset))) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .utf16Offset(offset)),
                    in: document
                )
            }
        }
    }

    func testDifferenceEndpointsMustBothBeGraphemeBoundaries() {
        let text = "🇺🇸👩🏽‍💻e\u{301}"
        let validDocument = makeDocument(
            text,
            differences: [TextGoToDifference(selectionRange: NSRange(location: 0, length: 11))]
        )
        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(document: validDocument, target: .difference(1)),
                in: validDocument
            )
        )

        for range in [
            NSRange(location: 2, length: 2),
            NSRange(location: 4, length: 2),
            NSRange(location: 11, length: 1)
        ] {
            let document = makeDocument(
                text,
                differences: [TextGoToDifference(selectionRange: range)]
            )
            assertGoToError(
                .invalidDifferenceRange(index: 1, location: range.location, length: range.length)
            ) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .difference(1)),
                    in: document
                )
            }
        }
    }

    func testDifferenceRangesAcceptFullDocumentAndZeroLengthBoundsThroughEOF() throws {
        let cases: [(String, NSRange, TextLocation, TextLocation)] = [
            (
                "",
                NSRange(location: 0, length: 0),
                location(line: 1, column: 1, utf16Column: 1, offset: 0),
                location(line: 1, column: 1, utf16Column: 1, offset: 0)
            ),
            (
                "ab",
                NSRange(location: 0, length: 2),
                location(line: 1, column: 1, utf16Column: 1, offset: 0),
                location(line: 1, column: 3, utf16Column: 3, offset: 2)
            ),
            (
                "ab",
                NSRange(location: 0, length: 0),
                location(line: 1, column: 1, utf16Column: 1, offset: 0),
                location(line: 1, column: 1, utf16Column: 1, offset: 0)
            ),
            (
                "ab",
                NSRange(location: 1, length: 0),
                location(line: 1, column: 2, utf16Column: 2, offset: 1),
                location(line: 1, column: 2, utf16Column: 2, offset: 1)
            ),
            (
                "ab",
                NSRange(location: 2, length: 0),
                location(line: 1, column: 3, utf16Column: 3, offset: 2),
                location(line: 1, column: 3, utf16Column: 3, offset: 2)
            ),
            (
                "ab",
                NSRange(location: 1, length: 1),
                location(line: 1, column: 2, utf16Column: 2, offset: 1),
                location(line: 1, column: 3, utf16Column: 3, offset: 2)
            )
        ]

        for (text, range, expectedStart, expectedEnd) in cases {
            let document = makeDocument(
                text,
                differences: [TextGoToDifference(selectionRange: range)]
            )
            let resolution = try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .difference(1)),
                in: document
            )

            XCTAssertEqual(resolution.selectionRange, range)
            XCTAssertEqual(resolution.selectionStart, expectedStart)
            XCTAssertEqual(resolution.selectionEnd, expectedEnd)
        }
    }

    func testTargetValidationRejectsInvalidIndicesLinesColumnsAndOffsets() throws {
        let bookmarks = try LineBookmarks(lines: [3])
        let document = makeDocument(
            "a\nb",
            differences: [TextGoToDifference(selectionRange: NSRange(location: 0, length: 1))],
            bookmarks: bookmarks
        )

        let cases: [(TextGoToTarget, TextGoToError)] = [
            (.line(TextPosition(line: 0)), .navigation(.invalidLine(0))),
            (
                .line(TextPosition(line: 1, column: 0)),
                .navigation(.invalidColumn(line: 1, column: 0))
            ),
            (
                .line(TextPosition(line: 1, column: 3)),
                .navigation(.invalidColumn(line: 1, column: 3))
            ),
            (.line(TextPosition(line: 3)), .navigation(.invalidLine(3))),
            (.difference(0), .invalidDifferenceIndex(index: 0, differenceCount: 1)),
            (.difference(2), .invalidDifferenceIndex(index: 2, differenceCount: 1)),
            (.difference(.max), .invalidDifferenceIndex(index: .max, differenceCount: 1)),
            (.bookmark(line: 0), .navigation(.invalidLine(0))),
            (.bookmark(line: 3), .navigation(.invalidLine(3))),
            (.utf16Offset(-1), .navigation(.invalidUTF16Offset(-1))),
            (.utf16Offset(.max), .navigation(.invalidUTF16Offset(.max)))
        ]

        for (target, expected) in cases {
            assertGoToError(expected) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: target),
                    in: document
                )
            }
        }
    }

    func testPercentValidationRejectsNonFiniteAndOutOfRangeValues() {
        let document = makeDocument("a")

        for percent in [Double.nan, .infinity, -.infinity] {
            assertGoToError(.nonFinitePercent) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .percent(percent)),
                    in: document
                )
            }
        }
        for percent in [-Double.leastNonzeroMagnitude, 100.000_000_1] {
            assertGoToError(.percentOutsideRange(percent)) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .percent(percent)),
                    in: document
                )
            }
        }
    }

    func testDifferenceRangesRejectNegativeNotFoundOverflowAndPastEnd() {
        let malformedRanges = [
            NSRange(location: -1, length: 0),
            NSRange(location: 0, length: -1),
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: Int.max - 1, length: 2)
        ]

        for range in malformedRanges {
            let document = makeDocument(
                "ab",
                differences: [TextGoToDifference(selectionRange: range)]
            )
            assertGoToError(
                .invalidDifferenceRange(index: 1, location: range.location, length: range.length)
            ) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .difference(1)),
                    in: document
                )
            }
        }

        for range in [
            NSRange(location: 2, length: 1),
            NSRange(location: 3, length: 0)
        ] {
            let document = makeDocument(
                "ab",
                differences: [TextGoToDifference(selectionRange: range)]
            )
            assertGoToError(
                .invalidDifferenceRange(index: 1, location: range.location, length: range.length)
            ) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .difference(1)),
                    in: document
                )
            }
        }
    }

    func testLineLengthLimitCountsContentButNotCanonicalTerminators() throws {
        for terminator in ["\n", "\r", "\r\n"] {
            let document = makeDocument("abc" + terminator)
            let resolution = try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 2))),
                in: document,
                limits: limits(
                    navigation: navigationLimits(maximumLineUTF16Length: 3)
                )
            )

            XCTAssertEqual(
                resolution.selectionRange,
                NSRange(location: 3 + terminator.utf16.count, length: 0)
            )
        }

        let terminatorOnlyDocument = makeDocument("\r\n\r\n")
        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(
                    document: terminatorOnlyDocument,
                    target: .line(TextPosition(line: 3))
                ),
                in: terminatorOnlyDocument,
                limits: limits(
                    navigation: navigationLimits(maximumLineUTF16Length: 0)
                )
            )
        )
    }

    func testMetadataLimitsAcceptExactCountsAndRejectOneMore() throws {
        let differences = [
            TextGoToDifference(selectionRange: NSRange(location: 0, length: 0)),
            TextGoToDifference(selectionRange: NSRange(location: 1, length: 0))
        ]
        let bookmarks = try LineBookmarks(lines: [1, 2])
        let document = makeDocument("a\nb", differences: differences, bookmarks: bookmarks)
        let exactLimits = limits(maximumDifferences: 2, maximumBookmarks: 2)

        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: exactLimits
            )
        )
        assertGoToError(.tooManyDifferences(maximumDifferences: 1)) {
            try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: self.limits(maximumDifferences: 1, maximumBookmarks: 2)
            )
        }
        assertGoToError(.tooManyBookmarks(maximumBookmarks: 1)) {
            try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: self.limits(maximumDifferences: 2, maximumBookmarks: 1)
            )
        }
    }

    func testNavigationLimitsAcceptExactInputLineCountAndLineLengthBounds() throws {
        let inputDocument = makeDocument("😀x\r\n")
        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(document: inputDocument, target: .line(TextPosition(line: 2))),
                in: inputDocument,
                limits: limits(
                    navigation: navigationLimits(maximumInputUTF16Length: 5)
                )
            )
        )
        let oversizedInput = makeDocument("😀xy\r\n")
        assertGoToError(.navigation(.inputTooLarge(maximumUTF16Length: 5))) {
            try TextGoTo.resolve(
                TextGoToRequest(document: oversizedInput, target: .line(TextPosition(line: 1))),
                in: oversizedInput,
                limits: self.limits(
                    navigation: self.navigationLimits(maximumInputUTF16Length: 5)
                )
            )
        }

        let exactLines = makeDocument("a\n")
        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(document: exactLines, target: .line(TextPosition(line: 2))),
                in: exactLines,
                limits: limits(navigation: navigationLimits(maximumLineCount: 2))
            )
        )
        let tooManyLines = makeDocument("a\nb\n")
        assertGoToError(.navigation(.tooManyLines(maximumLines: 2))) {
            try TextGoTo.resolve(
                TextGoToRequest(document: tooManyLines, target: .line(TextPosition(line: 1))),
                in: tooManyLines,
                limits: self.limits(
                    navigation: self.navigationLimits(maximumLineCount: 2)
                )
            )
        }

        let exactLineLength = makeDocument("😀x")
        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(
                    document: exactLineLength,
                    target: .line(TextPosition(line: 1, column: 3))
                ),
                in: exactLineLength,
                limits: limits(
                    navigation: navigationLimits(maximumLineUTF16Length: 3)
                )
            )
        )
        let longLine = makeDocument("😀xy")
        assertGoToError(.navigation(.lineTooLong(line: 1, maximumUTF16Length: 3))) {
            try TextGoTo.resolve(
                TextGoToRequest(document: longLine, target: .line(TextPosition(line: 1))),
                in: longLine,
                limits: self.limits(
                    navigation: self.navigationLimits(maximumLineUTF16Length: 3)
                )
            )
        }
    }

    func testMinimumLimitsAreAcceptedAndEveryInvalidLimitIsRejected() throws {
        let minimumNavigation = navigationLimits(
            maximumInputUTF16Length: 0,
            maximumLineCount: 1,
            maximumLineUTF16Length: 0,
            maximumTokenCount: 1,
            maximumSymbolCount: 0,
            maximumSymbolNameUTF16Length: 1,
            maximumLookupResults: 1
        )
        let minimumLimits = limits(
            navigation: minimumNavigation,
            maximumDifferences: 0,
            maximumBookmarks: 0,
            maximumGraphemeClusterUTF16Length: 1,
            maximumWork: 0
        )
        let empty = makeDocument("")
        let resolution = try TextGoTo.resolve(
            TextGoToRequest(document: empty, target: .line(TextPosition(line: 1))),
            in: empty,
            limits: minimumLimits
        )
        XCTAssertEqual(resolution.workUnitsConsumed, 0)

        let invalidLimits = [
            limits(navigation: navigationLimits(maximumInputUTF16Length: -1)),
            limits(navigation: navigationLimits(maximumLineCount: 0)),
            limits(navigation: navigationLimits(maximumLineUTF16Length: -1)),
            limits(navigation: navigationLimits(maximumTokenCount: 0)),
            limits(navigation: navigationLimits(maximumSymbolCount: -1)),
            limits(navigation: navigationLimits(maximumSymbolNameUTF16Length: 0)),
            limits(navigation: navigationLimits(maximumLookupResults: 0)),
            limits(maximumDifferences: -1),
            limits(maximumBookmarks: -1),
            limits(maximumGraphemeClusterUTF16Length: 0),
            limits(maximumWork: -1)
        ]
        for invalid in invalidLimits {
            assertGoToError(.invalidLimits) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: empty, target: .line(TextPosition(line: 1))),
                    in: empty,
                    limits: invalid
                )
            }
        }
    }

    func testGraphemeClusterLimitAcceptsExactUTF16LengthAndRejectsOneLess() throws {
        let cluster = "👩🏽‍💻"
        XCTAssertEqual(cluster.utf16.count, 7)
        let document = makeDocument(cluster)

        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(
                    document: document,
                    target: .line(TextPosition(line: 1, column: 2))
                ),
                in: document,
                limits: limits(maximumGraphemeClusterUTF16Length: 7)
            )
        )
        assertGoToError(.graphemeSegmentationTooComplex(maximumClusterUTF16Length: 6)) {
            try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: self.limits(maximumGraphemeClusterUTF16Length: 6)
            )
        }
    }

    func testWholeDocumentValidationRejectsOversizedLateClusterBeforeEarlyTarget() {
        let text = "first\nsecond\nlast" + String(repeating: "\u{301}", count: 8)
        let document = makeDocument(text)

        assertGoToError(.graphemeSegmentationTooComplex(maximumClusterUTF16Length: 8)) {
            try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                in: document,
                limits: self.limits(maximumGraphemeClusterUTF16Length: 8)
            )
        }
    }

    func testEachTargetReportsExactWorkAndRejectsOneUnitLess() throws {
        let document = makeDocument(
            "ab\nc",
            differences: [TextGoToDifference(selectionRange: NSRange(location: 1, length: 1))],
            bookmarks: try LineBookmarks(lines: [2])
        )
        let cases: [(TextGoToTarget, Int)] = [
            (.line(TextPosition(line: 1, column: 2)), 10),
            (.percent(100), 8),
            (.difference(1), 14),
            (.bookmark(line: 2), 9),
            (.utf16Offset(1), 10)
        ]

        for (target, exactWork) in cases {
            let resolution = try TextGoTo.resolve(
                TextGoToRequest(document: document, target: target),
                in: document,
                limits: limits(maximumWork: exactWork)
            )
            XCTAssertEqual(resolution.workUnitsConsumed, exactWork)

            assertGoToError(.workLimitExceeded(maximumWork: exactWork - 1)) {
                try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: target),
                    in: document,
                    limits: self.limits(maximumWork: exactWork - 1)
                )
            }
        }

        XCTAssertNoThrow(
            try TextGoTo.resolve(
                TextGoToRequest(document: document, target: .utf16Offset(1)),
                in: document,
                limits: limits(maximumWork: .max)
            )
        )
    }

    func testLargeResolutionTaskAcceptsCancellationBeforeReportingCompletion() async {
        let inputLength = 8 * 1_024 * 1_024
        let document = makeDocument(String(repeating: "x", count: inputLength))
        let outcome = TextGoToCancellationState()
        let cancellationLimits = limits(
            navigation: navigationLimits(
                maximumInputUTF16Length: inputLength,
                maximumLineUTF16Length: inputLength
            ),
            maximumWork: .max
        )

        let task = Task.detached(priority: .userInitiated) {
            outcome.recordStart()
            do {
                _ = try TextGoTo.resolve(
                    TextGoToRequest(document: document, target: .line(TextPosition(line: 1))),
                    in: document,
                    limits: cancellationLimits
                )
                outcome.recordCompletion(.succeeded)
            } catch is CancellationError {
                outcome.recordCompletion(.cancelled)
            } catch {
                outcome.recordCompletion(.failed(String(describing: error)))
            }
        }

        guard await outcome.waitUntilStarted(timeout: 5) else {
            task.cancel()
            _ = await outcome.waitUntilCompleted(timeout: 5)
            XCTFail("Large resolution did not start within bounded wait")
            return
        }

        // TextGoTo has no public progress hook, so this cannot distinguish its entry check from a later
        // cancellation check. Keep the claim at worker level: after a bounded interval without reported
        // completion, cancel only while start/finish state is locked against the worker's completion update.
        guard !(await outcome.waitUntilCompleted(timeout: 0.05)) else {
            XCTFail("Large resolution completed before cancellation window")
            return
        }
        guard outcome.cancelIfRunning({ task.cancel() }) else {
            XCTFail("Large resolution finished before cancellation could be requested")
            return
        }
        guard await outcome.waitUntilCompleted(timeout: 5) else {
            task.cancel()
            _ = await outcome.waitUntilCompleted(timeout: 5)
            XCTFail("Cancelled resolution exceeded bounded wait")
            return
        }
        XCTAssertEqual(outcome.load(), .cancelled)
    }

    private func makeDocument(
        _ text: String,
        revision: UInt64 = 1,
        differences: [TextGoToDifference] = [],
        bookmarks: LineBookmarks = LineBookmarks()
    ) -> TextGoToDocumentSnapshot {
        TextGoToDocumentSnapshot(
            identity: identity,
            revision: revision,
            text: text,
            differences: differences,
            bookmarks: bookmarks
        )
    }

    private func location(
        line: Int,
        column: Int,
        utf16Column: Int,
        offset: Int
    ) -> TextLocation {
        TextLocation(
            position: TextPosition(line: line, column: column),
            utf16Column: utf16Column,
            utf16Offset: offset
        )
    }

    private func assertGoToError<T>(
        _ expected: TextGoToError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> T
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? TextGoToError, expected, file: file, line: line)
        }
    }

    private func limits(
        navigation: TextNavigationLimits = .default,
        maximumDifferences: Int = 100,
        maximumBookmarks: Int = 100,
        maximumGraphemeClusterUTF16Length: Int = 100,
        maximumWork: Int = 100_000
    ) -> TextGoToLimits {
        TextGoToLimits(
            navigation: navigation,
            maximumDifferences: maximumDifferences,
            maximumBookmarks: maximumBookmarks,
            maximumGraphemeClusterUTF16Length: maximumGraphemeClusterUTF16Length,
            maximumWork: maximumWork
        )
    }

    private func navigationLimits(
        maximumInputUTF16Length: Int = 100_000,
        maximumLineCount: Int = 100_000,
        maximumLineUTF16Length: Int = 100_000,
        maximumTokenCount: Int = 100_000,
        maximumSymbolCount: Int = 100_000,
        maximumSymbolNameUTF16Length: Int = 100,
        maximumLookupResults: Int = 100
    ) -> TextNavigationLimits {
        TextNavigationLimits(
            maximumInputUTF16Length: maximumInputUTF16Length,
            maximumLineCount: maximumLineCount,
            maximumLineUTF16Length: maximumLineUTF16Length,
            maximumTokenCount: maximumTokenCount,
            maximumSymbolCount: maximumSymbolCount,
            maximumSymbolNameUTF16Length: maximumSymbolNameUTF16Length,
            maximumLookupResults: maximumLookupResults
        )
    }
}

private enum TextGoToCancellationOutcome: Equatable {
    case pending
    case succeeded
    case cancelled
    case failed(String)
}

private final class TextGoToCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let completed = DispatchSemaphore(value: 0)
    private var didStart = false
    private var outcome = TextGoToCancellationOutcome.pending

    func recordStart() {
        lock.lock()
        didStart = true
        lock.unlock()
        started.signal()
    }

    func recordCompletion(_ outcome: TextGoToCancellationOutcome) {
        lock.lock()
        self.outcome = outcome
        lock.unlock()
        completed.signal()
    }

    func cancelIfRunning(_ cancel: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard didStart, outcome == .pending else { return false }
        cancel()
        return true
    }

    func waitUntilStarted(timeout: TimeInterval) async -> Bool {
        await waitForTextGoToSemaphore(started, timeout: timeout)
    }

    func waitUntilCompleted(timeout: TimeInterval) async -> Bool {
        await waitForTextGoToSemaphore(completed, timeout: timeout)
    }

    func load() -> TextGoToCancellationOutcome {
        lock.lock()
        let outcome = outcome
        lock.unlock()
        return outcome
    }
}

private func waitForTextGoToSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: TimeInterval
) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(
                returning: semaphore.wait(timeout: .now() + timeout) == .success
            )
        }
    }
}
