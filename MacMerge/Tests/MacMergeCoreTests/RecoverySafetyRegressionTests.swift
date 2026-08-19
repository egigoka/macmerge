import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class RecoverySafetyRegressionTests: XCTestCase {
    func testCommittedCreateMutationNeverAdvertisesDestinationAsRecovery() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.txt")

        XCTAssertThrowsError(try TextFileDocumentIO.create(
            at: url,
            text: "created",
            beforePublishing: {},
            afterPublishing: { publishedURL in
                try Data("replacement".utf8).write(to: publishedURL, options: .atomic)
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
            XCTAssertFalse(error.localizedDescription.contains(url.path))
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("replacement".utf8))
    }

    func testBinaryRecoveryErrorDescriptionLabelsRecoveryCopy() {
        let path = "/tmp/fixture.bin.macmerge-recovery-test"

        XCTAssertEqual(
            BinaryFileDocumentError.saveOutcomeUncertain(path).errorDescription,
            "Save outcome could not be verified. Recovery copy: \(path)."
        )
    }

    func testBinaryUncoordinatedExternalEditIsPreservedInRecovery() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        let original = Data([0x00, 0x01, 0x02])
        let externalEdit = Data([0xAA, 0xBB, 0xCC])
        let macMergeEdit = Data([0x00, 0xFE, 0x02])
        try original.write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        let recoveryURL = try assertBinaryOutcomeUncertain {
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: { try externalEdit.write(to: url, options: .atomic) },
                afterReplacing: {}
            )
        }

        XCTAssertEqual(try Data(contentsOf: url), macMergeEdit)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), externalEdit)
        XCTAssertEqual(try artifactNames(in: directory), [recoveryURL.lastPathComponent])
        XCTAssertEqual(document.data, macMergeEdit)
        XCTAssertEqual(document.persistedData, original)
        XCTAssertTrue(document.isDirty)
    }

    func testBinaryReplacementFailureBeforeRecoveryCreationPreservesOriginalError() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        let original = Data([0x00, 0x01])
        try original.write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        XCTAssertThrowsError(
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {
                    let stagedURLs = try FileManager.default
                        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                        .filter {
                            $0.lastPathComponent.hasPrefix(".macmerge-binary-")
                                && $0.pathExtension == "tmp"
                        }
                    XCTAssertEqual(stagedURLs.count, 1)
                    guard let stagedURL = stagedURLs.first else { return }
                    try FileManager.default.removeItem(at: stagedURL)
                },
                afterReplacing: {}
            )
        ) { error in
            XCTAssertFalse(error is BinaryFileDocumentError, "Pre-replacement error was hidden: \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try artifactNames(in: directory), [])
        XCTAssertTrue(document.isDirty)
    }

    func testBinarySymlinkRetargetAfterReplacementReportsUncertainty() throws {
        let directory = try makeTemporaryDirectory()
        let firstTarget = directory.appending(path: "first.bin")
        let secondTarget = directory.appending(path: "second.bin")
        let link = directory.appending(path: "document.bin")
        let original = Data([0x10, 0x20])
        let macMergeEdit = Data([0x10, 0xFE])
        let secondUserData = Data([0xA0, 0xB0])
        try original.write(to: firstTarget)
        try secondUserData.write(to: secondTarget)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstTarget)
        var document = try BinaryFileDocumentIO.load(from: link)
        try document.replaceByte(at: 1, with: 0xFE)

        let recoveryURL = try assertBinaryOutcomeUncertain {
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {},
                afterReplacing: {
                    try FileManager.default.removeItem(at: link)
                    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secondTarget)
                }
            )
        }

        XCTAssertEqual(link.resolvingSymlinksInPath().standardizedFileURL, secondTarget.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: firstTarget), macMergeEdit)
        XCTAssertEqual(try Data(contentsOf: secondTarget), secondUserData)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), original)
        XCTAssertEqual(try artifactNames(in: directory), [recoveryURL.lastPathComponent])
        XCTAssertEqual(document.data, macMergeEdit)
        XCTAssertEqual(document.persistedData, original)
        XCTAssertTrue(document.isDirty)
    }

    func testBinaryMissingRecoveryArtifactIsNeverPromised() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        let preservedUserDataURL = directory.appending(path: "preserved-user-data.bin")
        let original = Data([0x10, 0x20])
        let macMergeEdit = Data([0x10, 0xFE])
        try original.write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)
        var removedRecoveryURL: URL?

        XCTAssertThrowsError(
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {},
                afterReplacing: {
                    let recoveryURLs = try recoveryArtifactURLs(in: directory)
                    XCTAssertEqual(recoveryURLs.count, 1)
                    guard let recoveryURL = recoveryURLs.first else { return }
                    try Data(contentsOf: recoveryURL).write(to: preservedUserDataURL)
                    try FileManager.default.removeItem(at: recoveryURL)
                    removedRecoveryURL = recoveryURL
                }
            )
        ) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }

        let recoveryURL = try XCTUnwrap(removedRecoveryURL)
        assertAbsentWithoutFollowingSymlinks(recoveryURL)
        XCTAssertEqual(try Data(contentsOf: url), macMergeEdit)
        XCTAssertEqual(try Data(contentsOf: preservedUserDataURL), original)
        XCTAssertEqual(try artifactNames(in: directory), [])
        XCTAssertEqual(document.data, macMergeEdit)
        XCTAssertEqual(document.persistedData, original)
        XCTAssertTrue(document.isDirty)
    }

    func testBinarySymlinkedRecoveryArtifactReportsPathlessUncertainty() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        let preservedUserDataURL = directory.appending(path: "preserved-user-data.bin")
        let original = Data([0x10, 0x20])
        let macMergeEdit = Data([0x10, 0xFE])
        try original.write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)
        var symlinkedRecoveryURL: URL?

        XCTAssertThrowsError(
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {},
                afterReplacing: {
                    let recoveryURLs = try recoveryArtifactURLs(in: directory)
                    XCTAssertEqual(recoveryURLs.count, 1)
                    guard let recoveryURL = recoveryURLs.first else { return }
                    try FileManager.default.moveItem(at: recoveryURL, to: preservedUserDataURL)
                    try FileManager.default.createSymbolicLink(
                        at: recoveryURL,
                        withDestinationURL: preservedUserDataURL
                    )
                    symlinkedRecoveryURL = recoveryURL
                }
            )
        ) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }

        let recoveryURL = try XCTUnwrap(symlinkedRecoveryURL)
        XCTAssertTrue(isSymbolicLinkWithoutFollowingSymlinks(recoveryURL))
        XCTAssertEqual(
            recoveryURL.resolvingSymlinksInPath().standardizedFileURL,
            preservedUserDataURL.standardizedFileURL
        )
        XCTAssertEqual(try Data(contentsOf: url), macMergeEdit)
        XCTAssertEqual(try Data(contentsOf: preservedUserDataURL), original)
        XCTAssertEqual(try artifactNames(in: directory), [recoveryURL.lastPathComponent])
        XCTAssertEqual(document.data, macMergeEdit)
        XCTAssertEqual(document.persistedData, original)
        XCTAssertTrue(document.isDirty)
    }

    func testTextUncertainOutcomePromisesOnlyVerifiedRecoveryPath() throws {
        let (url, document) = try editedTextDocument()
        let externalEdit = Data("external user data".utf8)
        var observedRecoveryURL: URL?

        XCTAssertThrowsError(
            try TextFileDocumentIO.save(document) { savedURL, recoveryURL in
                observedRecoveryURL = recoveryURL
                try externalEdit.write(to: savedURL, options: .atomic)
            }
        ) { error in
            guard case .saveOutcomeUncertain(let path) = error as? TextFileDocumentError else {
                return XCTFail("Expected uncertainty with verified recovery, got \(error)")
            }
            let promisedURL = URL(filePath: path)
            XCTAssertEqual(promisedURL, observedRecoveryURL)
            XCTAssertTrue(isRegularFileWithoutFollowingSymlinks(promisedURL))
            XCTAssertEqual(try? Data(contentsOf: promisedURL), Data("original user data".utf8))
        }

        XCTAssertEqual(try Data(contentsOf: url), externalEdit)
        let recoveryURL = try XCTUnwrap(observedRecoveryURL)
        XCTAssertEqual(try artifactNames(in: url.deletingLastPathComponent()), [recoveryURL.lastPathComponent])
        XCTAssertEqual(document.text, "MacMerge edit")
        XCTAssertEqual(document.persistedText, "original user data")
        XCTAssertEqual(document.persistedData, Data("original user data".utf8))
        XCTAssertTrue(document.isDirty)
    }

    func testTextMissingRecoveryArtifactReportsPathlessUncertainty() throws {
        let (url, document) = try editedTextDocument()
        let externalEdit = Data("external user data".utf8)
        var removedRecoveryURL: URL?

        XCTAssertThrowsError(
            try TextFileDocumentIO.save(document) { savedURL, recoveryURL in
                try FileManager.default.removeItem(at: recoveryURL)
                removedRecoveryURL = recoveryURL
                try externalEdit.write(to: savedURL, options: .atomic)
            }
        ) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }

        let recoveryURL = try XCTUnwrap(removedRecoveryURL)
        assertAbsentWithoutFollowingSymlinks(recoveryURL)
        XCTAssertEqual(try Data(contentsOf: url), externalEdit)
        XCTAssertEqual(try artifactNames(in: url.deletingLastPathComponent()), [])
        XCTAssertEqual(document.text, "MacMerge edit")
        XCTAssertEqual(document.persistedText, "original user data")
        XCTAssertEqual(document.persistedData, Data("original user data".utf8))
        XCTAssertTrue(document.isDirty)
    }

    func testTextSymlinkedRecoveryArtifactReportsPathlessUncertainty() throws {
        let (url, document) = try editedTextDocument()
        let directory = url.deletingLastPathComponent()
        let preservedUserDataURL = directory.appending(path: "preserved-user-data.txt")
        let externalEdit = Data("external user data".utf8)
        var symlinkedRecoveryURL: URL?

        XCTAssertThrowsError(
            try TextFileDocumentIO.save(document) { savedURL, recoveryURL in
                try FileManager.default.moveItem(at: recoveryURL, to: preservedUserDataURL)
                try FileManager.default.createSymbolicLink(
                    at: recoveryURL,
                    withDestinationURL: preservedUserDataURL
                )
                symlinkedRecoveryURL = recoveryURL
                try externalEdit.write(to: savedURL, options: .atomic)
            }
        ) { error in
            guard case .saveOutcomeUncertain(let path) = error as? TextFileDocumentError else {
                return XCTFail("Expected moved recovery, got \(error)")
            }
            XCTAssertEqual(
                URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL,
                preservedUserDataURL.resolvingSymlinksInPath().standardizedFileURL
            )
        }

        let recoveryURL = try XCTUnwrap(symlinkedRecoveryURL)
        XCTAssertTrue(isSymbolicLinkWithoutFollowingSymlinks(recoveryURL))
        XCTAssertEqual(
            recoveryURL.resolvingSymlinksInPath().standardizedFileURL,
            preservedUserDataURL.standardizedFileURL
        )
        XCTAssertEqual(try Data(contentsOf: url), externalEdit)
        XCTAssertEqual(try Data(contentsOf: preservedUserDataURL), Data("original user data".utf8))
        XCTAssertEqual(try artifactNames(in: directory), [recoveryURL.lastPathComponent])
        XCTAssertEqual(document.text, "MacMerge edit")
        XCTAssertEqual(document.persistedText, "original user data")
        XCTAssertEqual(document.persistedData, Data("original user data".utf8))
        XCTAssertTrue(document.isDirty)
    }

    private func editedTextDocument() throws -> (URL, TextFileDocument) {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.txt")
        try Data("original user data".utf8).write(to: url)
        var document = try TextFileDocumentIO.load(from: url)
        document.text = "MacMerge edit"
        return (url, document)
    }

    private func assertBinaryOutcomeUncertain<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) throws -> URL {
        do {
            _ = try operation()
            XCTFail("Expected uncertain binary save outcome", file: file, line: line)
            throw CocoaError(.fileWriteUnknown)
        } catch BinaryFileDocumentError.saveOutcomeUncertain(let path) {
            let recoveryURL = URL(filePath: path)
            XCTAssertTrue(
                isRegularFileWithoutFollowingSymlinks(recoveryURL),
                "Uncertain outcome promised unverified recovery path",
                file: file,
                line: line
            )
            return recoveryURL
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
            throw error
        }
    }

    private func isRegularFileWithoutFollowingSymlinks(_ url: URL) -> Bool {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        return result == 0 && information.st_mode & S_IFMT == S_IFREG
    }

    private func isSymbolicLinkWithoutFollowingSymlinks(_ url: URL) -> Bool {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        return result == 0 && information.st_mode & S_IFMT == S_IFLNK
    }

    private func assertAbsentWithoutFollowingSymlinks(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        let errorNumber = errno
        XCTAssertEqual(result, -1, "Expected path to be absent", file: file, line: line)
        XCTAssertEqual(errorNumber, ENOENT, "Expected lstat to fail with ENOENT", file: file, line: line)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func recoveryArtifactURLs(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".macmerge-recovery-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func artifactNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(".macmerge-") || $0.contains(".macmerge-recovery-") }
            .sorted()
    }
}
