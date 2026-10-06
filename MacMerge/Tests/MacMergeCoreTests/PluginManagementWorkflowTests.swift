import CryptoKit
import Foundation
import MacMergeCore
import XCTest

/// Public API coverage intentionally cannot mint `PluginAuthorization`, consume a
/// `PluginManagementSelectionReceipt`, mint or consume a `PluginManagementExecutorLease`, or
/// construct executor reports. Those one-shot, revocation, expiry, replay, lease-invalidation, and
/// stale-not-committed branches are package-trusted boundaries and are documented at their nearest
/// public fail-closed assertions below rather than reached through `@testable`.
final class PluginManagementWorkflowTests: XCTestCase {
    func testRevisionOrderingCodableAndWorkflowLimitHardBoundariesAreExact() throws {
        let first = PluginManagementRevision(lineage: 3, generation: 9)
        let next = PluginManagementRevision(lineage: 3, generation: 10)
        let otherLineage = PluginManagementRevision(lineage: 4, generation: 0)

        XCTAssertLessThan(first, next)
        XCTAssertLessThan(next, otherLineage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        XCTAssertEqual(try JSONDecoder().decode(PluginManagementRevision.self, from: data), next)

        let maximum = try PluginManagementWorkflowLimits(
            maximumListedItemCount: PluginManagementWorkflowLimits.hardMaximumListedItemCount,
            maximumWorkUnits: PluginManagementWorkflowLimits.hardMaximumWorkUnits,
            cancellationCheckInterval: PluginManagementWorkflowLimits.hardMaximumCancellationCheckInterval
        )
        XCTAssertEqual(maximum.maximumListedItemCount, PluginCatalogLimits.hardMaximumItemCount)
        XCTAssertEqual(maximum.maximumWorkUnits, PluginCatalogLimits.hardMaximumWork)
        XCTAssertEqual(maximum.cancellationCheckInterval, 4_096)

        let invalidValues: [(Int, Int, Int)] = [
            (0, 1, 1),
            (PluginManagementWorkflowLimits.hardMaximumListedItemCount + 1, 1, 1),
            (1, 0, 1),
            (1, PluginManagementWorkflowLimits.hardMaximumWorkUnits + 1, 1),
            (1, 1, 0),
            (1, 1, PluginManagementWorkflowLimits.hardMaximumCancellationCheckInterval + 1)
        ]
        for (listed, work, interval) in invalidValues {
            assertWorkflowError(.invalidLimits) {
                try PluginManagementWorkflowLimits(
                    maximumListedItemCount: listed,
                    maximumWorkUnits: work,
                    cancellationCheckInterval: interval
                )
            }
        }
    }

    func testListFilterAndIntentProjectionAreDeterministic() throws {
        let first = try makeBasicFixture(reverseRegistration: false)
        let second = try makeBasicFixture(reverseRegistration: true)
        let workflow = PluginManagementWorkflow()

        let entries = try workflow.list(snapshot: first.snapshot)
        XCTAssertEqual(entries.map(\.item.id), [first.alpha.id, first.beta.id])
        XCTAssertEqual(entries.map(\.invocationIntent), [.automatic, .disabled])
        XCTAssertEqual(entries.map(\.preferredAutomaticRank), [0, nil])
        XCTAssertEqual(entries[0].manualDecision.reason, .externalToolPolicy(.explicitExternalExecutableRuleRequired))
        XCTAssertEqual(entries[0].automaticDecision.reason, .externalToolPolicy(.explicitExternalExecutableRuleRequired))
        XCTAssertEqual(entries[1].manualDecision.reason, .executionBackendUnavailable)
        XCTAssertEqual(entries[1].automaticDecision.reason, .automaticUseNotDeclared)
        XCTAssertEqual(entries, try workflow.list(snapshot: second.snapshot))

        XCTAssertEqual(
            try workflow.list(
                snapshot: first.snapshot,
                matching: PluginCatalogFilter(mode: .automatic)
            ).map(\.item.id),
            [first.alpha.id]
        )
        XCTAssertEqual(
            try workflow.list(
                snapshot: first.snapshot,
                matching: PluginCatalogFilter(capability: .transform)
            ).map(\.item.id),
            [first.beta.id]
        )
        XCTAssertEqual(
            try workflow.list(
                snapshot: first.snapshot,
                matching: PluginCatalogFilter(fileExtension: ".TXT")
            ).map(\.item.id),
            [first.alpha.id]
        )
        XCTAssertEqual(
            try workflow.list(
                snapshot: first.snapshot,
                matching: PluginCatalogFilter(contentTypeIdentifier: "PUBLIC.PLAIN-TEXT")
            ).map(\.item.id),
            [first.alpha.id]
        )
        XCTAssertEqual(
            try workflow.list(
                snapshot: first.snapshot,
                matching: PluginCatalogFilter(identifier: first.beta.id)
            ).map(\.item.id),
            [first.beta.id]
        )
    }

    func testSettingsPreserveSchemaOrderSourcesPrivacyAndSecretAbsence() throws {
        let fixture = try makeSettingsFixture(secretPreference: "PUBLIC-VALUE")
        let entries = try PluginManagementWorkflow().settings(
            for: fixture.item.id,
            snapshot: fixture.snapshot
        )

        XCTAssertEqual(entries.map(\.schema.key), ["enabled", "profile", "token"])
        XCTAssertEqual(entries.map(\.privacy), [.nonSecret, .nonSecret, .secret])
        XCTAssertEqual(entries.map(\.valueSource), [.catalogDefault, .preference, .secretNotExposed])
        XCTAssertEqual(entries[0].value, .boolean(false))
        XCTAssertEqual(entries[1].value, .string("PUBLIC-VALUE"))
        XCTAssertNil(entries[2].value)

        let missing = try PluginIdentifier("plugin.missing")
        assertWorkflowError(.unknownPlugin(missing)) {
            try PluginManagementWorkflow().settings(for: missing, snapshot: fixture.snapshot)
        }
    }

    func testSelectionReceiptBindsRequestAndExactSnapshotWhileMissingAuthorityFailsClosed() throws {
        let fixture = try makeBasicFixture()
        let workflow = PluginManagementWorkflow()
        let request = PluginManagementSelectionRequest(
            filter: try PluginCatalogFilter(fileExtension: "txt"),
            mode: .automatic
        )
        let receipt = try workflow.select(request, snapshot: fixture.snapshot, authorizations: [:])
        let copy = receipt

        XCTAssertEqual(receipt.request, request)
        XCTAssertEqual(receipt.expectedSnapshot.revision, fixture.snapshot.revision)
        XCTAssertTrue(try receipt.expectedSnapshot.matches(fixture.snapshot))
        XCTAssertEqual(receipt.description, copy.description)
        XCTAssertTrue(receipt.description.contains("outcome: <redacted>"))
        XCTAssertFalse(receipt.description.contains(fixture.alpha.id.rawValue))

        let entry = try XCTUnwrap(try workflow.list(snapshot: fixture.snapshot).first)
        XCTAssertEqual(entry.manualDecision.reason, .externalToolPolicy(.explicitExternalExecutableRuleRequired))

        // Public clients cannot construct a trusted verifier or authorization. Therefore public
        // selection rejects before trust, approval, revocation, expiry, replay, and one-shot consume
        // can be exercised; receipt consumption itself is package-only.
        XCTAssertEqual(Set(PluginTrustState.allCases), Set([.bundled, .trustedPublisher, .localDevelopment, .untrusted, .revoked, .invalid]))
        XCTAssertEqual(Set(PluginApprovalState.allCases), Set([.notApproved, .manual, .automatic]))
    }

    func testSnapshotCASRequiresRevisionAndCompleteStateEquality() throws {
        let fixture = try makeBasicFixture()
        let cas = fixture.snapshot.cas
        XCTAssertTrue(try cas.matches(fixture.snapshot))
        XCTAssertNoThrow(try cas.validate(fixture.snapshot))

        let disabledPreferences = try PluginCatalogPreferences(catalog: fixture.catalog)
        let sameRevisionDifferentPreferences = try PluginManagementSnapshot(
            revision: fixture.snapshot.revision,
            catalog: fixture.catalog,
            preferences: disabledPreferences
        )
        XCTAssertFalse(try cas.matches(sameRevisionDifferentPreferences))
        assertWorkflowError(.snapshotContentsChanged(revision: fixture.snapshot.revision)) {
            try cas.validate(sameRevisionDifferentPreferences)
        }

        let changedAlpha = try PluginCatalogItem(
            id: fixture.alpha.id,
            displayName: "Changed Alpha",
            version: fixture.alpha.version,
            capability: fixture.alpha.capability,
            automaticEligible: true,
            matchMetadata: fixture.alpha.matchMetadata
        )
        let changedCatalog = try PluginCatalog(items: [changedAlpha, fixture.beta])
        let changedPreferences = try PluginCatalogPreferences(
            catalog: changedCatalog,
            enabledPluginIdentifiers: [changedAlpha.id],
            automaticPluginIdentifiers: [changedAlpha.id],
            preferredAutomaticPluginIdentifiers: [changedAlpha.id]
        )
        let sameRevisionDifferentCatalog = try PluginManagementSnapshot(
            revision: fixture.snapshot.revision,
            catalog: changedCatalog,
            preferences: changedPreferences
        )
        XCTAssertFalse(try cas.matches(sameRevisionDifferentCatalog))

        let staleRevision = PluginManagementRevision(
            lineage: fixture.snapshot.revision.lineage,
            generation: fixture.snapshot.revision.generation + 1
        )
        let stale = try PluginManagementSnapshot(
            revision: staleRevision,
            catalog: fixture.catalog,
            preferences: fixture.preferences
        )
        XCTAssertFalse(try cas.matches(stale))
        assertWorkflowError(.staleSnapshot(expected: fixture.snapshot.revision, actual: staleRevision)) {
            try cas.validate(stale)
        }
    }

    func testEnableAndDisablePlanningMaintainAutomaticAndPreferredInvariants() throws {
        let fixture = try makeModeFixture()
        let workflow = PluginManagementWorkflow()
        let disable = try workflow.plan(
            .setEnabled(identifier: fixture.beta.id, enabled: false),
            snapshot: fixture.snapshot
        )

        XCTAssertFalse(disable.projectedSnapshot.preferences.enabledPluginIdentifiers.contains(fixture.beta.id))
        XCTAssertFalse(disable.projectedSnapshot.preferences.automaticPluginIdentifiers.contains(fixture.beta.id))
        XCTAssertEqual(disable.projectedSnapshot.preferences.preferredAutomaticPluginIdentifiers, [fixture.alpha.id])
        XCTAssertEqual(disable.receipt.editKind, .setEnabled)

        let enable = try workflow.plan(
            .setEnabled(identifier: fixture.beta.id, enabled: true),
            snapshot: disable.projectedSnapshot
        )
        XCTAssertTrue(enable.projectedSnapshot.preferences.enabledPluginIdentifiers.contains(fixture.beta.id))
        XCTAssertFalse(enable.projectedSnapshot.preferences.automaticPluginIdentifiers.contains(fixture.beta.id))
        XCTAssertEqual(enable.projectedSnapshot.preferences.preferredAutomaticPluginIdentifiers, [fixture.alpha.id])
        XCTAssertEqual(enable.projectedSnapshot.revision.generation, disable.projectedSnapshot.revision.generation + 1)

        assertWorkflowError(.noChange) {
            try workflow.plan(
                .setEnabled(identifier: fixture.alpha.id, enabled: true),
                snapshot: fixture.snapshot
            )
        }
    }

    func testInvocationModeAndAutomaticOrderPlanningAreExact() throws {
        let fixture = try makeModeFixture()
        let workflow = PluginManagementWorkflow()
        let manual = try workflow.plan(
            .setInvocationMode(identifier: fixture.alpha.id, mode: .manual),
            snapshot: fixture.snapshot
        )
        XCTAssertTrue(manual.projectedSnapshot.preferences.enabledPluginIdentifiers.contains(fixture.alpha.id))
        XCTAssertFalse(manual.projectedSnapshot.preferences.automaticPluginIdentifiers.contains(fixture.alpha.id))
        XCTAssertEqual(manual.projectedSnapshot.preferences.preferredAutomaticPluginIdentifiers, [fixture.beta.id])

        let automatic = try workflow.plan(
            .setInvocationMode(identifier: fixture.alpha.id, mode: .automatic),
            snapshot: manual.projectedSnapshot
        )
        XCTAssertTrue(automatic.projectedSnapshot.preferences.automaticPluginIdentifiers.contains(fixture.alpha.id))
        XCTAssertEqual(automatic.projectedSnapshot.preferences.preferredAutomaticPluginIdentifiers, [fixture.beta.id])

        let reordered = try workflow.plan(
            .reorderAutomaticPlugins([fixture.alpha.id, fixture.beta.id]),
            snapshot: fixture.snapshot
        )
        XCTAssertEqual(
            reordered.projectedSnapshot.preferences.preferredAutomaticPluginIdentifiers,
            [fixture.alpha.id, fixture.beta.id]
        )

        assertWorkflowError(.manualUseNotDeclared(fixture.automaticOnly.id)) {
            try workflow.plan(
                .setInvocationMode(identifier: fixture.automaticOnly.id, mode: .manual),
                snapshot: fixture.snapshot
            )
        }
        assertWorkflowError(.automaticUseNotDeclared(fixture.manualOnly.id)) {
            try workflow.plan(
                .setInvocationMode(identifier: fixture.manualOnly.id, mode: .automatic),
                snapshot: fixture.snapshot
            )
        }
        assertWorkflowError(.catalog(.duplicatePreferredPlugin)) {
            try workflow.plan(
                .reorderAutomaticPlugins([fixture.alpha.id, fixture.alpha.id]),
                snapshot: fixture.snapshot
            )
        }
        assertWorkflowError(.catalog(.preferredPluginMustBeAutomatic)) {
            try workflow.plan(
                .reorderAutomaticPlugins([fixture.manualOnly.id]),
                snapshot: fixture.snapshot
            )
        }
    }

    func testSettingEditsUseTrustedPrivacyAndValidatedSchema() throws {
        let fixture = try makeSettingsFixture(secretPreference: "original")
        let workflow = PluginManagementWorkflow()
        let set = try workflow.plan(
            .setSetting(identifier: fixture.item.id, key: "enabled", value: .boolean(true)),
            snapshot: fixture.snapshot
        )
        XCTAssertEqual(set.projectedSnapshot.preferences.settingValues[fixture.item.id]?["enabled"], .boolean(true))
        XCTAssertEqual(set.receipt.editKind, .setSetting)

        let remove = try workflow.plan(
            .removeSetting(identifier: fixture.item.id, key: "profile"),
            snapshot: fixture.snapshot
        )
        XCTAssertNil(remove.projectedSnapshot.preferences.settingValues[fixture.item.id])
        let projectedSettings = try workflow.settings(for: fixture.item.id, snapshot: remove.projectedSnapshot)
        XCTAssertEqual(projectedSettings[1].valueSource, .catalogDefault)
        XCTAssertEqual(projectedSettings[1].value, .string("catalog-default"))

        assertWorkflowError(.secretSettingRequiresTrustedStorage(identifier: fixture.item.id, key: "token")) {
            try workflow.plan(
                .setSetting(identifier: fixture.item.id, key: "token", value: .string("must-not-persist")),
                snapshot: fixture.snapshot
            )
        }
        assertWorkflowError(.unknownSetting(identifier: fixture.item.id, key: "missing")) {
            try workflow.plan(
                .removeSetting(identifier: fixture.item.id, key: "missing"),
                snapshot: fixture.snapshot
            )
        }
        assertWorkflowError(.catalog(.invalidSettingValue)) {
            try workflow.plan(
                .setSetting(identifier: fixture.item.id, key: "enabled", value: .string("wrong-kind")),
                snapshot: fixture.snapshot
            )
        }
    }

    func testCatalogMutationsAndReloadFailClosed() throws {
        let fixture = try makeBasicFixture()
        let workflow = PluginManagementWorkflow()
        let newItem = try PluginCatalogItem(
            id: PluginIdentifier("plugin.new"),
            displayName: "New",
            version: "1",
            capability: .transform
        )

        assertWorkflowError(.catalogMutationUnavailable(.add)) {
            try workflow.plan(.addCatalogItem(newItem), snapshot: fixture.snapshot)
        }
        assertWorkflowError(.catalogMutationUnavailable(.update)) {
            try workflow.plan(.updateCatalogItem(fixture.alpha), snapshot: fixture.snapshot)
        }
        assertWorkflowError(.catalogMutationUnavailable(.remove)) {
            try workflow.plan(.removeCatalogItem(fixture.alpha.id), snapshot: fixture.snapshot)
        }

        let request = try workflow.reloadRequest(snapshot: fixture.snapshot)
        XCTAssertEqual(request.operationOutcome.operation, .reload)
        XCTAssertEqual(request.operationOutcome.status, .unsupported)
        XCTAssertEqual(request.operationOutcome.reason, .pluginReloadUnsupported)
        let result = try workflow.reloadResult(for: request, currentSnapshot: fixture.snapshot)
        XCTAssertEqual(result.validatedRevision, fixture.snapshot.revision)
        XCTAssertEqual(result.disposition, .unavailable(request.operationOutcome))
        XCTAssertFalse(request.operationOutcome.isSupported)

        let staleRevision = PluginManagementRevision(
            lineage: fixture.snapshot.revision.lineage,
            generation: fixture.snapshot.revision.generation + 1
        )
        let stale = try PluginManagementSnapshot(
            revision: staleRevision,
            catalog: fixture.catalog,
            preferences: fixture.preferences
        )
        assertWorkflowError(.staleSnapshot(expected: fixture.snapshot.revision, actual: staleRevision)) {
            try workflow.reloadResult(for: request, currentSnapshot: stale)
        }
    }

    func testExternalToolBindingReportsEveryPublicState() throws {
        let fixture = try makeExternalBindingFixture()
        let entries = try PluginManagementWorkflow().list(snapshot: fixture.snapshot)
        let bindings = Dictionary(uniqueKeysWithValues: entries.map { ($0.item.id.rawValue, $0.externalToolBinding) })

        XCTAssertEqual(bindings["plugin.backend-unavailable"], .executionBackendUnavailable)
        XCTAssertEqual(bindings["plugin.reference-missing"], .ruleReferenceMissing(.unpacker))
        XCTAssertEqual(
            bindings["plugin.rule-absent"],
            .ruleNotConfigured(ruleIdentifier: "rule-absent", capability: .unpacker)
        )
        XCTAssertEqual(
            bindings["plugin.rule-mismatch"],
            .ruleCapabilityMismatch(
                ruleIdentifier: "rule-prediffer",
                expected: .unpacker,
                actual: .prediffer
            )
        )
        XCTAssertEqual(
            bindings["plugin.rule-bound"],
            .bound(
                ruleIdentifier: "rule-unpacker",
                capability: .unpacker,
                policyDecision: ExternalToolCapabilityDecision(
                    capability: .unpacker,
                    status: .supported,
                    reason: .explicitExternalExecutableRuleConfigured
                )
            )
        )
    }

    func testTrustApprovalCatalogsAndAuthorizationAbsenceRemainActionSpecific() throws {
        XCTAssertEqual(
            PluginTrustState.allCases.map(\.rawValue),
            ["bundled", "trustedPublisher", "localDevelopment", "untrusted", "revoked", "invalid"]
        )
        XCTAssertEqual(PluginApprovalState.allCases.map(\.rawValue), ["notApproved", "manual", "automatic"])

        let fixture = try makeExternalBindingFixture()
        let bound = try XCTUnwrap(fixture.catalog.item(withIdentifier: try PluginIdentifier("plugin.rule-bound")))
        let preferences = try PluginCatalogPreferences(
            catalog: fixture.catalog,
            enabledPluginIdentifiers: [bound.id],
            automaticPluginIdentifiers: [bound.id]
        )
        let snapshot = try PluginManagementSnapshot(
            revision: fixture.snapshot.revision,
            catalog: fixture.catalog,
            preferences: preferences,
            externalToolPolicy: fixture.policy
        )
        let entry = try XCTUnwrap(
            try PluginManagementWorkflow().list(
                snapshot: snapshot,
                matching: PluginCatalogFilter(identifier: bound.id)
            ).first
        )
        XCTAssertEqual(entry.manualDecision.reason, .authorizationMissing)
        XCTAssertEqual(entry.automaticDecision.reason, .authorizationMissing)

        // Opaque trusted authorization creation is package-only. Public coverage therefore proves
        // rejection; trust, approval, revocation, expiry, and cross-receipt replay acceptance paths
        // cannot be forged here.
        XCTAssertFalse(entry.manualDecision.isEligible)
        XCTAssertFalse(entry.automaticDecision.isEligible)
    }

    func testDescriptionsDebugDescriptionsAndMirrorsRedactSensitiveState() throws {
        let sentinel = "TOP-SECRET-PREFERENCE"
        let fixture = try makeSettingsFixture(secretPreference: sentinel)
        let workflow = PluginManagementWorkflow()
        let setting = try XCTUnwrap(try workflow.settings(for: fixture.item.id, snapshot: fixture.snapshot).first { $0.schema.key == "profile" })
        let request = PluginManagementSelectionRequest(mode: .manual)
        let selection = try workflow.select(request, snapshot: fixture.snapshot, authorizations: [:])
        let intent = PluginManagementEditIntent.setSetting(
            identifier: fixture.item.id,
            key: "profile",
            value: .string("SECOND-SECRET")
        )
        let plan = try workflow.plan(intent, snapshot: fixture.snapshot)
        let reload = try workflow.reloadRequest(snapshot: fixture.snapshot)
        let reloadResult = try workflow.reloadResult(for: reload, currentSnapshot: fixture.snapshot)
        let values: [Any] = [
            fixture.snapshot,
            fixture.snapshot.cas,
            setting,
            selection,
            intent,
            plan,
            plan.receipt,
            plan.receipt.persistence,
            reload,
            reloadResult
        ]

        for value in values {
            let output = diagnostics(value)
            XCTAssertFalse(output.contains(sentinel), output)
            XCTAssertFalse(output.contains("SECOND-SECRET"), output)
        }
        XCTAssertTrue(plan.description.contains("payload: <redacted>"))
        XCTAssertTrue(selection.description.contains("outcome: <redacted>"))
        XCTAssertTrue(plan.receipt.persistence.description.contains("contents: <redacted>"))
    }

    func testPlanningReceiptsPersistenceAndExecutorContractsAreExact() throws {
        let fixture = try makeSettingsFixture(secretPreference: "before")
        let workflow = PluginManagementWorkflow()
        let intent = PluginManagementEditIntent.setSetting(
            identifier: fixture.item.id,
            key: "profile",
            value: .string("after")
        )
        let first = try workflow.plan(intent, snapshot: fixture.snapshot)
        let second = try workflow.plan(intent, snapshot: fixture.snapshot)
        let canonicalData = try first.projectedSnapshot.preferences.encodedData(for: fixture.catalog)

        XCTAssertEqual(first.receipt.expectedRevision, fixture.snapshot.revision)
        XCTAssertEqual(first.receipt.projectedRevision, first.projectedSnapshot.revision)
        XCTAssertEqual(first.receipt.editKind, .setSetting)
        XCTAssertEqual(first.receipt.persistence.schemaVersion, PluginCatalogPreferences.currentSchemaVersion)
        XCTAssertEqual(first.receipt.persistence.byteCount, canonicalData.count)
        XCTAssertEqual(first.receipt.persistence, second.receipt.persistence)
        XCTAssertEqual(first.executorContract, .required)
        XCTAssertEqual(first.executorContract.snapshot, .holdExactSnapshotCASUntilStateAndPersistenceCommit)
        XCTAssertEqual(first.executorContract.persistence, .publishExactCanonicalRedactedPreferencesWithoutRegeneration)
        XCTAssertEqual(first.executorContract.security, .trustedHostOnlyNeverExecuteInspectOrExportSecrets)
        XCTAssertEqual(first.executorContract.cancellation, .cancelBeforeCommitOrReturnExactCompletedReceipt)
        XCTAssertNoThrow(try first.validateCurrentSnapshot(fixture.snapshot))

        let staleRevision = PluginManagementRevision(
            lineage: fixture.snapshot.revision.lineage,
            generation: fixture.snapshot.revision.generation + 1
        )
        let stale = try PluginManagementSnapshot(
            revision: staleRevision,
            catalog: fixture.catalog,
            preferences: fixture.preferences
        )
        assertWorkflowError(.staleSnapshot(expected: fixture.snapshot.revision, actual: staleRevision)) {
            try first.validateCurrentSnapshot(stale)
        }

        XCTAssertEqual(
            PluginManagementExecutionNonCommitReason.allCases.map(\.rawValue),
            ["cancelled", "staleSnapshot", "persistenceUnavailable", "ownerStateUnavailable", "contractUnsupported", "rejected"]
        )
        // Lease minting/consumption, execution receipts, and not-committed/stale executor reports are
        // package-only. Public callers can inspect requirements and planning proof, but cannot forge a
        // lease, replay it, retain it after invalidation, or claim a stale report committed.
    }

    func testProjectedPreferencePersistenceIsCanonicalStrictAndDeterministic() throws {
        let fixture = try makeSettingsFixture(secretPreference: "before")
        let workflow = PluginManagementWorkflow()
        let plan = try workflow.plan(
            .setSetting(identifier: fixture.item.id, key: "profile", value: .string("persisted")),
            snapshot: fixture.snapshot
        )
        let data = try plan.projectedSnapshot.preferences.encodedData(for: fixture.catalog)

        XCTAssertEqual(
            try PluginCatalogPreferences.decode(from: data, for: fixture.catalog),
            plan.projectedSnapshot.preferences
        )
        XCTAssertEqual(try plan.projectedSnapshot.preferences.encodedData(for: fixture.catalog), data)
        XCTAssertEqual(plan.receipt.persistence.byteCount, data.count)
        XCTAssertFalse(data.contains(Data("token".utf8)))

        assertCatalogError(.nonCanonicalPersistence) {
            try PluginCatalogPreferences.decode(from: Data([0x20]) + data, for: fixture.catalog)
        }
        let unsupported = String(decoding: data, as: UTF8.self).replacingOccurrences(
            of: "\"schemaVersion\":1",
            with: "\"schemaVersion\":2"
        )
        assertCatalogError(.unsupportedSchemaVersion(2)) {
            try PluginCatalogPreferences.decode(from: Data(unsupported.utf8), for: fixture.catalog)
        }
    }

    func testPlanningRejectsUnknownNoChangeAndRevisionExhaustion() throws {
        let fixture = try makeBasicFixture()
        let workflow = PluginManagementWorkflow()
        let missing = try PluginIdentifier("plugin.missing")

        assertWorkflowError(.unknownPlugin(missing)) {
            try workflow.plan(.setEnabled(identifier: missing, enabled: true), snapshot: fixture.snapshot)
        }
        assertWorkflowError(.noChange) {
            try workflow.plan(
                .reorderAutomaticPlugins([fixture.alpha.id]),
                snapshot: fixture.snapshot
            )
        }

        let exhaustedRevision = PluginManagementRevision(lineage: 77, generation: UInt64.max)
        let exhausted = try PluginManagementSnapshot(
            revision: exhaustedRevision,
            catalog: fixture.catalog,
            preferences: fixture.preferences
        )
        assertWorkflowError(.revisionExhausted(exhaustedRevision)) {
            try workflow.plan(
                .setEnabled(identifier: fixture.beta.id, enabled: true),
                snapshot: exhausted
            )
        }
    }

    func testListSettingsAndSelectionResultLimitsAcceptExactCountsAndRejectOneLess() throws {
        let basic = try makeBasicFixture()
        let exactList = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumListedItemCount: 2)
        )
        XCTAssertEqual(try exactList.list(snapshot: basic.snapshot).count, 2)

