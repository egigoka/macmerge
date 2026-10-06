import CryptoKit
import Foundation

/// UI-independent bounded toolbar state matrix and interaction routing model.
///
/// Covers the todo.md Toolbar rows without UI or XCUI wiring: exact command
/// order/grouping in fresh and loaded windows, six invocation kinds (primary click,
/// menu-arrow click, menu item selection, keyboard activation, VoiceOver activation,
/// disabled activation), and every toolbar action across the ten lifecycle states
/// (empty, loading, equal, different, selected, dirty, read-only, failed, untitled,
/// externally changed). Enablement always resolves through `ComparisonCommandState`;
/// this matrix never declares a competing policy.
public enum ToolbarInteractionMatrix: Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias Item = ToolbarConfiguration.Item
    public typealias Scenario = ToolbarAuditLifecycleScenario
    public typealias Invocation = ToolbarAuditInvocationKind
    public typealias Outcome = ToolbarAuditInteractionOutcome
    public typealias StableID = ToolbarAuditStableID
    public typealias CommandContext = ComparisonCommandState.Context
    public typealias SemanticCommand = ComparisonCommandState.Identifier
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let requiredScenarios = Scenario.allCases
    public static let requiredInvocations = Invocation.allCases
    public static let requiredWindows = ToolbarAuditScreenshotContext.allCases
    public static let manifestRevision = ToolbarAuditManifest.canonicalRevision

    public static let unknownActionCode = StableID(rawValue: "toolbarInteraction.unknownAction")
    public static let misroutedPrimaryCode = StableID(rawValue: "toolbarInteraction.misroutedPrimary")
    public static let misroutedMenuCode = StableID(rawValue: "toolbarInteraction.misroutedMenu")
    public static let missingBindingCode = StableID(rawValue: "toolbarInteraction.missingBinding")

    /// Window contexts for the screenshot/AX order-and-grouping regression.
    public enum Window: String, CaseIterable, Equatable, Hashable, Sendable {
        case freshWindow
        case loadedComparison

        public init(_ context: ToolbarAuditScreenshotContext) {
            switch context {
            case .freshWindow: self = .freshWindow
            case .loadedComparison: self = .loadedComparison
            }
        }

        public var screenshotContext: ToolbarAuditScreenshotContext {
            switch self {
            case .freshWindow: .freshWindow
            case .loadedComparison: .loadedComparison
            }
        }

        /// Representative lifecycle state for captures in this window.
        public var representativeScenario: Scenario {
            switch self {
            case .freshWindow: .empty
            case .loadedComparison: .different
            }
        }
    }

    /// Caller-owned control identity with stable menu order. Secondary order is
    /// significant and preserved exactly; it must match menu presentation order.
    public struct ControlDescriptor: Equatable, Hashable, Sendable {
        public let controlID: StableID
        public let command: Command
        public let primaryActionID: StableID
        public let secondaryActionIDs: [StableID]

        public init(
            controlID: StableID,
            command: Command,
            primaryActionID: StableID,
            secondaryActionIDs: [StableID] = []
        ) {
            self.controlID = controlID
            self.command = command
            self.primaryActionID = primaryActionID
            self.secondaryActionIDs = secondaryActionIDs
        }

        public init(_ requirement: ToolbarAuditControlRequirement) {
            controlID = requirement.id
            command = requirement.command
            primaryActionID = requirement.behavior.primaryActionID
            secondaryActionIDs = requirement.behavior.secondary.actionIDs
        }

        public var hasSecondaryMenu: Bool { !secondaryActionIDs.isEmpty }

        public var allActionIDs: [StableID] {
            [primaryActionID] + secondaryActionIDs
        }
    }

    /// Enablement of one toolbar action in one lifecycle state.
    public struct LifecycleRow: Equatable, Hashable, Sendable {
        public let scenario: Scenario
        public let controlID: StableID
        public let command: Command
        public let actionID: StableID
        public let isEnabled: Bool
        public let disabledReasonID: StableID?

        public init(
            scenario: Scenario,
            controlID: StableID,
            command: Command,
            actionID: StableID,
            isEnabled: Bool,
            disabledReasonID: StableID? = nil
        ) {
            self.scenario = scenario
            self.controlID = controlID
            self.command = command
            self.actionID = actionID
            self.isEnabled = isEnabled
            self.disabledReasonID = disabledReasonID
        }
    }

    /// Routed result of one invocation kind against one action in one scenario.
    public struct InteractionRoute: Equatable, Hashable, Sendable {
        public let scenario: Scenario
        public let controlID: StableID
        public let actionID: StableID
        public let invocation: Invocation
        public let outcome: Outcome
        public let isEnabled: Bool

        public init(
            scenario: Scenario,
            controlID: StableID,
            actionID: StableID,
            invocation: Invocation,
            outcome: Outcome,
            isEnabled: Bool
        ) {
            self.scenario = scenario
            self.controlID = controlID
            self.actionID = actionID
            self.invocation = invocation
            self.outcome = outcome
            self.isEnabled = isEnabled
        }

        public var performsAction: Bool {
            switch outcome {
            case .invoked, .menuPresented: true
            case .blocked, .noOp, .failed: false
            }
        }
    }

    /// Exact order/grouping evidence expected in one window context.
    public struct ScreenshotRow: Equatable, Hashable, Sendable {
        public let context: Window
        public let scenario: Scenario
        public let manifestRevision: ToolbarAuditRevision
        public let items: [Item]
        public let groups: [ToolbarAuditCommandGroup]

        public init(
            context: Window,
            scenario: Scenario,
            manifestRevision: ToolbarAuditRevision,
            items: [Item],
            groups: [ToolbarAuditCommandGroup]
        ) {
            self.context = context
            self.scenario = scenario
            self.manifestRevision = manifestRevision
            self.items = items
            self.groups = groups
        }
    }

    /// Deterministic, redacted evidence bundle for the full matrix.
    public struct Matrix: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let source: String
        public let manifestRevision: ToolbarAuditRevision
        public let lifecycleRows: [LifecycleRow]
        public let interactionRoutes: [InteractionRoute]
        public let screenshotRows: [ScreenshotRow]
        public let digestHex: String

        public init(
            source: String,
            manifestRevision: ToolbarAuditRevision,
            lifecycleRows: [LifecycleRow],
            interactionRoutes: [InteractionRoute],
            screenshotRows: [ScreenshotRow],
            digestHex: String
        ) {
            self.source = source.precomposedStringWithCanonicalMapping
            self.manifestRevision = manifestRevision
            self.lifecycleRows = lifecycleRows
            self.interactionRoutes = interactionRoutes
            self.screenshotRows = screenshotRows
            self.digestHex = digestHex.precomposedStringWithCanonicalMapping
        }

        public var description: String {
            "ToolbarInteractionMatrix(lifecycleRows: \(lifecycleRows.count), interactionRoutes: \(interactionRoutes.count), screenshots: \(screenshotRows.count), digest: \(digestHex))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "manifestRevision": manifestRevision.rawValue,
                    "lifecycleRowCount": lifecycleRows.count,
                    "interactionRouteCount": interactionRoutes.count,
                    "screenshotRowCount": screenshotRows.count,
                    "digest": digestHex,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public enum Limit: String, CaseIterable, Equatable, Hashable, Sendable {
        case controls
        case secondaryActions
        case lifecycleRows
        case interactionRows
        case screenshots
        case stringBytes
        case totalStringBytes
        case work
        case cancellationCheckInterval
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumControls = 64
        public static let hardMaximumSecondaryActionsPerControl = 64
        public static let hardMaximumLifecycleRows = 4_096
        public static let hardMaximumInteractionRows = 65_536
        public static let hardMaximumScreenshots = 64
        public static let hardMaximumStringUTF8Bytes = 64 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 16 * 1_024 * 1_024
        public static let hardMaximumWorkUnits = 512 * 1_024 * 1_024
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumControls: Int
        public let maximumSecondaryActionsPerControl: Int
        public let maximumLifecycleRows: Int
        public let maximumInteractionRows: Int
        public let maximumScreenshots: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumControls: Int = 32,
            maximumSecondaryActionsPerControl: Int = 16,
            maximumLifecycleRows: Int = 1_024,
            maximumInteractionRows: Int = 8_192,
            maximumScreenshots: Int = 16,
            maximumStringUTF8Bytes: Int = 16 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
            maximumWorkUnits: Int = 4 * 1_024 * 1_024,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumControls = maximumControls
            self.maximumSecondaryActionsPerControl = maximumSecondaryActionsPerControl
            self.maximumLifecycleRows = maximumLifecycleRows
            self.maximumInteractionRows = maximumInteractionRows
            self.maximumScreenshots = maximumScreenshots
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        fileprivate func validate() throws {
            try validateValue(maximumControls, limit: .controls, range: 1...Self.hardMaximumControls)
            try validateValue(maximumSecondaryActionsPerControl, limit: .secondaryActions, range: 0...Self.hardMaximumSecondaryActionsPerControl)
            try validateValue(maximumLifecycleRows, limit: .lifecycleRows, range: 1...Self.hardMaximumLifecycleRows)
            try validateValue(maximumInteractionRows, limit: .interactionRows, range: 1...Self.hardMaximumInteractionRows)
            try validateValue(maximumScreenshots, limit: .screenshots, range: 1...Self.hardMaximumScreenshots)
            try validateValue(maximumStringUTF8Bytes, limit: .stringBytes, range: 1...Self.hardMaximumStringUTF8Bytes)
            try validateValue(maximumTotalStringUTF8Bytes, limit: .totalStringBytes, range: 1...Self.hardMaximumTotalStringUTF8Bytes)
            try validateValue(maximumWorkUnits, limit: .work, range: 1...Self.hardMaximumWorkUnits)
            try validateValue(cancellationCheckInterval, limit: .cancellationCheckInterval, range: 1...Self.hardMaximumCancellationCheckInterval)
        }

        private func validateValue(_ value: Int, limit: Limit, range: ClosedRange<Int>) throws {
            guard range.contains(value) else {
                throw ToolbarInteractionMatrixError.invalidLimit(name: limit.rawValue, value: value, maximum: range.upperBound)
            }
        }
    }

    /// Authoritative semantic input for one lifecycle row. Enablement resolves through
    /// `ComparisonCommandState`; this matrix cannot declare a conflicting state.
    public static func commandContext(for scenario: Scenario) -> CommandContext {
        switch scenario {
        case .empty:
            CommandContext()
        case .loading:
            CommandContext(lifecycle: .loading)
        case .equal:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true)
            )
        case .different:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                hasSignificantDifferences: true,
                differenceNavigation: availableDifferenceNavigation()
            )
        case .selected:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                hasSelection: true,
                hasSignificantDifferences: true,
                differenceNavigation: availableDifferenceNavigation()
            )
        case .dirty:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true, isDirty: true),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                hasSignificantDifferences: true,
                canUndo: true,
                differenceNavigation: availableDifferenceNavigation()
            )
        case .readOnly:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: false),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                hasSignificantDifferences: true,
                canUndo: true,
                differenceNavigation: availableDifferenceNavigation()
            )
        case .failed:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true),
                lifecycle: .failed
            )
        case .untitled:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true, isDirty: true, isUntitled: true),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true, isDirty: true, isUntitled: true),
                hasSignificantDifferences: true,
                canUndo: true,
                differenceNavigation: availableDifferenceNavigation()
            )
        case .externallyChanged:
            CommandContext(
                left: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true, hasExternalChange: true),
                right: ComparisonCommandState.PaneState(isLoaded: true, isEditable: true, hasExternalChange: true),
                hasSignificantDifferences: true,
                canUndo: true,
                differenceNavigation: availableDifferenceNavigation()
            )
        }
    }

    /// Shared enablement for one semantic command in one lifecycle state.
    public static func availability(of command: SemanticCommand, in scenario: Scenario) -> ToolbarAuditAvailability {
        let resolution = ComparisonCommandState.resolve(command, in: commandContext(for: scenario))
        switch resolution.availability {
        case .enabled:
            return .enabled
        case .disabled(let reason):
            return .disabled(reason: stableReasonID(for: reason))
        }
    }

    /// Enablement of one toolbar action. Secondary actions resolve through the caller-supplied
    /// semantic binding; primary actions map directly from their toolbar command.
    public static func availability(
        control: ControlDescriptor,
        actionID: StableID,
        in scenario: Scenario,
        bindings: [StableID: SemanticCommand] = [:]
    ) -> ToolbarAuditAvailability {
        let semantic: SemanticCommand
        if actionID == control.primaryActionID {
            semantic = SemanticCommand(control.command)
        } else if let bound = bindings[actionID] {
            semantic = bound
        } else {
            return .disabled(reason: missingBindingCode)
        }
        return availability(of: semantic, in: scenario)
    }

    /// Pure invocation routing. Disabled actions never perform: every invocation except a
    /// correctly targeted `disabledActivation` probe resolves to `blocked`, and that probe
    /// resolves to `noOp` when misapplied to an enabled action.
    public static func route(
        invocation: Invocation,
        isEnabled: Bool,
        control: ControlDescriptor,
        actionID: StableID
    ) -> Outcome {
        if invocation == .disabledActivation {
            return isEnabled ? .noOp : .blocked
        }
        guard isEnabled else { return .blocked }
        switch invocation {
        case .disabledActivation:
            return .blocked
        case .primaryClick, .keyboardActivation, .voiceOverActivation:
            guard actionID == control.primaryActionID else {
                return .failed(code: misroutedPrimaryCode)
            }
            return .invoked(actionID: actionID)
        case .menuArrowClick:
            guard control.hasSecondaryMenu else { return .noOp }
            guard actionID == control.primaryActionID else {
                return .failed(code: misroutedMenuCode)
            }
            return .menuPresented(actionIDs: control.secondaryActionIDs)
        case .menuItemSelection:
            guard control.secondaryActionIDs.contains(actionID) else {
                return .failed(code: unknownActionCode)
            }
            return .invoked(actionID: actionID)
        }
    }

    /// Resolve enablement through shared command policy, then route the invocation.
    public static func resolveRoute(
        scenario: Scenario,
        control: ControlDescriptor,
        actionID: StableID,
        invocation: Invocation,
        bindings: [StableID: SemanticCommand] = [:]
    ) -> InteractionRoute {
        let availability = availability(control: control, actionID: actionID, in: scenario, bindings: bindings)
        let outcome = route(invocation: invocation, isEnabled: availability.isEnabled, control: control, actionID: actionID)
        return InteractionRoute(
            scenario: scenario,
            controlID: control.controlID,
            actionID: actionID,
            invocation: invocation,
            outcome: outcome,
            isEnabled: availability.isEnabled
        )
    }

    /// Exact canonical items expected in every window context. Fresh and loaded windows
    /// share one order/grouping; that invariance is the regression assertion.
    public static func screenshotItems(for window: Window) -> [Item] {
        _ = window
        return ToolbarAuditManifest.canonical.items
    }

    public static func screenshotGroups(for window: Window) -> [ToolbarAuditCommandGroup] {
        _ = window
        return ToolbarAuditManifest.canonical.groups
    }

    /// Build the complete deterministic matrix for the given controls. Throws on duplicate
    /// identity, missing secondary bindings, unknown bindings, limit violations, or
    /// cancellation. Row order is canonical: scenario, command, action, invocation.
    public static func makeMatrix(
        controls: [ControlDescriptor],
        semanticBindings: [StableID: SemanticCommand] = [:],
        source: String,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Matrix {
        try limits.validate()
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try budget.checkCancellation()
        var strings = StringBudget(limits: limits)
        try strings.add(source, field: "source")
        guard !isBlank(source) else {
            throw ToolbarInteractionMatrixError.invalidSource(field: "source")
        }
        guard !controls.isEmpty else {
            throw ToolbarInteractionMatrixError.emptyControls
        }
        guard controls.count <= limits.maximumControls else {
            throw ToolbarInteractionMatrixError.countLimitExceeded(kind: "controls", maximum: limits.maximumControls)
        }
        let sortedControls = try validatedControls(controls, limits: limits, strings: &strings, budget: &budget)
        try validateBindings(semanticBindings, controls: sortedControls, strings: &strings, budget: &budget)
        let bindings = semanticBindings
        let lifecycleRows = try buildLifecycleRows(controls: sortedControls, bindings: bindings, limits: limits, budget: &budget)
        let interactionRoutes = try buildInteractionRoutes(controls: sortedControls, bindings: bindings, limits: limits, budget: &budget)
        let screenshotRows = try buildScreenshotRows(limits: limits, budget: &budget)
        let digestHex = digest(lifecycleRows: lifecycleRows, interactionRoutes: interactionRoutes, screenshotRows: screenshotRows)
        return Matrix(
            source: source,
            manifestRevision: manifestRevision,
            lifecycleRows: lifecycleRows,
            interactionRoutes: interactionRoutes,
            screenshotRows: screenshotRows,
            digestHex: digestHex
        )
    }

    private static func availableDifferenceNavigation() -> ComparisonCommandState.DifferenceNavigation {
        ComparisonCommandState.DifferenceNavigation(
            canSelectLineDifference: true,
            canSelectNextDifference: true,
            canSelectPreviousDifference: true,
            canSelectFirstDifference: true,
            canSelectCurrentDifference: true,
            canSelectLastDifference: true
        )
    }

    private static func stableReasonID(for reason: ComparisonCommandState.DisabledReason) -> StableID {
        switch reason {
        case .sessionLocked:
            StableID(rawValue: "toolbarInteraction.sessionLocked")
        case .comparisonLoading:
            StableID(rawValue: "toolbarInteraction.comparisonLoading")
        case .comparisonRefreshing:
            StableID(rawValue: "toolbarInteraction.comparisonRefreshing")
        case .comparisonStale:
            StableID(rawValue: "toolbarInteraction.comparisonStale")
        case .comparisonFailed:
            StableID(rawValue: "toolbarInteraction.comparisonFailed")
        case .comparisonCanceled:
            StableID(rawValue: "toolbarInteraction.comparisonCanceled")
        case .noComparison:
            StableID(rawValue: "toolbarInteraction.noComparison")
        case .requiresThreePane:
            StableID(rawValue: "toolbarInteraction.requiresThreePane")
        case .sideNotLoaded(let side):
            StableID(rawValue: "toolbarInteraction.sideNotLoaded.\(String(describing: side))")
        case .destinationReadOnly(let side):
            StableID(rawValue: "toolbarInteraction.destinationReadOnly.\(String(describing: side))")
        case .sideReadOnly(let side):
            StableID(rawValue: "toolbarInteraction.sideReadOnly.\(String(describing: side))")
        case .noSelection:
            StableID(rawValue: "toolbarInteraction.noSelection")
        case .noSignificantDifferences:
            StableID(rawValue: "toolbarInteraction.noSignificantDifferences")
        case .noUnsavedChanges:
            StableID(rawValue: "toolbarInteraction.noUnsavedChanges")
        case .noUnsavedChangesOnSide(let side):
            StableID(rawValue: "toolbarInteraction.noUnsavedChangesOnSide.\(String(describing: side))")
        case .unsavedChanges(let side):
            StableID(rawValue: "toolbarInteraction.unsavedChanges.\(String(describing: side))")
        case .externalChange(let side):
            StableID(rawValue: "toolbarInteraction.externalChange.\(String(describing: side))")
        case .noUndo:
            StableID(rawValue: "toolbarInteraction.noUndo")
        case .noRedo:
            StableID(rawValue: "toolbarInteraction.noRedo")
        case .noLineDifference:
            StableID(rawValue: "toolbarInteraction.noLineDifference")
        case .noPreviousLineDifference:
            StableID(rawValue: "toolbarInteraction.noPreviousLineDifference")
        case .noNextDifference:
            StableID(rawValue: "toolbarInteraction.noNextDifference")
        case .noPreviousDifference:
            StableID(rawValue: "toolbarInteraction.noPreviousDifference")
        case .noFirstDifference:
            StableID(rawValue: "toolbarInteraction.noFirstDifference")
        case .noCurrentDifference:
            StableID(rawValue: "toolbarInteraction.noCurrentDifference")
        case .noLastDifference:
            StableID(rawValue: "toolbarInteraction.noLastDifference")
        case .noConflicts:
            StableID(rawValue: "toolbarInteraction.noConflicts")
        case .noFirstConflict:
            StableID(rawValue: "toolbarInteraction.noFirstConflict")
        case .noNextConflict:
            StableID(rawValue: "toolbarInteraction.noNextConflict")
        case .noPreviousConflict:
            StableID(rawValue: "toolbarInteraction.noPreviousConflict")
        case .noCurrentConflict:
            StableID(rawValue: "toolbarInteraction.noCurrentConflict")
        case .noLastConflict:
            StableID(rawValue: "toolbarInteraction.noLastConflict")
        case .noFirstComparedFile:
            StableID(rawValue: "toolbarInteraction.noFirstComparedFile")
        case .noPreviousComparedFile:
            StableID(rawValue: "toolbarInteraction.noPreviousComparedFile")
        case .noNextComparedFile:
            StableID(rawValue: "toolbarInteraction.noNextComparedFile")
        case .noLastComparedFile:
            StableID(rawValue: "toolbarInteraction.noLastComparedFile")
        case .noReloadablePane:
            StableID(rawValue: "toolbarInteraction.noReloadablePane")
        case .paneChangeUnavailable:
            StableID(rawValue: "toolbarInteraction.paneChangeUnavailable")
        case .paneChangeBackUnavailable:
            StableID(rawValue: "toolbarInteraction.paneChangeBackUnavailable")
        case .automaticMergeUnavailable:
            StableID(rawValue: "toolbarInteraction.automaticMergeUnavailable")
        case .unsupportedCommand(let identifier):
            StableID(rawValue: "toolbarInteraction.unsupportedCommand.\(identifier.rawValue)")
        }
    }

    private static func validatedControls(
        _ controls: [ControlDescriptor],
        limits: Limits,
        strings: inout StringBudget,
        budget: inout WorkBudget
    ) throws -> [ControlDescriptor] {
        var seenControlIDs = Set<StableID>()
        var seenCommands = Set<Command>()
        for control in controls {
            try budget.consume()
            try strings.identifier(control.controlID, field: "controls.controlID")
            try strings.identifier(control.primaryActionID, field: "controls.primaryActionID")
            guard seenControlIDs.insert(control.controlID).inserted else {
                throw ToolbarInteractionMatrixError.duplicateControl(id: control.controlID)
            }
            guard seenCommands.insert(control.command).inserted else {
                throw ToolbarInteractionMatrixError.duplicateCommand(command: control.command)
            }
            guard control.secondaryActionIDs.count <= limits.maximumSecondaryActionsPerControl else {
                throw ToolbarInteractionMatrixError.countLimitExceeded(kind: "secondaryActions", maximum: limits.maximumSecondaryActionsPerControl)
            }
            var seenActions = Set<StableID>()
            seenActions.insert(control.primaryActionID)
            for actionID in control.secondaryActionIDs {
                try budget.consume()
                try strings.identifier(actionID, field: "controls.secondaryActionID")
                guard seenActions.insert(actionID).inserted else {
                    throw ToolbarInteractionMatrixError.duplicateAction(id: actionID)
                }
            }
        }
        let commandOrder = Dictionary(uniqueKeysWithValues: Command.allCases.enumerated().map { ($1, $0) })
        return controls.sorted {
            let leftOrder = commandOrder[$0.command] ?? Int.max
            let rightOrder = commandOrder[$1.command] ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return $0.controlID < $1.controlID
        }
    }

    private static func validateBindings(
        _ bindings: [StableID: SemanticCommand],
        controls: [ControlDescriptor],
        strings: inout StringBudget,
        budget: inout WorkBudget
    ) throws {
        var knownActions = Set<StableID>()
        for control in controls {
            knownActions.formUnion(control.allActionIDs)
        }
        for actionID in bindings.keys {
            try budget.consume()
            try strings.identifier(actionID, field: "semanticBindings.actionID")
            guard knownActions.contains(actionID) else {
                throw ToolbarInteractionMatrixError.unknownBinding(actionID: actionID)
            }
        }
        for control in controls {
            for actionID in control.secondaryActionIDs {
                try budget.consume()
                guard bindings[actionID] != nil else {
                    throw ToolbarInteractionMatrixError.missingSemanticBinding(actionID: actionID)
                }
            }
        }
    }

    private static func buildLifecycleRows(
        controls: [ControlDescriptor],
        bindings: [StableID: SemanticCommand],
        limits: Limits,
        budget: inout WorkBudget
    ) throws -> [LifecycleRow] {
        var rows: [LifecycleRow] = []
        for scenario in Scenario.allCases {
            for control in controls {
                for actionID in control.allActionIDs {
                    try budget.consume()
                    let availability = availability(control: control, actionID: actionID, in: scenario, bindings: bindings)
                    let disabledReasonID: StableID?
                    switch availability {
                    case .enabled:
                        disabledReasonID = nil
                    case .disabled(let reason):
                        disabledReasonID = reason
                    }
                    rows.append(
                        LifecycleRow(
                            scenario: scenario,
                            controlID: control.controlID,
                            command: control.command,
                            actionID: actionID,
                            isEnabled: availability.isEnabled,
                            disabledReasonID: disabledReasonID
                        )
                    )
                }
            }
        }
        guard rows.count <= limits.maximumLifecycleRows else {
            throw ToolbarInteractionMatrixError.countLimitExceeded(kind: "lifecycleRows", maximum: limits.maximumLifecycleRows)
        }
        return rows
    }

    private static func buildInteractionRoutes(
        controls: [ControlDescriptor],
        bindings: [StableID: SemanticCommand],
        limits: Limits,
        budget: inout WorkBudget
    ) throws -> [InteractionRoute] {
        var routes: [InteractionRoute] = []
        for scenario in Scenario.allCases {
            for control in controls {
                for actionID in control.allActionIDs {
                    for invocation in Invocation.allCases {
                        try budget.consume()
                        routes.append(resolveRoute(scenario: scenario, control: control, actionID: actionID, invocation: invocation, bindings: bindings))
                    }
                }
            }
        }
        guard routes.count <= limits.maximumInteractionRows else {
            throw ToolbarInteractionMatrixError.countLimitExceeded(kind: "interactionRoutes", maximum: limits.maximumInteractionRows)
        }
        return routes
    }

    private static func buildScreenshotRows(limits: Limits, budget: inout WorkBudget) throws -> [ScreenshotRow] {
        var rows: [ScreenshotRow] = []
        for window in Window.allCases {
            try budget.consume()
            rows.append(
                ScreenshotRow(
                    context: window,
                    scenario: window.representativeScenario,
                    manifestRevision: manifestRevision,
                    items: screenshotItems(for: window),
                    groups: screenshotGroups(for: window)
                )
            )
        }
        guard rows.count <= limits.maximumScreenshots else {
            throw ToolbarInteractionMatrixError.countLimitExceeded(kind: "screenshots", maximum: limits.maximumScreenshots)
        }
        return rows
    }

    private static func digest(
        lifecycleRows: [LifecycleRow],
        interactionRoutes: [InteractionRoute],
        screenshotRows: [ScreenshotRow]
    ) -> String {
        var hasher = SHA256()
        for row in lifecycleRows {
            update(&hasher, string: "L")
            update(&hasher, string: row.scenario.rawValue)
            update(&hasher, string: row.command.rawValue)
            update(&hasher, string: row.actionID.rawValue)
            update(&hasher, string: row.isEnabled ? "1" : "0")
            if let reason = row.disabledReasonID {
                update(&hasher, string: reason.rawValue)
            }
        }
        for route in interactionRoutes {
            update(&hasher, string: "I")
            update(&hasher, string: route.scenario.rawValue)
            update(&hasher, string: route.controlID.rawValue)
            update(&hasher, string: route.actionID.rawValue)
            update(&hasher, string: route.invocation.rawValue)
            update(&hasher, string: outcomeDiscriminator(route.outcome))
            update(&hasher, string: route.isEnabled ? "1" : "0")
        }
        for row in screenshotRows {
            update(&hasher, string: "S")
            update(&hasher, string: row.context.rawValue)
            update(&hasher, string: String(row.manifestRevision.rawValue))
            for item in row.items {
                switch item {
                case .command(let command):
                    update(&hasher, string: command.rawValue)
                case .separator:
                    update(&hasher, string: "|")
                }
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func update(_ hasher: inout SHA256, string: String) {
        hasher.update(data: Data(string.utf8))
    }

    private static func outcomeDiscriminator(_ outcome: Outcome) -> String {
        switch outcome {
        case .invoked(let actionID):
            "invoked:" + actionID.rawValue
        case .menuPresented(let actionIDs):
            "menu:" + actionIDs.map(\.rawValue).joined(separator: ",")
        case .blocked:
            "blocked"
        case .noOp:
            "noOp"
        case .failed(let code):
            "failed:" + code.rawValue
        }
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ToolbarInteractionMatrixError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimit(name: String, value: Int, maximum: Int)
    case countLimitExceeded(kind: String, maximum: Int)
    case stringTooLarge(field: String, maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximum: Int)
    case emptyControls
    case duplicateControl(id: ToolbarInteractionMatrix.StableID)
    case duplicateCommand(command: ToolbarInteractionMatrix.Command)
    case duplicateAction(id: ToolbarInteractionMatrix.StableID)
    case unknownBinding(actionID: ToolbarInteractionMatrix.StableID)
    case missingSemanticBinding(actionID: ToolbarInteractionMatrix.StableID)
    case invalidSource(field: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value, let maximum):
            "Toolbar interaction-matrix limit \(name) is invalid (\(value)); supported maximum is \(maximum)."
        case .countLimitExceeded(let kind, let maximum):
            "Toolbar interaction matrix exceeds the \(maximum)-\(kind) limit."
        case .stringTooLarge(let field, let maximumUTF8Bytes):
            "Toolbar interaction-matrix field \(field) exceeds \(maximumUTF8Bytes) UTF-8 bytes."
        case .totalStringsTooLarge(let maximumUTF8Bytes):
            "Toolbar interaction-matrix strings exceed \(maximumUTF8Bytes) UTF-8 bytes."
        case .workLimitExceeded(let maximum):
            "Toolbar interaction matrix exceeds the \(maximum)-unit work limit."
        case .emptyControls:
            "Toolbar interaction matrix requires at least one control."
        case .duplicateControl(let id):
            "Toolbar interaction matrix has a duplicate control identity (\(id.rawValue))."
        case .duplicateCommand(let command):
            "Toolbar interaction matrix has a duplicate command (\(command.rawValue))."
        case .duplicateAction(let id):
            "Toolbar interaction matrix has a duplicate action identity (\(id.rawValue))."
        case .unknownBinding(let actionID):
            "Toolbar interaction matrix has a binding for an unknown action (\(actionID.rawValue))."
        case .missingSemanticBinding(let actionID):
            "Toolbar interaction matrix has no semantic binding for secondary action (\(actionID.rawValue))."
        case .invalidSource(let field):
            "Toolbar interaction-matrix source is invalid at \(field)."
        case .cancelled:
            "Toolbar interaction matrix was cancelled."
        }
    }
}

private struct ToolbarInteractionMatrixWorkBudget {
    let maximum: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ToolbarInteractionMatrix.CancellationCheck
    private(set) var completed = 0
    private var nextCancellationCheck: Int

    init(limits: ToolbarInteractionMatrix.Limits, cancellationCheck: @escaping ToolbarInteractionMatrix.CancellationCheck) {
        maximum = limits.maximumWorkUnits
        cancellationCheckInterval = limits.cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
        nextCancellationCheck = limits.cancellationCheckInterval
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0, amount <= maximum, completed <= maximum - amount else {
            throw ToolbarInteractionMatrixError.workLimitExceeded(maximum: maximum)
        }
        completed += amount
        if completed >= nextCancellationCheck {
            try checkCancellation()
            let (next, overflow) = completed.addingReportingOverflow(cancellationCheckInterval)
            nextCancellationCheck = overflow ? Int.max : next
        }
    }

    func checkCancellation() throws {
        do {
            try cancellationCheck()
        } catch {
            throw ToolbarInteractionMatrixError.cancelled
        }
    }
}

private struct ToolbarInteractionMatrixStringBudget {
    let limits: ToolbarInteractionMatrix.Limits
    private var total = 0

    init(limits: ToolbarInteractionMatrix.Limits) {
        self.limits = limits
    }

    mutating func identifier(_ value: ToolbarInteractionMatrix.StableID, field: String) throws {
        try nonblank(value.rawValue, field: field)
        guard !value.rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ToolbarInteractionMatrixError.invalidSource(field: field)
        }
    }

    mutating func nonblank(_ value: String, field: String) throws {
        try add(value, field: field)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolbarInteractionMatrixError.invalidSource(field: field)
        }
    }

    mutating func add(_ value: String, field: String) throws {
        let count = value.utf8.count
        guard count <= limits.maximumStringUTF8Bytes else {
            throw ToolbarInteractionMatrixError.stringTooLarge(field: field, maximumUTF8Bytes: limits.maximumStringUTF8Bytes)
        }
        guard total <= limits.maximumTotalStringUTF8Bytes - count else {
            throw ToolbarInteractionMatrixError.totalStringsTooLarge(maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes)
        }
        total += count
    }
}

private typealias WorkBudget = ToolbarInteractionMatrixWorkBudget
private typealias StringBudget = ToolbarInteractionMatrixStringBudget
