import AppKit
import Darwin
import Foundation
import MacMergeCore
import XCTest

@testable import MacMerge

@MainActor
final class ComparisonSessionStoreTests: XCTestCase {
    func testStoreRoundTripsAndClearsSessionAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComparisonSessionStore(
            fileURL: directory.appending(path: "ComparisonSession.json")
        )
        let state = try makeState()

        XCTAssertNil(try store.load())
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        try store.clear()
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.clear())
    }

    func testConditionalClearOnlyRemovesMatchingSession() throws {
        let directory = try makeFixture()
        let store = ComparisonSessionStore(
            fileURL: directory.appending(path: "ComparisonSession.json")
        )
        let original = try makeState()
        let replacement = try ComparisonSessionState(
            left: .scratchpad("replacement"),
            right: .scratchpad("right"),
            windowFrame: makeFrame()
        )
        let firstReceipt = try store.save(original)
        let secondReceipt = try store.save(original)

        try store.clear(savedBy: firstReceipt)
        XCTAssertEqual(try store.load(), original)

        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: replacement.encodedData())
        try handle.synchronize()
        try handle.close()
        try store.clear(savedBy: secondReceipt)
        XCTAssertEqual(try store.load(), replacement)

        let currentReceipt = try store.save(original)
        try store.clear(savedBy: currentReceipt)
        XCTAssertNil(try store.load())
    }

    func testStorePreservesAbandonedQuarantineAndFailsClosed() throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let quarantineURL = directory.appending(path: ".ComparisonSession.json.quarantine")
        let store = ComparisonSessionStore(fileURL: fileURL)
        let state = try makeState()
        try store.save(state)
        try FileManager.default.moveItem(at: fileURL, to: quarantineURL)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(state))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), try state.encodedData())
    }

    func testStorePreservesStaleQuarantineWithoutBlockingActiveSession() throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let quarantineURL = directory.appending(path: ".ComparisonSession.json.quarantine")
        let store = ComparisonSessionStore(fileURL: fileURL)
        let state = try makeState()
        let stale = Data("stale quarantine".utf8)
        try store.save(state)
        try stale.write(to: quarantineURL)

        XCTAssertEqual(try store.load(), state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        let recoveryURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first {
                $0.lastPathComponent.hasPrefix(".ComparisonSession.json.")
                    && $0.pathExtension == "recovery"
            }
        )
        XCTAssertEqual(try Data(contentsOf: recoveryURL), stale)
    }

    func testMaximumAcceptedSessionNameSupportsQuarantineRecovery() throws {
        let directory = try makeFixture()
        let fileName = String(repeating: "x", count: 200)
        let fileURL = directory.appending(path: fileName)
        let quarantineURL = directory.appending(path: ".\(fileName).quarantine")
        let store = ComparisonSessionStore(fileURL: fileURL)
        let state = try makeState()
        let stale = Data("stale".utf8)
        try store.save(state)
        try stale.write(to: quarantineURL)

        XCTAssertEqual(try store.load(), state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineURL.path))
        let recoveryURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first {
                $0.lastPathComponent.hasPrefix(".\(fileName).")
                    && $0.pathExtension == "recovery"
            }
        )
        XCTAssertEqual(try Data(contentsOf: recoveryURL), stale)
    }

    func testStoreRejectsReservedLockAndInvalidLocations() throws {
        let directory = try makeFixture()
        let lockURL = directory.appending(path: ".ComparisonSession.lock")

        XCTAssertThrowsError(try ComparisonSessionStore(fileURL: lockURL).load())
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: directory.appending(path: ".comparisonsession.LOCK")
            ).save(makeState())
        )
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: directory.appending(path: ".comparisonsession.QUARANTINE")
            ).save(makeState())
        )
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: URL(string: "https://example.com/ComparisonSession.json")!
            ).load()
        )
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: URL(fileURLWithPath: directory.path, isDirectory: true)
            ).load()
        )
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: URL(string: "file:ComparisonSession.json")!
            ).load()
        )
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: URL(string: "file://example.com/tmp/ComparisonSession.json")!
            ).load()
        )
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: directory
                    .appending(path: "parent\0suffix", directoryHint: .isDirectory)
                    .appending(path: "ComparisonSession.json")
            ).load()
        )
        XCTAssertThrowsError(
            try ComparisonSessionStore(
                fileURL: directory.appending(path: String(repeating: "x", count: 201))
            ).load()
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: lockURL.path))

        try Data().write(to: lockURL)
        let aliasURL = directory.appending(path: "session-alias.json")
        try FileManager.default.linkItem(at: lockURL, to: aliasURL)
        XCTAssertThrowsError(try ComparisonSessionStore(fileURL: aliasURL).load())

        var status = stat()
        XCTAssertEqual(lstat(lockURL.path, &status), 0)
        XCTAssertEqual(status.st_mode & S_IFMT, S_IFREG)
    }

    func testStoreRejectsOversizedFileWithoutReadingUnboundedData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "ComparisonSession.json")
        try Data(
            repeating: 0x20,
            count: ComparisonSessionState.maximumPersistedBytes + 1
        ).write(to: fileURL)
        let store = ComparisonSessionStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual(
                $0 as? ComparisonSessionStateError,
                .encodedDataTooLarge(maximumBytes: ComparisonSessionState.maximumPersistedBytes)
            )
        }
        let original = try Data(contentsOf: fileURL)
        guard case .failed = store.loadAndClearCorrupt() else {
            return XCTFail("Oversized sessions must be preserved")
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testStoreRejectsSymlinkAndFIFOWithoutBlocking() throws {
        let directory = try makeFixture()
        let target = directory.appending(path: "target.json")
        try Data("{}".utf8).write(to: target)
        let symlink = directory.appending(path: "session-link.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        XCTAssertThrowsError(try ComparisonSessionStore(fileURL: symlink).load())

        let fifo = directory.appending(path: "session.fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try ComparisonSessionStore(fileURL: fifo).load())
    }

    func testStoreQuarantinesUnixSocketWithoutAttemptingOpen() throws {
        let directory = try makeFixture()
        let socketURL = directory.appending(path: "session.socket")
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return XCTFail("Unix socket fixture path exceeds sockaddr_un.sun_path")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let addressLength = socklen_t(address.sun_len)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, addressLength)
            }
        }
        XCTAssertEqual(bindResult, 0)
        let store = ComparisonSessionStore(fileURL: socketURL)

        guard case .corrupt(_, cleared: true) = store.loadAndClearCorrupt() else {
            return XCTFail("Unix socket session node must be quarantined and cleared")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
    }

    func testFailedSaveAndClearRetainPreviousAtomicSession() throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let store = ComparisonSessionStore(fileURL: fileURL)
        let original = try makeState()
        try store.save(original)
        XCTAssertEqual(chmod(directory.path, 0o500), 0)
        defer { chmod(directory.path, 0o700) }

        XCTAssertThrowsError(
            try store.save(
                ComparisonSessionState(
                    left: .scratchpad("replacement"),
                    right: .scratchpad("right"),
                    windowFrame: try makeFrame()
                )
            )
        )
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(try store.load(), original)
    }

    func testCrossInstanceOperationsRemainSerializedAndDecodable() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let first = ComparisonSessionStore(fileURL: fileURL)
        let second = ComparisonSessionStore(fileURL: fileURL)
        let state = try makeState()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    if index.isMultiple(of: 3) {
                        try second.clear()
                    } else {
                        try first.save(state)
                    }
                }
            }
            try await group.waitForAll()
        }

        let concurrentResult = try first.load()
        XCTAssertTrue(concurrentResult == nil || concurrentResult == state)

        try first.save(state)
        XCTAssertEqual(try first.load(), state)
    }

    func testDelegateRestoresStoredSessionWhenNoExplicitOpenExists() async throws {
        let directory = try makeFixture()
        let store = ComparisonSessionStore(
            fileURL: directory.appending(path: "ComparisonSession.json")
        )
        let state = try makeState()
        try store.save(state)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: store
        )

        await delegate.loadInitialComparison(arguments: [])
        await waitUntilIdle(delegate.model)

        XCTAssertEqual(delegate.model.left.text, "left")
        XCTAssertEqual(delegate.model.right.text, "right")
        XCTAssertFalse(delegate.model.left.isEditable)
        XCTAssertEqual(delegate.model.activeSide, .right)
    }

    func testDelegateExplicitArgumentsTakePrecedenceOverStoredSession() async throws {
        let directory = try makeFixture()
        let store = ComparisonSessionStore(
            fileURL: directory.appending(path: "ComparisonSession.json")
        )
        try store.save(try makeState())
        let leftURL = directory.appending(path: "explicit-left.txt")
        let rightURL = directory.appending(path: "explicit-right.txt")
        try Data("explicit left".utf8).write(to: leftURL)
        try Data("explicit right".utf8).write(to: rightURL)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: store
        )

        await delegate.loadInitialComparison(arguments: [leftURL.path, rightURL.path])
        await waitUntilIdle(delegate.model)

        XCTAssertEqual(delegate.model.left.url, leftURL)
        XCTAssertEqual(delegate.model.right.url, rightURL)
        XCTAssertTrue(delegate.model.left.isEditable)
        XCTAssertTrue(delegate.model.right.isEditable)
    }

    func testDelegatePersistsWithCachedFrameAfterWindowUnregistration() async throws {
        let directory = try makeFixture()
        let store = ComparisonSessionStore(
            fileURL: directory.appending(path: "ComparisonSession.json")
        )
        let model = ComparisonModel()
        model.createEmptyComparison()
        let delegate = ApplicationDelegate(model: model, sessionStore: store)
        await delegate.loadInitialComparison(arguments: [])
        let frame = NSRect(x: 30, y: 40, width: 900, height: 700)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        delegate.registerComparisonWindow(window, replacing: nil)
        window.setFrame(NSRect(x: 60, y: 70, width: 1000, height: 750), display: false)
        let expectedFrame = window.frame
        delegate.registerComparisonWindow(nil, replacing: window)

        let persisted = expectation(description: "session persisted")
        delegate.persistSession { succeeded in
            XCTAssertTrue(succeeded)
            persisted.fulfill()
        }
        await fulfillment(of: [persisted], timeout: 2)

        let state = try XCTUnwrap(store.load())
        XCTAssertEqual(state.windowFrame.x, expectedFrame.origin.x)
        XCTAssertEqual(state.windowFrame.y, expectedFrame.origin.y)
        XCTAssertEqual(state.windowFrame.width, expectedFrame.width)
        XCTAssertEqual(state.windowFrame.height, expectedFrame.height)
        XCTAssertNil(model.errorMessage)
    }

    func testDelegatePersistsLatestFrameAfterComparisonWindowCloses() async throws {
        let directory = try makeFixture()
        let store = ComparisonSessionStore(
            fileURL: directory.appending(path: "ComparisonSession.json")
        )
        let model = ComparisonModel()
        model.createEmptyComparison()
        let delegate = ApplicationDelegate(model: model, sessionStore: store)
        await delegate.loadInitialComparison(arguments: [])
        let window = NSWindow(
            contentRect: NSRect(x: 30, y: 40, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        delegate.registerComparisonWindow(window, replacing: nil)
        window.setFrame(NSRect(x: 80, y: 90, width: 1100, height: 800), display: false)
        let expectedFrame = window.frame
        window.delegate?.windowWillClose?(
            Notification(name: NSWindow.willCloseNotification, object: window)
        )

        let persisted = expectation(description: "session persisted")
        delegate.persistSession { succeeded in
            XCTAssertTrue(succeeded)
            persisted.fulfill()
        }
        await fulfillment(of: [persisted], timeout: 2)

        let state = try XCTUnwrap(store.load())
        XCTAssertEqual(state.windowFrame.x, expectedFrame.origin.x)
        XCTAssertEqual(state.windowFrame.y, expectedFrame.origin.y)
        XCTAssertEqual(state.windowFrame.width, expectedFrame.width)
        XCTAssertEqual(state.windowFrame.height, expectedFrame.height)
        XCTAssertNil(model.errorMessage)
    }

    func testForwardedCloseVetoPreventsSideEffectsAndApprovedRetryDoesNotAskAgain() async throws {
        let directory = try makeFixture()
        let store = ComparisonSessionStore(
            fileURL: directory.appending(path: "ComparisonSession.json")
        )
        let model = ComparisonModel()
        model.createEmptyComparison()
        var closeRequestCount = 0
        let delegate = ApplicationDelegate(
            model: model,
            sessionStore: store,
            performComparisonWindowClose: { _ in closeRequestCount += 1 }
        )
        await delegate.loadInitialComparison(arguments: [])
        let forwardingDelegate = SequencedCloseDelegate(results: [false, true, false])
        let window = NSWindow(
            contentRect: NSRect(x: 30, y: 40, width: 900, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.delegate = forwardingDelegate
        delegate.registerComparisonWindow(window, replacing: nil)

        XCTAssertFalse(window.delegate?.windowShouldClose?(window) ?? true)
        XCTAssertEqual(forwardingDelegate.callCount, 1)
        XCTAssertNil(try store.load())

        XCTAssertFalse(window.delegate?.windowShouldClose?(window) ?? true)
        await waitUntil { closeRequestCount == 1 }
        XCTAssertEqual(forwardingDelegate.callCount, 2)
        XCTAssertNotNil(try store.load())
        XCTAssertTrue(window.delegate?.windowShouldClose?(window) ?? false)
        XCTAssertEqual(forwardingDelegate.callCount, 2)
    }

    func testDelegateInvalidExplicitArgumentsDoNotRestoreStoredSession() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let store = ComparisonSessionStore(fileURL: fileURL)
        try store.save(try makeState())
        let existing = directory.appending(path: "existing.txt")
        try Data("existing".utf8).write(to: existing)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: store
        )

        await delegate.loadInitialComparison(
            arguments: [existing.path, directory.appending(path: "missing.txt").path]
        )

        XCTAssertFalse(delegate.model.left.isLoaded)
        XCTAssertFalse(delegate.model.right.isLoaded)
        XCTAssertNotNil(delegate.model.errorMessage)
        XCTAssertEqual(try store.load(), try makeState())
    }

    func testDelegateClearsMalformedButPreservesUnloadableStoredSessions() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let store = ComparisonSessionStore(fileURL: fileURL)
        try Data("not json".utf8).write(to: fileURL)
        var delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: store
        )

        await delegate.loadInitialComparison(arguments: [])
        await waitUntil { !FileManager.default.fileExists(atPath: fileURL.path) }
        XCTAssertNotNil(delegate.model.errorMessage)

        let missingState = try ComparisonSessionState(
            left: .scratchpad("left"),
            right: .file(directory.appending(path: "missing.txt")),
            windowFrame: try makeFrame()
        )
        try store.save(missingState)
        delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: store
        )
        await delegate.loadInitialComparison(arguments: [])
        await waitUntilIdle(delegate.model)

        XCTAssertEqual(try store.load(), missingState)
        XCTAssertFalse(delegate.model.left.isLoaded)
        XCTAssertFalse(delegate.model.right.isLoaded)
        XCTAssertNotNil(delegate.model.errorMessage)
    }

    func testDelegatePreservesUnsupportedFutureSession() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        var data = try makeState().encodedData()
        let oldVersion = Data(#""schemaVersion":1"#.utf8)
        let range = try XCTUnwrap(data.range(of: oldVersion))
        data.replaceSubrange(range, with: Data(#""schemaVersion":2"#.utf8))
        try data.write(to: fileURL)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: ComparisonSessionStore(fileURL: fileURL)
        )

        await delegate.loadInitialComparison(arguments: [])

        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertFalse(delegate.model.left.isLoaded)
        XCTAssertNotNil(delegate.model.errorMessage)
    }

    func testDelegatePreservesLargerFutureSessionBeforeV1Bounds() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        var data = Data(#"{"schemaVersion":2,"payload":""#.utf8)
        data.append(Data(repeating: 0x78, count: ComparisonSessionState.maximumEncodedBytes))
        data.append(Data(#""}"#.utf8))
        try data.write(to: fileURL)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: ComparisonSessionStore(fileURL: fileURL)
        )

        await delegate.loadInitialComparison(arguments: [])

        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertNotNil(delegate.model.errorMessage)
    }

    func testDelegatePreservesDeepFutureSessionBeforeV1Bounds() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let nesting =
            String(repeating: "[", count: 24)
            + "true"
            + String(repeating: "]", count: 24)
        let data = Data(#"{"schemaVersion":2,"payload":\#(nesting)}"#.utf8)
        try data.write(to: fileURL)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: ComparisonSessionStore(fileURL: fileURL)
        )

        await delegate.loadInitialComparison(arguments: [])

        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertNotNil(delegate.model.errorMessage)
    }

    func testDelegatePreservesFutureSessionWhenSchemaProbeLimitIsExceeded() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        let nesting =
            String(repeating: "[", count: 80)
            + "true"
            + String(repeating: "]", count: 80)
        let data = Data(#"{"payload":\#(nesting),"schemaVersion":2}"#.utf8)
        try data.write(to: fileURL)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: ComparisonSessionStore(fileURL: fileURL)
        )

        await delegate.loadInitialComparison(arguments: [])

        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertNotNil(delegate.model.errorMessage)
    }

    func testDelegateClearsObsoleteSessionVersion() async throws {
        let directory = try makeFixture()
        let fileURL = directory.appending(path: "ComparisonSession.json")
        try Data(#"{"schemaVersion":0}"#.utf8).write(to: fileURL)
        let delegate = ApplicationDelegate(
            model: ComparisonModel(),
            sessionStore: ComparisonSessionStore(fileURL: fileURL)
        )

        await delegate.loadInitialComparison(arguments: [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNotNil(delegate.model.errorMessage)
    }

    private func makeState() throws -> ComparisonSessionState {
        try ComparisonSessionState(
            left: .scratchpad("left"),
            right: .scratchpad("right"),
            leftReadOnly: true,
            activeSide: .right,
            windowFrame: try makeFrame()
        )
    }

    private func makeFrame() throws -> ComparisonSessionState.WindowFrame {
        try ComparisonSessionState.WindowFrame(
            x: 10,
            y: 20,
            width: 800,
            height: 600
        )
    }

    private func makeFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func waitUntilIdle(_ model: ComparisonModel) async {
        await withCheckedContinuation { continuation in
            model.whenIdle { continuation.resume() }
        }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class SequencedCloseDelegate: NSObject, NSWindowDelegate {
    private var results: [Bool]
    private(set) var callCount = 0

    init(results: [Bool]) {
        self.results = results
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        defer { callCount += 1 }
        return results.indices.contains(callCount) ? results[callCount] : true
    }
}
