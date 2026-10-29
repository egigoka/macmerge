import Foundation
import XCTest

@testable import MacMergeCore

final class CodePageRoundTripHarnessStageTests: XCTestCase {
    private typealias Harness = CodePageRoundTripHarness
    private typealias Stage = CodePageRoundTripHarness.Stage

    private static let windowsEncodings: [TextFileEncoding] = [
        .windows1250, .windows1251, .windows1252, .windows1253, .windows1254, .windows1255
    ]

    private static let crlf: [UInt8] = [0x0D, 0x0A]
    private static let markerPrefix = Array("// MacMerge round-trip edit: ".utf8)
    private static let escapeToJIS: [UInt8] = [0x1B, 0x24, 0x42]
    private static let escapeToASCII: [UInt8] = [0x1B, 0x28, 0x42]

    /// Edit-marker bytes pinned against the Windows code page tables (and the
    /// Unicode encoding forms), not derived from the converter under test.
    private static let markerBytes: [TextFileEncoding: [UInt8]] = [
        .utf8: markerPrefix + [
            0x63, 0x61, 0x66, 0xC3, 0xA9, 0x20, 0xE2, 0x9C, 0x93, 0x20,
            0xE7, 0xB7, 0xA8, 0xE9, 0x9B, 0x86, 0x20, 0xF0, 0x9F, 0x98, 0x80
        ],
        // 編集テスト: CP932 95 D2 8F 57 83 65 83 58 83 67.
        .shiftJIS: markerPrefix + [0x95, 0xD2, 0x8F, 0x57, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67],
        .japaneseEUC: markerPrefix + [0xCA, 0xD4, 0xBD, 0xB8, 0xA5, 0xC6, 0xA5, 0xB9, 0xA5, 0xC8],
        .iso2022JP: markerPrefix + escapeToJIS
            + [0x4A, 0x54, 0x3D, 0x38, 0x25, 0x46, 0x25, 0x39, 0x25, 0x48] + escapeToASCII,
        // žluťoučký
        .windows1250: markerPrefix + [0x9E, 0x6C, 0x75, 0x9D, 0x6F, 0x75, 0xE8, 0x6B, 0xFD],
        // правка
        .windows1251: markerPrefix + [0xEF, 0xF0, 0xE0, 0xE2, 0xEA, 0xE0],
        // café €
        .windows1252: markerPrefix + [0x63, 0x61, 0x66, 0xE9, 0x20, 0x80],
        // δοκιμή
        .windows1253: markerPrefix + [0xE4, 0xEF, 0xEA, 0xE9, 0xEC, 0xDE],
        // düzenleme ğış
        .windows1254: markerPrefix + [0x64, 0xFC, 0x7A, 0x65, 0x6E, 0x6C, 0x65, 0x6D, 0x65, 0x20, 0xF0, 0xFD, 0xFE],
        // עריכה
        .windows1255: markerPrefix + [0xF2, 0xF8, 0xE9, 0xEB, 0xE4]
    ]

    private struct Run {
        let result: Harness.FixtureResult
        /// Right working-copy bytes captured right after the edited save.
        let savedBytes: Data?
    }

    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodePageRoundTripHarnessStageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeFixture(
        _ bytes: Data,
        folder: String,
        in root: URL,
        named name: String = "fixture.txt"
    ) throws -> Harness.Fixture {
        let directory = root.appendingPathComponent("source/\(folder)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return Harness.Fixture(
            relativePath: "Codepages/\(folder)/\(name)",
            url: url,
            folderName: folder,
            expected: try XCTUnwrap(Harness.fixtureFolderEncodings[folder])
        )
    }

