/// Platform-safe equivalents and focus-aware routing for First/Current/Last Difference.
///
/// WinMerge `Src/Merge.rc` (`IDR_MAINFRAME` accelerators) binds:
///
/// | Command         | WinMerge ID  | Accelerator |
/// |-----------------|--------------|-------------|
/// | First Difference   | `ID_FIRSTDIFF` | `Alt+Home`  |
/// | Current Difference | `ID_CURDIFF`   | `Alt+Enter` |
/// | Last Difference    | `ID_LASTDIFF`  | `Alt+End`   |
///
/// On macOS, Alt maps to Option. `DifferenceNavigationShortcuts` already routes those three
/// Option chords as focus-routed alternates, but the shared `KeyboardShortcutPolicy` reserves
/// every one of them for native text editing whenever a text view owns input
/// (`moveBackwardToParagraphStart`, `insertNewlineIgnoringFieldEditor` in editable text,
/// `moveForwardToParagraphEnd`), yielding to navigation only inside single-line diff rows.
/// So from a find field, an editable pane, or any multi-line text view there is no keyboard
/// path to First/Current/Last.
///
/// This router closes that gap with one platform-safe equivalent per command that has no
/// native text-editing reservation under any focus, paralleling how `DirectionalCopyShortcuts`
/// keeps `Command-Option-Left/Right` as menu key equivalents while `Option-Left/Right` stays
/// focus-routed:
///
/// | Command         | Equivalent          | WinMerge accelerator |
/// |-----------------|---------------------|----------------------|
/// | First Difference   | `Command-Option-Home`   | `VK_HOME, ALT`   |
/// | Current Difference | `Command-Option-Return` | `VK_RETURN, ALT` |
/// | Last Difference    | `Command-Option-End`    | `VK_END, ALT`    |
///
/// The WinMerge `Option` chords are not duplicated here: `winMergeBindings(for:)` derives them
/// from `DifferenceNavigationShortcuts`, and `route` delegates those chords to
/// `DifferenceNavigationShortcuts.route` (including its single-line diff-row yield) so the two
/// routers cannot drift. Only the three equivalents are new, and they carry
/// `menuKeyEquivalent` delivery because no focus owns them natively.
///
/// State handling mirrors the sibling router: lifecycle, dirty, selection, and read-only
/// facts flow into `policy.resolve` through the caller's `KeyboardShortcutPolicy.Context`
/// (navigation itself requires the `.different` lifecycle and constrains nothing else), and
/// `enabledCommands` is re-gated to the First/Current/Last subset so this router can never
/// dispatch a non-navigation command that shares a chord in the policy.
///
/// UI-independent and synchronous. Platform code converts the physical key event to a
/// `Chord` and dispatches the returned command; this type never observes a live key press.
public enum FirstLastDifferenceShortcuts {
    public typealias Chord = KeyboardShortcutPolicy.Chord
    public typealias Delivery = DifferenceNavigationShortcuts.Delivery
    public typealias Command = DifferenceNavigationShortcuts.Command
    public typealias Decision = DifferenceNavigationShortcuts.Decision
    public typealias PassThroughReason = DifferenceNavigationShortcuts.PassThroughReason

    /// The only commands this router dispatches, in canonical command order.
    public static let commands: [Command] = [.first, .current, .last]

    /// One platform-safe equivalent chord for a First/Current/Last command.
    public struct EquivalentBinding: Equatable, Hashable, Sendable {
        public let command: Command
        public let chord: Chord
        public let delivery: Delivery
        /// Accelerator spelling of the originating WinMerge binding, as written in
        /// `Src/Merge.rc`.
        public let winMergeAccelerator: String

        public init(command: Command, chord: Chord, delivery: Delivery, winMergeAccelerator: String) {
            self.command = command
            self.chord = chord
            self.delivery = delivery
            self.winMergeAccelerator = winMergeAccelerator
        }
    }

    /// The three platform-safe equivalents in canonical command order.
    public static let equivalentBindings: [EquivalentBinding] = [
        EquivalentBinding(
            command: .first,
            chord: chord(.home, [.command, .option]),
            delivery: .menuKeyEquivalent,
            winMergeAccelerator: "VK_HOME, ALT"
        ),
        EquivalentBinding(
            command: .current,
            chord: chord(.return, [.command, .option]),
            delivery: .menuKeyEquivalent,
            winMergeAccelerator: "VK_RETURN, ALT"
        ),
        EquivalentBinding(
            command: .last,
            chord: chord(.end, [.command, .option]),
            delivery: .menuKeyEquivalent,
            winMergeAccelerator: "VK_END, ALT"
        )
    ]

    /// WinMerge `Option` bindings for `command`, derived from `DifferenceNavigationShortcuts`
    /// so this router cannot drift from the audited catalog.
    public static func winMergeBindings(for command: Command) -> [DifferenceNavigationShortcuts.Binding] {
        DifferenceNavigationShortcuts.bindings(for: command)
    }

    public static func equivalentBinding(for command: Command) -> EquivalentBinding? {
        equivalentBindings.first { $0.command == command }
    }

