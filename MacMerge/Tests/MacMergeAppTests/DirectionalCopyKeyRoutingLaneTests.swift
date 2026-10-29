import AppKit
import Foundation
import MacMergeCore
import SwiftUI
import XCTest

@testable import MacMerge

/// Lane 6 coverage for `DirectionalCopyKeyRouter`: NSEvent-to-chord conversion, live-model
/// decisions (current-row difference, per-side read-only, empty window), real-window `handle`
/// with text first responders, and the catalog-to-SwiftUI menu shortcut bridge.
@MainActor
final class DirectionalCopyKeyRoutingLaneTests: XCTestCase {
    typealias Chord = KeyboardShortcutPolicy.Chord
    typealias Router = DirectionalCopyKeyRouter

    private let optionRight = try! Chord(.special(.rightArrow), modifiers: [.option])
    private let optionLeft = try! Chord(.special(.leftArrow), modifiers: [.option])

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

    private func arrow(_ right: Bool, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try keyEvent(
            keyCode: right ? 124 : 123,
            characters: right ? "\u{F703}" : "\u{F702}",
            modifiers: modifiers.union(.function))
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

    private func textView(editable: Bool) -> NSTextView {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        view.isEditable = editable
        view.isSelectable = true
        return view
    }

    private func loadedModel() async throws -> ComparisonModel {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let leftURL = directory.appending(path: "left.txt")
        let rightURL = directory.appending(path: "right.txt")
        try Data("same\nleft\nsame\n".utf8).write(to: leftURL)
        try Data("same\nright\nsame\n".utf8).write(to: rightURL)
        let model = ComparisonModel()
        model.enqueueOpen([leftURL, rightURL])
        await waitUntilIdle(model)
        XCTAssertTrue(model.hasDifferences)
        return model
    }

    private func waitUntilIdle(_ model: ComparisonModel) async {
        let idle = expectation(description: "idle")
        model.whenIdle { idle.fulfill() }
        await fulfillment(of: [idle], timeout: 5)
    }

    /// Puts the cursor on the only difference without an explicit difference selection.
    private func focusCurrentRowOnDifference(_ model: ComparisonModel) throws -> DiffRow.ID {
        let difference = try XCTUnwrap(model.rows.first { $0.left?.text == "left" })
        model.selectDifference(nil)
        model.moveCursor(to: difference.id)
        XCTAssertNil(model.selectedDifferenceID)
        XCTAssertFalse(model.hasSelectedDifference)
        XCTAssertTrue(model.hasCurrentDifference)
        return difference.id
    }

    // MARK: chord(for:)

    func testChordConvertsOnlyLeftRightArrowsAndDropsFunctionFlag() throws {
        XCTAssertEqual(Router.chord(for: try arrow(true, [.option])), optionRight)
        XCTAssertEqual(Router.chord(for: try arrow(false, [.option])), optionLeft)
        XCTAssertEqual(
            Router.chord(for: try arrow(true, [.option, .shift, .command, .control])),
            try Chord(.special(.rightArrow), modifiers: [.option, .shift, .command, .control]))
        XCTAssertEqual(
            Router.chord(for: try arrow(false, [])), try Chord(.special(.leftArrow)))
        // Up/Down arrows belong to the difference navigation router.
        let down = try keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: [.option, .function])
        XCTAssertNil(Router.chord(for: down))
        let letter = try keyEvent(keyCode: 0, characters: "a", modifiers: [.option])
        XCTAssertNil(Router.chord(for: letter))
    }

    // MARK: decision(for:editorFocus:model:)

    func testEmptyWindowNeverPerforms() {
        let model = ComparisonModel()
        XCTAssertFalse(model.hasCurrentDifference)
        XCTAssertTrue(model.enabledDirectionalCopyCommands.isEmpty)
        for chord in [optionRight, optionLeft] {
            let decision = Router.decision(for: chord, editorFocus: .none, model: model)
            XCTAssertNil(decision.command, "\(chord)")
        }
    }

