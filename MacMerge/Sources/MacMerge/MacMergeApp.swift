import AppKit
import Darwin
import MacMergeCore
import Observation
import OSLog
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
    private let reportURL: URL?
    private let lock = NSLock()
    private var starts: [String: UInt64] = [:]
    private var metrics: [String: Int] = [:]

    private init() {
        let environment = ProcessInfo.processInfo.environment
        reportURL = environment["MACMERGE_PERFORMANCE_REPORT"].map { URL(filePath: $0) }
        shouldAutoScroll = environment["MACMERGE_PERFORMANCE_AUTOSCROLL"] == "1"
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

    func finishScroll() {
        guard reportURL != nil else { return }
        lock.withLock {
            guard let start = starts.removeValue(forKey: "scroll") else { return }
            metrics["scroll_ms"] = Int(
                (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            )
            metrics["resident_mib"] = Int(residentMemoryBytes() / 1_048_576)
            metrics["complete"] = 1
            writeReport()
        }
    }

    private func writeReport() {
        guard let reportURL,
              let data = try? JSONSerialization.data(
                withJSONObject: metrics,
                options: [.prettyPrinted, .sortedKeys]
              ) else { return }
        try? data.write(to: reportURL, options: .atomic)
    }

    private func residentMemoryBytes() -> UInt64 {
        var information = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(information.resident_size) : 0
    }
}

@main
struct MacMergeApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        Window("MacMerge", id: "comparison") {
            ComparisonView(
                model: applicationDelegate.model,
                requestNew: applicationDelegate.requestNewComparison,
                openComparison: applicationDelegate.openComparison
            )
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

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = ComparisonModel(userDefaults: .standard)

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
            model.saveAllChanges { [weak model] saved in
                if saved { model?.createEmptyComparison() }
            }
        case .alertThirdButtonReturn:
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
            Button("Save Left", action: { model.save(.left) })
                .disabled(!model.left.isDirty || model.isWorking)
            Button("Save Right", action: { model.save(.right) })
                .disabled(!model.right.isDirty || model.isWorking)
            Divider()
            Button("Save Left As...", action: { model.saveAs(.left) })
                .disabled(!model.left.isLoaded || model.isWorking)
            Button("Save Right As...", action: { model.saveAs(.right) })
                .disabled(!model.right.isLoaded || model.isWorking)
            Divider()
            Toggle("Merge Mode", isOn: Binding(
                get: { model.isMergeMode },
                set: { model.setMergeMode($0) }
            ))
            .keyboardShortcut(KeyEquivalent("\u{F70C}"), modifiers: [])
            Divider()
            Button("Reload from Disk", action: applicationDelegate.requestReloadComparison)
                .keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: .command)
                .disabled(!model.canReloadFromDisk)
        }
        CommandGroup(after: .undoRedo) {
            Button("Select Line Difference", action: model.selectLineDifference)
                .keyboardShortcut(KeyEquivalent("\u{F707}"), modifiers: [])
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
            Button("Copy to Right") {
                model.mergeSelectedDifference(direction: .leftToRight, advance: false)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!model.canMergeCurrentDifference)
            Button("Copy to Left") {
                model.mergeSelectedDifference(direction: .rightToLeft, advance: false)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!model.canMergeCurrentDifference)
            Button("Copy to Right and Advance") {
                model.mergeSelectedDifference(direction: .leftToRight, advance: true)
            }
            .disabled(!model.canMergeCurrentDifference)
            Button("Copy to Left and Advance") {
                model.mergeSelectedDifference(direction: .rightToLeft, advance: true)
            }
            .disabled(!model.canMergeCurrentDifference)
            Divider()
            Button("Copy All to Right") {
                model.mergeAll(direction: .leftToRight)
            }
            .disabled(!model.canNavigateDifferences)
            Button("Copy All to Left") {
                model.mergeAll(direction: .rightToLeft)
            }
            .disabled(!model.canNavigateDifferences)
        }
        CommandGroup(after: .toolbar) {
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
            if case let .failure(error) = result, !isCancellation(error) {
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
        _lineFilters = State(initialValue: model.options.lineFilters.map {
            LineFilterDraft(pattern: $0.pattern, caseSensitive: $0.caseSensitive)
        })
        _substitutionsEnabled = State(initialValue: model.options.substitutionsEnabled)
        _substitutions = State(initialValue: model.options.substitutions.map {
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
                        substitutions.append(SubstitutionDraft(
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
    let differenceLocations: DifferenceLocations
    let differenceRowIndices: [UInt32]
    let locationMap: LocationMap
    let summary: DiffSummary
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
           block(at: lastIndex).endRow == rowIndex {
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
        let kind: DiffKind = switch entry >> (Self.rowBits * 2) {
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
        let kindValue: UInt64 = switch kind {
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
              id.rightNumber.map({ (1...Int(lineNumberMask)).contains($0) }) ?? true else { return nil }
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
    let rows = try LineDiff.compare(left: left, right: right, options: options)
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

func intralineDifferenceRange(in text: String, comparedWith other: String) -> NSRange? {
    var textStart = text.startIndex
    var otherStart = other.startIndex
    while textStart < text.endIndex,
          otherStart < other.endIndex,
          text[textStart] == other[otherStart] {
        text.formIndex(after: &textStart)
        other.formIndex(after: &otherStart)
    }

    var textEnd = text.endIndex
    var otherEnd = other.endIndex
    while textEnd > textStart, otherEnd > otherStart {
        let previousText = text.index(before: textEnd)
        let previousOther = other.index(before: otherEnd)
        guard text[previousText] == other[previousOther] else { break }
        textEnd = previousText
        otherEnd = previousOther
    }

    guard textStart < textEnd else { return nil }
    return NSRange(textStart ..< textEnd, in: text)
}

private struct ComparisonOptionsStore {
    private static let key = "comparisonOptions.v1"
    let userDefaults: UserDefaults

    func load() -> LineDiffOptions {
        guard let data = userDefaults.data(forKey: Self.key),
              let options = try? JSONDecoder().decode(LineDiffOptions.self, from: data) else {
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
        didSet { rowsRevision &+= 1 }
    }
    private(set) var maximumLineColumns = 0
    private(set) var differenceLocations = DifferenceLocations()
    private(set) var differenceRowIndices: [UInt32] = []
    private(set) var locationMap = LocationMap()
    private(set) var summary = DiffSummary(rows: [])
    private(set) var selectedDifferenceID: DiffRow.ID?
    private(set) var currentRowID: DiffRow.ID?
    private(set) var selectedDifferenceRevealRevision = 0
    private(set) var lineDifferenceSelectionRevision = 0
    private(set) var paneFocusRevision = 0
    private(set) var activeSide = ComparisonSide.left
    private(set) var isMergeMode: Bool
    private(set) var isWorking = false
    private(set) var comparisonFailed = false
    private(set) var isComparisonCurrent = true
    private(set) var pendingExternalOpenURLs: [URL]?
    private(set) var pendingEncodingSelection: PendingEncodingSelection?
    private(set) var hasPendingSaveWarning = false
    private(set) var options: LineDiffOptions
    private(set) var optionsRevision = 0
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
    private var lineEditBaselines: [LineEditKey: String] = [:]
    private let optionsStore: ComparisonOptionsStore?
    private let userDefaults: UserDefaults?

    init(userDefaults: UserDefaults? = nil) {
        let optionsStore = userDefaults.map(ComparisonOptionsStore.init(userDefaults:))
        self.optionsStore = optionsStore
        self.userDefaults = userDefaults
        options = optionsStore?.load() ?? LineDiffOptions()
        isMergeMode = userDefaults?.bool(forKey: "mergeMode") ?? false
    }

    var isReady: Bool {
        left.isLoaded && right.isLoaded
    }

    var hasScratchpad: Bool { left.isUntitled || right.isUntitled }

    var canUndo: Bool { history.canUndo && !isWorking }
    var canRedo: Bool { history.canRedo && !isWorking }
    var hasDifferences: Bool { summary.differences > 0 && isComparisonCurrent }
    var hasUnsavedChanges: Bool { left.isDirty || right.isDirty }
    var hasSelectedDifference: Bool { selectedDifferenceID != nil && !isWorking }
    var canMergeCurrentDifference: Bool { currentDifferenceID != nil && !isWorking }
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
        guard !isWorking,
              let id = currentDifferenceID,
              let location = differenceLocations[id],
              rows.indices.contains(location.rowIndex),
              rows[location.rowIndex].kind == .modified,
              let leftText = rows[location.rowIndex].left?.text,
              let rightText = rows[location.rowIndex].right?.text else { return false }
        let text = activeSide == .left ? leftText : rightText
        let other = activeSide == .left ? rightText : leftText
        return intralineDifferenceRange(in: text, comparedWith: other) != nil
    }
    var hasReloadableUnsavedChanges: Bool {
        (left.document?.isDirty == true) || (right.document?.isDirty == true)
    }
    var canCreateEmptyComparison: Bool { !isWorking }

    var selectedDifferencePosition: Int? {
        guard let selectedDifferenceID,
              let rowIndex = differenceLocations[selectedDifferenceID]?.rowIndex,
              let position = orderedDifferencePosition(forRowIndex: rowIndex) else { return nil }
        return position + 1
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
        differenceLocations = DifferenceLocations()
        differenceRowIndices = []
        locationMap = LocationMap()
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
        guard !isWorking, file(on: side).isLoaded else { return }
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
        guard !isWorking, file(on: side).isLoaded else { return }
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
        let currentDifferenceRowIndices = differenceRowIndices
        let preferredDifferenceIndex: Int?
        if advancesToNextDifference,
           let rowIndex = differenceLocations[rowID]?.rowIndex,
           let index = orderedDifferencePosition(forRowIndex: rowIndex) {
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
        guard !isWorking, isComparisonCurrent else { return }
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
        guard !isWorking, isComparisonCurrent else { return }
        currentRowID = id
        guard let id, differenceLocations[id] != nil else {
            selectedDifferenceID = nil
            return
        }
        selectedDifferenceID = id
    }

    func activateSide(_ side: ComparisonSide) {
        activeSide = side
    }

    func changePane() {
        guard isReady, !isWorking else { return }
        activeSide = activeSide == .left ? .right : .left
        paneFocusRevision &+= 1
    }

    func setMergeMode(_ enabled: Bool) {
        guard isMergeMode != enabled else { return }
        isMergeMode = enabled
        userDefaults?.set(enabled, forKey: "mergeMode")
    }

    func handleMergeModeKey(_ keyCode: UInt16, rowID: DiffRow.ID) -> Bool {
        guard isMergeMode, !isWorking else { return false }
        switch keyCode {
        case 123:
            merge(rowID: rowID, direction: .rightToLeft)
        case 124:
            merge(rowID: rowID, direction: .leftToRight)
        case 125:
            selectNextDifference()
            paneFocusRevision &+= 1
        case 126:
            selectPreviousDifference()
            paneFocusRevision &+= 1
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
        guard canSelectLineDifference else { return }
        selectCurrentDifference()
        lineDifferenceSelectionRevision &+= 1
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
           saveDestinationsCollide(destination, oppositeURL) {
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

    func saveReloadableChanges(completion: @escaping @MainActor (Bool) -> Void) {
        let sides = [ComparisonSide.left, .right].filter {
            file(on: $0).document?.isDirty == true
        }
        saveReloadableChanges(sides[...], completion: completion)
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
            differenceLocations = DifferenceLocations()
            differenceRowIndices = []
            locationMap = LocationMap()
            summary = DiffSummary(rows: [])
            comparisonFailed = false
            return
        }

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
                    summary = comparison.summary
                    comparisonFailed = false
                    isComparisonCurrent = true
                    if let index, !differenceRowIndices.isEmpty {
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
        var effective = options
        guard effective.ignoreComments else { return effective }
        let fileExtension = [left.url, right.url]
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
        guard let originID = selectedDifferenceID ?? currentRowID else {
            let position = offset > 0 ? differenceRowIndices.startIndex : differenceRowIndices.index(before: differenceRowIndices.endIndex)
            return differenceID(at: position)
        }
        if let rowIndex = differenceLocations[originID]?.rowIndex,
           let position = orderedDifferencePosition(forRowIndex: rowIndex) {
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

    private func performSaveAs(_ side: ComparisonSide, destination: URL) async -> Bool {
        let original = file(on: side)
        do {
            let document = try await Task.detached {
                if let source = original.document {
                    return try TextFileDocumentIO.saveAs(source, to: destination)
                }
                guard let scratchpad = original.scratchpad else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return try TextFileDocumentIO.create(at: destination, text: scratchpad.text)
            }.value
            guard file(on: side) == original else { return false }
            let canonicalized = !document.text.unicodeScalars.elementsEqual(original.text.unicodeScalars)
            setFile(ComparedFile(document: document), on: side)
            if canonicalized {
                history.reset(to: snapshot)
                selectedDifferenceID = nil
                scheduleDiff()
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
    let requestNew: () -> Void
    let openComparison: () -> Void
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
                        selectedDifferenceID: model.selectedDifferenceID,
                        selectedDifferenceRevealRevision: model.selectedDifferenceRevealRevision,
                        lineDifferenceSelectionRevision: model.lineDifferenceSelectionRevision,
                        paneFocusRevision: model.paneFocusRevision,
                        paneFocusRowID: model.currentRowID,
                        activeSide: model.activeSide,
                        leftEditable: model.left.isLoaded,
                        rightEditable: model.right.isLoaded,
                        selectDifference: model.activateRow,
                        activateSide: model.activateSide,
                        editLeft: { model.editLine(rowID: $0, on: .left, replacement: $1) },
                        editRight: { model.editLine(rowID: $0, on: .right, replacement: $1) },
                        finishEditingLeft: { model.finishLineEditing(rowID: $0, on: .left) },
                        finishEditingRight: { model.finishLineEditing(rowID: $0, on: .right) },
                        contextMenuActions: DiffContextMenuActions(
                            activate: { rowID, side in
                                model.activateRow(rowID)
                                model.activateSide(side)
                            },
                            canMerge: { model.canMergeCurrentDifference },
                            merge: { rowID, direction in
                                model.merge(rowID: rowID, direction: direction)
                            },
                            canSelectLineDifference: { model.canSelectLineDifference },
                            selectLineDifference: model.selectLineDifference,
                            canUndo: { model.canUndo },
                            undo: model.undo,
                            canRedo: { model.canRedo },
                            redo: model.redo,
                            fileURL: { side in
                                side == .left ? model.left.url : model.right.url
                            },
                            handleMergeModeKey: model.handleMergeModeKey
                        )
                    )
                }
            } else {
                EmptyComparisonView()
            }

            Divider()
            ComparisonStatusBar(model: model)
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
                Button("Save Left", action: { model.save(.left) })
                    .disabled(!model.left.isDirty)
                Button("Save Right", action: { model.save(.right) })
                    .disabled(!model.right.isDirty)
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

            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .disabled(!model.canUndo)
                .help("Undo the last edit or merge")
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .disabled(!model.canRedo)
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

            Button("Copy selected difference to right", systemImage: "arrow.right") {
                model.mergeSelectedDifference(direction: .leftToRight, advance: false)
            }
                .disabled(!model.canMergeCurrentDifference)
                .help("Copy the selected or current difference to right")
            Button("Copy selected difference to left", systemImage: "arrow.left") {
                model.mergeSelectedDifference(direction: .rightToLeft, advance: false)
            }
                .disabled(!model.canMergeCurrentDifference)
                .help("Copy the selected or current difference to left")

            Button(
                "Copy selected difference to right and advance",
                systemImage: "arrow.right.circle",
                action: { model.mergeSelectedDifference(direction: .leftToRight, advance: true) }
            )
            .disabled(!model.canMergeCurrentDifference)
            .help("Copy selected difference to right and advance")
            Button(
                "Copy selected difference to left and advance",
                systemImage: "arrow.left.circle",
                action: { model.mergeSelectedDifference(direction: .rightToLeft, advance: true) }
            )
            .disabled(!model.canMergeCurrentDifference)
            .help("Copy selected difference to left and advance")

            toolbarDivider

            Button("Copy all differences to right", systemImage: "arrow.right.to.line") {
                requestMergeAll(.leftToRight)
            }
            .disabled(!model.canNavigateDifferences)
            .help("Copy all differences to right")
            Button("Copy all differences to left", systemImage: "arrow.left.to.line") {
                requestMergeAll(.rightToLeft)
            }
            .disabled(!model.canNavigateDifferences)
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
    let canMerge: () -> Bool
    let merge: (DiffRow.ID, MergeDirection) -> Void
    let canSelectLineDifference: () -> Bool
    let selectLineDifference: () -> Void
    let canUndo: () -> Bool
    let undo: () -> Void
    let canRedo: () -> Bool
    let redo: () -> Void
    let fileURL: (ComparisonSide) -> URL?
    let handleMergeModeKey: (UInt16, DiffRow.ID) -> Bool
}

private struct DiffCanvas: View {
    let rows: [DiffRow]
    let rowsRevision: Int
    let maximumLineColumns: Int
    let differenceLocations: DifferenceLocations
    let locationMap: LocationMap
    let selectedDifferenceID: DiffRow.ID?
    let selectedDifferenceRevealRevision: Int
    let lineDifferenceSelectionRevision: Int
    let paneFocusRevision: Int
    let paneFocusRowID: DiffRow.ID?
    let activeSide: ComparisonSide
    let leftEditable: Bool
    let rightEditable: Bool
    let selectDifference: (DiffRow.ID?) -> Void
    let activateSide: (ComparisonSide) -> Void
    let editLeft: (DiffRow.ID, String) -> Void
    let editRight: (DiffRow.ID, String) -> Void
    let finishEditingLeft: (DiffRow.ID) -> Void
    let finishEditingRight: (DiffRow.ID) -> Void
    let contextMenuActions: DiffContextMenuActions
    @State private var viewport = LocationViewport.empty
    @State private var navigationRow: Int?
    @State private var navigationRevision = 0

    var body: some View {
        HStack(spacing: 0) {
            DiffTableView(
                rows: rows,
                rowsRevision: rowsRevision,
                maximumLineColumns: maximumLineColumns,
                differenceLocations: differenceLocations,
                selectedDifferenceID: selectedDifferenceID,
                selectedDifferenceRevealRevision: selectedDifferenceRevealRevision,
                lineDifferenceSelectionRevision: lineDifferenceSelectionRevision,
                paneFocusRevision: paneFocusRevision,
                paneFocusRowID: paneFocusRowID,
                activeSide: activeSide,
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
                contextMenuActions: contextMenuActions
            )
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            LocationPane(
                map: locationMap,
                viewport: viewport,
                selectedRow: selectedDifferenceID.flatMap { differenceLocations[$0]?.rowIndex },
                navigate: navigate
            )
            .frame(width: 92)
        }
    }

    private func updateViewport(_ next: LocationViewport) {
        guard viewport != next else { return }
        viewport = next
    }

    private func navigate(to rowIndex: Int, side: ComparisonSide) {
        navigationRow = rowIndex
        navigationRevision &+= 1
        activateSide(side)
    }
}

private struct LocationPane: View {
    let map: LocationMap
    let viewport: LocationViewport
    let selectedRow: Int?
    let navigate: (Int, ComparisonSide) -> Void

    var body: some View {
        HStack(spacing: 8) {
            LocationBar(
                side: .left,
                map: map,
                viewport: viewport,
                selectedRow: selectedRow,
                navigate: navigate
            )
            LocationBar(
                side: .right,
                map: map,
                viewport: viewport,
                selectedRow: selectedRow,
                navigate: navigate
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location Pane")
    }
}

private struct LocationBar: View {
    let side: ComparisonSide
    let map: LocationMap
    let viewport: LocationViewport
    let selectedRow: Int?
    let navigate: (Int, ComparisonSide) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LocationMarks(map: map, side: side)
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
                              let row = map.rowIndex(at: Double(value.location.y / size.height)) else {
                            return
                        }
                        navigate(row, side)
                    }
            )
            .accessibilityRepresentation {
                Slider(value: accessibilityPosition, in: 0...1) {
                    Text("\(side == .left ? "Left" : "Right") file location map")
                }
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("Adjust to scroll the comparison")
                .disabled(map.rowCount == 0)
            }
        }
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
    let map: LocationMap
    let side: ComparisonSide

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(nsColor: .textBackgroundColor)))
            context.stroke(Path(bounds), with: .color(.secondary.opacity(0.55)), lineWidth: 1)
            guard map.rowCount > 0, size.height > 0 else { return }

            let scale = size.height / CGFloat(map.rowCount)
            for index in 0 ..< map.blockCount {
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
    let selectedDifferenceID: DiffRow.ID?
    let selectedDifferenceRevealRevision: Int
    let lineDifferenceSelectionRevision: Int
    let paneFocusRevision: Int
    let paneFocusRowID: DiffRow.ID?
    let activeSide: ComparisonSide
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
    let contextMenuActions: DiffContextMenuActions

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rows: rows,
            rowsRevision: rowsRevision,
            differenceLocations: differenceLocations,
            selectedDifferenceRevealRevision: selectedDifferenceRevealRevision,
            lineDifferenceSelectionRevision: lineDifferenceSelectionRevision,
            paneFocusRevision: paneFocusRevision,
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
            contextMenuActions: contextMenuActions
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
        scrollView.contentView.postsBoundsChangedNotifications = true
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
        context.coordinator.observeViewport(in: scrollView.contentView)
        return container
    }

    func updateNSView(_ container: DiffTableContainerView, context: Context) {
        guard let tableView = context.coordinator.tableView else { return }
        context.coordinator.selectDifference = selectDifference
        context.coordinator.activateSide = activateSide
        context.coordinator.editLeft = editLeft
        context.coordinator.editRight = editRight
        context.coordinator.finishEditingLeft = finishEditingLeft
        context.coordinator.finishEditingRight = finishEditingRight
        context.coordinator.contextMenuActions = contextMenuActions
        context.coordinator.viewportChanged = viewportChanged
        context.coordinator.differenceLocations = differenceLocations
        let editabilityChanged = context.coordinator.leftEditable != leftEditable
            || context.coordinator.rightEditable != rightEditable
        context.coordinator.leftEditable = leftEditable
        context.coordinator.rightEditable = rightEditable
        context.coordinator.appendsEditableRow = leftEditable || rightEditable

        if context.coordinator.rowsRevision != rowsRevision || editabilityChanged {
            context.coordinator.setRows(
                rows,
                revision: rowsRevision,
                differenceLocations: differenceLocations
            )
            context.coordinator.beginFirstVisibleRowTrace()
            tableView.reloadData()
            context.coordinator.restorePendingEditorFocus()
            context.coordinator.finishFirstVisibleRowTraceAfterLayout()
        }
        container.maximumTextWidth = CGFloat(maximumLineColumns) * 7.25 + 12

        let oldSelection = context.coordinator.selectedDifferenceID
        let revealRequested = context.coordinator.selectedDifferenceRevealRevision
            != selectedDifferenceRevealRevision
        let lineSelectionRequested = context.coordinator.lineDifferenceSelectionRevision
            != lineDifferenceSelectionRevision
        let paneFocusRequested = context.coordinator.paneFocusRevision != paneFocusRevision
        context.coordinator.selectedDifferenceID = selectedDifferenceID
        context.coordinator.selectedDifferenceRevealRevision = selectedDifferenceRevealRevision
        context.coordinator.lineDifferenceSelectionRevision = lineDifferenceSelectionRevision
        context.coordinator.paneFocusRevision = paneFocusRevision
        context.coordinator.synchronizeTableSelection()
        context.coordinator.refreshVisibleRows(for: [oldSelection, selectedDifferenceID].compactMap { $0 })
        if oldSelection != selectedDifferenceID || revealRequested,
           let selectedDifferenceID,
           let location = context.coordinator.differenceLocations[selectedDifferenceID] {
            tableView.scrollRowToVisible(location.rowIndex)
        }
        if lineSelectionRequested,
           let selectedDifferenceID,
           let location = context.coordinator.differenceLocations[selectedDifferenceID] {
            tableView.scrollRowToVisible(location.rowIndex)
            DispatchQueue.main.async { [weak tableView] in
                guard let tableView,
                      let cell = tableView.view(
                        atColumn: 0,
                        row: location.rowIndex,
                        makeIfNecessary: true
                      ) as? DiffTableCellView else { return }
                cell.selectDifferenceRange(on: activeSide)
            }
        }
        if paneFocusRequested {
            context.coordinator.focusEditor(on: activeSide, rowID: paneFocusRowID)
        }
        if context.coordinator.navigationRevision != navigationRevision,
           let navigationRow {
            context.coordinator.navigationRevision = navigationRevision
            context.coordinator.scroll(toCenteredRow: navigationRow)
        }
        context.coordinator.reportViewport()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let editableRow = DiffRow(left: nil, right: nil, kind: .unchanged)
        var rows: [DiffRow]
        var rowsRevision: Int
        var differenceLocations: DifferenceLocations
        var selectedDifferenceID: DiffRow.ID?
        var selectedDifferenceRevealRevision: Int
        var lineDifferenceSelectionRevision: Int
        var paneFocusRevision: Int
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
        }

        init(
            rows: [DiffRow],
            rowsRevision: Int,
            differenceLocations: DifferenceLocations,
            selectedDifferenceRevealRevision: Int,
            lineDifferenceSelectionRevision: Int,
            paneFocusRevision: Int,
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
            contextMenuActions: DiffContextMenuActions
        ) {
            self.rows = rows
            self.rowsRevision = rowsRevision
            self.differenceLocations = differenceLocations
            self.selectedDifferenceRevealRevision = selectedDifferenceRevealRevision
            self.lineDifferenceSelectionRevision = lineDifferenceSelectionRevision
            self.paneFocusRevision = paneFocusRevision
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
            let cell = tableView.makeView(withIdentifier: .diffCell, owner: self) as? DiffTableCellView
                ?? DiffTableCellView()
            cell.identifier = .diffCell
            cell.configure(
                row: displayedRow,
                selected: displayedRow.id == selectedDifferenceID,
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
                      let id = self.firstVisibleRowSignpostID else { return }
                PerformanceTrace.end("FirstVisibleRow", id: id)
                self.firstVisibleRowSignpostID = nil
                PerformanceProbe.shared.end("first_render")
                guard PerformanceProbe.shared.shouldAutoScroll, !self.didAutoScroll else { return }
                self.didAutoScroll = true
                self.autoScrollSignpostID = PerformanceTrace.begin("AutoScroll")
                PerformanceProbe.shared.begin("scroll")
                tableView.scrollRowToVisible(tableView.numberOfRows - 1)
                tableView.layoutSubtreeIfNeeded()
                DispatchQueue.main.async { [weak self] in
                    if let id = self?.autoScrollSignpostID {
                        PerformanceTrace.end("AutoScroll", id: id)
                        self?.autoScrollSignpostID = nil
                    }
                    PerformanceProbe.shared.finishScroll()
                }
            }
        }

        func setRows(
            _ rows: [DiffRow],
            revision: Int,
            differenceLocations: DifferenceLocations
        ) {
            self.rows = rows
            rowsRevision = revision
            self.differenceLocations = differenceLocations
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
            guard let row = displayedRow(at: rowIndex) else { return }
            let currentLine = side == .left ? row.left?.number : row.right?.number
            let insertionLine = rows[..<min(rowIndex, rows.count)].reduce(into: 1) { number, row in
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

        func focusEditor(on side: ComparisonSide, rowID: DiffRow.ID?) {
            guard let tableView else { return }
            let rowIndex = rowID.flatMap { id in rows.firstIndex(where: { $0.id == id }) }
                ?? max(0, tableView.row(at: tableView.visibleRect.origin))
            guard rows.indices.contains(rowIndex) else { return }
            tableView.scrollRowToVisible(rowIndex)
            DispatchQueue.main.async { [weak tableView] in
                guard let tableView,
                      let cell = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: true)
                        as? DiffTableCellView else { return }
                _ = cell.focusEditor(on: side)
            }
        }

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
        let didEnd = event.phase.contains(.ended) || event.phase.contains(.cancelled)
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
        contextMenuActions: DiffContextMenuActions,
        activateLeft: @escaping () -> Void,
        activateRight: @escaping () -> Void,
        continueEditingLeft: @escaping (Int) -> Void,
        continueEditingRight: @escaping (Int) -> Void
    ) {
        leftText.prepareForReuse()
        rightText.prepareForReuse()
        self.row = row
        leftNumber.stringValue = row.left.map { String($0.number) } ?? ""
        leftText.stringValue = row.left?.text ?? ""
        leftText.setDifferenceRange(differenceRange(for: row, side: .left))
        leftText.configureContextMenu(row: row, side: .left, actions: contextMenuActions)
        leftText.configureEditable(
            leftEditable,
            accessibilityLabel: editorAccessibilityLabel(for: row, side: .left),
            activate: activateLeft,
            finish: { [rowID = row.id] in finishEditingLeft(rowID) },
            continueAfterNewline: continueEditingLeft
        ) { [rowID = row.id] replacement in
            editLeft(rowID, replacement)
        }
        rightNumber.stringValue = row.right.map { String($0.number) } ?? ""
        rightText.stringValue = row.right?.text ?? ""
        rightText.setDifferenceRange(differenceRange(for: row, side: .right))
        rightText.configureContextMenu(row: row, side: .right, actions: contextMenuActions)
        rightText.configureEditable(
            rightEditable,
            accessibilityLabel: editorAccessibilityLabel(for: row, side: .right),
            activate: activateRight,
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

    func selectDifferenceRange(on side: ComparisonSide) {
        switch side {
        case .left:
            leftText.selectDifferenceRange()
        case .right:
            rightText.selectDifferenceRange()
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

    private func differenceRange(for row: DiffRow, side: ComparisonSide) -> NSRange? {
        guard row.kind == .modified,
              let left = row.left?.text,
              let right = row.right?.text else { return nil }
        switch side {
        case .left:
            return intralineDifferenceRange(in: left, comparedWith: right)
        case .right:
            return intralineDifferenceRange(in: right, comparedWith: left)
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
private final class DiffContextTextView: NSTextView {
    var contextMenuProvider: (() -> NSMenu?)?
    var mergeModeKeyHandler: ((NSEvent) -> Bool)?

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
        case undo
        case redo
        case cut
        case copy
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
    private var differenceRange: NSRange?
    private var activateHandler: (() -> Void)?
    private var commitHandler: ((String) -> Void)?
    private var finishHandler: (() -> Void)?
    private var continueAfterNewlineHandler: ((Int) -> Void)?
    private var contextMenuRow: DiffRow?
    private var contextMenuSide: ComparisonSide?
    private var contextMenuActions: DiffContextMenuActions?
    private var contextMenuItemCount = 0

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

    func configureContextMenu(
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
              let actions = contextMenuActions else { return }
        actions.activate(row.id, side)
        menu.removeAllItems()

        let otherSideName = side == .left ? "Right" : "Left"
        addItem(
            to: menu,
            title: "Copy to \(otherSideName)",
            action: .copyToOther,
            keyEquivalent: side == .left ? "\u{F703}" : "\u{F702}",
            modifiers: [.option],
            enabled: row.kind != .unchanged && actions.canMerge()
        )
        addItem(
            to: menu,
            title: "Copy from \(otherSideName)",
            action: .copyFromOther,
            keyEquivalent: side == .left ? "\u{F702}" : "\u{F703}",
            modifiers: [.option, .shift],
            enabled: row.kind != .unchanged && actions.canMerge()
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
            title: "Paste",
            action: .paste,
            enabled: textView.isEditable && NSPasteboard.general.canReadItem(withDataConformingToTypes: [UTType.plainText.identifier])
        )
        menu.addItem(.separator())

        addUnsupportedSubmenu(to: menu, title: "Scripts", items: ["< Empty >"])
        menu.addItem(.separator())

        addDisabledItem(to: menu, title: "Go to...", keyEquivalent: "g", modifiers: [.command])
        addDisabledItem(to: menu, title: "Go to Definition", keyEquivalent: "\u{F70F}")
        addDisabledItem(to: menu, title: "Go to Moved Line Between Left and Right")
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
              let actions = contextMenuActions else { return }
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
        case .undo:
            actions.undo()
        case .redo:
            actions.redo()
        case .cut:
            textView.cut(nil)
        case .copy:
            textView.copy(nil)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func setDifferenceRange(_ range: NSRange?) {
        differenceRange = range
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        guard let range else { return }
        let visibleRange = NSIntersectionRange(range, fullRange)
        guard visibleRange.length > 0 else { return }
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: NSColor.systemOrange.withAlphaComponent(0.48),
            forCharacterRange: visibleRange
        )
    }

    func selectDifferenceRange() {
        guard let differenceRange,
              textView.window?.makeFirstResponder(textView) == true else { return }
        textView.setSelectedRange(differenceRange)
        textView.scrollRangeToVisible(differenceRange)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        commitIfChanged()
        finishHandler?()
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
