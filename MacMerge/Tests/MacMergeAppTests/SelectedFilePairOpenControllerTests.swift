import Foundation
import XCTest

@testable import MacMerge
@testable import MacMergeCore

@MainActor
final class SelectedFilePairOpenControllerTests: XCTestCase {
    private typealias Batch = SelectedFilePairTextOpenBatch

    func testSecondOpenCancelsFirstPlansIO() async throws {
        let probe = PlannerProbe()
        let controller = SelectedFilePairOpenController { _, _, _, isCancelled in
            let call = probe.begin()
            guard call == 1 else { return .failure(.emptySelection) }
            // Simulates long sniffing I/O that polls the cancellation check between rows. It
            // outlasts the test's 5-second waits, so a missed cancel fails the wait, not the stub.
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if isCancelled() {
                    probe.recordFirstCancelled()
                    return .failure(.cancelled)
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
            return .failure(.cancelled)
        }
        let model = ComparisonModel()
        let results = DirectoryResults(
            leftRoot: FileManager.default.temporaryDirectory,
            rightRoot: FileManager.default.temporaryDirectory
        )

        controller.open(results, into: model)
        try await waitUntil { probe.calls >= 1 }
        controller.open(results, into: model)

        try await waitUntil { probe.firstCancelled }
        try await waitUntil { !controller.isPlanning }
        XCTAssertEqual(model.errorMessage, Batch.Error.emptySelection.localizedDescription)
    }

    func testCancelPlanningReachesDetachedPlanner() async throws {
        let probe = PlannerProbe()
        let controller = SelectedFilePairOpenController { _, _, _, isCancelled in
            _ = probe.begin()
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if isCancelled() {
                    probe.recordFirstCancelled()
                    break
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
            return .failure(.cancelled)
        }
        let model = ComparisonModel()
        let results = DirectoryResults(
            leftRoot: FileManager.default.temporaryDirectory,
            rightRoot: FileManager.default.temporaryDirectory
        )

        controller.open(results, into: model)
        try await waitUntil { probe.calls >= 1 }
        controller.cancelPlanning()

        try await waitUntil { probe.firstCancelled }
        XCTAssertFalse(controller.isPlanning)
        XCTAssertNil(model.errorMessage)
    }

    func testMessageSaysOnlyTheFirstOfSeveralPairsOpens() {
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        let id = DirectoryResult.ID(leftRelativePath: "a.txt", rightRelativePath: "a.txt")
        let pair = Batch.Pair(
            resultIDs: [id],
            leftRelativePath: "a.txt",
            rightRelativePath: "a.txt",
            leftURL: url,
            rightURL: url,
            status: .different
        )
        let skipped = Batch.Rejection(resultID: id, relativePath: "b.bin", reason: .nonText(.left))
        let plan = Batch.Plan(pairs: [pair, pair, pair], rejections: [skipped], selectedCount: 4)

        let message = SelectedFilePairOpenController.message(for: plan)

        XCTAssertTrue(message.hasPrefix("Opening the first of 3 text comparisons"), message)
        XCTAssertTrue(message.contains("Merge > Next Selected File Pair"), message)
        XCTAssertTrue(message.contains("1 selected item was skipped."), message)
        XCTAssertTrue(message.contains("b.bin: left file is binary"), message)
        XCTAssertFalse(message.contains("Opened 3"), message)
    }

    func testNoQueuedPairsDisablesEveryMove() {
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()

        XCTAssertFalse(controller.hasQueuedPairs)
        for command in DirectoryPairNavigationCommand.allCases {
            XCTAssertFalse(controller.canMove(command, model: model))
        }
        XCTAssertNil(controller.currentIndex(in: model))
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class PlannerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var cancelled = false

    var calls: Int { lock.withLock { callCount } }
    var firstCancelled: Bool { lock.withLock { cancelled } }

    func begin() -> Int {
        lock.withLock {
            callCount += 1
            return callCount
        }
    }

    func recordFirstCancelled() {
        lock.withLock { cancelled = true }
    }
}
