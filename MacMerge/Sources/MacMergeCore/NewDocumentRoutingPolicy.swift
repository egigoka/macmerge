import Foundation

/// UI-independent routing for the New split button, New menus, shortcuts, and accessibility actions.
///
/// Routing validates immutable caller snapshots and creates planning values only. It never creates a
/// document, presents UI, touches the file system, or materializes a pane source.
public enum NewDocumentRoutingPolicy: Sendable {
    public typealias Mode = NewComparisonDocumentPlan.Mode
    public typealias PaneCount = NewComparisonDocumentPlan.PaneCount
    public typealias CancellationCheck =
        @Sendable () throws(NewDocumentRoutingPolicyError) -> Void

    public static func taskCancellationCheck() throws(NewDocumentRoutingPolicyError) {
        if Task<Never, Never>.isCancelled {
            throw .cancelled
        }
    }

    /// Stable WinMerge command identity. Raw values are persistence and dispatch contracts.
    public enum CommandID: String, CaseIterable, Comparable, Hashable, Sendable {
        case twoPaneText = "ID_FILE_NEW"
        case twoPaneTable = "ID_FILE_NEW_TABLE"
        case twoPaneBinary = "ID_FILE_NEW_HEX"
        case twoPaneImage = "ID_FILE_NEW_IMAGE"
        case twoPaneWebpage = "ID_FILE_NEW_WEBPAGE"
        case twoPaneFolder = "ID_FILE_NEW_FOLDER"
        case threePaneText = "ID_FILE_NEW3"
        case threePaneTable = "ID_FILE_NEW3_TABLE"
        case threePaneBinary = "ID_FILE_NEW3_HEX"
        case threePaneImage = "ID_FILE_NEW3_IMAGE"
        case threePaneWebpage = "ID_FILE_NEW3_WEBPAGE"
        case threePaneFolder = "ID_FILE_NEW3_FOLDER"

        public static func < (left: CommandID, right: CommandID) -> Bool {
            left.order < right.order
        }

        public init(mode: Mode, paneCount: PaneCount) {
            switch (paneCount, mode) {
            case (.two, .text): self = .twoPaneText
            case (.two, .table): self = .twoPaneTable
            case (.two, .binary): self = .twoPaneBinary
            case (.two, .image): self = .twoPaneImage
            case (.two, .webpage): self = .twoPaneWebpage
            case (.two, .folder): self = .twoPaneFolder
            case (.three, .text): self = .threePaneText
            case (.three, .table): self = .threePaneTable
            case (.three, .binary): self = .threePaneBinary
            case (.three, .image): self = .threePaneImage
            case (.three, .webpage): self = .threePaneWebpage
            case (.three, .folder): self = .threePaneFolder
            }
        }

        public var mode: Mode {
            switch self {
            case .twoPaneText, .threePaneText: .text
            case .twoPaneTable, .threePaneTable: .table
            case .twoPaneBinary, .threePaneBinary: .binary
            case .twoPaneImage, .threePaneImage: .image
            case .twoPaneWebpage, .threePaneWebpage: .webpage
            case .twoPaneFolder, .threePaneFolder: .folder
            }
        }

        public var paneCount: PaneCount {
            switch self {
            case .twoPaneText, .twoPaneTable, .twoPaneBinary, .twoPaneImage,
                .twoPaneWebpage, .twoPaneFolder:
                .two
            case .threePaneText, .threePaneTable, .threePaneBinary, .threePaneImage,
                .threePaneWebpage, .threePaneFolder:
                .three
            }
        }

        public var documentCommand: NewComparisonDocumentPlan.Command {
            NewComparisonDocumentPlan.Command(mode: mode, paneCount: paneCount)
        }

        fileprivate var order: Int {
            switch self {
            case .twoPaneText: 0
            case .twoPaneTable: 1
            case .twoPaneBinary: 2
            case .twoPaneImage: 3
            case .twoPaneWebpage: 4
            case .twoPaneFolder: 5
            case .threePaneText: 6
            case .threePaneTable: 7
            case .threePaneBinary: 8
            case .threePaneImage: 9
            case .threePaneWebpage: 10
            case .threePaneFolder: 11
            }
        }
    }

    public enum PrimaryActionPolicy: String, CaseIterable, Hashable, Sendable {
        /// The main button and Command-N always route to two-pane Text. Selection never changes it.
        case fixedIDFileNew

        public var commandID: CommandID { .twoPaneText }
    }

    public enum InvocationKind: String, CaseIterable, Hashable, Sendable {
        case keyboardShortcut
        case menuItem
        case toolbarPrimaryAction
        case toolbarSecondaryAction
        case voiceOverPrimaryAction
        case voiceOverSecondaryAction

        public var isPrimary: Bool {
            switch self {
            case .keyboardShortcut, .toolbarPrimaryAction, .voiceOverPrimaryAction: true
            case .menuItem, .toolbarSecondaryAction, .voiceOverSecondaryAction: false
            }
        }
    }

    /// Localization lookup intent only. None of these raw values is display text.
    public enum LabelIntent: String, CaseIterable, Hashable, Sendable {
        case splitButton = "command.new.splitButton"
        case twoPaneGroup = "command.new.group.twoPane"
        case threePaneGroup = "command.new.group.threePane"
        case text = "command.new.mode.text"
        case table = "command.new.mode.table"
        case binary = "command.new.mode.binary"
        case image = "command.new.mode.image"
        case webpage = "command.new.mode.webpage"
        case folder = "command.new.mode.folder"
        case twoPaneText = "command.new.action.twoPane.text"
        case twoPaneTable = "command.new.action.twoPane.table"
        case twoPaneBinary = "command.new.action.twoPane.binary"
        case twoPaneImage = "command.new.action.twoPane.image"
        case twoPaneWebpage = "command.new.action.twoPane.webpage"
        case twoPaneFolder = "command.new.action.twoPane.folder"
        case threePaneText = "command.new.action.threePane.text"
        case threePaneTable = "command.new.action.threePane.table"
        case threePaneBinary = "command.new.action.threePane.binary"
        case threePaneImage = "command.new.action.threePane.image"
        case threePaneWebpage = "command.new.action.threePane.webpage"
        case threePaneFolder = "command.new.action.threePane.folder"
    }

    public enum MenuGroup: Int, CaseIterable, Comparable, Hashable, Sendable {
        case twoPane
        case threePane

        public static func < (left: MenuGroup, right: MenuGroup) -> Bool {
            left.rawValue < right.rawValue
        }

        public var labelIntent: LabelIntent {
            switch self {
            case .twoPane: .twoPaneGroup
            case .threePane: .threePaneGroup
            }
        }
    }

    public enum ActionPresentation: String, Hashable, Sendable {
        /// Unsupported actions remain represented and disabled; callers must not omit them.
        case visible
    }

    public enum CommandGate: Equatable, Hashable, Sendable {
        case enabled
        case disabled(ComparisonCommandState.DisabledReason)

        public init(comparisonContext: ComparisonCommandState.Context) {
            let resolution = ComparisonCommandState.resolve(.newComparison, in: comparisonContext)
            if let reason = resolution.disabledReason {
                self = .disabled(reason)
            } else {
                self = .enabled
            }
        }

        public var isEnabled: Bool { self == .enabled }
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case unsupportedMode(Mode)
        case unsupportedPaneCount(mode: Mode, paneCount: PaneCount)
        case commandState(ComparisonCommandState.DisabledReason)
        case planningFailure(NewDocumentRoutingPlannerStage)
    }

    public enum Availability: Equatable, Hashable, Sendable {
        case enabled
        case disabled(DisabledReason)

        public var isEnabled: Bool { self == .enabled }

        public var disabledReason: DisabledReason? {
            guard case .disabled(let reason) = self else { return nil }
            return reason
        }
    }

