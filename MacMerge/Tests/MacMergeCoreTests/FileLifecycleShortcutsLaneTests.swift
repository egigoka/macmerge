import Foundation
import XCTest
@testable import MacMergeCore

/// Lane 4 coverage for the New/Open/Save/Close/Quit catalog beyond the baseline tests:
/// policy and coverage-audit drift detection, state-matrix and toolbar derivation, catalog
/// helpers, and menu-inventory edge cases (bounds, selectors, titles, modifiers).
final class FileLifecycleShortcutsLaneTests: XCTestCase {
    typealias Catalog = FileLifecycleShortcuts
    typealias Policy = KeyboardShortcutPolicy
    typealias Item = FileLifecycleShortcuts.ObservedMenuItem

    // MARK: - Catalog helpers

    func testCommandOrderingMatchesDeclarationOrder() {
        XCTAssertEqual(Catalog.Command.allCases.sorted(), [.new, .open, .save, .close, .quit])
        XCTAssertLessThan(Catalog.Command.new, Catalog.Command.quit)
        XCTAssertFalse(Catalog.Command.close < Catalog.Command.close)
    }

    func testCatalogHelpersMirrorBindings() throws {
        for binding in Catalog.bindings {
            XCTAssertEqual(Catalog.key(binding.command), .character(binding.key))
            XCTAssertEqual(Catalog.key(binding.command), binding.policyKey)
            XCTAssertEqual(Catalog.modifiers(binding.command), binding.modifiers)
            XCTAssertEqual(
                binding.chord,
                try Policy.Chord(binding.policyKey, modifiers: binding.modifiers))
        }
    }

    func testMenuActionAndRoutingIdentity() {
        XCTAssertEqual(Catalog.binding(for: .new).comparisonCommand, .newComparison)
        XCTAssertEqual(Catalog.binding(for: .open).comparisonCommand, .openComparison)
        XCTAssertEqual(Catalog.binding(for: .save).comparisonCommand, .save)
        XCTAssertNil(Catalog.binding(for: .close).comparisonCommand)
        XCTAssertNil(Catalog.binding(for: .quit).comparisonCommand)

        XCTAssertNil(Catalog.binding(for: .new).menuAction.dispatchedSelector)
        XCTAssertEqual(Catalog.binding(for: .close).menuAction.dispatchedSelector, "performClose:")
        XCTAssertEqual(Catalog.binding(for: .quit).menuAction.dispatchedSelector, "terminate:")

        XCTAssertEqual(Catalog.binding(for: .new).auditCommand, .comparison(.newComparison))
        XCTAssertEqual(Catalog.binding(for: .open).auditCommand, .comparison(.openComparison))
        XCTAssertEqual(Catalog.binding(for: .save).auditCommand, .comparison(.save))
        XCTAssertEqual(Catalog.binding(for: .close).auditCommand, .close)
        XCTAssertEqual(Catalog.binding(for: .quit).auditCommand, .quit)
    }

    func testMenuLocationsMatchMacOSConventions() {
        XCTAssertEqual(Catalog.binding(for: .quit).menuLocation, .applicationMenu)
        for command in [Catalog.Command.new, .open, .save, .close] {
            XCTAssertEqual(Catalog.binding(for: command).menuLocation, .fileMenu, "\(command)")
        }
    }

    func testHelpTextSpellsEveryCatalogChord() {
        XCTAssertEqual(
            Catalog.Command.allCases.map(Catalog.helpText),
            ["Command-N", "Command-O", "Command-S", "Command-W", "Command-Q"])
        for binding in Catalog.bindings {
            XCTAssertEqual(Catalog.helpText(binding.command), Catalog.helpText(for: binding))
        }
    }

    func testHelpTextOrdersModifiersLikeMacOSMenus() throws {
        let template = Catalog.binding(for: .save)
        func spelled(_ modifiers: Set<Policy.Modifier>, key: Character = "s") throws -> String {
            Catalog.helpText(
                for: try Catalog.Binding(
                    command: .save, key: key, modifiers: modifiers,
                    menuTitle: template.menuTitle, menuLocation: template.menuLocation,
                    menuAction: template.menuAction, auditCommand: template.auditCommand))
        }
        XCTAssertEqual(
            try spelled([.function, .command, .shift, .option, .control]),
            "Control-Option-Shift-Command-Function-S")
        XCTAssertEqual(try spelled([.shift, .command]), "Shift-Command-S")
        XCTAssertEqual(try spelled([.option, .command], key: "1"), "Option-Command-1")
    }

