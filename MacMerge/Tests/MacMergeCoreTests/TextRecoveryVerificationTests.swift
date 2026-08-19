import Foundation
@testable import MacMergeCore
import XCTest

final class TextRecoveryVerificationTests: XCTestCase {
    func testUncertainSaveDoesNotPromiseMissingRecoveryCopy() throws {
        let (url, document) = try editedDocument()

        XCTAssertThrowsError(try TextFileDocumentIO.save(document) { savedURL, backupURL in
            try FileManager.default.removeItem(at: backupURL)
            try Data("intervening edit".utf8).write(to: savedURL, options: .atomic)
        }) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("intervening edit".utf8))
    }

    func testSuccessfulSaveDoesNotWarnAboutRemovedRecoveryCopy() throws {
        let (url, document) = try editedDocument()
        var removedBackupURL: URL?

        let result = try TextFileDocumentIO.save(document) { _, backupURL in
            try FileManager.default.removeItem(at: backupURL)
            removedBackupURL = backupURL
        }

        XCTAssertNil(result.warning)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(removedBackupURL).path))
    }

    func testUncertainSaveReportsVerifiedRecoveryCopy() throws {
        let (url, document) = try editedDocument()
        var retainedBackupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(document) { savedURL, backupURL in
            try Data("intervening edit".utf8).write(to: savedURL, options: .atomic)
            retainedBackupURL = backupURL
        }) { error in
            guard let path = retainedBackupURL?.path else {
                return XCTFail("Expected retained recovery URL")
            }
            XCTAssertEqual(
                error as? TextFileDocumentError,
                .saveOutcomeUncertain(path)
            )
        }

        let backupURL = try XCTUnwrap(retainedBackupURL)
        XCTAssertEqual(try Data(contentsOf: url), Data("intervening edit".utf8))
        XCTAssertEqual(try Data(contentsOf: backupURL), Data("original".utf8))
    }

    private func editedDocument() throws -> (url: URL, document: TextFileDocument) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.txt")
        try Data("original".utf8).write(to: url)
        var document = try TextFileDocumentIO.load(from: url)
        document.text = "saved edit"
        return (url, document)
    }
}