    public struct Revision: RawRepresentable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: Revision, right: Revision) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public struct SnapshotIdentity: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let lineage: UUID
        public let generation: UInt64

        public init(lineage: UUID, generation: UInt64) {
            self.lineage = lineage
            self.generation = generation
        }

        public var description: String {
            "NewDocumentRoutingPolicy.SnapshotIdentity(lineage: <redacted>, generation: \(generation))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["lineage": "<redacted>", "generation": generation],
                displayStyle: .struct
            )
        }
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumCommandCount = CommandID.allCases.count
        public static let hardMaximumWorkUnits = 1_000_000
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let hardMaximumConsumedReceiptCount = 1_000_000
        public static let `default` = Limits()

        public let maximumCommandCount: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int
        public let maximumConsumedReceiptCount: Int

        public init(
            maximumCommandCount: Int = CommandID.allCases.count,
            maximumWorkUnits: Int = 4_096,
            cancellationCheckInterval: Int = 32,
            maximumConsumedReceiptCount: Int = 65_536
        ) {
            self.maximumCommandCount = maximumCommandCount
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
            self.maximumConsumedReceiptCount = maximumConsumedReceiptCount
        }

        fileprivate func validate() throws(NewDocumentRoutingPolicyError) {
            guard (1...Self.hardMaximumCommandCount).contains(maximumCommandCount) else {
                throw .invalidLimit(.commandCount, value: maximumCommandCount)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw .invalidLimit(.workUnits, value: maximumWorkUnits)
            }
            guard
                (1...Self.hardMaximumCancellationCheckInterval).contains(
                    cancellationCheckInterval
                )
            else {
                throw .invalidLimit(
                    .cancellationCheckInterval,
                    value: cancellationCheckInterval
                )
            }
            guard
                (1...Self.hardMaximumConsumedReceiptCount).contains(
                    maximumConsumedReceiptCount
                )
            else {
                throw .invalidLimit(
                    .consumedReceiptCount,
                    value: maximumConsumedReceiptCount
                )
            }
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case commandCount
        case workUnits
        case cancellationCheckInterval
        case consumedReceiptCount
    }

    /// Exact defaults used by conversion. Revision reuse with different values is rejected.
    public struct DefaultsSnapshot: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let revision: Revision
        public let primaryActionPolicy: PrimaryActionPolicy
        public let comparisonOpenRequestLimits: ComparisonOpenRequestLimits
        public let documentPlanLimits: NewComparisonDocumentPlan.Limits
        public let routingLimits: Limits

        public init(
            revision: Revision,
            primaryActionPolicy: PrimaryActionPolicy = .fixedIDFileNew,
            comparisonOpenRequestLimits: ComparisonOpenRequestLimits = .default,
            documentPlanLimits: NewComparisonDocumentPlan.Limits = .default,
            routingLimits: Limits = .default
        ) {
            self.revision = revision
            self.primaryActionPolicy = primaryActionPolicy
            self.comparisonOpenRequestLimits = comparisonOpenRequestLimits
            self.documentPlanLimits = documentPlanLimits
            self.routingLimits = routingLimits
        }

        public static func current(revision: Revision) -> DefaultsSnapshot {
            DefaultsSnapshot(revision: revision)
        }

        public var description: String {
            "NewDocumentRoutingPolicy.DefaultsSnapshot(revision: \(revision.rawValue), primaryActionPolicy: \(primaryActionPolicy.rawValue), defaults: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "revision": revision.rawValue,
                    "primaryActionPolicy": primaryActionPolicy.rawValue,
                    "defaults": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Concrete option families captured from one owner revision. `.defaults` is never deferred.
    public struct OptionsSnapshot: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let revision: Revision
        public let textTwoWay: LineDiffOptions
        public let textThreeWay: ThreeWayTextMergeOptions
        public let tableParsing: DelimitedTableParsingOptions
        public let tableTwoWay: TableComparisonOptions
        public let tableThreeWay: ThreeWayTableComparisonOptions
        public let binaryTwoWay: BinaryComparisonOptions
        public let binaryThreeWay: ThreeWayBinaryComparisonOptions
        public let imageLoading: ImageComparisonLimits
        public let imageComparison: ImageComparisonOptions
        public let webpageTwoWay: WebPageComparisonOptions
        public let webpageThreeWay: ThreeWayWebPageComparisonOptions
        public let folderScanning: FolderScanOptions
        public let folderTwoWay: FolderComparisonOptions
        public let folderThreeWay: ThreeWayFolderComparisonOptions

        public init(
            revision: Revision,
            textTwoWay: LineDiffOptions = LineDiffOptions(),
            textThreeWay: ThreeWayTextMergeOptions = ThreeWayTextMergeOptions(),
            tableParsing: DelimitedTableParsingOptions = .commaSeparated,
            tableTwoWay: TableComparisonOptions = .default,
            tableThreeWay: ThreeWayTableComparisonOptions = .default,
            binaryTwoWay: BinaryComparisonOptions = BinaryComparisonOptions(),
            binaryThreeWay: ThreeWayBinaryComparisonOptions = .default,
            imageLoading: ImageComparisonLimits = .default,
            imageComparison: ImageComparisonOptions = .default,
            webpageTwoWay: WebPageComparisonOptions = .default,
            webpageThreeWay: ThreeWayWebPageComparisonOptions = .default,
            folderScanning: FolderScanOptions = FolderScanOptions(),
            folderTwoWay: FolderComparisonOptions = FolderComparisonOptions(),
            folderThreeWay: ThreeWayFolderComparisonOptions = .default
        ) {
            self.revision = revision
            self.textTwoWay = textTwoWay
            self.textThreeWay = textThreeWay
            self.tableParsing = tableParsing
            self.tableTwoWay = tableTwoWay
            self.tableThreeWay = tableThreeWay
            self.binaryTwoWay = binaryTwoWay
            self.binaryThreeWay = binaryThreeWay
            self.imageLoading = imageLoading
            self.imageComparison = imageComparison
            self.webpageTwoWay = webpageTwoWay
            self.webpageThreeWay = webpageThreeWay
            self.folderScanning = folderScanning
            self.folderTwoWay = folderTwoWay
            self.folderThreeWay = folderThreeWay
        }

        public static func current(revision: Revision) -> OptionsSnapshot {
            OptionsSnapshot(revision: revision)
        }

        public func modeOptions(for mode: Mode) -> ComparisonOpenModeOptions {
            switch mode {
            case .text:
                .text(twoWay: textTwoWay, threeWay: textThreeWay)
            case .table:
                .table(
                    parsing: tableParsing,
                    twoWay: tableTwoWay,
                    threeWay: tableThreeWay
                )
            case .binary:
                .binary(twoWay: binaryTwoWay, threeWay: binaryThreeWay)
            case .image:
                .image(loading: imageLoading, comparison: imageComparison)
            case .webpage:
                .webpage(twoWay: webpageTwoWay, threeWay: webpageThreeWay)
            case .folder:
                .folder(
                    scanning: folderScanning,
                    twoWay: folderTwoWay,
                    threeWay: folderThreeWay
                )
            }
        }

        public var description: String {
            "NewDocumentRoutingPolicy.OptionsSnapshot(revision: \(revision.rawValue), options: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["revision": revision.rawValue, "options": "<redacted>"],
                displayStyle: .struct
            )
        }
    }

    /// Capability state remains revisioned even when a mode is unsupported. Commands stay visible.
    public struct CapabilitySnapshot: Equatable, Sendable {
        public let revision: Revision
        public let twoPaneModes: Set<Mode>
        public let threePaneModes: Set<Mode>

        public init(
            revision: Revision,
            twoPaneModes: Set<Mode> = Set(Mode.allCases),
            threePaneModes: Set<Mode> = Set(Mode.allCases)
        ) {
            self.revision = revision
            self.twoPaneModes = twoPaneModes
            self.threePaneModes = threePaneModes
        }

        public static func allSupported(revision: Revision) -> CapabilitySnapshot {
            CapabilitySnapshot(revision: revision)
        }

        public func supports(mode: Mode, paneCount: PaneCount) -> Bool {
            switch paneCount {
            case .two: twoPaneModes.contains(mode)
            case .three: threePaneModes.contains(mode)
            }
        }

        public func supports(mode: Mode) -> Bool {
            twoPaneModes.contains(mode) || threePaneModes.contains(mode)
        }
    }

    fileprivate struct PlanningFailure: Equatable, Sendable {
        let stage: NewDocumentRoutingPlannerStage
        let error: NewDocumentRoutingPolicyError

        init(_ error: NewDocumentRoutingPolicyError) {
            self.error = error
            switch error {
            case .comparisonOpenRequest:
                stage = .comparisonOpenRequest
            case .nonConcreteModeOptions:
                stage = .validatedModeOptions
            case .newComparisonDocumentPlan:
                stage = .newComparisonDocumentPlan
            case .unexpectedPlannerFailure(let stage):
                self.stage = stage
            default:
                stage = .newComparisonDocumentPlan
            }
        }
    }

    public struct Snapshot: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: SnapshotIdentity
        public let commandGate: CommandGate
        public let capabilities: CapabilitySnapshot
        public let defaults: DefaultsSnapshot
        public let options: OptionsSnapshot
        fileprivate let planningFailures: [CommandID: PlanningFailure]

        public init(
            identity: SnapshotIdentity,
            commandGate: CommandGate,
            capabilities: CapabilitySnapshot,
            defaults: DefaultsSnapshot,
            options: OptionsSnapshot,
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) throws(NewDocumentRoutingPolicyError) {
            try defaults.routingLimits.validate()
            guard CommandID.allCases.count <= defaults.routingLimits.maximumCommandCount else {
                throw .commandLimitExceeded(
                    maximum: defaults.routingLimits.maximumCommandCount
                )
            }
            var work = try Work(
                limits: defaults.routingLimits,
                cancellationCheck: cancellationCheck
            )
            try work.checkCancellation()
            let planningFailures = try NewDocumentRoutingPolicy.preflightPlanning(
                commandGate: commandGate,
                capabilities: capabilities,
                defaults: defaults,
                options: options,
                work: &work
            )
            try work.checkCancellation()
            self.identity = identity
            self.commandGate = commandGate
            self.capabilities = capabilities
            self.defaults = defaults
            self.options = options
            self.planningFailures = planningFailures
        }

        public var fingerprint: SnapshotFingerprint {
            SnapshotFingerprint(self)
        }

        public var description: String {
            "NewDocumentRoutingPolicy.Snapshot(generation: \(identity.generation), defaultsRevision: \(defaults.revision.rawValue), optionsRevision: \(options.revision.rawValue), capabilitiesRevision: \(capabilities.revision.rawValue), payloads: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "identity": identity,
                    "commandEnabled": commandGate.isEnabled,
                    "defaultsRevision": defaults.revision.rawValue,
                    "optionsRevision": options.revision.rawValue,
                    "capabilitiesRevision": capabilities.revision.rawValue,
                    "planningFailureCount": planningFailures.count,
                    "payloads": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct SnapshotFingerprint: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let identity: SnapshotIdentity
        public let defaultsRevision: Revision
        public let optionsRevision: Revision
        public let capabilitiesRevision: Revision

        private let commandGate: CommandGate
        private let capabilities: CapabilitySnapshot
        private let defaults: DefaultsSnapshot
        private let options: OptionsSnapshot

        fileprivate init(_ snapshot: Snapshot) {
            identity = snapshot.identity
            defaultsRevision = snapshot.defaults.revision
            optionsRevision = snapshot.options.revision
            capabilitiesRevision = snapshot.capabilities.revision
            commandGate = snapshot.commandGate
            capabilities = snapshot.capabilities
            defaults = snapshot.defaults
            options = snapshot.options
        }

        public var description: String {
            "NewDocumentRoutingPolicy.SnapshotFingerprint(generation: \(identity.generation), defaultsRevision: \(defaultsRevision.rawValue), optionsRevision: \(optionsRevision.rawValue), capabilitiesRevision: \(capabilitiesRevision.rawValue), bindings: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "identity": identity,
                    "defaultsRevision": defaultsRevision.rawValue,
                    "optionsRevision": optionsRevision.rawValue,
                    "capabilitiesRevision": capabilitiesRevision.rawValue,
                    "bindings": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func validateCurrent(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) throws(NewDocumentRoutingPolicyError) {
            try cancellationCheck()
            guard identity.lineage == snapshot.identity.lineage else {
                throw .staleSnapshot(expected: identity, actual: snapshot.identity)
            }
            guard defaultsRevision == snapshot.defaults.revision else {
                throw .staleDefaults(
                    expected: defaultsRevision,
                    actual: snapshot.defaults.revision
                )
            }
            guard optionsRevision == snapshot.options.revision else {
                throw .staleOptions(
                    expected: optionsRevision,
                    actual: snapshot.options.revision
                )
            }
            guard capabilitiesRevision == snapshot.capabilities.revision else {
                throw .staleCapabilities(
                    expected: capabilitiesRevision,
                    actual: snapshot.capabilities.revision
                )
            }
            guard identity.generation == snapshot.identity.generation else {
                throw .staleSnapshot(expected: identity, actual: snapshot.identity)
            }
            guard defaults == snapshot.defaults else {
                throw .defaultsRevisionCollision(defaultsRevision)
            }
            try cancellationCheck()
            guard options == snapshot.options else {
                throw .optionsRevisionCollision(optionsRevision)
            }
            try cancellationCheck()
            guard capabilities == snapshot.capabilities else {
                throw .capabilitiesRevisionCollision(capabilitiesRevision)
            }
            guard commandGate == snapshot.commandGate else {
                throw .snapshotRevisionCollision(identity)
            }
            try cancellationCheck()
        }
    }

    public struct MenuPlacement: Equatable, Hashable, Sendable {
        public let group: MenuGroup
        public let groupOrder: Int
        public let itemOrder: Int

        fileprivate init(commandID: CommandID) {
            group = commandID.paneCount == .two ? .twoPane : .threePane
            groupOrder = group.rawValue
            itemOrder = commandID.order % Mode.allCases.count
        }
    }

    public struct ActionDescriptor: Equatable, Sendable {
        public let commandID: CommandID
        public let mode: Mode
        public let paneCount: PaneCount
        public let menuLabelIntent: LabelIntent
        public let actionLabelIntent: LabelIntent
        public let menuPlacement: MenuPlacement?
        public let invocationKinds: Set<InvocationKind>
        public let presentation: ActionPresentation
        public let availability: Availability

        public var isEnabled: Bool { availability.isEnabled }
        public var disabledReason: DisabledReason? { availability.disabledReason }
    }

    public struct MenuGroupDescriptor: Equatable, Sendable {
        public let group: MenuGroup
        public let order: Int
        public let labelIntent: LabelIntent
        public let actions: [ActionDescriptor]

        fileprivate init(group: MenuGroup, actions: [ActionDescriptor]) {
            self.group = group
            order = group.rawValue
            labelIntent = group.labelIntent
            self.actions = actions
        }
    }

    public struct Presentation: Equatable, Sendable {
        public let primaryActionPolicy: PrimaryActionPolicy
        public let splitButtonLabelIntent: LabelIntent
        public let primaryAction: ActionDescriptor
        public let menuGroups: [MenuGroupDescriptor]
        public let workPerformed: Int

        public var secondaryActions: [ActionDescriptor] {
            menuGroups.flatMap(\.actions)
        }

        fileprivate init(
            primaryActionPolicy: PrimaryActionPolicy,
            primaryAction: ActionDescriptor,
            menuGroups: [MenuGroupDescriptor],
            workPerformed: Int
        ) {
            self.primaryActionPolicy = primaryActionPolicy
            splitButtonLabelIntent = .splitButton
            self.primaryAction = primaryAction
            self.menuGroups = menuGroups
            self.workPerformed = workPerformed
        }
    }

    public struct InvocationID: RawRepresentable, Equatable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var description: String { "NewDocumentRoutingPolicy.InvocationID(<redacted>)" }
        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct Invocation: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let id: InvocationID
        public let kind: InvocationKind
        /// Must be nil for primary kinds and nonnil for secondary kinds.
        public let commandID: CommandID?

        public init(id: InvocationID, kind: InvocationKind, commandID: CommandID? = nil) {
            self.id = id
            self.kind = kind
            self.commandID = commandID
        }

        public var description: String {
            "NewDocumentRoutingPolicy.Invocation(kind: \(kind.rawValue), commandID: \(commandID?.rawValue ?? "none"), id: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "id": "<redacted>",
                    "kind": kind.rawValue,
                    "commandID": commandID?.rawValue as Any
                ],
                displayStyle: .struct
            )
        }
    }

    /// Resolved invocation bound to exact current defaults, options, capabilities, and command state.
    public struct Request: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let invocation: Invocation
        public let commandID: CommandID
        public let expectedSnapshotFingerprint: SnapshotFingerprint
        public let routingWorkPerformed: Int

        fileprivate init(
            invocation: Invocation,
            commandID: CommandID,
            expectedSnapshotFingerprint: SnapshotFingerprint,
            routingWorkPerformed: Int
        ) {
            self.invocation = invocation
            self.commandID = commandID
            self.expectedSnapshotFingerprint = expectedSnapshotFingerprint
            self.routingWorkPerformed = routingWorkPerformed
        }

        public var description: String {
            "NewDocumentRoutingPolicy.Request(kind: \(invocation.kind.rawValue), commandID: \(commandID.rawValue), routingWorkPerformed: \(routingWorkPerformed), bindings: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "invocationKind": invocation.kind.rawValue,
                    "commandID": commandID.rawValue,
                    "routingWorkPerformed": routingWorkPerformed,
                    "identifiers": "<redacted>",
                    "snapshotBindings": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func validateCurrentSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) throws(NewDocumentRoutingPolicyError) {
            try expectedSnapshotFingerprint.validateCurrent(
                snapshot,
                cancellationCheck: cancellationCheck
            )
        }
    }

    /// Internal deterministic bridge into `ComparisonOpenRequestPlanner` and document planning.
    private struct PlanInputs: Equatable, Sendable {
        let routingRequest: Request
        /// Synthetic, in-memory validation request. Its local URLs are lexical probes only.
        let optionValidationRequest: ComparisonOpenRequest
        let documentCommand: NewComparisonDocumentPlan.Command
        let scratchpads: [NewComparisonDocumentPlan.Scratchpad]?
        let documentPlanLimits: NewComparisonDocumentPlan.Limits
        let routingWorkPerformed: Int

    }

    public struct ReceiptID: RawRepresentable, Equatable, Hashable, Sendable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var description: String { "NewDocumentRoutingPolicy.ReceiptID(<redacted>)" }
        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct Receipt: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let id: ReceiptID
        public let ledgerID: ReceiptLedger.ID
        public let invocationKind: InvocationKind
        public let commandID: CommandID
        public let expectedSnapshotFingerprint: SnapshotFingerprint
        public let defaultsRevision: Revision
        public let optionsRevision: Revision

        fileprivate init(
            request: Request,
            ledgerID: ReceiptLedger.ID
        ) {
            id = ReceiptID(rawValue: request.invocation.id.rawValue)
            self.ledgerID = ledgerID
            invocationKind = request.invocation.kind
            commandID = request.commandID
            expectedSnapshotFingerprint = request.expectedSnapshotFingerprint
            defaultsRevision = request.expectedSnapshotFingerprint.defaultsRevision
            optionsRevision = request.expectedSnapshotFingerprint.optionsRevision
        }

        public var description: String {
            "NewDocumentRoutingPolicy.Receipt(invocationKind: \(invocationKind.rawValue), commandID: \(commandID.rawValue), defaultsRevision: \(defaultsRevision.rawValue), optionsRevision: \(optionsRevision.rawValue), identifiers: <redacted>, snapshotBindings: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "invocationKind": invocationKind.rawValue,
                    "commandID": commandID.rawValue,
                    "defaultsRevision": defaultsRevision.rawValue,
                    "optionsRevision": optionsRevision.rawValue,
                    "identifiers": "<redacted>",
                    "snapshotBindings": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func validateCurrentSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) throws(NewDocumentRoutingPolicyError) {
            try expectedSnapshotFingerprint.validateCurrent(
                snapshot,
                cancellationCheck: cancellationCheck
            )
        }
    }

    public struct Plan: Equatable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let receipt: Receipt
        public let routingWorkPerformed: Int
        public let documentPlanningWorkPerformed: Int

        fileprivate let documentPlan: NewComparisonDocumentPlan

        fileprivate init(
            documentPlan: NewComparisonDocumentPlan,
            receipt: Receipt,
            routingWorkPerformed: Int
        ) {
            self.documentPlan = documentPlan
            self.receipt = receipt
            self.routingWorkPerformed = routingWorkPerformed
            documentPlanningWorkPerformed = documentPlan.workPerformed
        }

        public var description: String {
            "NewDocumentRoutingPolicy.Plan(commandID: \(receipt.commandID.rawValue), routingWorkPerformed: \(routingWorkPerformed), documentPlanningWorkPerformed: \(documentPlanningWorkPerformed), documentPlan: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "receipt": receipt,
                    "routingWorkPerformed": routingWorkPerformed,
                    "documentPlanningWorkPerformed": documentPlanningWorkPerformed,
                    "documentPlan": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public func validateCurrentSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) throws(NewDocumentRoutingPolicyError) {
            try receipt.validateCurrentSnapshot(
                snapshot,
                cancellationCheck: cancellationCheck
            )
        }
    }

    public struct ExecutionAuthorization: Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        private let receiptID: ReceiptID
        private let receiptLedger: ReceiptLedger

        fileprivate init(receiptID: ReceiptID, receiptLedger: ReceiptLedger) {
            self.receiptID = receiptID
            self.receiptLedger = receiptLedger
        }

        public var description: String {
            "NewDocumentRoutingPolicy.ExecutionAuthorization(receiptID: <redacted>, ledger: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["receiptID": "<redacted>", "ledger": "<redacted>"],
                displayStyle: .struct
            )
        }

        /// Transfers the authorized document plan exactly once.
        public func consume(
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) async throws(NewDocumentRoutingPolicyError)
            -> NewComparisonDocumentPlan
        {
            try await receiptLedger.consumeAuthorization(
                receiptID,
                cancellationCheck: cancellationCheck
            )
        }
    }

    /// Actor isolation makes freshness validation and one-shot receipt consumption one operation.
    public actor ReceiptLedger: CustomStringConvertible, CustomDebugStringConvertible,
        CustomReflectable
    {
        public struct ID: RawRepresentable, Equatable, Hashable, Sendable,
            CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
        {
            public let rawValue: UUID

            public init(rawValue: UUID = UUID()) {
                self.rawValue = rawValue
            }

            public var description: String {
                "NewDocumentRoutingPolicy.ReceiptLedger.ID(<redacted>)"
            }

            public var debugDescription: String { description }

            public var customMirror: Mirror {
                Mirror(self, children: ["rawValue": "<redacted>"], displayStyle: .struct)
            }
        }

        public nonisolated let id: ID
        public nonisolated let limits: Limits
        private let lineage: UUID
        private var authoritativeSnapshot: Snapshot
        private var consumedReceiptIDs: Set<ReceiptID> = []
        private var authorizedPlans: [ReceiptID: Plan] = [:]

        public init(authoritativeSnapshot: Snapshot) throws(NewDocumentRoutingPolicyError) {
            try authoritativeSnapshot.defaults.routingLimits.validate()
            id = ID()
            limits = authoritativeSnapshot.defaults.routingLimits
            lineage = authoritativeSnapshot.identity.lineage
            self.authoritativeSnapshot = authoritativeSnapshot
        }

        public nonisolated var description: String {
            "NewDocumentRoutingPolicy.ReceiptLedger(id: <redacted>, state: <actor-isolated>)"
        }

        public nonisolated var debugDescription: String { description }

        public nonisolated var customMirror: Mirror {
            Mirror(
                self,
                children: ["id": "<redacted>", "state": "<actor-isolated>"],
                displayStyle: .class
            )
        }

        public var consumedReceiptCount: Int { consumedReceiptIDs.count }

        /// Replaces authoritative state without permitting lineage or generation rollback.
        public func updateAuthoritativeSnapshot(
            _ snapshot: Snapshot,
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) throws(NewDocumentRoutingPolicyError) {
            try cancellationCheck()
            guard snapshot.identity.lineage == lineage else {
                throw .staleSnapshot(
                    expected: authoritativeSnapshot.identity,
                    actual: snapshot.identity
                )
            }
            guard snapshot.identity.generation >= authoritativeSnapshot.identity.generation else {
                throw .snapshotRollback(
                    current: authoritativeSnapshot.identity,
                    proposed: snapshot.identity
                )
            }
            guard snapshot.defaults.routingLimits == limits else {
                throw .receiptLedgerLimitsMismatch
            }
            if snapshot.identity.generation == authoritativeSnapshot.identity.generation {
                try authoritativeSnapshot.fingerprint.validateCurrent(
                    snapshot,
                    cancellationCheck: cancellationCheck
                )
            } else {
                guard snapshot.defaults.revision >= authoritativeSnapshot.defaults.revision,
                    snapshot.options.revision >= authoritativeSnapshot.options.revision,
                    snapshot.capabilities.revision >= authoritativeSnapshot.capabilities.revision
                else {
                    throw .snapshotRollback(
                        current: authoritativeSnapshot.identity,
                        proposed: snapshot.identity
                    )
                }
                if snapshot.defaults.revision == authoritativeSnapshot.defaults.revision,
                    snapshot.defaults != authoritativeSnapshot.defaults
                {
                    throw .defaultsRevisionCollision(snapshot.defaults.revision)
                }
                try cancellationCheck()
                if snapshot.options.revision == authoritativeSnapshot.options.revision,
                    snapshot.options != authoritativeSnapshot.options
                {
                    throw .optionsRevisionCollision(snapshot.options.revision)
                }
                try cancellationCheck()
                if snapshot.capabilities.revision == authoritativeSnapshot.capabilities.revision,
                    snapshot.capabilities != authoritativeSnapshot.capabilities
                {
                    throw .capabilitiesRevisionCollision(snapshot.capabilities.revision)
                }
            }
            try cancellationCheck()
            if snapshot.identity.generation > authoritativeSnapshot.identity.generation {
                authorizedPlans.removeAll(keepingCapacity: false)
            }
            authoritativeSnapshot = snapshot
        }

        /// Checks authoritative freshness and consumes receipt in this actor turn.
        public func consume(
            _ plan: Plan,
            cancellationCheck: @escaping CancellationCheck =
                NewDocumentRoutingPolicy.taskCancellationCheck
        ) throws(NewDocumentRoutingPolicyError) -> ExecutionAuthorization {
            try cancellationCheck()
            guard plan.receipt.ledgerID == id else {
                throw .receiptLedgerMismatch(expected: plan.receipt.ledgerID, actual: id)
            }
            guard !consumedReceiptIDs.contains(plan.receipt.id) else {
                throw .receiptAlreadyConsumed(plan.receipt.id)
            }
            try plan.validateCurrentSnapshot(
                authoritativeSnapshot,
                cancellationCheck: cancellationCheck
            )
            guard limits == authoritativeSnapshot.defaults.routingLimits else {
                throw .receiptLedgerLimitsMismatch
            }
            guard consumedReceiptIDs.count < limits.maximumConsumedReceiptCount else {
                throw .receiptLimitExceeded(maximum: limits.maximumConsumedReceiptCount)
            }
            try cancellationCheck()
            consumedReceiptIDs.insert(plan.receipt.id)
            authorizedPlans[plan.receipt.id] = plan
            return ExecutionAuthorization(receiptID: plan.receipt.id, receiptLedger: self)
        }

        fileprivate func consumeAuthorization(
            _ receiptID: ReceiptID,
            cancellationCheck: @escaping CancellationCheck
        ) throws(NewDocumentRoutingPolicyError) -> NewComparisonDocumentPlan {
            try cancellationCheck()
            guard let plan = authorizedPlans[receiptID] else {
                throw .executionAuthorizationAlreadyConsumed
            }
            do {
                try plan.validateCurrentSnapshot(
                    authoritativeSnapshot,
                    cancellationCheck: cancellationCheck
                )
            } catch let error {
                if error != .cancelled { authorizedPlans[receiptID] = nil }
                throw error
            }
            try cancellationCheck()
            authorizedPlans[receiptID] = nil
            return plan.documentPlan
        }
    }

    public static func presentation(
        in snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(NewDocumentRoutingPolicyError) -> Presentation {
        let limits = snapshot.defaults.routingLimits
        try limits.validate()
        guard CommandID.allCases.count <= limits.maximumCommandCount else {
            throw .commandLimitExceeded(maximum: limits.maximumCommandCount)
        }
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try work.checkCancellation()

        var actions: [ActionDescriptor] = []
        actions.reserveCapacity(CommandID.allCases.count)
        for commandID in CommandID.allCases {
            try work.consume()
            actions.append(secondaryDescriptor(commandID, snapshot: snapshot))
        }
        let groups = MenuGroup.allCases.map { group in
            MenuGroupDescriptor(
                group: group,
                actions: actions.filter { $0.menuPlacement?.group == group }
            )
        }
        try work.consume(groups.count)
        let primaryCommand = snapshot.defaults.primaryActionPolicy.commandID
        let primary = primaryDescriptor(primaryCommand, snapshot: snapshot)
        try work.consume()
        try work.checkCancellation()
        return Presentation(
            primaryActionPolicy: snapshot.defaults.primaryActionPolicy,
            primaryAction: primary,
            menuGroups: groups,
            workPerformed: work.completed
        )
    }

    public static func makeRequest(
        for invocation: Invocation,
        in snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(NewDocumentRoutingPolicyError) -> Request {
        let limits = snapshot.defaults.routingLimits
        try limits.validate()
        var work = try Work(limits: limits, cancellationCheck: cancellationCheck)
        try work.checkCancellation()

        let commandID: CommandID
        if invocation.kind.isPrimary {
            guard invocation.commandID == nil else {
                throw .unexpectedCommandForPrimaryInvocation(
                    kind: invocation.kind,
                    commandID: invocation.commandID!
                )
            }
            commandID = snapshot.defaults.primaryActionPolicy.commandID
        } else {
            guard let requestedCommand = invocation.commandID else {
                throw .missingCommandForSecondaryInvocation(invocation.kind)
            }
            commandID = requestedCommand
        }
        try work.consume()
        try requireAvailable(commandID, in: snapshot)
        try work.consume()
        try work.checkCancellation()
        return Request(
            invocation: invocation,
            commandID: commandID,
            expectedSnapshotFingerprint: snapshot.fingerprint,
            routingWorkPerformed: work.completed
        )
    }

    private static func makePlanInputs(
        for request: Request,
        currentSnapshot snapshot: Snapshot,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(NewDocumentRoutingPolicyError) -> PlanInputs {
        try request.validateCurrentSnapshot(
            snapshot,
            cancellationCheck: cancellationCheck
        )
        let limits = snapshot.defaults.routingLimits
        var work = try Work(
            limits: limits,
            completed: request.routingWorkPerformed,
            cancellationCheck: cancellationCheck
        )
        try work.checkCancellation()
        try requireAvailable(request.commandID, in: snapshot)
        try work.consume()

        let commandID = request.commandID
        let validationRequest = try optionValidationRequest(
            invocationID: request.invocation.id,
            commandID: commandID,
            options: snapshot.options.modeOptions(for: commandID.mode),
            limits: snapshot.defaults.comparisonOpenRequestLimits,
            work: &work
        )
        try work.checkCancellation()
        return PlanInputs(
            routingRequest: request,
            optionValidationRequest: validationRequest,
            documentCommand: commandID.documentCommand,
            scratchpads: nil,
            documentPlanLimits: snapshot.defaults.documentPlanLimits,
            routingWorkPerformed: work.completed
        )
    }

    public static func plan(
        _ request: Request,
        currentSnapshot snapshot: Snapshot,
        receiptLedger: ReceiptLedger,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(NewDocumentRoutingPolicyError) -> Plan {
        let inputs = try makePlanInputs(
            for: request,
            currentSnapshot: snapshot,
            cancellationCheck: cancellationCheck
        )
        return try plan(
            inputs,
            currentSnapshot: snapshot,
            receiptLedger: receiptLedger,
            cancellationCheck: cancellationCheck
        )
    }

    private static func plan(
        _ inputs: PlanInputs,
        currentSnapshot snapshot: Snapshot,
        receiptLedger: ReceiptLedger,
        cancellationCheck: @escaping CancellationCheck = taskCancellationCheck
    ) throws(NewDocumentRoutingPolicyError) -> Plan {
        try inputs.routingRequest.validateCurrentSnapshot(
            snapshot,
            cancellationCheck: cancellationCheck
        )
        guard receiptLedger.limits == snapshot.defaults.routingLimits else {
            throw .receiptLedgerLimitsMismatch
        }
        let limits = snapshot.defaults.routingLimits
        var work = try Work(
            limits: limits,
            completed: inputs.routingWorkPerformed,
            cancellationCheck: cancellationCheck
        )
        try work.checkCancellation()

        let openPlan: ComparisonOpenPlan
        try work.consume()
        try work.checkCancellation()
        do {
            // Nested planner only observes task cancellation. It has no side effects, so checking
            // immediately after it prevents a custom cancellation from publishing its result.
            openPlan = try ComparisonOpenRequestPlanner.plan(
                inputs.optionValidationRequest,
                expecting: inputs.optionValidationRequest.identity
            )
        } catch let error as ComparisonOpenRequestError {
            if error == .cancelled { throw .cancelled }
            throw .comparisonOpenRequest(error)
        } catch {
            throw .unexpectedPlannerFailure(.comparisonOpenRequest)
        }
        try work.checkCancellation()

        let validatedOptions: NewComparisonDocumentPlan.ValidatedModeOptions
        try work.consume()
        try work.checkCancellation()
        do {
            guard
                let value = try NewComparisonDocumentPlan.ValidatedModeOptions(
                    openPlan,
                    currentRequest: inputs.optionValidationRequest
                )
            else {
                throw NewDocumentRoutingPolicyError.nonConcreteModeOptions(
                    inputs.routingRequest.commandID.mode
                )
            }
            validatedOptions = value
        } catch let error as NewDocumentRoutingPolicyError {
            throw error
        } catch let error as ComparisonOpenRequestError {
            throw .comparisonOpenRequest(error)
        } catch {
            throw .unexpectedPlannerFailure(.validatedModeOptions)
        }

        let documentPlan: NewComparisonDocumentPlan
        try work.consume()
        try work.checkCancellation()
        do {
            documentPlan = try NewComparisonDocumentPlan.make(
                command: inputs.documentCommand,
                scratchpads: inputs.scratchpads,
                modeOptions: validatedOptions,
                limits: inputs.documentPlanLimits,
                cancellationCheck: cancellationCheck
            )
        } catch let error as NewDocumentRoutingPolicyError {
            throw error
        } catch let error as NewComparisonDocumentPlanError {
            if error == .cancelled { throw .cancelled }
            throw .newComparisonDocumentPlan(error)
        } catch {
            throw .unexpectedPlannerFailure(.newComparisonDocumentPlan)
        }
        try work.checkCancellation()
        let receipt = Receipt(
            request: inputs.routingRequest,
            ledgerID: receiptLedger.id
        )
        return Plan(
            documentPlan: documentPlan,
            receipt: receipt,
            routingWorkPerformed: work.completed
        )
    }

    public static func availability(
        of commandID: CommandID,
        in snapshot: Snapshot
    ) -> Availability {
        let baseAvailability = baseAvailability(
            of: commandID,
            commandGate: snapshot.commandGate,
            capabilities: snapshot.capabilities
        )
        guard baseAvailability.isEnabled else { return baseAvailability }
        if let failure = snapshot.planningFailures[commandID] {
            return .disabled(.planningFailure(failure.stage))
        }
        guard
            commandID.paneCount.rawValue
                <= snapshot.defaults.documentPlanLimits.maximumPaneCount
        else {
            return .disabled(
                .unsupportedPaneCount(mode: commandID.mode, paneCount: commandID.paneCount)
            )
        }
        return .enabled
    }

    private static func baseAvailability(
        of commandID: CommandID,
        commandGate: CommandGate,
        capabilities: CapabilitySnapshot
    ) -> Availability {
        guard capabilities.supports(mode: commandID.mode) else {
            return .disabled(.unsupportedMode(commandID.mode))
        }
        guard capabilities.supports(mode: commandID.mode, paneCount: commandID.paneCount) else {
            return .disabled(
                .unsupportedPaneCount(mode: commandID.mode, paneCount: commandID.paneCount)
            )
        }
        switch commandGate {
        case .enabled:
            return .enabled
        case .disabled(let reason):
            return .disabled(.commandState(reason))
        }
    }

    private static func requireAvailable(
        _ commandID: CommandID,
        in snapshot: Snapshot
    ) throws(NewDocumentRoutingPolicyError) {
        guard case .disabled(let reason) = availability(of: commandID, in: snapshot) else {
            return
        }
        switch reason {
        case .unsupportedMode(let mode):
            throw .unsupportedMode(mode)
        case .unsupportedPaneCount(let mode, let paneCount):
            throw .unsupportedPaneCount(mode: mode, paneCount: paneCount)
        case .commandState(let stateReason):
            throw .commandDisabled(commandID, reason: stateReason)
        case .planningFailure:
            guard let failure = snapshot.planningFailures[commandID] else {
                throw .unexpectedPlannerFailure(.newComparisonDocumentPlan)
            }
            throw failure.error
        }
    }

    private static func primaryDescriptor(
        _ commandID: CommandID,
        snapshot: Snapshot
    ) -> ActionDescriptor {
        ActionDescriptor(
            commandID: commandID,
            mode: commandID.mode,
            paneCount: commandID.paneCount,
            menuLabelIntent: modeLabelIntent(commandID.mode),
            actionLabelIntent: actionLabelIntent(commandID),
            menuPlacement: nil,
            invocationKinds: [
                .keyboardShortcut,
                .toolbarPrimaryAction,
                .voiceOverPrimaryAction
            ],
            presentation: .visible,
            availability: availability(of: commandID, in: snapshot)
        )
    }

    private static func secondaryDescriptor(
        _ commandID: CommandID,
        snapshot: Snapshot
    ) -> ActionDescriptor {
        ActionDescriptor(
            commandID: commandID,
            mode: commandID.mode,
            paneCount: commandID.paneCount,
            menuLabelIntent: modeLabelIntent(commandID.mode),
            actionLabelIntent: actionLabelIntent(commandID),
            menuPlacement: MenuPlacement(commandID: commandID),
            invocationKinds: [
                .menuItem,
                .toolbarSecondaryAction,
                .voiceOverSecondaryAction
            ],
            presentation: .visible,
            availability: availability(of: commandID, in: snapshot)
        )
    }

    private static func modeLabelIntent(_ mode: Mode) -> LabelIntent {
        switch mode {
        case .text: .text
        case .table: .table
        case .binary: .binary
        case .image: .image
        case .webpage: .webpage
        case .folder: .folder
        }
    }

    private static func actionLabelIntent(_ commandID: CommandID) -> LabelIntent {
        switch commandID {
        case .twoPaneText: .twoPaneText
        case .twoPaneTable: .twoPaneTable
        case .twoPaneBinary: .twoPaneBinary
        case .twoPaneImage: .twoPaneImage
        case .twoPaneWebpage: .twoPaneWebpage
        case .twoPaneFolder: .twoPaneFolder
        case .threePaneText: .threePaneText
        case .threePaneTable: .threePaneTable
        case .threePaneBinary: .threePaneBinary
        case .threePaneImage: .threePaneImage
        case .threePaneWebpage: .threePaneWebpage
        case .threePaneFolder: .threePaneFolder
        }
    }

    private static func optionValidationRequest(
        invocationID: InvocationID,
        commandID: CommandID,
        options: ComparisonOpenModeOptions,
        limits: ComparisonOpenRequestLimits,
        work: inout Work
    ) throws(NewDocumentRoutingPolicyError) -> ComparisonOpenRequest {
        var sides: [ComparisonOpenSide] = []
        sides.reserveCapacity(commandID.paneCount.rawValue)
        for pane in commandID.paneCount.panes {
            try work.consume()
            let position = sidePosition(pane)
            sides.append(
                ComparisonOpenSide(
                    position: position,
                    source: validationSource(
                        mode: commandID.mode,
                        commandID: commandID,
                        position: position
                    )
                )
            )
        }
        return ComparisonOpenRequest(
            identity: ComparisonOpenRequestIdentity(rawValue: invocationID.rawValue),
            sides: sides,
            modeSelection: .explicit(commandID.mode.comparisonProjectMode),
            modeOptions: options,
            limits: limits
        )
    }

    private static func preflightPlanning(
        commandGate: CommandGate,
        capabilities: CapabilitySnapshot,
        defaults: DefaultsSnapshot,
        options: OptionsSnapshot,
        work: inout Work
    ) throws(NewDocumentRoutingPolicyError) -> [CommandID: PlanningFailure] {
        let validationID = InvocationID(
            rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
        try NewDocumentRoutingOptionShapeValidator.validateRequestLimits(
            defaults.comparisonOpenRequestLimits
        )
        do {
            try defaults.documentPlanLimits.validate()
        } catch let error as NewComparisonDocumentPlanError {
            throw .newComparisonDocumentPlan(error)
        } catch {
            throw .unexpectedPlannerFailure(.newComparisonDocumentPlan)
        }
        for mode in Mode.allCases {
            try work.checkCancellation()
            try NewDocumentRoutingOptionShapeValidator.validate(
                options,
                mode: mode,
                requestLimits: defaults.comparisonOpenRequestLimits,
                work: &work
            )
        }
        var failures: [CommandID: PlanningFailure] = [:]
        for commandID in CommandID.allCases {
            try work.consume()
            try work.checkCancellation()
            guard
                baseAvailability(
                    of: commandID,
                    commandGate: commandGate,
                    capabilities: capabilities
                ).isEnabled
            else {
                continue
            }
            do {
                guard
                    commandID.paneCount.rawValue
                        <= defaults.documentPlanLimits.maximumPaneCount
                else {
                    continue
                }
                let request = try optionValidationRequest(
                    invocationID: validationID,
                    commandID: commandID,
                    options: options.modeOptions(for: commandID.mode),
                    limits: defaults.comparisonOpenRequestLimits,
                    work: &work
                )
                // ComparisonOpenRequestPlanner cannot accept custom cancellation. It is pure, so
                // post-checking safely discards any result produced after custom cancellation.
                try work.checkCancellation()
                let openPlan = try ComparisonOpenRequestPlanner.plan(
                    request,
                    expecting: request.identity
                )
                try work.checkCancellation()
                guard
                    let validatedOptions = try NewComparisonDocumentPlan.ValidatedModeOptions(
                        openPlan,
                        currentRequest: request
                    )
                else {
                    throw NewDocumentRoutingPolicyError.nonConcreteModeOptions(commandID.mode)
                }
                try work.checkCancellation()
                _ = try NewComparisonDocumentPlan.make(
                    command: commandID.documentCommand,
                    scratchpads: nil,
                    modeOptions: validatedOptions,
                    limits: defaults.documentPlanLimits,
                    cancellationCheck: work.cancellationCheck
                )
                try work.checkCancellation()
            } catch let error as NewDocumentRoutingPolicyError {
                switch error {
                case .comparisonOpenRequest, .nonConcreteModeOptions,
                    .newComparisonDocumentPlan, .unexpectedPlannerFailure:
                    failures[commandID] = PlanningFailure(error)
                default:
                    throw error
                }
            } catch let error as ComparisonOpenRequestError {
                if error == .cancelled { throw .cancelled }
                failures[commandID] = PlanningFailure(.comparisonOpenRequest(error))
            } catch let error as NewComparisonDocumentPlanError {
                if error == .cancelled { throw .cancelled }
                failures[commandID] = PlanningFailure(.newComparisonDocumentPlan(error))
            } catch {
                failures[commandID] = PlanningFailure(
                    .unexpectedPlannerFailure(.newComparisonDocumentPlan)
                )
            }
        }
        return failures
    }

    private static func sidePosition(
        _ pane: NewComparisonDocumentPlan.Pane
    ) -> ComparisonOpenSidePosition {
        switch pane {
        case .left: .left
        case .middle: .middle
        case .right: .right
        }
    }

    private static func validationSource(
        mode: Mode,
        commandID: CommandID,
        position: ComparisonOpenSidePosition
    ) -> ComparisonOpenSource {
        switch mode {
        case .text, .table, .webpage:
            return .scratchpad(text: "")
        case .binary, .image:
            let fileExtension = mode == .binary ? "bin" : "png"
            return .localFile(
                validationURL(
                    commandID: commandID,
                    position: position,
                    leafExtension: fileExtension,
                    isDirectory: false
                )
            )
        case .folder:
            return .localFolder(
                validationURL(
                    commandID: commandID,
                    position: position,
                    leafExtension: nil,
                    isDirectory: true
                )
            )
        }
    }

    private static func validationURL(
        commandID: CommandID,
        position: ComparisonOpenSidePosition,
        leafExtension: String?,
        isDirectory: Bool
    ) -> URL {
        let suffix = leafExtension.map { ".\($0)" } ?? ""
        let path =
            "/.macmerge-new-document-option-validation/\(commandID.rawValue)/"
            + "\(position.rawValue)\(suffix)"
        return URL(filePath: path, directoryHint: isDirectory ? .isDirectory : .notDirectory)
    }

}

public enum NewDocumentRoutingPlannerStage: String, Equatable, Hashable, Sendable {
    case comparisonOpenRequest
    case validatedModeOptions
    case newComparisonDocumentPlan
}

public enum NewDocumentRoutingPolicyError: Error, Equatable, LocalizedError, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    case cancelled
    case invalidLimit(NewDocumentRoutingPolicy.Limit, value: Int)
    case commandLimitExceeded(maximum: Int)
    case workLimitExceeded(maximum: Int)
    case missingCommandForSecondaryInvocation(NewDocumentRoutingPolicy.InvocationKind)
    case unexpectedCommandForPrimaryInvocation(
        kind: NewDocumentRoutingPolicy.InvocationKind,
        commandID: NewDocumentRoutingPolicy.CommandID
    )
    case unsupportedMode(NewDocumentRoutingPolicy.Mode)
    case unsupportedPaneCount(
        mode: NewDocumentRoutingPolicy.Mode,
        paneCount: NewDocumentRoutingPolicy.PaneCount
    )
    case commandDisabled(
        NewDocumentRoutingPolicy.CommandID,
        reason: ComparisonCommandState.DisabledReason
    )
    case staleSnapshot(
        expected: NewDocumentRoutingPolicy.SnapshotIdentity,
        actual: NewDocumentRoutingPolicy.SnapshotIdentity
    )
    case staleDefaults(
        expected: NewDocumentRoutingPolicy.Revision,
        actual: NewDocumentRoutingPolicy.Revision
    )
    case defaultsRevisionCollision(NewDocumentRoutingPolicy.Revision)
    case staleOptions(
        expected: NewDocumentRoutingPolicy.Revision,
        actual: NewDocumentRoutingPolicy.Revision
    )
    case optionsRevisionCollision(NewDocumentRoutingPolicy.Revision)
    case staleCapabilities(
        expected: NewDocumentRoutingPolicy.Revision,
        actual: NewDocumentRoutingPolicy.Revision
    )
    case capabilitiesRevisionCollision(NewDocumentRoutingPolicy.Revision)
    case snapshotRevisionCollision(NewDocumentRoutingPolicy.SnapshotIdentity)
    case snapshotRollback(
        current: NewDocumentRoutingPolicy.SnapshotIdentity,
        proposed: NewDocumentRoutingPolicy.SnapshotIdentity
    )
    case receiptLedgerMismatch(
        expected: NewDocumentRoutingPolicy.ReceiptLedger.ID,
        actual: NewDocumentRoutingPolicy.ReceiptLedger.ID
    )
    case receiptLedgerLimitsMismatch
    case receiptAlreadyConsumed(NewDocumentRoutingPolicy.ReceiptID)
    case receiptLimitExceeded(maximum: Int)
    case executionAuthorizationAlreadyConsumed
    case comparisonOpenRequest(ComparisonOpenRequestError)
    case nonConcreteModeOptions(NewDocumentRoutingPolicy.Mode)
    case newComparisonDocumentPlan(NewComparisonDocumentPlanError)
    case unexpectedPlannerFailure(NewDocumentRoutingPlannerStage)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "New-document routing was cancelled."
        case .invalidLimit(let limit, let value):
            "Invalid new-document routing limit \(limit.rawValue): \(value)."
        case .commandLimitExceeded(let maximum):
            "New-document routing requires more than the configured \(maximum)-command limit."
        case .workLimitExceeded(let maximum):
            "New-document routing exceeds the \(maximum)-unit work limit."
        case .missingCommandForSecondaryInvocation(let kind):
            "New-document \(kind.rawValue) invocation requires an explicit secondary command."
        case .unexpectedCommandForPrimaryInvocation(let kind, let commandID):
            "New-document \(kind.rawValue) invocation cannot override primary command \(commandID.rawValue)."
        case .unsupportedMode(let mode):
            "New-document routing does not support \(mode.rawValue) mode."
        case .unsupportedPaneCount(let mode, let paneCount):
            "New-document routing does not support \(paneCount.rawValue)-pane \(mode.rawValue) mode."
        case .commandDisabled(let commandID, _):
            "New-document command \(commandID.rawValue) is disabled by current command state."
        case .staleSnapshot:
            "New-document routing snapshot is stale."
        case .staleDefaults:
            "New-document defaults revision is stale."
        case .defaultsRevisionCollision:
            "New-document defaults changed without advancing their revision."
        case .staleOptions:
            "New-document options revision is stale."
        case .optionsRevisionCollision:
            "New-document options changed without advancing their revision."
        case .staleCapabilities:
            "New-document capabilities revision is stale."
        case .capabilitiesRevisionCollision:
            "New-document capabilities changed without advancing their revision."
        case .snapshotRevisionCollision:
            "New-document command state changed without advancing its snapshot generation."
        case .snapshotRollback:
            "New-document authoritative snapshot cannot move backward."
        case .receiptLedgerMismatch:
            "New-document receipt belongs to a different one-shot ledger."
        case .receiptLedgerLimitsMismatch:
            "New-document receipt ledger limits do not match current routing defaults."
        case .receiptAlreadyConsumed:
            "New-document routing receipt was already consumed."
        case .receiptLimitExceeded(let maximum):
            "New-document receipt ledger exceeds its \(maximum)-receipt limit."
        case .executionAuthorizationAlreadyConsumed:
            "New-document execution authorization was already consumed."
        case .comparisonOpenRequest:
            "Comparison open request planning failed; details are redacted."
        case .nonConcreteModeOptions(let mode):
            "New-document \(mode.rawValue) options did not resolve to a concrete current snapshot."
        case .newComparisonDocumentPlan:
            "New comparison document planning failed; details are redacted."
        case .unexpectedPlannerFailure(let stage):
            "New-document routing failed unexpectedly during \(stage.rawValue) planning."
        }
    }

    public var description: String {
        errorDescription ?? "New-document routing failed; details are redacted."
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["description": description, "details": "<redacted>"],
            displayStyle: .enum
        )
    }
}

