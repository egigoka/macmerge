import Foundation
import MacMergeCore
import XCTest

/// Edge cases for the difference-navigation catalog and router beyond the main matrix in
/// `DifferenceNavigationShortcutsTests`: identifier mapping bounds, display names, gating that
/// ignores the caller's own enabled set, custom policies, and policy failures.
final class DifferenceNavigationShortcutsEdgeCaseTests: XCTestCase {
    typealias Catalog = DifferenceNavigationShortcuts
    typealias Command = DifferenceNavigationShortcuts.Command
    typealias Chord = KeyboardShortcutPolicy.Chord
    typealias Policy = KeyboardShortcutPolicy

    private let optionDown = try! Chord(.special(.downArrow), modifiers: [.option])
    private let optionReturn = try! Chord(.special(.return), modifiers: [.option])

    private func sharedPolicy() throws -> Policy {
        try Catalog.sharedPolicy.get()
    }

    // MARK: Command identity

    func testCommandRejectsEveryNonNavigationIdentifier() {
        let navigation = Set(Command.allCases.map(\.identifier))
        XCTAssertEqual(navigation.count, Command.allCases.count)
        for identifier in ComparisonCommandState.Identifier.allCases
        where !navigation.contains(identifier) {
            XCTAssertNil(Command(identifier), "\(identifier)")
        }
        // Conflict navigation shares the Next/Previous/First/Current/Last shape but is distinct.
        for identifier: ComparisonCommandState.Identifier in [
            .nextConflict, .previousConflict, .firstConflict, .currentConflict, .lastConflict
        ] {
            XCTAssertNil(Command(identifier))
        }
    }

    func testWinMergeCommandIDsAndMenuTitlesAreDistinctAndExact() {
        XCTAssertEqual(
            Command.allCases.map(\.winMergeCommandID),
            ["ID_NEXTDIFF", "ID_PREVDIFF", "ID_FIRSTDIFF", "ID_CURDIFF", "ID_LASTDIFF"]
        )
        XCTAssertEqual(
            Command.allCases.map(\.menuTitle),
            [
                "Next Difference", "Previous Difference", "First Difference", "Current Difference",
                "Last Difference"
            ]
        )
    }

    // MARK: Catalog lookups

    func testEveryCommandHasExactlyOneFocusRoutedOptionAlternate() {
        for command in Command.allCases {
            let alternates = Catalog.bindings(for: command)
                .filter { $0.delivery == .focusRoutedAlternate }
            XCTAssertEqual(alternates.count, 1, "\(command)")
            XCTAssertEqual(alternates.first?.chord.modifiers, [.option], "\(command)")
        }
        XCTAssertEqual(Set(Catalog.bindings.map(\.chord)).count, Catalog.bindings.count)
    }

    func testFocusRoutedLookupRejectsNearMissChords() throws {
        let nearMisses: [Chord] = [
            try Chord(.special(.downArrow)),
            try Chord(.special(.downArrow), modifiers: [.option, .shift]),
            try Chord(.special(.downArrow), modifiers: [.command]),
            try Chord(.special(.downArrow), modifiers: [.control]),
            try Chord(.special(.return)),
            try Chord(.special(.return), modifiers: [.option, .command]),
            try Chord(.special(.pageDown), modifiers: [.option]),
            try Chord(.function(8)),
            try Chord(.function(7)),
            try Chord(.function(8), modifiers: [.option])
        ]
        for chord in nearMisses {
            XCTAssertNil(Catalog.focusRoutedBinding(matching: chord), "\(chord)")
            XCTAssertEqual(
                Catalog.route(
                    chord,
                    in: .init(lifecycle: .different),
                    enabledCommands: Set(Command.allCases),
                    policy: try sharedPolicy()
                ),
                .passThrough(.notNavigationAlternate),
                "\(chord)"
            )
        }
    }

