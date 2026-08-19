import AppKit
import Darwin
import MacMergeCore
import OSLog
import Observation
import SwiftUI
import UniformTypeIdentifiers

private enum PerformanceTrace {
    static let log = OSLog(
        subsystem: "io.github.egigoka.MacMerge",
        category: .pointsOfInterest
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}

private final class PerformanceProbe: @unchecked Sendable {
    static let shared = PerformanceProbe()

    let shouldAutoScroll: Bool
    let shouldForceLocationPane: Bool
    private let reportURL: URL?
    private let lock = NSLock()
    private var starts: [String: UInt64] = [:]
    private var metrics: [String: Any] = [:]
    private var renderedLocationPaneSides: Set<ComparisonSide> = []
    private var locationPaneGeneration: Int?

    private init() {
        let environment = ProcessInfo.processInfo.environment
        reportURL = environment["MACMERGE_PERFORMANCE_REPORT"].map { URL(filePath: $0) }
        shouldAutoScroll = environment["MACMERGE_PERFORMANCE_AUTOSCROLL"] == "1"
        shouldForceLocationPane = environment["MACMERGE_PERFORMANCE_LOCATION_PANE"] == "1"
        for (environmentKey, reportKey) in [
            ("MACMERGE_PERFORMANCE_LINE_COUNT", "fixture_line_count"),
            ("MACMERGE_PERFORMANCE_LINE_BYTES", "fixture_line_bytes"),
            ("MACMERGE_PERFORMANCE_LOAD_BUDGET_MS", "load_budget_ms"),
            ("MACMERGE_PERFORMANCE_COMPARISON_BUDGET_MS", "comparison_budget_ms"),
            ("MACMERGE_PERFORMANCE_FIRST_RENDER_BUDGET_MS", "first_render_budget_ms"),
            ("MACMERGE_PERFORMANCE_SCROLL_BUDGET_MS", "scroll_budget_ms"),
            ("MACMERGE_PERFORMANCE_LOCATION_PANE_BUDGET_MS", "location_pane_budget_ms"),
            ("MACMERGE_PERFORMANCE_RESIDENT_BUDGET_MIB", "resident_budget_mib")
        ] {
            if let value = environment[environmentKey].flatMap(Int.init) {
                metrics[reportKey] = value
            }
        }
        for (environmentKey, reportKey) in [
            ("MACMERGE_PERFORMANCE_DENSITY", "fixture_density"),
            ("MACMERGE_PERFORMANCE_CONTENT", "fixture_content")
        ] {
            if let value = environment[environmentKey] {
                metrics[reportKey] = value
            }
        }
        metrics["location_pane_requested"] = shouldForceLocationPane ? 1 : 0
        metrics["machine_model"] = Self.machineModel()
        metrics["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
    }

    func begin(_ phase: String) {
        guard reportURL != nil else { return }
        lock.withLock {
            starts[phase] = DispatchTime.now().uptimeNanoseconds
        }
    }

    func end(_ phase: String) {
        guard reportURL != nil else { return }
        lock.withLock {
            guard let start = starts.removeValue(forKey: phase) else { return }
            metrics["\(phase)_ms"] = Int(
                (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            )
            writeReport()
        }
    }

    func beginFirstRender(rowCount: Int) {
        guard reportURL != nil else { return }
        lock.withLock {
            metrics["rows"] = rowCount
            starts["first_render"] = DispatchTime.now().uptimeNanoseconds
        }
    }

    func locationPaneDrawStarted(
        generation: Int,
        rowCount: Int,
        blockCount: Int,
        size: CGSize
    ) -> UInt64? {
        guard reportURL != nil, shouldForceLocationPane,
            rowCount > 0, blockCount > 0, size.width > 0, size.height > 0
        else { return nil }
        return lock.withLock {
            guard metrics["fixture_line_count"] as? Int == rowCount else { return nil }
            if let currentGeneration = locationPaneGeneration {
                guard generation >= currentGeneration else { return nil }
                if generation > currentGeneration {
                    renderedLocationPaneSides.removeAll(keepingCapacity: true)
                    starts.removeValue(forKey: "location_pane")
                    metrics.removeValue(forKey: "location_pane_rendered")
                    metrics.removeValue(forKey: "location_pane_render_ms")
                }
            }
            locationPaneGeneration = generation
            let start = starts["location_pane"] ?? DispatchTime.now().uptimeNanoseconds
            starts["location_pane"] = start
            return start
        }
    }

    func locationPaneRendered(
        start: UInt64?,
        generation: Int,
        side: ComparisonSide,
        rowCount: Int,
        blockCount: Int
    ) {
        guard let start, rowCount > 0, blockCount > 0 else { return }
        lock.withLock {
            guard generation == locationPaneGeneration else { return }
            guard metrics["location_pane_rendered"] == nil else { return }
            renderedLocationPaneSides.insert(side)
            guard renderedLocationPaneSides == [.left, .right] else { return }
            metrics["location_pane_render_ms"] = Int(
                (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            )
            metrics["location_pane_rendered"] = 1
            metrics["location_map_rows"] = rowCount
            metrics["location_map_blocks"] = blockCount
            finalizeIfComplete()
            writeReport()
        }
    }

    func finishScroll() {
        guard reportURL != nil else { return }
        lock.withLock {
            guard let start = starts.removeValue(forKey: "scroll") else { return }
            metrics["scroll_ms"] = Int(
                (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            )
            finalizeIfComplete()
            writeReport()
        }
    }

    private func finalizeIfComplete() {
        guard metrics["complete"] == nil, metrics["scroll_ms"] != nil else { return }
        if shouldForceLocationPane, metrics["location_pane_render_ms"] == nil { return }
        let residentBytes = residentMemoryBytes()
        metrics["resident_sampled"] = residentBytes == nil ? 0 : 1
        metrics["resident_bytes"] = residentBytes ?? 0
        metrics["resident_mib"] = (residentBytes ?? 0) / 1_048_576
        metrics["complete"] = 1
    }

    private func writeReport() {
        guard let reportURL,
            let data = try? JSONSerialization.data(
                withJSONObject: metrics,
                options: [.prettyPrinted, .sortedKeys]
            )
        else { return }
        try? data.write(to: reportURL, options: .atomic)
    }

    private func residentMemoryBytes() -> Int? {
        var information = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        return Int(exactly: information.resident_size)
    }

    private static func machineModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return "unknown"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let modelBytes = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: modelBytes, as: UTF8.self)
    }
}

struct MacMergeConfigurationMetadata: Equatable, Sendable {
    let appName: String
    let appVersion: String
    let buildVersion: String
    let operatingSystem: String
    let architecture: String
    let localeIdentifier: String
    let sandboxState: ConfigurationReportSandboxState
    let redactionRoots: [String]
    let usernames: [String]
}

enum MacMergeConfigurationReporter {
    static func build(
        metadata: MacMergeConfigurationMetadata,
        options: LineDiffOptions
    ) throws -> String {
        try ConfigurationReport(
            appName: metadata.appName,
            appVersion: metadata.appVersion,
            buildVersion: metadata.buildVersion,
            operatingSystem: metadata.operatingSystem,
            architecture: metadata.architecture,
            localeIdentifier: metadata.localeIdentifier,
            sandboxState: metadata.sandboxState,
            comparisonLimits: [
                ConfigurationReportRecord(
                    name: "Maximum numbered-copy output bytes",
                    value: NumberedTextCopyOptions.defaultMaximumOutputBytes
                ),
                ConfigurationReportRecord(
                    name: "Maximum numbered-copy rows",
                    value: NumberedTextCopyOptions.defaultMaximumRows
                ),
                ConfigurationReportRecord(
                    name: "Maximum text file bytes per side",
                    value: TextFileDocumentIO.maximumFileSize
                )
            ],
            features: featureRecords(options: options),
            redactionRoots: metadata.redactionRoots,
            usernames: metadata.usernames
        ).build()
    }

    @MainActor
    static func buildCurrent(options: LineDiffOptions) throws -> String {
        let bundle = Bundle.main
        let processInfo = ProcessInfo.processInfo
        let homeDirectory = NSHomeDirectory()
        let username = processInfo.userName
        return try build(
            metadata: MacMergeConfigurationMetadata(
                appName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? "MacMerge",
                appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "unknown",
                buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? "unknown",
                operatingSystem: "macOS \(processInfo.operatingSystemVersionString)",
                architecture: currentArchitecture,
                localeIdentifier: Locale.current.identifier,
                sandboxState: ConfigurationReportSandboxState(
                    isSandboxed: processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
                ),
                redactionRoots: validRedactionRoot(homeDirectory).map { [$0] } ?? [],
                usernames: validUsername(username).map { [$0] } ?? []
            ),
            options: options
        )
    }

    private static func featureRecords(
        options: LineDiffOptions
    ) -> [ConfigurationReportRecord] {
        [
            ConfigurationReportRecord(name: "Algorithm", value: options.algorithm.rawValue),
            ConfigurationReportRecord(
                name: "Detect moved blocks",
                value: enabledText(options.detectMovedBlocks)
            ),
            ConfigurationReportRecord(
                name: "Ignore blank lines",
                value: enabledText(options.ignoreBlankLines)
            ),
            ConfigurationReportRecord(
                name: "Ignore case",
                value: enabledText(options.ignoreCase)
            ),
            ConfigurationReportRecord(
                name: "Ignore comments",
                value: enabledText(options.ignoreComments)
            ),
            ConfigurationReportRecord(
                name: "Ignore line endings",
                value: enabledText(options.ignoreLineEndings)
            ),
            ConfigurationReportRecord(
                name: "Ignore numbers",
                value: enabledText(options.ignoreNumbers)
            ),
            ConfigurationReportRecord(
                name: "Indent heuristic",
                value: enabledText(options.indentHeuristic)
            ),
            ConfigurationReportRecord(
                name: "Line filters",
                value: ruleSummary(enabled: options.lineFiltersEnabled, count: options.lineFilters.count)
            ),
            ConfigurationReportRecord(
                name: "Substitutions",
                value: ruleSummary(
                    enabled: options.substitutionsEnabled,
                    count: options.substitutions.count
                )
            ),
            ConfigurationReportRecord(name: "Whitespace", value: options.whitespace.rawValue)
        ]
    }

    private static func enabledText(_ enabled: Bool) -> String {
        enabled ? "enabled" : "disabled"
    }

    private static func ruleSummary(enabled: Bool, count: Int) -> String {
        enabled ? "enabled (\(count))" : "disabled (\(count))"
    }

    private static func validRedactionRoot(_ value: String) -> String? {
        guard !value.isEmpty, value != "/", value != "\\" else { return nil }
        return value
    }

    private static func validUsername(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }
}

enum ClipboardTextWriterError: Error, LocalizedError, Equatable {
    case writeRejected

    var errorDescription: String? {
        "The pasteboard rejected the text."
    }
}

@MainActor
enum ClipboardTextWriter {
    static func write(_ text: String, to pasteboard: NSPasteboard = .general) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardTextWriterError.writeRejected
        }
    }
}

@MainActor
private enum NumberedCopyRequestCoordinator {
    private static var generation: UInt64 = 0

    static func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    static func isCurrent(_ request: UInt64) -> Bool {
        generation == request
    }
}

enum NumberedRowCopyCommand {
    static func isEnabled(row: DiffRow, side: ComparisonSide) -> Bool {
        switch side {
        case .left: row.left != nil
        case .right: row.right != nil
        }
    }

    static func text(row: DiffRow, side: ComparisonSide) throws -> String {
        try NumberedTextCopy.format(
            rows: [row],
            selectedRanges: [0..<1],
            side: side == .left ? .left : .right
        )
    }
}

@main
struct MacMergeApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        Window("MacMerge", id: "comparison") {
            ComparisonView(
                model: applicationDelegate.model,
                loadInitialComparison: { await applicationDelegate.loadInitialComparison() },
                requestNew: applicationDelegate.requestNewComparison,
                openComparison: applicationDelegate.openComparison,
                undo: applicationDelegate.undo,
                redo: applicationDelegate.redo,
                canUndo: { applicationDelegate.canUndo },
                canRedo: { applicationDelegate.canRedo }
            )
            .background {
                ComparisonWindowRegistration(applicationDelegate: applicationDelegate)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)
        .commands {
            WinMergeCommands(applicationDelegate: applicationDelegate)
        }

        Settings {
            ComparisonSettingsView(model: applicationDelegate.model)
        }
    }
}

private struct ComparisonWindowRegistration: View {
    let applicationDelegate: ApplicationDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ComparisonWindowReader(register: applicationDelegate.registerComparisonWindow)
            .frame(width: 0, height: 0)
            .onAppear {
                let openWindow = openWindow
                applicationDelegate.setComparisonWindowOpener {
                    openWindow(id: "comparison")
                }
            }
    }
}

private struct ComparisonWindowReader: NSViewRepresentable {
    let register: @MainActor (NSWindow?, NSWindow?) -> Void

    func makeNSView(context: Context) -> ComparisonWindowReaderView {
        ComparisonWindowReaderView(register: register)
    }

    func updateNSView(_ nsView: ComparisonWindowReaderView, context: Context) {
        nsView.register = register
        nsView.reportWindow()
    }

    static func dismantleNSView(_ nsView: ComparisonWindowReaderView, coordinator: ()) {
        nsView.register?(nil, nsView.reportedWindow)
        nsView.register = nil
    }
}

@MainActor
private final class ComparisonWindowReaderView: NSView {
    var register: (@MainActor (NSWindow?, NSWindow?) -> Void)?
    private(set) weak var reportedWindow: NSWindow?

    init(register: @escaping @MainActor (NSWindow?, NSWindow?) -> Void) {
        self.register = register
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
    }

