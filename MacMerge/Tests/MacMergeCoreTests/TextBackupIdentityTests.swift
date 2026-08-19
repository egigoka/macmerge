import Foundation
@testable import MacMergeCore
import XCTest

final class TextBackupIdentityTests: XCTestCase {
    func testExternalEditInSnapshotToReplaceGapIsPreservedAsRecoveryWarning() throws {
        let (url, document) = try editedDocument()
        let externalEdit = Data("external".utf8)
        var backupURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            replaceItem: { originalURL, newURL, backupItemName in
                let handle = try FileHandle(forWritingTo: originalURL)
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: externalEdit)
                try handle.synchronize()
                try handle.close()
                backupURL = originalURL.deletingLastPathComponent()
                    .appending(path: backupItemName)
                return try FileManager.default.replaceItemAt(
                    originalURL,
                    withItemAt: newURL,
                    backupItemName: backupItemName,
                    options: .withoutDeletingBackupItem
                )
            },
            afterReplacing: { _, _ in }
        )

        let recoveryURL = try XCTUnwrap(backupURL)
        XCTAssertEqual(result.warning, .recoveryCopyPreserved(recoveryURL.path))
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: recoveryURL), externalEdit)
    }

    func testMovedExternalEditBackupUsesStableReferenceWarning() throws {
        let (url, document) = try editedDocument()
        let externalEdit = Data("external".utf8)
        let retainedDirectory = url.deletingLastPathComponent()
            .appending(path: "retained", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: retainedDirectory, withIntermediateDirectories: false)
        let movedRecoveryURL = retainedDirectory.appending(path: "external-recovery")

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {
                try externalEdit.write(to: url, options: .atomic)
            },
            afterReplacing: { _, backupURL in
                try FileManager.default.moveItem(at: backupURL, to: movedRecoveryURL)
            }
        )

        guard case .recoveryCopyPreserved(let warningPath) = result.warning else {
            return XCTFail("Expected moved recovery warning")
        }
        XCTAssertEqual(
            URL(filePath: warningPath).resolvingSymlinksInPath().standardizedFileURL,
            movedRecoveryURL.resolvingSymlinksInPath().standardizedFileURL
        )
        XCTAssertEqual(try Data(contentsOf: movedRecoveryURL), externalEdit)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
    }

    func testSameByteInodeSwapInSnapshotToReplaceGapPreservesBackup() throws {
        let (url, document) = try editedDocument()
        let initialInode = try inode(at: url)
        var backupURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {
                try document.persistedData.write(to: url, options: .atomic)
                XCTAssertNotEqual(try inode(at: url), initialInode)
            },
            replaceItem: { originalURL, newURL, backupItemName in
                backupURL = originalURL.deletingLastPathComponent()
                    .appending(path: backupItemName)
                return try FileManager.default.replaceItemAt(
                    originalURL,
                    withItemAt: newURL,
                    backupItemName: backupItemName,
                    options: .withoutDeletingBackupItem
                )
            },
            afterReplacing: { _, _ in }
        )

        let recoveryURL = try XCTUnwrap(backupURL)
        XCTAssertEqual(result.warning, .recoveryCopyPreserved(recoveryURL.path))
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        XCTAssertEqual(try Data(contentsOf: recoveryURL), document.persistedData)
    }

    func testSameByteTargetSwapAfterReplacementReportsUncertainty() throws {
        let (url, document) = try editedDocument()
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(document) { savedURL, candidateBackupURL in
            backupURL = candidateBackupURL
            let savedData = try Data(contentsOf: savedURL)
            let originalInode = try inode(at: savedURL)
            try savedData.write(to: savedURL, options: .atomic)
            XCTAssertNotEqual(try inode(at: savedURL), originalInode)
        }) { error in
            guard let backupURL else { return XCTFail("Expected backup URL") }
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertain(backupURL.path))
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), document.persistedData)
    }

    func testForeignStagedReplacementIsNotRenamedOrDeletedByCleanup() throws {
        let (url, document) = try editedDocument()
        let foreignData = Data("foreign staged replacement".utf8)
        var stagedURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: {
                let candidates = try FileManager.default.contentsOfDirectory(
                    at: url.deletingLastPathComponent(),
                    includingPropertiesForKeys: nil
                ).filter { $0.lastPathComponent.hasPrefix(".macmerge-") && $0.pathExtension == "tmp" }
                let candidate = try XCTUnwrap(candidates.first)
                XCTAssertEqual(candidates.count, 1)
                try FileManager.default.removeItem(at: candidate)
                try foreignData.write(to: candidate)
                stagedURL = candidate
            },
            afterReplacing: { _, _ in XCTFail("Replacement must not run") }
        ))

        let retainedURL = try XCTUnwrap(stagedURL)
        XCTAssertEqual(try Data(contentsOf: url), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: retainedURL), foreignData)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .contains { $0.hasPrefix(".macmerge-cleanup-") })
    }

    func testSameStorageSaveAsUsesRequestedSymlinkAndPreservesVerifiedWarning() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "target.txt")
        let sourceLink = directory.appending(path: "source-link.txt")
        let destinationLink = directory.appending(path: "destination-link.txt")
        try Data("original".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: destinationLink, withDestinationURL: target)
        var document = try TextFileDocumentIO.load(from: sourceLink)
        document.text = "saved edit"
        var recoveryURL: URL?

        let result = try TextFileDocumentIO.saveAs(
            document,
            to: destinationLink,
            beforePublishing: {},
            afterPublishing: { _ in },
            saveSameStorage: { candidate in
                try TextFileDocumentIO.save(
                    candidate,
                    beforeReplacing: {},
                    afterReplacing: { _, candidateRecoveryURL in
                        recoveryURL = candidateRecoveryURL
                    },
                    afterVerifyingRecovery: { _ in
                        throw CocoaError(.fileWriteUnknown)
                    }
                )
            }
        )

        let retainedRecoveryURL = try XCTUnwrap(recoveryURL)
        XCTAssertEqual(result.document.url, destinationLink)
        XCTAssertEqual(result.document.storageURL, target.standardizedFileURL)
        XCTAssertEqual(result.warning, .recoveryCopyPreserved(retainedRecoveryURL.path))
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: target), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: retainedRecoveryURL), Data("original".utf8))
    }

    func testSameStorageSaveAsRejectsWarningWithoutRetainedMetadata() throws {
        let directory = try makeTemporaryDirectory()
        let target = directory.appending(path: "target.txt")
        let sourceLink = directory.appending(path: "source-link.txt")
        let destinationLink = directory.appending(path: "destination-link.txt")
        let unverifiedPath = directory.appending(path: "unverified-recovery").path
        try Data("original".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: destinationLink, withDestinationURL: target)
        var document = try TextFileDocumentIO.load(from: sourceLink)
        document.text = "saved edit"

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationLink,
            beforePublishing: {},
            afterPublishing: { _ in },
            saveSameStorage: { candidate in
                let saved = try TextFileDocumentIO.save(candidate)
                return TextFileSaveResult(
                    document: saved.document,
                    warning: .recoveryCopyPreserved(unverifiedPath)
                )
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
            XCTAssertFalse(error.localizedDescription.contains(unverifiedPath))
        }

        XCTAssertEqual(try Data(contentsOf: target), Data("saved edit".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unverifiedPath))
    }

    func testSameStorageSaveAsRejectsWarningAfterRetainedFileSubstitution() throws {
        let directory = try makeTemporaryDirectory()
        let target = directory.appending(path: "target.txt")
        let sourceLink = directory.appending(path: "source-link.txt")
        let destinationLink = directory.appending(path: "destination-link.txt")
        let foreignData = Data("foreign replacement".utf8)
        try Data("original".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: destinationLink, withDestinationURL: target)
        var document = try TextFileDocumentIO.load(from: sourceLink)
        document.text = "saved edit"
        var recoveryURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationLink,
            beforePublishing: {},
            afterPublishing: { _ in },
            saveSameStorage: { candidate in
                let result = try TextFileDocumentIO.save(
                    candidate,
                    beforeReplacing: {},
                    afterReplacing: { _, candidateRecoveryURL in
                        recoveryURL = candidateRecoveryURL
                    },
                    afterVerifyingRecovery: { _ in
                        throw CocoaError(.fileWriteUnknown)
                    }
                )
                let retainedURL = try XCTUnwrap(recoveryURL)
                try FileManager.default.removeItem(at: retainedURL)
                try foreignData.write(to: retainedURL)
                return result
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
            if let recoveryURL {
                XCTAssertFalse(error.localizedDescription.contains(recoveryURL.path))
            }
        }

        XCTAssertEqual(try Data(contentsOf: target), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(recoveryURL)), foreignData)
    }

    func testSameStorageSaveAsRejectsDestinationSymlinkRetargetAfterSave() throws {
        let directory = try makeTemporaryDirectory()
        let firstTarget = directory.appending(path: "first.txt")
        let secondTarget = directory.appending(path: "second.txt")
        let sourceLink = directory.appending(path: "source-link.txt")
        let destinationLink = directory.appending(path: "destination-link.txt")
        try Data("original".utf8).write(to: firstTarget)
        try Data("unrelated".utf8).write(to: secondTarget)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: firstTarget)
        try FileManager.default.createSymbolicLink(at: destinationLink, withDestinationURL: firstTarget)
        var document = try TextFileDocumentIO.load(from: sourceLink)
        document.text = "saved edit"

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationLink,
            beforePublishing: {},
            afterPublishing: { _ in },
            saveSameStorage: { candidate in
                let result = try TextFileDocumentIO.save(candidate)
                try FileManager.default.removeItem(at: destinationLink)
                try FileManager.default.createSymbolicLink(at: destinationLink, withDestinationURL: secondTarget)
                return result
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }

        XCTAssertEqual(try Data(contentsOf: firstTarget), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: secondTarget), Data("unrelated".utf8))
        XCTAssertEqual(destinationLink.resolvingSymlinksInPath().standardizedFileURL, secondTarget.standardizedFileURL)
    }

    func testSameStorageSaveAsRejectsSameByteInodeReplacementAndPreservesRecoveryTruth() throws {
        let directory = try makeTemporaryDirectory()
        let target = directory.appending(path: "target.txt")
        let sourceLink = directory.appending(path: "source-link.txt")
        let destinationLink = directory.appending(path: "destination-link.txt")
        try Data("original".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: destinationLink, withDestinationURL: target)
        var document = try TextFileDocumentIO.load(from: sourceLink)
        document.text = "saved edit"
        var recoveryURL: URL?
        var replacementInode: NSNumber?

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationLink,
            beforePublishing: {},
            afterPublishing: { _ in },
            saveSameStorage: { candidate in
                let result = try TextFileDocumentIO.save(
                    candidate,
                    beforeReplacing: {},
                    afterReplacing: { _, candidateRecoveryURL in
                        recoveryURL = candidateRecoveryURL
                    },
                    afterVerifyingRecovery: { _ in
                        throw CocoaError(.fileWriteUnknown)
                    }
                )
                let committedInode = try inode(at: target)
                try result.document.persistedData.write(to: target, options: .atomic)
                replacementInode = try inode(at: target)
                XCTAssertNotEqual(replacementInode, committedInode)
                return result
            }
        )) { error in
            guard let recoveryURL else { return XCTFail("Expected retained recovery URL") }
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertain(recoveryURL.path))
        }

        XCTAssertEqual(try inode(at: target), try XCTUnwrap(replacementInode))
        XCTAssertEqual(try Data(contentsOf: target), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(recoveryURL)), Data("original".utf8))
    }

    func testReplaceErrorAfterTargetAndBackupMutationReportsVerifiedRecovery() throws {
        let (url, document) = try editedDocument()
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            replaceItem: { originalURL, newURL, backupItemName in
                let candidateBackupURL = originalURL.deletingLastPathComponent()
                    .appending(path: backupItemName)
                backupURL = candidateBackupURL
                try FileManager.default.moveItem(at: originalURL, to: candidateBackupURL)
                try FileManager.default.moveItem(at: newURL, to: originalURL)
                throw CocoaError(.fileWriteUnknown)
            },
            afterReplacing: { _, _ in XCTFail("Replacement error must skip success hook") }
        )) { error in
            guard let backupURL else { return XCTFail("Expected backup URL") }
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertain(backupURL.path))
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), Data("original".utf8))
    }

    func testReplaceErrorWithUnrelatedBackupReportsPathlessUncertainty() throws {
        let (url, document) = try editedDocument()
        let unrelated = Data("unrelated".utf8)
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            replaceItem: { originalURL, newURL, backupItemName in
                let candidateBackupURL = originalURL.deletingLastPathComponent()
                    .appending(path: backupItemName)
                backupURL = candidateBackupURL
                try FileManager.default.moveItem(at: originalURL, to: candidateBackupURL)
                try FileManager.default.moveItem(at: newURL, to: originalURL)
                try FileManager.default.removeItem(at: candidateBackupURL)
                try unrelated.write(to: candidateBackupURL)
                throw CocoaError(.fileWriteUnknown)
            },
            afterReplacing: { _, _ in XCTFail("Replacement error must skip success hook") }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), unrelated)
    }

    func testReplaceErrorAfterCommittedTargetWithoutBackupIsPathlessUncertainty() throws {
        let (url, document) = try editedDocument()

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            replaceItem: { originalURL, newURL, _ in
                try Data(contentsOf: newURL).write(to: originalURL, options: .atomic)
                throw CocoaError(.fileWriteUnknown)
            },
            afterReplacing: { _, _ in XCTFail("Replacement error must skip success hook") }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
    }

    func testCleanSaveCreatesNoRecoveryAndSkipsReplacement() throws {
        let (url, editedDocument) = try editedDocument()
        var document = editedDocument
        document.text = document.persistedText

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            replaceItem: { _, _, _ in
                XCTFail("Clean save must not replace target")
                return nil
            },
            afterReplacing: { _, _ in XCTFail("Clean save must not create recovery") }
        )

        XCTAssertNil(result.warning)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("original".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path),
            [url.lastPathComponent]
        )
    }

    func testRemovedBackupAfterConcurrentEditReturnsSavedResult() throws {
        let (url, document) = try editedDocument()
        let concurrentEdit = Data("concurrent edit".utf8)
        var backupURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: { try concurrentEdit.write(to: url, options: .atomic) },
            afterReplacing: { _, candidateBackupURL in
                backupURL = candidateBackupURL
                try FileManager.default.removeItem(at: candidateBackupURL)
            }
        )

        XCTAssertNil(result.warning)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(backupURL).path))
    }

    func testMismatchedRegularBackupWarnsWithoutAdvertisingRecovery() throws {
        let (url, document) = try editedDocument()
        let concurrentEdit = Data("concurrent edit".utf8)
        var backupURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: { try concurrentEdit.write(to: url, options: .atomic) },
            afterReplacing: { _, candidateBackupURL in backupURL = candidateBackupURL }
        )

        let preservedBackupURL = try XCTUnwrap(backupURL)
        XCTAssertEqual(result.warning, .recoveryCopyPreserved(preservedBackupURL.path))
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: preservedBackupURL), concurrentEdit)
        XCTAssertFalse(result.warning?.localizedDescription.contains("recovery copy") == true)
    }

    func testSameByteBackupInodeSwapPreservesAndAdvertisesRecovery() throws {
        let (url, document) = try editedDocument()
        let concurrentEdit = Data("concurrent edit".utf8)
        var backupURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: { try concurrentEdit.write(to: url, options: .atomic) },
            afterReplacing: { _, candidateBackupURL in
                backupURL = candidateBackupURL
                let displacedData = try Data(contentsOf: candidateBackupURL)
                let originalInode = try inode(at: candidateBackupURL)
                let swappedURL = candidateBackupURL.deletingLastPathComponent()
                    .appending(path: ".same-byte-swap-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: swappedURL) }
                try displacedData.write(to: swappedURL)
                XCTAssertNotEqual(try inode(at: swappedURL), originalInode)
                try FileManager.default.removeItem(at: candidateBackupURL)
                try FileManager.default.moveItem(at: swappedURL, to: candidateBackupURL)
            }
        )

        let recoveryURL = try XCTUnwrap(backupURL)
        XCTAssertEqual(result.warning, .recoveryCopyPreserved(recoveryURL.path))
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: recoveryURL), concurrentEdit)
    }

    func testMismatchedBackupInodeSwapReportsPathlessUncertainty() throws {
        let (url, document) = try editedDocument()
        let concurrentEdit = Data("concurrent edit".utf8)
        let unrelated = Data("unrelated".utf8)
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: { try concurrentEdit.write(to: url, options: .atomic) },
            afterReplacing: { _, candidateBackupURL in
                backupURL = candidateBackupURL
                let originalInode = try inode(at: candidateBackupURL)
                let swappedURL = candidateBackupURL.deletingLastPathComponent()
                    .appending(path: ".mismatched-swap-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: swappedURL) }
                try unrelated.write(to: swappedURL)
                XCTAssertNotEqual(try inode(at: swappedURL), originalInode)
                try FileManager.default.removeItem(at: candidateBackupURL)
                try FileManager.default.moveItem(at: swappedURL, to: candidateBackupURL)
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
            if let backupURL {
                XCTAssertFalse(error.localizedDescription.contains(backupURL.path))
            }
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), unrelated)
    }

    func testConcurrentDisplacedEditIsAdvertisedWhenTargetVerificationFails() throws {
        let (url, document) = try editedDocument()
        let concurrentEdit = Data("concurrent edit".utf8)
        let targetEdit = Data("target edit".utf8)
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: { try concurrentEdit.write(to: url, options: .atomic) },
            afterReplacing: { savedURL, candidateBackupURL in
                backupURL = candidateBackupURL
                try targetEdit.write(to: savedURL, options: .atomic)
            }
        )) { error in
            guard let backupURL else { return XCTFail("Expected backup URL") }
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertain(backupURL.path))
        }

        XCTAssertEqual(try Data(contentsOf: url), targetEdit)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), concurrentEdit)
    }

    func testStaleWarningArtifactIsNotPromotedToPromisedRecovery() throws {
        let (url, document) = try editedDocument()
        let concurrentEdit = Data("concurrent edit".utf8)
        let unrelated = Data("unrelated artifact".utf8)
        let targetEdit = Data("target edit".utf8)
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: { try concurrentEdit.write(to: url, options: .atomic) },
            afterReplacing: { _, candidateBackupURL in backupURL = candidateBackupURL },
            beforeFinalVerification: {
                try unrelated.write(to: try XCTUnwrap(backupURL), options: .atomic)
                try targetEdit.write(to: url, options: .atomic)
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
            if let backupURL {
                XCTAssertFalse(error.localizedDescription.contains(backupURL.path))
            }
        }

        XCTAssertEqual(try Data(contentsOf: url), targetEdit)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), unrelated)
    }

    func testThrowingFinalVerificationHookReportsVerifiedRecovery() throws {
        let (url, document) = try editedDocument()
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            afterReplacing: { _, candidateBackupURL in backupURL = candidateBackupURL },
            beforeFinalVerification: { throw CocoaError(.fileWriteUnknown) }
        )) { error in
            guard let backupURL else { return XCTFail("Expected retained recovery URL") }
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertain(backupURL.path))
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), Data("original".utf8))
    }

    func testThrowingFinalVerificationHookReportsPathlessUncertaintyAfterRecoveryRemoval() throws {
        let (url, document) = try editedDocument()
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            afterReplacing: { _, candidateBackupURL in backupURL = candidateBackupURL },
            beforeFinalVerification: {
                try FileManager.default.removeItem(at: try XCTUnwrap(backupURL))
                throw CocoaError(.fileWriteUnknown)
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
            if let backupURL {
                XCTAssertFalse(error.localizedDescription.contains(backupURL.path))
            }
        }

        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(backupURL).path))
    }

    func testMismatchedBackupAfterConcurrentEditReportsPathlessUncertainty() throws {
        let (url, document) = try editedDocument()
        let concurrentEdit = Data("concurrent edit".utf8)
        let targetEdit = Data("target edit".utf8)
        let replacement = Data("unrelated replacement".utf8)
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(
            document,
            beforeReplacing: { try concurrentEdit.write(to: url, options: .atomic) },
            afterReplacing: { savedURL, candidateBackupURL in
                try targetEdit.write(to: savedURL, options: .atomic)
                try FileManager.default.removeItem(at: candidateBackupURL)
                try replacement.write(to: candidateBackupURL)
                backupURL = candidateBackupURL
            }
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
            if let backupURL {
                XCTAssertFalse(error.localizedDescription.contains(backupURL.path))
            }
        }

        XCTAssertEqual(try Data(contentsOf: url), targetEdit)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), replacement)
    }

    func testVerifiedBackupWithPersistedBytesIsAdvertised() throws {
        let (url, document) = try editedDocument()
        let externalEdit = Data("external edit".utf8)
        var backupURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.save(document) { savedURL, candidateBackupURL in
            backupURL = candidateBackupURL
            try externalEdit.write(to: savedURL, options: .atomic)
        }) { error in
            guard let backupURL else { return XCTFail("Expected backup URL") }
            XCTAssertEqual(error as? TextFileDocumentError, .saveOutcomeUncertain(backupURL.path))
        }

        XCTAssertEqual(try Data(contentsOf: url), externalEdit)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backupURL)), document.persistedData)
    }

    func testOrdinarySaveRemovesVerifiedRecoveryWithoutWarning() throws {
        let (url, document) = try editedDocument()
        let result = try TextFileDocumentIO.save(document)

        XCTAssertNil(result.warning)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path),
            [url.lastPathComponent]
        )
    }

    func testPostVerificationRemovalReturnsNoWarning() throws {
        let (url, document) = try editedDocument()
        var backupURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            afterReplacing: { _, candidateBackupURL in backupURL = candidateBackupURL },
            afterVerifyingRecovery: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertNil(result.warning)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(backupURL).path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path),
            [url.lastPathComponent]
        )
    }

    func testPostVerificationSwapLeavesMismatchAtOriginalPath() throws {
        let (url, document) = try editedDocument()
        let unrelated = Data("unrelated".utf8)
        var backupURL: URL?
        var preservedRecoveryURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            replaceItem: { originalURL, newURL, backupItemName in
                try FileManager.default.replaceItemAt(
                    originalURL,
                    withItemAt: newURL,
                    backupItemName: backupItemName,
                    options: .withoutDeletingBackupItem
                )
            },
            afterReplacing: { _, candidateBackupURL in backupURL = candidateBackupURL },
            afterVerifyingRecovery: { candidateBackupURL in
                let preservedURL = candidateBackupURL.deletingLastPathComponent()
                    .appending(path: "preserved-recovery")
                try FileManager.default.moveItem(at: candidateBackupURL, to: preservedURL)
                try unrelated.write(to: candidateBackupURL)
                preservedRecoveryURL = preservedURL
            }
        )

        let replacementURL = try XCTUnwrap(backupURL)
        guard case .recoveryCopyPreserved(let warningPath) = result.warning else {
            return XCTFail("Expected preserved artifact warning")
        }
        let retainedURL = URL(filePath: warningPath)
        XCTAssertEqual(
            retainedURL.standardizedFileURL,
            try XCTUnwrap(preservedRecoveryURL).standardizedFileURL
        )
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: replacementURL), unrelated)
        XCTAssertEqual(try Data(contentsOf: retainedURL), document.persistedData)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: retainedURL.deletingLastPathComponent().path)
            .contains { $0.hasPrefix(".macmerge-cleanup-") })
    }

    func testMissingBackupPathReportsMovedRecoveryFromStableReference() throws {
        let (url, document) = try editedDocument()
        let retainedDirectory = url.deletingLastPathComponent()
            .appending(path: "retained", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: retainedDirectory, withIntermediateDirectories: false)
        let movedRecoveryURL = retainedDirectory.appending(path: "moved-recovery")

        let result = try TextFileDocumentIO.save(document) { _, backupURL in
            try FileManager.default.moveItem(at: backupURL, to: movedRecoveryURL)
        }

        guard case .recoveryCopyPreserved(let warningPath) = result.warning else {
            return XCTFail("Expected moved recovery warning")
        }
        XCTAssertEqual(
            URL(filePath: warningPath).resolvingSymlinksInPath().standardizedFileURL,
            movedRecoveryURL.resolvingSymlinksInPath().standardizedFileURL
        )
        XCTAssertEqual(try Data(contentsOf: movedRecoveryURL), document.persistedData)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
    }

    func testPostDeletionVerificationSameByteSwapDoesNotDeleteReplacement() throws {
        let (url, document) = try editedDocument()
        let sameByteReplacement = document.persistedData
        var recoveryURL: URL?
        var retainedRecoveryURL: URL?
        var expectedRecoveryInode: NSNumber?
        var replacementInode: NSNumber?
        let retainedDirectory = url.deletingLastPathComponent()
            .appending(path: "retained", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: retainedDirectory, withIntermediateDirectories: false)

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            afterReplacing: { _, _ in },
            afterVerifyingRecoveryBeforeDeletion: { candidateRecoveryURL in
                recoveryURL = candidateRecoveryURL
                expectedRecoveryInode = try inode(at: candidateRecoveryURL)
                let retainedURL = retainedDirectory.appending(path: "retained-recovery")
                try FileManager.default.moveItem(at: candidateRecoveryURL, to: retainedURL)
                try sameByteReplacement.write(to: candidateRecoveryURL)
                replacementInode = try inode(at: candidateRecoveryURL)
                retainedRecoveryURL = retainedURL
            }
        )

        let replacementURL = try XCTUnwrap(recoveryURL)
        let expectedRecoveryURL = try XCTUnwrap(retainedRecoveryURL)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("saved edit".utf8))
        XCTAssertEqual(try Data(contentsOf: replacementURL), sameByteReplacement)
        XCTAssertEqual(try inode(at: replacementURL), try XCTUnwrap(replacementInode))
        XCTAssertNotEqual(replacementInode, expectedRecoveryInode)
        XCTAssertEqual(try inode(at: expectedRecoveryURL), try XCTUnwrap(expectedRecoveryInode))
        XCTAssertEqual(try Data(contentsOf: expectedRecoveryURL), document.persistedData)
        guard case .recoveryCopyPreserved(let warningPath) = result.warning else {
            return XCTFail("Expected retained recovery warning")
        }
        XCTAssertEqual(URL(filePath: warningPath).standardizedFileURL, expectedRecoveryURL.standardizedFileURL)
    }

    func testPostVerificationMovePreservesMovedRecoveryAndPathReplacement() throws {
        let (url, document) = try editedDocument()
        let unrelated = Data("unrelated replacement".utf8)
        let retainedDirectory = url.deletingLastPathComponent()
            .appending(path: "retained", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: retainedDirectory, withIntermediateDirectories: false)
        var originalRecoveryURL: URL?
        var movedRecoveryURL: URL?

        let result = try TextFileDocumentIO.save(
            document,
            beforeReplacing: {},
            afterReplacing: { _, _ in },
            afterVerifyingRecoveryBeforeDeletion: { recoveryURL in
                originalRecoveryURL = recoveryURL
                let movedURL = retainedDirectory.appending(path: "moved-recovery")
                try FileManager.default.moveItem(at: recoveryURL, to: movedURL)
                try unrelated.write(to: recoveryURL)
                movedRecoveryURL = movedURL
            }
        )

        let replacementURL = try XCTUnwrap(originalRecoveryURL)
        let retainedURL = try XCTUnwrap(movedRecoveryURL)
        XCTAssertEqual(try Data(contentsOf: replacementURL), unrelated)
        XCTAssertEqual(try Data(contentsOf: retainedURL), document.persistedData)
        guard case .recoveryCopyPreserved(let warningPath) = result.warning else {
            return XCTFail("Expected retained recovery warning")
        }
        XCTAssertEqual(
            URL(filePath: warningPath).resolvingSymlinksInPath().standardizedFileURL,
            retainedURL.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    func testIdentityBoundDeleteReturnsExactInt16Results() throws {
        let directory = try makeTemporaryDirectory()
        let artifactURL = directory.appending(path: "artifact.txt")
        try Data("artifact".utf8).write(to: artifactURL)

        let statuses: (Int16, Int16) = try XCTUnwrap(
            TextFileDocumentIO.identityBoundDeleteStatusesForTesting(at: artifactURL)
        )

        XCTAssertEqual(statuses.0, Int16(0))
        XCTAssertEqual(statuses.1, Int16(-43))
        XCTAssertEqual(UInt16(bitPattern: statuses.1), 0xFFD5)
        XCTAssertEqual(Int32(statuses.1), -43)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
    }

    private func editedDocument() throws -> (url: URL, document: TextFileDocument) {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.txt")
        try Data("original".utf8).write(to: url)
        var document = try TextFileDocumentIO.load(from: url)
        document.text = "saved edit"
        return (url, document)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func inode(at url: URL) throws -> NSNumber {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber)
    }
}
