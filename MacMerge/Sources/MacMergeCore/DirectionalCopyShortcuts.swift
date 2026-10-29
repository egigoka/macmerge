/// Catalog, conflict audit, and focus-aware routing for WinMerge directional copy accelerators.
///
/// WinMerge `Src/Merge.rc` (`IDR_MAINFRAME` accelerators) binds:
///
/// | Command                    | WinMerge ID          | Accelerator        |
/// |----------------------------|----------------------|--------------------|
/// | Copy to Right              | `ID_L2R`             | `Alt+Right`        |
/// | Copy to Left               | `ID_R2L`             | `Alt+Left`         |
/// | Copy to Right and Advance  | `ID_L2RNEXT`         | `Ctrl+Alt+Right`   |
/// | Copy to Left and Advance   | `ID_R2LNEXT`         | `Ctrl+Alt+Left`    |
/// | Copy from Left             | `ID_COPY_FROM_LEFT`  | `Alt+Shift+Right`  |
/// | Copy from Right            | `ID_COPY_FROM_RIGHT` | `Alt+Shift+Left`   |
///
/// On macOS, Alt maps to Option and Ctrl to Command. Option-Left/Right is standard word
/// navigation in every selectable or editable text view, so Copy to Right/Left cannot be plain
/// menu key equivalents: AppKit offers menu key equivalents before the focused text view sees the
/// key, which would steal word navigation. Those two chords are focus-routed alternates that a
/// key monitor offers to `route(_:in:enabledCommands:policy:)`; the shared
/// `KeyboardShortcutPolicy` keeps the chord for native text whenever a text view owns input.
///
/// Command-Option-Left/Right has no standard text-system meaning, so copy-and-advance stays a
/// menu key equivalent. The Merge menu derives those key equivalents from `menuBinding(for:)`,
/// and `auditConflicts(policy:)` re-verifies the catalog split against the policy's native
/// reservations so a future reservation cannot silently make a menu binding steal text
/// navigation. The audit covers this catalog, not a captured live menu.
///
/// Option-Shift-Left/Right extends the selection by word in text views. WinMerge binds it to
/// Copy from Left/Right (`CMergeEditView::OnCopyFromLeft`/`OnCopyFromRight`, which call
/// `OnCopyX2Y` in both 2- and 3-pane compares to copy into the active pane). In MacMerge that
/// command is only reachable from the diff-row context menu, so the chords stay unbound because
/// native word-selection extension owns them. They are recorded in
/// `unmappedWinMergeAccelerators`.
public enum DirectionalCopyShortcuts {
    public typealias Chord = KeyboardShortcutPolicy.Chord
    public typealias Delivery = DifferenceNavigationShortcuts.Delivery

    public enum Command: String, CaseIterable, Equatable, Hashable, Sendable {
        case copyToRight
        case copyToLeft
        case copyToRightAndAdvance
        case copyToLeftAndAdvance

        public var identifier: ComparisonCommandState.Identifier {
            switch self {
            case .copyToRight: .copyToRight
            case .copyToLeft: .copyToLeft
            case .copyToRightAndAdvance: .copyToRightAndAdvance
            case .copyToLeftAndAdvance: .copyToLeftAndAdvance
            }
        }

        public init?(_ identifier: ComparisonCommandState.Identifier) {
            switch identifier {
            case .copyToRight: self = .copyToRight
            case .copyToLeft: self = .copyToLeft
            case .copyToRightAndAdvance: self = .copyToRightAndAdvance
            case .copyToLeftAndAdvance: self = .copyToLeftAndAdvance
            default: return nil
            }
        }

        /// WinMerge `Src/resource.h` command identifier.
        public var winMergeCommandID: String {
            switch self {
            case .copyToRight: "ID_L2R"
            case .copyToLeft: "ID_R2L"
            case .copyToRightAndAdvance: "ID_L2RNEXT"
            case .copyToLeftAndAdvance: "ID_R2LNEXT"
            }
        }

        public var menuTitle: String {
            switch self {
            case .copyToRight: "Copy to Right"
            case .copyToLeft: "Copy to Left"
            case .copyToRightAndAdvance: "Copy to Right and Advance"
            case .copyToLeftAndAdvance: "Copy to Left and Advance"
            }
        }

        public var advancesSelection: Bool {
            switch self {
            case .copyToRight, .copyToLeft: false
            case .copyToRightAndAdvance, .copyToLeftAndAdvance: true
            }
        }
    }

