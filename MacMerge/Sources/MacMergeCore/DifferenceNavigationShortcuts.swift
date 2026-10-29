/// Catalog and focus-aware routing for WinMerge difference-navigation accelerators.
///
/// WinMerge `Src/Merge.rc` (`IDR_MAINFRAME` accelerators) binds:
///
/// | Command              | WinMerge ID     | Accelerators        |
/// |----------------------|-----------------|---------------------|
/// | Next Difference      | `ID_NEXTDIFF`   | `F8`, `Alt+Down`    |
/// | Previous Difference  | `ID_PREVDIFF`   | `F7`, `Alt+Up`      |
/// | First Difference     | `ID_FIRSTDIFF`  | `Alt+Home`          |
/// | Current Difference   | `ID_CURDIFF`    | `Alt+Enter`         |
/// | Last Difference      | `ID_LASTDIFF`   | `Alt+End`           |
///
/// On macOS, Alt maps to Option. Option-Up/Down/Home/End are standard paragraph/document
/// navigation in text views and Option-Return inserts a raw newline in editable text, so those
/// chords cannot be plain menu key equivalents: a menu key equivalent fires before the focused
/// text view sees the key and would steal native editing. `F8`/`F7` have no native text meaning
/// and stay menu key equivalents. The Option chords are focus-routed alternates: platform code
/// offers each key event to `route(_:in:enabledCommands:policy:)`, which defers to
/// `KeyboardShortcutPolicy` so a native text-editing reservation wins whenever a text view owns
/// input, and performs the navigation command only when no reservation applies.
///
/// Single-line diff rows: every comparison row is a one-line text view, so clicking a row makes
/// a text view first responder. Paragraph moves (Option-Up/Down) and paragraph start/end
/// (Option-Home/End) inside one line are near no-ops, so when the caller reports that focus is a
/// single-line diff row, those four reservations yield to navigation (WinMerge fires Alt+arrow
/// inside the merge editor too). Every other reservation still wins there, including Option-Return
/// in an editable row, and multi-line or other text views (for example find fields) keep the
/// paragraph reservations.
public enum DifferenceNavigationShortcuts {
    public typealias Chord = KeyboardShortcutPolicy.Chord

    public enum Command: String, CaseIterable, Equatable, Hashable, Sendable {
        case next
        case previous
        case first
        case current
        case last

        public var identifier: ComparisonCommandState.Identifier {
            switch self {
            case .next: .nextDifference
            case .previous: .previousDifference
            case .first: .firstDifference
            case .current: .currentDifference
            case .last: .lastDifference
            }
        }

        public init?(_ identifier: ComparisonCommandState.Identifier) {
            switch identifier {
            case .nextDifference: self = .next
            case .previousDifference: self = .previous
            case .firstDifference: self = .first
            case .currentDifference: self = .current
            case .lastDifference: self = .last
            default: return nil
            }
        }

        /// WinMerge `Src/resource.h` command identifier.
        public var winMergeCommandID: String {
            switch self {
            case .next: "ID_NEXTDIFF"
            case .previous: "ID_PREVDIFF"
            case .first: "ID_FIRSTDIFF"
            case .current: "ID_CURDIFF"
            case .last: "ID_LASTDIFF"
            }
        }

        public var menuTitle: String {
            switch self {
            case .next: "Next Difference"
            case .previous: "Previous Difference"
            case .first: "First Difference"
            case .current: "Current Difference"
            case .last: "Last Difference"
            }
        }
    }

    public enum Delivery: String, CaseIterable, Equatable, Hashable, Sendable {
        /// Bound as the menu item's key equivalent; no native text-editing meaning.
        case menuKeyEquivalent
        /// Dispatched by a focus-aware key monitor so native text editing keeps the chord
        /// whenever a text view owns input.
        case focusRoutedAlternate
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

    /// Every navigation binding in canonical command order. Chords match
    /// `KeyboardShortcutPolicy.unfinishedAuditCommandShortcuts` exactly.
    public static let bindings: [Binding] = [
        binding(.next, .function(8), [], .menuKeyEquivalent, "VK_F8"),
        binding(.next, .special(.downArrow), [.option], .focusRoutedAlternate, "VK_DOWN, ALT"),
        binding(.previous, .function(7), [], .menuKeyEquivalent, "VK_F7"),
        binding(.previous, .special(.upArrow), [.option], .focusRoutedAlternate, "VK_UP, ALT"),
        binding(.first, .special(.home), [.option], .focusRoutedAlternate, "VK_HOME, ALT"),
        binding(.current, .special(.return), [.option], .focusRoutedAlternate, "VK_RETURN, ALT"),
        binding(.last, .special(.end), [.option], .focusRoutedAlternate, "VK_END, ALT")
    ]

    public static func bindings(for command: Command) -> [Binding] {
        bindings.filter { $0.command == command }
    }

    /// The single menu key equivalent for `command`, or `nil` when the command is only reachable
    /// through focus-routed alternates (First/Current/Last).
    public static func menuBinding(for command: Command) -> Binding? {
        bindings.first { $0.command == command && $0.delivery == .menuKeyEquivalent }
    }

    public static var focusRoutedBindings: [Binding] {
        bindings.filter { $0.delivery == .focusRoutedAlternate }
    }

    public static func focusRoutedBinding(matching chord: Chord) -> Binding? {
        bindings.first { $0.delivery == .focusRoutedAlternate && $0.chord == chord }
    }

    /// Why a key event was left for the rest of the event pipeline.
    public enum PassThroughReason: Equatable, Hashable, Sendable {
        /// The chord is not a focus-routed navigation alternate.
        case notNavigationAlternate
        /// A focused text view owns the chord for native editing or navigation.
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

