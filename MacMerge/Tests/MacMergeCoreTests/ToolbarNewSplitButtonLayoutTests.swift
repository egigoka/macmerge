import Foundation
import XCTest

@testable import MacMergeCore

/// Covers how `ToolbarNewSplitButtonPlan` reaches the rendered toolbar through
/// `ToolbarCommandLayout.makeControl(.newComparison)`: menu structure, ids, availability mapping,
/// and dispatch gating on `State.implementedNewCommands`.
final class ToolbarNewSplitButtonLayoutTests: XCTestCase {
    typealias Plan = ToolbarNewSplitButtonPlan
    typealias Layout = ToolbarCommandLayout

    private let twoPaneIDs = [
        "ID_FILE_NEW", "ID_FILE_NEW_TABLE", "ID_FILE_NEW_HEX",
        "ID_FILE_NEW_IMAGE", "ID_FILE_NEW_WEBPAGE", "ID_FILE_NEW_FOLDER"
    ]
    private let threePaneIDs = [
        "ID_FILE_NEW3", "ID_FILE_NEW3_TABLE", "ID_FILE_NEW3_HEX",
        "ID_FILE_NEW3_IMAGE", "ID_FILE_NEW3_WEBPAGE", "ID_FILE_NEW3_FOLDER"
    ]
    private let modeTitles = ["Text", "Table", "Binary", "Image", "Webpage", "Folder"]

    private func newControl(_ state: Layout.State = .freshWindow) throws -> Layout.Control {
        try XCTUnwrap(Layout.make(state: state).control(for: .newComparison))
    }

    // MARK: - Menu structure

    func testMenuIsInlineTwoPaneItemsThenSeparatorThenThreePaneSubmenu() throws {
        let control = try newControl()
        XCTAssertEqual(control.kind, .splitButton)
        XCTAssertTrue(control.hasSecondaryActions)
        // Two-pane items inline, then a separator, then one three-pane submenu.
        XCTAssertEqual(control.menu.count, twoPaneIDs.count + 2)

        let inline = control.menu.prefix(twoPaneIDs.count).map { element -> Layout.MenuItem? in
            if case .item(let item) = element { return item }
            return nil
        }
        XCTAssertEqual(inline.compactMap { $0?.id }, twoPaneIDs)
        XCTAssertEqual(inline.compactMap { $0?.title }, modeTitles)
        XCTAssertEqual(
            inline.compactMap { $0?.accessibilityLabel },
            modeTitles.map { "New \($0) Comparison" })
        XCTAssertTrue(inline.allSatisfy { $0?.systemImage == nil })

        XCTAssertEqual(control.menu[twoPaneIDs.count], .separator)
        guard case .submenu(let id, let title, let elements) = control.menu[twoPaneIDs.count + 1]
        else {
            return XCTFail("Expected three-pane submenu, got \(control.menu[twoPaneIDs.count + 1])")
        }
        XCTAssertEqual(id, Plan.SectionKind.threePane.rawValue)
        XCTAssertEqual(title, "New (3 panes)")
        XCTAssertEqual(elements.count, threePaneIDs.count)
        XCTAssertFalse(elements.contains(.separator))
        XCTAssertEqual(elements.flatMap(\.items).map(\.id), threePaneIDs)
        XCTAssertEqual(elements.flatMap(\.items).map(\.title), modeTitles)
        XCTAssertEqual(
            elements.flatMap(\.items).compactMap(\.accessibilityLabel),
            modeTitles.map { "New 3-Pane \($0) Comparison" })
    }

    func testMenuItemActionsMatchTheirCommandIDs() throws {
        let control = try newControl()
        let allIDs = Plan.CommandID.allCases.map(\.rawValue)
        XCTAssertEqual(control.menuItems.count, allIDs.count, "Every CommandID appears once")
        XCTAssertEqual(Set(control.menuItems.map(\.id)), Set(allIDs))
        for item in control.menuItems {
            let commandID = try XCTUnwrap(Plan.CommandID(rawValue: item.id))
            XCTAssertEqual(item.action, .newDocument(commandID), item.id)
        }
    }

