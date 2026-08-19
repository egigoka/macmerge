import Darwin
import Foundation
import XCTest

@testable import MacMergeCore

final class BinaryFileDocumentTests: XCTestCase {
    func testLoadPreservesArbitraryBytesAndConfiguredBound() throws {
        let data = Data([0x00, 0x81, 0x98, 0xFF])
        let url = try temporaryFile(data: data)

        let document = try BinaryFileDocumentIO.load(from: url, maximumBytes: 4)

        XCTAssertEqual(document.data, data)
        XCTAssertEqual(document.persistedData, data)
        XCTAssertEqual(document.maximumByteCount, 4)
        XCTAssertFalse(document.isDirty)
    }

    func testLoadRejectsOversizedFileBeforeReadingIt() throws {
        let url = try temporaryFile(data: Data(repeating: 0xAA, count: 9))

        XCTAssertThrowsError(try BinaryFileDocumentIO.load(from: url, maximumBytes: 8)) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .fileTooLarge(maximumBytes: 8))
        }
    }

    func testByteEditsInsertionsAndDeletionsAreBounded() throws {
        let url = try temporaryFile(data: Data([0x10, 0x20, 0x30]))
        var document = try BinaryFileDocumentIO.load(from: url, maximumBytes: 5)

        try document.replaceByte(at: 1, with: 0x21)
        try document.insert(Data([0xAA, 0xBB]), at: 2)
        try document.removeSubrange(0..<1)

        XCTAssertEqual(document.data, Data([0x21, 0xAA, 0xBB, 0x30]))
        XCTAssertTrue(document.isDirty)
        XCTAssertThrowsError(try document.insert(Data([0xCC, 0xDD]), at: 4)) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .fileTooLarge(maximumBytes: 5))
        }
        XCTAssertThrowsError(try document.replaceByte(at: 4, with: 0)) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .invalidByteOffset(4))
        }
        XCTAssertThrowsError(try document.removeSubrange(3..<5)) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .invalidByteRange(3..<5))
        }
    }

    func testNoOpAndRevertedEditsRemainClean() throws {
        let original = Data([0x10, 0x20, 0x30])
        let url = try temporaryFile(data: original)
        var document = try BinaryFileDocumentIO.load(from: url)

        try document.replaceByte(at: 1, with: 0x20)
        try document.replaceSubrange(0..<document.byteCount, with: original)
        XCTAssertFalse(document.isDirty)

        try document.replaceByte(at: 1, with: 0xFF)
        XCTAssertTrue(document.isDirty)
        try document.replaceByte(at: 0, with: 0x10)
        XCTAssertTrue(document.isDirty)
        try document.replaceSubrange(0..<document.byteCount, with: original)
        XCTAssertFalse(document.isDirty)

        try document.insert(Data([0xAA]), at: 1)
        XCTAssertTrue(document.isDirty)
        try document.removeSubrange(1..<2)
        XCTAssertFalse(document.isDirty)
    }

    func testStructuralEditsReconcileDirtyStateWhenOriginalShapeReturns() throws {
        let original = Data([0x10, 0x20, 0x30, 0x40])
        let url = try temporaryFile(data: original)
        var document = try BinaryFileDocumentIO.load(from: url)

        try document.insert(Data([0xAA]), at: 1)
        try document.removeSubrange(3..<4)

        XCTAssertEqual(document.data, Data([0x10, 0xAA, 0x20, 0x40]))
        XCTAssertEqual(document.byteCount, original.count)
        XCTAssertTrue(document.isDirty)

        try document.replaceSubrange(1..<3, with: Data([0x20, 0x30]))

        XCTAssertEqual(document.data, original)
        XCTAssertFalse(document.isDirty)

        try document.removeSubrange(1..<3)
        XCTAssertTrue(document.isDirty)
        try document.replaceSubrange(0..<document.byteCount, with: original)
        XCTAssertFalse(document.isDirty)
    }

    func testSavePersistsEditsAndMarksReturnedDocumentClean() throws {
        let url = try temporaryFile(data: Data([0x00, 0x01, 0x02]))
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceSubrange(1..<2, with: Data([0xFE, 0xFF]))

        let result = try BinaryFileDocumentIO.save(document)
        let saved = result.document

        XCTAssertEqual(try Data(contentsOf: url), Data([0x00, 0xFE, 0xFF, 0x02]))
        XCTAssertEqual(saved.data, saved.persistedData)
        XCTAssertFalse(saved.isDirty)
        XCTAssertNil(result.warning)
    }

    func testSaveRejectsExternalChangesWithoutOverwritingThem() throws {
        let url = try temporaryFile(data: Data([0x00, 0x01, 0x02]))
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)
        let external = Data([0xAA, 0xBB, 0xCC])
        try external.write(to: url, options: .atomic)

        XCTAssertThrowsError(try BinaryFileDocumentIO.save(document)) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .changedOnDisk)
        }
        XCTAssertEqual(try Data(contentsOf: url), external)
    }

    func testSaveThroughSymlinkPreservesLinkAndUpdatesTarget() throws {
        let target = try temporaryFile(data: Data([0x00, 0x01]))
        let link = target.deletingLastPathComponent().appending(path: "linked.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var document = try BinaryFileDocumentIO.load(from: link)
        try document.replaceByte(at: 1, with: 0xFE)

        _ = try BinaryFileDocumentIO.save(document)

        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(try Data(contentsOf: target), Data([0x00, 0xFE]))
    }

    func testSaveRejectsRetargetedSymlink() throws {
        let first = try temporaryFile(data: Data([0x00]))
        let second = first.deletingLastPathComponent().appending(path: "second.bin")
        try Data([0x01]).write(to: second)
        let link = first.deletingLastPathComponent().appending(path: "retargeted.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        var document = try BinaryFileDocumentIO.load(from: link)
        try document.replaceByte(at: 0, with: 0xFF)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)

        XCTAssertThrowsError(try BinaryFileDocumentIO.save(document)) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .changedOnDisk)
        }
        XCTAssertEqual(try Data(contentsOf: first), Data([0x00]))
        XCTAssertEqual(try Data(contentsOf: second), Data([0x01]))
    }

    func testConcurrentWriteDuringReplacementIsPreservedAsRecovery() throws {
        let original = Data([0x00, 0x01])
        let external = Data([0xAA, 0xBB])
        let url = try temporaryFile(data: original)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        XCTAssertThrowsError(
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: { try external.write(to: url) },
                afterReplacing: {}
            )
        ) { error in
            guard case .saveOutcomeUncertain(let path) = error as? BinaryFileDocumentError else {
                return XCTFail("Expected uncertain save, got \(error)")
            }
            XCTAssertEqual(try? Data(contentsOf: URL(filePath: path)), external)
        }
    }

    func testPostReplacementFailureReportsUncertainOutcomeWithRecovery() throws {
        let original = Data([0x00, 0x01])
        let url = try temporaryFile(data: original)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        XCTAssertThrowsError(
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {},
                afterReplacing: { throw CocoaError(.fileReadUnknown) }
            )
        ) { error in
            guard case .saveOutcomeUncertain(let path) = error as? BinaryFileDocumentError else {
                return XCTFail("Expected uncertain save, got \(error)")
            }
            XCTAssertEqual(try? Data(contentsOf: URL(filePath: path)), original)
        }
    }

    func testSaveSupportsSourceNameAtComponentLimit() throws {
        let directory = try temporaryDirectory()
        let maximumNameLength = directory.path.withCString { Darwin.pathconf($0, _PC_NAME_MAX) }
        let url = directory.appending(path: String(repeating: "a", count: Int(maximumNameLength)))
        try Data([0x00, 0x01]).write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        let result = try BinaryFileDocumentIO.save(document)

        XCTAssertEqual(try Data(contentsOf: url), Data([0x00, 0xFE]))
        XCTAssertFalse(result.document.isDirty)
        XCTAssertNil(result.warning)
    }

    func testRecoveryFor255ByteUTF8SourceNameStaysWithinComponentLimit() throws {
        let original = Data([0x00, 0x01])
        let directory = try temporaryDirectory()
        let maximumNameLength = directory.path.withCString { Darwin.pathconf($0, _PC_NAME_MAX) }
        guard maximumNameLength >= 255 else {
            throw XCTSkip("Temporary filesystem does not support 255-byte components.")
        }
        let sourceName = String(repeating: "\u{1F600}", count: 63) + "bin"
        XCTAssertEqual(sourceName.utf8.count, 255)
        let url = directory.appending(path: sourceName)
        try original.write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        let result = try BinaryFileDocumentIO.save(
            document,
            beforeReplacing: {},
            afterReplacing: {},
            beforeRemovingRecovery: { throw CocoaError(.fileWriteNoPermission) }
        )

        guard case .recoveryCopyPreserved(let path) = result.warning else {
            return XCTFail("Expected retained recovery warning")
        }
        let recoveryURL = URL(filePath: path)
        XCTAssertLessThanOrEqual(recoveryURL.lastPathComponent.utf8.count, Int(maximumNameLength))
        XCTAssertTrue(recoveryURL.lastPathComponent.contains(".macmerge-recovery-"))
        XCTAssertEqual(try Data(contentsOf: recoveryURL), original)
        XCTAssertEqual(result.document.data, Data([0x00, 0xFE]))
        XCTAssertEqual(result.document.persistedData, result.document.data)
        XCTAssertFalse(result.document.isDirty)
    }

    func testCorruptedRecoveryArtifactIsNotPromised() throws {
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        try Data([0x00, 0x01]).write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        XCTAssertThrowsError(
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {},
                afterReplacing: {
                    let recoveryURL = try XCTUnwrap(self.recoveryURL(in: directory))
                    try Data([0xDE, 0xAD]).write(to: recoveryURL)
                    throw CocoaError(.fileReadUnknown)
                }
            )
        ) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }
    }

    func testMissingRecoveryArtifactIsNotPromised() throws {
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        try Data([0x00, 0x01]).write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        XCTAssertThrowsError(
            try BinaryFileDocumentIO.save(
                document,
                beforeReplacing: {},
                afterReplacing: {
                    let recoveryURL = try XCTUnwrap(self.recoveryURL(in: directory))
                    try FileManager.default.removeItem(at: recoveryURL)
                    throw CocoaError(.fileReadUnknown)
                }
            )
        ) { error in
            XCTAssertEqual(error as? BinaryFileDocumentError, .saveOutcomeUncertainWithoutRecovery)
        }
    }

    func testRecoveryCleanupFailureReturnsWarningAfterSuccessfulSave() throws {
        let original = Data([0x00, 0x01])
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        try original.write(to: url)
        var document = try BinaryFileDocumentIO.load(from: url)
        try document.replaceByte(at: 1, with: 0xFE)

        let result = try BinaryFileDocumentIO.save(
            document,
            beforeReplacing: {},
            afterReplacing: {},
            beforeRemovingRecovery: { throw CocoaError(.fileWriteNoPermission) }
        )

        guard case .recoveryCopyPreserved(let path) = result.warning else {
            return XCTFail("Expected retained recovery warning")
        }
        XCTAssertEqual(try Data(contentsOf: url), Data([0x00, 0xFE]))
        XCTAssertEqual(try Data(contentsOf: URL(filePath: path)), original)
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(result.document.data, Data([0x00, 0xFE]))
        XCTAssertEqual(result.document.persistedData, result.document.data)
        XCTAssertFalse(result.document.isDirty)
    }

    func testLoadRejectsFIFOWithoutWaitingForWriter() throws {
        if let fifoPath = ProcessInfo.processInfo.environment[Self.fifoChildPathEnvironment] {
            XCTAssertThrowsError(try BinaryFileDocumentIO.load(from: URL(filePath: fifoPath))) { error in
                XCTAssertEqual(error as? BinaryFileDocumentError, .notRegularFile)
            }
            return
        }

        let directory = try temporaryDirectory()
        let url = directory.appending(path: "fixture.pipe")
        XCTAssertEqual(Darwin.mkfifo(url.path, 0o600), 0)

        try assertTestPassesInBoundedSubprocess(
            "MacMergeCoreTests.BinaryFileDocumentTests/testLoadRejectsFIFOWithoutWaitingForWriter",
            environment: [Self.fifoChildPathEnvironment: url.path]
        )
    }

    private func temporaryFile(data: Data) throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "fixture.bin")
        try data.write(to: url)
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func recoveryURL(in directory: URL) throws -> URL? {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.contains(".macmerge-recovery-") }
    }

    private func assertTestPassesInBoundedSubprocess(
        _ testName: String,
        environment additions: [String: String],
        timeout: DispatchTimeInterval = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = Process()
        process.executableURL = URL(filePath: CommandLine.arguments[0])
        process.arguments = ["-XCTest", testName, Bundle(for: Self.self).bundleURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, addition in addition }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        try process.run()
        guard terminated.wait(timeout: .now() + timeout) == .success else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            XCTFail("Child test exceeded bounded timeout", file: file, line: line)
            return
        }
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit, file: file, line: line)
        XCTAssertEqual(process.terminationStatus, 0, file: file, line: line)
    }

    private static let fifoChildPathEnvironment = "MACMERGE_BINARY_FIFO_CHILD_PATH"
}