        let shortList = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumListedItemCount: 1)
        )
        assertWorkflowError(.resultLimitExceeded(maximum: 1)) {
            try shortList.list(snapshot: basic.snapshot)
        }
        assertWorkflowError(.resultLimitExceeded(maximum: 1)) {
            try shortList.select(
                PluginManagementSelectionRequest(mode: .manual),
                snapshot: basic.snapshot,
                authorizations: [:]
            )
        }

        let settings = try makeSettingsFixture(secretPreference: "value")
        let exactSettings = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumListedItemCount: 3)
        )
        XCTAssertEqual(try exactSettings.settings(for: settings.item.id, snapshot: settings.snapshot).count, 3)
        let shortSettings = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumListedItemCount: 2)
        )
        assertWorkflowError(.resultLimitExceeded(maximum: 2)) {
            try shortSettings.settings(for: settings.item.id, snapshot: settings.snapshot)
        }
    }

    func testPolicyScanWorkLimitAcceptsExactPublicCostAndRejectsOneLess() throws {
        let fixture = try makeExternalBindingFixture()
        let exactWork = try listWorkCost(snapshot: fixture.snapshot, filter: .all)
        XCTAssertGreaterThan(exactWork, 1)
        let exact = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumWorkUnits: exactWork)
        )
        XCTAssertEqual(try exact.list(snapshot: fixture.snapshot).count, fixture.catalog.items.count)

        let short = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumWorkUnits: exactWork - 1)
        )
        assertWorkflowError(.workLimitExceeded(maximum: exactWork - 1)) {
            try short.list(snapshot: fixture.snapshot)
        }
    }

    func testReloadWorkLimitsAcceptExactRequestAndValidationCosts() throws {
        let fixture = try makeBasicFixture()
        let snapshotCost = snapshotWorkCost(fixture.snapshot)
        let exactRequestWorkflow = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumWorkUnits: snapshotCost)
        )
        XCTAssertNoThrow(try exactRequestWorkflow.reloadRequest(snapshot: fixture.snapshot))
        let shortRequestWorkflow = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumWorkUnits: snapshotCost - 1)
        )
        assertWorkflowError(.workLimitExceeded(maximum: snapshotCost - 1)) {
            try shortRequestWorkflow.reloadRequest(snapshot: fixture.snapshot)
        }

        let resultCost = 2 * snapshotCost + 1
        let exactResultWorkflow = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumWorkUnits: resultCost)
        )
        let exactRequest = try exactResultWorkflow.reloadRequest(snapshot: fixture.snapshot)
        XCTAssertNoThrow(
            try exactResultWorkflow.reloadResult(
                for: exactRequest,
                currentSnapshot: fixture.snapshot
            )
        )

        let shortResultWorkflow = PluginManagementWorkflow(
            limits: try PluginManagementWorkflowLimits(maximumWorkUnits: resultCost - 1)
        )
        let shortRequest = try shortResultWorkflow.reloadRequest(snapshot: fixture.snapshot)
        assertWorkflowError(.workLimitExceeded(maximum: resultCost - 1)) {
            try shortResultWorkflow.reloadResult(
                for: shortRequest,
                currentSnapshot: fixture.snapshot
            )
        }
    }

    func testEveryPublicWorkflowEntryPointHonorsPreexistingCancellation() async throws {
        let fixture = try makeSettingsFixture(secretPreference: "before")
        let workflow = PluginManagementWorkflow()
        let reloadRequest = try workflow.reloadRequest(snapshot: fixture.snapshot)
        let selectionRequest = PluginManagementSelectionRequest(mode: .manual)
        let operations: [@Sendable () throws -> Void] = [
            {
                _ = try PluginManagementSnapshot(
                    revision: fixture.snapshot.revision,
                    catalog: fixture.catalog,
                    preferences: fixture.preferences
                )
            },
            { _ = try workflow.list(snapshot: fixture.snapshot) },
            { _ = try workflow.settings(for: fixture.item.id, snapshot: fixture.snapshot) },
            { _ = try workflow.select(selectionRequest, snapshot: fixture.snapshot, authorizations: [:]) },
            {
                _ = try workflow.plan(
                    .setSetting(identifier: fixture.item.id, key: "profile", value: .string("after")),
                    snapshot: fixture.snapshot
                )
            },
            { _ = try workflow.reloadRequest(snapshot: fixture.snapshot) },
            { _ = try workflow.reloadResult(for: reloadRequest, currentSnapshot: fixture.snapshot) },
            { try fixture.snapshot.cas.validate(fixture.snapshot) },
            { _ = try fixture.snapshot.cas.matches(fixture.snapshot) }
        ]

        for operation in operations {
            let error = await preCancelledWorkflowError(operation)
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testRegistrationSetDictionaryAndReceiptProjectionRemainDeterministic() throws {
        let first = try makeBasicFixture(reverseRegistration: false)
        let second = try makeBasicFixture(reverseRegistration: true)
        XCTAssertEqual(first.catalog, second.catalog)
        XCTAssertEqual(first.preferences, second.preferences)
        XCTAssertEqual(
            try first.preferences.encodedData(for: first.catalog),
            try second.preferences.encodedData(for: second.catalog)
        )

        let workflow = PluginManagementWorkflow()
        XCTAssertEqual(
            try workflow.list(snapshot: first.snapshot),
            try workflow.list(snapshot: second.snapshot)
        )
        XCTAssertTrue(try first.snapshot.cas.matches(second.snapshot))

        let firstSelection = try workflow.select(
            PluginManagementSelectionRequest(mode: .automatic),
            snapshot: first.snapshot,
            authorizations: [:]
        )
        let secondSelection = try workflow.select(
            PluginManagementSelectionRequest(mode: .automatic),
            snapshot: second.snapshot,
            authorizations: [:]
        )
        XCTAssertEqual(firstSelection.description, secondSelection.description)
    }

    private func makeBasicFixture(reverseRegistration: Bool = false) throws -> BasicFixture {
        let alpha = try PluginCatalogItem(
            id: PluginIdentifier("plugin.alpha"),
            displayName: "Alpha",
            version: "1",
            capability: .unpacker,
            automaticEligible: true,
            matchMetadata: PluginMatchMetadata(
                fileExtensions: ["txt"],
                contentTypeIdentifiers: ["public.plain-text"]
            )
        )
        let beta = try PluginCatalogItem(
            id: PluginIdentifier("plugin.beta"),
            displayName: "Beta",
            version: "1",
            capability: .transform,
            matchMetadata: PluginMatchMetadata(fileExtensions: ["md"])
        )
        let catalog = try PluginCatalog(items: reverseRegistration ? [beta, alpha] : [alpha, beta])
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [alpha.id],
            automaticPluginIdentifiers: [alpha.id],
            preferredAutomaticPluginIdentifiers: [alpha.id]
        )
        let snapshot = try PluginManagementSnapshot(
            revision: PluginManagementRevision(lineage: 11, generation: 7),
            catalog: catalog,
            preferences: preferences
        )
        return BasicFixture(
            alpha: alpha,
            beta: beta,
            catalog: catalog,
            preferences: preferences,
            snapshot: snapshot
        )
    }

    private func makeSettingsFixture(secretPreference: String) throws -> SettingsFixture {
        let settings = [
            try PluginSettingSchema(
                key: "token",
                title: "Token",
                constraint: .string(maximumUTF8Bytes: 256)
            ),
            try PluginSettingSchema(
                key: "profile",
                title: "Profile",
                constraint: .string(maximumUTF8Bytes: 256),
                defaultValue: .string("catalog-default")
            ),
            try PluginSettingSchema(
                key: "enabled",
                title: "Enabled",
                constraint: .boolean,
                defaultValue: .boolean(false)
            )
        ]
        let item = try PluginCatalogItem(
            id: PluginIdentifier("plugin.settings"),
            displayName: "Settings",
            version: "1",
            capability: .transform,
            automaticEligible: true,
            settings: settings
        )
        let policy = try PluginSettingPrivacyPolicy(
            classifications: [
                try item.settingIdentity(forKey: "enabled"): .nonSecret,
                try item.settingIdentity(forKey: "profile"): .nonSecret,
                try item.settingIdentity(forKey: "token"): .secret
            ]
        )
        let catalog = try PluginCatalog(items: [item], settingPrivacyPolicy: policy)
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [item.id],
            automaticPluginIdentifiers: [item.id],
            preferredAutomaticPluginIdentifiers: [item.id],
            settingValues: [item.id: ["profile": .string(secretPreference)]]
        )
        let snapshot = try PluginManagementSnapshot(
            revision: PluginManagementRevision(lineage: 22, generation: 3),
            catalog: catalog,
            preferences: preferences
        )
        return SettingsFixture(
            item: item,
            catalog: catalog,
            preferences: preferences,
            snapshot: snapshot
        )
    }

    private func makeModeFixture() throws -> ModeFixture {
        let alpha = try modeItem("plugin.alpha", automaticEligible: true)
        let beta = try modeItem("plugin.beta", automaticEligible: true)
        let manualOnly = try modeItem("plugin.manual", automaticEligible: false)
        let automaticOnly = try PluginCatalogItem(
            id: PluginIdentifier("plugin.automatic-only"),
            displayName: "plugin.automatic-only",
            version: "1",
            capability: .transform,
            manualEligible: false,
            automaticEligible: true
        )
        let catalog = try PluginCatalog(items: [manualOnly, beta, automaticOnly, alpha])
        let preferences = try PluginCatalogPreferences(
            catalog: catalog,
            enabledPluginIdentifiers: [alpha.id, beta.id],
            automaticPluginIdentifiers: [alpha.id, beta.id],
            preferredAutomaticPluginIdentifiers: [beta.id, alpha.id]
        )
        let snapshot = try PluginManagementSnapshot(
            revision: PluginManagementRevision(lineage: 33, generation: 4),
            catalog: catalog,
            preferences: preferences
        )
        return ModeFixture(
            alpha: alpha,
            beta: beta,
            manualOnly: manualOnly,
            automaticOnly: automaticOnly,
            snapshot: snapshot
        )
    }

    private func modeItem(
        _ identifier: String,
        automaticEligible: Bool
    ) throws -> PluginCatalogItem {
        try PluginCatalogItem(
            id: PluginIdentifier(identifier),
            displayName: identifier,
            version: "1",
            capability: .transform,
            automaticEligible: automaticEligible
        )
    }

    private func makeExternalBindingFixture() throws -> ExternalBindingFixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(
            path: "MacMergePluginManagementWorkflowTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try setPermissions(0o700, on: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let executableData = Data("reviewed-plugin-management-tool".utf8)
        let executableURL = root.appending(path: "reviewed-tool")
        try executableData.write(to: executableURL)
        try setPermissions(0o700, on: executableURL)
        let digest = Array(SHA256.hash(data: executableData))
        let unpackerRule = externalRule(
            identifier: "rule-unpacker",
            capability: .unpacker,
            executableURL: executableURL,
            digest: digest,
            root: root
        )
        let predifferRule = externalRule(
            identifier: "rule-prediffer",
            capability: .prediffer,
            executableURL: executableURL,
            digest: digest,
            root: root
        )
        let policy = try ExternalToolPolicy(externalExecutableRules: [unpackerRule, predifferRule])
        let items = [
            try externalItem("plugin.rule-bound", capability: .unpacker, rule: "rule-unpacker"),
            try externalItem("plugin.rule-mismatch", capability: .unpacker, rule: "rule-prediffer"),
            try externalItem("plugin.rule-absent", capability: .unpacker, rule: "rule-absent"),
            try externalItem("plugin.reference-missing", capability: .unpacker),
            try externalItem("plugin.backend-unavailable", capability: .transform)
        ]
        let catalog = try PluginCatalog(items: items)
        let preferences = try PluginCatalogPreferences(catalog: catalog)
        let snapshot = try PluginManagementSnapshot(
            revision: PluginManagementRevision(lineage: 44, generation: 5),
            catalog: catalog,
            preferences: preferences,
            externalToolPolicy: policy
        )
        return ExternalBindingFixture(
            catalog: catalog,
            policy: policy,
            snapshot: snapshot
        )
    }

    private func externalRule(
        identifier: String,
        capability: ExternalToolCapability,
        executableURL: URL,
        digest: [UInt8],
        root: URL
    ) -> ExternalToolExecutableRule {
        ExternalToolExecutableRule(
            identifier: identifier,
            capability: capability,
            executableURL: executableURL,
            approvedExecutableSHA256: digest,
            permittedWorkingDirectories: [ExternalToolPathScope(url: root, kind: .exactItem)],
            permittedReadScopes: [ExternalToolPathScope(url: root, kind: .directoryTree)],
            allowedEnvironmentKeys: ["SAFE"],
            argumentConstraints: [.value]
        )
    }

    private func externalItem(
        _ identifier: String,
        capability: PluginCapability,
        rule: String? = nil
    ) throws -> PluginCatalogItem {
        try PluginCatalogItem(
            id: PluginIdentifier(identifier),
            displayName: identifier,
            version: "1",
            capability: capability,
            automaticEligible: true,
            externalToolRuleIdentifier: rule
        )
    }

    private func setPermissions(_ permissions: Int, on url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }

    private func diagnostics(_ value: Any) -> String {
        let reflected = Mirror(reflecting: value).children.map {
            "\($0.label ?? "<nil>")=\(String(reflecting: $0.value))"
        }
        return ([String(describing: value), String(reflecting: value)] + reflected)
            .joined(separator: "\n")
    }

    private func assertWorkflowError<Value>(
        _ expected: PluginManagementWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> Value
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? PluginManagementWorkflowError, expected, file: file, line: line)
        }
    }

    private func assertCatalogError<Value>(
        _ expected: PluginCatalogError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ expression: () throws -> Value
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? PluginCatalogError, expected, file: file, line: line)
        }
    }
}