    public struct Binding: Equatable, Hashable, Sendable {
        public let command: Command
        public let chord: Chord
        public let delivery: Delivery
        /// Accelerator spelling as written in WinMerge `Src/Merge.rc`.
        public let winMergeAccelerator: String

        public init(
            command: Command,
            chord: Chord,
            delivery: Delivery,
            winMergeAccelerator: String
        ) {
            self.command = command
            self.chord = chord
            self.delivery = delivery
            self.winMergeAccelerator = winMergeAccelerator
        }
    }

    /// Every directional copy binding in canonical command order. Chords match
    /// `KeyboardShortcutPolicy.unfinishedAuditCommandShortcuts` exactly.
    public static let bindings: [Binding] = [
        binding(.copyToRight, .rightArrow, [.option], .focusRoutedAlternate, "VK_RIGHT, ALT"),
        binding(.copyToLeft, .leftArrow, [.option], .focusRoutedAlternate, "VK_LEFT, ALT"),
        binding(
            .copyToRightAndAdvance,
            .rightArrow,
            [.command, .option],
            .menuKeyEquivalent,
            "VK_RIGHT, CONTROL, ALT"
        ),
        binding(
            .copyToLeftAndAdvance,
            .leftArrow,
            [.command, .option],
            .menuKeyEquivalent,
            "VK_LEFT, CONTROL, ALT"
        )
    ]

    /// A WinMerge copy accelerator that MacMerge deliberately leaves unbound.
    public struct UnmappedAccelerator: Equatable, Hashable, Sendable {
        public enum Reason: Equatable, Hashable, Sendable {
            /// The macOS chord belongs to native text editing, so MacMerge offers the command
            /// only through a context menu, not a key equivalent.
            case nativeTextReservation(KeyboardShortcutPolicy.NativeTextEditingCommand)
        }

        public let winMergeCommandID: String
        public let winMergeAccelerator: String
        public let macChord: Chord
        public let reason: Reason

        public init(
            winMergeCommandID: String,
            winMergeAccelerator: String,
            macChord: Chord,
            reason: Reason
        ) {
            self.winMergeCommandID = winMergeCommandID
            self.winMergeAccelerator = winMergeAccelerator
            self.macChord = macChord
            self.reason = reason
        }
    }

    public static let unmappedWinMergeAccelerators: [UnmappedAccelerator] = [
        UnmappedAccelerator(
            winMergeCommandID: "ID_COPY_FROM_LEFT",
            winMergeAccelerator: "VK_RIGHT, SHIFT, ALT",
            macChord: chord(.rightArrow, [.option, .shift]),
            reason: .nativeTextReservation(.moveWordRightAndModifySelection)
        ),
        UnmappedAccelerator(
            winMergeCommandID: "ID_COPY_FROM_RIGHT",
            winMergeAccelerator: "VK_LEFT, SHIFT, ALT",
            macChord: chord(.leftArrow, [.option, .shift]),
            reason: .nativeTextReservation(.moveWordLeftAndModifySelection)
        )
    ]

    public static func bindings(for command: Command) -> [Binding] {
        bindings.filter { $0.command == command }
    }

    /// The menu key equivalent for `command`, or `nil` when the command is only reachable by
    /// keyboard through a focus-routed alternate (Copy to Right/Left).
    public static func menuBinding(for command: Command) -> Binding? {
        bindings.first { $0.command == command && $0.delivery == .menuKeyEquivalent }
    }