    private func run(
        _ bytes: [UInt8],
        folder: String,
        byteLimit: Int = Harness.maximumFixtureBytes,
        marker: String? = nil,
        fault: Harness.FaultInjection? = nil,
        save: ((TextFileDocument) throws -> TextFileDocument)? = nil
    ) throws -> Run {
        let root = try makeScratchDirectory()
        let fixture = try writeFixture(Data(bytes), folder: folder, in: root)
        var savedBytes: Data?
        let result = Harness.runFixture(
            fixture,
            in: root.appendingPathComponent("work", isDirectory: true),
            byteLimit: byteLimit,
            markerOverride: marker,
            saveOverride: save
        ) { point, left, right in
            if point == .afterSave { savedBytes = try? Data(contentsOf: right) }
            fault?(point, left, right)
        }
        return Run(result: result, savedBytes: savedBytes)
    }

    /// A save that bypasses `TextFileDocumentIO.save`'s fail-closed guard and writes the
    /// codec's canonical encoding of the whole text, plus `extra` trailing bytes.
    private static func canonicalSave(
        appending extra: [UInt8] = []
    ) -> (TextFileDocument) throws -> TextFileDocument {
        { document in
            var bytes = try TextFileCodec.encode(
                DecodedTextFile(
                    text: document.text,
                    encoding: document.encoding,
                    hasByteOrderMark: document.hasByteOrderMark
                ))
            bytes.append(contentsOf: extra)
            try bytes.write(to: document.url)
            return try TextFileDocumentIO.load(from: document.url, assuming: document.encoding)
        }
    }

    /// A legacy source whose unedited bytes are not the codec's canonical encoding:
    /// the production save fails closed, and a save that does canonicalize is caught
    /// by the byte stage at the first rewritten byte.
    private func assertNoncanonicalSource(
        line2: [UInt8],
        folder: String,
        encoding: TextFileEncoding,
        firstRewrittenByteInLine2 offset: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source: [UInt8] = [0x61] + Self.crlf + line2
        let production = try run(source, folder: folder).result
        assertFailed(
            production,
            at: .save,
            with: .saveFailed("Text could not be encoded as \(encoding.displayName)."),
            file: file,
            line: line
        )

        let markerCount = try marker(encoding).count + 2
        let saved = source.count + markerCount
        let canonicalized = try run(source, folder: folder, save: Self.canonicalSave()).result
        assertFailed(
            canonicalized, at: .byteComparison,
            with: .canonicalizedUneditedBytes(
                .init(expectedCount: saved, actualCount: saved, firstDifferenceOffset: 3 + markerCount + offset)
            ), file: file, line: line)
    }

    private func marker(_ encoding: TextFileEncoding) throws -> [UInt8] {
        try XCTUnwrap(Self.markerBytes[encoding], "\(encoding)")
    }

    private func status(_ result: Harness.FixtureResult, _ stage: Stage) -> Harness.StageStatus? {
        result.stages.first { $0.stage == stage }?.status
    }

