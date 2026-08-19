import Foundation
import XCTest

@testable import MacMergeCore

final class LineEndingConversionTests: XCTestCase {
    func testWholeDocumentConversionHandlesEveryMixedTerminator() {
        let source = "alpha\r\nbeta\ngamma\rdelta\r\n"
        let cases: [(LineEnding, String, Int)] = [
            (.crlf, "alpha\r\nbeta\r\ngamma\r\ndelta\r\n", 2),
            (.lf, "alpha\nbeta\ngamma\ndelta\n", 3),
            (.cr, "alpha\rbeta\rgamma\rdelta\r", 3)
        ]

        for (lineEnding, expected, expectedChanges) in cases {
            let result = LineEndingConversion.convert(source, to: lineEnding)

            XCTAssertEqual(result.text, expected, lineEnding.displayName)
            XCTAssertEqual(result.lineCount, 4, lineEnding.displayName)
            XCTAssertEqual(result.changedTerminatorCount, expectedChanges, lineEnding.displayName)
            XCTAssertTrue(result.changed, lineEnding.displayName)
        }
    }

    func testSelectedConversionPreservesNonselectedTerminatorsAndUnterminatedFinalLine() throws {
        let source = "zero\r\none\ntwo\rthree\r\nfour"

        let result = try LineEndingConversion.convert(source, lines: 1..<4, to: .crlf)

        XCTAssertEqual(result.text, "zero\r\none\r\ntwo\r\nthree\r\nfour")
        XCTAssertEqual(result.lineCount, 5)
        XCTAssertEqual(result.changedTerminatorCount, 2)
        XCTAssertTrue(result.changed)
    }

    func testSelectedConversionPreservesDifferentTerminatorAtInteriorUpperBound() throws {
        let source = "zero\r\none\ntwo\rthree"

        let result = try LineEndingConversion.convert(source, lines: 1..<2, to: .crlf)

        XCTAssertEqual(result.text, "zero\r\none\r\ntwo\rthree")
        XCTAssertEqual(result.lineCount, 4)
        XCTAssertEqual(result.changedTerminatorCount, 1)
    }

    func testSelectingFinalUnterminatedLinePreservesPrecedingTerminator() throws {
        let source = "one\r\ntwo"

        let result = try LineEndingConversion.convert(source, lines: 1..<2, to: .lf)

        XCTAssertEqual(result.text, source)
        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(result.changedTerminatorCount, 0)
        XCTAssertFalse(result.changed)
    }

    func testCRLFIsAtomicForLineCountingAndSelection() throws {
        let source = "first\r\nsecond\rthird\n"

        XCTAssertEqual(LineEndingConversion.lineCount(in: source), 3)
        let result = try LineEndingConversion.convert(source, lines: 1..<2, to: .lf)

        XCTAssertEqual(result.text, "first\r\nsecond\nthird\n")
        XCTAssertEqual(result.lineCount, 3)
        XCTAssertEqual(result.changedTerminatorCount, 1)
    }

    func testConversionPreservesPresenceOrAbsenceOfFinalNewline() {
        let terminated = LineEndingConversion.convert("one\rtwo\n", to: .crlf)
        let unterminated = LineEndingConversion.convert("one\rtwo", to: .crlf)

        XCTAssertEqual(terminated.text, "one\r\ntwo\r\n")
        XCTAssertEqual(terminated.lineCount, 2)
        XCTAssertTrue(terminated.text.hasSuffix(LineEnding.crlf.rawValue))
        XCTAssertEqual(unterminated.text, "one\r\ntwo")
        XCTAssertEqual(unterminated.lineCount, 2)
        XCTAssertFalse(unterminated.text.hasSuffix(LineEnding.crlf.rawValue))
    }

    func testEmptyAndUnterminatedSingleLineHaveNoTerminatorsToConvert() throws {
        let empty = LineEndingConversion.convert("", to: .crlf)
        let single = LineEndingConversion.convert("single", to: .crlf)
        let selectedSingle = try LineEndingConversion.convert("single", lines: 0..<1, to: .cr)

        XCTAssertEqual(empty, LineEndingConversionResult(text: "", lineCount: 0, changedTerminatorCount: 0))
        XCTAssertFalse(empty.changed)
        XCTAssertEqual(
            single,
            LineEndingConversionResult(
                text: "single",
                lineCount: 1,
                changedTerminatorCount: 0
            ))
        XCTAssertFalse(single.changed)
        XCTAssertEqual(
            selectedSingle,
            LineEndingConversionResult(
                text: "single",
                lineCount: 1,
                changedTerminatorCount: 0
            ))
    }

