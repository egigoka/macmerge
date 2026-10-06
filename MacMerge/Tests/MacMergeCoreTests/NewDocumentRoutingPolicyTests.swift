import Foundation
import MacMergeCore
import XCTest

final class NewDocumentRoutingPolicyTests: XCTestCase {
    typealias Policy = NewDocumentRoutingPolicy
    typealias PolicyError = NewDocumentRoutingPolicyError
    typealias DocumentPlan = NewComparisonDocumentPlan

    private var expectedActions: [ExpectedAction] {
        [
            ExpectedAction(
                commandID: .twoPaneText,
                rawValue: "ID_FILE_NEW",
                mode: .text,
                paneCount: .two,
                menuLabelIntent: .text,
                actionLabelIntent: .twoPaneText,
                documentCommand: .twoWayText,
                group: .twoPane,
                groupOrder: 0,
                itemOrder: 0,
                panes: [.left, .right],
                sources: [.scratchpad(.text("")), .scratchpad(.text(""))],
                sourceSemantics: .scratchpad(.text),
                requiresSourceMaterialization: false,
                scratchpadCount: 2,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .twoPaneTable,
                rawValue: "ID_FILE_NEW_TABLE",
                mode: .table,
                paneCount: .two,
                menuLabelIntent: .table,
                actionLabelIntent: .twoPaneTable,
                documentCommand: .twoWayTable,
                group: .twoPane,
                groupOrder: 0,
                itemOrder: 1,
                panes: [.left, .right],
                sources: [.scratchpad(.text("")), .scratchpad(.text(""))],
                sourceSemantics: .scratchpad(.text),
                requiresSourceMaterialization: false,
                scratchpadCount: 2,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .twoPaneBinary,
                rawValue: "ID_FILE_NEW_HEX",
                mode: .binary,
                paneCount: .two,
                menuLabelIntent: .binary,
                actionLabelIntent: .twoPaneBinary,
                documentCommand: .twoWayBinary,
                group: .twoPane,
                groupOrder: 0,
                itemOrder: 2,
                panes: [.left, .right],
                sources: [.scratchpad(.binary(Data())), .scratchpad(.binary(Data()))],
                sourceSemantics: .scratchpad(.binary),
                requiresSourceMaterialization: false,
                scratchpadCount: 2,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .twoPaneImage,
                rawValue: "ID_FILE_NEW_IMAGE",
                mode: .image,
                paneCount: .two,
                menuLabelIntent: .image,
                actionLabelIntent: .twoPaneImage,
                documentCommand: .twoWayImage,
                group: .twoPane,
                groupOrder: 0,
                itemOrder: 3,
                panes: [.left, .right],
                sources: [.emptyImage, .emptyImage],
                sourceSemantics: .emptyImage,
                requiresSourceMaterialization: false,
                scratchpadCount: 0,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .twoPaneWebpage,
                rawValue: "ID_FILE_NEW_WEBPAGE",
                mode: .webpage,
                paneCount: .two,
                menuLabelIntent: .webpage,
                actionLabelIntent: .twoPaneWebpage,
                documentCommand: .twoWayWebpage,
                group: .twoPane,
                groupOrder: 0,
                itemOrder: 4,
                panes: [.left, .right],
                sources: [.blankWebpage, .blankWebpage],
                sourceSemantics: .blankWebpage,
                requiresSourceMaterialization: false,
                scratchpadCount: 0,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .twoPaneFolder,
                rawValue: "ID_FILE_NEW_FOLDER",
                mode: .folder,
                paneCount: .two,
                menuLabelIntent: .folder,
                actionLabelIntent: .twoPaneFolder,
                documentCommand: .twoWayFolder,
                group: .twoPane,
                groupOrder: 0,
                itemOrder: 5,
                panes: [.left, .right],
                sources: [.requiredSource(.emptyFolder), .requiredSource(.emptyFolder)],
                sourceSemantics: .requiredSource(.emptyFolder),
                requiresSourceMaterialization: true,
                scratchpadCount: 0,
                requiredSourceCount: 2
            ),
            ExpectedAction(
                commandID: .threePaneText,
                rawValue: "ID_FILE_NEW3",
                mode: .text,
                paneCount: .three,
                menuLabelIntent: .text,
                actionLabelIntent: .threePaneText,
                documentCommand: .threeWayText,
                group: .threePane,
                groupOrder: 1,
                itemOrder: 0,
                panes: [.left, .middle, .right],
                sources: [
                    .scratchpad(.text("")),
                    .scratchpad(.text("")),
                    .scratchpad(.text(""))
                ],
                sourceSemantics: .scratchpad(.text),
                requiresSourceMaterialization: false,
                scratchpadCount: 3,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .threePaneTable,
                rawValue: "ID_FILE_NEW3_TABLE",
                mode: .table,
                paneCount: .three,
                menuLabelIntent: .table,
                actionLabelIntent: .threePaneTable,
                documentCommand: .threeWayTable,
                group: .threePane,
                groupOrder: 1,
                itemOrder: 1,
                panes: [.left, .middle, .right],
                sources: [
                    .scratchpad(.text("")),
                    .scratchpad(.text("")),
                    .scratchpad(.text(""))
                ],
                sourceSemantics: .scratchpad(.text),
                requiresSourceMaterialization: false,
                scratchpadCount: 3,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .threePaneBinary,
                rawValue: "ID_FILE_NEW3_HEX",
                mode: .binary,
                paneCount: .three,
                menuLabelIntent: .binary,
                actionLabelIntent: .threePaneBinary,
                documentCommand: .threeWayBinary,
                group: .threePane,
                groupOrder: 1,
                itemOrder: 2,
                panes: [.left, .middle, .right],
                sources: [
                    .scratchpad(.binary(Data())),
                    .scratchpad(.binary(Data())),
                    .scratchpad(.binary(Data()))
                ],
                sourceSemantics: .scratchpad(.binary),
                requiresSourceMaterialization: false,
                scratchpadCount: 3,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .threePaneImage,
                rawValue: "ID_FILE_NEW3_IMAGE",
                mode: .image,
                paneCount: .three,
                menuLabelIntent: .image,
                actionLabelIntent: .threePaneImage,
                documentCommand: .threeWayImage,
                group: .threePane,
                groupOrder: 1,
                itemOrder: 3,
                panes: [.left, .middle, .right],
                sources: [.emptyImage, .emptyImage, .emptyImage],
                sourceSemantics: .emptyImage,
                requiresSourceMaterialization: false,
                scratchpadCount: 0,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .threePaneWebpage,
                rawValue: "ID_FILE_NEW3_WEBPAGE",
                mode: .webpage,
                paneCount: .three,
                menuLabelIntent: .webpage,
                actionLabelIntent: .threePaneWebpage,
                documentCommand: .threeWayWebpage,
                group: .threePane,
                groupOrder: 1,
                itemOrder: 4,
                panes: [.left, .middle, .right],
                sources: [.blankWebpage, .blankWebpage, .blankWebpage],
                sourceSemantics: .blankWebpage,
                requiresSourceMaterialization: false,
                scratchpadCount: 0,
                requiredSourceCount: 0
            ),
            ExpectedAction(
                commandID: .threePaneFolder,
                rawValue: "ID_FILE_NEW3_FOLDER",
                mode: .folder,
                paneCount: .three,
                menuLabelIntent: .folder,
                actionLabelIntent: .threePaneFolder,
                documentCommand: .threeWayFolder,
                group: .threePane,
                groupOrder: 1,
                itemOrder: 5,
                panes: [.left, .middle, .right],
                sources: [
                    .requiredSource(.emptyFolder),
                    .requiredSource(.emptyFolder),
                    .requiredSource(.emptyFolder)
                ],
                sourceSemantics: .requiredSource(.emptyFolder),
                requiresSourceMaterialization: true,
                scratchpadCount: 0,
                requiredSourceCount: 3
            )
        ]
    }