    func reportWindow() {
        guard reportedWindow !== window else { return }
        let previousWindow = reportedWindow
        reportedWindow = window
        register?(window, previousWindow)
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private enum UnsavedChangesDecision {
        case save
        case cancel
        case discard
    }

    let model: ComparisonModel
    private let crashReporter: LocalCrashReporter
    private weak var comparisonWindow: NSWindow?
    private var comparisonWindowFrame: NSRect?
    private var comparisonWindowDelegate: ComparisonWindowDelegateProxy?
    private weak var comparisonWindowPendingDiscard: NSWindow?
    private weak var comparisonWindowApprovedToClose: NSWindow?
    private var openComparisonWindow: (@MainActor () -> Void)?
    private var comparisonCloseRetryScheduled = false
    private var comparisonClosePersistencePending = false
    private var hasPersistedCurrentSession = false
    private var shouldTerminateWithoutPersistingSession = false
    private let sessionStore: ComparisonSessionStore
    private let performComparisonWindowClose: @MainActor (NSWindow) -> Void
    private var didLoadInitialComparison = false
    private var pendingRestoredWindowFrame: ComparisonSessionState.WindowFrame?
    private var allowsRestoredWindowFrame = true
    private var lifecycleGeneration: UInt64 = 0
    private var isInitialComparisonLoadPending = true
    private var initialComparisonLoadWaiters: [@MainActor () -> Void] = []

    override convenience init() {
        let userDefaults = UserDefaults.standard
        self.init(
            model: ComparisonModel(
                userDefaults: userDefaults,
                bookmarkStore: SecurityScopedBookmarkStore(userDefaults: userDefaults)
            ),
            sessionStore: .applicationSupportStore()
        )
    }

    init(
        model: ComparisonModel,
        sessionStore: ComparisonSessionStore,
        crashReporter: LocalCrashReporter = LocalCrashReporter(),
        performComparisonWindowClose: @escaping @MainActor (NSWindow) -> Void = {
            $0.performClose(nil)
        }
    ) {
        self.model = model
        self.sessionStore = sessionStore
        self.crashReporter = crashReporter
        self.performComparisonWindowClose = performComparisonWindowClose
        super.init()
        for name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSText.didBeginEditingNotification,
            NSText.didChangeNotification,
            NSText.didEndEditingNotification
        ] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(commandRoutingDidChange(_:)),
                name: name,
                object: nil
            )
        }
        model.explicitOpenWillBegin = { [weak self] in
            self?.invalidatePendingLifecycleActions()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        crashReporter.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        crashReporter.stop()
    }

    func openComparison() {
        let panel = NSOpenPanel()
        panel.title = "Select Files to Compare"
        panel.message = "Select one or two files."
        panel.prompt = "Compare"
        panel.allowedContentTypes = [.plainText, .sourceCode, .data]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        model.enqueueOpen(Array(panel.urls.prefix(2)))
    }

    func requestNewComparison() {
        guard model.hasUnsavedChanges else {
            invalidatePendingLifecycleActions()
            model.createEmptyComparison()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before creating a new comparison?"
        alert.informativeText = "Unsaved changes will be lost if you create a new comparison without saving."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.saveAllChanges { [weak self] saved in
                guard let self, saved else { return }
                self.invalidatePendingLifecycleActions()
                self.model.createEmptyComparison()
            }
        case .alertThirdButtonReturn:
            invalidatePendingLifecycleActions()
            model.createEmptyComparison()
        default:
            break
        }
    }

    func requestReloadComparison() {
        guard model.canReloadFromDisk else { return }
        guard model.hasReloadableUnsavedChanges else {
            model.reloadFromDisk()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before reloading from disk?"
        alert.informativeText = "Reload replaces edited file contents with their current versions on disk."
        alert.addButton(withTitle: "Save and Reload")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard and Reload")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.saveReloadableChanges { [weak model] saved in
                if saved { model?.reloadFromDisk() }
            }
        case .alertThirdButtonReturn:
            model.discardChangesAndReloadFromDisk()
        default:
            break
        }
    }

    var canUndo: Bool {
        _ = model.commandRoutingRevision
        let keyWindow = NSApplication.shared.keyWindow
        return ComparisonUndoRouter.canUndo(
            model: model,
            in: keyWindow,
            allowsComparisonFallback: keyWindow != nil && keyWindow === comparisonWindow
        )
    }
    var canRedo: Bool {
        _ = model.commandRoutingRevision
        let keyWindow = NSApplication.shared.keyWindow
        return ComparisonUndoRouter.canRedo(
            model: model,
            in: keyWindow,
            allowsComparisonFallback: keyWindow != nil && keyWindow === comparisonWindow
        )
    }

    func undo() {
        let keyWindow = NSApplication.shared.keyWindow
        ComparisonUndoRouter.undo(
            model: model,
            in: keyWindow,
            allowsComparisonFallback: keyWindow != nil && keyWindow === comparisonWindow
        )
    }

    func redo() {
        let keyWindow = NSApplication.shared.keyWindow
        ComparisonUndoRouter.redo(
            model: model,
            in: keyWindow,
            allowsComparisonFallback: keyWindow != nil && keyWindow === comparisonWindow
        )
    }

    @objc private func commandRoutingDidChange(_ notification: Notification) {
        if let text = notification.object as? NSText {
            guard let window = text.window,
                window === NSApplication.shared.keyWindow,
                notification.name == NSText.didEndEditingNotification
                    || window.firstResponder === text
            else { return }
        }
        model.invalidateCommandRouting()
    }

    func copyConfigurationReport() {
        do {
            let report = try MacMergeConfigurationReporter.buildCurrent(options: model.options)
            try ClipboardTextWriter.write(report)
        } catch {
            presentCopyError(error, messageText: "Could not copy configuration report")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        lifecycleGeneration &+= 1
        didLoadInitialComparison = true
        allowsRestoredWindowFrame = false
        hasPersistedCurrentSession = false
        pendingRestoredWindowFrame = nil
        restoreComparisonWindow(application)
        model.enqueueOpen(urls)
        finishInitialComparisonLoad()
    }

    func loadInitialComparison(
        arguments: [String] = Array(ProcessInfo.processInfo.arguments.dropFirst())
    ) async {
        guard !didLoadInitialComparison else {
            finishInitialComparisonLoad()
            return
        }
        didLoadInitialComparison = true
        defer { finishInitialComparisonLoad() }
        let generation = lifecycleGeneration

        if !arguments.isEmpty {
            let urls = await Task.detached {
                let urls = arguments.prefix(2).map { URL(fileURLWithPath: $0) }
                return !urls.isEmpty
                    && urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
                    ? urls
                    : nil
            }.value
            guard lifecycleGeneration == generation else { return }
            guard let urls else {
                model.errorMessage = "Could not open the requested comparison because one or more files do not exist."
                return
            }
            lifecycleGeneration &+= 1
            allowsRestoredWindowFrame = false
            hasPersistedCurrentSession = false
            pendingRestoredWindowFrame = nil
            model.enqueueOpen(urls)
            return
        }

        let result = await Task.detached {
            self.sessionStore.loadAndClearCorrupt()
        }.value
        guard lifecycleGeneration == generation else { return }
        guard allowsRestoredWindowFrame else { return }
        switch result {
        case .success(nil):
            return
        case .success(let state?):
            model.restoreSession(state) { [weak self] restored in
                guard let self else { return }
                guard restored == .restored else { return }
                guard self.allowsRestoredWindowFrame else { return }
                self.pendingRestoredWindowFrame = state.windowFrame
                self.applyPendingRestoredWindowFrame()
            }
        case .corrupt(let message, let cleared):
            model.errorMessage =
                cleared
                ? "Could not restore the previous comparison. \(message)"
                : "Could not restore or discard the invalid previous comparison. \(message)"
        case .failed(let message):
            model.errorMessage = "Could not restore the previous comparison. \(message)"
        }
    }

    func setComparisonWindowOpener(_ action: @escaping @MainActor () -> Void) {
        openComparisonWindow = action
    }

    private func invalidatePendingLifecycleActions() {
        lifecycleGeneration &+= 1
        comparisonWindowApprovedToClose = nil
        comparisonWindowPendingDiscard = nil
        hasPersistedCurrentSession = false
        shouldTerminateWithoutPersistingSession = false
    }

    func registerComparisonWindow(_ window: NSWindow?, replacing previousWindow: NSWindow?) {
        if window == nil {
            guard comparisonWindow === previousWindow else { return }
            comparisonWindowFrame = previousWindow?.frame ?? comparisonWindowFrame
            detachComparisonWindowDelegate()
            return
        }
        guard comparisonWindow !== window else { return }
        detachComparisonWindowDelegate()
        guard let window else { return }
        shouldTerminateWithoutPersistingSession = false

        let delegate = ComparisonWindowDelegateProxy(
            owner: self,
            forwardingTo: window.delegate
        )
        comparisonWindow = window
        comparisonWindowFrame = window.frame
        comparisonWindowDelegate = delegate
        window.delegate = delegate
        applyPendingRestoredWindowFrame()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let generation = lifecycleGeneration
        sender.keyWindow?.makeFirstResponder(nil)
        model.suspendQueuedOpenRequests()
        guard !model.hasPendingSaveWarning else {
            restoreComparisonWindow(sender)
            model.resumeQueuedOpenRequests()
            return .terminateCancel
        }
        guard !isInitialComparisonLoadPending else {
            initialComparisonLoadWaiters.append { [weak self, weak sender] in
                guard let self, let sender else { return }
                self.completeTerminationRequest(sender, expectedGeneration: generation)
            }
            return .terminateLater
        }
        guard !model.isWorking else {
            model.whenIdle { [weak self, weak sender] in
                guard let self, let sender else { return }
                self.completeTerminationRequest(sender, expectedGeneration: generation)
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

    private func completeTerminationRequest(
        _ sender: NSApplication,
        expectedGeneration: UInt64
    ) {
        guard lifecycleGeneration == expectedGeneration else {
            finishTermination(sender, allowed: false)
            return
        }
        guard !model.isWorking else {
            model.whenIdle { [weak self, weak sender] in
                guard let self, let sender else { return }
                self.completeTerminationRequest(
                    sender,
                    expectedGeneration: expectedGeneration
                )
            }
            return
        }
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
        let generation = lifecycleGeneration
        guard !model.hasPendingSaveWarning else { return .terminateCancel }
        if shouldTerminateWithoutPersistingSession { return .terminateNow }
        guard model.hasUnsavedChanges else {
            persistSession { [weak self, weak sender] saved in
                guard let self, let sender else { return }
                guard self.lifecycleGeneration == generation else {
                    self.finishTermination(sender, allowed: false)
                    return
                }
                self.finishTermination(sender, allowed: saved)
            }
            return .terminateLater
        }

        switch unsavedChangesDecision(
            messageText: "Save changes before quitting MacMerge?",
            informativeText: "Unsaved changes will be lost if you quit without saving."
        ) {
        case .save:
            model.saveAllChanges { saved in
                Task { @MainActor in
                    await Task.yield()
                    guard saved else {
                        self.finishTermination(sender, allowed: false)
                        return
                    }
                    guard self.lifecycleGeneration == generation else {
                        self.finishTermination(sender, allowed: false)
                        return
                    }
                    self.persistSession { persisted in
                        guard self.lifecycleGeneration == generation else {
                            self.finishTermination(sender, allowed: false)
                            return
                        }
                        self.finishTermination(sender, allowed: persisted)
                    }
                }
            }
            return .terminateLater
        case .discard:
            guard model.lockSessionDiscard() else { return .terminateCancel }
            clearSession { [weak self, weak sender] cleared in
                guard let self, let sender else { return }
                self.model.unlockSessionPersistence {
                    guard self.lifecycleGeneration == generation else {
                        self.finishTermination(sender, allowed: false)
                        return
                    }
                    if cleared { self.shouldTerminateWithoutPersistingSession = true }
                    self.finishTermination(sender, allowed: cleared)
                }
            }
            return .terminateLater
        case .cancel:
            return .terminateCancel
        }
    }

    fileprivate func comparisonWindowShouldClose(_ window: NSWindow) -> Bool {
        let generation = lifecycleGeneration
        if comparisonWindowApprovedToClose === window { return true }
        window.makeFirstResponder(nil)
        guard !model.hasPendingSaveWarning else {
            window.makeKeyAndOrderFront(nil)
            return false
        }
        guard !model.isWorking else {
            if !comparisonCloseRetryScheduled {
                comparisonCloseRetryScheduled = true
                model.whenIdle { [weak self, weak window] in
                    guard let self else { return }
                    self.comparisonCloseRetryScheduled = false
                    guard self.lifecycleGeneration == generation else { return }
                    if let window {
                        self.performComparisonWindowClose(window)
                    }
                }
            }
            return false
        }
        guard !comparisonClosePersistencePending else { return false }
        guard model.hasUnsavedChanges else {
            comparisonClosePersistencePending = true
            persistSession(window: window) { [weak self, weak window] saved in
                guard let self else { return }
                self.comparisonClosePersistencePending = false
                guard self.lifecycleGeneration == generation else { return }
                guard saved, let window else {
                    window?.makeKeyAndOrderFront(nil)
                    return
                }
                self.comparisonWindowApprovedToClose = window
                self.performComparisonWindowClose(window)
            }
            return false
        }

        switch unsavedChangesDecision(
            messageText: "Save changes before closing this comparison?",
            informativeText: "Unsaved changes will be lost if you close without saving."
        ) {
        case .save:
            model.saveAllChanges { [weak self, weak window] saved in
                guard let self else { return }
                if saved {
                    guard self.lifecycleGeneration == generation else { return }
                    self.comparisonClosePersistencePending = true
                    self.persistSession(window: window) { persisted in
                        self.comparisonClosePersistencePending = false
                        guard self.lifecycleGeneration == generation else { return }
                        guard persisted, let window else {
                            window?.makeKeyAndOrderFront(nil)
                            return
                        }
                        self.comparisonWindowApprovedToClose = window
                        self.performComparisonWindowClose(window)
                    }
                } else if window != nil {
                    self.restoreComparisonWindow(.shared)
                }
            }
            return false
        case .discard:
            guard model.lockSessionDiscard() else { return false }
            comparisonClosePersistencePending = true
            clearSession { [weak self, weak window] cleared in
                guard let self else { return }
                self.comparisonClosePersistencePending = false
                guard self.lifecycleGeneration == generation else {
                    self.model.unlockSessionPersistence()
                    return
                }
                guard cleared, let window else {
                    self.model.unlockSessionPersistence()
                    window?.makeKeyAndOrderFront(nil)
                    return
                }
                self.comparisonWindowPendingDiscard = window
                self.comparisonWindowApprovedToClose = window
                self.shouldTerminateWithoutPersistingSession = true
                self.model.unlockSessionPersistence {
                    self.performComparisonWindowClose(window)
                }
            }
            return false
        case .cancel:
            return false
        }
    }

    fileprivate func comparisonWindowDidClose(_ window: NSWindow) {
        guard comparisonWindow === window else { return }
        comparisonWindowFrame = window.frame
        comparisonWindowApprovedToClose = nil
        if comparisonWindowPendingDiscard === window {
            comparisonWindowPendingDiscard = nil
            model.createEmptyComparison()
        }
        detachComparisonWindowDelegate()
    }

    fileprivate func comparisonWindowCloseWasVetoed(_ window: NSWindow) {
        guard comparisonWindow === window else { return }
        comparisonWindowApprovedToClose = nil
        if comparisonWindowPendingDiscard === window {
            comparisonWindowPendingDiscard = nil
        }
    }

    fileprivate func comparisonWindowCloseIsApproved(_ window: NSWindow) -> Bool {
        comparisonWindowApprovedToClose === window
    }

    private func unsavedChangesDecision(
        messageText: String,
        informativeText: String
    ) -> UnsavedChangesDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        return switch alert.runModal() {
        case .alertFirstButtonReturn: .save
        case .alertThirdButtonReturn: .discard
        default: .cancel
        }
    }

    private func restoreComparisonWindow(_ application: NSApplication) {
        application.activate()
        if let comparisonWindow {
            comparisonWindow.makeKeyAndOrderFront(nil)
        } else {
            openComparisonWindow?()
        }
    }

    func persistSession(
        window: NSWindow? = nil,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let window = window ?? comparisonWindow
        let frame = window?.frame ?? comparisonWindowFrame
        guard let frame else {
            if model.isReady {
                if hasPersistedCurrentSession {
                    Task { @MainActor in
                        await Task.yield()
                        completion(true)
                    }
                } else {
                    model.errorMessage = "Could not preserve this comparison because its window state is unavailable."
                    completion(false)
                }
            } else if model.hasLoadedSide {
                clearSession(completion: completion)
            } else {
                Task { @MainActor in
                    await Task.yield()
                    completion(true)
                }
            }
            return
        }
        guard model.lockSessionPersistence() else {
            model.errorMessage = "Could not preserve this comparison while it is changing."
            completion(false)
            return
        }
        let generation = lifecycleGeneration
        let store = sessionStore
        Task {
            defer { model.unlockSessionPersistence() }
            do {
                let frame = try ComparisonSessionState.WindowFrame(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.width,
                    height: frame.height
                )
                guard let state = try await model.sessionState(windowFrame: frame) else {
                    if model.isReady {
                        model.errorMessage = "Could not preserve this comparison because one or more file permissions are unavailable."
                        completion(false)
                    } else if model.hasLoadedSide {
                        let failure = await Task.detached { () -> String? in
                            do {
                                try store.clear()
                                return nil
                            } catch {
                                return error.localizedDescription
                            }
                        }.value
                        if let failure {
                            model.errorMessage = "Could not clear the incomplete comparison session. \(failure)"
                        }
                        completion(failure == nil)
                    } else {
                        completion(true)
                    }
                    return
                }
                let saveResult = await Task.detached {
                    () -> (ComparisonSessionStore.SaveReceipt?, String?) in
                    do {
                        try state.validate()
                        return (try store.save(state), nil)
                    } catch let error as ComparisonSessionStore.SaveCommitError {
                        return (error.receipt, error.localizedDescription)
                    } catch {
                        return (nil, error.localizedDescription)
                    }
                }.value
                guard lifecycleGeneration == generation else {
                    if let receipt = saveResult.0 {
                        let cleanupFailure = await Task.detached { () -> String? in
                            do {
                                try store.clear(savedBy: receipt)
                                return nil
                            } catch {
                                return error.localizedDescription
                            }
                        }.value
                        if let cleanupFailure {
                            model.errorMessage = "Could not discard an obsolete comparison session. \(cleanupFailure)"
                        }
                    }
                    completion(false)
                    return
                }
                if let failure = saveResult.1 {
                    model.errorMessage = "Could not preserve this comparison for the next launch. \(failure)"
                }
                if saveResult.1 == nil { hasPersistedCurrentSession = true }
                completion(saveResult.1 == nil)
            } catch {
                model.errorMessage = "Could not preserve this comparison for the next launch. \(error.localizedDescription)"
                completion(false)
            }
        }
    }

    private func clearSession(completion: @escaping @MainActor (Bool) -> Void) {
        let store = sessionStore
        Task {
            let failure = await Task.detached { () -> String? in
                do {
                    try store.clear()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure {
                model.errorMessage = "Could not discard the previous comparison session. \(failure)"
            }
            if failure == nil { hasPersistedCurrentSession = true }
            completion(failure == nil)
        }
    }

    private func finishTermination(_ sender: NSApplication, allowed: Bool) {
        sender.reply(toApplicationShouldTerminate: allowed)
        guard !allowed else { return }
        restoreComparisonWindow(sender)
        model.resumeQueuedOpenRequests()
    }

    private func finishInitialComparisonLoad() {
        guard isInitialComparisonLoadPending else { return }
        isInitialComparisonLoadPending = false
        let waiters = initialComparisonLoadWaiters
        initialComparisonLoadWaiters.removeAll()
        for waiter in waiters {
            waiter()
        }
    }

    private func applyPendingRestoredWindowFrame() {
        guard let window = comparisonWindow,
            let frame = pendingRestoredWindowFrame
        else { return }
        pendingRestoredWindowFrame = nil
        let requested = NSRect(
            x: frame.x,
            y: frame.y,
            width: frame.width,
            height: frame.height
        )
        let screen =
            NSScreen.screens.max {
                let first = $0.visibleFrame.intersection(requested)
                let second = $1.visibleFrame.intersection(requested)
                return first.width * first.height < second.width * second.height
            } ?? NSScreen.main
        let restored =
            screen.map { screen in
                let visible = screen.visibleFrame
                let width = min(requested.width, visible.width)
                let height = min(requested.height, visible.height)
                return NSRect(
                    x: min(max(requested.minX, visible.minX), visible.maxX - width),
                    y: min(max(requested.minY, visible.minY), visible.maxY - height),
                    width: width,
                    height: height
                )
            } ?? requested
        window.setFrame(restored, display: false)
    }

    private func presentCopyError(_ error: Error, messageText: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = messageText
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func detachComparisonWindowDelegate() {
        guard let delegate = comparisonWindowDelegate else {
            comparisonWindow = nil
            return
        }
        if let comparisonWindow, comparisonWindow.delegate === delegate {
            comparisonWindow.delegate = delegate.forwardingDelegate
        }
        delegate.owner = nil
        comparisonWindowPendingDiscard = nil
        comparisonWindowApprovedToClose = nil
        comparisonClosePersistencePending = false
        comparisonWindow = nil
        comparisonWindowDelegate = nil
    }
}

@MainActor
private final class ComparisonWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var owner: ApplicationDelegate?
    nonisolated(unsafe) weak var forwardingDelegate: (any NSWindowDelegate)?

    init(owner: ApplicationDelegate, forwardingTo delegate: (any NSWindowDelegate)?) {
        self.owner = owner
        forwardingDelegate = delegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if owner?.comparisonWindowCloseIsApproved(sender) == true {
            return owner?.comparisonWindowShouldClose(sender) != false
        }
        guard forwardingDelegate?.windowShouldClose?(sender) != false else {
            owner?.comparisonWindowCloseWasVetoed(sender)
            return false
        }
        guard owner?.comparisonWindowShouldClose(sender) != false else { return false }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        let forwardingDelegate = forwardingDelegate
        guard let window = notification.object as? NSWindow else { return }
        owner?.comparisonWindowDidClose(window)
        forwardingDelegate?.windowWillClose?(notification)
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || forwardingDelegate?.responds(to: aSelector) == true
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forwardingDelegate?.responds(to: aSelector) == true {
            return forwardingDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

enum ComparisonCopyCommand: CaseIterable {
    case selectedToRight
    case selectedToLeft
    case selectedToRightAndAdvance
    case selectedToLeftAndAdvance
    case allToRight
    case allToLeft

    var menuTitle: String {
        switch self {
        case .selectedToRight: "Copy to Right"
        case .selectedToLeft: "Copy to Left"
        case .selectedToRightAndAdvance: "Copy to Right and Advance"
        case .selectedToLeftAndAdvance: "Copy to Left and Advance"
        case .allToRight: "Copy All to Right"
        case .allToLeft: "Copy All to Left"
        }
    }

    var toolbarLabel: String {
        switch self {
        case .selectedToRight: "Copy selected difference to right"
        case .selectedToLeft: "Copy selected difference to left"
        case .selectedToRightAndAdvance: "Copy selected difference to right and advance"
        case .selectedToLeftAndAdvance: "Copy selected difference to left and advance"
        case .allToRight: "Copy all differences to right"
        case .allToLeft: "Copy all differences to left"
        }
    }

    var direction: MergeDirection {
        switch self {
        case .selectedToRight, .selectedToRightAndAdvance, .allToRight: .leftToRight
        case .selectedToLeft, .selectedToLeftAndAdvance, .allToLeft: .rightToLeft
        }
    }

    var policyCommand: MergeCommandPolicy.Command {
        switch self {
        case .selectedToRight: .leftToRight
        case .selectedToLeft: .rightToLeft
        case .selectedToRightAndAdvance: .leftToRightAndAdvance
        case .selectedToLeftAndAdvance: .rightToLeftAndAdvance
        case .allToRight: .copyAllToRight
        case .allToLeft: .copyAllToLeft
        }
    }

    @MainActor
    func perform(on model: ComparisonModel) {
        guard isEnabled(on: model) else { return }
        switch self {
        case .selectedToRight, .selectedToLeft:
            model.mergeSelectedDifference(direction: direction, advance: false)
        case .selectedToRightAndAdvance, .selectedToLeftAndAdvance:
            model.mergeSelectedDifference(direction: direction, advance: true)
        case .allToRight, .allToLeft:
            model.mergeAll(direction: direction)
        }
    }

    @MainActor
    func isEnabled(on model: ComparisonModel) -> Bool {
        model.isMergeCommandEnabled(policyCommand)
    }
}

enum ComparisonSaveCommand: CaseIterable {
    case left
    case right

    var side: ComparisonSide {
        switch self {
        case .left: .left
        case .right: .right
        }
    }

    var policyCommand: MergeCommandPolicy.Command {
        switch self {
        case .left: .saveLeft
        case .right: .saveRight
        }
    }

    @MainActor
    func perform(
        on model: ComparisonModel,
        scratchpadDestination: URL? = nil,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard isEnabled(on: model) else {
            completion?(false)
            return
        }
        model.save(
            side,
            scratchpadDestination: scratchpadDestination,
            completion: completion
        )
    }

    @MainActor
    func isEnabled(on model: ComparisonModel) -> Bool {
        model.isMergeCommandEnabled(policyCommand)
    }
}

enum ComparisonReadOnlyCommand: CaseIterable, Hashable {
    case left
    case right

    var side: ComparisonSide {
        switch self {
        case .left: .left
        case .right: .right
        }
    }

    var menuTitle: String {
        switch self {
        case .left: "Left Read-Only"
        case .right: "Right Read-Only"
        }
    }

    @MainActor
    func isEnabled(on model: ComparisonModel) -> Bool {
        model.canSetEditable(on: side)
    }

    @MainActor
    func isOn(on model: ComparisonModel) -> Bool {
        let file = side == .left ? model.left : model.right
        return file.isLoaded && !file.isEditable
    }

    @MainActor
    func setReadOnly(_ readOnly: Bool, on model: ComparisonModel) {
        guard isEnabled(on: model) else { return }
        model.setEditable(!readOnly, on: side)
    }

    @MainActor
    func perform(on model: ComparisonModel) {
        setReadOnly(!isOn(on: model), on: model)
    }
}

private enum ComparisonReadOnlyPresentation {
    static func actionLabel(
        side: ComparisonSide,
        isLoaded: Bool,
        isEditable: Bool
    ) -> String {
        let sideName = side == .left ? "left" : "right"
        guard isLoaded else { return "No \(sideName) file loaded" }
        return isEditable
            ? "Make \(sideName) file read-only"
            : "Make \(sideName) file editable"
    }

    static func accessibilityValue(isLoaded: Bool, isEditable: Bool) -> String {
        guard isLoaded else { return "No file loaded" }
        return isEditable ? "Editable" : "Read-only"
    }
}

private struct WinMergeCommands: Commands {
    let applicationDelegate: ApplicationDelegate

    private var model: ComparisonModel { applicationDelegate.model }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Text Comparison", action: applicationDelegate.requestNewComparison)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.canCreateEmptyComparison)
            Button("Open...", action: applicationDelegate.openComparison)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isWorking)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                model.saveAllChanges { _ in }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.hasUnsavedChanges || model.isWorking)
            Divider()
            Button("Save Left") {
                ComparisonSaveCommand.left.perform(on: model)
            }
            .disabled(!ComparisonSaveCommand.left.isEnabled(on: model))
            Button("Save Right") {
                ComparisonSaveCommand.right.perform(on: model)
            }
            .disabled(!ComparisonSaveCommand.right.isEnabled(on: model))
            Divider()
            Button("Save Left As...", action: { model.saveAs(.left) })
                .disabled(!model.left.isLoaded || model.isWorking)
            Button("Save Right As...", action: { model.saveAs(.right) })
                .disabled(!model.right.isLoaded || model.isWorking)
            Divider()
            Menu("Read-Only") {
                Toggle(
                    ComparisonReadOnlyCommand.left.menuTitle,
                    isOn: Binding(
                        get: { ComparisonReadOnlyCommand.left.isOn(on: model) },
                        set: { ComparisonReadOnlyCommand.left.setReadOnly($0, on: model) }
                    )
                )
                .disabled(!ComparisonReadOnlyCommand.left.isEnabled(on: model))
                Toggle(
                    ComparisonReadOnlyCommand.right.menuTitle,
                    isOn: Binding(
                        get: { ComparisonReadOnlyCommand.right.isOn(on: model) },
                        set: { ComparisonReadOnlyCommand.right.setReadOnly($0, on: model) }
                    )
                )
                .disabled(!ComparisonReadOnlyCommand.right.isEnabled(on: model))
            }
            Divider()
            Toggle(
                "Merge Mode",
                isOn: Binding(
                    get: { model.isMergeMode },
                    set: { model.setMergeMode($0) }
                )
            )
            .keyboardShortcut(KeyEquivalent("\u{F70C}"), modifiers: [])
            Divider()
            Button("Reload from Disk", action: applicationDelegate.requestReloadComparison)
                .keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: .command)
                .disabled(!model.canReloadFromDisk)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo", action: applicationDelegate.undo)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!applicationDelegate.canUndo)
            Button("Redo", action: applicationDelegate.redo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!applicationDelegate.canRedo)
        }
        CommandGroup(after: .undoRedo) {
            Button("Select Line Difference", action: model.selectLineDifference)
                .keyboardShortcut(KeyEquivalent("\u{F707}"), modifiers: [])
                .disabled(!model.canSelectLineDifference)
            Button("Select Previous Line Difference", action: model.selectPreviousLineDifference)
                .keyboardShortcut(KeyEquivalent("\u{F707}"), modifiers: .shift)
                .disabled(!model.canSelectLineDifference)
        }
        CommandMenu("Merge") {
            Button("Next Difference", action: model.selectNextDifference)
                .keyboardShortcut(KeyEquivalent("\u{F70B}"), modifiers: [])
                .disabled(!model.canSelectNextDifference)
            Button("Previous Difference", action: model.selectPreviousDifference)
                .keyboardShortcut(KeyEquivalent("\u{F70A}"), modifiers: [])
                .disabled(!model.canSelectPreviousDifference)
            Button("First Difference", action: model.selectFirstDifference)
                .disabled(!model.canNavigateDifferences)
            Button("Current Difference", action: model.selectCurrentDifference)
                .disabled(!model.canSelectCurrentDifference)
            Button("Last Difference", action: model.selectLastDifference)
                .disabled(!model.canNavigateDifferences)
            Divider()
            Button(ComparisonCopyCommand.selectedToRight.menuTitle) {
                ComparisonCopyCommand.selectedToRight.perform(on: model)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!ComparisonCopyCommand.selectedToRight.isEnabled(on: model))
            Button(ComparisonCopyCommand.selectedToLeft.menuTitle) {
                ComparisonCopyCommand.selectedToLeft.perform(on: model)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!ComparisonCopyCommand.selectedToLeft.isEnabled(on: model))
            Button(ComparisonCopyCommand.selectedToRightAndAdvance.menuTitle) {
                ComparisonCopyCommand.selectedToRightAndAdvance.perform(on: model)
            }
            .disabled(!ComparisonCopyCommand.selectedToRightAndAdvance.isEnabled(on: model))
            Button(ComparisonCopyCommand.selectedToLeftAndAdvance.menuTitle) {
                ComparisonCopyCommand.selectedToLeftAndAdvance.perform(on: model)
            }
            .disabled(!ComparisonCopyCommand.selectedToLeftAndAdvance.isEnabled(on: model))
            Divider()
            Button(ComparisonCopyCommand.allToRight.menuTitle) {
                ComparisonCopyCommand.allToRight.perform(on: model)
            }
            .disabled(!ComparisonCopyCommand.allToRight.isEnabled(on: model))
            Button(ComparisonCopyCommand.allToLeft.menuTitle) {
                ComparisonCopyCommand.allToLeft.perform(on: model)
            }
            .disabled(!ComparisonCopyCommand.allToLeft.isEnabled(on: model))
        }
        CommandGroup(after: .toolbar) {
            Toggle(
                "Location Pane",
                isOn: Binding(
                    get: { model.isLocationPaneVisible },
                    set: { model.setLocationPaneVisible($0) }
                ))
            Divider()
            Button("Refresh", action: model.refresh)
                .keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: [])
                .disabled(!model.canRefresh)
        }
        CommandGroup(after: .windowArrangement) {
            Button("Change Pane", action: model.changePane)
                .keyboardShortcut(KeyEquivalent("\u{F709}"), modifiers: [])
                .disabled(!model.isReady || model.isWorking)
            Button("Change Pane Back", action: model.changePane)
                .keyboardShortcut(KeyEquivalent("\u{F709}"), modifiers: [.shift])
                .disabled(!model.isReady || model.isWorking)
        }
        CommandMenu("Tools") {
            Button("Filters...") {}
                .disabled(true)
            Button("Generate Patch...") {}
                .disabled(true)
            Divider()
            SettingsLink {
                Text("Options...")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Plugins") {
            Button("No plugins installed") {}
                .disabled(true)
        }
        CommandGroup(after: .help) {
            Button("Copy Configuration Report", action: applicationDelegate.copyConfigurationReport)
        }
    }
}

@MainActor
enum ComparisonUndoRouter {
    static func focusedEditableTextView(
        in window: NSWindow? = NSApplication.shared.keyWindow
    ) -> NSTextView? {
        guard let textView = window?.firstResponder as? NSTextView,
            textView.isEditable
        else { return nil }
        return textView
    }

    static func canUndo(model: ComparisonModel) -> Bool {
        canUndo(
            model: model,
            in: NSApplication.shared.keyWindow,
            allowsComparisonFallback: false
        )
    }

    static func canUndo(
        model: ComparisonModel,
        in window: NSWindow?,
        allowsComparisonFallback: Bool = true
    ) -> Bool {
        let focusedTextView = focusedEditableTextView(in: window)
        guard focusedTextView != nil || allowsComparisonFallback else { return false }
        return canUndo(model: model, focusedTextView: focusedTextView)
    }

    static func canUndo(model: ComparisonModel, focusedTextView: NSTextView?) -> Bool {
        guard let focusedTextView else { return model.canUndo }
        if let diffTextView = focusedTextView as? DiffContextTextView,
            diffTextView.routesUndoToComparisonHistory
                || focusedTextView.undoManager?.canUndo != true
        {
            return model.canUndo
        }
        return focusedTextView.undoManager?.canUndo == true
    }

    static func canRedo(model: ComparisonModel) -> Bool {
        canRedo(
            model: model,
            in: NSApplication.shared.keyWindow,
            allowsComparisonFallback: false
        )
    }

    static func canRedo(
        model: ComparisonModel,
        in window: NSWindow?,
        allowsComparisonFallback: Bool = true
    ) -> Bool {
        let focusedTextView = focusedEditableTextView(in: window)
        guard focusedTextView != nil || allowsComparisonFallback else { return false }
        return canRedo(model: model, focusedTextView: focusedTextView)
    }

    static func canRedo(model: ComparisonModel, focusedTextView: NSTextView?) -> Bool {
        guard let focusedTextView else { return model.canRedo }
        if let diffTextView = focusedTextView as? DiffContextTextView,
            diffTextView.routesUndoToComparisonHistory
                || focusedTextView.undoManager?.canRedo != true
        {
            return model.canRedo
        }
        return focusedTextView.undoManager?.canRedo == true
    }

    static func undo(model: ComparisonModel) {
        undo(
            model: model,
            in: NSApplication.shared.keyWindow,
            allowsComparisonFallback: false
        )
    }

    static func undo(
        model: ComparisonModel,
        in window: NSWindow?,
        allowsComparisonFallback: Bool = true
    ) {
        let focusedTextView = focusedEditableTextView(in: window)
        guard focusedTextView != nil || allowsComparisonFallback else { return }
        undo(model: model, focusedTextView: focusedTextView)
    }

    static func undo(model: ComparisonModel, focusedTextView: NSTextView?) {
        guard let focusedTextView else {
            model.undo()
            return
        }
        if let diffTextView = focusedTextView as? DiffContextTextView,
            diffTextView.routesUndoToComparisonHistory
                || focusedTextView.undoManager?.canUndo != true
        {
            model.undo()
            return
        }
        focusedTextView.undoManager?.undo()
    }

    static func redo(model: ComparisonModel) {
        redo(
            model: model,
            in: NSApplication.shared.keyWindow,
            allowsComparisonFallback: false
        )
    }

    static func redo(
        model: ComparisonModel,
        in window: NSWindow?,
        allowsComparisonFallback: Bool = true
    ) {
        let focusedTextView = focusedEditableTextView(in: window)
        guard focusedTextView != nil || allowsComparisonFallback else { return }
        redo(model: model, focusedTextView: focusedTextView)
    }

    static func redo(model: ComparisonModel, focusedTextView: NSTextView?) {
        guard let focusedTextView else {
            model.redo()
            return
        }
        if let diffTextView = focusedTextView as? DiffContextTextView,
            diffTextView.routesUndoToComparisonHistory
                || focusedTextView.undoManager?.canRedo != true
        {
            model.redo()
            return
        }
        focusedTextView.undoManager?.redo()
    }
}

private struct ComparisonSettingsView: View {
    let model: ComparisonModel
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: ComparisonOptionsDocument?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            TabView {
                Form {
                    Picker("Algorithm", selection: optionBinding(\.algorithm)) {
                        Text("Default").tag(DiffAlgorithm.default)
                        Text("Minimal").tag(DiffAlgorithm.minimal)
                        Text("Patience").tag(DiffAlgorithm.patience)
                        Text("Histogram").tag(DiffAlgorithm.histogram)
                        Text("None").tag(DiffAlgorithm.none)
                    }
                    Picker("Whitespace", selection: optionBinding(\.whitespace)) {
                        Text("Compare all").tag(WhitespaceComparison.compareAll)
                        Text("Ignore changes").tag(WhitespaceComparison.ignoreChanges)
                        Text("Ignore all").tag(WhitespaceComparison.ignoreAll)
                    }
                    Toggle("Ignore case", isOn: optionBinding(\.ignoreCase))
                    Toggle("Ignore numbers", isOn: optionBinding(\.ignoreNumbers))
                    Toggle("Ignore blank lines", isOn: optionBinding(\.ignoreBlankLines))
                    Toggle("Ignore comment differences", isOn: optionBinding(\.ignoreComments))
                    Toggle("Ignore line ending style", isOn: optionBinding(\.ignoreLineEndings))
                    Toggle("Indent heuristic", isOn: optionBinding(\.indentHeuristic))
                    Toggle("Detect moved blocks", isOn: optionBinding(\.detectMovedBlocks))
                }
                .formStyle(.grouped)
                .padding(.horizontal, 12)
                .tabItem { Label("Compare", systemImage: "text.page") }

                FilterSettingsView(model: model)
                    .id(model.optionsRevision)
                    .tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
            }

            HStack {
                Button("Import...") { isImporting = true }
                Button("Export...") {
                    exportDocument = ComparisonOptionsDocument(options: model.options)
                    isExporting = true
                }
                Spacer()
                Button("Reset to Defaults", action: model.resetOptions)
                    .disabled(model.options == LineDiffOptions())
            }
        }
        .padding(20)
        .frame(width: 680, height: 520)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importOptions
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "MacMerge Comparison Options"
        ) { result in
            if case .failure(let error) = result, !isCancellation(error) {
                errorMessage = "Could not export comparison options. \(error.localizedDescription)"
            }
            exportDocument = nil
        }
        .alert(
            "Comparison options",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func optionBinding<Value>(
        _ keyPath: WritableKeyPath<LineDiffOptions, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.options[keyPath: keyPath] },
            set: { value in
                var options = model.options
                options[keyPath: keyPath] = value
                model.setOptions(options)
            }
        )
    }

    private func importOptions(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let options = try JSONDecoder().decode(
                LineDiffOptions.self,
                from: Data(contentsOf: url)
            )
            model.setOptions(options)
        } catch {
            guard !isCancellation(error) else { return }
            errorMessage = "Could not import comparison options. \(error.localizedDescription)"
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}

private struct FilterSettingsView: View {
    private struct LineFilterDraft: Identifiable {
        let id = UUID()
        var pattern: String
        var caseSensitive: Bool
    }

    private struct SubstitutionDraft: Identifiable {
        let id = UUID()
        var pattern: String
        var replacement: String
        var caseSensitive: Bool
    }

    let model: ComparisonModel
    @State private var lineFiltersEnabled: Bool
    @State private var lineFilters: [LineFilterDraft]
    @State private var substitutionsEnabled: Bool
    @State private var substitutions: [SubstitutionDraft]
    @State private var errorMessage: String?

    init(model: ComparisonModel) {
        self.model = model
        _lineFiltersEnabled = State(initialValue: model.options.lineFiltersEnabled)
        _lineFilters = State(
            initialValue: model.options.lineFilters.map {
                LineFilterDraft(pattern: $0.pattern, caseSensitive: $0.caseSensitive)
            })
        _substitutionsEnabled = State(initialValue: model.options.substitutionsEnabled)
        _substitutions = State(
            initialValue: model.options.substitutions.map {
                SubstitutionDraft(
                    pattern: $0.pattern,
                    replacement: $0.replacement,
                    caseSensitive: $0.caseSensitive
                )
            })
    }

