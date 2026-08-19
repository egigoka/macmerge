import Foundation
import MacMergeCore
import XCTest

final class EncodingRecoveryTests: XCTestCase {
    func testLegacyCreateReturnsCanonicalPersistedText() throws {
        let source = try temporaryFile(data: Data())

        let document = try TextFileDocumentIO.create(
            at: source,
            text: "ｱ",
            encoding: .iso2022JP
        )

        XCTAssertEqual(document.text, "ア")
        XCTAssertEqual(document.persistedText, "ア")
        XCTAssertEqual(document.persistedData, try Data(contentsOf: source))
        XCTAssertFalse(document.isDirty)
    }

    func testNoncanonicalCP932AliasesRemainByteExactAndEditedSavesFailClosed() throws {
        let fixtures: [(bytes: [UInt8], text: String)] = [
            ([0xFA, 0x5C], "纊"),
            ([0xFA, 0x40], "ⅰ"),
            ([0xFA, 0x5B], "∵"),
        ]

        for fixture in fixtures {
            let original = Data(fixture.bytes)
            let source = try temporaryFile(data: original)
            let destination = source.deletingLastPathComponent().appending(path: "edited-copy.txt")
            var document = try TextFileDocumentIO.load(from: source, assuming: .shiftJIS)

            XCTAssertEqual(document.text, fixture.text)
            let cleanSave = try TextFileDocumentIO.save(document)
            XCTAssertNil(cleanSave.warning)
            XCTAssertEqual(try Data(contentsOf: source), original)

            document = cleanSave.document
            document.text += "!"
            XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.shiftJIS))
            }
            XCTAssertThrowsError(try TextFileDocumentIO.saveAs(document, to: destination)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.shiftJIS))
            }
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testNoncanonicalCP50220StreamsRemainByteExactAndEditedSavesFailClosed() throws {
        let fixtures: [(bytes: [UInt8], text: String)] = [
            ([0x1B, 0x24, 0x40, 0x24, 0x22, 0x1B, 0x28, 0x42], "あ"),
            ([0x1B, 0x28, 0x49, 0x31, 0x1B, 0x28, 0x42], "ｱ"),
            ([0x0E, 0x31, 0x0F], "ｱ"),
        ]

        for fixture in fixtures {
            let original = Data(fixture.bytes)
            let source = try temporaryFile(data: original)
            let destination = source.deletingLastPathComponent().appending(path: "edited-copy.txt")
            var document = try TextFileDocumentIO.load(from: source, assuming: .iso2022JP)

            XCTAssertEqual(document.text, fixture.text)
            let cleanSave = try TextFileDocumentIO.save(document)
            XCTAssertNil(cleanSave.warning)
            XCTAssertEqual(try Data(contentsOf: source), original)

            document = cleanSave.document
            document.text += "!"
            XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.iso2022JP))
            }
            XCTAssertThrowsError(try TextFileDocumentIO.saveAs(document, to: destination)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.iso2022JP))
            }
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testUnrepresentableLegacyEditsFailWithoutChangingSourceOrCreatingCopy() throws {
        let fixtures: [(bytes: [UInt8], encoding: TextFileEncoding, text: String)] = [
            ([0x83, 0x65], .shiftJIS, "テ"),
            ([0x1B, 0x24, 0x42, 0x25, 0x46, 0x1B, 0x28, 0x42], .iso2022JP, "テ"),
            ([0x8C], .windows1250, "Ś"),
            ([0xCF], .windows1251, "П"),
            ([0x8C], .windows1252, "Œ"),
            ([0xDD], .windows1254, "İ"),
        ]

        for fixture in fixtures {
            let original = Data(fixture.bytes)
            let source = try temporaryFile(data: original)
            let destination = source.deletingLastPathComponent().appending(path: "unrepresentable-copy.txt")
            var document = try TextFileDocumentIO.load(from: source, assuming: fixture.encoding)

            XCTAssertEqual(document.text, fixture.text)
            document.text += "🙂"

            XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(fixture.encoding))
            }
            XCTAssertThrowsError(try TextFileDocumentIO.saveAs(document, to: destination)) { error in
                XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(fixture.encoding))
            }
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testCP50220CanonicalizingSaveReturnsCanonicalDocumentAndBytes() throws {
        let source = try temporaryFile(data: Data([0x41]))
        var document = try TextFileDocumentIO.load(from: source, assuming: .iso2022JP)
        document.text = "ｱ"

        let result = try TextFileDocumentIO.save(document)

        XCTAssertEqual(
            try Data(contentsOf: source),
            Data([0x1B, 0x24, 0x42, 0x25, 0x22, 0x1B, 0x28, 0x42])
        )
        XCTAssertEqual(result.document.text, "ア")
        XCTAssertEqual(result.document.persistedText, "ア")
        XCTAssertEqual(
            result.document.persistedData,
            Data([0x1B, 0x24, 0x42, 0x25, 0x22, 0x1B, 0x28, 0x42])
        )
        XCTAssertFalse(result.document.isDirty)
        XCTAssertNil(result.warning)
    }

    func testAmbiguousInputsRequireExplicitSelectionBeforeByteExactSave() throws {
        let jis = Data([0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42])
        let jisSource = try temporaryFile(data: jis)

        XCTAssertThrowsError(try TextFileDocumentIO.load(from: jisSource)) { error in
            XCTAssertEqual(
                error as? TextFileCodecError,
                .ambiguousTextEncoding([.utf8, .iso2022JP])
            )
        }
        let selectedJIS = try TextFileDocumentIO.load(from: jisSource, assuming: .iso2022JP)
        XCTAssertEqual(selectedJIS.text, "あ")
        XCTAssertEqual(selectedJIS.encoding, .iso2022JP)
        XCTAssertEqual(try Data(contentsOf: jisSource), jis)
        XCTAssertEqual(try Data(contentsOf: try saveClean(selectedJIS)), jis)

        let windows = Data([0x80, 0x8A, 0x8C, 0x9A, 0x9C, 0x9F])
        let selections: [(TextFileEncoding, String)] = [
            (.windows1250, "€ŠŚšśź"),
            (.windows1251, "ЂЉЊљњџ"),
            (.windows1252, "€ŠŒšœŸ"),
            (.windows1254, "€ŠŒšœŸ"),
        ]

        for (encoding, expectedText) in selections {
            let source = try temporaryFile(data: windows)
            XCTAssertThrowsError(try TextFileDocumentIO.load(from: source)) { error in
                XCTAssertEqual(
                    error as? TextFileCodecError,
                    .ambiguousTextEncoding([.windows1250, .windows1251, .windows1252, .windows1254])
                )
            }

            var document = try TextFileDocumentIO.load(from: source, assuming: encoding)
            XCTAssertEqual(document.text, expectedText)
            XCTAssertEqual(document.encoding, encoding)
            document.text += "!"

            let result = try TextFileDocumentIO.save(document)
            XCTAssertEqual(result.document.encoding, encoding)
            XCTAssertEqual(try Data(contentsOf: source), windows + Data([0x21]))
        }

        let greek = Data([0xC1, 0xE1, 0xD9, 0xF9])
        let greekSource = try temporaryFile(data: greek)
        var selectedGreek = try TextFileDocumentIO.load(from: greekSource, assuming: .windows1253)
        XCTAssertEqual(selectedGreek.text, "ΑαΩω")
        XCTAssertEqual(selectedGreek.encoding, .windows1253)
        selectedGreek.text += "!"

        let greekResult = try TextFileDocumentIO.save(selectedGreek)
        XCTAssertNil(greekResult.warning)
        XCTAssertEqual(greekResult.document.encoding, .windows1253)
        XCTAssertEqual(try Data(contentsOf: greekSource), greek + Data([0x21]))
    }

    private func saveClean(_ document: TextFileDocument) throws -> URL {
        let result = try TextFileDocumentIO.save(document)
        XCTAssertNil(result.warning)
        return result.document.url
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
