import XCTest

@testable import MacMergeCore

final class ToolbarCommandLayoutTests: XCTestCase {
    private typealias Layout = ToolbarCommandLayout
    private typealias Snapshot = ToolbarCommandOrderSnapshot

    private static let loaded = Layout.State(
        isLeftLoaded: true, isRightLoaded: true, canSaveLeft: true, canSaveRight: false,
        hasUnsavedChanges: true, canUndo: true, canRedo: false, canSelectLineDifference: true,
        hasNavigableDifferences: true, canSelectNextDifference: true,
        canSelectPreviousDifference: false, canSelectCurrentDifference: true,
        canCopyToRight: true, canCopyToLeft: true, canCopyToRightAndAdvance: true,
        canCopyToLeftAndAdvance: true, canCopyAllToRight: true, canCopyAllToLeft: true,
        canRefresh: true)

    private static let orderGolden =
        "newComparison openComparison save | undo redo | selectLineDifference | "
        + "nextDifference previousDifference | nextConflict previousConflict | "
        + "firstDifference currentDifference lastDifference | copyToRight copyToLeft | "
        + "copyToRightAndAdvance copyToLeftAndAdvance | copyAllToRight copyAllToLeft | "
        + "autoMerge | firstComparedFile previousComparedFile nextComparedFile lastComparedFile | "
        + "options | refresh | "

    private static let newMenuGolden =
        "ID_FILE_NEW,!ID_FILE_NEW_TABLE,!ID_FILE_NEW_HEX,!ID_FILE_NEW_IMAGE,!ID_FILE_NEW_WEBPAGE,"
        + "!ID_FILE_NEW_FOLDER,-,threePane>,!ID_FILE_NEW3,!ID_FILE_NEW3_TABLE,!ID_FILE_NEW3_HEX,"
        + "!ID_FILE_NEW3_IMAGE,!ID_FILE_NEW3_WEBPAGE,!ID_FILE_NEW3_FOLDER,<"

    // MARK: - Order and grouping

    func testOrderSignatureGoldenIsSharedByFreshAndLoadedWindows() {
        let fresh = Layout.make(state: .freshWindow).orderSnapshot
        let loaded = Layout.make(state: Self.loaded).orderSnapshot
        XCTAssertEqual(fresh.orderSignature, Self.orderGolden)
        XCTAssertEqual(loaded.orderSignature, Self.orderGolden)
    }

    func testOrderMatchesMainframeToolbarParsedFromMerge2RC() throws {
        let lines = try Self.winMergeSource("Src/Merge2.rc").components(separatedBy: .newlines)
        let start = try XCTUnwrap(
            lines.firstIndex { $0.hasPrefix("IDR_MAINFRAME") && $0.contains("TOOLBAR") },
            "IDR_MAINFRAME TOOLBAR not found")
        var parsed: [ToolbarConfiguration.Item] = []
        for line in lines[(start + 1)...] {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let keyword = tokens.first, keyword != "BEGIN" else { continue }
            if keyword == "END" { break }
            if keyword == "SEPARATOR" {
                parsed.append(.separator)
            } else if keyword == "BUTTON", tokens.count > 1 {
                let command = try XCTUnwrap(
                    Self.winMergeCommandIDs[tokens[1]], "Unmapped toolbar id \(tokens[1])")
                parsed.append(.command(command))
            }
        }
        XCTAssertEqual(parsed.count, 39)
        XCTAssertEqual(Layout.make(state: .freshWindow).orderSnapshot.items, parsed)
        XCTAssertEqual(Layout.make(state: Self.loaded).orderSnapshot.items, parsed)
        XCTAssertEqual(
            Layout.make(state: .freshWindow).orderSnapshot.divergences(from: parsed),
            [.missingSecondaryActions(.options)])
    }

    func testReorderedConfigurationChangesSignatureAndReportsSlotMismatch() throws {
        var items = ToolbarConfiguration.winMergeDefaultItems
        items.swapAt(0, 1)
        let configuration = try ToolbarConfiguration(items: items)
        let snapshot = Layout.make(state: .freshWindow, configuration: configuration).orderSnapshot
        XCTAssertNotEqual(snapshot.orderSignature, Self.orderGolden)
        XCTAssertTrue(
            snapshot.divergences().contains(
                .slotMismatch(
                    index: 0, expected: .command(.newComparison), actual: .command(.openComparison))))
    }