    func testToolbarHelpTextIsBuiltFromCatalogHelpText() {
        XCTAssertTrue(ToolbarNewSplitButtonPlan.primaryHelp.hasSuffix("(\(Catalog.helpText(.new)))"))
        let layout = ToolbarCommandLayout.make(state: .freshWindow)
        XCTAssertEqual(
            layout.control(for: .openComparison)?.help.hasSuffix("(\(Catalog.helpText(.open)))"),
            true)
        XCTAssertEqual(
            layout.control(for: .save)?.help.hasSuffix("(\(Catalog.helpText(.save)))"), true)
    }

    func testMatrixShortcutIDsAreDistinctAndRouteLikeCatalog() {
        let ids = Catalog.Command.allCases.map(Catalog.matrixShortcutID)
        XCTAssertEqual(Set(ids).count, ids.count)
        for binding in Catalog.bindings {
            guard
                let row = KeyboardShortcutStateMatrix.canonicalDescriptors.first(where: {
                    $0.id == Catalog.matrixShortcutID(binding.command)
                })
            else {
                XCTFail("missing matrix row for \(binding.command)")
                continue
            }
            XCTAssertEqual(row.chord, binding.chord, "\(binding.command)")
            XCTAssertEqual(row.applicationCommand, binding.comparisonCommand, "\(binding.command)")
            XCTAssertEqual(row.isSystemCommand, binding.comparisonCommand == nil, "\(binding.command)")
        }
    }

    func testMatrixChordMismatchIsReported() throws {
        let save = Catalog.binding(for: .save)
        let shifted = try Policy.Chord(save.policyKey, modifiers: [.command, .shift])
        let descriptors = KeyboardShortcutStateMatrix.canonicalDescriptors.map { row in
            guard row.id == Catalog.matrixShortcutID(.save) else { return row }
            return KeyboardShortcutStateMatrix.ShortcutDescriptor(
                id: row.id, chord: shifted, applicationCommand: row.applicationCommand,
                winMergeAccelerator: row.winMergeAccelerator, requirement: row.requirement,
                preservesNativeEditing: row.preservesNativeEditing,
                isSystemCommand: row.isSystemCommand)
        }
        XCTAssertEqual(
            try Catalog.verifyCatalogConsistency(
                policy: try Policy.makeUnfinishedAudit(), matrixDescriptors: descriptors),
            [.matrixDescriptorChordMismatch(.save, observed: shifted)])
    }

    func testMatrixCommandMismatchIsReported() throws {
        func mutated(
            _ command: Catalog.Command,
            applicationCommand: (Policy.Command?) -> Policy.Command?,
            isSystemCommand: (Bool) -> Bool
        ) -> [KeyboardShortcutStateMatrix.ShortcutDescriptor] {
            KeyboardShortcutStateMatrix.canonicalDescriptors.map { row in
                guard row.id == Catalog.matrixShortcutID(command) else { return row }
                return KeyboardShortcutStateMatrix.ShortcutDescriptor(
                    id: row.id, chord: row.chord,
                    applicationCommand: applicationCommand(row.applicationCommand),
                    winMergeAccelerator: row.winMergeAccelerator, requirement: row.requirement,
                    preservesNativeEditing: row.preservesNativeEditing,
                    isSystemCommand: isSystemCommand(row.isSystemCommand))
            }
        }
        let policy = try Policy.makeUnfinishedAudit()
        let wrongCommand = mutated(.open, applicationCommand: { _ in .save }, isSystemCommand: { $0 })
        XCTAssertEqual(
            try Catalog.verifyCatalogConsistency(policy: policy, matrixDescriptors: wrongCommand),
            [.matrixDescriptorCommandMismatch(.open)])
        let notSystem = mutated(.quit, applicationCommand: { $0 }, isSystemCommand: { _ in false })
        XCTAssertEqual(
            try Catalog.verifyCatalogConsistency(policy: policy, matrixDescriptors: notSystem),
            [.matrixDescriptorCommandMismatch(.quit)])
    }

