import AppKit
import Combine
import MacMergeCore
import SwiftUI
import XCTest

@testable import MacMerge

/// Lane 4 app-side edge cases: menu capture (nesting, depth, separators, modifiers, empty
/// menus), nil-target Close dispatch through the responder chain, and `KeyWindowClosability`
/// refresh, sheet handling, and notification observation.
/// Exercises constructed `NSMenu`s only; the live SwiftUI-built menu bar is not rendered here.
@MainActor
final class FileLifecycleShortcutBindingsLaneTests: XCTestCase {
    typealias Catalog = FileLifecycleShortcuts

    func testCaptureOfMissingMainMenuIsEmpty() {
        XCTAssertEqual(FileLifecycleMenuCapture.capture(nil), [])
        XCTAssertEqual(
            FileLifecycleMenuCapture.verify(nil),
            Catalog.Command.allCases.map { .menuItemMissing($0) })
    }

    func testCaptureAssignsLocationByPosition() {
        let main = NSMenu(title: "Main")
        addTopLevel(menu("App", [NSMenuItem(title: "About", action: nil, keyEquivalent: "")]), to: main)
        addTopLevel(menu("Datei", [NSMenuItem(title: "Open...", action: nil, keyEquivalent: "o")]), to: main)
        addTopLevel(menu("Edit", [NSMenuItem(title: "Copy", action: nil, keyEquivalent: "c")]), to: main)

        let captured = FileLifecycleMenuCapture.capture(main)
        XCTAssertEqual(captured.map(\.title), ["About", "Open...", "Copy"])
        XCTAssertEqual(captured.map(\.location), [.applicationMenu, .fileMenu, nil])
    }

    func testCaptureSkipsSeparatorsAndUntitledUnboundItems() {
        let main = NSMenu(title: "Main")
        addTopLevel(menu("App", []), to: main)
        addTopLevel(
            menu(
                "File",
                [
                    .separator(),
                    NSMenuItem(title: "", action: nil, keyEquivalent: ""),
                    NSMenuItem(title: "", action: nil, keyEquivalent: "w"),
                    NSMenuItem(title: "Save Left", action: nil, keyEquivalent: "")
                ]), to: main)

        let captured = FileLifecycleMenuCapture.capture(main)
        XCTAssertEqual(captured.map(\.title), ["", "Save Left"])
        XCTAssertEqual(captured.map(\.keyEquivalent), ["w", ""])
    }

    func testCaptureInheritsLocationIntoNestedSubmenus() {
        let nested = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        nested.submenu = menu("Recent", [NSMenuItem(title: "Deep", action: nil, keyEquivalent: "d")])
        let main = NSMenu(title: "Main")
        addTopLevel(menu("App", []), to: main)
        addTopLevel(menu("File", [nested]), to: main)

        let captured = FileLifecycleMenuCapture.capture(main)
        XCTAssertEqual(captured.map(\.title), ["Recent", "Deep"])
        XCTAssertEqual(captured.map(\.location), [.fileMenu, .fileMenu])
    }

    func testCaptureStopsAtMaximumDepth() {
        var innermost = menu("Level", [NSMenuItem(title: "Bottom", action: nil, keyEquivalent: "")])
        for level in stride(from: FileLifecycleMenuCapture.maximumDepth, through: 1, by: -1) {
            let item = NSMenuItem(title: "L\(level)", action: nil, keyEquivalent: "")
            item.submenu = innermost
            innermost = menu("L\(level)", [item])
        }
        let main = NSMenu(title: "Main")
        addTopLevel(innermost, to: main)

        let titles = FileLifecycleMenuCapture.capture(main).map(\.title)
        XCTAssertEqual(titles.count, FileLifecycleMenuCapture.maximumDepth)
        XCTAssertFalse(titles.contains("Bottom"))
    }

    func testCaptureMapsModifierFlagsAndSelector() {
        let item = NSMenuItem(
            title: "Everything", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "e")
        item.keyEquivalentModifierMask = [.command, .control, .option, .shift, .function]
        let plain = NSMenuItem(title: "Plain", action: nil, keyEquivalent: "p")
        plain.keyEquivalentModifierMask = []
        let main = NSMenu(title: "Main")
        addTopLevel(menu("App", [item, plain]), to: main)

        let captured = FileLifecycleMenuCapture.capture(main)
        XCTAssertEqual(captured.first?.modifiers, [.command, .control, .option, .shift, .function])
        XCTAssertEqual(captured.first?.actionSelector, "terminate:")
        XCTAssertEqual(captured.last?.modifiers, [])
        XCTAssertNil(captured.last?.actionSelector)
    }