    func testExactCommandInventoryOrderGroupingAndLabelIntents() throws {
        let expectations = expectedActions
        let expectedCommands = expectations.map(\.commandID)

        XCTAssertEqual(Policy.CommandID.allCases, expectedCommands)
        XCTAssertEqual(expectedCommands.sorted(), expectedCommands)
        XCTAssertEqual(expectedCommands.map(\.rawValue), expectations.map(\.rawValue))
        XCTAssertEqual(Policy.MenuGroup.allCases, [.twoPane, .threePane])
        XCTAssertEqual(Policy.MenuGroup.twoPane.labelIntent, .twoPaneGroup)
        XCTAssertEqual(Policy.MenuGroup.threePane.labelIntent, .threePaneGroup)
        XCTAssertEqual(
            Policy.LabelIntent.allCases.map(\.rawValue),
            [
                "command.new.splitButton",
                "command.new.group.twoPane",
                "command.new.group.threePane",
                "command.new.mode.text",
                "command.new.mode.table",
                "command.new.mode.binary",
                "command.new.mode.image",
                "command.new.mode.webpage",
                "command.new.mode.folder",
                "command.new.action.twoPane.text",
                "command.new.action.twoPane.table",
                "command.new.action.twoPane.binary",
                "command.new.action.twoPane.image",
                "command.new.action.twoPane.webpage",
                "command.new.action.twoPane.folder",
                "command.new.action.threePane.text",
                "command.new.action.threePane.table",
                "command.new.action.threePane.binary",
                "command.new.action.threePane.image",
                "command.new.action.threePane.webpage",
                "command.new.action.threePane.folder"
            ]
        )

        let presentation = try Policy.presentation(in: snapshot())
        XCTAssertEqual(presentation.splitButtonLabelIntent, .splitButton)
        XCTAssertEqual(presentation.menuGroups.map(\.group), [.twoPane, .threePane])
        XCTAssertEqual(presentation.menuGroups.map(\.order), [0, 1])
        XCTAssertEqual(presentation.menuGroups.map(\.labelIntent), [.twoPaneGroup, .threePaneGroup])
        let twoPaneGroup = try XCTUnwrap(
            presentation.menuGroups.first { $0.group == .twoPane }
        )
        let threePaneGroup = try XCTUnwrap(
            presentation.menuGroups.first { $0.group == .threePane }
        )
        XCTAssertEqual(
            twoPaneGroup.actions.map(\.commandID),
            expectations.filter { $0.group == .twoPane }.map(\.commandID)
        )
        XCTAssertEqual(
            threePaneGroup.actions.map(\.commandID),
            expectations.filter { $0.group == .threePane }.map(\.commandID)
        )
        XCTAssertEqual(presentation.secondaryActions.map(\.commandID), expectedCommands)
        XCTAssertEqual(presentation.secondaryActions.count, expectations.count)

        for (action, expectation) in zip(presentation.secondaryActions, expectations) {
            let command = expectation.commandID
            XCTAssertEqual(command.mode, expectation.mode, command.rawValue)
            XCTAssertEqual(command.paneCount, expectation.paneCount, command.rawValue)
            XCTAssertEqual(Policy.CommandID(mode: command.mode, paneCount: command.paneCount), command)
            XCTAssertEqual(command.documentCommand, expectation.documentCommand, command.rawValue)
            XCTAssertEqual(
                DocumentPlan.Command(mode: command.mode, paneCount: command.paneCount),
                expectation.documentCommand,
                command.rawValue
            )
            XCTAssertEqual(action.mode, expectation.mode, command.rawValue)
            XCTAssertEqual(action.paneCount, expectation.paneCount, command.rawValue)
            XCTAssertEqual(action.menuLabelIntent, expectation.menuLabelIntent, command.rawValue)
            XCTAssertEqual(action.actionLabelIntent, expectation.actionLabelIntent, command.rawValue)
            XCTAssertEqual(action.presentation, .visible, command.rawValue)
            XCTAssertEqual(action.availability, .enabled, command.rawValue)
            XCTAssertEqual(action.menuPlacement?.group, expectation.group, command.rawValue)
            XCTAssertEqual(action.menuPlacement?.groupOrder, expectation.groupOrder, command.rawValue)
            XCTAssertEqual(action.menuPlacement?.itemOrder, expectation.itemOrder, command.rawValue)
            XCTAssertEqual(
                action.invocationKinds,
                [.menuItem, .toolbarSecondaryAction, .voiceOverSecondaryAction],
                command.rawValue
            )
        }
    }

    func testPrimarySplitButtonAndInvocationKindCommandMatrixRouteExactly() throws {
        let value = try snapshot()
        let presentation = try Policy.presentation(in: value)
        let primaryKinds: Set<Policy.InvocationKind> = [
            .keyboardShortcut,
            .toolbarPrimaryAction,
            .voiceOverPrimaryAction
        ]
        let secondaryKinds: Set<Policy.InvocationKind> = [
            .menuItem,
            .toolbarSecondaryAction,
            .voiceOverSecondaryAction
        ]

        XCTAssertEqual(Policy.PrimaryActionPolicy.allCases, [.fixedIDFileNew])
        XCTAssertEqual(Policy.PrimaryActionPolicy.fixedIDFileNew.commandID, .twoPaneText)
        XCTAssertEqual(
            Policy.InvocationKind.allCases,
            [
                .keyboardShortcut,
                .menuItem,
                .toolbarPrimaryAction,
                .toolbarSecondaryAction,
                .voiceOverPrimaryAction,
                .voiceOverSecondaryAction
            ])
        XCTAssertEqual(Set(Policy.InvocationKind.allCases.filter(\.isPrimary)), primaryKinds)
        XCTAssertEqual(presentation.primaryActionPolicy, .fixedIDFileNew)
        XCTAssertEqual(presentation.primaryAction.commandID, .twoPaneText)
        XCTAssertEqual(presentation.primaryAction.invocationKinds, primaryKinds)
        XCTAssertNil(presentation.primaryAction.menuPlacement)
        XCTAssertEqual(presentation.primaryAction.availability, .enabled)
        XCTAssertEqual(presentation.primaryAction.presentation, .visible)
        XCTAssertTrue(presentation.secondaryActions.allSatisfy { $0.invocationKinds == secondaryKinds })

        var invocationSeed = 10
        let commandCandidates: [Policy.CommandID?] =
            [nil]
            + Policy.CommandID.allCases.map(Optional.some)
        for kind in Policy.InvocationKind.allCases {
            for commandID in commandCandidates {
                defer { invocationSeed += 1 }
                let invocation = Policy.Invocation(
                    id: invocationID(invocationSeed),
                    kind: kind,
                    commandID: commandID
                )
                if kind.isPrimary {
                    guard let commandID else {
                        let request = try Policy.makeRequest(for: invocation, in: value)
                        XCTAssertEqual(request.invocation, invocation, kind.rawValue)
                        XCTAssertEqual(request.commandID, .twoPaneText, kind.rawValue)
                        continue
                    }
                    assertError(
                        .unexpectedCommandForPrimaryInvocation(
                            kind: kind,
                            commandID: commandID
                        )
                    ) {
                        try Policy.makeRequest(for: invocation, in: value)
                    }
                } else {
                    guard let commandID else {
                        assertError(.missingCommandForSecondaryInvocation(kind)) {
                            try Policy.makeRequest(for: invocation, in: value)
                        }
                        continue
                    }
                    let request = try Policy.makeRequest(for: invocation, in: value)
                    XCTAssertEqual(request.invocation, invocation, kind.rawValue)
                    XCTAssertEqual(request.commandID, commandID, kind.rawValue)
                }
            }
        }
    }

