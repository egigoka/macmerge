import Foundation
import MacMergeCore
import XCTest

final class ToolbarAuditContractTests: XCTestCase {
    func testCanonicalManifestPreservesCommandOrderGroupsAndSeparatorBoundaries() {
        let expectedGroups: [[ToolbarAuditCommand]] = [
            [.newComparison, .openComparison, .save],
            [.undo, .redo],
            [.selectLineDifference],
            [.nextDifference, .previousDifference],
            [.nextConflict, .previousConflict],
            [.firstDifference, .currentDifference, .lastDifference],
            [.copyToRight, .copyToLeft],
            [.copyToRightAndAdvance, .copyToLeftAndAdvance],
            [.copyAllToRight, .copyAllToLeft],
            [.autoMerge],
            [.firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile],
            [.options],
            [.refresh]
        ]

        let manifest = ToolbarAuditManifest.canonical

        XCTAssertEqual(manifest.revision, ToolbarAuditManifest.canonicalRevision)
        XCTAssertEqual(manifest.items, ToolbarConfiguration.winMergeDefaultItems)
        XCTAssertEqual(manifest.items.count, 39)
        XCTAssertEqual(manifest.commands, ToolbarAuditCommand.allCases)
        XCTAssertEqual(manifest.groups.map(\.commands), expectedGroups)
        XCTAssertTrue(manifest.groups.allSatisfy(\.hasTrailingSeparator))
        XCTAssertEqual(manifest.groups.flatMap(\.items), manifest.items)
    }

