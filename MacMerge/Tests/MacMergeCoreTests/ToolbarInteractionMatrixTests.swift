import Foundation
import MacMergeCore
import XCTest

final class ToolbarInteractionMatrixTests: XCTestCase {
    private typealias Command = ToolbarConfiguration.Command
    private typealias InteractionMatrix = ToolbarInteractionMatrix
    private typealias Invocation = ToolbarAuditInvocationKind
    private typealias Limits = ToolbarInteractionMatrix.Limits
    private typealias MatrixError = ToolbarInteractionMatrixError
    private typealias Outcome = ToolbarAuditInteractionOutcome
    private typealias Scenario = ToolbarAuditLifecycleScenario
    private typealias SemanticCommand = ComparisonCommandState.Identifier
    private typealias StableID = ToolbarAuditStableID

    func testRequiredCollectionsCoverAllScenariosInvocationsAndWindows() {
        XCTAssertEqual(InteractionMatrix.requiredScenarios, Scenario.allCases)
        XCTAssertEqual(InteractionMatrix.requiredInvocations, Invocation.allCases)
        XCTAssertEqual(InteractionMatrix.requiredWindows, ToolbarAuditScreenshotContext.allCases)
        XCTAssertEqual(Scenario.allCases.count, 10)
        XCTAssertEqual(Invocation.allCases.count, 6)
        XCTAssertEqual(ToolbarAuditScreenshotContext.allCases.count, 2)
    }

    func testLifecycleScenariosHaveExactCanonicalOrder() {
        XCTAssertEqual(
            Scenario.allCases.map(\.rawValue),
            [
                "empty", "loading", "equal", "different", "selected", "dirty",
                "readOnly", "failed", "untitled", "externallyChanged"
            ]
        )
    }

    func testInvocationKindsHaveExactCanonicalOrder() {
        XCTAssertEqual(
            Invocation.allCases.map(\.rawValue),
            [
                "primaryClick", "menuArrowClick", "menuItemSelection",
                "keyboardActivation", "voiceOverActivation", "disabledActivation"
            ]
        )
    }

    func testManifestRevisionMatchesCanonical() {
        XCTAssertEqual(InteractionMatrix.manifestRevision, ToolbarAuditManifest.canonicalRevision)
        XCTAssertEqual(InteractionMatrix.manifestRevision, ToolbarAuditManifest.canonical.revision)
    }

    func testWindowMapsScreenshotContextAndRepresentativeScenario() {
        for context in ToolbarAuditScreenshotContext.allCases {
            XCTAssertEqual(InteractionMatrix.Window(context).screenshotContext, context)
        }
        XCTAssertEqual(InteractionMatrix.Window.freshWindow.representativeScenario, .empty)
        XCTAssertEqual(InteractionMatrix.Window.loadedComparison.representativeScenario, .different)
        XCTAssertEqual(InteractionMatrix.Window.freshWindow, InteractionMatrix.Window(.freshWindow))
        XCTAssertEqual(
            InteractionMatrix.Window.loadedComparison,
            InteractionMatrix.Window(.loadedComparison)
        )
    }

    func testCommandContextMapsAllTenScenarios() {
        let empty = InteractionMatrix.commandContext(for: .empty)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.hasSelection)
        XCTAssertFalse(empty.hasSignificantDifferences)
        XCTAssertFalse(empty.canUndo)
        XCTAssertEqual(empty.comparisonLifecycle, .currentSuccess)

        let loading = InteractionMatrix.commandContext(for: .loading)
        XCTAssertEqual(loading.comparisonLifecycle, .loading)
        XCTAssertFalse(loading.hasSignificantDifferences)

        let equal = InteractionMatrix.commandContext(for: .equal)
        XCTAssertFalse(equal.isEmpty)
        XCTAssertFalse(equal.hasSignificantDifferences)

        let different = InteractionMatrix.commandContext(for: .different)
        XCTAssertTrue(different.hasSignificantDifferences)
        XCTAssertFalse(different.hasSelection)
        XCTAssertTrue(different.differenceNavigation.canSelectNextDifference)

        let selected = InteractionMatrix.commandContext(for: .selected)
        XCTAssertTrue(selected.hasSelection)
        XCTAssertTrue(selected.hasSignificantDifferences)

