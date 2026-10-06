import Foundation

/// UI-independent intent for one command in the New or New (3 panes) submenu.
///
/// Planning never creates a document, opens a picker, reads a file, creates a directory, or loads
/// a webpage. A document host must materialize the returned pane sources and provide any UI.
public struct NewComparisonDocumentPlan: Equatable, Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public enum Mode: String, CaseIterable, Hashable, Sendable {
        case text
        case table
        case binary
        case image
        case webpage
        case folder

        public static let `default`: Mode = .text

        public var comparisonProjectMode: ComparisonProject.Mode {
            switch self {
            case .text: .text
            case .table: .table
            case .binary: .binary
            case .image: .image
            case .webpage: .webpage
            case .folder: .folder
            }
        }

        public init?(comparisonProjectMode: ComparisonProject.Mode) {
            switch comparisonProjectMode {
            case .automatic: return nil
            case .text: self = .text
            case .table: self = .table
            case .binary: self = .binary
            case .image: self = .image
            case .webpage: self = .webpage
            case .folder: self = .folder
            }
        }
    }

    public enum PaneCount: Int, CaseIterable, Hashable, Sendable {
        case two = 2
        case three = 3

        public static let `default`: PaneCount = .two

        public var panes: [Pane] {
            switch self {
            case .two: [.left, .right]
            case .three: [.left, .middle, .right]
            }
        }

        public var paneLayoutPaneCount: PaneLayout.PaneCount {
            switch self {
            case .two: .two
            case .three: .three
            }
        }
    }

    public enum Pane: String, CaseIterable, Hashable, Sendable {
        case left
        case middle
        case right

        public var identity: PaneIdentity {
            switch self {
            case .left: .left
            case .middle: .middle
            case .right: .right
            }
        }

        public var defaultLabel: PaneLabel {
            switch self {
            case .left:
                PaneLabel(
                    localized: LocalizedStringResource(
                        "Untitled Left",
                        defaultValue: "Untitled Left",
                        bundle: .main,
                        comment: "Default label for the left pane of a new comparison"
                    )
                )
            case .middle:
                PaneLabel(
                    localized: LocalizedStringResource(
                        "Untitled Middle",
                        defaultValue: "Untitled Middle",
                        bundle: .main,
                        comment: "Default label for the middle pane of a new comparison"
                    )
                )
            case .right:
                PaneLabel(
                    localized: LocalizedStringResource(
                        "Untitled Right",
                        defaultValue: "Untitled Right",
                        bundle: .main,
                        comment: "Default label for the right pane of a new comparison"
                    )
                )
            }
        }

        fileprivate var sortOrder: Int {
            switch self {
            case .left: 0
            case .middle: 1
            case .right: 2
            }
        }
    }

    /// Stable semantic command identity. Declaration order matches WinMerge's two submenus.
    public enum Command: String, CaseIterable, Hashable, Sendable {
        case twoWayText
        case twoWayTable
        case twoWayBinary
        case twoWayImage
        case twoWayWebpage
        case twoWayFolder
        case threeWayText
        case threeWayTable
        case threeWayBinary
        case threeWayImage
        case threeWayWebpage
        case threeWayFolder

        public static let `default`: Command = .twoWayText

        public init(mode: Mode, paneCount: PaneCount) {
            switch (paneCount, mode) {
            case (.two, .text): self = .twoWayText
            case (.two, .table): self = .twoWayTable
            case (.two, .binary): self = .twoWayBinary
            case (.two, .image): self = .twoWayImage
            case (.two, .webpage): self = .twoWayWebpage
            case (.two, .folder): self = .twoWayFolder
            case (.three, .text): self = .threeWayText
            case (.three, .table): self = .threeWayTable
            case (.three, .binary): self = .threeWayBinary
            case (.three, .image): self = .threeWayImage
            case (.three, .webpage): self = .threeWayWebpage
            case (.three, .folder): self = .threeWayFolder
            }
        }

        public var mode: Mode {
            switch self {
            case .twoWayText, .threeWayText: .text
            case .twoWayTable, .threeWayTable: .table
            case .twoWayBinary, .threeWayBinary: .binary
            case .twoWayImage, .threeWayImage: .image
            case .twoWayWebpage, .threeWayWebpage: .webpage
            case .twoWayFolder, .threeWayFolder: .folder
            }
        }

        public var paneCount: PaneCount {
            switch self {
            case .twoWayText, .twoWayTable, .twoWayBinary, .twoWayImage, .twoWayWebpage,
                .twoWayFolder:
                .two
            case .threeWayText, .threeWayTable, .threeWayBinary, .threeWayImage,
                .threeWayWebpage, .threeWayFolder:
                .three
            }
        }
    }

    public enum ScratchpadKind: String, CaseIterable, Hashable, Sendable {
        case text
        case binary
    }

    /// Source a document host must supply before comparison can begin.
    public enum RequiredSourceKind: String, CaseIterable, Hashable, Sendable {
        /// Caller-created empty directory. Planning never creates or retains temporary folders.
        case emptyFolder
    }

    public enum SourceSemantics: Hashable, Sendable {
        case scratchpad(ScratchpadKind)
        case emptyImage
        case blankWebpage
        case requiredSource(RequiredSourceKind)
    }

    /// This file supplies intent only; app/document integration is deliberately a separate layer.
    public enum DocumentCreationSupport: String, Hashable, Sendable {
        case planningOnly
    }

    public struct Capability: Hashable, Sendable {
        public let mode: Mode
        public let supportedPaneCounts: [PaneCount]
        public let sourceSemantics: SourceSemantics
        public let documentCreationSupport: DocumentCreationSupport

        public var supportsTwoWay: Bool { supportedPaneCounts.contains(.two) }
        public var supportsThreeWay: Bool { supportedPaneCounts.contains(.three) }
        public var requiresSourceMaterialization: Bool {
            if case .requiredSource = sourceSemantics { true } else { false }
        }

        public init(mode: Mode) {
            self.mode = mode
            supportedPaneCounts = PaneCount.allCases
            documentCreationSupport = .planningOnly
            switch mode {
            case .text, .table:
                sourceSemantics = .scratchpad(.text)
            case .binary:
                sourceSemantics = .scratchpad(.binary)
            case .image:
                sourceSemantics = .emptyImage
            case .webpage:
                sourceSemantics = .blankWebpage
            case .folder:
                sourceSemantics = .requiredSource(.emptyFolder)
            }
        }

        public func supports(_ paneCount: PaneCount) -> Bool {
            supportedPaneCounts.contains(paneCount)
        }
    }

    public enum ScratchpadContent: Hashable, Sendable {
        case text(String)
        case binary(Data)

        public var kind: ScratchpadKind {
            switch self {
            case .text: .text
            case .binary: .binary
            }
        }
    }

    /// Resolved label retained with app-localization intent. Hosts display `resolvedValue` so the
    /// exact string validated by planning is materialized. `.main` is intentional: the app owns
    /// user-facing translations while this package target has no resource bundle.
    public struct PaneLabel: Equatable, Sendable, ExpressibleByStringLiteral {
        public let resolvedValue: String
        public let localizationResource: LocalizedStringResource?

        public init(_ resolvedValue: String) {
            self.resolvedValue = resolvedValue
            localizationResource = nil
        }

        public init(localized resource: LocalizedStringResource) {
            resolvedValue = String(localized: resource)
            localizationResource = resource
        }

        public init(stringLiteral value: String) {
            self.init(value)
        }
    }

    /// Optional caller override for a scratchpad-backed mode. Omit overrides for empty defaults.
    public struct Scratchpad: Equatable, Sendable {
        public let pane: Pane
        public let label: PaneLabel
        public let content: ScratchpadContent

        public init(
            pane: Pane,
            label: PaneLabel? = nil,
            content: ScratchpadContent
        ) {
            self.pane = pane
            self.label = label ?? pane.defaultLabel
            self.content = content
        }
    }

    public enum PaneSource: Hashable, Sendable {
        case scratchpad(ScratchpadContent)
        /// Deterministic transparent 1x1 RGBA image intent.
        case emptyImage
        /// Deterministic empty UTF-8 HTML document intent.
        case blankWebpage
        case requiredSource(RequiredSourceKind)
    }

    public struct PlannedPane: Equatable, Sendable {
        public let pane: Pane
        public let label: PaneLabel
        public let source: PaneSource

        public init(pane: Pane, label: PaneLabel, source: PaneSource) {
            self.pane = pane
            self.label = label
            self.source = source
        }
    }

    /// Concrete current settings already validated by `ComparisonOpenRequestPlanner`.
    public struct ValidatedModeOptions: Equatable, Sendable {
        public let requestIdentity: ComparisonOpenRequestIdentity
        public let mode: Mode
        public let paneCount: PaneCount
        public let value: ComparisonOpenModeOptions

        public init?(_ plan: ComparisonOpenPlan, currentRequest: ComparisonOpenRequest) throws {
            try plan.requireCurrentRequest(currentRequest)
            guard let mode = Mode(comparisonProjectMode: plan.modeResolution.mode),
                plan.modeOptions != .defaults
            else {
                return nil
            }
            requestIdentity = plan.requestIdentity
            self.mode = mode
            paneCount = plan.isThreeWay ? .three : .two
            value = plan.modeOptions
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case paneCount
        case scratchpadBytes
        case combinedScratchpadBytes
        case labelUTF8Bytes
        case planningWorkUnits
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumPaneCount = 3
        public static let hardMaximumScratchpadBytes = 64 * 1024 * 1024
        public static let hardMaximumCombinedScratchpadBytes = 192 * 1024 * 1024
        public static let hardMaximumLabelUTF8Bytes = 4 * 1024
        public static let hardMaximumPlanningWorkUnits = 512 * 1024 * 1024
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumPaneCount: Int
        public let maximumScratchpadBytes: Int
        public let maximumCombinedScratchpadBytes: Int
        public let maximumLabelUTF8Bytes: Int
        public let maximumPlanningWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumPaneCount: Int = Limits.hardMaximumPaneCount,
            maximumScratchpadBytes: Int = Limits.hardMaximumScratchpadBytes,
            maximumCombinedScratchpadBytes: Int = Limits.hardMaximumCombinedScratchpadBytes,
            maximumLabelUTF8Bytes: Int = 1_024,
            maximumPlanningWorkUnits: Int = 256 * 1024 * 1024,
            cancellationCheckInterval: Int = Limits.hardMaximumCancellationCheckInterval
        ) {
            self.maximumPaneCount = maximumPaneCount
            self.maximumScratchpadBytes = maximumScratchpadBytes
            self.maximumCombinedScratchpadBytes = maximumCombinedScratchpadBytes
            self.maximumLabelUTF8Bytes = maximumLabelUTF8Bytes
            self.maximumPlanningWorkUnits = maximumPlanningWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (2...Self.hardMaximumPaneCount).contains(maximumPaneCount) else {
                throw NewComparisonDocumentPlanError.invalidLimit(
                    .paneCount,
                    value: maximumPaneCount
                )
            }
            guard (0...Self.hardMaximumScratchpadBytes).contains(maximumScratchpadBytes) else {
                throw NewComparisonDocumentPlanError.invalidLimit(
                    .scratchpadBytes,
                    value: maximumScratchpadBytes
                )
            }
            guard
                (0...Self.hardMaximumCombinedScratchpadBytes).contains(
                    maximumCombinedScratchpadBytes
                )
            else {
                throw NewComparisonDocumentPlanError.invalidLimit(
                    .combinedScratchpadBytes,
                    value: maximumCombinedScratchpadBytes
                )
            }
            guard maximumCombinedScratchpadBytes >= maximumScratchpadBytes else {
                throw NewComparisonDocumentPlanError.invalidLimit(
                    .combinedScratchpadBytes,
                    value: maximumCombinedScratchpadBytes
                )
            }
            guard (1...Self.hardMaximumLabelUTF8Bytes).contains(maximumLabelUTF8Bytes) else {
                throw NewComparisonDocumentPlanError.invalidLimit(
                    .labelUTF8Bytes,
                    value: maximumLabelUTF8Bytes
                )
            }
            guard (1...Self.hardMaximumPlanningWorkUnits).contains(maximumPlanningWorkUnits) else {
                throw NewComparisonDocumentPlanError.invalidLimit(
                    .planningWorkUnits,
                    value: maximumPlanningWorkUnits
                )
            }
            guard
                (1...Self.hardMaximumCancellationCheckInterval).contains(
                    cancellationCheckInterval
                )
            else {
                throw NewComparisonDocumentPlanError.invalidLimit(
                    .cancellationCheckInterval,
                    value: cancellationCheckInterval
                )
            }
        }
    }

    public static let capabilities = Mode.allCases.map(Capability.init(mode:))

    public let command: Command
    public let mode: Mode
    public let paneCount: PaneCount
    public let capability: Capability
    public let panes: [PlannedPane]
    public let modeOptions: ValidatedModeOptions
    public let limits: Limits
    public let workPerformed: Int

    public var sourceSemantics: SourceSemantics { capability.sourceSemantics }
    public var requiresSourceMaterialization: Bool { capability.requiresSourceMaterialization }
    public var scratchpads: [Scratchpad] {
        panes.compactMap { pane in
            guard case .scratchpad(let content) = pane.source else { return nil }
            return Scratchpad(pane: pane.pane, label: pane.label, content: content)
        }
    }
    public var requiredSources: [PlannedPane] {
        panes.filter { if case .requiredSource = $0.source { true } else { false } }
    }

    public static func capability(for mode: Mode) -> Capability {
        Capability(mode: mode)
    }

    public static func command(for mode: Mode, paneCount: PaneCount) -> Command {
        Command(mode: mode, paneCount: paneCount)
    }

    /// Creates a deterministic plan. Scratchpad overrides are valid only for scratchpad modes.
    public static func make(
        command: Command = .default,
        scratchpads: [Scratchpad]? = nil,
        modeOptions: ValidatedModeOptions,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            if Task<Never, Never>.isCancelled {
                throw NewComparisonDocumentPlanError.cancelled
            }
        }
    ) throws -> NewComparisonDocumentPlan {
        var work = NewComparisonDocumentPlanningWork(
            maximum: limits.maximumPlanningWorkUnits,
            cancellationCheckInterval: limits.cancellationCheckInterval,
            cancellationCheck: cancellationCheck
        )
        try work.checkCancellation()
        try limits.validate()

        let mode = command.mode
        let paneCount = command.paneCount
        guard paneCount.rawValue <= limits.maximumPaneCount else {
            throw NewComparisonDocumentPlanError.paneLimitExceeded(
                requested: paneCount,
                maximum: limits.maximumPaneCount
            )
        }
        let capability = Capability(mode: mode)
        guard capability.supports(paneCount) else {
            throw NewComparisonDocumentPlanError.unsupportedPaneCount(
                mode: mode,
                paneCount: paneCount
            )
        }
        try work.consume()

        guard modeOptions.mode == mode, modeOptions.paneCount == paneCount else {
            throw NewComparisonDocumentPlanError.modeOptionsMismatch(
                expectedMode: mode,
                expectedPaneCount: paneCount,
                actualMode: modeOptions.mode,
                actualPaneCount: modeOptions.paneCount
            )
        }

        let plannedPanes: [PlannedPane]
        switch capability.sourceSemantics {
        case .scratchpad(let kind):
            let values = try canonicalScratchpads(
                scratchpads ?? defaultScratchpads(for: paneCount, kind: kind),
                paneCount: paneCount,
                expectedKind: kind,
                modeOptions: modeOptions,
                limits: limits,
                work: &work
            )
            plannedPanes = values.map {
                PlannedPane(
                    pane: $0.pane,
                    label: $0.label,
                    source: .scratchpad($0.content)
                )
            }
        case .emptyImage, .blankWebpage, .requiredSource:
            guard scratchpads == nil else {
                throw NewComparisonDocumentPlanError.scratchpadsNotSupported(mode: mode)
            }
            var values: [PlannedPane] = []
            values.reserveCapacity(paneCount.rawValue)
            for pane in paneCount.panes {
                try work.consume()
                try validateLabel(
                    pane.defaultLabel,
                    pane: pane,
                    limits: limits,
                    work: &work
                )
                values.append(
                    PlannedPane(
                        pane: pane,
                        label: pane.defaultLabel,
                        source: paneSource(for: capability.sourceSemantics)
                    )
                )
            }
            plannedPanes = values
        }

        try work.checkCancellation()
        return NewComparisonDocumentPlan(
            command: command,
            mode: mode,
            paneCount: paneCount,
            capability: capability,
            panes: plannedPanes,
            modeOptions: modeOptions,
            limits: limits,
            workPerformed: work.completed
        )
    }

    public static func make(
        mode: Mode,
        paneCount: PaneCount,
        scratchpads: [Scratchpad]? = nil,
        modeOptions: ValidatedModeOptions,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            if Task<Never, Never>.isCancelled {
                throw NewComparisonDocumentPlanError.cancelled
            }
        }
    ) throws -> NewComparisonDocumentPlan {
        try make(
            command: Command(mode: mode, paneCount: paneCount),
            scratchpads: scratchpads,
            modeOptions: modeOptions,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    public static func plan(
        command: Command = .default,
        scratchpads: [Scratchpad]? = nil,
        modeOptions: ValidatedModeOptions,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            if Task<Never, Never>.isCancelled {
                throw NewComparisonDocumentPlanError.cancelled
            }
        }
    ) throws -> NewComparisonDocumentPlan {
        try make(
            command: command,
            scratchpads: scratchpads,
            modeOptions: modeOptions,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    private static func defaultScratchpads(
        for paneCount: PaneCount,
        kind: ScratchpadKind
    ) -> [Scratchpad] {
        paneCount.panes.map { pane in
            let content: ScratchpadContent = kind == .text ? .text("") : .binary(Data())
            return Scratchpad(pane: pane, content: content)
        }
    }

    private static func canonicalScratchpads(
        _ scratchpads: [Scratchpad],
        paneCount: PaneCount,
        expectedKind: ScratchpadKind,
        modeOptions: ValidatedModeOptions,
        limits: Limits,
        work: inout NewComparisonDocumentPlanningWork
    ) throws -> [Scratchpad] {
        let expectedPanes = paneCount.panes
        guard scratchpads.count == expectedPanes.count else {
            throw NewComparisonDocumentPlanError.invalidScratchpadCount(
                expected: expectedPanes.count,
                actual: scratchpads.count
            )
        }

        var seen: Set<Pane> = []
        var totalBytes = 0
        for scratchpad in scratchpads {
            try work.consume()
            guard expectedPanes.contains(scratchpad.pane) else {
                throw NewComparisonDocumentPlanError.unexpectedScratchpad(scratchpad.pane)
            }
            guard seen.insert(scratchpad.pane).inserted else {
                throw NewComparisonDocumentPlanError.duplicateScratchpad(scratchpad.pane)
            }
            guard scratchpad.content.kind == expectedKind else {
                throw NewComparisonDocumentPlanError.scratchpadKindMismatch(
                    pane: scratchpad.pane,
                    expected: expectedKind,
                    actual: scratchpad.content.kind
                )
            }
            try validateLabel(scratchpad.label, pane: scratchpad.pane, limits: limits, work: &work)
            let remainingCombinedBytes = limits.maximumCombinedScratchpadBytes - totalBytes
            let paneMaximumBytes = min(
                limits.maximumScratchpadBytes,
                scratchpadMaximumBytes(modeOptions.value, paneCount: paneCount)
            )
            let maximumBytes = min(paneMaximumBytes, remainingCombinedBytes)
            let limitError: NewComparisonDocumentPlanError =
                remainingCombinedBytes < paneMaximumBytes
                ? .combinedScratchpadsTooLarge(
                    maximumBytes: limits.maximumCombinedScratchpadBytes
                )
                : .scratchpadTooLarge(
                    pane: scratchpad.pane,
                    maximumBytes: paneMaximumBytes
                )
            let byteCount = try validateContent(
                scratchpad.content,
                pane: scratchpad.pane,
                maximumBytes: maximumBytes,
                maximumLines: scratchpadMaximumLines(
                    modeOptions.value,
                    paneCount: paneCount
                ),
                limitError: limitError,
                work: &work
            )
            let (combined, overflow) = totalBytes.addingReportingOverflow(byteCount)
            guard !overflow, combined <= limits.maximumCombinedScratchpadBytes else {
                throw NewComparisonDocumentPlanError.combinedScratchpadsTooLarge(
                    maximumBytes: limits.maximumCombinedScratchpadBytes
                )
            }
            totalBytes = combined
        }
        if let missing = expectedPanes.first(where: { !seen.contains($0) }) {
            throw NewComparisonDocumentPlanError.missingScratchpad(missing)
        }
        return scratchpads.sorted { $0.pane.sortOrder < $1.pane.sortOrder }
    }

    private static func validateLabel(
        _ label: PaneLabel,
        pane: Pane,
        limits: Limits,
        work: inout NewComparisonDocumentPlanningWork
    ) throws {
        let label = label.resolvedValue
        guard
            try boundedUTF8Count(
                label,
                maximum: limits.maximumLabelUTF8Bytes,
                work: &work
            ) != nil
        else {
            throw NewComparisonDocumentPlanError.paneLabelTooLarge(
                pane: pane,
                maximumUTF8Bytes: limits.maximumLabelUTF8Bytes
            )
        }
        guard !label.isEmpty, !label.contains("\0"), label.contains(where: { !$0.isWhitespace }) else {
            throw NewComparisonDocumentPlanError.invalidPaneLabel(pane)
        }
    }

    private static func validateContent(
        _ content: ScratchpadContent,
        pane: Pane,
        maximumBytes: Int,
        maximumLines: Int?,
        limitError: NewComparisonDocumentPlanError,
        work: inout NewComparisonDocumentPlanningWork
    ) throws -> Int {
        switch content {
        case .text(let text):
            var byteCount = 0
            var lineCount = 0
            var previousWasCarriageReturn = false
            var endsWithTerminator = false
            for byte in text.utf8 {
                guard byteCount < maximumBytes else { throw limitError }
                byteCount += 1
                try work.consume()
                if byte == 0x0A {
                    if !previousWasCarriageReturn { lineCount += 1 }
                    endsWithTerminator = true
                } else if byte == 0x0D {
                    lineCount += 1
                    endsWithTerminator = true
                } else {
                    endsWithTerminator = false
                }
                if let maximumLines, lineCount > maximumLines {
                    throw NewComparisonDocumentPlanError.scratchpadLineLimitExceeded(
                        pane: pane,
                        maximumLines: maximumLines
                    )
                }
                previousWasCarriageReturn = byte == 0x0D
            }
            if !text.isEmpty, !endsWithTerminator { lineCount += 1 }
            if let maximumLines, lineCount > maximumLines {
                throw NewComparisonDocumentPlanError.scratchpadLineLimitExceeded(
                    pane: pane,
                    maximumLines: maximumLines
                )
            }
            return byteCount
        case .binary(let data):
            guard data.count <= maximumBytes else {
                throw limitError
            }
            try work.consume(data.count)
            return data.count
        }
    }

    private static func boundedUTF8Count(
        _ value: String,
        maximum: Int,
        work: inout NewComparisonDocumentPlanningWork
    ) throws -> Int? {
        var count = 0
        for _ in value.utf8 {
            guard count < maximum else { return nil }
            count += 1
            try work.consume()
        }
        return count
    }

    private static func scratchpadMaximumBytes(
        _ options: ComparisonOpenModeOptions,
        paneCount: PaneCount
    ) -> Int {
        switch options {
        case .text(_, let threeWay):
            return paneCount == .three ? threeWay.maximumInputBytes : Limits.hardMaximumScratchpadBytes
        case .table(let parsing, _, let threeWay):
            return paneCount == .three
                ? threeWay.parsingOptions.limits.maximumInputBytes
                : parsing.limits.maximumInputBytes
        case .binary(_, let threeWay):
            return paneCount == .three ? threeWay.maximumInputBytes : Limits.hardMaximumScratchpadBytes
        case .defaults, .image, .webpage, .folder:
            return Limits.hardMaximumScratchpadBytes
        }
    }

    private static func scratchpadMaximumLines(
        _ options: ComparisonOpenModeOptions,
        paneCount: PaneCount
    ) -> Int? {
        guard paneCount == .three, case .text(_, let threeWay) = options else { return nil }
        return threeWay.maximumInputLines
    }

    private static func paneSource(for semantics: SourceSemantics) -> PaneSource {
        switch semantics {
        case .scratchpad:
            preconditionFailure("Scratchpad sources are planned separately")
        case .emptyImage:
            return .emptyImage
        case .blankWebpage:
            return .blankWebpage
        case .requiredSource(let kind):
            return .requiredSource(kind)
        }
    }

    private init(
        command: Command,
        mode: Mode,
        paneCount: PaneCount,
        capability: Capability,
        panes: [PlannedPane],
        modeOptions: ValidatedModeOptions,
        limits: Limits,
        workPerformed: Int
    ) {
        self.command = command
        self.mode = mode
        self.paneCount = paneCount
        self.capability = capability
        self.panes = panes
        self.modeOptions = modeOptions
        self.limits = limits
        self.workPerformed = workPerformed
    }
}

public enum NewComparisonDocumentPlanError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(NewComparisonDocumentPlan.Limit, value: Int)
    case paneLimitExceeded(requested: NewComparisonDocumentPlan.PaneCount, maximum: Int)
    case unsupportedPaneCount(
        mode: NewComparisonDocumentPlan.Mode,
        paneCount: NewComparisonDocumentPlan.PaneCount
    )
    case scratchpadsNotSupported(mode: NewComparisonDocumentPlan.Mode)
    case modeOptionsMismatch(
        expectedMode: NewComparisonDocumentPlan.Mode,
        expectedPaneCount: NewComparisonDocumentPlan.PaneCount,
        actualMode: NewComparisonDocumentPlan.Mode,
        actualPaneCount: NewComparisonDocumentPlan.PaneCount
    )
    case invalidScratchpadCount(expected: Int, actual: Int)
    case unexpectedScratchpad(NewComparisonDocumentPlan.Pane)
    case duplicateScratchpad(NewComparisonDocumentPlan.Pane)
    case missingScratchpad(NewComparisonDocumentPlan.Pane)
    case scratchpadKindMismatch(
        pane: NewComparisonDocumentPlan.Pane,
        expected: NewComparisonDocumentPlan.ScratchpadKind,
        actual: NewComparisonDocumentPlan.ScratchpadKind
    )
    case invalidPaneLabel(NewComparisonDocumentPlan.Pane)
    case paneLabelTooLarge(
        pane: NewComparisonDocumentPlan.Pane,
        maximumUTF8Bytes: Int
    )
    case scratchpadTooLarge(pane: NewComparisonDocumentPlan.Pane, maximumBytes: Int)
    case scratchpadLineLimitExceeded(
        pane: NewComparisonDocumentPlan.Pane,
        maximumLines: Int
    )
    case combinedScratchpadsTooLarge(maximumBytes: Int)
    case planningWorkExceeded(maximumWorkUnits: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "New comparison document planning was cancelled."
        case .invalidLimit(let limit, let value):
            "Invalid new comparison document limit \(limit.rawValue): \(value)."
        case .paneLimitExceeded(let requested, let maximum):
            "A \(requested.rawValue)-pane new comparison exceeds the \(maximum)-pane limit."
        case .unsupportedPaneCount(let mode, let paneCount):
            "New \(mode.rawValue) comparison planning does not support \(paneCount.rawValue) panes."
        case .scratchpadsNotSupported(let mode):
            "New \(mode.rawValue) comparisons do not accept scratchpads."
        case .modeOptionsMismatch(let expectedMode, let expectedCount, let actualMode, let actualCount):
            "New \(expectedCount.rawValue)-pane \(expectedMode.rawValue) comparison options cannot use \(actualCount.rawValue)-pane \(actualMode.rawValue) settings."
        case .invalidScratchpadCount(let expected, let actual):
            "New comparison planning requires \(expected) scratchpads, not \(actual)."
        case .unexpectedScratchpad(let pane):
            "New comparison planning does not expect a \(pane.rawValue) scratchpad."
        case .duplicateScratchpad(let pane):
            "New comparison planning contains the \(pane.rawValue) scratchpad more than once."
        case .missingScratchpad(let pane):
            "New comparison planning is missing the \(pane.rawValue) scratchpad."
        case .scratchpadKindMismatch(let pane, let expected, let actual):
            "New comparison \(pane.rawValue) scratchpad requires \(expected.rawValue) content, not \(actual.rawValue)."
        case .invalidPaneLabel(let pane):
            "New comparison \(pane.rawValue) pane label is invalid."
        case .paneLabelTooLarge(let pane, let maximum):
            "New comparison \(pane.rawValue) pane label exceeds \(maximum) UTF-8 bytes."
        case .scratchpadTooLarge(let pane, let maximum):
            "New comparison \(pane.rawValue) scratchpad exceeds \(maximum) bytes."
        case .scratchpadLineLimitExceeded(let pane, let maximum):
            "New comparison \(pane.rawValue) scratchpad exceeds \(maximum) lines."
        case .combinedScratchpadsTooLarge(let maximum):
            "New comparison scratchpads exceed \(maximum) combined bytes."
        case .planningWorkExceeded(let maximum):
            "New comparison document planning exceeds the \(maximum)-unit work limit."
        }
    }
}

private struct NewComparisonDocumentPlanningWork {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: NewComparisonDocumentPlan.CancellationCheck
    private(set) var completed = 0

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0 else {
            try checkCancellation()
            throw NewComparisonDocumentPlanError.planningWorkExceeded(maximumWorkUnits: maximum)
        }
        guard amount <= maximum, completed <= maximum - amount else {
            try checkCancellation()
            throw NewComparisonDocumentPlanError.planningWorkExceeded(maximumWorkUnits: maximum)
        }
        let previousCheckBucket = completed / cancellationCheckInterval
        completed += amount
        if completed / cancellationCheckInterval != previousCheckBucket {
            try checkCancellation()
        }
    }

    func checkCancellation() throws {
        do {
            try cancellationCheck()
        } catch is CancellationError {
            throw NewComparisonDocumentPlanError.cancelled
        }
    }
}