    func testCurrentRowDifferenceEnablesBothDirectionsAndMatchesMenuGate() async throws {
        let model = try await loadedModel()
        _ = try focusCurrentRowOnDifference(model)
        XCTAssertEqual(
            model.enabledDirectionalCopyCommands, Set(DirectionalCopyShortcuts.Command.allCases))
        for command in DirectionalCopyShortcuts.Command.allCases {
            XCTAssertEqual(
                model.enabledDirectionalCopyCommands.contains(command),
                command.comparisonCopyCommand.isEnabled(on: model), "\(command)")
        }
        XCTAssertEqual(
            Router.decision(for: optionLeft, editorFocus: .none, model: model), .perform(.copyToLeft))
        XCTAssertEqual(
            Router.decision(for: optionLeft, editorFocus: .editable, model: model),
            .passThrough(.nativeTextEditing(.moveWordLeft)))
    }

    func testCursorOffDifferenceIsUnavailable() async throws {
        let model = try await loadedModel()
        let same = try XCTUnwrap(model.rows.first { $0.left?.text == "same" })
        model.selectDifference(nil)
        model.moveCursor(to: same.id)
        XCTAssertFalse(model.hasCurrentDifference)
        XCTAssertFalse(ComparisonCopyCommand.selectedToRight.isEnabled(on: model))
        XCTAssertNil(Router.decision(for: optionRight, editorFocus: .none, model: model).command)
    }

    func testReadOnlyTargetSideBlocksOnlyThatDirection() async throws {
        let model = try await loadedModel()
        _ = try focusCurrentRowOnDifference(model)
        XCTAssertTrue(ComparisonReadOnlyCommand.right.isEnabled(on: model))
        ComparisonReadOnlyCommand.right.setReadOnly(true, on: model)
        XCTAssertTrue(ComparisonReadOnlyCommand.right.isOn(on: model))

        XCTAssertFalse(ComparisonCopyCommand.selectedToRight.isEnabled(on: model))
        XCTAssertEqual(
            Router.decision(for: optionRight, editorFocus: .none, model: model),
            .passThrough(.unavailable(.copyToRight)))
        XCTAssertEqual(
            Router.decision(for: optionLeft, editorFocus: .none, model: model),
            .perform(.copyToLeft))
    }

    func testPolicyFailurePassesThroughWithoutPerforming() async throws {
        let model = try await loadedModel()
        _ = try focusCurrentRowOnDifference(model)
        let failure = KeyboardShortcutPolicyError.workLimitExceeded(maximum: 1)
        for chord in [optionRight, optionLeft] {
            XCTAssertEqual(
                Router.decision(
                    for: chord, editorFocus: .none, model: model, policy: .failure(failure)),
                .passThrough(.policyFailure(failure)), "\(chord)")
        }
        // The default argument is the shared policy used by the installed monitor.
        let shared = try DifferenceNavigationShortcuts.sharedPolicy.get()
        XCTAssertEqual(
            Router.decision(for: optionRight, editorFocus: .none, model: model, policy: .success(shared)),
            Router.decision(for: optionRight, editorFocus: .none, model: model))
    }

    // MARK: handle(_:in:model:)

    func testHandleCopiesCurrentRowDifferenceWithoutTextFocus() async throws {
        let model = try await loadedModel()
        _ = try focusCurrentRowOnDifference(model)
        let window = makeWindow(firstResponder: nil)
        XCTAssertTrue(Router.handle(try arrow(true, [.option]), in: window, model: model))
        await waitUntilIdle(model)
        XCTAssertTrue(model.right.isDirty)
        XCTAssertFalse(model.left.isDirty)
        XCTAssertFalse(model.hasDifferences)
    }

    func testHandleLeavesWordNavigationToFocusedTextViews() async throws {
        let model = try await loadedModel()
        _ = try focusCurrentRowOnDifference(model)
        for editable in [false, true] {
            let window = makeWindow(firstResponder: textView(editable: editable))
            for right in [true, false] {
                XCTAssertFalse(
                    Router.handle(try arrow(right, [.option]), in: window, model: model),
                    "editable=\(editable) right=\(right)")
            }
        }
        await waitUntilIdle(model)
        XCTAssertFalse(model.left.isDirty)
        XCTAssertFalse(model.right.isDirty)
        XCTAssertTrue(model.hasDifferences)
    }

