import Foundation
import MacMergeCore
import XCTest

/// Focused coverage for `FirstLastDifferenceShortcuts`: WinMerge Option chords plus the
/// Command-Option platform equivalents route First/Current/Last from every focus without
/// stealing native text editing.
final class FirstLastDifferenceShortcutsTests: XCTestCase {
    typealias Router = FirstLastDifferenceShortcuts
    typealias Navigator = DifferenceNavigationShortcuts
    typealias Command = DifferenceNavigationShortcuts.Command
    typealias Chord = KeyboardShortcutPolicy.Chord
    typealias Policy = KeyboardShortcutPolicy

    private let optionHome = try! Chord(.special(.home), modifiers: [.option])
    private let optionReturn = try! Chord(.special(.return), modifiers: [.option])
    private let optionEnd = try! Chord(.special(.end), modifiers: [.option])
    private let commandOptionHome = try! Chord(.special(.home), modifiers: [.command, .option])
    private let commandOptionReturn = try! Chord(.special(.return), modifiers: [.command, .option])
    private let commandOptionEnd = try! Chord(.special(.end), modifiers: [.command, .option])

    private let firstLast: Set<Command> = [.first, .current, .last]

    private func sharedPolicy() throws -> Policy {
        try Navigator.sharedPolicy.get()
    }

    func testEquivalentCatalogShapeMatchesWinMergeAccelerators() {
        XCTAssertEqual(Router.commands, [.first, .current, .last])
        XCTAssertEqual(
            Router.equivalentBindings.map(\.winMergeAccelerator),
            ["VK_HOME, ALT", "VK_RETURN, ALT", "VK_END, ALT"])
        XCTAssertEqual(
            Router.equivalentBindings.map(\.chord),
            [commandOptionHome, commandOptionReturn, commandOptionEnd])
        XCTAssertTrue(Router.equivalentBindings.allSatisfy { $0.delivery == .menuKeyEquivalent })
        for command in firstLast {
            XCTAssertEqual(Router.winMergeBindings(for: command), Navigator.bindings(for: command))
            XCTAssertEqual(Router.menuBinding(for: command)?.chord, Router.equivalentBinding(for: command)?.chord)
            XCTAssertNotNil(Router.menuBinding(for: command), "\(command)")
            XCTAssertEqual(
                Router.shortcutHint(for: command),
                Navigator.displayName(of: Router.equivalentBinding(for: command)!.chord))
        }
        XCTAssertNil(Router.equivalentBinding(matching: optionHome))
        XCTAssertEqual(Router.equivalentBinding(matching: commandOptionHome)?.command, .first)
    }

    func testPolicyContainsCommandOptionEquivalents() {
        let wanted: [Policy.Command: Chord] = [
            .firstDifference: commandOptionHome,
            .currentDifference: commandOptionReturn,
            .lastDifference: commandOptionEnd
        ]
        for (command, chord) in wanted {
            let match = Policy.unfinishedAuditCommandShortcuts.first {
                $0.command == command && $0.chord == chord
            }
            XCTAssertNotNil(match, "\(command)")
            XCTAssertEqual(match?.enabledLifecycleStates, [.different], "\(command)")
        }
    }

    func testSharedPolicyAuditIsCleanSoEquivalentsNeverStealText() throws {
        XCTAssertEqual(Router.auditEquivalents(policy: try sharedPolicy()), [])
        XCTAssertEqual(Router.auditEquivalents(policy: try Policy.makeUnfinishedAudit()), [])
        for (chord, command) in [
            (commandOptionHome, Command.first), (commandOptionReturn, .current),
            (commandOptionEnd, .last)
        ] {
            for focus in [Policy.EditorFocus.readOnly, .editable] {
                let resolution = try sharedPolicy().resolve(
                    chord,
                    in: .init(lifecycle: .different, editorFocus: focus),
                    cancellationCheck: {})
                XCTAssertEqual(resolution.route, .applicationCommand(command.identifier), "\(focus)")
            }
        }
    }

    func testEquivalentsRouteFromEveryFocusIncludingTextViews() throws {
        let policy = try sharedPolicy()
        let cases: [(Chord, Command)] = [
            (commandOptionHome, .first), (commandOptionReturn, .current),
            (commandOptionEnd, .last)
        ]
        for (chord, command) in cases {
            for focus in Policy.EditorFocus.allCases {
                for singleLineRow in [false, true] {
                    XCTAssertEqual(
                        Router.route(
                            chord,
                            in: .init(lifecycle: .different, editorFocus: focus),
                            enabledCommands: firstLast,
                            policy: policy,
                            focusIsSingleLineDiffRow: singleLineRow),
                        .perform(command),
                        "\(command) \(focus) row=\(singleLineRow)")
                }
            }
        }
    }

