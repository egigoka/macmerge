import XCTest

@testable import MacMergeCore

/// Lane 3 edge-case coverage for `ToolbarCommandLayout` and `ToolbarCommandOrderSnapshot`:
/// working gates, per-side save gates, New routing from the layout state, dispatch error paths,
/// identifier scheme, grouping edge cases, and divergence bounds.
final class ToolbarCommandLayoutLaneTests: XCTestCase {
    private typealias Layout = ToolbarCommandLayout
    private typealias Snapshot = ToolbarCommandOrderSnapshot
    private typealias Command = ToolbarConfiguration.Command

    private static let allEnabled = Layout.State(
        isLeftLoaded: true, isRightLoaded: true, canSaveLeft: true, canSaveRight: true,
        hasUnsavedChanges: true, canUndo: true, canRedo: true, canSelectLineDifference: true,
        hasNavigableDifferences: true, canSelectNextDifference: true,
        canSelectPreviousDifference: true, canSelectCurrentDifference: true,
        canCopyToRight: true, canCopyToLeft: true, canCopyToRightAndAdvance: true,
        canCopyToLeftAndAdvance: true, canCopyAllToRight: true, canCopyAllToLeft: true,
        canRefresh: true)

    private static let threePaneOrFolderOnly: Set<Command> = [
        .nextConflict, .previousConflict, .autoMerge, .firstComparedFile,
        .previousComparedFile, .nextComparedFile, .lastComparedFile
    ]

    // MARK: - Layout shape

    func testEveryConfiguredCommandHasExactlyOneControl() {
        let layout = Layout.make(state: .freshWindow)
        XCTAssertEqual(layout.controls.map(\.command), ToolbarConfiguration.winMergeDefault.commands)
        XCTAssertEqual(Set(layout.controls.map(\.command)).count, layout.controls.count)
        XCTAssertEqual(layout.slots.count, ToolbarConfiguration.winMergeDefaultItems.count)
    }

    func testOnlyNewOpenSaveAreSplitButtonsAndOnlyThoseHaveMenus() {
        let layout = Layout.make(state: Self.allEnabled)
        for control in layout.controls {
            let isSplit = [Command.newComparison, .openComparison, .save].contains(control.command)
            XCTAssertEqual(control.kind, isSplit ? .splitButton : .button, "\(control.command)")
            XCTAssertEqual(control.hasSecondaryActions, isSplit)
            XCTAssertEqual(control.menu.isEmpty, !isSplit, "\(control.command)")
            XCTAssertEqual(control.accessibilityHint != nil, isSplit, "\(control.command)")
        }
    }

    func testOptionsIsAnEnabledPlainButtonWithoutHintInEveryState() throws {
        var working = Self.allEnabled
        working.isWorking = true
        for state in [Layout.State.freshWindow, Self.allEnabled, working] {
            let options = try XCTUnwrap(Layout.make(state: state).control(for: .options))
            XCTAssertEqual(options.kind, .button)
            XCTAssertTrue(options.isEnabled)
            XCTAssertNil(options.accessibilityHint)
            XCTAssertEqual(options.primaryAction, .openOptions)
        }
    }

    // MARK: - Accessibility identifiers

    func testAccessibilityIdentifiersUseOneSchemeIncludingNew() {
        let layout = Layout.make(state: .freshWindow)
        for control in layout.controls {
            XCTAssertEqual(control.accessibilityIdentifier, "toolbar.\(control.command.rawValue)")
            XCTAssertEqual(
                control.accessibilityIdentifier, Layout.accessibilityIdentifier(for: control.command))
            for item in control.menuItems {
                XCTAssertEqual(
                    Layout.accessibilityIdentifier(for: item, in: control.command),
                    "toolbar.\(control.command.rawValue).\(item.id)")
            }
        }
        XCTAssertEqual(
            layout.control(for: .newComparison)?.accessibilityIdentifier,
            "toolbar.newComparison")
        XCTAssertFalse(layout.controls.contains { $0.accessibilityIdentifier.contains("ID_FILE") })
    }