    func testMenuMirrorsPlanEntriesInOrder() throws {
        let state = Layout.State.freshWindow
        let plan = Plan.make(
            isNewCommandEnabled: !state.isWorking,
            implementedCommands: state.implementedNewCommands)
        let control = try newControl(state)
        XCTAssertEqual(control.menuItems.map(\.id), plan.entries.map(\.id))
        XCTAssertEqual(control.menuItems.map(\.title), plan.entries.map(\.title))
        XCTAssertEqual(control.menuItems.map(\.isEnabled), plan.entries.map(\.isEnabled))
    }

    func testPrimaryStringsAndAccessibility() throws {
        let control = try newControl()
        XCTAssertEqual(control.title, "New")
        XCTAssertEqual(control.help, "New Documents (Command-N)")
        XCTAssertEqual(control.accessibilityLabel, "New Documents")
        XCTAssertEqual(control.accessibilityHint, Plan.secondaryActionsAccessibilityHint)
        XCTAssertEqual(control.primaryAction, .newDocument(.twoPaneText))
        XCTAssertEqual(control.systemImage, "doc.badge.plus")
    }

    func testShippedAccessibilityIdentifiersComeFromLayout() throws {
        let control = try newControl()
        let controlID = Layout.accessibilityIdentifier(for: .newComparison)
        XCTAssertEqual(control.accessibilityIdentifier, controlID)
        XCTAssertEqual(
            controlID, ToolbarAccessibilityInventory.controlID(for: .newComparison).rawValue)

        let itemIDs = control.menuItems.map {
            Layout.accessibilityIdentifier(for: $0, in: .newComparison)
        }
        XCTAssertEqual(itemIDs, (twoPaneIDs + threePaneIDs).map { "\(controlID).\($0)" })

        let descriptor = Layout.interactionMatrixDescriptor(for: control)
        XCTAssertEqual(descriptor.secondaryActionIDs.map(\.rawValue), itemIDs)
    }

    // MARK: - Availability

    func testFreshWindowEnablesOnlyImplementedTwoPaneText() throws {
        let control = try newControl()
        XCTAssertEqual(control.availability, .enabled)
        XCTAssertEqual(control.menuItems.filter(\.isEnabled).map(\.id), ["ID_FILE_NEW"])
        let folder = try XCTUnwrap(control.menuItems.first { $0.id == "ID_FILE_NEW_FOLDER" })
        XCTAssertEqual(
            folder.availability,
            .disabled(.newDocument(.notImplemented(mode: .folder, paneCount: .two))))
        let threeText = try XCTUnwrap(control.menuItems.first { $0.id == "ID_FILE_NEW3" })
        XCTAssertEqual(
            threeText.availability,
            .disabled(.newDocument(.notImplemented(mode: .text, paneCount: .three))))
    }

    func testWorkingMapsGateToComparisonWorkingEverywhere() throws {
        let control = try newControl(Layout.State(isWorking: true))
        XCTAssertEqual(control.availability, .disabled(.comparisonWorking))
        XCTAssertEqual(control.menuItems.count, Plan.CommandID.allCases.count)
        XCTAssertTrue(
            control.menuItems.allSatisfy { $0.availability == .disabled(.comparisonWorking) })
    }

    func testDefaultStateUsesCurrentlyImplementedCommands() {
        XCTAssertEqual(Layout.State().implementedNewCommands, Plan.currentlyImplementedCommands)
        XCTAssertEqual(
            Layout.State.freshWindow.implementedNewCommands, Plan.currentlyImplementedCommands)
    }

    func testCustomImplementedSetDrivesEnabledItems() throws {
        let state = Layout.State(implementedNewCommands: [.twoPaneText, .threePaneTable])
        let control = try newControl(state)
        XCTAssertEqual(
            control.menuItems.filter(\.isEnabled).map(\.id), ["ID_FILE_NEW", "ID_FILE_NEW3_TABLE"])
    }