    func testEmptyMatrixReportsEveryCommandMissing() throws {
        let findings = try Catalog.verifyCatalogConsistency(
            policy: try Policy.makeUnfinishedAudit(), matrixDescriptors: [])
        XCTAssertEqual(findings, Catalog.Command.allCases.map { .matrixDescriptorMissing($0) })
    }

    func testCatalogFindingsOnEmptyCatalogReportsAllMissing() {
        XCTAssertEqual(
            Catalog.catalogFindings([]), Catalog.Command.allCases.map { .catalogMissingCommand($0) })
    }

    func testCatalogAcceptsDigitKeyAndRejectsPunctuation() throws {
        var digit = Catalog.bindings.filter { $0.command != .new }
        digit.insert(try makeBinding(.new, key: "1"), at: 0)
        XCTAssertEqual(Catalog.catalogFindings(digit), [])

        var punctuation = Catalog.bindings.filter { $0.command != .new }
        punctuation.insert(try makeBinding(.new, key: ","), at: 0)
        XCTAssertEqual(
            Catalog.catalogFindings(punctuation), [.catalogUnsupportedKey(.new, ",")])
    }

    func testCatalogReportsCombinedKeyAndModifierViolations() throws {
        var bindings = Catalog.bindings.filter { $0.command != .open }
        bindings.append(try makeBinding(.open, key: "O", modifiers: [.command, .function]))
        XCTAssertEqual(
            Catalog.catalogFindings(bindings),
            [.catalogUnsupportedKey(.open, "O"), .catalogUnsupportedModifier(.open, .function)])
    }

    func testMacOSDescriptorMatchesCanonicalAuditDescriptor() {
        for binding in Catalog.bindings {
            let audit = ShortcutCoverageAudit.Inventory.canonical.bindings.first {
                $0.command == binding.auditCommand
            }
            XCTAssertEqual(
                audit?.shortcut.canonicalized, Catalog.macOSDescriptor(for: binding),
                "\(binding.command)")
        }
    }

    // MARK: - Policy drift

    func testPolicyMissingSaveChordIsReported() throws {
        let shifted = try Policy.Chord(.character("s"), modifiers: [.command, .shift])
        let shortcuts = Policy.unfinishedAuditCommandShortcuts.map { entry in
            entry.command == .save && entry.chord == Catalog.binding(for: .save).chord
                ? rechord(entry, shifted) : entry
        }
        let policy = try Policy(
            commandShortcuts: shortcuts,
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations)
        let findings = try Catalog.verifyCatalogConsistency(policy: policy)

        XCTAssertTrue(findings.contains(.policyBindingMissing(.save)), "\(findings)")
        XCTAssertTrue(
            findings.contains(.policyBindingUnexpectedChord(.save, shifted)), "\(findings)")
        let routeMismatchFocuses = findings.compactMap { finding -> Policy.EditorFocus? in
            if case .policyRouteMismatch(.save, let focus, _) = finding { return focus }
            return nil
        }
        XCTAssertEqual(routeMismatchFocuses, [.none, .editable])
        XCTAssertTrue(
            findings.allSatisfy { finding in
                switch finding {
                case .policyBindingMissing(.save), .policyBindingUnexpectedChord(.save, _),
                    .policyRouteMismatch(.save, _, _):
                    true
                default: false
                }
            }, "\(findings)")
    }

    func testPolicyClaimingQuitChordIsReported() throws {
        let quit = Catalog.binding(for: .quit).chord
        let shortcuts =
            Policy.unfinishedAuditCommandShortcuts
            + [Policy.CommandShortcut(command: .newComparison, chord: quit)]
        let policy = try Policy(
            commandShortcuts: shortcuts,
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations)
        let findings = try Catalog.verifyCatalogConsistency(policy: policy)

        XCTAssertTrue(findings.contains(.policyBindingUnexpectedChord(.new, quit)), "\(findings)")
        XCTAssertTrue(
            findings.contains(.policyRouteMismatch(.quit, .none, .applicationCommand(.newComparison))),
            "\(findings)")
        XCTAssertTrue(
            findings.contains(
                .policyRouteMismatch(.quit, .editable, .applicationCommand(.newComparison))),
            "\(findings)")
    }

