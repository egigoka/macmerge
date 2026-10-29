import Foundation
import MacMergeCore
import XCTest

/// Guards the WinMerge difference-navigation catalog (F8/F7, Alt-arrow/Home/Enter/End) and the
/// focus-aware router that dispatches the Option chords.
final class DifferenceNavigationShortcutsTests: XCTestCase {
    typealias Catalog = DifferenceNavigationShortcuts
    typealias Command = DifferenceNavigationShortcuts.Command
    typealias Chord = KeyboardShortcutPolicy.Chord

    private func policy() throws -> KeyboardShortcutPolicy {
        try Catalog.sharedPolicy.get()
    }

    private func chord(for command: Command) throws -> Chord {
        try XCTUnwrap(Catalog.bindings(for: command).first { $0.delivery == .focusRoutedAlternate })
            .chord
    }

    func testCatalogMatchesWinMergeAccelerators() throws {
        XCTAssertEqual(
            Catalog.bindings.map(\.winMergeAccelerator),
            [
                "VK_F8", "VK_DOWN, ALT", "VK_F7", "VK_UP, ALT", "VK_HOME, ALT", "VK_RETURN, ALT",
                "VK_END, ALT"
            ]
        )
        XCTAssertEqual(Catalog.menuBinding(for: .next)?.chord, try Chord(.function(8)))
        XCTAssertEqual(Catalog.menuBinding(for: .previous)?.chord, try Chord(.function(7)))
        XCTAssertNil(Catalog.menuBinding(for: .first))
        XCTAssertNil(Catalog.menuBinding(for: .current))
        XCTAssertNil(Catalog.menuBinding(for: .last))
        XCTAssertEqual(Catalog.focusRoutedBindings.count, 5)
        XCTAssertTrue(Catalog.focusRoutedBindings.allSatisfy { $0.chord.modifiers == [.option] })
        for command in Command.allCases {
            XCTAssertEqual(Command(command.identifier), command)
        }
    }

    func testCatalogStaysInParityWithPolicyShortcuts() {
        let identifiers = Set(Command.allCases.map(\.identifier))
        let policyPairs = Set(
            KeyboardShortcutPolicy.unfinishedAuditCommandShortcuts
                .filter { identifiers.contains($0.command) }
                .map { "\($0.command.rawValue)|\($0.chord)" }
        )
        let catalogPairs = Set(
            Catalog.bindings.map { "\($0.command.identifier.rawValue)|\($0.chord)" })
        XCTAssertEqual(catalogPairs, policyPairs)
    }

    func testRouteAcrossFocusStatesCommandsAndAvailability() throws {
        let policy = try policy()
        let reserved: [Command: KeyboardShortcutPolicy.NativeTextEditingCommand] = [
            .next: .moveParagraphDown,
            .previous: .moveParagraphUp,
            .first: .moveBackwardToParagraphStart,
            .last: .moveForwardToParagraphEnd
        ]
        for focus in KeyboardShortcutPolicy.EditorFocus.allCases {
            for singleLineRow in [false, true] where !(singleLineRow && focus == .none) {
                for command in Command.allCases {
                    for enabled in [true, false] {
                        let decision = Catalog.route(
                            try chord(for: command),
                            in: .init(lifecycle: .different, editorFocus: focus),
                            enabledCommands: enabled ? Set(Command.allCases) : [],
                            policy: policy,
                            focusIsSingleLineDiffRow: singleLineRow
                        )
                        let expected: Catalog.Decision
                        if command == .current, focus == .editable {
                            // Option-Return inserts a newline in editable text, even in a row.
                            expected = .passThrough(
                                .nativeTextEditing(.insertNewlineIgnoringFieldEditor))
                        } else if focus != .none, !singleLineRow, let native = reserved[command] {
                            expected = .passThrough(.nativeTextEditing(native))
                        } else {
                            expected = enabled ? .perform(command) : .passThrough(.unavailable(command))
                        }
                        XCTAssertEqual(
                            decision, expected,
                            "\(command) focus=\(focus) singleLine=\(singleLineRow) enabled=\(enabled)"
                        )
                    }
                }
            }
        }
    }

    func testRouteOnlyEnablesListedCommands() throws {
        let decision = Catalog.route(
            try chord(for: .first),
            in: .init(lifecycle: .different),
            enabledCommands: [.next, .last],
            policy: try policy()
        )
        XCTAssertEqual(decision, .passThrough(.unavailable(.first)))
    }

    func testRouteRespectsLifecycle() throws {
        for lifecycle in [KeyboardShortcutPolicy.LifecycleState.loading, .empty, .equal] {
            let decision = Catalog.route(
                try chord(for: .next),
                in: .init(lifecycle: lifecycle),
                enabledCommands: Set(Command.allCases),
                policy: try policy()
            )
            XCTAssertNil(decision.command, "\(lifecycle)")
        }
    }

    func testOptionShiftDownNeverDispatchesNextConflict() throws {
        let optionShiftDown = try Chord(.special(.downArrow), modifiers: [.option, .shift])
        for focus in KeyboardShortcutPolicy.EditorFocus.allCases {
            let decision = Catalog.route(
                optionShiftDown,
                in: .init(lifecycle: .different, editorFocus: focus),
                enabledCommands: Set(Command.allCases),
                policy: try policy(),
                focusIsSingleLineDiffRow: focus != .none
            )
            XCTAssertEqual(decision, .passThrough(.notNavigationAlternate))
        }
    }

    func testMenuChordsAreNotFocusRouted() throws {
        for key in [7, 8] {
            XCTAssertEqual(
                Catalog.route(
                    try Chord(.function(key)),
                    in: .init(lifecycle: .different),
                    enabledCommands: Set(Command.allCases),
                    policy: try policy()
                ),
                .passThrough(.notNavigationAlternate)
            )
        }
    }
}
