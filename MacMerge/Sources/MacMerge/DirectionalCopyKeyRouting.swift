import AppKit
import MacMergeCore
import SwiftUI

extension DirectionalCopyShortcuts.Command {
    /// The app command that performs this shortcut through the same entry point as the menu.
    var comparisonCopyCommand: ComparisonCopyCommand {
        switch self {
        case .copyToRight: .selectedToRight
        case .copyToLeft: .selectedToLeft
        case .copyToRightAndAdvance: .selectedToRightAndAdvance
        case .copyToLeftAndAdvance: .selectedToLeftAndAdvance
        }
    }
}

extension ComparisonModel {
    /// Live availability matching the Merge menu's `.disabled` gates, including per-side
    /// read-only protection enforced by `MergeCommandPolicy`.
    var enabledDirectionalCopyCommands: Set<DirectionalCopyShortcuts.Command> {
        Set(
            DirectionalCopyShortcuts.Command.allCases.filter {
                $0.comparisonCopyCommand.isEnabled(on: self)
            }
        )
    }
}

extension DirectionalCopyShortcuts.Binding {
    /// SwiftUI menu shortcut for a `.menuKeyEquivalent` arrow binding (copy-and-advance), derived
    /// from the shared catalog. `nil` for focus-routed alternates, which must never become menu
    /// key equivalents because AppKit would offer them before the focused text view.
    var menuKeyboardShortcut: KeyboardShortcut? {
        guard delivery == .menuKeyEquivalent else { return nil }
        let key: KeyEquivalent
        switch chord.key {
        case .special(.leftArrow): key = .leftArrow
        case .special(.rightArrow): key = .rightArrow
        case .special(.upArrow): key = .upArrow
        case .special(.downArrow): key = .downArrow
        default: return nil
        }
        var eventModifiers: EventModifiers = []
        for modifier in chord.modifiers {
            switch modifier {
            case .command: eventModifiers.insert(.command)
            case .control: eventModifiers.insert(.control)
            case .option: eventModifiers.insert(.option)
            case .shift: eventModifiers.insert(.shift)
            case .function: continue
            }
        }
        return KeyboardShortcut(key, modifiers: eventModifiers)
    }
}

extension View {
    /// Binds the catalog's menu key equivalent for copy-and-advance, or the focus-routed
    /// Option-arrow tooltip for Copy to Right/Left, which have no menu key equivalent.
    @ViewBuilder
    func directionalCopyShortcut(_ command: DirectionalCopyShortcuts.Command) -> some View {
        if let shortcut = DirectionalCopyShortcuts.menuBinding(for: command)?.menuKeyboardShortcut {
            keyboardShortcut(shortcut)
        } else if let hint = DirectionalCopyShortcuts.alternateHint(for: command) {
            help(hint)
        } else {
            self
        }
    }
}

/// Dispatches WinMerge's Alt-Left/Right copy accelerators as Option chords without stealing
/// word navigation from selectable or editable text. Copy-and-advance (`Command-Option-arrow`)
/// stays a Merge menu key equivalent because the text system does not reserve it.
@MainActor
final class DirectionalCopyKeyRouter {
    private var monitor: Any?

    func install(for window: NSWindow, model: ComparisonModel) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak window, weak model] event in
            guard let window, let model, Self.shouldHandle(event, in: window) else { return event }
            return Self.handle(event, in: window, model: model) ? nil : event
        }
    }

    /// Whether a local key monitor installed for `window` may act on `event`: only events
    /// addressed to that window while it is key and has no sheet attached.
    static func shouldHandle(_ event: NSEvent, in window: NSWindow) -> Bool {
        event.window === window && window.isKeyWindow && window.attachedSheet == nil
    }

    var isInstalled: Bool { monitor != nil }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Returns `true` when the event performed a copy command and must be consumed.
    static func handle(_ event: NSEvent, in window: NSWindow, model: ComparisonModel) -> Bool {
        guard let chord = chord(for: event),
            DirectionalCopyShortcuts.focusRoutedBinding(matching: chord) != nil
        else { return false }
        let decision = decision(
            for: chord,
            editorFocus: DifferenceNavigationKeyRouter.editorFocus(of: window),
            model: model
        )
        guard let command = decision.command else { return false }
        command.comparisonCopyCommand.perform(on: model)
        return true
    }

    /// Routes `chord` against the live model. `hasSelection` uses the same current-difference
    /// source as the Merge menu (selected difference, or else the current row when it is a
    /// difference), so the chord works whenever the menu item is enabled.
    static func decision(
        for chord: KeyboardShortcutPolicy.Chord,
        editorFocus: KeyboardShortcutPolicy.EditorFocus,
        model: ComparisonModel,
        policy sharedPolicy: Result<KeyboardShortcutPolicy, KeyboardShortcutPolicyError> =
            DifferenceNavigationShortcuts.sharedPolicy
    ) -> DirectionalCopyShortcuts.Decision {
        let policy: KeyboardShortcutPolicy
        switch sharedPolicy {
        case .success(let shared): policy = shared
        case .failure(let error): return .passThrough(.policyFailure(error))
        }
        let context = KeyboardShortcutPolicy.Context(
            lifecycle: model.differenceNavigationLifecycle,
            hasSelection: model.hasCurrentDifference,
            editorFocus: editorFocus
        )
        return DirectionalCopyShortcuts.route(
            chord,
            in: context,
            enabledCommands: model.enabledDirectionalCopyCommands,
            policy: policy
        )
    }

    /// Converts the physical Left/Right arrow keys. Other keys return `nil`.
    static func chord(for event: NSEvent) -> KeyboardShortcutPolicy.Chord? {
        let key: KeyboardShortcutPolicy.Key
        switch event.keyCode {
        case 123: key = .special(.leftArrow)
        case 124: key = .special(.rightArrow)
        default: return nil
        }
        // Arrow keys always carry the Function flag; it is not a user modifier here.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<KeyboardShortcutPolicy.Modifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return try? KeyboardShortcutPolicy.Chord(key, modifiers: modifiers)
    }
}
