import MacMergeCore
import XCTest

/// Lane 6 coverage for `DirectionalCopyShortcuts`: catalog shape against WinMerge `Merge.rc`,
/// display/hint strings, the conflict audit against synthetic policies, and focus-aware routing
/// (native word navigation wins under text focus; copy commands never steal it).
final class DirectionalCopyShortcutsLaneTests: XCTestCase {
    typealias Catalog = DirectionalCopyShortcuts
    typealias Policy = KeyboardShortcutPolicy
    typealias Chord = KeyboardShortcutPolicy.Chord

    private static func chord(
        _ key: Policy.SpecialKey, _ modifiers: Set<Policy.Modifier>
    ) -> Chord {
        try! Chord(.special(key), modifiers: modifiers)
    }

    private let optionRight = chord(.rightArrow, [.option])
    private let optionLeft = chord(.leftArrow, [.option])
    private let commandOptionRight = chord(.rightArrow, [.command, .option])
    private let optionShiftRight = chord(.rightArrow, [.option, .shift])
    private let commandRight = chord(.rightArrow, [.command])

    private func sharedPolicy() throws -> Policy {
        try DifferenceNavigationShortcuts.sharedPolicy.get()
    }

    private func context(
        _ focus: Policy.EditorFocus = .none,
        lifecycle: Policy.LifecycleState = .different,
        hasSelection: Bool = true,
        isReadOnly: Bool = false
    ) -> Policy.Context {
        Policy.Context(
            lifecycle: lifecycle,
            hasSelection: hasSelection,
            isReadOnly: isReadOnly,
            editorFocus: focus
        )
    }

    private let allCopy = Set(DirectionalCopyShortcuts.Command.allCases)

    // MARK: - Catalog

    func testCatalogMatchesWinMergeAcceleratorsInCanonicalOrder() {
        XCTAssertEqual(Catalog.bindings.map(\.command), Catalog.Command.allCases)
        XCTAssertEqual(
            Catalog.bindings.map(\.winMergeAccelerator),
            ["VK_RIGHT, ALT", "VK_LEFT, ALT", "VK_RIGHT, CONTROL, ALT", "VK_LEFT, CONTROL, ALT"])
        XCTAssertEqual(
            Catalog.Command.allCases.map(\.winMergeCommandID),
            ["ID_L2R", "ID_R2L", "ID_L2RNEXT", "ID_R2LNEXT"])
        XCTAssertEqual(
            Catalog.bindings.map(\.chord),
            [optionRight, optionLeft, commandOptionRight, Self.chord(.leftArrow, [.command, .option])])
        XCTAssertEqual(
            Catalog.bindings.map(\.delivery),
            [.focusRoutedAlternate, .focusRoutedAlternate, .menuKeyEquivalent, .menuKeyEquivalent])
    }

    func testCatalogChordsMatchSharedPolicyCopyShortcuts() {
        let policyCopies = Policy.unfinishedAuditCommandShortcuts.filter {
            Catalog.Command($0.command) != nil
        }
        XCTAssertEqual(
            Set(policyCopies.map { [$0.command.rawValue: $0.chord] }),
            Set(Catalog.bindings.map { [$0.command.identifier.rawValue: $0.chord] }))
        for shortcut in policyCopies {
            XCTAssertTrue(shortcut.requiresSelection, "\(shortcut.command)")
            XCTAssertFalse(shortcut.allowsReadOnly, "\(shortcut.command)")
        }
    }

    func testCommandIdentifierRoundTripAndNonCopyIdentifiersAreRejected() {
        for command in Catalog.Command.allCases {
            XCTAssertEqual(Catalog.Command(command.identifier), command)
            XCTAssertEqual(Catalog.bindings(for: command).count, 1)
        }
        let copyIDs = Set(Catalog.Command.allCases.map(\.identifier))
        for identifier in ComparisonCommandState.Identifier.allCases where !copyIDs.contains(identifier) {
            XCTAssertNil(Catalog.Command(identifier), "\(identifier)")
        }
        XCTAssertNil(Catalog.Command(.copyAllToRight))
        XCTAssertNil(Catalog.Command(.nextDifference))
    }

    func testMenuTitlesAndAdvanceFlags() {
        XCTAssertEqual(
            Catalog.Command.allCases.map(\.menuTitle),
            ["Copy to Right", "Copy to Left", "Copy to Right and Advance", "Copy to Left and Advance"])
        XCTAssertEqual(Catalog.Command.allCases.map(\.advancesSelection), [false, false, true, true])
    }