private struct BasicFixture: Sendable {
    let alpha: PluginCatalogItem
    let beta: PluginCatalogItem
    let catalog: PluginCatalog
    let preferences: PluginCatalogPreferences
    let snapshot: PluginManagementSnapshot
}

private struct SettingsFixture: Sendable {
    let item: PluginCatalogItem
    let catalog: PluginCatalog
    let preferences: PluginCatalogPreferences
    let snapshot: PluginManagementSnapshot
}

private struct ModeFixture: Sendable {
    let alpha: PluginCatalogItem
    let beta: PluginCatalogItem
    let manualOnly: PluginCatalogItem
    let automaticOnly: PluginCatalogItem
    let snapshot: PluginManagementSnapshot
}

private struct ExternalBindingFixture: Sendable {
    let catalog: PluginCatalog
    let policy: ExternalToolPolicy
    let snapshot: PluginManagementSnapshot
}

private func preCancelledWorkflowError(
    _ operation: @escaping @Sendable () throws -> Void
) async -> PluginManagementWorkflowError? {
    await Task.detached {
        withUnsafeCurrentTask { $0?.cancel() }
        do {
            try operation()
            return nil
        } catch let error as PluginManagementWorkflowError {
            return error
        } catch {
            return nil
        }
    }.value
}

private func listWorkCost(
    snapshot: PluginManagementSnapshot,
    filter: PluginCatalogFilter
) throws -> Int {
    let rulesCost = snapshot.externalToolPolicy.externalExecutableRules.reduce(0) {
        $0 + ruleWorkCost($1)
    }
    return try snapshotWorkCost(snapshot)
        + snapshot.catalog.items(matching: filter).reduce(0) {
            $0 + 3 * (itemWorkCost($1) + rulesCost)
        }
}