    func testIdentifiersAndMenuItemIDsAreUnique() {
        let layout = Layout.make(state: Self.allEnabled)
        let ids = layout.controls.map(\.accessibilityIdentifier)
        XCTAssertEqual(Set(ids).count, ids.count)
        for control in layout.controls {
            let itemIDs = control.menuItems.map(\.id)
            XCTAssertEqual(Set(itemIDs).count, itemIDs.count, "\(control.command)")
        }
    }

    // MARK: - Availability gates

    func testWorkingDisablesEveryControlExceptOptions() {
        var state = Self.allEnabled
        state.isWorking = true
        let layout = Layout.make(state: state)
        for control in layout.controls {
            if control.command == .options {
                XCTAssertTrue(control.isEnabled)
            } else if Self.threePaneOrFolderOnly.contains(control.command) {
                XCTAssertFalse(control.isEnabled, "\(control.command)")
            } else {
                XCTAssertEqual(
                    control.availability, .disabled(.comparisonWorking), "\(control.command)")
            }
        }
    }

    func testAllEnabledStateEnablesEverythingButThreePaneAndFolderCommands() {
        let layout = Layout.make(state: Self.allEnabled)
        for control in layout.controls {
            XCTAssertEqual(
                control.isEnabled, !Self.threePaneOrFolderOnly.contains(control.command),
                "\(control.command)")
        }
        XCTAssertEqual(
            layout.control(for: .autoMerge)?.availability,
            .disabled(.requiresThreePaneComparison))
        XCTAssertEqual(
            layout.control(for: .nextConflict)?.availability,
            .disabled(.requiresThreePaneConflictComparison))
        XCTAssertEqual(
            layout.control(for: .lastComparedFile)?.availability,
            .disabled(.requiresFolderComparison))
    }

    func testFreshWindowDisabledReasons() {
        let layout = Layout.make(state: .freshWindow)
        let expected: [Command: Layout.DisabledReason] = [
            .save: .nothingLoaded,
            .undo: .nothingToUndo,
            .redo: .nothingToRedo,
            .selectLineDifference: .noLineDifference,
            .nextDifference: .noDifferences,
            .previousDifference: .noDifferences,
            .nextConflict: .requiresThreePaneConflictComparison,
            .previousConflict: .requiresThreePaneConflictComparison,
            .firstDifference: .noDifferences,
            .currentDifference: .noCurrentDifference,
            .lastDifference: .noDifferences,
            .copyToRight: .mergeUnavailable,
            .copyToLeft: .mergeUnavailable,
            .copyToRightAndAdvance: .mergeUnavailable,
            .copyToLeftAndAdvance: .mergeUnavailable,
            .copyAllToRight: .mergeUnavailable,
            .copyAllToLeft: .mergeUnavailable,
            .autoMerge: .requiresThreePaneComparison,
            .firstComparedFile: .requiresFolderComparison,
            .previousComparedFile: .requiresFolderComparison,
            .nextComparedFile: .requiresFolderComparison,
            .lastComparedFile: .requiresFolderComparison,
            .refresh: .comparisonNotReady
        ]
        // Every disabled control needs a row; every other control must be enabled.
        var actual: [Command: Layout.DisabledReason] = [:]
        for control in layout.controls {
            if let reason = control.availability.disabledReason { actual[control.command] = reason }
        }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(
            Set(layout.controls.filter(\.isEnabled).map(\.command)),
            [.newComparison, .openComparison, .options])
    }

    func testNavigationWithDifferencesButNoAdjacentTarget() {
        var state = Layout.State.freshWindow
        state.hasNavigableDifferences = true
        let layout = Layout.make(state: state)
        XCTAssertEqual(
            layout.control(for: .nextDifference)?.availability, .disabled(.noAdjacentDifference))
        XCTAssertEqual(
            layout.control(for: .previousDifference)?.availability,
            .disabled(.noAdjacentDifference))
        XCTAssertTrue(layout.control(for: .firstDifference)?.isEnabled ?? false)
        XCTAssertTrue(layout.control(for: .lastDifference)?.isEnabled ?? false)
    }

