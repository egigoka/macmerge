import AppKit
import MacMergeCore
import SwiftUI

extension FileLifecycleShortcuts.Binding {
    /// SwiftUI shortcut derived from the shared catalog; the app never spells these keys itself.
    var keyboardShortcut: KeyboardShortcut {
        var eventModifiers: EventModifiers = []
        for modifier in modifiers {
            switch modifier {
            case .command: eventModifiers.insert(.command)
            case .control: eventModifiers.insert(.control)
            case .option: eventModifiers.insert(.option)
            case .shift: eventModifiers.insert(.shift)
            case .function:
                // SwiftUI cannot express Function; `catalogFindings` rejects it in the catalog.
                continue
            }
        }
        return KeyboardShortcut(KeyEquivalent(key), modifiers: eventModifiers)
    }
}

extension View {
    /// Binds the catalog shortcut for a file/application lifecycle command.
    func fileLifecycleShortcut(_ command: FileLifecycleShortcuts.Command) -> some View {
        keyboardShortcut(FileLifecycleShortcuts.binding(for: command).keyboardShortcut)
    }
}

/// File > Close (`Command-W`). Replacing SwiftUI's `.saveItem` group removes the standard Close
/// item, so MacMerge restores it from the catalog. It sends the catalog selector down the
/// responder chain so the key window (comparison or Settings) closes through its normal
/// `windowShouldClose` path, including the unsaved-changes veto.
/// Like AppKit's own Close item, it is disabled when there is no closable key window.
struct FileLifecycleCloseCommand: View {
    @ObservedObject private var keyWindow = KeyWindowClosability.shared

    var body: some View {
        let binding = FileLifecycleShortcuts.binding(for: .close)
        Button(binding.menuTitle) {
            FileLifecycleResponderDispatch.send(binding)
        }
        .fileLifecycleShortcut(.close)
        .disabled(!keyWindow.canClose)
    }
}

/// Tracks whether the key window can be closed, so File > Close greys out for sheets,
/// non-closable panels, or no key window, matching AppKit's `performClose:` validation.
@MainActor
final class KeyWindowClosability: ObservableObject {
    static let shared = KeyWindowClosability()

    @Published private(set) var canClose: Bool
    private let keyWindow: @MainActor () -> NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(
        keyWindow: @escaping @MainActor () -> NSWindow? = { NSApplication.shared.keyWindow },
        notificationCenter: NotificationCenter = .default
    ) {
        self.keyWindow = keyWindow
        canClose = Self.canClose(keyWindow())
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification
        ]
        for name in names {
            observers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.refresh(self.keyWindow())
                    }
                })
        }
    }

    func refresh(_ keyWindow: NSWindow?) {
        let value = Self.canClose(keyWindow)
        if value != canClose { canClose = value }
    }

    static func canClose(_ window: NSWindow?) -> Bool {
        guard let window, window.styleMask.contains(.closable) else { return false }
        // A sheet is key while attached; Command-W must not close its parent behind it.
        return window.sheetParent == nil
    }
}

@MainActor
enum FileLifecycleResponderDispatch {
    /// Sends the catalog's responder-chain selector to the first responder of the key window
    /// (or to `target` when given). Returns `false` when nothing handled it.
    @discardableResult
    static func send(
        _ binding: FileLifecycleShortcuts.Binding,
        application: NSApplication = .shared,
        to target: Any? = nil
    ) -> Bool {
        guard case .responderChainSelector(let selectorName) = binding.menuAction else {
            return false
        }
        return application.sendAction(NSSelectorFromString(selectorName), to: target, from: nil)
    }
}

/// Captures the live menu bar into the platform-neutral inventory that
/// `FileLifecycleShortcuts.verifyMenu` checks.
@MainActor
enum FileLifecycleMenuCapture {
    static let maximumDepth = 8
    static let fileMenuIndex = 1

    static func capture(
        _ mainMenu: NSMenu? = NSApplication.shared.mainMenu
    ) -> [FileLifecycleShortcuts.ObservedMenuItem] {
        guard let mainMenu else { return [] }
        var result: [FileLifecycleShortcuts.ObservedMenuItem] = []
        for (index, topLevelItem) in mainMenu.items.enumerated() {
            guard let submenu = topLevelItem.submenu else { continue }
            let location: FileLifecycleShortcuts.MenuLocation? =
                if index == 0 {
                    .applicationMenu
                } else if index == fileMenuIndex {
                    // Position, not the localized title: the File menu follows the app menu.
                    .fileMenu
                } else {
                    nil
                }
            collect(submenu, location: location, depth: 1, into: &result)
        }
        return result
    }

    static func verify(
        _ mainMenu: NSMenu? = NSApplication.shared.mainMenu
    ) -> [FileLifecycleShortcuts.Finding] {
        FileLifecycleShortcuts.verifyMenu(capture(mainMenu))
    }

    private static func collect(
        _ menu: NSMenu,
        location: FileLifecycleShortcuts.MenuLocation?,
        depth: Int,
        into result: inout [FileLifecycleShortcuts.ObservedMenuItem]
    ) {
        guard depth <= maximumDepth else { return }
        for item in menu.items {
            if result.count > FileLifecycleShortcuts.maximumObservedMenuItems { return }
            if item.isSeparatorItem { continue }
            if !item.keyEquivalent.isEmpty || !item.title.isEmpty {
                result.append(
                    FileLifecycleShortcuts.ObservedMenuItem(
                        title: item.title,
                        keyEquivalent: item.keyEquivalent,
                        modifiers: modifiers(item.keyEquivalentModifierMask),
                        actionSelector: item.action.map(NSStringFromSelector),
                        location: location
                    ))
            }
            // Services entries are user-configurable system items, not MacMerge bindings.
            if let submenu = item.submenu, submenu !== NSApplication.shared.servicesMenu {
                collect(submenu, location: location, depth: depth + 1, into: &result)
            }
        }
    }

    private static func modifiers(
        _ flags: NSEvent.ModifierFlags
    ) -> Set<KeyboardShortcutPolicy.Modifier> {
        var result: Set<KeyboardShortcutPolicy.Modifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }
}
