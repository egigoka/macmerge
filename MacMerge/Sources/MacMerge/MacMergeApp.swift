import AppKit
import Darwin
import MacMergeCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@main
struct MacMergeApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        Window("MacMerge", id: "comparison") {
            ComparisonView(model: applicationDelegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = ComparisonModel()

    func application(_ application: NSApplication, open urls: [URL]) {
        application.activate()
        application.windows.first?.makeKeyAndOrderFront(nil)
        model.enqueueOpen(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sender.keyWindow?.makeFirstResponder(nil)
        model.suspendQueuedOpenRequests()
        guard !model.hasPendingSaveWarning else {
            restoreComparisonWindow(sender)
            model.resumeQueuedOpenRequests()
            return .terminateCancel
        }
        guard !model.isWorking else {
            model.whenIdle { [weak self, weak sender] in
                guard let self, let sender else { return }
                self.completeTerminationRequest(sender)
            }
            return .terminateLater
        }
        let reply = terminationReply(sender)
        if reply == .terminateCancel {
            restoreComparisonWindow(sender)
            model.resumeQueuedOpenRequests()
        }
        return reply
    }

    private func completeTerminationRequest(_ sender: NSApplication) {
        guard !model.hasPendingSaveWarning else {
            sender.reply(toApplicationShouldTerminate: false)
            restoreComparisonWindow(sender)
            model.resumeQueuedOpenRequests()
            return
        }
        switch terminationReply(sender) {
        case .terminateNow:
            sender.reply(toApplicationShouldTerminate: true)
        case .terminateCancel:
            sender.reply(toApplicationShouldTerminate: false)
            restoreComparisonWindow(sender)
            model.resumeQueuedOpenRequests()
        case .terminateLater:
            break
        @unknown default:
            sender.reply(toApplicationShouldTerminate: false)
        }
    }

    private func terminationReply(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !model.hasPendingSaveWarning else { return .terminateCancel }
        guard model.hasUnsavedChanges else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before quitting MacMerge?"
        alert.informativeText = "Unsaved changes will be lost if you quit without saving."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.saveAllChanges { saved in
                sender.reply(toApplicationShouldTerminate: saved)
                if !saved {
                    self.restoreComparisonWindow(sender)
                    self.model.resumeQueuedOpenRequests()
                }
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    private func restoreComparisonWindow(_ application: NSApplication) {
        application.activate()
        application.windows.first?.makeKeyAndOrderFront(nil)
    }
}

enum ComparisonSide: Equatable, Hashable, Sendable {
    case left
    case right
}

struct PendingEncodingSelection: Equatable, Sendable {
    let url: URL
    let side: ComparisonSide
    let candidates: [TextFileEncoding]
}

private struct AmbiguousOpenError: Error, Sendable {
    let request: PendingEncodingSelection
}

struct ComparedFile: Equatable, Sendable {
    struct Scratchpad: Equatable, Sendable {
        let name: String
        var text: String
        let persistedText: String
    }

    var document: TextFileDocument?
    var scratchpad: Scratchpad?

    var url: URL? { document?.url }

    var text: String {
        get { document?.text ?? scratchpad?.text ?? "" }
        set {
            if document != nil {
                document?.text = newValue
            } else if scratchpad != nil {
                scratchpad?.text = newValue
            }
        }
    }

    var isDirty: Bool {
        if let document {
            return document.isDirty
        }
        guard let scratchpad else { return false }
        return !scratchpad.text.unicodeScalars.elementsEqual(scratchpad.persistedText.unicodeScalars)
    }

    var displayName: String {
        document?.displayName ?? scratchpad?.name ?? "Choose file"
    }

    var isLoaded: Bool { document != nil || scratchpad != nil }
    var isUntitled: Bool { scratchpad != nil }

    static func scratchpad(named name: String) -> ComparedFile {
        ComparedFile(
            document: nil,
            scratchpad: Scratchpad(name: name, text: "", persistedText: "")
        )
    }
}

private struct ComparisonRenderResult: Sendable {
    let rows: [DiffRow]
    let maximumLineColumns: Int
    let differenceLocations: [DiffRow.ID: DifferenceLocation]
    let differenceIDs: [DiffRow.ID]
    let summary: DiffSummary
}

struct DifferenceLocation: Sendable {
    let rowIndex: Int
    let position: Int
}

private actor ComparisonWorker {
    func compare(left: String, right: String) throws -> ComparisonRenderResult {
        try Task.checkCancellation()
        return try computeComparison(left: left, right: right)
    }
}

private func computeComparison(left: String, right: String) throws -> ComparisonRenderResult {
    let rows = try LineDiff.compare(left: left, right: right)
    var maximumLineColumns = 0
    var differenceLocations: [DiffRow.ID: DifferenceLocation] = [:]
    var differenceIDs: [DiffRow.ID] = []
    differenceLocations.reserveCapacity(rows.count / 4)
    for (index, row) in rows.enumerated() {
        maximumLineColumns = max(
            maximumLineColumns,
            row.left.map { displayColumnCount($0.text) } ?? 0,
            row.right.map { displayColumnCount($0.text) } ?? 0
        )
        if row.kind != .unchanged {
            differenceLocations[row.id] = DifferenceLocation(
                rowIndex: index,
                position: differenceIDs.count
            )
            differenceIDs.append(row.id)
        }
    }
    return ComparisonRenderResult(
        rows: rows,
        maximumLineColumns: maximumLineColumns,
        differenceLocations: differenceLocations,
        differenceIDs: differenceIDs,
        summary: DiffSummary(rows: rows)
    )
}

private func displayColumnCount(_ text: String) -> Int {
    var column = 0
    for scalar in text.unicodeScalars {
        if scalar == "\t" {
            column += 8 - (column % 8)
        } else {
            column += scalar.isASCII ? 1 : 2
        }
    }
    return column
}

@Observable
@MainActor
final class ComparisonModel {
    private struct ScratchpadEditKey: Hashable {
        let side: ComparisonSide
        let rowID: DiffRow.ID
    }

    private enum OpenRequest {
        case automatic([URL])
        case side(URL, ComparisonSide)
        case replacingSide(URL, ComparisonSide)
    }

    private(set) var left = ComparedFile()
    private(set) var right = ComparedFile()
    private(set) var rowsRevision = 0
    private(set) var rows: [DiffRow] = [] {
        didSet { rowsRevision &+= 1 }
    }
    private(set) var maximumLineColumns = 0
    private(set) var differenceLocations: [DiffRow.ID: DifferenceLocation] = [:]
    private(set) var differenceIDs: [DiffRow.ID] = []
    private(set) var summary = DiffSummary(rows: [])
    private(set) var selectedDifferenceID: DiffRow.ID?
    private(set) var isWorking = false
    private(set) var comparisonFailed = false
    private(set) var isComparisonCurrent = true
    private(set) var pendingExternalOpenURLs: [URL]?
    private(set) var pendingEncodingSelection: PendingEncodingSelection?
    private(set) var hasPendingSaveWarning = false
    var errorMessage: String?

    private var loadedInitialArguments = false
    private var history = ComparisonHistory(current: ComparisonSnapshot(left: "", right: ""))
    private var activeOperationCount = 0
    private var leftLoadGeneration = 0
    private var rightLoadGeneration = 0
    private var diffGeneration = 0
    private var queuedOpenRequests: [OpenRequest] = []
    private var operationCompletions: [@MainActor () -> Void] = []
    private var idleWaiters: [@MainActor () -> Void] = []
    private var openQueueSuspended = false
    private let comparisonWorker = ComparisonWorker()
    private var pendingEncodingRetry: (@MainActor (TextFileEncoding) -> Void)?
    private var liveDiffTask: Task<Void, Never>?
    private var scratchpadEditBaselines: [ScratchpadEditKey: String] = [:]

    var isReady: Bool {
        left.isLoaded && right.isLoaded
    }

    var hasScratchpad: Bool { left.isUntitled || right.isUntitled }

    var canUndo: Bool { history.canUndo && !isWorking }
    var canRedo: Bool { history.canRedo && !isWorking }
    var hasDifferences: Bool { summary.differences > 0 && isComparisonCurrent }
    var hasUnsavedChanges: Bool { left.isDirty || right.isDirty }
    var hasSelectedDifference: Bool { selectedDifferenceID != nil && !isWorking }
    var canNavigateDifferences: Bool { hasDifferences && !isWorking }
    var canSelectPreviousDifference: Bool {
        guard canNavigateDifferences, let selectedDifferencePosition else { return canNavigateDifferences }
        return selectedDifferencePosition > 1
    }
    var canSelectNextDifference: Bool {
        guard canNavigateDifferences, let selectedDifferencePosition else { return canNavigateDifferences }
        return selectedDifferencePosition < summary.differences
    }
    var canReloadFromDisk: Bool { !isWorking && (left.url != nil || right.url != nil) }
    var hasReloadableUnsavedChanges: Bool {
        (left.document?.isDirty == true) || (right.document?.isDirty == true)
    }
    var canCreateEmptyComparison: Bool { !isWorking }

    var selectedDifferencePosition: Int? {
        guard let selectedDifferenceID else { return nil }
        return differenceLocations[selectedDifferenceID].map { $0.position + 1 }
    }

    func isDirty(_ side: ComparisonSide) -> Bool {
        side == .left ? left.isDirty : right.isDirty
    }

    func createEmptyComparison() {
        commitActiveEditor()
        guard canCreateEmptyComparison else { return }
        liveDiffTask?.cancel()
        liveDiffTask = nil
        leftLoadGeneration += 1
        rightLoadGeneration += 1
        diffGeneration += 1
        queuedOpenRequests.removeAll()
        pendingExternalOpenURLs = nil
        pendingEncodingSelection = nil
        pendingEncodingRetry = nil
        left = .scratchpad(named: "Untitled Left")
        right = .scratchpad(named: "Untitled Right")
        rows = []
        maximumLineColumns = 0
        differenceLocations = [:]
        differenceIDs = []
        summary = DiffSummary(rows: [])
        selectedDifferenceID = nil
        comparisonFailed = false
        isComparisonCurrent = true
        errorMessage = nil
        scratchpadEditBaselines.removeAll()
        history.reset(to: snapshot)
    }

    func editText(_ text: String, on side: ComparisonSide) {
        guard !isWorking, hasScratchpad else { return }
        switch side {
        case .left:
            left.text = text
        case .right:
            right.text = text
        }
        history.reset(to: snapshot)
        selectedDifferenceID = nil
        isComparisonCurrent = false
        scheduleLiveDiff()
    }

    func editScratchpadLine(rowID: DiffRow.ID, on side: ComparisonSide, replacement: String) {
        guard !isWorking, file(on: side).isUntitled else { return }
        let editKey = ScratchpadEditKey(side: side, rowID: rowID)
        let beginsEditSession = scratchpadEditBaselines[editKey] == nil
        let baselineText = scratchpadEditBaselines[editKey] ?? file(on: side).text
        scratchpadEditBaselines[editKey] = baselineText
        let rowIndex: Int
        let row: DiffRow?
        if rowID.leftNumber == nil, rowID.rightNumber == nil {
            rowIndex = rows.count
            row = nil
        } else {
            guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
            rowIndex = index
            row = rows[index]
        }
        let lineNumber = side == .left ? row?.left?.number : row?.right?.number
        let insertionIndex = rows[..<rowIndex].reduce(into: 0) { count, row in
            if side == .left ? row.left != nil : row.right != nil {
                count += 1
            }
        }
        let current = snapshot
        let editedText = LineTextEditing.replacingLine(
            in: baselineText,
            lineNumber: lineNumber,
            insertionIndex: insertionIndex,
            with: replacement
        )
        let next = ComparisonSnapshot(
            left: side == .left ? editedText : current.left,
            right: side == .right ? editedText : current.right
        )
        let changed = beginsEditSession ? history.commit(next) : history.replaceCurrent(next)
        guard changed else { return }
        apply(next)
        selectedDifferenceID = nil
        isComparisonCurrent = false
        if replacement.contains(where: { $0.isNewline }) {
            scheduleLiveDiff()
        }
    }

    func finishScratchpadLineEditing(rowID: DiffRow.ID, on side: ComparisonSide) {
        let removed = scratchpadEditBaselines.removeValue(
            forKey: ScratchpadEditKey(side: side, rowID: rowID)
        )
        if removed != nil {
            history.discardRedundantUndo()
            scheduleLiveDiff()
        }
    }

    func commitActiveEditor() {
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
    }

    func enqueueOpen(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        queuedOpenRequests.append(.automatic(Array(urls.prefix(2))))
        drainOpenRequestsIfIdle()
    }

    func enqueueOpen(_ url: URL, into side: ComparisonSide) {
        queuedOpenRequests.append(.side(url, side))
        drainOpenRequestsIfIdle()
    }

    func enqueueReplacingOpen(_ url: URL, into side: ComparisonSide) {
        queuedOpenRequests.append(.replacingSide(url, side))
        drainOpenRequestsIfIdle()
    }

    func selectPendingEncoding(_ encoding: TextFileEncoding) {
        guard pendingEncodingSelection?.candidates.contains(encoding) == true,
              let retry = pendingEncodingRetry else { return }
        pendingEncodingSelection = nil
        pendingEncodingRetry = nil
        retry(encoding)
    }

    func cancelPendingEncodingSelection() {
        pendingEncodingSelection = nil
        pendingEncodingRetry = nil
        drainOpenRequestsIfIdle()
    }

    func acceptPendingExternalOpen() {
        guard !isWorking, let urls = pendingExternalOpenURLs else { return }
        pendingExternalOpenURLs = nil
        processOpen(.automatic(urls))
    }

    func cancelPendingExternalOpen() {
        pendingExternalOpenURLs = nil
        drainOpenRequestsIfIdle()
    }

    func discardChangesAndAcceptPendingExternalOpen() {
        guard !isWorking, let urls = pendingExternalOpenURLs else { return }
        pendingExternalOpenURLs = nil
        startOpen(urls, replacingDirtyFiles: true)
    }

    func resumeQueuedOpenRequests() {
        openQueueSuspended = false
        drainOpenRequestsIfIdle()
    }

    func suspendQueuedOpenRequests() {
        openQueueSuspended = true
    }

    func whenIdle(_ action: @escaping @MainActor () -> Void) {
        idleWaiters.append(action)
        deliverIdleWaitersIfIdle()
    }

    private func processOpen(_ request: OpenRequest) {
        switch request {
        case let .automatic(urls):
            processAutomaticOpen(urls)
        case let .side(url, side):
            guard !isDirty(side) else {
                errorMessage = "Save or discard edits on the \(side == .left ? "left" : "right") side before opening another file."
                drainOpenRequestsIfIdle()
                return
            }
            load(url, into: side)
        case let .replacingSide(url, side):
            load(url, into: side)
        }
    }

    private func processAutomaticOpen(_ urls: [URL]) {
        let sides: [ComparisonSide]
        if urls.count > 1 {
            sides = [.left, .right]
        } else if !left.isLoaded {
            sides = [.left]
        } else if !right.isLoaded {
            sides = [.right]
        } else {
            sides = [.left]
        }

        let requests = Array(zip(urls.prefix(2), sides))
        for (_, side) in requests {
            guard !isDirty(side) else {
                pendingExternalOpenURLs = urls
                return
            }
        }
        startOpen(urls, replacingDirtyFiles: false)
    }

    private func startOpen(_ urls: [URL], replacingDirtyFiles: Bool) {
        let sides: [ComparisonSide]
        if urls.count > 1 {
            sides = [.left, .right]
        } else if !left.isLoaded {
            sides = [.left]
        } else if !right.isLoaded {
            sides = [.right]
        } else {
            sides = [.left]
        }

        let requests = Array(zip(urls.prefix(2), sides))
        if !replacingDirtyFiles, requests.contains(where: { isDirty($0.1) }) {
            pendingExternalOpenURLs = urls
            return
        }
        if requests.count == 2 {
            loadPair(requests[0].0, requests[1].0)
            return
        }
        for (url, side) in requests {
            load(url, into: side)
        }
    }

    private func loadPair(
        _ leftURL: URL,
        _ rightURL: URL,
        leftEncoding: TextFileEncoding? = nil,
        rightEncoding: TextFileEncoding? = nil
    ) {
        let leftGeneration = nextLoadGeneration(for: .left)
        let rightGeneration = nextLoadGeneration(for: .right)
        beginOperation()
        Task {
            do {
                let documents = try await Task.detached {
                    let leftDocument: TextFileDocument
                    do {
                        leftDocument = try leftEncoding.map {
                            try TextFileDocumentIO.load(from: leftURL, assuming: $0)
                        } ?? TextFileDocumentIO.load(from: leftURL)
                    } catch let TextFileCodecError.ambiguousTextEncoding(candidates) {
                        throw AmbiguousOpenError(request: PendingEncodingSelection(
                            url: leftURL,
                            side: .left,
                            candidates: candidates
                        ))
                    }
                    let rightDocument: TextFileDocument
                    do {
                        rightDocument = try rightEncoding.map {
                            try TextFileDocumentIO.load(from: rightURL, assuming: $0)
                        } ?? TextFileDocumentIO.load(from: rightURL)
                    } catch let TextFileCodecError.ambiguousTextEncoding(candidates) {
                        throw AmbiguousOpenError(request: PendingEncodingSelection(
                            url: rightURL,
                            side: .right,
                            candidates: candidates
                        ))
                    }
                    return (leftDocument, rightDocument)
                }.value
                guard leftGeneration == loadGeneration(for: .left),
                      rightGeneration == loadGeneration(for: .right) else {
                    endOperation()
                    return
                }
                left = ComparedFile(document: documents.0)
                right = ComparedFile(document: documents.1)
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
                endOperation()
            } catch {
                if leftGeneration == loadGeneration(for: .left),
                   rightGeneration == loadGeneration(for: .right) {
                    if let ambiguous = error as? AmbiguousOpenError {
                        requestEncodingSelection(ambiguous.request) { encoding in
                            self.loadPair(
                                leftURL,
                                rightURL,
                                leftEncoding: ambiguous.request.side == .left ? encoding : leftEncoding,
                                rightEncoding: ambiguous.request.side == .right ? encoding : rightEncoding
                            )
                        }
                    } else {
                        errorMessage = "Could not open comparison. \(error.localizedDescription)"
                    }
                }
                endOperation()
            }
        }
    }

    func load(
        _ url: URL,
        into side: ComparisonSide,
        assuming encoding: TextFileEncoding? = nil
    ) {
        let generation = nextLoadGeneration(for: side)
        beginOperation()
        Task {
            do {
                let document = try await Task.detached {
                    try encoding.map { try TextFileDocumentIO.load(from: url, assuming: $0) }
                        ?? TextFileDocumentIO.load(from: url)
                }.value
                guard generation == loadGeneration(for: side) else {
                    endOperation()
                    return
                }

                switch side {
                case .left:
                    left = ComparedFile(document: document)
                case .right:
                    right = ComparedFile(document: document)
                }
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
                endOperation()
            } catch {
                if generation == loadGeneration(for: side) {
                    if case let TextFileCodecError.ambiguousTextEncoding(candidates) = error {
                        let request = PendingEncodingSelection(url: url, side: side, candidates: candidates)
                        requestEncodingSelection(request) { selectedEncoding in
                            self.load(url, into: side, assuming: selectedEncoding)
                        }
                    } else {
                        errorMessage = "Could not read \(url.lastPathComponent). \(error.localizedDescription)"
                    }
                }
                endOperation()
            }
        }
    }

    func reportImporterFailure(_ error: Error) {
        let cocoaError = error as NSError
        guard cocoaError.domain != NSCocoaErrorDomain || cocoaError.code != NSUserCancelledError else {
            return
        }
        errorMessage = "Could not open file. \(error.localizedDescription)"
    }

    func dismissErrorMessage() {
        errorMessage = nil
        hasPendingSaveWarning = false
    }

    func merge(
        rowID: DiffRow.ID,
        direction: MergeDirection,
        advancesToNextDifference: Bool = false
    ) {
        commitActiveEditor()
        guard !isWorking, isComparisonCurrent else { return }
        let currentDifferenceIDs = differenceIDs
        let preferredDifferenceIndex: Int?
        if advancesToNextDifference,
           let index = differenceLocations[rowID]?.position {
            preferredDifferenceIndex = index == currentDifferenceIDs.count - 1 ? nil : index
        } else {
            preferredDifferenceIndex = nil
        }
        let source = snapshot
        beginOperation()
        Task {
            do {
                let result = try await Task.detached {
                    try LineMerge.apply(
                        rowID: rowID,
                        direction: direction,
                        left: source.left,
                        right: source.right
                    )
                }.value
                guard snapshot == source, let result else {
                    endOperation()
                    return
                }
                commit(result, selectingDifferenceAt: preferredDifferenceIndex)
                endOperation()
            } catch {
                errorMessage = error.localizedDescription
                endOperation()
            }
        }
    }

    func mergeAll(direction: MergeDirection) {
        commitActiveEditor()
        guard !isWorking, isComparisonCurrent else { return }
        let source = snapshot
        beginOperation()
        Task {
            do {
                let result = try await Task.detached {
                    try LineMerge.applyAll(
                        direction: direction,
                        left: source.left,
                        right: source.right
                    )
                }.value
                guard snapshot == source, let result else {
                    endOperation()
                    return
                }
                commit(result, selectingDifferenceAt: nil)
                endOperation()
            } catch {
                errorMessage = error.localizedDescription
                endOperation()
            }
        }
    }

    func undo() {
        commitActiveEditor()
        guard !isWorking else { return }
        guard let snapshot = history.undo() else { return }
        apply(snapshot)
        selectedDifferenceID = nil
        scheduleDiff()
    }

    func redo() {
        commitActiveEditor()
        guard !isWorking else { return }
        guard let snapshot = history.redo() else { return }
        apply(snapshot)
        selectedDifferenceID = nil
        scheduleDiff()
    }

    func selectDifference(_ id: DiffRow.ID?) {
        guard !isWorking, isComparisonCurrent else { return }
        guard let id else {
            selectedDifferenceID = nil
            return
        }
        guard differenceLocations[id] != nil else { return }
        selectedDifferenceID = id
    }

    func selectPreviousDifference() {
        selectAdjacentDifference(offset: -1)
    }

    func selectNextDifference() {
        selectAdjacentDifference(offset: 1)
    }

    func selectFirstDifference() {
        guard !isWorking else { return }
        selectedDifferenceID = differenceIDs.first
    }

    func selectLastDifference() {
        guard !isWorking else { return }
        selectedDifferenceID = differenceIDs.last
    }

    func mergeSelectedDifference(direction: MergeDirection, advance: Bool) {
        guard let selectedDifferenceID else { return }
        merge(
            rowID: selectedDifferenceID,
            direction: direction,
            advancesToNextDifference: advance
        )
    }

    func reloadFromDisk() {
        guard canReloadFromDisk, !hasReloadableUnsavedChanges else { return }
        reloadDocumentBackedSides()
    }

    func discardChangesAndReloadFromDisk() {
        guard canReloadFromDisk else { return }
        reloadDocumentBackedSides()
    }

    func save(
        _ side: ComparisonSide,
        scratchpadDestination destinationURL: URL? = nil,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard !isWorking else {
            completion?(false)
            return
        }
        let destination = destinationURL ?? saveDestinationIfNeeded(for: side)
        if file(on: side).isUntitled, destination == nil {
            completion?(false)
            return
        }
        if let destination,
           let oppositeURL = file(on: side == .left ? .right : .left).url,
           saveDestinationsCollide(destination, oppositeURL) {
            errorMessage = "Choose a save location different from the other comparison file."
            completion?(false)
            return
        }
        beginOperation()
        Task {
            let saved = await performSave(side, scratchpadDestination: destination)
            operationCompletions.append { completion?(saved) }
            endOperation()
        }
    }

    func saveAllChanges(
        scratchpadDestinations: [ComparisonSide: URL] = [:],
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard !isWorking else {
            completion(false)
            return
        }
        let leftDestination = left.isDirty
            ? scratchpadDestinations[.left] ?? saveDestinationIfNeeded(for: .left)
            : nil
        if left.isDirty, left.isUntitled, leftDestination == nil {
            completion(false)
            return
        }
        let rightDestination = right.isDirty
            ? scratchpadDestinations[.right] ?? saveDestinationIfNeeded(for: .right)
            : nil
        if right.isDirty, right.isUntitled, rightDestination == nil {
            completion(false)
            return
        }
        let leftTarget = left.isDirty ? (leftDestination ?? left.url) : nil
        let rightTarget = right.isDirty ? (rightDestination ?? right.url) : nil
        if let leftTarget, let rightTarget,
           saveDestinationsCollide(leftTarget, rightTarget) {
            errorMessage = "Choose different save locations for the left and right files."
            completion(false)
            return
        }
        if let leftDestination, let rightURL = right.url,
           saveDestinationsCollide(leftDestination, rightURL) {
            errorMessage = "Choose a left save location different from the right comparison file."
            completion(false)
            return
        }
        if let rightDestination, let leftURL = left.url,
           saveDestinationsCollide(rightDestination, leftURL) {
            errorMessage = "Choose a right save location different from the left comparison file."
            completion(false)
            return
        }
        beginOperation()
        Task {
            if left.isDirty {
                guard await performSave(.left, scratchpadDestination: leftDestination) else {
                    operationCompletions.append { completion(false) }
                    endOperation()
                    return
                }
            }
            if right.isDirty {
                guard await performSave(.right, scratchpadDestination: rightDestination) else {
                    operationCompletions.append { completion(false) }
                    endOperation()
                    return
                }
            }
            operationCompletions.append { completion(true) }
            endOperation()
        }
    }

    func loadInitialArguments() {
        guard !loadedInitialArguments else { return }
        loadedInitialArguments = true

        let urls = Array(ProcessInfo.processInfo.arguments.dropFirst()
            .lazy
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(2))
        enqueueOpen(urls)
    }

    private func scheduleDiff(selectingDifferenceAt index: Int? = nil) {
        liveDiffTask?.cancel()
        liveDiffTask = nil
        diffGeneration += 1
        let generation = diffGeneration
        guard isReady else {
            rows = []
            maximumLineColumns = 0
            differenceLocations = [:]
            differenceIDs = []
            summary = DiffSummary(rows: [])
            comparisonFailed = false
            return
        }

        let source = snapshot
        beginOperation()
        Task {
            do {
                let comparison = try await comparisonWorker.compare(left: source.left, right: source.right)
                if generation == diffGeneration, source == snapshot {
                    rows = comparison.rows
                    maximumLineColumns = comparison.maximumLineColumns
                    differenceLocations = comparison.differenceLocations
                    differenceIDs = comparison.differenceIDs
                    summary = comparison.summary
                    comparisonFailed = false
                    isComparisonCurrent = true
                    if let index, !differenceIDs.isEmpty {
                        selectedDifferenceID = differenceIDs[min(index, differenceIDs.count - 1)]
                    } else if selectedDifferenceID.map({ differenceLocations[$0] == nil }) == true {
                        selectedDifferenceID = nil
                    }
                }
                endOperation()
            } catch {
                if generation == diffGeneration {
                    rows = []
                    maximumLineColumns = 0
                    differenceLocations = [:]
                    differenceIDs = []
                    summary = DiffSummary(rows: [])
                    comparisonFailed = true
                    isComparisonCurrent = false
                    selectedDifferenceID = nil
                    errorMessage = error.localizedDescription
                }
                endOperation()
            }
        }
    }

    private var snapshot: ComparisonSnapshot {
        ComparisonSnapshot(left: left.text, right: right.text)
    }

    private func scheduleLiveDiff() {
        liveDiffTask?.cancel()
        diffGeneration += 1
        let generation = diffGeneration
        let source = snapshot
        liveDiffTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(120))
                let comparison = try await comparisonWorker.compare(left: source.left, right: source.right)
                guard !Task.isCancelled, generation == diffGeneration, source == snapshot else { return }
                rows = comparison.rows
                maximumLineColumns = comparison.maximumLineColumns
                differenceLocations = comparison.differenceLocations
                differenceIDs = comparison.differenceIDs
                summary = comparison.summary
                comparisonFailed = false
                isComparisonCurrent = true
            } catch is CancellationError {
                return
            } catch {
                guard generation == diffGeneration else { return }
                rows = []
                maximumLineColumns = 0
                differenceLocations = [:]
                differenceIDs = []
                summary = DiffSummary(rows: [])
                comparisonFailed = true
                isComparisonCurrent = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func commit(_ result: LineMergeResult, selectingDifferenceAt index: Int?) {
        let next = ComparisonSnapshot(left: result.left, right: result.right)
        guard history.commit(next) else { return }
        apply(next)
        selectedDifferenceID = nil
        scheduleDiff(selectingDifferenceAt: index)
    }

    private func apply(_ snapshot: ComparisonSnapshot) {
        left.text = snapshot.left
        right.text = snapshot.right
    }

    private func selectAdjacentDifference(offset: Int) {
        guard !isWorking else { return }
        let ids = differenceIDs
        guard !ids.isEmpty else {
            selectedDifferenceID = nil
            return
        }

        guard let selectedDifferenceID,
              let index = differenceLocations[selectedDifferenceID]?.position else {
            self.selectedDifferenceID = offset > 0 ? ids[0] : ids[ids.count - 1]
            return
        }

        let nextIndex = index + offset
        guard ids.indices.contains(nextIndex) else { return }
        self.selectedDifferenceID = ids[nextIndex]
    }

    private func performSave(_ side: ComparisonSide, scratchpadDestination: URL? = nil) async -> Bool {
        let original = file(on: side)
        if let scratchpad = original.scratchpad {
            guard let scratchpadDestination else { return false }
            do {
                let document = try await Task.detached {
                    try TextFileDocumentIO.create(at: scratchpadDestination, text: scratchpad.text)
                }.value
                guard file(on: side) == original else { return false }
                setFile(ComparedFile(document: document), on: side)
                return true
            } catch {
                errorMessage = "Could not save \(original.displayName). \(error.localizedDescription)"
                return false
            }
        }

        guard let document = original.document else { return false }
        do {
            let result = try await Task.detached {
                try TextFileDocumentIO.save(document)
            }.value
            let canonicalized = !result.document.text.unicodeScalars.elementsEqual(document.text.unicodeScalars)
            switch side {
            case .left:
                guard left.document == document else {
                    return false
                }
                left.document = result.document
            case .right:
                guard right.document == document else {
                    return false
                }
                right.document = result.document
            }
            if canonicalized {
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
            }
            if let warning = result.warning {
                errorMessage = warning.localizedDescription
                hasPendingSaveWarning = true
                return false
            }
            return true
        } catch {
            errorMessage = "Could not save \(document.displayName). \(error.localizedDescription)"
            return false
        }
    }

    private func file(on side: ComparisonSide) -> ComparedFile {
        side == .left ? left : right
    }

    private func setFile(_ file: ComparedFile, on side: ComparisonSide) {
        switch side {
        case .left:
            left = file
        case .right:
            right = file
        }
    }

    private func saveDestinationIfNeeded(for side: ComparisonSide) -> URL? {
        let file = file(on: side)
        guard file.isUntitled else { return nil }
        let panel = NSSavePanel()
        panel.title = "Save \(file.displayName)"
        panel.nameFieldStringValue = "\(file.displayName).txt"
        panel.allowedContentTypes = [.plainText]
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func saveDestinationsCollide(_ first: URL, _ second: URL) -> Bool {
        saveDestinationIdentity(first) == saveDestinationIdentity(second)
    }

    private func saveDestinationIdentity(_ url: URL) -> String {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        var fileInfo = stat()
        if Darwin.lstat(resolved.path, &fileInfo) == 0 {
            return "inode:\(fileInfo.st_dev):\(fileInfo.st_ino)"
        }

        let directory = resolved.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL
        let values = try? directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        var name = resolved.lastPathComponent.precomposedStringWithCanonicalMapping
        if values?.volumeSupportsCaseSensitiveNames != true {
            name = name.lowercased()
        }
        return "path:\(directory.path)/\(name)"
    }

    private func reloadDocumentBackedSides() {
        guard !isWorking else { return }
        let leftDocument = left.document
        let rightDocument = right.document
        guard leftDocument != nil || rightDocument != nil else { return }

        let leftGeneration = leftDocument.map { _ in nextLoadGeneration(for: .left) }
        let rightGeneration = rightDocument.map { _ in nextLoadGeneration(for: .right) }
        beginOperation()
        Task {
            do {
                let documents = try await Task.detached {
                    let loadedLeft = try leftDocument.map {
                        try TextFileDocumentIO.load(from: $0.url, assuming: $0.encoding)
                    }
                    let loadedRight = try rightDocument.map {
                        try TextFileDocumentIO.load(from: $0.url, assuming: $0.encoding)
                    }
                    return (loadedLeft, loadedRight)
                }.value
                guard leftGeneration.map({ $0 == loadGeneration(for: .left) }) ?? true,
                      rightGeneration.map({ $0 == loadGeneration(for: .right) }) ?? true else {
                    endOperation()
                    return
                }
                if let document = documents.0 {
                    left = ComparedFile(document: document)
                }
                if let document = documents.1 {
                    right = ComparedFile(document: document)
                }
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
                endOperation()
            } catch {
                errorMessage = "Could not reload comparison. \(error.localizedDescription)"
                endOperation()
            }
        }
    }

    private func nextLoadGeneration(for side: ComparisonSide) -> Int {
        switch side {
        case .left:
            leftLoadGeneration += 1
            return leftLoadGeneration
        case .right:
            rightLoadGeneration += 1
            return rightLoadGeneration
        }
    }

    private func requestEncodingSelection(
        _ request: PendingEncodingSelection,
        retry: @escaping @MainActor (TextFileEncoding) -> Void
    ) {
        pendingEncodingSelection = request
        pendingEncodingRetry = retry
    }

    private func loadGeneration(for side: ComparisonSide) -> Int {
        side == .left ? leftLoadGeneration : rightLoadGeneration
    }

    private func beginOperation() {
        activeOperationCount += 1
        isWorking = true
    }

    private func endOperation() {
        activeOperationCount = max(0, activeOperationCount - 1)
        isWorking = activeOperationCount > 0
        guard !isWorking else { return }
        while !operationCompletions.isEmpty, !isWorking {
            operationCompletions.removeFirst()()
        }
        guard !isWorking else { return }
        drainOpenRequestsIfIdle()
        guard !isWorking else { return }
        deliverIdleWaitersIfIdle()
    }

    private func drainOpenRequestsIfIdle() {
        guard !openQueueSuspended,
              !isWorking,
              pendingExternalOpenURLs == nil,
              pendingEncodingSelection == nil,
              !queuedOpenRequests.isEmpty else { return }
        processOpen(queuedOpenRequests.removeFirst())
    }

    private func deliverIdleWaitersIfIdle() {
        while !idleWaiters.isEmpty,
              !isWorking,
              queuedOpenRequests.isEmpty || openQueueSuspended {
            idleWaiters.removeFirst()()
        }
    }
}

private struct ComparisonView: View {
    let model: ComparisonModel
    @State private var importingSide: ComparisonSide?
    @State private var presentsImporter = false
    @State private var replacementSide: ComparisonSide?
    @State private var pendingImportedURL: URL?
    @State private var mergeAllDirection: MergeDirection?
    @State private var confirmsDiscardAndReload = false
    @State private var confirmsNewComparison = false

    var body: some View {
        VStack(spacing: 0) {
            ComparisonHeader(
                leftName: model.left.displayName,
                rightName: model.right.displayName,
                leftIsLoaded: model.left.isLoaded,
                rightIsLoaded: model.right.isLoaded,
                leftIsUntitled: model.left.isUntitled,
                rightIsUntitled: model.right.isUntitled,
                leftIsDirty: model.left.isDirty,
                rightIsDirty: model.right.isDirty,
                summary: model.summary,
                isReady: model.isReady,
                comparisonFailed: model.comparisonFailed,
                openLeft: { openImporter(for: .left) },
                openRight: { openImporter(for: .right) },
                saveLeft: { model.save(.left) },
                saveRight: { model.save(.right) }
            )
            Divider()

            ComparisonToolbar(
                model: model,
                requestNew: requestNewComparison,
                openLeft: { openImporter(for: .left) },
                openRight: { openImporter(for: .right) },
                requestMergeAll: { mergeAllDirection = $0 },
                requestReload: requestReload
            )
            Divider()

            if model.isReady {
                if model.comparisonFailed {
                    ContentUnavailableView(
                        "Comparison failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Resolve the reported error, then reopen either file to retry.")
                    )
                } else {
                    DiffCanvas(
                        rows: model.rows,
                        rowsRevision: model.rowsRevision,
                        maximumLineColumns: model.maximumLineColumns,
                        differenceLocations: model.differenceLocations,
                        selectedDifferenceID: model.selectedDifferenceID,
                        leftEditable: model.left.isUntitled,
                        rightEditable: model.right.isUntitled,
                        selectDifference: model.selectDifference,
                        editLeft: { model.editScratchpadLine(rowID: $0, on: .left, replacement: $1) },
                        editRight: { model.editScratchpadLine(rowID: $0, on: .right, replacement: $1) },
                        finishEditingLeft: { model.finishScratchpadLineEditing(rowID: $0, on: .left) },
                        finishEditingRight: { model.finishScratchpadLineEditing(rowID: $0, on: .right) }
                    )
                }
            } else {
                EmptyComparisonView(
                    hasLeftFile: model.left.isLoaded,
                    hasRightFile: model.right.isLoaded,
                    openLeft: { openImporter(for: .left) },
                    openRight: { openImporter(for: .right) }
                )
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if model.isWorking {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.45)
                    ProgressView("Processing...")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .disabled(model.isWorking)
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [.plainText, .sourceCode, .data],
            allowsMultipleSelection: false
        ) { result in
            let side = importingSide
            importingSide = nil
            switch result {
            case let .success(urls):
                if let url = urls.first, let side {
                    if model.isDirty(side) {
                        pendingImportedURL = url
                        replacementSide = side
                    } else {
                        model.enqueueOpen(url, into: side)
                    }
                }
            case let .failure(error):
                model.reportImporterFailure(error)
            }
        }
        .alert(
            "File operation notice",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissErrorMessage() } }
            )
        ) {
            Button("OK") {
                model.dismissErrorMessage()
            }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            replacementTitle,
            isPresented: Binding(
                get: { replacementSide != nil },
                set: {
                    if !$0 {
                        replacementSide = nil
                        pendingImportedURL = nil
                    }
                }
            )
        ) {
            if let replacementSide {
                Button("Save and Open Another File...") {
                    let importedURL = pendingImportedURL
                    model.save(replacementSide) { saved in
                        if saved {
                            continueReplacement(for: replacementSide, importedURL: importedURL)
                        }
                    }
                }
                Button("Discard Changes and Open...", role: .destructive) {
                    continueReplacement(for: replacementSide, importedURL: pendingImportedURL)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("Opening another file will replace unsaved edits on this side.")
        }
        .confirmationDialog(
            "Open files from Finder?",
            isPresented: Binding(
                get: { model.pendingExternalOpenURLs != nil },
                set: { _ in }
            )
        ) {
            Button("Save Changes and Open") {
                model.saveAllChanges { saved in
                    if saved {
                        model.acceptPendingExternalOpen()
                    }
                }
            }
            .disabled(model.isWorking)
            Button("Discard Changes and Open", role: .destructive) {
                model.discardChangesAndAcceptPendingExternalOpen()
            }
            .disabled(model.isWorking)
            Button("Cancel", role: .cancel) {
                model.cancelPendingExternalOpen()
            }
        } message: {
            Text("Finder requested files that would replace unsaved edits.")
        }
        .confirmationDialog(
            "Choose file encoding",
            isPresented: Binding(
                get: { model.pendingEncodingSelection != nil },
                set: { _ in }
            )
        ) {
            if let selection = model.pendingEncodingSelection {
                ForEach(selection.candidates, id: \.rawValue) { encoding in
                    Button(encoding.displayName) {
                        model.selectPendingEncoding(encoding)
                    }
                }
                Button("Cancel", role: .cancel) {
                    model.cancelPendingEncodingSelection()
                }
            }
        } message: {
            Text("\(model.pendingEncodingSelection?.url.lastPathComponent ?? "File") matches multiple encodings. Choose how to decode it.")
        }
        .confirmationDialog(
            "Create a new empty comparison?",
            isPresented: $confirmsNewComparison
        ) {
            Button("Save Changes and Create New") {
                model.saveAllChanges { saved in
                    if saved {
                        model.createEmptyComparison()
                    }
                }
            }
            Button("Discard Changes and Create New", role: .destructive) {
                model.createEmptyComparison()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved changes in the current comparison will be lost.")
        }
        .confirmationDialog(
            "Discard changes and reload?",
            isPresented: $confirmsDiscardAndReload
        ) {
            Button("Discard Changes and Reload", role: .destructive) {
                model.discardChangesAndReloadFromDisk()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Document-backed files will be reloaded from disk. Unsaved changes to those files will be lost; untitled panes remain unchanged.")
        }
        .confirmationDialog(
            mergeAllTitle,
            isPresented: Binding(
                get: { mergeAllDirection != nil },
                set: { if !$0 { mergeAllDirection = nil } }
            )
        ) {
            if let mergeAllDirection {
                Button("Merge All Changes") {
                    model.mergeAll(direction: mergeAllDirection)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("Every difference will be copied to the target file. You can undo this operation before saving.")
        }
        .task {
            model.loadInitialArguments()
        }
    }

    private func openImporter(for side: ComparisonSide) {
        guard !model.isDirty(side) else {
            replacementSide = side
            return
        }

        presentImporter(for: side)
    }

    private func presentImporter(for side: ComparisonSide) {
        replacementSide = nil
        pendingImportedURL = nil
        importingSide = side
        presentsImporter = true
    }

    private func continueReplacement(for side: ComparisonSide, importedURL: URL?) {
        if let importedURL {
            replacementSide = nil
            pendingImportedURL = nil
            model.enqueueReplacingOpen(importedURL, into: side)
        } else {
            presentImporter(for: side)
        }
    }

    private var replacementTitle: String {
        "Save changes to the \(replacementSide == .left ? "left" : "right") file?"
    }

    private var mergeAllTitle: String {
        switch mergeAllDirection {
        case .leftToRight:
            "Merge all changes from left to right?"
        case .rightToLeft:
            "Merge all changes from right to left?"
        case nil:
            "Merge all changes?"
        }
    }

    private func requestNewComparison() {
        if model.hasUnsavedChanges {
            confirmsNewComparison = true
        } else {
            model.createEmptyComparison()
        }
    }

    private func requestReload() {
        if model.hasReloadableUnsavedChanges {
            confirmsDiscardAndReload = true
        } else {
            model.reloadFromDisk()
        }
    }
}

private struct ComparisonHeader: View {
    let leftName: String
    let rightName: String
    let leftIsLoaded: Bool
    let rightIsLoaded: Bool
    let leftIsUntitled: Bool
    let rightIsUntitled: Bool
    let leftIsDirty: Bool
    let rightIsDirty: Bool
    let summary: DiffSummary
    let isReady: Bool
    let comparisonFailed: Bool
    let openLeft: () -> Void
    let openRight: () -> Void
    let saveLeft: () -> Void
    let saveRight: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            FileControl(
                name: leftName,
                side: .left,
                isLoaded: leftIsLoaded,
                isUntitled: leftIsUntitled,
                isDirty: leftIsDirty,
                open: openLeft,
                save: saveLeft
            )
                .frame(maxWidth: .infinity, alignment: .leading)

            if isReady {
                if comparisonFailed {
                    Label("FAILED", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 18)
                } else {
                    DifferenceCounter(summary: summary)
                        .padding(.horizontal, 18)
                }
            } else {
                Text("MACMERGE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }

            FileControl(
                name: rightName,
                side: .right,
                isLoaded: rightIsLoaded,
                isUntitled: rightIsUntitled,
                isDirty: rightIsDirty,
                open: openRight,
                save: saveRight
            )
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }
}

private struct FileControl: View {
    let name: String
    let side: ComparisonSide
    let isLoaded: Bool
    let isUntitled: Bool
    let isDirty: Bool
    let open: () -> Void
    let save: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if side == .left {
                fileButton
            }
            Button("Save", systemImage: "square.and.arrow.down", action: save)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!isDirty)
                .help("Save \(sideName.lowercased()) file")
                .accessibilityLabel("Save \(sideName.lowercased()) file")
            if side == .right {
                fileButton
            }
        }
    }

    private var fileButton: some View {
        FileButton(
            name: name,
            side: sideName,
            isLoaded: isLoaded,
            isUntitled: isUntitled,
            isDirty: isDirty,
            action: open
        )
    }

    private var sideName: String {
        side == .left ? "LEFT" : "RIGHT"
    }
}

private struct FileButton: View {
    let name: String
    let side: String
    let isLoaded: Bool
    let isUntitled: Bool
    let isDirty: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: side == "LEFT" ? .leading : .trailing, spacing: 4) {
                Text(side)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                if isDirty {
                    Text("EDITED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 7) {
                    if side == "RIGHT" {
                        Image(systemName: "arrow.up.doc")
                    }
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if side == "LEFT" {
                        Image(systemName: "arrow.up.doc")
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLoaded ? "\(side.capitalized) file, \(name)" : "No \(side.lowercased()) file selected")
        .accessibilityValue(isLoaded ? accessibilityValue : "")
        .accessibilityHint(isLoaded ? "Choose another \(side.lowercased()) file" : "Choose a \(side.lowercased()) file")
    }

    private var accessibilityValue: String {
        if isUntitled {
            return isDirty ? "Edited, untitled" : "Untitled"
        }
        return isDirty ? "Edited" : "Saved"
    }
}

private struct DifferenceCounter: View {
    let summary: DiffSummary

    var body: some View {
        VStack(spacing: 2) {
            Text(summary.differences, format: .number)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(summary.differences == 1 ? "CHANGE" : "CHANGES")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.differences) differences")
    }
}

private struct ComparisonToolbar: View {
    let model: ComparisonModel
    let requestNew: () -> Void
    let openLeft: () -> Void
    let openRight: () -> Void
    let requestMergeAll: (MergeDirection) -> Void
    let requestReload: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("New empty comparison", systemImage: "doc.badge.plus", action: requestNew)
                .disabled(!model.canCreateEmptyComparison)
                .help("Create an empty two-file comparison")

            Menu("Open files", systemImage: "folder") {
                Button("Open Left...", systemImage: "rectangle.split.2x1", action: openLeft)
                Button("Open Right...", systemImage: "rectangle.split.2x1", action: openRight)
            }
            .disabled(model.isWorking)
            .help("Open or replace a comparison file")

            Button("Save changed files", systemImage: "square.and.arrow.down") {
                model.saveAllChanges { _ in }
            }
                .disabled(!model.hasUnsavedChanges || model.isWorking)
                .help("Save all changed files")

            toolbarDivider

            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .disabled(!model.canUndo)
                .help("Undo merge")
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .disabled(!model.canRedo)
                .help("Redo merge")

            toolbarDivider

            Button("First difference", systemImage: "arrow.up.to.line", action: model.selectFirstDifference)
                .disabled(!model.canNavigateDifferences)
                .help("Go to first difference")
            Button("Previous difference", systemImage: "arrow.up", action: model.selectPreviousDifference)
                .disabled(!model.canSelectPreviousDifference)
                .help("Go to previous difference")
            Text(selectionLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 68)
                .accessibilityLabel(selectionAccessibilityLabel)
                .accessibilityAddTraits(.updatesFrequently)
            Button("Next difference", systemImage: "arrow.down", action: model.selectNextDifference)
                .disabled(!model.canSelectNextDifference)
                .help("Go to next difference")
            Button("Last difference", systemImage: "arrow.down.to.line", action: model.selectLastDifference)
                .disabled(!model.canNavigateDifferences)
                .help("Go to last difference")

            toolbarDivider

            Button("Copy selected difference to right", systemImage: "arrow.right") {
                model.mergeSelectedDifference(direction: .leftToRight, advance: false)
            }
                .disabled(!model.hasSelectedDifference)
                .help("Copy selected difference to right")
            Button("Copy selected difference to left", systemImage: "arrow.left") {
                model.mergeSelectedDifference(direction: .rightToLeft, advance: false)
            }
                .disabled(!model.hasSelectedDifference)
                .help("Copy selected difference to left")

            Button(
                "Copy selected difference to right and advance",
                systemImage: "arrow.right.circle",
                action: { model.mergeSelectedDifference(direction: .leftToRight, advance: true) }
            )
            .disabled(!model.hasSelectedDifference)
            .help("Copy selected difference to right and advance")
            Button(
                "Copy selected difference to left and advance",
                systemImage: "arrow.left.circle",
                action: { model.mergeSelectedDifference(direction: .rightToLeft, advance: true) }
            )
            .disabled(!model.hasSelectedDifference)
            .help("Copy selected difference to left and advance")

            toolbarDivider

            Menu("Merge all", systemImage: "arrow.left.arrow.right") {
                Button("Copy All to Right", systemImage: "arrow.right.square") {
                    requestMergeAll(.leftToRight)
                }
                Button("Copy All to Left", systemImage: "arrow.left.square") {
                    requestMergeAll(.rightToLeft)
                }
            }
            .disabled(!model.canNavigateDifferences)
            .help("Copy all differences")

            toolbarDivider

            Button("Reload files", systemImage: "arrow.clockwise", action: requestReload)
                .disabled(!model.canReloadFromDisk)
                .help(model.hasUnsavedChanges ? "Discard changes and reload both files" : "Reload both files from disk")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comparison commands")
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 18)
    }

    private var selectionLabel: String {
        guard let selectedPosition = model.selectedDifferencePosition else {
            return "- / \(model.summary.differences)"
        }
        return "\(selectedPosition) / \(model.summary.differences)"
    }

    private var selectionAccessibilityLabel: String {
        guard let selectedPosition = model.selectedDifferencePosition else {
            return "No difference selected, \(model.summary.differences) total"
        }
        return "Difference \(selectedPosition) of \(model.summary.differences)"
    }
}

private struct EmptyComparisonView: View {
    let hasLeftFile: Bool
    let hasRightFile: Bool
    let openLeft: () -> Void
    let openRight: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.secondary)
            VStack(spacing: 7) {
                Text("Open two files to compare")
                    .font(.title2.weight(.semibold))
                Text("Line changes stay aligned across one continuous comparison surface.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(hasLeftFile ? "Replace left" : "Open left", action: openLeft)
                Button(hasRightFile ? "Replace right" : "Open right", action: openRight)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct DiffCanvas: View {
    let rows: [DiffRow]
    let rowsRevision: Int
    let maximumLineColumns: Int
    let differenceLocations: [DiffRow.ID: DifferenceLocation]
    let selectedDifferenceID: DiffRow.ID?
    let leftEditable: Bool
    let rightEditable: Bool
    let selectDifference: (DiffRow.ID?) -> Void
    let editLeft: (DiffRow.ID, String) -> Void
    let editRight: (DiffRow.ID, String) -> Void
    let finishEditingLeft: (DiffRow.ID) -> Void
    let finishEditingRight: (DiffRow.ID) -> Void

    var body: some View {
        DiffTableView(
            rows: rows,
            rowsRevision: rowsRevision,
            maximumLineColumns: maximumLineColumns,
            differenceLocations: differenceLocations,
            selectedDifferenceID: selectedDifferenceID,
            leftEditable: leftEditable,
            rightEditable: rightEditable,
            selectDifference: selectDifference,
            editLeft: editLeft,
            editRight: editRight,
            finishEditingLeft: finishEditingLeft,
            finishEditingRight: finishEditingRight
        )
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct DiffTableView: NSViewRepresentable {
    let rows: [DiffRow]
    let rowsRevision: Int
    let maximumLineColumns: Int
    let differenceLocations: [DiffRow.ID: DifferenceLocation]
    let selectedDifferenceID: DiffRow.ID?
    let leftEditable: Bool
    let rightEditable: Bool
    let selectDifference: (DiffRow.ID?) -> Void
    let editLeft: (DiffRow.ID, String) -> Void
    let editRight: (DiffRow.ID, String) -> Void
    let finishEditingLeft: (DiffRow.ID) -> Void
    let finishEditingRight: (DiffRow.ID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rows: displayedRows,
            rowsRevision: rowsRevision,
            differenceLocations: differenceLocations,
            leftEditable: leftEditable,
            rightEditable: rightEditable,
            selectDifference: selectDifference,
            editLeft: editLeft,
            editRight: editRight,
            finishEditingLeft: finishEditingLeft,
            finishEditingRight: finishEditingRight
        )
    }

    func makeNSView(context: Context) -> DiffTableContainerView {
        let tableView = NSTableView()
        let column = NSTableColumn(identifier: .diffContent)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = DiffTableCellView.rowHeight
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.usesAutomaticRowHeights = false
        tableView.backgroundColor = .textBackgroundColor
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView

        let scrollView = DiffVerticalScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        let container = DiffTableContainerView(scrollView: scrollView)
        scrollView.horizontalScrollHandler = { [weak coordinator = context.coordinator] delta in
            coordinator?.scrollHorizontally(by: delta)
        }
        container.horizontalOffsetDidChange = { [weak coordinator = context.coordinator] in
            coordinator?.refreshVisibleHorizontalOffsets()
        }
        container.horizontalScroller.target = context.coordinator
        container.horizontalScroller.action = #selector(Coordinator.scrollHorizontally(_:))
        context.coordinator.container = container
        return container
    }

    func updateNSView(_ container: DiffTableContainerView, context: Context) {
        guard let tableView = context.coordinator.tableView else { return }
        context.coordinator.selectDifference = selectDifference
        context.coordinator.editLeft = editLeft
        context.coordinator.editRight = editRight
        context.coordinator.finishEditingLeft = finishEditingLeft
        context.coordinator.finishEditingRight = finishEditingRight
        context.coordinator.differenceLocations = differenceLocations
        let editabilityChanged = context.coordinator.leftEditable != leftEditable
            || context.coordinator.rightEditable != rightEditable
        context.coordinator.leftEditable = leftEditable
        context.coordinator.rightEditable = rightEditable

        if context.coordinator.rowsRevision != rowsRevision || editabilityChanged {
            context.coordinator.setRows(
                displayedRows,
                revision: rowsRevision,
                differenceLocations: differenceLocations
            )
            tableView.reloadData()
            context.coordinator.restorePendingEditorFocus()
        }
        container.maximumTextWidth = CGFloat(maximumLineColumns) * 7.25 + 12

        let oldSelection = context.coordinator.selectedDifferenceID
        context.coordinator.selectedDifferenceID = selectedDifferenceID
        context.coordinator.synchronizeTableSelection()
        context.coordinator.refreshVisibleRows(for: [oldSelection, selectedDifferenceID].compactMap { $0 })
        if oldSelection != selectedDifferenceID,
           let selectedDifferenceID,
           let location = context.coordinator.differenceLocations[selectedDifferenceID] {
            tableView.scrollRowToVisible(location.rowIndex)
        }
    }

    private var displayedRows: [DiffRow] {
        guard leftEditable || rightEditable else { return rows }
        return rows + [DiffRow(
            id: DiffRow.ID(leftNumber: nil, rightNumber: nil),
            left: nil,
            right: nil,
            kind: .unchanged
        )]
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var rows: [DiffRow]
        var rowsRevision: Int
        var differenceLocations: [DiffRow.ID: DifferenceLocation]
        var selectedDifferenceID: DiffRow.ID?
        var leftEditable: Bool
        var rightEditable: Bool
        var selectDifference: (DiffRow.ID?) -> Void
        var editLeft: (DiffRow.ID, String) -> Void
        var editRight: (DiffRow.ID, String) -> Void
        var finishEditingLeft: (DiffRow.ID) -> Void
        var finishEditingRight: (DiffRow.ID) -> Void
        weak var tableView: NSTableView?
        weak var container: DiffTableContainerView?
        private var isSynchronizingSelection = false
        private var pendingEditorFocus: PendingEditorFocus?

        private struct PendingEditorFocus {
            let side: ComparisonSide
            let lineNumber: Int
        }

        init(
            rows: [DiffRow],
            rowsRevision: Int,
            differenceLocations: [DiffRow.ID: DifferenceLocation],
            leftEditable: Bool,
            rightEditable: Bool,
            selectDifference: @escaping (DiffRow.ID?) -> Void,
            editLeft: @escaping (DiffRow.ID, String) -> Void,
            editRight: @escaping (DiffRow.ID, String) -> Void,
            finishEditingLeft: @escaping (DiffRow.ID) -> Void,
            finishEditingRight: @escaping (DiffRow.ID) -> Void
        ) {
            self.rows = rows
            self.rowsRevision = rowsRevision
            self.differenceLocations = differenceLocations
            self.leftEditable = leftEditable
            self.rightEditable = rightEditable
            self.selectDifference = selectDifference
            self.editLeft = editLeft
            self.editRight = editRight
            self.finishEditingLeft = finishEditingLeft
            self.finishEditingRight = finishEditingRight
            super.init()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            rows.indices.contains(row) && rows[row].kind != .unchanged
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSynchronizingSelection, let tableView else { return }
            guard rows.indices.contains(tableView.selectedRow) else {
                selectDifference(nil)
                return
            }
            guard rows[tableView.selectedRow].kind != .unchanged else { return }
            selectDifference(rows[tableView.selectedRow].id)
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            let cell = tableView.makeView(withIdentifier: .diffCell, owner: self) as? DiffTableCellView
                ?? DiffTableCellView()
            cell.identifier = .diffCell
            cell.configure(
                row: rows[row],
                selected: rows[row].id == selectedDifferenceID,
                leftEditable: leftEditable,
                rightEditable: rightEditable,
                horizontalOffset: container?.horizontalOffset ?? 0,
                maximumTextWidth: container?.maximumTextWidth ?? 0,
                editLeft: editLeft,
                editRight: editRight,
                finishEditingLeft: finishEditingLeft,
                finishEditingRight: finishEditingRight,
                continueEditingLeft: { [weak self] lineOffset in
                    self?.continueEditing(fromRow: row, side: .left, lineOffset: lineOffset)
                },
                continueEditingRight: { [weak self] lineOffset in
                    self?.continueEditing(fromRow: row, side: .right, lineOffset: lineOffset)
                }
            )
            return cell
        }

        func setRows(
            _ rows: [DiffRow],
            revision: Int,
            differenceLocations: [DiffRow.ID: DifferenceLocation]
        ) {
            self.rows = rows
            rowsRevision = revision
            self.differenceLocations = differenceLocations
        }

        func refreshVisibleRows(for ids: [DiffRow.ID]) {
            guard let tableView else { return }
            for id in ids {
                guard let location = differenceLocations[id],
                      let cell = tableView.view(
                        atColumn: 0,
                        row: location.rowIndex,
                        makeIfNecessary: false
                      )
                        as? DiffTableCellView else { continue }
                cell.setSelected(id == selectedDifferenceID)
            }
        }

        @objc func scrollHorizontally(_ sender: NSScroller) {
            guard let container else { return }
            container.updateHorizontalOffset(from: sender)
        }

        func scrollHorizontally(by delta: CGFloat) {
            guard let container else { return }
            container.updateHorizontalOffset(by: delta)
        }

        func synchronizeTableSelection() {
            guard let tableView else { return }
            isSynchronizingSelection = true
            defer { isSynchronizingSelection = false }
            if let selectedDifferenceID,
               let location = differenceLocations[selectedDifferenceID] {
                tableView.selectRowIndexes(
                    IndexSet(integer: location.rowIndex),
                    byExtendingSelection: false
                )
            } else {
                tableView.deselectAll(nil)
            }
        }

        func refreshVisibleHorizontalOffsets() {
            guard let tableView, let container else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            for row in visibleRows.location ..< NSMaxRange(visibleRows) {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? DiffTableCellView else { continue }
                cell.setHorizontalLayout(
                    offset: container.horizontalOffset,
                    maximumTextWidth: container.maximumTextWidth
                )
            }
        }

        private func continueEditing(fromRow rowIndex: Int, side: ComparisonSide, lineOffset: Int) {
            guard rows.indices.contains(rowIndex) else { return }
            let currentLine = side == .left ? rows[rowIndex].left?.number : rows[rowIndex].right?.number
            let insertionLine = rows[..<rowIndex].reduce(into: 1) { number, row in
                if side == .left ? row.left != nil : row.right != nil {
                    number += 1
                }
            }
            pendingEditorFocus = PendingEditorFocus(
                side: side,
                lineNumber: (currentLine ?? insertionLine) + lineOffset
            )
        }

        func restorePendingEditorFocus() {
            guard let pendingEditorFocus, let tableView else { return }
            guard let rowIndex = rows.firstIndex(where: { row in
                let line = pendingEditorFocus.side == .left ? row.left?.number : row.right?.number
                return line == pendingEditorFocus.lineNumber
            }) else { return }
            tableView.scrollRowToVisible(rowIndex)
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView,
                      let cell = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: true)
                        as? DiffTableCellView,
                      cell.focusEditor(on: pendingEditorFocus.side) else { return }
                self.pendingEditorFocus = nil
            }
        }

    }
}

@MainActor
private final class DiffVerticalScrollView: NSScrollView {
    var horizontalScrollHandler: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaX != 0 {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 24
            horizontalScrollHandler?(-event.scrollingDeltaX * scale)
        }
        if event.scrollingDeltaY != 0 || event.scrollingDeltaX == 0 {
            super.scrollWheel(with: event)
        }
    }
}

@MainActor
private final class DiffTableContainerView: NSView {
    let scrollView: NSScrollView
    let horizontalScroller = NSScroller()
    var horizontalOffsetDidChange: (() -> Void)?
    var maximumTextWidth: CGFloat = 0 {
        didSet {
            needsLayout = true
        }
    }
    private(set) var horizontalOffset: CGFloat = 0

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        horizontalScroller.scrollerStyle = .legacy
        addSubview(scrollView)
        addSubview(horizontalScroller)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let oldOffset = horizontalOffset
        let scrollerHeight = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        horizontalScroller.frame = NSRect(x: 0, y: 0, width: bounds.width, height: scrollerHeight)
        scrollView.frame = NSRect(x: 0, y: scrollerHeight, width: bounds.width, height: max(0, bounds.height - scrollerHeight))
        updateScrollerMetrics()
        if oldOffset != horizontalOffset {
            horizontalOffsetDidChange?()
        }
    }

    func updateHorizontalOffset(from scroller: NSScroller) {
        switch scroller.hitPart {
        case .decrementLine:
            horizontalOffset -= 24
        case .incrementLine:
            horizontalOffset += 24
        case .decrementPage:
            horizontalOffset -= textViewportWidth * 0.8
        case .incrementPage:
            horizontalOffset += textViewportWidth * 0.8
        default:
            horizontalOffset = maximumOffset * CGFloat(scroller.doubleValue)
        }
        horizontalOffset = min(max(0, horizontalOffset), maximumOffset)
        scroller.doubleValue = maximumOffset > 0 ? Double(horizontalOffset / maximumOffset) : 0
        horizontalOffsetDidChange?()
    }

    func updateHorizontalOffset(by delta: CGFloat) {
        horizontalOffset = min(max(0, horizontalOffset + delta), maximumOffset)
        horizontalScroller.doubleValue = maximumOffset > 0 ? Double(horizontalOffset / maximumOffset) : 0
        horizontalOffsetDidChange?()
    }

    private var textViewportWidth: CGFloat {
        let paneWidth = max(0, (scrollView.contentSize.width - DiffTableCellView.controlsWidth) / 2)
        return max(0, paneWidth - DiffTableCellView.numberAreaWidth - 8)
    }

    private var maximumOffset: CGFloat {
        max(0, maximumTextWidth - textViewportWidth)
    }

    private func updateScrollerMetrics() {
        let viewportWidth = textViewportWidth
        let totalWidth = max(viewportWidth, maximumTextWidth)
        horizontalScroller.isEnabled = maximumOffset > 0
        horizontalScroller.knobProportion = totalWidth > 0 ? viewportWidth / totalWidth : 1
        if maximumOffset == 0 {
            horizontalOffset = 0
            horizontalScroller.doubleValue = 0
        } else {
            horizontalOffset = min(horizontalOffset, maximumOffset)
            horizontalScroller.doubleValue = Double(horizontalOffset / maximumOffset)
        }
    }
}

@MainActor
private final class DiffTableCellView: NSTableCellView {
    static let rowHeight: CGFloat = 28
    static let controlsWidth: CGFloat = 1
    static let numberAreaWidth: CGFloat = 66
    private static let modifiedTint = NSColor.systemOrange.withAlphaComponent(0.13)
    private static let removedTint = NSColor.systemRed.withAlphaComponent(0.13)
    private static let addedTint = NSColor.systemTeal.withAlphaComponent(0.14)
    private static let dividerColor = NSColor.separatorColor.withAlphaComponent(0.7)
    private let leftNumber = makeLabel(fontSize: 10, color: .tertiaryLabelColor, alignment: .right)
    private let leftText = DiffLineTextView()
    private let rightNumber = makeLabel(fontSize: 10, color: .tertiaryLabelColor, alignment: .right)
    private let rightText = DiffLineTextView()
    private var row: DiffRow?
    private var selected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [leftNumber, leftText, rightNumber, rightText] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let paneWidth = max(0, (bounds.width - Self.controlsWidth) / 2)
        let numberWidth = Self.numberAreaWidth - 10
        leftNumber.frame = NSRect(x: 0, y: 0, width: numberWidth, height: bounds.height)
        leftText.frame = NSRect(
            x: Self.numberAreaWidth,
            y: 0,
            width: max(0, paneWidth - Self.numberAreaWidth - 8),
            height: bounds.height
        )
        let controlsX = paneWidth
        rightNumber.frame = NSRect(x: controlsX + Self.controlsWidth, y: 0, width: numberWidth, height: bounds.height)
        rightText.frame = NSRect(
            x: controlsX + Self.controlsWidth + Self.numberAreaWidth,
            y: 0,
            width: max(0, paneWidth - Self.numberAreaWidth - 8),
            height: bounds.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let row, let context = NSGraphicsContext.current?.cgContext else { return }
        let paneWidth = max(0, (bounds.width - Self.controlsWidth) / 2)
        fill(
            NSRect(x: 0, y: 0, width: paneWidth, height: bounds.height),
            color: tint(for: row.kind, side: .left),
            dirtyRect: dirtyRect,
            context: context
        )
        fill(
            NSRect(x: paneWidth, y: 0, width: Self.controlsWidth, height: bounds.height),
            color: .controlBackgroundColor,
            dirtyRect: dirtyRect,
            context: context
        )
        fill(
            NSRect(x: paneWidth + Self.controlsWidth, y: 0, width: paneWidth, height: bounds.height),
            color: tint(for: row.kind, side: .right),
            dirtyRect: dirtyRect,
            context: context
        )
        fill(NSRect(x: paneWidth, y: 0, width: 1, height: bounds.height), color: Self.dividerColor, dirtyRect: dirtyRect, context: context)
        fill(NSRect(x: 0, y: 0, width: 4, height: bounds.height), color: statusColor(for: row.kind, side: .left), dirtyRect: dirtyRect, context: context)
        fill(NSRect(x: paneWidth + 1, y: 0, width: 4, height: bounds.height), color: statusColor(for: row.kind, side: .right), dirtyRect: dirtyRect, context: context)
    }

    func configure(
        row: DiffRow,
        selected: Bool,
        leftEditable: Bool,
        rightEditable: Bool,
        horizontalOffset: CGFloat,
        maximumTextWidth: CGFloat,
        editLeft: @escaping (DiffRow.ID, String) -> Void,
        editRight: @escaping (DiffRow.ID, String) -> Void,
        finishEditingLeft: @escaping (DiffRow.ID) -> Void,
        finishEditingRight: @escaping (DiffRow.ID) -> Void,
        continueEditingLeft: @escaping (Int) -> Void,
        continueEditingRight: @escaping (Int) -> Void
    ) {
        leftText.prepareForReuse()
        rightText.prepareForReuse()
        self.row = row
        leftNumber.stringValue = row.left.map { String($0.number) } ?? ""
        leftText.stringValue = row.left?.text ?? ""
        leftText.configureEditable(
            leftEditable,
            accessibilityLabel: editorAccessibilityLabel(for: row, side: .left),
            finish: { [rowID = row.id] in finishEditingLeft(rowID) },
            continueAfterNewline: continueEditingLeft
        ) { [rowID = row.id] replacement in
            editLeft(rowID, replacement)
        }
        rightNumber.stringValue = row.right.map { String($0.number) } ?? ""
        rightText.stringValue = row.right?.text ?? ""
        rightText.configureEditable(
            rightEditable,
            accessibilityLabel: editorAccessibilityLabel(for: row, side: .right),
            finish: { [rowID = row.id] in finishEditingRight(rowID) },
            continueAfterNewline: continueEditingRight
        ) { [rowID = row.id] replacement in
            editRight(rowID, replacement)
        }
        setHorizontalLayout(offset: horizontalOffset, maximumTextWidth: maximumTextWidth)
        setAccessibilityLabel(accessibilityLabel(for: row))
        setAccessibilityValue(selected ? "Selected" : nil)
        setSelected(selected)
        needsLayout = true
        needsDisplay = true
    }

    func setSelected(_ selected: Bool) {
        guard self.selected != selected else { return }
        self.selected = selected
        setAccessibilityValue(selected ? "Selected" : nil)
        needsDisplay = true
    }

    func focusEditor(on side: ComparisonSide) -> Bool {
        switch side {
        case .left: return leftText.focusAtStart()
        case .right: return rightText.focusAtStart()
        }
    }

    func setHorizontalLayout(offset: CGFloat, maximumTextWidth: CGFloat) {
        leftText.setHorizontalLayout(offset: offset, contentWidth: maximumTextWidth)
        rightText.setHorizontalLayout(offset: offset, contentWidth: maximumTextWidth)
    }

    private func tint(for kind: DiffKind, side: ComparisonSide) -> NSColor {
        switch (kind, side) {
        case (.modified, _): Self.modifiedTint
        case (.removed, .left): Self.removedTint
        case (.added, .right): Self.addedTint
        default: .clear
        }
    }

    private func statusColor(for kind: DiffKind, side: ComparisonSide) -> NSColor {
        if selected, kind != .unchanged { return .controlAccentColor }
        switch (kind, side) {
        case (.modified, _): return .systemOrange
        case (.removed, .left): return .systemRed
        case (.added, .right): return .systemTeal
        default: return .clear
        }
    }

    private func fill(
        _ rect: NSRect,
        color: NSColor,
        dirtyRect: NSRect,
        context: CGContext
    ) {
        let clipped = rect.intersection(dirtyRect)
        guard !clipped.isEmpty else { return }
        context.setFillColor(color.cgColor)
        context.fill(clipped)
    }

    private func accessibilityLabel(for row: DiffRow) -> String {
        let state: String
        switch row.kind {
        case .unchanged: state = "Unchanged"
        case .modified: state = "Modified"
        case .removed: state = "Removed"
        case .added: state = "Added"
        }
        let left = row.left.map { "left line \($0.number)" } ?? "no left line"
        let right = row.right.map { "right line \($0.number)" } ?? "no right line"
        return "\(state), \(left), \(right)"
    }

    private func editorAccessibilityLabel(for row: DiffRow, side: ComparisonSide) -> String {
        let sideName = side == .left ? "Left" : "Right"
        let line = side == .left ? row.left?.number : row.right?.number
        return line.map { "\(sideName) editable line \($0)" } ?? "\(sideName) new line"
    }

    private static func makeLabel(
        fontSize: CGFloat,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        selectable: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.isSelectable = selectable
        field.drawsBackground = false
        return field
    }

}

@MainActor
private final class LockedLineScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        var ancestor = superview
        while let view = ancestor {
            if let tableScrollView = view as? DiffVerticalScrollView {
                tableScrollView.scrollWheel(with: event)
                return
            }
            ancestor = view.superview
        }
    }
}

@MainActor
private final class LockedLineClipView: NSClipView {
    var horizontalOriginRequestHandler: ((CGFloat) -> Void)?
    var allowsVerticalEditing = false
    private var lockedOriginX: CGFloat = 0
    private var isApplyingLock = false

    func lock(to originX: CGFloat) {
        lockedOriginX = originX
        isApplyingLock = true
        defer { isApplyingLock = false }
        scroll(to: NSPoint(x: originX, y: allowsVerticalEditing ? bounds.origin.y : 0))
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        if !isApplyingLock, abs(constrained.origin.x - lockedOriginX) > 0.5 {
            horizontalOriginRequestHandler?(constrained.origin.x)
        }
        constrained.origin.x = lockedOriginX
        if !allowsVerticalEditing {
            constrained.origin.y = 0
        }
        return constrained
    }
}

@MainActor
private final class DiffLineTextView: NSView, NSTextViewDelegate {
    private let scrollView = LockedLineScrollView()
    private let clipView = LockedLineClipView()
    private let textView: NSTextView = {
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let container = NSTextContainer(
            size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: 28)
        )
        container.widthTracksTextView = false
        container.heightTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        let view = NSTextView(frame: .zero, textContainer: container)
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .labelColor
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.allowsUndo = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 28)
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = false
        view.autoresizingMask = []
        return view
    }()
    private var horizontalOffset: CGFloat = 0
    private var contentWidth: CGFloat = 0
    private var committedValue = ""
    private var commitHandler: ((String) -> Void)?
    private var finishHandler: (() -> Void)?
    private var continueAfterNewlineHandler: ((Int) -> Void)?

