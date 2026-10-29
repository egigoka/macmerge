import Foundation
import MacMergeCore
import XCTest

/// Guards the New/Open/Save/Close/Quit catalog: exact chords, consistency with the policy,
/// coverage audit, state matrix, and toolbar help, and menu-inventory verification.
final class FileLifecycleShortcutsTests: XCTestCase {
    typealias Catalog = FileLifecycleShortcuts
    typealias Item = FileLifecycleShortcuts.ObservedMenuItem

    func testCatalogDeclaresExactStandardChords() throws {
        let expected: [Catalog.Command: Character] = [
            .new: "n", .open: "o", .save: "s", .close: "w", .quit: "q"
        ]
        XCTAssertEqual(Catalog.bindings.map(\.command), Catalog.Command.allCases)
        for binding in Catalog.bindings {
            XCTAssertEqual(binding.key, expected[binding.command])
            XCTAssertEqual(binding.modifiers, [.command])
            XCTAssertEqual(
                binding.chord,
                try KeyboardShortcutPolicy.Chord(
                    .character(expected[binding.command]!),
                    modifiers: [.command]
                )
            )
        }
        XCTAssertEqual(Catalog.binding(for: .quit).menuAction, .appKitSelector("terminate:"))
        XCTAssertEqual(
            Catalog.binding(for: .close).menuAction, .responderChainSelector("performClose:"))
    }

    func testCatalogIsConsistentWithPolicyAuditAndMatrix() throws {
        let policy = try KeyboardShortcutPolicy.makeUnfinishedAudit()
        XCTAssertEqual(try Catalog.verifyCatalogConsistency(policy: policy), [])
        XCTAssertEqual(Catalog.catalogFindings(Catalog.bindings), [])
    }

    func testMatrixRowsCarryCatalogChords() {
        for binding in Catalog.bindings {
            let row = KeyboardShortcutStateMatrix.canonicalDescriptors.first {
                $0.id == Catalog.matrixShortcutID(binding.command)
            }
            XCTAssertEqual(row?.chord, binding.chord, "\(binding.command)")
        }
    }

    func testMissingMatrixRowIsReported() throws {
        let policy = try KeyboardShortcutPolicy.makeUnfinishedAudit()
        let descriptors = KeyboardShortcutStateMatrix.canonicalDescriptors.filter {
            $0.id != .closeCommandW
        }
        let findings = try Catalog.verifyCatalogConsistency(
            policy: policy, matrixDescriptors: descriptors)
        XCTAssertEqual(findings, [.matrixDescriptorMissing(.close)])
    }

    func testToolbarHelpTextUsesCatalogShortcuts() {
        XCTAssertEqual(Catalog.helpText(.new), "Command-N")
        XCTAssertEqual(Catalog.helpText(.open), "Command-O")
        XCTAssertEqual(Catalog.helpText(.save), "Command-S")
        XCTAssertEqual(ToolbarNewSplitButtonPlan.primaryHelp, "New Documents (Command-N)")
        let layout = ToolbarCommandLayout.make(state: .freshWindow)
        XCTAssertEqual(
            layout.control(for: .openComparison)?.help, "Select files to compare (Command-O)")
        XCTAssertEqual(layout.control(for: .save)?.help, "Save changed files (Command-S)")
    }

    // MARK: - Catalog constraints

    func testCatalogRejectsUppercaseKey() throws {
        var bindings = Catalog.bindings.filter { $0.command != .new }
        bindings.insert(try makeBinding(.new, key: "N"), at: 0)
        XCTAssertEqual(Catalog.catalogFindings(bindings), [.catalogUnsupportedKey(.new, "N")])
    }

    func testCatalogRejectsFunctionModifier() throws {
        var bindings = Catalog.bindings.filter { $0.command != .save }
        bindings.append(try makeBinding(.save, key: "s", modifiers: [.command, .function]))
        XCTAssertEqual(
            Catalog.catalogFindings(bindings), [.catalogUnsupportedModifier(.save, .function)])
    }

    func testCatalogRejectsNonASCIIKeyAtConstruction() {
        XCTAssertThrowsError(try makeBinding(.open, key: "ö"))
    }

    func testCatalogReportsDuplicateChordAndMissingCommand() throws {
        var bindings = Catalog.bindings.filter { $0.command != .close }
        bindings.append(try makeBinding(.save, key: "q"))
        XCTAssertEqual(
            Set(Catalog.catalogFindings(bindings)),
            [
                .catalogDuplicateCommand(.save),
                .catalogDuplicateChord(.quit, .save),
                .catalogMissingCommand(.close)
            ])
    }

    // MARK: - Menu verification

    func testVerifyMenuAcceptsStandardInventory() {
        XCTAssertEqual(Catalog.verifyMenu(Self.goodMenu), [])
    }

    func testVerifyMenuReportsMissingItem() {
        let items = Self.goodMenu.filter { $0.title != "Close" }
        XCTAssertEqual(Catalog.verifyMenu(items), [.menuItemMissing(.close)])
    }

    func testVerifyMenuReportsDuplicateBinding() {
        let items = Self.goodMenu + [item("Save", "s", location: .fileMenu)]
        XCTAssertEqual(Catalog.verifyMenu(items), [.menuItemDuplicated(.save, count: 2)])
    }

    func testVerifyMenuReportsWrongTitleAndLocation() {
        let items = Self.goodMenu.map { item -> Item in
            guard item.title == "Open..." else { return item }
            return self.item("Open Recent", "o", location: nil)
        }
        XCTAssertEqual(
            Catalog.verifyMenu(items),
            [
                .menuItemTitleMismatch(.open, observed: "Open Recent"),
                .menuItemLocationMismatch(.open, observed: nil)
            ])
    }

    func testVerifyMenuReportsWrongQuitSelector() {
        let items = Self.goodMenu.map { item -> Item in
            guard item.title.hasPrefix("Quit") else { return item }
            return self.item(item.title, "q", action: "hide:", location: .applicationMenu)
        }
        XCTAssertEqual(
            Catalog.verifyMenu(items), [.menuItemActionMismatch(.quit, observed: "hide:")])
    }

    func testVerifyMenuTreatsUppercaseKeyEquivalentAsShift() {
        let items = Self.goodMenu.map { item -> Item in
            guard item.title == "New Text Comparison" else { return item }
            return self.item(item.title, "N", location: .fileMenu)
        }
        XCTAssertEqual(
            Catalog.verifyMenu(items),
            [
                .menuItemMissing(.new),
                .menuItemTitleBoundElsewhere(.new, observedKeyEquivalent: "N")
            ])
    }

    func testVerifyMenuRejectsOversizedInventory() {
        let items = Array(
            repeating: item("x", "", location: nil),
            count: Catalog.maximumObservedMenuItems + 1)
        XCTAssertEqual(
            Catalog.verifyMenu(items),
            [.menuInventoryTooLarge(maximum: Catalog.maximumObservedMenuItems)])
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
            actionSelector: "bridge:", location: .fileMenu),
        Item(
            title: "Save Left", keyEquivalent: "", modifiers: [],
            actionSelector: "bridge:", location: .fileMenu)
    ]

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

    private func makeBinding(
        _ command: Catalog.Command,
        key: Character,
        modifiers: Set<KeyboardShortcutPolicy.Modifier> = [.command]
    ) throws -> Catalog.Binding {
        let template = Catalog.binding(for: command)
        return try Catalog.Binding(
            command: command,
            key: key,
            modifiers: modifiers,
            menuTitle: template.menuTitle,
            menuLocation: template.menuLocation,
            menuAction: template.menuAction,
            auditCommand: template.auditCommand
        )
    }
}
