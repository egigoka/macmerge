import Foundation
import MacMergeCore
import XCTest

/// Focused adoption tests for `NewDocumentCreation` only. Routing internals
/// are covered by `NewDocumentCreationTests`; here every path goes through the
/// creation facade: invocation-to-intent mapping, primary-only enforcement,
/// blank determinism, exact options, fingerprint staleness, limits,
/// cancellation, ledger one-shot behavior, and localization keys.
final class NewDocumentCreationAdoptionTests: XCTestCase {
    typealias Creation = NewDocumentCreation
    typealias Policy = NewDocumentRoutingPolicy
    typealias CreationError = NewDocumentRoutingPolicyError

    private func revision(_ value: UInt64) -> Policy.Revision {
        Policy.Revision(rawValue: value)
    }

    private func uuid(_ seed: Int) -> UUID {
        let byte = UInt8(truncatingIfNeeded: seed)
        return UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    private func snapshot(
        identity: Policy.SnapshotIdentity? = nil,
        commandGate: Policy.CommandGate = .enabled,
        capabilities: Policy.CapabilitySnapshot? = nil,
        defaults: Policy.DefaultsSnapshot? = nil,
        options: Policy.OptionsSnapshot? = nil
    ) throws(CreationError) -> Policy.Snapshot {
        try Policy.Snapshot(
            identity: identity
                ?? Policy.SnapshotIdentity(lineage: uuid(1), generation: 1),
            commandGate: commandGate,
            capabilities: capabilities ?? .allSupported(revision: revision(1)),
            defaults: defaults ?? Policy.DefaultsSnapshot(revision: revision(1)),
            options: options ?? Policy.OptionsSnapshot(revision: revision(1))
        )
    }

    private func primaryInvocation(_ seed: Int, kind: Policy.InvocationKind) -> Policy.Invocation {
        Policy.Invocation(id: Policy.InvocationID(rawValue: uuid(seed)), kind: kind)
    }

    private func execute(
        commandID: Policy.CommandID,
        seed: Int,
        snapshot: Policy.Snapshot,
        ledger: Creation.CreationLedger
    ) async throws(CreationError) -> (Creation.Intent, NewComparisonDocumentPlan) {
        let invocation = Policy.Invocation(
            id: Policy.InvocationID(rawValue: uuid(seed)),
            kind: .menuItem,
            commandID: commandID
        )
        let request = try Creation.request(for: invocation, in: snapshot)
        let plan = try await ledger.plan(request, currentSnapshot: snapshot)
        let authorization = try await ledger.consume(plan)
        let document = try await authorization.consume()
        return (plan.intent, document)
    }

    // MARK: - Intents per command and invocation

    func testAllTwelveCommandsMapToExpectedIntents() throws {
        let value = try snapshot()
        for (index, commandID) in Policy.CommandID.allCases.enumerated() {
            let invocation = Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(100 + index)),
                kind: .menuItem,
                commandID: commandID
            )
            let intent = try Creation.intent(for: invocation, in: value)
            XCTAssertEqual(intent.commandID, commandID)
            XCTAssertEqual(intent.mode, commandID.mode)
            XCTAssertEqual(intent.paneCount, commandID.paneCount)
            XCTAssertEqual(intent.invocationKind, .menuItem)
            XCTAssertEqual(intent.paneIntents.count, commandID.paneCount.rawValue)
        }
    }

    func testEveryInvocationKindReachesIntentLayer() throws {
        let value = try snapshot()
        for (index, kind) in Policy.InvocationKind.allCases.enumerated() {
            if kind.isPrimary {
                let intent = try Creation.intent(
                    for: primaryInvocation(200 + index, kind: kind),
                    in: value
                )
                XCTAssertEqual(intent.commandID, .twoPaneText, kind.rawValue)
                XCTAssertEqual(intent.invocationKind, kind, kind.rawValue)
            } else {
                let invocation = Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(201 + index)),
                    kind: kind,
                    commandID: .threePaneImage
                )
                let intent = try Creation.intent(for: invocation, in: value)
                XCTAssertEqual(intent.commandID, .threePaneImage, kind.rawValue)
                XCTAssertEqual(intent.invocationKind, kind, kind.rawValue)
            }
        }
    }

    // MARK: - Primary-only enforcement

    func testPrimaryInvocationRejectsExplicitCommand() throws {
        let value = try snapshot()
        for (index, kind) in Policy.InvocationKind.allCases.enumerated() where kind.isPrimary {
            let invocation = Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(210 + index)),
                kind: kind,
                commandID: .threePaneFolder
            )
            XCTAssertThrowsError(
                try Creation.intent(for: invocation, in: value)
            ) { error in
                XCTAssertEqual(
                    error as? CreationError,
                    .unexpectedCommandForPrimaryInvocation(
                        kind: kind,
                        commandID: .threePaneFolder
                    )
                )
            }
        }
    }

    func testSecondaryInvocationRequiresExplicitCommand() throws {
        let value = try snapshot()
        for (index, kind) in Policy.InvocationKind.allCases.enumerated() where !kind.isPrimary {
            let invocation = Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(220 + index)),
                kind: kind
            )
            XCTAssertThrowsError(
                try Creation.intent(for: invocation, in: value)
            ) { error in
                XCTAssertEqual(
                    error as? CreationError,
                    .missingCommandForSecondaryInvocation(kind)
                )
            }
        }
    }

    // MARK: - Blank determinism

    func testBlankIntentsAreDeterministicAcrossSnapshots() throws {
        let first = try snapshot()
        let second = try snapshot()
        for (index, commandID) in Policy.CommandID.allCases.enumerated() {
            let firstIntent = try Creation.intent(
                for: Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(230 + index)),
                    kind: .menuItem,
                    commandID: commandID
                ),
                in: first
            )
            let secondIntent = try Creation.intent(
                for: Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(244 + index)),
                    kind: .toolbarSecondaryAction,
                    commandID: commandID
                ),
                in: second
            )
            // Same command yields identical pane sources and options; the
            // invocation binding itself is caller state, not blank content.
            XCTAssertEqual(firstIntent.paneIntents, secondIntent.paneIntents)
            XCTAssertEqual(firstIntent.modeOptions, secondIntent.modeOptions)
            XCTAssertEqual(firstIntent.menuLabelIntent, secondIntent.menuLabelIntent)
            XCTAssertEqual(
                firstIntent.actionLabelIntent,
                secondIntent.actionLabelIntent
            )
        }
    }

    func testBlankPaneSourcesMatchDocumentSemantics() throws {
        let text = Creation.blankPaneIntents(for: .twoPaneText)
        XCTAssertEqual(
            text.map(\.source),
            [.scratchpad(.text("")), .scratchpad(.text(""))]
        )
        let table = Creation.blankPaneIntents(for: .threePaneTable)
        XCTAssertEqual(table.count, 3)
        XCTAssertTrue(
            table.allSatisfy {
                if case .scratchpad(.text("")) = $0.source { true } else { false }
            }
        )
        let binary = Creation.blankPaneIntents(for: .twoPaneBinary)
        XCTAssertEqual(
            binary.map(\.source),
            [.scratchpad(.binary(Data())), .scratchpad(.binary(Data()))]
        )
        let image = Creation.blankPaneIntents(for: .twoPaneImage)
        XCTAssertEqual(image.map(\.source), [.emptyImage, .emptyImage])
        let webpage = Creation.blankPaneIntents(for: .threePaneWebpage)
        XCTAssertEqual(
            webpage.map(\.source),
            [.blankWebpage, .blankWebpage, .blankWebpage]
        )
        let folder = Creation.blankPaneIntents(for: .twoPaneFolder)
        XCTAssertEqual(
            folder.map(\.source),
            [.requiredSource(.emptyFolder), .requiredSource(.emptyFolder)]
        )
    }

    // MARK: - Options carry-through

    func testConfiguredOptionsCarryThroughToIntent() throws {
        let configured = Policy.OptionsSnapshot(
            revision: revision(1),
            textTwoWay: LineDiffOptions(ignoreCase: true),
            tableTwoWay: TableComparisonOptions(maximumExactEditDistance: 1_024),
            binaryTwoWay: BinaryComparisonOptions(maximumExactEditDistance: 1_023),
            imageComparison: ImageComparisonOptions(channelTolerance: 7),
            webpageTwoWay: WebPageComparisonOptions(mode: .renderedText),
            folderTwoWay: FolderComparisonOptions(method: .contentIfAvailable)
        )
        let value = try snapshot(options: configured)
        let cases: [(Policy.CommandID, ComparisonOpenModeOptions)] = [
            (
                .threePaneText,
                .text(twoWay: configured.textTwoWay, threeWay: configured.textThreeWay)
            ),
            (
                .twoPaneTable,
                .table(
                    parsing: configured.tableParsing,
                    twoWay: configured.tableTwoWay,
                    threeWay: configured.tableThreeWay
                )
            ),
            (
                .twoPaneBinary,
                .binary(twoWay: configured.binaryTwoWay, threeWay: configured.binaryThreeWay)
            ),
            (
                .twoPaneImage,
                .image(loading: configured.imageLoading, comparison: configured.imageComparison)
            ),
            (
                .twoPaneWebpage,
                .webpage(twoWay: configured.webpageTwoWay, threeWay: configured.webpageThreeWay)
            ),
            (
                .twoPaneFolder,
                .folder(
                    scanning: configured.folderScanning,
                    twoWay: configured.folderTwoWay,
                    threeWay: configured.folderThreeWay
                )
            )
        ]
        for (index, (commandID, expected)) in cases.enumerated() {
            let intent = try Creation.intent(
                for: Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(250 + index)),
                    kind: .menuItem,
                    commandID: commandID
                ),
                in: value
            )
            XCTAssertEqual(intent.modeOptions, expected, commandID.rawValue)
        }
    }

    func testLedgerPlannedDocumentMatchesIntent() async throws {
        let configured = Policy.OptionsSnapshot(
            revision: revision(1),
            textTwoWay: LineDiffOptions(ignoreCase: true)
        )
        let value = try snapshot(options: configured)
        let ledger = try Creation.CreationLedger(authoritativeSnapshot: value)
        let invocation = Policy.Invocation(
            id: Policy.InvocationID(rawValue: uuid(252)),
            kind: .menuItem,
            commandID: .twoPaneText
        )
        let request = try Creation.request(for: invocation, in: value)
        let plan = try await ledger.plan(request, currentSnapshot: value)
        XCTAssertEqual(plan.intent.commandID, .twoPaneText)
        XCTAssertEqual(
            plan.intent.modeOptions,
            .text(twoWay: configured.textTwoWay, threeWay: configured.textThreeWay)
        )
        XCTAssertEqual(plan.intent.paneIntents.count, 2)
        let authorization = try await ledger.consume(plan)
        XCTAssertEqual(authorization.intent, plan.intent)
        let document = try await authorization.consume()
        XCTAssertEqual(document.command, .twoWayText)
        XCTAssertEqual(
            document.panes.map(\.source),
            plan.intent.paneIntents.map(\.source)
        )
        XCTAssertEqual(document.modeOptions.value, plan.intent.modeOptions)
        XCTAssertEqual(
            document.modeOptions.value,
            .text(twoWay: configured.textTwoWay, threeWay: configured.textThreeWay)
        )
    }

    // MARK: - Fingerprint staleness

    func testStaleFingerprintRejected() throws {
        let base = try snapshot()
        let request = try Creation.request(
            for: Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(260)),
                kind: .menuItem,
                commandID: .twoPaneTable
            ),
            in: base
        )
        let intent = try Creation.intent(for: request, in: base)
        let staleGeneration = try snapshot(
            identity: Policy.SnapshotIdentity(lineage: uuid(1), generation: 2)
        )
        XCTAssertThrowsError(try intent.validateCurrentSnapshot(staleGeneration)) {
            error in
            XCTAssertEqual(
                error as? CreationError,
                .staleSnapshot(expected: base.identity, actual: staleGeneration.identity)
            )
        }
        let staleOptions = try snapshot(
            options: Policy.OptionsSnapshot(revision: revision(2))
        )
        XCTAssertThrowsError(try intent.validateCurrentSnapshot(staleOptions)) {
            error in
            XCTAssertEqual(
                error as? CreationError,
                .staleOptions(expected: revision(1), actual: revision(2))
            )
        }
        // Planning against a stale snapshot fails before any receipt exists.
        XCTAssertThrowsError(
            try Creation.intent(for: request, in: staleOptions)
        ) { error in
            XCTAssertEqual(
                error as? CreationError,
                .staleOptions(expected: revision(1), actual: revision(2))
            )
        }
        let defaultsCollision = try snapshot(
            defaults: Policy.DefaultsSnapshot(
                revision: revision(1),
                documentPlanLimits: NewComparisonDocumentPlan.Limits(maximumPaneCount: 2)
            )
        )
        XCTAssertThrowsError(try intent.validateCurrentSnapshot(defaultsCollision)) {
            error in
            XCTAssertEqual(
                error as? CreationError,
                .defaultsRevisionCollision(revision(1))
            )
        }
        let optionsCollision = try snapshot(
            options: Policy.OptionsSnapshot(
                revision: revision(1),
                textTwoWay: LineDiffOptions(ignoreCase: true)
            )
        )
        XCTAssertThrowsError(try intent.validateCurrentSnapshot(optionsCollision)) {
            error in
            XCTAssertEqual(
                error as? CreationError,
                .optionsRevisionCollision(revision(1))
            )
        }
        let capabilitiesCollision = try snapshot(
            capabilities: Policy.CapabilitySnapshot(
                revision: revision(1),
                twoPaneModes: Set(Policy.Mode.allCases).subtracting([.image]),
                threePaneModes: Set(Policy.Mode.allCases)
            )
        )
        XCTAssertThrowsError(
            try intent.validateCurrentSnapshot(capabilitiesCollision)
        ) { error in
            XCTAssertEqual(
                error as? CreationError,
                .capabilitiesRevisionCollision(revision(1))
            )
        }
    }

    func testLedgerConsumeRejectsStaleSnapshot() async throws {
        let base = try snapshot()
        let ledger = try Creation.CreationLedger(authoritativeSnapshot: base)
        let request = try Creation.request(
            for: Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(261)),
                kind: .menuItem,
                commandID: .twoPaneText
            ),
            in: base
        )
        let plan = try await ledger.plan(request, currentSnapshot: base)
        let stale = try snapshot(
            identity: Policy.SnapshotIdentity(lineage: uuid(1), generation: 2)
        )
        try await ledger.updateAuthoritativeSnapshot(stale)
        do {
            _ = try await ledger.consume(plan)
            XCTFail("stale consume must throw")
        } catch {
            XCTAssertEqual(
                error as? CreationError,
                .staleSnapshot(expected: base.identity, actual: stale.identity)
            )
        }
    }

    // MARK: - Limits and cancellation

    func testInvalidLimitsFailFast() throws {
        for limit in Policy.Limit.allCases {
            var routingLimits = Policy.Limits.default
            switch limit {
            case .commandCount:
                routingLimits = Policy.Limits(maximumCommandCount: 0)
            case .workUnits:
                routingLimits = Policy.Limits(maximumWorkUnits: 0)
            case .cancellationCheckInterval:
                routingLimits = Policy.Limits(cancellationCheckInterval: 0)
            case .consumedReceiptCount:
                routingLimits = Policy.Limits(maximumConsumedReceiptCount: 0)
            }
            let defaults = Policy.DefaultsSnapshot(
                revision: revision(1),
                routingLimits: routingLimits
            )
            XCTAssertThrowsError(
                try snapshot(defaults: defaults)
            ) { error in
                XCTAssertEqual(error as? CreationError, .invalidLimit(limit, value: 0))
            }
        }
    }

    func testTinyWorkBudgetExhaustsDuringPlanning() async throws {
        let defaults = Policy.DefaultsSnapshot(
            revision: revision(1),
            routingLimits: Policy.Limits(maximumWorkUnits: 1)
        )
        XCTAssertThrowsError(try snapshot(defaults: defaults)) { error in
            XCTAssertEqual(error as? CreationError, .workLimitExceeded(maximum: 1))
        }
    }

    func testCancelledCheckAbortsRequestAndPresentation() throws {
        let value = try snapshot()
        let cancelled: Creation.CancellationCheck = {
            () throws(CreationError) -> Void in throw .cancelled
        }
        XCTAssertThrowsError(
            try Creation.request(
                for: Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(270)),
                    kind: .menuItem,
                    commandID: .twoPaneText
                ),
                in: value,
                cancellationCheck: cancelled
            )
        ) { error in
            XCTAssertEqual(error as? CreationError, .cancelled)
        }
        XCTAssertThrowsError(
            try Creation.presentation(in: value, cancellationCheck: cancelled)
        ) { error in
            XCTAssertEqual(error as? CreationError, .cancelled)
        }
    }

    // MARK: - Ledger one-shot

    func testReceiptAndAuthorizationAreOneShot() async throws {
        let value = try snapshot()
        let ledger = try Creation.CreationLedger(authoritativeSnapshot: value)
        let request = try Creation.request(
            for: Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(280)),
                kind: .menuItem,
                commandID: .twoPaneTable
            ),
            in: value
        )
        let plan = try await ledger.plan(request, currentSnapshot: value)
        XCTAssertEqual(plan.receipt.id.rawValue, uuid(280))
        let authorization = try await ledger.consume(plan)
        let document = try await authorization.consume()
        XCTAssertEqual(document.command, .twoWayTable)
        do {
            _ = try await ledger.consume(plan)
            XCTFail("second consume must throw")
        } catch {
            XCTAssertEqual(
                error as? CreationError,
                .receiptAlreadyConsumed(plan.receipt.id)
            )
        }
        do {
            _ = try await authorization.consume()
            XCTFail("second authorization consume must throw")
        } catch {
            XCTAssertEqual(
                error as? CreationError,
                .executionAuthorizationAlreadyConsumed
            )
        }
        let consumed = await ledger.consumedReceiptCount()
        XCTAssertEqual(consumed, 1)
    }

    func testLedgerRejectsForeignReceipts() async throws {
        let value = try snapshot()
        let expected = try Creation.CreationLedger(authoritativeSnapshot: value)
        let foreign = try Creation.CreationLedger(authoritativeSnapshot: value)
        let request = try Creation.request(
            for: Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(281)),
                kind: .menuItem,
                commandID: .twoPaneImage
            ),
            in: value
        )
        let plan = try await expected.plan(request, currentSnapshot: value)
        do {
            _ = try await foreign.consume(plan)
            XCTFail("foreign consume must throw")
        } catch {
            XCTAssertEqual(
                error as? CreationError,
                .receiptLedgerMismatch(
                    expected: plan.receipt.ledgerID,
                    actual: foreign.id
                )
            )
        }
    }

    // MARK: - Localization keys

    func testLabelIntentsAreStableLookupKeys() throws {
        XCTAssertEqual(
            Creation.LabelIntent.allCases.map(\.rawValue),
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
        XCTAssertEqual(Creation.LabelIntent.allCases.count, 21)
        XCTAssertEqual(
            Creation.actionLabelIntent(for: .twoPaneText).rawValue,
            "command.new.action.twoPane.text"
        )
        XCTAssertEqual(
            Creation.actionLabelIntent(for: .threePaneFolder).rawValue,
            "command.new.action.threePane.folder"
        )
        XCTAssertEqual(
            Creation.menuLabelIntent(for: .folder).rawValue,
            "command.new.mode.folder"
        )
        XCTAssertEqual(
            Policy.InvocationKind.allCases.map(\.rawValue),
            [
                "keyboardShortcut",
                "menuItem",
                "toolbarPrimaryAction",
                "toolbarSecondaryAction",
                "voiceOverPrimaryAction",
                "voiceOverSecondaryAction"
            ]
        )
    }

    func testDisabledGateAndUnsupportedCapabilityStayVisibleAndRejected() throws {
        let capabilities = Policy.CapabilitySnapshot(
            revision: revision(1),
            twoPaneModes: [.text, .table, .folder],
            threePaneModes: [.text]
        )
        let value = try snapshot(capabilities: capabilities)
        XCTAssertThrowsError(
            try Creation.intent(
                for: Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(182)),
                    kind: .menuItem,
                    commandID: .twoPaneImage
                ),
                in: value
            )
        ) { error in
            XCTAssertEqual(error as? CreationError, .unsupportedMode(.image))
        }
        let locked = try snapshot(
            commandGate: Policy.CommandGate(
                comparisonContext: ComparisonCommandState.Context(isSessionLocked: true)
            )
        )
        XCTAssertThrowsError(
            try Creation.intent(
                for: Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(183)),
                    kind: .keyboardShortcut
                ),
                in: locked
            )
        ) { error in
            XCTAssertEqual(
                error as? CreationError,
                .commandDisabled(.twoPaneText, reason: .sessionLocked)
            )
        }
        XCTAssertTrue(
            try Creation.presentation(in: locked).secondaryActions.allSatisfy {
                $0.presentation == .visible
            }
        )
    }

    func testIntentCarriesPresentationLabelIntents() throws {
        let value = try snapshot()
        let presentation = try Creation.presentation(in: value)
        XCTAssertEqual(presentation.splitButtonLabelIntent, .splitButton)
        XCTAssertEqual(presentation.primaryAction.commandID, .twoPaneText)
        for (index, commandID) in Policy.CommandID.allCases.enumerated() {
            let invocation = Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(290 + index)),
                kind: .menuItem,
                commandID: commandID
            )
            let intent = try Creation.intent(for: invocation, in: value)
            XCTAssertEqual(
                intent.menuLabelIntent,
                Creation.menuLabelIntent(for: commandID.mode)
            )
            XCTAssertEqual(
                intent.actionLabelIntent,
                Creation.actionLabelIntent(for: commandID)
            )
        }
    }

    // MARK: - Redaction

    func testDescriptionsRedactBindings() throws {
        let value = try snapshot()
        let intent = try Creation.intent(
            for: Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(300)),
                kind: .menuItem,
                commandID: .twoPaneText
            ),
            in: value
        )
        for text in [
            String(describing: intent),
            String(describing: value.fingerprint),
            String(describing: intent.expectedSnapshotFingerprint)
        ] {
            XCTAssertFalse(text.contains(uuid(300).uuidString))
            XCTAssertFalse(text.contains(uuid(1).uuidString))
        }
        XCTAssertTrue(String(describing: intent).contains("<redacted>"))
    }
}
