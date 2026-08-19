import Foundation
@testable import MacMerge
import MacMergeCore
import XCTest

@MainActor
final class ComparisonGenerationStateTests: XCTestCase {
    func testEditingMarksComparisonNonCurrentImmediately() async {
        let model = await currentScratchpad(left: "same\n", right: "same\n")

        model.editText("changed\n", on: .left)

        XCTAssertFalse(model.isComparisonCurrent)

        model.refresh()
        await waitUntilIdle(model)
        XCTAssertTrue(model.isComparisonCurrent)
    }

    func testSchedulingNewLoadKeepsPreviousComparisonCurrentWhileWorking() async throws {
        let model = await currentScratchpad(left: "old\n", right: "old\n")
        let replacement = try temporaryFile(name: "replacement.txt", content: "new\n")
        let gate = ComparisonGenerationFileGate()
        try await gate.acquireExclusiveAccess(to: replacement)
        defer { gate.release() }

        model.load(replacement, into: .left)

        XCTAssertTrue(model.isWorking)
        XCTAssertTrue(model.isComparisonCurrent)
        XCTAssertEqual(model.left.text, "old\n")
        XCTAssertFalse(model.canRefresh, "Commands must remain blocked until loading finishes")

        gate.release()
        await waitUntilIdle(model)
        XCTAssertEqual(model.left.url, replacement)
        XCTAssertTrue(model.isComparisonCurrent)
    }

    func testNewestExplicitGenerationIsOnlyResultPublished() async {
        let model = await currentScratchpad(left: "Token 1\n", right: "token 2\n")
        let revision = model.rowsRevision
        var supersededOptions = model.options
        supersededOptions.ignoreCase = true
        var newestOptions = supersededOptions
        newestOptions.ignoreNumbers = true

        model.setOptions(supersededOptions)
        model.setOptions(newestOptions)

        XCTAssertFalse(model.isComparisonCurrent)
        await waitUntilIdle(model)

        XCTAssertEqual(model.options, newestOptions)
        XCTAssertEqual(model.summary.differences, 0)
        XCTAssertEqual(model.rows.map(\.kind), [.unchanged])
        XCTAssertEqual(
            model.rowsRevision,
            revision + 1,
            "Superseded generation must not publish before newest generation"
        )
        XCTAssertTrue(model.isComparisonCurrent)
        XCTAssertFalse(model.comparisonFailed)
    }

    func testCanceledPendingLiveDiffCannotRepublishAfterExplicitComparison() async {
        let model = await currentScratchpad(left: "seed left\n", right: "seed right\n")
        let revision = model.rowsRevision

        model.editText("obsolete left\n", on: .left)
        model.editText("obsolete right\n", on: .right)
        await Task.yield()
        model.editText("newest\n", on: .left)
        model.editText("newest\n", on: .right)
        model.refresh()
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.text, "newest\n")
        XCTAssertEqual(model.right.text, "newest\n")
        XCTAssertEqual(model.summary.differences, 0)
        XCTAssertEqual(model.rows.map(\.kind), [.unchanged])
        XCTAssertEqual(
            model.rowsRevision,
            revision + 1,
            "Canceled pending comparisons must not publish before the explicit result"
        )
        XCTAssertTrue(model.isComparisonCurrent)
    }

    func testFailedNewestGenerationRemainsNonCurrent() async {
        let model = await currentScratchpad(left: "left\n", right: "right\n")
        var invalidOptions = model.options
        invalidOptions.lineFilters = [LineFilterRule(pattern: "[")]

        model.setOptions(invalidOptions)

        XCTAssertFalse(model.isComparisonCurrent)
        await waitUntilIdle(model)

        XCTAssertTrue(model.comparisonFailed)
        XCTAssertFalse(model.isComparisonCurrent)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.summary, DiffSummary(rows: []))
        XCTAssertNotNil(model.errorMessage)
    }

    private func currentScratchpad(left: String, right: String) async -> ComparisonModel {
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText(left, on: .left)
        model.editText(right, on: .right)
        model.refresh()
        await waitUntilIdle(model)
        XCTAssertTrue(model.isComparisonCurrent)
        XCTAssertFalse(model.comparisonFailed)
        return model
    }

    private func waitUntilIdle(_ model: ComparisonModel, timeout: TimeInterval = 5) async {
        let idle = expectation(description: "Comparison model becomes idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: timeout)
    }

    private func temporaryFile(name: String, content: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data(content.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}

private final class ComparisonGenerationFileGate: @unchecked Sendable {
    private static let timeout: DispatchTimeInterval = .seconds(5)
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var isReleased = false

    func acquireExclusiveAccess(to url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let attempt = ComparisonGenerationFileGateAttempt(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) {
                attempt.timeOut()
            }
            DispatchQueue.global().async { [releaseSemaphore] in
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(
                    writingItemAt: url,
                    options: .forReplacing,
                    error: &coordinationError
                ) { _ in
                    attempt.grantAccess()
                    if releaseSemaphore.wait(timeout: .now() + Self.timeout) == .timedOut {
                        XCTFail("Timed out waiting to release coordinated file access")
                    }
                }
                attempt.coordinationFinished(error: coordinationError)
            }
        }
    }

    func release() {
        lock.withLock {
            guard !isReleased else { return }
            isReleased = true
            releaseSemaphore.signal()
        }
    }
}

private final class ComparisonGenerationFileGateAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var accessWasGranted = false

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func grantAccess() {
        let continuation = lock.withLock {
            accessWasGranted = true
            return takeContinuation()
        }
        continuation?.resume()
    }

    func coordinationFinished(error: NSError?) {
        let failure: Error = error.map { $0 as Error } ?? CocoaError(.fileReadUnknown)
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            guard !accessWasGranted else { return nil }
            return takeContinuation()
        }
        continuation?.resume(throwing: failure)
    }

    func timeOut() {
        let continuation = lock.withLock { takeContinuation() }
        continuation?.resume(throwing: ComparisonGenerationFileGateError.timedOut)
    }

    private func takeContinuation() -> CheckedContinuation<Void, Error>? {
        defer { continuation = nil }
        return continuation
    }
}

private enum ComparisonGenerationFileGateError: Error {
    case timedOut
}
