// Focused tests for blank new documents via routing policy.
// Covers routing, planning, authorization for blank documents.
import Foundation
import MacMergeCore
import XCTest

final class NewDocumentCreationTests: XCTestCase {
    typealias Policy = NewDocumentRoutingPolicy
    typealias Creation = NewDocumentCreation
    typealias PolicyError = NewDocumentRoutingPolicyError
    typealias DocumentPlan = NewComparisonDocumentPlan

    // MARK: - Helpers

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
    ) throws(PolicyError) -> Policy.Snapshot {
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

    private func secondaryInvocation(_ seed: Int, commandID: Policy.CommandID) -> Policy.Invocation {
        Policy.Invocation(
            id: Policy.InvocationID(rawValue: uuid(seed)),
            kind: .menuItem,
            commandID: commandID
        )
    }

    private func assertPolicyError(
        _ expected: PolicyError,
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? PolicyError, expected, file: file, line: line)
        }
    }

    private func assertAsyncPolicyError(
        _ expected: PolicyError,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
        } catch {
            XCTAssertEqual(error as? PolicyError, expected, file: file, line: line)
            return
        }
        XCTFail("Expected \(expected), got success", file: file, line: line)
    }

    private func planDocument(
        commandID: Policy.CommandID,
        seed: Int,
        snapshot: Policy.Snapshot,
        ledger: Creation.CreationLedger
    ) async throws -> DocumentPlan {
        let request = try Creation.request(
            for: secondaryInvocation(seed, commandID: commandID),
            in: snapshot
        )
        let creationPlan = try await ledger.plan(request, currentSnapshot: snapshot)
        return try await (try await ledger.consume(creationPlan)).consume()
    }

    // MARK: - 12 commands x invocation kinds

    func testAllTwelveCommandsCoverEveryModeAndPaneCount() throws {
        XCTAssertEqual(Policy.CommandID.allCases.count, 12)
        XCTAssertEqual(Set(Policy.CommandID.allCases.map(\.mode)).count, 6)
        XCTAssertEqual(
            Policy.CommandID.allCases.filter { $0.paneCount == .two }.count,
            6
        )
        XCTAssertEqual(
            Policy.CommandID.allCases.filter { $0.paneCount == .three }.count,
            6
        )
        // Raw values are the persistence/dispatch contract.
        XCTAssertEqual(
            Policy.CommandID.allCases.map(\.rawValue).sorted(),
            [
                "ID_FILE_NEW", "ID_FILE_NEW3", "ID_FILE_NEW3_FOLDER",
                "ID_FILE_NEW3_HEX", "ID_FILE_NEW3_IMAGE", "ID_FILE_NEW3_TABLE",
                "ID_FILE_NEW3_WEBPAGE", "ID_FILE_NEW_FOLDER", "ID_FILE_NEW_HEX",
                "ID_FILE_NEW_IMAGE", "ID_FILE_NEW_TABLE", "ID_FILE_NEW_WEBPAGE"
            ]
        )
    }

    func testEveryInvocationKindRoutesToExpectedCommand() throws {
        let value = try snapshot()
        for (kindIndex, kind) in Policy.InvocationKind.allCases.enumerated() {
            if kind.isPrimary {
                let request = try Policy.makeRequest(
                    for: primaryInvocation(10 + kindIndex, kind: kind),
                    in: value
                )
                XCTAssertEqual(request.commandID, .twoPaneText, kind.rawValue)
            } else {
                for (commandIndex, commandID) in Policy.CommandID.allCases.enumerated() {
                    let invocation = Policy.Invocation(
                        id: Policy.InvocationID(rawValue: uuid(20 + kindIndex * 20 + commandIndex)),
                        kind: kind,
                        commandID: commandID
                    )
                    let request = try Policy.makeRequest(for: invocation, in: value)
                    XCTAssertEqual(request.commandID, commandID, kind.rawValue)
                }
            }
        }
    }

    // MARK: - Primary-only enforcement

    func testPrimaryInvocationsRejectExplicitCommands() throws {
        let value = try snapshot()
        for (index, kind) in Policy.InvocationKind.allCases.enumerated() where kind.isPrimary {
            let invocation = Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(30 + index)),
                kind: kind,
                commandID: .threePaneFolder
            )
            assertPolicyError(
                .unexpectedCommandForPrimaryInvocation(kind: kind, commandID: .threePaneFolder)
            ) {
                _ = try Policy.makeRequest(for: invocation, in: value)
            }
        }
    }

    func testSecondaryInvocationsRequireExplicitCommands() throws {
        let value = try snapshot()
        for (index, kind) in Policy.InvocationKind.allCases.enumerated() where !kind.isPrimary {
            let invocation = Policy.Invocation(
                id: Policy.InvocationID(rawValue: uuid(35 + index)),
                kind: kind
            )
            assertPolicyError(.missingCommandForSecondaryInvocation(kind)) {
                _ = try Policy.makeRequest(for: invocation, in: value)
            }
        }
    }

    // MARK: - Blank-intent determinism

    func testBlankTextDocumentIsDeterministicAcrossIndependentSnapshots() async throws {
        let first = try snapshot(
            identity: Policy.SnapshotIdentity(lineage: uuid(1), generation: 1)
        )
        let second = try snapshot(
            identity: Policy.SnapshotIdentity(lineage: uuid(2), generation: 1)
        )
        let firstLedger = try Creation.CreationLedger(authoritativeSnapshot: first)
        let secondLedger = try Creation.CreationLedger(authoritativeSnapshot: second)
        let firstDocument = try await planDocument(
            commandID: .twoPaneText,
            seed: 40,
            snapshot: first,
            ledger: firstLedger
        )
        let secondDocument = try await planDocument(
            commandID: .twoPaneText,
            seed: 40,
            snapshot: second,
            ledger: secondLedger
        )
        XCTAssertEqual(firstDocument, secondDocument)
        XCTAssertEqual(firstDocument.command, .twoWayText)
        XCTAssertEqual(
            firstDocument.panes.map(\.source),
            [.scratchpad(.text("")), .scratchpad(.text(""))]
        )
    }

    // MARK: - Options carry-through

    func testConfiguredOptionsCarryThroughToDocumentPlan() async throws {
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
        let ledger = try Creation.CreationLedger(authoritativeSnapshot: value)
        let cases: [(Policy.CommandID, ComparisonOpenModeOptions)] = [
            (
                .twoPaneText,
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
            let document = try await planDocument(
                commandID: commandID,
                seed: 50 + index,
                snapshot: value,
                ledger: ledger
            )
            XCTAssertEqual(document.modeOptions.value, expected, commandID.rawValue)
        }
    }

    // MARK: - Fingerprint staleness

    func testFingerprintRejectsEveryStaleBinding() throws {
        let base = try snapshot()
        let fingerprint = base.fingerprint
        let otherLineage = Policy.SnapshotIdentity(lineage: uuid(99), generation: 1)
        let staleLineage = try snapshot(identity: otherLineage)
        assertPolicyError(.staleSnapshot(expected: base.identity, actual: otherLineage)) {
            try fingerprint.validateCurrent(staleLineage)
        }
        let staleGeneration = try snapshot(
            identity: Policy.SnapshotIdentity(lineage: uuid(1), generation: 2)
        )
        assertPolicyError(
            .staleSnapshot(expected: base.identity, actual: staleGeneration.identity)
        ) {
            try fingerprint.validateCurrent(staleGeneration)
        }
        let staleDefaults = try snapshot(
            defaults: Policy.DefaultsSnapshot(revision: revision(2))
        )
        assertPolicyError(.staleDefaults(expected: revision(1), actual: revision(2))) {
            try fingerprint.validateCurrent(staleDefaults)
        }
        let staleOptions = try snapshot(
            options: Policy.OptionsSnapshot(revision: revision(2))
        )
        assertPolicyError(.staleOptions(expected: revision(1), actual: revision(2))) {
            try fingerprint.validateCurrent(staleOptions)
        }
        let staleCapabilities = try snapshot(
            capabilities: Policy.CapabilitySnapshot(revision: revision(2))
        )
        assertPolicyError(
            .staleCapabilities(expected: revision(1), actual: revision(2))
        ) {
            try fingerprint.validateCurrent(staleCapabilities)
        }
        let defaultsCollision = try snapshot(
            defaults: Policy.DefaultsSnapshot(
                revision: revision(1),
                documentPlanLimits: DocumentPlan.Limits(maximumPaneCount: 2)
            )
        )
        assertPolicyError(.defaultsRevisionCollision(revision(1))) {
            try fingerprint.validateCurrent(defaultsCollision)
        }
        let optionsCollision = try snapshot(
            options: Policy.OptionsSnapshot(
                revision: revision(1),
                textTwoWay: LineDiffOptions(ignoreCase: true)
            )
        )
        assertPolicyError(.optionsRevisionCollision(revision(1))) {
            try fingerprint.validateCurrent(optionsCollision)
        }
        let capabilitiesCollision = try snapshot(
            capabilities: Policy.CapabilitySnapshot(
                revision: revision(1),
                twoPaneModes: Set(Policy.Mode.allCases).subtracting([.image]),
                threePaneModes: Set(Policy.Mode.allCases)
            )
        )
        assertPolicyError(.capabilitiesRevisionCollision(revision(1))) {
            try fingerprint.validateCurrent(capabilitiesCollision)
        }
        let gateCollision = try snapshot(
            commandGate: Policy.CommandGate(
                comparisonContext: ComparisonCommandState.Context(isSessionLocked: true)
            )
        )
        assertPolicyError(.snapshotRevisionCollision(base.identity)) {
            try fingerprint.validateCurrent(gateCollision)
        }
    }

    func testDisabledGateAndUnsupportedCapabilityStayVisibleAndRejected() throws {
        let capabilities = Policy.CapabilitySnapshot(
            revision: revision(1),
            twoPaneModes: [.text, .table, .folder],
            threePaneModes: [.text]
        )
        let value = try snapshot(capabilities: capabilities)
        XCTAssertEqual(
            Policy.availability(of: .twoPaneImage, in: value),
            .disabled(.unsupportedMode(.image))
        )
        XCTAssertEqual(
            Policy.availability(of: .threePaneTable, in: value),
            .disabled(.unsupportedPaneCount(mode: .table, paneCount: .three))
        )
        XCTAssertTrue(try Policy.presentation(in: value).secondaryActions.allSatisfy {
            $0.presentation == .visible
        })
        assertPolicyError(.unsupportedMode(.image)) {
            _ = try Policy.makeRequest(
                for: secondaryInvocation(90, commandID: .twoPaneImage),
                in: value
            )
        }
        let locked = try snapshot(
            commandGate: Policy.CommandGate(
                comparisonContext: ComparisonCommandState.Context(isSessionLocked: true)
            )
        )
        XCTAssertEqual(
            Policy.availability(of: .twoPaneText, in: locked),
            .disabled(.commandState(.sessionLocked))
        )
        assertPolicyError(.commandDisabled(.twoPaneText, reason: .sessionLocked)) {
            _ = try Policy.makeRequest(
                for: Policy.Invocation(
                    id: Policy.InvocationID(rawValue: uuid(91)),
                    kind: .keyboardShortcut
                ),
                in: locked
            )
        }
    }

    // MARK: - Limits, budget, cancel

    func testInvalidLimitsFailFast() {
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
            assertPolicyError(.invalidLimit(limit, value: 0)) {
                _ = try Policy.Snapshot(
                    identity: Policy.SnapshotIdentity(lineage: uuid(1), generation: 1),
                    commandGate: .enabled,
                    capabilities: .allSupported(revision: revision(1)),
                    defaults: defaults,
                    options: Policy.OptionsSnapshot(revision: revision(1))
                )
            }
        }
    }

    func testCommandLimitBelowTwelveRejected() {
        let defaults = Policy.DefaultsSnapshot(
            revision: revision(1),
            routingLimits: Policy.Limits(maximumCommandCount: 11)
        )
        assertPolicyError(.commandLimitExceeded(maximum: 11)) {
            _ = try Policy.Snapshot(
                identity: Policy.SnapshotIdentity(lineage: uuid(1), generation: 1),
                commandGate: .enabled,
                capabilities: .allSupported(revision: revision(1)),
                defaults: defaults,
                options: Policy.OptionsSnapshot(revision: revision(1))
            )
        }
    }

    func testTinyWorkBudgetExhaustsDuringSnapshotPreflight() {
        let defaults = Policy.DefaultsSnapshot(
            revision: revision(1),
            routingLimits: Policy.Limits(maximumWorkUnits: 1)
        )
        assertPolicyError(.workLimitExceeded(maximum: 1)) {
            _ = try snapshot(defaults: defaults)
        }
    }

    func testCancelledCheckAbortsRequestAndPlan() throws {
        let value = try snapshot()
        let cancelled: Policy.CancellationCheck = { () throws(PolicyError) -> Void in throw .cancelled }
        assertPolicyError(.cancelled) {
            _ = try Policy.makeRequest(
                for: secondaryInvocation(60, commandID: .twoPaneText),
                in: value,
                cancellationCheck: cancelled
            )
        }
        assertPolicyError(.cancelled) {
            _ = try Policy.presentation(in: value, cancellationCheck: cancelled)
        }
    }

    // MARK: - Receipts / ledger one-shot

    func testReceiptAndAuthorizationAreOneShot() async throws {
        let value = try snapshot()
        let ledger = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let request = try Policy.makeRequest(
            for: secondaryInvocation(70, commandID: .twoPaneTable),
            in: value
        )
        let routingPlan = try Policy.plan(
            request,
            currentSnapshot: value,
            receiptLedger: ledger
        )
        XCTAssertEqual(routingPlan.receipt.id.rawValue, uuid(70))
        XCTAssertEqual(routingPlan.receipt.ledgerID, ledger.id)
        let authorization = try await ledger.consume(routingPlan)
        let document = try await authorization.consume()
        XCTAssertEqual(document.command, .twoWayTable)
        await assertAsyncPolicyError(.receiptAlreadyConsumed(routingPlan.receipt.id)) {
            _ = try await ledger.consume(routingPlan)
        }
        await assertAsyncPolicyError(.executionAuthorizationAlreadyConsumed) {
            _ = try await authorization.consume()
        }
        let consumed = await ledger.consumedReceiptCount
        XCTAssertEqual(consumed, 1)
    }

    func testLedgerRejectsForeignReceipts() async throws {
        let value = try snapshot()
        let expected = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let foreign = try Policy.ReceiptLedger(authoritativeSnapshot: value)
        let request = try Policy.makeRequest(
            for: secondaryInvocation(71, commandID: .twoPaneImage),
            in: value
        )
        let routingPlan = try Policy.plan(
            request,
            currentSnapshot: value,
            receiptLedger: expected
        )
        await assertAsyncPolicyError(
            .receiptLedgerMismatch(expected: routingPlan.receipt.ledgerID, actual: foreign.id)
        ) {
            _ = try await foreign.consume(routingPlan)
        }
    }

    // MARK: - Localization keys

    func testLabelIntentsAreStableLookupKeys() throws {
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
        XCTAssertEqual(Policy.LabelIntent.allCases.count, 21)
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
        let value = try snapshot()
        let presentation = try Policy.presentation(in: value)
        XCTAssertEqual(presentation.splitButtonLabelIntent, .splitButton)
        XCTAssertEqual(presentation.primaryAction.menuLabelIntent, .text)
        XCTAssertEqual(presentation.primaryAction.actionLabelIntent, .twoPaneText)
        XCTAssertNil(presentation.primaryAction.menuPlacement)
        let groups = Dictionary(
            uniqueKeysWithValues: presentation.menuGroups.map { ($0.group, $0) }
        )
        XCTAssertEqual(groups[.twoPane]?.labelIntent, .twoPaneGroup)
        XCTAssertEqual(groups[.threePane]?.labelIntent, .threePaneGroup)
        XCTAssertEqual(groups[.twoPane]?.actions.count, 6)
        XCTAssertEqual(groups[.threePane]?.actions.count, 6)
    }

    func testBlankDocumentPanesCarryLocalizationResources() async throws {
        let value = try snapshot()
        let ledger = try Creation.CreationLedger(authoritativeSnapshot: value)
        let document = try await planDocument(
            commandID: .twoPaneText,
            seed: 80,
            snapshot: value,
            ledger: ledger
        )
        XCTAssertTrue(
            document.panes.allSatisfy { $0.label.localizationResource != nil }
        )
    }
}