    func testCaptureOfCatalogBuiltMenuVerifiesClean() {
        let main = NSMenu(title: "Main")
        let quit = Catalog.binding(for: .quit)
        let quitItem = NSMenuItem(
            title: quit.menuTitle, action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: String(quit.key))
        addTopLevel(menu("MacMerge", [quitItem]), to: main)
        let fileItems = [Catalog.Command.new, .open, .close, .save].map { command in
            let binding = Catalog.binding(for: command)
            let item = NSMenuItem(
                title: binding.menuTitle, action: Selector(("bridgedAction:")),
                keyEquivalent: binding.keyboardShortcut.key.character.description)
            return item
        }
        addTopLevel(menu("Fichier", fileItems), to: main)
        XCTAssertEqual(FileLifecycleMenuCapture.verify(main), [])
    }

    func testCaptureDetectsShiftedCloseShortcut() {
        let main = NSMenu(title: "Main")
        addTopLevel(
            menu(
                "MacMerge",
                [
                    NSMenuItem(
                        title: "Quit MacMerge", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
                ]), to: main)
        let close = NSMenuItem(title: "Close", action: nil, keyEquivalent: "W")
        let fileItems =
            [Catalog.Command.new, .open, .save].map { command -> NSMenuItem in
                let binding = Catalog.binding(for: command)
                return NSMenuItem(
                    title: binding.menuTitle, action: Selector(("bridgedAction:")),
                    keyEquivalent: String(binding.key))
            } + [close]
        addTopLevel(menu("File", fileItems), to: main)

        XCTAssertEqual(
            FileLifecycleMenuCapture.verify(main),
            [.menuItemMissing(.close), .menuItemTitleBoundElsewhere(.close, observedKeyEquivalent: "W")])
    }

    func testSwiftUIShortcutMapsEveryExpressibleModifier() throws {
        let template = Catalog.binding(for: .save)
        let binding = try Catalog.Binding(
            command: .save, key: "s", modifiers: [.command, .control, .option, .shift],
            menuTitle: template.menuTitle, menuLocation: template.menuLocation,
            menuAction: template.menuAction, auditCommand: template.auditCommand)
        XCTAssertEqual(binding.keyboardShortcut.modifiers, [.command, .control, .option, .shift])
        XCTAssertEqual(binding.keyboardShortcut.key.character, "s")
    }

    func testSwiftUIShortcutDropsFunctionModifier() throws {
        let template = Catalog.binding(for: .save)
        let binding = try Catalog.Binding(
            command: .save, key: "s", modifiers: [.command, .option, .function],
            menuTitle: template.menuTitle, menuLocation: template.menuLocation,
            menuAction: template.menuAction, auditCommand: template.auditCommand)
        XCTAssertEqual(binding.keyboardShortcut.modifiers, [.command, .option])
        // The catalog guard is what keeps such an entry out of the shipped menu.
        XCTAssertTrue(
            Catalog.catalogFindings([binding]).contains(.catalogUnsupportedModifier(.save, .function)))
    }

    /// With no key window the nil-targeted responder chain has no `performClose:` handler, so
    /// dispatch reports `false` instead of closing anything.
    func testCloseDispatchWithoutKeyWindowIsUnhandled() {
        guard hostHasNoKeyOrMainWindow() else { return }
        let application = NSApplication.shared
        let savedDelegate = application.delegate
        application.delegate = nil
        defer { application.delegate = savedDelegate }
        XCTAssertFalse(FileLifecycleResponderDispatch.send(Catalog.binding(for: .close)))
    }

    /// Production dispatch uses a nil target. With no key or main window AppKit walks on to
    /// `NSApp` and its delegate, so a delegate that implements `performClose:` proves the
    /// selector really travels the responder chain rather than an explicit target.
    func testCloseDispatchWithNilTargetTravelsResponderChain() {
        guard hostHasNoKeyOrMainWindow() else { return }
        let application = NSApplication.shared
        let savedDelegate = application.delegate
        let recorder = PerformCloseRecordingDelegate()
        application.delegate = recorder
        defer { application.delegate = savedDelegate }

        XCTAssertTrue(FileLifecycleResponderDispatch.send(Catalog.binding(for: .close)))
        XCTAssertEqual(recorder.performCloseCount, 1)
        for command in [Catalog.Command.new, .open, .save, .quit] {
            XCTAssertFalse(FileLifecycleResponderDispatch.send(Catalog.binding(for: command)))
        }
        XCTAssertEqual(recorder.performCloseCount, 1)
    }

    func testAttachedSheetCannotClose() throws {
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        XCTAssertTrue(KeyWindowClosability.canClose(sheet), "closable before it is attached")
        parent.beginSheet(sheet)
        defer { parent.endSheet(sheet) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        try XCTSkipIf(
            sheet.sheetParent == nil,
            "AppKit did not attach the sheet in this headless test host")
        XCTAssertTrue(sheet.styleMask.contains(.closable))
        XCTAssertFalse(KeyWindowClosability.canClose(sheet))
        XCTAssertTrue(KeyWindowClosability.canClose(parent))
    }

    func testClosabilityRefreshTracksWindow() {
        let tracker = KeyWindowClosability(
            keyWindow: { nil }, notificationCenter: NotificationCenter())
        let closable = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let panel = NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)

        tracker.refresh(closable)
        XCTAssertTrue(tracker.canClose)
        tracker.refresh(panel)
        XCTAssertFalse(tracker.canClose)
        tracker.refresh(closable)
        XCTAssertTrue(tracker.canClose)
        tracker.refresh(nil)
        XCTAssertFalse(tracker.canClose)
    }

    func testClosabilityRefreshPublishesOnlyOnChange() {
        let tracker = KeyWindowClosability(
            keyWindow: { nil }, notificationCenter: NotificationCenter())
        tracker.refresh(nil)
        var publishCount = 0
        let subscription = tracker.objectWillChange.sink { publishCount += 1 }
        defer { subscription.cancel() }

        tracker.refresh(nil)
        XCTAssertEqual(publishCount, 0)
        let closable = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        tracker.refresh(closable)
        tracker.refresh(closable)
        XCTAssertEqual(publishCount, 1)
    }

    func testClosabilityObservesNotifications() {
        let center = NotificationCenter()
        let closable = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let currentKey = KeyWindowBox(closable)
        let tracker = KeyWindowClosability(
            keyWindow: { currentKey.window }, notificationCenter: center)
        XCTAssertTrue(tracker.canClose, "initial value reads the injected key window")

        let steps: [(Notification.Name, NSWindow?, Bool)] = [
            (NSWindow.didResignKeyNotification, nil, false),
            (NSWindow.didBecomeKeyNotification, closable, true),
            (NSWindow.willCloseNotification, nil, false)
        ]
        for (name, nextKey, expected) in steps {
            currentKey.window = nextKey
            let published = expectation(description: "\(name.rawValue) publishes")
            let subscription = tracker.objectWillChange.sink { published.fulfill() }
            center.post(name: name, object: nil)
            wait(for: [published], timeout: 5)
            subscription.cancel()
            RunLoop.main.run(until: Date())
            XCTAssertEqual(tracker.canClose, expected, "\(name.rawValue)")
        }
    }

    // MARK: - Helpers

    /// Nil-target dispatch tests depend on AppKit having no key or main window; a host that has
    /// one fails loudly here instead of silently skipping.
    private func hostHasNoKeyOrMainWindow() -> Bool {
        let application = NSApplication.shared
        guard application.keyWindow == nil, application.mainWindow == nil else {
            XCTFail("test host unexpectedly has a key or main window")
            return false
        }
        return true
    }

    @MainActor
    private final class KeyWindowBox {
        var window: NSWindow?

        init(_ window: NSWindow?) { self.window = window }
    }

    private final class PerformCloseRecordingDelegate: NSObject, NSApplicationDelegate {
        private(set) var performCloseCount = 0

        @objc func performClose(_ sender: Any?) {
            performCloseCount += 1
        }
    }

    private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        for item in items { menu.addItem(item) }
        return menu
    }

    private func addTopLevel(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