    func testCapabilityAndCommandGateAvailabilityKeepUnsupportedCommandsVisible() throws {
        let capabilities = Policy.CapabilitySnapshot(
            revision: revision(1),
            twoPaneModes: [.text, .table, .folder],
            threePaneModes: [.text]
        )
        let value = try snapshot(capabilities: capabilities)
        let presentation = try Policy.presentation(in: value)

        XCTAssertEqual(presentation.secondaryActions.count, 12)
        XCTAssertTrue(presentation.secondaryActions.allSatisfy { $0.presentation == .visible })
        XCTAssertEqual(presentation.primaryAction.availability, .enabled)
        XCTAssertEqual(Policy.availability(of: .twoPaneText, in: value), .enabled)
        XCTAssertEqual(
            Policy.availability(of: .twoPaneImage, in: value),
            .disabled(.unsupportedMode(.image))
        )
        XCTAssertEqual(
            Policy.availability(of: .threePaneTable, in: value),
            .disabled(.unsupportedPaneCount(mode: .table, paneCount: .three))
        )
        XCTAssertEqual(
            presentation.secondaryActions.first { $0.commandID == .twoPaneImage }?.disabledReason,
            .unsupportedMode(.image)
        )
        XCTAssertEqual(
            presentation.secondaryActions.first { $0.commandID == .threePaneTable }?.disabledReason,
            .unsupportedPaneCount(mode: .table, paneCount: .three)
        )
        assertError(.unsupportedMode(.image)) {
            try Policy.makeRequest(
                for: secondaryInvocation(40, commandID: .twoPaneImage),
                in: value
            )
        }
        assertError(.unsupportedPaneCount(mode: .table, paneCount: .three)) {
            try Policy.makeRequest(
                for: secondaryInvocation(41, commandID: .threePaneTable),
                in: value
            )
        }

        let lockedGate = Policy.CommandGate(
            comparisonContext: ComparisonCommandState.Context(isSessionLocked: true)
        )
        let locked = try snapshot(commandGate: lockedGate)
        let lockedPresentation = try Policy.presentation(in: locked)
        XCTAssertEqual(
            lockedPresentation.primaryAction.availability,
            .disabled(.commandState(.sessionLocked))
        )
        XCTAssertEqual(lockedPresentation.primaryAction.presentation, .visible)
        XCTAssertTrue(
            lockedPresentation.secondaryActions.allSatisfy {
                $0.availability == .disabled(.commandState(.sessionLocked))
                    && $0.presentation == .visible
            }
        )
        assertError(.commandDisabled(.twoPaneText, reason: .sessionLocked)) {
            try Policy.makeRequest(
                for: Policy.Invocation(id: invocationID(42), kind: .keyboardShortcut),
                in: locked
            )
        }

        let noTextCapabilities = Policy.CapabilitySnapshot(
            revision: revision(1),
            twoPaneModes: Set(Policy.Mode.allCases).subtracting([.text]),
            threePaneModes: Set(Policy.Mode.allCases).subtracting([.text])
        )
        let noText = try snapshot(capabilities: noTextCapabilities)
        let noTextPrimary = try Policy.presentation(in: noText).primaryAction
        XCTAssertEqual(noTextPrimary.availability, .disabled(.unsupportedMode(.text)))
        XCTAssertEqual(noTextPrimary.presentation, .visible)
        assertError(.unsupportedMode(.text)) {
            try Policy.makeRequest(
                for: Policy.Invocation(id: invocationID(43), kind: .toolbarPrimaryAction),
                in: noText
            )
        }
    }

    func testConfiguredTwoPaneDocumentLimitDisablesEveryThreePaneMode() throws {
        let limits = DocumentPlan.Limits(maximumPaneCount: 2)
        let value = try snapshot(defaults: defaults(documentPlanLimits: limits))
        let presentation = try Policy.presentation(in: value)

        XCTAssertTrue(presentation.secondaryActions.prefix(6).allSatisfy(\.isEnabled))
        XCTAssertEqual(presentation.secondaryActions.suffix(6).count, 6)
        for action in presentation.secondaryActions.suffix(6) {
            XCTAssertEqual(action.presentation, .visible)
            XCTAssertEqual(
                action.availability,
                .disabled(.unsupportedPaneCount(mode: action.mode, paneCount: .three)),
                action.commandID.rawValue
            )
        }
        assertError(.unsupportedPaneCount(mode: .webpage, paneCount: .three)) {
            try Policy.makeRequest(
                for: secondaryInvocation(50, commandID: .threePaneWebpage),
                in: value
            )
        }
    }

    func testConfiguredLimitsFailDuringSnapshotPreflight() {
        let invalidRoutingLimits: [(Policy.Limits, PolicyError)] = [
            (
                Policy.Limits(maximumCommandCount: 0),
                .invalidLimit(.commandCount, value: 0)
            ),
            (
                Policy.Limits(maximumCommandCount: Policy.Limits.hardMaximumCommandCount + 1),
                .invalidLimit(
                    .commandCount,
                    value: Policy.Limits.hardMaximumCommandCount + 1
                )
            ),
            (
                Policy.Limits(maximumWorkUnits: 0),
                .invalidLimit(.workUnits, value: 0)
            ),
            (
                Policy.Limits(maximumWorkUnits: Policy.Limits.hardMaximumWorkUnits + 1),
                .invalidLimit(.workUnits, value: Policy.Limits.hardMaximumWorkUnits + 1)
            ),
            (
                Policy.Limits(cancellationCheckInterval: 0),
                .invalidLimit(.cancellationCheckInterval, value: 0)
            ),
            (
                Policy.Limits(
                    cancellationCheckInterval:
                        Policy.Limits.hardMaximumCancellationCheckInterval + 1
                ),
                .invalidLimit(
                    .cancellationCheckInterval,
                    value: Policy.Limits.hardMaximumCancellationCheckInterval + 1
                )
            ),
            (
                Policy.Limits(maximumConsumedReceiptCount: 0),
                .invalidLimit(.consumedReceiptCount, value: 0)
            ),
            (
                Policy.Limits(
                    maximumConsumedReceiptCount:
                        Policy.Limits.hardMaximumConsumedReceiptCount + 1
                ),
                .invalidLimit(
                    .consumedReceiptCount,
                    value: Policy.Limits.hardMaximumConsumedReceiptCount + 1
                )
            )
        ]
        for (limits, expectedError) in invalidRoutingLimits {
            assertError(expectedError) {
                try snapshot(defaults: defaults(routingLimits: limits))
            }
        }
        assertError(.commandLimitExceeded(maximum: 11)) {
            try snapshot(defaults: defaults(routingLimits: Policy.Limits(maximumCommandCount: 11)))
        }
        assertError(.workLimitExceeded(maximum: 1)) {
            try snapshot(defaults: defaults(routingLimits: Policy.Limits(maximumWorkUnits: 1)))
        }
        assertError(.comparisonOpenRequest(.invalidLimit(.optionItemCount))) {
            try snapshot(
                defaults: defaults(
                    comparisonOpenRequestLimits: ComparisonOpenRequestLimits(
                        maximumOptionItemCount: -1
                    )
                )
            )
        }
        assertError(
            .newComparisonDocumentPlan(.invalidLimit(.paneCount, value: 1))
        ) {
            try snapshot(
                defaults: defaults(
                    documentPlanLimits: DocumentPlan.Limits(maximumPaneCount: 1)
                )
            )
        }
    }

    func testSnapshotPreflightAcceptsExactCommandAndWorkBoundaries() throws {
        let noModes = Policy.CapabilitySnapshot(
            revision: revision(1),
            twoPaneModes: [],
            threePaneModes: []
        )
        let emptyImageOptions = options(
            imageLoading: ImageComparisonLimits(
                maximumEncodedBytes: ImageComparisonLimits.default.maximumEncodedBytes,
                maximumDimension: ImageComparisonLimits.default.maximumDimension,
                maximumPixelCount: ImageComparisonLimits.default.maximumPixelCount,
                maximumDecodedBytes: ImageComparisonLimits.default.maximumDecodedBytes,
                supportedTypeIdentifiers: []
            )
        )
        let exactLimits = Policy.Limits(
            maximumCommandCount: 12,
            maximumWorkUnits: 20,
            cancellationCheckInterval: 20,
            maximumConsumedReceiptCount: 1
        )

        _ = try snapshot(
            capabilities: noModes,
            defaults: defaults(routingLimits: exactLimits),
            options: emptyImageOptions
        )
        assertError(.workLimitExceeded(maximum: 19)) {
            try snapshot(
                capabilities: noModes,
                defaults: defaults(
                    routingLimits: Policy.Limits(
                        maximumCommandCount: 12,
                        maximumWorkUnits: 19,
                        cancellationCheckInterval: 19,
                        maximumConsumedReceiptCount: 1
                    )
                ),
                options: emptyImageOptions
            )
        }
    }