    func testHandleLeavesWordNavigationToFocusedDiffPaneTextView() async throws {
        let model = try await loadedModel()
        _ = try focusCurrentRowOnDifference(model)
        // The real diff pane text view, configured read-only selectable like DiffLineTextView.
        let pane = DiffContextTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        pane.isEditable = false
        pane.isSelectable = true
        let window = makeWindow(firstResponder: pane)
        XCTAssertEqual(DifferenceNavigationKeyRouter.editorFocus(of: window), .readOnly)
        XCTAssertEqual(
            Router.decision(
                for: optionRight, editorFocus: DifferenceNavigationKeyRouter.editorFocus(of: window),
                model: model),
            .passThrough(.nativeTextEditing(.moveWordRight)))
        for right in [true, false] {
            XCTAssertFalse(Router.handle(try arrow(right, [.option]), in: window, model: model))
        }
        pane.isEditable = true
        XCTAssertEqual(DifferenceNavigationKeyRouter.editorFocus(of: window), .editable)
        XCTAssertFalse(Router.handle(try arrow(true, [.option]), in: window, model: model))
        await waitUntilIdle(model)
        XCTAssertFalse(model.left.isDirty)
        XCTAssertFalse(model.right.isDirty)
        XCTAssertTrue(model.hasDifferences)
    }

    func testHandleIgnoresNonAlternateChordsEvenWithoutTextFocus() async throws {
        let model = try await loadedModel()
        _ = try focusCurrentRowOnDifference(model)
        let window = makeWindow(firstResponder: nil)
        // Command-Option-arrow is a menu key equivalent; Option-Shift and Command-arrow are
        // native text selection/line moves; a bare arrow is cursor movement.
        for modifiers: NSEvent.ModifierFlags in [
            [.command, .option], [.option, .shift], [.command], [], [.control, .option]
        ] {
            XCTAssertFalse(
                Router.handle(try arrow(true, modifiers), in: window, model: model), "\(modifiers)")
        }
        XCTAssertFalse(model.right.isDirty)
        XCTAssertFalse(model.left.isDirty)
    }

    func testInstallRemoveSequenceTracksMonitor() async throws {
        let model = try await loadedModel()
        let router = Router()
        let window = makeWindow(firstResponder: nil)
        XCTAssertFalse(router.isInstalled)
        router.remove()
        XCTAssertFalse(router.isInstalled)
        router.install(for: window, model: model)
        XCTAssertTrue(router.isInstalled)
        router.install(for: window, model: model)
        XCTAssertTrue(router.isInstalled)
        router.remove()
        XCTAssertFalse(router.isInstalled)
        router.remove()
        XCTAssertFalse(router.isInstalled)
    }

    // MARK: shouldHandle(_:in:)

    /// Lets a test window report key status and an attached sheet without a running app.
    private final class StubWindow: NSWindow {
        var stubIsKey = true
        var stubSheet: NSWindow?
        override var isKeyWindow: Bool { stubIsKey }
        override var attachedSheet: NSWindow? { stubSheet }
    }

    private func stubWindow() -> StubWindow {
        let window = StubWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        addTeardownBlock { @MainActor in window.close() }
        return window
    }