    func testSingleTerminatedLineConvertsWithoutCreatingAnotherLine() throws {
        let result = try LineEndingConversion.convert("\r\n", lines: 0..<1, to: .lf)

        XCTAssertEqual(result.text, "\n")
        XCTAssertEqual(result.lineCount, 1)
        XCTAssertEqual(result.changedTerminatorCount, 1)
    }

    func testEmptySelectionAtDocumentEndIsValidAndDoesNothing() throws {
        let source = "one\r\ntwo"

        let result = try LineEndingConversion.convert(source, lines: 2..<2, to: .lf)

        XCTAssertEqual(result.text, source)
        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(result.changedTerminatorCount, 0)
        XCTAssertFalse(result.changed)
    }

    func testInvalidAndIntMaxRangesReportRequestedRangeAndLineCount() {
        let source = "one\r\ntwo"
        let ranges = [
            -1..<0,
            0..<3,
            Int.max..<Int.max,
            0..<Int.max
        ]

        for range in ranges {
            XCTAssertThrowsError(try LineEndingConversion.convert(source, lines: range, to: .lf)) { error in
                XCTAssertEqual(
                    error as? LineEndingConversionError,
                    .invalidLineRange(requested: range, lineCount: 2)
                )
            }
        }
    }

    func testDocumentNoOpConversionKeepsCleanPersistedStateAndMetadata() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("alpha\nbeta\n".utf8)
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url)

        let result = document.convertLineEndings(to: .lf)

        XCTAssertFalse(result.changed)
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertTrue(document.hasByteOrderMark)
        XCTAssertEqual(document.persistedText, "alpha\nbeta\n")
        XCTAssertEqual(document.persistedData, original)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDocumentNoOpWhileDirtyAndConversionRestoringPersistedText() throws {
        let originalText = "alpha\r\nbeta\r\n"
        let original = Data(originalText.utf8)
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url)

        XCTAssertTrue(document.convertLineEndings(to: .lf).changed)
        XCTAssertTrue(document.isDirty)

        let noOp = document.convertLineEndings(to: .lf)

        XCTAssertFalse(noOp.changed)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.text, "alpha\nbeta\n")
        XCTAssertEqual(document.persistedText, originalText)
        XCTAssertEqual(document.persistedData, original)

        let restored = document.convertLineEndings(to: .crlf)

        XCTAssertTrue(restored.changed)
        XCTAssertEqual(restored.changedTerminatorCount, 2)
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(document.text, originalText)
        XCTAssertEqual(document.persistedText, originalText)
        XCTAssertEqual(document.persistedData, original)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDocumentConversionAndSavePreserveBOMlessUTF8AndUTF16Bytes() throws {
        let originalText = "alpha\r\nβ\n"
        let convertedText = "alpha\nβ\n"
        let cases: [(TextFileEncoding, String.Encoding)] = [
            (.utf8, .utf8),
            (.utf16LittleEndian, .utf16LittleEndian)
        ]

        for (encoding, stringEncoding) in cases {
            let original = try XCTUnwrap(originalText.data(using: stringEncoding))
            let expected = try XCTUnwrap(convertedText.data(using: stringEncoding))
            let url = try temporaryFile(data: original)
            var document =
                encoding == .utf8
                ? try TextFileDocumentIO.load(from: url)
                : try TextFileDocumentIO.load(from: url, assuming: encoding)

            let conversion = document.convertLineEndings(to: .lf)
            let saved = try TextFileDocumentIO.save(document).document
            let reloaded =
                encoding == .utf8
                ? try TextFileDocumentIO.load(from: url)
                : try TextFileDocumentIO.load(from: url, assuming: encoding)

            XCTAssertEqual(conversion.changedTerminatorCount, 1, encoding.displayName)
            XCTAssertEqual(saved.text, convertedText, encoding.displayName)
            XCTAssertEqual(saved.encoding, encoding, encoding.displayName)
            XCTAssertFalse(saved.hasByteOrderMark, encoding.displayName)
            XCTAssertFalse(saved.isDirty, encoding.displayName)
            XCTAssertEqual(saved.persistedData, expected, encoding.displayName)
            XCTAssertEqual(try Data(contentsOf: url), expected, encoding.displayName)
            XCTAssertEqual(reloaded, saved, encoding.displayName)
        }
    }

    func testDocumentConversionAndSavePreserveUTF16BigEndianBytesAndReload() throws {
        let originalText = "alpha\r\nβ\n"
        let convertedText = "alpha\rβ\r"
        let original =
            Data([0xFE, 0xFF])
            + (try XCTUnwrap(originalText.data(using: .utf16BigEndian)))
        let expected =
            Data([0xFE, 0xFF])
            + (try XCTUnwrap(convertedText.data(using: .utf16BigEndian)))
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url)

        let conversion = document.convertLineEndings(to: .cr)
        let saved = try TextFileDocumentIO.save(document).document
        let reloaded = try TextFileDocumentIO.load(from: url)

        XCTAssertEqual(conversion.changedTerminatorCount, 2)
        XCTAssertEqual(saved.text, convertedText)
        XCTAssertEqual(saved.encoding, .utf16BigEndian)
        XCTAssertTrue(saved.hasByteOrderMark)
        XCTAssertFalse(saved.isDirty)
        XCTAssertEqual(saved.persistedData, expected)
        XCTAssertEqual(try Data(contentsOf: url), expected)
        XCTAssertEqual(reloaded, saved)
    }

    func testDocumentConversionAndSavePreserveUTF16EncodingAndBOM() throws {
        let originalText = "alpha\r\nbeta\ngamma"
        let convertedText = "alpha\rbeta\rgamma"
        let original =
            Data([0xFF, 0xFE])
            + (try XCTUnwrap(originalText.data(using: .utf16LittleEndian)))
        let expected =
            Data([0xFF, 0xFE])
            + (try XCTUnwrap(convertedText.data(using: .utf16LittleEndian)))
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url)

        let conversion = document.convertLineEndings(to: .cr)

        XCTAssertEqual(conversion.text, convertedText)
        XCTAssertEqual(conversion.changedTerminatorCount, 2)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.encoding, .utf16LittleEndian)
        XCTAssertTrue(document.hasByteOrderMark)
        XCTAssertEqual(document.persistedText, originalText)
        XCTAssertEqual(document.persistedData, original)
        XCTAssertEqual(try Data(contentsOf: url), original)

        let saved = try TextFileDocumentIO.save(document).document

        XCTAssertEqual(saved.text, convertedText)
        XCTAssertEqual(saved.persistedText, convertedText)
        XCTAssertEqual(saved.encoding, .utf16LittleEndian)
        XCTAssertTrue(saved.hasByteOrderMark)
        XCTAssertFalse(saved.isDirty)
        XCTAssertEqual(saved.persistedData, expected)
        XCTAssertEqual(try Data(contentsOf: url), expected)
    }

    func testInvalidDocumentSelectionLeavesTextAndCleanStateUnchanged() throws {
        let original = Data("alpha\r\nbeta".utf8)
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url)

        XCTAssertThrowsError(try document.convertLineEndings(in: 0..<Int.max, to: .lf)) { error in
            XCTAssertEqual(
                error as? LineEndingConversionError,
                .invalidLineRange(requested: 0..<Int.max, lineCount: 2)
            )
        }
        XCTAssertEqual(document.text, "alpha\r\nbeta")
        XCTAssertEqual(document.persistedText, "alpha\r\nbeta")
        XCTAssertEqual(document.persistedData, original)
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertFalse(document.hasByteOrderMark)
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSelectedDocumentConversionSavesOnlySelectedTerminators() throws {
        let original = Data("zero\r\none\ntwo\rthree\r\nfour".utf8)
        let expected = Data("zero\r\none\r\ntwo\r\nthree\r\nfour".utf8)
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url)

        let conversion = try document.convertLineEndings(in: 1..<3, to: .crlf)

        XCTAssertEqual(conversion.text, String(decoding: expected, as: UTF8.self))
        XCTAssertEqual(conversion.changedTerminatorCount, 2)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.persistedData, original)
        XCTAssertEqual(try Data(contentsOf: url), original)

        let saved = try TextFileDocumentIO.save(document).document

        XCTAssertEqual(saved.text, String(decoding: expected, as: UTF8.self))
        XCTAssertEqual(saved.persistedText, saved.text)
        XCTAssertEqual(saved.persistedData, expected)
        XCTAssertFalse(saved.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), expected)
    }

    private func temporaryFile(data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "fixture.txt")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}