    func testEmptyImplementedSetDisablesPrimaryWithNotImplementedReason() throws {
        let control = try newControl(Layout.State(implementedNewCommands: []))
        XCTAssertEqual(
            control.availability,
            .disabled(.newDocument(.notImplemented(mode: .text, paneCount: .two))))
        XCTAssertTrue(control.menuItems.allSatisfy { !$0.isEnabled })
    }

    func testDisabledPrimaryBlocksImplementedSecondaryActions() throws {
        // Deliberate deviation from WinMerge, whose drop-down arrow stays usable while the
        // primary button is disabled: `ToolbarCommandLayout` gives a split button one
        // availability, taken from the primary command. Unreachable today because `.twoPaneText`
        // is always in `currentlyImplementedCommands`.
        let control = try newControl(Layout.State(implementedNewCommands: [.twoPaneFolder]))
        let reason = Layout.DisabledReason.newDocument(
            .notImplemented(mode: .text, paneCount: .two))
        XCTAssertEqual(control.availability, .disabled(reason))
        XCTAssertEqual(
            Layout.dispatch(.menuItemSelection("ID_FILE_NEW_FOLDER"), to: control),
            .ignored(.controlDisabled(reason)))
        XCTAssertEqual(
            Layout.dispatch(.menuArrowClick, to: control), .ignored(.controlDisabled(reason)))
    }

    // MARK: - Dispatch

    func testPrimaryInteractionsPerformTwoPaneText() {
        let layout = Layout.make(state: .freshWindow)
        for interaction in [Layout.Interaction.primaryClick, .keyboardActivation, .voiceOverPress] {
            XCTAssertEqual(
                layout.dispatch(interaction, to: .newComparison),
                .perform(.newDocument(.twoPaneText)), "\(interaction)")
        }
    }

    func testMenuArrowPresentsFullMenu() throws {
        let layout = Layout.make(state: .freshWindow)
        for interaction in [Layout.Interaction.menuArrowClick, .voiceOverShowMenu] {
            guard case .presentMenu(let menu)? = layout.dispatch(interaction, to: .newComparison)
            else { return XCTFail("\(interaction) did not present a menu") }
            XCTAssertEqual(menu.count, twoPaneIDs.count + 2, "\(interaction)")
            XCTAssertEqual(menu.firstIndex(of: .separator), twoPaneIDs.count, "\(interaction)")
            XCTAssertEqual(menu.flatMap(\.items).map(\.id), twoPaneIDs + threePaneIDs)
        }
    }