    private func optionRightEvent(for window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option, .function],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{F703}",
                charactersIgnoringModifiers: "\u{F703}",
                isARepeat: false,
                keyCode: 124
            ))
    }

    func testShouldHandleOnlyKeyEventsForTheKeyWindowWithoutSheet() throws {
        let window = stubWindow()
        let event = try optionRightEvent(for: window)
        XCTAssertTrue(event.window === window)
        XCTAssertTrue(Router.shouldHandle(event, in: window))

        window.stubIsKey = false
        XCTAssertFalse(Router.shouldHandle(event, in: window), "non-key window")
        window.stubIsKey = true

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 50),
            styleMask: [.titled], backing: .buffered, defer: true)
        sheet.isReleasedWhenClosed = false
        window.stubSheet = sheet
        XCTAssertFalse(Router.shouldHandle(event, in: window), "attached sheet")
        window.stubSheet = nil

        let other = stubWindow()
        XCTAssertFalse(Router.shouldHandle(event, in: other), "event for another window")
        // Synthetic events with no window never reach the router.
        XCTAssertFalse(Router.shouldHandle(try arrow(true, [.option]), in: window), "windowless event")
    }

    // MARK: Menu bridge

    func testMenuKeyboardShortcutBridgeForEveryBinding() throws {
        for binding in DirectionalCopyShortcuts.bindings {
            let shortcut = binding.menuKeyboardShortcut
            switch binding.delivery {
            case .focusRoutedAlternate:
                XCTAssertNil(shortcut, "\(binding.command)")
            case .menuKeyEquivalent:
                let unwrapped = try XCTUnwrap(shortcut, "\(binding.command)")
                XCTAssertEqual(unwrapped.modifiers, [.command, .option])
                XCTAssertEqual(
                    unwrapped.key,
                    binding.command == .copyToRightAndAdvance ? .rightArrow : .leftArrow)
            }
        }
    }

    func testMenuKeyboardShortcutHandlesOtherKeysAndModifiers() throws {
        func binding(_ key: KeyboardShortcutPolicy.Key, _ modifiers: Set<KeyboardShortcutPolicy.Modifier>)
            throws -> DirectionalCopyShortcuts.Binding
        {
            DirectionalCopyShortcuts.Binding(
                command: .copyToRightAndAdvance,
                chord: try Chord(key, modifiers: modifiers),
                delivery: .menuKeyEquivalent,
                winMergeAccelerator: "test")
        }
        let up = try XCTUnwrap(
            try binding(.special(.upArrow), [.control, .shift, .function]).menuKeyboardShortcut)
        XCTAssertEqual(up.key, .upArrow)
        XCTAssertEqual(up.modifiers, [.control, .shift])
        XCTAssertEqual(
            try binding(.special(.downArrow), [.command]).menuKeyboardShortcut?.key, .downArrow)
        // Non-arrow keys are outside this bridge.
        XCTAssertNil(try binding(.special(.home), [.command]).menuKeyboardShortcut)
        XCTAssertNil(try binding(.function(8), []).menuKeyboardShortcut)
        XCTAssertNil(try binding(.character("c"), [.command]).menuKeyboardShortcut)
    }

    /// Source guard for the menu-drift fix: the Merge menu takes all four copy shortcuts from
    /// the catalog and never hardcodes an arrow key equivalent. No live menu snapshot exists.
    func testMergeMenuBindsCopyShortcutsThroughCatalog() throws {
        let appSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/MacMerge/MacMergeApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)
        for command in ["copyToRight", "copyToLeft", "copyToRightAndAdvance", "copyToLeftAndAdvance"] {
            XCTAssertEqual(
                source.components(separatedBy: ".directionalCopyShortcut(.\(command))").count - 1, 1,
                command)
        }
        for key in [".rightArrow", ".leftArrow"] {
            XCTAssertFalse(source.contains(".keyboardShortcut(\(key)"), key)
        }
        // Copy to Right/Left carry the Option-arrow tooltip instead of a key equivalent.
        XCTAssertNotNil(DirectionalCopyShortcuts.alternateHint(for: .copyToRight))
        XCTAssertNotNil(DirectionalCopyShortcuts.alternateHint(for: .copyToLeft))
    }

    func testComparisonCopyCommandMapping() {
        XCTAssertEqual(
            DirectionalCopyShortcuts.Command.allCases.map(\.comparisonCopyCommand),
            [.selectedToRight, .selectedToLeft, .selectedToRightAndAdvance, .selectedToLeftAndAdvance])
        for command in DirectionalCopyShortcuts.Command.allCases {
            XCTAssertEqual(command.comparisonCopyCommand.menuTitle, command.menuTitle)
        }
    }
}