    /// Human-readable macOS spelling of a copy chord, for example `Option-Right Arrow`.
    /// Modifiers follow the macOS menu order (Control, Option, Shift, Command).
    public static func displayName(of chord: Chord) -> String {
        let order: [(KeyboardShortcutPolicy.Modifier, String)] = [
            (.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")
        ]
        let modifiers = order.filter { chord.modifiers.contains($0.0) }.map(\.1)
        let key: String
        switch chord.key {
        case .special(.leftArrow): key = "Left Arrow"
        case .special(.rightArrow): key = "Right Arrow"
        case .special(.upArrow): key = "Up Arrow"
        case .special(.downArrow): key = "Down Arrow"
        case .special(.home): key = "Home"
        case .special(.end): key = "End"
        case .special(.pageUp): key = "Page Up"
        case .special(.pageDown): key = "Page Down"
        case .special(.backspace): key = "Delete"
        case .special(.delete): key = "Forward Delete"
        case .special(.escape): key = "Escape"
        case .special(.return): key = "Return"
        case .special(.space): key = "Space"
        case .special(.tab): key = "Tab"
        case .character(let character): key = String(character).uppercased()
        case .function(let number): key = "F\(number)"
        }
        return (modifiers + [key]).joined(separator: "-")
    }

    /// Short shortcut note for tooltips. Focus-routed chords name the focus they need, because a
    /// focused selectable or editable text view keeps them for word navigation.
    public static func shortcutHint(for command: Command) -> String {
        if let binding = menuBinding(for: command) {
            return displayName(of: binding.chord)
        }
        let alternates = bindings(for: command).filter { $0.delivery == .focusRoutedAlternate }
        let names = alternates.map { displayName(of: $0.chord) }.joined(separator: ", ")
        return "\(names) when the diff list has focus"
    }

    /// Menu item tooltip for a command whose keyboard access is a focus-routed alternate, or
    /// `nil` when the menu item already shows its key equivalent.
    public static func alternateHint(for command: Command) -> String? {
        let alternates = bindings(for: command).filter { $0.delivery == .focusRoutedAlternate }
        guard !alternates.isEmpty else { return nil }
        let names = alternates.map {
            "\(displayName(of: $0.chord)) (WinMerge \($0.winMergeAccelerator))"
        }.joined(separator: ", ")
        return "Also \(names) when the diff list has focus. "
            + "A focused text view keeps the chord for word navigation."
    }

    public static var focusRoutedBindings: [Binding] {
        bindings.filter { $0.delivery == .focusRoutedAlternate }
    }

    public static func focusRoutedBinding(matching chord: Chord) -> Binding? {
        bindings.first { $0.delivery == .focusRoutedAlternate && $0.chord == chord }
    }

    // MARK: - Conflict audit

    /// One way a binding's delivery disagrees with the policy's native text reservations.
    public struct Conflict: Equatable, Hashable, Sendable {
        public enum Kind: Equatable, Hashable, Sendable {
            /// A menu key equivalent resolves to native text editing under text focus, so the
            /// menu would fire before the text view and steal the chord.
            case menuKeyEquivalentStealsNativeText(KeyboardShortcutPolicy.NativeTextEditingCommand)
            /// A focus-routed binding never yields to native text, so it gains nothing from
            /// focus routing and should be reviewed as a menu key equivalent.
            case focusRoutingWithoutNativeReservation
            /// The binding does not dispatch its command even when no text view owns input.
            case unreachableWithoutTextFocus(KeyboardShortcutPolicy.Route)
            /// The policy could not resolve the chord within its limits.
            case policyFailure(KeyboardShortcutPolicyError)
        }

        public let binding: Binding
        public let editorFocus: KeyboardShortcutPolicy.EditorFocus
        public let kind: Kind

        public init(binding: Binding, editorFocus: KeyboardShortcutPolicy.EditorFocus, kind: Kind) {
            self.binding = binding
            self.editorFocus = editorFocus
            self.kind = kind
        }
    }

    /// Verifies every binding against `policy` in a state where all copy commands are available.
    /// Returns findings in binding order, then focus order (`none`, `readOnly`, `editable`).
    /// An empty result means focus routing exactly covers the chords native text owns.
    public static func auditConflicts(policy: KeyboardShortcutPolicy) -> [Conflict] {
        var conflicts: [Conflict] = []
        for binding in bindings {
            for focus in KeyboardShortcutPolicy.EditorFocus.allCases {
                let context = auditContext(editorFocus: focus)
                let resolution: KeyboardShortcutPolicy.Resolution
                do {
                    resolution = try policy.resolve(binding.chord, in: context, cancellationCheck: {})
                } catch {
                    conflicts.append(
                        Conflict(binding: binding, editorFocus: focus, kind: .policyFailure(error))
                    )
                    continue
                }
                if let kind = conflictKind(binding: binding, focus: focus, route: resolution) {
                    conflicts.append(Conflict(binding: binding, editorFocus: focus, kind: kind))
                }
            }
        }
        return conflicts
    }

    private static func auditContext(
        editorFocus: KeyboardShortcutPolicy.EditorFocus
    ) -> KeyboardShortcutPolicy.Context {
        KeyboardShortcutPolicy.Context(
            lifecycle: .different,
            hasSelection: true,
            isReadOnly: false,
            editorFocus: editorFocus,
            enabledCommands: Set(Command.allCases.map(\.identifier))
        )
    }

    private static func conflictKind(
        binding: Binding,
        focus: KeyboardShortcutPolicy.EditorFocus,
        route resolution: KeyboardShortcutPolicy.Resolution
    ) -> Conflict.Kind? {
        if focus == .none {
            guard resolution.applicationCommand == binding.command.identifier else {
                return .unreachableWithoutTextFocus(resolution.route)
            }
            return nil
        }
        switch (binding.delivery, resolution.route) {
        case (.menuKeyEquivalent, .nativeTextEditing(let native)):
            return .menuKeyEquivalentStealsNativeText(native)
        case (.focusRoutedAlternate, .nativeTextEditing):
            return nil
        case (.focusRoutedAlternate, _):
            return .focusRoutingWithoutNativeReservation
        case (.menuKeyEquivalent, _):
            return nil
        }
    }

    // MARK: - Routing

    /// Why a key event was left for the rest of the event pipeline.
    public enum PassThroughReason: Equatable, Hashable, Sendable {
        /// The chord is not a focus-routed directional copy alternate.
        case notCopyAlternate
        /// A focused selectable or editable text view owns the chord for native navigation.
        case nativeTextEditing(KeyboardShortcutPolicy.NativeTextEditingCommand)
        /// The command is bound but unavailable in the current comparison state.
        case unavailable(Command)
        /// The shared policy blocked the chord, for example on an unexpected collision.
        case blocked
        /// The shared policy could not resolve the chord within its limits.
        case policyFailure(KeyboardShortcutPolicyError)
    }

    public enum Decision: Equatable, Hashable, Sendable {
        /// Perform the command and consume the key event.
        case perform(Command)
        /// Leave the event untouched for the responder chain and menus.
        case passThrough(PassThroughReason)

        public var command: Command? {
            guard case .perform(let command) = self else { return nil }
            return command
        }
    }

    /// Routes one focus-routed alternate chord. `context.enabledCommands` is replaced by the copy
    /// commands in `enabledCommands`, so this router can never dispatch a non-copy command that
    /// shares a chord in the policy, and native text reservations always win under text focus.
    public static func route(
        _ chord: Chord,
        in context: KeyboardShortcutPolicy.Context,
        enabledCommands: Set<Command>,
        policy: KeyboardShortcutPolicy
    ) -> Decision {
        guard let binding = focusRoutedBinding(matching: chord) else {
            return .passThrough(.notCopyAlternate)
        }
        let gatedContext = KeyboardShortcutPolicy.Context(
            lifecycle: context.lifecycle,
            isDirty: context.isDirty,
            hasSelection: context.hasSelection,
            isReadOnly: context.isReadOnly,
            editorFocus: context.editorFocus,
            enabledCommands: Set(enabledCommands.map(\.identifier))
        )
        let resolution: KeyboardShortcutPolicy.Resolution
        do {
            // Key routing runs synchronously on the event path; task cancellation is not
            // meaningful there and the policy's work limits still bound the call.
            resolution = try policy.resolve(chord, in: gatedContext, cancellationCheck: {})
        } catch {
            return .passThrough(.policyFailure(error))
        }
        switch resolution.route {
        case .nativeTextEditing(let nativeCommand):
            return .passThrough(.nativeTextEditing(nativeCommand))
        case .applicationCommand(let identifier):
            guard resolution.isEnabled, let command = Command(identifier),
                command == binding.command
            else {
                return .passThrough(.blocked)
            }
            return .perform(command)
        case .blocked, .unhandled:
            // A disabled non-copy command sharing the chord is a block, not copy unavailability.
            guard resolution.matchedCommands.contains(binding.command.identifier) else {
                return .passThrough(.blocked)
            }
            switch resolution.availabilityReason {
            case .disabled(.commandUnavailable), .disabled(.commandConditions):
                return .passThrough(.unavailable(binding.command))
            default:
                return .passThrough(.blocked)
            }
        }
    }

    private static func chord(
        _ key: KeyboardShortcutPolicy.SpecialKey,
        _ modifiers: Set<KeyboardShortcutPolicy.Modifier>
    ) -> Chord {
        try! Chord(.special(key), modifiers: modifiers)
    }

    private static func binding(
        _ command: Command,
        _ key: KeyboardShortcutPolicy.SpecialKey,
        _ modifiers: Set<KeyboardShortcutPolicy.Modifier>,
        _ delivery: Delivery,
        _ winMergeAccelerator: String
    ) -> Binding {
        Binding(
            command: command,
            chord: chord(key, modifiers),
            delivery: delivery,
            winMergeAccelerator: winMergeAccelerator
        )
    }
}