    private func assertFailed(
        _ result: Harness.FixtureResult,
        at stage: Stage,
        with failure: Harness.Failure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.stages.map(\.stage), Stage.allCases, file: file, line: line)
        for outcome in result.stages {
            let expected: Harness.StageStatus =
                outcome.stage < stage
                ? .passed
                : outcome.stage == stage ? .failed(failure) : .notRun
            XCTAssertEqual(outcome.status, expected, "\(outcome.stage)", file: file, line: line)
        }
    }

    // MARK: Pinned Windows bytes

    func testEditMarkersEncodeToWindowsCodePageBytes() throws {
        for encoding in Harness.supportedEncodings where encoding != .utf16LittleEndian && encoding != .utf16BigEndian {
            let encoded = try TextFileCodec.encode(
                DecodedTextFile(text: Harness.editMarker(for: encoding), encoding: encoding, hasByteOrderMark: false)
            )
            XCTAssertEqual(Array(encoded), try marker(encoding), "\(encoding)")
        }
        // U+1F600 is the surrogate pair D83D DE00 in both UTF-16 byte orders.
        let little = try TextFileCodec.encode(
            DecodedTextFile(text: Harness.editMarker(for: .utf16LittleEndian), encoding: .utf16LittleEndian, hasByteOrderMark: false)
        )
        XCTAssertEqual(Array(little.suffix(4)), [0x3D, 0xD8, 0x00, 0xDE])
        let big = try TextFileCodec.encode(
            DecodedTextFile(text: Harness.editMarker(for: .utf16BigEndian), encoding: .utf16BigEndian, hasByteOrderMark: false)
        )
        XCTAssertEqual(Array(big.suffix(4)), [0xD8, 0x3D, 0xDE, 0x00])
    }

    func testSynthesizedBytesMatchWindowsTablesAndKeepUnterminatedLastLine() throws {
        // Pinned characters from each sample: CP1250 ř, CP1251 ъ, CP1252 €5, CP1253 Ξ,
        // CP1254 ı, CP1255 ₪.
        let pinned: [TextFileEncoding: [UInt8]] = [
            .windows1250: [0x50, 0xF8],
            .windows1251: [0xD1, 0xFA],
            .windows1252: [0x80, 0x35],
            .windows1253: [0xCE],
            .windows1254: [0x6C, 0xFD],
            .windows1255: [0xA4]
        ]
        for encoding in Self.windowsEncodings {
            let bytes = try XCTUnwrap(Harness.synthesizedFixtureBytes(for: encoding), "\(encoding)")
            XCTAssertNotNil(bytes.firstRange(of: Data(try XCTUnwrap(pinned[encoding]))), "\(encoding)")
            XCTAssertNotNil(bytes.firstRange(of: Data([0x0A, 0x0A])), "\(encoding)")
            XCTAssertNotEqual(bytes.last, 0x0A, "\(encoding)")
            XCTAssertNotEqual(bytes.last, 0x0D, "\(encoding)")
        }
        // Line 1 of the Japanese fixtures ends with 日本語テキスト, so the edit is
        // spliced after a multibyte prefix (and, for ISO-2022-JP, a JIS-mode run).
        let firstLineEndings: [TextFileEncoding: [UInt8]] = [
            .shiftJIS: [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x83, 0x65, 0x83, 0x4C, 0x83, 0x58, 0x83, 0x67] + Self.crlf,
            .japaneseEUC: [0xC6, 0xFC, 0xCB, 0xDC, 0xB8, 0xEC, 0xA5, 0xC6, 0xA5, 0xAD, 0xA5, 0xB9, 0xA5, 0xC8] + Self.crlf,
            .iso2022JP: Self.escapeToJIS
                + [0x46, 0x7C, 0x4B, 0x5C, 0x38, 0x6C, 0x25, 0x46, 0x25, 0x2D, 0x25, 0x39, 0x25, 0x48]
                + Self.escapeToASCII + Self.crlf
        ]
        for (encoding, ending) in firstLineEndings {
            let bytes = try XCTUnwrap(Harness.synthesizedFixtureBytes(for: encoding), "\(encoding)")
            let firstLineEnd = try XCTUnwrap(bytes.firstRange(of: Data(Self.crlf)), "\(encoding)").upperBound
            XCTAssertEqual(Array(bytes.prefix(firstLineEnd).suffix(ending.count)), ending, "\(encoding)")
        }
        let wide = try XCTUnwrap(Harness.synthesizedFixtureBytes(for: .utf16BigEndian))
        XCTAssertEqual(Array(wide.prefix(2)), [0xFE, 0xFF])
        let narrow = try XCTUnwrap(Harness.synthesizedFixtureBytes(for: .utf8))
        XCTAssertNotEqual(Array(narrow.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testSynthesizedFolderEncodingPrefersNoByteOrderMark() {
        XCTAssertEqual(
            Harness.synthesizedFolderEncoding(for: .utf8),
            .init(encoding: .utf8, hasByteOrderMark: false, windowsCodePage: 65001)
        )
        XCTAssertEqual(Harness.synthesizedFolderEncoding(for: .utf16LittleEndian)?.hasByteOrderMark, true)
        for (encoding, page) in zip(Self.windowsEncodings, [1250, 1251, 1252, 1253, 1254, 1255]) {
            XCTAssertEqual(Harness.synthesizedFolderEncoding(for: encoding)?.windowsCodePage, page)
        }
    }

    func testSynthesizedFixturesRoundTripForEveryEncoding() throws {
        let root = try makeScratchDirectory()
        for (index, encoding) in Harness.supportedEncodings.enumerated() {
            let result = Harness.runSynthesizedFixture(
                for: encoding,
                in: root.appendingPathComponent("\(index)", isDirectory: true)
            )
            XCTAssertTrue(result.isByteExactRoundTrip, "\(encoding): \(String(describing: result.firstFailure))")
            XCTAssertTrue(result.relativePath.hasPrefix(Harness.synthesizedPathPrefix + "/"), result.relativePath)
        }
    }

    // MARK: Splice after a non-ASCII first line

    func testJapaneseSpliceAfterKanjiFirstLineChangesOnlyEditedBytes() throws {
        // Line 1 is 編集 and line 2 is テスト (unterminated), in Windows bytes.
        let fixtures: [(folder: String, encoding: TextFileEncoding, firstLine: [UInt8], rest: [UInt8])] = [
            ("CP932", .shiftJIS, [0x95, 0xD2, 0x8F, 0x57] + Self.crlf, [0x83, 0x65, 0x83, 0x58, 0x83, 0x67]),
            ("CP51932", .japaneseEUC, [0xCA, 0xD4, 0xBD, 0xB8] + Self.crlf, [0xA5, 0xC6, 0xA5, 0xB9, 0xA5, 0xC8]),
            (
                "CP50220",
                .iso2022JP,
                [0x1B, 0x24, 0x42, 0x4A, 0x54, 0x3D, 0x38, 0x1B, 0x28, 0x42] + Self.crlf,
                Self.escapeToJIS + [0x25, 0x46, 0x25, 0x39, 0x25, 0x48] + Self.escapeToASCII
            )
        ]
        for fixture in fixtures {
            let run = try run(fixture.firstLine + fixture.rest, folder: fixture.folder)
            XCTAssertTrue(run.result.isByteExactRoundTrip, "\(fixture.folder): \(String(describing: run.result.firstFailure))")
            let expected = fixture.firstLine + (try marker(fixture.encoding)) + Self.crlf + fixture.rest
            XCTAssertEqual(run.savedBytes.map(Array.init), expected, fixture.folder)
        }
    }

    // MARK: Byte-stage negatives from real codec behavior

    func testCP50220JISRomanDesignationIsNoncanonical() throws {
        // Line 2 returns to single-byte mode with ESC ( J (JIS X 0201 Roman); the codec
        // always writes ESC ( B.
        try assertNoncanonicalSource(
            line2: Self.escapeToJIS + [0x4A, 0x54, 0x3D, 0x38, 0x1B, 0x28, 0x4A] + Self.crlf + [0x7A],
            folder: "CP50220",
            encoding: .iso2022JP,
            firstRewrittenByteInLine2: 9
        )
    }

    func testCP50220OldJISDesignationIsNoncanonical() throws {
        // Line 2 enters JIS X 0208 with the 1978 designation ESC $ @; the codec writes ESC $ B.
        try assertNoncanonicalSource(
            line2: [0x1B, 0x24, 0x40, 0x4A, 0x54, 0x3D, 0x38] + Self.escapeToASCII + Self.crlf + [0x7A],
            folder: "CP50220",
            encoding: .iso2022JP,
            firstRewrittenByteInLine2: 2
        )
    }

    func testCP50220NoncanonicalFirstLineMakesSpliceUnavailable() throws {
        // Line 1 ends with ESC ( J, which re-encoding the prefix cannot reproduce.
        let source: [UInt8] = Self.escapeToJIS + [0x4A, 0x54, 0x1B, 0x28, 0x4A] + Self.crlf + [0x7A]
        assertFailed(try run(source, folder: "CP50220").result, at: .edit, with: .spliceUnavailable)
    }

    func testCP50220HalfwidthKanaCannotBeSavedUnchanged() throws {
        // ｱ (U+FF71) as ESC ( I 0x31 and as SO 0x31 SI. CP50220 has no single-byte kana and
        // writes ア instead, like Windows. The production save fails closed; a save that
        // writes the fullwidth form is caught because the reloaded text changed.
        let escapeKana: [UInt8] = [0x61] + Self.crlf + [0x1B, 0x28, 0x49, 0x31] + Self.escapeToASCII
        let shiftKana: [UInt8] = [0x61] + Self.crlf + [0x0E, 0x31, 0x0F]
        for source in [escapeKana, shiftKana] {
            assertFailed(
                try run(source, folder: "CP50220").result,
                at: .save,
                with: .saveFailed("Text could not be encoded as ISO-2022-JP (CP50220).")
            )
            let canonicalized = try run(source, folder: "CP50220", save: Self.canonicalSave()).result
            assertFailed(canonicalized, at: .reload, with: .reloadTextMismatch)
        }
    }

    func testCP932NECRowThirteenAliasIsNoncanonical() throws {
        // ≒ as NEC row 13 (87 90) is written back as JIS X 0208 81 E0, as Windows does.
        try assertNoncanonicalSource(line2: [0x87, 0x90], folder: "CP932", encoding: .shiftJIS, firstRewrittenByteInLine2: 0)
    }

    func testCP932IBMExtensionAliasIsNoncanonical() throws {
        // ⅰ (U+2170) has an IBM extension code FA 40 and an NEC-selected code EE EF.
        // Windows CP932 writes FA 40; Foundation's Shift_JIS converter writes EE EF.
        // This pins that known divergence: an edited FA 40 file cannot be saved.
        try assertNoncanonicalSource(line2: [0xFA, 0x40], folder: "CP932", encoding: .shiftJIS, firstRewrittenByteInLine2: 0)
        let necSelected: [UInt8] = [0x61] + Self.crlf + [0xEE, 0xEF]
        XCTAssertTrue(try run(necSelected, folder: "CP932").result.isByteExactRoundTrip)
    }

    func testNoncanonicalSaveOutputFailsSave() throws {
        let source = Array("a\r\nb".utf8)
        let run = try run(source, folder: "CP1252", save: Self.canonicalSave(appending: [0x21]))
        let canonical = source.count + (try marker(.windows1252)).count + 2
        assertFailed(
            run.result, at: .save,
            with: .savedBytesNotCanonical(
                .init(expectedCount: canonical, actualCount: canonical + 1, firstDifferenceOffset: canonical)
            ))
    }

    // MARK: Edit-stage negatives

    func testUnrepresentableMarkerFailsEdit() throws {
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252", marker: "\u{65E5}\u{672C}")
        assertFailed(run.result, at: .edit, with: .editNotRepresentable)
        XCTAssertEqual(run.result.editMarker, "\u{65E5}\u{672C}")
    }

    func testMultiLineMarkerFailsSingleInsertionCheck() throws {
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252", marker: "x\r\ny")
        assertFailed(run.result, at: .edit, with: .unexpectedDifferences(.init(modified: 0, removed: 0, added: 2)))
    }

    // MARK: Fault injection after save

    func testDeletedSaveFailsReload() throws {
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252") { point, _, right in
            if point == .afterSave { try? FileManager.default.removeItem(at: right) }
        }
        guard case .failed(.reloadFailed)? = status(run.result, .reload) else {
            return XCTFail("reload status \(String(describing: status(run.result, .reload)))")
        }
        XCTAssertEqual(run.result.firstFailure?.stage, .reload)
        XCTAssertEqual(status(run.result, .byteComparison), .notRun)
    }

    func testRewrittenTextFailsReload() throws {
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252") { point, _, right in
            if point == .afterSave { try? Data("a\r\nX\r\nb".utf8).write(to: right) }
        }
        assertFailed(run.result, at: .reload, with: .reloadTextMismatch)
    }

    func testStrippedByteOrderMarkFailsReload() throws {
        let run = try run([0xEF, 0xBB, 0xBF] + Array("a\r\nb".utf8), folder: "UTF-8") { point, _, right in
            guard point == .afterSave, let bytes = try? Data(contentsOf: right) else { return }
            try? bytes.dropFirst(3).write(to: right)
        }
        assertFailed(run.result, at: .reload, with: .byteOrderMarkMismatch(expected: true, actual: false))
    }

    func testSameTextDifferentBytesFailsReload() throws {
        // The trailing ESC ( B becomes ESC ( J: identical text, different bytes.
        let source: [UInt8] = [0x61] + Self.crlf + Self.escapeToJIS + [0x4A, 0x54] + Self.escapeToASCII
        let run = try run(source, folder: "CP50220") { point, _, right in
            guard point == .afterSave, var bytes = try? Data(contentsOf: right) else { return }
            bytes[bytes.count - 1] = 0x4A
            try? bytes.write(to: right)
        }
        let saved = source.count + (try marker(.iso2022JP)).count + 2
        assertFailed(
            run.result, at: .reload,
            with: .reloadBytesMismatch(
                .init(expectedCount: saved, actualCount: saved, firstDifferenceOffset: saved - 1)
            ))
    }

    func testReadOnlyWorkingCopyFailsRevertSave() throws {
        var lockedDirectory: URL?
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252") { point, _, right in
            guard point == .afterSave else { return }
            lockedDirectory = right.deletingLastPathComponent()
            try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: right.path)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o555],
                ofItemAtPath: right.deletingLastPathComponent().path
            )
        }
        if let lockedDirectory {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDirectory.path)
        }
        guard case .failed(.revertSaveFailed)? = status(run.result, .byteComparison) else {
            return XCTFail("byte status \(String(describing: status(run.result, .byteComparison)))")
        }
        XCTAssertEqual(run.result.firstFailure?.stage, .byteComparison)
    }

    // MARK: Fault injection after revert

    func testTamperedRevertFailsByteComparison() throws {
        let source = Array("a\r\nb".utf8)
        let run = try run(source, folder: "CP1252") { point, _, right in
            if point == .afterRevertSave { try? Data("a\r\nc".utf8).write(to: right) }
        }
        assertFailed(
            run.result, at: .byteComparison,
            with: .revertBytesMismatch(
                .init(expectedCount: 4, actualCount: 4, firstDifferenceOffset: 3)
            ))
    }

    func testDeletedRevertFailsByteComparison() throws {
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252") { point, _, right in
            if point == .afterRevertSave { try? FileManager.default.removeItem(at: right) }
        }
        assertFailed(run.result, at: .byteComparison, with: .revertSaveFailed("reverted file unreadable"))
    }

    func testTamperedUntouchedCopyFailsByteComparison() throws {
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252") { point, left, _ in
            if point == .afterRevertSave { try? Data("a\r\nb\r\n".utf8).write(to: left) }
        }
        assertFailed(
            run.result, at: .byteComparison,
            with: .untouchedCopyMismatch(
                .init(expectedCount: 4, actualCount: 6, firstDifferenceOffset: 4)
            ))
    }

    func testDeletedUntouchedCopyFailsByteComparison() throws {
        let run = try run(Array("a\r\nb".utf8), folder: "CP1252") { point, left, _ in
            if point == .afterRevertSave { try? FileManager.default.removeItem(at: left) }
        }
        assertFailed(run.result, at: .byteComparison, with: .untouchedCopyUnreadable)
    }

    // MARK: Single fixtures and load errors

    func testCarriageReturnOnlyFixtureRoundTrips() throws {
        let source: [UInt8] = [0x61, 0xE9, 0x0D, 0x62, 0x0D, 0x63]
        let run = try run(source, folder: "CP1252")
        XCTAssertTrue(run.result.isByteExactRoundTrip, String(describing: run.result.firstFailure))
        XCTAssertEqual(run.savedBytes.map(Array.init), [0x61, 0xE9, 0x0D] + (try marker(.windows1252)) + [0x0D, 0x62, 0x0D, 0x63])
    }

    func testEmptyFixtureRoundTripsAsMarkerOnly() throws {
        let run = try run([], folder: "CP1252")
        XCTAssertTrue(run.result.isByteExactRoundTrip, String(describing: run.result.firstFailure))
        XCTAssertEqual(run.result.sourceByteCount, 0)
        XCTAssertEqual(run.savedBytes.map(Array.init), try marker(.windows1252))
    }

    func testUnterminatedFixtureAppendsWinMergeDefaultCRLF() throws {
        // WinMerge treats a file without any EOL as DOS style, so the appended line
        // starts with CRLF rather than the macOS LF.
        let source: [UInt8] = [0x63, 0x61, 0x66, 0xE9]
        let run = try run(source, folder: "CP1252")
        XCTAssertTrue(run.result.isByteExactRoundTrip, String(describing: run.result.firstFailure))
        XCTAssertEqual(run.savedBytes.map(Array.init), source + Self.crlf + (try marker(.windows1252)))
        XCTAssertEqual(Harness.defaultLineEnding, "\r\n")
    }

    func testMissingFixtureFailsLoadAndSkipsLaterStages() throws {
        let root = try makeScratchDirectory()
        let fixture = Harness.Fixture(
            relativePath: "Codepages/CP1252/missing.txt",
            url: root.appendingPathComponent("missing.txt"),
            folderName: "CP1252",
            expected: try XCTUnwrap(Harness.fixtureFolderEncodings["CP1252"])
        )
        let result = Harness.runFixture(fixture, in: root.appendingPathComponent("work", isDirectory: true))
        assertFailed(result, at: .load, with: .fixtureUnreadable)
        XCTAssertNil(result.automaticDetection)
    }

    func testByteLimitBoundary() throws {
        let atLimit = Array("a\r\n".utf8) + Array(repeating: 0x62, count: 61)
        let accepted = try run(atLimit, folder: "CP1252", byteLimit: 64)
        XCTAssertTrue(accepted.result.isByteExactRoundTrip, String(describing: accepted.result.firstFailure))
        XCTAssertEqual(accepted.result.sourceByteCount, 64)

        let rejected = try run(atLimit + [0x62], folder: "CP1252", byteLimit: 64)
        assertFailed(rejected.result, at: .load, with: .fixtureTooLarge(byteCount: 65))
        XCTAssertEqual(rejected.result.sourceByteCount, 65)
        XCTAssertNil(rejected.result.automaticDetection)
    }

    func testMissingByteOrderMarkFailsLoad() throws {
        let result = try run(Array("a\nb".utf8), folder: "UTF-8").result
        assertFailed(result, at: .load, with: .byteOrderMarkMismatch(expected: true, actual: false))
    }

    func testUndecodableBytesFailLoad() throws {
        let result = try run([0x61, 0xFF, 0xFE, 0x0A], folder: "UTF-8-NOBOM").result
        guard case .failed(.loadFailed)? = status(result, .load) else {
            return XCTFail("load status \(String(describing: status(result, .load)))")
        }
        XCTAssertEqual(result.stages.dropFirst().map(\.status), Array(repeating: .notRun, count: Stage.allCases.count - 1))
    }

    func testWorkingCopyCollisionFailsLoad() throws {
        let root = try makeScratchDirectory()
        let fixture = try writeFixture(Data("a\nb".utf8), folder: "CP1252", in: root)
        let work = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: work.appendingPathComponent("left-fixture.txt"))

        let result = Harness.runFixture(fixture, in: work)
        assertFailed(result, at: .load, with: .workingCopyFailed)
        XCTAssertEqual(try Data(contentsOf: work.appendingPathComponent("left-fixture.txt")), Data("stale".utf8))
    }

    // MARK: Run lifecycle

    func testCancellationDuringSynthesisThrows() throws {
        let root = try makeScratchDirectory()
        let folder = root.appendingPathComponent("Codepages/CP1252", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Unicode", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("a\r\nb".utf8).write(to: folder.appendingPathComponent("a.txt"))
        let catalog = try Harness.discover(dataRoot: root)
        let fixtureCount = catalog.fixtures.count
        XCTAssertFalse(catalog.encodingsWithoutFixture.isEmpty)

        let work = try makeScratchDirectory()
        let calls = Counter()
        // Every real fixture passes the check; the first synthesized fixture is cancelled.
        XCTAssertThrowsError(
            try Harness.run(catalog: catalog, workingDirectory: work, cancellationCheck: { calls.next() > fixtureCount })
        ) { error in
            XCTAssertEqual(error as? Harness.HarnessError, .cancelled)
        }
        XCTAssertEqual(calls.value, fixtureCount + 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path), [])
    }

    func testRunCatalogCarriesKnownUnsupportedCodePages() throws {
        let root = try makeScratchDirectory()
        let catalog = Harness.Catalog(dataRoot: root, fixtures: [], unsupportedFixtures: [])
        let report = try Harness.run(catalog: catalog, workingDirectory: root, synthesizeMissingEncodings: false)
        XCTAssertEqual(report.knownUnsupportedCodePages, Harness.knownUnsupportedCodePages)
        XCTAssertEqual(report.results, [])
        XCTAssertEqual(report.synthesizedResults, [])
        XCTAssertFalse(report.allFixturesByteExact)
        XCTAssertFalse(report.allSynthesizedByteExact)
    }

    // MARK: Discovery and report gating

    func testMissingFamilyKeepsReportFromClaimingFullCoverage() throws {
        let root = try makeScratchDirectory()
        let folder = root.appendingPathComponent("Unicode/UTF-8-NOBOM", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a\nb".utf8).write(to: folder.appendingPathComponent("a.txt"))

        let report = try Harness.run(dataRoot: root, synthesizeMissingEncodings: false)
        XCTAssertEqual(report.passedCount, 1)
        XCTAssertEqual(report.catalog.unsupportedFixtures, [.init(relativePath: "Codepages/", reason: .missingFixtureFamily)])
        XCTAssertFalse(report.allFixturesByteExact)
    }

    func testEmptyUnrecognizedFolderIsReportedButEmptyRecognizedFolderIsNot() throws {
        let root = try makeScratchDirectory()
        for path in ["Codepages/CP7777", "Codepages/CP1252", "Unicode"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let catalog = try Harness.discover(dataRoot: root)
        XCTAssertEqual(catalog.fixtures, [])
        XCTAssertEqual(catalog.unsupportedFixtures, [.init(relativePath: "Codepages/CP7777/", reason: .unrecognizedFixtureFolder)])
        XCTAssertEqual(catalog.encodingsWithoutFixture, Harness.supportedEncodings)
    }

    func testFixtureLimitCountsMissingFamily() throws {
        let root = try makeScratchDirectory()
        let folder = root.appendingPathComponent("Codepages/CP1252", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // "Unicode/" is missing and counts as one unsupported entry toward the limit.
        for index in 0..<(Harness.maximumFixtures - 1) {
            try Data().write(to: folder.appendingPathComponent("f\(index).txt"))
        }
        let catalog = try Harness.discover(dataRoot: root)
        XCTAssertEqual(catalog.fixtures.count, Harness.maximumFixtures - 1)
        XCTAssertEqual(catalog.unsupportedFixtures, [.init(relativePath: "Unicode/", reason: .missingFixtureFamily)])

        try Data().write(to: folder.appendingPathComponent("overflow.txt"))
        XCTAssertThrowsError(try Harness.discover(dataRoot: root)) { error in
            XCTAssertEqual(error as? Harness.HarnessError, .fixtureLimitExceeded(maximum: Harness.maximumFixtures))
        }
    }

    func testIncompleteStagesAreNotByteExact() {
        let expected = Harness.FixtureFolderEncoding(encoding: .utf8, hasByteOrderMark: false, windowsCodePage: 65001)
        let partial = Harness.FixtureResult(
            relativePath: "x",
            expected: expected,
            sourceByteCount: 0,
            automaticDetection: nil,
            stages: [.init(stage: .load, status: .passed)],
            savedByteCount: 0,
            editMarker: ""
        )
        XCTAssertFalse(partial.isByteExactRoundTrip)
        XCTAssertNil(partial.firstFailure.map { "\($0)" })
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
