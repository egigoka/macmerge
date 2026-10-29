import AppKit
import MacMergeCore
import SwiftUI
import XCTest

@testable import MacMerge

/// App-side checks for the New/Open/Save/Close/Quit catalog: SwiftUI shortcut derivation,
/// menu capture and verification over a constructed `NSMenu`, Close dispatch, and Close
/// enablement. The live SwiftUI-built menu bar is not exercised here (no rendered menu seam).
@MainActor
final class FileLifecycleShortcutBindingsTests: XCTestCase {
    typealias Catalog = FileLifecycleShortcuts

    func testSwiftUIShortcutsMatchCatalog() {
        for binding in Catalog.bindings {
            let shortcut = binding.keyboardShortcut
            XCTAssertEqual(shortcut.key.character, binding.key, "\(binding.command)")
            XCTAssertEqual(shortcut.modifiers, .command, "\(binding.command)")
        }
    }

    func testCaptureVerifiesCatalogMenuWithLocalizedFileTitle() {
        let menu = Self.makeMainMenu(fileTitle: "Ablage")
        XCTAssertEqual(FileLifecycleMenuCapture.verify(menu), [])
    }

    func testCaptureReportsItemsOutsideFileMenuPosition() {
        let menu = Self.makeMainMenu(fileTitle: "File", insertMenuBeforeFile: true)
        let findings = Set(FileLifecycleMenuCapture.verify(menu))
        XCTAssertEqual(
            findings,
            Set(
                [Catalog.Command.new, .open, .save, .close].map {
                    Catalog.Finding.menuItemLocationMismatch($0, observed: nil)
                }))
    }

    func testCaptureReportsWrongQuitSelector() {
        let menu = Self.makeMainMenu(fileTitle: "File", quitSelector: #selector(NSApplication.hide(_:)))
        XCTAssertEqual(
            FileLifecycleMenuCapture.verify(menu),
            [.menuItemActionMismatch(.quit, observed: "hide:")])
    }

    func testCloseDispatchSendsPerformClose() {
        let window = RecordingWindow()
        let handled = FileLifecycleResponderDispatch.send(
            Catalog.binding(for: .close), to: window)
        XCTAssertTrue(handled)
        XCTAssertEqual(window.performCloseCount, 1)
    }

    func testNonResponderBindingsAreNotDispatched() {
        let window = RecordingWindow()
        for command in [Catalog.Command.new, .open, .save, .quit] {
            XCTAssertFalse(
                FileLifecycleResponderDispatch.send(Catalog.binding(for: command), to: window))
        }
        XCTAssertEqual(window.performCloseCount, 0)
    }

    func testCloseEnablementFollowsKeyWindowClosability() {
        XCTAssertFalse(KeyWindowClosability.canClose(nil))
        let closable = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        XCTAssertTrue(KeyWindowClosability.canClose(closable))
        let panel = NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertFalse(KeyWindowClosability.canClose(panel))
    }

    // MARK: - Helpers

    private final class RecordingWindow: NSWindow {
        private(set) var performCloseCount = 0

        init() {
            super.init(
                contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered,
                defer: true)
        }

        override func performClose(_ sender: Any?) {
            performCloseCount += 1
        }
    }

    private static func makeMainMenu(
        fileTitle: String,
        insertMenuBeforeFile: Bool = false,
        quitSelector: Selector = #selector(NSApplication.terminate(_:))
    ) -> NSMenu {
        let main = NSMenu(title: "Main")

        let appMenu = NSMenu(title: "MacMerge")
        let quit = Catalog.binding(for: .quit)
        appMenu.addItem(
            NSMenuItem(
                title: "\(quit.menuTitle) MacMerge", action: quitSelector,
                keyEquivalent: String(quit.key)))
        addTopLevel(appMenu, to: main)

        if insertMenuBeforeFile {
            addTopLevel(NSMenu(title: "Extra"), to: main)
        }

        let fileMenu = NSMenu(title: fileTitle)
        for command in [Catalog.Command.new, .open, .close, .save] {
            let binding = Catalog.binding(for: command)
            fileMenu.addItem(
                NSMenuItem(
                    title: binding.menuTitle, action: Selector(("bridgedAction:")),
                    keyEquivalent: String(binding.key)))
        }
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Save Left", action: nil, keyEquivalent: ""))
        addTopLevel(fileMenu, to: main)
        return main
    }

    private static func addTopLevel(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
