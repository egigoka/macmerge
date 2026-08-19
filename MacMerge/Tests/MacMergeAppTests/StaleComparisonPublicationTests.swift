import Foundation
@testable import MacMerge
import MacMergeCore
import XCTest

@MainActor
final class StaleComparisonPublicationTests: XCTestCase {
    func testOverlappingComparisonsPublishOnlyNewestResult() async {
        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText("seed left\n", on: .left)
        model.editText("seed right\n", on: .right)
        await waitUntilCurrent(model)
        XCTAssertEqual(model.summary.differences, 1)
        let revision = model.rowsRevision

        model.editText("canceled left\n", on: .left)
        model.editText("canceled right\n", on: .right)
        model.editText("newest\n", on: .left)
        model.editText("newest\n", on: .right)
        await waitUntilCurrent(model)

        XCTAssertEqual(model.left.text, "newest\n")
        XCTAssertEqual(model.right.text, "newest\n")
        XCTAssertEqual(model.summary.differences, 0)
        XCTAssertEqual(model.rows.map(\.kind), [.unchanged])
        XCTAssertEqual(
            model.rowsRevision,
            revision + 1,
            "Canceled comparisons must not transiently publish before newest result"
        )
    }

    func testStaleOpenGenerationCannotReplaceNewerInputOrResult() async throws {
        let staleURL = try temporaryFile(name: "stale.txt", content: "stale\n")
        let newestURL = try temporaryFile(name: "newest.txt", content: "newest\n")
        let gate = CoordinatedFileGate()
        await gate.acquireExclusiveAccess(to: staleURL)
        defer { gate.release() }

        let model = ComparisonModel()
        model.createEmptyComparison()
        model.editText("newest\n", on: .right)
        await waitUntilCurrent(model)
        let revision = model.rowsRevision

        model.load(staleURL, into: .left)
        model.load(newestURL, into: .left)
        await waitUntil {
            model.left.url == newestURL && model.isComparisonCurrent
        }

        XCTAssertEqual(model.left.text, "newest\n")
        XCTAssertEqual(
            model.summary.differences,
            0,
            "Previous comparison remained current after newer open input was installed"
        )
        XCTAssertEqual(
            model.rows.map(\.kind),
            [.unchanged],
            "Current rows must describe newest open input"
        )

        gate.release()
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.url, newestURL)
        XCTAssertEqual(model.left.text, "newest\n")
        XCTAssertEqual(model.summary.differences, 0)
        XCTAssertEqual(
            model.rowsRevision,
            revision + 1,
            "Stale open must not schedule or publish a comparison"
        )
    }

    private func waitUntilCurrent(_ model: ComparisonModel) async {
        await waitUntil { model.isComparisonCurrent }
    }

    private func waitUntilIdle(_ model: ComparisonModel) async {
        await withCheckedContinuation { continuation in
            model.whenIdle {
                continuation.resume()
            }
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
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

private final class CoordinatedFileGate: @unchecked Sendable {
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var isReleased = false

    func acquireExclusiveAccess(to url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [releaseSemaphore] in
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(
                    writingItemAt: url,
                    options: .forReplacing,
                    error: &coordinationError
                ) { _ in
                    continuation.resume()
                    releaseSemaphore.wait()
                }
                XCTAssertNil(coordinationError)
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