    func testFocusRoutedLookupOnlyMatchesPlainOptionArrows() {
        XCTAssertEqual(Catalog.focusRoutedBindings.map(\.command), [.copyToRight, .copyToLeft])
        XCTAssertEqual(Catalog.focusRoutedBinding(matching: optionRight)?.command, .copyToRight)
        XCTAssertEqual(Catalog.focusRoutedBinding(matching: optionLeft)?.command, .copyToLeft)
        for chord in [
            commandOptionRight, optionShiftRight, commandRight,
            Self.chord(.rightArrow, []), Self.chord(.upArrow, [.option]),
            Self.chord(.rightArrow, [.control, .option])
        ] {
            XCTAssertNil(Catalog.focusRoutedBinding(matching: chord), "\(chord)")
        }
    }

    func testMenuBindingNeverReturnsFocusRoutedChord() throws {
        // Copy to Right/Left are reachable by keyboard only through the focus-routed alternate.
        XCTAssertNil(Catalog.menuBinding(for: .copyToRight))
        XCTAssertNil(Catalog.menuBinding(for: .copyToLeft))
        for (command, key) in [
            (Catalog.Command.copyToRightAndAdvance, KeyboardShortcutPolicy.SpecialKey.rightArrow),
            (.copyToLeftAndAdvance, .leftArrow)
        ] {
            let binding = try XCTUnwrap(Catalog.menuBinding(for: command), "\(command)")
            XCTAssertEqual(binding.command, command)
            XCTAssertEqual(binding.delivery, .menuKeyEquivalent)
            XCTAssertEqual(binding.chord, Self.chord(key, [.command, .option]), "\(command)")
        }
    }

    // MARK: - Display and hints

    func testDisplayNameUsesMacMenuModifierOrderAndKeyNames() throws {
        XCTAssertEqual(Catalog.displayName(of: optionLeft), "Option-Left Arrow")
        XCTAssertEqual(Catalog.displayName(of: commandOptionRight), "Option-Command-Right Arrow")
        XCTAssertEqual(
            Catalog.displayName(of: Self.chord(.upArrow, [.command, .shift, .option, .control])),
            "Control-Option-Shift-Command-Up Arrow")
        XCTAssertEqual(Catalog.displayName(of: Self.chord(.downArrow, [])), "Down Arrow")
        XCTAssertEqual(Catalog.displayName(of: Self.chord(.home, [.option])), "Option-Home")
        let specialNames: [(KeyboardShortcutPolicy.SpecialKey, String)] = [
            (.end, "End"), (.pageUp, "Page Up"), (.pageDown, "Page Down"),
            (.backspace, "Delete"), (.delete, "Forward Delete"), (.escape, "Escape"),
            (.return, "Return"), (.space, "Space"), (.tab, "Tab")
        ]
        for (key, name) in specialNames {
            XCTAssertEqual(Catalog.displayName(of: Self.chord(key, [.command])), "Command-\(name)")
        }
        XCTAssertEqual(
            Catalog.displayName(of: try Chord(.character("s"), modifiers: [.command])), "Command-S")
        XCTAssertEqual(Catalog.displayName(of: try Chord(.function(8))), "F8")
        // The Function modifier has no menu spelling and is dropped.
        XCTAssertEqual(
            Catalog.displayName(of: Self.chord(.leftArrow, [.function, .option])), "Option-Left Arrow")
    }

    func testHintsForLeftAndAdvanceVariants() {
        XCTAssertEqual(Catalog.shortcutHint(for: .copyToLeftAndAdvance), "Option-Command-Left Arrow")
        XCTAssertNil(Catalog.alternateHint(for: .copyToRightAndAdvance))
        XCTAssertEqual(
            Catalog.alternateHint(for: .copyToLeft),
            "Also Option-Left Arrow (WinMerge VK_LEFT, ALT) when the diff list has focus. "
                + "A focused text view keeps the chord for word navigation.")
        // Focus-routed hints must not claim the chord works everywhere.
        for command in [Catalog.Command.copyToRight, .copyToLeft] {
            XCTAssertTrue(Catalog.shortcutHint(for: command).hasSuffix("when the diff list has focus"))
        }
    }

    func testToolbarHelpSurfacesFocusRoutedChord() throws {
        let layout = ToolbarCommandLayout.make(state: .freshWindow)
        let right = try XCTUnwrap(layout.control(for: .copyToRight))
        let left = try XCTUnwrap(layout.control(for: .copyToLeft))
        XCTAssertTrue(
            right.help.contains("(Option-Right Arrow when the diff list has focus)"), right.help)
        XCTAssertTrue(
            left.help.contains("(Option-Left Arrow when the diff list has focus)"), left.help)
    }