private struct NewDocumentRoutingWork {
    let limits: NewDocumentRoutingPolicy.Limits
    let cancellationCheck: NewDocumentRoutingPolicy.CancellationCheck
    private(set) var completed: Int

    init(
        limits: NewDocumentRoutingPolicy.Limits,
        completed: Int = 0,
        cancellationCheck: @escaping NewDocumentRoutingPolicy.CancellationCheck
    ) throws(NewDocumentRoutingPolicyError) {
        guard completed >= 0, completed <= limits.maximumWorkUnits else {
            throw .workLimitExceeded(maximum: limits.maximumWorkUnits)
        }
        self.limits = limits
        self.completed = completed
        self.cancellationCheck = cancellationCheck
    }

    mutating func consume(_ amount: Int = 1) throws(NewDocumentRoutingPolicyError) {
        guard amount >= 0, amount <= limits.maximumWorkUnits - completed else {
            try checkCancellation()
            throw .workLimitExceeded(maximum: limits.maximumWorkUnits)
        }
        let previousBucket = completed / limits.cancellationCheckInterval
        completed += amount
        if completed / limits.cancellationCheckInterval != previousBucket {
            try checkCancellation()
        }
    }

    func checkCancellation() throws(NewDocumentRoutingPolicyError) {
        try cancellationCheck()
    }
}