    /// Routes one focus-routed alternate chord. `context.enabledCommands` is replaced by the
    /// navigation commands in `enabledCommands`, so this router can never dispatch any
    /// non-navigation command that shares a chord in the policy (for example Option-Shift-Down
    /// for Next Conflict).
    ///
    /// Pass `focusIsSingleLineDiffRow: true` only when the focused text view is a one-line
    /// comparison row; then the reservations in `singleLineRowYieldingReservations` yield to
    /// navigation. `context.editorFocus` must still describe that text view.
    public static func route(
        _ chord: Chord,
        in context: KeyboardShortcutPolicy.Context,
        enabledCommands: Set<Command>,
        policy: KeyboardShortcutPolicy,
        focusIsSingleLineDiffRow: Bool = false
    ) -> Decision {
        guard let binding = focusRoutedBinding(matching: chord) else {
            return .passThrough(.notNavigationAlternate)
        }
        let gatedIdentifiers = Set(enabledCommands.map(\.identifier))
        var resolution: KeyboardShortcutPolicy.Resolution
        do {
            // Key routing runs synchronously on the event path; task cancellation is not
            // meaningful there and the policy's work limits still bound the call.
            resolution = try policy.resolve(
                chord,
                in: gated(context, focus: context.editorFocus, enabled: gatedIdentifiers),
                cancellationCheck: {}
            )
            if focusIsSingleLineDiffRow,
                case .nativeTextEditing(let nativeCommand) = resolution.route,
                singleLineRowYieldingReservations.contains(nativeCommand)
            {
                resolution = try policy.resolve(
                    chord,
                    in: gated(context, focus: .none, enabled: gatedIdentifiers),
                    cancellationCheck: {}
                )
            }
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
            if case .disabled(.commandUnavailable) = resolution.availabilityReason {
                return .passThrough(.unavailable(binding.command))
            }
            if case .disabled(.commandConditions) = resolution.availabilityReason {
                return .passThrough(.unavailable(binding.command))
            }
            return .passThrough(.blocked)
        }
    }

    /// Native reservations that are near no-ops inside a one-line diff row and therefore yield to
    /// the WinMerge Alt-arrow/Home/End navigation chords there.
    public static let singleLineRowYieldingReservations: Set<KeyboardShortcutPolicy.NativeTextEditingCommand> = [
        .moveParagraphUp,
        .moveParagraphDown,
        .moveBackwardToParagraphStart,
        .moveForwardToParagraphEnd
    ]

    /// Tooltip text naming the focus-routed Option chord for `command`, so menu users can find
    /// the WinMerge Alt-key equivalents that cannot be menu key equivalents.
    public static func alternateHint(for command: Command) -> String? {
        let alternates = bindings(for: command).filter { $0.delivery == .focusRoutedAlternate }
        guard !alternates.isEmpty else { return nil }
        let names = alternates.map { "\(displayName(of: $0.chord)) (WinMerge \($0.winMergeAccelerator))" }
        return "Also \(names.joined(separator: ", "))."
    }

    /// Human-readable macOS spelling of a navigation chord, for example `Option-Down Arrow`.
    public static func displayName(of chord: Chord) -> String {
        let order: [(KeyboardShortcutPolicy.Modifier, String)] = [
            (.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")
        ]
        let modifiers = order.filter { chord.modifiers.contains($0.0) }.map(\.1)
        let key: String
        switch chord.key {
        case .character(let character): key = String(character).uppercased()
        case .function(let number): key = "F\(number)"
        case .special(let special): key = displayName(of: special)
        }
        return (modifiers + [key]).joined(separator: "-")
    }

    /// macOS keyboard spelling of a special key. Exhaustive so new keys need a real name.
    private static func displayName(of key: KeyboardShortcutPolicy.SpecialKey) -> String {
        switch key {
        case .backspace: "Delete"
        case .delete: "Forward Delete"
        case .downArrow: "Down Arrow"
        case .end: "End"
        case .escape: "Escape"
        case .home: "Home"
        case .leftArrow: "Left Arrow"
        case .pageDown: "Page Down"
        case .pageUp: "Page Up"
        case .return: "Return"
        case .rightArrow: "Right Arrow"
        case .space: "Space"
        case .tab: "Tab"
        case .upArrow: "Up Arrow"
        }
    }

    private static func gated(
        _ context: KeyboardShortcutPolicy.Context,
        focus: KeyboardShortcutPolicy.EditorFocus,
        enabled: Set<ComparisonCommandState.Identifier>
    ) -> KeyboardShortcutPolicy.Context {
        KeyboardShortcutPolicy.Context(
            lifecycle: context.lifecycle,
            isDirty: context.isDirty,
            hasSelection: context.hasSelection,
            isReadOnly: context.isReadOnly,
            editorFocus: focus,
            enabledCommands: enabled
        )
    }

    /// Shared policy instance for platform routing, built once from the audited shortcut set.
    public static let sharedPolicy: Result<KeyboardShortcutPolicy, KeyboardShortcutPolicyError> =
        Result { () throws(KeyboardShortcutPolicyError) -> KeyboardShortcutPolicy in
            try KeyboardShortcutPolicy.makeUnfinishedAudit(cancellationCheck: {})
        }

    private static func binding(
        _ command: Command,
        _ key: KeyboardShortcutPolicy.Key,
        _ modifiers: Set<KeyboardShortcutPolicy.Modifier>,
        _ delivery: Delivery,
        _ winMergeAccelerator: String
    ) -> Binding {
        Binding(
            command: command,
            chord: try! Chord(key, modifiers: modifiers),
            delivery: delivery,
            winMergeAccelerator: winMergeAccelerator
        )
    }
}
