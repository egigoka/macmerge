import AppKit
import Foundation
import MacMergeCore
import ObjectiveC
import SwiftUI
import XCTest

@testable import MacMerge

/// Test stand-in for the private one-line comparison-row text view.
private final class TestSingleLineRowTextView: NSTextView, SingleLineDiffRowTextView {}

/// Drives `DifferenceNavigationKeyRouter.handle` with real windows, first responders, and a
/// loaded comparison, plus edge cases of the catalog-to-SwiftUI menu shortcut bridge.
@MainActor
final class DifferenceNavigationKeyRoutingWindowTests: XCTestCase {
    typealias Chord = KeyboardShortcutPolicy.Chord
    typealias Binding = DifferenceNavigationShortcuts.Binding

    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))
    }

    private func optionDown() throws -> NSEvent {
        try keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.option, .function])
    }

    private func makeWindow(firstResponder: NSView?) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        if let firstResponder {
            firstResponder.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
            window.contentView?.addSubview(firstResponder)
            XCTAssertTrue(window.makeFirstResponder(firstResponder))
        }
        addTeardownBlock { @MainActor in window.close() }
        return window
    }

    private func textView<T: NSTextView>(_ type: T.Type, editable: Bool) -> T {
        let view = T(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        view.isEditable = editable
        view.isSelectable = true
        return view
    }

    /// Two-pane comparison with two separate differences.
    private func loadedModel() async throws -> ComparisonModel {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let leftURL = directory.appending(path: "left.txt")
        let rightURL = directory.appending(path: "right.txt")
        try Data("a\nleft one\nsame\nleft two\nz\n".utf8).write(to: leftURL)
        try Data("a\nright one\nsame\nright two\nz\n".utf8).write(to: rightURL)
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        let idle = expectation(description: "idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: 30)
        XCTAssertTrue(model.hasDifferences)
        return model
    }

    // MARK: editorFocus

    func testEditorFocusReflectsFirstResponder() {
        XCTAssertEqual(
            DifferenceNavigationKeyRouter.editorFocus(of: makeWindow(firstResponder: nil)), .none)
        XCTAssertEqual(
            DifferenceNavigationKeyRouter.editorFocus(
                of: makeWindow(firstResponder: textView(NSTextView.self, editable: true))),
            .editable
        )
        XCTAssertEqual(
            DifferenceNavigationKeyRouter.editorFocus(
                of: makeWindow(firstResponder: textView(NSTextView.self, editable: false))),
            .readOnly
        )
        XCTAssertEqual(
            DifferenceNavigationKeyRouter.editorFocus(
                of: makeWindow(firstResponder: textView(TestSingleLineRowTextView.self, editable: true))),
            .editable
        )
        XCTAssertEqual(
            DifferenceNavigationKeyRouter.editorFocus(
                of: makeWindow(firstResponder: textView(TestSingleLineRowTextView.self, editable: false))),
            .readOnly
        )
    }

    /// The tests above use a stand-in subclass; this pins the real row view's conformance
    /// so deleting it from MacMergeApp.swift fails a test.
    func testRealDiffContextTextViewAdoptsSingleLineRowProtocol() throws {
        let count = Int(objc_getClassList(nil, 0))
        let buffer = UnsafeMutablePointer<AnyClass>.allocate(capacity: count)
        defer { buffer.deallocate() }
        let filled = Int(
            objc_getClassList(AutoreleasingUnsafeMutablePointer(buffer), Int32(count)))
        let matches = (0..<filled).map { buffer[$0] }.filter {
            let name = NSStringFromClass($0)
            return name.contains("DiffContextTextView")
        }
        XCTAssertEqual(matches.count, 1, "\(matches.map(NSStringFromClass))")
        let rowClass: AnyClass = try XCTUnwrap(matches.first)
        XCTAssertTrue(rowClass is any SingleLineDiffRowTextView.Type, NSStringFromClass(rowClass))
    }

    // MARK: handle()

    func testHandleNavigatesWithoutTextFocus() async throws {
        let model = try await loadedModel()
        let window = makeWindow(firstResponder: nil)
        model.performDifferenceNavigation(.last)
        let last = try XCTUnwrap(model.selectedDifferenceID)
        model.performDifferenceNavigation(.first)
        XCTAssertNotEqual(model.selectedDifferenceID, last)
        XCTAssertTrue(DifferenceNavigationKeyRouter.handle(try optionDown(), in: window, model: model))
        XCTAssertEqual(model.selectedDifferenceID, last)
    }

    func testHandleInSingleLineRowNavigatesForArrowsHomeEnd() async throws {
        let model = try await loadedModel()
        for editable in [false, true] {
            let window = makeWindow(
                firstResponder: textView(TestSingleLineRowTextView.self, editable: editable))
            let end = try keyEvent(keyCode: 119, characters: "\u{F72B}", modifiers: [.option, .function])
            XCTAssertTrue(DifferenceNavigationKeyRouter.handle(end, in: window, model: model))
            let last = try XCTUnwrap(model.selectedDifferenceID)
            let home = try keyEvent(keyCode: 115, characters: "\u{F729}", modifiers: [.option, .function])
            XCTAssertTrue(DifferenceNavigationKeyRouter.handle(home, in: window, model: model))
            let first = try XCTUnwrap(model.selectedDifferenceID)
            XCTAssertNotEqual(first, last, "editable=\(editable)")
            XCTAssertTrue(
                DifferenceNavigationKeyRouter.handle(try optionDown(), in: window, model: model))
            XCTAssertEqual(model.selectedDifferenceID, last, "editable=\(editable)")
            let up = try keyEvent(keyCode: 126, characters: "\u{F700}", modifiers: [.option, .function])
            XCTAssertTrue(DifferenceNavigationKeyRouter.handle(up, in: window, model: model))
            XCTAssertEqual(model.selectedDifferenceID, first, "editable=\(editable)")
        }
    }

    func testHandleLeavesParagraphMovesToOrdinaryTextViews() async throws {
        let model = try await loadedModel()
        model.performDifferenceNavigation(.first)
        let first = model.selectedDifferenceID
        for editable in [false, true] {
            let window = makeWindow(firstResponder: textView(NSTextView.self, editable: editable))
            XCTAssertFalse(
                DifferenceNavigationKeyRouter.handle(try optionDown(), in: window, model: model))
            XCTAssertEqual(model.selectedDifferenceID, first, "editable=\(editable)")
        }
    }

    func testHandleOptionReturnInEditableRowKeepsNewlineButReadOnlyRowSelectsCurrent()
        async throws
    {
        let model = try await loadedModel()
        model.performDifferenceNavigation(.last)
        let last = try XCTUnwrap(model.selectedDifferenceID)
        var revision = model.selectedDifferenceRevealRevision
        for keyCode: UInt16 in [36, 76] {
            let event = try keyEvent(keyCode: keyCode, characters: "\r", modifiers: [.option])
            let editable = makeWindow(
                firstResponder: textView(TestSingleLineRowTextView.self, editable: true))
            XCTAssertFalse(DifferenceNavigationKeyRouter.handle(event, in: editable, model: model))
            XCTAssertEqual(model.selectedDifferenceRevealRevision, revision)
        }
        let readOnly = makeWindow(
            firstResponder: textView(TestSingleLineRowTextView.self, editable: false))
        for (keyCode, characters): (UInt16, String) in [(36, "\r"), (76, "\u{3}")] {
            let event = try keyEvent(keyCode: keyCode, characters: characters, modifiers: [.option])
            XCTAssertTrue(
                DifferenceNavigationKeyRouter.handle(event, in: readOnly, model: model), "\(keyCode)")
            XCTAssertNotEqual(model.selectedDifferenceRevealRevision, revision, "\(keyCode)")
            // Current Difference keeps the selection; First would move it.
            XCTAssertEqual(model.selectedDifferenceID, last, "\(keyCode)")
            revision = model.selectedDifferenceRevealRevision
        }
    }

    func testHandleIgnoresNonNavigationKeysAndModifierVariants() async throws {
        let model = try await loadedModel()
        model.performDifferenceNavigation(.first)
        let selected = model.selectedDifferenceID
        let revision = model.selectedDifferenceRevealRevision
        let window = makeWindow(firstResponder: nil)
        let events: [NSEvent] = [
            try keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.function]),
            try keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.option, .shift, .function]),
            try keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.command, .function]),
            try keyEvent(keyCode: 100, characters: "\u{F70B}", modifiers: [.function]),
            try keyEvent(keyCode: 98, characters: "\u{F70A}", modifiers: [.function]),
            try keyEvent(keyCode: 0, characters: "a", modifiers: [.option])
        ]
        for event in events {
            XCTAssertFalse(
                DifferenceNavigationKeyRouter.handle(event, in: window, model: model),
                "keyCode \(event.keyCode) flags \(event.modifierFlags.rawValue)"
            )
        }
        XCTAssertEqual(model.selectedDifferenceID, selected)
        XCTAssertEqual(model.selectedDifferenceRevealRevision, revision)
    }

    func testHandleDoesNothingWithoutComparison() throws {
        let model = ComparisonModel()
        let window = makeWindow(firstResponder: nil)
        XCTAssertFalse(DifferenceNavigationKeyRouter.handle(try optionDown(), in: window, model: model))
        XCTAssertNil(model.selectedDifferenceID)
    }

    func testRouterInstallAndRemoveAreIdempotent() {
        let router = DifferenceNavigationKeyRouter()
        let window = makeWindow(firstResponder: nil)
        let model = ComparisonModel()
        XCTAssertFalse(router.isInstalled)
        router.install(for: window, model: model)
        router.install(for: window, model: model)
        XCTAssertTrue(router.isInstalled)
        router.remove()
        XCTAssertFalse(router.isInstalled)
        router.remove()
        XCTAssertFalse(router.isInstalled)
    }

    func testMonitorGateRejectsOtherWindowsAndNonKeyWindows() throws {
        let window = makeWindow(firstResponder: nil)
        // windowNumber 0 resolves to no window, as for an event aimed at another window.
        XCTAssertNil(try optionDown().window)
        XCTAssertFalse(DifferenceNavigationKeyRouter.accepts(try optionDown(), in: window))

        window.orderFront(nil)
        let ownEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.option, .function],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
                isARepeat: false, keyCode: 125))
        XCTAssertTrue(ownEvent.window === window)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(DifferenceNavigationKeyRouter.accepts(ownEvent, in: window))
    }

    // MARK: menuKeyboardShortcut bridge

    func testMenuKeyboardShortcutMapsFunctionKeysAndModifiers() throws {
        let binding = Binding(
            command: .next,
            chord: try Chord(.function(5), modifiers: [.command, .shift, .option, .control]),
            delivery: .menuKeyEquivalent,
            winMergeAccelerator: "test"
        )
        let shortcut = try XCTUnwrap(binding.menuKeyboardShortcut)
        XCTAssertEqual(shortcut.key, KeyEquivalent("\u{F708}"))
        XCTAssertEqual(shortcut.modifiers, [.command, .shift, .option, .control])

        let f1 = Binding(
            command: .next, chord: try Chord(.function(1)), delivery: .menuKeyEquivalent,
            winMergeAccelerator: "test")
        XCTAssertEqual(f1.menuKeyboardShortcut?.key, KeyEquivalent("\u{F704}"))
    }

    func testMenuKeyboardShortcutRejectsNonFunctionAndFocusRoutedBindings() throws {
        let nonFunction = Binding(
            command: .next, chord: try Chord(.special(.downArrow)), delivery: .menuKeyEquivalent,
            winMergeAccelerator: "test")
        XCTAssertNil(nonFunction.menuKeyboardShortcut)
        let focusRoutedFunction = Binding(
            command: .next, chord: try Chord(.function(8)), delivery: .focusRoutedAlternate,
            winMergeAccelerator: "test")
        XCTAssertNil(focusRoutedFunction.menuKeyboardShortcut)
    }

    func testEnabledCommandsAtFirstAndLastDifference() async throws {
        let model = try await loadedModel()
        model.performDifferenceNavigation(.first)
        XCTAssertEqual(model.differenceNavigationLifecycle, .different)
        XCTAssertEqual(model.enabledDifferenceNavigationCommands, [.next, .first, .last, .current])
        model.performDifferenceNavigation(.last)
        XCTAssertEqual(
            model.enabledDifferenceNavigationCommands, [.previous, .first, .last, .current])
    }
}