private typealias Work = NewDocumentRoutingWork

private enum NewDocumentRoutingOptionShapeValidator {
    static func validateRequestLimits(
        _ requestLimits: ComparisonOpenRequestLimits
    ) throws(NewDocumentRoutingPolicyError) {
        guard (0...ComparisonOpenRequestLimits.hardMaximumPathUTF8Bytes).contains(requestLimits.maximumPathUTF8Bytes) else {
            throw .comparisonOpenRequest(.invalidLimit(.pathUTF8Bytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumTotalPathUTF8Bytes).contains(
                requestLimits.maximumTotalPathUTF8Bytes
            ),
            requestLimits.maximumTotalPathUTF8Bytes >= requestLimits.maximumPathUTF8Bytes
        else {
            throw .comparisonOpenRequest(.invalidLimit(.totalPathUTF8Bytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumRemoteURLUTF8Bytes).contains(
                requestLimits.maximumRemoteURLUTF8Bytes
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.remoteURLUTF8Bytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumScratchpadUTF8Bytes).contains(
                requestLimits.maximumScratchpadUTF8Bytes
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.scratchpadUTF8Bytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumCombinedScratchpadUTF8Bytes).contains(
                requestLimits.maximumCombinedScratchpadUTF8Bytes
            ),
            requestLimits.maximumCombinedScratchpadUTF8Bytes
                >= requestLimits.maximumScratchpadUTF8Bytes
        else {
            throw .comparisonOpenRequest(.invalidLimit(.combinedScratchpadUTF8Bytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumLabelUTF8Bytes).contains(
                requestLimits.maximumLabelUTF8Bytes
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.labelUTF8Bytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumDeclaredBytes).contains(
                requestLimits.maximumDeclaredBytes
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.declaredBytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumDeclaredWorkUnits).contains(
                requestLimits.maximumDeclaredWorkUnits
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.declaredWorkUnits))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumPlanningWorkUnits).contains(
                requestLimits.maximumPlanningWorkUnits
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.planningWorkUnits))
        }
        try validateOptionLimits(requestLimits)
    }

    static func validate(
        _ options: NewDocumentRoutingPolicy.OptionsSnapshot,
        mode: NewDocumentRoutingPolicy.Mode,
        requestLimits: ComparisonOpenRequestLimits,
        work: inout Work
    ) throws(NewDocumentRoutingPolicyError) {
        try validateOptionLimits(requestLimits)

        switch mode {
        case .text:
            try validate(
                lineOptions: options.textTwoWay,
                extraValues: [],
                requestLimits: requestLimits,
                work: &work
            )
        case .table:
            try validate(
                lineOptions: nil,
                extraValues: tableStrings(options),
                requestLimits: requestLimits,
                work: &work
            )
        case .image:
            let identifiers = options.imageLoading.supportedTypeIdentifiers
            guard identifiers.count <= requestLimits.maximumOptionItemCount else {
                throw .comparisonOpenRequest(
                    .tooManyOptionItems(maximum: requestLimits.maximumOptionItemCount)
                )
            }
            try validate(
                lineOptions: nil,
                extraValues: Array(identifiers),
                requestLimits: requestLimits,
                work: &work
            )
            _ = try boundedSorted(identifiers, work: &work)
        case .webpage:
            let webpageContext =
                options.webpageThreeWay.expectedContext.map { [$0.identifier] } ?? []
            try validate(
                lineOptions: options.webpageTwoWay.lineDiffOptions,
                extraValues: webpageContext,
                requestLimits: requestLimits,
                work: &work
            )
        case .binary, .folder:
            break
        }
    }

    private static func validateOptionLimits(
        _ requestLimits: ComparisonOpenRequestLimits
    ) throws(NewDocumentRoutingPolicyError) {
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumOptionItemCount).contains(
                requestLimits.maximumOptionItemCount
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.optionItemCount))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumOptionStringUTF8Bytes).contains(
                requestLimits.maximumOptionStringUTF8Bytes
            )
        else {
            throw .comparisonOpenRequest(.invalidLimit(.optionStringUTF8Bytes))
        }
        guard
            (0...ComparisonOpenRequestLimits.hardMaximumTotalOptionStringUTF8Bytes).contains(
                requestLimits.maximumTotalOptionStringUTF8Bytes
            ),
            requestLimits.maximumTotalOptionStringUTF8Bytes
                >= requestLimits.maximumOptionStringUTF8Bytes
        else {
            throw .comparisonOpenRequest(.invalidLimit(.totalOptionStringUTF8Bytes))
        }

    }

    private static func validate(
        lineOptions: LineDiffOptions?,
        extraValues: [String],
        requestLimits: ComparisonOpenRequestLimits,
        work: inout Work
    ) throws(NewDocumentRoutingPolicyError) {
        let (lineItemCount, lineItemOverflow) =
            lineOptions.map {
                $0.lineFilters.count.addingReportingOverflow($0.substitutions.count)
            } ?? (0, false)
        let (itemCount, itemOverflow) = lineItemCount.addingReportingOverflow(
            extraValues.count
        )
        guard
            !lineItemOverflow,
            !itemOverflow,
            itemCount <= requestLimits.maximumOptionItemCount
        else {
            throw .comparisonOpenRequest(
                .tooManyOptionItems(maximum: requestLimits.maximumOptionItemCount)
            )
        }

        var values = extraValues
        if let lineOptions {
            values.append(contentsOf: lineOptions.lineFilters.map(\.pattern))
            for substitution in lineOptions.substitutions {
                values.append(substitution.pattern)
                values.append(substitution.replacement)
            }
        }
        var totalBytes = 0
        for value in values {
            try work.checkCancellation()
            try work.consume()
            var byteCount = 0
            for _ in value.utf8 {
                guard byteCount < requestLimits.maximumOptionStringUTF8Bytes else {
                    throw .comparisonOpenRequest(
                        .optionStringTooLarge(
                            name: "newDocumentRouting.options",
                            maximumUTF8Bytes: requestLimits.maximumOptionStringUTF8Bytes
                        )
                    )
                }
                byteCount += 1
                try work.consume()
            }
            let (nextTotal, overflow) = totalBytes.addingReportingOverflow(byteCount)
            guard
                !overflow,
                nextTotal <= requestLimits.maximumTotalOptionStringUTF8Bytes
            else {
                throw .comparisonOpenRequest(
                    .totalOptionStringsTooLarge(
                        maximumUTF8Bytes: requestLimits.maximumTotalOptionStringUTF8Bytes
                    )
                )
            }
            totalBytes = nextTotal
        }
    }

    private static func tableStrings(
        _ options: NewDocumentRoutingPolicy.OptionsSnapshot
    ) -> [String] {
        let parsingOptions = [
            options.tableParsing,
            options.tableThreeWay.parsingOptions
        ]
        return parsingOptions.flatMap { parsing in
            [String(parsing.delimiter)] + (parsing.quote.map { [String($0)] } ?? [])
        }
    }

    private static func boundedSorted(
        _ values: Set<String>,
        work: inout Work
    ) throws(NewDocumentRoutingPolicyError) -> [String] {
        var result = Array(values)
        var buffer = result
        var width = 1
        while width < result.count {
            var lowerBound = 0
            while lowerBound < result.count {
                try work.checkCancellation()
                let middle = min(lowerBound + width, result.count)
                let upperBound = min(middle + width, result.count)
                var left = lowerBound
                var right = middle
                var destination = lowerBound
                while left < middle || right < upperBound {
                    try work.consume()
                    if right == upperBound || (left < middle && result[left] <= result[right]) {
                        buffer[destination] = result[left]
                        left += 1
                    } else {
                        buffer[destination] = result[right]
                        right += 1
                    }
                    destination += 1
                }
                lowerBound = upperBound
            }
            swap(&result, &buffer)
            let (nextWidth, overflow) = width.multipliedReportingOverflow(by: 2)
            width = overflow ? result.count : nextWidth
        }
        return result
    }
}
