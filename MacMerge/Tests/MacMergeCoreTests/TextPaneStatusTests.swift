import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class TextPaneStatusTests: XCTestCase {
    func testInputFingerprintAndStatusEqualityRetainSourceIdentity() throws {
        let original = input(
            text: "A\u{1F600}",
            revision: 7,
            caret: 1,
            selection: NSRange(location: 1, length: 2)
        )
        let copy = original
        let independent = input(
            text: String(original.text),
            revision: 7,
            caret: 1,
            selection: NSRange(location: 1, length: 2)
        )

        XCTAssertEqual(original, copy)
        XCTAssertNotEqual(original, independent)

        let originalFingerprint = try TextPaneStatus.snapshotFingerprint(for: original)
        let repeatedFingerprint = try TextPaneStatus.snapshotFingerprint(for: original)
        let independentFingerprint = try TextPaneStatus.snapshotFingerprint(for: independent)
        XCTAssertEqual(originalFingerprint, repeatedFingerprint)
        XCTAssertNotEqual(originalFingerprint, independentFingerprint)
        XCTAssertEqual(originalFingerprint.textUTF16Length, independentFingerprint.textUTF16Length)
        XCTAssertEqual(originalFingerprint.textDigestLow, independentFingerprint.textDigestLow)
        XCTAssertEqual(originalFingerprint.textDigestHigh, independentFingerprint.textDigestHigh)

        let first = try TextPaneStatus(input: original)
        let second = try TextPaneStatus(input: original)
        let third = try TextPaneStatus(input: independent)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertEqual(first.sourceSnapshotFingerprint, originalFingerprint)
        requireSendable(first)
        requireSendable(originalFingerprint)
    }

    func testFreshnessUsesExactUTF16InsteadOfCanonicalStringEquality() throws {
        let precomposed = input(text: "\u{00E9}", revision: 11, caret: 0)
        let decomposed = input(text: "e\u{0301}", revision: 11, caret: 0)
        let independentExact = input(text: String(precomposed.text), revision: 11, caret: 0)
        let status = try TextPaneStatus(input: precomposed)

        XCTAssertEqual(precomposed.text, decomposed.text)
        XCTAssertEqual(precomposed.text.utf16.count, 1)
        XCTAssertEqual(decomposed.text.utf16.count, 2)
        XCTAssertTrue(try status.isCurrent(input: precomposed))
        XCTAssertTrue(try status.isCurrent(input: independentExact))
        XCTAssertFalse(try status.isCurrent(input: decomposed))
        XCTAssertNoThrow(try status.validateCurrent(input: independentExact))
        assertStatusError(.staleSnapshot) {
            try status.validateCurrent(input: decomposed)
        }

        let exactFingerprint = try TextPaneStatus.snapshotFingerprint(for: independentExact)
        let canonicalFingerprint = try TextPaneStatus.snapshotFingerprint(for: decomposed)
        XCTAssertNotEqual(status.sourceSnapshotFingerprint, exactFingerprint)
        XCTAssertNoThrow(try status.validateCurrent(snapshotFingerprint: exactFingerprint))
        assertStatusError(.staleSnapshot) {
            try status.validateCurrent(snapshotFingerprint: canonicalFingerprint)
        }
    }

    func testFreshnessRejectsEveryMetadataChangeAndReportsRevisionFirst() throws {
        let original = input(
            text: "ab",
            revision: 19,
            caret: 1,
            selection: NSRange(location: 0, length: 1)
        )
        let status = try TextPaneStatus(input: original)
        let staleInputs = [
            input(text: "ac", revision: 19, caret: 1, selection: NSRange(location: 0, length: 1)),
            input(text: "ab", revision: 19, caret: 0, selection: NSRange(location: 0, length: 1)),
            input(text: "ab", revision: 19, caret: 1, selection: NSRange(location: 1, length: 1)),
            input(
                text: "ab",
                revision: 19,
                caret: 1,
                selection: NSRange(location: 0, length: 1),
                encoding: .windows1252
            ),
            input(
                text: "ab",
                revision: 19,
                caret: 1,
                selection: NSRange(location: 0, length: 1),
                hasByteOrderMark: true
            ),
            input(
                text: "ab",
                revision: 19,
                caret: 1,
                selection: NSRange(location: 0, length: 1),
                isReadOnly: true
            ),
            input(
                text: "ab",
                revision: 19,
                caret: 1,
                selection: NSRange(location: 0, length: 1),
                isDirty: true
            ),
            input(
                text: "ab",
                revision: 19,
                caret: 1,
                selection: NSRange(location: 0, length: 1),
                tabWidth: 8
            )
        ]

        for stale in staleInputs {
            XCTAssertFalse(try status.isCurrent(input: stale))
            assertStatusError(.staleSnapshot) {
                try status.validateCurrent(input: stale)
            }
        }

        let changedLimits = limits(maximumWorkUnits: 100)
        XCTAssertFalse(try status.isCurrent(input: original, limits: changedLimits))
        assertStatusError(.staleSnapshot) {
            try status.validateCurrent(input: original, limits: changedLimits)
        }

        let changedRevision = input(text: "ab", revision: 20, caret: 1, tabWidth: 0)
        XCTAssertFalse(try status.isCurrent(input: changedRevision))
        assertStatusError(.staleRevision(expected: 19, actual: 20)) {
            try status.validateCurrent(input: changedRevision)
        }
        XCTAssertTrue(status.hasSourceRevision(19))
        XCTAssertFalse(status.hasSourceRevision(20))
        XCTAssertNoThrow(try status.validateSourceRevision(19))
        assertStatusError(.staleRevision(expected: 19, actual: 20)) {
            try status.validateSourceRevision(20)
        }
    }

    func testNilSelectionNormalizesToCaretForStatusFingerprintAndFreshness() throws {
        let implicit = input(text: "abc", revision: 23, caret: 2)
        let explicit = input(
            text: "abc",
            revision: 23,
            caret: 2,
            selection: NSRange(location: 2, length: 0)
        )
        let status = try TextPaneStatus(input: implicit)
        let explicitFingerprint = try TextPaneStatus.snapshotFingerprint(for: explicit)

        XCTAssertNil(implicit.selectionUTF16Range)
        XCTAssertEqual(status.selectionUTF16Range, NSRange(location: 2, length: 0))
        XCTAssertEqual(
            status.sourceSnapshotFingerprint.selectionUTF16Range,
            NSRange(location: 2, length: 0)
        )
        XCTAssertTrue(status.selection.isEmpty)
        XCTAssertEqual(status.selectedGraphemeCount, 0)
        XCTAssertEqual(status.selectedUnicodeScalarCount, 0)
        XCTAssertEqual(status.selectedUTF16Count, 0)
        XCTAssertEqual(status.selectedLineCount, 0)
        XCTAssertTrue(try status.isCurrent(input: explicit))
        XCTAssertNoThrow(try status.validateCurrent(snapshotFingerprint: explicitFingerprint))
    }

    func testDocumentDirtyStateUsesLogicalORWithCallerState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextPaneStatusTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let cleanDocument = try TextFileDocumentIO.create(at: url, text: "clean")
        var dirtyDocument = cleanDocument
        dirtyDocument.text += " edit"

        let cleanInput = TextPaneStatusInput(
            document: cleanDocument,
            revision: 1,
            caretUTF16Offset: 0,
            isReadOnly: false,
            isDirty: false
        )
        let callerDirtyInput = TextPaneStatusInput(
            document: cleanDocument,
            revision: 1,
            caretUTF16Offset: 0,
            isReadOnly: false,
            isDirty: true
        )
        let documentDirtyInput = TextPaneStatusInput(
            document: dirtyDocument,
            revision: 1,
            caretUTF16Offset: 0,
            isReadOnly: false,
            isDirty: false
        )
        let bothDirtyInput = TextPaneStatusInput(
            document: dirtyDocument,
            revision: 1,
            caretUTF16Offset: 0,
            isReadOnly: false,
            isDirty: true
        )

        XCTAssertFalse(cleanDocument.isDirty)
        XCTAssertTrue(dirtyDocument.isDirty)
        XCTAssertFalse(cleanInput.isDirty)
        XCTAssertTrue(callerDirtyInput.isDirty)
        XCTAssertTrue(documentDirtyInput.isDirty)
        XCTAssertTrue(bothDirtyInput.isDirty)
        XCTAssertFalse(try TextPaneStatus(input: cleanInput).isDirty)
        XCTAssertTrue(try TextPaneStatus(input: callerDirtyInput).isDirty)
        XCTAssertTrue(try TextPaneStatus(input: documentDirtyInput).isDirty)
        XCTAssertTrue(
            try TextPaneStatus(
                document: dirtyDocument,
                revision: 1,
                caretUTF16Offset: 0,
                isReadOnly: false,
                isDirty: false
            ).isDirty
        )
        XCTAssertTrue(
            try TextPaneStatus(
                document: cleanDocument,
                revision: 1,
                caretUTF16Offset: 0,
                isReadOnly: false,
                isDirty: true
            ).isDirty
        )
    }

    func testCallerDirtyDocumentInitializersShortCircuitDocumentDirtyComparison() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MacMergeCore/TextPaneStatus.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let compactSource = source.filter { !$0.isWhitespace }
        XCTAssertEqual(
            compactSource.components(separatedBy: "isDirty:isDirty||document.isDirty").count - 1,
            1,
            "Caller dirty state must short-circuit the linear document comparison"
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextPaneStatusTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(repeating: "x", count: 1_000_001)
        let cleanDocument = try TextFileDocumentIO.create(at: url, text: text)
        var lastScalarDirtyDocument = cleanDocument
        lastScalarDirtyDocument.text.removeLast()
        lastScalarDirtyDocument.text.append("y")

        XCTAssertFalse(cleanDocument.isDirty)
        XCTAssertTrue(lastScalarDirtyDocument.isDirty)
        for document in [cleanDocument, lastScalarDirtyDocument] {
            XCTAssertTrue(
                TextPaneStatusInput(
                    document: document,
                    revision: 1,
                    caretUTF16Offset: 0,
                    isReadOnly: false,
                    isDirty: true
                ).isDirty
            )
        }
    }

    func testPositionSelectionGraphemeScalarAndAccessibilityLabelsAreExact() throws {
        let text = "A\t\u{1F600}e\u{0301} \r\nZ"
        let status = try TextPaneStatus(
            input: input(
                text: text,
                revision: 31,
                caret: 4,
                selection: NSRange(location: 2, length: 8),
                encoding: .utf16LittleEndian,
                hasByteOrderMark: true,
                isReadOnly: true,
                isDirty: true
            )
        )

        XCTAssertEqual(status.sourceRevision, 31)
        XCTAssertEqual(status.textUTF16Length, 10)
        XCTAssertEqual(status.lineCount, 2)
        XCTAssertEqual(
            status.position,
            TextPanePositionStatus(
                line: 1,
                logicalColumn: 4,
                visualColumn: 6,
                utf16Column: 5,
                utf16Offset: 4
            )
        )
        XCTAssertEqual(status.line, 1)
        XCTAssertEqual(status.logicalColumn, 4)
        XCTAssertEqual(status.visualColumn, 6)
        XCTAssertEqual(status.utf16Column, 5)
        XCTAssertEqual(status.caretUTF16Offset, 4)

        let character = try XCTUnwrap(status.currentCharacter)
        XCTAssertEqual(character.character, "e\u{0301}")
        XCTAssertEqual(character.displayName, "e\u{0301}")
        XCTAssertEqual(character.unicodeScalarCount, 2)
        XCTAssertEqual(character.utf16Count, 2)
        XCTAssertFalse(character.areScalarsTruncated)
        XCTAssertEqual(
            character.scalars,
            [
                TextPaneUnicodeScalarStatus(
                    value: 0x0065,
                    codePoint: "U+0065",
                    name: "LATIN SMALL LETTER E",
                    accessibilityLabel: "U+0065, LATIN SMALL LETTER E"
                ),
                TextPaneUnicodeScalarStatus(
                    value: 0x0301,
                    codePoint: "U+0301",
                    name: "COMBINING ACUTE ACCENT",
                    accessibilityLabel: "U+0301, COMBINING ACUTE ACCENT"
                )
            ]
        )
        XCTAssertEqual(
            character.accessibilityLabel,
            "Character e\u{0301}; U+0065, LATIN SMALL LETTER E, U+0301, COMBINING ACUTE ACCENT"
        )

        XCTAssertEqual(
            status.selection,
            TextPaneSelectionStatus(
                utf16Range: NSRange(location: 2, length: 8),
                graphemeCount: 5,
                unicodeScalarCount: 7,
                utf16Count: 8,
                lineCount: 2
            )
        )
        XCTAssertEqual(status.selectionUTF16Range, NSRange(location: 2, length: 8))
        XCTAssertEqual(status.selectedGraphemeCount, 5)
        XCTAssertEqual(status.selectedUnicodeScalarCount, 7)
        XCTAssertEqual(status.selectedUTF16Count, 8)
        XCTAssertEqual(status.selectedLineCount, 2)
        XCTAssertEqual(status.encoding, .utf16LittleEndian)
        XCTAssertEqual(status.encodingDisplayName, "UTF-16 LE BOM")
        XCTAssertTrue(status.hasByteOrderMark)
        XCTAssertTrue(status.isReadOnly)
        XCTAssertTrue(status.isDirty)
        XCTAssertEqual(status.tabWidth, 4)
        XCTAssertEqual(
            status.lineEndings,
            TextPaneLineEndingSummary(
                crlfCount: 1,
                lfCount: 0,
                crCount: 0,
                dominant: .crlf,
                isMixed: false
            )
        )
        XCTAssertEqual(status.dominantLineEnding, .crlf)
        XCTAssertFalse(status.hasMixedLineEndings)

        let combinedLabel = [
            "Line 1, logical column 4, visual column 6",
            "Character e\u{0301}; U+0065, LATIN SMALL LETTER E, U+0301, COMBINING ACUTE ACCENT",
            "5 graphemes, 7 Unicode scalars, 8 UTF-16 units selected across 2 lines",
            "Encoding: UTF-16 LE, with byte-order mark",
            "Line endings: CRLF, 1 total",
            "Read only, modified"
        ].joined(separator: ". ")
        let labels = TextPaneStatusLabels(
            position: "Line 1, logical column 4, visual column 6",
            character: "Character e\u{0301}; U+0065, LATIN SMALL LETTER E, U+0301, COMBINING ACUTE ACCENT",
            selection: "5 graphemes, 7 Unicode scalars, 8 UTF-16 units selected across 2 lines",
            encoding: "Encoding: UTF-16 LE, with byte-order mark",
            lineEndings: "Line endings: CRLF, 1 total",
            documentState: "Read only, modified",
            combined: combinedLabel
        )
        XCTAssertEqual(status.accessibilityLabels, labels)
    }

    func testCharacterStatusesCoverControlsSpaceSupplementaryAndUnnamedScalars() throws {
        let fixtures: [(String, String, Int, Int, [String])] = [
            ("\t", "Tab", 1, 1, ["U+0009"]),
            ("\r\n", "Carriage return and line feed", 2, 2, ["U+000D", "U+000A"]),
            ("\n", "Line feed", 1, 1, ["U+000A"]),
            ("\r", "Carriage return", 1, 1, ["U+000D"]),
            (" ", "Space", 1, 1, ["U+0020"]),
            ("e\u{0301}", "e\u{0301}", 2, 2, ["U+0065", "U+0301"]),
            ("\u{1F600}", "\u{1F600}", 1, 2, ["U+1F600"])
        ]

        for (text, displayName, scalarCount, utf16Count, codePoints) in fixtures {
            let character = try XCTUnwrap(
                try TextPaneStatus(input: input(text: text, revision: 1, caret: 0))
                    .currentCharacter
            )
            XCTAssertEqual(character.character, text, displayName)
            XCTAssertEqual(character.displayName, displayName, displayName)
            XCTAssertEqual(character.unicodeScalarCount, scalarCount, displayName)
            XCTAssertEqual(character.utf16Count, utf16Count, displayName)
            XCTAssertEqual(character.scalars.map(\.codePoint), codePoints, displayName)
        }

        let tab = try XCTUnwrap(
            try TextPaneStatus(input: input(text: "\t", revision: 1, caret: 0))
                .currentCharacter
        )
        XCTAssertEqual(tab.scalars.first?.name, "CHARACTER TABULATION")
        XCTAssertEqual(
            tab.accessibilityLabel,
            "Character Tab; U+0009, CHARACTER TABULATION"
        )

        let noncharacter = String(try XCTUnwrap(Unicode.Scalar(0xFDD0)))
        let unnamed = try XCTUnwrap(
            try TextPaneStatus(input: input(text: noncharacter, revision: 1, caret: 0))
                .currentCharacter
        )
        XCTAssertNil(unnamed.scalars.first?.name)
        XCTAssertEqual(unnamed.unicodeScalarCount, 1)
        XCTAssertEqual(unnamed.scalars.first?.accessibilityLabel, "U+FDD0, unnamed Unicode scalar")

        let eof = try TextPaneStatus(input: input(text: "x", revision: 1, caret: 1))
        XCTAssertNil(eof.currentCharacter)
        XCTAssertEqual(eof.accessibilityLabels.character, "No character at insertion point")
    }

    func testCRLFLFCRAndUnicodeSeparatorsHaveDistinctLineSemantics() throws {
        let text = "a\r\nb\nc\rd\u{2028}e\u{2029}f"
        let status = try TextPaneStatus(
            input: input(
                text: text,
                revision: 41,
                caret: 8,
                selection: NSRange(location: 8, length: 3)
            )
        )

        XCTAssertEqual(status.textUTF16Length, 12)
        XCTAssertEqual(status.lineCount, 4)
        XCTAssertEqual(
            status.position,
            TextPanePositionStatus(
                line: 4,
                logicalColumn: 2,
                visualColumn: 2,
                utf16Column: 2,
                utf16Offset: 8
            )
        )
        XCTAssertEqual(
            status.selection,
            TextPaneSelectionStatus(
                utf16Range: NSRange(location: 8, length: 3),
                graphemeCount: 3,
                unicodeScalarCount: 3,
                utf16Count: 3,
                lineCount: 1
            )
        )
        XCTAssertEqual(status.lineEndings.crlfCount, 1)
        XCTAssertEqual(status.lineEndings.lfCount, 1)
        XCTAssertEqual(status.lineEndings.crCount, 1)
        XCTAssertEqual(status.lineEndings.totalCount, 3)
        XCTAssertEqual(status.lineEndings.dominant, .crlf)
        XCTAssertTrue(status.lineEndings.isMixed)
        XCTAssertEqual(status.lineEndings.displayName, "Mixed (CRLF dominant)")
        XCTAssertEqual(
            status.lineEndings.accessibilityLabel,
            "Mixed line endings, CRLF dominant; 1 CRLF, 1 LF, 1 CR"
        )
        XCTAssertEqual(status.accessibilityLabels.lineEndings, status.lineEndings.accessibilityLabel)

        let lineSeparator = try XCTUnwrap(status.currentCharacter)
        XCTAssertEqual(lineSeparator.character, "\u{2028}")
        XCTAssertEqual(lineSeparator.scalars.first?.codePoint, "U+2028")
        XCTAssertEqual(lineSeparator.scalars.first?.name, "LINE SEPARATOR")

        let paragraphSeparator = try XCTUnwrap(
            try TextPaneStatus(input: input(text: text, revision: 41, caret: 10))
                .currentCharacter
        )
        XCTAssertEqual(paragraphSeparator.character, "\u{2029}")
        XCTAssertEqual(paragraphSeparator.scalars.first?.name, "PARAGRAPH SEPARATOR")
    }

    func testSelectionsEndingExactlyAfterEveryTerminatorCountOnlyTouchedLines() throws {
        let text = "a\r\nb\nc\rd"
        let fixtures: [(String, NSRange, Int, Int, Int, Int)] = [
            ("CRLF only", NSRange(location: 1, length: 2), 1, 2, 2, 1),
            ("through CRLF", NSRange(location: 0, length: 3), 2, 3, 3, 1),
            ("LF only", NSRange(location: 4, length: 1), 1, 1, 1, 1),
            ("through LF", NSRange(location: 3, length: 2), 2, 2, 2, 1),
            ("CR only", NSRange(location: 6, length: 1), 1, 1, 1, 1),
            ("through CR", NSRange(location: 5, length: 2), 2, 2, 2, 1)
        ]

        for (name, range, graphemes, scalars, utf16, lines) in fixtures {
            let status = try TextPaneStatus(
                input: input(text: text, revision: 1, caret: 0, selection: range)
            )
            XCTAssertEqual(status.selectionUTF16Range, range, name)
            XCTAssertEqual(status.selectedGraphemeCount, graphemes, name)
            XCTAssertEqual(status.selectedUnicodeScalarCount, scalars, name)
            XCTAssertEqual(status.selectedUTF16Count, utf16, name)
            XCTAssertEqual(status.selectedLineCount, lines, name)
        }
    }

    func testAccessibilityLabelsCoverSelectionAndDocumentStateBranches() throws {
        let fixtures:
            [(
                name: String,
                text: String,
                caret: Int,
                selection: NSRange?,
                readOnly: Bool,
                dirty: Bool,
                character: String,
                selectionLabel: String,
                lineEndings: String,
                documentState: String
            )] = [
                (
                    "empty editable clean",
                    "x",
                    1,
                    nil,
                    false,
                    false,
                    "No character at insertion point",
                    "No selection",
                    "No line endings",
                    "Editable, unmodified"
                ),
                (
                    "singular editable dirty",
                    "x",
                    0,
                    NSRange(location: 0, length: 1),
                    false,
                    true,
                    "Character x; U+0078, LATIN SMALL LETTER X",
                    "1 grapheme, 1 Unicode scalar, 1 UTF-16 unit selected across 1 line",
                    "No line endings",
                    "Editable, modified"
                ),
                (
                    "multi-scalar read-only clean",
                    "e\u{0301}",
                    0,
                    NSRange(location: 0, length: 2),
                    true,
                    false,
                    "Character e\u{0301}; U+0065, LATIN SMALL LETTER E, U+0301, COMBINING ACUTE ACCENT",
                    "1 grapheme, 2 Unicode scalars, 2 UTF-16 units selected across 1 line",
                    "No line endings",
                    "Read only, unmodified"
                ),
                (
                    "plural read-only dirty",
                    "a\nb",
                    0,
                    NSRange(location: 0, length: 3),
                    true,
                    true,
                    "Character a; U+0061, LATIN SMALL LETTER A",
                    "3 graphemes, 3 Unicode scalars, 3 UTF-16 units selected across 2 lines",
                    "Line endings: LF, 1 total",
                    "Read only, modified"
                )
            ]

        for fixture in fixtures {
            let status = try TextPaneStatus(
                input: input(
                    text: fixture.text,
                    revision: 1,
                    caret: fixture.caret,
                    selection: fixture.selection,
                    isReadOnly: fixture.readOnly,
                    isDirty: fixture.dirty
                )
            )
            let labels = status.accessibilityLabels
            XCTAssertEqual(labels.character, fixture.character, fixture.name)
            XCTAssertEqual(labels.selection, fixture.selectionLabel, fixture.name)
            XCTAssertEqual(labels.lineEndings, fixture.lineEndings, fixture.name)
            XCTAssertEqual(labels.documentState, fixture.documentState, fixture.name)
            XCTAssertEqual(
                labels.combined,
                [
                    labels.position,
                    fixture.character,
                    fixture.selectionLabel,
                    labels.encoding,
                    fixture.lineEndings,
                    fixture.documentState
                ].joined(separator: ". "),
                fixture.name
            )
        }
    }

    func testLineEndingSummaryHandlesNoneTrailingLinesTieOrderAndSaturation() throws {
        let empty = try TextPaneStatus(input: input(text: "", revision: 1, caret: 0))
        XCTAssertEqual(empty.lineCount, 1)
        XCTAssertEqual(empty.lineEndings.totalCount, 0)
        XCTAssertNil(empty.lineEndings.dominant)
        XCTAssertEqual(empty.lineEndings.displayName, "None")
        XCTAssertEqual(empty.lineEndings.accessibilityLabel, "No line endings")
        XCTAssertEqual(empty.accessibilityLabels.lineEndings, "No line endings")

        let trailing = try TextPaneStatus(input: input(text: "x\n", revision: 1, caret: 2))
        XCTAssertEqual(trailing.lineCount, 2)
        XCTAssertEqual(trailing.position.line, 2)
        XCTAssertNil(trailing.currentCharacter)

        let lfFirstTie = try TextPaneStatus(
            input: input(text: "a\nb\r\nc\r", revision: 1, caret: 0)
        )
        XCTAssertEqual(lfFirstTie.lineEndings.dominant, .lf)

        let saturated = TextPaneLineEndingSummary(
            crlfCount: .max,
            lfCount: 1,
            crCount: 1,
            dominant: .crlf,
            isMixed: true
        )
        XCTAssertEqual(saturated.totalCount, .max)
        XCTAssertEqual(saturated.displayName, "Mixed (CRLF dominant)")
        XCTAssertEqual(
            saturated.accessibilityLabel,
            "Mixed line endings, CRLF dominant; \(Int.max) CRLF, 1 LF, 1 CR"
        )
    }

    func testTabsUseConfiguredStopsAndSaturateAtIntMax() throws {
        let ordinary = try TextPaneStatus(
            input: input(text: "a\tb\t", revision: 1, caret: 4, tabWidth: 4)
        )
        XCTAssertEqual(ordinary.logicalColumn, 5)
        XCTAssertEqual(ordinary.visualColumn, 9)
        XCTAssertEqual(ordinary.utf16Column, 5)

        let afterFirstTab = try TextPaneStatus(
            input: input(text: "a\tb", revision: 1, caret: 2, tabWidth: 4)
        )
        XCTAssertEqual(afterFirstTab.logicalColumn, 3)
        XCTAssertEqual(afterFirstTab.visualColumn, 5)

        let saturated = try TextPaneStatus(
            input: input(text: "\t\t", revision: 1, caret: 2, tabWidth: .max)
        )
        XCTAssertEqual(saturated.logicalColumn, 3)
        XCTAssertEqual(saturated.visualColumn, .max)
        XCTAssertEqual(saturated.tabWidth, .max)
    }

    func testEncodingAndByteOrderMarkValidationCoversEveryEncoding() throws {
        let allEncodings: [TextFileEncoding] = [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .shiftJIS,
            .japaneseEUC,
            .iso2022JP,
            .windows1250,
            .windows1251,
            .windows1252,
            .windows1253,
            .windows1254,
            .windows1255
        ]
        XCTAssertEqual(Set(allEncodings.map(\.rawValue)).count, allEncodings.count)
        for encoding in allEncodings {
            _ = byteOrderMarkSupport(for: encoding)
            let status = try TextPaneStatus(
                input: input(text: "", revision: 1, caret: 0, encoding: encoding)
            )
            XCTAssertEqual(status.encoding, encoding)
            XCTAssertEqual(status.encodingDisplayName, encoding.displayName)
            XCTAssertEqual(
                status.accessibilityLabels.encoding,
                "Encoding: \(encoding.displayName), without byte-order mark"
            )
        }

        let bomEncodings = allEncodings.filter { byteOrderMarkSupport(for: $0) }
        for encoding in bomEncodings {
            let status = try TextPaneStatus(
                input: input(
                    text: "",
                    revision: 1,
                    caret: 0,
                    encoding: encoding,
                    hasByteOrderMark: true
                )
            )
            XCTAssertEqual(status.encodingDisplayName, "\(encoding.displayName) BOM")
            XCTAssertEqual(
                status.accessibilityLabels.encoding,
                "Encoding: \(encoding.displayName), with byte-order mark"
            )
        }

        for encoding in allEncodings where !byteOrderMarkSupport(for: encoding) {
            assertStatusError(.invalidByteOrderMark(encoding)) {
                try TextPaneStatus(
                    input: input(
                        text: "",
                        revision: 1,
                        caret: 0,
                        encoding: encoding,
                        hasByteOrderMark: true
                    )
                )
            }
        }
    }

    func testCaretAndSelectionValidationRejectsBoundsOverflowAndSplitGraphemes() {
        let text = "A\u{1F600}e\u{0301}\r\nZ"

        assertStatusError(.invalidCaretUTF16Offset(-1)) {
            try TextPaneStatus(input: input(text: text, revision: 1, caret: -1))
        }
        assertStatusError(.invalidCaretUTF16Offset(9)) {
            try TextPaneStatus(input: input(text: text, revision: 1, caret: 9))
        }
        for offset in [2, 4, 6] {
            assertStatusError(.utf16OffsetSplitsGrapheme(offset)) {
                try TextPaneStatus(input: input(text: text, revision: 1, caret: offset))
            }
        }

        let negativeLocation = NSRange(location: -1, length: 0)
        assertStatusError(.invalidSelectionUTF16Range(negativeLocation)) {
            try TextPaneStatus(
                input: input(text: text, revision: 1, caret: 0, selection: negativeLocation)
            )
        }
        let negativeLength = NSRange(location: 0, length: -1)
        assertStatusError(.invalidSelectionUTF16Range(negativeLength)) {
            try TextPaneStatus(
                input: input(text: text, revision: 1, caret: 0, selection: negativeLength)
            )
        }
        let overflow = NSRange(location: .max, length: 1)
        assertStatusError(.invalidSelectionUTF16Range(overflow)) {
            try TextPaneStatus(
                input: input(text: text, revision: 1, caret: 0, selection: overflow)
            )
        }
        let outOfBounds = NSRange(location: 8, length: 1)
        assertStatusError(.invalidSelectionUTF16Range(outOfBounds)) {
            try TextPaneStatus(
                input: input(text: text, revision: 1, caret: 0, selection: outOfBounds)
            )
        }
        let splitStart = NSRange(location: 2, length: 1)
        assertStatusError(.utf16OffsetSplitsGrapheme(2)) {
            try TextPaneStatus(
                input: input(text: text, revision: 1, caret: 0, selection: splitStart)
            )
        }
        let splitEnd = NSRange(location: 1, length: 1)
        assertStatusError(.utf16OffsetSplitsGrapheme(2)) {
            try TextPaneStatus(
                input: input(text: text, revision: 1, caret: 0, selection: splitEnd)
            )
        }
    }

    func testMalformedInputsFailConsistentlyThroughEveryInputAPI() throws {
        let text = "A\u{1F600}e\u{0301}\r\nZ"
        let status = try TextPaneStatus(input: input(text: text, revision: 1, caret: 0))
        let negativeLocation = NSRange(location: -1, length: 0)
        let negativeLength = NSRange(location: 0, length: -1)
        let overflow = NSRange(location: .max, length: 1)
        let outOfBounds = NSRange(location: 8, length: 1)
        let splitStart = NSRange(location: 2, length: 1)
        let splitEnd = NSRange(location: 1, length: 1)
        let fixtures: [(String, TextPaneStatusInput, TextPaneStatusError)] = [
            (
                "tab width",
                input(text: text, revision: 1, caret: 0, tabWidth: 0),
                .invalidTabWidth(0)
            ),
            (
                "negative caret",
                input(text: text, revision: 1, caret: -1),
                .invalidCaretUTF16Offset(-1)
            ),
            (
                "caret beyond end",
                input(text: text, revision: 1, caret: 9),
                .invalidCaretUTF16Offset(9)
            ),
            (
                "negative selection location",
                input(text: text, revision: 1, caret: 0, selection: negativeLocation),
                .invalidSelectionUTF16Range(negativeLocation)
            ),
            (
                "negative selection length",
                input(text: text, revision: 1, caret: 0, selection: negativeLength),
                .invalidSelectionUTF16Range(negativeLength)
            ),
            (
                "selection overflow",
                input(text: text, revision: 1, caret: 0, selection: overflow),
                .invalidSelectionUTF16Range(overflow)
            ),
            (
                "selection beyond end",
                input(text: text, revision: 1, caret: 0, selection: outOfBounds),
                .invalidSelectionUTF16Range(outOfBounds)
            ),
            (
                "split selection start",
                input(text: text, revision: 1, caret: 0, selection: splitStart),
                .utf16OffsetSplitsGrapheme(2)
            ),
            (
                "split selection end",
                input(text: text, revision: 1, caret: 0, selection: splitEnd),
                .utf16OffsetSplitsGrapheme(2)
            ),
            (
                "split caret",
                input(text: text, revision: 1, caret: 4),
                .utf16OffsetSplitsGrapheme(4)
            ),
            (
                "invalid byte-order mark",
                input(
                    text: text,
                    revision: 1,
                    caret: 0,
                    encoding: .windows1252,
                    hasByteOrderMark: true
                ),
                .invalidByteOrderMark(.windows1252)
            )
        ]

        for (name, malformed, expected) in fixtures {
            assertInputAPIsThrow(expected, name: name, input: malformed, status: status)
        }
    }

    func testLimitsValidateEveryFieldAndAcceptExactInputAndGraphemeBounds() throws {
        let invalidLimits = [
            limits(maximumInputUTF16Length: -1),
            limits(maximumWorkUnits: -1),
            limits(maximumGraphemeUTF16Length: 0),
            limits(maximumReportedScalarsPerGrapheme: -1),
            limits(cancellationCheckInterval: 0)
        ]
        for invalid in invalidLimits {
            assertStatusError(.invalidLimits) {
                try TextPaneStatus(input: input(text: "", revision: 1, caret: 0), limits: invalid)
            }
            assertStatusError(.invalidLimits) {
                try TextPaneStatus.snapshotFingerprint(
                    for: input(text: "", revision: 1, caret: 0),
                    limits: invalid
                )
            }
        }

        let exact = limits(
            maximumInputUTF16Length: 2,
            maximumWorkUnits: 4,
            maximumGraphemeUTF16Length: 2,
            maximumReportedScalarsPerGrapheme: 0,
            cancellationCheckInterval: 1
        )
        let exactStatus = try TextPaneStatus(
            input: input(text: "e\u{0301}", revision: 1, caret: 0),
            limits: exact
        )
        XCTAssertEqual(exactStatus.textUTF16Length, 2)
        XCTAssertTrue(try XCTUnwrap(exactStatus.currentCharacter).areScalarsTruncated)
        XCTAssertEqual(try XCTUnwrap(exactStatus.currentCharacter).scalars, [])

        assertStatusError(.inputTooLarge(maximumUTF16Length: 1)) {
            try TextPaneStatus(
                input: input(text: "\u{1F600}", revision: 1, caret: 0),
                limits: limits(maximumInputUTF16Length: 1)
            )
        }
        assertStatusError(.graphemeTooLarge(maximumUTF16Length: 1)) {
            try TextPaneStatus(
                input: input(text: "e\u{0301}", revision: 1, caret: 0),
                limits: limits(maximumGraphemeUTF16Length: 1)
            )
        }

        let zeroWork = limits(
            maximumInputUTF16Length: 0,
            maximumWorkUnits: 0,
            maximumGraphemeUTF16Length: 1
        )
        XCTAssertNoThrow(
            try TextPaneStatus(input: input(text: "", revision: 1, caret: 0), limits: zeroWork)
        )
        XCTAssertNoThrow(
            try TextPaneStatus.snapshotFingerprint(
                for: input(text: "", revision: 1, caret: 0),
                limits: zeroWork
            )
        )
    }

    func testCalculationFingerprintAndFreshnessChargeExactlyTwoUTF16Passes() throws {
        let text = "A\u{1F600}e\u{0301}"
        let utf16Length = text.utf16.count
        XCTAssertEqual(utf16Length, 5)
        let exact = limits(
            maximumInputUTF16Length: utf16Length,
            maximumWorkUnits: 2 * utf16Length,
            maximumGraphemeUTF16Length: 2
        )
        let insufficient = limits(
            maximumInputUTF16Length: utf16Length,
            maximumWorkUnits: 2 * utf16Length - 1,
            maximumGraphemeUTF16Length: 2
        )
        let original = input(text: text, revision: 51, caret: utf16Length)
        let independent = input(text: String(text), revision: 51, caret: utf16Length)

        let status = try TextPaneStatus.calculate(input: original, limits: exact)
        XCTAssertEqual(status.textUTF16Length, utf16Length)
        XCTAssertNoThrow(try TextPaneStatus.snapshotFingerprint(for: original, limits: exact))
        XCTAssertTrue(try status.isCurrent(input: independent, limits: exact))
        XCTAssertNoThrow(try status.validateCurrent(input: independent, limits: exact))

        assertStatusError(.workLimitExceeded(maximumWorkUnits: 2 * utf16Length - 1)) {
            try TextPaneStatus.calculate(input: original, limits: insufficient)
        }
        assertStatusError(.workLimitExceeded(maximumWorkUnits: 2 * utf16Length - 1)) {
            try TextPaneStatus.snapshotFingerprint(for: original, limits: insufficient)
        }
        assertStatusError(.workLimitExceeded(maximumWorkUnits: 2 * utf16Length - 1)) {
            try status.isCurrent(input: independent, limits: insufficient)
        }
        assertStatusError(.workLimitExceeded(maximumWorkUnits: 2 * utf16Length - 1)) {
            try status.validateCurrent(input: independent, limits: insufficient)
        }
    }

    func testShorterFreshnessCandidateChargesExpectedTextRemainderExactlyOnce() throws {
        let sourceLimits = limits(
            maximumInputUTF16Length: 2,
            maximumWorkUnits: 4,
            maximumGraphemeUTF16Length: 2
        )
        let status = try TextPaneStatus(
            input: input(text: "ab", revision: 61, caret: 0),
            limits: sourceLimits
        )
        let shorter = input(text: "a", revision: 61, caret: 0)
        let exactCandidateWork = limits(
            maximumInputUTF16Length: 2,
            maximumWorkUnits: 3,
            maximumGraphemeUTF16Length: 2
        )
        let insufficientCandidateWork = limits(
            maximumInputUTF16Length: 2,
            maximumWorkUnits: 2,
            maximumGraphemeUTF16Length: 2
        )

        XCTAssertFalse(try status.isCurrent(input: shorter, limits: exactCandidateWork))
        assertStatusError(.workLimitExceeded(maximumWorkUnits: 2)) {
            try status.isCurrent(input: shorter, limits: insufficientCandidateWork)
        }
    }

    func testHugeGraphemeHonorsExactSizeWorkSelectionAndScalarReportingBounds() throws {
        let scalarCount = 65_537
        let text = "a" + String(repeating: "\u{0301}", count: scalarCount - 1)
        let exact = limits(
            maximumInputUTF16Length: scalarCount,
            maximumWorkUnits: 2 * scalarCount,
            maximumGraphemeUTF16Length: scalarCount,
            maximumReportedScalarsPerGrapheme: 3,
            cancellationCheckInterval: 257
        )
        let status = try TextPaneStatus(
            input: input(
                text: text,
                revision: 71,
                caret: 0,
                selection: NSRange(location: 0, length: scalarCount)
            ),
            limits: exact
        )

        let character = try XCTUnwrap(status.currentCharacter)
        XCTAssertEqual(status.textUTF16Length, scalarCount)
        XCTAssertEqual(status.lineCount, 1)
        XCTAssertEqual(character.character, text)
        XCTAssertEqual(character.unicodeScalarCount, scalarCount)
        XCTAssertEqual(character.utf16Count, scalarCount)
        XCTAssertEqual(character.scalars.count, 3)
        XCTAssertEqual(character.scalars.map(\.codePoint), ["U+0061", "U+0301", "U+0301"])
        XCTAssertTrue(character.areScalarsTruncated)
        XCTAssertTrue(
            character.accessibilityLabel.hasSuffix(
                "first 3 of \(scalarCount) Unicode scalars shown"
            )
        )
        XCTAssertEqual(status.selectedGraphemeCount, 1)
        XCTAssertEqual(status.selectedUnicodeScalarCount, scalarCount)
        XCTAssertEqual(status.selectedUTF16Count, scalarCount)
        XCTAssertEqual(status.selectedLineCount, 1)

        assertStatusError(.workLimitExceeded(maximumWorkUnits: 2 * scalarCount - 1)) {
            try TextPaneStatus(
                input: input(text: text, revision: 71, caret: 0),
                limits: limits(
                    maximumInputUTF16Length: scalarCount,
                    maximumWorkUnits: 2 * scalarCount - 1,
                    maximumGraphemeUTF16Length: scalarCount
                )
            )
        }
        assertStatusError(.graphemeTooLarge(maximumUTF16Length: scalarCount - 1)) {
            try TextPaneStatus(
                input: input(text: text, revision: 71, caret: 0),
                limits: limits(
                    maximumInputUTF16Length: scalarCount,
                    maximumWorkUnits: 2 * scalarCount,
                    maximumGraphemeUTF16Length: scalarCount - 1
                )
            )
        }
    }

    func testEveryScanningAPIHonorsPreCancellationAndDocumentedPrecedence() async throws {
        let validInput = input(text: "x", revision: 1, caret: 0)
        let staleInput = input(text: "x", revision: 2, caret: 0)
        let invalidInput = input(text: "x", revision: 1, caret: 0, tabWidth: 0)
        let invalidLimits = limits(maximumWorkUnits: -1)
        let status = try TextPaneStatus(input: validInput)
        let staleFingerprint = try TextPaneStatus.snapshotFingerprint(for: staleInput)
        let cancellationFirstOperations: [(String, @Sendable () throws -> Void)] = [
            ("initializer", { _ = try TextPaneStatus(input: validInput) }),
            ("calculate", { _ = try TextPaneStatus.calculate(input: validInput) }),
            (
                "snapshot fingerprint",
                {
                    _ = try TextPaneStatus.snapshotFingerprint(for: validInput)
                }
            ),
            ("is current", { _ = try status.isCurrent(input: staleInput) }),
            ("validate current input", { try status.validateCurrent(input: staleInput) }),
            (
                "validate current fingerprint",
                {
                    try status.validateCurrent(snapshotFingerprint: staleFingerprint)
                }
            )
        ]
        for (name, operation) in cancellationFirstOperations {
            await assertPrecancelled(name, operation: operation)
        }

        let validationFirstOperations: [(String, @Sendable () throws -> Void)] = [
            ("initializer metadata", { _ = try TextPaneStatus(input: invalidInput) }),
            (
                "calculate metadata",
                {
                    _ = try TextPaneStatus.calculate(input: invalidInput)
                }
            ),
            (
                "snapshot fingerprint metadata",
                {
                    _ = try TextPaneStatus.snapshotFingerprint(for: invalidInput)
                }
            )
        ]
        for (name, operation) in validationFirstOperations {
            await assertPrecancelledStatusError(
                .invalidTabWidth(0),
                name: name,
                operation: operation
            )
        }

        let limitFirstOperations: [(String, @Sendable () throws -> Void)] = [
            (
                "initializer limits",
                {
                    _ = try TextPaneStatus(input: validInput, limits: invalidLimits)
                }
            ),
            (
                "calculate limits",
                {
                    _ = try TextPaneStatus.calculate(input: validInput, limits: invalidLimits)
                }
            ),
            (
                "snapshot fingerprint limits",
                {
                    _ = try TextPaneStatus.snapshotFingerprint(for: validInput, limits: invalidLimits)
                }
            ),
            (
                "is current limits",
                {
                    _ = try status.isCurrent(input: validInput, limits: invalidLimits)
                }
            ),
            (
                "validate current limits",
                {
                    try status.validateCurrent(input: validInput, limits: invalidLimits)
                }
            )
        ]
        for (name, operation) in limitFirstOperations {
            await assertPrecancelledStatusError(.invalidLimits, name: name, operation: operation)
        }

        let overBudgetLimits = limits(maximumWorkUnits: 0)
        let cancelledOverBudgetOperations: [(String, @Sendable () throws -> Void)] = [
            (
                "initializer canceled over budget",
                {
                    _ = try TextPaneStatus(input: validInput, limits: overBudgetLimits)
                }
            ),
            (
                "calculate canceled over budget",
                {
                    _ = try TextPaneStatus.calculate(input: validInput, limits: overBudgetLimits)
                }
            ),
            (
                "snapshot fingerprint canceled over budget",
                {
                    _ = try TextPaneStatus.snapshotFingerprint(
                        for: validInput,
                        limits: overBudgetLimits
                    )
                }
            ),
            (
                "is current canceled over budget",
                {
                    _ = try status.isCurrent(input: validInput, limits: overBudgetLimits)
                }
            ),
            (
                "validate current canceled over budget",
                {
                    try status.validateCurrent(input: validInput, limits: overBudgetLimits)
                }
            )
        ]
        for (name, operation) in cancelledOverBudgetOperations {
            assertStatusError(
                .workLimitExceeded(maximumWorkUnits: 0),
                "Uncancelled control: \(name)",
                operation: operation
            )
        }
        for (name, operation) in cancelledOverBudgetOperations {
            await assertCanceledBeforeScanning(name, operation: operation)
        }
    }

    func testCancellationStopsDeterministicallyObservedInFlightScannerWork() async {
        let scalarCount = 2_000_001
        let text = "a" + String(repeating: "\u{0301}", count: scalarCount - 1)
        let cancellationLimits = limits(
            maximumInputUTF16Length: scalarCount,
            maximumWorkUnits: 2 * scalarCount,
            maximumGraphemeUTF16Length: scalarCount,
            cancellationCheckInterval: 1
        )
        let cancellationInput = input(text: text, revision: 1, caret: 0)
        let probe = TextPaneStatusInFlightProbe()
        let task = Task.detached { () throws -> TextPaneStatus in
            probe.begin()
            defer { probe.finish() }
            return try TextPaneStatus(
                input: cancellationInput,
                limits: cancellationLimits
            )
        }
        guard let observation = probe.waitUntilStarted(timeout: 5) else {
            task.cancel()
            XCTFail("Scanner worker did not start")
            return
        }
        guard
            probe.waitForCPUTime(
                observation: observation,
                minimumNanoseconds: 5_000_000,
                timeout: 5
            )
        else {
            task.cancel()
            await assertCancellation(task)
            mach_port_deallocate(mach_task_self_, observation.thread)
            XCTFail("Scanner worker did not perform observable in-flight CPU work")
            return
        }
        task.cancel()
        await assertCancellation(task)
        mach_port_deallocate(mach_task_self_, observation.thread)
    }

    private static func requireSendable<T: Sendable>(_: T) {}

    private func requireSendable<T: Sendable>(_ value: T) {
        Self.requireSendable(value)
    }

    private func input(
        text: String,
        revision: UInt64,
        caret: Int,
        selection: NSRange? = nil,
        encoding: TextFileEncoding = .utf8,
        hasByteOrderMark: Bool = false,
        isReadOnly: Bool = false,
        isDirty: Bool = false,
        tabWidth: Int = 4
    ) -> TextPaneStatusInput {
        TextPaneStatusInput(
            text: text,
            revision: revision,
            caretUTF16Offset: caret,
            selectionUTF16Range: selection,
            encoding: encoding,
            hasByteOrderMark: hasByteOrderMark,
            isReadOnly: isReadOnly,
            isDirty: isDirty,
            tabWidth: tabWidth
        )
    }

    private func limits(
        maximumInputUTF16Length: Int = 1_000_000,
        maximumWorkUnits: Int = 4_000_000,
        maximumGraphemeUTF16Length: Int = 1_000_000,
        maximumReportedScalarsPerGrapheme: Int = 256,
        cancellationCheckInterval: Int = 4_096
    ) -> TextPaneStatusLimits {
        TextPaneStatusLimits(
            maximumInputUTF16Length: maximumInputUTF16Length,
            maximumWorkUnits: maximumWorkUnits,
            maximumGraphemeUTF16Length: maximumGraphemeUTF16Length,
            maximumReportedScalarsPerGrapheme: maximumReportedScalarsPerGrapheme,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func byteOrderMarkSupport(for encoding: TextFileEncoding) -> Bool {
        switch encoding {
        case .utf8, .utf16LittleEndian, .utf16BigEndian:
            true
        case .shiftJIS, .japaneseEUC, .iso2022JP, .windows1250, .windows1251,
            .windows1252, .windows1253, .windows1254, .windows1255:
            false
        }
    }

    private func assertInputAPIsThrow(
        _ expected: TextPaneStatusError,
        name: String,
        input malformed: TextPaneStatusInput,
        status: TextPaneStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let operations: [(String, () throws -> Void)] = [
            ("initializer", { _ = try TextPaneStatus(input: malformed) }),
            ("calculate", { _ = try TextPaneStatus.calculate(input: malformed) }),
            (
                "snapshot fingerprint",
                {
                    _ = try TextPaneStatus.snapshotFingerprint(for: malformed)
                }
            ),
            ("is current", { _ = try status.isCurrent(input: malformed) }),
            ("validate current", { try status.validateCurrent(input: malformed) })
        ]
        for (api, operation) in operations {
            assertStatusError(
                expected,
                "\(name): \(api)",
                file: file,
                line: line,
                operation: operation
            )
        }
    }

    private func assertStatusError<T>(
        _ expected: TextPaneStatusError,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? TextPaneStatusError,
                expected,
                message,
                file: file,
                line: line
            )
        }
    }

    private func assertCancellation<T: Sendable>(
        _ task: Task<T, Error>,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Cancelled operation unexpectedly succeeded: \(message)", file: file, line: line)
        } catch is CancellationError {
            return
        } catch {
            XCTFail("Expected CancellationError for \(message), got \(error)", file: file, line: line)
        }
    }

    private func assertPrecancelled(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping @Sendable () throws -> Void
    ) async {
        let task = Task.detached { () throws -> Void in
            withUnsafeCurrentTask { $0?.cancel() }
            try operation()
        }
        do {
            try await task.value
            XCTFail("Pre-cancelled \(name) unexpectedly succeeded", file: file, line: line)
        } catch is CancellationError {
        } catch {
            XCTFail("Pre-cancelled \(name) returned \(error)", file: file, line: line)
        }
    }

    private func assertPrecancelledStatusError(
        _ expected: TextPaneStatusError,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping @Sendable () throws -> Void
    ) async {
        let task = Task.detached { () throws -> Void in
            withUnsafeCurrentTask { $0?.cancel() }
            try operation()
        }
        do {
            try await task.value
            XCTFail("Pre-cancelled \(name) unexpectedly succeeded", file: file, line: line)
        } catch let error as TextPaneStatusError {
            XCTAssertEqual(error, expected, name, file: file, line: line)
        } catch {
            XCTFail("Pre-cancelled \(name) returned \(error)", file: file, line: line)
        }
    }

    private func assertCanceledBeforeScanning(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: @escaping @Sendable () throws -> Void
    ) async {
        let gate = TextPaneStatusCancellationGate()
        let task = Task.detached { () throws -> Void in
            gate.enter()
            try operation()
        }
        guard await gate.waitUntilEntered(timeout: .seconds(5)) else {
            task.cancel()
            gate.release()
            _ = try? await task.value
            XCTFail("\(name) did not reach cancellation gate", file: file, line: line)
            return
        }
        task.cancel()
        gate.release()
        await assertCancellation(task, name, file: file, line: line)
    }
}

private final class TextPaneStatusCancellationGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let resume = DispatchSemaphore(value: 0)

    func enter() {
        entered.signal()
        _ = resume.wait(timeout: .now() + .seconds(5))
    }

    func waitUntilEntered(timeout: DispatchTimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: self.entered.wait(timeout: .now() + timeout) == .success
                )
            }
        }
    }

    func release() {
        resume.signal()
    }
}

private final class TextPaneStatusInFlightProbe: @unchecked Sendable {
    struct Observation: Sendable {
        let thread: thread_t
        let initialCPUNanoseconds: UInt64
    }

    private let condition = NSCondition()
    private var observation: Observation?
    private var isFinished = false

    func begin() {
        let thread = mach_thread_self()
        let initialCPUNanoseconds = threadCPUNanoseconds(thread) ?? 0
        condition.lock()
        observation = Observation(
            thread: thread,
            initialCPUNanoseconds: initialCPUNanoseconds
        )
        condition.broadcast()
        condition.unlock()
    }

    func finish() {
        condition.lock()
        isFinished = true
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilStarted(timeout: TimeInterval) -> Observation? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while observation == nil, !isFinished {
            guard condition.wait(until: deadline) else { break }
        }
        return observation
    }

    func waitForCPUTime(
        observation: Observation,
        minimumNanoseconds: UInt64,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            condition.lock()
            let finished = isFinished
            condition.unlock()
            if finished { return false }
            if let current = threadCPUNanoseconds(observation.thread),
                current >= observation.initialCPUNanoseconds + minimumNanoseconds
            {
                return true
            }
            usleep(100)
        }
        return false
    }

    private func threadCPUNanoseconds(_ thread: thread_t) -> UInt64? {
        var info = thread_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let seconds = UInt64(info.user_time.seconds) + UInt64(info.system_time.seconds)
        let microseconds =
            UInt64(info.user_time.microseconds) + UInt64(info.system_time.microseconds)
        return seconds * 1_000_000_000 + microseconds * 1_000
    }
}