    var stringValue: String {
        get { textView.string }
        set {
            guard textView.string != newValue else { return }
            textView.string = newValue
            committedValue = newValue
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipView.horizontalOriginRequestHandler = { [weak self] originX in
            self?.requestGlobalHorizontalOffset(originX)
        }
        scrollView.contentView = clipView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        textView.delegate = self
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        updateDocumentFrame()
    }

    func setHorizontalLayout(offset: CGFloat, contentWidth: CGFloat) {
        guard horizontalOffset != offset || self.contentWidth != contentWidth else { return }
        horizontalOffset = offset
        self.contentWidth = contentWidth
        updateDocumentFrame()
        clipView.lock(to: offset)
        scrollView.reflectScrolledClipView(clipView)
    }

    func configureEditable(
        _ editable: Bool,
        accessibilityLabel: String,
        finish: @escaping () -> Void,
        continueAfterNewline: @escaping (Int) -> Void,
        commit: @escaping (String) -> Void
    ) {
        textView.isEditable = editable
        textView.isSelectable = true
        clipView.allowsVerticalEditing = editable
        commitHandler = editable ? commit : nil
        finishHandler = editable ? finish : nil
        continueAfterNewlineHandler = editable ? continueAfterNewline : nil
        textView.setAccessibilityLabel(accessibilityLabel)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        commitIfChanged()
        finishHandler?()
        commitHandler = nil
        finishHandler = nil
        continueAfterNewlineHandler = nil
    }

    func textDidChange(_ notification: Notification) {
        commitIfChanged()
    }

    func textDidEndEditing(_ notification: Notification) {
        commitIfChanged()
        finishHandler?()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) else {
            return false
        }
        let replacement = NSMutableString(string: textView.string)
        let selectedRange = textView.selectedRange()
        replacement.replaceCharacters(in: selectedRange, with: "\n")
        textView.string = replacement as String
        let caret = selectedRange.location + 1
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        commitIfChanged()
        let prefix = (textView.string as NSString).substring(to: caret)
        let lineOffset = prefix.reduce(into: 0) { count, character in
            if character == "\n" || character == "\r" { count += 1 }
        }
        finishHandler?()
        continueAfterNewlineHandler?(max(1, lineOffset))
        return true
    }

    func focusAtStart() -> Bool {
        guard textView.isEditable, let window = textView.window else { return false }
        guard window.makeFirstResponder(textView) else { return false }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return true
    }

    private func updateDocumentFrame() {
        let width = max(bounds.width + horizontalOffset, contentWidth)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
    }

    private func requestGlobalHorizontalOffset(_ originX: CGFloat) {
        let delta = originX - horizontalOffset
        guard abs(delta) > 0.5 else { return }
        var ancestor = superview
        while let view = ancestor {
            if let tableScrollView = view as? DiffVerticalScrollView {
                tableScrollView.horizontalScrollHandler?(delta)
                return
            }
            ancestor = view.superview
        }
    }

    private func commitIfChanged() {
        guard let commitHandler, textView.string != committedValue else { return }
        let replacement = textView.string
        committedValue = replacement
        commitHandler(replacement)
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let diffContent = NSUserInterfaceItemIdentifier("MacMerge.DiffContent")
    static let diffCell = NSUserInterfaceItemIdentifier("MacMerge.DiffCell")
}