    // MARK: - Unmapped Copy from Left/Right

    func testUnmappedCopyFromChordsAreNativeOnlyAndNeverBound() throws {
        let policy = try sharedPolicy()
        XCTAssertEqual(
            Catalog.unmappedWinMergeAccelerators.map(\.winMergeCommandID),
            ["ID_COPY_FROM_LEFT", "ID_COPY_FROM_RIGHT"])
        XCTAssertEqual(
            Catalog.unmappedWinMergeAccelerators.map(\.winMergeAccelerator),
            ["VK_RIGHT, SHIFT, ALT", "VK_LEFT, SHIFT, ALT"])
        let boundChords = Set(Catalog.bindings.map(\.chord))
        for unmapped in Catalog.unmappedWinMergeAccelerators {
            XCTAssertFalse(boundChords.contains(unmapped.macChord))
            guard case .nativeTextReservation(let native) = unmapped.reason else {
                return XCTFail("unexpected reason")
            }
            for focus in [Policy.EditorFocus.readOnly, .editable] {
                let resolution = try policy.resolve(
                    unmapped.macChord, in: context(focus), cancellationCheck: {})
                XCTAssertEqual(resolution.route, .nativeTextEditing(native), "\(focus)")
            }
            XCTAssertEqual(
                Catalog.route(unmapped.macChord, in: context(), enabledCommands: allCopy, policy: policy),
                .passThrough(.notCopyAlternate))
        }
    }

    // MARK: - Audit

    func testSharedPolicyAuditIsEmptyAndUnfinishedAuditAgrees() throws {
        XCTAssertEqual(Catalog.auditConflicts(policy: try sharedPolicy()), [])
        XCTAssertEqual(Catalog.auditConflicts(policy: try Policy.makeUnfinishedAudit()), [])
    }

    func testAuditFlagsFocusRoutingWithoutNativeReservation() throws {
        let policy = try Policy(commandShortcuts: Policy.unfinishedAuditCommandShortcuts)
        let conflicts = Catalog.auditConflicts(policy: policy)
        XCTAssertEqual(conflicts.map(\.binding.command), [.copyToRight, .copyToRight, .copyToLeft, .copyToLeft])
        XCTAssertEqual(conflicts.map(\.editorFocus), [.readOnly, .editable, .readOnly, .editable])
        XCTAssertTrue(conflicts.allSatisfy { $0.kind == .focusRoutingWithoutNativeReservation })
    }

    func testAuditFlagsMenuKeyEquivalentThatWouldStealNativeText() throws {
        let stolen = Policy.NativeTextEditingReservation(
            command: .moveParagraphDown, chord: commandOptionRight)
        let policy = try Policy(
            commandShortcuts: Policy.unfinishedAuditCommandShortcuts,
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations + [stolen])
        let conflicts = Catalog.auditConflicts(policy: policy)
        XCTAssertEqual(conflicts.map(\.binding.command), [.copyToRightAndAdvance, .copyToRightAndAdvance])
        XCTAssertEqual(conflicts.map(\.editorFocus), [.readOnly, .editable])
        XCTAssertTrue(
            conflicts.allSatisfy { $0.kind == .menuKeyEquivalentStealsNativeText(.moveParagraphDown) })
    }

    func testAuditFlagsUnreachableBindingsWhenPolicyLacksCopyShortcuts() throws {
        let policy = try Policy(
            commandShortcuts: [],
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations)
        let conflicts = Catalog.auditConflicts(policy: policy)
        let noFocus = conflicts.filter { $0.editorFocus == .none }
        XCTAssertEqual(noFocus.map(\.binding.command), Catalog.Command.allCases)
        for conflict in noFocus {
            guard case .unreachableWithoutTextFocus(let route) = conflict.kind else {
                return XCTFail("\(conflict)")
            }
            XCTAssertEqual(route, .unhandled, "\(conflict.binding.command)")
        }
        // Menu-delivered advance chords have no native meaning, so text focus adds no findings.
        XCTAssertFalse(
            conflicts.contains { $0.editorFocus != .none && $0.binding.delivery == .menuKeyEquivalent })
    }

    // MARK: - Routing

    func testRouteDispatchesOnlyWithoutTextFocus() throws {
        let policy = try sharedPolicy()
        XCTAssertEqual(
            Catalog.route(optionRight, in: context(), enabledCommands: allCopy, policy: policy),
            .perform(.copyToRight))
        XCTAssertEqual(
            Catalog.route(optionLeft, in: context(), enabledCommands: allCopy, policy: policy),
            .perform(.copyToLeft))
        XCTAssertEqual(
            Catalog.route(optionRight, in: context(.readOnly), enabledCommands: allCopy, policy: policy),
            .passThrough(.nativeTextEditing(.moveWordRight)))
        XCTAssertEqual(
            Catalog.route(optionLeft, in: context(.editable), enabledCommands: allCopy, policy: policy),
            .passThrough(.nativeTextEditing(.moveWordLeft)))
    }