    func testSaveWithOneSideLoadedGatesItemsPerSide() throws {
        var state = Layout.State.freshWindow
        state.isLeftLoaded = true
        state.canSaveLeft = true
        state.hasUnsavedChanges = true
        let save = try XCTUnwrap(Layout.make(state: state).control(for: .save))
        XCTAssertTrue(save.isEnabled)
        let items = Dictionary(uniqueKeysWithValues: save.menuItems.map { ($0.id, $0) })
        XCTAssertEqual(items["saveLeft"]?.availability, .enabled)
        XCTAssertEqual(items["saveRight"]?.availability, .disabled(.sideNotLoaded))
        XCTAssertEqual(items["saveLeftAs"]?.availability, .enabled)
        XCTAssertEqual(items["saveRightAs"]?.availability, .disabled(.sideNotLoaded))
    }

    func testSaveDisabledWhenLoadedButUnmodifiedEvenIfSidesSavable() throws {
        var state = Self.allEnabled
        state.hasUnsavedChanges = false
        let save = try XCTUnwrap(Layout.make(state: state).control(for: .save))
        XCTAssertEqual(save.availability, .disabled(.nothingToSave))
        // Items stay individually gated, but the disabled control blocks every interaction.
        XCTAssertEqual(
            Layout.dispatch(.menuItemSelection("saveLeft"), to: save),
            .ignored(.controlDisabled(.nothingToSave)))
        XCTAssertEqual(
            Layout.dispatch(.menuArrowClick, to: save),
            .ignored(.controlDisabled(.nothingToSave)))
    }

    // MARK: - New routing uses layout state

    func testNewMenuDisablesUnimplementedCommands() throws {
        let control = try XCTUnwrap(Layout.make(state: .freshWindow).control(for: .newComparison))
        XCTAssertEqual(control.primaryAction, .newDocument(.twoPaneText))
        let folder = try XCTUnwrap(control.menuItems.first { $0.id == "ID_FILE_NEW_FOLDER" })
        XCTAssertFalse(folder.isEnabled)
        guard case .disabled(.newDocument(.notImplemented)) = folder.availability else {
            return XCTFail("Expected notImplemented, got \(folder.availability)")
        }
        let reason = try XCTUnwrap(folder.availability.disabledReason)
        XCTAssertEqual(
            Layout.dispatch(.menuItemSelection("ID_FILE_NEW_FOLDER"), to: control),
            .ignored(.menuItemDisabled(id: "ID_FILE_NEW_FOLDER", reason)))
    }