private func snapshotWorkCost(_ snapshot: PluginManagementSnapshot) -> Int {
    1 + snapshot.catalog.items.reduce(0) { $0 + itemWorkCost($1) }
        + snapshot.preferences.enabledPluginIdentifiers.reduce(0) { $0 + $1.rawValue.utf8.count + 1 }
        + snapshot.preferences.automaticPluginIdentifiers.reduce(0) { $0 + $1.rawValue.utf8.count + 1 }
        + snapshot.preferences.preferredAutomaticPluginIdentifiers.reduce(0) { $0 + $1.rawValue.utf8.count + 1 }
        + snapshot.preferences.settingValues.reduce(0) { total, namespace in
            total + namespace.key.rawValue.utf8.count + 1
                + namespace.value.reduce(0) { valueTotal, setting in
                    valueTotal + setting.key.utf8.count + 1 + settingValueWorkCost(setting.value)
                }
        }
        + snapshot.externalToolPolicy.externalExecutableRules.reduce(0) { $0 + ruleWorkCost($1) }
}

private func itemWorkCost(_ item: PluginCatalogItem) -> Int {
    item.id.rawValue.utf8.count + item.displayName.utf8.count
        + (item.summary?.utf8.count ?? 0) + item.version.utf8.count
        + (item.externalToolRuleIdentifier?.utf8.count ?? 0) + 1
        + (item.matchMetadata.fileExtensions + item.matchMetadata.contentTypeIdentifiers).reduce(0) {
            $0 + $1.utf8.count + 1
        }
        + item.settings.reduce(0) { total, schema in
            total + schema.key.utf8.count + schema.title.utf8.count
                + (schema.summary?.utf8.count ?? 0) + 1
                + choiceWorkCost(schema.constraint)
                + (schema.defaultValue.map(settingValueWorkCost) ?? 0)
        }
}

private func ruleWorkCost(_ rule: ExternalToolExecutableRule) -> Int {
    rule.identifier.utf8.count + rule.executableURL.absoluteString.utf8.count
        + rule.approvedExecutableSHA256.count + 1
        + (rule.permittedWorkingDirectories + rule.permittedReadScopes + rule.permittedWriteScopes).reduce(0) {
            $0 + $1.url.absoluteString.utf8.count + 1
        }
        + rule.allowedEnvironmentKeys.reduce(0) { $0 + $1.utf8.count + 1 }
        + rule.argumentConstraints.reduce(0) { total, constraint in
            switch constraint {
            case .exact(let value): total + value.utf8.count + 1
            case .oneOf(let values): total + values.reduce(0) { $0 + $1.utf8.count + 1 }
            case .value, .readPath, .writePath: total + 1
            }
        }
}

private func choiceWorkCost(_ constraint: PluginSettingConstraint) -> Int {
    guard case .choice(let choices) = constraint else { return 0 }
    return choices.reduce(0) { $0 + $1.utf8.count + 1 }
}

private func settingValueWorkCost(_ value: PluginSettingValue) -> Int {
    switch value {
    case .boolean, .integer: 1
    case .string(let value), .choice(let value): value.utf8.count + 1
    }
}