        let dirty = InteractionMatrix.commandContext(for: .dirty)
        XCTAssertTrue(dirty.left.isDirty)
        XCTAssertTrue(dirty.canUndo)

        let readOnly = InteractionMatrix.commandContext(for: .readOnly)
        XCTAssertTrue(readOnly.left.isReadOnly)
        XCTAssertTrue(readOnly.hasSignificantDifferences)

        let failed = InteractionMatrix.commandContext(for: .failed)
        XCTAssertEqual(failed.comparisonLifecycle, .failed)

        let untitled = InteractionMatrix.commandContext(for: .untitled)
        XCTAssertTrue(untitled.left.isUntitled)
        XCTAssertTrue(untitled.canUndo)

        let changed = InteractionMatrix.commandContext(for: .externallyChanged)
        XCTAssertTrue(changed.left.hasExternalChange)
        XCTAssertTrue(changed.right.hasExternalChange)
        XCTAssertTrue(changed.canUndo)
    }

    func testAvailabilityMatchesSharedCommandStateForEveryScenarioAndCommand() {
        for scenario in Scenario.allCases {
            let context = InteractionMatrix.commandContext(for: scenario)
            for command in Command.allCases {
                let semantic = SemanticCommand(command)
                let expected = ComparisonCommandState.resolve(semantic, in: context)
                let actual = InteractionMatrix.availability(of: semantic, in: scenario)
                XCTAssertEqual(actual.isEnabled, expected.isEnabled, "\(scenario.rawValue).\(command.rawValue)")
                XCTAssertEqual(actual == .enabled, expected.isEnabled, "\(scenario.rawValue).\(command.rawValue)")
            }
        }
    }

    func testDisabledAvailabilityAlwaysCarriesStableReason() {
        for scenario in Scenario.allCases {
            for command in Command.allCases {
                let actual = InteractionMatrix.availability(of: SemanticCommand(command), in: scenario)
                switch actual {
                case .enabled:
                    break
                case .disabled(let reason):
                    XCTAssertFalse(reason.rawValue.isEmpty, "\(scenario.rawValue).\(command.rawValue)")
                }
            }
        }
    }

    func testPrimaryAvailabilityMapsDirectlyFromToolbarCommand() {
        let control = makePrimaryControl(command: .save, suffix: "save")
        for scenario in Scenario.allCases {
            XCTAssertEqual(
                InteractionMatrix.availability(
                    control: control,
                    actionID: control.primaryActionID,
                    in: scenario
                ),
                InteractionMatrix.availability(of: SemanticCommand(control.command), in: scenario),
                scenario.rawValue
            )
        }
    }

    func testSecondaryWithoutBindingIsDisabledAsMissingBinding() {
        let control = makeControl(command: .save, suffix: "unbound", secondaries: ["extra"])
        for scenario in Scenario.allCases {
            let availability = InteractionMatrix.availability(
                control: control,
                actionID: control.secondaryActionIDs[0],
                in: scenario
            )
            XCTAssertFalse(availability.isEnabled, scenario.rawValue)
            if case .disabled(let reason) = availability {
                XCTAssertEqual(reason, InteractionMatrix.missingBindingCode, scenario.rawValue)
            } else {
                XCTFail("Expected disabled missing binding in \(scenario.rawValue)")
            }
        }
    }

    func testSecondaryWithBindingResolvesThroughBoundCommand() throws {
        let (control, bindings) = makeMenuControl()
        let bound = try XCTUnwrap(bindings[control.secondaryActionIDs[0]])
        for scenario in Scenario.allCases {
            XCTAssertEqual(
                InteractionMatrix.availability(
                    control: control,
                    actionID: control.secondaryActionIDs[0],
                    in: scenario,
                    bindings: bindings
                ),
                InteractionMatrix.availability(of: bound, in: scenario),
                scenario.rawValue
            )
        }
    }

    func testDisabledActionsNeverPerformAcrossAllInvocations() {
        let control = makeControl(command: .save, suffix: "gated", secondaries: ["extra"])
        let secondary = control.secondaryActionIDs[0]
        XCTAssertFalse(
            InteractionMatrix.availability(control: control, actionID: secondary, in: .different).isEnabled
        )
        for invocation in Invocation.allCases {
            let outcome = InteractionMatrix.route(
                invocation: invocation,
                isEnabled: false,
                control: control,
                actionID: secondary
            )
            XCTAssertEqual(outcome, .blocked, invocation.rawValue)
            let route = InteractionMatrix.resolveRoute(
                scenario: .different,
                control: control,
                actionID: secondary,
                invocation: invocation
            )
            XCTAssertEqual(route.outcome, .blocked, invocation.rawValue)
            XCTAssertFalse(route.performsAction, invocation.rawValue)
            XCTAssertFalse(route.isEnabled, invocation.rawValue)
        }
    }

    func testDisabledActivationProbeOnEnabledActionIsNoOp() {
        let control = makePrimaryControl()
        let outcome = InteractionMatrix.route(
            invocation: .disabledActivation,
            isEnabled: true,
            control: control,
            actionID: control.primaryActionID
        )
        XCTAssertEqual(outcome, .noOp)
        let probe = InteractionMatrix.InteractionRoute(
            scenario: .different,
            controlID: control.controlID,
            actionID: control.primaryActionID,
            invocation: .disabledActivation,
            outcome: outcome,
            isEnabled: true
        )
        XCTAssertFalse(probe.performsAction)
        XCTAssertEqual(
            InteractionMatrix.InteractionRoute(
                scenario: .different,
                controlID: control.controlID,
                actionID: control.primaryActionID,
                invocation: .primaryClick,
                outcome: .invoked(actionID: control.primaryActionID),
                isEnabled: true
            ).performsAction,
            true
        )
    }

    func testEnabledPrimaryClickKeyboardAndVoiceOverInvokePrimary() {
        let control = makePrimaryControl()
        XCTAssertFalse(control.hasSecondaryMenu)
        XCTAssertEqual(control.allActionIDs, [control.primaryActionID])
        for invocation in [Invocation.primaryClick, .keyboardActivation, .voiceOverActivation] {
            XCTAssertEqual(
                InteractionMatrix.route(
                    invocation: invocation,
                    isEnabled: true,
                    control: control,
                    actionID: control.primaryActionID
                ),
                .invoked(actionID: control.primaryActionID),
                invocation.rawValue
            )
        }
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .menuArrowClick,
                isEnabled: true,
                control: control,
                actionID: control.primaryActionID
            ),
            .noOp
        )
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .menuItemSelection,
                isEnabled: true,
                control: control,
                actionID: control.primaryActionID
            ),
            .failed(code: InteractionMatrix.unknownActionCode)
        )
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .disabledActivation,
                isEnabled: true,
                control: control,
                actionID: control.primaryActionID
            ),
            .noOp
        )
    }

    func testMisroutedPrimaryActivationsFail() {
        let (control, _) = makeMenuControl()
        let secondary = control.secondaryActionIDs[0]
        for invocation in [Invocation.primaryClick, .keyboardActivation, .voiceOverActivation] {
            let outcome = InteractionMatrix.route(
                invocation: invocation,
                isEnabled: true,
                control: control,
                actionID: secondary
            )
            XCTAssertEqual(outcome, .failed(code: InteractionMatrix.misroutedPrimaryCode), invocation.rawValue)
        }
    }

    func testMenuArrowOnPrimaryPresentsSecondaryInOrder() {
        let (control, _) = makeMenuControl()
        XCTAssertTrue(control.hasSecondaryMenu)
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .menuArrowClick,
                isEnabled: true,
                control: control,
                actionID: control.primaryActionID
            ),
            .menuPresented(actionIDs: control.secondaryActionIDs)
        )
    }

    func testMenuArrowOnSecondaryFailsAsMisroutedMenu() {
        let (control, _) = makeMenuControl()
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .menuArrowClick,
                isEnabled: true,
                control: control,
                actionID: control.secondaryActionIDs[1]
            ),
            .failed(code: InteractionMatrix.misroutedMenuCode)
        )
    }

    func testMenuItemSelectionInvokesSecondaryAndRejectsUnknown() {
        let (control, _) = makeMenuControl()
        for secondary in control.secondaryActionIDs {
            XCTAssertEqual(
                InteractionMatrix.route(
                    invocation: .menuItemSelection,
                    isEnabled: true,
                    control: control,
                    actionID: secondary
                ),
                .invoked(actionID: secondary)
            )
        }
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .menuItemSelection,
                isEnabled: true,
                control: control,
                actionID: StableID(rawValue: "test.toolbar.action.ghost")
            ),
            .failed(code: InteractionMatrix.unknownActionCode)
        )
    }

    func testResolveRouteCombinesAvailabilityAndRouting() {
        let (control, bindings) = makeMenuControl()
        for scenario in [Scenario.empty, Scenario.different] {
            for actionID in control.allActionIDs {
                for invocation in Invocation.allCases {
                    let availability = InteractionMatrix.availability(
                        control: control,
                        actionID: actionID,
                        in: scenario,
                        bindings: bindings
                    )
                    let expected = InteractionMatrix.route(
                        invocation: invocation,
                        isEnabled: availability.isEnabled,
                        control: control,
                        actionID: actionID
                    )
                    let route = InteractionMatrix.resolveRoute(
                        scenario: scenario,
                        control: control,
                        actionID: actionID,
                        invocation: invocation,
                        bindings: bindings
                    )
                    XCTAssertEqual(route.scenario, scenario)
                    XCTAssertEqual(route.controlID, control.controlID)
                    XCTAssertEqual(route.actionID, actionID)
                    XCTAssertEqual(route.invocation, invocation)
                    XCTAssertEqual(route.isEnabled, availability.isEnabled)
                    XCTAssertEqual(route.outcome, expected)
                }
            }
        }
    }

    func testScreenshotItemsMatchCanonicalOrderInBothWindows() {
        let canonical = ToolbarAuditManifest.canonical.items
        XCTAssertEqual(canonical, ToolbarConfiguration.winMergeDefaultItems)
        XCTAssertFalse(canonical.isEmpty)
        for window in InteractionMatrix.Window.allCases {
            XCTAssertEqual(InteractionMatrix.screenshotItems(for: window), canonical, window.rawValue)
        }
        XCTAssertEqual(
            InteractionMatrix.screenshotItems(for: .freshWindow),
            InteractionMatrix.screenshotItems(for: .loadedComparison)
        )
    }

    func testScreenshotGroupsMatchCanonicalGroupsAndBindCommands() {
        let canonical = ToolbarAuditManifest.canonical.groups
        XCTAssertFalse(canonical.isEmpty)
        for window in InteractionMatrix.Window.allCases {
            XCTAssertEqual(InteractionMatrix.screenshotGroups(for: window), canonical, window.rawValue)
        }
        XCTAssertEqual(canonical.flatMap(\.commands), ToolbarAuditManifest.canonical.commands)
    }

    func testDigestIsDeterministicAndBindsSecondaryOrder() throws {
        let control = makeControl(command: .save, suffix: "ordered", secondaries: ["alpha", "beta"])
        let bindings: [StableID: SemanticCommand] = [
            control.secondaryActionIDs[0]: .undo,
            control.secondaryActionIDs[1]: .redo
        ]
        let baseline = try makeMatrix(controls: [control], bindings: bindings)
        let repeatRun = try makeMatrix(controls: [control], bindings: bindings)
        XCTAssertEqual(baseline.digestHex, repeatRun.digestHex)

        let reordered = InteractionMatrix.ControlDescriptor(
            controlID: control.controlID,
            command: control.command,
            primaryActionID: control.primaryActionID,
            secondaryActionIDs: Array(control.secondaryActionIDs.reversed())
        )
        let swapped = try makeMatrix(controls: [reordered], bindings: bindings)
        XCTAssertNotEqual(baseline.digestHex, swapped.digestHex)
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .menuArrowClick,
                isEnabled: true,
                control: control,
                actionID: control.primaryActionID
            ),
            .menuPresented(actionIDs: control.secondaryActionIDs)
        )
        XCTAssertEqual(
            InteractionMatrix.route(
                invocation: .menuArrowClick,
                isEnabled: true,
                control: reordered,
                actionID: reordered.primaryActionID
            ),
            .menuPresented(actionIDs: reordered.secondaryActionIDs)
        )
    }

    func testDigestHexIsLowercaseSHA256Hex() throws {
        let matrix = try makeMatrix(controls: [makePrimaryControl()])
        XCTAssertEqual(matrix.digestHex.count, 64)
        XCTAssertTrue(matrix.digestHex.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    func testDescriptionAndMirrorAreRedacted() throws {
        let (control, bindings) = makeMenuControl()
        let matrix = try makeMatrix(controls: [control], bindings: bindings)
        let description = String(describing: matrix)
        XCTAssertTrue(description.contains("lifecycleRows: \(matrix.lifecycleRows.count)"))
        XCTAssertTrue(description.contains("interactionRoutes: \(matrix.interactionRoutes.count)"))
        XCTAssertTrue(description.contains("screenshots: \(matrix.screenshotRows.count)"))
        XCTAssertTrue(description.contains(matrix.digestHex))
        XCTAssertFalse(description.contains(control.controlID.rawValue))
        XCTAssertFalse(description.contains(control.primaryActionID.rawValue))
        XCTAssertEqual(matrix.debugDescription, description)
        var contents: String?
        var digest: String?
        for child in matrix.customMirror.children {
            if child.label == "contents" {
                contents = child.value as? String
            }
            if child.label == "digest" {
                digest = child.value as? String
            }
        }
        XCTAssertEqual(contents, "<redacted>")
        XCTAssertEqual(digest, matrix.digestHex)
    }

    func testMakeMatrixUsesCanonicalRowOrder() throws {
        let save = makeControl(command: .save, suffix: "save")
        let refresh = makeControl(command: .refresh, suffix: "refresh")
        let open = makeControl(command: .openComparison, suffix: "open")
        let matrix = try makeMatrix(controls: [refresh, save, open])
        let rowsPerScenario = 3
        XCTAssertEqual(matrix.lifecycleRows.count, Scenario.allCases.count * rowsPerScenario)
        for (index, scenario) in Scenario.allCases.enumerated() {
            let block = matrix.lifecycleRows[index * rowsPerScenario..<(index + 1) * rowsPerScenario]
            XCTAssertEqual(block.map(\.scenario), [scenario, scenario, scenario])
            XCTAssertEqual(block.map(\.command), [.openComparison, .save, .refresh])
        }
        XCTAssertEqual(matrix.interactionRoutes.count, matrix.lifecycleRows.count * Invocation.allCases.count)
        let firstScenario = try XCTUnwrap(Scenario.allCases.first)
        let firstRoutes = matrix.interactionRoutes.prefix(Invocation.allCases.count)
        XCTAssertEqual(firstRoutes.map(\.invocation), Invocation.allCases)
        XCTAssertTrue(firstRoutes.allSatisfy { $0.scenario == firstScenario })
    }

    func testMakeMatrixRejectsEmptyDuplicateAndBindingErrors() {
        assertMatrixError(.emptyControls, controls: [], source: "test-source")
        assertMatrixError(
            .invalidSource(field: "source"),
            controls: [makePrimaryControl()],
            source: "   "
        )
        let control = makePrimaryControl()
        assertMatrixError(
            .duplicateControl(id: control.controlID),
            controls: [control, control],
            source: "test-source"
        )
        assertMatrixError(
            .duplicateCommand(command: .save),
            controls: [
                makeControl(command: .save, suffix: "one"),
                makeControl(command: .save, suffix: "two")
            ],
            source: "test-source"
        )
        let sharedID = StableID(rawValue: "test.toolbar.action.shared")
        assertMatrixError(
            .duplicateAction(id: sharedID),
            controls: [
                InteractionMatrix.ControlDescriptor(
                    controlID: StableID(rawValue: "test.toolbar.control.colliding"),
                    command: .undo,
                    primaryActionID: sharedID,
                    secondaryActionIDs: [sharedID]
                )
            ],
            source: "test-source"
        )
        let menu = makeControl(command: .copyToRight, suffix: "unbound", secondaries: ["extra"])
        assertMatrixError(
            .missingSemanticBinding(actionID: menu.secondaryActionIDs[0]),
            controls: [menu],
            source: "test-source"
        )
        assertMatrixError(
            .unknownBinding(actionID: StableID(rawValue: "test.toolbar.action.ghost")),
            controls: [makePrimaryControl()],
            bindings: [StableID(rawValue: "test.toolbar.action.ghost"): .save],
            source: "test-source"
        )
    }

    func testMakeMatrixEnforcesBoundedLimits() {
        let one = makePrimaryControl(suffix: "one")
        let two = makePrimaryControl(command: .undo, suffix: "two")
        assertMatrixError(
            .invalidLimit(name: "controls", value: 0, maximum: Limits.hardMaximumControls),
            controls: [one],
            source: "test-source",
            limits: Limits(maximumControls: 0)
        )
        assertMatrixError(
            .invalidLimit(
                name: "cancellationCheckInterval",
                value: 0,
                maximum: Limits.hardMaximumCancellationCheckInterval
            ),
            controls: [one],
            source: "test-source",
            limits: Limits(cancellationCheckInterval: 0)
        )
        assertMatrixError(
            .countLimitExceeded(kind: "controls", maximum: 1),
            controls: [one, two],
            source: "test-source",
            limits: Limits(maximumControls: 1)
        )
        assertMatrixError(
            .countLimitExceeded(kind: "lifecycleRows", maximum: 1),
            controls: [one],
            source: "test-source",
            limits: Limits(maximumLifecycleRows: 1)
        )
        assertMatrixError(
            .countLimitExceeded(kind: "interactionRoutes", maximum: 1),
            controls: [one],
            source: "test-source",
            limits: Limits(maximumInteractionRows: 1)
        )
        assertMatrixError(
            .countLimitExceeded(kind: "screenshots", maximum: 1),
            controls: [one],
            source: "test-source",
            limits: Limits(maximumScreenshots: 1)
        )
        assertMatrixError(
            .stringTooLarge(field: "source", maximumUTF8Bytes: 1),
            controls: [one],
            source: "test-source",
            limits: Limits(maximumStringUTF8Bytes: 1)
        )
        assertMatrixError(
            .workLimitExceeded(maximum: 1),
            controls: [one],
            source: "test-source",
            limits: Limits(maximumWorkUnits: 1)
        )
    }

    func testMakeMatrixCancellationAborts() {
        XCTAssertThrowsError(
            try InteractionMatrix.makeMatrix(
                controls: [makePrimaryControl()],
                semanticBindings: [:],
                source: "test-source",
                limits: Limits(),
                cancellationCheck: { throw ProbeCancellation() }
            )
        ) { error in
            XCTAssertEqual(error as? MatrixError, .cancelled)
        }
    }

    private func makeControl(
        command: Command,
        suffix: String,
        secondaries: [String] = []
    ) -> InteractionMatrix.ControlDescriptor {
        InteractionMatrix.ControlDescriptor(
            controlID: StableID(rawValue: "test.toolbar.control.\(suffix)"),
            command: command,
            primaryActionID: StableID(rawValue: "test.toolbar.action.\(suffix).primary"),
            secondaryActionIDs: secondaries.map { StableID(rawValue: "test.toolbar.action.\(suffix).\($0)") }
        )
    }

    private func makePrimaryControl(
        command: Command = .save,
        suffix: String = "primary"
    ) -> InteractionMatrix.ControlDescriptor {
        makeControl(command: command, suffix: suffix)
    }

    private func makeMenuControl() -> (InteractionMatrix.ControlDescriptor, [StableID: SemanticCommand]) {
        let control = makeControl(command: .copyToRight, suffix: "copy", secondaries: ["first", "second"])
        let bindings: [StableID: SemanticCommand] = [
            control.secondaryActionIDs[0]: .copyAllToRight,
            control.secondaryActionIDs[1]: .copyAllToLeft
        ]
        return (control, bindings)
    }

    private func makeMatrix(
        controls: [InteractionMatrix.ControlDescriptor],
        bindings: [StableID: SemanticCommand] = [:],
        source: String = "test-source",
        limits: Limits = Limits()
    ) throws -> InteractionMatrix.Matrix {
        try InteractionMatrix.makeMatrix(
            controls: controls,
            semanticBindings: bindings,
            source: source,
            limits: limits,
            cancellationCheck: {}
        )
    }

    private func assertMatrixError(
        _ expected: MatrixError,
        controls: [InteractionMatrix.ControlDescriptor],
        bindings: [StableID: SemanticCommand] = [:],
        source: String,
        limits: Limits = Limits(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try InteractionMatrix.makeMatrix(
                controls: controls,
                semanticBindings: bindings,
                source: source,
                limits: limits,
                cancellationCheck: {}
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? MatrixError, expected, file: file, line: line)
        }
    }
}

private struct ProbeCancellation: Error {}