    func testSemanticPreflightFailuresDisableCommandsAndPreserveUnderlyingError() throws {
        let control = try snapshot()
        for commandID in [Policy.CommandID.twoPaneImage, .threePaneImage] {
            let action = try XCTUnwrap(
                Policy.presentation(in: control).secondaryActions.first {
                    $0.commandID == commandID
                }
            )
            XCTAssertEqual(action.availability, .enabled, commandID.rawValue)
        }

        let invalidLoading = ImageComparisonLimits(
            maximumEncodedBytes: ImageComparisonLimits.default.maximumEncodedBytes,
            maximumDimension: ImageComparisonLimits.default.maximumDimension,
            maximumPixelCount: ImageComparisonLimits.default.maximumPixelCount,
            maximumDecodedBytes: ImageComparisonLimits.default.maximumDecodedBytes,
            supportedTypeIdentifiers: ["invalid.private.image-type"]
        )
        let value = try snapshot(options: options(imageLoading: invalidLoading))
        let presentation = try Policy.presentation(in: value)

        for (index, commandID) in [Policy.CommandID.twoPaneImage, .threePaneImage].enumerated() {
            let action = try XCTUnwrap(
                presentation.secondaryActions.first { $0.commandID == commandID }
            )
            XCTAssertEqual(action.availability, .disabled(.planningFailure(.comparisonOpenRequest)))
            XCTAssertEqual(action.presentation, .visible)
            assertError(
                .comparisonOpenRequest(.invalidOption(name: "image.supportedTypeIdentifier"))
            ) {
                try Policy.makeRequest(
                    for: secondaryInvocation(60 + index, commandID: commandID),
                    in: value
                )
            }
        }
    }

    func testDefaultsOptionsAndCapabilitiesBindPlanCurrentSnapshot() throws {
        let identity = snapshotIdentity(generation: 7)
        let base = try snapshot(identity: identity)
        let request = try Policy.makeRequest(
            for: secondaryInvocation(70, commandID: .threePaneText),
            in: base
        )
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: base)
        let plan = try Policy.plan(request, currentSnapshot: base, receiptLedger: ledger)

        XCTAssertEqual(request.expectedSnapshotFingerprint.identity, identity)
        XCTAssertEqual(request.expectedSnapshotFingerprint.defaultsRevision, revision(1))
        XCTAssertEqual(request.expectedSnapshotFingerprint.optionsRevision, revision(1))
        XCTAssertEqual(request.expectedSnapshotFingerprint.capabilitiesRevision, revision(1))
        XCTAssertEqual(plan.receipt.defaultsRevision, revision(1))
        XCTAssertEqual(plan.receipt.optionsRevision, revision(1))

        let staleDefaults = try snapshot(
            identity: identity,
            defaults: defaults(revision: 2)
        )
        assertError(.staleDefaults(expected: revision(1), actual: revision(2))) {
            try request.validateCurrentSnapshot(staleDefaults)
        }
        assertError(.staleDefaults(expected: revision(1), actual: revision(2))) {
            try plan.validateCurrentSnapshot(staleDefaults)
        }
        assertError(.staleDefaults(expected: revision(1), actual: revision(2))) {
            try Policy.plan(request, currentSnapshot: staleDefaults, receiptLedger: ledger)
        }

        let staleOptions = try snapshot(
            identity: identity,
            options: options(revision: 2)
        )
        assertError(.staleOptions(expected: revision(1), actual: revision(2))) {
            try request.validateCurrentSnapshot(staleOptions)
        }
        assertError(.staleOptions(expected: revision(1), actual: revision(2))) {
            try plan.validateCurrentSnapshot(staleOptions)
        }
        assertError(.staleOptions(expected: revision(1), actual: revision(2))) {
            try Policy.plan(request, currentSnapshot: staleOptions, receiptLedger: ledger)
        }

        let staleCapabilities = try snapshot(
            identity: identity,
            capabilities: .allSupported(revision: revision(2))
        )
        assertError(.staleCapabilities(expected: revision(1), actual: revision(2))) {
            try request.validateCurrentSnapshot(staleCapabilities)
        }
        assertError(.staleCapabilities(expected: revision(1), actual: revision(2))) {
            try plan.validateCurrentSnapshot(staleCapabilities)
        }
        assertError(.staleCapabilities(expected: revision(1), actual: revision(2))) {
            try Policy.plan(request, currentSnapshot: staleCapabilities, receiptLedger: ledger)
        }

        let defaultsCollision = try snapshot(
            identity: identity,
            defaults: defaults(documentPlanLimits: DocumentPlan.Limits(maximumPaneCount: 2))
        )
        assertError(.defaultsRevisionCollision(revision(1))) {
            try request.validateCurrentSnapshot(defaultsCollision)
        }

