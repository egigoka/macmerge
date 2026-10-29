import AppKit
import MacMergeCore
import SwiftUI

/// Marks a one-line comparison-row text view. Paragraph moves inside it are near no-ops, so the
/// WinMerge Alt-arrow/Home/End navigation chords take precedence there (see
/// `DifferenceNavigationShortcuts.singleLineRowYieldingReservations`).
protocol SingleLineDiffRowTextView: NSTextView {}

extension DifferenceNavigationShortcuts.Binding {
    /// SwiftUI menu shortcut for a `.menuKeyEquivalent` binding (`F8`/`F7`), derived from the
    /// shared catalog so the Merge menu never spells these keys itself. `nil` for focus-routed
    /// alternates, which must never become menu key equivalents.
    var menuKeyboardShortcut: KeyboardShortcut? {
        guard delivery == .menuKeyEquivalent,
            case .function(let number) = chord.key, (1...35).contains(number),
            let scalar = UnicodeScalar(0xF703 + number)
        else { return nil }
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
        return KeyboardShortcut(KeyEquivalent(Character(scalar)), modifiers: eventModifiers)
    }
}

extension View {
    /// Binds the catalog's menu key equivalent (if any) and the Option-chord tooltip for a
    /// difference-navigation command.
    @ViewBuilder
    func differenceNavigationShortcut(_ command: DifferenceNavigationShortcuts.Command) -> some View {
        let hint = DifferenceNavigationShortcuts.alternateHint(for: command) ?? ""
        if let shortcut = DifferenceNavigationShortcuts.menuBinding(for: command)?
            .menuKeyboardShortcut
        {
            keyboardShortcut(shortcut).help(hint)
        } else {
            help(hint)
        }
    }
}

extension ComparisonModel {
    /// Live availability matching the Merge menu's `.disabled` gates.
    var enabledDifferenceNavigationCommands: Set<DifferenceNavigationShortcuts.Command> {
        var result: Set<DifferenceNavigationShortcuts.Command> = []
        if canSelectNextDifference { result.insert(.next) }
        if canSelectPreviousDifference { result.insert(.previous) }
        if canNavigateDifferences {
            result.insert(.first)
            result.insert(.last)
        }
        if canSelectCurrentDifference { result.insert(.current) }
        return result
    }

    /// Coarse lifecycle for the shared policy. The exact per-command gate comes from
    /// `enabledDifferenceNavigationCommands`; this only must not block a command the menu
    /// enables. Current Difference stays enabled on a stale comparison with a selected
    /// difference, so that state also reports `.different`.
    var differenceNavigationLifecycle: KeyboardShortcutPolicy.LifecycleState {
        if isWorking { return .loading }
        if hasDifferences || canSelectCurrentDifference { return .different }
        if comparisonFailed { return .failed }
        return isComparisonCurrent ? .equal : .empty
    }

    /// Performs one navigation command through the same model entry points as the Merge menu.
    func performDifferenceNavigation(_ command: DifferenceNavigationShortcuts.Command) {
        switch command {
        case .next: selectNextDifference()
        case .previous: selectPreviousDifference()
        case .first: selectFirstDifference()
        case .current: selectCurrentDifference()
        case .last: selectLastDifference()
        }
    }
}

/// Dispatches WinMerge's Alt-arrow/Home/Enter/End navigation accelerators as Option chords
/// without stealing native text navigation. Menu key equivalents (`F8`/`F7`) stay with the menu.
@MainActor
final class DifferenceNavigationKeyRouter {
    private var monitor: Any?

    func install(for window: NSWindow, model: ComparisonModel) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak window, weak model] event in
            guard let window, let model, Self.accepts(event, in: window) else { return event }
            return Self.handle(event, in: window, model: model) ? nil : event
        }
    }

    var isInstalled: Bool { monitor != nil }

    /// Monitor gate: only key events for this key window with no sheet attached are routed.
    static func accepts(_ event: NSEvent, in window: NSWindow) -> Bool {
        event.window === window && window.isKeyWindow && window.attachedSheet == nil
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Returns `true` when the event performed a navigation command and must be consumed.
    static func handle(_ event: NSEvent, in window: NSWindow, model: ComparisonModel) -> Bool {
        guard let chord = chord(for: event),
            DifferenceNavigationShortcuts.focusRoutedBinding(matching: chord) != nil,
            case .success(let policy) = DifferenceNavigationShortcuts.sharedPolicy
        else { return false }
        let context = KeyboardShortcutPolicy.Context(
            lifecycle: model.differenceNavigationLifecycle,
            editorFocus: editorFocus(of: window)
        )
        let decision = DifferenceNavigationShortcuts.route(
            chord,
            in: context,
            enabledCommands: model.enabledDifferenceNavigationCommands,
            policy: policy,
            focusIsSingleLineDiffRow: window.firstResponder is SingleLineDiffRowTextView
        )
        guard let command = decision.command else { return false }
        model.performDifferenceNavigation(command)
        return true
    }

    static func editorFocus(of window: NSWindow) -> KeyboardShortcutPolicy.EditorFocus {
        guard let textView = window.firstResponder as? NSTextView else { return .none }
        return textView.isEditable ? .editable : .readOnly
    }

    /// Converts the physical keys used by navigation accelerators. Other keys return `nil`.
    static func chord(for event: NSEvent) -> KeyboardShortcutPolicy.Chord? {
        let key: KeyboardShortcutPolicy.Key
        switch event.keyCode {
        case 125: key = .special(.downArrow)
        case 126: key = .special(.upArrow)
        case 115: key = .special(.home)
        case 119: key = .special(.end)
        // Return and keypad Enter both produce WinMerge's VK_RETURN.
        case 36, 76: key = .special(.return)
        // F7/F8 are menu key equivalents handled by the Merge menu, not this router.
        default: return nil
        }
        // Arrow/Home/End always carry the Function flag; it is not a user modifier here.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<KeyboardShortcutPolicy.Modifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return try? KeyboardShortcutPolicy.Chord(key, modifiers: modifiers)
    }
}
