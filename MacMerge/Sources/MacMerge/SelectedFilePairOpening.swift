import Foundation
import MacMergeCore
import Observation
import SwiftUI

/// Opens selected folder-result file pairs as two-pane text comparisons.
///
/// The app currently hosts one comparison window, so only the first accepted pair is loaded; the
/// remaining accepted pairs stay queued in visible folder-result order. The Merge-menu Selected
/// File Pair commands load queued pairs into the comparison window through the model's normal open
/// queue, which keeps its unsaved-changes confirmation.
///
/// The position in the queue is derived from the files the model actually shows, so a canceled
/// confirmation, a failed load, or an unrelated open (File > Open, drag, session restore) never
/// leaves the commands stepping from a pair that is not displayed.
@Observable
@MainActor
final class SelectedFilePairOpenController {
    typealias Batch = SelectedFilePairTextOpenBatch
    typealias Planner =
        @Sendable (
            DirectoryResults,
            Set<DirectoryResult.ID>?,
            Batch.Limits,
            @escaping Batch.CancellationCheck
        ) -> Result<Batch.Plan, Batch.Error>

    static let maximumListedRejections = 5

    static let defaultPlanner: Planner = { results, selectedIDs, limits, isCancelled in
        Result { () throws(Batch.Error) -> Batch.Plan in
            try Batch.plan(
                results: results,
                selectedIDs: selectedIDs,
                limits: limits,
                isCancelled: isCancelled
            )
        }
    }

    private(set) var pairs: [Batch.Pair] = []
    private(set) var isPlanning = false
    /// Index of the most recently requested pair. It is only trusted while the model shows it.
    private(set) var requestedIndex: Int?

    @ObservationIgnored private let planner: Planner
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var planningTask: Task<Void, Never>?
    @ObservationIgnored private var planCancellation: PlanCancellation?

    init(planner: @escaping Planner = SelectedFilePairOpenController.defaultPlanner) {
        self.planner = planner
    }

    /// Whether the Merge-menu stepping commands have anything to step through.
    var hasQueuedPairs: Bool { pairs.count > 1 }

    /// Index of the queued pair the model currently shows, or `nil` when it shows something else.
    func currentIndex(in model: ComparisonModel) -> Int? {
        guard let leftURL = model.left.url, let rightURL = model.right.url else { return nil }
        let matches = { (index: Int) -> Bool in
            Self.sameFile(self.pairs[index].leftURL, leftURL)
                && Self.sameFile(self.pairs[index].rightURL, rightURL)
        }
        if let requestedIndex, pairs.indices.contains(requestedIndex), matches(requestedIndex) {
            return requestedIndex
        }
        return pairs.indices.first(where: matches)
    }

    /// Plans `selectedIDs` (or the results' selection) off the main thread, then opens the first
    /// accepted pair in `model`. A newer request cancels the I/O of any request still planning.
    ///
    /// The returned task finishes once the request's outcome was applied or dropped as stale.
    @discardableResult
    func open(
        _ results: DirectoryResults,
        selectedIDs: Set<DirectoryResult.ID>? = nil,
        into model: ComparisonModel,
        limits: Batch.Limits = .default
    ) -> Task<Void, Never> {
        cancelPlanning()
        let requestGeneration = generation
        let cancellation = PlanCancellation()
        planCancellation = cancellation
        isPlanning = true
        let planner = planner
        let task = Task { [weak self, weak model] in
            let detached = Task.detached(priority: .userInitiated) {
                planner(results, selectedIDs, limits) { cancellation.isCancelled }
            }
            let outcome = await withTaskCancellationHandler {
                await detached.value
            } onCancel: {
                cancellation.cancel()
                detached.cancel()
            }
            guard let self, let model, self.generation == requestGeneration else { return }
            self.isPlanning = false
            self.planningTask = nil
            self.planCancellation = nil
            self.apply(outcome, to: model)
        }
        planningTask = task
        return task
    }

    func cancelPlanning() {
        planCancellation?.cancel()
        planCancellation = nil
        planningTask?.cancel()
        planningTask = nil
        generation &+= 1
        isPlanning = false
    }

    /// Forgets the queued pairs. Comparisons already loaded stay open.
    func reset() {
        cancelPlanning()
        pairs = []
        requestedIndex = nil
    }

    func canMove(_ command: DirectoryPairNavigationCommand, model: ComparisonModel) -> Bool {
        !isPlanning
            && !model.isWorking
            && model.pendingExternalOpenURLs == nil
            && model.pendingEncodingSelection == nil
            && destination(for: command, from: currentIndex(in: model)) != nil
    }

    func move(_ command: DirectoryPairNavigationCommand, model: ComparisonModel) {
        guard canMove(command, model: model),
            let index = destination(for: command, from: currentIndex(in: model))
        else { return }
        openPair(at: index, in: model)
    }

    // MARK: - Private

    private func apply(_ outcome: Result<Batch.Plan, Batch.Error>, to model: ComparisonModel) {
        switch outcome {
        case .failure(.cancelled):
            return
        case .failure(let error):
            model.errorMessage = error.localizedDescription
        case .success(let plan):
            // Like a planning error, a plan with nothing openable keeps the earlier queue, which
            // still matches what the comparison window shows.
            guard !plan.pairs.isEmpty else {
                model.errorMessage = Self.message(for: plan)
                return
            }
            pairs = plan.pairs
            requestedIndex = nil
            openPair(at: 0, in: model)
            if !plan.rejections.isEmpty {
                deliverWhenSettled(Self.message(for: plan), to: model, generation: generation)
            }
        }
    }