    func testCompleteContractCoversActionsPresentationLifecycleInteractionsAndScreenshots() throws {
        let fixture = makeFixture()
        let contract = fixture.contract
        let allActionIDs = contract.controls.flatMap(\.behavior.allActionIDs)

        XCTAssertEqual(contract.controls.map(\.command), contract.manifest.commands)
        XCTAssertEqual(Set(allActionIDs).count, allActionIDs.count)
        XCTAssertEqual(
            contract.lifecycleExpectations.count,
            ToolbarAuditLifecycleScenario.allCases.count * allActionIDs.count
        )
        for scenario in ToolbarAuditLifecycleScenario.allCases {
            for control in contract.controls {
                for actionID in control.behavior.allActionIDs {
                    let matches = contract.lifecycleExpectations.filter {
                        $0.scenario == scenario
                            && $0.command == control.command
                            && $0.actionID == actionID
                    }
                    XCTAssertEqual(matches.count, 1, "\(scenario.rawValue)/\(actionID.rawValue)")
                    XCTAssertEqual(matches.first?.availability.isEnabled, scenario != .empty)
                }
            }
        }

        let save = try XCTUnwrap(contract.controls.first { $0.command == .save })
        XCTAssertEqual(save.behavior.primaryActionID, primaryActionID(.save))
        XCTAssertEqual(save.behavior.secondary.actionIDs, saveSecondaryActionIDs)
        XCTAssertEqual(save.behavior.allActionIDs, [primaryActionID(.save)] + saveSecondaryActionIDs)
        XCTAssertEqual(save.shortcut?.canonicalChord, "command:1:s")
        XCTAssertEqual(save.shortcut?.display, "Command-S")
        for control in contract.controls {
            XCTAssertFalse(control.tooltip.isEmpty)
            XCTAssertEqual(control.accessibility.identifier, control.id)
            XCTAssertEqual(control.accessibility.role, .button)
            XCTAssertFalse(control.accessibility.label.isEmpty)
            XCTAssertFalse(control.accessibility.hint.isEmpty)
            XCTAssertNil(control.accessibility.isEnabled)
            XCTAssertTrue(control.accessibility.isKeyboardFocusable)
            XCTAssertEqual(control.accessibility.actions, [.activate])
        }
        if case .menu(let actions) = save.behavior.secondary {
            XCTAssertEqual(actions.map(\.id), saveSecondaryActionIDs)
            XCTAssertTrue(actions.allSatisfy { $0.accessibility.role == .menuItem })
            XCTAssertTrue(actions.allSatisfy { $0.accessibility.isEnabled == nil })
            XCTAssertTrue(actions.allSatisfy { $0.accessibility.actions == [.activate] })
        } else {
            XCTFail("Save control must expose ordered secondary actions")
        }

        XCTAssertEqual(
            Set(contract.interactionExpectations.map(\.invocation)),
            Set(ToolbarAuditInvocationKind.allCases)
        )
        XCTAssertEqual(
            contract.screenshotExpectations,
            ToolbarAuditContract.requiredScreenshotExpectations
        )
        XCTAssertEqual(
            contract.screenshotExpectations.map(\.context),
            ToolbarAuditScreenshotContext.allCases
        )
        XCTAssertTrue(contract.screenshotExpectations.allSatisfy(\.requiresAccessibilitySidecar))

        let report = try contract.audit(evidence: fixture.evidence)
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.formatVersion, ToolbarAudit.reportFormatVersion)
        XCTAssertEqual(report.contractRevision, contract.revision)
        XCTAssertEqual(report.manifestRevision, contract.manifest.revision)
        XCTAssertEqual(
            ToolbarAuditReport.scopeStatement,
            "Static checks of caller-supplied toolbar requirements and evidence; not runtime UI or VoiceOver conformance."
        )
    }

    func testPrimarySecondaryTooltipShortcutAndAXViolationsHaveSpecificFindings() throws {
        let fixture = makeFixture()
        let scenario = ToolbarAuditLifecycleScenario.different
        let saveID = controlID(.save)
        let missingPresentation = replacingControl(
            in: fixture.evidence,
            scenario: scenario,
            command: .save
        ) { observation in
            ToolbarAuditControlObservation(
                id: observation.id,
                command: observation.command,
                behavior: observation.behavior,
                tooltip: nil,
                shortcut: nil,
                accessibility: ToolbarAuditAXMetadata(
                    identifier: id("wrong.save.ax"),
                    role: .menuItem,
                    label: "Wrong save label",
                    value: "Wrong value",
                    hint: "Wrong save hint",
                    isEnabled: false,
                    checkedState: .on,
                    selectedState: .selected,
                    isKeyboardFocusable: false,
                    actions: [.showMenu]
                ),
                availability: .disabled(reason: id("wrong.availability"))
            )
        }

        let missingReport = try fixture.contract.audit(evidence: missingPresentation)
        XCTAssertEqual(
            Set(missingReport.findings.map(\.code)),
            [
                .accessibilityActionsMismatch,
                .accessibilityCheckedStateMismatch,
                .accessibilityEnabledStateMismatch,
                .accessibilityFocusMismatch,
                .accessibilityHintMismatch,
                .accessibilityIdentifierMismatch,
                .accessibilityLabelMismatch,
                .accessibilityRoleMismatch,
                .accessibilitySelectedStateMismatch,
                .accessibilityValueMismatch,
                .availabilityMismatch,
                .shortcutMissing,
                .tooltipMissing
            ]
        )
        XCTAssertTrue(missingReport.findings.allSatisfy { $0.subjectID == saveID })

        let wrongText = replacingControl(
            in: fixture.evidence,
            scenario: scenario,
            command: .save
        ) { observation in
            ToolbarAuditControlObservation(
                id: observation.id,
                command: observation.command,
                behavior: observation.behavior,
                tooltip: "Wrong tooltip",
                shortcut: ToolbarAuditShortcut(
                    key: "x",
                    modifiers: [.command],
                    display: "Command-X"
                ),
                accessibility: observation.accessibility,
                availability: observation.availability
            )
        }
        let wrongTextReport = try fixture.contract.audit(evidence: wrongText)
        XCTAssertEqual(
            Set(wrongTextReport.findings.map(\.code)),
            [.shortcutMismatch, .tooltipMismatch]
        )

        let wrongBehavior = replacingControl(
            in: fixture.evidence,
            scenario: scenario,
            command: .save
        ) { observation in
            guard case .menu(let actions) = observation.behavior.secondary else {
                return observation
            }
            let changed = ToolbarAuditSecondaryAction(
                id: actions[0].id,
                accessibility: ToolbarAuditAXMetadata(
                    identifier: actions[0].accessibility.identifier,
                    role: actions[0].accessibility.role,
                    label: "Wrong secondary label",
                    value: actions[0].accessibility.value,
                    hint: actions[0].accessibility.hint,
                    isEnabled: false,
                    checkedState: actions[0].accessibility.checkedState,
                    selectedState: actions[0].accessibility.selectedState,
                    isKeyboardFocusable: actions[0].accessibility.isKeyboardFocusable,
                    actions: actions[0].accessibility.actions
                )
            )
            return ToolbarAuditControlObservation(
                id: observation.id,
                command: observation.command,
                behavior: ToolbarAuditControlBehavior(
                    primaryActionID: id("wrong.save.primary"),
                    secondary: .menu(actions: [actions[1], changed])
                ),
                tooltip: observation.tooltip,
                shortcut: observation.shortcut,
                accessibility: observation.accessibility,
                availability: observation.availability
            )
        }
        let behaviorReport = try fixture.contract.audit(evidence: wrongBehavior)
        XCTAssertEqual(
            Set(behaviorReport.findings.map(\.code)),
            [
                .primaryBehaviorMismatch,
                .secondaryAccessibilityMismatch,
                .secondaryAvailabilityMismatch,
                .secondaryBehaviorMismatch
            ]
        )
    }

    func testLifecycleAvailabilityAndEnabledStateAreCheckedIndependently() throws {
        let fixture = makeFixture()
        let enabledStateOnly = replacingControl(
            in: fixture.evidence,
            scenario: .empty,
            command: .openComparison
        ) { observation in
            ToolbarAuditControlObservation(
                id: observation.id,
                command: observation.command,
                behavior: observation.behavior,
                tooltip: observation.tooltip,
                shortcut: observation.shortcut,
                accessibility: withEnabled(observation.accessibility, true),
                availability: observation.availability
            )
        }

        let enabledStateReport = try fixture.contract.audit(evidence: enabledStateOnly)

        XCTAssertEqual(
            findingTuples(enabledStateReport),
            [
                findingTuple(
                    code: .accessibilityEnabledStateMismatch,
                    command: .openComparison,
                    scenario: .empty,
                    subjectID: controlID(.openComparison),
                    message: "Observed semantic accessibility metadata differs from its requirement."
                )
            ]
        )

        let availabilityOnly = replacingControl(
            in: fixture.evidence,
            scenario: .empty,
            command: .openComparison
        ) { observation in
            ToolbarAuditControlObservation(
                id: observation.id,
                command: observation.command,
                behavior: observation.behavior,
                tooltip: observation.tooltip,
                shortcut: observation.shortcut,
                accessibility: observation.accessibility,
                availability: .enabled
            )
        }
        let availabilityReport = try fixture.contract.audit(evidence: availabilityOnly)

        XCTAssertEqual(
            findingTuples(availabilityReport),
            [
                findingTuple(
                    code: .availabilityMismatch,
                    command: .openComparison,
                    scenario: .empty,
                    subjectID: controlID(.openComparison),
                    message: "Observed availability differs from the lifecycle matrix."
                )
            ]
        )
    }

    func testEveryLifecycleScenarioReportsInjectedMismatchAndOmittedEvidence() throws {
        let fixture = makeFixture()
        let command = ToolbarAuditCommand.openComparison

        for scenario in ToolbarAuditLifecycleScenario.allCases {
            let expectedEnabled = scenario != .empty
            let mismatched = replacingControl(
                in: fixture.evidence,
                scenario: scenario,
                command: command
            ) { observation in
                ToolbarAuditControlObservation(
                    id: observation.id,
                    command: observation.command,
                    behavior: observation.behavior,
                    tooltip: observation.tooltip,
                    shortcut: observation.shortcut,
                    accessibility: withEnabled(observation.accessibility, !expectedEnabled),
                    availability: expectedEnabled
                        ? .disabled(reason: id("injected.\(scenario.rawValue)"))
                        : .enabled
                )
            }
            let mismatchReport = try fixture.contract.audit(evidence: mismatched)

            XCTAssertEqual(
                findingTuples(mismatchReport),
                [
                    findingTuple(
                        code: .accessibilityEnabledStateMismatch,
                        command: command,
                        scenario: scenario,
                        subjectID: controlID(command),
                        message: "Observed semantic accessibility metadata differs from its requirement."
                    ),
                    findingTuple(
                        code: .availabilityMismatch,
                        command: command,
                        scenario: scenario,
                        subjectID: controlID(command),
                        message: "Observed availability differs from the lifecycle matrix."
                    )
                ],
                scenario.rawValue
            )

            let omitted = replacingSurfaces(
                in: fixture.evidence,
                with: fixture.evidence.surfaces.filter { $0.scenario != scenario }
            )
            let omissionReport = try fixture.contract.audit(evidence: omitted)

            XCTAssertEqual(
                findingTuples(omissionReport),
                [
                    findingTuple(
                        code: .lifecycleEvidenceMissing,
                        scenario: scenario,
                        message: "Lifecycle matrix row has no toolbar surface evidence."
                    )
                ],
                scenario.rawValue
            )
        }
    }

    func testCommandOrderMismatchDoesNotFalselyReportGroupingMismatch() throws {
        let fixture = makeFixture()
        var sameBoundaries = fixture.contract.manifest.items
        sameBoundaries.swapAt(0, 1)
        let surfaceEvidence = replacingItems(
            in: fixture.evidence,
            scenario: .different,
            items: sameBoundaries
        )
        let surfaceReport = try fixture.contract.audit(evidence: surfaceEvidence)

        XCTAssertEqual(findings(.commandOrderMismatch, in: surfaceReport).count, 1)
        XCTAssertTrue(findings(.commandGroupingMismatch, in: surfaceReport).isEmpty)

        let screenshotEvidence = replacingScreenshotItems(
            in: fixture.evidence,
            context: .loadedComparison,
            items: sameBoundaries
        )
        let screenshotReport = try fixture.contract.audit(evidence: screenshotEvidence)

        XCTAssertEqual(findings(.screenshotOrderMismatch, in: screenshotReport).count, 1)
        XCTAssertTrue(findings(.screenshotGroupingMismatch, in: screenshotReport).isEmpty)
    }

    func testTrailingSeparatorRemovalIsGroupingOnlyForSurfaceAndScreenshot() throws {
        let fixture = makeFixture()
        var withoutTrailingSeparator = fixture.contract.manifest.items
        XCTAssertEqual(withoutTrailingSeparator.removeLast(), .separator)
        let groupedSurface = replacingItems(
            in: fixture.evidence,
            scenario: .loadedSurfaceScenario,
            items: withoutTrailingSeparator
        )
        let groupedReport = try fixture.contract.audit(evidence: groupedSurface)

        XCTAssertEqual(groupedReport.findings.map(\.code), [.commandGroupingMismatch])

        let screenshot = try XCTUnwrap(
            fixture.evidence.screenshots.first { $0.context == .freshWindow }
        )
        let missingSidecar = replacingScreenshot(
            in: fixture.evidence,
            context: .freshWindow,
            with: ToolbarAuditScreenshotEvidence(
                context: screenshot.context,
                manifestRevision: screenshot.manifestRevision,
                items: withoutTrailingSeparator,
                screenshotDigest: screenshot.screenshotDigest,
                accessibilitySidecarDigest: screenshot.accessibilitySidecarDigest,
                source: screenshot.source
            )
        )
        let screenshotReport = try fixture.contract.audit(evidence: missingSidecar)

        XCTAssertEqual(screenshotReport.findings.map(\.code), [.screenshotGroupingMismatch])
    }

    func testScreenshotSidecarsAndMissingEvidenceUseContextFramedIDs() throws {
        let fixture = makeFixture()
        let withoutSidecars = ToolbarAuditEvidence(
            contractRevision: fixture.evidence.contractRevision,
            surfaces: fixture.evidence.surfaces,
            interactions: fixture.evidence.interactions,
            screenshots: fixture.evidence.screenshots.map { screenshot in
                ToolbarAuditScreenshotEvidence(
                    context: screenshot.context,
                    manifestRevision: screenshot.manifestRevision,
                    items: screenshot.items,
                    screenshotDigest: screenshot.screenshotDigest,
                    accessibilitySidecarDigest: nil,
                    source: screenshot.source
                )
            }
        )
        let sidecarReport = try fixture.contract.audit(evidence: withoutSidecars)

        XCTAssertEqual(
            findingTuples(sidecarReport),
            ToolbarAuditScreenshotContext.allCases.map { context in
                findingTuple(
                    code: .screenshotAccessibilitySidecarMissing,
                    discriminator: context.rawValue,
                    message: "Screenshot evidence has no required semantic AX sidecar digest."
                )
            }
        )
        XCTAssertEqual(Set(sidecarReport.findings.map(\.id)).count, 2)

        var missingIDs: [ToolbarAuditFinding.ID] = []
        for context in ToolbarAuditScreenshotContext.allCases {
            let missingContext = ToolbarAuditEvidence(
                contractRevision: fixture.evidence.contractRevision,
                surfaces: fixture.evidence.surfaces,
                interactions: fixture.evidence.interactions,
                screenshots: fixture.evidence.screenshots.filter { $0.context != context }
            )
            let missingReport = try fixture.contract.audit(evidence: missingContext)
            let expected = findingTuple(
                code: .screenshotEvidenceMissing,
                discriminator: context.rawValue,
                message: "Required screenshot context has no evidence."
            )

            XCTAssertEqual(findingTuples(missingReport), [expected], context.rawValue)
            missingIDs.append(try XCTUnwrap(missingReport.findings.first?.id))
        }
        XCTAssertEqual(Set(missingIDs).count, 2)
    }

    func testLifecycleControlAndInteractionOmissionsHaveExactFindings() throws {
        let fixture = makeFixture()
        let lifecycleScenario = ToolbarAuditLifecycleScenario.failed
        let missingLifecycle = replacingSurfaces(
            in: fixture.evidence,
            with: fixture.evidence.surfaces.filter { $0.scenario != lifecycleScenario }
        )
        let lifecycleReport = try fixture.contract.audit(evidence: missingLifecycle)

        XCTAssertEqual(
            findingTuples(lifecycleReport),
            [
                findingTuple(
                    code: .lifecycleEvidenceMissing,
                    scenario: lifecycleScenario,
                    message: "Lifecycle matrix row has no toolbar surface evidence."
                )
            ]
        )

        let controlScenario = ToolbarAuditLifecycleScenario.dirty
        let missingControl = replacingControls(
            in: fixture.evidence,
            scenario: controlScenario,
            with: { $0.filter { $0.command != .refresh } }
        )
        let controlReport = try fixture.contract.audit(evidence: missingControl)

        XCTAssertEqual(
            findingTuples(controlReport),
            [
                findingTuple(
                    code: .controlEvidenceMissing,
                    command: .refresh,
                    scenario: controlScenario,
                    subjectID: controlID(.refresh),
                    message: "Toolbar control has no evidence in this lifecycle scenario."
                )
            ]
        )

        let actionID = primaryActionID(.save)
        let missingInteraction = replacingInteractions(
            in: fixture.evidence,
            with: fixture.evidence.interactions.filter {
                !($0.scenario == .different
                    && $0.controlID == controlID(.save)
                    && $0.actionID == actionID
                    && $0.invocation == .primaryClick)
            }
        )
        let interactionReport = try fixture.contract.audit(evidence: missingInteraction)

        XCTAssertEqual(
            findingTuples(interactionReport),
            [
                findingTuple(
                    code: .interactionEvidenceMissing,
                    scenario: .different,
                    subjectID: controlID(.save),
                    discriminator: framed(
                        ToolbarAuditInvocationKind.primaryClick.rawValue,
                        actionID.rawValue
                    ),
                    message: "Required interaction has no evidence."
                )
            ]
        )
    }

    func testEvidenceArchiveRoundTripsCanonicalizesOrderAndRejectsCorruption() throws {
        let fixture = makeFixture()
        let archive = try fixture.evidence.encodedData()
        let decoded = try ToolbarAuditEvidence.decode(from: archive)

        XCTAssertEqual(decoded, fixture.evidence)
        XCTAssertEqual(try decoded.encodedData(), archive)

        let reordered = reorderedEvidence(fixture.evidence)
        XCTAssertEqual(try reordered.encodedData(), archive)
        XCTAssertEqual(try ToolbarAuditEvidence.decode(from: reordered.encodedData()), fixture.evidence)

        var corrupt = archive
        let lastIndex = corrupt.index(before: corrupt.endIndex)
        corrupt[lastIndex] = corrupt[lastIndex] ^ 0x01
        assertToolbarError(.archiveChecksumMismatch) {
            try ToolbarAuditEvidence.decode(from: corrupt)
        }
    }

    func testStaleCancellationCountArchiveAndWorkGuardsFailClosed() throws {
        let fixture = makeFixture()
        let staleRevision = ToolbarAuditRevision(rawValue: fixture.contract.revision.rawValue + 1)
        let staleEvidence = ToolbarAuditEvidence(
            contractRevision: staleRevision,
            surfaces: fixture.evidence.surfaces,
            interactions: fixture.evidence.interactions,
            screenshots: fixture.evidence.screenshots
        )
        assertToolbarError(
            .staleEvidence(expected: fixture.contract.revision, actual: staleRevision)
        ) {
            try fixture.contract.audit(evidence: staleEvidence)
        }

        let staleManifestRevision = ToolbarAuditRevision(
            rawValue: fixture.contract.manifest.revision.rawValue + 1
        )
        let staleSurface = replacingManifestRevision(
            in: fixture.evidence,
            scenario: .empty,
            revision: staleManifestRevision
        )
        assertToolbarError(
            .staleManifest(
                expected: fixture.contract.manifest.revision,
                actual: staleManifestRevision
            )
        ) {
            try fixture.contract.audit(evidence: staleSurface)
        }

        assertToolbarError(.cancelled) {
            try fixture.contract.audit(evidence: fixture.evidence) {
                throw CancellationError()
            }
        }
        assertToolbarError(.cancelled) {
            try fixture.evidence.encodedData {
                throw CancellationError()
            }
        }

        assertToolbarError(
            .invalidLimit(
                name: "maximumControls",
                value: ToolbarAuditLimits.hardMaximumControls + 1,
                maximum: ToolbarAuditLimits.hardMaximumControls
            )
        ) {
            try fixture.contract.audit(
                evidence: fixture.evidence,
                limits: ToolbarAuditLimits(
                    maximumControls: ToolbarAuditLimits.hardMaximumControls + 1
                )
            )
        }
        assertToolbarError(
            .countLimitExceeded(
                kind: "control",
                maximum: fixture.contract.controls.count - 1
            )
        ) {
            try fixture.contract.audit(
                evidence: fixture.evidence,
                limits: ToolbarAuditLimits(
                    maximumControls: fixture.contract.controls.count - 1
                )
            )
        }
        assertToolbarError(.workLimitExceeded(maximum: 1)) {
            try fixture.contract.audit(
                evidence: fixture.evidence,
                limits: ToolbarAuditLimits(maximumWorkUnits: 1)
            )
        }

        let archive = try fixture.evidence.encodedData()
        assertToolbarError(.archiveTooLarge(maximumBytes: archive.count - 1)) {
            try ToolbarAuditEvidence.decode(
                from: archive,
                limits: ToolbarAuditLimits(maximumArchiveBytes: archive.count - 1)
            )
        }
    }

    func testInvokedActionMismatchAndDisabledSuccessFindingsHaveUniqueDeterministicIDs() throws {
        let fixture = makeFixture()
        let savePrimary = primaryActionID(.save)
        let secondary = saveSecondaryActionIDs[0]
        let interactions = fixture.evidence.interactions.map { interaction in
            let outcome: ToolbarAuditInteractionOutcome
            switch (
                interaction.scenario,
                interaction.actionID,
                interaction.invocation
            ) {
            case (.different, savePrimary, .primaryClick):
                outcome = .invoked(actionID: secondary)
            case (.empty, savePrimary, .disabledActivation):
                outcome = .invoked(actionID: savePrimary)
            case (.empty, secondary, .disabledActivation):
                outcome = .invoked(actionID: secondary)
            default:
                return interaction
            }
            return ToolbarAuditInteractionEvidence(
                scenario: interaction.scenario,
                controlID: interaction.controlID,
                actionID: interaction.actionID,
                invocation: interaction.invocation,
                outcome: outcome,
                source: interaction.source
            )
        }
        let mismatched = ToolbarAuditEvidence(
            contractRevision: fixture.evidence.contractRevision,
            surfaces: fixture.evidence.surfaces,
            interactions: interactions,
            screenshots: fixture.evidence.screenshots
        )

        let report = try fixture.contract.audit(evidence: mismatched)
        let reorderedReport = try fixture.contract.audit(evidence: reorderedEvidence(mismatched))
        let ids = report.findings.map(\.id)

        XCTAssertEqual(findings(.interactionOutcomeMismatch, in: report).count, 4)
        XCTAssertEqual(findings(.disabledActivationSucceeded, in: report).count, 2)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(report, reorderedReport)
        XCTAssertEqual(report.findings.map(\.id), reorderedReport.findings.map(\.id))
    }

    func testFindingsUseExplicitDeterministicOrderAcrossMixedSeverities() throws {
        let fixture = makeFixture()
        let contract = ToolbarAuditContract(
            revision: fixture.contract.revision,
            controls: fixture.contract.controls,
            lifecycleExpectations: fixture.contract.lifecycleExpectations,
            interactionExpectations: fixture.contract.interactionExpectations,
            screenshotExpectations: [
                ToolbarAuditScreenshotExpectation(context: .loadedComparison)
            ]
        )

        let report = try contract.audit(evidence: fixture.evidence)

        XCTAssertEqual(
            findingTuples(report),
            [
                findingTuple(
                    severity: .error,
                    code: .screenshotRequirementMissing,
                    discriminator: ToolbarAuditScreenshotContext.freshWindow.rawValue,
                    message: "Screenshot contract has no freshWindow expectation."
                ),
                findingTuple(
                    severity: .warning,
                    code: .unexpectedScreenshotEvidence,
                    discriminator: ToolbarAuditScreenshotContext.freshWindow.rawValue,
                    message: "Screenshot evidence has no matching contract expectation."
                )
            ]
        )
        XCTAssertEqual(report.highestSeverity, .error)
        XCTAssertTrue(report.containsErrors)
    }

    func testFindingIDsFrameVariableLengthComponentsAtBoundaryCollisions() throws {
        let fixture = makeFixture()
        let control = controlID(.openComparison)
        let records = [
            (actionID: id("a"), invokedID: id("bc")),
            (actionID: id("ab"), invokedID: id("c"))
        ]
        let interactions =
            fixture.evidence.interactions
            + records.map { record in
                ToolbarAuditInteractionEvidence(
                    scenario: .different,
                    controlID: control,
                    actionID: record.actionID,
                    invocation: .primaryClick,
                    outcome: .invoked(actionID: record.invokedID),
                    source: "interaction.boundary.\(record.actionID.rawValue)"
                )
            }
        let evidence = replacingInteractions(in: fixture.evidence, with: interactions)

        let report = try fixture.contract.audit(evidence: evidence)
        let expected = records.map { record in
            findingTuple(
                code: .interactionOutcomeMismatch,
                scenario: .different,
                subjectID: control,
                discriminator: framed(
                    "recordIdentity",
                    ToolbarAuditInvocationKind.primaryClick.rawValue,
                    record.actionID.rawValue,
                    record.invokedID.rawValue
                ),
                message: "Observed interaction invoked a different action than its record identity."
            )
        }

        XCTAssertEqual(findingTuples(report), expected)
        XCTAssertEqual(Set(report.findings.map(\.id)).count, records.count)
    }

    func testPrimaryAndSecondaryActionsCanHaveMixedAvailabilityInOneScenario() throws {
        let fixture = makeFixture()
        let scenario = ToolbarAuditLifecycleScenario.loading
        let secondaryID = saveSecondaryActionIDs[0]
        let lifecycle = fixture.contract.lifecycleExpectations.map { expectation in
            guard expectation.scenario == scenario,
                expectation.command == .save,
                expectation.actionID == secondaryID
            else { return expectation }
            return ToolbarAuditLifecycleExpectation(
                scenario: expectation.scenario,
                command: expectation.command,
                actionID: expectation.actionID,
                availability: .disabled(reason: id("loading.secondary"))
            )
        }
        let blockedExpectation = ToolbarAuditInteractionExpectation(
            scenario: scenario,
            controlID: controlID(.save),
            actionID: secondaryID,
            invocation: .disabledActivation,
            outcome: .blocked
        )
        let contract = ToolbarAuditContract(
            revision: fixture.contract.revision,
            controls: fixture.contract.controls,
            lifecycleExpectations: lifecycle,
            interactionExpectations: fixture.contract.interactionExpectations + [blockedExpectation]
        )
        let mixedSurface = replacingControl(
            in: fixture.evidence,
            scenario: scenario,
            command: .save
        ) { observation in
            guard case .menu(let actions) = observation.behavior.secondary else {
                return observation
            }
            let mixedActions = actions.map { action in
                ToolbarAuditSecondaryAction(
                    id: action.id,
                    accessibility: withEnabled(
                        action.accessibility,
                        action.id != secondaryID
                    )
                )
            }
            return ToolbarAuditControlObservation(
                id: observation.id,
                command: observation.command,
                behavior: ToolbarAuditControlBehavior(
                    primaryActionID: observation.behavior.primaryActionID,
                    secondary: .menu(actions: mixedActions)
                ),
                tooltip: observation.tooltip,
                shortcut: observation.shortcut,
                accessibility: observation.accessibility,
                availability: observation.availability
            )
        }
        let matchingEvidence = replacingInteractions(
            in: mixedSurface,
            with: mixedSurface.interactions + [
                ToolbarAuditInteractionEvidence(
                    scenario: scenario,
                    controlID: controlID(.save),
                    actionID: secondaryID,
                    invocation: .disabledActivation,
                    outcome: .blocked,
                    source: "interaction.loading.secondary"
                )
            ]
        )

        XCTAssertTrue(try contract.audit(evidence: matchingEvidence).passed)

        let mismatchedEvidence = replacingControl(
            in: matchingEvidence,
            scenario: scenario,
            command: .save
        ) { observation in
            guard case .menu(let actions) = observation.behavior.secondary else {
                return observation
            }
            let allEnabled = actions.map { action in
                ToolbarAuditSecondaryAction(
                    id: action.id,
                    accessibility: withEnabled(action.accessibility, true)
                )
            }
            return ToolbarAuditControlObservation(
                id: observation.id,
                command: observation.command,
                behavior: ToolbarAuditControlBehavior(
                    primaryActionID: observation.behavior.primaryActionID,
                    secondary: .menu(actions: allEnabled)
                ),
                tooltip: observation.tooltip,
                shortcut: observation.shortcut,
                accessibility: observation.accessibility,
                availability: observation.availability
            )
        }
        let mismatchReport = try contract.audit(evidence: mismatchedEvidence)

        XCTAssertEqual(
            findingTuples(mismatchReport),
            [
                findingTuple(
                    code: .secondaryAvailabilityMismatch,
                    command: .save,
                    scenario: scenario,
                    subjectID: secondaryID,
                    message: "Secondary action enabled state differs from the lifecycle matrix."
                )
            ]
        )
    }

    private func makeFixture() -> Fixture {
        let revision = ToolbarAuditRevision(rawValue: 17)
        let controls = ToolbarAuditManifest.canonical.commands.map(makeRequirement)
        let lifecycle = ToolbarAuditLifecycleScenario.allCases.flatMap { scenario in
            controls.flatMap { control in
                control.behavior.allActionIDs.map { actionID in
                    ToolbarAuditLifecycleExpectation(
                        scenario: scenario,
                        command: control.command,
                        actionID: actionID,
                        availability: availability(for: scenario)
                    )
                }
            }
        }
        let interactions = controls.flatMap(makeInteractionExpectations)
        let contract = ToolbarAuditContract(
            revision: revision,
            controls: controls,
            lifecycleExpectations: lifecycle,
            interactionExpectations: interactions
        )
        let surfaces = ToolbarAuditLifecycleScenario.allCases.map { scenario in
            ToolbarAuditSurfaceEvidence(
                scenario: scenario,
                manifestRevision: contract.manifest.revision,
                items: contract.manifest.items,
                controls: controls.map { observation(for: $0, scenario: scenario) },
                source: "surface.\(scenario.rawValue)"
            )
        }
        let interactionEvidence = interactions.map {
            ToolbarAuditInteractionEvidence(
                scenario: $0.scenario,
                controlID: $0.controlID,
                actionID: $0.actionID,
                invocation: $0.invocation,
                outcome: $0.outcome,
                source: "interaction.\($0.invocation.rawValue)"
            )
        }
        let screenshots = ToolbarAuditScreenshotContext.allCases.map { context in
            ToolbarAuditScreenshotEvidence(
                context: context,
                manifestRevision: contract.manifest.revision,
                items: contract.manifest.items,
                screenshotDigest: digest(context == .freshWindow ? "a" : "b"),
                accessibilitySidecarDigest: digest(context == .freshWindow ? "c" : "d"),
                source: "screenshot.\(context.rawValue)"
            )
        }
        return Fixture(
            contract: contract,
            evidence: ToolbarAuditEvidence(
                contractRevision: revision,
                surfaces: surfaces,
                interactions: interactionEvidence,
                screenshots: screenshots
            )
        )
    }

    private func makeRequirement(_ command: ToolbarAuditCommand) -> ToolbarAuditControlRequirement {
        let secondary: ToolbarAuditSecondaryBehavior
        if command == .save {
            secondary = .menu(
                actions: saveSecondaryActionIDs.enumerated().map { index, actionID in
                    ToolbarAuditSecondaryAction(
                        id: actionID,
                        accessibility: ToolbarAuditAXMetadata(
                            identifier: actionID,
                            role: .menuItem,
                            label: "Save secondary \(index + 1)",
                            hint: "Runs save secondary action \(index + 1)"
                        )
                    )
                }
            )
        } else {
            secondary = .none
        }
        let shortcut =
            command == .save
            ? ToolbarAuditShortcut(key: "s", modifiers: [.command], display: "Command-S")
            : nil
        return ToolbarAuditControlRequirement(
            id: controlID(command),
            command: command,
            behavior: ToolbarAuditControlBehavior(
                primaryActionID: primaryActionID(command),
                secondary: secondary
            ),
            tooltip: "\(command.rawValue) tooltip",
            shortcut: shortcut,
            accessibility: ToolbarAuditAXMetadata(
                identifier: controlID(command),
                label: "Toolbar \(command.rawValue)",
                hint: "Runs \(command.rawValue)"
            )
        )
    }

    private func makeInteractionExpectations(
        _ control: ToolbarAuditControlRequirement
    ) -> [ToolbarAuditInteractionExpectation] {
        let primary = control.behavior.primaryActionID
        var expectations = [
            ToolbarAuditInteractionExpectation(
                scenario: .different,
                controlID: control.id,
                actionID: primary,
                invocation: .primaryClick,
                outcome: .invoked(actionID: primary)
            ),
            ToolbarAuditInteractionExpectation(
                scenario: .different,
                controlID: control.id,
                actionID: primary,
                invocation: .keyboardActivation,
                outcome: .invoked(actionID: primary)
            ),
            ToolbarAuditInteractionExpectation(
                scenario: .different,
                controlID: control.id,
                actionID: primary,
                invocation: .voiceOverActivation,
                outcome: .invoked(actionID: primary)
            )
        ]
        if case .menu(let actions) = control.behavior.secondary {
            expectations.append(
                ToolbarAuditInteractionExpectation(
                    scenario: .different,
                    controlID: control.id,
                    actionID: primary,
                    invocation: .menuArrowClick,
                    outcome: .menuPresented(actionIDs: actions.map(\.id))
                )
            )
            expectations.append(
                contentsOf: actions.map { action in
                    ToolbarAuditInteractionExpectation(
                        scenario: .different,
                        controlID: control.id,
                        actionID: action.id,
                        invocation: .menuItemSelection,
                        outcome: .invoked(actionID: action.id)
                    )
                }
            )
        }
        expectations.append(
            contentsOf: control.behavior.allActionIDs.map { actionID in
                ToolbarAuditInteractionExpectation(
                    scenario: .empty,
                    controlID: control.id,
                    actionID: actionID,
                    invocation: .disabledActivation,
                    outcome: .blocked
                )
            }
        )
        return expectations
    }

    private func observation(
        for requirement: ToolbarAuditControlRequirement,
        scenario: ToolbarAuditLifecycleScenario
    ) -> ToolbarAuditControlObservation {
        let enabled = scenario != .empty
        let secondary: ToolbarAuditSecondaryBehavior
        switch requirement.behavior.secondary {
        case .none:
            secondary = .none
        case .menu(let actions):
            secondary = .menu(
                actions: actions.map {
                    ToolbarAuditSecondaryAction(
                        id: $0.id,
                        accessibility: withEnabled($0.accessibility, enabled)
                    )
                }
            )
        }
        return ToolbarAuditControlObservation(
            id: requirement.id,
            command: requirement.command,
            behavior: ToolbarAuditControlBehavior(
                primaryActionID: requirement.behavior.primaryActionID,
                secondary: secondary
            ),
            tooltip: requirement.tooltip,
            shortcut: requirement.shortcut,
            accessibility: withEnabled(requirement.accessibility, enabled),
            availability: availability(for: scenario)
        )
    }

    private func availability(
        for scenario: ToolbarAuditLifecycleScenario
    ) -> ToolbarAuditAvailability {
        scenario == .empty ? .disabled(reason: id("empty")) : .enabled
    }

    private func withEnabled(
        _ metadata: ToolbarAuditAXMetadata,
        _ enabled: Bool
    ) -> ToolbarAuditAXMetadata {
        ToolbarAuditAXMetadata(
            identifier: metadata.identifier,
            role: metadata.role,
            label: metadata.label,
            value: metadata.value,
            hint: metadata.hint,
            isEnabled: enabled,
            checkedState: metadata.checkedState,
            selectedState: metadata.selectedState,
            isKeyboardFocusable: metadata.isKeyboardFocusable,
            actions: metadata.actions
        )
    }

    private func replacingControl(
        in evidence: ToolbarAuditEvidence,
        scenario: ToolbarAuditLifecycleScenario,
        command: ToolbarAuditCommand,
        transform: (ToolbarAuditControlObservation) -> ToolbarAuditControlObservation
    ) -> ToolbarAuditEvidence {
        ToolbarAuditEvidence(
            contractRevision: evidence.contractRevision,
            surfaces: evidence.surfaces.map { surface in
                guard surface.scenario == scenario else { return surface }
                return ToolbarAuditSurfaceEvidence(
                    scenario: surface.scenario,
                    manifestRevision: surface.manifestRevision,
                    items: surface.items,
                    controls: surface.controls.map {
                        $0.command == command ? transform($0) : $0
                    },
                    source: surface.source
                )
            },
            interactions: evidence.interactions,
            screenshots: evidence.screenshots
        )
    }

    private func replacingControls(
        in evidence: ToolbarAuditEvidence,
        scenario: ToolbarAuditLifecycleScenario,
        with transform: ([ToolbarAuditControlObservation]) -> [ToolbarAuditControlObservation]
    ) -> ToolbarAuditEvidence {
        replacingSurfaces(
            in: evidence,
            with: evidence.surfaces.map { surface in
                guard surface.scenario == scenario else { return surface }
                return ToolbarAuditSurfaceEvidence(
                    scenario: surface.scenario,
                    manifestRevision: surface.manifestRevision,
                    items: surface.items,
                    controls: transform(surface.controls),
                    source: surface.source
                )
            }
        )
    }

    private func replacingSurfaces(
        in evidence: ToolbarAuditEvidence,
        with surfaces: [ToolbarAuditSurfaceEvidence]
    ) -> ToolbarAuditEvidence {
        ToolbarAuditEvidence(
            contractRevision: evidence.contractRevision,
            surfaces: surfaces,
            interactions: evidence.interactions,
            screenshots: evidence.screenshots
        )
    }

    private func replacingInteractions(
        in evidence: ToolbarAuditEvidence,
        with interactions: [ToolbarAuditInteractionEvidence]
    ) -> ToolbarAuditEvidence {
        ToolbarAuditEvidence(
            contractRevision: evidence.contractRevision,
            surfaces: evidence.surfaces,
            interactions: interactions,
            screenshots: evidence.screenshots
        )
    }

    private func replacingItems(
        in evidence: ToolbarAuditEvidence,
        scenario: ToolbarAuditLifecycleScenario,
        items: [ToolbarAuditItem]
    ) -> ToolbarAuditEvidence {
        ToolbarAuditEvidence(
            contractRevision: evidence.contractRevision,
            surfaces: evidence.surfaces.map { surface in
                guard surface.scenario == scenario else { return surface }
                return ToolbarAuditSurfaceEvidence(
                    scenario: surface.scenario,
                    manifestRevision: surface.manifestRevision,
                    items: items,
                    controls: surface.controls,
                    source: surface.source
                )
            },
            interactions: evidence.interactions,
            screenshots: evidence.screenshots
        )
    }

    private func replacingManifestRevision(
        in evidence: ToolbarAuditEvidence,
        scenario: ToolbarAuditLifecycleScenario,
        revision: ToolbarAuditRevision
    ) -> ToolbarAuditEvidence {
        ToolbarAuditEvidence(
            contractRevision: evidence.contractRevision,
            surfaces: evidence.surfaces.map { surface in
                guard surface.scenario == scenario else { return surface }
                return ToolbarAuditSurfaceEvidence(
                    scenario: surface.scenario,
                    manifestRevision: revision,
                    items: surface.items,
                    controls: surface.controls,
                    source: surface.source
                )
            },
            interactions: evidence.interactions,
            screenshots: evidence.screenshots
        )
    }

    private func replacingScreenshotItems(
        in evidence: ToolbarAuditEvidence,
        context: ToolbarAuditScreenshotContext,
        items: [ToolbarAuditItem]
    ) -> ToolbarAuditEvidence {
        guard let screenshot = evidence.screenshots.first(where: { $0.context == context }) else {
            return evidence
        }
        return replacingScreenshot(
            in: evidence,
            context: context,
            with: ToolbarAuditScreenshotEvidence(
                context: screenshot.context,
                manifestRevision: screenshot.manifestRevision,
                items: items,
                screenshotDigest: screenshot.screenshotDigest,
                accessibilitySidecarDigest: screenshot.accessibilitySidecarDigest,
                source: screenshot.source
            )
        )
    }

    private func replacingScreenshot(
        in evidence: ToolbarAuditEvidence,
        context: ToolbarAuditScreenshotContext,
        with replacement: ToolbarAuditScreenshotEvidence
    ) -> ToolbarAuditEvidence {
        ToolbarAuditEvidence(
            contractRevision: evidence.contractRevision,
            surfaces: evidence.surfaces,
            interactions: evidence.interactions,
            screenshots: evidence.screenshots.map { $0.context == context ? replacement : $0 }
        )
    }

    private func reorderedEvidence(_ evidence: ToolbarAuditEvidence) -> ToolbarAuditEvidence {
        ToolbarAuditEvidence(
            contractRevision: evidence.contractRevision,
            surfaces: evidence.surfaces.reversed().map { surface in
                ToolbarAuditSurfaceEvidence(
                    scenario: surface.scenario,
                    manifestRevision: surface.manifestRevision,
                    items: surface.items,
                    controls: surface.controls.reversed(),
                    source: surface.source
                )
            },
            interactions: evidence.interactions.reversed(),
            screenshots: evidence.screenshots.reversed()
        )
    }

    private func findings(
        _ code: ToolbarAuditFindingCode,
        in report: ToolbarAuditReport
    ) -> [ToolbarAuditFinding] {
        report.findings.filter { $0.code == code }
    }

    private func findingTuples(_ report: ToolbarAuditReport) -> [FindingTuple] {
        report.findings.map {
            FindingTuple(
                severity: $0.severity,
                code: $0.code,
                command: $0.command,
                scenario: $0.scenario,
                subjectID: $0.subjectID,
                id: $0.id,
                message: $0.message
            )
        }
    }

    private func findingTuple(
        severity: ToolbarAuditFindingSeverity = .error,
        code: ToolbarAuditFindingCode,
        command: ToolbarAuditCommand? = nil,
        scenario: ToolbarAuditLifecycleScenario? = nil,
        subjectID: ToolbarAuditStableID? = nil,
        discriminator: String = "",
        message: String
    ) -> FindingTuple {
        FindingTuple(
            severity: severity,
            code: code,
            command: command,
            scenario: scenario,
            subjectID: subjectID,
            id: ToolbarAuditFinding.ID(
                rawValue: framed(
                    code.rawValue,
                    command?.rawValue ?? "",
                    scenario?.rawValue ?? "",
                    subjectID?.rawValue ?? "",
                    discriminator
                )
            ),
            message: message
        )
    }

    private func assertToolbarError<T>(
        _ expected: ToolbarAuditError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ToolbarAuditError, expected, file: file, line: line)
        }
    }

    private func controlID(_ command: ToolbarAuditCommand) -> ToolbarAuditStableID {
        id("control.\(command.rawValue)")
    }

    private func primaryActionID(_ command: ToolbarAuditCommand) -> ToolbarAuditStableID {
        id("action.\(command.rawValue).primary")
    }

    private var saveSecondaryActionIDs: [ToolbarAuditStableID] {
        [id("action.save.copy"), id("action.save.as")]
    }

    private func id(_ rawValue: String) -> ToolbarAuditStableID {
        ToolbarAuditStableID(rawValue: rawValue)
    }

    private func digest(_ character: Character) -> ToolbarAuditArtifactDigest {
        ToolbarAuditArtifactDigest(lowercaseHex: String(repeating: character, count: 64))
    }

    private func framed(_ components: String...) -> String {
        components.map { "\($0.utf8.count):\($0)" }.joined()
    }

    private struct FindingTuple: Equatable {
        let severity: ToolbarAuditFindingSeverity
        let code: ToolbarAuditFindingCode
        let command: ToolbarAuditCommand?
        let scenario: ToolbarAuditLifecycleScenario?
        let subjectID: ToolbarAuditStableID?
        let id: ToolbarAuditFinding.ID
        let message: String
    }

    private struct Fixture {
        let contract: ToolbarAuditContract
        let evidence: ToolbarAuditEvidence
    }
}

extension ToolbarAuditLifecycleScenario {
    fileprivate static let loadedSurfaceScenario = ToolbarAuditLifecycleScenario.different
}