        let optionsCollision = try snapshot(
            identity: identity,
            options: options(textTwoWay: LineDiffOptions(ignoreCase: true))
        )
        assertError(.optionsRevisionCollision(revision(1))) {
            try request.validateCurrentSnapshot(optionsCollision)
        }
    }

    func testEveryCommandConvertsThroughAuthorizationToExactDocumentPlanSemantics() async throws {
        let configuredOptions = options(
            textTwoWay: LineDiffOptions(ignoreCase: true),
            textThreeWay: ThreeWayTextMergeOptions(diffAlgorithm: .minimal),
            tableParsing: DelimitedTableParsingOptions(delimiter: ";"),
            tableTwoWay: TableComparisonOptions(maximumExactEditDistance: 1_024),
            tableThreeWay: ThreeWayTableComparisonOptions(maximumResultRows: 2_000_000),
            binaryTwoWay: BinaryComparisonOptions(maximumExactEditDistance: 1_023),
            binaryThreeWay: ThreeWayBinaryComparisonOptions(maximumRegions: 500_000),
            imageLoading: ImageComparisonLimits(
                maximumEncodedBytes: 32 * 1_024 * 1_024,
                maximumDimension: 8_192,
                maximumPixelCount: 8 * 1_024 * 1_024,
                maximumDecodedBytes: 64 * 1_024 * 1_024
            ),
            imageComparison: ImageComparisonOptions(channelTolerance: 7),
            webpageTwoWay: WebPageComparisonOptions(mode: .renderedText),
            webpageThreeWay: ThreeWayWebPageComparisonOptions(diffAlgorithm: .histogram),
            folderScanning: FolderScanOptions(hiddenFilePolicy: .excludeEntriesAndSymbolicLinkTargets),
            folderTwoWay: FolderComparisonOptions(method: .contentIfAvailable),
            folderThreeWay: ThreeWayFolderComparisonOptions(maximumResultEntries: 2_000_000)
        )
        let value = try snapshot(options: configuredOptions)
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)

        for (index, expectation) in expectedActions.enumerated() {
            let commandID = expectation.commandID
            let invocation = secondaryInvocation(80 + index, commandID: commandID)
            let request = try Policy.makeRequest(for: invocation, in: value)
            let routingPlan = try Policy.plan(
                request,
                currentSnapshot: value,
                receiptLedger: ledger
            )

            XCTAssertEqual(routingPlan.receipt.id.rawValue, invocation.id.rawValue)
            XCTAssertEqual(routingPlan.receipt.commandID, commandID)
            XCTAssertEqual(routingPlan.receipt.invocationKind, .menuItem)
            XCTAssertGreaterThan(routingPlan.routingWorkPerformed, request.routingWorkPerformed)
            XCTAssertGreaterThan(routingPlan.documentPlanningWorkPerformed, 0)

            let authorization = try await ledger.consume(routingPlan)
            let document = try await authorization.consume()
            XCTAssertEqual(document.command, expectation.documentCommand, commandID.rawValue)
            XCTAssertEqual(document.mode, expectation.mode, commandID.rawValue)
            XCTAssertEqual(document.paneCount, expectation.paneCount, commandID.rawValue)
            XCTAssertEqual(document.panes.map(\.pane), expectation.panes, commandID.rawValue)
            XCTAssertEqual(
                document.panes.map(\.label.resolvedValue),
                expectation.panes.map(\.defaultLabel.resolvedValue),
                commandID.rawValue
            )
            XCTAssertTrue(
                document.panes.allSatisfy { $0.label.localizationResource != nil },
                commandID.rawValue
            )
            XCTAssertEqual(
                document.panes.map(\.source),
                expectation.sources,
                commandID.rawValue
            )
            XCTAssertEqual(
                document.modeOptions.value,
                expectedModeOptions(for: expectation.mode, options: configuredOptions),
                commandID.rawValue
            )
            XCTAssertEqual(document.modeOptions.mode, expectation.mode, commandID.rawValue)
            XCTAssertEqual(document.modeOptions.paneCount, expectation.paneCount)
            XCTAssertEqual(document.modeOptions.requestIdentity.rawValue, invocation.id.rawValue)
            XCTAssertEqual(document.sourceSemantics, expectation.sourceSemantics, commandID.rawValue)
            XCTAssertEqual(
                document.requiresSourceMaterialization,
                expectation.requiresSourceMaterialization,
                commandID.rawValue
            )
            XCTAssertEqual(document.scratchpads.count, expectation.scratchpadCount, commandID.rawValue)
            XCTAssertEqual(document.requiredSources.count, expectation.requiredSourceCount, commandID.rawValue)
            XCTAssertEqual(document.limits, value.defaults.documentPlanLimits)
        }
        let consumedReceiptCount = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedReceiptCount, Policy.CommandID.allCases.count)
    }

    func testUnavailableCommandsSkipSemanticPlanningValidation() throws {
        let emptyImageLoading = ImageComparisonLimits(
            maximumEncodedBytes: ImageComparisonLimits.default.maximumEncodedBytes,
            maximumDimension: ImageComparisonLimits.default.maximumDimension,
            maximumPixelCount: ImageComparisonLimits.default.maximumPixelCount,
            maximumDecodedBytes: ImageComparisonLimits.default.maximumDecodedBytes,
            supportedTypeIdentifiers: []
        )
        let capabilities = Policy.CapabilitySnapshot(
            revision: revision(1),
            twoPaneModes: Set(Policy.Mode.allCases).subtracting([.image]),
            threePaneModes: Set(Policy.Mode.allCases).subtracting([.image])
        )
        let value = try snapshot(
            capabilities: capabilities,
            options: options(imageLoading: emptyImageLoading)
        )

        XCTAssertEqual(
            Policy.availability(of: .twoPaneImage, in: value),
            .disabled(.unsupportedMode(.image))
        )
        XCTAssertEqual(
            Policy.availability(of: .threePaneImage, in: value),
            .disabled(.unsupportedMode(.image))
        )
        XCTAssertTrue(try Policy.presentation(in: value).secondaryActions.allSatisfy { $0.presentation == .visible })
    }

    func testOptionCountLimitPrecedesSetSortingAndSemanticValidation() {
        let identifiers: Set<String> = [
            "public.png",
            "public.jpeg",
            "public.tiff",
            "public.heic",
            "invalid.private.unsorted"
        ]
        let loading = ImageComparisonLimits(
            maximumEncodedBytes: ImageComparisonLimits.default.maximumEncodedBytes,
            maximumDimension: ImageComparisonLimits.default.maximumDimension,
            maximumPixelCount: ImageComparisonLimits.default.maximumPixelCount,
            maximumDecodedBytes: ImageComparisonLimits.default.maximumDecodedBytes,
            supportedTypeIdentifiers: identifiers
        )
        let requestLimits = ComparisonOpenRequestLimits(maximumOptionItemCount: 4)

        assertError(.comparisonOpenRequest(.tooManyOptionItems(maximum: 4))) {
            try snapshot(
                defaults: defaults(comparisonOpenRequestLimits: requestLimits),
                options: options(imageLoading: loading)
            )
        }
    }

    func testCustomCancellationCoversEverySynchronousCheckpoint() throws {
        assertError(.workLimitExceeded(maximum: 1)) {
            try snapshot(defaults: defaults(routingLimits: Policy.Limits(maximumWorkUnits: 1)))
        }

        try assertEveryCancellationCheckpoint { probe in
            try snapshot(cancellationCheck: probe.check)
        }

        let value = try snapshot()
        try assertEveryCancellationCheckpoint { probe in
            try Policy.presentation(in: value, cancellationCheck: probe.check)
        }
        try assertEveryCancellationCheckpoint { probe in
            try Policy.makeRequest(
                for: secondaryInvocation(98, commandID: .twoPaneText),
                in: value,
                cancellationCheck: probe.check
            )
        }

        let request = try Policy.makeRequest(
            for: secondaryInvocation(99, commandID: .twoPaneText),
            in: value
        )
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        try assertEveryCancellationCheckpoint { probe in
            try Policy.plan(
                request,
                currentSnapshot: value,
                receiptLedger: ledger,
                cancellationCheck: probe.check
            )
        }
        try assertEveryCancellationCheckpoint { probe in
            try request.validateCurrentSnapshot(value, cancellationCheck: probe.check)
        }
    }

    func testDefaultCancellationRejectsEveryPreCancelledPublicPath() async throws {
        let identity = snapshotIdentity(generation: 1)
        let capabilities = Policy.CapabilitySnapshot.allSupported(revision: revision(1))
        let defaults = defaults()
        let options = options()
        let value = try snapshot()
        let request = try Policy.makeRequest(
            for: secondaryInvocation(99, commandID: .twoPaneText),
            in: value
        )
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let plan = try Policy.plan(request, currentSnapshot: value, receiptLedger: ledger)

        let snapshotCancellationError = await defaultCancellationError {
            try Policy.Snapshot(
                identity: identity,
                commandGate: .enabled,
                capabilities: capabilities,
                defaults: defaults,
                options: options
            )
        }
        XCTAssertEqual(snapshotCancellationError, .cancelled)
        let presentationCancellationError = await defaultCancellationError {
            try Policy.presentation(in: value)
        }
        XCTAssertEqual(presentationCancellationError, .cancelled)
        let makeRequestCancellationError = await defaultCancellationError {
            try Policy.makeRequest(
                for: Policy.Invocation(id: Policy.InvocationID(rawValue: UUID()), kind: .menuItem),
                in: value
            )
        }
        XCTAssertEqual(makeRequestCancellationError, .cancelled)
        let requestValidationCancellationError = await defaultCancellationError {
            try request.validateCurrentSnapshot(value)
        }
        XCTAssertEqual(requestValidationCancellationError, .cancelled)
        let planCancellationError = await defaultCancellationError {
            try Policy.plan(request, currentSnapshot: value, receiptLedger: ledger)
        }
        XCTAssertEqual(planCancellationError, .cancelled)
        let planValidationCancellationError = await defaultCancellationError {
            try plan.validateCurrentSnapshot(value)
        }
        XCTAssertEqual(planValidationCancellationError, .cancelled)
        let ledgerUpdateCancellationError = await defaultCancellationError {
            try await ledger.updateAuthoritativeSnapshot(value)
        }
        XCTAssertEqual(ledgerUpdateCancellationError, .cancelled)
        let ledgerConsumeCancellationError = await defaultCancellationError {
            try await ledger.consume(plan)
        }
        XCTAssertEqual(ledgerConsumeCancellationError, .cancelled)
        let consumedAfterCancelledDefaultReceipt = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedAfterCancelledDefaultReceipt, 0)

        let authorization = try await ledger.consume(plan)
        let authorizationConsumeCancellationError = await defaultCancellationError {
            try await authorization.consume()
        }
        XCTAssertEqual(authorizationConsumeCancellationError, .cancelled)
        let document = try await authorization.consume()
        XCTAssertEqual(document.command, .twoWayText)
    }

    func testCustomCancellationDoesNotConsumeReceiptOrAuthorization() async throws {
        let value = try snapshot()
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let plan = try routingPlan(99, commandID: .twoPaneText, snapshot: value, ledger: ledger)
        let cancelledReceipt = CancellationProbe(cancelAtCall: 1)
        await assertAsyncError(.cancelled) {
            try await ledger.consume(plan, cancellationCheck: cancelledReceipt.check)
        }
        let consumedAfterCancelledCustomReceipt = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedAfterCancelledCustomReceipt, 0)

        let authorization = try await ledger.consume(plan)
        let cancelledAuthorization = CancellationProbe(cancelAtCall: 1)
        await assertAsyncError(.cancelled) {
            try await authorization.consume(cancellationCheck: cancelledAuthorization.check)
        }
        let document = try await authorization.consume()
        XCTAssertEqual(document.command, .twoWayText)
    }

    func testIndependentConstructionIsDeterministic() async throws {
        let firstSnapshot = try snapshot()
        let secondSnapshot = try snapshot()
        XCTAssertEqual(firstSnapshot, secondSnapshot)

        let invocation = secondaryInvocation(100, commandID: .threePaneTable)
        let firstRequest = try Policy.makeRequest(for: invocation, in: firstSnapshot)
        let secondRequest = try Policy.makeRequest(for: invocation, in: secondSnapshot)
        XCTAssertEqual(firstRequest, secondRequest)

        let firstLedger = try Policy.ReceiptLedger(authoritativeSnapshot: firstSnapshot)
        let secondLedger = try Policy.ReceiptLedger(authoritativeSnapshot: secondSnapshot)
        let firstPlan = try Policy.plan(
            firstRequest,
            currentSnapshot: firstSnapshot,
            receiptLedger: firstLedger
        )
        let secondPlan = try Policy.plan(
            secondRequest,
            currentSnapshot: secondSnapshot,
            receiptLedger: secondLedger
        )
        XCTAssertNotEqual(firstLedger.id, secondLedger.id)
        XCTAssertEqual(firstPlan.receipt.id, secondPlan.receipt.id)
        XCTAssertEqual(firstPlan.receipt.commandID, secondPlan.receipt.commandID)
        XCTAssertEqual(firstPlan.receipt.invocationKind, secondPlan.receipt.invocationKind)
        XCTAssertEqual(
            firstPlan.receipt.expectedSnapshotFingerprint,
            secondPlan.receipt.expectedSnapshotFingerprint
        )
        XCTAssertEqual(firstPlan.routingWorkPerformed, secondPlan.routingWorkPerformed)
        XCTAssertEqual(
            firstPlan.documentPlanningWorkPerformed,
            secondPlan.documentPlanningWorkPerformed
        )

        let firstAuthorization = try await firstLedger.consume(firstPlan)
        let secondAuthorization = try await secondLedger.consume(secondPlan)
        let firstDocument = try await firstAuthorization.consume()
        let secondDocument = try await secondAuthorization.consume()
        XCTAssertEqual(firstDocument, secondDocument)
    }

    func testReceiptsAreDeterministicAndDiagnosticsRedactEveryStringOptionLeaf() throws {
        let textFilterSecret = "PRIVATE-TEXT-FILTER"
        let textSubstitutionPatternSecret = "PRIVATE-TEXT-SUBSTITUTION-PATTERN"
        let textSubstitutionReplacementSecret = "PRIVATE-TEXT-SUBSTITUTION-REPLACEMENT"
        let tableDelimiterSecret: Character = "@"
        let tableQuoteSecret: Character = "~"
        let firstImageIdentifierSecret = "public.heic"
        let secondImageIdentifierSecret = "public.png"
        let webpageFilterSecret = "PRIVATE-WEB-FILTER"
        let webpageSubstitutionPatternSecret = "PRIVATE-WEB-SUBSTITUTION-PATTERN"
        let webpageSubstitutionReplacementSecret = "PRIVATE-WEB-SUBSTITUTION-REPLACEMENT"
        let webpageContextSecret = "PRIVATE-WEB-CONTEXT"
        let secrets = [
            textFilterSecret,
            textSubstitutionPatternSecret,
            textSubstitutionReplacementSecret,
            String(tableDelimiterSecret),
            String(tableQuoteSecret),
            firstImageIdentifierSecret,
            secondImageIdentifierSecret,
            webpageFilterSecret,
            webpageSubstitutionPatternSecret,
            webpageSubstitutionReplacementSecret,
            webpageContextSecret
        ]
        let lineOptions = LineDiffOptions(
            lineFilters: [LineFilterRule(pattern: textFilterSecret)],
            substitutions: [
                SubstitutionRule(
                    pattern: textSubstitutionPatternSecret,
                    replacement: textSubstitutionReplacementSecret
                )
            ]
        )
        let tableParsing = DelimitedTableParsingOptions(
            delimiter: tableDelimiterSecret,
            quote: tableQuoteSecret
        )
        let webpageLineOptions = LineDiffOptions(
            lineFilters: [LineFilterRule(pattern: webpageFilterSecret)],
            substitutions: [
                SubstitutionRule(
                    pattern: webpageSubstitutionPatternSecret,
                    replacement: webpageSubstitutionReplacementSecret
                )
            ]
        )
        let imageLoading = ImageComparisonLimits(
            maximumEncodedBytes: ImageComparisonLimits.default.maximumEncodedBytes,
            maximumDimension: ImageComparisonLimits.default.maximumDimension,
            maximumPixelCount: ImageComparisonLimits.default.maximumPixelCount,
            maximumDecodedBytes: ImageComparisonLimits.default.maximumDecodedBytes,
            supportedTypeIdentifiers: [firstImageIdentifierSecret, secondImageIdentifierSecret]
        )
        let optionSnapshot = options(
            textTwoWay: lineOptions,
            tableParsing: tableParsing,
            tableThreeWay: ThreeWayTableComparisonOptions(parsingOptions: tableParsing),
            imageLoading: imageLoading,
            webpageTwoWay: WebPageComparisonOptions(lineDiffOptions: webpageLineOptions),
            webpageThreeWay: ThreeWayWebPageComparisonOptions(
                expectedContext: ThreeWayWebPageComparisonContext(
                    identifier: webpageContextSecret,
                    generation: 9
                )
            )
        )
        let value = try snapshot(options: optionSnapshot)
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let invocation = secondaryInvocation(100, commandID: .twoPaneText)
        let request = try Policy.makeRequest(for: invocation, in: value)
        let first = try Policy.plan(request, currentSnapshot: value, receiptLedger: ledger)
        let second = try Policy.plan(request, currentSnapshot: value, receiptLedger: ledger)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.id.rawValue, invocation.id.rawValue)
        XCTAssertEqual(first.receipt.ledgerID, ledger.id)
        XCTAssertEqual(first.routingWorkPerformed, second.routingWorkPerformed)
        XCTAssertEqual(first.documentPlanningWorkPerformed, second.documentPlanningWorkPerformed)

        let diagnosticValues: [Any] = [
            optionSnapshot,
            value,
            value.fingerprint,
            invocation,
            request,
            first.receipt,
            first,
            ledger
        ]
        for value in diagnosticValues {
            var dumped = ""
            dump(value, to: &dumped)
            for diagnostic in [
                String(describing: value),
                String(reflecting: value),
                dumped
            ] {
                for secret in secrets {
                    XCTAssertFalse(diagnostic.contains(secret), diagnostic)
                }
            }
        }
    }

    func testReceiptLedgerRejectsWrongLedgerReplayAndAuthorizationReplay() async throws {
        let value = try snapshot()
        let expectedLedger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let wrongLedger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let request = try Policy.makeRequest(
            for: secondaryInvocation(110, commandID: .twoPaneBinary),
            in: value
        )
        let plan = try Policy.plan(
            request,
            currentSnapshot: value,
            receiptLedger: expectedLedger
        )

        await assertAsyncError(
            .receiptLedgerMismatch(expected: expectedLedger.id, actual: wrongLedger.id)
        ) {
            try await wrongLedger.consume(plan)
        }
        let wrongLedgerConsumedCount = await wrongLedger.consumedReceiptCount
        let expectedLedgerConsumedCountBeforeSuccess = await expectedLedger.consumedReceiptCount
        XCTAssertEqual(wrongLedgerConsumedCount, 0)
        XCTAssertEqual(expectedLedgerConsumedCountBeforeSuccess, 0)

        let authorization = try await expectedLedger.consume(plan)
        await assertAsyncError(.receiptAlreadyConsumed(plan.receipt.id)) {
            try await expectedLedger.consume(plan)
        }
        let document = try await authorization.consume()
        XCTAssertEqual(document.command, .twoWayBinary)
        await assertAsyncError(.executionAuthorizationAlreadyConsumed) {
            try await authorization.consume()
        }
        await assertAsyncError(.receiptAlreadyConsumed(plan.receipt.id)) {
            try await expectedLedger.consume(plan)
        }
        let consumedReceiptCount = await expectedLedger.consumedReceiptCount
        XCTAssertEqual(consumedReceiptCount, 1)
    }

    func testReceiptLimitIsCheckedAfterUniqueReceiptValidation() async throws {
        let routingLimits = Policy.Limits(maximumConsumedReceiptCount: 1)
        let value = try snapshot(defaults: defaults(routingLimits: routingLimits))
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let first = try routingPlan(120, commandID: .twoPaneText, snapshot: value, ledger: ledger)
        let second = try routingPlan(121, commandID: .twoPaneTable, snapshot: value, ledger: ledger)

        _ = try await ledger.consume(first)
        await assertAsyncError(.receiptLimitExceeded(maximum: 1)) {
            try await ledger.consume(second)
        }
        let consumedAfterLimitFailure = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedAfterLimitFailure, 1)
        await assertAsyncError(.receiptAlreadyConsumed(first.receipt.id)) {
            try await ledger.consume(first)
        }
        let consumedReceiptCount = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedReceiptCount, 1)
    }

    func testStaleReceiptsRollbackAndAuthorizedPlanRevocationFailClosed() async throws {
        let base = try snapshot(identity: snapshotIdentity(generation: 1))
        let current = try snapshot(identity: snapshotIdentity(generation: 2))
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: base)
        let stalePlan = try routingPlan(
            130,
            commandID: .threePaneWebpage,
            snapshot: base,
            ledger: ledger
        )

        try await ledger.updateAuthoritativeSnapshot(current)
        await assertAsyncError(
            .staleSnapshot(expected: base.identity, actual: current.identity)
        ) {
            try await ledger.consume(stalePlan)
        }
        let consumedAfterStaleFailure = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedAfterStaleFailure, 0)

        let replayRequest = try Policy.makeRequest(
            for: Policy.Invocation(
                id: Policy.InvocationID(rawValue: stalePlan.receipt.id.rawValue),
                kind: .menuItem,
                commandID: .threePaneWebpage
            ),
            in: current
        )
        let replayPlan = try Policy.plan(
            replayRequest,
            currentSnapshot: current,
            receiptLedger: ledger
        )
        let replayAuthorization = try await ledger.consume(replayPlan)
        let replayDocument = try await replayAuthorization.consume()
        XCTAssertEqual(replayDocument.command, .threeWayWebpage)
        let consumedAfterFreshReplay = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedAfterFreshReplay, 1)
        await assertAsyncError(
            .snapshotRollback(current: current.identity, proposed: base.identity)
        ) {
            try await ledger.updateAuthoritativeSnapshot(base)
        }

        let revocationLedger = try Policy.ReceiptLedger(authoritativeSnapshot: base)
        let authorizedPlan = try routingPlan(
            131,
            commandID: .twoPaneFolder,
            snapshot: base,
            ledger: revocationLedger
        )
        let authorization = try await revocationLedger.consume(authorizedPlan)
        try await revocationLedger.updateAuthoritativeSnapshot(current)
        await assertAsyncError(.executionAuthorizationAlreadyConsumed) {
            try await authorization.consume()
        }
        let revokedLedgerConsumedCount = await revocationLedger.consumedReceiptCount
        XCTAssertEqual(revokedLedgerConsumedCount, 1)
    }

    func testActorConcurrencyAllowsOneReceiptAndOneAuthorizationConsumer() async throws {
        let value = try snapshot()
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let plan = try routingPlan(
            140,
            commandID: .threePaneFolder,
            snapshot: value,
            ledger: ledger
        )
        let attemptCount = 32

        let receiptResults = await withTaskGroup(
            of: AuthorizationRaceResult.self,
            returning: [AuthorizationRaceResult].self
        ) { group in
            let barrier = ConcurrentStartBarrier(participantCount: attemptCount)
            for _ in 0..<attemptCount {
                group.addTask {
                    await barrier.wait()
                    do {
                        return .authorized(try await ledger.consume(plan))
                    } catch {
                        return .failed(requirePolicyError(error))
                    }
                }
            }
            var results: [AuthorizationRaceResult] = []
            for await result in group { results.append(result) }
            return results
        }
        let authorizations: [Policy.ExecutionAuthorization] = receiptResults.compactMap { result in
            guard case .authorized(let authorization) = result else { return nil }
            return authorization
        }
        let receiptFailures: [PolicyError] = receiptResults.compactMap { result in
            guard case .failed(let error) = result else { return nil }
            return error
        }
        XCTAssertEqual(authorizations.count, 1)
        XCTAssertEqual(
            receiptFailures.filter {
                $0 == PolicyError.receiptAlreadyConsumed(plan.receipt.id)
            }.count,
            attemptCount - 1
        )
        let consumedReceiptCount = await ledger.consumedReceiptCount
        XCTAssertEqual(consumedReceiptCount, 1)

        let authorization = try XCTUnwrap(authorizations.first)
        let executionResults = await withTaskGroup(
            of: ExecutionRaceResult.self,
            returning: [ExecutionRaceResult].self
        ) { group in
            let barrier = ConcurrentStartBarrier(participantCount: attemptCount)
            for _ in 0..<attemptCount {
                group.addTask {
                    await barrier.wait()
                    do {
                        return .executed(try await authorization.consume())
                    } catch {
                        return .failed(requirePolicyError(error))
                    }
                }
            }
            var results: [ExecutionRaceResult] = []
            for await result in group { results.append(result) }
            return results
        }
        let documents: [DocumentPlan] = executionResults.compactMap { result in
            guard case .executed(let document) = result else { return nil }
            return document
        }
        let executionFailures: [PolicyError] = executionResults.compactMap { result in
            guard case .failed(let error) = result else { return nil }
            return error
        }
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(try XCTUnwrap(documents.first).command, .threeWayFolder)
        XCTAssertEqual(
            executionFailures.filter {
                $0 == PolicyError.executionAuthorizationAlreadyConsumed
            }.count,
            attemptCount - 1
        )
    }

    private func snapshot(
        identity: Policy.SnapshotIdentity? = nil,
        commandGate: Policy.CommandGate = .enabled,
        capabilities: Policy.CapabilitySnapshot? = nil,
        defaults: Policy.DefaultsSnapshot? = nil,
        options: Policy.OptionsSnapshot? = nil,
        cancellationCheck: @escaping Policy.CancellationCheck = Policy.taskCancellationCheck
    ) throws(PolicyError) -> Policy.Snapshot {
        try Policy.Snapshot(
            identity: identity ?? snapshotIdentity(generation: 1),
            commandGate: commandGate,
            capabilities: capabilities ?? .allSupported(revision: revision(1)),
            defaults: defaults ?? self.defaults(),
            options: options ?? self.options(),
            cancellationCheck: cancellationCheck
        )
    }

    private func defaults(
        revision value: UInt64 = 1,
        comparisonOpenRequestLimits: ComparisonOpenRequestLimits = .default,
        documentPlanLimits: DocumentPlan.Limits = .default,
        routingLimits: Policy.Limits = .default
    ) -> Policy.DefaultsSnapshot {
        Policy.DefaultsSnapshot(
            revision: revision(value),
            comparisonOpenRequestLimits: comparisonOpenRequestLimits,
            documentPlanLimits: documentPlanLimits,
            routingLimits: routingLimits
        )
    }

    private func options(
        revision value: UInt64 = 1,
        textTwoWay: LineDiffOptions = LineDiffOptions(),
        textThreeWay: ThreeWayTextMergeOptions = ThreeWayTextMergeOptions(),
        tableParsing: DelimitedTableParsingOptions = .commaSeparated,
        tableTwoWay: TableComparisonOptions = .default,
        tableThreeWay: ThreeWayTableComparisonOptions = .default,
        binaryTwoWay: BinaryComparisonOptions = BinaryComparisonOptions(),
        binaryThreeWay: ThreeWayBinaryComparisonOptions = .default,
        imageLoading: ImageComparisonLimits = .default,
        imageComparison: ImageComparisonOptions = .default,
        webpageTwoWay: WebPageComparisonOptions = .default,
        webpageThreeWay: ThreeWayWebPageComparisonOptions = .default,
        folderScanning: FolderScanOptions = FolderScanOptions(),
        folderTwoWay: FolderComparisonOptions = FolderComparisonOptions(),
        folderThreeWay: ThreeWayFolderComparisonOptions = .default
    ) -> Policy.OptionsSnapshot {
        Policy.OptionsSnapshot(
            revision: revision(value),
            textTwoWay: textTwoWay,
            textThreeWay: textThreeWay,
            tableParsing: tableParsing,
            tableTwoWay: tableTwoWay,
            tableThreeWay: tableThreeWay,
            binaryTwoWay: binaryTwoWay,
            binaryThreeWay: binaryThreeWay,
            imageLoading: imageLoading,
            imageComparison: imageComparison,
            webpageTwoWay: webpageTwoWay,
            webpageThreeWay: webpageThreeWay,
            folderScanning: folderScanning,
            folderTwoWay: folderTwoWay,
            folderThreeWay: folderThreeWay
        )
    }

    private func routingPlan(
        _ invocationSeed: Int,
        commandID: Policy.CommandID,
        snapshot: Policy.Snapshot,
        ledger: Policy.ReceiptLedger
    ) throws(PolicyError) -> Policy.Plan {
        let request = try Policy.makeRequest(
            for: secondaryInvocation(invocationSeed, commandID: commandID),
            in: snapshot
        )
        return try Policy.plan(request, currentSnapshot: snapshot, receiptLedger: ledger)
    }

    private func expectedModeOptions(
        for mode: Policy.Mode,
        options: Policy.OptionsSnapshot
    ) -> ComparisonOpenModeOptions {
        switch mode {
        case .text:
            .text(twoWay: options.textTwoWay, threeWay: options.textThreeWay)
        case .table:
            .table(
                parsing: options.tableParsing,
                twoWay: options.tableTwoWay,
                threeWay: options.tableThreeWay
            )
        case .binary:
            .binary(twoWay: options.binaryTwoWay, threeWay: options.binaryThreeWay)
        case .image:
            .image(loading: options.imageLoading, comparison: options.imageComparison)
        case .webpage:
            .webpage(twoWay: options.webpageTwoWay, threeWay: options.webpageThreeWay)
        case .folder:
            .folder(
                scanning: options.folderScanning,
                twoWay: options.folderTwoWay,
                threeWay: options.folderThreeWay
            )
        }
    }

    private func secondaryInvocation(
        _ seed: Int,
        commandID: Policy.CommandID
    ) -> Policy.Invocation {
        Policy.Invocation(
            id: invocationID(seed),
            kind: .menuItem,
            commandID: commandID
        )
    }

    private func invocationID(_ seed: Int) -> Policy.InvocationID {
        Policy.InvocationID(rawValue: uuid(seed))
    }

    private func snapshotIdentity(generation: UInt64) -> Policy.SnapshotIdentity {
        Policy.SnapshotIdentity(lineage: uuid(1), generation: generation)
    }

    private func revision(_ value: UInt64) -> Policy.Revision {
        Policy.Revision(rawValue: value)
    }

    private func uuid(_ seed: Int) -> UUID {
        let byte = UInt8(truncatingIfNeeded: seed)
        return UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    private func assertEveryCancellationCheckpoint<T>(
        operation: (CancellationProbe) throws -> T
    ) throws {
        let baseline = CancellationProbe(cancelAtCall: .max)
        _ = try operation(baseline)
        XCTAssertGreaterThan(baseline.callCount, 0)
        for checkpoint in 1...baseline.callCount {
            let probe = CancellationProbe(cancelAtCall: checkpoint)
            assertError(.cancelled) {
                try operation(probe)
            }
            XCTAssertEqual(probe.callCount, checkpoint)
        }
        let beyondFinalCheckpoint = CancellationProbe(cancelAtCall: baseline.callCount + 1)
        _ = try operation(beyondFinalCheckpoint)
        XCTAssertEqual(beyondFinalCheckpoint.callCount, baseline.callCount)
    }

    private func defaultCancellationError<T: Sendable>(
        operation: @escaping @Sendable () async throws -> T
    ) async -> PolicyError? {
        let task = Task { () throws -> T in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await operation()
        }
        do {
            _ = try await task.value
            return nil
        } catch {
            return error as? PolicyError
        }
    }

    private func assertError<T>(
        _ expected: PolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? PolicyError, expected, file: file, line: line)
        }
    }

    private func assertAsyncError<T>(
        _ expected: PolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PolicyError, expected, file: file, line: line)
        }
    }
}