    func testWinMergeChordsDelegateWithNativeTextYield() throws {
        let policy = try sharedPolicy()
        // No focus: both routers perform.
        for (chord, command) in [
            (optionHome, Command.first), (optionReturn, .current), (optionEnd, .last)
        ] {
            XCTAssertEqual(
                Router.route(
                    chord, in: .init(lifecycle: .different), enabledCommands: firstLast,
                    policy: policy),
                Navigator.route(
                    chord, in: .init(lifecycle: .different),
                    enabledCommands: Set(Navigator.Command.allCases), policy: policy))
            XCTAssertEqual(
                Router.route(
                    chord, in: .init(lifecycle: .different), enabledCommands: firstLast,
                    policy: policy),
                .perform(command))
        }
        // Editable text keeps Option-Return for newline even in a single-line row.
        XCTAssertEqual(
            Router.route(
                optionReturn,
                in: .init(lifecycle: .different, editorFocus: .editable),
                enabledCommands: firstLast, policy: policy, focusIsSingleLineDiffRow: true),
            .passThrough(.nativeTextEditing(.insertNewlineIgnoringFieldEditor)))
        // Paragraph moves yield to navigation inside a single-line diff row.
        XCTAssertEqual(
            Router.route(
                optionHome,
                in: .init(lifecycle: .different, editorFocus: .readOnly),
                enabledCommands: firstLast, policy: policy, focusIsSingleLineDiffRow: true),
            .perform(.first))
        XCTAssertEqual(
            Router.route(
                optionEnd,
                in: .init(lifecycle: .different, editorFocus: .editable),
                enabledCommands: firstLast, policy: policy, focusIsSingleLineDiffRow: true),
            .perform(.last))
        // Multi-line text keeps the paragraph reservations.
        XCTAssertEqual(
            Router.route(
                optionHome,
                in: .init(lifecycle: .different, editorFocus: .readOnly),
                enabledCommands: firstLast, policy: policy),
            .passThrough(.nativeTextEditing(.moveBackwardToParagraphStart)))
    }

    func testDelegationGatedToFirstCurrentLastSubset() throws {
        let policy = try sharedPolicy()
        // Missing command reads as unavailable, not blocked.
        XCTAssertEqual(
            Router.route(
                commandOptionHome, in: .init(lifecycle: .different),
                enabledCommands: [.current, .last], policy: policy),
            .passThrough(.unavailable(.first)))
        XCTAssertEqual(
            Router.route(
                optionEnd, in: .init(lifecycle: .different), enabledCommands: [.first],
                policy: policy),
            .passThrough(.unavailable(.last)))
        // A caller set of only Next/Previous never enables First.
        XCTAssertEqual(
            Router.route(
                commandOptionHome, in: .init(lifecycle: .different),
                enabledCommands: [.next, .previous], policy: policy),
            .passThrough(.unavailable(.first)))
        // The caller's context gate cannot widen the router gate.
        let wide = Policy.Context(lifecycle: .different, enabledCommands: [.firstDifference])
        XCTAssertEqual(
            Router.route(
                commandOptionEnd, in: wide, enabledCommands: [.first], policy: policy),
            .passThrough(.unavailable(.last)))
        // Lifecycle without differences never performs.
        for lifecycle in [Policy.LifecycleState.empty, .loading, .equal, .failed] {
            XCTAssertEqual(
                Router.route(
                    commandOptionReturn, in: .init(lifecycle: lifecycle),
                    enabledCommands: firstLast, policy: policy),
                .passThrough(.unavailable(.current)), "\(lifecycle)")
        }
    }

    func testHijackedPolicyChordNeverDispatchesForeignCommand() throws {
        // Drift within the First/Current/Last subset dispatches nothing: the chord resolves
        // to an enabled command the catalog does not associate with it.
        let driftedWithinSubset = try Policy(
            commandShortcuts: [.init(command: .lastDifference, chord: optionHome)],
            cancellationCheck: {})
        XCTAssertEqual(
            Router.route(
                optionHome, in: .init(lifecycle: .different), enabledCommands: firstLast,
                policy: driftedWithinSubset),
            .passThrough(.blocked))
        // A chord bound only to a non-navigation command reads as unavailable First,
        // paralleling DifferenceNavigationShortcuts' non-navigation gate.
        let hijackedWinMerge = try Policy(
            commandShortcuts: [.init(command: .nextConflict, chord: optionHome)],
            cancellationCheck: {})
        XCTAssertEqual(
            Router.route(
                optionHome, in: .init(lifecycle: .different), enabledCommands: firstLast,
                policy: hijackedWinMerge),
            .passThrough(.unavailable(.first)))
        let hijackedEquivalent = try Policy(
            commandShortcuts: [.init(command: .nextDifference, chord: commandOptionHome)],
            cancellationCheck: {})
        XCTAssertEqual(
            Router.route(
                commandOptionHome, in: .init(lifecycle: .different),
                enabledCommands: firstLast, policy: hijackedEquivalent),
            .passThrough(.blocked))
    }

    func testBlockedAndUnhandledFlaggedEveryFocus() throws {
        let empty = try Policy(commandShortcuts: [], cancellationCheck: {})
        let conflicts = Router.auditEquivalents(policy: empty)
        XCTAssertEqual(conflicts.count, 9)
        for focus in Policy.EditorFocus.allCases {
            for binding in Router.equivalentBindings {
                XCTAssertTrue(
                    conflicts.contains {
                        $0.binding == binding && $0.editorFocus == focus
                            && $0.kind == .unreachableWithoutTextFocus(.unhandled)
                    }, "\(binding.command) \(focus)")
                XCTAssertEqual(
                    Router.route(
                        binding.chord, in: .init(lifecycle: .different, editorFocus: focus),
                        enabledCommands: firstLast, policy: empty),
                    .passThrough(.blocked), "\(binding.command) \(focus)")
            }
        }
        // Unknown chords are never navigation alternates, in any focus.
        for focus in Policy.EditorFocus.allCases {
            XCTAssertEqual(
                Router.route(
                    try Chord(.function(8)), in: .init(lifecycle: .different, editorFocus: focus),
                    enabledCommands: firstLast, policy: try sharedPolicy()),
                .passThrough(.notNavigationAlternate), "\(focus)")
        }
    }
}