    func testStateSignatureGoldensForFreshAndLoadedWindows() {
        let fresh = Layout.make(state: .freshWindow).orderSnapshot.stateSignature
        let loaded = Layout.make(state: Self.loaded).orderSnapshot.stateSignature
        XCTAssertEqual(
            fresh,
            "newComparison[splitButton,on:\(Self.newMenuGolden)] "
                + "openComparison[splitButton,on:openComparison,-,openLeft,openRight] "
                + "save[splitButton,off:!saveLeft,!saveRight,-,!saveLeftAs,!saveRightAs] | "
                + "undo[button,off] redo[button,off] | selectLineDifference[button,off] | "
                + "nextDifference[button,off] previousDifference[button,off] | "
                + "nextConflict[button,off] previousConflict[button,off] | "
                + "firstDifference[button,off] currentDifference[button,off] "
                + "lastDifference[button,off] | copyToRight[button,off] copyToLeft[button,off] | "
                + "copyToRightAndAdvance[button,off] copyToLeftAndAdvance[button,off] | "
                + "copyAllToRight[button,off] copyAllToLeft[button,off] | autoMerge[button,off] | "
                + "firstComparedFile[button,off] previousComparedFile[button,off] "
                + "nextComparedFile[button,off] lastComparedFile[button,off] | "
                + "options[button,on] | refresh[button,off] | ")
        XCTAssertEqual(
            loaded,
            "newComparison[splitButton,on:\(Self.newMenuGolden)] "
                + "openComparison[splitButton,on:openComparison,-,openLeft,openRight] "
                + "save[splitButton,on:saveLeft,!saveRight,-,saveLeftAs,saveRightAs] | "
                + "undo[button,on] redo[button,off] | selectLineDifference[button,on] | "
                + "nextDifference[button,on] previousDifference[button,off] | "
                + "nextConflict[button,off] previousConflict[button,off] | "
                + "firstDifference[button,on] currentDifference[button,on] "
                + "lastDifference[button,on] | copyToRight[button,on] copyToLeft[button,on] | "
                + "copyToRightAndAdvance[button,on] copyToLeftAndAdvance[button,on] | "
                + "copyAllToRight[button,on] copyAllToLeft[button,on] | autoMerge[button,off] | "
                + "firstComparedFile[button,off] previousComparedFile[button,off] "
                + "nextComparedFile[button,off] lastComparedFile[button,off] | "
                + "options[button,on] | refresh[button,on] | ")
    }

    func testPresentationGoldenCoversTitlesIdentifiersHintsAndHelp() {
        let lines = Layout.make(state: .freshWindow).orderSnapshot.presentationLines
        XCTAssertEqual(lines, Self.presentationGolden)
        // Presentation text does not depend on state.
        XCTAssertEqual(Layout.make(state: Self.loaded).orderSnapshot.presentationLines, lines)
    }

    // MARK: - WinMerge drop-down parity

    func testDivergencesReportOnlyMissingOptionsDropDown() {
        let divergences = Layout.make(state: .freshWindow).orderSnapshot.divergences()
        XCTAssertEqual(divergences, [.missingSecondaryActions(.options)])
    }