    func testMenuSelectionPerformsOnlyImplementedCommands() {
        let layout = Layout.make(state: .freshWindow)
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("ID_FILE_NEW"), to: .newComparison),
            .perform(.newDocument(.twoPaneText)))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("ID_FILE_NEW_HEX"), to: .newComparison),
            .ignored(
                .menuItemDisabled(
                    id: "ID_FILE_NEW_HEX",
                    .newDocument(.notImplemented(mode: .binary, paneCount: .two)))))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("ID_FILE_NEW3_WEBPAGE"), to: .newComparison),
            .ignored(
                .menuItemDisabled(
                    id: "ID_FILE_NEW3_WEBPAGE",
                    .newDocument(.notImplemented(mode: .webpage, paneCount: .three)))))
    }

    func testEveryDispatchedNewActionIsInTheLayoutsImplementedSet() {
        // The app's `perform(.newDocument)` gates on `layout.state.implementedNewCommands`.
        // An action the layout dispatches must therefore be in that same set.
        // Three primary paths plus one selection per menu item.
        let primaryPaths = 3
        let allCount = Plan.CommandID.allCases.count
        let cases: [(state: Layout.State, expectedPerforms: Int)] = [
            (.freshWindow, primaryPaths + 1),
            (Layout.State(implementedNewCommands: []), 0),
            (
                Layout.State(implementedNewCommands: Set(Plan.CommandID.allCases)),
                primaryPaths + allCount
            ),
            (Layout.State(implementedNewCommands: [.threePaneImage]), 0),
            (
                Layout.State(isWorking: true, implementedNewCommands: Set(Plan.CommandID.allCases)),
                0
            )
        ]
        for (state, expectedPerforms) in cases {
            let layout = Layout.make(state: state)
            guard let control = layout.control(for: .newComparison) else {
                return XCTFail("Missing New control")
            }
            let interactions: [Layout.Interaction] =
                [.primaryClick, .keyboardActivation, .voiceOverPress]
                + control.menuItems.map { .menuItemSelection($0.id) }
            var performs = 0
            for interaction in interactions {
                guard
                    case .newDocument(let commandID)? =
                        layout.dispatch(interaction, to: .newComparison)?.performedAction
                else { continue }
                performs += 1
                XCTAssertFalse(state.isWorking)
                XCTAssertTrue(
                    state.implementedNewCommands.contains(commandID),
                    "\(commandID) dispatched but not implemented in \(state)")
            }
            XCTAssertEqual(performs, expectedPerforms, "\(state)")
        }
    }

    func testUnknownMenuItemIsIgnored() {
        let layout = Layout.make(state: .freshWindow)
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("ID_FILE_NEW_BOGUS"), to: .newComparison),
            .ignored(.unknownMenuItem("ID_FILE_NEW_BOGUS")))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("threePane"), to: .newComparison),
            .ignored(.unknownMenuItem("threePane")),
            "Submenu ids are not selectable items")
    }

    func testWorkingIgnoresEveryInteraction() {
        let layout = Layout.make(state: Layout.State(isWorking: true))
        for interaction: Layout.Interaction in [
            .primaryClick, .menuArrowClick, .menuItemSelection("ID_FILE_NEW"),
            .keyboardActivation, .voiceOverPress, .voiceOverShowMenu
        ] {
            XCTAssertEqual(
                layout.dispatch(interaction, to: .newComparison),
                .ignored(.controlDisabled(.comparisonWorking)), "\(interaction)")
        }
    }

    // MARK: - Contracts

    func testSecondaryMenuContractMatchesShippedMenu() throws {
        let control = try newControl()
        let contract = try XCTUnwrap(
            ToolbarCommandOrderSnapshot.secondaryMenuContracts.first {
                $0.command == .newComparison
            })
        XCTAssertEqual(contract.winMergeMenu, "IDR_POPUP_NEW")
        XCTAssertEqual(contract.macItemIDs, control.menuItems.map(\.id))
        XCTAssertNotNil(contract.macException, "The three-pane submenu is a Mac exception")
        XCTAssertTrue(ToolbarCommandOrderSnapshot.splitButtonCommands.contains(.newComparison))
    }

    func testSubmenuIDDoesNotCollideWithAnyItemID() throws {
        let layout = Layout.make(state: .freshWindow)
        let control = try XCTUnwrap(layout.control(for: .newComparison))
        let submenuIDs = control.menu.compactMap { element -> String? in
            if case .submenu(let id, _, _) = element { return id }
            return nil
        }
        XCTAssertEqual(submenuIDs, [Plan.SectionKind.threePane.rawValue])
        let itemIDs = layout.slots.flatMap { slot -> [String] in
            guard case .control(let other) = slot else { return [] }
            return other.menuItems.map(\.id)
        }
        XCTAssertTrue(Set(submenuIDs).isDisjoint(with: itemIDs))
    }
}

/// Edge cases for the plan's value types and resource parsing.
final class ToolbarNewSplitButtonPlanEdgeCaseTests: XCTestCase {
    typealias Plan = ToolbarNewSplitButtonPlan

    func testMnemonicEdgeCases() {
        XCTAssertEqual(Plan.strippingMnemonic(""), "")
        XCTAssertEqual(Plan.strippingMnemonic("&"), "")
        XCTAssertEqual(Plan.strippingMnemonic("&&"), "&")
        XCTAssertEqual(Plan.strippingMnemonic("&A&B"), "AB")
        XCTAssertNil(Plan.mnemonic(in: ""))
        XCTAssertNil(Plan.mnemonic(in: "&"))
        XCTAssertNil(Plan.mnemonic(in: "&&"))
        XCTAssertEqual(Plan.mnemonic(in: "&Alpha"), "a", "Mnemonic is lowercased")
        XCTAssertEqual(Plan.mnemonic(in: "&A&B"), "a", "First marker wins")
        XCTAssertEqual(Plan.mnemonic(in: "x&&&Y"), "y")
    }

