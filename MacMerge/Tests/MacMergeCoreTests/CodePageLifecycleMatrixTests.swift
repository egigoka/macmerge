import Foundation
import MacMergeCore
import XCTest

final class CodePageLifecycleMatrixTests: XCTestCase {
    func testCanonicalCodePageLifecycleMatrix() throws {
        let root = try temporaryRoot(named: "canonical")

        for fixture in try canonicalFixtures() {
            let directory = root.appending(path: fixture.name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appending(path: "source.txt")
            try fixture.original.write(to: source)

            assertExplicitSelectionRequired(
                at: source,
                expected: fixture.ambiguityCandidates,
                fixture: fixture.name
            )
            var document = try TextFileDocumentIO.load(from: source, assuming: fixture.encoding)

            assertMetadata(document, fixture: fixture, expectedData: fixture.original)
            XCTAssertTrue(document.text.contains(fixture.expectedText), fixture.name)
            if fixture.repositoryFixture {
                XCTAssertTrue(document.text.hasSuffix("\r\n"), fixture.name)
            }

            let peer = try TextFileDocumentIO.load(from: source, assuming: fixture.encoding)
            assertUnchangedComparison(document.text, peer.text, fixture: fixture.name)

            let cleanSave = try TextFileDocumentIO.save(document)
            XCTAssertNil(cleanSave.warning, fixture.name)
            XCTAssertEqual(try Data(contentsOf: source), fixture.original, fixture.name)
            assertMetadata(cleanSave.document, fixture: fixture, expectedData: fixture.original)
            try assertArtifactInventory(in: directory, expected: ["source.txt"], fixture: fixture.name)

            let cleanCopy = directory.appending(path: "clean-copy.txt")
            let cleanSaveAs = try TextFileDocumentIO.saveAs(document, to: cleanCopy).document
            XCTAssertEqual(cleanSaveAs.url, cleanCopy, fixture.name)
            XCTAssertEqual(try Data(contentsOf: cleanCopy), fixture.original, fixture.name)
            assertMetadata(cleanSaveAs, fixture: fixture, expectedData: fixture.original)

            let reloadedCleanCopy = try TextFileDocumentIO.load(from: cleanCopy, assuming: fixture.encoding)
            XCTAssertEqual(try Data(contentsOf: cleanCopy), fixture.original, fixture.name)
            assertMetadata(reloadedCleanCopy, fixture: fixture, expectedData: fixture.original)
            assertScalarEquality(reloadedCleanCopy.text, document.text, fixture: fixture.name)
            try assertArtifactInventory(
                in: directory,
                expected: ["clean-copy.txt", "source.txt"],
                fixture: fixture.name
            )

            document = try TextFileDocumentIO.load(from: source, assuming: fixture.encoding)
            assertMetadata(document, fixture: fixture, expectedData: fixture.original)
            assertUnchangedComparison(cleanSave.document.text, document.text, fixture: fixture.name)

            let originalText = document.text
            document.text += fixture.editText
            XCTAssertTrue(document.isDirty, fixture.name)
            let editedRows = try LineDiff.compare(left: originalText, right: document.text)
            XCTAssertGreaterThan(DiffSummary(rows: editedRows).differences, 0, fixture.name)

            let expectedEditedData = fixture.original + fixture.editBytes
            let editedSave = try TextFileDocumentIO.save(document)
            XCTAssertNil(editedSave.warning, fixture.name)
            XCTAssertEqual(try Data(contentsOf: source), expectedEditedData, fixture.name)
            assertMetadata(editedSave.document, fixture: fixture, expectedData: expectedEditedData)
            try assertArtifactInventory(
                in: directory,
                expected: ["clean-copy.txt", "source.txt"],
                fixture: fixture.name
            )

            let reloaded = try TextFileDocumentIO.load(from: source, assuming: fixture.encoding)
            assertMetadata(reloaded, fixture: fixture, expectedData: expectedEditedData)
            assertScalarEquality(reloaded.text, document.text, fixture: fixture.name)
            assertUnchangedComparison(editedSave.document.text, reloaded.text, fixture: fixture.name)

            let secondCleanSave = try TextFileDocumentIO.save(reloaded)
            XCTAssertNil(secondCleanSave.warning, fixture.name)
            XCTAssertEqual(try Data(contentsOf: source), expectedEditedData, fixture.name)
            try assertArtifactInventory(
                in: directory,
                expected: ["clean-copy.txt", "source.txt"],
                fixture: fixture.name
            )

            var unrepresentable = reloaded
            unrepresentable.text += "🙂"
            let rejectedCopy = directory.appending(path: "unrepresentable-copy.txt")
            let rejectedCopySentinel = Data("preseeded destination".utf8)
            try rejectedCopySentinel.write(to: rejectedCopy)
            assertEncodingFailure(fixture.encoding, fixture: fixture.name) {
                try TextFileDocumentIO.save(unrepresentable)
            }
            assertEncodingFailure(fixture.encoding, fixture: fixture.name) {
                try TextFileDocumentIO.saveAs(unrepresentable, to: rejectedCopy)
            }
            XCTAssertEqual(try Data(contentsOf: source), expectedEditedData, fixture.name)
            XCTAssertEqual(try Data(contentsOf: rejectedCopy), rejectedCopySentinel, fixture.name)
            try assertArtifactInventory(
                in: directory,
                expected: ["clean-copy.txt", "source.txt", "unrepresentable-copy.txt"],
                fixture: fixture.name
            )
        }
    }

    func testNoncanonicalLegacyStreamsPreserveCleanBytesAndRejectEdits() throws {
        let fixtures: [(name: String, data: Data, encoding: TextFileEncoding, text: String)] = [
            ("CP932-alias", Data([0xFA, 0x5C]), .shiftJIS, "纊"),
            (
                "CP50220-JIS-C6226",
                Data([0x1B, 0x24, 0x40, 0x24, 0x22, 0x1B, 0x28, 0x42]),
                .iso2022JP,
                "あ"
            )
        ]
        let root = try temporaryRoot(named: "noncanonical")

        for fixture in fixtures {
            let directory = root.appending(path: fixture.name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appending(path: "source.txt")
            try fixture.data.write(to: source)

            var document = try TextFileDocumentIO.load(from: source, assuming: fixture.encoding)
            XCTAssertEqual(document.encoding, fixture.encoding, fixture.name)
            XCTAssertFalse(document.hasByteOrderMark, fixture.name)
            XCTAssertEqual(document.persistedData, fixture.data, fixture.name)
            assertScalarEquality(document.text, fixture.text, fixture: fixture.name)
            assertUnchangedComparison(document.text, fixture.text, fixture: fixture.name)

            let cleanSave = try TextFileDocumentIO.save(document)
            XCTAssertNil(cleanSave.warning, fixture.name)
            XCTAssertEqual(try Data(contentsOf: source), fixture.data, fixture.name)
            try assertArtifactInventory(in: directory, expected: ["source.txt"], fixture: fixture.name)

            let cleanCopy = directory.appending(path: "clean-copy.txt")
            let cleanSaveAs = try TextFileDocumentIO.saveAs(document, to: cleanCopy).document
            XCTAssertEqual(cleanSaveAs.url, cleanCopy, fixture.name)
            XCTAssertEqual(cleanSaveAs.persistedData, fixture.data, fixture.name)
            XCTAssertFalse(cleanSaveAs.isDirty, fixture.name)
            XCTAssertEqual(try Data(contentsOf: cleanCopy), fixture.data, fixture.name)

            let reloadedCleanCopy = try TextFileDocumentIO.load(from: cleanCopy, assuming: fixture.encoding)
            XCTAssertEqual(reloadedCleanCopy.encoding, fixture.encoding, fixture.name)
            XCTAssertEqual(reloadedCleanCopy.persistedData, fixture.data, fixture.name)
            XCTAssertFalse(reloadedCleanCopy.isDirty, fixture.name)
            assertScalarEquality(reloadedCleanCopy.text, fixture.text, fixture: fixture.name)
            XCTAssertEqual(try Data(contentsOf: cleanCopy), fixture.data, fixture.name)
            try assertArtifactInventory(
                in: directory,
                expected: ["clean-copy.txt", "source.txt"],
                fixture: fixture.name
            )

            document = cleanSave.document
            document.text += "!"
            let rejectedCopy = directory.appending(path: "edited-copy.txt")
            let rejectedCopySentinel = Data("preseeded destination".utf8)
            try rejectedCopySentinel.write(to: rejectedCopy)
            assertEncodingFailure(fixture.encoding, fixture: fixture.name) {
                try TextFileDocumentIO.save(document)
            }
            assertEncodingFailure(fixture.encoding, fixture: fixture.name) {
                try TextFileDocumentIO.saveAs(document, to: rejectedCopy)
            }
            XCTAssertEqual(try Data(contentsOf: source), fixture.data, fixture.name)
            XCTAssertEqual(try Data(contentsOf: rejectedCopy), rejectedCopySentinel, fixture.name)
            try assertArtifactInventory(
                in: directory,
                expected: ["clean-copy.txt", "edited-copy.txt", "source.txt"],
                fixture: fixture.name
            )

            let reloaded = try TextFileDocumentIO.load(from: source, assuming: fixture.encoding)
            XCTAssertEqual(reloaded.persistedData, fixture.data, fixture.name)
            assertScalarEquality(reloaded.text, fixture.text, fixture: fixture.name)
        }
    }

    private func canonicalFixtures() throws -> [Fixture] {
        let codePageRoot =
            repositoryRoot
            .appending(path: "Testing", directoryHint: .isDirectory)
            .appending(path: "Data", directoryHint: .isDirectory)
            .appending(path: "Codepages", directoryHint: .isDirectory)

        return [
            Fixture(
                name: "CP932",
                original: try repositoryFixture("CP932", under: codePageRoot),
                encoding: .shiftJIS,
                displayName: "Shift-JIS (CP932)",
                expectedText: "CP932テスト",
                editText: "// テスト\r\n",
                editBytes: Data([0x2F, 0x2F, 0x20, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67, 0x0D, 0x0A]),
                repositoryFixture: true,
                ambiguityCandidates: [
                    .shiftJIS, .windows1251, .windows1252, .windows1253, .windows1254
                ]
            ),
            Fixture(
                name: "CP51932",
                original: try repositoryFixture("CP51932", under: codePageRoot),
                encoding: .japaneseEUC,
                displayName: "EUC-JP (CP51932)",
                expectedText: "CP51932テスト",
                editText: "// テスト\r\n",
                editBytes: Data([0x2F, 0x2F, 0x20, 0xA5, 0xC6, 0xA5, 0xB9, 0xA5, 0xC8, 0x0D, 0x0A]),
                repositoryFixture: true,
                ambiguityCandidates: [
                    .shiftJIS, .japaneseEUC, .windows1250, .windows1251, .windows1252, .windows1253,
                    .windows1254
                ]
            ),
            Fixture(
                name: "CP50220",
                original: try repositoryFixture("CP50220", under: codePageRoot),
                encoding: .iso2022JP,
                displayName: "ISO-2022-JP (CP50220)",
                expectedText: "CP50220テスト",
                editText: "// テスト\r\n",
                editBytes: Data([
                    0x2F, 0x2F, 0x20, 0x1B, 0x24, 0x42, 0x25, 0x46, 0x25, 0x39, 0x25, 0x48,
                    0x1B, 0x28, 0x42, 0x0D, 0x0A
                ]),
                repositoryFixture: true,
                ambiguityCandidates: [.utf8, .iso2022JP]
            ),
            Fixture(
                name: "CP1250",
                original: Data([
                    0xBE, 0x9A, 0xE8, 0x9D, 0x9E, 0xFD, 0xE1, 0xED, 0xE9, 0xFA, 0xE4, 0xF4,
                    0x20, 0xBC, 0x8A, 0xC8, 0x8D, 0x8E, 0xDD, 0xC1, 0xCD, 0xC9, 0xDA, 0xC4, 0xD4
                ]),
                encoding: .windows1250,
                displayName: "Central European (CP1250)",
                expectedText: "ľščťžýáíéúäô ĽŠČŤŽÝÁÍÉÚÄÔ",
                editText: " ž",
                editBytes: Data([0x20, 0x9E]),
                repositoryFixture: false,
                ambiguityCandidates: [.windows1250, .windows1251]
            ),
            Fixture(
                name: "CP1251",
                original: Data(0xE1...0xFF),
                encoding: .windows1251,
                displayName: "Cyrillic (CP1251)",
                expectedText: "бвгдежзийклмнопрстуфхцчшщъыьэюя",
                editText: " Я",
                editBytes: Data([0x20, 0xDF]),
                repositoryFixture: false,
                ambiguityCandidates: [.windows1250, .windows1251, .windows1252, .windows1254]
            ),
            Fixture(
                name: "CP1252",
                original: Data([0x80, 0x8A, 0x8C, 0x9A, 0x9C, 0x9F]),
                encoding: .windows1252,
                displayName: "Western European (CP1252)",
                expectedText: "€ŠŒšœŸ",
                editText: " é",
                editBytes: Data([0x20, 0xE9]),
                repositoryFixture: false,
                ambiguityCandidates: [.windows1250, .windows1251, .windows1252, .windows1254]
            ),
            Fixture(
                name: "CP1253",
                original: Data([0xA2, 0xC1, 0xE1, 0xD9, 0xF9, 0xFE]),
                encoding: .windows1253,
                displayName: "Greek (CP1253)",
                expectedText: "ΆΑαΩωώ",
                editText: " β",
                editBytes: Data([0x20, 0xE2]),
                repositoryFixture: false,
                ambiguityCandidates: [
                    .japaneseEUC, .windows1250, .windows1251, .windows1252, .windows1253, .windows1254
                ]
            ),
            Fixture(
                name: "CP1254",
                original: Data([0xD0, 0xDD, 0xDE, 0xF0, 0xFD, 0xFE]),
                encoding: .windows1254,
                displayName: "Turkish (CP1254)",
                expectedText: "ĞİŞğış",
                editText: " ç",
                editBytes: Data([0x20, 0xE7]),
                repositoryFixture: false,
                ambiguityCandidates: [
                    .windows1250, .windows1251, .windows1252, .windows1253, .windows1254
                ]
            )
        ]
    }

    private func repositoryFixture(_ codePage: String, under root: URL) throws -> Data {
        let url =
            root
            .appending(path: codePage, directoryHint: .isDirectory)
            .appending(path: "DiffItem.h")
        return try Data(contentsOf: url)
    }

    private func assertExplicitSelectionRequired(
        at url: URL,
        expected expectedEncodings: [TextFileEncoding],
        fixture: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try TextFileDocumentIO.load(from: url), fixture, file: file, line: line) { error in
            guard case .ambiguousTextEncoding(let encodings) = error as? TextFileCodecError else {
                return XCTFail("\(fixture): expected ambiguity, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(encodings, expectedEncodings, fixture, file: file, line: line)
        }
    }

    private func assertArtifactInventory(
        in directory: URL,
        expected: [String],
        fixture: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()
        XCTAssertEqual(entries, expected.sorted(), fixture, file: file, line: line)
    }

    private func assertMetadata(
        _ document: TextFileDocument,
        fixture: Fixture,
        expectedData: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(document.encoding, fixture.encoding, fixture.name, file: file, line: line)
        XCTAssertEqual(document.encoding.displayName, fixture.displayName, fixture.name, file: file, line: line)
        XCTAssertFalse(document.hasByteOrderMark, fixture.name, file: file, line: line)
        XCTAssertFalse(document.isDirty, fixture.name, file: file, line: line)
        XCTAssertEqual(document.persistedData, expectedData, fixture.name, file: file, line: line)
        assertScalarEquality(document.text, document.persistedText, fixture: fixture.name, file: file, line: line)
    }

    private func assertUnchangedComparison(
        _ left: String,
        _ right: String,
        fixture: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let rows = try LineDiff.compare(left: left, right: right)
            XCTAssertFalse(rows.isEmpty, fixture, file: file, line: line)
            XCTAssertTrue(rows.allSatisfy { $0.kind == .unchanged }, fixture, file: file, line: line)
            XCTAssertEqual(DiffSummary(rows: rows).differences, 0, fixture, file: file, line: line)
        } catch {
            XCTFail("\(fixture): comparison failed: \(error)", file: file, line: line)
        }
    }

    private func assertScalarEquality(
        _ actual: String,
        _ expected: String,
        fixture: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.unicodeScalars.map(\.value),
            expected.unicodeScalars.map(\.value),
            fixture,
            file: file,
            line: line
        )
    }

    private func assertEncodingFailure<T>(
        _ encoding: TextFileEncoding,
        fixture: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), fixture, file: file, line: line) { error in
            XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(encoding), fixture, file: file, line: line)
        }
    }

    private func temporaryRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "MacMerge-CodePageLifecycleMatrixTests-\(name)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct Fixture {
        let name: String
        let original: Data
        let encoding: TextFileEncoding
        let displayName: String
        let expectedText: String
        let editText: String
        let editBytes: Data
        let repositoryFixture: Bool
        let ambiguityCandidates: [TextFileEncoding]
    }
}