    func testSplitButtonCommandsMatchDropDownLoopParsedFromMainFrm() throws {
        let source = try Self.winMergeSource("Src/MainFrm.cpp")
        let loop = try XCTUnwrap(
            source.components(separatedBy: .newlines).first {
                $0.contains("for (auto cmd : {") && $0.contains("ID_FILE_NEW")
            }, "TBSTYLE_DROPDOWN loop not found")
        let open = try XCTUnwrap(loop.firstIndex(of: "{"))
        let close = try XCTUnwrap(loop.lastIndex(of: "}"))
        let ids = loop[loop.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let commands = try ids.map {
            try XCTUnwrap(Self.winMergeCommandIDs[$0], "Unmapped drop-down id \($0)")
        }
        XCTAssertEqual(Snapshot.splitButtonCommands, commands)
    }

    func testNewMenuContractIsALiteralWinMergeIDList() throws {
        // Literal so the contract and the rendered menu cannot both drift through the plan.
        let contract = try XCTUnwrap(
            Snapshot.secondaryMenuContracts.first { $0.command == .newComparison })
        XCTAssertEqual(
            contract.macItemIDs,
            [
                "ID_FILE_NEW", "ID_FILE_NEW_TABLE", "ID_FILE_NEW_HEX", "ID_FILE_NEW_IMAGE",
                "ID_FILE_NEW_WEBPAGE", "ID_FILE_NEW_FOLDER", "ID_FILE_NEW3", "ID_FILE_NEW3_TABLE",
                "ID_FILE_NEW3_HEX", "ID_FILE_NEW3_IMAGE", "ID_FILE_NEW3_WEBPAGE", "ID_FILE_NEW3_FOLDER"
            ])
    }

    func testEveryWinMergeDropDownHasASecondaryMenuContract() {
        XCTAssertEqual(
            Snapshot.secondaryMenuContracts.map(\.command), Snapshot.splitButtonCommands)
        let menus = Dictionary(
            uniqueKeysWithValues: Snapshot.secondaryMenuContracts.map { ($0.command, $0.winMergeMenu) })
        XCTAssertEqual(menus[.options], "IDR_POPUP_DIFF_OPTIONS")
        XCTAssertEqual(menus[.newComparison], "IDR_POPUP_NEW")
        XCTAssertEqual(menus[.openComparison], "IDR_POPUP_OPEN")
        XCTAssertEqual(menus[.save], "IDR_POPUP_SAVE")
        for contract in Snapshot.secondaryMenuContracts where contract.command != .options {
            XCTAssertNotNil(contract.macException, "\(contract.command) needs a documented exception")
        }
    }

    func testMenuContentRegressionIsReported() throws {
        let layout = Layout.make(state: Self.loaded)
        let slots = layout.slots.map { slot -> Layout.Slot in
            guard let control = slot.control, control.command == .save else { return slot }
            return .control(
                Layout.Control(
                    command: control.command, kind: control.kind, title: control.title,
                    systemImage: control.systemImage, help: control.help,
                    accessibilityLabel: control.accessibilityLabel,
                    accessibilityHint: control.accessibilityHint,
                    accessibilityIdentifier: control.accessibilityIdentifier,
                    primaryAction: control.primaryAction, availability: control.availability,
                    menu: Array(control.menu.prefix(2))))
        }
        let snapshot = Layout(
            state: layout.state, configuration: layout.configuration, slots: slots
        ).orderSnapshot
        XCTAssertTrue(
            snapshot.divergences().contains(
                .secondaryMenuMismatch(
                    .save, expected: ["saveLeft", "saveRight", "saveLeftAs", "saveRightAs"],
                    actual: ["saveLeft", "saveRight"])))
    }

    // MARK: - Availability

    func testSaveRequiresUnsavedChangesLikeWinMerge() throws {
        var state = Self.loaded
        state.hasUnsavedChanges = false
        let control = try XCTUnwrap(Layout.make(state: state).control(for: .save))
        XCTAssertEqual(control.availability, .disabled(.nothingToSave))
        let fresh = try XCTUnwrap(Layout.make(state: .freshWindow).control(for: .save))
        XCTAssertEqual(fresh.availability, .disabled(.nothingLoaded))
        state.isWorking = true
        XCTAssertEqual(
            Layout.make(state: state).control(for: .save)?.availability,
            .disabled(.comparisonWorking))
    }

    func testSaveWithUnsavedChangesButNoSavableSide() throws {
        // A dirty read-only side: the control stays enabled like WinMerge (`IsModified()`), and
        // the app's `saveAllChanges` reports the read-only error instead of silently no-oping.
        // Only the per-side Save items are gated; Save As stays available.
        var state = Self.loaded
        state.canSaveLeft = false
        state.canSaveRight = false
        let layout = Layout.make(state: state)
        let save = try XCTUnwrap(layout.control(for: .save))
        XCTAssertEqual(save.availability, .enabled)
        XCTAssertEqual(layout.dispatch(.primaryClick, to: .save), .perform(.saveAllChanges))
        let items = Dictionary(uniqueKeysWithValues: save.menuItems.map { ($0.id, $0.availability) })
        XCTAssertEqual(
            items,
            [
                "saveLeft": .disabled(.nothingToSave), "saveRight": .disabled(.nothingToSave),
                "saveLeftAs": .enabled, "saveRightAs": .enabled
            ])
    }

    func testTurningOffEachStateFlagFlipsOnlyItsOwnControls() {
        let reflected = Set(
            Mirror(reflecting: Self.allEnabled).children.compactMap { child in
                child.value is Bool ? child.label : nil
            })
        // `isWorking` is off in `allEnabled`; testWorkingDisablesEveryControlExceptOptions
        // covers turning it on.
        XCTAssertEqual(
            Set(Self.flagFlips.map(\.name)), reflected.subtracting(["isWorking"]),
            "Every Bool gate in State needs a row")
        let base = Self.availabilityMap(Layout.make(state: Self.allEnabled))
        XCTAssertTrue(base.values.contains(.enabled))
        for flip in Self.flagFlips {
            var state = Self.allEnabled
            XCTAssertTrue(state[keyPath: flip.keyPath], flip.name)
            state[keyPath: flip.keyPath] = false
            let after = Self.availabilityMap(Layout.make(state: state))
            var changed: [String: Layout.Availability] = [:]
            for (key, availability) in after where base[key] != availability {
                changed[key] = availability
            }
            XCTAssertEqual(changed, flip.flips.mapValues { .disabled($0) }, flip.name)
        }
    }

    func testEmptyImplementedNewCommandsFlipsOnlyNewControl() {
        var state = Self.allEnabled
        state.implementedNewCommands = []
        let base = Self.availabilityMap(Layout.make(state: Self.allEnabled))
        let after = Self.availabilityMap(Layout.make(state: state))
        let changed = Set(after.keys.filter { base[$0] != after[$0] })
        XCTAssertEqual(changed, ["newComparison", "newComparison.ID_FILE_NEW"])
    }

    func testCopyTitlesComeFromSharedTable() {
        let layout = Layout.make(state: .freshWindow)
        let copyCommands: [ToolbarConfiguration.Command] = [
            .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance,
            .copyAllToRight, .copyAllToLeft
        ]
        for command in copyCommands {
            let title = Layout.copyTitle(for: command)
            XCTAssertNotNil(title)
            XCTAssertEqual(layout.control(for: command)?.title, title)
        }
        XCTAssertNil(Layout.copyTitle(for: .undo))
    }

    // MARK: - Dispatch

    func testDispatchOutcomes() throws {
        let layout = Layout.make(state: Self.loaded)
        XCTAssertEqual(layout.dispatch(.primaryClick, to: .save), .perform(.saveAllChanges))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("saveLeftAs"), to: .save), .perform(.saveLeftAs))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("saveRight"), to: .save),
            .ignored(.menuItemDisabled(id: "saveRight", .nothingToSave)))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("saveMiddle"), to: .save),
            .ignored(.unknownMenuItem("saveMiddle")))
        XCTAssertEqual(
            layout.dispatch(.menuArrowClick, to: .save),
            .presentMenu(try XCTUnwrap(layout.control(for: .save)).menu))
        XCTAssertEqual(layout.dispatch(.menuArrowClick, to: .undo), .ignored(.noSecondaryActions))
        XCTAssertEqual(layout.dispatch(.primaryClick, to: .options), .perform(.openOptions))
        XCTAssertEqual(
            layout.dispatch(.primaryClick, to: .copyAllToLeft), .perform(.requestCopyAllToLeft))
        XCTAssertEqual(
            layout.dispatch(.menuItemSelection("ID_FILE_NEW"), to: .newComparison),
            .perform(.newDocument(.twoPaneText)))
        XCTAssertEqual(
            layout.dispatch(.primaryClick, to: .autoMerge),
            .ignored(.controlDisabled(.requiresThreePaneComparison)))

        let fresh = Layout.make(state: .freshWindow)
        XCTAssertEqual(
            fresh.dispatch(.menuArrowClick, to: .save), .ignored(.controlDisabled(.nothingLoaded)))
    }

    func testOnlyPrimaryClickAndMenuSelectionAreAppDispatched() {
        XCTAssertEqual(Layout.Interaction.primaryClick.routing, .appDispatched)
        XCTAssertEqual(Layout.Interaction.menuItemSelection("x").routing, .appDispatched)
        for interaction: Layout.Interaction in [
            .menuArrowClick, .keyboardActivation, .voiceOverPress, .voiceOverShowMenu
        ] {
            XCTAssertEqual(interaction.routing, .nativeUnverified, "\(interaction)")
        }
    }

    // MARK: - Interaction matrix agreement

    func testDescriptorsUseInventoryIdentifiersForEveryControl() {
        let layout = Layout.make(state: .freshWindow)
        XCTAssertEqual(layout.interactionMatrixDescriptors.count, layout.controls.count)
        for (control, descriptor) in zip(layout.controls, layout.interactionMatrixDescriptors) {
            XCTAssertEqual(descriptor.command, control.command)
            XCTAssertEqual(
                descriptor.controlID, ToolbarAccessibilityInventory.controlID(for: control.command))
            XCTAssertEqual(descriptor.controlID.rawValue, control.accessibilityIdentifier)
            XCTAssertEqual(
                descriptor.primaryActionID,
                ToolbarAccessibilityInventory.primaryActionID(for: control.command))
            XCTAssertEqual(descriptor.hasSecondaryMenu, control.hasSecondaryActions)
        }
        let save = layout.interactionMatrixDescriptors.first { $0.command == .save }
        XCTAssertEqual(
            save?.secondaryActionIDs.map(\.rawValue),
            [
                "toolbar.save.saveLeft", "toolbar.save.saveRight",
                "toolbar.save.saveLeftAs", "toolbar.save.saveRightAs"
            ])
    }

    func testDispatchAgreesWithInteractionMatrixRouting() {
        let primaryKinds: [(Layout.Interaction, ToolbarAuditInvocationKind)] = [
            (.primaryClick, .primaryClick), (.keyboardActivation, .keyboardActivation),
            (.voiceOverPress, .voiceOverActivation), (.menuArrowClick, .menuArrowClick)
        ]
        for state in [Layout.State.freshWindow, Self.loaded, Self.allEnabled] {
            let layout = Layout.make(state: state)
            for control in layout.controls {
                let descriptor = Layout.interactionMatrixDescriptor(for: control)
                for (interaction, invocation) in primaryKinds {
                    assertAgreement(
                        layout, control, interaction, invocation, descriptor,
                        descriptor.primaryActionID, isEnabled: control.isEnabled)
                }
                XCTAssertEqual(descriptor.secondaryActionIDs.count, control.menuItems.count)
                for (item, actionID) in zip(control.menuItems, descriptor.secondaryActionIDs) {
                    assertAgreement(
                        layout, control, .menuItemSelection(item.id), .menuItemSelection,
                        descriptor, actionID, isEnabled: control.isEnabled && item.isEnabled)
                }
                // The matrix's disabled-activation probe blocks exactly when dispatch ignores the
                // control as disabled.
                let probe = ToolbarInteractionMatrix.route(
                    invocation: .disabledActivation, isEnabled: control.isEnabled,
                    control: descriptor, actionID: descriptor.primaryActionID)
                let ignoredAsDisabled: Bool
                if case .ignored(.controlDisabled) = layout.dispatch(.primaryClick, to: control.command) {
                    ignoredAsDisabled = true
                } else {
                    ignoredAsDisabled = false
                }
                XCTAssertEqual(probe == .blocked, ignoredAsDisabled, "\(control.command)")
            }
        }
    }

    func testAgreementCheckRejectsMisroutedPrimaryAction() throws {
        // A control whose primary action belongs to another command must not agree.
        let layout = Layout.make(state: Self.allEnabled)
        let control = try XCTUnwrap(layout.control(for: .copyToRight))
        XCTAssertEqual(Self.primaryStableID(for: .copyToLeft)?.rawValue, "toolbar.copyToLeft.primary")
        XCTAssertNotEqual(
            Self.primaryStableID(for: .copyToLeft),
            Layout.interactionMatrixDescriptor(for: control).primaryActionID)
        XCTAssertEqual(
            Self.menuItemStableID(for: .saveRight)?.rawValue, "toolbar.save.saveRight")
        XCTAssertNil(Self.menuItemStableID(for: .undo))
    }

    private func assertAgreement(
        _ layout: Layout,
        _ control: Layout.Control,
        _ interaction: Layout.Interaction,
        _ invocation: ToolbarAuditInvocationKind,
        _ descriptor: ToolbarInteractionMatrix.ControlDescriptor,
        _ actionID: ToolbarAuditStableID,
        isEnabled: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = ToolbarInteractionMatrix.route(
            invocation: invocation, isEnabled: isEnabled, control: descriptor, actionID: actionID)
        // Map the outcome to ids from independent literal tables, never from `expected`.
        let actual: ToolbarAuditInteractionOutcome? =
            switch layout.dispatch(
                interaction, to: control.command)
            {
            case .perform(let action):
                Self.performedStableID(action, via: interaction).map { .invoked(actionID: $0) }
                    ?? .failed(code: ToolbarAuditStableID(rawValue: "unmapped"))
            case .presentMenu(let elements):
                .menuPresented(
                    actionIDs: elements.flatMap(\.items).map {
                        ToolbarAuditStableID(rawValue: "toolbar.\(control.command.rawValue).\($0.id)")
                    })
            case .ignored(.noSecondaryActions): .noOp
            case .ignored: .blocked
            case nil: nil
            }
        XCTAssertEqual(
            actual, expected, "\(control.command) \(interaction)", file: file, line: line)
    }

    // MARK: - Independent reference tables

    private typealias Command = ToolbarConfiguration.Command

    private static let allEnabled = Layout.State(
        isLeftLoaded: true, isRightLoaded: true, canSaveLeft: true, canSaveRight: true,
        hasUnsavedChanges: true, canUndo: true, canRedo: true, canSelectLineDifference: true,
        hasNavigableDifferences: true, canSelectNextDifference: true,
        canSelectPreviousDifference: true, canSelectCurrentDifference: true,
        canCopyToRight: true, canCopyToLeft: true, canCopyToRightAndAdvance: true,
        canCopyToLeftAndAdvance: true, canCopyAllToRight: true, canCopyAllToLeft: true,
        canRefresh: true)

    private struct FlagFlip {
        let name: String
        let keyPath: WritableKeyPath<Layout.State, Bool>
        /// Availability keys (`command` or `command.item`) that must flip, with their reason.
        let flips: [String: Layout.DisabledReason]
    }

    private static var flagFlips: [FlagFlip] {
        [
            FlagFlip(
                name: "isLeftLoaded", keyPath: \.isLeftLoaded,
                flips: [
                    "save.saveLeft": .sideNotLoaded, "save.saveLeftAs": .sideNotLoaded
                ]),
            FlagFlip(
                name: "isRightLoaded", keyPath: \.isRightLoaded,
                flips: [
                    "save.saveRight": .sideNotLoaded, "save.saveRightAs": .sideNotLoaded
                ]),
            FlagFlip(
                name: "canSaveLeft", keyPath: \.canSaveLeft,
                flips: [
                    "save.saveLeft": .nothingToSave
                ]),
            FlagFlip(
                name: "canSaveRight", keyPath: \.canSaveRight,
                flips: [
                    "save.saveRight": .nothingToSave
                ]),
            FlagFlip(
                name: "hasUnsavedChanges", keyPath: \.hasUnsavedChanges,
                flips: [
                    "save": .nothingToSave
                ]),
            FlagFlip(name: "canUndo", keyPath: \.canUndo, flips: ["undo": .nothingToUndo]),
            FlagFlip(name: "canRedo", keyPath: \.canRedo, flips: ["redo": .nothingToRedo]),
            FlagFlip(
                name: "canSelectLineDifference", keyPath: \.canSelectLineDifference,
                flips: ["selectLineDifference": .noLineDifference]),
            FlagFlip(
                name: "hasNavigableDifferences", keyPath: \.hasNavigableDifferences,
                flips: [
                    "nextDifference": .noDifferences, "previousDifference": .noDifferences,
                    "firstDifference": .noDifferences, "lastDifference": .noDifferences
                ]),
            FlagFlip(
                name: "canSelectNextDifference", keyPath: \.canSelectNextDifference,
                flips: ["nextDifference": .noAdjacentDifference]),
            FlagFlip(
                name: "canSelectPreviousDifference", keyPath: \.canSelectPreviousDifference,
                flips: ["previousDifference": .noAdjacentDifference]),
            FlagFlip(
                name: "canSelectCurrentDifference", keyPath: \.canSelectCurrentDifference,
                flips: ["currentDifference": .noCurrentDifference]),
            FlagFlip(
                name: "canCopyToRight", keyPath: \.canCopyToRight,
                flips: [
                    "copyToRight": .mergeUnavailable
                ]),
            FlagFlip(
                name: "canCopyToLeft", keyPath: \.canCopyToLeft,
                flips: [
                    "copyToLeft": .mergeUnavailable
                ]),
            FlagFlip(
                name: "canCopyToRightAndAdvance", keyPath: \.canCopyToRightAndAdvance,
                flips: [
                    "copyToRightAndAdvance": .mergeUnavailable
                ]),
            FlagFlip(
                name: "canCopyToLeftAndAdvance", keyPath: \.canCopyToLeftAndAdvance,
                flips: [
                    "copyToLeftAndAdvance": .mergeUnavailable
                ]),
            FlagFlip(
                name: "canCopyAllToRight", keyPath: \.canCopyAllToRight,
                flips: [
                    "copyAllToRight": .mergeUnavailable
                ]),
            FlagFlip(
                name: "canCopyAllToLeft", keyPath: \.canCopyAllToLeft,
                flips: [
                    "copyAllToLeft": .mergeUnavailable
                ]),
            FlagFlip(
                name: "canRefresh", keyPath: \.canRefresh,
                flips: [
                    "refresh": .comparisonNotReady
                ])
        ]
    }

    private static func availabilityMap(_ layout: Layout) -> [String: Layout.Availability] {
        var map: [String: Layout.Availability] = [:]
        for control in layout.controls {
            map[control.command.rawValue] = control.availability
            for item in control.menuItems {
                map["\(control.command.rawValue).\(item.id)"] = item.availability
            }
        }
        return map
    }

    /// Primary action each command must run, written out independently of the layout.
    private static let primaryActions: [Command: Layout.Action] = [
        .newComparison: .newDocument(.twoPaneText), .openComparison: .openComparison,
        .save: .saveAllChanges, .undo: .undo, .redo: .redo,
        .selectLineDifference: .selectLineDifference, .nextDifference: .nextDifference,
        .previousDifference: .previousDifference, .nextConflict: .nextConflict,
        .previousConflict: .previousConflict, .firstDifference: .firstDifference,
        .currentDifference: .currentDifference, .lastDifference: .lastDifference,
        .copyToRight: .copyToRight, .copyToLeft: .copyToLeft,
        .copyToRightAndAdvance: .copyToRightAndAdvance,
        .copyToLeftAndAdvance: .copyToLeftAndAdvance,
        .copyAllToRight: .requestCopyAllToRight, .copyAllToLeft: .requestCopyAllToLeft,
        .autoMerge: .autoMerge, .firstComparedFile: .firstComparedFile,
        .previousComparedFile: .previousComparedFile, .nextComparedFile: .nextComparedFile,
        .lastComparedFile: .lastComparedFile, .options: .openOptions, .refresh: .refresh
    ]

    private static func primaryStableID(for action: Layout.Action) -> ToolbarAuditStableID? {
        let commands = primaryActions.filter { $0.value == action }.map(\.key)
        guard commands.count == 1, let command = commands.first else { return nil }
        return ToolbarAuditStableID(rawValue: "toolbar.\(command.rawValue).primary")
    }

    private static func performedStableID(
        _ action: Layout.Action, via interaction: Layout.Interaction
    ) -> ToolbarAuditStableID? {
        if case .menuItemSelection = interaction { return menuItemStableID(for: action) }
        return primaryStableID(for: action)
    }

    private static func menuItemStableID(for action: Layout.Action) -> ToolbarAuditStableID? {
        let pair: (Command, String)? =
            switch action {
            case .newDocument(let id): (.newComparison, id.rawValue)
            case .openComparison: (.openComparison, "openComparison")
            case .openLeft: (.openComparison, "openLeft")
            case .openRight: (.openComparison, "openRight")
            case .saveLeft: (.save, "saveLeft")
            case .saveRight: (.save, "saveRight")
            case .saveLeftAs: (.save, "saveLeftAs")
            case .saveRightAs: (.save, "saveRightAs")
            default: nil
            }
        return pair.map { ToolbarAuditStableID(rawValue: "toolbar.\($0.0.rawValue).\($0.1)") }
    }

    /// WinMerge resource id to Mac command, written out independently of production tables.
    private static let winMergeCommandIDs: [String: Command] = [
        "ID_FILE_NEW": .newComparison, "ID_FILE_OPEN": .openComparison, "ID_FILE_SAVE": .save,
        "ID_EDIT_UNDO": .undo, "ID_EDIT_REDO": .redo, "ID_SELECTLINEDIFF": .selectLineDifference,
        "ID_NEXTDIFF": .nextDifference, "ID_PREVDIFF": .previousDifference,
        "ID_NEXTCONFLICT": .nextConflict, "ID_PREVCONFLICT": .previousConflict,
        "ID_FIRSTDIFF": .firstDifference, "ID_CURDIFF": .currentDifference,
        "ID_LASTDIFF": .lastDifference, "ID_L2R": .copyToRight, "ID_R2L": .copyToLeft,
        "ID_L2RNEXT": .copyToRightAndAdvance, "ID_R2LNEXT": .copyToLeftAndAdvance,
        "ID_ALL_RIGHT": .copyAllToRight, "ID_ALL_LEFT": .copyAllToLeft,
        "ID_AUTO_MERGE": .autoMerge, "ID_FIRSTFILE": .firstComparedFile,
        "ID_PREVFILE": .previousComparedFile, "ID_NEXTFILE": .nextComparedFile,
        "ID_LASTFILE": .lastComparedFile, "ID_OPTIONS": .options, "ID_REFRESH": .refresh
    ]

    private static func winMergeSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MacMergeCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MacMerge
            .deletingLastPathComponent()  // repo root
            .appending(path: relativePath)
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("\(relativePath) not found at \(url.path)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static let presentationGolden: [String] = [
        "newComparison | toolbar.newComparison | New | New Documents | Shows more New comparison types. | New Documents (Command-N)",
        "openComparison | toolbar.openComparison | Open files | Open files | Shows options to open each side. | Select files to compare (Command-O)",
        "save | toolbar.save | Save | Save | Shows options to save each side. | Save changed files (Command-S)",
        "undo | toolbar.undo | Undo | Undo | - | Undo the last edit or merge",
        "redo | toolbar.redo | Redo | Redo | - | Redo the last edit or merge",
        "selectLineDifference | toolbar.selectLineDifference | Select line difference | Select line difference | - | Select the intra-line difference in the active pane (F4)",
        "nextDifference | toolbar.nextDifference | Next difference | Next difference | - | Go to next difference (F8)",
        "previousDifference | toolbar.previousDifference | Previous difference | Previous difference | - | Go to previous difference (F7)",
        "nextConflict | toolbar.nextConflict | Next conflict | Next conflict | - | Next conflict is available in three-pane conflict comparisons",
        "previousConflict | toolbar.previousConflict | Previous conflict | Previous conflict | - | Previous conflict is available in three-pane conflict comparisons",
        "firstDifference | toolbar.firstDifference | First difference | First difference | - | Go to first difference",
        "currentDifference | toolbar.currentDifference | Current difference | Current difference | - | Reveal the current difference",
        "lastDifference | toolbar.lastDifference | Last difference | Last difference | - | Go to last difference",
        "copyToRight | toolbar.copyToRight | Copy selected difference to right | Copy selected difference to right | - | Copy the selected or current difference to right (Option-Right Arrow when the diff list has focus)",
        "copyToLeft | toolbar.copyToLeft | Copy selected difference to left | Copy selected difference to left | - | Copy the selected or current difference to left (Option-Left Arrow when the diff list has focus)",
        "copyToRightAndAdvance | toolbar.copyToRightAndAdvance | Copy selected difference to right and advance | Copy selected difference to right and advance | - | Copy selected difference to right and advance",
        "copyToLeftAndAdvance | toolbar.copyToLeftAndAdvance | Copy selected difference to left and advance | Copy selected difference to left and advance | - | Copy selected difference to left and advance",
        "copyAllToRight | toolbar.copyAllToRight | Copy all differences to right | Copy all differences to right | - | Copy all differences to right",
        "copyAllToLeft | toolbar.copyAllToLeft | Copy all differences to left | Copy all differences to left | - | Copy all differences to left",
        "autoMerge | toolbar.autoMerge | Auto merge | Auto merge | - | Auto Merge is available in clean three-pane comparisons",
        "firstComparedFile | toolbar.firstComparedFile | First compared file | First compared file | - | Compared-file navigation is available from folder comparisons",
        "previousComparedFile | toolbar.previousComparedFile | Previous compared file | Previous compared file | - | Compared-file navigation is available from folder comparisons",
        "nextComparedFile | toolbar.nextComparedFile | Next compared file | Next compared file | - | Compared-file navigation is available from folder comparisons",
        "lastComparedFile | toolbar.lastComparedFile | Last compared file | Last compared file | - | Compared-file navigation is available from folder comparisons",
        "options | toolbar.options | Options | Options | - | Open comparison options (Command-,)",
        "refresh | toolbar.refresh | Refresh | Refresh | - | Recompare the current in-memory text without reloading files"
    ]
}