    func testTextFocusWinsEvenWhenCopyIsUnavailable() throws {
        let policy = try sharedPolicy()
        for focus in [Policy.EditorFocus.readOnly, .editable] {
            let decision = Catalog.route(
                optionLeft, in: context(focus, hasSelection: false), enabledCommands: [],
                policy: policy)
            XCTAssertEqual(decision, .passThrough(.nativeTextEditing(.moveWordLeft)), "\(focus)")
            XCTAssertNil(decision.command)
        }
    }

    func testRouteNeverHandlesNonAlternateChords() throws {
        let policy = try sharedPolicy()
        for chord in [commandOptionRight, optionShiftRight, commandRight, Self.chord(.downArrow, [.option])] {
            XCTAssertEqual(
                Catalog.route(chord, in: context(), enabledCommands: allCopy, policy: policy),
                .passThrough(.notCopyAlternate), "\(chord)")
        }
    }

    func testRouteReportsUnavailableForStateGates() throws {
        let policy = try sharedPolicy()
        // The command missing from the live enabled set.
        XCTAssertEqual(
            Catalog.route(
                optionRight, in: context(), enabledCommands: [.copyToLeft], policy: policy),
            .passThrough(.unavailable(.copyToRight)))
        // No selected or current difference.
        XCTAssertEqual(
            Catalog.route(
                optionRight, in: context(hasSelection: false), enabledCommands: allCopy, policy: policy),
            .passThrough(.unavailable(.copyToRight)))
        // Read-only document.
        XCTAssertEqual(
            Catalog.route(
                optionLeft, in: context(isReadOnly: true), enabledCommands: allCopy, policy: policy),
            .passThrough(.unavailable(.copyToLeft)))
        // Lifecycles without differences.
        for lifecycle in [Policy.LifecycleState.empty, .loading, .equal, .failed] {
            let decision = Catalog.route(
                optionRight, in: context(lifecycle: lifecycle), enabledCommands: allCopy,
                policy: policy)
            XCTAssertEqual(decision, .passThrough(.unavailable(.copyToRight)), "\(lifecycle)")
        }
    }

    func testRouteIgnoresCallerEnabledCommandsAndNeverDispatchesNonCopyCommands() throws {
        let policy = try sharedPolicy()
        // A caller-provided enabled set is replaced by the copy gate.
        let wide = Policy.Context(
            lifecycle: .different, hasSelection: true,
            enabledCommands: Set(ComparisonCommandState.Identifier.allCases))
        XCTAssertEqual(
            Catalog.route(optionRight, in: wide, enabledCommands: [], policy: policy),
            .passThrough(.unavailable(.copyToRight)))

        // A policy that binds Option-Right to a non-copy command must not dispatch it.
        let hijack = try Policy(commandShortcuts: [
            Policy.CommandShortcut(command: .nextDifference, chord: optionRight)
        ])
        let decision = Catalog.route(optionRight, in: context(), enabledCommands: allCopy, policy: hijack)
        XCTAssertEqual(decision, .passThrough(.blocked))
    }

    func testRouteWithoutBindingInPolicyPassesThrough() throws {
        let empty = try Policy(commandShortcuts: [])
        let decision = Catalog.route(optionRight, in: context(), enabledCommands: allCopy, policy: empty)
        XCTAssertNil(decision.command)
        XCTAssertEqual(decision, .passThrough(.blocked))
    }

    func testRouteIgnoresTaskCancellationOnEventPath() async throws {
        let policy = try sharedPolicy()
        let allCopy = self.allCopy
        let chord = optionRight
        let task = Task { () -> Catalog.Decision in
            withUnsafeCurrentTask { $0?.cancel() }
            return Catalog.route(
                chord,
                in: Policy.Context(lifecycle: .different, hasSelection: true),
                enabledCommands: allCopy, policy: policy)
        }
        let decision = await task.value
        XCTAssertEqual(decision, .perform(.copyToRight))
    }

    func testDecisionCommandAccessor() {
        XCTAssertEqual(Catalog.Decision.perform(.copyToLeft).command, .copyToLeft)
        XCTAssertNil(Catalog.Decision.passThrough(.blocked).command)
        XCTAssertNil(Catalog.Decision.passThrough(.unavailable(.copyToLeft)).command)
    }
}