    func testSingleLineYieldingReservationsExcludeOptionReturnNewline() {
        XCTAssertEqual(
            Catalog.singleLineRowYieldingReservations,
            [
                .moveParagraphUp, .moveParagraphDown, .moveBackwardToParagraphStart,
                .moveForwardToParagraphEnd
            ]
        )
        XCTAssertFalse(
            Catalog.singleLineRowYieldingReservations.contains(.insertNewlineIgnoringFieldEditor))
    }

    // MARK: Display names and hints

    func testDisplayNameOrdersModifiersAndSpellsKeys() throws {
        XCTAssertEqual(Catalog.displayName(of: try Chord(.function(8))), "F8")
        XCTAssertEqual(
            Catalog.displayName(of: try Chord(.special(.upArrow), modifiers: [.option])),
            "Option-Up Arrow"
        )
        XCTAssertEqual(
            Catalog.displayName(
                of: try Chord(.special(.end), modifiers: [.command, .shift, .option, .control])),
            "Control-Option-Shift-Command-End"
        )
        XCTAssertEqual(
            Catalog.displayName(of: try Chord(.character("k"), modifiers: [.command])),
            "Command-K"
        )
    }

    func testDisplayNameSpellsEverySpecialKey() throws {
        let expected: [KeyboardShortcutPolicy.SpecialKey: String] = [
            .backspace: "Delete", .delete: "Forward Delete", .downArrow: "Down Arrow",
            .end: "End", .escape: "Escape", .home: "Home", .leftArrow: "Left Arrow",
            .pageDown: "Page Down", .pageUp: "Page Up", .return: "Return",
            .rightArrow: "Right Arrow", .space: "Space", .tab: "Tab", .upArrow: "Up Arrow"
        ]
        XCTAssertEqual(Set(expected.keys), Set(KeyboardShortcutPolicy.SpecialKey.allCases))
        for (special, name) in expected {
            XCTAssertEqual(Catalog.displayName(of: try Chord(.special(special))), name)
        }
    }

    func testAlternateHintsForEveryCommand() {
        XCTAssertEqual(
            Command.allCases.map { Catalog.alternateHint(for: $0) },
            [
                "Also Option-Down Arrow (WinMerge VK_DOWN, ALT).",
                "Also Option-Up Arrow (WinMerge VK_UP, ALT).",
                "Also Option-Home (WinMerge VK_HOME, ALT).",
                "Also Option-Return (WinMerge VK_RETURN, ALT).",
                "Also Option-End (WinMerge VK_END, ALT)."
            ]
        )
    }

    // MARK: Routing gates

    func testDecisionCommandIsNilForEveryPassThrough() {
        let reasons: [Catalog.PassThroughReason] = [
            .notNavigationAlternate, .nativeTextEditing(.moveParagraphDown), .unavailable(.next),
            .blocked
        ]
        for reason in reasons {
            XCTAssertNil(Catalog.Decision.passThrough(reason).command)
        }
        XCTAssertEqual(Catalog.Decision.perform(.last).command, .last)
    }

    func testContextEnabledCommandsAreReplacedByNavigationGate() throws {
        // A caller-provided enabled set must neither enable nor disable navigation.
        let context = Policy.Context(
            lifecycle: .different,
            enabledCommands: [.nextDifference, .firstDifference]
        )
        XCTAssertEqual(
            Catalog.route(optionDown, in: context, enabledCommands: [], policy: try sharedPolicy()),
            .passThrough(.unavailable(.next))
        )
        let emptyContext = Policy.Context(lifecycle: .different, enabledCommands: [])
        XCTAssertEqual(
            Catalog.route(
                optionDown, in: emptyContext, enabledCommands: [.next], policy: try sharedPolicy()),
            .perform(.next)
        )
    }

    func testSingleLineRowFlagIsIgnoredWithoutTextFocus() throws {
        for flag in [false, true] {
            XCTAssertEqual(
                Catalog.route(
                    optionDown,
                    in: .init(lifecycle: .different, editorFocus: .none),
                    enabledCommands: [.next],
                    policy: try sharedPolicy(),
                    focusIsSingleLineDiffRow: flag
                ),
                .perform(.next)
            )
        }
    }

