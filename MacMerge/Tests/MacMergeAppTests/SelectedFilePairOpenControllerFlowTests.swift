import Foundation
import XCTest

@testable import MacMerge
@testable import MacMergeCore

/// End-to-end coverage of `SelectedFilePairOpenController` with the real planner and model.
@MainActor
final class SelectedFilePairOpenControllerFlowTests: XCTestCase {
    private typealias Batch = SelectedFilePairTextOpenBatch

    nonisolated(unsafe) private var workspace: URL!
    nonisolated private var leftRoot: URL { workspace.appendingPathComponent("left", isDirectory: true) }
    nonisolated private var rightRoot: URL { workspace.appendingPathComponent("right", isDirectory: true) }

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectedFilePairOpenControllerFlowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: leftRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rightRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
    }

    // MARK: - Opening

    func testOpenLoadsFirstPairAndQueuesTheRest() async throws {
        let results = try makeTextResults(["a.txt", "b.txt", "c.txt"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()

        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntilIdle(model)

        XCTAssertEqual(controller.pairs.map(\.leftRelativePath), ["a.txt", "b.txt", "c.txt"])
        XCTAssertTrue(controller.hasQueuedPairs)
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.left.url?.lastPathComponent, "a.txt")
        XCTAssertEqual(model.right.url?.lastPathComponent, "a.txt")
        XCTAssertEqual(controller.currentIndex(in: model), 0)
        XCTAssertNil(model.errorMessage, "No rows were skipped, so no alert is shown")
    }

    func testStepCommandsWalkTheQueueAndDisableAtTheEnds() async throws {
        let results = try makeTextResults(["a.txt", "b.txt", "c.txt"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()
        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntilIdle(model)

        XCTAssertFalse(controller.canMove(.first, model: model))
        XCTAssertFalse(controller.canMove(.previous, model: model))
        XCTAssertTrue(controller.canMove(.next, model: model))
        XCTAssertTrue(controller.canMove(.last, model: model))

        controller.move(.next, model: model)
        await waitUntilIdle(model)
        XCTAssertEqual(controller.currentIndex(in: model), 1)
        XCTAssertEqual(model.left.url?.lastPathComponent, "b.txt")
        XCTAssertTrue(controller.canMove(.previous, model: model))
        XCTAssertTrue(controller.canMove(.first, model: model))

        controller.move(.last, model: model)
        await waitUntilIdle(model)
        XCTAssertEqual(controller.currentIndex(in: model), 2)
        XCTAssertFalse(controller.canMove(.next, model: model))
        XCTAssertFalse(controller.canMove(.last, model: model))

        // Next at the end of the queue stays on the last pair.
        controller.move(.next, model: model)
        await waitUntilIdle(model)
        XCTAssertEqual(controller.currentIndex(in: model), 2)

        controller.move(.previous, model: model)
        await waitUntilIdle(model)
        XCTAssertEqual(controller.currentIndex(in: model), 1)

        controller.move(.first, model: model)
        await waitUntilIdle(model)
        XCTAssertEqual(controller.currentIndex(in: model), 0)
        XCTAssertEqual(model.left.url?.lastPathComponent, "a.txt")
    }

    func testSinglePairDoesNotExposeStepCommands() async throws {
        let results = try makeTextResults(["only.txt"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()

        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntilIdle(model)

        XCTAssertEqual(controller.pairs.count, 1)
        XCTAssertFalse(controller.hasQueuedPairs)
        XCTAssertEqual(model.left.url?.lastPathComponent, "only.txt")
    }

    func testUnrelatedOpenLeavesTheQueueWithoutACurrentPair() async throws {
        let results = try makeTextResults(["a.txt", "b.txt"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()
        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntilIdle(model)

        let other = workspace.appendingPathComponent("other.txt")
        try Data("other\n".utf8).write(to: other)
        model.enqueueOpen([other, other])
        await waitUntilIdle(model)

        XCTAssertNil(controller.currentIndex(in: model))
        XCTAssertFalse(controller.canMove(.next, model: model))
        XCTAssertFalse(controller.canMove(.previous, model: model))
        XCTAssertTrue(controller.canMove(.first, model: model))
        XCTAssertTrue(controller.canMove(.last, model: model))
    }

    func testSkippedRowsAreReportedAfterTheOpenSettles() async throws {
        let results = try makeResults(text: ["a.txt", "b.txt"], binary: ["z.bin"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()

        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntil { model.errorMessage != nil }

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.hasPrefix("Opening the first of 2 text comparisons"), message)
        XCTAssertTrue(message.contains("1 selected item was skipped."), message)
        XCTAssertTrue(message.contains("z.bin: left file is binary"), message)
        XCTAssertEqual(model.left.url?.lastPathComponent, "a.txt")
    }

    func testNothingOpenableReportsWithoutLoadingOrQueueing() async throws {
        let results = try makeResults(text: [], binary: ["x.bin", "y.bin"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()

        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }

        XCTAssertTrue(controller.pairs.isEmpty)
        XCTAssertNil(model.left.url)
        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(
            message.hasPrefix("None of the 2 selected items can be opened as a text comparison."),
            message
        )
    }

    func testNothingOpenablePlanKeepsAnEarlierQueue() async throws {
        let results = try makeResults(text: ["a.txt", "b.txt"], binary: ["z.bin"])
        let ids = idsByPath(results)
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()
        await controller.open(results, selectedIDs: [ids["a.txt"]!, ids["b.txt"]!], into: model).value
        await waitUntilIdle(model)

        await controller.open(results, selectedIDs: [ids["z.bin"]!], into: model).value
        await waitUntilIdle(model)

        XCTAssertEqual(controller.pairs.map(\.leftRelativePath), ["a.txt", "b.txt"])
        XCTAssertEqual(model.left.url?.lastPathComponent, "a.txt")
        XCTAssertEqual(controller.currentIndex(in: model), 0)
        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(
            message.hasPrefix("None of the 1 selected items can be opened as a text comparison."),
            message
        )
    }

    func testPlanningErrorIsShownAndKeepsAnEarlierQueue() async throws {
        let results = try makeTextResults(["a.txt", "b.txt"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()
        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntilIdle(model)

        controller.open(results, selectedIDs: [], into: model)
        await waitUntil { !controller.isPlanning }

        XCTAssertEqual(model.errorMessage, Batch.Error.emptySelection.localizedDescription)
        XCTAssertEqual(controller.pairs.count, 2)
    }

    func testSelectionTooLargeIsReportedFromLimits() async throws {
        let results = try makeTextResults(["a.txt", "b.txt"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()

        controller.open(results, into: model, limits: Batch.Limits(maximumSelectedResults: 1))
        await waitUntil { !controller.isPlanning }

        XCTAssertEqual(
            model.errorMessage,
            Batch.Error.selectionTooLarge(count: 2, maximum: 1).localizedDescription
        )
        XCTAssertTrue(controller.pairs.isEmpty)
    }

    func testResetForgetsTheQueueButKeepsTheLoadedComparison() async throws {
        let results = try makeTextResults(["a.txt", "b.txt"])
        let controller = SelectedFilePairOpenController()
        let model = ComparisonModel()
        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntilIdle(model)

        controller.reset()

        XCTAssertTrue(controller.pairs.isEmpty)
        XCTAssertNil(controller.requestedIndex)
        XCTAssertFalse(controller.hasQueuedPairs)
        XCTAssertEqual(model.left.url?.lastPathComponent, "a.txt")
    }

    func testCancelledPlanResultIsNeverApplied() async throws {
        let results = try makeTextResults(["a.txt", "b.txt"])
        let gate = PlannerGate()
        defer { gate.release() }
        let probe = PlanReturnProbe()
        let realPlanner = SelectedFilePairOpenController.defaultPlanner
        let controller = SelectedFilePairOpenController { results, ids, limits, _ in
            _ = probe.begin()
            gate.wait()
            // Ignores cancellation, so a real successful plan reaches the controller.
            return probe.record(realPlanner(results, ids, limits) { false })
        }
        let model = ComparisonModel()

        let task = controller.open(results, into: model)
        XCTAssertTrue(controller.isPlanning)
        controller.cancelPlanning()
        gate.release()
        await task.value

        XCTAssertEqual(probe.returnedPairCounts, [2], "The planner returned a successful plan")
        XCTAssertFalse(controller.isPlanning)
        XCTAssertTrue(controller.pairs.isEmpty)
        XCTAssertNil(controller.requestedIndex)
        XCTAssertNil(model.left.url)
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.errorMessage)
    }

    func testStaleSuccessfulPlanFinishingAfterANewerRequestIsDropped() async throws {
        let results = try makeTextResults(["a.txt", "b.txt", "c.txt", "d.txt"])
        let ids = idsByPath(results)
        let gate = PlannerGate()
        defer { gate.release() }
        let probe = PlanReturnProbe()
        let realPlanner = SelectedFilePairOpenController.defaultPlanner
        let controller = SelectedFilePairOpenController { results, ids, limits, _ in
            if probe.begin() == 1 {
                gate.wait()
            }
            // Ignores cancellation, so the first request still produces a successful plan.
            return probe.record(realPlanner(results, ids, limits) { false })
        }
        let model = ComparisonModel()

        let first = controller.open(results, selectedIDs: [ids["a.txt"]!, ids["b.txt"]!], into: model)
        await waitUntil { probe.calls == 1 }
        let second = controller.open(results, selectedIDs: [ids["c.txt"]!, ids["d.txt"]!], into: model)
        await second.value
        await waitUntilIdle(model)
        XCTAssertEqual(model.left.url?.lastPathComponent, "c.txt")

        gate.release()
        await first.value
        await waitUntilIdle(model)

        XCTAssertEqual(probe.returnedPairCounts, [2, 2], "Both planners returned successful plans")
        XCTAssertEqual(controller.pairs.map(\.leftRelativePath), ["c.txt", "d.txt"])
        XCTAssertEqual(model.left.url?.lastPathComponent, "c.txt")
        XCTAssertEqual(model.right.url?.lastPathComponent, "c.txt")
        XCTAssertEqual(controller.currentIndex(in: model), 0)
        XCTAssertFalse(controller.isPlanning)
        XCTAssertNil(model.errorMessage)
    }

    func testApplicationDelegateEntryPointOpensIntoItsModel() async throws {
        let results = try makeTextResults(["a.txt", "b.txt"])
        let model = ComparisonModel()
        let delegate = ApplicationDelegate(
            model: model,
            sessionStore: ComparisonSessionStore(fileURL: workspace.appending(path: "session.json"))
        )

        delegate.openSelectedFilePairs(in: results)
        XCTAssertTrue(delegate.selectedFilePairOpener.isPlanning)
        await waitUntil { !delegate.selectedFilePairOpener.isPlanning }
        await waitUntilIdle(model)

        XCTAssertEqual(model.left.url?.lastPathComponent, "a.txt")
        XCTAssertEqual(delegate.selectedFilePairOpener.pairs.count, 2)
        XCTAssertTrue(delegate.selectedFilePairOpener.hasQueuedPairs)
    }

    // MARK: - Unsaved-changes confirmation

    func testPendingConfirmationDefersSkippedMessageAndDisablesMoves() async throws {
        let results = try makeResults(text: ["a.txt", "b.txt"], binary: ["z.bin"])
        let model = try await makeDirtyModel()

        let controller = SelectedFilePairOpenController()
        controller.open(results, into: model)
        await waitUntil { !controller.isPlanning }
        await waitUntil { model.pendingExternalOpenURLs != nil }
        // Let any premature idle delivery run before checking it did not happen.
        await settle(model)

        XCTAssertNil(model.errorMessage, "Skipped-rows alert must wait for the confirmation")
        XCTAssertNil(controller.currentIndex(in: model), "The pair is not shown yet")
        for command in DirectoryPairNavigationCommand.allCases {
            XCTAssertFalse(controller.canMove(command, model: model))
        }

        model.cancelPendingExternalOpen()
        await waitUntil { model.errorMessage != nil }

        XCTAssertEqual(model.left.url?.lastPathComponent, "dirty-left.txt", "The canceled open keeps the dirty comparison")
        XCTAssertNil(controller.currentIndex(in: model))
        XCTAssertTrue(model.errorMessage?.contains("z.bin: left file is binary") == true)
        XCTAssertTrue(controller.canMove(.first, model: model))
        XCTAssertFalse(controller.canMove(.next, model: model))
    }

    func testDiscardingChangesOpensThePairAndThenReportsSkippedRows() async throws {
        let results = try makeResults(text: ["a.txt"], binary: ["z.bin"])
        let model = try await makeDirtyModel()

        let controller = SelectedFilePairOpenController()
        controller.open(results, into: model)
        await waitUntil { model.pendingExternalOpenURLs != nil }
        XCTAssertNil(model.errorMessage)

        model.discardChangesAndAcceptPendingExternalOpen()
        await waitUntil { model.errorMessage != nil }

        XCTAssertEqual(model.left.url?.lastPathComponent, "a.txt")
        XCTAssertEqual(controller.currentIndex(in: model), 0)
        XCTAssertTrue(model.errorMessage?.hasPrefix("Opening 1 text comparison;") == true)
    }

    func testMoveIsIgnoredWhileAConfirmationIsPending() async throws {
        let results = try makeTextResults(["a.txt", "b.txt"])
        let model = try await makeDirtyModel()
        let controller = SelectedFilePairOpenController()
        await controller.open(results, into: model).value
        await waitUntil { model.pendingExternalOpenURLs != nil }
        let pending = model.pendingExternalOpenURLs
        XCTAssertEqual(controller.requestedIndex, 0)

        // Last has a destination (the model shows neither pair), so only the pending guard stops it.
        controller.move(.last, model: model)

        XCTAssertEqual(controller.requestedIndex, 0)
        XCTAssertEqual(model.pendingExternalOpenURLs, pending)
        model.cancelPendingExternalOpen()
        await waitUntilIdle(model)
        XCTAssertEqual(model.left.url?.lastPathComponent, "dirty-left.txt", "No open of b.txt was queued")
        XCTAssertNil(model.pendingExternalOpenURLs)
    }

    func testResetWhileConfirmationIsPendingDropsTheDeferredMessage() async throws {
        let results = try makeResults(text: ["a.txt"], binary: ["z.bin"])
        let model = try await makeDirtyModel()
        let controller = SelectedFilePairOpenController()
        await controller.open(results, into: model).value
        await waitUntil { model.pendingExternalOpenURLs != nil }

        controller.reset()
        model.cancelPendingExternalOpen()
        await settle(model)

        XCTAssertNil(model.errorMessage, "A newer generation drops the deferred skipped-rows message")
    }

    func testNewerOpenWhileConfirmationIsPendingDropsTheDeferredMessage() async throws {
        let results = try makeResults(text: ["a.txt"], binary: ["z.bin"])
        let ids = idsByPath(results)
        let model = try await makeDirtyModel()
        let controller = SelectedFilePairOpenController()
        await controller.open(results, into: model).value
        await waitUntil { model.pendingExternalOpenURLs != nil }

        // The newer request has nothing to skip, so any message must come from the stale one.
        await controller.open(results, selectedIDs: [ids["a.txt"]!], into: model).value
        model.cancelPendingExternalOpen()
        await settle(model)
        model.cancelPendingExternalOpen()
        await settle(model)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(controller.pairs.map(\.leftRelativePath), ["a.txt"])
    }

    func testSkippedMessageIsAppendedToAnExistingError() async throws {
        let results = try makeResults(text: ["a.txt"], binary: ["z.bin"])
        let model = try await makeDirtyModel()
        let controller = SelectedFilePairOpenController()
        await controller.open(results, into: model).value
        await waitUntil { model.pendingExternalOpenURLs != nil }

        model.errorMessage = "prior"
        model.cancelPendingExternalOpen()
        await waitUntil { model.errorMessage != "prior" }

        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.hasPrefix("prior\n\nOpening 1 text comparison;"), message)
        XCTAssertTrue(message.contains("z.bin: left file is binary"), message)
    }

    // MARK: - Encoding choice

    func testPendingEncodingChoiceDefersSkippedMessageAndDisablesMoves() async throws {
        // ISO-2022-JP bytes that also decode as UTF-8, so the model asks which encoding to use.
        try Data([0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42])
            .write(to: leftRoot.appendingPathComponent("a-jis.txt"))
        try Data("plain\n".utf8).write(to: rightRoot.appendingPathComponent("a-jis.txt"))
        let base = try makeResults(text: ["b.txt"], binary: ["z.bin"])
        let jisRow = DirectoryResult(
            left: DirectoryEntryMetadata(relativePath: "a-jis.txt", kind: .file),
            right: DirectoryEntryMetadata(relativePath: "a-jis.txt", kind: .file),
            status: .different
        )
        let rows = base.results + [jisRow]
        let results = DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: rows,
            selectedIDs: Set(rows.map(\.id))
        )
        let model = ComparisonModel()
        let controller = SelectedFilePairOpenController()

        await controller.open(results, into: model).value
        await waitUntil { model.pendingEncodingSelection != nil }
        await settle(model)

        XCTAssertNil(model.errorMessage, "Skipped-rows alert must wait for the encoding choice")
        XCTAssertEqual(controller.pairs.map(\.leftRelativePath), ["a-jis.txt", "b.txt"])
        for command in DirectoryPairNavigationCommand.allCases {
            XCTAssertFalse(controller.canMove(command, model: model))
        }

        model.selectPendingEncoding(.iso2022JP)
        await waitUntil { model.errorMessage != nil }

        XCTAssertNil(model.pendingEncodingSelection)
        XCTAssertEqual(model.left.url?.lastPathComponent, "a-jis.txt")
        XCTAssertEqual(controller.currentIndex(in: model), 0)
        XCTAssertTrue(controller.canMove(.next, model: model))
        XCTAssertTrue(model.errorMessage?.contains("z.bin: left file is binary") == true)
    }

    // MARK: - Message

    func testMessageForOnePairAndManySkippedRowsTruncatesTheList() {
        let id = DirectoryResult.ID(leftRelativePath: "a.txt", rightRelativePath: "a.txt")
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        let pair = Batch.Pair(
            resultIDs: [id],
            leftRelativePath: "a.txt",
            rightRelativePath: "a.txt",
            leftURL: url,
            rightURL: url,
            status: .different
        )
        let rejections = (0..<8).map {
            Batch.Rejection(resultID: id, relativePath: "r\($0)", reason: .folder)
        }
        let plan = Batch.Plan(pairs: [pair], rejections: rejections, selectedCount: 9)

        let lines = SelectedFilePairOpenController.message(for: plan).components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "Opening 1 text comparison; 8 selected items were skipped.")
        XCTAssertEqual(lines.count, 1 + SelectedFilePairOpenController.maximumListedRejections + 1)
        XCTAssertEqual(lines[1], "r0: folder")
        XCTAssertEqual(lines.last, "…and 3 more.")
    }

    func testMessageForNoPairsListsEveryReasonWithinTheLimit() {
        let id = DirectoryResult.ID(leftRelativePath: "x", rightRelativePath: "x")
        let plan = Batch.Plan(
            pairs: [],
            rejections: [
                Batch.Rejection(resultID: id, relativePath: "x", reason: .missingSide(.left)),
                Batch.Rejection(resultID: id, relativePath: "y", reason: .openLimitReached)
            ],
            selectedCount: 2
        )

        let message = SelectedFilePairOpenController.message(for: plan)

        XCTAssertEqual(
            message,
            "None of the 2 selected items can be opened as a text comparison.\n"
                + "x: no left file\ny: too many files selected"
        )
    }

    // MARK: - Helpers

    private func makeTextResults(_ names: [String]) throws -> DirectoryResults {
        try makeResults(text: names, binary: [])
    }

    private func makeResults(text: [String], binary: [String]) throws -> DirectoryResults {
        for name in text {
            try Data("left \(name)\n".utf8).write(to: leftRoot.appendingPathComponent(name))
            try Data("right \(name)\n".utf8).write(to: rightRoot.appendingPathComponent(name))
        }
        for name in binary {
            try Data([0x00, 0x01]).write(to: leftRoot.appendingPathComponent(name))
            try Data([0x00, 0x02]).write(to: rightRoot.appendingPathComponent(name))
        }
        let rows = (text + binary).map {
            DirectoryResult(
                left: DirectoryEntryMetadata(relativePath: $0, kind: .file),
                right: DirectoryEntryMetadata(relativePath: $0, kind: .file),
                status: .different
            )
        }
        return DirectoryResults(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            results: rows,
            selectedIDs: Set(rows.map(\.id))
        )
    }

    private func idsByPath(_ results: DirectoryResults) -> [String: DirectoryResult.ID] {
        Dictionary(uniqueKeysWithValues: results.results.map { ($0.relativePath, $0.id) })
    }

    /// Loads two files and merges one difference, so the right side has unsaved changes.
    private func makeDirtyModel() async throws -> ComparisonModel {
        let model = ComparisonModel()
        let originalLeft = workspace.appendingPathComponent("dirty-left.txt")
        let originalRight = workspace.appendingPathComponent("dirty-right.txt")
        try Data("left\n".utf8).write(to: originalLeft)
        try Data("right\n".utf8).write(to: originalRight)
        model.enqueueOpen([originalLeft, originalRight])
        await waitUntilIdle(model)
        let rowID = try XCTUnwrap(model.rows.first(where: { $0.kind != .unchanged })?.id)
        model.merge(rowID: rowID, direction: .leftToRight)
        await waitUntilIdle(model)
        XCTAssertTrue(model.right.isDirty)
        return model
    }

    /// Runs main-actor work already scheduled (such as an observation retry), then waits for idle.
    private func settle(_ model: ComparisonModel) async {
        await Task { @MainActor in }.value
        await waitUntilIdle(model)
    }

    private func waitUntilIdle(_ model: ComparisonModel, timeout: TimeInterval = 10) async {
        let idle = IdleFlag()
        model.whenIdle { idle.isSet = true }
        await waitUntil(timeout: timeout) { idle.isSet }
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// Blocks the detached planner until the test releases it.
private final class PlannerGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func wait() { semaphore.wait() }
    func release() { semaphore.signal() }
}

/// Records each planner call and the pair count of each successful plan it returned.
private final class PlanReturnProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var pairCounts: [Int] = []

    var calls: Int { lock.withLock { callCount } }
    var returnedPairCounts: [Int] { lock.withLock { pairCounts } }

    func begin() -> Int {
        lock.withLock {
            callCount += 1
            return callCount
        }
    }

    func record(
        _ outcome: Result<SelectedFilePairTextOpenBatch.Plan, SelectedFilePairTextOpenBatch.Error>
    ) -> Result<SelectedFilePairTextOpenBatch.Plan, SelectedFilePairTextOpenBatch.Error> {
        if case .success(let plan) = outcome {
            lock.withLock { pairCounts.append(plan.pairs.count) }
        }
        return outcome
    }
}

@MainActor
private final class IdleFlag {
    var isSet = false
}
