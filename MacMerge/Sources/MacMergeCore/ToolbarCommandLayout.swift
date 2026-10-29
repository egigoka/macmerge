import Foundation

/// The comparison window toolbar as the app renders it: control order, separators, control kinds,
/// titles, availability, secondary menus, and the action each interaction dispatches.
///
/// The app's `ComparisonToolbar` view renders `slots` in order and routes primary clicks and
/// menu item selections through `dispatch(_:to:)`. Menu-arrow clicks, keyboard activation, and
/// VoiceOver actions are handled natively by SwiftUI `Menu`/`Button`; their rows in `dispatch`
/// describe the expected native behavior and are not app-routed (see `Interaction.routing`).
/// Slot order and separators come from a `ToolbarConfiguration` (WinMerge `IDR_MAINFRAME` order
/// from `Src/Merge2.rc` by default), never from a second hand-written list.
///
/// `interactionMatrixDescriptors` derives `ToolbarInteractionMatrix.ControlDescriptor` values
/// from this layout, so the audit matrix and the rendered toolbar share ids and secondary actions.
///
/// Scope: this is a model-level contract. It does not prove native AppKit hit-testing, focus
/// order, VoiceOver announcements, or pixel layout; those still require screenshot/AX evidence.
public struct ToolbarCommandLayout: Equatable, Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias NewCommandID = ToolbarNewSplitButtonPlan.CommandID

    // MARK: - Actions

    /// Semantic action the app performs. Every enabled activation resolves to exactly one action.
    public enum Action: Equatable, Hashable, Sendable {
        case newDocument(NewCommandID)
        case openComparison
        case openLeft
        case openRight
        case saveAllChanges
        case saveLeft
        case saveRight
        case saveLeftAs
        case saveRightAs
        case undo
        case redo
        case selectLineDifference
        case nextDifference
        case previousDifference
        case nextConflict
        case previousConflict
        case firstDifference
        case currentDifference
        case lastDifference
        case copyToRight
        case copyToLeft
        case copyToRightAndAdvance
        case copyToLeftAndAdvance
        /// Copy All asks for confirmation before merging, matching WinMerge.
        case requestCopyAllToRight
        case requestCopyAllToLeft
        case autoMerge
        case firstComparedFile
        case previousComparedFile
        case nextComparedFile
        case lastComparedFile
        case openOptions
        case refresh
    }

    // MARK: - Availability

    public enum DisabledReason: Equatable, Hashable, Sendable {
        /// A comparison operation is in progress.
        case comparisonWorking
        /// No side is loaded, so there is nothing to save.
        case nothingLoaded
        /// This side is not loaded.
        case sideNotLoaded
        /// The side is loaded but has nothing that can be saved now.
        case nothingToSave
        case nothingToUndo
        case nothingToRedo
        /// The active difference has no intra-line difference to select.
        case noLineDifference
        case noDifferences
        case noAdjacentDifference
        case noCurrentDifference
        /// The merge policy rejects this copy for the current selection, sides, or read-only state.
        case mergeUnavailable
        /// Both sides must be loaded and idle to recompare.
        case comparisonNotReady
        /// Conflict navigation needs a three-pane conflict comparison, which the app lacks.
        case requiresThreePaneConflictComparison
        /// Auto Merge needs a clean three-pane comparison, which the app lacks.
        case requiresThreePaneComparison
        /// Compared-file navigation needs a parent folder comparison, which the app lacks.
        case requiresFolderComparison
        /// New command routing from `ToolbarNewSplitButtonPlan`.
        case newDocument(ToolbarNewSplitButtonPlan.DisabledReason)
    }

    public enum Availability: Equatable, Hashable, Sendable {
        case enabled
        case disabled(DisabledReason)

        public var isEnabled: Bool { self == .enabled }

        public var disabledReason: DisabledReason? {
            guard case .disabled(let reason) = self else { return nil }
            return reason
        }

        fileprivate static func gate(_ isEnabled: Bool, else reason: DisabledReason) -> Self {
            isEnabled ? .enabled : .disabled(reason)
        }

        fileprivate static func gate(
            notWorking isWorking: Bool, _ isEnabled: Bool, else reason: DisabledReason
        ) -> Self {
            isWorking ? .disabled(.comparisonWorking) : gate(isEnabled, else: reason)
        }
    }

    // MARK: - App state input

    /// Every gate the toolbar reads from the comparison model. The app fills this from
    /// `ComparisonModel` and its command enums; tests can fill it directly.
    public struct State: Equatable, Hashable, Sendable {
        public var isWorking: Bool
        public var isLeftLoaded: Bool
        public var isRightLoaded: Bool
        public var canSaveLeft: Bool
        public var canSaveRight: Bool
        /// Any side has unsaved edits. WinMerge enables Save only when `IsModified()`.
        public var hasUnsavedChanges: Bool
        public var canUndo: Bool
        public var canRedo: Bool
        public var canSelectLineDifference: Bool
        public var hasNavigableDifferences: Bool
        public var canSelectNextDifference: Bool
        public var canSelectPreviousDifference: Bool
        public var canSelectCurrentDifference: Bool
        public var canCopyToRight: Bool
        public var canCopyToLeft: Bool
        public var canCopyToRightAndAdvance: Bool
        public var canCopyToLeftAndAdvance: Bool
        public var canCopyAllToRight: Bool
        public var canCopyAllToLeft: Bool
        public var canRefresh: Bool
        /// Commands the app can create from the New split button today.
        public var implementedNewCommands: Set<NewCommandID>

        public init(
            isWorking: Bool = false,
            isLeftLoaded: Bool = false,
            isRightLoaded: Bool = false,
            canSaveLeft: Bool = false,
            canSaveRight: Bool = false,
            hasUnsavedChanges: Bool = false,
            canUndo: Bool = false,
            canRedo: Bool = false,
            canSelectLineDifference: Bool = false,
            hasNavigableDifferences: Bool = false,
            canSelectNextDifference: Bool = false,
            canSelectPreviousDifference: Bool = false,
            canSelectCurrentDifference: Bool = false,
            canCopyToRight: Bool = false,
            canCopyToLeft: Bool = false,
            canCopyToRightAndAdvance: Bool = false,
            canCopyToLeftAndAdvance: Bool = false,
            canCopyAllToRight: Bool = false,
            canCopyAllToLeft: Bool = false,
            canRefresh: Bool = false,
            implementedNewCommands: Set<NewCommandID> =
                ToolbarNewSplitButtonPlan.currentlyImplementedCommands
        ) {
            self.isWorking = isWorking
            self.isLeftLoaded = isLeftLoaded
            self.isRightLoaded = isRightLoaded
            self.canSaveLeft = canSaveLeft
            self.canSaveRight = canSaveRight
            self.hasUnsavedChanges = hasUnsavedChanges
            self.canUndo = canUndo
            self.canRedo = canRedo
            self.canSelectLineDifference = canSelectLineDifference
            self.hasNavigableDifferences = hasNavigableDifferences
            self.canSelectNextDifference = canSelectNextDifference
            self.canSelectPreviousDifference = canSelectPreviousDifference
            self.canSelectCurrentDifference = canSelectCurrentDifference
            self.canCopyToRight = canCopyToRight
            self.canCopyToLeft = canCopyToLeft
            self.canCopyToRightAndAdvance = canCopyToRightAndAdvance
            self.canCopyToLeftAndAdvance = canCopyToLeftAndAdvance
            self.canCopyAllToRight = canCopyAllToRight
            self.canCopyAllToLeft = canCopyAllToLeft
            self.canRefresh = canRefresh
            self.implementedNewCommands = implementedNewCommands
        }

        /// Gates of a newly opened window: idle, nothing loaded, no history, no differences.
        public static let freshWindow = State()

        public var hasLoadedSide: Bool { isLeftLoaded || isRightLoaded }
    }

    // MARK: - Controls

    public enum ControlKind: String, CaseIterable, Hashable, Sendable {
        /// Single-action button.
        case button
        /// Primary button plus visible drop-down arrow with secondary actions.
        case splitButton
    }

    public struct MenuItem: Equatable, Hashable, Sendable, Identifiable {
        /// Stable identity, also used as the accessibility identifier suffix.
        public let id: String
        public let title: String
        public let accessibilityLabel: String?
        public let systemImage: String?
        public let action: Action
        public let availability: Availability

        public var isEnabled: Bool { availability.isEnabled }
    }

    public indirect enum MenuElement: Equatable, Hashable, Sendable {
        case item(MenuItem)
        case separator
        case submenu(id: String, title: String, elements: [MenuElement])

        /// Selectable items in this element, depth first.
        public var items: [MenuItem] {
            switch self {
            case .item(let item): [item]
            case .separator: []
            case .submenu(_, _, let elements): elements.flatMap(\.items)
            }
        }
    }

    public struct Control: Equatable, Hashable, Sendable, Identifiable {
        public let command: Command
        public let kind: ControlKind
        public let title: String
        public let systemImage: String
        public let help: String
        /// Overrides `title` for VoiceOver when present.
        public let accessibilityLabel: String?
        /// VoiceOver hint announcing secondary actions, when present.
        public let accessibilityHint: String?
        public let accessibilityIdentifier: String
        public let primaryAction: Action
        public let availability: Availability
        /// Secondary actions. Empty unless `kind == .splitButton`.
        public let menu: [MenuElement]

        public var id: Command { command }
        public var isEnabled: Bool { availability.isEnabled }
        public var menuItems: [MenuItem] { menu.flatMap(\.items) }
        public var hasSecondaryActions: Bool { kind == .splitButton }
    }

    public enum Slot: Equatable, Hashable, Sendable {
        case control(Control)
        case separator

        public var control: Control? {
            guard case .control(let control) = self else { return nil }
            return control
        }
    }

    // MARK: - Layout

    public let state: State
    public let configuration: ToolbarConfiguration
    public let slots: [Slot]

    public var controls: [Control] { slots.compactMap(\.control) }

    public func control(for command: Command) -> Control? {
        controls.first { $0.command == command }
    }

    /// Builds the toolbar for the given gates. Order and separators follow `configuration.items`.
    public static func make(
        state: State,
        configuration: ToolbarConfiguration = .winMergeDefault
    ) -> ToolbarCommandLayout {
        let slots: [Slot] = configuration.items.map { item in
            switch item {
            case .separator: .separator
            case .command(let command): .control(makeControl(command, state: state))
            }
        }
        return ToolbarCommandLayout(state: state, configuration: configuration, slots: slots)
    }

    /// Stable accessibility identifier for a toolbar control: `toolbar.<command>`, the same id
    /// `ToolbarAccessibilityInventory.controlID(for:)` and the audit contract use. No exceptions.
    public static func accessibilityIdentifier(for command: Command) -> String {
        ToolbarAccessibilityInventory.controlID(for: command).rawValue
    }

    /// Stable accessibility identifier for a menu item: `toolbar.<command>.<item id>`.
    public static func accessibilityIdentifier(for item: MenuItem, in command: Command) -> String {
        "\(accessibilityIdentifier(for: command)).\(item.id)"
    }

    /// Toolbar title for the six copy commands. `ComparisonCopyCommand.toolbarLabel` in the app
    /// reads this table, so toolbar titles and AX test fixtures cannot drift apart.
    public static func copyTitle(for command: Command) -> String? {
        switch command {
        case .copyToRight: "Copy selected difference to right"
        case .copyToLeft: "Copy selected difference to left"
        case .copyToRightAndAdvance: "Copy selected difference to right and advance"
        case .copyToLeftAndAdvance: "Copy selected difference to left and advance"
        case .copyAllToRight: "Copy all differences to right"
        case .copyAllToLeft: "Copy all differences to left"
        default: nil
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func makeControl(_ command: Command, state: State) -> Control {
        let working = state.isWorking
        let copyLabel = copyTitle(for: command) ?? ""
        func button(
            _ title: String, _ systemImage: String, _ help: String,
            _ action: Action, _ availability: Availability
        ) -> Control {
            Control(
                command: command, kind: .button, title: title, systemImage: systemImage,
                help: help, accessibilityLabel: nil, accessibilityHint: nil,
                accessibilityIdentifier: accessibilityIdentifier(for: command),
                primaryAction: action, availability: availability, menu: []
            )
        }

        switch command {
        case .newComparison:
            let plan = ToolbarNewSplitButtonPlan.make(
                isNewCommandEnabled: !working,
                implementedCommands: state.implementedNewCommands
            )
            return Control(
                command: command, kind: .splitButton,
                title: ToolbarNewSplitButtonPlan.primaryTitle,
                systemImage: "doc.badge.plus",
                help: ToolbarNewSplitButtonPlan.primaryHelp,
                accessibilityLabel: ToolbarNewSplitButtonPlan.primaryAccessibilityLabel,
                accessibilityHint: ToolbarNewSplitButtonPlan.secondaryActionsAccessibilityHint,
                accessibilityIdentifier: accessibilityIdentifier(for: command),
                primaryAction: .newDocument(plan.primaryCommandID),
                availability: newAvailability(plan.primaryAvailability),
                menu: newMenu(plan)
            )

        case .openComparison:
            let availability = Availability.gate(!working, else: .comparisonWorking)
            return Control(
                command: command, kind: .splitButton, title: "Open files", systemImage: "folder",
                help: "Select files to compare (\(FileLifecycleShortcuts.helpText(.open)))",
                accessibilityLabel: nil, accessibilityHint: "Shows options to open each side.",
                accessibilityIdentifier: accessibilityIdentifier(for: command),
                primaryAction: .openComparison, availability: availability,
                menu: [
                    .item(
                        MenuItem(
                            id: "openComparison", title: "Open Comparison...", accessibilityLabel: nil,
                            systemImage: "folder", action: .openComparison, availability: .enabled)),
                    .separator,
                    .item(
                        MenuItem(
                            id: "openLeft", title: "Open Left...", accessibilityLabel: nil,
                            systemImage: "rectangle.split.2x1", action: .openLeft,
                            availability: .enabled)),
                    .item(
                        MenuItem(
                            id: "openRight", title: "Open Right...", accessibilityLabel: nil,
                            systemImage: "rectangle.split.2x1", action: .openRight,
                            availability: .enabled))
                ]
            )

        case .save:
            // WinMerge `CMergeDoc::OnUpdateFileSave` enables Save only when a side is modified.
            let availability: Availability =
                if working {
                    .disabled(.comparisonWorking)
                } else if !state.hasLoadedSide {
                    .disabled(.nothingLoaded)
                } else {
                    .gate(state.hasUnsavedChanges, else: .nothingToSave)
                }
            func saveGate(loaded: Bool, canSave: Bool) -> Availability {
                loaded ? .gate(canSave, else: .nothingToSave) : .disabled(.sideNotLoaded)
            }
            return Control(
                command: command, kind: .splitButton, title: "Save",
                systemImage: "square.and.arrow.down",
                help: "Save changed files (\(FileLifecycleShortcuts.helpText(.save)))",
                accessibilityLabel: nil, accessibilityHint: "Shows options to save each side.",
                accessibilityIdentifier: accessibilityIdentifier(for: command),
                primaryAction: .saveAllChanges, availability: availability,
                menu: [
                    .item(
                        MenuItem(
                            id: "saveLeft", title: "Save Left", accessibilityLabel: nil,
                            systemImage: nil, action: .saveLeft,
                            availability: saveGate(loaded: state.isLeftLoaded, canSave: state.canSaveLeft))),
                    .item(
                        MenuItem(
                            id: "saveRight", title: "Save Right", accessibilityLabel: nil,
                            systemImage: nil, action: .saveRight,
                            availability: saveGate(loaded: state.isRightLoaded, canSave: state.canSaveRight))),
                    .separator,
                    .item(
                        MenuItem(
                            id: "saveLeftAs", title: "Save Left As...", accessibilityLabel: nil,
                            systemImage: nil, action: .saveLeftAs,
                            availability: .gate(state.isLeftLoaded, else: .sideNotLoaded))),
                    .item(
                        MenuItem(
                            id: "saveRightAs", title: "Save Right As...", accessibilityLabel: nil,
                            systemImage: nil, action: .saveRightAs,
                            availability: .gate(state.isRightLoaded, else: .sideNotLoaded)))
                ]
            )

        case .undo:
            return button(
                "Undo", "arrow.uturn.backward", "Undo the last edit or merge", .undo,
                .gate(notWorking: working, state.canUndo, else: .nothingToUndo))
        case .redo:
            return button(
                "Redo", "arrow.uturn.forward", "Redo the last edit or merge", .redo,
                .gate(notWorking: working, state.canRedo, else: .nothingToRedo))
        case .selectLineDifference:
            return button(
                "Select line difference", "character.cursor.ibeam",
                "Select the intra-line difference in the active pane (F4)", .selectLineDifference,
                .gate(notWorking: working, state.canSelectLineDifference, else: .noLineDifference))
        case .nextDifference:
            return button(
                "Next difference", "arrow.down", "Go to next difference (F8)", .nextDifference,
                navigation(state, state.canSelectNextDifference))
        case .previousDifference:
            return button(
                "Previous difference", "arrow.up", "Go to previous difference (F7)",
                .previousDifference, navigation(state, state.canSelectPreviousDifference))
        case .nextConflict:
            return button(
                "Next conflict", "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                "Next conflict is available in three-pane conflict comparisons", .nextConflict,
                .disabled(.requiresThreePaneConflictComparison))
        case .previousConflict:
            return button(
                "Previous conflict", "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                "Previous conflict is available in three-pane conflict comparisons",
                .previousConflict, .disabled(.requiresThreePaneConflictComparison))
        case .firstDifference:
            return button(
                "First difference", "arrow.up.to.line", "Go to first difference",
                .firstDifference, navigation(state, true))
        case .currentDifference:
            return button(
                "Current difference", "scope", "Reveal the current difference",
                .currentDifference,
                .gate(
                    notWorking: working, state.canSelectCurrentDifference,
                    else: .noCurrentDifference))
        case .lastDifference:
            return button(
                "Last difference", "arrow.down.to.line", "Go to last difference",
                .lastDifference, navigation(state, true))
        case .copyToRight:
            return button(
                copyLabel, "arrow.right",
                "Copy the selected or current difference to right ("
                    + DirectionalCopyShortcuts.shortcutHint(for: .copyToRight) + ")", .copyToRight,
                merge(state, state.canCopyToRight))
        case .copyToLeft:
            return button(
                copyLabel, "arrow.left",
                "Copy the selected or current difference to left ("
                    + DirectionalCopyShortcuts.shortcutHint(for: .copyToLeft) + ")", .copyToLeft,
                merge(state, state.canCopyToLeft))
        case .copyToRightAndAdvance:
            return button(
                copyLabel, "arrow.right.circle",
                "Copy selected difference to right and advance", .copyToRightAndAdvance,
                merge(state, state.canCopyToRightAndAdvance))
        case .copyToLeftAndAdvance:
            return button(
                copyLabel, "arrow.left.circle",
                "Copy selected difference to left and advance", .copyToLeftAndAdvance,
                merge(state, state.canCopyToLeftAndAdvance))
        case .copyAllToRight:
            return button(
                copyLabel, "arrow.right.to.line",
                "Copy all differences to right", .requestCopyAllToRight,
                merge(state, state.canCopyAllToRight))
        case .copyAllToLeft:
            return button(
                copyLabel, "arrow.left.to.line",
                "Copy all differences to left", .requestCopyAllToLeft,
                merge(state, state.canCopyAllToLeft))
        case .autoMerge:
            return button(
                "Auto merge", "wand.and.stars",
                "Auto Merge is available in clean three-pane comparisons", .autoMerge,
                .disabled(.requiresThreePaneComparison))
        case .firstComparedFile:
            return button(
                "First compared file", "backward.end", comparedFileHelp, .firstComparedFile,
                .disabled(.requiresFolderComparison))
        case .previousComparedFile:
            return button(
                "Previous compared file", "backward", comparedFileHelp, .previousComparedFile,
                .disabled(.requiresFolderComparison))
        case .nextComparedFile:
            return button(
                "Next compared file", "forward", comparedFileHelp, .nextComparedFile,
                .disabled(.requiresFolderComparison))
        case .lastComparedFile:
            return button(
                "Last compared file", "forward.end", comparedFileHelp, .lastComparedFile,
                .disabled(.requiresFolderComparison))
        case .options:
            // Plain button; the app performs `.openOptions` with `openSettings`. WinMerge also
            // shows an `IDR_POPUP_DIFF_OPTIONS` drop-down here, which the Mac lacks, so
            // `ToolbarCommandOrderSnapshot.divergences()` reports `.missingSecondaryActions(.options)`.
            return button(
                "Options", "gearshape", "Open comparison options (Command-,)", .openOptions,
                .enabled)
        case .refresh:
            return button(
                "Refresh", "arrow.clockwise",
                "Recompare the current in-memory text without reloading files", .refresh,
                .gate(notWorking: working, state.canRefresh, else: .comparisonNotReady))
        }
    }

    private static let comparedFileHelp =
        "Compared-file navigation is available from folder comparisons"

    private static func navigation(_ state: State, _ hasTarget: Bool) -> Availability {
        if state.isWorking { return .disabled(.comparisonWorking) }
        guard state.hasNavigableDifferences else { return .disabled(.noDifferences) }
        return .gate(hasTarget, else: .noAdjacentDifference)
    }

    private static func merge(_ state: State, _ isEnabled: Bool) -> Availability {
        .gate(notWorking: state.isWorking, isEnabled, else: .mergeUnavailable)
    }

    private static func newAvailability(
        _ availability: ToolbarNewSplitButtonPlan.Availability
    ) -> Availability {
        switch availability {
        case .enabled: .enabled
        case .disabled(.newCommandUnavailable): .disabled(.comparisonWorking)
        case .disabled(let reason): .disabled(.newDocument(reason))
        }
    }

    private static func newMenu(_ plan: ToolbarNewSplitButtonPlan) -> [MenuElement] {
        var elements: [MenuElement] = []
        for (index, section) in plan.sections.enumerated() {
            if index > 0 { elements.append(.separator) }
            let items: [MenuElement] = section.entries.map { entry in
                .item(
                    MenuItem(
                        id: entry.commandID.rawValue, title: entry.title,
                        accessibilityLabel: entry.accessibilityLabel, systemImage: nil,
                        action: .newDocument(entry.commandID),
                        availability: newAvailability(entry.availability)))
            }
            switch section.presentation {
            case .inline:
                elements.append(contentsOf: items)
            case .submenu:
                elements.append(
                    .submenu(id: section.id, title: section.title ?? "", elements: items))
            }
        }
        return elements
    }

    // MARK: - Interaction dispatch

    /// Ways a user can activate a toolbar control.
    public enum Interaction: Equatable, Hashable, Sendable {
        /// Mouse click on the control body (the primary half of a split button).
        case primaryClick
        /// Mouse click on a split button's drop-down arrow.
        case menuArrowClick
        /// Choosing an item, by `MenuItem.id`, from the split button's menu.
        case menuItemSelection(String)
        /// Space with keyboard focus on the control (Full Keyboard Access).
        case keyboardActivation
        /// VoiceOver `AXPress` (VO-Space).
        case voiceOverPress
        /// VoiceOver `AXShowMenu` (VO-Shift-M).
        case voiceOverShowMenu

        /// Who resolves this interaction in the running app.
        public var routing: InteractionRouting {
            switch self {
            case .primaryClick, .menuItemSelection: .appDispatched
            case .menuArrowClick, .keyboardActivation, .voiceOverPress, .voiceOverShowMenu:
                .nativeUnverified
            }
        }
    }

    public enum InteractionRouting: Equatable, Hashable, Sendable {
        /// The app calls `dispatch(_:to:)` and performs the returned action.
        case appDispatched
        /// SwiftUI `Menu`/`Button` handles the event natively. The `dispatch` row is the expected
        /// native behavior only; no AX test has verified it (for example, `Menu(primaryAction:)`
        /// may present the menu on `AXPress` instead of running the primary action).
        case nativeUnverified
    }

    public enum IgnoredReason: Equatable, Hashable, Sendable {
        /// The control is disabled, so no part of it reacts.
        case controlDisabled(DisabledReason)
        /// The chosen menu item is disabled.
        case menuItemDisabled(id: String, DisabledReason)
        /// The control has no menu.
        case noSecondaryActions
        /// The menu has no item with this identifier.
        case unknownMenuItem(String)
    }

    public enum InteractionOutcome: Equatable, Hashable, Sendable {
        case perform(Action)
        case presentMenu([MenuElement])
        case ignored(IgnoredReason)

        public var performedAction: Action? {
            guard case .perform(let action) = self else { return nil }
            return action
        }
    }

    /// Resolves an interaction to its outcome. The app calls this for primary clicks and menu item
    /// selections; other interactions are `.nativeUnverified` expectations.
    /// Returns `nil` only when the command is absent from this layout.
    public func dispatch(_ interaction: Interaction, to command: Command) -> InteractionOutcome? {
        control(for: command).map { Self.dispatch(interaction, to: $0) }
    }

    public static func dispatch(
        _ interaction: Interaction, to control: Control
    ) -> InteractionOutcome {
        if case .disabled(let reason) = control.availability {
            return .ignored(.controlDisabled(reason))
        }
        switch interaction {
        case .primaryClick, .keyboardActivation, .voiceOverPress:
            return .perform(control.primaryAction)
        case .menuArrowClick, .voiceOverShowMenu:
            guard control.hasSecondaryActions else { return .ignored(.noSecondaryActions) }
            return .presentMenu(control.menu)
        case .menuItemSelection(let id):
            guard control.hasSecondaryActions else { return .ignored(.noSecondaryActions) }
            guard let item = control.menuItems.first(where: { $0.id == id }) else {
                return .ignored(.unknownMenuItem(id))
            }
            if case .disabled(let reason) = item.availability {
                return .ignored(.menuItemDisabled(id: id, reason))
            }
            return .perform(item.action)
        }
    }

    // MARK: - Interaction matrix bridge

    /// Audit-matrix descriptors derived from this layout: control id is the accessibility id,
    /// primary action id is `ToolbarAccessibilityInventory.primaryActionID(for:)`, and secondary
    /// action ids are the menu items' accessibility ids in menu order.
    public var interactionMatrixDescriptors: [ToolbarInteractionMatrix.ControlDescriptor] {
        controls.map(Self.interactionMatrixDescriptor(for:))
    }

    public static func interactionMatrixDescriptor(
        for control: Control
    ) -> ToolbarInteractionMatrix.ControlDescriptor {
        ToolbarInteractionMatrix.ControlDescriptor(
            controlID: ToolbarAuditStableID(rawValue: control.accessibilityIdentifier),
            command: control.command,
            primaryActionID: ToolbarAccessibilityInventory.primaryActionID(for: control.command),
            secondaryActionIDs: control.menuItems.map {
                ToolbarAuditStableID(
                    rawValue: accessibilityIdentifier(for: $0, in: control.command))
            }
        )
    }

    // MARK: - Order and grouping snapshot

    public var orderSnapshot: ToolbarCommandOrderSnapshot {
        ToolbarCommandOrderSnapshot(layout: self)
    }
}

/// Deterministic order, grouping, kind, and enabled-state snapshot of a `ToolbarCommandLayout`.
///
/// `orderSignature` is state-independent: a fresh window and a loaded comparison must produce the
/// same signature. `stateSignature` adds enabled state and menu contents for per-scenario goldens.
public struct ToolbarCommandOrderSnapshot: Equatable, Hashable, Sendable {
    public struct Entry: Equatable, Hashable, Sendable {
        public let command: ToolbarConfiguration.Command
        public let kind: ToolbarCommandLayout.ControlKind
        public let isEnabled: Bool
        /// Menu item ids in order. `"!id"` marks a disabled item, `"-"` a separator, and
        /// `"id>"`/`"<"` open and close a submenu.
        public let menu: [String]
        /// Selectable menu item ids in order, without state or structure tokens.
        public let menuItemIDs: [String]
        public let title: String
        public let accessibilityLabel: String
        public let accessibilityHint: String?
        public let accessibilityIdentifier: String
        public let help: String
    }

    public enum Divergence: Equatable, Hashable, Sendable {
        /// Slot sequence differs from the reference items at this index.
        case slotMismatch(
            index: Int, expected: ToolbarConfiguration.Item?,
            actual: ToolbarConfiguration.Item?)
        /// A control is not a primary/drop-down split control where WinMerge has one.
        case missingSecondaryActions(ToolbarConfiguration.Command)
        /// A split control's menu items differ from its `SecondaryMenuContract`.
        case secondaryMenuMismatch(
            ToolbarConfiguration.Command, expected: [String], actual: [String])
    }

    /// Expected secondary menu of one WinMerge drop-down control.
    public struct SecondaryMenuContract: Equatable, Hashable, Sendable {
        public let command: ToolbarConfiguration.Command
        /// WinMerge menu resource shown by `CMainFrame::OnToolbarButtonDropDown`.
        public let winMergeMenu: String
        /// Menu item ids the Mac control must show, in order. `nil` when the Mac has no menu yet.
        public let macItemIDs: [String]?
        /// Why the Mac menu differs from `winMergeMenu`, or `nil` when it mirrors it.
        public let macException: String?
    }

    /// Separator-delimited groups. Empty groups (adjacent or edge separators) are preserved.
    public let groups: [[Entry]]
    /// Slot sequence as configuration items, for direct comparison with `Merge2.rc`.
    public let items: [ToolbarConfiguration.Item]

    /// Commands WinMerge draws with `TBSTYLE_DROPDOWN`: `Src/MainFrm.cpp` loops over
    /// `{ ID_OPTIONS, ID_FILE_NEW, ID_FILE_OPEN, ID_FILE_SAVE }`.
    public static let splitButtonCommands: [ToolbarConfiguration.Command] = [
        .options, .newComparison, .openComparison, .save
    ]

    /// Secondary menu source for every WinMerge drop-down, with documented Mac exceptions.
    public static let secondaryMenuContracts: [SecondaryMenuContract] = [
        SecondaryMenuContract(
            command: .options, winMergeMenu: "IDR_POPUP_DIFF_OPTIONS", macItemIDs: nil,
            macException: nil),
        SecondaryMenuContract(
            command: .newComparison, winMergeMenu: "IDR_POPUP_NEW",
            macItemIDs: ToolbarNewSplitButtonPlan.make(isNewCommandEnabled: true)
                .entries.map(\.commandID.rawValue),
            macException:
                "Adds the File menu New (&3 panes) submenu; see ToolbarNewSplitButtonPlan."),
        SecondaryMenuContract(
            command: .openComparison, winMergeMenu: "IDR_POPUP_OPEN",
            macItemIDs: ["openComparison", "openLeft", "openRight"],
            macException:
                "WinMerge shows the recent-files (MRU) list; the Mac has no MRU list and offers "
                + "Open Comparison, Open Left, and Open Right instead."),
        SecondaryMenuContract(
            command: .save, winMergeMenu: "IDR_POPUP_SAVE",
            macItemIDs: ["saveLeft", "saveRight", "saveLeftAs", "saveRightAs"],
            macException:
                "Save Middle and Save Middle As are omitted: the Mac comparison window is two-pane.")
    ]

    public init(layout: ToolbarCommandLayout) {
        var groups: [[Entry]] = [[]]
        var items: [ToolbarConfiguration.Item] = []
        for slot in layout.slots {
            switch slot {
            case .separator:
                groups.append([])
                items.append(.separator)
            case .control(let control):
                groups[groups.count - 1].append(
                    Entry(
                        command: control.command, kind: control.kind, isEnabled: control.isEnabled,
                        menu: Self.menuTokens(control.menu),
                        menuItemIDs: control.menuItems.map(\.id),
                        title: control.title,
                        accessibilityLabel: control.accessibilityLabel ?? control.title,
                        accessibilityHint: control.accessibilityHint,
                        accessibilityIdentifier: control.accessibilityIdentifier,
                        help: control.help))
                items.append(.command(control.command))
            }
        }
        self.groups = groups
        self.items = items
    }

    /// Order and grouping only, e.g. `newComparison openComparison save | undo redo | ...`.
    public var orderSignature: String {
        groups.map { $0.map(\.command.rawValue).joined(separator: " ") }.joined(separator: " | ")
    }

    /// Order, grouping, kind, enabled state, and menu shape.
    public var stateSignature: String {
        groups.map { group in
            group.map { entry in
                var token = "\(entry.command.rawValue)[\(entry.kind.rawValue),"
                token += entry.isEnabled ? "on" : "off"
                if !entry.menu.isEmpty { token += ":" + entry.menu.joined(separator: ",") }
                return token + "]"
            }.joined(separator: " ")
        }.joined(separator: " | ")
    }

    /// Title, VoiceOver label, hint, accessibility id, and help per control, one line each.
    /// Golden tests compare this to catch label and id regressions.
    public var presentationLines: [String] {
        groups.joined().map { entry in
            [
                entry.command.rawValue, entry.accessibilityIdentifier, entry.title,
                entry.accessibilityLabel, entry.accessibilityHint ?? "-", entry.help
            ].joined(separator: " | ")
        }
    }

    /// Differences from the reference toolbar: slot order and grouping, WinMerge drop-down
    /// controls (Options, New, Open, Save), and secondary menu items per
    /// `secondaryMenuContracts`. Menu differences recorded as a contract's `macException` are
    /// documented, not reported. Defaults to WinMerge `IDR_MAINFRAME`.
    public func divergences(
        from reference: [ToolbarConfiguration.Item] = ToolbarConfiguration.winMergeDefaultItems
    ) -> [Divergence] {
        var result: [Divergence] = []
        for index in 0..<max(reference.count, items.count) {
            let expected = reference.indices.contains(index) ? reference[index] : nil
            let actual = items.indices.contains(index) ? items[index] : nil
            if expected != actual {
                result.append(.slotMismatch(index: index, expected: expected, actual: actual))
            }
        }
        let entries = Dictionary(
            groups.joined().map { ($0.command, $0) }, uniquingKeysWith: { first, _ in first })
        for command in Self.splitButtonCommands {
            if let entry = entries[command], entry.kind != .splitButton {
                result.append(.missingSecondaryActions(command))
            }
        }
        for contract in Self.secondaryMenuContracts {
            guard let entry = entries[contract.command], entry.kind == .splitButton,
                let expected = contract.macItemIDs, expected != entry.menuItemIDs
            else { continue }
            result.append(
                .secondaryMenuMismatch(
                    contract.command, expected: expected, actual: entry.menuItemIDs))
        }
        return result
    }

    private static func menuTokens(_ elements: [ToolbarCommandLayout.MenuElement]) -> [String] {
        elements.flatMap { element -> [String] in
            switch element {
            case .item(let item): [item.isEnabled ? item.id : "!\(item.id)"]
            case .separator: ["-"]
            case .submenu(let id, _, let children): ["\(id)>"] + menuTokens(children) + ["<"]
            }
        }
    }
}