    func testSingleLineRowStillHonoursLifecycleAndAvailability() throws {
        for focus: Policy.EditorFocus in [.readOnly, .editable] {
            XCTAssertEqual(
                Catalog.route(
                    optionDown,
                    in: .init(lifecycle: .loading, editorFocus: focus),
                    enabledCommands: Set(Command.allCases),
                    policy: try sharedPolicy(),
                    focusIsSingleLineDiffRow: true
                ),
                .passThrough(.unavailable(.next)),
                "\(focus)"
            )
            XCTAssertEqual(
                Catalog.route(
                    optionDown,
                    in: .init(lifecycle: .different, editorFocus: focus),
                    enabledCommands: [.previous],
                    policy: try sharedPolicy(),
                    focusIsSingleLineDiffRow: true
                ),
                .passThrough(.unavailable(.next)),
                "\(focus)"
            )
        }
    }

    func testReadOnlyRowOptionReturnPerformsCurrentButEditableRowKeepsNewline() throws {
        XCTAssertEqual(
            Catalog.route(
                optionReturn,
                in: .init(lifecycle: .different, editorFocus: .readOnly),
                enabledCommands: [.current],
                policy: try sharedPolicy(),
                focusIsSingleLineDiffRow: true
            ),
            .perform(.current)
        )
        XCTAssertEqual(
            Catalog.route(
                optionReturn,
                in: .init(lifecycle: .different, editorFocus: .editable),
                enabledCommands: [.current],
                policy: try sharedPolicy(),
                focusIsSingleLineDiffRow: true
            ),
            .passThrough(.nativeTextEditing(.insertNewlineIgnoringFieldEditor))
        )
    }

    func testEveryLifecycleOtherThanDifferentNeverPerforms() throws {
        for lifecycle in Policy.LifecycleState.allCases where lifecycle != .different {
            for command in Command.allCases {
                let chord = try XCTUnwrap(
                    Catalog.bindings(for: command).first { $0.delivery == .focusRoutedAlternate }
                ).chord
                let decision = Catalog.route(
                    chord,
                    in: .init(lifecycle: lifecycle),
                    enabledCommands: Set(Command.allCases),
                    policy: try sharedPolicy()
                )
                XCTAssertNil(decision.command, "\(command) \(lifecycle)")
            }
        }
    }

    // MARK: Custom policies

    func testPolicyWithoutNavigationShortcutsBlocks() throws {
        let policy = try Policy(commandShortcuts: [], cancellationCheck: {})
        XCTAssertEqual(
            Catalog.route(
                optionDown,
                in: .init(lifecycle: .different),
                enabledCommands: Set(Command.allCases),
                policy: policy
            ),
            .passThrough(.blocked)
        )
    }

    func testPolicyMappingChordToAnotherNavigationCommandIsBlocked() throws {
        // A drifted policy (Option-Down bound to First Difference) must not dispatch a command
        // the catalog does not associate with the chord.
        let policy = try Policy(
            commandShortcuts: [.init(command: .firstDifference, chord: optionDown)],
            cancellationCheck: {}
        )
        XCTAssertEqual(
            Catalog.route(
                optionDown,
                in: .init(lifecycle: .different),
                enabledCommands: Set(Command.allCases),
                policy: policy
            ),
            .passThrough(.blocked)
        )
    }

    func testPolicyMappingChordToNonNavigationCommandNeverDispatchesIt() throws {
        let policy = try Policy(
            commandShortcuts: [.init(command: .nextConflict, chord: optionDown)],
            cancellationCheck: {}
        )
        let decision = Catalog.route(
            optionDown,
            in: .init(lifecycle: .different, enabledCommands: [.nextConflict]),
            enabledCommands: Set(Command.allCases),
            policy: policy
        )
        // The router's gate never enables nextConflict, so the chord reads as unavailable.
        XCTAssertEqual(decision, .passThrough(.unavailable(.next)))
    }
}