    func testResourceTablesHaveUniqueMnemonicsPerMenu() {
        for table in [Plan.toolbarPopupResources, Plan.threePaneResources] {
            let mnemonics = table.compactMap { Plan.mnemonic(in: $0.resourceTitle) }
            XCTAssertEqual(mnemonics.count, table.count)
            XCTAssertEqual(Set(mnemonics).count, table.count)
        }
    }

    func testResourceTablesSplitByPaneCount() {
        XCTAssertTrue(Plan.toolbarPopupResources.allSatisfy { $0.commandID.paneCount == .two })
        XCTAssertTrue(Plan.threePaneResources.allSatisfy { $0.commandID.paneCount == .three })
        XCTAssertEqual(
            Plan.toolbarPopupResources.map(\.commandID.mode),
            Plan.threePaneResources.map(\.commandID.mode))
        XCTAssertEqual(Plan.threePaneSubmenuResourceTitle, "New (&3 panes)")
    }

    func testAccessibilityLabelsAreUniqueAndSelfContained() {
        let labels = Plan.CommandID.allCases.map(Plan.accessibilityLabel(for:))
        XCTAssertEqual(Set(labels).count, Plan.CommandID.allCases.count)
        XCTAssertTrue(labels.allSatisfy { $0.hasPrefix("New ") && $0.hasSuffix(" Comparison") })
    }

    func testSectionIDsAndEntryLookup() throws {
        let plan = Plan.make(isNewCommandEnabled: true)
        XCTAssertEqual(plan.sections.map(\.id), ["twoPane", "threePane"])
        XCTAssertNil(plan.sections[0].resourceTitle)
        XCTAssertEqual(plan.entry(for: .threePaneFolder)?.title, "Folder")
    }

    func testClosedGateWinsOverImplementedSet() {
        let plan = Plan.make(
            isNewCommandEnabled: false, implementedCommands: Set(Plan.CommandID.allCases))
        XCTAssertTrue(plan.entries.allSatisfy { $0.availability == .disabled(.newCommandUnavailable) })
        XCTAssertEqual(plan.primaryAvailability, .disabled(.newCommandUnavailable))
    }

    func testAllImplementedEnablesEverything() {
        let plan = Plan.make(
            isNewCommandEnabled: true, implementedCommands: Set(Plan.CommandID.allCases))
        XCTAssertTrue(plan.entries.allSatisfy(\.isEnabled))
        XCTAssertEqual(plan.primaryAvailability, .enabled)
    }

    func testRepresentsEveryToolbarPopupCommandHoldsForBothVariantsAndGates() {
        for variant in Plan.ThreePaneVariants.allCases {
            for gate in [true, false] {
                let plan = Plan.make(
                    isNewCommandEnabled: gate, implementedCommands: [], threePaneVariants: variant)
                XCTAssertTrue(plan.representsEveryToolbarPopupCommand, "\(variant) \(gate)")
            }
        }
    }

    func testRepresentsEveryToolbarPopupCommandFailsWhenAPopupEntryIsMissing() throws {
        let full = Plan.make(isNewCommandEnabled: true, threePaneVariants: .omitted)
        let section = try XCTUnwrap(full.sections.first)
        let trimmed = Plan(
            primaryCommandID: full.primaryCommandID,
            primaryAvailability: full.primaryAvailability,
            sections: [
                Plan.Section(
                    kind: section.kind, title: section.title, resourceTitle: section.resourceTitle,
                    presentation: section.presentation,
                    entries: section.entries.filter { $0.commandID != .twoPaneImage })
            ])
        XCTAssertFalse(trimmed.representsEveryToolbarPopupCommand)
    }
}