private struct ExpectedAction {
    let commandID: NewDocumentRoutingPolicy.CommandID
    let rawValue: String
    let mode: NewDocumentRoutingPolicy.Mode
    let paneCount: NewDocumentRoutingPolicy.PaneCount
    let menuLabelIntent: NewDocumentRoutingPolicy.LabelIntent
    let actionLabelIntent: NewDocumentRoutingPolicy.LabelIntent
    let documentCommand: NewComparisonDocumentPlan.Command
    let group: NewDocumentRoutingPolicy.MenuGroup
    let groupOrder: Int
    let itemOrder: Int
    let panes: [NewComparisonDocumentPlan.Pane]
    let sources: [NewComparisonDocumentPlan.PaneSource]
    let sourceSemantics: NewComparisonDocumentPlan.SourceSemantics
    let requiresSourceMaterialization: Bool
    let scratchpadCount: Int
    let requiredSourceCount: Int
}

private func requirePolicyError(_ error: any Error) -> NewDocumentRoutingPolicyError {
    guard let error = error as? NewDocumentRoutingPolicyError else {
        preconditionFailure("Unexpected error type: \(type(of: error))")
    }
    return error
}

private enum AuthorizationRaceResult: Sendable {
    case authorized(NewDocumentRoutingPolicy.ExecutionAuthorization)
    case failed(NewDocumentRoutingPolicyError)
}

private enum ExecutionRaceResult: Sendable {
    case executed(NewComparisonDocumentPlan)
    case failed(NewDocumentRoutingPolicyError)
}

private actor ConcurrentStartBarrier {
    private let participantCount: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func wait() async {
        arrivals += 1
        guard arrivals < participantCount else {
            let continuations = waiters
            waiters.removeAll(keepingCapacity: false)
            for continuation in continuations {
                continuation.resume()
            }
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAtCall: Int
    private var calls = 0

    init(cancelAtCall: Int) {
        self.cancelAtCall = cancelAtCall
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func check() throws(NewDocumentRoutingPolicyError) {
        let shouldCancel = lock.withLock {
            calls += 1
            return calls >= cancelAtCall
        }
        if shouldCancel { throw .cancelled }
    }
}