    func testPolicyWithoutLifecycleShortcutsReportsEveryAppOwnedCommand() throws {
        let catalogCommands = Set(Catalog.bindings.compactMap(\.comparisonCommand))
        let policy = try Policy(
            commandShortcuts: Policy.unfinishedAuditCommandShortcuts.filter {
                !catalogCommands.contains($0.command)
            },
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations)
        let findings = try Catalog.verifyCatalogConsistency(policy: policy)
        // Close and Quit stay AppKit-owned, so removing the app entries flags only New/Open/Save.
        XCTAssertEqual(
            findings,
            [Catalog.Command.new, .open, .save].flatMap { command -> [Catalog.Finding] in
                [
                    .policyBindingMissing(command),
                    .policyRouteMismatch(command, .none, .unhandled),
                    .policyRouteMismatch(command, .editable, .unhandled)
                ]
            })
    }

    // MARK: - Coverage-audit drift

    func testAuditBindingAtWrongChordIsReported() throws {
        let shifted = try Policy.Chord(.character("s"), modifiers: [.command, .shift])
        let inventory = mutatedInventory { binding in
            guard binding.command == .comparison(.save) else { return binding }
            return rebuild(
                binding,
                shortcut: MenuShortcutDescriptor(
                    platform: .macOS, key: "s", modifiers: [.command, .shift]),
                policyChord: shifted)
        }
        let findings = try verify(inventory: inventory)
        XCTAssertEqual(
            findings, [.auditBindingMissing(.save), .auditBindingUnexpectedChord(.save, shifted)])
    }

    func testAuditDescriptorMismatchIsReported() throws {
        let inventory = mutatedInventory { binding in
            guard binding.command == .close else { return binding }
            return rebuild(
                binding,
                shortcut: MenuShortcutDescriptor(
                    platform: .macOS, key: "w", modifiers: [.command, .option]),
                policyChord: binding.policyChord)
        }
        XCTAssertEqual(try verify(inventory: inventory), [.auditBindingDescriptorMismatch(.close)])
    }

    func testAuditChordClaimedByOtherCommandIsReported() throws {
        let open = Catalog.binding(for: .open)
        let inventory = mutatedInventory { binding in
            guard binding.command == .comparison(.undo) else { return binding }
            return rebuild(
                binding, shortcut: Catalog.macOSDescriptor(for: open), policyChord: open.chord)
        }
        XCTAssertEqual(
            try verify(inventory: inventory),
            [.auditChordClaimedByOtherCommand(.open, .comparison(.undo))])
    }

    func testAuditMissingQuitIsReported() throws {
        let canonical = ShortcutCoverageAudit.Inventory.canonical
        let inventory = ShortcutCoverageAudit.Inventory(
            revision: canonical.revision,
            bindings: canonical.bindings.filter { $0.command != .quit },
            nativeBindings: canonical.nativeBindings)
        XCTAssertEqual(try verify(inventory: inventory), [.auditBindingMissing(.quit)])
    }

    // MARK: - ObservedMenuItem chord

    func testObservedItemChordEdgeCases() throws {
        XCTAssertNil(item("Blank", "", location: .fileMenu).chord)
        XCTAssertNil(item("Multi", "ab", location: .fileMenu).chord)
        XCTAssertEqual(item("New", "n", location: .fileMenu).chord, Catalog.binding(for: .new).chord)
        let upper = item("New", "N", location: .fileMenu).chord
        XCTAssertNotEqual(upper, Catalog.binding(for: .new).chord)
        let explicitShift = Item(
            title: "New", keyEquivalent: "n", modifiers: [.command, .shift],
            actionSelector: nil, location: .fileMenu)
        XCTAssertEqual(upper, explicitShift.chord)
    }

    // MARK: - Menu verification edges

