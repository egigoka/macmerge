import Darwin
import Foundation
import XCTest
@testable import MacMergeCore

final class FilesystemRaceTests: XCTestCase {
    func testSaveAsPreservesConcurrentDestinationReplacementAsRecovery() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let concurrentData = Data("concurrent destination".utf8)
        try Data("source".utf8).write(to: sourceURL)
        try Data("old destination".utf8).write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"

        var recoveryURL: URL?
        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {
                try concurrentData.write(to: destinationURL, options: .atomic)
            },
            afterPublishing: { _ in },
            saveSameStorage: TextFileDocumentIO.save
        )) { error in
            guard case .saveOutcomeUncertain(let path) = error as? TextFileDocumentError else {
                return XCTFail("Expected verified recovery, got \(error)")
            }
            recoveryURL = URL(filePath: path)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("MacMerge copy".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(recoveryURL)), concurrentData)
    }

    func testSaveAsPreservesInPlaceDestinationEditAsRecovery() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let originalDestination = Data("old destination".utf8)
        let concurrentData = Data("new destination".utf8)
        try Data("source".utf8).write(to: sourceURL)
        try originalDestination.write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"

        var recoveryURL: URL?
        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {
                let handle = try FileHandle(forWritingTo: destinationURL)
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: concurrentData)
                try handle.synchronize()
                try handle.close()
            },
            afterPublishing: { _ in },
            saveSameStorage: TextFileDocumentIO.save
        )) { error in
            guard case .saveOutcomeUncertain(let path) = error as? TextFileDocumentError else {
                return XCTFail("Expected verified recovery, got \(error)")
            }
            recoveryURL = URL(filePath: path)
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("MacMerge copy".utf8))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(recoveryURL)), concurrentData)
    }

    func testSaveAsFinalDisplacedCleanupSubstitutionPreservesBothFiles() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let movedRecoveryURL = directory.appending(path: "moved-recovery.txt")
        let originalDestination = Data("old destination".utf8)
        let foreignData = Data("foreign replacement".utf8)
        try Data("source".utf8).write(to: sourceURL)
        try originalDestination.write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"

        let result = try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {},
            afterPublishing: { _ in },
            afterVerifyingDisplacedDestination: { displacedURL in
                try FileManager.default.moveItem(at: displacedURL, to: movedRecoveryURL)
                try foreignData.write(to: displacedURL)
            },
            saveSameStorage: TextFileDocumentIO.save
        )

        guard case .recoveryCopyPreserved(let warningPath) = result.warning else {
            return XCTFail("Expected retained recovery warning")
        }
        XCTAssertEqual(
            URL(filePath: warningPath).resolvingSymlinksInPath().standardizedFileURL,
            movedRecoveryURL.resolvingSymlinksInPath().standardizedFileURL
        )
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("MacMerge copy".utf8))
        XCTAssertEqual(try Data(contentsOf: movedRecoveryURL), originalDestination)
        let temporaryURL = try XCTUnwrap(try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix(".macmerge-") && $0.pathExtension == "tmp" })
        XCTAssertEqual(try Data(contentsOf: temporaryURL), foreignData)
    }

    func testSaveAsCleanupDoesNotAdvertiseForeignFileSubstitutedForDeletedRecovery() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let originalDestination = Data("old destination".utf8)
        let foreignData = Data("foreign replacement".utf8)
        try Data("source".utf8).write(to: sourceURL)
        try originalDestination.write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"
        var recoveryURL: URL?

        let result = try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {},
            afterPublishing: { _ in },
            afterVerifyingDisplacedDestination: { displacedURL in
                recoveryURL = displacedURL
                try FileManager.default.removeItem(at: displacedURL)
                try foreignData.write(to: displacedURL)
            },
            saveSameStorage: TextFileDocumentIO.save
        )

        let substitutedURL = try XCTUnwrap(recoveryURL)
        XCTAssertNil(result.warning)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("MacMerge copy".utf8))
        XCTAssertEqual(try Data(contentsOf: substitutedURL), foreignData)
        XCTAssertNotEqual(try Data(contentsOf: substitutedURL), originalDestination)
    }

    func testSaveAsDisplacedSubstitutionNeverCertifiesSubstitutedArtifactAsRecovery() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let preservedOriginalURL = directory.appending(path: "preserved-original.txt")
        let originalDestination = Data("old destination".utf8)
        let foreignData = Data("foreign replacement".utf8)
        try Data("source".utf8).write(to: sourceURL)
        try originalDestination.write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"
        var substitutedURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {},
            afterPublishing: { _ in XCTFail("Substituted displaced artifact must stop publication") },
            afterSwappingDestination: { displacedURL in
                substitutedURL = displacedURL
                try FileManager.default.moveItem(at: displacedURL, to: preservedOriginalURL)
                try foreignData.write(to: displacedURL)
            },
            saveSameStorage: TextFileDocumentIO.save
        )) { error in
            guard case .saveOutcomeUncertain(let path) = error as? TextFileDocumentError else {
                return XCTFail("Expected verified original recovery, got \(error)")
            }
            let recoveryURL = URL(filePath: path)
            XCTAssertEqual(
                recoveryURL.resolvingSymlinksInPath().standardizedFileURL,
                preservedOriginalURL.standardizedFileURL
            )
            XCTAssertEqual(try? Data(contentsOf: recoveryURL), originalDestination)
            XCTAssertNotEqual(recoveryURL.standardizedFileURL, substitutedURL?.standardizedFileURL)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("MacMerge copy".utf8))
        XCTAssertEqual(try Data(contentsOf: preservedOriginalURL), originalDestination)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(substitutedURL)), foreignData)
    }

    func testSaveAsPostSwapIdentityErrorMapsToUncertainCommittedOutcome() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        try Data("source".utf8).write(to: sourceURL)
        try Data("old destination".utf8).write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {},
            afterPublishing: { _ in },
            afterVerifyingDisplacedDestination: { _ in
                XCTAssertEqual(destinationURL.path.withCString { Darwin.unlink($0) }, 0)
                let symlinkResult = sourceURL.path.withCString { sourcePath in
                    destinationURL.path.withCString { destinationPath in
                        Darwin.symlink(sourcePath, destinationPath)
                    }
                }
                XCTAssertEqual(symlinkResult, 0)
            },
            saveSameStorage: TextFileDocumentIO.save
        )) { error in
            guard case .saveOutcomeUncertain(let path) = error as? TextFileDocumentError else {
                return XCTFail("Expected retained recovery, got \(error)")
            }
            XCTAssertEqual(try? Data(contentsOf: URL(filePath: path)), Data("old destination".utf8))
        }

        var destinationInformation = stat()
        XCTAssertEqual(destinationURL.path.withCString { Darwin.lstat($0, &destinationInformation) }, 0)
        XCTAssertEqual(destinationInformation.st_mode & S_IFMT, S_IFLNK)
        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("source".utf8))
    }

    func testSaveAsPostPublishingFailureReportsRetainedDestinationRecovery() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let originalDestination = Data("old destination".utf8)
        let postPublishData = Data("post publish mutation".utf8)
        try Data("source".utf8).write(to: sourceURL)
        try originalDestination.write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"
        var recoveryURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {},
            afterPublishing: { publishedURL in
                try postPublishData.write(to: publishedURL, options: .atomic)
            },
            saveSameStorage: TextFileDocumentIO.save
        )) { error in
            guard case .saveOutcomeUncertain(let path) = error as? TextFileDocumentError else {
                return XCTFail("Expected verified recovery, got \(error)")
            }
            recoveryURL = URL(filePath: path)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), postPublishData)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(recoveryURL)), originalDestination)
    }

    func testSaveAsStagedSubstitutionIsNeverDeletedByFailureCleanup() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let foreignData = Data("foreign staged replacement".utf8)
        try Data("source".utf8).write(to: sourceURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"
        var stagedURL: URL?

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {
                let candidate = try XCTUnwrap(try FileManager.default
                    .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .first { $0.lastPathComponent.hasPrefix(".macmerge-") && $0.pathExtension == "tmp" })
                try FileManager.default.removeItem(at: candidate)
                try foreignData.write(to: candidate)
                stagedURL = candidate
            },
            afterPublishing: { _ in XCTFail("Foreign staged file must not publish") },
            saveSameStorage: TextFileDocumentIO.save
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .changedOnDisk)
        }

        let retainedURL = try XCTUnwrap(stagedURL)
        XCTAssertEqual(try Data(contentsOf: retainedURL), foreignData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testSaveAsRejectsInPlaceStagedMutationBeforePublishing() throws {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appending(path: "source.txt")
        let destinationURL = directory.appending(path: "destination.txt")
        let mutatedData = Data("mutated staged bytes".utf8)
        try Data("source".utf8).write(to: sourceURL)
        try Data("old destination".utf8).write(to: destinationURL)
        var document = try TextFileDocumentIO.load(from: sourceURL)
        document.text = "MacMerge copy"

        XCTAssertThrowsError(try TextFileDocumentIO.saveAs(
            document,
            to: destinationURL,
            beforePublishing: {
                let stagedURL = try XCTUnwrap(try FileManager.default
                    .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .first { $0.lastPathComponent.hasPrefix(".macmerge-") && $0.pathExtension == "tmp" })
                let handle = try FileHandle(forWritingTo: stagedURL)
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: mutatedData)
                try handle.synchronize()
                try handle.close()
            },
            afterPublishing: { _ in XCTFail("Mutated staged bytes must not publish") },
            saveSameStorage: TextFileDocumentIO.save
        )) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .changedOnDisk)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("old destination".utf8))
    }

    func testSaveRejectsSameSizeExternalEditWithRestoredModificationDate() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.txt")
        let original = Data("original".utf8)
        let external = Data("external".utf8)
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        try original.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)

        var document = try TextFileDocumentIO.load(from: url)
        document.text = "MacMerge edit"
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: url.path)

        try external.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
        let externalAttributes = try FileManager.default.attributesOfItem(atPath: url.path)

        XCTAssertEqual(originalAttributes[.size] as? NSNumber, externalAttributes[.size] as? NSNumber)
        XCTAssertEqual(
            originalAttributes[.modificationDate] as? Date,
            externalAttributes[.modificationDate] as? Date
        )
        assertChangedOnDisk(try TextFileDocumentIO.save(document))
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testSecondSaveFromSameSnapshotCannotOverwriteFirstSave() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.txt")
        try Data("original".utf8).write(to: url)
        var firstDocument = try TextFileDocumentIO.load(from: url)
        var secondDocument = try TextFileDocumentIO.load(from: url)
        firstDocument.text = "first edit"
        secondDocument.text = "second edit"

        let firstResult = try TextFileDocumentIO.save(firstDocument)

        XCTAssertFalse(firstResult.document.isDirty)
        XCTAssertNil(firstResult.warning)
        assertChangedOnDisk(try TextFileDocumentIO.save(secondDocument))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first edit")
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testSaveRejectsSymlinkRetargetedToIdenticalFile() throws {
        let directory = try makeTemporaryDirectory()
        let firstTarget = directory.appending(path: "first.txt")
        let secondTarget = directory.appending(path: "second.txt")
        let link = directory.appending(path: "document.txt")
        let original = Data("identical contents".utf8)
        try original.write(to: firstTarget)
        try original.write(to: secondTarget)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstTarget)
        var document = try TextFileDocumentIO.load(from: link)
        document.text = "MacMerge edit"

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secondTarget)

        assertChangedOnDisk(try TextFileDocumentIO.save(document))
        XCTAssertEqual(try Data(contentsOf: firstTarget), original)
        XCTAssertEqual(try Data(contentsOf: secondTarget), original)
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testCoordinatedSaveRejectsPresenterFlushBeforeWriterAccess() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.txt")
        let external = Data("presenter edit".utf8)
        try Data("original".utf8).write(to: url)
        var document = try TextFileDocumentIO.load(from: url)
        document.text = "MacMerge edit"
        let presenter = FlushingFilePresenter(url: url) {
            try external.write(to: url)
        }
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        assertChangedOnDisk(try TextFileDocumentIO.save(document))

        XCTAssertTrue(presenter.didFlush)
        XCTAssertNil(presenter.flushErrorDescription)
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertEqual(try artifactNames(in: directory), [])
    }

    func testSuccessfulSaveRetainsOlderRecoveryCopyAndCleansCurrentArtifacts() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.txt")
        let olderRecoveryURL = directory.appending(path: "fixture.txt.macmerge-recovery-retained")
        let olderRecoveryData = Data("older recovery".utf8)
        try Data("original".utf8).write(to: url)
        try olderRecoveryData.write(to: olderRecoveryURL)
        var document = try TextFileDocumentIO.load(from: url)
        document.text = "saved edit"

        let result = try TextFileDocumentIO.save(document)

        XCTAssertNil(result.warning)
        XCTAssertFalse(result.document.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "saved edit")
        XCTAssertEqual(try Data(contentsOf: olderRecoveryURL), olderRecoveryData)
        XCTAssertEqual(try artifactNames(in: directory), [olderRecoveryURL.lastPathComponent])
    }

    func testBinarySavePreservesEditDisplacedDuringReplacement() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        let original = Data([0x00, 0x01, 0x02])
        let external = Data([0xAA, 0xBB, 0xCC])
        let edited = Data([0x00, 0xFE, 0x02])
        try original.write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        let recoveryURL = try assertBinarySaveOutcomeUncertain {
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: { try external.write(to: url, options: .atomic) },
                afterReplacing: {}
            )
        }

        XCTAssertEqual(try Data(contentsOf: url), edited)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), external)
        XCTAssertEqual(try artifactNames(in: directory), [recoveryURL.lastPathComponent])
    }

    func testBinarySaveRejectsSymlinkRetargetAfterReplacement() throws {
        let directory = try makeTemporaryDirectory()
        let firstTarget = directory.appending(path: "first.bin")
        let secondTarget = directory.appending(path: "second.bin")
        let link = directory.appending(path: "document.bin")
        let original = Data([0x00, 0x01, 0x02])
        let edited = Data([0x00, 0xFE, 0x02])
        try original.write(to: firstTarget)
        try edited.write(to: secondTarget)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: firstTarget)
        var document = try BinaryFileDocumentIO.load(from: link)
        try document.replaceByte(at: 1, with: 0xFE)

        let recoveryURL = try assertBinarySaveOutcomeUncertain {
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {},
                afterReplacing: {
                    try FileManager.default.removeItem(at: link)
                    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secondTarget)
                }
            )
        }

        XCTAssertEqual(try Data(contentsOf: firstTarget), edited)
        XCTAssertEqual(try Data(contentsOf: secondTarget), edited)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), original)
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(link.resolvingSymlinksInPath().standardizedFileURL, secondTarget.standardizedFileURL)
        XCTAssertEqual(try artifactNames(in: directory), [recoveryURL.lastPathComponent])
    }

    private func assertChangedOnDisk<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? TextFileDocumentError, .changedOnDisk, file: file, line: line)
        }
    }

    private func assertBinarySaveOutcomeUncertain<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) throws -> URL {
        do {
            _ = try operation()
            XCTFail("Expected uncertain binary save outcome", file: file, line: line)
            throw CocoaError(.fileWriteUnknown)
        } catch BinaryFileDocumentError.saveOutcomeUncertain(let path) {
            return URL(filePath: path)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
            throw error
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func artifactNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(".macmerge-") || $0.contains(".macmerge-recovery-") }
            .sorted()
    }
}

private final class FlushingFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue

    private let flush: @Sendable () throws -> Void
    private let lock = NSLock()
    private var hasFlushed = false
    private var storedFlushErrorDescription: String?

    init(url: URL, flush: @escaping @Sendable () throws -> Void) {
        presentedItemURL = url.standardizedFileURL
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        self.flush = flush
    }

    var didFlush: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasFlushed
    }

    var flushErrorDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedFlushErrorDescription
    }

    func savePresentedItemChanges(completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(flushOnce())
    }

    func relinquishPresentedItem(
        toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void
    ) {
        _ = flushOnce()
        writer(nil)
    }

    private func flushOnce() -> (any Error)? {
        lock.lock()
        if hasFlushed {
            lock.unlock()
            return nil
        }
        hasFlushed = true
        lock.unlock()

        do {
            try flush()
            return nil
        } catch {
            lock.lock()
            storedFlushErrorDescription = String(describing: error)
            lock.unlock()
            return error
        }
    }
}