    private func openPair(at index: Int, in model: ComparisonModel) {
        guard pairs.indices.contains(index) else { return }
        requestedIndex = index
        let pair = pairs[index]
        model.enqueueOpen([pair.leftURL, pair.rightURL])
    }

    /// Shows `message` only after any unsaved-changes or encoding decision for the open is settled
    /// and the open queue is idle, so it never competes with those confirmations.
    private func deliverWhenSettled(
        _ message: String,
        to model: ComparisonModel,
        generation token: UInt64
    ) {
        guard token == generation else { return }
        guard !Self.hasPendingOpenDecision(model) else {
            withObservationTracking {
                _ = model.pendingExternalOpenURLs
                _ = model.pendingEncodingSelection
            } onChange: { [weak self, weak model] in
                Task { @MainActor in
                    guard let self, let model else { return }
                    self.deliverWhenSettled(message, to: model, generation: token)
                }
            }
            return
        }
        model.whenIdle { [weak self, weak model] in
            guard let self, let model, token == self.generation else { return }
            guard !Self.hasPendingOpenDecision(model) else {
                self.deliverWhenSettled(message, to: model, generation: token)
                return
            }
            if let existing = model.errorMessage, !existing.isEmpty {
                model.errorMessage = existing + "\n\n" + message
            } else {
                model.errorMessage = message
            }
        }
    }

    private static func hasPendingOpenDecision(_ model: ComparisonModel) -> Bool {
        model.pendingExternalOpenURLs != nil || model.pendingEncodingSelection != nil
    }

    private func destination(
        for command: DirectoryPairNavigationCommand,
        from currentIndex: Int?
    ) -> Int? {
        guard !pairs.isEmpty else { return nil }
        let lastIndex = pairs.count - 1
        switch command {
        case .first:
            return currentIndex == 0 ? nil : 0
        case .last:
            return currentIndex == lastIndex ? nil : lastIndex
        case .previous:
            guard let currentIndex, currentIndex > 0 else { return nil }
            return currentIndex - 1
        case .next:
            guard let currentIndex, currentIndex < lastIndex else { return nil }
            return currentIndex + 1
        }
    }

    private static func sameFile(_ left: URL, _ right: URL) -> Bool {
        left.standardizedFileURL.path == right.standardizedFileURL.path
    }

    static func message(for plan: Batch.Plan) -> String {
        var lines: [String] = []
        let skipped = plan.rejections.count
        let skippedText = "\(skipped) selected item\(skipped == 1 ? " was" : "s were") skipped."
        switch plan.pairs.count {
        case 0:
            lines.append(
                "None of the \(plan.selectedCount) selected items can be opened as a text comparison."
            )
        case 1:
            lines.append("Opening 1 text comparison; \(skippedText)")
        case let count:
            lines.append(
                "Opening the first of \(count) text comparisons; use Merge > Next Selected File "
                    + "Pair to open the others. \(skippedText)"
            )
        }
        for rejection in plan.rejections.prefix(maximumListedRejections) {
            lines.append("\(rejection.relativePath): \(rejection.reason.summary)")
        }
        let remaining = plan.rejections.count - maximumListedRejections
        if remaining > 0 {
            lines.append("…and \(remaining) more.")
        }
        return lines.joined(separator: "\n")
    }
}

/// Cancellation flag shared with the detached planning task, which does not inherit the
/// cancellation of the task that awaits it.
private final class PlanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

extension ApplicationDelegate {
    /// Entry point for folder-result views: opens the selected file pairs as text comparisons.
    /// No folder-results view calls it yet.
    func openSelectedFilePairs(
        in results: DirectoryResults,
        selectedIDs: Set<DirectoryResult.ID>? = nil
    ) {
        selectedFilePairOpener.open(results, selectedIDs: selectedIDs, into: model)
    }
}

/// Merge-menu items that step through the queued selected file pairs.
///
/// WinMerge's First/Previous/Next/Last File (`ID_FIRSTFILE`...`ID_LASTFILE`) walk the folder
/// results. Without a folder-results view, these items walk only the queue built by
/// `openSelectedFilePairs`, and they appear only while more than one pair is queued.
struct SelectedFilePairMenuItems: View {
    let applicationDelegate: ApplicationDelegate

    private var controller: SelectedFilePairOpenController {
        applicationDelegate.selectedFilePairOpener
    }
    private var model: ComparisonModel { applicationDelegate.model }

    var body: some View {
        if controller.hasQueuedPairs {
            Divider()
            item("First Selected File Pair", .first)
            item("Previous Selected File Pair", .previous)
            item("Next Selected File Pair", .next)
            item("Last Selected File Pair", .last)
        }
    }

    private func item(_ title: String, _ command: DirectoryPairNavigationCommand) -> some View {
        Button(title) {
            controller.move(command, model: model)
        }
        .disabled(!controller.canMove(command, model: model))
    }
}