    var body: some View {
        Form {
            Section("Line Filters") {
                Toggle("Enable line filters", isOn: $lineFiltersEnabled)
                Text("Matching lines are ignored when differences are evaluated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($lineFilters) { $filter in
                    HStack {
                        TextField("Regular expression", text: $filter.pattern)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Match case", isOn: $filter.caseSensitive)
                        Button("Remove", systemImage: "minus.circle") {
                            lineFilters.removeAll { $0.id == filter.id }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                Button("Add Line Filter", systemImage: "plus") {
                    lineFilters.append(LineFilterDraft(pattern: "", caseSensitive: true))
                }
            }

            Section("Substitution Filters") {
                Toggle("Enable substitutions", isOn: $substitutionsEnabled)
                Text("Pattern matches are replaced only for comparison; saved files are unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($substitutions) { $substitution in
                    HStack {
                        TextField("Regular expression", text: $substitution.pattern)
                            .textFieldStyle(.roundedBorder)
                        TextField("Replacement", text: $substitution.replacement)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Match case", isOn: $substitution.caseSensitive)
                        Button("Remove", systemImage: "minus.circle") {
                            substitutions.removeAll { $0.id == substitution.id }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                HStack {
                    Button("Add Substitution", systemImage: "plus") {
                        substitutions.append(
                            SubstitutionDraft(
                                pattern: "",
                                replacement: "",
                                caseSensitive: true
                            ))
                    }
                    Spacer()
                    Button("Clear All") {
                        lineFilters.removeAll()
                        substitutions.removeAll()
                    }
                    .disabled(lineFilters.isEmpty && substitutions.isEmpty)
                    Button("Apply", action: apply)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
        .alert(
            "Invalid comparison filter",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func apply() {
        var options = model.options
        options.lineFiltersEnabled = lineFiltersEnabled
        options.lineFilters = lineFilters.map {
            LineFilterRule(pattern: $0.pattern, caseSensitive: $0.caseSensitive)
        }
        options.substitutionsEnabled = substitutionsEnabled
        options.substitutions = substitutions.map {
            SubstitutionRule(
                pattern: $0.pattern,
                replacement: $0.replacement,
                caseSensitive: $0.caseSensitive
            )
        }
        do {
            _ = try LineDiff.compare(left: "", right: "", options: options)
            model.setOptions(options)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ComparisonOptionsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let options: LineDiffOptions

    init(options: LineDiffOptions) {
        self.options = options
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        options = try JSONDecoder().decode(LineDiffOptions.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(options))
    }
}

enum ComparisonSide: Equatable, Hashable, Sendable {
    case left
    case right
}

enum SessionRestoreResult: Equatable, Sendable {
    case restored
    case cancelled
    case failed
}

enum LineDifferenceSelectionDirection: Equatable, Sendable {
    case next
    case previous
}

struct DiffFocusRequest: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case focusEditor(rowID: DiffRow.ID?, side: ComparisonSide, centersRow: Bool)
        case selectLineDifference(
            rowID: DiffRow.ID,
            side: ComparisonSide,
            direction: LineDifferenceSelectionDirection
        )
        case continueEditing(
            side: ComparisonSide,
            lineNumber: Int,
            afterRowsRevision: Int
        )
    }

    let generation: Int
    let action: Action
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
    var isEditable: Bool

    init(
        document: TextFileDocument? = nil,
        scratchpad: Scratchpad? = nil,
        isEditable: Bool? = nil
    ) {
        self.document = document
        self.scratchpad = scratchpad
        self.isEditable = isEditable ?? (document != nil || scratchpad != nil)
    }

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
            scratchpad: Scratchpad(name: name, text: "", persistedText: ""),
            isEditable: true
        )
    }
}

private struct ComparisonRenderResult: Sendable {
    let rows: [DiffRow]
    let maximumLineColumns: Int
    let differenceLocations: DifferenceLocations
    let differenceRowIndices: [UInt32]
    let locationMap: LocationMap
    let movedRows: MovedRowMap
    let summary: DiffSummary
}

struct MovedRowBlock: Equatable, Sendable {
    let leftStartRow: UInt32
    let leftEndRow: UInt32
    let rightStartRow: UInt32
    let rightEndRow: UInt32
}

struct MovedRowMap: Equatable, Sendable {
    private var leftToRight: [UInt64]
    private var rightToLeft: [UInt64]
    private(set) var blocks: [MovedRowBlock]

    init() {
        leftToRight = []
        rightToLeft = []
        blocks = []
    }

    init(rows: [DiffRow], movedLines: MovedLines) {
        leftToRight = []
        rightToLeft = []
        blocks = []
        guard !rows.isEmpty, !movedLines.isEmpty else { return }
        var connectorPairs = Set<UInt64>()
        let maximumLeftLine = rows.lazy.compactMap { $0.id.leftNumber }.max() ?? 0
        let maximumRightLine = rows.lazy.compactMap { $0.id.rightNumber }.max() ?? 0
        var leftRows = Array(repeating: UInt32.max, count: maximumLeftLine)
        var rightRows = Array(repeating: UInt32.max, count: maximumRightLine)
        var significantRows = Array(repeating: false, count: rows.count)
        for (rowIndex, row) in rows.enumerated() {
            guard let packedRow = UInt32(exactly: rowIndex) else {
                preconditionFailure("Moved row exceeds comparison limits")
            }
            let id = row.id
            if let line = id.leftNumber, leftRows.indices.contains(line - 1) {
                leftRows[line - 1] = packedRow
            }
            if let line = id.rightNumber, rightRows.indices.contains(line - 1) {
                rightRows[line - 1] = packedRow
            }
            significantRows[rowIndex] = row.kind != .unchanged
        }

        leftToRight.reserveCapacity(movedLines.leftToRightCount)
        for index in 0..<movedLines.leftToRightCount {
            let pair = movedLines.leftToRightPair(at: index)
            guard leftRows.indices.contains(pair.leftLine - 1),
                rightRows.indices.contains(pair.rightLine - 1)
            else { continue }
            let leftRow = leftRows[pair.leftLine - 1]
            let rightRow = rightRows[pair.rightLine - 1]
            guard leftRow != .max,
                rightRow != .max,
                significantRows[Int(leftRow)],
                significantRows[Int(rightRow)]
            else { continue }
            leftToRight.append(Self.pack(sourceLine: pair.leftLine, targetRow: rightRow))
            connectorPairs.insert(Self.pack(leftRow: leftRow, rightRow: rightRow))
        }

        rightToLeft.reserveCapacity(movedLines.rightToLeftCount)
        for index in 0..<movedLines.rightToLeftCount {
            let pair = movedLines.rightToLeftPair(at: index)
            guard leftRows.indices.contains(pair.leftLine - 1),
                rightRows.indices.contains(pair.rightLine - 1)
            else { continue }
            let leftRow = leftRows[pair.leftLine - 1]
            let rightRow = rightRows[pair.rightLine - 1]
            guard leftRow != .max,
                rightRow != .max,
                significantRows[Int(leftRow)],
                significantRows[Int(rightRow)]
            else { continue }
            rightToLeft.append(Self.pack(sourceLine: pair.rightLine, targetRow: leftRow))
            connectorPairs.insert(Self.pack(leftRow: leftRow, rightRow: rightRow))
        }

        for entry in connectorPairs.sorted() {
            let leftRow = UInt32(entry >> 32)
            let rightRow = UInt32(truncatingIfNeeded: entry)
            if leftRow > 0,
                rightRow > 0,
                connectorPairs.contains(Self.pack(leftRow: leftRow - 1, rightRow: rightRow - 1))
            {
                continue
            }
            var leftEndRow = leftRow + 1
            var rightEndRow = rightRow + 1
            while connectorPairs.contains(Self.pack(leftRow: leftEndRow, rightRow: rightEndRow)) {
                leftEndRow += 1
                rightEndRow += 1
            }
            blocks.append(
                MovedRowBlock(
                    leftStartRow: leftRow,
                    leftEndRow: leftEndRow,
                    rightStartRow: rightRow,
                    rightEndRow: rightEndRow
                ))
        }
    }

    #if DEBUG
        init(testRows rows: [DiffRow], movedLeft: Bool, movedRight: Bool) {
            self.init()
            guard movedLeft || movedRight else { return }
            if movedLeft {
                leftToRight = rows.compactMap { row in
                    guard let line = row.left?.number else { return nil }
                    return Self.pack(sourceLine: line, targetRow: 0)
                }
            }
            if movedRight {
                rightToLeft = rows.compactMap { row in
                    guard let line = row.right?.number else { return nil }
                    return Self.pack(sourceLine: line, targetRow: 0)
                }
            }
        }
    #endif

    var isEmpty: Bool { leftToRight.isEmpty && rightToLeft.isEmpty }
    var blockCount: Int { blocks.count }
    var shallowStorageBytes: Int {
        (leftToRight.count + rightToLeft.count) * MemoryLayout<UInt64>.stride
            + blocks.count * MemoryLayout<MovedRowBlock>.stride
    }

    func isMoved(line: Int, on side: ComparisonSide) -> Bool {
        targetRow(forLine: line, on: side) != nil
    }

    func targetRow(forLine line: Int, on side: ComparisonSide) -> Int? {
        let entries = side == .left ? leftToRight : rightToLeft
        guard let source = UInt32(exactly: line), source != 0 else { return nil }
        var lower = entries.startIndex
        var upper = entries.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if UInt32(entries[middle] >> 32) < source {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < entries.endIndex, UInt32(entries[lower] >> 32) == source else {
            return nil
        }
        return Int(UInt32(truncatingIfNeeded: entries[lower]))
    }

    private static func pack(sourceLine: Int, targetRow: UInt32) -> UInt64 {
        guard let source = UInt32(exactly: sourceLine), source != 0 else {
            preconditionFailure("Moved line exceeds comparison limits")
        }
        return UInt64(source) << 32 | UInt64(targetRow)
    }

    private static func pack(leftRow: UInt32, rightRow: UInt32) -> UInt64 {
        UInt64(leftRow) << 32 | UInt64(rightRow)
    }
}

struct LocationMapBlock: Equatable, Sendable {
    let startRow: UInt32
    let endRow: UInt32
    let kind: DiffKind
}

struct LocationMap: Equatable, Sendable {
    private static let rowBits = 21
    private static let rowMask = (UInt64(1) << rowBits) - 1
    private(set) var rowCount = 0
    private var entries: [UInt64] = []

    init() {}

    init(rows: [DiffRow]) {
        for row in rows {
            append(row.kind)
        }
    }

    mutating func append(_ kind: DiffKind) {
        guard let rowIndex = UInt32(exactly: rowCount) else {
            preconditionFailure("Location map exceeds comparison limits")
        }
        rowCount += 1
        guard kind != .unchanged else { return }
        if let lastIndex = entries.indices.last,
            block(at: lastIndex).kind == kind,
            block(at: lastIndex).endRow == rowIndex
        {
            let startRow = block(at: lastIndex).startRow
            entries[lastIndex] = Self.pack(startRow: startRow, endRow: rowIndex + 1, kind: kind)
        } else {
            entries.append(Self.pack(startRow: rowIndex, endRow: rowIndex + 1, kind: kind))
        }
    }

    var blockCount: Int { entries.count }
    var shallowStorageBytes: Int { entries.count * MemoryLayout<UInt64>.stride }
    var blocks: [LocationMapBlock] { entries.indices.map(block(at:)) }

    func block(at index: Int) -> LocationMapBlock {
        let entry = entries[index]
        let kind: DiffKind =
            switch entry >> (Self.rowBits * 2) {
            case 1: .modified
            case 2: .removed
            default: .added
            }
        return LocationMapBlock(
            startRow: UInt32(entry & Self.rowMask),
            endRow: UInt32((entry >> Self.rowBits) & Self.rowMask),
            kind: kind
        )
    }

    func rowIndex(at fraction: Double) -> Int? {
        guard rowCount > 0, fraction.isFinite else { return nil }
        let clamped = min(max(0, fraction), 1)
        return min(rowCount - 1, Int((Double(rowCount) * clamped).rounded(.down)))
    }

    private static func pack(startRow: UInt32, endRow: UInt32, kind: DiffKind) -> UInt64 {
        precondition(UInt64(startRow) <= rowMask && UInt64(endRow) <= rowMask)
        let kindValue: UInt64 =
            switch kind {
            case .modified: 1
            case .removed: 2
            case .added: 3
            case .unchanged: 0
            }
        return UInt64(startRow) | (UInt64(endRow) << rowBits) | (kindValue << (rowBits * 2))
    }
}

struct LocationViewport: Equatable, Sendable {
    let startRow: Int
    let endRow: Int

    static let empty = LocationViewport(startRow: 0, endRow: 0)

    init(startRow: Int, endRow: Int) {
        self.startRow = max(0, startRow)
        self.endRow = max(self.startRow, endRow)
    }

    var rowCount: Int { endRow - startRow }

    func contains(row: Int) -> Bool {
        startRow <= row && row < endRow
    }

    func position(totalRowCount: Int) -> Double {
        let maximumStart = max(0, totalRowCount - rowCount)
        guard maximumStart > 0 else { return 0 }
        return Double(min(startRow, maximumStart)) / Double(maximumStart)
    }

    func centeredRow(at position: Double, totalRowCount: Int) -> Int? {
        guard totalRowCount > 0, position.isFinite else { return nil }
        let maximumStart = max(0, totalRowCount - rowCount)
        let targetStart = Int((Double(maximumStart) * min(max(0, position), 1)).rounded())
        return min(totalRowCount - 1, targetStart + rowCount / 2)
    }
}

struct DifferenceLocation: Sendable {
    let rowIndex: Int
}

struct DifferenceLocations: Sendable {
    private static let lineNumberBits = 21
    private static let lineNumberMask = (UInt64(1) << lineNumberBits) - 1
    private static let rowIndexMask = (UInt64(1) << lineNumberBits) - 1
    private var entries: [UInt64]

    init() {
        entries = []
    }

    init(rows: [DiffRow], differenceRowIndices: [UInt32]) {
        guard !differenceRowIndices.isEmpty else {
            entries = []
            return
        }
        var capacity = 1
        while capacity < differenceRowIndices.count * 2 { capacity <<= 1 }
        entries = Array(repeating: 0, count: capacity)
        for rowIndex in differenceRowIndices {
            insert(rows[Int(rowIndex)].id, rowIndex: rowIndex)
        }
    }

    subscript(id: DiffRow.ID) -> DifferenceLocation? {
        guard !entries.isEmpty, let key = Self.key(for: id) else { return nil }
        var slot = Self.hash(key) & (entries.count - 1)
        for _ in entries.indices {
            let entry = entries[slot]
            if entry == 0 { return nil }
            let storedKey = entry & ((UInt64(1) << (Self.lineNumberBits * 2)) - 1)
            if storedKey == key {
                return DifferenceLocation(
                    rowIndex: Int((entry >> (Self.lineNumberBits * 2)) & Self.rowIndexMask)
                )
            }
            slot = (slot + 1) & (entries.count - 1)
        }
        return nil
    }

    var shallowStorageBytes: Int {
        entries.count * MemoryLayout<UInt64>.stride
    }

    private mutating func insert(_ id: DiffRow.ID, rowIndex: UInt32) {
        guard let key = Self.key(for: id), UInt64(rowIndex) <= Self.rowIndexMask else {
            preconditionFailure("Difference location exceeds comparison limits")
        }
        var slot = Self.hash(key) & (entries.count - 1)
        let keyMask = (UInt64(1) << (Self.lineNumberBits * 2)) - 1
        while entries[slot] != 0 {
            precondition(entries[slot] & keyMask != key, "Duplicate difference row ID")
            slot = (slot + 1) & (entries.count - 1)
        }
        entries[slot] = key | (UInt64(rowIndex) << (Self.lineNumberBits * 2))
    }

    private static func key(for id: DiffRow.ID) -> UInt64? {
        let left = id.leftNumber ?? 0
        let right = id.rightNumber ?? 0
        guard id.leftNumber.map({ (1...Int(lineNumberMask)).contains($0) }) ?? true,
            id.rightNumber.map({ (1...Int(lineNumberMask)).contains($0) }) ?? true
        else { return nil }
        let key = UInt64(left) | (UInt64(right) << lineNumberBits)
        return key == 0 ? nil : key
    }

    private static func hash(_ key: UInt64) -> Int {
        var value = key
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Int(truncatingIfNeeded: value)
    }
}

private actor ComparisonWorker {
    func compare(left: String, right: String, options: LineDiffOptions) throws -> ComparisonRenderResult {
        let signpostID = PerformanceTrace.begin("Comparison")
        defer { PerformanceTrace.end("Comparison", id: signpostID) }
        PerformanceProbe.shared.begin("comparison")
        defer { PerformanceProbe.shared.end("comparison") }
        try Task.checkCancellation()
        return try computeComparison(left: left, right: right, options: options)
    }
}

private func computeComparison(
    left: String,
    right: String,
    options: LineDiffOptions = LineDiffOptions()
) throws -> ComparisonRenderResult {
    let result = try LineDiff.compareResult(left: left, right: right, options: options)
    let rows = result.rows
    var maximumLineColumns = 0
    var differenceRowIndices: [UInt32] = []
    var locationMap = LocationMap()
    for (index, row) in rows.enumerated() {
        locationMap.append(row.kind)
        maximumLineColumns = max(
            maximumLineColumns,
            row.left.map { displayColumnCount($0.text) } ?? 0,
            row.right.map { displayColumnCount($0.text) } ?? 0
        )
        if row.kind != .unchanged {
            guard let rowIndex = UInt32(exactly: index) else {
                preconditionFailure("Difference row exceeds comparison limits")
            }
            differenceRowIndices.append(rowIndex)
        }
    }
    let differenceLocations = DifferenceLocations(
        rows: rows,
        differenceRowIndices: differenceRowIndices
    )
    return ComparisonRenderResult(
        rows: rows,
        maximumLineColumns: maximumLineColumns,
        differenceLocations: differenceLocations,
        differenceRowIndices: differenceRowIndices,
        locationMap: locationMap,
        movedRows: MovedRowMap(rows: rows, movedLines: result.movedLines),
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

private let intralineUTF8Budget = 16_384
private let intralineUTF16Budget = 8_192
private let intralineCharacterBudget = 2_048

func intralineDifferenceRanges(in text: String, comparedWith other: String) -> [NSRange] {
    guard !exceedsIntralineBudget(text), !exceedsIntralineBudget(other) else {
        return []
    }
    guard text != other else { return [] }
    let characters = Array(text)
    let otherCharacters = Array(other)
    let difference = characters.difference(from: otherCharacters)
    var insertions = Array(repeating: false, count: characters.count)
    var removals = Array(repeating: false, count: otherCharacters.count)
    for change in difference {
        switch change {
        case .insert(let offset, _, _):
            insertions[offset] = true
        case .remove(let offset, _, _):
            removals[offset] = true
        }
    }

    var utf16Offsets = [Int]()
    utf16Offsets.reserveCapacity(characters.count + 1)
    utf16Offsets.append(0)
    for character in characters {
        utf16Offsets.append(utf16Offsets.last! + String(character).utf16.count)
    }

    var targetOffset = 0
    var otherOffset = 0
    var changedOffsets: [(offset: Int, length: Int)] = []
    while targetOffset < characters.count || otherOffset < otherCharacters.count {
        if otherOffset < removals.count, removals[otherOffset] {
            changedOffsets.append((targetOffset, 0))
            otherOffset += 1
        } else if targetOffset < insertions.count, insertions[targetOffset] {
            changedOffsets.append((targetOffset, 1))
            targetOffset += 1
        } else {
            targetOffset += 1
            otherOffset += 1
        }
    }

    var ranges = [NSRange]()
    var rangeStart: Int?
    var end = 0
    func appendRange() {
        guard let rangeStart else { return }
        ranges.append(
            NSRange(
                location: utf16Offsets[rangeStart],
                length: utf16Offsets[end] - utf16Offsets[rangeStart]
            ))
    }
    for change in changedOffsets {
        let changeEnd = change.offset + change.length
        if rangeStart != nil {
            if change.offset <= end {
                end = max(end, changeEnd)
            } else {
                appendRange()
                rangeStart = change.offset
                end = changeEnd
            }
        } else {
            rangeStart = change.offset
            end = changeEnd
        }
    }
    appendRange()
    return ranges
}

private func exceedsIntralineBudget(_ text: String) -> Bool {
    text.utf8.prefix(intralineUTF8Budget + 1).count > intralineUTF8Budget
        || text.utf16.prefix(intralineUTF16Budget + 1).count > intralineUTF16Budget
        || text.prefix(intralineCharacterBudget + 1).count > intralineCharacterBudget
}

func intralineDifferenceRange(in text: String, comparedWith other: String) -> NSRange? {
    let ranges = intralineDifferenceRanges(in: text, comparedWith: other)
    guard let first = ranges.first else { return nil }
    guard first.length == 0,
        let next = ranges.dropFirst().first,
        next.length > 0
    else { return first }
    return NSRange(
        location: first.location,
        length: NSMaxRange(next) - first.location
    )
}

func lineDifferenceRange(
    in ranges: [NSRange],
    from selection: NSRange,
    direction: LineDifferenceSelectionDirection,
    advancesFromSelection: Bool = true
) -> NSRange? {
    guard !ranges.isEmpty else { return nil }
    let currentIndex = advancesFromSelection ? ranges.firstIndex(of: selection) : nil
    switch direction {
    case .next:
        if let currentIndex {
            return ranges[(currentIndex + 1) % ranges.count]
        }
        return ranges.first {
            NSLocationInRange(selection.location, $0) || $0.location >= selection.location
        } ?? ranges[0]
    case .previous:
        if let currentIndex {
            return ranges[(currentIndex + ranges.count - 1) % ranges.count]
        }
        return ranges.last {
            NSLocationInRange(selection.location, $0) || $0.location <= selection.location
        } ?? ranges[ranges.count - 1]
    }
}

private struct ComparisonOptionsStore {
    private static let key = "comparisonOptions.v1"
    let userDefaults: UserDefaults

    func load() -> LineDiffOptions {
        guard let data = userDefaults.data(forKey: Self.key),
            let options = try? JSONDecoder().decode(LineDiffOptions.self, from: data)
        else {
            return LineDiffOptions()
        }
        return options
    }

    func save(_ options: LineDiffOptions) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        userDefaults.set(data, forKey: Self.key)
    }
}

@Observable
@MainActor
final class ComparisonModel {
    static let minimumLocationPaneWidth: CGFloat = 72
    static let maximumLocationPaneWidth: CGFloat = 240
    private static let locationPaneVisibleKey = "locationPane.visible"
    private static let locationPaneWidthKey = "locationPane.width"
    private static let locationPaneMoveCursorKey = "locationPane.moveCursorOnClick"

    private struct LineEditKey: Hashable {
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
        didSet {
            rowsRevision &+= 1
            visibleViewport = .empty
        }
    }
    private(set) var maximumLineColumns = 0
    private(set) var differenceLocations = DifferenceLocations()
    private(set) var differenceRowIndices: [UInt32] = []
    private(set) var locationMap = LocationMap()
    private(set) var movedRows = MovedRowMap()
    private(set) var summary = DiffSummary(rows: [])
    private(set) var selectedDifferenceID: DiffRow.ID?
    private(set) var currentRowID: DiffRow.ID?
    var currentRowIndex: Int? {
        currentRowID.flatMap { id in rows.firstIndex { $0.id == id } }
    }
    private(set) var selectedDifferenceRevealRevision = 0
    private(set) var lineDifferenceSelectionRevision = 0
    private(set) var lineDifferenceSelectionDirection = LineDifferenceSelectionDirection.next
    private(set) var paneFocusRevision = 0
    private(set) var focusGeneration = 0
    private(set) var focusRequest: DiffFocusRequest?
    private(set) var activeSide = ComparisonSide.left
    private(set) var isMergeMode: Bool
    private(set) var isLocationPaneVisible: Bool
    private(set) var locationPaneWidth: CGFloat
    private(set) var locationPaneMovesCursorOnClick: Bool
    private(set) var isWorking = false
    private(set) var comparisonFailed = false
    private(set) var isComparisonCurrent = true
    private(set) var pendingExternalOpenURLs: [URL]?
    private(set) var pendingEncodingSelection: PendingEncodingSelection?
    private(set) var hasPendingSaveWarning = false
    private(set) var options: LineDiffOptions
    private(set) var optionsRevision = 0
    private(set) var commandRoutingRevision = 0
    var errorMessage: String?

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
    private var lineEditBaselines: [LineEditKey: String] = [:]
    private var visibleViewport = LocationViewport.empty
    private var isRestoringSession = false
    private var sessionRestoreTask: Task<Void, Never>?
    private var sessionRestoreOperationID: UInt64?
    private var nextSessionRestoreOperationID: UInt64 = 0
    private var sessionRestoreCompletion: (@MainActor (SessionRestoreResult) -> Void)?
    private var sessionPersistenceLocked = false
    var explicitOpenWillBegin: (@MainActor () -> Void)?
    private let optionsStore: ComparisonOptionsStore?
    private let userDefaults: UserDefaults?
    private let bookmarkStore: SecurityScopedBookmarkStore?

    init(
        userDefaults: UserDefaults? = nil,
        bookmarkStore: SecurityScopedBookmarkStore? = nil,
        forceLocationPaneVisible: Bool = PerformanceProbe.shared.shouldForceLocationPane
    ) {
        let optionsStore = userDefaults.map(ComparisonOptionsStore.init(userDefaults:))
        self.optionsStore = optionsStore
        self.userDefaults = userDefaults
        self.bookmarkStore = bookmarkStore
        options = optionsStore?.load() ?? LineDiffOptions()
        isMergeMode = userDefaults?.bool(forKey: "mergeMode") ?? false
        isLocationPaneVisible =
            forceLocationPaneVisible
            || userDefaults?.object(forKey: Self.locationPaneVisibleKey)
                .map { ($0 as? NSNumber)?.boolValue ?? true } ?? true
        locationPaneWidth = Self.clampedLocationPaneWidth(
            userDefaults?.object(forKey: Self.locationPaneWidthKey)
                .flatMap { ($0 as? NSNumber)?.doubleValue }
                .map { CGFloat($0) } ?? 92
        )
        locationPaneMovesCursorOnClick =
            userDefaults?.object(forKey: Self.locationPaneMoveCursorKey)
            .map { ($0 as? NSNumber)?.boolValue ?? true } ?? true
    }

    var isReady: Bool {
        left.isLoaded && right.isLoaded
    }

    var hasScratchpad: Bool { left.isUntitled || right.isUntitled }
    var hasLoadedSide: Bool { left.isLoaded || right.isLoaded }

    var canUndo: Bool { history.canUndo && !isWorking }
    var canRedo: Bool { history.canRedo && !isWorking }
    var hasDifferences: Bool { summary.differences > 0 && isComparisonCurrent }
    var hasUnsavedChanges: Bool { left.isDirty || right.isDirty }
    var hasSelectedDifference: Bool { selectedDifferenceID != nil && !isWorking }
    var canMergeCurrentDifference: Bool {
        canMergeCurrentDifference(direction: .leftToRight)
            || canMergeCurrentDifference(direction: .rightToLeft)
    }
    var canNavigateDifferences: Bool { hasDifferences && !isWorking }
    var canSelectPreviousDifference: Bool {
        canNavigateDifferences && adjacentDifferenceID(offset: -1) != nil
    }
    var canSelectNextDifference: Bool {
        canNavigateDifferences && adjacentDifferenceID(offset: 1) != nil
    }
    var canReloadFromDisk: Bool { !isWorking && (left.url != nil || right.url != nil) }
    var canRefresh: Bool { isReady && !isWorking }
    var canSelectCurrentDifference: Bool {
        currentDifferenceID != nil && !isWorking
    }
    var canSelectLineDifference: Bool {
        guard !isWorking, isComparisonCurrent,
            let id = currentDifferenceID,
            let location = differenceLocations[id],
            rows.indices.contains(location.rowIndex),
            rows[location.rowIndex].kind == .modified,
            let leftText = rows[location.rowIndex].left?.text,
            let rightText = rows[location.rowIndex].right?.text
        else { return false }
        let text = activeSide == .left ? leftText : rightText
        let other = activeSide == .left ? rightText : leftText
        return intralineDifferenceRange(in: text, comparedWith: other) != nil
    }
    var hasReloadableUnsavedChanges: Bool {
        (left.document?.isDirty == true) || (right.document?.isDirty == true)
    }
    var canCreateEmptyComparison: Bool { !isWorking }

    func canMergeCurrentDifference(direction: MergeDirection) -> Bool {
        mergeCommandAvailability(
            direction == .leftToRight ? .leftToRight : .rightToLeft
        ).isEnabled
    }

    func isMergeCommandEnabled(_ command: MergeCommandPolicy.Command) -> Bool {
        mergeCommandAvailability(command).isEnabled
    }

    func mergeCommandState(
        hasSelection: Bool? = nil
    ) -> MergeCommandPolicy.State {
        MergeCommandPolicy.State(
            left: mergeSideState(left),
            right: mergeSideState(right),
            comparisonLifecycle: comparisonLifecycle,
            hasSelection: hasSelection ?? (currentDifferenceID != nil),
            hasSignificantDifferences: summary.differences > 0
        )
    }

    var selectedDifferencePosition: Int? {
        guard let selectedDifferenceID,
            let rowIndex = differenceLocations[selectedDifferenceID]?.rowIndex,
            let position = orderedDifferencePosition(forRowIndex: rowIndex)
        else { return nil }
        return position + 1
    }

    func isDirty(_ side: ComparisonSide) -> Bool {
        side == .left ? left.isDirty : right.isDirty
    }

    func canSetEditable(on side: ComparisonSide) -> Bool {
        !isWorking && !sessionPersistenceLocked && file(on: side).isLoaded
    }

    func setEditable(_ editable: Bool, on side: ComparisonSide) {
        guard canSetEditable(on: side), file(on: side).isEditable != editable else { return }
        if !editable {
            commitActiveEditor()
            invalidateFocusRequest()
        }
        switch side {
        case .left:
            left.isEditable = editable
        case .right:
            right.isEditable = editable
        }
    }

    func sessionState(
        windowFrame: ComparisonSessionState.WindowFrame
    ) async throws -> ComparisonSessionState? {
        guard !isWorking || sessionPersistenceLocked, !hasUnsavedChanges,
            let leftIdentity = sessionIdentity(left),
            let rightIdentity = sessionIdentity(right)
        else { return nil }
        let leftReadOnly = !left.isEditable
        let rightReadOnly = !right.isEditable
        let leftEncoding = left.document.map { ComparisonSessionState.FileEncoding($0.encoding) }
        let rightEncoding = right.document.map { ComparisonSessionState.FileEncoding($0.encoding) }
        let selectedRow = selectedDifferenceID.flatMap { differenceLocations[$0]?.rowIndex }
        let savedActiveSide: ComparisonSessionState.Side = activeSide == .left ? .left : .right
        let locationPaneVisible = isLocationPaneVisible
        let savedLocationPaneWidth = Double(locationPaneWidth)
        return try await Task.detached {
            try ComparisonSessionState(
                left: leftIdentity,
                right: rightIdentity,
                leftReadOnly: leftReadOnly,
                rightReadOnly: rightReadOnly,
                leftEncoding: leftEncoding,
                rightEncoding: rightEncoding,
                selectedRow: selectedRow,
                activeSide: savedActiveSide,
                windowFrame: windowFrame,
                splitOrientation: .vertical,
                splitFraction: 0.5,
                locationPaneVisible: locationPaneVisible,
                locationPaneWidth: savedLocationPaneWidth
            )
        }.value
    }

    func restoreSession(
        _ state: ComparisonSessionState,
        completion: (@MainActor (SessionRestoreResult) -> Void)? = nil
    ) {
        guard !isWorking, !left.isLoaded, !right.isLoaded else {
            completion?(.cancelled)
            return
        }
        invalidateFocusRequest()
        let leftGeneration = nextLoadGeneration(for: .left)
        let rightGeneration = nextLoadGeneration(for: .right)
        let comparisonOptions = options
        let comparisonOptionsRevision = optionsRevision
        isRestoringSession = true
        beginOperation()
        nextSessionRestoreOperationID &+= 1
        let operationID = nextSessionRestoreOperationID
        sessionRestoreOperationID = operationID
        sessionRestoreCompletion = completion
        let bookmarkStore = bookmarkStore
        sessionRestoreTask = Task {
            do {
                let worker = Task.detached {
                    try Task.checkCancellation()
                    let resolvedLeft = Self.resolvedIdentity(
                        state.left,
                        bookmarkStore: bookmarkStore
                    )
                    let resolvedRight = Self.resolvedIdentity(
                        state.right,
                        bookmarkStore: bookmarkStore
                    )
                    let resolvedState = try ComparisonSessionState(
                        left: resolvedLeft,
                        right: resolvedRight,
                        leftReadOnly: state.leftReadOnly,
                        rightReadOnly: state.rightReadOnly,
                        leftEncoding: state.leftEncoding,
                        rightEncoding: state.rightEncoding,
                        selectedRow: state.selectedRow,
                        activeSide: state.activeSide,
                        windowFrame: state.windowFrame,
                        splitOrientation: state.splitOrientation,
                        splitFraction: state.splitFraction,
                        locationPaneVisible: state.locationPaneVisible,
                        locationPaneWidth: state.locationPaneWidth
                    )
                    let left = try Self.restoredFile(
                        resolvedState.left,
                        side: .left,
                        readOnly: resolvedState.leftReadOnly,
                        encoding: resolvedState.leftEncoding
                    )
                    try Task.checkCancellation()
                    let right = try Self.restoredFile(
                        resolvedState.right,
                        side: .right,
                        readOnly: resolvedState.rightReadOnly,
                        encoding: resolvedState.rightEncoding
                    )
                    try Task.checkCancellation()
                    let effectiveOptions = Self.effectiveComparisonOptions(
                        comparisonOptions,
                        leftURL: left.url,
                        rightURL: right.url
                    )
                    let comparison = try computeComparison(
                        left: left.text,
                        right: right.text,
                        options: effectiveOptions
                    )
                    return (resolvedState, left, right, comparison)
                }
                let restored = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard leftGeneration == loadGeneration(for: .left),
                    rightGeneration == loadGeneration(for: .right),
                    comparisonOptionsRevision == optionsRevision
                else {
                    completeSessionRestore(.cancelled, operationID: operationID)
                    return
                }
                let resolvedState = restored.0
                left = restored.1
                right = restored.2
                rows = restored.3.rows
                maximumLineColumns = restored.3.maximumLineColumns
                differenceLocations = restored.3.differenceLocations
                differenceRowIndices = restored.3.differenceRowIndices
                locationMap = restored.3.locationMap
                movedRows = restored.3.movedRows
                summary = restored.3.summary
                comparisonFailed = false
                isComparisonCurrent = true
                activeSide = resolvedState.activeSide == .left ? .left : .right
                setLocationPaneVisible(resolvedState.locationPaneVisible)
                setLocationPaneWidth(CGFloat(resolvedState.locationPaneWidth))
                history.reset(to: snapshot)
                if let selectedRow = resolvedState.selectedRow,
                    rows.indices.contains(selectedRow)
                {
                    currentRowID = rows[selectedRow].id
                    selectedDifferenceID =
                        rows[selectedRow].kind == .unchanged
                        ? nil
                        : currentRowID
                } else {
                    selectedDifferenceID = nil
                    currentRowID = nil
                }
                completeSessionRestore(.restored, operationID: operationID)
            } catch {
                if leftGeneration == loadGeneration(for: .left),
                    rightGeneration == loadGeneration(for: .right)
                {
                    errorMessage = "Could not restore the previous comparison. \(error.localizedDescription)"
                }
                let result: SessionRestoreResult =
                    leftGeneration == loadGeneration(for: .left)
                        && rightGeneration == loadGeneration(for: .right)
                    ? .failed
                    : .cancelled
                completeSessionRestore(result, operationID: operationID)
            }
        }
    }

    func createEmptyComparison() {
        commitActiveEditor()
        guard canCreateEmptyComparison else { return }
        invalidateFocusRequest()
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
        differenceLocations = DifferenceLocations()
        differenceRowIndices = []
        locationMap = LocationMap()
        movedRows = MovedRowMap()
        summary = DiffSummary(rows: [])
        selectedDifferenceID = nil
        currentRowID = nil
        comparisonFailed = false
        isComparisonCurrent = true
        errorMessage = nil
        lineEditBaselines.removeAll()
        history.reset(to: snapshot)
    }

    func editText(_ text: String, on side: ComparisonSide) {
        guard !isWorking, !sessionPersistenceLocked, file(on: side).isEditable else { return }
        invalidateFocusRequest()
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

    func editLine(rowID: DiffRow.ID, on side: ComparisonSide, replacement: String) {
        guard !isWorking, !sessionPersistenceLocked, file(on: side).isEditable else { return }
        let editKey = LineEditKey(side: side, rowID: rowID)
        let beginsEditSession = lineEditBaselines[editKey] == nil
        let baselineText = lineEditBaselines[editKey] ?? file(on: side).text
        lineEditBaselines[editKey] = baselineText
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

    func finishLineEditing(rowID: DiffRow.ID, on side: ComparisonSide) {
        let removed = lineEditBaselines.removeValue(
            forKey: LineEditKey(side: side, rowID: rowID)
        )
        if removed != nil {
            history.discardRedundantUndo()
            scheduleLiveDiff()
        }
    }

    func commitActiveEditor() {
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
    }

    func invalidateCommandRouting() {
        commandRoutingRevision &+= 1
    }

    func enqueueOpen(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        explicitOpenWillBegin?()
        cancelSessionRestore()
        queuedOpenRequests.append(.automatic(Array(urls.prefix(2))))
        drainOpenRequestsIfIdle()
    }

    func enqueueOpen(_ url: URL, into side: ComparisonSide) {
        explicitOpenWillBegin?()
        cancelSessionRestore()
        queuedOpenRequests.append(.side(url, side))
        drainOpenRequestsIfIdle()
    }

    func enqueueReplacingOpen(_ url: URL, into side: ComparisonSide) {
        explicitOpenWillBegin?()
        cancelSessionRestore()
        queuedOpenRequests.append(.replacingSide(url, side))
        drainOpenRequestsIfIdle()
    }

    func selectPendingEncoding(_ encoding: TextFileEncoding) {
        guard pendingEncodingSelection?.candidates.contains(encoding) == true,
            let retry = pendingEncodingRetry
        else { return }
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
        case .automatic(let urls):
            processAutomaticOpen(urls)
        case .side(let url, let side):
            guard !isDirty(side) else {
                errorMessage = "Save or discard edits on the \(side == .left ? "left" : "right") side before opening another file."
                drainOpenRequestsIfIdle()
                return
            }
            load(url, into: side)
        case .replacingSide(let url, let side):
            load(url, into: side)
        }
    }

    private func cancelSessionRestore() {
        guard isRestoringSession else { return }
        sessionRestoreTask?.cancel()
        leftLoadGeneration += 1
        rightLoadGeneration += 1
    }

    private func completeSessionRestore(
        _ result: SessionRestoreResult,
        operationID: UInt64?
    ) {
        guard let operationID, sessionRestoreOperationID == operationID else { return }
        let completion = sessionRestoreCompletion
        sessionRestoreCompletion = nil
        isRestoringSession = false
        sessionRestoreTask = nil
        operationCompletions.append { completion?(result) }
        finishSessionRestoreOperation(operationID)
    }

    private func finishSessionRestoreOperation(_ operationID: UInt64?) {
        guard let operationID, sessionRestoreOperationID == operationID else { return }
        sessionRestoreOperationID = nil
        endOperation()
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
        invalidateFocusRequest()
        let signpostID = PerformanceTrace.begin("LoadPair")
        PerformanceProbe.shared.begin("load")
        let leftGeneration = nextLoadGeneration(for: .left)
        let rightGeneration = nextLoadGeneration(for: .right)
        beginOperation()
        Task {
            defer { PerformanceTrace.end("LoadPair", id: signpostID) }
            defer { PerformanceProbe.shared.end("load") }
            do {
                let documents = try await Task.detached {
                    let leftDocument: TextFileDocument
                    do {
                        leftDocument =
                            try leftEncoding.map {
                                try TextFileDocumentIO.load(from: leftURL, assuming: $0)
                            } ?? TextFileDocumentIO.load(from: leftURL)
                    } catch let TextFileCodecError.ambiguousTextEncoding(candidates) {
                        throw AmbiguousOpenError(
                            request: PendingEncodingSelection(
                                url: leftURL,
                                side: .left,
                                candidates: candidates
                            ))
                    }
                    let rightDocument: TextFileDocument
                    do {
                        rightDocument =
                            try rightEncoding.map {
                                try TextFileDocumentIO.load(from: rightURL, assuming: $0)
                            } ?? TextFileDocumentIO.load(from: rightURL)
                    } catch let TextFileCodecError.ambiguousTextEncoding(candidates) {
                        throw AmbiguousOpenError(
                            request: PendingEncodingSelection(
                                url: rightURL,
                                side: .right,
                                candidates: candidates
                            ))
                    }
                    return (leftDocument, rightDocument)
                }.value
                guard leftGeneration == loadGeneration(for: .left),
                    rightGeneration == loadGeneration(for: .right)
                else {
                    endOperation()
                    return
                }
                invalidateFocusRequest()
                left = ComparedFile(document: documents.0)
                right = ComparedFile(document: documents.1)
                persistAccess(to: documents.0.url)
                persistAccess(to: documents.1.url)
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
                endOperation()
            } catch {
                if leftGeneration == loadGeneration(for: .left),
                    rightGeneration == loadGeneration(for: .right)
                {
                    invalidateFocusRequest()
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
        invalidateFocusRequest()
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

                invalidateFocusRequest()
                switch side {
                case .left:
                    left = ComparedFile(document: document)
                case .right:
                    right = ComparedFile(document: document)
                }
                persistAccess(to: document.url)
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
                endOperation()
            } catch {
                if generation == loadGeneration(for: side) {
                    invalidateFocusRequest()
                    if case TextFileCodecError.ambiguousTextEncoding(let candidates) = error {
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
        invalidateFocusRequest()
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
        let command: MergeCommandPolicy.Command =
            switch (direction, advancesToNextDifference) {
            case (.leftToRight, false): .leftToRight
            case (.rightToLeft, false): .rightToLeft
            case (.leftToRight, true): .leftToRightAndAdvance
            case (.rightToLeft, true): .rightToLeftAndAdvance
            }
        guard
            mergeCommandAvailability(
                command,
                hasSelection: differenceLocations[rowID] != nil
            ).isEnabled
        else { return }
        let currentDifferenceRowIndices = differenceRowIndices
        let preferredDifferenceIndex: Int?
        if advancesToNextDifference,
            let rowIndex = differenceLocations[rowID]?.rowIndex,
            let index = orderedDifferencePosition(forRowIndex: rowIndex)
        {
            preferredDifferenceIndex = index == currentDifferenceRowIndices.count - 1 ? nil : index
        } else {
            preferredDifferenceIndex = nil
        }
        let source = snapshot
        let comparisonOptions = effectiveComparisonOptions
        beginOperation()
        Task {
            do {
                let result = try await Task.detached {
                    try LineMerge.apply(
                        rowID: rowID,
                        direction: direction,
                        left: source.left,
                        right: source.right,
                        options: comparisonOptions
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
        let command: MergeCommandPolicy.Command =
            direction == .leftToRight
            ? .copyAllToRight
            : .copyAllToLeft
        guard mergeCommandAvailability(command).isEnabled else { return }
        let source = snapshot
        let comparisonOptions = effectiveComparisonOptions
        beginOperation()
        Task {
            do {
                let result = try await Task.detached {
                    try LineMerge.applyAll(
                        direction: direction,
                        left: source.left,
                        right: source.right,
                        options: comparisonOptions
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
        currentRowID = id
    }

    func activateRow(_ id: DiffRow.ID?) {
        invalidateFocusRequest()
        guard !isWorking, isComparisonCurrent else { return }
        currentRowID = id
        guard let id, differenceLocations[id] != nil else {
            selectedDifferenceID = nil
            return
        }
        selectedDifferenceID = id
    }

    func moveCursor(to id: DiffRow.ID?) {
        guard !isWorking, isComparisonCurrent else { return }
        guard let id else {
            currentRowID = nil
            return
        }
        guard rows.contains(where: { $0.id == id }) else { return }
        currentRowID = id
    }

    func updateViewport(_ viewport: LocationViewport) {
        visibleViewport = viewport
    }

    func activateSide(_ side: ComparisonSide) {
        invalidateFocusRequest()
        activeSide = side
    }

    func changePane() {
        guard isReady, !isWorking else { return }
        activeSide = activeSide == .left ? .right : .left
        paneFocusRevision &+= 1
        requestFocus(.focusEditor(rowID: currentRowID, side: activeSide, centersRow: false))
    }

    func setMergeMode(_ enabled: Bool) {
        guard isMergeMode != enabled else { return }
        isMergeMode = enabled
        userDefaults?.set(enabled, forKey: "mergeMode")
    }

    func setLocationPaneVisible(_ visible: Bool) {
        guard !sessionPersistenceLocked else { return }
        guard isLocationPaneVisible != visible else { return }
        isLocationPaneVisible = visible
        userDefaults?.set(visible, forKey: Self.locationPaneVisibleKey)
    }

    func setLocationPaneWidth(_ width: CGFloat) {
        guard !sessionPersistenceLocked else { return }
        let width = Self.clampedLocationPaneWidth(width)
        guard locationPaneWidth != width else { return }
        locationPaneWidth = width
        userDefaults?.set(Double(width), forKey: Self.locationPaneWidthKey)
    }

    func setLocationPaneMovesCursorOnClick(_ enabled: Bool) {
        guard !sessionPersistenceLocked else { return }
        guard locationPaneMovesCursorOnClick != enabled else { return }
        locationPaneMovesCursorOnClick = enabled
        userDefaults?.set(enabled, forKey: Self.locationPaneMoveCursorKey)
    }

    func setDetectMovedBlocks(_ enabled: Bool) {
        var options = options
        options.detectMovedBlocks = enabled
        setOptions(options)
    }

    func handleMergeModeKey(_ keyCode: UInt16, rowID: DiffRow.ID) -> Bool {
        guard isMergeMode, !isWorking else { return false }
        switch keyCode {
        case 123:
            guard
                mergeCommandAvailability(
                    .rightToLeft,
                    hasSelection: differenceLocations[rowID] != nil
                ).isEnabled
            else { return false }
            merge(rowID: rowID, direction: .rightToLeft)
        case 124:
            guard
                mergeCommandAvailability(
                    .leftToRight,
                    hasSelection: differenceLocations[rowID] != nil
                ).isEnabled
            else { return false }
            merge(rowID: rowID, direction: .leftToRight)
        case 125:
            selectNextDifference()
            paneFocusRevision &+= 1
            requestFocus(.focusEditor(rowID: currentRowID, side: activeSide, centersRow: false))
        case 126:
            selectPreviousDifference()
            paneFocusRevision &+= 1
            requestFocus(.focusEditor(rowID: currentRowID, side: activeSide, centersRow: false))
        default:
            return false
        }
        return true
    }

    func selectPreviousDifference() {
        selectAdjacentDifference(offset: -1)
    }

    func selectNextDifference() {
        selectAdjacentDifference(offset: 1)
    }

    func selectFirstDifference() {
        guard !isWorking else { return }
        selectedDifferenceID = differenceID(at: differenceRowIndices.startIndex)
        currentRowID = selectedDifferenceID
    }

    func selectCurrentDifference() {
        guard let currentDifferenceID else { return }
        selectedDifferenceID = currentDifferenceID
        currentRowID = currentDifferenceID
        selectedDifferenceRevealRevision &+= 1
    }

    func selectLineDifference() {
        requestLineDifferenceSelection(.next)
    }

    func selectPreviousLineDifference() {
        requestLineDifferenceSelection(.previous)
    }

    func canGoToMovedLine(_ id: DiffRow.ID, _ side: ComparisonSide) -> Bool {
        guard !isWorking, isComparisonCurrent,
            let location = differenceLocations[id],
            rows.indices.contains(location.rowIndex)
        else { return false }
        let row = rows[location.rowIndex]
        let line = side == .left ? row.left?.number : row.right?.number
        return line.flatMap { movedRows.targetRow(forLine: $0, on: side) } != nil
    }

    private func requestLineDifferenceSelection(_ direction: LineDifferenceSelectionDirection) {
        guard canSelectLineDifference, let rowID = currentDifferenceID else { return }
        let side = activeSide
        selectCurrentDifference()
        lineDifferenceSelectionDirection = direction
        lineDifferenceSelectionRevision &+= 1
        requestFocus(.selectLineDifference(rowID: rowID, side: side, direction: direction))
    }

    func goToMovedLine(_ id: DiffRow.ID, _ side: ComparisonSide) {
        guard canGoToMovedLine(id, side),
            let location = differenceLocations[id]
        else { return }
        let row = rows[location.rowIndex]
        let line = side == .left ? row.left?.number : row.right?.number
        guard let line,
            let targetRow = movedRows.targetRow(forLine: line, on: side),
            rows.indices.contains(targetRow)
        else { return }
        let targetID = rows[targetRow].id
        currentRowID = targetID
        selectedDifferenceID = rows[targetRow].kind == .unchanged ? nil : targetID
        activeSide = side == .left ? .right : .left
        selectedDifferenceRevealRevision &+= 1
        paneFocusRevision &+= 1
        requestFocus(.focusEditor(rowID: targetID, side: activeSide, centersRow: false))
    }

    func requestNavigationFocus(rowID: DiffRow.ID?, side: ComparisonSide) {
        guard !isWorking, isComparisonCurrent,
            rowID.map({ requestedID in rows.contains { $0.id == requestedID } }) ?? true
        else {
            return
        }
        requestFocus(.focusEditor(rowID: rowID, side: side, centersRow: true))
    }

    func continueEditing(on side: ComparisonSide, lineNumber: Int) {
        guard lineNumber > 0 else { return }
        requestFocus(
            .continueEditing(
                side: side,
                lineNumber: lineNumber,
                afterRowsRevision: rowsRevision
            ))
    }

    private func requestFocus(_ action: DiffFocusRequest.Action) {
        focusGeneration &+= 1
        focusRequest = DiffFocusRequest(generation: focusGeneration, action: action)
    }

    private func invalidateFocusRequest() {
        focusGeneration &+= 1
        focusRequest = nil
    }

    func selectLastDifference() {
        guard !isWorking else { return }
        selectedDifferenceID = differenceRowIndices.indices.last.flatMap(differenceID(at:))
        currentRowID = selectedDifferenceID
    }

    func refresh() {
        commitActiveEditor()
        guard canRefresh else { return }
        scheduleDiff(selectingDifferenceAt: selectedDifferencePosition.map { $0 - 1 })
    }

    func setOptions(_ options: LineDiffOptions) {
        guard !sessionPersistenceLocked, !isRestoringSession else { return }
        guard self.options != options else { return }
        self.options = options
        optionsRevision &+= 1
        optionsStore?.save(options)
        if isReady {
            scheduleDiff(selectingDifferenceAt: selectedDifferencePosition.map { $0 - 1 })
        }
    }

    func resetOptions() {
        setOptions(LineDiffOptions())
    }

    func mergeSelectedDifference(direction: MergeDirection, advance: Bool) {
        guard let selectedDifferenceID = currentDifferenceID else { return }
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
        let command: MergeCommandPolicy.Command = side == .left ? .saveLeft : .saveRight
        guard mergeCommandAvailability(command).isEnabled else {
            if file(on: side).isDirty, !file(on: side).isEditable {
                reportReadOnlySaveError(for: side)
            }
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
            saveDestinationsCollide(destination, oppositeURL)
        {
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

    func saveAs(
        _ side: ComparisonSide,
        destination destinationURL: URL? = nil,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard !isWorking, file(on: side).isLoaded else {
            completion?(false)
            return
        }
        guard let destination = destinationURL ?? saveAsDestination(for: side) else {
            completion?(false)
            return
        }
        if let oppositeURL = file(on: side == .left ? .right : .left).url,
            saveDestinationsCollide(destination, oppositeURL)
        {
            errorMessage = "Choose a save location different from the other comparison file."
            completion?(false)
            return
        }
        beginOperation()
        Task {
            let saved = await performSaveAs(side, destination: destination)
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
        if let readOnlySide = [ComparisonSide.left, .right].first(where: {
            file(on: $0).isDirty && !file(on: $0).isEditable
        }) {
            reportReadOnlySaveError(for: readOnlySide)
            completion(false)
            return
        }
        let leftDestination =
            left.isDirty
            ? scratchpadDestinations[.left] ?? saveDestinationIfNeeded(for: .left)
            : nil
        if left.isDirty, left.isUntitled, leftDestination == nil {
            completion(false)
            return
        }
        let rightDestination =
            right.isDirty
            ? scratchpadDestinations[.right] ?? saveDestinationIfNeeded(for: .right)
            : nil
        if right.isDirty, right.isUntitled, rightDestination == nil {
            completion(false)
            return
        }
        let leftTarget = left.isDirty ? (leftDestination ?? left.url) : nil
        let rightTarget = right.isDirty ? (rightDestination ?? right.url) : nil
        if let leftTarget, let rightTarget,
            saveDestinationsCollide(leftTarget, rightTarget)
        {
            errorMessage = "Choose different save locations for the left and right files."
            completion(false)
            return
        }
        if let leftDestination, let rightURL = right.url,
            saveDestinationsCollide(leftDestination, rightURL)
        {
            errorMessage = "Choose a left save location different from the right comparison file."
            completion(false)
            return
        }
        if let rightDestination, let leftURL = left.url,
            saveDestinationsCollide(rightDestination, leftURL)
        {
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

    func saveReloadableChanges(completion: @escaping @MainActor (Bool) -> Void) {
        let sides = [ComparisonSide.left, .right].filter {
            file(on: $0).document?.isDirty == true
        }
        if let readOnlySide = sides.first(where: { !file(on: $0).isEditable }) {
            reportReadOnlySaveError(for: readOnlySide)
            completion(false)
            return
        }
        saveReloadableChanges(sides[...], completion: completion)
    }

    private func scheduleDiff(
        selectingDifferenceAt index: Int? = nil,
        selectingRowAt restoredRowIndex: Int? = nil
    ) {
        liveDiffTask?.cancel()
        liveDiffTask = nil
        diffGeneration += 1
        let generation = diffGeneration
        guard isReady else {
            rows = []
            maximumLineColumns = 0
            differenceLocations = DifferenceLocations()
            differenceRowIndices = []
            locationMap = LocationMap()
            movedRows = MovedRowMap()
            summary = DiffSummary(rows: [])
            comparisonFailed = false
            return
        }

        isComparisonCurrent = false
        let source = snapshot
        let comparisonOptions = effectiveComparisonOptions
        beginOperation()
        Task {
            do {
                let comparison = try await comparisonWorker.compare(
                    left: source.left,
                    right: source.right,
                    options: comparisonOptions
                )
                if generation == diffGeneration, source == snapshot {
                    rows = comparison.rows
                    maximumLineColumns = comparison.maximumLineColumns
                    differenceLocations = comparison.differenceLocations
                    differenceRowIndices = comparison.differenceRowIndices
                    locationMap = comparison.locationMap
                    movedRows = comparison.movedRows
                    summary = comparison.summary
                    comparisonFailed = false
                    isComparisonCurrent = true
                    if let restoredRowIndex, rows.indices.contains(restoredRowIndex) {
                        currentRowID = rows[restoredRowIndex].id
                        selectedDifferenceID =
                            rows[restoredRowIndex].kind == .unchanged
                            ? nil
                            : currentRowID
                    } else if let index, !differenceRowIndices.isEmpty {
                        selectedDifferenceID = differenceID(at: min(index, differenceRowIndices.count - 1))
                        currentRowID = selectedDifferenceID
                    } else if selectedDifferenceID.map({ differenceLocations[$0] == nil }) == true {
                        selectedDifferenceID = nil
                    }
                }
                endOperation()
            } catch {
                if generation == diffGeneration {
                    rows = []
                    maximumLineColumns = 0
                    differenceLocations = DifferenceLocations()
                    differenceRowIndices = []
                    locationMap = LocationMap()
                    movedRows = MovedRowMap()
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

    private var effectiveComparisonOptions: LineDiffOptions {
        Self.effectiveComparisonOptions(options, leftURL: left.url, rightURL: right.url)
    }

    nonisolated private static func effectiveComparisonOptions(
        _ options: LineDiffOptions,
        leftURL: URL?,
        rightURL: URL?
    ) -> LineDiffOptions {
        var effective = options
        guard effective.ignoreComments else { return effective }
        let fileExtension = [leftURL, rightURL]
            .compactMap { $0?.pathExtension }
            .first { !$0.isEmpty }
        effective.commentSyntax = fileExtension.flatMap(CommentSyntax.init(fileExtension:))
        return effective
    }

    private func scheduleLiveDiff() {
        liveDiffTask?.cancel()
        diffGeneration += 1
        let generation = diffGeneration
        let source = snapshot
        let comparisonOptions = effectiveComparisonOptions
        liveDiffTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(120))
                let comparison = try await comparisonWorker.compare(
                    left: source.left,
                    right: source.right,
                    options: comparisonOptions
                )
                guard !Task.isCancelled, generation == diffGeneration, source == snapshot else { return }
                rows = comparison.rows
                maximumLineColumns = comparison.maximumLineColumns
                differenceLocations = comparison.differenceLocations
                differenceRowIndices = comparison.differenceRowIndices
                locationMap = comparison.locationMap
                movedRows = comparison.movedRows
                summary = comparison.summary
                comparisonFailed = false
                isComparisonCurrent = true
            } catch is CancellationError {
                return
            } catch {
                guard generation == diffGeneration else { return }
                rows = []
                maximumLineColumns = 0
                differenceLocations = DifferenceLocations()
                differenceRowIndices = []
                locationMap = LocationMap()
                movedRows = MovedRowMap()
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
        invalidateFocusRequest()
        left.text = snapshot.left
        right.text = snapshot.right
    }

    private func selectAdjacentDifference(offset: Int) {
        guard !isWorking else { return }
        guard !differenceRowIndices.isEmpty else {
            selectedDifferenceID = nil
            return
        }
        guard let nextID = adjacentDifferenceID(offset: offset) else { return }
        selectedDifferenceID = nextID
        currentRowID = nextID
    }

    private func adjacentDifferenceID(offset: Int) -> DiffRow.ID? {
        guard !differenceRowIndices.isEmpty else { return nil }
        guard let originID = differenceNavigationOriginID else {
            let position = offset > 0 ? differenceRowIndices.startIndex : differenceRowIndices.index(before: differenceRowIndices.endIndex)
            return differenceID(at: position)
        }
        if let rowIndex = differenceLocations[originID]?.rowIndex,
            let position = orderedDifferencePosition(forRowIndex: rowIndex)
        {
            let nextPosition = position + offset
            return differenceID(at: nextPosition)
        }
        guard let rowIndex = rows.firstIndex(where: { $0.id == originID }) else { return nil }
        let insertion = differenceInsertionIndex(forRowIndex: rowIndex)
        if offset > 0 {
            return differenceID(at: insertion)
        }
        return insertion > 0 ? differenceID(at: insertion - 1) : nil
    }

    private var differenceNavigationOriginID: DiffRow.ID? {
        if let selectedDifferenceID,
            let rowIndex = differenceLocations[selectedDifferenceID]?.rowIndex,
            visibleViewport.contains(row: rowIndex)
        {
            return selectedDifferenceID
        }
        return currentRowID
    }

    private func differenceID(at position: Int) -> DiffRow.ID? {
        guard differenceRowIndices.indices.contains(position) else { return nil }
        let rowIndex = Int(differenceRowIndices[position])
        return rows.indices.contains(rowIndex) ? rows[rowIndex].id : nil
    }

    private func orderedDifferencePosition(forRowIndex rowIndex: Int) -> Int? {
        let position = differenceInsertionIndex(forRowIndex: rowIndex)
        return differenceRowIndices.indices.contains(position) && Int(differenceRowIndices[position]) == rowIndex
            ? position
            : nil
    }

    private func differenceInsertionIndex(forRowIndex rowIndex: Int) -> Int {
        var lower = differenceRowIndices.startIndex
        var upper = differenceRowIndices.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if Int(differenceRowIndices[middle]) < rowIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private var currentDifferenceID: DiffRow.ID? {
        if let selectedDifferenceID, differenceLocations[selectedDifferenceID] != nil {
            return selectedDifferenceID
        }
        guard let currentRowID, differenceLocations[currentRowID] != nil else { return nil }
        return currentRowID
    }

    private func mergeCommandAvailability(
        _ command: MergeCommandPolicy.Command,
        hasSelection: Bool? = nil
    ) -> MergeCommandPolicy.Availability {
        MergeCommandPolicy.evaluate(mergeCommandState(hasSelection: hasSelection))[command]
    }

    private var comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle {
        if isWorking { return .loading }
        if comparisonFailed { return .failed }
        return isComparisonCurrent ? .currentSuccess : .stale
    }

    private func mergeSideState(_ file: ComparedFile) -> MergeCommandPolicy.SideState {
        MergeCommandPolicy.SideState(
            isLoaded: file.isLoaded,
            isEditable: file.isEditable,
            isDirty: file.isDirty
        )
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
                persistAccess(to: document.url)
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
                invalidateFocusRequest()
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

    private func performSaveAs(_ side: ComparisonSide, destination: URL) async -> Bool {
        let original = file(on: side)
        do {
            let result = try await Task.detached {
                if let source = original.document {
                    return try TextFileDocumentIO.saveAs(source, to: destination)
                }
                guard let scratchpad = original.scratchpad else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return TextFileSaveResult(
                    document: try TextFileDocumentIO.create(at: destination, text: scratchpad.text)
                )
            }.value
            guard file(on: side) == original else { return false }
            let warning = result.warning
            let document = result.document
            let canonicalized = !document.text.unicodeScalars.elementsEqual(original.text.unicodeScalars)
            setFile(ComparedFile(document: document, isEditable: original.isEditable), on: side)
            persistAccess(to: document.url)
            if canonicalized {
                invalidateFocusRequest()
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
            }
            if let warning {
                errorMessage = warning.localizedDescription
                hasPendingSaveWarning = true
                return false
            }
            return true
        } catch {
            errorMessage = "Could not save \(original.displayName). \(error.localizedDescription)"
            return false
        }
    }

    private func file(on side: ComparisonSide) -> ComparedFile {
        side == .left ? left : right
    }

    private func reportReadOnlySaveError(for side: ComparisonSide) {
        errorMessage = "Make the \(side == .left ? "left" : "right") file editable before saving its changes."
    }

    private func saveReloadableChanges(
        _ sides: ArraySlice<ComparisonSide>,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let side = sides.first else {
            completion(true)
            return
        }
        save(side) { [weak self] saved in
            guard let self, saved else {
                completion(false)
                return
            }
            self.saveReloadableChanges(sides.dropFirst(), completion: completion)
        }
    }

    private func setFile(_ file: ComparedFile, on side: ComparisonSide) {
        switch side {
        case .left:
            left = file
        case .right:
            right = file
        }
    }

    nonisolated private static func resolvedIdentity(
        _ identity: ComparisonSessionState.SideIdentity,
        bookmarkStore: SecurityScopedBookmarkStore?
    ) -> ComparisonSessionState.SideIdentity {
        switch identity {
        case .file(let url): .file(bookmarkStore?.resolveAccess(to: url) ?? url)
        case .scratchpad: identity
        }
    }

    private func sessionIdentity(
        _ file: ComparedFile
    ) -> ComparisonSessionState.SideIdentity? {
        if let url = file.url {
            guard bookmarkStore?.hasPersistedAccess(to: url) ?? true else { return nil }
            return .file(url)
        }
        if let scratchpad = file.scratchpad { return .scratchpad(scratchpad.text) }
        return nil
    }

    nonisolated private static func restoredFile(
        _ identity: ComparisonSessionState.SideIdentity,
        side: ComparisonSide,
        readOnly: Bool,
        encoding: ComparisonSessionState.FileEncoding?
    ) throws -> ComparedFile {
        switch identity {
        case .file(let url):
            return ComparedFile(
                document: try encoding.map {
                    try TextFileDocumentIO.load(from: url, assuming: $0.textFileEncoding)
                } ?? TextFileDocumentIO.load(from: url),
                isEditable: !readOnly
            )
        case .scratchpad(let text):
            return ComparedFile(
                scratchpad: ComparedFile.Scratchpad(
                    name: side == .left ? "Untitled Left" : "Untitled Right",
                    text: text,
                    persistedText: text
                ),
                isEditable: !readOnly
            )
        }
    }

    private func persistAccess(to url: URL) {
        guard let bookmarkStore else { return }
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            try bookmarkStore.persistAccess(to: url)
        } catch {
            errorMessage = "Saved \(url.lastPathComponent), but access could not be preserved for the next launch."
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

    private func saveAsDestination(for side: ComparisonSide) -> URL? {
        let file = file(on: side)
        let panel = NSSavePanel()
        panel.title = "Save \(file.displayName) As"
        panel.nameFieldStringValue = file.isUntitled ? "\(file.displayName).txt" : file.displayName
        panel.allowedContentTypes = [.plainText]
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func saveDestinationsCollide(_ first: URL, _ second: URL) -> Bool {
        saveDestinationIdentity(first) == saveDestinationIdentity(second)
    }

    private func saveDestinationIdentity(_ url: URL) -> String {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
        }
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
        let leftIsEditable = left.isEditable
        let rightIsEditable = right.isEditable
        guard leftDocument != nil || rightDocument != nil else { return }

        invalidateFocusRequest()
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
                    rightGeneration.map({ $0 == loadGeneration(for: .right) }) ?? true
                else {
                    endOperation()
                    return
                }
                invalidateFocusRequest()
                if let document = documents.0 {
                    left = ComparedFile(document: document, isEditable: leftIsEditable)
                }
                if let document = documents.1 {
                    right = ComparedFile(document: document, isEditable: rightIsEditable)
                }
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
                endOperation()
            } catch {
                if leftGeneration.map({ $0 == loadGeneration(for: .left) }) ?? true,
                    rightGeneration.map({ $0 == loadGeneration(for: .right) }) ?? true
                {
                    invalidateFocusRequest()
                }
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

    private func endOperation(
        beforeDeliveringCallbacks action: (@MainActor () -> Void)? = nil
    ) {
        activeOperationCount = max(0, activeOperationCount - 1)
        isWorking = activeOperationCount > 0
        guard !isWorking else { return }
        action?()
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
            !queuedOpenRequests.isEmpty
        else { return }
        processOpen(queuedOpenRequests.removeFirst())
    }

    func lockSessionPersistence() -> Bool {
        guard !sessionPersistenceLocked, !isWorking, !hasUnsavedChanges else { return false }
        commitActiveEditor()
        guard !hasUnsavedChanges else { return false }
        sessionPersistenceLocked = true
        beginOperation()
        return true
    }

    func lockSessionDiscard() -> Bool {
        guard !sessionPersistenceLocked, !isWorking else { return false }
        commitActiveEditor()
        sessionPersistenceLocked = true
        beginOperation()
        return true
    }

    func unlockSessionPersistence(
        beforeDeliveringCallbacks action: (@MainActor () -> Void)? = nil
    ) {
        guard sessionPersistenceLocked else { return }
        sessionPersistenceLocked = false
        endOperation(beforeDeliveringCallbacks: action)
    }

    private func deliverIdleWaitersIfIdle() {
        while !idleWaiters.isEmpty,
            !isWorking,
            queuedOpenRequests.isEmpty || openQueueSuspended
        {
            idleWaiters.removeFirst()()
        }
    }

    static func clampedLocationPaneWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return 92 }
        return min(maximumLocationPaneWidth, max(minimumLocationPaneWidth, width))
    }
}

extension ComparisonSessionState.FileEncoding {
    fileprivate init(_ encoding: TextFileEncoding) {
        self = ComparisonSessionState.FileEncoding(rawValue: encoding.rawValue)!
    }

    fileprivate var textFileEncoding: TextFileEncoding {
        TextFileEncoding(rawValue: rawValue)!
    }
}

private struct ComparisonView: View {
    let model: ComparisonModel
    let loadInitialComparison: @MainActor () async -> Void
    let requestNew: () -> Void
    let openComparison: () -> Void
    let undo: () -> Void
    let redo: () -> Void
    let canUndo: () -> Bool
    let canRedo: () -> Bool
    @State private var importingSide: ComparisonSide?
    @State private var presentsImporter = false
    @State private var replacementSide: ComparisonSide?
    @State private var pendingImportedURL: URL?
    @State private var mergeAllDirection: MergeDirection?

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
                leftIsEditable: model.left.isEditable,
                rightIsEditable: model.right.isEditable,
                leftCanSave: ComparisonSaveCommand.left.isEnabled(on: model),
                rightCanSave: ComparisonSaveCommand.right.isEnabled(on: model),
                leftCanToggleReadOnly: ComparisonReadOnlyCommand.left.isEnabled(on: model),
                rightCanToggleReadOnly: ComparisonReadOnlyCommand.right.isEnabled(on: model),
                summary: model.summary,
                isReady: model.isReady,
                comparisonFailed: model.comparisonFailed,
                openLeft: { openImporter(for: .left) },
                openRight: { openImporter(for: .right) },
                saveLeft: { ComparisonSaveCommand.left.perform(on: model) },
                saveRight: { ComparisonSaveCommand.right.perform(on: model) },
                setLeftReadOnly: { ComparisonReadOnlyCommand.left.setReadOnly($0, on: model) },
                setRightReadOnly: { ComparisonReadOnlyCommand.right.setReadOnly($0, on: model) }
            )
            Divider()

            ComparisonToolbar(
                model: model,
                undo: undo,
                redo: redo,
                canUndo: canUndo(),
                canRedo: canRedo(),
                requestNew: requestNew,
                openComparison: openComparison,
                openLeft: { openImporter(for: .left) },
                openRight: { openImporter(for: .right) },
                requestMergeAll: { mergeAllDirection = $0 }
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
                        locationMap: model.locationMap,
                        movedRows: model.movedRows,
                        isLocationPaneVisible: model.isLocationPaneVisible,
                        locationPaneWidth: model.locationPaneWidth,
                        locationPaneMovesCursorOnClick: model.locationPaneMovesCursorOnClick,
                        detectsMovedBlocks: model.options.detectMovedBlocks,
                        selectedDifferenceID: model.selectedDifferenceID,
                        currentRowIndex: model.currentRowIndex,
                        selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision,
                        focusRequest: model.focusRequest,
                        isFocusRequestCurrent: { model.focusGeneration == $0 },
                        leftEditable: model.left.isEditable,
                        rightEditable: model.right.isEditable,
                        selectDifference: model.activateRow,
                        activateSide: model.activateSide,
                        editLeft: { model.editLine(rowID: $0, on: .left, replacement: $1) },
                        editRight: { model.editLine(rowID: $0, on: .right, replacement: $1) },
                        finishEditingLeft: { model.finishLineEditing(rowID: $0, on: .left) },
                        finishEditingRight: { model.finishLineEditing(rowID: $0, on: .right) },
                        viewportChanged: model.updateViewport,
                        moveCursor: model.moveCursor,
                        requestNavigationFocus: model.requestNavigationFocus,
                        continueEditing: model.continueEditing,
                        setLocationPaneWidth: model.setLocationPaneWidth,
                        setLocationPaneMovesCursorOnClick: model.setLocationPaneMovesCursorOnClick,
                        setDetectMovedBlocks: model.setDetectMovedBlocks,
                        contextMenuActions: .live(
                            model: model,
                            canUndo: canUndo,
                            undo: undo,
                            canRedo: canRedo,
                            redo: redo
                        )
                    )
                }
            } else {
                EmptyComparisonView()
            }

            Divider()
            ComparisonStatusBar(model: model)
        }
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
            case .success(let urls):
                if let url = urls.first, let side {
                    if model.isDirty(side) {
                        pendingImportedURL = url
                        replacementSide = side
                    } else {
                        model.enqueueOpen(url, into: side)
                    }
                }
            case .failure(let error):
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
                .disabled(
                    replacementSide == .left
                        ? !ComparisonSaveCommand.left.isEnabled(on: model)
                        : !ComparisonSaveCommand.right.isEnabled(on: model)
                )
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
            await loadInitialComparison()
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
    let leftIsEditable: Bool
    let rightIsEditable: Bool
    let leftCanSave: Bool
    let rightCanSave: Bool
    let leftCanToggleReadOnly: Bool
    let rightCanToggleReadOnly: Bool
    let summary: DiffSummary
    let isReady: Bool
    let comparisonFailed: Bool
    let openLeft: () -> Void
    let openRight: () -> Void
    let saveLeft: () -> Void
    let saveRight: () -> Void
    let setLeftReadOnly: (Bool) -> Void
    let setRightReadOnly: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            FileControl(
                name: leftName,
                side: .left,
                isLoaded: leftIsLoaded,
                isUntitled: leftIsUntitled,
                isDirty: leftIsDirty,
                isEditable: leftIsEditable,
                canSave: leftCanSave,
                canToggleReadOnly: leftCanToggleReadOnly,
                open: openLeft,
                save: saveLeft,
                setReadOnly: setLeftReadOnly
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
                isEditable: rightIsEditable,
                canSave: rightCanSave,
                canToggleReadOnly: rightCanToggleReadOnly,
                open: openRight,
                save: saveRight,
                setReadOnly: setRightReadOnly
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
    let isEditable: Bool
    let canSave: Bool
    let canToggleReadOnly: Bool
    let open: () -> Void
    let save: () -> Void
    let setReadOnly: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if side == .left {
                fileButton
            }
            Button("Save", systemImage: "square.and.arrow.down", action: save)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!canSave)
                .help("Save \(sideName.lowercased()) file")
                .accessibilityLabel("Save \(sideName.lowercased()) file")
            ComparisonReadOnlyControl(
                side: side,
                isLoaded: isLoaded,
                isEditable: isEditable,
                isEnabled: canToggleReadOnly,
                setReadOnly: setReadOnly
            )
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
            isEditable: isEditable,
            action: open
        )
    }

    private var sideName: String {
        side == .left ? "LEFT" : "RIGHT"
    }
}

private struct ComparisonReadOnlyControl: View {
    let side: ComparisonSide
    let isLoaded: Bool
    let isEditable: Bool
    let isEnabled: Bool
    let setReadOnly: (Bool) -> Void

    var body: some View {
        Button(
            ComparisonReadOnlyPresentation.actionLabel(
                side: side,
                isLoaded: isLoaded,
                isEditable: isEditable
            ),
            systemImage: isEditable ? "lock.open" : "lock.fill"
        ) {
            setReadOnly(isEditable)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(
            ComparisonReadOnlyPresentation.actionLabel(
                side: side,
                isLoaded: isLoaded,
                isEditable: isEditable
            )
        )
        .accessibilityLabel(
            ComparisonReadOnlyPresentation.actionLabel(
                side: side,
                isLoaded: isLoaded,
                isEditable: isEditable
            )
        )
        .accessibilityValue(
            ComparisonReadOnlyPresentation.accessibilityValue(
                isLoaded: isLoaded,
                isEditable: isEditable
            ))
    }
}

private struct FileButton: View {
    let name: String
    let side: String
    let isLoaded: Bool
    let isUntitled: Bool
    let isDirty: Bool
    let isEditable: Bool
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
        let editability = isEditable ? "Editable" : "Read-only"
        if isUntitled {
            return isDirty ? "Edited, untitled, \(editability)" : "Untitled, \(editability)"
        }
        return isDirty ? "Edited, \(editability)" : "Saved, \(editability)"
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
    let undo: () -> Void
    let redo: () -> Void
    let canUndo: Bool
    let canRedo: Bool
    let requestNew: () -> Void
    let openComparison: () -> Void
    let openLeft: () -> Void
    let openRight: () -> Void
    let requestMergeAll: (MergeDirection) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Menu("New comparison", systemImage: "doc.badge.plus") {
                Button("Text", action: requestNew)
                Divider()
                Button("Table") {}.disabled(true)
                Button("Binary") {}.disabled(true)
                Button("Image") {}.disabled(true)
                Button("Webpage") {}.disabled(true)
                Button("Folder") {}.disabled(true)
                Divider()
                Menu("New (3 panes)") {
                    Button("Text") {}.disabled(true)
                    Button("Table") {}.disabled(true)
                    Button("Binary") {}.disabled(true)
                    Button("Image") {}.disabled(true)
                    Button("Webpage") {}.disabled(true)
                    Button("Folder") {}.disabled(true)
                }
            } primaryAction: {
                requestNew()
            }
            .disabled(!model.canCreateEmptyComparison)
            .help("Create a new text comparison (Command-N)")

            Menu("Open files", systemImage: "folder") {
                Button("Open Comparison...", systemImage: "folder", action: openComparison)
                Divider()
                Button("Open Left...", systemImage: "rectangle.split.2x1", action: openLeft)
                Button("Open Right...", systemImage: "rectangle.split.2x1", action: openRight)
            } primaryAction: {
                openComparison()
            }
            .disabled(model.isWorking)
            .help("Select files to compare (Command-O)")

            Menu("Save", systemImage: "square.and.arrow.down") {
                Button("Save Left") {
                    ComparisonSaveCommand.left.perform(on: model)
                }
                .disabled(!ComparisonSaveCommand.left.isEnabled(on: model))
                Button("Save Right") {
                    ComparisonSaveCommand.right.perform(on: model)
                }
                .disabled(!ComparisonSaveCommand.right.isEnabled(on: model))
                Divider()
                Button("Save Left As...", action: { model.saveAs(.left) })
                    .disabled(!model.left.isLoaded)
                Button("Save Right As...", action: { model.saveAs(.right) })
                    .disabled(!model.right.isLoaded)
            } primaryAction: {
                model.saveAllChanges { _ in }
            }
            .disabled(model.isWorking || (!model.left.isLoaded && !model.right.isLoaded))
            .help("Save changed files (Command-S)")

            toolbarDivider

            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .disabled(!canUndo)
                .help("Undo the last edit or merge")
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .disabled(!canRedo)
                .help("Redo the last edit or merge")

            toolbarDivider

            Button("Select line difference", systemImage: "character.cursor.ibeam") {
                model.selectLineDifference()
            }
            .disabled(!model.canSelectLineDifference)
            .help("Select the intra-line difference in the active pane (F4)")

            toolbarDivider

            Button("Next difference", systemImage: "arrow.down", action: model.selectNextDifference)
                .disabled(!model.canSelectNextDifference)
                .help("Go to next difference (F8)")
            Button("Previous difference", systemImage: "arrow.up", action: model.selectPreviousDifference)
                .disabled(!model.canSelectPreviousDifference)
                .help("Go to previous difference (F7)")

            toolbarDivider

            Button("Next conflict", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90") {}
                .disabled(true)
                .help("Next conflict is available in three-pane conflict comparisons")
            Button("Previous conflict", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90") {}
                .disabled(true)
                .help("Previous conflict is available in three-pane conflict comparisons")

            toolbarDivider

            Button("First difference", systemImage: "arrow.up.to.line", action: model.selectFirstDifference)
                .disabled(!model.canNavigateDifferences)
                .help("Go to first difference")
            Button("Current difference", systemImage: "scope", action: model.selectCurrentDifference)
                .disabled(!model.canSelectCurrentDifference)
                .help("Reveal the current difference")
            Button("Last difference", systemImage: "arrow.down.to.line", action: model.selectLastDifference)
                .disabled(!model.canNavigateDifferences)
                .help("Go to last difference")

            toolbarDivider

            Button(ComparisonCopyCommand.selectedToRight.toolbarLabel, systemImage: "arrow.right") {
                ComparisonCopyCommand.selectedToRight.perform(on: model)
            }
            .disabled(!ComparisonCopyCommand.selectedToRight.isEnabled(on: model))
            .help("Copy the selected or current difference to right")
            Button(ComparisonCopyCommand.selectedToLeft.toolbarLabel, systemImage: "arrow.left") {
                ComparisonCopyCommand.selectedToLeft.perform(on: model)
            }
            .disabled(!ComparisonCopyCommand.selectedToLeft.isEnabled(on: model))
            .help("Copy the selected or current difference to left")

            Button(
                ComparisonCopyCommand.selectedToRightAndAdvance.toolbarLabel,
                systemImage: "arrow.right.circle",
                action: { ComparisonCopyCommand.selectedToRightAndAdvance.perform(on: model) }
            )
            .disabled(!ComparisonCopyCommand.selectedToRightAndAdvance.isEnabled(on: model))
            .help("Copy selected difference to right and advance")
            Button(
                ComparisonCopyCommand.selectedToLeftAndAdvance.toolbarLabel,
                systemImage: "arrow.left.circle",
                action: { ComparisonCopyCommand.selectedToLeftAndAdvance.perform(on: model) }
            )
            .disabled(!ComparisonCopyCommand.selectedToLeftAndAdvance.isEnabled(on: model))
            .help("Copy selected difference to left and advance")

            toolbarDivider

            Button(ComparisonCopyCommand.allToRight.toolbarLabel, systemImage: "arrow.right.to.line") {
                requestMergeAll(ComparisonCopyCommand.allToRight.direction)
            }
            .disabled(!ComparisonCopyCommand.allToRight.isEnabled(on: model))
            .help("Copy all differences to right")
            Button(ComparisonCopyCommand.allToLeft.toolbarLabel, systemImage: "arrow.left.to.line") {
                requestMergeAll(ComparisonCopyCommand.allToLeft.direction)
            }
            .disabled(!ComparisonCopyCommand.allToLeft.isEnabled(on: model))
            .help("Copy all differences to left")

            toolbarDivider

            Button("Auto merge", systemImage: "wand.and.stars") {}
                .disabled(true)
                .help("Auto Merge is available in clean three-pane comparisons")

            toolbarDivider

            Button("First compared file", systemImage: "backward.end") {}
                .disabled(true)
                .help("Compared-file navigation is available from folder comparisons")
            Button("Previous compared file", systemImage: "backward") {}
                .disabled(true)
                .help("Compared-file navigation is available from folder comparisons")
            Button("Next compared file", systemImage: "forward") {}
                .disabled(true)
                .help("Compared-file navigation is available from folder comparisons")
            Button("Last compared file", systemImage: "forward.end") {}
                .disabled(true)
                .help("Compared-file navigation is available from folder comparisons")

            toolbarDivider

            SettingsLink {
                Label("Options", systemImage: "gearshape")
            }
            .help("Open comparison options (Command-,)")

            toolbarDivider

            Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh)
                .disabled(!model.canRefresh)
                .help("Recompare the current in-memory text without reloading files")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comparison commands")
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 18)
    }

}

private struct EmptyComparisonView: View {
    var body: some View {
        Color(nsColor: NSColor(calibratedWhite: 0.53, alpha: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("No comparison open")
    }
}

private struct ComparisonStatusBar: View {
    let model: ComparisonModel

    var body: some View {
        HStack(spacing: 8) {
            Text(statusText)
            Spacer()
            if model.isReady {
                if model.isMergeMode {
                    Text("Merge Mode")
                    Divider().frame(height: 12)
                }
                Text("Differences: \(model.summary.differences)")
                Divider().frame(height: 12)
                Text("Left: \(model.left.displayName)")
                Divider().frame(height: 12)
                Text("Right: \(model.right.displayName)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusText: String {
        if model.isWorking { return "Comparing..." }
        if model.comparisonFailed { return "Comparison failed" }
        if !model.isReady { return "Ready" }
        return model.summary.differences == 0 ? "Files are identical" : "Comparison complete"
    }
}

private struct DiffContextMenuActions {
    let activate: (DiffRow.ID, ComparisonSide) -> Void
    let canMerge: (MergeDirection) -> Bool
    let merge: (DiffRow.ID, MergeDirection) -> Void
    let canSelectLineDifference: () -> Bool
    let selectLineDifference: () -> Void
    let selectPreviousLineDifference: () -> Void
    let canGoToMovedLine: (DiffRow.ID, ComparisonSide) -> Bool
    let goToMovedLine: (DiffRow.ID, ComparisonSide) -> Void
    let canUndo: () -> Bool
    let undo: () -> Void
    let canRedo: () -> Bool
    let redo: () -> Void
    let fileURL: (ComparisonSide) -> URL?
    let handleMergeModeKey: (UInt16, DiffRow.ID) -> Bool

    @MainActor
    static func live(
        model: ComparisonModel,
        canUndo: @escaping () -> Bool,
        undo: @escaping () -> Void,
        canRedo: @escaping () -> Bool,
        redo: @escaping () -> Void
    ) -> Self {
        Self(
            activate: { rowID, side in
                model.activateRow(rowID)
                model.activateSide(side)
            },
            canMerge: model.canMergeCurrentDifference(direction:),
            merge: { rowID, direction in model.merge(rowID: rowID, direction: direction) },
            canSelectLineDifference: { model.canSelectLineDifference },
            selectLineDifference: model.selectLineDifference,
            selectPreviousLineDifference: model.selectPreviousLineDifference,
            canGoToMovedLine: model.canGoToMovedLine,
            goToMovedLine: model.goToMovedLine,
            canUndo: canUndo,
            undo: undo,
            canRedo: canRedo,
            redo: redo,
            fileURL: { side in side == .left ? model.left.url : model.right.url },
            handleMergeModeKey: model.handleMergeModeKey
        )
    }
}

private struct DiffCanvas: View {
    let rows: [DiffRow]
    let rowsRevision: Int
    let maximumLineColumns: Int
    let differenceLocations: DifferenceLocations
    let locationMap: LocationMap
    let movedRows: MovedRowMap
    let isLocationPaneVisible: Bool
    let locationPaneWidth: CGFloat
    let locationPaneMovesCursorOnClick: Bool
    let detectsMovedBlocks: Bool
    let selectedDifferenceID: DiffRow.ID?
    let currentRowIndex: Int?
    let selectedDifferenceRevealRevision: Int
    let focusRequest: DiffFocusRequest?
    let isFocusRequestCurrent: (Int) -> Bool
    let leftEditable: Bool
    let rightEditable: Bool
    let selectDifference: (DiffRow.ID?) -> Void
    let activateSide: (ComparisonSide) -> Void
    let editLeft: (DiffRow.ID, String) -> Void
    let editRight: (DiffRow.ID, String) -> Void
    let finishEditingLeft: (DiffRow.ID) -> Void
    let finishEditingRight: (DiffRow.ID) -> Void
    let viewportChanged: (LocationViewport) -> Void
    let moveCursor: (DiffRow.ID?) -> Void
    let requestNavigationFocus: (DiffRow.ID?, ComparisonSide) -> Void
    let continueEditing: (ComparisonSide, Int) -> Void
    let setLocationPaneWidth: (CGFloat) -> Void
    let setLocationPaneMovesCursorOnClick: (Bool) -> Void
    let setDetectMovedBlocks: (Bool) -> Void
    let contextMenuActions: DiffContextMenuActions
    @State private var viewport = LocationViewport.empty
    @State private var navigationRow: Int?
    @State private var navigationRevision = 0
    @GestureState private var locationPaneResizeTranslation: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            DiffTableView(
                rows: rows,
                rowsRevision: rowsRevision,
                maximumLineColumns: maximumLineColumns,
                differenceLocations: differenceLocations,
                movedRows: movedRows,
                selectedDifferenceID: selectedDifferenceID,
                selectedDifferenceRevealRevision: selectedDifferenceRevealRevision,
                focusRequest: focusRequest,
                isFocusRequestCurrent: isFocusRequestCurrent,
                leftEditable: leftEditable,
                rightEditable: rightEditable,
                navigationRow: navigationRow,
                navigationRevision: navigationRevision,
                viewportChanged: updateViewport,
                selectDifference: selectDifference,
                activateSide: activateSide,
                editLeft: editLeft,
                editRight: editRight,
                finishEditingLeft: finishEditingLeft,
                finishEditingRight: finishEditingRight,
                continueEditing: continueEditing,
                contextMenuActions: contextMenuActions
            )
            .background(Color(nsColor: .textBackgroundColor))

            if isLocationPaneVisible {
                LocationPaneResizeHandle(
                    width: effectiveLocationPaneWidth,
                    setWidth: setLocationPaneWidth
                )
                .gesture(locationPaneResizeGesture)

                LocationPane(
                    renderGeneration: rowsRevision,
                    map: locationMap,
                    movedRows: movedRows,
                    viewport: viewport,
                    selectedRow: selectedDifferenceID.flatMap { differenceLocations[$0]?.rowIndex },
                    currentRow: currentRowIndex,
                    movesCursorOnClick: locationPaneMovesCursorOnClick,
                    detectsMovedBlocks: detectsMovedBlocks,
                    lineNumber: lineNumber,
                    exactLineNumber: exactLineNumber,
                    navigate: navigate,
                    goToLine: goToLine,
                    setMovesCursorOnClick: setLocationPaneMovesCursorOnClick,
                    setDetectMovedBlocks: setDetectMovedBlocks
                )
                .frame(width: effectiveLocationPaneWidth)
            }
        }
    }

    private var effectiveLocationPaneWidth: CGFloat {
        min(
            ComparisonModel.maximumLocationPaneWidth,
            max(
                ComparisonModel.minimumLocationPaneWidth,
                locationPaneWidth - locationPaneResizeTranslation
            )
        )
    }

    private var locationPaneResizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($locationPaneResizeTranslation) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                setLocationPaneWidth(locationPaneWidth - value.translation.width)
            }
    }

    private func updateViewport(_ next: LocationViewport) {
        if viewport != next { viewport = next }
        viewportChanged(next)
    }

    private func navigate(to rowIndex: Int, side: ComparisonSide, activate: Bool = true) {
        if activate {
            let rowID = rows.indices.contains(rowIndex) ? rows[rowIndex].id : nil
            moveCursor(rowID)
            activateSide(side)
            requestNavigationFocus(rowID, side)
        } else {
            navigationRow = rowIndex
            navigationRevision &+= 1
        }
    }

    private func goToLine(_ lineNumber: Int, side: ComparisonSide) {
        guard lineNumber > 0,
            let rowIndex = rows.firstIndex(where: { row in
                let number = side == .left ? row.id.leftNumber : row.id.rightNumber
                return number == lineNumber
            })
        else { return }
        navigate(to: rowIndex, side: side)
    }

    private func lineNumber(at rowIndex: Int, side: ComparisonSide) -> Int? {
        guard !rows.isEmpty else { return nil }
        let rowIndex = min(max(0, rowIndex), rows.count - 1)
        if let line = side == .left ? rows[rowIndex].id.leftNumber : rows[rowIndex].id.rightNumber {
            return line
        }
        var distance = 1
        while rowIndex - distance >= 0 || rowIndex + distance < rows.count {
            if rowIndex - distance >= 0 {
                let row = rows[rowIndex - distance]
                if let line = side == .left ? row.id.leftNumber : row.id.rightNumber {
                    return line
                }
            }
            if rowIndex + distance < rows.count {
                let row = rows[rowIndex + distance]
                if let line = side == .left ? row.id.leftNumber : row.id.rightNumber {
                    return line
                }
            }
            distance += 1
        }
        return nil
    }

    private func exactLineNumber(at rowIndex: Int, side: ComparisonSide) -> Int? {
        guard rows.indices.contains(rowIndex) else { return nil }
        return side == .left ? rows[rowIndex].id.leftNumber : rows[rowIndex].id.rightNumber
    }
}

private struct LocationPaneResizeHandle: View {
    let width: CGFloat
    let setWidth: (CGFloat) -> Void

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 5)
            .contentShape(.rect)
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Location Pane width")
            .accessibilityValue("\(Int(width.rounded())) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    setWidth(width + 8)
                case .decrement:
                    setWidth(width - 8)
                @unknown default:
                    break
                }
            }
    }
}

private struct LocationPane: View {
    let renderGeneration: Int
    let map: LocationMap
    let movedRows: MovedRowMap
    let viewport: LocationViewport
    let selectedRow: Int?
    let currentRow: Int?
    let movesCursorOnClick: Bool
    let detectsMovedBlocks: Bool
    let lineNumber: (Int, ComparisonSide) -> Int?
    let exactLineNumber: (Int, ComparisonSide) -> Int?
    let navigate: (Int, ComparisonSide, Bool) -> Void
    let goToLine: (Int, ComparisonSide) -> Void
    let setMovesCursorOnClick: (Bool) -> Void
    let setDetectMovedBlocks: (Bool) -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                LocationBar(
                    renderGeneration: renderGeneration,
                    side: .left,
                    map: map,
                    viewport: viewport,
                    selectedRow: selectedRow,
                    navigate: { navigate($0, $1, true) },
                    accessibilityNavigate: navigate
                )
                LocationBar(
                    renderGeneration: renderGeneration,
                    side: .right,
                    map: map,
                    viewport: viewport,
                    selectedRow: selectedRow,
                    navigate: { navigate($0, $1, true) },
                    accessibilityNavigate: navigate
                )
            }
            MovedConnectors(
                rowCount: map.rowCount,
                movedRows: movedRows,
                selectedRow: selectedRow
            )
            LocationPaneInteractionView(
                map: map,
                currentRow: min(max(0, currentRow ?? 0), max(0, map.rowCount - 1)),
                movesCursorOnClick: movesCursorOnClick,
                detectsMovedBlocks: detectsMovedBlocks,
                lineNumber: lineNumber,
                exactLineNumber: exactLineNumber,
                navigate: navigate,
                goToLine: goToLine,
                setMovesCursorOnClick: setMovesCursorOnClick,
                setDetectMovedBlocks: setDetectMovedBlocks
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location Pane")
    }

}

private struct LocationPaneInteractionView: NSViewRepresentable {
    let map: LocationMap
    let currentRow: Int
    let movesCursorOnClick: Bool
    let detectsMovedBlocks: Bool
    let lineNumber: (Int, ComparisonSide) -> Int?
    let exactLineNumber: (Int, ComparisonSide) -> Int?
    let navigate: (Int, ComparisonSide, Bool) -> Void
    let goToLine: (Int, ComparisonSide) -> Void
    let setMovesCursorOnClick: (Bool) -> Void
    let setDetectMovedBlocks: (Bool) -> Void

    func makeNSView(context: Context) -> LocationPaneInteractionNSView {
        let view = LocationPaneInteractionNSView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Location Pane Commands")
        return view
    }

    func updateNSView(_ view: LocationPaneInteractionNSView, context: Context) {
        view.map = map
        view.contextRow = currentRow
        view.movesCursorOnClick = movesCursorOnClick
        view.detectsMovedBlocks = detectsMovedBlocks
        view.lineNumber = lineNumber
        view.exactLineNumber = exactLineNumber
        view.navigate = navigate
        view.goToLine = goToLine
        view.setMovesCursorOnClick = setMovesCursorOnClick
        view.setDetectMovedBlocks = setDetectMovedBlocks
        view.updateAccessibilityActions()
    }
}

@MainActor
private final class LocationPaneInteractionNSView: NSView {
    private enum MenuAction: Int {
        case goToLine
        case goTo
        case moveCursorOnClick
        case noMovedBlocks
        case allMovedBlocks
    }

    var map = LocationMap()
    var movesCursorOnClick = true
    var detectsMovedBlocks = false
    var lineNumber: ((Int, ComparisonSide) -> Int?)?
    var exactLineNumber: ((Int, ComparisonSide) -> Int?)?
    var navigate: ((Int, ComparisonSide, Bool) -> Void)?
    var goToLine: ((Int, ComparisonSide) -> Void)?
    var setMovesCursorOnClick: ((Bool) -> Void)?
    var setDetectMovedBlocks: ((Bool) -> Void)?
    var contextRow = 0
    private var contextSide = ComparisonSide.left

    override var isFlipped: Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? { "Location Pane Commands" }

    func updateAccessibilityActions() {
        var actions = [NSAccessibilityCustomAction]()
        if exactLineNumber?(contextRow, .left) != nil {
            actions.append(
                customAction(named: "Go to Left Line") { [weak self] in
                    self?.performGoToLine(on: .left) ?? false
                })
        }
        if exactLineNumber?(contextRow, .right) != nil {
            actions.append(
                customAction(named: "Go to Right Line") { [weak self] in
                    self?.performGoToLine(on: .right) ?? false
                })
        }
        actions.append(
            customAction(named: "Go to Left...") { [weak self] in
                guard let self else { return false }
                presentGoToDialog(on: .left)
                return true
            })
        actions.append(
            customAction(named: "Go to Right...") { [weak self] in
                guard let self else { return false }
                presentGoToDialog(on: .right)
                return true
            })
        actions.append(
            customAction(named: movesCursorOnClick ? "Disable Move Cursor on Click" : "Enable Move Cursor on Click") { [weak self] in
                guard let self else { return false }
                setMovesCursorOnClick?(!movesCursorOnClick)
                return true
            })
        actions.append(contentsOf: [
            customAction(named: "No Moved Blocks") { [weak self] in
                guard let self else { return false }
                setDetectMovedBlocks?(false)
                return true
            },
            customAction(named: "All Moved Blocks") { [weak self] in
                guard let self else { return false }
                setDetectMovedBlocks?(true)
                return true
            }
        ])
        setAccessibilityCustomActions(actions)
    }

    override func mouseDown(with event: NSEvent) {
        navigate(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        navigate(at: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let root = window?.contentView,
            let scrollView = firstTableScrollView(in: root)
        else {
            super.scrollWheel(with: event)
            return
        }
        scrollView.scrollWheel(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        contextSide = side(at: point)
        contextRow = row(at: point) ?? 0
        let line = lineNumber?(contextRow, contextSide)
        let menu = NSMenu(title: "Location Pane")
        menu.autoenablesItems = false
        if let line {
            addItem(to: menu, title: "Go to Line \(line)", action: .goToLine)
        }
        addItem(to: menu, title: "Go to...", action: .goTo, keyEquivalent: "g", modifiers: .command)
        let definition = NSMenuItem(title: "Go to Definition", action: nil, keyEquivalent: "")
        definition.isEnabled = false
        menu.addItem(definition)
        menu.addItem(.separator())
        addItem(
            to: menu,
            title: "Move Cursor on Click",
            action: .moveCursorOnClick,
            state: movesCursorOnClick ? .on : .off
        )
        menu.addItem(.separator())
        addItem(
            to: menu,
            title: "No Moved Blocks",
            action: .noMovedBlocks,
            state: detectsMovedBlocks ? .off : .on
        )
        addItem(
            to: menu,
            title: "All Moved Blocks",
            action: .allMovedBlocks,
            state: detectsMovedBlocks ? .on : .off
        )
        return menu
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = MenuAction(rawValue: sender.tag) else { return }
        switch action {
        case .goToLine:
            if let line = lineNumber?(contextRow, contextSide) {
                goToLine?(line, contextSide)
            }
        case .goTo:
            presentGoToDialog(on: contextSide)
        case .moveCursorOnClick:
            setMovesCursorOnClick?(!movesCursorOnClick)
        case .noMovedBlocks:
            setDetectMovedBlocks?(false)
        case .allMovedBlocks:
            setDetectMovedBlocks?(true)
        }
    }

    private func performGoToLine(on side: ComparisonSide) -> Bool {
        guard map.rowCount > 0 else { return false }
        contextSide = side
        let row = min(max(0, contextRow), map.rowCount - 1)
        guard let line = exactLineNumber?(row, side) else { return false }
        goToLine?(line, side)
        return true
    }

    private func customAction(
        named name: String,
        handler: @escaping @MainActor () -> Bool
    ) -> NSAccessibilityCustomAction {
        NSAccessibilityCustomAction(name: name, handler: handler)
    }

    private func navigate(at point: NSPoint) {
        guard let row = row(at: point) else { return }
        navigate?(row, side(at: point), movesCursorOnClick)
    }

    private func row(at point: NSPoint) -> Int? {
        guard bounds.height > 0 else { return nil }
        return map.rowIndex(at: Double(point.y / bounds.height))
    }

    private func side(at point: NSPoint) -> ComparisonSide {
        point.x < bounds.midX ? .left : .right
    }

    private func presentGoToDialog(on side: ComparisonSide) {
        contextSide = side
        let input = NSTextField(string: lineNumber?(contextRow, side).map(String.init) ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = side == .left ? "Enter a left line number." : "Enter a right line number."
        alert.accessoryView = input
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
            let line = Int(input.stringValue),
            line > 0
        else { return }
        goToLine?(line, side)
    }

    private func addItem(
        to menu: NSMenu,
        title: String,
        action: MenuAction,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        state: NSControl.StateValue = .off
    ) {
        let item = NSMenuItem(
            title: title,
            action: #selector(performMenuAction(_:)),
            keyEquivalent: keyEquivalent
        )
        item.target = self
        item.tag = action.rawValue
        item.keyEquivalentModifierMask = modifiers
        item.state = state
        item.isEnabled = true
        menu.addItem(item)
    }

    private func firstTableScrollView(in view: NSView) -> DiffVerticalScrollView? {
        if let scrollView = view as? DiffVerticalScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstTableScrollView(in: child) { return scrollView }
        }
        return nil
    }
}

private struct MovedConnectors: View {
    let rowCount: Int
    let movedRows: MovedRowMap
    let selectedRow: Int?

    var body: some View {
        Canvas { context, size in
            guard rowCount > 0, size.height > 0 else { return }
            let scale = size.height / CGFloat(rowCount)
            let leftX = (size.width - 8) / 2
            let rightX = (size.width + 8) / 2
            for block in movedRows.blocks {
                let leftTop = CGFloat(block.leftStartRow) * scale
                let leftBottom = max(leftTop + 1, CGFloat(block.leftEndRow) * scale)
                let rightTop = CGFloat(block.rightStartRow) * scale
                let rightBottom = max(rightTop + 1, CGFloat(block.rightEndRow) * scale)
                var path = Path()
                path.move(to: CGPoint(x: leftX, y: leftTop))
                path.addCurve(
                    to: CGPoint(x: rightX, y: rightTop),
                    control1: CGPoint(x: size.width / 2, y: leftTop),
                    control2: CGPoint(x: size.width / 2, y: rightTop)
                )
                path.addLine(to: CGPoint(x: rightX, y: rightBottom))
                path.addCurve(
                    to: CGPoint(x: leftX, y: leftBottom),
                    control1: CGPoint(x: size.width / 2, y: rightBottom),
                    control2: CGPoint(x: size.width / 2, y: leftBottom)
                )
                path.closeSubpath()
                let selected =
                    selectedRow.map {
                        (Int(block.leftStartRow)..<Int(block.leftEndRow)).contains($0)
                            || (Int(block.rightStartRow)..<Int(block.rightEndRow)).contains($0)
                    } ?? false
                let color = selected ? Color.accentColor : Color.blue.opacity(0.72)
                context.fill(path, with: .color(color.opacity(0.78)))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LocationBar: View {
    let renderGeneration: Int
    let side: ComparisonSide
    let map: LocationMap
    let viewport: LocationViewport
    let selectedRow: Int?
    let navigate: (Int, ComparisonSide) -> Void
    let accessibilityNavigate: (Int, ComparisonSide, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LocationMarks(renderGeneration: renderGeneration, map: map, side: side)
                LocationIndicator(
                    rowCount: map.rowCount,
                    viewport: viewport,
                    selectedRow: selectedRow
                )
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard size.height > 0,
                            let row = map.rowIndex(at: Double(value.location.y / size.height))
                        else {
                            return
                        }
                        navigate(row, side)
                    }
            )
            .accessibilityRepresentation {
                LocationSliderControl(
                    side: side,
                    map: map,
                    viewport: viewport,
                    navigate: { accessibilityNavigate($0, $1, false) }
                )
            }
        }
    }
}

private struct LocationSliderControl: View {
    let side: ComparisonSide
    let map: LocationMap
    let viewport: LocationViewport
    let navigate: (Int, ComparisonSide) -> Void

    var body: some View {
        Slider(value: accessibilityPosition, in: 0...1) {
            Text("\(side == .left ? "Left" : "Right") file location map")
        }
        .accessibilityLabel("\(side == .left ? "Left" : "Right") file location map")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Adjust to scroll the comparison")
        .disabled(map.rowCount == 0 || viewport.rowCount >= map.rowCount)
    }

    private var accessibilityPosition: Binding<Double> {
        Binding(
            get: { viewport.position(totalRowCount: map.rowCount) },
            set: { fraction in
                guard let row = viewport.centeredRow(at: fraction, totalRowCount: map.rowCount) else {
                    return
                }
                navigate(row, side)
            }
        )
    }

    private var accessibilityValue: String {
        guard map.rowCount > 0 else { return "Empty comparison" }
        return "Comparison rows \(viewport.startRow + 1) through \(max(viewport.startRow + 1, viewport.endRow)) of \(map.rowCount)"
    }
}

private struct LocationMarks: View {
    let renderGeneration: Int
    let map: LocationMap
    let side: ComparisonSide

    var body: some View {
        Canvas { context, size in
            let performanceStart = PerformanceProbe.shared.locationPaneDrawStarted(
                generation: renderGeneration,
                rowCount: map.rowCount,
                blockCount: map.blockCount,
                size: size
            )
            defer {
                PerformanceProbe.shared.locationPaneRendered(
                    start: performanceStart,
                    generation: renderGeneration,
                    side: side,
                    rowCount: map.rowCount,
                    blockCount: map.blockCount
                )
            }
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(nsColor: .textBackgroundColor)))
            context.stroke(Path(bounds), with: .color(.secondary.opacity(0.55)), lineWidth: 1)
            guard map.rowCount > 0, size.height > 0 else { return }

            let scale = size.height / CGFloat(map.rowCount)
            for index in 0..<map.blockCount {
                let block = map.block(at: index)
                guard isVisible(block.kind) else { continue }
                let top = CGFloat(block.startRow) * scale
                let bottom = CGFloat(block.endRow) * scale
                let inset: CGFloat = block.kind == .modified ? 1 : 4
                let blockRect = CGRect(
                    x: inset,
                    y: top,
                    width: max(0, size.width - inset * 2),
                    height: max(1, bottom - top)
                )
                context.fill(Path(blockRect), with: .color(color(for: block.kind)))
                if block.kind != .modified {
                    context.stroke(Path(blockRect), with: .color(.primary.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func isVisible(_ kind: DiffKind) -> Bool {
        switch (kind, side) {
        case (.modified, _), (.removed, .left), (.added, .right): true
        default: false
        }
    }

    private func color(for kind: DiffKind) -> Color {
        switch kind {
        case .modified: .orange.opacity(0.72)
        case .removed: .red.opacity(0.72)
        case .added: .teal.opacity(0.72)
        case .unchanged: .clear
        }
    }
}

private struct LocationIndicator: View {
    let rowCount: Int
    let viewport: LocationViewport
    let selectedRow: Int?

    var body: some View {
        Canvas { context, size in
            guard rowCount > 0, size.height > 0 else { return }
            let scale = size.height / CGFloat(rowCount)
            let viewportTop = CGFloat(min(viewport.startRow, rowCount)) * scale
            let viewportBottom = CGFloat(min(viewport.endRow, rowCount)) * scale
            let viewportRect = CGRect(
                x: 0,
                y: viewportTop,
                width: size.width,
                height: max(2, viewportBottom - viewportTop)
            ).intersection(CGRect(origin: .zero, size: size))
            context.fill(Path(viewportRect), with: .color(.primary.opacity(0.12)))
            context.stroke(Path(viewportRect), with: .color(.primary.opacity(0.6)), lineWidth: 1)

            if let selectedRow {
                let y = min(size.height - 1, max(1, CGFloat(selectedRow) * scale))
                var marker = Path()
                marker.move(to: CGPoint(x: 0, y: y))
                marker.addLine(to: CGPoint(x: min(7, size.width), y: y))
                context.stroke(marker, with: .color(.accentColor), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DiffTableView: NSViewRepresentable {
    let rows: [DiffRow]
    let rowsRevision: Int
    let maximumLineColumns: Int
    let differenceLocations: DifferenceLocations
    let movedRows: MovedRowMap
    let selectedDifferenceID: DiffRow.ID?
    let selectedDifferenceRevealRevision: Int
    let focusRequest: DiffFocusRequest?
    let isFocusRequestCurrent: (Int) -> Bool
    let leftEditable: Bool
    let rightEditable: Bool
    let navigationRow: Int?
    let navigationRevision: Int
    let viewportChanged: (LocationViewport) -> Void
    let selectDifference: (DiffRow.ID?) -> Void
    let activateSide: (ComparisonSide) -> Void
    let editLeft: (DiffRow.ID, String) -> Void
    let editRight: (DiffRow.ID, String) -> Void
    let finishEditingLeft: (DiffRow.ID) -> Void
    let finishEditingRight: (DiffRow.ID) -> Void
    let continueEditing: (ComparisonSide, Int) -> Void
    let contextMenuActions: DiffContextMenuActions

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rows: rows,
            rowsRevision: rowsRevision,
            differenceLocations: differenceLocations,
            movedRows: movedRows,
            selectedDifferenceRevealRevision: selectedDifferenceRevealRevision,
            focusGeneration: 0,
            isFocusRequestCurrent: isFocusRequestCurrent,
            leftEditable: leftEditable,
            rightEditable: rightEditable,
            appendsEditableRow: leftEditable || rightEditable,
            navigationRevision: navigationRevision,
            viewportChanged: viewportChanged,
            selectDifference: selectDifference,
            activateSide: activateSide,
            editLeft: editLeft,
            editRight: editRight,
            finishEditingLeft: finishEditingLeft,
            finishEditingRight: finishEditingRight,
            continueEditing: continueEditing,
            contextMenuActions: contextMenuActions
        )
    }

    func makeNSView(context: Context) -> DiffTableContainerView {
        makeNSView(coordinator: context.coordinator)
    }

    fileprivate func makeNSView(coordinator: Coordinator) -> DiffTableContainerView {
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
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        coordinator.tableView = tableView

        let scrollView = DiffVerticalScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true
        let container = DiffTableContainerView(scrollView: scrollView)
        scrollView.horizontalScrollHandler = { [weak coordinator] delta in
            coordinator?.scrollHorizontally(by: delta)
        }
        container.horizontalLayoutDidChange = { [weak coordinator] in
            coordinator?.refreshVisibleHorizontalOffsets()
        }
        container.horizontalScroller.target = coordinator
        container.horizontalScroller.action = #selector(Coordinator.scrollHorizontally(_:))
        coordinator.container = container
        coordinator.observeViewport(in: scrollView.contentView)
        return container
    }

    func updateNSView(_ container: DiffTableContainerView, context: Context) {
        updateNSView(container, coordinator: context.coordinator)
    }

    fileprivate func updateNSView(
        _ container: DiffTableContainerView,
        coordinator: Coordinator
    ) {
        guard let tableView = coordinator.tableView else { return }
        coordinator.selectDifference = selectDifference
        coordinator.activateSide = activateSide
        coordinator.editLeft = editLeft
        coordinator.editRight = editRight
        coordinator.finishEditingLeft = finishEditingLeft
        coordinator.finishEditingRight = finishEditingRight
        coordinator.continueEditing = continueEditing
        coordinator.contextMenuActions = contextMenuActions
        coordinator.isFocusRequestCurrent = isFocusRequestCurrent
        coordinator.viewportChanged = viewportChanged
        coordinator.differenceLocations = differenceLocations
        coordinator.movedRows = movedRows
        let editabilityChanged =
            coordinator.leftEditable != leftEditable
            || coordinator.rightEditable != rightEditable
        coordinator.leftEditable = leftEditable
        coordinator.rightEditable = rightEditable
        coordinator.appendsEditableRow = leftEditable || rightEditable

        if coordinator.rowsRevision != rowsRevision || editabilityChanged {
            coordinator.setRows(
                rows,
                revision: rowsRevision,
                differenceLocations: differenceLocations,
                movedRows: movedRows
            )
            coordinator.beginFirstVisibleRowTrace()
            tableView.reloadData()
            coordinator.finishFirstVisibleRowTraceAfterLayout()
        }
        container.maximumTextWidth = CGFloat(maximumLineColumns) * 7.25 + 12

        let oldSelection = coordinator.selectedDifferenceID
        let revealRequested =
            coordinator.selectedDifferenceRevealRevision
            != selectedDifferenceRevealRevision
        coordinator.selectedDifferenceID = selectedDifferenceID
        coordinator.selectedDifferenceRevealRevision = selectedDifferenceRevealRevision
        coordinator.synchronizeTableSelection()
        coordinator.refreshVisibleRows(for: [oldSelection, selectedDifferenceID].compactMap { $0 })
        if oldSelection != selectedDifferenceID || revealRequested,
            let selectedDifferenceID,
            let location = coordinator.differenceLocations[selectedDifferenceID]
        {
            tableView.scrollRowToVisible(location.rowIndex)
        }
        if coordinator.navigationRevision != navigationRevision {
            coordinator.navigationRevision = navigationRevision
            if let navigationRow {
                coordinator.scroll(toCenteredRow: navigationRow)
            }
        }
        coordinator.accept(focusRequest)
        coordinator.restorePendingEditorFocus()
        coordinator.reportViewport()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let editableRow = DiffRow(left: nil, right: nil, kind: .unchanged)
        var rows: [DiffRow]
        var rowsRevision: Int
        var differenceLocations: DifferenceLocations
        var movedRows: MovedRowMap
        var selectedDifferenceID: DiffRow.ID?
        var selectedDifferenceRevealRevision: Int
        private(set) var focusGeneration: Int
        var isFocusRequestCurrent: (Int) -> Bool
        var leftEditable: Bool
        var rightEditable: Bool
        var appendsEditableRow: Bool
        var navigationRevision: Int
        var viewportChanged: (LocationViewport) -> Void
        var selectDifference: (DiffRow.ID?) -> Void
        var activateSide: (ComparisonSide) -> Void
        var editLeft: (DiffRow.ID, String) -> Void
        var editRight: (DiffRow.ID, String) -> Void
        var finishEditingLeft: (DiffRow.ID) -> Void
        var finishEditingRight: (DiffRow.ID) -> Void
        var continueEditing: (ComparisonSide, Int) -> Void
        var contextMenuActions: DiffContextMenuActions
        weak var tableView: NSTableView?
        weak var container: DiffTableContainerView?
        private var isSynchronizingSelection = false
        private var pendingEditorFocus: PendingEditorFocus?
        private var firstVisibleRowSignpostID: OSSignpostID?
        private var autoScrollSignpostID: OSSignpostID?
        private var didAutoScroll = false
        nonisolated(unsafe) private var viewportObserver: NSObjectProtocol?
        private var lastReportedViewport: LocationViewport?

        private struct PendingEditorFocus {
            let side: ComparisonSide
            let lineNumber: Int
            let afterRowsRevision: Int
            let requestGeneration: Int
        }

        private struct DeferredLineDifferenceSelection {
            let rowID: DiffRow.ID
            let side: ComparisonSide
            let direction: LineDifferenceSelectionDirection
            let rowsRevision: Int
            let requestGeneration: Int
        }

        private struct DeferredEditorFocus {
            let rowID: DiffRow.ID
            let side: ComparisonSide
            let rowsRevision: Int
            let requestGeneration: Int
        }

        private struct DeferredPendingEditorFocus {
            let rowID: DiffRow.ID
            let side: ComparisonSide
            let rowsRevision: Int
            let requestGeneration: Int
        }

        init(
            rows: [DiffRow],
            rowsRevision: Int,
            differenceLocations: DifferenceLocations,
            movedRows: MovedRowMap,
            selectedDifferenceRevealRevision: Int,
            focusGeneration: Int,
            isFocusRequestCurrent: @escaping (Int) -> Bool,
            leftEditable: Bool,
            rightEditable: Bool,
            appendsEditableRow: Bool,
            navigationRevision: Int,
            viewportChanged: @escaping (LocationViewport) -> Void,
            selectDifference: @escaping (DiffRow.ID?) -> Void,
            activateSide: @escaping (ComparisonSide) -> Void,
            editLeft: @escaping (DiffRow.ID, String) -> Void,
            editRight: @escaping (DiffRow.ID, String) -> Void,
            finishEditingLeft: @escaping (DiffRow.ID) -> Void,
            finishEditingRight: @escaping (DiffRow.ID) -> Void,
            continueEditing: @escaping (ComparisonSide, Int) -> Void,
            contextMenuActions: DiffContextMenuActions
        ) {
            self.rows = rows
            self.rowsRevision = rowsRevision
            self.differenceLocations = differenceLocations
            self.movedRows = movedRows
            self.selectedDifferenceRevealRevision = selectedDifferenceRevealRevision
            self.focusGeneration = focusGeneration
            self.isFocusRequestCurrent = isFocusRequestCurrent
            self.leftEditable = leftEditable
            self.rightEditable = rightEditable
            self.appendsEditableRow = appendsEditableRow
            self.navigationRevision = navigationRevision
            self.viewportChanged = viewportChanged
            self.selectDifference = selectDifference
            self.activateSide = activateSide
            self.editLeft = editLeft
            self.editRight = editRight
            self.finishEditingLeft = finishEditingLeft
            self.finishEditingRight = finishEditingRight
            self.continueEditing = continueEditing
            self.contextMenuActions = contextMenuActions
            super.init()
        }

        deinit {
            if let viewportObserver {
                NotificationCenter.default.removeObserver(viewportObserver)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count + (appendsEditableRow ? 1 : 0)
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            displayedRow(at: row)?.kind != .unchanged
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSynchronizingSelection, let tableView else { return }
            guard let row = displayedRow(at: tableView.selectedRow) else {
                selectDifference(nil)
                return
            }
            guard row.kind != .unchanged else { return }
            selectDifference(row.id)
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let displayedRow = displayedRow(at: row) else { return nil }
            let cell =
                tableView.makeView(withIdentifier: .diffCell, owner: self) as? DiffTableCellView
                ?? DiffTableCellView()
            cell.identifier = .diffCell
            cell.configure(
                row: displayedRow,
                selected: displayedRow.id == selectedDifferenceID,
                movedLeft: displayedRow.left.map { movedRows.isMoved(line: $0.number, on: .left) } ?? false,
                movedRight: displayedRow.right.map { movedRows.isMoved(line: $0.number, on: .right) } ?? false,
                leftEditable: leftEditable,
                rightEditable: rightEditable,
                horizontalOffset: container?.horizontalOffset ?? 0,
                maximumTextWidth: container?.maximumTextWidth ?? 0,
                editLeft: editLeft,
                editRight: editRight,
                finishEditingLeft: finishEditingLeft,
                finishEditingRight: finishEditingRight,
                contextMenuActions: contextMenuActions,
                activateLeft: { [weak self, id = displayedRow.id] in
                    self?.selectDifference(id)
                    self?.activateSide(.left)
                },
                activateRight: { [weak self, id = displayedRow.id] in
                    self?.selectDifference(id)
                    self?.activateSide(.right)
                },
                continueEditingLeft: { [weak self] lineOffset in
                    self?.continueEditing(fromRow: row, side: .left, lineOffset: lineOffset)
                },
                continueEditingRight: { [weak self] lineOffset in
                    self?.continueEditing(fromRow: row, side: .right, lineOffset: lineOffset)
                }
            )
            return cell
        }

        func beginFirstVisibleRowTrace() {
            if let id = firstVisibleRowSignpostID {
                PerformanceTrace.end("FirstVisibleRow", id: id)
            }
            guard !rows.isEmpty else {
                firstVisibleRowSignpostID = nil
                return
            }
            firstVisibleRowSignpostID = PerformanceTrace.begin("FirstVisibleRow")
            PerformanceProbe.shared.beginFirstRender(
                rowCount: rows.count + (appendsEditableRow ? 1 : 0)
            )
        }

        func finishFirstVisibleRowTraceAfterLayout() {
            guard firstVisibleRowSignpostID != nil, let tableView else { return }
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView, tableView.numberOfRows > 0 else { return }
                tableView.layoutSubtreeIfNeeded()
                guard tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) != nil,
                    let id = self.firstVisibleRowSignpostID
                else { return }
                PerformanceTrace.end("FirstVisibleRow", id: id)
                self.firstVisibleRowSignpostID = nil
                PerformanceProbe.shared.end("first_render")
                guard PerformanceProbe.shared.shouldAutoScroll, !self.didAutoScroll else { return }
                self.didAutoScroll = true
                self.autoScrollSignpostID = PerformanceTrace.begin("AutoScroll")
                PerformanceProbe.shared.begin("scroll")
                tableView.scrollRowToVisible(tableView.numberOfRows - 1)
                tableView.layoutSubtreeIfNeeded()
                self.finishAutoScrollWhenVisible(
                    tableView,
                    rowsRevision: self.rowsRevision,
                    remainingAttempts: 100
                )
            }
        }

        private func finishAutoScrollWhenVisible(
            _ tableView: NSTableView,
            rowsRevision expectedRowsRevision: Int,
            remainingAttempts: Int
        ) {
            guard remainingAttempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tableView] in
                guard let self, let tableView,
                    self.rowsRevision == expectedRowsRevision,
                    tableView.window != nil,
                    tableView.numberOfRows > 0
                else { return }
                tableView.layoutSubtreeIfNeeded()
                let lastRow = tableView.numberOfRows - 1
                guard tableView.rows(in: tableView.visibleRect).contains(lastRow) else {
                    self.finishAutoScrollWhenVisible(
                        tableView,
                        rowsRevision: expectedRowsRevision,
                        remainingAttempts: remainingAttempts - 1
                    )
                    return
                }
                if let id = self.autoScrollSignpostID {
                    PerformanceTrace.end("AutoScroll", id: id)
                    self.autoScrollSignpostID = nil
                }
                PerformanceProbe.shared.finishScroll()
            }
        }

        func setRows(
            _ rows: [DiffRow],
            revision: Int,
            differenceLocations: DifferenceLocations,
            movedRows: MovedRowMap
        ) {
            self.rows = rows
            rowsRevision = revision
            self.differenceLocations = differenceLocations
            self.movedRows = movedRows
            lastReportedViewport = nil
        }

        func observeViewport(in clipView: NSClipView) {
            if let viewportObserver {
                NotificationCenter.default.removeObserver(viewportObserver)
            }
            viewportObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportViewport()
                }
            }
        }

        func reportViewport() {
            guard let tableView, !rows.isEmpty else {
                publishViewport(.empty)
                return
            }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            let start = min(rows.count, visibleRows.location)
            let end = min(rows.count, NSMaxRange(visibleRows))
            publishViewport(LocationViewport(startRow: start, endRow: end))
        }

        func scroll(toCenteredRow rowIndex: Int) {
            guard let tableView, let scrollView = tableView.enclosingScrollView, !rows.isEmpty else {
                return
            }
            let row = min(max(0, rowIndex), rows.count - 1)
            let rowRect = tableView.rect(ofRow: row)
            let maximumY = max(0, tableView.bounds.height - scrollView.contentSize.height)
            let targetY = min(maximumY, max(0, rowRect.midY - scrollView.contentSize.height / 2))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            reportViewport()
        }

        private func publishViewport(_ viewport: LocationViewport) {
            guard lastReportedViewport != viewport else { return }
            lastReportedViewport = viewport
            DispatchQueue.main.async { [viewportChanged] in
                viewportChanged(viewport)
            }
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
                        as? DiffTableCellView
                else { continue }
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
                let location = differenceLocations[selectedDifferenceID]
            {
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
            for row in visibleRows.location..<NSMaxRange(visibleRows) {
                guard
                    let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                        as? DiffTableCellView
                else { continue }
                cell.setHorizontalLayout(
                    offset: container.horizontalOffset,
                    maximumTextWidth: container.maximumTextWidth
                )
            }
        }

        private func continueEditing(fromRow rowIndex: Int, side: ComparisonSide, lineOffset: Int) {
            guard let row = displayedRow(at: rowIndex) else { return }
            let currentLine = side == .left ? row.left?.number : row.right?.number
            let insertionLine = rows[..<min(rowIndex, rows.count)].reduce(into: 1) { number, row in
                if side == .left ? row.left != nil : row.right != nil {
                    number += 1
                }
            }
            continueEditing(side, (currentLine ?? insertionLine) + lineOffset)
        }

        func accept(_ request: DiffFocusRequest?) {
            guard let request,
                request.generation > focusGeneration,
                isFocusRequestCurrent(request.generation)
            else { return }
            focusGeneration = request.generation
            pendingEditorFocus = nil
            switch request.action {
            case .focusEditor(let rowID, let side, let centersRow):
                focusEditor(
                    on: side,
                    rowID: rowID,
                    centersRow: centersRow,
                    requestGeneration: request.generation
                )
            case .selectLineDifference(let rowID, let side, let direction):
                selectDifferenceRange(
                    on: side,
                    rowID: rowID,
                    direction: direction,
                    requestGeneration: request.generation
                )
            case .continueEditing(let side, let lineNumber, let afterRowsRevision):
                pendingEditorFocus = PendingEditorFocus(
                    side: side,
                    lineNumber: lineNumber,
                    afterRowsRevision: afterRowsRevision,
                    requestGeneration: request.generation
                )
            }
        }

        func restorePendingEditorFocus() {
            guard let pendingEditorFocus, let tableView else { return }
            guard rowsRevision > pendingEditorFocus.afterRowsRevision else { return }
            guard
                let rowIndex = rows.firstIndex(where: { row in
                    let line = pendingEditorFocus.side == .left ? row.left?.number : row.right?.number
                    return line == pendingEditorFocus.lineNumber
                })
            else { return }
            let request = DeferredPendingEditorFocus(
                rowID: rows[rowIndex].id,
                side: pendingEditorFocus.side,
                rowsRevision: rowsRevision,
                requestGeneration: pendingEditorFocus.requestGeneration
            )
            tableView.scrollRowToVisible(rowIndex)
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                _ = self.performPendingEditorFocus(request, in: tableView)
            }
        }

        func selectDifferenceRange(
            on side: ComparisonSide,
            rowID: DiffRow.ID,
            direction: LineDifferenceSelectionDirection,
            requestGeneration: Int
        ) {
            guard let tableView,
                let rowIndex = rows.firstIndex(where: { $0.id == rowID })
            else { return }
            let request = DeferredLineDifferenceSelection(
                rowID: rowID,
                side: side,
                direction: direction,
                rowsRevision: rowsRevision,
                requestGeneration: requestGeneration
            )
            tableView.scrollRowToVisible(rowIndex)
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                _ = self.performLineDifferenceSelection(request, in: tableView)
            }
        }

        func focusEditor(
            on side: ComparisonSide,
            rowID: DiffRow.ID?,
            centersRow: Bool,
            requestGeneration: Int
        ) {
            guard let tableView else { return }
            let rowIndex: Int
            if let rowID {
                guard let requestedRowIndex = rows.firstIndex(where: { $0.id == rowID }) else {
                    return
                }
                rowIndex = requestedRowIndex
            } else {
                rowIndex = max(0, tableView.row(at: tableView.visibleRect.origin))
            }
            guard rows.indices.contains(rowIndex) else { return }
            if centersRow { scroll(toCenteredRow: rowIndex) }
            let request = DeferredEditorFocus(
                rowID: rows[rowIndex].id,
                side: side,
                rowsRevision: rowsRevision,
                requestGeneration: requestGeneration
            )
            tableView.scrollRowToVisible(rowIndex)
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                _ = self.performEditorFocus(request, in: tableView)
            }
        }

        private func performLineDifferenceSelection(
            _ request: DeferredLineDifferenceSelection,
            in tableView: NSTableView
        ) -> Bool {
            guard rowsRevision == request.rowsRevision,
                focusGeneration == request.requestGeneration,
                isFocusRequestCurrent(request.requestGeneration),
                let rowIndex = rows.firstIndex(where: { $0.id == request.rowID }),
                let cell = tableView.view(
                    atColumn: 0,
                    row: rowIndex,
                    makeIfNecessary: true
                ) as? DiffTableCellView,
                cell.represents(rowID: request.rowID)
            else { return false }
            cell.selectDifferenceRange(on: request.side, direction: request.direction)
            return true
        }

        private func performEditorFocus(
            _ request: DeferredEditorFocus,
            in tableView: NSTableView
        ) -> Bool {
            guard rowsRevision == request.rowsRevision,
                focusGeneration == request.requestGeneration,
                isFocusRequestCurrent(request.requestGeneration),
                let rowIndex = rows.firstIndex(where: { $0.id == request.rowID }),
                let cell = tableView.view(
                    atColumn: 0,
                    row: rowIndex,
                    makeIfNecessary: true
                ) as? DiffTableCellView,
                cell.represents(rowID: request.rowID)
            else { return false }
            return cell.focusEditor(on: request.side)
        }

        private func performPendingEditorFocus(
            _ request: DeferredPendingEditorFocus,
            in tableView: NSTableView
        ) -> Bool {
            guard rowsRevision == request.rowsRevision,
                focusGeneration == request.requestGeneration,
                isFocusRequestCurrent(request.requestGeneration),
                pendingEditorFocus?.requestGeneration == request.requestGeneration,
                let rowIndex = rows.firstIndex(where: { $0.id == request.rowID }),
                let cell = tableView.view(
                    atColumn: 0,
                    row: rowIndex,
                    makeIfNecessary: true
                ) as? DiffTableCellView,
                cell.represents(rowID: request.rowID),
                cell.focusEditor(on: request.side),
                pendingEditorFocus?.requestGeneration == request.requestGeneration
            else { return false }
            pendingEditorFocus = nil
            return true
        }

        #if DEBUG
            func testCaptureLineDifferenceSelection(
                on side: ComparisonSide,
                rowID: DiffRow.ID,
                direction: LineDifferenceSelectionDirection
            ) -> () -> Bool {
                let request = DeferredLineDifferenceSelection(
                    rowID: rowID,
                    side: side,
                    direction: direction,
                    rowsRevision: rowsRevision,
                    requestGeneration: focusGeneration
                )
                return { [weak self, weak tableView] in
                    guard let self, let tableView else { return false }
                    return self.performLineDifferenceSelection(request, in: tableView)
                }
            }

            func testCapturePaneFocus(on side: ComparisonSide, rowID: DiffRow.ID) -> () -> Bool {
                let request = DeferredEditorFocus(
                    rowID: rowID,
                    side: side,
                    rowsRevision: rowsRevision,
                    requestGeneration: focusGeneration
                )
                return { [weak self, weak tableView] in
                    guard let self, let tableView else { return false }
                    return self.performEditorFocus(request, in: tableView)
                }
            }

            func testAdvanceLineDifferenceSelectionRevision() {
                focusGeneration &+= 1
            }

            func testAdvancePaneFocusRevision() {
                focusGeneration &+= 1
            }

            func testSetPendingEditorFocus(side: ComparisonSide, lineNumber: Int) {
                focusGeneration &+= 1
                pendingEditorFocus = PendingEditorFocus(
                    side: side,
                    lineNumber: lineNumber,
                    afterRowsRevision: rowsRevision - 1,
                    requestGeneration: focusGeneration
                )
            }

            func testCapturePendingEditorFocus() -> (() -> Bool)? {
                guard let pendingEditorFocus,
                    let rowIndex = rows.firstIndex(where: { row in
                        let line = pendingEditorFocus.side == .left ? row.left?.number : row.right?.number
                        return line == pendingEditorFocus.lineNumber
                    })
                else { return nil }
                let request = DeferredPendingEditorFocus(
                    rowID: rows[rowIndex].id,
                    side: pendingEditorFocus.side,
                    rowsRevision: rowsRevision,
                    requestGeneration: pendingEditorFocus.requestGeneration
                )
                return { [weak self, weak tableView] in
                    guard let self, let tableView else { return false }
                    return self.performPendingEditorFocus(request, in: tableView)
                }
            }

            var testPendingEditorFocusLineNumber: Int? { pendingEditorFocus?.lineNumber }
        #endif

        private func displayedRow(at index: Int) -> DiffRow? {
            if rows.indices.contains(index) { return rows[index] }
            if appendsEditableRow && index == rows.count { return Self.editableRow }
            return nil
        }

    }
}

@MainActor
private final class DiffVerticalScrollView: NSScrollView {
    var horizontalScrollHandler: ((CGFloat) -> Void)?
    private var scrollSignpostID: OSSignpostID?

    override func scrollWheel(with event: NSEvent) {
        if scrollSignpostID == nil {
            scrollSignpostID = PerformanceTrace.begin("ScrollGesture")
        }
        if event.scrollingDeltaX != 0 {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 24
            horizontalScrollHandler?(-event.scrollingDeltaX * scale)
        }
        if event.scrollingDeltaY != 0 || event.scrollingDeltaX == 0 {
            super.scrollWheel(with: event)
        }
        let isDiscrete = event.phase.isEmpty && event.momentumPhase.isEmpty
        let didEnd =
            event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
        if isDiscrete || didEnd, let id = scrollSignpostID {
            PerformanceTrace.end("ScrollGesture", id: id)
            scrollSignpostID = nil
        }
    }
}

@MainActor
private final class DiffTableContainerView: NSView {
    let scrollView: NSScrollView
    let horizontalScroller = NSScroller()
    var horizontalLayoutDidChange: (() -> Void)?
    var maximumTextWidth: CGFloat = 0 {
        didSet {
            guard maximumTextWidth != oldValue else { return }
            needsLayout = true
            updateScrollerMetrics()
            horizontalLayoutDidChange?()
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
            horizontalLayoutDidChange?()
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
        horizontalLayoutDidChange?()
    }

    func updateHorizontalOffset(by delta: CGFloat) {
        horizontalOffset = min(max(0, horizontalOffset + delta), maximumOffset)
        horizontalScroller.doubleValue = maximumOffset > 0 ? Double(horizontalOffset / maximumOffset) : 0
        horizontalLayoutDidChange?()
    }

    private var textViewportWidth: CGFloat {
        let paneWidth = max(0, (scrollView.contentSize.width - DiffTableCellView.controlsWidth) / 2)
        return max(0, paneWidth - DiffTableCellView.numberAreaWidth - 8)
    }

    private var maximumOffset: CGFloat {
        max(0, maximumTextWidth - textViewportWidth)
    }

    #if DEBUG
        var testMaximumOffset: CGFloat { maximumOffset }
    #endif

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
    private static let movedTint = NSColor.systemBlue.withAlphaComponent(0.18)
    private static let dividerColor = NSColor.separatorColor.withAlphaComponent(0.7)
    private let leftNumber = makeLabel(fontSize: 10, color: .tertiaryLabelColor, alignment: .right)
    private let leftText = DiffLineTextView()
    private let rightNumber = makeLabel(fontSize: 10, color: .tertiaryLabelColor, alignment: .right)
    private let rightText = DiffLineTextView()
    private var row: DiffRow?
    private var selected = false
    private var movedLeft = false
    private var movedRight = false

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
            color: tint(for: row.kind, side: .left, moved: movedLeft),
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
            color: tint(for: row.kind, side: .right, moved: movedRight),
            dirtyRect: dirtyRect,
            context: context
        )
        fill(NSRect(x: paneWidth, y: 0, width: 1, height: bounds.height), color: Self.dividerColor, dirtyRect: dirtyRect, context: context)
        fill(
            NSRect(x: 0, y: 0, width: 4, height: bounds.height), color: statusColor(for: row.kind, side: .left, moved: movedLeft), dirtyRect: dirtyRect,
            context: context)
        fill(
            NSRect(x: paneWidth + 1, y: 0, width: 4, height: bounds.height), color: statusColor(for: row.kind, side: .right, moved: movedRight),
            dirtyRect: dirtyRect, context: context)
    }

    func configure(
        row: DiffRow,
        selected: Bool,
        movedLeft: Bool,
        movedRight: Bool,
        leftEditable: Bool,
        rightEditable: Bool,
        horizontalOffset: CGFloat,
        maximumTextWidth: CGFloat,
        editLeft: @escaping (DiffRow.ID, String) -> Void,
        editRight: @escaping (DiffRow.ID, String) -> Void,
        finishEditingLeft: @escaping (DiffRow.ID) -> Void,
        finishEditingRight: @escaping (DiffRow.ID) -> Void,
        contextMenuActions: DiffContextMenuActions,
        activateLeft: @escaping () -> Void,
        activateRight: @escaping () -> Void,
        continueEditingLeft: @escaping (Int) -> Void,
        continueEditingRight: @escaping (Int) -> Void
    ) {
        leftText.prepareForReuse()
        rightText.prepareForReuse()
        self.row = row
        self.movedLeft = movedLeft
        self.movedRight = movedRight
        leftNumber.stringValue = row.left.map { String($0.number) } ?? ""
        leftText.stringValue = row.left?.text ?? ""
        leftText.setDifferenceRanges(differenceRanges(for: row, side: .left))
        leftText.configureContextMenu(row: row, side: .left, actions: contextMenuActions)
        leftText.configureEditable(
            leftEditable,
            accessibilityLabel: editorAccessibilityLabel(
                for: row,
                side: .left,
                editable: leftEditable
            ),
            activate: activateLeft,
            finish: { [rowID = row.id] in finishEditingLeft(rowID) },
            continueAfterNewline: continueEditingLeft,
            commit: { [rowID = row.id] replacement in
                editLeft(rowID, replacement)
            }
        )
        rightNumber.stringValue = row.right.map { String($0.number) } ?? ""
        rightText.stringValue = row.right?.text ?? ""
        rightText.setDifferenceRanges(differenceRanges(for: row, side: .right))
        rightText.configureContextMenu(row: row, side: .right, actions: contextMenuActions)
        rightText.configureEditable(
            rightEditable,
            accessibilityLabel: editorAccessibilityLabel(
                for: row,
                side: .right,
                editable: rightEditable
            ),
            activate: activateRight,
            finish: { [rowID = row.id] in finishEditingRight(rowID) },
            continueAfterNewline: continueEditingRight,
            commit: { [rowID = row.id] replacement in
                editRight(rowID, replacement)
            }
        )
        setHorizontalLayout(offset: horizontalOffset, maximumTextWidth: maximumTextWidth)
        setAccessibilityLabel(accessibilityLabel(for: row, movedLeft: movedLeft, movedRight: movedRight))
        setSelected(selected)
        needsLayout = true
        needsDisplay = true
    }

    func setSelected(_ selected: Bool) {
        let changed = self.selected != selected
        self.selected = selected
        setAccessibilitySelected(selected)
        setAccessibilityValue(nil)
        if changed { needsDisplay = true }
    }

    func represents(rowID: DiffRow.ID) -> Bool {
        row?.id == rowID
    }

    func focusEditor(on side: ComparisonSide) -> Bool {
        switch side {
        case .left: return leftText.focusAtStart()
        case .right: return rightText.focusAtStart()
        }
    }

    func selectDifferenceRange(
        on side: ComparisonSide,
        direction: LineDifferenceSelectionDirection
    ) {
        switch side {
        case .left:
            leftText.selectDifferenceRange(direction: direction)
        case .right:
            rightText.selectDifferenceRange(direction: direction)
        }
    }

    func setHorizontalLayout(offset: CGFloat, maximumTextWidth: CGFloat) {
        leftText.setHorizontalLayout(offset: offset, contentWidth: maximumTextWidth)
        rightText.setHorizontalLayout(offset: offset, contentWidth: maximumTextWidth)
    }

    #if DEBUG
        var testHorizontalPaneStates:
            (
                leftOffset: CGFloat,
                rightOffset: CGFloat,
                leftContentWidth: CGFloat,
                rightContentWidth: CGFloat
            )
        {
            (
                leftText.visibleHorizontalOffset,
                rightText.visibleHorizontalOffset,
                leftText.visibleContentWidth,
                rightText.visibleContentWidth
            )
        }

        func testScrollLeftWheel(with event: NSEvent) {
            leftText.testScrollWheel(with: event)
        }

        var testStatusColors: (left: NSColor?, right: NSColor?) {
            guard let row else { return (nil, nil) }
            return (
                statusColor(for: row.kind, side: .left, moved: movedLeft),
                statusColor(for: row.kind, side: .right, moved: movedRight)
            )
        }

        func testRebindIdentity(to row: DiffRow) {
            self.row = row
        }

        func testBeginEditing(on side: ComparisonSide) -> Bool {
            switch side {
            case .left: leftText.testBeginEditing()
            case .right: rightText.testBeginEditing()
            }
        }

        func testInsertNewline(on side: ComparisonSide, selectedRange: NSRange) {
            let editor = side == .left ? leftText : rightText
            editor.testSetSelectedRange(selectedRange)
            editor.testInsertNewline()
        }

        func testSelectedRange(on side: ComparisonSide) -> NSRange {
            switch side {
            case .left: leftText.testSelectedRange
            case .right: rightText.testSelectedRange
            }
        }

        func testIsEditorFocused(on side: ComparisonSide) -> Bool {
            let editor = side == .left ? leftText : rightText
            return window?.firstResponder === editor.testTextView
        }
    #endif

    private func tint(for kind: DiffKind, side: ComparisonSide, moved: Bool) -> NSColor {
        if moved { return Self.movedTint }
        return switch (kind, side) {
        case (.modified, _): Self.modifiedTint
        case (.removed, .left): Self.removedTint
        case (.added, .right): Self.addedTint
        default: .clear
        }
    }

    private func differenceRanges(for row: DiffRow, side: ComparisonSide) -> [NSRange] {
        guard row.kind == .modified,
            let left = row.left?.text,
            let right = row.right?.text
        else { return [] }
        switch side {
        case .left:
            return intralineDifferenceRanges(in: left, comparedWith: right)
        case .right:
            return intralineDifferenceRanges(in: right, comparedWith: left)
        }
    }

    private func statusColor(for kind: DiffKind, side: ComparisonSide, moved: Bool) -> NSColor {
        if selected, kind != .unchanged { return .controlAccentColor }
        if moved { return .systemBlue }
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

    private func accessibilityLabel(for row: DiffRow, movedLeft: Bool, movedRight: Bool) -> String {
        let state: String
        switch row.kind {
        case .unchanged: state = "Unchanged"
        case .modified: state = "Modified"
        case .removed: state = "Removed"
        case .added: state = "Added"
        }
        let left = row.left.map { "left line \($0.number)" } ?? "no left line"
        let right = row.right.map { "right line \($0.number)" } ?? "no right line"
        let moved =
            switch (movedLeft, movedRight) {
            case (true, true): ", moved on both sides"
            case (true, false): ", moved on left"
            case (false, true): ", moved on right"
            case (false, false): ""
            }
        return "\(state)\(moved), \(left), \(right)"
    }

    private func editorAccessibilityLabel(
        for row: DiffRow,
        side: ComparisonSide,
        editable: Bool
    ) -> String {
        let sideName = side == .left ? "Left" : "Right"
        let access = editable ? "editable" : "read-only"
        let line = side == .left ? row.left?.number : row.right?.number
        return line.map { "\(sideName) \(access) line \($0)" } ?? "\(sideName) \(access) new line"
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
        if !isApplyingLock,
            window?.firstResponder === documentView,
            abs(constrained.origin.x - lockedOriginX) > 0.5
        {
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
private final class DiffContextTextView: NSTextView {
    var contextMenuProvider: (() -> NSMenu?)?
    var mergeModeKeyHandler: ((NSEvent) -> Bool)?
    var routesUndoToComparisonHistory = false
    let localUndoManager = UndoManager()

    override var undoManager: UndoManager? { localUndoManager }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?() ?? super.menu(for: event)
    }

    override func keyDown(with event: NSEvent) {
        let hasModifier = !event.modifierFlags
            .intersection([.shift, .control, .command, .option])
            .isEmpty
        if hasModifier || mergeModeKeyHandler?(event) != true {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class DiffLineTextView: NSView, NSTextViewDelegate, NSMenuDelegate {
    private enum ContextAction: Int {
        case copyToOther
        case copyFromOther
        case copyLeftDifference
        case copyRightDifference
        case selectLineDifference
        case selectPreviousLineDifference
        case goToMovedLine
        case undo
        case redo
        case cut
        case copy
        case copyWithLineNumber
        case paste
        case openDefault
        case revealInFinder
    }

    private let scrollView = LockedLineScrollView()
    private let clipView = LockedLineClipView()
    private let textView: DiffContextTextView = {
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
        let view = DiffContextTextView(frame: .zero, textContainer: container)
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .labelColor
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 28)
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = false
        view.autoresizingMask = []
        view.setAccessibilityElement(true)
        view.setAccessibilityEnabled(true)
        return view
    }()
    private var horizontalOffset: CGFloat = 0
    private var contentWidth: CGFloat = 0
    private var committedValue = ""
    private var differenceRanges: [NSRange] = []
    private var selectedDifferenceRange: NSRange?
    private var activateHandler: (() -> Void)?
    private var commitHandler: ((String) -> Void)?
    private var finishHandler: (() -> Void)?
    private var continueAfterNewlineHandler: ((Int) -> Void)?
    private var contextMenuRow: DiffRow?
    private var contextMenuSide: ComparisonSide?
    private var contextMenuActions: DiffContextMenuActions?
    private var contextMenuItemCount = 0
    private var pasteboard = NSPasteboard.general

    var stringValue: String {
        get { textView.string }
        set {
            guard textView.string != newValue else { return }
            textView.string = newValue
            committedValue = newValue
        }
    }

    #if DEBUG
        var testSelectedRange: NSRange { textView.selectedRange() }
        var testCanUndo: Bool { textView.undoManager?.canUndo == true }
        var testTextView: NSTextView { textView }
        var visibleHorizontalOffset: CGFloat { clipView.bounds.origin.x }
        var visibleContentWidth: CGFloat { contentWidth }

        func testSeedUndoMutation(_ replacement: String) {
            textView.undoManager?.registerUndo(withTarget: textView) { textView in
                textView.string = replacement
            }
        }

        func testUndo() {
            textView.undoManager?.undo()
        }

        func testSetSelectedRange(_ range: NSRange) {
            textView.setSelectedRange(range)
        }

        func testInsertNewline() {
            _ = self.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        }

        func testBeginEditing() -> Bool {
            guard textView.window?.makeFirstResponder(textView) == true else { return false }
            textDidBeginEditing(Notification(name: NSText.didBeginEditingNotification, object: textView))
            return true
        }

        func testScrollWheel(with event: NSEvent) {
            scrollView.scrollWheel(with: event)
        }

        func testUsePasteboard(_ pasteboard: NSPasteboard) {
            self.pasteboard = pasteboard
        }
    #endif

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
        let menu = NSMenu(title: "Text Comparison")
        menu.autoenablesItems = false
        menu.allowsContextMenuPlugIns = false
        menu.delegate = self
        textView.menu = menu
        textView.contextMenuProvider = { [weak self, weak menu] in
            guard let self, let menu else { return nil }
            self.menuNeedsUpdate(menu)
            return menu
        }
        textView.mergeModeKeyHandler = { [weak self] event in
            guard let self, let row = contextMenuRow else { return false }
            return contextMenuActions?.handleMergeModeKey(event.keyCode, row.id) == true
        }
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
        activate: @escaping () -> Void,
        finish: @escaping () -> Void,
        continueAfterNewline: @escaping (Int) -> Void,
        commit: @escaping (String) -> Void
    ) {
        textView.isEditable = editable
        textView.isSelectable = true
        clipView.allowsVerticalEditing = editable
        activateHandler = activate
        commitHandler = editable ? commit : nil
        finishHandler = editable ? finish : nil
        continueAfterNewlineHandler = editable ? continueAfterNewline : nil
        textView.setAccessibilityLabel(accessibilityLabel)
    }

    fileprivate func configureContextMenu(
        row: DiffRow,
        side: ComparisonSide,
        actions: DiffContextMenuActions
    ) {
        contextMenuRow = row
        contextMenuSide = side
        contextMenuActions = actions
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let row = contextMenuRow,
            let side = contextMenuSide,
            let actions = contextMenuActions
        else { return }
        actions.activate(row.id, side)
        menu.removeAllItems()

        let otherSideName = side == .left ? "Right" : "Left"
        addItem(
            to: menu,
            title: "Copy to \(otherSideName)",
            action: .copyToOther,
            keyEquivalent: side == .left ? "\u{F703}" : "\u{F702}",
            modifiers: [.option],
            enabled: row.kind != .unchanged
                && actions.canMerge(
                    side == .left ? .leftToRight : .rightToLeft
                )
        )
        addItem(
            to: menu,
            title: "Copy from \(otherSideName)",
            action: .copyFromOther,
            keyEquivalent: side == .left ? "\u{F702}" : "\u{F703}",
            modifiers: [.option, .shift],
            enabled: row.kind != .unchanged
                && actions.canMerge(
                    side == .left ? .rightToLeft : .leftToRight
                )
        )
        menu.addItem(.separator())

        addDisabledItem(to: menu, title: "Copy Selected Lines to \(otherSideName)")
        addDisabledItem(to: menu, title: "Copy Selected Lines from \(otherSideName)")
        menu.addItem(.separator())

        addItem(
            to: menu,
            title: "Copy Selected Diff (Left) to Clipboard",
            action: .copyLeftDifference,
            keyEquivalent: "1",
            modifiers: [.command],
            enabled: row.kind != .unchanged
        )
        addItem(
            to: menu,
            title: "Copy Selected Diff (Right) to Clipboard",
            action: .copyRightDifference,
            keyEquivalent: "2",
            modifiers: [.command],
            enabled: row.kind != .unchanged
        )
        menu.addItem(.separator())

        addItem(
            to: menu,
            title: "Select Line Difference",
            action: .selectLineDifference,
            keyEquivalent: "\u{F707}",
            enabled: actions.canSelectLineDifference()
        )
        addItem(
            to: menu,
            title: "Select Previous Line Difference",
            action: .selectPreviousLineDifference,
            keyEquivalent: "\u{F707}",
            modifiers: .shift,
            enabled: actions.canSelectLineDifference()
        )
        addUnsupportedSubmenu(
            to: menu,
            title: "Add to Filters",
            items: ["Add to Display Filter", "Add to Line Filters", "Add to Substitution Filters"]
        )
        menu.addItem(.separator())

        addItem(to: menu, title: "Undo", action: .undo, enabled: actions.canUndo())
        addItem(to: menu, title: "Redo", action: .redo, enabled: actions.canRedo())
        menu.addItem(.separator())

        let selectionExists = textView.selectedRange().length > 0
        addItem(to: menu, title: "Cut", action: .cut, enabled: textView.isEditable && selectionExists)
        addItem(to: menu, title: "Copy", action: .copy, enabled: selectionExists)
        addItem(
            to: menu,
            title: "Copy with Line Number",
            action: .copyWithLineNumber,
            keyEquivalent: "c",
            modifiers: [.command, .shift],
            enabled: NumberedRowCopyCommand.isEnabled(row: row, side: side)
        )
        addItem(
            to: menu,
            title: "Paste",
            action: .paste,
            enabled: textView.isEditable && NSPasteboard.general.canReadItem(withDataConformingToTypes: [UTType.plainText.identifier])
        )
        menu.addItem(.separator())

        addUnsupportedSubmenu(to: menu, title: "Scripts", items: ["< Empty >"])
        menu.addItem(.separator())

        addDisabledItem(to: menu, title: "Go to...", keyEquivalent: "g", modifiers: [.command])
        addDisabledItem(to: menu, title: "Go to Definition", keyEquivalent: "\u{F70F}")
        addItem(
            to: menu,
            title: "Go to Moved Line Between Left and Right",
            action: .goToMovedLine,
            enabled: actions.canGoToMovedLine(row.id, side)
        )
        menu.addItem(.separator())

        let hasFile = actions.fileURL(side) != nil
        let openMenu = NSMenu(title: "Open")
        openMenu.autoenablesItems = false
        addItem(
            to: openMenu,
            title: "With Registered Application",
            action: .openDefault,
            enabled: hasFile
        )
        addDisabledItem(to: openMenu, title: "With External Editor")
        addDisabledItem(to: openMenu, title: "With...")
        addItem(
            to: openMenu,
            title: "Open Parent Folder...",
            action: .revealInFinder,
            enabled: hasFile
        )
        let openItem = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
        openItem.submenu = openMenu
        menu.addItem(openItem)
        addDisabledItem(to: menu, title: "Shell Menu")
        contextMenuItemCount = menu.items.count
    }

    func menuWillOpen(_ menu: NSMenu) {
        while menu.items.count > contextMenuItemCount {
            menu.removeItem(at: menu.items.count - 1)
        }
    }

    @objc private func performContextAction(_ sender: NSMenuItem) {
        guard let action = ContextAction(rawValue: sender.tag),
            let row = contextMenuRow,
            let side = contextMenuSide,
            let actions = contextMenuActions
        else { return }
        switch action {
        case .copyToOther:
            actions.merge(row.id, side == .left ? .leftToRight : .rightToLeft)
        case .copyFromOther:
            actions.merge(row.id, side == .left ? .rightToLeft : .leftToRight)
        case .copyLeftDifference:
            copyDifferenceToPasteboard(row.left?.text ?? "")
        case .copyRightDifference:
            copyDifferenceToPasteboard(row.right?.text ?? "")
        case .selectLineDifference:
            actions.selectLineDifference()
        case .selectPreviousLineDifference:
            actions.selectPreviousLineDifference()
        case .goToMovedLine:
            actions.goToMovedLine(row.id, side)
        case .undo:
            actions.undo()
        case .redo:
            actions.redo()
        case .cut:
            textView.cut(nil)
        case .copy:
            textView.copy(nil)
        case .copyWithLineNumber:
            copyNumberedRowToPasteboard(row, side: side)
        case .paste:
            textView.paste(nil)
        case .openDefault:
            if let url = actions.fileURL(side) { NSWorkspace.shared.open(url) }
        case .revealInFinder:
            if let url = actions.fileURL(side) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func addItem(
        to menu: NSMenu,
        title: String,
        action: ContextAction,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        enabled: Bool
    ) {
        let item = NSMenuItem(
            title: title,
            action: #selector(performContextAction(_:)),
            keyEquivalent: keyEquivalent
        )
        item.target = self
        item.tag = action.rawValue
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func addDisabledItem(
        to menu: NSMenu,
        title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addUnsupportedSubmenu(to menu: NSMenu, title: String, items: [String]) {
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        for title in items {
            addDisabledItem(to: submenu, title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func copyDifferenceToPasteboard(_ text: String) {
        do {
            try ClipboardTextWriter.write(text, to: pasteboard)
        } catch {
            presentCopyError(error, messageText: "Could not copy difference")
        }
    }

    private func copyNumberedRowToPasteboard(_ row: DiffRow, side: ComparisonSide) {
        let request = NumberedCopyRequestCoordinator.begin()
        let pasteboardChangeCount = pasteboard.changeCount
        let lineNumber = side == .left ? row.id.leftNumber : row.id.rightNumber
        let visibleText = textView.string
        Task { [weak self] in
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    guard let lineNumber else { throw NumberedTextCopyError.emptySelection }
                    let visibleRow = DiffRow(
                        left: side == .left
                            ? DiffLine(number: lineNumber, text: visibleText)
                            : nil,
                        right: side == .right
                            ? DiffLine(number: lineNumber, text: visibleText)
                            : nil,
                        kind: row.kind
                    )
                    return try NumberedRowCopyCommand.text(row: visibleRow, side: side)
                }.value
                guard let self,
                    NumberedCopyRequestCoordinator.isCurrent(request),
                    pasteboard.changeCount == pasteboardChangeCount
                else { return }
                try ClipboardTextWriter.write(text, to: pasteboard)
            } catch {
                guard let self, NumberedCopyRequestCoordinator.isCurrent(request) else { return }
                presentCopyError(
                    error,
                    messageText: "Could not copy line with its number"
                )
            }
        }
    }

    private func presentCopyError(_ error: Error, messageText: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = messageText
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    func setDifferenceRanges(_ ranges: [NSRange]) {
        differenceRanges = ranges
        selectedDifferenceRange = nil
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        for range in ranges {
            let visibleRange = NSIntersectionRange(range, fullRange)
            guard visibleRange.length > 0 else { continue }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemOrange.withAlphaComponent(0.48),
                forCharacterRange: visibleRange
            )
        }
    }

    func selectDifferenceRange(direction: LineDifferenceSelectionDirection) {
        guard !differenceRanges.isEmpty,
            textView.window?.makeFirstResponder(textView) == true
        else { return }
        let selection = textView.selectedRange()
        guard
            let differenceRange = lineDifferenceRange(
                in: differenceRanges,
                from: selection,
                direction: direction,
                advancesFromSelection: selectedDifferenceRange == selection
            )
        else { return }
        textView.setSelectedRange(differenceRange)
        selectedDifferenceRange = differenceRange
        textView.scrollRangeToVisible(differenceRange)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        commitIfChanged()
        finishHandler?()
        textView.localUndoManager.removeAllActions()
        textView.routesUndoToComparisonHistory = false
        differenceRanges = []
        selectedDifferenceRange = nil
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        commitHandler = nil
        activateHandler = nil
        finishHandler = nil
        continueAfterNewlineHandler = nil
        contextMenuRow = nil
        contextMenuSide = nil
        contextMenuActions = nil
    }

    func textDidChange(_ notification: Notification) {
        commitIfChanged()
    }

    func textDidBeginEditing(_ notification: Notification) {
        activateHandler?()
    }

    func textDidEndEditing(_ notification: Notification) {
        commitIfChanged()
        finishHandler?()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard
            commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        else {
            return false
        }
        guard let textView = textView as? DiffContextTextView else { return false }
        let selectedRange = textView.selectedRange()
        textView.breakUndoCoalescing()
        textView.routesUndoToComparisonHistory = true
        textView.localUndoManager.disableUndoRegistration()
        textView.insertText("\n", replacementRange: selectedRange)
        textView.localUndoManager.enableUndoRegistration()
        textView.breakUndoCoalescing()
        let caret = selectedRange.location + 1
        commitIfChanged()
        let prefix = (textView.string as NSString).substring(to: caret)
        let lineOffset = prefix.reduce(into: 0) { count, character in
            switch character {
            case "\n", "\r", "\r\n":
                count += 1
            default:
                break
            }
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

#if DEBUG
    @MainActor
    final class DiffTableHorizontalScrollTestHarness {
        struct VisibleCell {
            let row: Int
            let identity: ObjectIdentifier
            let leftOffset: CGFloat
            let rightOffset: CGFloat
            let leftContentWidth: CGFloat
            let rightContentWidth: CGFloat
        }

        private let coordinator: DiffTableView.Coordinator
        private let container: DiffTableContainerView
        private let window: NSWindow
        private let rootView: NSView
        private var rowsRevision = 0

        private final class WindowScrollWheelEvent: NSEvent {
            private weak var targetWindow: NSWindow?
            private let targetWindowNumber: Int
            private let targetLocation: NSPoint
            private let horizontalDelta: CGFloat

            init(window: NSWindow, windowNumber: Int, location: NSPoint, deltaX: CGFloat) {
                targetWindow = window
                targetWindowNumber = windowNumber
                targetLocation = location
                horizontalDelta = deltaX
                super.init()
            }

            required init?(coder: NSCoder) {
                nil
            }

            override var type: NSEvent.EventType { .scrollWheel }
            override var window: NSWindow? { targetWindow }
            override var windowNumber: Int { targetWindowNumber }
            override var locationInWindow: NSPoint { targetLocation }
            override var scrollingDeltaX: CGFloat { horizontalDelta }
            override var scrollingDeltaY: CGFloat { 0 }
            override var hasPreciseScrollingDeltas: Bool { true }
            override var phase: NSEvent.Phase { [] }
            override var momentumPhase: NSEvent.Phase { [] }
        }

        init(rows: [DiffRow], width: CGFloat, height: CGFloat, maximumTextWidth: CGFloat) {
            let actions = DiffContextMenuActions(
                activate: { _, _ in },
                canMerge: { _ in false },
                merge: { _, _ in },
                canSelectLineDifference: { false },
                selectLineDifference: {},
                selectPreviousLineDifference: {},
                canGoToMovedLine: { _, _ in false },
                goToMovedLine: { _, _ in },
                canUndo: { false },
                undo: {},
                canRedo: { false },
                redo: {},
                fileURL: { _ in nil },
                handleMergeModeKey: { _, _ in false }
            )
            let view = DiffTableView(
                rows: rows,
                rowsRevision: 0,
                maximumLineColumns: 0,
                differenceLocations: DifferenceLocations(),
                movedRows: MovedRowMap(),
                selectedDifferenceID: nil,
                selectedDifferenceRevealRevision: 0,
                focusRequest: nil,
                isFocusRequestCurrent: { _ in true },
                leftEditable: false,
                rightEditable: false,
                navigationRow: nil,
                navigationRevision: 0,
                viewportChanged: { _ in },
                selectDifference: { _ in },
                activateSide: { _ in },
                editLeft: { _, _ in },
                editRight: { _, _ in },
                finishEditingLeft: { _ in },
                finishEditingRight: { _ in },
                continueEditing: { _, _ in },
                contextMenuActions: actions
            )
            coordinator = view.makeCoordinator()
            container = view.makeNSView(coordinator: coordinator)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            rootView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            window.contentView = rootView
            container.frame = rootView.bounds
            container.autoresizingMask = [.width, .height]
            rootView.addSubview(container)
            coordinator.tableView?.reloadData()
            layout()
            container.maximumTextWidth = maximumTextWidth
            layout()
        }

        var horizontalOffset: CGFloat { container.horizontalOffset }
        var maximumOffset: CGFloat { container.testMaximumOffset }
        var maximumTextWidth: CGFloat { container.maximumTextWidth }

        func scrollHorizontally(by delta: CGFloat) {
            container.updateHorizontalOffset(by: delta)
            layout()
        }

        func scrollWithScroller(to offset: CGFloat) -> Bool {
            let maximumOffset = container.testMaximumOffset
            container.horizontalScroller.doubleValue =
                maximumOffset > 0
                ? Double(offset / maximumOffset)
                : 0
            let didSend = container.horizontalScroller.sendAction(
                container.horizontalScroller.action,
                to: container.horizontalScroller.target
            )
            layout()
            return didSend
        }

        func scrollWithWheel(by delta: CGFloat, fromVisiblePane: Bool = false) -> Bool {
            guard
                let event = CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .pixel,
                    wheelCount: 2,
                    wheel1: 0,
                    wheel2: Int32(-delta.rounded()),
                    wheel3: 0
                ).flatMap(NSEvent.init(cgEvent:))
            else { return false }
            if fromVisiblePane {
                guard let cell = firstVisibleCell() else { return false }
                cell.testScrollLeftWheel(with: event)
            } else {
                container.scrollView.scrollWheel(with: event)
            }
            layout()
            return true
        }

        func scrollWithWindowWheelFromVisiblePane(by delta: CGFloat) -> Bool {
            guard let cell = firstVisibleCell() else { return false }
            let location = cell.convert(
                NSPoint(x: DiffTableCellView.numberAreaWidth + 16, y: cell.bounds.midY),
                to: nil
            )
            let wasVisible = window.isVisible
            if !wasVisible { window.orderBack(nil) }
            window.sendEvent(
                WindowScrollWheelEvent(
                    window: window,
                    windowNumber: window.windowNumber,
                    location: location,
                    deltaX: -delta
                ))
            if !wasVisible { window.orderOut(nil) }
            layout()
            return true
        }

        func reload(rows: [DiffRow], maximumTextWidth: CGFloat) {
            rowsRevision &+= 1
            coordinator.setRows(
                rows,
                revision: rowsRevision,
                differenceLocations: DifferenceLocations(),
                movedRows: MovedRowMap()
            )
            coordinator.tableView?.reloadData()
            layout()
            container.maximumTextWidth = maximumTextWidth
            layout()
        }

        func scrollRowToVisible(_ row: Int) {
            coordinator.tableView?.scrollRowToVisible(row)
            layout()
        }

        func resize(to width: CGFloat) {
            rootView.frame.size.width = width
            container.frame.size.width = width
            layout()
        }

        func setMaximumTextWidth(_ width: CGFloat) {
            container.maximumTextWidth = width
            layout()
        }

        func visibleCells() -> [VisibleCell] {
            guard let tableView = coordinator.tableView else { return [] }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return [] }
            return (visibleRows.location..<min(NSMaxRange(visibleRows), tableView.numberOfRows)).compactMap { row in
                guard
                    let cell = tableView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                    ) as? DiffTableCellView
                else { return nil }
                let state = cell.testHorizontalPaneStates
                return VisibleCell(
                    row: row,
                    identity: ObjectIdentifier(cell),
                    leftOffset: state.leftOffset,
                    rightOffset: state.rightOffset,
                    leftContentWidth: state.leftContentWidth,
                    rightContentWidth: state.rightContentWidth
                )
            }
        }

        func close() {
            window.makeFirstResponder(nil)
            container.removeFromSuperview()
            window.contentView = nil
            window.close()
        }

        private func firstVisibleCell() -> DiffTableCellView? {
            guard let tableView = coordinator.tableView else { return nil }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return nil }
            return tableView.view(
                atColumn: 0,
                row: visibleRows.location,
                makeIfNecessary: false
            ) as? DiffTableCellView
        }

        private func layout() {
            rootView.layoutSubtreeIfNeeded()
            container.layout()
            container.layoutSubtreeIfNeeded()
            container.scrollView.layoutSubtreeIfNeeded()
            container.scrollView.documentView?.layoutSubtreeIfNeeded()
            container.displayIfNeeded()
        }
    }

    @MainActor
    final class AccessibilityCommandTestHarness {
        struct VisibleCellState {
            let row: Int
            let identity: ObjectIdentifier
            let isSelected: Bool
            let leftStatusColor: NSColor?
            let rightStatusColor: NSColor?
        }

        struct RowState {
            let role: NSAccessibility.Role?
            let label: String?
            let value: String?
            let isSelected: Bool
            let lineNumbers: [String]
            let editors: [ElementState]
        }

        struct ElementState {
            let role: NSAccessibility.Role?
            let label: String?
            let value: String?
            let isEnabled: Bool
            let isValueSettable: Bool
        }

        struct SliderState {
            let role: NSAccessibility.Role?
            let label: String?
            let value: Double?
            let isEnabled: Bool
            let isValueSettable: Bool
            let isIncrementAllowed: Bool
            let isDecrementAllowed: Bool
        }

        struct MenuItemState {
            let role: NSAccessibility.Role?
            let label: String?
            let isEnabled: Bool
        }

        struct CommandState {
            let role: NSAccessibility.Role?
            let label: String?
            let isEnabled: Bool
        }

        struct NavigationCall: Equatable {
            let row: Int
            let side: ComparisonSide
            let activatesEditor: Bool
        }

        @MainActor
        final class Row {
            private let harness: Table
            private let rowIndex: Int

            init(
                row: DiffRow,
                selected: Bool,
                movedLeft: Bool = false,
                movedRight: Bool = false,
                leftEditable: Bool = true,
                rightEditable: Bool = true
            ) {
                harness = Table(
                    rows: [row],
                    selectedDifferenceID: selected ? row.id : nil,
                    movedLeft: movedLeft,
                    movedRight: movedRight,
                    leftEditable: leftEditable,
                    rightEditable: rightEditable
                )
                rowIndex = 0
            }

            var state: RowState {
                harness.rowState(at: rowIndex)
            }

            func setSelected(_ selected: Bool) {
                harness.setSelected(selected, at: rowIndex)
            }

            func close() {
                harness.close()
            }
        }

        @MainActor
        final class Table {
            private let coordinator: DiffTableView.Coordinator
            private let container: DiffTableContainerView
            private let window: NSWindow
            private var rows: [DiffRow]
            private let movedRows: MovedRowMap
            private let leftEditable: Bool
            private let rightEditable: Bool
            private let viewportChanged: (LocationViewport) -> Void
            private var rowsRevision = 0

            init(
                rows: [DiffRow],
                selectedDifferenceID: DiffRow.ID? = nil,
                movedLeft: Bool = false,
                movedRight: Bool = false,
                leftEditable: Bool = true,
                rightEditable: Bool = true,
                viewportChanged: @escaping (LocationViewport) -> Void = { _ in }
            ) {
                let movedRows = AccessibilityCommandTestHarness.movedRows(
                    rows: rows,
                    movedLeft: movedLeft,
                    movedRight: movedRight
                )
                self.rows = rows
                self.movedRows = movedRows
                self.leftEditable = leftEditable
                self.rightEditable = rightEditable
                self.viewportChanged = viewportChanged
                let view = Self.makeView(
                    rows: rows,
                    movedRows: movedRows,
                    selectedDifferenceID: selectedDifferenceID,
                    selectedDifferenceRevealRevision: 0,
                    leftEditable: leftEditable,
                    rightEditable: rightEditable,
                    viewportChanged: viewportChanged
                )
                coordinator = view.makeCoordinator()
                container = view.makeNSView(coordinator: coordinator)
                window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 800, height: 160),
                    styleMask: [],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = container
                coordinator.tableView?.reloadData()
                layout()
                coordinator.selectedDifferenceID = selectedDifferenceID
                coordinator.synchronizeTableSelection()
                coordinator.refreshVisibleRows(for: selectedDifferenceID.map { [$0] } ?? [])
                layout()
                coordinator.reportViewport()
            }

            var tableRole: NSAccessibility.Role? {
                coordinator.tableView?.accessibilityRole()
            }

            var accessibilityRowRoles: [NSAccessibility.Role?] {
                let rows = (coordinator.tableView as NSAccessibilityProtocol?)?.accessibilityRows() ?? []
                return rows.map(Self.dynamicAccessibilityRole)
            }

            var selectedAccessibilityRowCount: Int {
                (coordinator.tableView as NSAccessibilityProtocol?)?.accessibilitySelectedRows()?.count ?? 0
            }

            var selectedAccessibilityRowRoles: [NSAccessibility.Role?] {
                let rows = (coordinator.tableView as NSAccessibilityProtocol?)?.accessibilitySelectedRows() ?? []
                return rows.map(Self.dynamicAccessibilityRole)
            }

            var selectedRow: Int { coordinator.tableView?.selectedRow ?? -1 }
            var selectedRowIndexes: IndexSet { coordinator.tableView?.selectedRowIndexes ?? [] }

            var visibleRows: Range<Int> {
                guard let tableView = coordinator.tableView else { return 0..<0 }
                let visible = tableView.rows(in: tableView.visibleRect)
                guard visible.location != NSNotFound else { return 0..<0 }
                return visible.location..<min(NSMaxRange(visible), tableView.numberOfRows)
            }

            var visibleCells: [VisibleCellState] {
                visibleRows.compactMap { row in
                    guard let cell = cell(at: row, makeIfNecessary: false) else { return nil }
                    let statusColors = cell.testStatusColors
                    return VisibleCellState(
                        row: row,
                        identity: ObjectIdentifier(cell),
                        isSelected: cell.isAccessibilitySelected(),
                        leftStatusColor: statusColors.left,
                        rightStatusColor: statusColors.right
                    )
                }
            }

            func update(
                selectedDifferenceID: DiffRow.ID?,
                selectedDifferenceRevealRevision: Int
            ) {
                let view = Self.makeView(
                    rows: rows,
                    movedRows: movedRows,
                    selectedDifferenceID: selectedDifferenceID,
                    selectedDifferenceRevealRevision: selectedDifferenceRevealRevision,
                    leftEditable: leftEditable,
                    rightEditable: rightEditable,
                    viewportChanged: viewportChanged
                )
                view.updateNSView(container, coordinator: coordinator)
                layout()
            }

            func scrollRowToVisible(_ row: Int) {
                coordinator.tableView?.scrollRowToVisible(row)
                layout()
                coordinator.reportViewport()
            }

            func isCellSelected(at row: Int) -> Bool {
                cell(at: row, makeIfNecessary: false)?.isAccessibilitySelected() ?? false
            }

            func rowState(at index: Int) -> RowState {
                guard let cell = cell(at: index) else {
                    preconditionFailure("Expected visible accessibility row")
                }
                let editors = textViews(in: cell)
                return RowState(
                    role: cell.accessibilityRole(),
                    label: cell.accessibilityLabel(),
                    value: cell.accessibilityValue() as? String,
                    isSelected: cell.isAccessibilitySelected(),
                    lineNumbers: cell.subviews.compactMap { ($0 as? NSTextField)?.stringValue },
                    editors: editors.map {
                        ElementState(
                            role: $0.accessibilityRole(),
                            label: $0.accessibilityLabel(),
                            value: $0.accessibilityValue(),
                            isEnabled: $0.isAccessibilityEnabled(),
                            isValueSettable: $0.isAccessibilitySelectorAllowed(
                                #selector(NSAccessibilityProtocol.setAccessibilityValue(_:))
                            )
                        )
                    }
                )
            }

            func setSelected(_ selected: Bool, at index: Int) {
                cell(at: index)?.setSelected(selected)
            }

            func captureLineDifferenceSelection(
                rowID: DiffRow.ID,
                side: ComparisonSide = .left,
                direction: LineDifferenceSelectionDirection = .next
            ) -> () -> Bool {
                coordinator.testCaptureLineDifferenceSelection(
                    on: side,
                    rowID: rowID,
                    direction: direction
                )
            }

            func capturePaneFocus(
                rowID: DiffRow.ID,
                side: ComparisonSide = .left
            ) -> () -> Bool {
                coordinator.testCapturePaneFocus(on: side, rowID: rowID)
            }

            func advanceLineDifferenceSelectionRequest() {
                coordinator.testAdvanceLineDifferenceSelectionRevision()
            }

            func advancePaneFocusRequest() {
                coordinator.testAdvancePaneFocusRevision()
            }

            func setPendingEditorFocus(side: ComparisonSide = .left, lineNumber: Int) {
                coordinator.testSetPendingEditorFocus(side: side, lineNumber: lineNumber)
            }

            func capturePendingEditorFocus() -> (() -> Bool)? {
                coordinator.testCapturePendingEditorFocus()
            }

            var pendingEditorFocusLineNumber: Int? {
                coordinator.testPendingEditorFocusLineNumber
            }

            func reuseRows(_ rows: [DiffRow], advanceRevision: Bool = true) {
                if advanceRevision { rowsRevision &+= 1 }
                self.rows = rows
                coordinator.setRows(
                    rows,
                    revision: rowsRevision,
                    differenceLocations: DifferenceLocations(
                        rows: rows,
                        differenceRowIndices: rows.indices
                            .filter { rows[$0].kind != .unchanged }
                            .map(UInt32.init)
                    ),
                    movedRows: movedRows
                )
                coordinator.tableView?.reloadData()
                layout()
            }

            func rebindVisibleCellIdentity(at index: Int, to row: DiffRow) {
                cell(at: index)?.testRebindIdentity(to: row)
            }

            func close() {
                window.makeFirstResponder(nil)
                window.contentView = nil
                window.close()
            }

            private func cell(
                at index: Int,
                makeIfNecessary: Bool = true
            ) -> DiffTableCellView? {
                coordinator.tableView?.view(
                    atColumn: 0,
                    row: index,
                    makeIfNecessary: makeIfNecessary
                ) as? DiffTableCellView
            }

            private static func makeView(
                rows: [DiffRow],
                movedRows: MovedRowMap,
                selectedDifferenceID: DiffRow.ID?,
                selectedDifferenceRevealRevision: Int,
                leftEditable: Bool,
                rightEditable: Bool,
                viewportChanged: @escaping (LocationViewport) -> Void
            ) -> DiffTableView {
                DiffTableView(
                    rows: rows,
                    rowsRevision: 0,
                    maximumLineColumns: 80,
                    differenceLocations: DifferenceLocations(
                        rows: rows,
                        differenceRowIndices: rows.indices
                            .filter { rows[$0].kind != .unchanged }
                            .map(UInt32.init)
                    ),
                    movedRows: movedRows,
                    selectedDifferenceID: selectedDifferenceID,
                    selectedDifferenceRevealRevision: selectedDifferenceRevealRevision,
                    focusRequest: nil,
                    isFocusRequestCurrent: { _ in true },
                    leftEditable: leftEditable,
                    rightEditable: rightEditable,
                    navigationRow: nil,
                    navigationRevision: 0,
                    viewportChanged: viewportChanged,
                    selectDifference: { _ in },
                    activateSide: { _ in },
                    editLeft: { _, _ in },
                    editRight: { _, _ in },
                    finishEditingLeft: { _ in },
                    finishEditingRight: { _ in },
                    continueEditing: { _, _ in },
                    contextMenuActions: noOpActions
                )
            }

            private static func dynamicAccessibilityRole(
                of element: Any
            ) -> NSAccessibility.Role? {
                let selector = NSSelectorFromString("accessibilityRoleAttribute")
                guard let object = element as? NSObjectProtocol,
                    object.responds(to: selector),
                    let result = object.perform(selector)
                else { return nil }
                let value = result.takeUnretainedValue()
                if let role = value as? NSAccessibility.Role { return role }
                guard let rawValue = value as? String else { return nil }
                return NSAccessibility.Role(rawValue: rawValue)
            }

            private func layout() {
                container.frame = NSRect(x: 0, y: 0, width: 800, height: 160)
                container.layoutSubtreeIfNeeded()
                container.scrollView.documentView?.layoutSubtreeIfNeeded()
            }
        }

        @MainActor
        final class ContextMenu {
            private let lineView = DiffLineTextView()
            private let menu = NSMenu(title: "Text Comparison")
            private let pasteboard = NSPasteboard(
                name: NSPasteboard.Name("MacMergeTests.\(UUID().uuidString)")
            )

            init(row: DiffRow, side: ComparisonSide, model: ComparisonModel) {
                menu.autoenablesItems = false
                lineView.testUsePasteboard(pasteboard)
                lineView.stringValue = side == .left ? row.left?.text ?? "" : row.right?.text ?? ""
                lineView.configureContextMenu(
                    row: row,
                    side: side,
                    actions: AccessibilityCommandTestHarness.actions(for: model)
                )
                lineView.menuNeedsUpdate(menu)
            }

            func item(titled title: String) -> MenuItemState? {
                let index = menu.indexOfItem(withTitle: title)
                guard index >= 0, let item = menu.item(at: index) else { return nil }
                return MenuItemState(
                    role: item.accessibilityRole(),
                    label: item.accessibilityLabel(),
                    isEnabled: item.isEnabled
                )
            }

            @discardableResult
            func performItem(titled title: String) -> Bool {
                let index = menu.indexOfItem(withTitle: title)
                guard index >= 0,
                    let item = menu.item(at: index),
                    item.isEnabled,
                    item.action != nil
                else { return false }
                if item.accessibilityPerformPress() { return true }
                guard let action = item.action else { return false }
                return NSApplication.shared.sendAction(action, to: item.target, from: item)
            }

            var copiedText: String? {
                pasteboard.string(forType: .string)
            }

            func setVisibleText(_ text: String) {
                lineView.stringValue = text
            }

            func waitForCopiedText() async -> String? {
                for _ in 0..<100 {
                    if let copiedText { return copiedText }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return copiedText
            }
        }

        @MainActor
        final class LineDifferenceEditor {
            private let lineView = DiffLineTextView()
            private let window: NSWindow
            private(set) var continuationOffsets: [Int] = []

            init(text: String, ranges: [NSRange]) {
                window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 400, height: 28),
                    styleMask: [],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = lineView
                configure(text: text, ranges: ranges)
                window.layoutIfNeeded()
            }

            var selectedRange: NSRange { lineView.testSelectedRange }
            var text: String { lineView.stringValue }
            var canUndo: Bool { lineView.testCanUndo }

            func select(_ direction: LineDifferenceSelectionDirection) {
                lineView.selectDifferenceRange(direction: direction)
            }

            func reuse(text: String, ranges: [NSRange]) {
                lineView.prepareForReuse()
                configure(text: text, ranges: ranges)
            }

            func seedUndoMutation(_ replacement: String) {
                lineView.testSeedUndoMutation(replacement)
            }

            func undo() {
                lineView.testUndo()
            }

            func setSelectedRange(_ range: NSRange) {
                lineView.testSetSelectedRange(range)
            }

            func insertNewline() {
                lineView.testInsertNewline()
            }

            func close() {
                window.makeFirstResponder(nil)
                window.contentView = nil
                window.close()
            }

            private func configure(text: String, ranges: [NSRange]) {
                lineView.stringValue = text
                lineView.setDifferenceRanges(ranges)
                lineView.configureEditable(
                    true,
                    accessibilityLabel: "Test editable line",
                    activate: {},
                    finish: {},
                    continueAfterNewline: { [weak self] in self?.continuationOffsets.append($0) },
                    commit: { _ in }
                )
            }
        }

        @MainActor
        final class LocationPaneCommands {
            private let view = LocationPaneInteractionNSView()
            private(set) var navigations: [NavigationCall] = []
            private(set) var goToLines: [(line: Int, side: ComparisonSide)] = []
            private(set) var moveCursorValues: [Bool] = []
            private(set) var movedBlockValues: [Bool] = []

            init(
                rows: [DiffRow],
                currentRow: Int = 0,
                movesCursorOnClick: Bool,
                detectsMovedBlocks: Bool
            ) {
                view.map = LocationMap(rows: rows)
                view.contextRow = currentRow
                view.movesCursorOnClick = movesCursorOnClick
                view.detectsMovedBlocks = detectsMovedBlocks
                view.lineNumber = { row, side in
                    guard rows.indices.contains(row) else { return nil }
                    return side == .left ? rows[row].left?.number : rows[row].right?.number
                }
                view.exactLineNumber = view.lineNumber
                view.navigate = { [weak self] row, side, activatesEditor in
                    self?.navigations.append(
                        NavigationCall(
                            row: row,
                            side: side,
                            activatesEditor: activatesEditor
                        ))
                }
                view.goToLine = { [weak self] line, side in
                    self?.goToLines.append((line, side))
                }
                view.setMovesCursorOnClick = { [weak self] in self?.moveCursorValues.append($0) }
                view.setDetectMovedBlocks = { [weak self] in self?.movedBlockValues.append($0) }
                view.updateAccessibilityActions()
            }

            var role: NSAccessibility.Role? { view.accessibilityRole() }
            var label: String? { view.accessibilityLabel() }
            var actionNames: [String] { view.accessibilityCustomActions()?.map(\.name) ?? [] }

            @discardableResult
            func performAction(named name: String) -> Bool {
                view.accessibilityCustomActions()?.first(where: { $0.name == name })?.handler?() ?? false
            }
        }

        @MainActor
        final class LocationSlider {
            private let host: NSHostingView<LocationSliderControl>
            private let window: NSWindow

            init(
                rows: [DiffRow],
                viewport: LocationViewport,
                side: ComparisonSide,
                navigate: @escaping (Int, ComparisonSide) -> Void
            ) {
                host = NSHostingView(
                    rootView: LocationSliderControl(
                        side: side,
                        map: LocationMap(rows: rows),
                        viewport: viewport,
                        navigate: navigate
                    ))
                window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 40, height: 240),
                    styleMask: [],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
            }

            var state: SliderState {
                guard let slider = accessibilitySlider else {
                    return SliderState(
                        role: nil,
                        label: nil,
                        value: nil,
                        isEnabled: false,
                        isValueSettable: false,
                        isIncrementAllowed: false,
                        isDecrementAllowed: false
                    )
                }
                return SliderState(
                    role: slider.accessibilityRole(),
                    label: slider.accessibilityLabel(),
                    value: slider.accessibilityValue() as? Double,
                    isEnabled: slider.isAccessibilityEnabled(),
                    isValueSettable: slider.isAccessibilitySelectorAllowed(
                        #selector(NSAccessibilityProtocol.setAccessibilityValue(_:))
                    ),
                    isIncrementAllowed: slider.isAccessibilitySelectorAllowed(
                        #selector(NSAccessibilityProtocol.accessibilityPerformIncrement)
                    ) && slider.isAccessibilityEnabled(),
                    isDecrementAllowed: slider.isAccessibilitySelectorAllowed(
                        #selector(NSAccessibilityProtocol.accessibilityPerformDecrement)
                    ) && slider.isAccessibilityEnabled()
                )
            }

            @discardableResult
            func setValue(_ value: Double) -> Bool {
                guard let slider = accessibilitySlider,
                    slider.isAccessibilitySelectorAllowed(
                        #selector(NSAccessibilityProtocol.setAccessibilityValue(_:))
                    )
                else { return false }
                slider.setAccessibilityValue(value)
                return true
            }

            @discardableResult
            func increment() -> Bool {
                guard let slider = accessibilitySlider,
                    slider.isAccessibilityEnabled(),
                    slider.isAccessibilitySelectorAllowed(
                        #selector(NSAccessibilityProtocol.accessibilityPerformIncrement)
                    )
                else { return false }
                slider.accessibilityPerformIncrement()
                return true
            }

            @discardableResult
            func decrement() -> Bool {
                guard let slider = accessibilitySlider,
                    slider.isAccessibilityEnabled(),
                    slider.isAccessibilitySelectorAllowed(
                        #selector(NSAccessibilityProtocol.accessibilityPerformDecrement)
                    )
                else { return false }
                slider.accessibilityPerformDecrement()
                return true
            }

            func close() {
                window.makeFirstResponder(nil)
                window.contentView = nil
                window.close()
            }

            private var accessibilitySlider: NSAccessibilityProtocol? {
                accessibilityElement(withRole: .slider, in: host)
            }

            private func accessibilityElement(
                withRole role: NSAccessibility.Role,
                in element: NSAccessibilityProtocol
            ) -> NSAccessibilityProtocol? {
                if element.accessibilityRole() == role {
                    return element
                }
                for child in element.accessibilityChildren() ?? [] {
                    guard let child = child as? NSAccessibilityProtocol else { continue }
                    if let match = accessibilityElement(withRole: role, in: child) { return match }
                }
                if let view = element as? NSView {
                    for subview in view.subviews {
                        if let match = accessibilityElement(withRole: role, in: subview) { return match }
                    }
                }
                return nil
            }
        }

        @MainActor
        final class ReadOnlyControl: NSObject {
            private let button = NSButton()
            private let requestedValue: Bool
            private(set) var requestedReadOnlyValues: [Bool] = []

            init(side: ComparisonSide, isLoaded: Bool, isEditable: Bool) {
                requestedValue = isEditable
                super.init()
                button.title = ComparisonReadOnlyPresentation.actionLabel(
                    side: side,
                    isLoaded: isLoaded,
                    isEditable: isEditable
                )
                button.target = self
                button.action = #selector(performCommand(_:))
                button.isEnabled = isLoaded
                button.setAccessibilityElement(true)
                button.setAccessibilityRole(.button)
                button.setAccessibilityLabel(button.title)
                button.setAccessibilityValue(
                    ComparisonReadOnlyPresentation.accessibilityValue(
                        isLoaded: isLoaded,
                        isEditable: isEditable
                    ))
            }

            var state: ElementState {
                ElementState(
                    role: button.accessibilityRole(),
                    label: button.accessibilityLabel(),
                    value: button.accessibilityValue() as? String,
                    isEnabled: button.isAccessibilityEnabled(),
                    isValueSettable: button.isAccessibilitySelectorAllowed(
                        #selector(NSAccessibilityProtocol.setAccessibilityValue(_:))
                    )
                )
            }

            @discardableResult
            func performAXPress() -> Bool {
                guard button.isEnabled else { return false }
                _ = button.accessibilityPerformPress()
                return true
            }

            func close() {}

            @objc private func performCommand(_ sender: NSButton) {
                requestedReadOnlyValues.append(requestedValue)
            }
        }

        @MainActor
        final class CopyCommandControl: NSObject {
            private let button = NSButton()
            private let command: ComparisonCopyCommand
            private let model: ComparisonModel

            init(command: ComparisonCopyCommand, model: ComparisonModel) {
                self.command = command
                self.model = model
                super.init()
                button.title = command.toolbarLabel
                button.target = self
                button.action = #selector(performCommand(_:))
                button.isEnabled = command.isEnabled(on: model)
                button.setAccessibilityElement(true)
                button.setAccessibilityRole(.button)
                button.setAccessibilityLabel(command.toolbarLabel)
            }

            var state: CommandState {
                CommandState(
                    role: button.accessibilityRole(),
                    label: button.accessibilityLabel(),
                    isEnabled: button.isAccessibilityEnabled()
                )
            }

            @discardableResult
            func performAXPress() -> Bool {
                guard button.isEnabled else { return false }
                _ = button.accessibilityPerformPress()
                return true
            }

            func close() {}

            @objc private func performCommand(_ sender: NSButton) {
                command.perform(on: model)
            }
        }

        private static var noOpActions: DiffContextMenuActions {
            DiffContextMenuActions(
                activate: { _, _ in },
                canMerge: { _ in false },
                merge: { _, _ in },
                canSelectLineDifference: { false },
                selectLineDifference: {},
                selectPreviousLineDifference: {},
                canGoToMovedLine: { _, _ in false },
                goToMovedLine: { _, _ in },
                canUndo: { false },
                undo: {},
                canRedo: { false },
                redo: {},
                fileURL: { _ in nil },
                handleMergeModeKey: { _, _ in false }
            )
        }

        private static func actions(for model: ComparisonModel) -> DiffContextMenuActions {
            .live(
                model: model,
                canUndo: { model.canUndo },
                undo: model.undo,
                canRedo: { model.canRedo },
                redo: model.redo
            )
        }

        private static func textViews(in root: NSView) -> [NSTextView] {
            var result = [NSTextView]()
            if let textView = root as? NSTextView {
                result.append(textView)
            }
            for subview in root.subviews {
                result.append(contentsOf: textViews(in: subview))
            }
            return result
        }

        private static func movedRows(
            rows: [DiffRow],
            movedLeft: Bool,
            movedRight: Bool
        ) -> MovedRowMap {
            MovedRowMap(
                testRows: rows,
                movedLeft: movedLeft,
                movedRight: movedRight
            )
        }
    }

    @MainActor
    final class ComparisonUpdateTestHarness {
        private let model: ComparisonModel
        private let coordinator: DiffTableView.Coordinator
        private let container: DiffTableContainerView
        private let window: NSWindow

        init(model: ComparisonModel) {
            self.model = model
            let view = Self.makeView(model: model)
            coordinator = view.makeCoordinator()
            container = view.makeNSView(coordinator: coordinator)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 180),
                styleMask: [],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = container
            coordinator.tableView?.reloadData()
            layout()
        }

        var focusedTextView: NSTextView? { window.firstResponder as? NSTextView }

        func update(focusRequest: DiffFocusRequest? = nil) {
            Self.makeView(
                model: model,
                focusRequest: focusRequest ?? model.focusRequest
            ).updateNSView(container, coordinator: coordinator)
            layout()
        }

        @discardableResult
        func beginEditing(rowID: DiffRow.ID, on side: ComparisonSide) -> Bool {
            cell(for: rowID)?.testBeginEditing(on: side) == true
        }

        func insertNewline(
            rowID: DiffRow.ID,
            on side: ComparisonSide,
            selectedRange: NSRange
        ) {
            guard let cell = cell(for: rowID) else {
                preconditionFailure("Expected visible comparison row")
            }
            cell.testInsertNewline(on: side, selectedRange: selectedRange)
        }

        func selectedRange(rowID: DiffRow.ID, on side: ComparisonSide) -> NSRange? {
            cell(for: rowID)?.testSelectedRange(on: side)
        }

        func isEditorFocused(rowID: DiffRow.ID, on side: ComparisonSide) -> Bool {
            cell(for: rowID)?.testIsEditorFocused(on: side) == true
        }

        func close() {
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
        }

        private func cell(for rowID: DiffRow.ID) -> DiffTableCellView? {
            guard let rowIndex = model.rows.firstIndex(where: { $0.id == rowID }) else { return nil }
            return coordinator.tableView?.view(
                atColumn: 0,
                row: rowIndex,
                makeIfNecessary: true
            ) as? DiffTableCellView
        }

        private func layout() {
            container.frame = NSRect(x: 0, y: 0, width: 800, height: 180)
            container.layoutSubtreeIfNeeded()
            container.scrollView.documentView?.layoutSubtreeIfNeeded()
        }

        private static func makeView(
            model: ComparisonModel,
            focusRequest: DiffFocusRequest? = nil
        ) -> DiffTableView {
            DiffTableView(
                rows: model.rows,
                rowsRevision: model.rowsRevision,
                maximumLineColumns: model.maximumLineColumns,
                differenceLocations: model.differenceLocations,
                movedRows: model.movedRows,
                selectedDifferenceID: model.selectedDifferenceID,
                selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision,
                focusRequest: focusRequest ?? model.focusRequest,
                isFocusRequestCurrent: { model.focusGeneration == $0 },
                leftEditable: model.left.isEditable,
                rightEditable: model.right.isEditable,
                navigationRow: nil,
                navigationRevision: 0,
                viewportChanged: model.updateViewport,
                selectDifference: model.activateRow,
                activateSide: model.activateSide,
                editLeft: { model.editLine(rowID: $0, on: .left, replacement: $1) },
                editRight: { model.editLine(rowID: $0, on: .right, replacement: $1) },
                finishEditingLeft: { model.finishLineEditing(rowID: $0, on: .left) },
                finishEditingRight: { model.finishLineEditing(rowID: $0, on: .right) },
                continueEditing: model.continueEditing,
                contextMenuActions: .live(
                    model: model,
                    canUndo: { model.canUndo },
                    undo: model.undo,
                    canRedo: { model.canRedo },
                    redo: model.redo
                )
            )
        }
    }
#endif

extension NSUserInterfaceItemIdentifier {
    fileprivate static let diffContent = NSUserInterfaceItemIdentifier("MacMerge.DiffContent")
    fileprivate static let diffCell = NSUserInterfaceItemIdentifier("MacMerge.DiffCell")
}
