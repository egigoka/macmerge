import Foundation
import MacMergeCore
import XCTest

final class CodePageLifecycleRegressionTests: XCTestCase {
    func testFreshCP1250CreateSaveAsReloadPreservesExactBytes() throws {
        let root = try temporaryRoot()
        let sourceURL = root.appending(path: "source.txt")
        let destinationURL = root.appending(path: "fresh-copy.txt")
        let expectedBytes = Data([0xBE, 0x9A, 0xE8, 0x9D, 0x9E, 0x21, 0x0D, 0x0A])
        let text = "ľščťž!\r\n"

        let document = try TextFileDocumentIO.create(
            at: sourceURL,
            text: text,
            encoding: .windows1250
        )

        XCTAssertEqual(document.url, sourceURL)
        XCTAssertEqual(document.persistedData, expectedBytes)
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try Data(contentsOf: sourceURL), expectedBytes)

        let saved = try TextFileDocumentIO.saveAs(document, to: destinationURL).document
        let reloaded = try TextFileDocumentIO.load(from: destinationURL, assuming: .windows1250)

        XCTAssertEqual(try Data(contentsOf: sourceURL), expectedBytes)
        XCTAssertEqual(try Data(contentsOf: destinationURL), expectedBytes)
        XCTAssertEqual(saved.url, destinationURL)
        XCTAssertEqual(saved.persistedData, expectedBytes)
        XCTAssertFalse(saved.isDirty)
        XCTAssertEqual(reloaded.url, destinationURL)
        XCTAssertEqual(reloaded.persistedData, expectedBytes)
        XCTAssertEqual(reloaded.text, text)
        XCTAssertEqual(reloaded.encoding, .windows1250)
        XCTAssertFalse(reloaded.hasByteOrderMark)
        XCTAssertFalse(reloaded.isDirty)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(),
            ["fresh-copy.txt", "source.txt"]
        )
    }

    func testDirectoryDestinationRejectionPreservesSourceAndLeavesNoArtifacts() throws {
        let root = try temporaryRoot()
        let sourceURL = root.appending(path: "source.txt")
        let destinationURL = root.appending(path: "existing", directoryHint: .isDirectory)
        let sentinelURL = destinationURL.appending(path: "sentinel.txt")
        let sourceBytes = Data([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2])
        let sentinelBytes = Data("existing destination".utf8)
        try sourceBytes.write(to: sourceURL)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: false)
        try sentinelBytes.write(to: sentinelURL)
        var document = try TextFileDocumentIO.load(from: sourceURL, assuming: .windows1251)
        document.text += "!"

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(document, to: destinationURL)) { error in
            let cocoaError = error as NSError
            XCTAssertEqual(cocoaError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(cocoaError.code, CocoaError.Code.fileWriteUnsupportedScheme.rawValue)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: sentinelURL), sentinelBytes)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(),
            ["existing", "source.txt"]
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destinationURL.path).sorted(),
            ["sentinel.txt"]
        )
    }

    func testAmbiguityCandidatesRetainExactDetectionOrder() throws {
        let root = try temporaryRoot()
        let url = root.appending(path: "ambiguous.txt")
        let bytes = Data([0xA4, 0xA2])
        try bytes.write(to: url)

        XCTAssertThrowsError(try TextFileDocumentIO.load(from: url)) { error in
            XCTAssertEqual(
                error as? TextFileCodecError,
                .ambiguousTextEncoding([
                    .shiftJIS,
                    .japaneseEUC,
                    .windows1250,
                    .windows1251,
                    .windows1252,
                    .windows1253,
                    .windows1254,
                ])
            )
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "MacMerge-CodePageLifecycleRegressionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }
}