    public static func equivalentBinding(matching chord: Chord) -> EquivalentBinding? {
        equivalentBindings.first { $0.chord == chord }
    }

    /// The menu key equivalent for `command`: the platform-safe equivalent. Never `nil` for
    /// the routed commands, unlike the WinMerge chords, which are focus-routed alternates.
    public static func menuBinding(for command: Command) -> EquivalentBinding? {
        equivalentBinding(for: command)
    }

    /// Short shortcut note for tooltips and menu help, naming the equivalent that works from
    /// any focus.
    public static func shortcutHint(for command: Command) -> String {
        guard let binding = equivalentBinding(for: command) else {
            return DifferenceNavigationShortcuts.alternateHint(for: command) ?? ""
        }
        return DifferenceNavigationShortcuts.displayName(of: binding.chord)
    }

    // MARK: - Conflict audit

    /// One way an equivalent's delivery disagrees with the policy's native text reservations.
    public struct Conflict: Equatable, Hashable, Sendable {
        public enum Kind: Equatable, Hashable, Sendable {
            /// A menu key equivalent resolves to native text editing under text focus, so the
            /// menu would fire before the text view and steal the chord.
            case menuKeyEquivalentStealsNativeText(KeyboardShortcutPolicy.NativeTextEditingCommand)
            /// The equivalent does not dispatch its command even when no text view owns input.
            case unreachableWithoutTextFocus(KeyboardShortcutPolicy.Route)
            /// The policy could not resolve the chord within its limits.
            case policyFailure(KeyboardShortcutPolicyError)
        }

        public let binding: EquivalentBinding
        public let editorFocus: KeyboardShortcutPolicy.EditorFocus
        public let kind: Kind

        public init(
            binding: EquivalentBinding,
            editorFocus: KeyboardShortcutPolicy.EditorFocus,
            kind: Kind
        ) {
            self.binding = binding
            self.editorFocus = editorFocus
            self.kind = kind
        }
    }

    /// Verifies every equivalent against `policy` in a state where all three commands are
    /// available. Returns findings in binding order, then focus order (`none`, `readOnly`,
    /// `editable`). An empty result means each equivalent dispatches from every focus and
    /// never steals native text editing.
    public static func auditEquivalents(policy: KeyboardShortcutPolicy) -> [Conflict] {
        var conflicts: [Conflict] = []
        for binding in equivalentBindings {
            for focus in KeyboardShortcutPolicy.EditorFocus.allCases {
                let context = KeyboardShortcutPolicy.Context(
                    lifecycle: .different,
                    hasSelection: true,
                    isReadOnly: false,
                    editorFocus: focus,
                    enabledCommands: Set(commands.map(\.identifier))
                )
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

    private static func conflictKind(
        binding: EquivalentBinding,
        focus: KeyboardShortcutPolicy.EditorFocus,
        route resolution: KeyboardShortcutPolicy.Resolution
    ) -> Conflict.Kind? {
        switch (binding.delivery, resolution.route) {
        case (.menuKeyEquivalent, .nativeTextEditing(let native)) where focus != .none:
            return .menuKeyEquivalentStealsNativeText(native)
        case (.menuKeyEquivalent, _):
            guard resolution.applicationCommand == binding.command.identifier else {
                return .unreachableWithoutTextFocus(resolution.route)
            }
            return nil
        case (.focusRoutedAlternate, _):
            return nil
        }
    }

    // MARK: - Routing

    /// Routes one First/Current/Last chord: a WinMerge `Option` alternate or a platform-safe
    /// equivalent. WinMerge chords delegate to `DifferenceNavigationShortcuts.route` (which
    /// owns the single-line diff-row yield); equivalents resolve directly against `policy`
    /// because no focus owns them natively. `context.enabledCommands` is re-gated to the
    /// First/Current/Last subset, so this router only narrows the caller's command gate.
    ///
    /// Pass `focusIsSingleLineDiffRow: true` only when the focused text view is a one-line
    /// comparison row; it is forwarded to the WinMerge-chord path and ignored by equivalents.
    public static func route(
        _ chord: Chord,
        in context: KeyboardShortcutPolicy.Context,
        enabledCommands: Set<Command>,
        policy: KeyboardShortcutPolicy,
        focusIsSingleLineDiffRow: Bool = false
    ) -> Decision {
        if let winMergeBinding = DifferenceNavigationShortcuts.focusRoutedBinding(matching: chord),
            commands.contains(winMergeBinding.command)
        {
            return DifferenceNavigationShortcuts.route(
                chord,
                in: context,
                enabledCommands: enabledCommands.intersection(Set(commands)),
                policy: policy,
                focusIsSingleLineDiffRow: focusIsSingleLineDiffRow
            )
        }
        guard let binding = equivalentBinding(matching: chord) else {
            return .passThrough(.notNavigationAlternate)
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
                command == binding.command, commands.contains(command)
            else {
                return .passThrough(.blocked)
            }
            return .perform(command)
        case .blocked, .unhandled:
            // A disabled non-navigation command sharing the chord is a block, not
            // First/Current/Last unavailability.
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
}
