import Foundation
@testable import MacMergeCore
import XCTest

final class TextFileDocumentTests: XCTestCase {
    func testEncodedFileLimitIsCheckedBeforeWriting() {
        XCTAssertThrowsError(try TextFileDocumentIO.validateEncodedSize(
            TextFileDocumentIO.maximumFileSize + 1
        )) { error in
            XCTAssertEqual(
                error as? TextFileDocumentError,
                .fileTooLarge(maximumBytes: TextFileDocumentIO.maximumFileSize)
            )
        }
    }

    func testCP50220SavePersistsCanonicalFullwidthText() throws {
        let url = try temporaryFile(data: Data([0x41]))
        var document = try TextFileDocumentIO.load(from: url, assuming: .iso2022JP)
        document.text = "ｱ"

        let result = try TextFileDocumentIO.save(document)

        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(result.document.text, "ア")
        XCTAssertEqual(result.document.persistedText, "ア")
        XCTAssertEqual(
            try Data(contentsOf: url),
            Data([0x1B, 0x24, 0x42, 0x25, 0x22, 0x1B, 0x28, 0x42])
        )
    }

    func testLoadEditAndSavePreservesEncodingMetadata() throws {
        let url = try temporaryFile(data: Data([0xEF, 0xBB, 0xBF]) + Data("old\r\n".utf8))
        var document = try TextFileDocumentIO.load(from: url)

        XCTAssertEqual(document.text, "old\r\n")
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertTrue(document.hasByteOrderMark)
        XCTAssertFalse(document.isDirty)

        document.text = "new\r\n"
        XCTAssertTrue(document.isDirty)
        let result = try TextFileDocumentIO.save(document)

        XCTAssertFalse(result.document.isDirty)
        XCTAssertNil(result.warning)
        XCTAssertEqual(try Data(contentsOf: url), Data([0xEF, 0xBB, 0xBF]) + Data("new\r\n".utf8))
    }

    func testSaveRejectsExternalChangesWithoutOverwritingThem() throws {
        let url = try temporaryFile(data: Data("original".utf8))
        var document = try TextFileDocumentIO.load(from: url)
        document.text = "MacMerge edit"
        try Data("external edit".utf8).write(to: url, options: .atomic)

        XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .changedOnDisk)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external edit")
    }

    func testSavingThroughSymlinkUpdatesTargetWithoutReplacingLink() throws {
        let target = try temporaryFile(data: Data("original".utf8))
        let link = target.deletingLastPathComponent().appending(path: "linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var document = try TextFileDocumentIO.load(from: link)
        document.text = "updated"

        _ = try TextFileDocumentIO.save(document)

        let values = try link.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertTrue(values.isSymbolicLink == true)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "updated")
    }

    func testCreatingThroughSymlinkUpdatesTargetWithoutReplacingLink() throws {
        let target = try temporaryFile(data: Data("original".utf8))
        let link = target.deletingLastPathComponent().appending(path: "created-through-link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let document = try TextFileDocumentIO.create(at: link, text: "created")

        let values = try link.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertTrue(values.isSymbolicLink == true)
        XCTAssertEqual(document.url, link)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "created")
    }

    func testSaveRejectsRetargetedSymlink() throws {
        let firstTarget = try temporaryFile(data: Data("first".utf8))
        let secondTarget = firstTarget.deletingLastPathComponent().appending(path: "second.txt")
        try Data("second".utf8).write(to: secondTarget)
        let link = firstTarget.deletingLastPathComponent().appending(path: "retargeted.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstTarget)
        var document = try TextFileDocumentIO.load(from: link)
        document.text = "MacMerge edit"
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secondTarget)

        XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .changedOnDisk)
        }
        XCTAssertEqual(try String(contentsOf: firstTarget, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: secondTarget, encoding: .utf8), "second")
    }

    func testEditingNoncanonicalCP932FailsInsteadOfRewritingAliases() throws {
        let original = Data([0xFA, 0x5C])
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url, assuming: .shiftJIS)
        document.text += "x"

        XCTAssertThrowsError(try TextFileDocumentIO.save(document)) { error in
            XCTAssertEqual(error as? TextFileCodecError, .encodingFailed(.shiftJIS))
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testLegacyFileSavePreservesDetectedCodepage() throws {
        let original = try XCTUnwrap("テスト\r\n".data(using: .shiftJIS))
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url, assuming: .shiftJIS)
        XCTAssertEqual(document.encoding, .shiftJIS)
        document.text = "テスト追加\r\n"

        _ = try TextFileDocumentIO.save(document)

        let expected = try XCTUnwrap("テスト追加\r\n".data(using: .shiftJIS))
        XCTAssertEqual(try Data(contentsOf: url), expected)
    }

    func testExplicitWindowsCodepageSavePreservesEncoding() throws {
        let original = Data([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x0D, 0x0A])
        let url = try temporaryFile(data: original)
        var document = try TextFileDocumentIO.load(from: url, assuming: .windows1251)
        XCTAssertEqual(document.text, "Привет\r\n")
        XCTAssertEqual(document.encoding, .windows1251)
        document.text = "Привет!\r\n"

        let result = try TextFileDocumentIO.save(document)

        XCTAssertEqual(result.document.encoding, .windows1251)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(
            try Data(contentsOf: url),
            Data([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x21, 0x0D, 0x0A])
        )
    }

    func testCanonicallyEquivalentScalarEditIsDirty() throws {
        let url = try temporaryFile(data: Data("café\n".utf8))
        var document = try TextFileDocumentIO.load(from: url)

        document.text = "cafe\u{301}\n"

        XCTAssertTrue(document.isDirty)
        _ = try TextFileDocumentIO.save(document)
        XCTAssertEqual(try Data(contentsOf: url), Data("cafe\u{301}\n".utf8))
    }

    func testCleanSaveAsPreservesExactBytesAndSource() throws {
        let original = Data([0xFA, 0x5C])
        let source = try temporaryFile(data: original)
        let destination = source.deletingLastPathComponent().appending(path: "copy.txt")
        let document = try TextFileDocumentIO.load(from: source, assuming: .shiftJIS)

        let saved = try TextFileDocumentIO.saveAs(document, to: destination).document

        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(saved.url, destination)
        XCTAssertFalse(saved.isDirty)
    }

    func testEditedSaveAsPreservesEncodingAndByteOrderMark() throws {
        let source = try temporaryFile(data: Data([0xEF, 0xBB, 0xBF]) + Data("old\r\n".utf8))
        let destination = source.deletingLastPathComponent().appending(path: "copy.txt")
        var document = try TextFileDocumentIO.load(from: source)
        document.text = "new\r\n"

        let saved = try TextFileDocumentIO.saveAs(document, to: destination).document

        XCTAssertEqual(try Data(contentsOf: source), Data([0xEF, 0xBB, 0xBF]) + Data("old\r\n".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data([0xEF, 0xBB, 0xBF]) + Data("new\r\n".utf8))
        XCTAssertEqual(saved.encoding, .utf8)
        XCTAssertTrue(saved.hasByteOrderMark)
        XCTAssertFalse(saved.isDirty)
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