    func testNewMenuFollowsStateImplementedCommandsNotStaticSet() throws {
        var state = Layout.State.freshWindow
        state.implementedNewCommands = [.twoPaneText, .twoPaneFolder]
        let layout = Layout.make(state: state)
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("ID_FILE_NEW_FOLDER"), to: .newComparison),
            .perform(.newDocument(.twoPaneFolder)))
        XCTAssertEqual(layout.state.implementedNewCommands, [.twoPaneText, .twoPaneFolder])
        // Static set unchanged: the app must route by the layout state.
        XCTAssertFalse(
            ToolbarNewSplitButtonPlan.currentlyImplementedCommands.contains(.twoPaneFolder))
    }

    func testNewWithEmptyImplementedSetDisablesPrimary() throws {
        var state = Layout.State.freshWindow
        state.implementedNewCommands = []
        let control = try XCTUnwrap(Layout.make(state: state).control(for: .newComparison))
        XCTAssertFalse(control.isEnabled)
        XCTAssertTrue(control.menuItems.allSatisfy { !$0.isEnabled })
        guard
            case .ignored(.controlDisabled(.newDocument)) =
                Layout.dispatch(.primaryClick, to: control)
        else { return XCTFail("Primary click must be ignored") }
    }

    func testNewWhileWorkingMapsToComparisonWorking() throws {
        var state = Layout.State.freshWindow
        state.isWorking = true
        let control = try XCTUnwrap(Layout.make(state: state).control(for: .newComparison))
        XCTAssertEqual(control.availability, .disabled(.comparisonWorking))
        XCTAssertTrue(
            control.menuItems.allSatisfy {
                $0.availability == .disabled(.comparisonWorking)
            })
    }

    func testNewMenuItemSelectionFromThreePaneSubmenuResolvesNested() throws {
        var state = Layout.State.freshWindow
        state.implementedNewCommands = [.twoPaneText, .threePaneText]
        let layout = Layout.make(state: state)
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("ID_FILE_NEW3"), to: .newComparison),
            .perform(.newDocument(.threePaneText)))
    }

    // MARK: - Dispatch error paths

    func testDispatchReturnsNilForCommandAbsentFromLayout() throws {
        var items = ToolbarConfiguration.winMergeDefaultItems
        items.removeAll { $0 == .command(.save) }
        let configuration = try ToolbarConfiguration(items: items)
        let layout = Layout.make(state: Self.allEnabled, configuration: configuration)
        XCTAssertNil(layout.control(for: .save))
        XCTAssertNil(layout.dispatch(.primaryClick, to: .save))
        XCTAssertNil(layout.dispatch(.menuItemSelection("saveLeft"), to: .save))
    }

    func testMenuItemSelectionOnPlainButtonIsIgnored() {
        let layout = Layout.make(state: Self.allEnabled)
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("anything"), to: .undo),
            .ignored(.noSecondaryActions))
        XCTAssertEqual(
            layout.dispatch(.voiceOverShowMenu, to: .refresh), .ignored(.noSecondaryActions))
    }

    func testUnknownAndEmptyMenuItemIDsAreIgnored() {
        let layout = Layout.make(state: Self.allEnabled)
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection(""), to: .openComparison),
            .ignored(.unknownMenuItem("")))
        // Separator tokens and submenu ids are not selectable items.
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("-"), to: .save), .ignored(.unknownMenuItem("-")))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("threePane"), to: .newComparison),
            .ignored(.unknownMenuItem("threePane")))
    }

    func testDisabledControlIgnoresEveryInteractionKind() throws {
        let undo = try XCTUnwrap(Layout.make(state: .freshWindow).control(for: .undo))
        for interaction: Layout.Interaction in [
            .primaryClick, .menuArrowClick, .menuItemSelection("x"), .keyboardActivation,
            .voiceOverPress, .voiceOverShowMenu
        ] {
            XCTAssertEqual(
                Layout.dispatch(interaction, to: undo),
                .ignored(.controlDisabled(.nothingToUndo)), "\(interaction)")
        }
    }

    func testNativeInteractionsMirrorPrimaryAndMenuRows() {
        let layout = Layout.make(state: Self.allEnabled)
        for control in layout.controls where control.isEnabled {
            let primary = Layout.dispatch(.primaryClick, to: control)
            XCTAssertEqual(Layout.dispatch(.keyboardActivation, to: control), primary)
            XCTAssertEqual(Layout.dispatch(.voiceOverPress, to: control), primary)
            XCTAssertEqual(
                Layout.dispatch(.voiceOverShowMenu, to: control),
                Layout.dispatch(.menuArrowClick, to: control))
            XCTAssertEqual(primary.performedAction, control.primaryAction)
        }
    }

    func testEveryEnabledMenuItemPerformsItsOwnAction() {
        let layout = Layout.make(state: Self.allEnabled)
        for control in layout.controls {
            for item in control.menuItems where item.isEnabled {
                XCTAssertEqual(
                    Layout.dispatch(.menuItemSelection(item.id), to: control),
                    .perform(item.action), "\(control.command).\(item.id)")
            }
        }
    }

    func testPerformedActionIsNilForNonPerformOutcomes() {
        XCTAssertNil(Layout.InteractionOutcome.presentMenu([]).performedAction)
        XCTAssertNil(Layout.InteractionOutcome.ignored(.noSecondaryActions).performedAction)
        XCTAssertEqual(Layout.InteractionOutcome.perform(.undo).performedAction, .undo)
    }

    func testCopyAllRequestsConfirmationInsteadOfDirectCopy() {
        let layout = Layout.make(state: Self.allEnabled)
        XCTAssertEqual(layout.control(for: .copyAllToRight)?.primaryAction, .requestCopyAllToRight)
        XCTAssertEqual(layout.control(for: .copyAllToLeft)?.primaryAction, .requestCopyAllToLeft)
    }

    // MARK: - Snapshot grouping edges

    func testLeadingTrailingAndAdjacentSeparatorsPreserveEmptyGroups() throws {
        let configuration = try ToolbarConfiguration(items: [
            .separator, .command(.undo), .separator, .separator, .command(.redo), .separator
        ])
        let snapshot = Layout.make(state: .freshWindow, configuration: configuration).orderSnapshot
        XCTAssertEqual(snapshot.groups.map { $0.map(\.command) }, [[], [.undo], [], [.redo], []])
        XCTAssertEqual(snapshot.orderSignature, " | undo |  | redo | ")
        XCTAssertEqual(snapshot.items, configuration.items)
    }

    func testEmptyConfigurationProducesOneEmptyGroup() throws {
        let configuration = try ToolbarConfiguration(items: [])
        let snapshot = Layout.make(state: .freshWindow, configuration: configuration).orderSnapshot
        XCTAssertEqual(snapshot.groups.count, 1)
        XCTAssertTrue(snapshot.groups[0].isEmpty)
        XCTAssertEqual(snapshot.orderSignature, "")
        XCTAssertEqual(snapshot.stateSignature, "")
        XCTAssertTrue(snapshot.presentationLines.isEmpty)
    }

    func testStateSignatureChangesWhenOnlyEnablementChanges() {
        var state = Self.allEnabled
        let before = Layout.make(state: state).orderSnapshot
        state.canRedo = false
        let after = Layout.make(state: state).orderSnapshot
        XCTAssertEqual(before.orderSignature, after.orderSignature)
        XCTAssertNotEqual(before.stateSignature, after.stateSignature)
        XCTAssertTrue(before.stateSignature.contains("redo[button,on]"))
        XCTAssertTrue(after.stateSignature.contains("redo[button,off]"))
    }

    func testSnapshotAccessibilityLabelFallsBackToTitle() {
        let snapshot = Layout.make(state: .freshWindow).orderSnapshot
        let entries = Dictionary(
            uniqueKeysWithValues: snapshot.groups.joined().map {
                ($0.command, $0)
            })
        XCTAssertEqual(entries[.newComparison]?.accessibilityLabel, "New Documents")
        XCTAssertEqual(entries[.newComparison]?.title, "New")
        XCTAssertEqual(entries[.refresh]?.accessibilityLabel, "Refresh")
        XCTAssertEqual(entries[.save]?.menuItemIDs, ["saveLeft", "saveRight", "saveLeftAs", "saveRightAs"])
    }

    // MARK: - Divergence bounds

    func testDivergencesReportExtraAndMissingTrailingSlots() throws {
        let reference = ToolbarConfiguration.winMergeDefaultItems
        var shorter = reference
        let removed = shorter.removeLast()
        let shortSnapshot = Layout.make(
            state: .freshWindow, configuration: try ToolbarConfiguration(items: shorter)
        ).orderSnapshot
        XCTAssertTrue(
            shortSnapshot.divergences().contains(
                .slotMismatch(index: reference.count - 1, expected: removed, actual: nil)))

        let longer = reference + [.separator]
        let longSnapshot = Layout.make(
            state: .freshWindow, configuration: try ToolbarConfiguration(items: longer)
        ).orderSnapshot
        XCTAssertTrue(
            longSnapshot.divergences().contains(
                .slotMismatch(index: reference.count, expected: nil, actual: .separator)))
    }

    func testRemovedSplitCommandIsNotReportedAsMissingDropDown() throws {
        let configuration = try ToolbarConfiguration(items: [.command(.undo)])
        let snapshot = Layout.make(state: .freshWindow, configuration: configuration).orderSnapshot
        let divergences = snapshot.divergences(from: [.command(.undo)])
        XCTAssertEqual(divergences, [])
    }

    func testMenuContractItemIDsMatchRenderedMenusForEveryState() {
        var working = Self.allEnabled
        working.isWorking = true
        for state in [Layout.State.freshWindow, Self.allEnabled, working] {
            let layout = Layout.make(state: state)
            for contract in Snapshot.secondaryMenuContracts {
                guard let expected = contract.macItemIDs else {
                    XCTAssertEqual(contract.command, .options)
                    continue
                }
                XCTAssertEqual(
                    layout.control(for: contract.command)?.menuItems.map(\.id), expected,
                    "\(contract.command)")
            }
        }
    }

    // MARK: - Copy titles

    func testCopyTitlesAreDistinctAndOnlyForCopyCommands() {
        let titles = Command.allCases.compactMap { Layout.copyTitle(for: $0) }
        XCTAssertEqual(titles.count, 6)
        XCTAssertEqual(Set(titles).count, 6)
    }
}