    func testVerifyMenuEmptyInventoryReportsEveryCommandMissing() {
        XCTAssertEqual(
            Catalog.verifyMenu([]), Catalog.Command.allCases.map { .menuItemMissing($0) })
    }

    func testVerifyMenuAcceptsInventoryAtExactLimit() {
        let filler = Array(
            repeating: item("filler", "", location: nil),
            count: Catalog.maximumObservedMenuItems - Self.goodMenu.count)
        let items = Self.goodMenu + filler
        XCTAssertEqual(items.count, Catalog.maximumObservedMenuItems)
        XCTAssertEqual(Catalog.verifyMenu(items), [])
    }

    func testVerifyMenuAcceptsBareQuitTitleAndRejectsOtherPrefixes() {
        let bare = replacing("Quit MacMerge", with: item("Quit", "q", action: "terminate:", location: .applicationMenu))
        XCTAssertEqual(Catalog.verifyMenu(bare), [])

        let glued = replacing(
            "Quit MacMerge", with: item("QuitMacMerge", "q", action: "terminate:", location: .applicationMenu))
        XCTAssertEqual(
            Catalog.verifyMenu(glued), [.menuItemTitleMismatch(.quit, observed: "QuitMacMerge")])
    }

    func testVerifyMenuRequiresExactTitleForFileCommands() {
        let items = replacing("Save", with: item("Save All", "s", location: .fileMenu))
        XCTAssertEqual(
            Catalog.verifyMenu(items), [.menuItemTitleMismatch(.save, observed: "Save All")])
    }

    func testVerifyMenuReportsQuitWithoutAction() {
        let items = replacing(
            "Quit MacMerge", with: item("Quit MacMerge", "q", action: nil, location: .applicationMenu))
        XCTAssertEqual(Catalog.verifyMenu(items), [.menuItemActionMismatch(.quit, observed: nil)])
    }

    func testVerifyMenuReportsQuitOutsideApplicationMenu() {
        let items = replacing(
            "Quit MacMerge", with: item("Quit MacMerge", "q", action: "terminate:", location: .fileMenu))
        XCTAssertEqual(
            Catalog.verifyMenu(items), [.menuItemLocationMismatch(.quit, observed: .fileMenu)])
    }

    /// A SwiftUI-bridged item (New, Open, Save, Close) with no action at all is dead.
    func testVerifyMenuReportsBridgedItemWithoutAction() {
        for title in ["New Text Comparison", "Open...", "Save", "Close"] {
            let original = Self.goodMenu.first { $0.title == title }!
            let dead = Item(
                title: original.title, keyEquivalent: original.keyEquivalent,
                modifiers: original.modifiers, actionSelector: nil, location: original.location)
            let findings = Catalog.verifyMenu(replacing(title, with: dead))
            XCTAssertEqual(findings.count, 1, title)
            guard case .menuItemActionMismatch(_, observed: nil) = findings.first else {
                return XCTFail("\(title): \(findings)")
            }
        }
    }

    /// Known limitation: the SwiftUI bridge selector is opaque, so a bridged item that carries
    /// some other action is still accepted; identity rests on title plus policy routing.
    func testVerifyMenuAcceptsAnyBridgeSelectorKnownLimitation() {
        let items = replacing(
            "Close", with: item("Close", "w", action: "unrelatedAction:", location: .fileMenu))
        XCTAssertEqual(Catalog.verifyMenu(items), [])
    }

    func testVerifyMenuReportsChordWithExtraModifierAsMissing() {
        let close = Item(
            title: "Close", keyEquivalent: "w", modifiers: [.command, .option],
            actionSelector: "bridge:", location: .fileMenu)
        let items = replacing("Close", with: close)
        XCTAssertEqual(
            Catalog.verifyMenu(items),
            [.menuItemMissing(.close), .menuItemTitleBoundElsewhere(.close, observedKeyEquivalent: "w")])
    }

    func testVerifyMenuReportsUnboundCatalogTitle() {
        let items = replacing("Open...", with: item("Open...", "", location: .fileMenu))
        XCTAssertEqual(
            Catalog.verifyMenu(items),
            [.menuItemMissing(.open), .menuItemTitleBoundElsewhere(.open, observedKeyEquivalent: "")])
    }

    func testVerifyMenuReportsDuplicatedChord() {
        let items =
            Self.goodMenu.filter { $0.title != "Save" }
            + [item("Revert", "s", location: .fileMenu), item("Save", "s", location: .fileMenu)]
        let findings = Catalog.verifyMenu(items)
        XCTAssertTrue(findings.contains(.menuItemDuplicated(.save, count: 2)), "\(findings)")
    }

    // MARK: - Helpers

    private static let goodMenu: [Item] = [
        Item(
            title: "Quit MacMerge", keyEquivalent: "q", modifiers: [.command],
            actionSelector: "terminate:", location: .applicationMenu),
        Item(
            title: "New Text Comparison", keyEquivalent: "n", modifiers: [.command],
            actionSelector: "bridge:", location: .fileMenu),
        Item(
            title: "Open...", keyEquivalent: "o", modifiers: [.command],
            actionSelector: "bridge:", location: .fileMenu),
        Item(
            title: "Close", keyEquivalent: "w", modifiers: [.command],
            actionSelector: "bridge:", location: .fileMenu),
        Item(
            title: "Save", keyEquivalent: "s", modifiers: [.command],
            actionSelector: "bridge:", location: .fileMenu)
    ]

    private func replacing(_ title: String, with replacement: Item) -> [Item] {
        Self.goodMenu.map { $0.title == title ? replacement : $0 }
    }

    private func item(
        _ title: String,
        _ key: String,
        action: String? = "bridge:",
        location: Catalog.MenuLocation?
    ) -> Item {
        Item(
            title: title, keyEquivalent: key, modifiers: key.isEmpty ? [] : [.command],
            actionSelector: action, location: location)
    }

    private func verify(
        inventory: ShortcutCoverageAudit.Inventory
    ) throws -> [Catalog.Finding] {
        try Catalog.verifyCatalogConsistency(
            policy: try Policy.makeUnfinishedAudit(), inventory: inventory)
    }

    private func mutatedInventory(
        _ transform: (ShortcutCoverageAudit.Binding) -> ShortcutCoverageAudit.Binding
    ) -> ShortcutCoverageAudit.Inventory {
        let canonical = ShortcutCoverageAudit.Inventory.canonical
        return ShortcutCoverageAudit.Inventory(
            revision: canonical.revision,
            bindings: canonical.bindings.map(transform),
            nativeBindings: canonical.nativeBindings)
    }

    private func rebuild(
        _ binding: ShortcutCoverageAudit.Binding,
        shortcut: MenuShortcutDescriptor,
        policyChord: Policy.Chord
    ) -> ShortcutCoverageAudit.Binding {
        ShortcutCoverageAudit.Binding(
            id: binding.id,
            command: binding.command,
            shortcut: shortcut,
            policyChord: policyChord,
            winMergeReference: binding.winMergeReference,
            policyRequirement: binding.policyRequirement,
            focusedEditorReservation: binding.focusedEditorReservation,
            invocationTargetAction: binding.invocationTargetAction,
            expectedResultID: binding.expectedResultID)
    }

    private func rechord(
        _ entry: Policy.CommandShortcut, _ chord: Policy.Chord
    ) -> Policy.CommandShortcut {
        Policy.CommandShortcut(
            command: entry.command,
            chord: chord,
            enabledLifecycleStates: entry.enabledLifecycleStates,
            requiresDirty: entry.requiresDirty,
            requiresSelection: entry.requiresSelection,
            allowsReadOnly: entry.allowsReadOnly)
    }

    private func makeBinding(
        _ command: Catalog.Command,
        key: Character,
        modifiers: Set<Policy.Modifier> = [.command]
    ) throws -> Catalog.Binding {
        let template = Catalog.binding(for: command)
        return try Catalog.Binding(
            command: command,
            key: key,
            modifiers: modifiers,
            menuTitle: template.menuTitle,
            menuLocation: template.menuLocation,
            menuAction: template.menuAction,
            auditCommand: template.auditCommand)
    }
}
