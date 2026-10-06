import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class AccessibilityEvidenceWorkflowTests: XCTestCase {
    func testCompleteMeasuredBuildBoundEvidenceCoversEveryDeclaredContract() throws {
        let fixture = try makeFixture()
        let result = try evaluate(fixture)

        XCTAssertEqual(result.report.formatVersion, AccessibilityEvidenceWorkflow.reportFormatVersion)
        XCTAssertEqual(result.archive.data.prefix(8), Data("MMAXEWF2".utf8))
        XCTAssertEqual(result.archive.sha256, sha256(result.archive.data))
        XCTAssertEqual(result.receipt.inventorySHA256.count, SHA256.byteCount)
        XCTAssertEqual(result.receipt.evidenceArchiveSHA256, result.archive.sha256)
        XCTAssertEqual(result.receipt.archiveByteCount, result.archive.data.count)
        XCTAssertEqual(result.receipt.requiredEvidenceCount, result.report.matrix.requiredCount)
        XCTAssertEqual(result.receipt.completeEvidenceCount, result.report.matrix.requiredCount)
        XCTAssertEqual(result.receipt.findingCount, 0)
        XCTAssertTrue(result.report.matrix.isComplete)
        XCTAssertTrue(result.report.isEvidenceCompleteAndValid)
        XCTAssertEqual(Set(result.report.matrix.cells.map(\.requirement.kind)), Set(AccessibilityEvidenceRequirementKind.allCases))
        XCTAssertEqual(result.report.findings, [])
        XCTAssertNoThrow(try result.receipt.validateCurrent(inventory: fixture.inventory, evidence: fixture.evidence, attachmentResolver: fixture.resolver))
        XCTAssertNoThrow(
            try AccessibilityEvidenceWorkflow.validate(
                archive: result.archive.data, for: fixture.evidence, boundTo: fixture.inventory, attachmentResolver: fixture.resolver))
    }

    func testArtifactSigningAndCaptureProvenanceAreExactBindings() throws {
        let fixture = try makeFixture()
        let otherBinding = binding(artifact: 0xA1, signing: 0xB2)

        assertWorkflowError(.staleBuild(expected: fixture.inventory.build, actual: fixture.evidence.build)) {
            try evaluate(replacingBundle(fixture, buildBinding: otherBinding))
        }
        assertWorkflowError(.staleBuild(expected: fixture.inventory.build, actual: fixture.inventory.build)) {
            let changed = replacingProvenance(fixture) { provenance in
                AccessibilityEvidenceCaptureProvenance(
                    capturedAtUnixMilliseconds: provenance.capturedAtUnixMilliseconds,
                    runNonce: provenance.runNonce,
                    collector: provenance.collector,
                    build: provenance.build,
                    buildBinding: otherBinding
                )
            }
            return try evaluate(changed)
        }
        for invalid in [
            AccessibilityEvidenceBuildBinding(artifactSHA256: [1], signingIdentitySHA256: digest(2)),
            AccessibilityEvidenceBuildBinding(artifactSHA256: digest(1), signingIdentitySHA256: [2]),
            AccessibilityEvidenceBuildBinding(artifactSHA256: digest(0), signingIdentitySHA256: digest(2)),
            AccessibilityEvidenceBuildBinding(artifactSHA256: digest(1), signingIdentitySHA256: digest(0))
        ] {
            assertWorkflowError(.invalidEvidence(field: "evidence.buildBinding")) {
                try evaluate(replacingBundle(fixture, buildBinding: invalid))
            }
        }
        let invalidProvenances = [
            provenance(fixture, timestamp: 0),
            provenance(fixture, nonce: [UInt8](repeating: 1, count: 15)),
            provenance(fixture, nonce: [UInt8](repeating: 1, count: 65))
        ]
        for invalid in invalidProvenances {
            assertWorkflowError(.invalidEvidence(field: "evidence.provenance")) {
                try evaluate(replacingProvenance(fixture) { _ in invalid })
            }
        }
    }

    func testAppBuildInventoryScenarioEnvironmentAndSnapshotCASAreIndependent() throws {
        let fixture = try makeFixture()
        let staleApp = reference("other-app", 1)
        let staleBuild = reference("other-build", 1)
        let staleInventory = reference("other-inventory", 1)
        let staleScenario = reference("scenario-light", 2)

        assertWorkflowError(.staleApp(expected: fixture.inventory.app, actual: staleApp)) {
            try evaluate(replacingBundle(fixture, app: staleApp))
        }
        assertWorkflowError(.staleBuild(expected: fixture.inventory.build, actual: staleBuild)) {
            try evaluate(replacingBundle(fixture, build: staleBuild))
        }
        assertWorkflowError(.staleInventory(expected: fixture.inventory.reference, actual: staleInventory)) {
            try evaluate(replacingBundle(fixture, inventory: staleInventory))
        }
        assertWorkflowError(.staleScenario(expected: reference("scenario-light", 1), actual: staleScenario)) {
            try evaluate(replacingScenarioReference(fixture, scenarioID: id("scenario-light"), with: staleScenario))
        }

        let environmentMismatch = try replacingSnapshot(fixture, scenarioID: id("scenario-light")) { $0 }
        let changedEnvironment = AccessibilityEvidenceEnvironment(
            fullKeyboardAccessEnabled: true,
            voiceOverEnabled: true,
            increasedContrastEnabled: true,
            differentiateWithoutColorEnabled: true,
            appearance: .light,
            localeIdentifier: "fr-FR",
            localizationExpansionThousandths: 2_000
        )
        let environmentEvidence = try replacingEnvironment(environmentMismatch, scenarioID: id("scenario-light"), with: changedEnvironment)
        let environmentReport = try evaluate(environmentEvidence).report
        XCTAssertTrue(environmentReport.findings.contains { $0.code == .environmentMismatch && $0.severity == .error })

        let changedSnapshot = try replacingSnapshot(fixture, scenarioID: id("scenario-light")) { snapshot in
            snapshotWith(snapshot, id: id("snapshot-light-v2"))
        }
        let snapshotReport = try evaluate(changedSnapshot).report
        XCTAssertTrue(snapshotReport.findings.contains { $0.code == .semanticSnapshotMismatch && $0.severity == .error })
        XCTAssertFalse(snapshotReport.isEvidenceCompleteAndValid)
    }

    func testRoleLabelHierarchyHiddenFocusActionsShortcutsStatesValueAndHintAreExact() throws {
        let fixture = try makeFixture()
        let mutations: [(String, (AccessibilitySemanticElement) -> AccessibilitySemanticElement)] = [
            ("role", { self.elementWith($0, role: .link) }),
            ("label", { self.elementWith($0, label: "Store") }),
            ("hierarchy", { self.elementWith($0, parentID: .some(nil)) }),
            ("hidden", { self.elementWith($0, hidden: true) }),
            ("focus", { self.elementWith($0, focusable: false) }),
            ("actions", { self.elementWith($0, actions: [$0.actions[0], self.action("secondary-action", .custom, label: "Secondary")]) }),
            ("shortcuts", { self.elementWith($0, shortcuts: [self.shortcut("save-shortcut", actionID: "save-action", key: "x")]) }),
            ("enabled", { self.elementWith($0, enabled: false) }),
            ("checked", { self.elementWith($0, checked: .off) }),
            ("selected", { self.elementWith($0, selected: .selected) }),
            ("value", { self.elementWith($0, value: "Changed") }),
            ("hint", { self.elementWith($0, hint: "Different hint") })
        ]

        for (name, mutation) in mutations {
            let changed = try replacingSnapshot(fixture, scenarioID: id("scenario-light")) { snapshot in
                replacingElement(snapshot, elementID: id("save-control"), mutation: mutation)
            }
            let report = try evaluate(changed).report
            XCTAssertTrue(report.findings.contains { $0.code == .semanticElementMismatch }, name)
            XCTAssertFalse(report.isEvidenceCompleteAndValid, name)
        }
    }

    func testAnnouncementsAndExactFocusOrderProduceDedicatedFindings() throws {
        let fixture = try makeFixture()
        let announcementChanged = try replacingSnapshot(fixture, scenarioID: id("scenario-light")) { snapshot in
            snapshotWith(
                snapshot,
                announcements: [
                    AccessibilityAnnouncement(
                        id: id("save-announcement"),
                        kind: .warning,
                        message: "Saved",
                        relatedElementID: id("save-control"),
                        triggerActionID: id("save-action"),
                        localizationExpansionEvidenceTokens: [localizationToken("announcement-localization")]
                    )
                ]
            )
        }
        let announcementReport = try evaluate(announcementChanged).report
        XCTAssertTrue(announcementReport.findings.contains { $0.code == .announcementMismatch })

        let focusChanged = try replacingSnapshot(fixture, scenarioID: id("scenario-light")) { snapshot in
            snapshotWith(snapshot, focusOrder: [])
        }
        let focusReport = try evaluate(focusChanged).report
        XCTAssertTrue(focusReport.findings.contains { $0.code == .focusOrderMismatch })
        XCTAssertEqual(
            focusReport.matrix.cells.first { $0.requirement.kind == .focusOrder && $0.requirement.scenarioID == id("scenario-light") }?.status, .complete)
    }

    func testPerControlContrastNonColorDarkAndLocalizationNeedScopedMeasurements() throws {
        let fixture = try makeFixture()
        let cases: [(AccessibilityEvidenceRequirementKind, (AccessibilityAuditEvidence) -> AccessibilityAuditEvidence)] = [
            (
                .increasedContrast,
                { evidence in
                    AccessibilityAuditEvidence(
                        contrast: evidence.contrast.map {
                            AccessibilityContrastEvidence(
                                token: $0.token,
                                subjectID: $0.subjectID,
                                surface: $0.surface,
                                measuredRatioThousandths: 2_999,
                                requiredRatioThousandths: 3_000,
                                origin: $0.origin,
                                source: $0.source
                            )
                        },
                        differentiateWithoutColor: evidence.differentiateWithoutColor,
                        localizationExpansion: evidence.localizationExpansion
                    )
                }
            ),
            (
                .differentiateWithoutColor,
                { evidence in
                    AccessibilityAuditEvidence(
                        contrast: evidence.contrast,
                        differentiateWithoutColor: evidence.differentiateWithoutColor.map {
                            AccessibilityDifferentiateWithoutColorEvidence(
                                token: $0.token,
                                meaning: $0.meaning,
                                nonColorCues: [],
                                origin: $0.origin,
                                source: $0.source
                            )
                        },
                        localizationExpansion: evidence.localizationExpansion
                    )
                }
            ),
            (
                .localizationExpansion,
                { evidence in
                    AccessibilityAuditEvidence(
                        contrast: evidence.contrast,
                        differentiateWithoutColor: evidence.differentiateWithoutColor,
                        localizationExpansion: evidence.localizationExpansion.map {
                            AccessibilityLocalizationExpansionEvidence(
                                token: $0.token,
                                subjectID: $0.subjectID,
                                field: $0.field,
                                localeIdentifier: $0.localeIdentifier,
                                baselineText: $0.baselineText,
                                expandedText: $0.baselineText,
                                outcome: .fits,
                                origin: $0.origin,
                                source: $0.source
                            )
                        }
                    )
                }
            )
        ]

        for (kind, mutation) in cases {
            let changed = try replacingSnapshot(fixture, scenarioID: id("scenario-dark")) { snapshot in
                snapshotWith(snapshot, evidence: mutation(snapshot.evidence))
            }
            let report = try evaluate(changed).report
            let cells = report.matrix.cells.filter {
                $0.requirement.scenarioID == id("scenario-dark") && $0.requirement.kind == kind
            }
            XCTAssertTrue(cells.contains { $0.status == .invalid }, kind.rawValue)
            XCTAssertTrue(report.findings.contains { $0.code == .evidenceValueMismatch }, kind.rawValue)
            if kind == .increasedContrast {
                XCTAssertTrue(
                    report.matrix.cells.filter {
                        $0.requirement.scenarioID == id("scenario-dark") && $0.requirement.kind == .darkMode
                    }.contains { $0.status == .invalid })
            }
        }
    }

    func testSuccessfulActionsRequireExactCanonicalPostconditions() throws {
        let fixture = try makeFixture()
        let actionKinds: Set<AccessibilityEvidenceRequirementKind> = [.actionBehavior, .fullKeyboardAccess, .voiceOverActivation]

        for mode in ["missing", "wrong"] {
            let changed = try mapObservations(fixture) { observation in
                guard actionKinds.contains(observation.requirement.kind),
                    observation.requirement.discriminator == id("save-action")
                else { return observation }
                return AccessibilityBehaviorObservation(
                    id: observation.id,
                    requirement: observation.requirement,
                    snapshotID: observation.snapshotID,
                    value: observation.value,
                    origin: observation.origin,
                    source: observation.source,
                    attachmentTokens: observation.attachmentTokens,
                    postconditionSnapshot: mode == "missing" ? nil : emptySnapshot("wrong-postcondition")
                )
            }
            let report = try evaluate(changed).report
            let expectedCount = actionKinds.count * fixture.evidence.scenarios.count
            XCTAssertEqual(report.findings.filter { $0.code == .invalidActionPostcondition }.count, expectedCount, mode)
            XCTAssertEqual(report.matrix.invalidCount, expectedCount, mode)
        }

        let blockedWithPostcondition = try mapObservations(fixture) { observation in
            guard observation.requirement.kind == .actionBehavior else { return observation }
            return AccessibilityBehaviorObservation(
                id: observation.id,
                requirement: observation.requirement,
                snapshotID: observation.snapshotID,
                value: .action(actionID: id("save-action"), kind: .activate, outcome: .blocked),
                origin: observation.origin,
                source: observation.source,
                attachmentTokens: observation.attachmentTokens,
                postconditionSnapshot: emptySnapshot("unexpected-postcondition")
            )
        }
        let blockedReport = try evaluate(blockedWithPostcondition).report
        XCTAssertTrue(blockedReport.findings.contains { $0.code == .invalidActionPostcondition })
    }

    func testAttachmentResolverVerifiesExactBytesDeclaredSizeHashAndOverflow() throws {
        let fixture = try makeFixture()
        let first = try XCTUnwrap(fixture.evidence.attachments.first)

        assertWorkflowError(.invalidEvidence(field: "attachments.byteCount")) {
            try AccessibilityEvidenceWorkflow.evaluate(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                attachmentResolver: { identifier, declared, cancellation in
                    let bytes = try fixture.resolver(identifier, declared, cancellation)
                    return bytes.dropLast()
                }
            )
        }
        assertWorkflowError(.invalidEvidence(field: "attachments.sha256")) {
            try AccessibilityEvidenceWorkflow.evaluate(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                attachmentResolver: { identifier, declared, cancellation in
                    var bytes = try fixture.resolver(identifier, declared, cancellation)
                    if identifier == first.id { bytes[bytes.startIndex] ^= 0xFF }
                    return bytes
                }
            )
        }
        assertWorkflowError(.invalidEvidence(field: "attachments.resolver")) {
            try AccessibilityEvidenceWorkflow.evaluate(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                attachmentResolver: { _, _, _ in
                    throw AccessibilityEvidenceAttachmentResolutionError.exceedsDeclaredByteCount
                }
            )
        }
    }

    func testCanonicalAttachmentBindsObservationSnapshotEnvironmentAndProvenance() throws {
        let fixture = try makeFixture()
        let scenario = try XCTUnwrap(fixture.evidence.scenarios.first)
        let observation = try XCTUnwrap(scenario.observations.first)
        let baseline = try AccessibilityEvidenceWorkflow.canonicalAttachmentData(for: observation, capturedIn: scenario)

        let changedEnvironment = AccessibilityScenarioEvidence(
            scenario: scenario.scenario,
            environment: AccessibilityEvidenceEnvironment(
                fullKeyboardAccessEnabled: true,
                voiceOverEnabled: true,
                increasedContrastEnabled: true,
                differentiateWithoutColorEnabled: true,
                appearance: scenario.environment.appearance,
                localeIdentifier: "fr-FR",
                localizationExpansionThousandths: 2_000
            ),
            provenance: scenario.provenance,
            snapshot: scenario.snapshot,
            observations: scenario.observations
        )
        let changedProvenance = AccessibilityScenarioEvidence(
            scenario: scenario.scenario,
            environment: scenario.environment,
            provenance: AccessibilityEvidenceCaptureProvenance(
                capturedAtUnixMilliseconds: scenario.provenance.capturedAtUnixMilliseconds + 1,
                runNonce: scenario.provenance.runNonce,
                collector: scenario.provenance.collector,
                build: scenario.provenance.build,
                buildBinding: scenario.provenance.buildBinding
            ),
            snapshot: scenario.snapshot,
            observations: scenario.observations
        )
        let changedSnapshot = AccessibilityScenarioEvidence(
            scenario: scenario.scenario,
            environment: scenario.environment,
            provenance: scenario.provenance,
            snapshot: snapshotWith(scenario.snapshot, id: id("changed-snapshot")),
            observations: scenario.observations
        )
        XCTAssertNotEqual(baseline, try AccessibilityEvidenceWorkflow.canonicalAttachmentData(for: observation, capturedIn: changedEnvironment))
        XCTAssertNotEqual(baseline, try AccessibilityEvidenceWorkflow.canonicalAttachmentData(for: observation, capturedIn: changedProvenance))
        XCTAssertNotEqual(baseline, try AccessibilityEvidenceWorkflow.canonicalAttachmentData(for: observation, capturedIn: changedSnapshot))

        let outsider = AccessibilityBehaviorObservation(
            id: id("outsider"),
            requirement: observation.requirement,
            snapshotID: observation.snapshotID,
            value: observation.value,
            origin: .automatedMeasurement,
            source: "collector"
        )
        assertWorkflowError(.invalidEvidence(field: "attachment.observationBinding")) {
            try AccessibilityEvidenceWorkflow.canonicalAttachmentData(for: outsider, capturedIn: scenario)
        }
    }

    func testCallerAssertionsNeverCompleteMeasuredCells() throws {
        let fixture = try makeFixture()
        let asserted = try mapObservations(fixture) { observation in
            AccessibilityBehaviorObservation(
                id: observation.id,
                requirement: observation.requirement,
                snapshotID: observation.snapshotID,
                value: observation.value,
                origin: .callerAssertion,
                source: observation.source,
                attachmentTokens: observation.attachmentTokens,
                postconditionSnapshot: observation.postconditionSnapshot
            )
        }
        let report = try evaluate(asserted).report

        XCTAssertEqual(report.matrix.assertionOnlyCount, report.matrix.requiredCount)
        XCTAssertEqual(report.matrix.completeCount, 0)
        XCTAssertFalse(report.matrix.isComplete)
        XCTAssertFalse(report.isEvidenceCompleteAndValid)
        XCTAssertEqual(report.findings.filter { $0.code == .assertionOnlyEvidence }.count, report.matrix.requiredCount)
    }

    func testDuplicateAndInvalidEvidenceProduceIndependentFindings() throws {
        let fixture = try makeFixture()
        let changed = try mapScenarios(fixture) { scenario in
            guard scenario.id == id("scenario-light"), let first = scenario.observations.first else {
                return scenario
            }
            let stripped = AccessibilityBehaviorObservation(
                id: first.id,
                requirement: first.requirement,
                snapshotID: first.snapshotID,
                value: first.value,
                origin: .callerAssertion,
                source: first.source,
                attachmentTokens: [],
                postconditionSnapshot: first.postconditionSnapshot
            )
            return AccessibilityScenarioEvidence(
                scenario: scenario.scenario,
                environment: scenario.environment,
                provenance: scenario.provenance,
                snapshot: scenario.snapshot,
                observations: [stripped, stripped] + Array(scenario.observations.dropFirst())
            )
        }
        let report = try evaluate(changed).report
        let codes = Set(report.findings.map(\.code))

        XCTAssertTrue(codes.contains(.duplicateObservationToken))
        XCTAssertTrue(codes.contains(.duplicateEvidence))
        XCTAssertTrue(codes.contains(.assertionOnlyEvidence))
        XCTAssertTrue(codes.contains(.attachmentReferenceMissing))
        XCTAssertEqual(report.matrix.cells.first { $0.requirement == changed.evidence.scenarios[0].observations[0].requirement }?.status, .invalid)
    }

    func testFocusOrderIDsRejectWhitespaceDuplicatesAndCountOverflow() throws {
        let fixture = try makeFixture()
        let invalidID = try replacingSnapshot(fixture, scenarioID: id("scenario-light")) { snapshot in
            snapshotWith(snapshot, focusOrder: [id("bad id")])
        }
        assertWorkflowError(.invalidEvidence(field: "evidence.snapshot.focusOrder")) {
            try evaluate(invalidID)
        }

        let duplicate = try replacingSnapshot(fixture, scenarioID: id("scenario-light")) { snapshot in
            snapshotWith(snapshot, focusOrder: [id("save-control"), id("save-control")])
        }
        assertWorkflowError(.invalidEvidence(field: "evidence.snapshot.focusOrder")) {
            try evaluate(duplicate)
        }

        assertWorkflowError(.countLimitExceeded(kind: .elements, maximum: 1)) {
            try evaluate(fixture, limits: limits(maximumElements: 1))
        }
    }

    func testNFCComparisonCanonicalArchiveReceiptAndOrderingAreDeterministic() throws {
        let fixture = try makeFixture()
        let decomposed = "Cafe\u{301}"
        let composed = decomposed.precomposedStringWithCanonicalMapping
        let nfcInventory = try replacingInventorySnapshots(fixture.inventory) { snapshot in
            relabelSnapshot(snapshot, label: composed)
        }
        let nfcFixture = try replacingAllSnapshots(fixture, inventory: nfcInventory) { snapshot in
            relabelSnapshot(snapshot, label: decomposed)
        }
        let nfcResult = try evaluate(nfcFixture)
        XCTAssertFalse(nfcResult.report.findings.contains { $0.code == .semanticElementMismatch })

        let reversedInventory = AccessibilityProductionControlInventory(
            app: nfcFixture.inventory.app,
            build: nfcFixture.inventory.build,
            buildBinding: nfcFixture.inventory.buildBinding,
            reference: nfcFixture.inventory.reference,
            controls: nfcFixture.inventory.controls.reversed(),
            scenarios: nfcFixture.inventory.scenarios.reversed()
        )
        let reversedBundle = AccessibilityEvidenceBundle(
            reference: nfcFixture.evidence.reference,
            app: nfcFixture.evidence.app,
            build: nfcFixture.evidence.build,
            buildBinding: nfcFixture.evidence.buildBinding,
            inventory: nfcFixture.evidence.inventory,
            scenarios: nfcFixture.evidence.scenarios.reversed().map { scenario in
                AccessibilityScenarioEvidence(
                    scenario: scenario.scenario,
                    environment: scenario.environment,
                    provenance: scenario.provenance,
                    snapshot: scenario.snapshot,
                    observations: scenario.observations.reversed()
                )
            },
            attachments: nfcFixture.evidence.attachments.reversed()
        )
        let reversedFixture = Fixture(inventory: reversedInventory, evidence: reversedBundle, attachmentData: nfcFixture.attachmentData)
        let reversedResult = try evaluate(reversedFixture)

        XCTAssertEqual(reversedResult.archive, nfcResult.archive)
        XCTAssertEqual(reversedResult.receipt, nfcResult.receipt)
        XCTAssertEqual(reversedResult.report, nfcResult.report)
    }

    func testArchiveRejectsStrictFramingVersionChecksumAndNoncanonicalPayload() throws {
        let fixture = try makeFixture()
        let result = try evaluate(fixture)

        var magic = result.archive.data
        magic[magic.startIndex] ^= 0x01
        assertWorkflowError(.invalidArchive) { try validate(magic, fixture) }

        var version = result.archive.data
        version[8] = 3
        version[9] = 0
        assertWorkflowError(.unsupportedArchiveVersion(3)) { try validate(version, fixture) }

        var reserved = result.archive.data
        reserved[10] = 1
        assertWorkflowError(.invalidArchive) { try validate(reserved, fixture) }

        var checksum = result.archive.data
        checksum[checksum.index(before: checksum.endIndex)] ^= 0x01
        assertWorkflowError(.archiveChecksumMismatch) { try validate(checksum, fixture) }

        var noncanonical = result.archive.data
        let payloadStart = 84
        noncanonical[noncanonical.index(before: noncanonical.endIndex)] ^= 0x01
        let payload = noncanonical.subdata(in: payloadStart..<noncanonical.count)
        noncanonical.replaceSubrange(52..<84, with: sha256(payload))
        assertWorkflowError(.nonCanonicalArchive) { try validate(noncanonical, fixture) }

        assertWorkflowError(.invalidArchive) { try validate(result.archive.data.dropLast(), fixture) }
    }

    func testReceiptCASDetectsStaleOwnersAndSameRevisionContentChanges() throws {
        let fixture = try makeFixture()
        let result = try evaluate(fixture)

        let staleEvidence = replacingBundle(fixture, reference: reference("evidence", 2))
        assertWorkflowError(.staleEvidence(expected: fixture.evidence.reference, actual: staleEvidence.evidence.reference)) {
            try result.receipt.validateCurrent(inventory: staleEvidence.inventory, evidence: staleEvidence.evidence, attachmentResolver: staleEvidence.resolver)
        }

        let changedInventory = AccessibilityProductionControlInventory(
            app: fixture.inventory.app,
            build: fixture.inventory.build,
            buildBinding: fixture.inventory.buildBinding,
            reference: fixture.inventory.reference,
            controls: fixture.inventory.controls.reversed(),
            scenarios: fixture.inventory.scenarios.map { scenario in
                AccessibilityEvidenceInventoryScenario(
                    reference: scenario.reference,
                    environment: scenario.environment,
                    expectedSnapshot: scenario.expectedSnapshot,
                    requiredEnvironmentChecks: scenario.requiredEnvironmentChecks,
                    actionPostconditions: scenario.actionPostconditions.map {
                        AccessibilityEvidenceActionPostcondition(actionID: $0.actionID, snapshotSHA256: digest(0xEE))
                    }
                )
            }
        )
        assertWorkflowError(.inventoryContentsChanged(fixture.inventory.reference)) {
            try result.receipt.validateCurrent(inventory: changedInventory, evidence: fixture.evidence, attachmentResolver: fixture.resolver)
        }

        let changedEvidence = try mapObservations(fixture) { observation in
            AccessibilityBehaviorObservation(
                id: observation.id,
                requirement: observation.requirement,
                snapshotID: observation.snapshotID,
                value: observation.value,
                origin: observation.origin,
                source: observation.source + "-changed",
                attachmentTokens: observation.attachmentTokens,
                postconditionSnapshot: observation.postconditionSnapshot
            )
        }
        assertWorkflowError(.evidenceContentsChanged(fixture.evidence.reference)) {
            try result.receipt.validateCurrent(
                inventory: changedEvidence.inventory, evidence: changedEvidence.evidence, attachmentResolver: changedEvidence.resolver)
        }
    }

    func testMissingUnexpectedDuplicateAndMismatchedFindingsHaveStableSeverityOrder() throws {
        let fixture = try makeFixture()
        let light = try XCTUnwrap(fixture.evidence.scenarios.first { $0.id == id("scenario-light") })
        let unexpected = AccessibilityScenarioEvidence(
            scenario: reference("unexpected-scenario", 1),
            environment: light.environment,
            provenance: light.provenance,
            snapshot: light.snapshot,
            observations: []
        )
        let malformed = AccessibilityEvidenceBundle(
            reference: fixture.evidence.reference,
            app: fixture.evidence.app,
            build: fixture.evidence.build,
            buildBinding: fixture.evidence.buildBinding,
            inventory: fixture.evidence.inventory,
            scenarios: [light, light, unexpected],
            attachments: fixture.evidence.attachments
        )
        let malformedFixture = Fixture(inventory: fixture.inventory, evidence: malformed, attachmentData: fixture.attachmentData)
        let report = try evaluate(malformedFixture).report
        let codes = Set(report.findings.map(\.code))

        XCTAssertTrue(codes.contains(.duplicateScenarioEvidence))
        XCTAssertTrue(codes.contains(.missingScenarioEvidence))
        XCTAssertTrue(codes.contains(.unexpectedScenarioEvidence))
        XCTAssertTrue(codes.contains(.orphanAttachment))
        XCTAssertTrue(codes.contains(.missingEvidence))
        XCTAssertEqual(report.highestSeverity, .error)
        XCTAssertTrue(report.containsErrors)
        XCTAssertEqual(report.findings.map(\.severity).prefix { $0 == .error }.count, report.findings.filter { $0.severity == .error }.count)
        XCTAssertEqual(report.findings.last?.severity, .warning)
    }

    func testRedactionAndStrictScopeWordingNeverExposePayloads() throws {
        let fixture = try makeFixture()
        let result = try evaluate(fixture)
        let secret = "TOP-SECRET-PAYLOAD"
        let environment = AccessibilityEvidenceEnvironment(
            fullKeyboardAccessEnabled: true,
            voiceOverEnabled: true,
            increasedContrastEnabled: true,
            differentiateWithoutColorEnabled: true,
            appearance: .dark,
            localeIdentifier: secret,
            localizationExpansionThousandths: 2_000
        )
        let attachment = AccessibilityEvidenceAttachment(
            id: id("redacted"),
            kind: .measurementRecord,
            mediaType: secret,
            byteCount: 1,
            sha256: digest(1),
            source: secret
        )
        let value = AccessibilityEvidenceValue.semanticLabel(secret)

        for description in [
            environment.description,
            environment.debugDescription,
            attachment.description,
            attachment.debugDescription,
            value.description,
            value.debugDescription,
            fixture.inventory.description,
            fixture.evidence.description,
            result.archive.description,
            result.receipt.description
        ] {
            XCTAssertFalse(description.contains(secret), description)
            XCTAssertTrue(description.contains("<redacted>"), description)
        }
        XCTAssertEqual(
            AccessibilityEvidenceReport.scopeStatement,
            "Deterministic validation of caller-supplied, build-bound semantic captures and verified attachment-backed observations for declared role, label, hierarchy, visibility, focusability, shortcuts, state, action postconditions, announcements, contrast, non-color, dark appearance, and localization requirements; not independent runtime accessibility or production compliance."
        )
        XCTAssertFalse(AccessibilityEvidenceReport.scopeStatement.hasPrefix(" "))
        XCTAssertFalse(AccessibilityEvidenceReport.scopeStatement.hasSuffix(" "))
        XCTAssertTrue(
            result.report.findings.allSatisfy { !$0.message.contains(secret) && $0.message == $0.message.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    func testEveryLimitRejectsZeroAndAboveHardMaximumWithTypedIdentity() throws {
        let fixture = try makeFixture()
        let invalid: [(AccessibilityEvidenceLimit, AccessibilityEvidenceWorkflowLimits)] = [
            (.controls, limits(maximumControls: 0)),
            (.scenarios, limits(maximumScenarios: 0)),
            (.elements, limits(maximumElements: 0)),
            (.observations, limits(maximumObservations: 0)),
            (.requiredRequirements, limits(maximumRequiredRequirements: 0)),
            (.attachments, limits(maximumAttachments: 0)),
            (.attachmentTokens, limits(maximumAttachmentTokens: 0)),
            (.attachmentTokensPerObservation, limits(maximumAttachmentTokensPerObservation: 0)),
            (.totalItems, limits(maximumTotalItems: 0)),
            (.stringUTF8Bytes, limits(maximumStringUTF8Bytes: 0)),
            (.totalStringUTF8Bytes, limits(maximumTotalStringUTF8Bytes: 0)),
            (.attachmentBytes, limits(maximumAttachmentBytes: 0)),
            (.totalAttachmentBytes, limits(maximumTotalAttachmentBytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.findings, limits(maximumFindings: 0)),
            (.archiveBytes, limits(maximumArchiveBytes: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0)),
            (.controls, limits(maximumControls: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.scenarios, limits(maximumScenarios: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.elements, limits(maximumElements: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.observations, limits(maximumObservations: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.requiredRequirements, limits(maximumRequiredRequirements: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.attachments, limits(maximumAttachments: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.attachmentTokens, limits(maximumAttachmentTokens: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.attachmentTokensPerObservation, limits(maximumAttachmentTokensPerObservation: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.totalItems, limits(maximumTotalItems: AccessibilityEvidenceWorkflowLimits.hardMaximumTotalItems + 1)),
            (.stringUTF8Bytes, limits(maximumStringUTF8Bytes: AccessibilityEvidenceWorkflowLimits.hardMaximumStringUTF8Bytes + 1)),
            (.totalStringUTF8Bytes, limits(maximumTotalStringUTF8Bytes: AccessibilityEvidenceWorkflowLimits.hardMaximumTotalStringUTF8Bytes + 1)),
            (.attachmentBytes, limits(maximumAttachmentBytes: AccessibilityEvidenceWorkflowLimits.hardMaximumAttachmentBytes + 1)),
            (.totalAttachmentBytes, limits(maximumTotalAttachmentBytes: AccessibilityEvidenceWorkflowLimits.hardMaximumTotalAttachmentBytes + 1)),
            (.workUnits, limits(maximumWorkUnits: AccessibilityEvidenceWorkflowLimits.hardMaximumWorkUnits + 1)),
            (.findings, limits(maximumFindings: AccessibilityEvidenceWorkflowLimits.hardMaximumCount + 1)),
            (.archiveBytes, limits(maximumArchiveBytes: AccessibilityEvidenceWorkflowLimits.hardMaximumArchiveBytes + 1)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: AccessibilityEvidenceWorkflowLimits.hardMaximumCancellationCheckInterval + 1))
        ]
        XCTAssertEqual(Set(invalid.map(\.0)), Set(AccessibilityEvidenceLimit.allCases))
        for (kind, value) in invalid {
            assertWorkflowError(.invalidLimit(kind)) {
                try evaluate(fixture, limits: value)
            }
        }
        XCTAssertNoThrow(try evaluate(fixture, limits: hardLimits()))
    }

    func testOperationalCountStringAttachmentFindingArchiveAndWorkLimitsFailClosed() throws {
        let fixture = try makeFixture()
        let cases: [(AccessibilityEvidenceWorkflowError, AccessibilityEvidenceWorkflowLimits)] = [
            (.countLimitExceeded(kind: .scenarios, maximum: 1), limits(maximumScenarios: 1)),
            (.countLimitExceeded(kind: .elements, maximum: 1), limits(maximumElements: 1)),
            (.countLimitExceeded(kind: .observations, maximum: 1), limits(maximumObservations: 1)),
            (.countLimitExceeded(kind: .requiredRequirements, maximum: 1), limits(maximumRequiredRequirements: 1)),
            (.countLimitExceeded(kind: .attachments, maximum: 1), limits(maximumAttachments: 1)),
            (.countLimitExceeded(kind: .attachmentTokens, maximum: 1), limits(maximumAttachmentTokens: 1)),
            (.countLimitExceeded(kind: .totalItems, maximum: 1), limits(maximumTotalItems: 1)),
            (.stringTooLarge(field: "inventory.reference.id", maximumUTF8Bytes: 1), limits(maximumStringUTF8Bytes: 1)),
            (.totalStringsTooLarge(maximumUTF8Bytes: 1), limits(maximumTotalStringUTF8Bytes: 1)),
            (.attachmentTooLarge(maximumBytes: 1), limits(maximumAttachmentBytes: 1)),
            (.totalAttachmentsTooLarge(maximumBytes: 1), limits(maximumTotalAttachmentBytes: 1)),
            (.archiveTooLarge(maximumBytes: 1), limits(maximumArchiveBytes: 1)),
            (.workLimitExceeded(maximum: 1), limits(maximumWorkUnits: 1))
        ]
        for (expected, value) in cases {
            assertWorkflowError(expected) { try evaluate(fixture, limits: value) }
        }

        let extraControlInventory = AccessibilityProductionControlInventory(
            app: fixture.inventory.app,
            build: fixture.inventory.build,
            buildBinding: fixture.inventory.buildBinding,
            reference: fixture.inventory.reference,
            controls: fixture.inventory.controls + [AccessibilityProductionControl(id: id("extra-control"), scenarioIDs: [id("scenario-light")])],
            scenarios: fixture.inventory.scenarios
        )
        let extraControl = Fixture(inventory: extraControlInventory, evidence: fixture.evidence, attachmentData: fixture.attachmentData)
        assertWorkflowError(.countLimitExceeded(kind: .controls, maximum: 1)) {
            try evaluate(extraControl, limits: limits(maximumControls: 1))
        }
    }

    func testAttachmentTokenPerObservationFindingAndCancellationLimitsAreEnforced() throws {
        let fixture = try makeFixture()
        let tooManyTokens = try mapObservations(fixture) { observation in
            AccessibilityBehaviorObservation(
                id: observation.id,
                requirement: observation.requirement,
                snapshotID: observation.snapshotID,
                value: observation.value,
                origin: observation.origin,
                source: observation.source,
                attachmentTokens: observation.attachmentTokens + [id("extra-attachment")],
                postconditionSnapshot: observation.postconditionSnapshot
            )
        }
        assertWorkflowError(.countLimitExceeded(kind: .attachmentTokensPerObservation, maximum: 1)) {
            try evaluate(tooManyTokens, limits: limits(maximumAttachmentTokensPerObservation: 1))
        }

        let missing = Fixture(
            inventory: fixture.inventory,
            evidence: AccessibilityEvidenceBundle(
                reference: fixture.evidence.reference,
                app: fixture.evidence.app,
                build: fixture.evidence.build,
                buildBinding: fixture.evidence.buildBinding,
                inventory: fixture.evidence.inventory,
                scenarios: [],
                attachments: []
            ),
            attachmentData: [:]
        )
        assertWorkflowError(.findingLimitExceeded(maximum: 1)) {
            try evaluate(missing, limits: limits(maximumFindings: 1))
        }

        assertWorkflowError(.cancelled) {
            try AccessibilityEvidenceWorkflow.evaluate(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                attachmentResolver: fixture.resolver,
                cancellationCheck: { true }
            )
        }
        assertWorkflowError(.cancelled) {
            try AccessibilityEvidenceWorkflow.evaluate(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                attachmentResolver: { _, _, _ in throw CancellationError() },
                cancellationCheck: { false }
            )
        }
    }

    private struct Fixture {
        let inventory: AccessibilityProductionControlInventory
        let evidence: AccessibilityEvidenceBundle
        let attachmentData: [AccessibilityStableID: Data]

        var resolver: AccessibilityEvidenceWorkflow.AttachmentResolver {
            { identifier, declaredByteCount, cancellationCheck in
                if cancellationCheck() { throw CancellationError() }
                guard let data = attachmentData[identifier], data.count <= declaredByteCount else {
                    throw AccessibilityEvidenceAttachmentResolutionError.exceedsDeclaredByteCount
                }
                return data
            }
        }
    }

    private func makeFixture() throws -> Fixture {
        let app = reference("macmerge-app", 7)
        let build = reference("production-build", 11)
        let inventoryReference = reference("accessibility-inventory", 13)
        let buildBinding = binding(artifact: 0x11, signing: 0x22)
        let lightEnvironment = environment(.light)
        let darkEnvironment = environment(.dark)
        let lightSnapshot = snapshot("light", label: "Save")
        let darkSnapshot = snapshot("dark", label: "Save")
        let lightScenario = try inventoryScenario(
            "scenario-light",
            environment: lightEnvironment,
            snapshot: lightSnapshot,
            checks: [.fullKeyboardAccess, .voiceOverActivation, .increasedContrast, .differentiateWithoutColor, .localizationExpansion]
        )
        let darkScenario = try inventoryScenario(
            "scenario-dark",
            environment: darkEnvironment,
            snapshot: darkSnapshot,
            checks: Set(AccessibilityEvidenceEnvironmentCheck.allCases)
        )
        let inventory = AccessibilityProductionControlInventory(
            app: app,
            build: build,
            buildBinding: buildBinding,
            reference: inventoryReference,
            controls: [AccessibilityProductionControl(id: id("save-control"), scenarioIDs: [lightScenario.id, darkScenario.id])],
            scenarios: [lightScenario, darkScenario]
        )
        let collector = reference("accessibility-collector", 5)
        let evidenceScenarios = [lightScenario, darkScenario].enumerated().map { index, scenario in
            let provenance = AccessibilityEvidenceCaptureProvenance(
                capturedAtUnixMilliseconds: 1_800_000_000_000 + UInt64(index),
                runNonce: [UInt8](repeating: UInt8(index + 1), count: 16),
                collector: collector,
                build: build,
                buildBinding: buildBinding
            )
            let observations = expectedObservations(scenario, snapshot: scenario.expectedSnapshot)
            return AccessibilityScenarioEvidence(
                scenario: scenario.reference,
                environment: scenario.environment,
                provenance: provenance,
                snapshot: scenario.expectedSnapshot,
                observations: observations
            )
        }
        let bareBundle = AccessibilityEvidenceBundle(
            reference: reference("evidence", 17),
            app: app,
            build: build,
            buildBinding: buildBinding,
            inventory: inventoryReference,
            scenarios: evidenceScenarios
        )
        return try bindAttachments(inventory: inventory, evidence: bareBundle)
    }

    private func inventoryScenario(
        _ name: String,
        environment: AccessibilityEvidenceEnvironment,
        snapshot: AccessibilityCommandControlSnapshot,
        checks: Set<AccessibilityEvidenceEnvironmentCheck>
    ) throws -> AccessibilityEvidenceInventoryScenario {
        AccessibilityEvidenceInventoryScenario(
            reference: reference(name, 1),
            environment: environment,
            expectedSnapshot: snapshot,
            requiredEnvironmentChecks: checks,
            actionPostconditions: [
                AccessibilityEvidenceActionPostcondition(
                    actionID: id("save-action"),
                    snapshotSHA256: sha256(try AccessibilityAudit.exactSnapshotData(of: snapshot))
                )
            ]
        )
    }

    private func expectedObservations(
        _ scenario: AccessibilityEvidenceInventoryScenario,
        snapshot: AccessibilityCommandControlSnapshot
    ) -> [AccessibilityBehaviorObservation] {
        var requirements: [(AccessibilityEvidenceRequirementKey, AccessibilityEvidenceValue, AccessibilityCommandControlSnapshot?)] = []
        let scenarioID = scenario.id
        requirements.append((key(scenarioID, .semanticSnapshot), .snapshot(scenario.expectedSnapshot.id), nil))
        requirements.append((key(scenarioID, .focusOrder), .focusOrder(scenario.expectedSnapshot.focusOrder), nil))
        for element in scenario.expectedSnapshot.elements.sorted(by: { $0.id < $1.id }) {
            let subject = element.id
            requirements += [
                (key(scenarioID, .semanticRole, subject), .semanticRole(element.role), nil),
                (key(scenarioID, .semanticLabel, subject), .semanticLabel(element.label), nil),
                (key(scenarioID, .semanticHierarchy, subject), .parentID(element.parentID), nil),
                (key(scenarioID, .hiddenState, subject), .hidden(element.isHiddenFromAssistiveTechnology), nil),
                (key(scenarioID, .focusability, subject), .focusable(element.isKeyboardFocusable), nil),
                (key(scenarioID, .keyboardShortcuts, subject), .keyboardShortcuts(element.keyboardShortcuts.map(\.id).sorted()), nil),
                (key(scenarioID, .enabledState, subject), .enabled(element.isEnabled), nil),
                (key(scenarioID, .checkedState, subject), .checked(element.checkedState), nil),
                (key(scenarioID, .selectedState, subject), .selected(element.selectedState), nil),
                (key(scenarioID, .value, subject), .value(element.value), nil),
                (key(scenarioID, .hint, subject), .hint(element.hint), nil)
            ]
            for action in element.actions.sorted(by: { $0.id < $1.id }) {
                let value = AccessibilityEvidenceValue.action(
                    actionID: action.id,
                    kind: action.kind,
                    outcome: element.isEnabled ? .performed : .blocked
                )
                let postcondition = element.isEnabled ? scenario.expectedSnapshot : nil
                requirements.append((key(scenarioID, .actionBehavior, subject, action.id), value, postcondition))
                if scenario.requiredEnvironmentChecks.contains(.fullKeyboardAccess) {
                    requirements.append((key(scenarioID, .fullKeyboardAccess, subject, action.id), value, postcondition))
                }
                if scenario.requiredEnvironmentChecks.contains(.voiceOverActivation) {
                    requirements.append((key(scenarioID, .voiceOverActivation, subject, action.id), value, postcondition))
                }
            }
            appendScopedRequirements(element, scenario: scenario, to: &requirements)
        }
        if scenario.requiredEnvironmentChecks.contains(.localizationExpansion) {
            for announcement in scenario.expectedSnapshot.announcements {
                for token in announcement.localizationExpansionEvidenceTokens {
                    requirements.append((key(scenarioID, .localizationExpansion, announcement.id, id(token.rawValue)), .condition(.satisfied), nil))
                }
            }
        }
        for announcement in scenario.expectedSnapshot.announcements.sorted(by: { $0.id < $1.id }) {
            requirements.append(
                (
                    key(scenarioID, .announcementBehavior, announcement.relatedElementID, announcement.id),
                    .announcement(announcementID: announcement.id, kind: announcement.kind, outcome: .delivered),
                    nil
                ))
        }
        return requirements.enumerated().map { index, item in
            let observationID = id("observation-\(scenarioID.rawValue)-\(index)")
            return AccessibilityBehaviorObservation(
                id: observationID,
                requirement: item.0,
                snapshotID: snapshot.id,
                value: item.1,
                origin: .automatedMeasurement,
                source: "production-collector",
                attachmentTokens: [id("attachment-\(scenarioID.rawValue)-\(index)")],
                postconditionSnapshot: item.2
            )
        }
    }

    private func appendScopedRequirements(
        _ element: AccessibilitySemanticElement,
        scenario: AccessibilityEvidenceInventoryScenario,
        to requirements: inout [(AccessibilityEvidenceRequirementKey, AccessibilityEvidenceValue, AccessibilityCommandControlSnapshot?)]
    ) {
        let scenarioID = scenario.id
        if scenario.requiredEnvironmentChecks.contains(.increasedContrast) {
            appendTokenRequirements(
                element.contrastEvidenceTokens.map(\.rawValue), kind: .increasedContrast, element: element, scenarioID: scenarioID, empty: .notApplicable,
                to: &requirements)
        }
        if scenario.requiredEnvironmentChecks.contains(.differentiateWithoutColor) {
            appendTokenRequirements(
                element.differentiateWithoutColorEvidenceTokens.map(\.rawValue), kind: .differentiateWithoutColor, element: element, scenarioID: scenarioID,
                empty: .notApplicable, to: &requirements)
        }
        if scenario.requiredEnvironmentChecks.contains(.darkMode) {
            appendTokenRequirements(
                element.contrastEvidenceTokens.map(\.rawValue), kind: .darkMode, element: element, scenarioID: scenarioID, empty: .notSatisfied,
                to: &requirements)
        }
        if scenario.requiredEnvironmentChecks.contains(.fullKeyboardAccess) {
            if element.actions.isEmpty {
                requirements.append((key(scenarioID, .fullKeyboardAccess, element.id), .condition(.notApplicable), nil))
            } else if element.keyboardShortcuts.isEmpty {
                requirements.append((key(scenarioID, .fullKeyboardAccess, element.id), .condition(.notSatisfied), nil))
            }
        }
        if scenario.requiredEnvironmentChecks.contains(.voiceOverActivation) {
            requirements.append((key(scenarioID, .voiceOverActivation, element.id), .condition(element.actions.isEmpty ? .notApplicable : .satisfied), nil))
        }
        if scenario.requiredEnvironmentChecks.contains(.localizationExpansion) {
            appendTokenRequirements(
                element.localizationExpansionEvidenceTokens.map(\.rawValue), kind: .localizationExpansion, element: element, scenarioID: scenarioID,
                empty: .notSatisfied, to: &requirements)
            for action in element.actions {
                for token in action.localizationExpansionEvidenceTokens {
                    requirements.append((key(scenarioID, .localizationExpansion, action.id, id(token.rawValue)), .condition(.satisfied), nil))
                }
            }
            for shortcut in element.keyboardShortcuts {
                for token in shortcut.localizationExpansionEvidenceTokens {
                    requirements.append((key(scenarioID, .localizationExpansion, shortcut.id, id(token.rawValue)), .condition(.satisfied), nil))
                }
            }
        }
    }

    private func appendTokenRequirements<Token>(
        _ tokens: [Token],
        kind: AccessibilityEvidenceRequirementKind,
        element: AccessibilitySemanticElement,
        scenarioID: AccessibilityStableID,
        empty: AccessibilityEvidenceConditionOutcome,
        to requirements: inout [(AccessibilityEvidenceRequirementKey, AccessibilityEvidenceValue, AccessibilityCommandControlSnapshot?)]
    ) where Token: StringProtocol {
        if tokens.isEmpty {
            requirements.append((key(scenarioID, kind, element.id), .condition(empty), nil))
        } else {
            for token in tokens {
                requirements.append((key(scenarioID, kind, element.id, id(String(token))), .condition(.satisfied), nil))
            }
        }
    }

    private func bindAttachments(
        inventory: AccessibilityProductionControlInventory,
        evidence: AccessibilityEvidenceBundle
    ) throws -> Fixture {
        var dataByID: [AccessibilityStableID: Data] = [:]
        var attachmentsByID: [AccessibilityStableID: AccessibilityEvidenceAttachment] = [:]
        for scenario in evidence.scenarios {
            for observation in scenario.observations {
                let data = try AccessibilityEvidenceWorkflow.canonicalAttachmentData(for: observation, capturedIn: scenario)
                for token in observation.attachmentTokens {
                    dataByID[token] = data
                    attachmentsByID[token] = AccessibilityEvidenceAttachment(
                        id: token,
                        kind: .measurementRecord,
                        mediaType: "application/vnd.macmerge.accessibility-observation",
                        byteCount: data.count,
                        sha256: sha256(data),
                        source: "production-collector"
                    )
                }
            }
        }
        let bound = AccessibilityEvidenceBundle(
            reference: evidence.reference,
            app: evidence.app,
            build: evidence.build,
            buildBinding: evidence.buildBinding,
            inventory: evidence.inventory,
            scenarios: evidence.scenarios,
            attachments: Array(attachmentsByID.values)
        )
        return Fixture(inventory: inventory, evidence: bound, attachmentData: dataByID)
    }

    private func mapObservations(
        _ fixture: Fixture,
        transform: (AccessibilityBehaviorObservation) -> AccessibilityBehaviorObservation
    ) throws -> Fixture {
        try mapScenarios(fixture) { scenario in
            AccessibilityScenarioEvidence(
                scenario: scenario.scenario,
                environment: scenario.environment,
                provenance: scenario.provenance,
                snapshot: scenario.snapshot,
                observations: scenario.observations.map(transform)
            )
        }
    }

    private func mapScenarios(
        _ fixture: Fixture,
        transform: (AccessibilityScenarioEvidence) -> AccessibilityScenarioEvidence
    ) throws -> Fixture {
        let bundle = AccessibilityEvidenceBundle(
            reference: fixture.evidence.reference,
            app: fixture.evidence.app,
            build: fixture.evidence.build,
            buildBinding: fixture.evidence.buildBinding,
            inventory: fixture.evidence.inventory,
            scenarios: fixture.evidence.scenarios.map(transform)
        )
        return try bindAttachments(inventory: fixture.inventory, evidence: bundle)
    }

    private func replacingSnapshot(
        _ fixture: Fixture,
        scenarioID: AccessibilityStableID,
        mutation: (AccessibilityCommandControlSnapshot) -> AccessibilityCommandControlSnapshot
    ) throws -> Fixture {
        try mapScenarios(fixture) { scenario in
            guard scenario.id == scenarioID else { return scenario }
            return AccessibilityScenarioEvidence(
                scenario: scenario.scenario,
                environment: scenario.environment,
                provenance: scenario.provenance,
                snapshot: mutation(scenario.snapshot),
                observations: scenario.observations.map { observation in
                    AccessibilityBehaviorObservation(
                        id: observation.id,
                        requirement: observation.requirement,
                        snapshotID: mutation(scenario.snapshot).id,
                        value: observation.value,
                        origin: observation.origin,
                        source: observation.source,
                        attachmentTokens: observation.attachmentTokens,
                        postconditionSnapshot: observation.postconditionSnapshot
                    )
                }
            )
        }
    }

    private func replacingAllSnapshots(
        _ fixture: Fixture,
        inventory: AccessibilityProductionControlInventory,
        mutation: (AccessibilityCommandControlSnapshot) -> AccessibilityCommandControlSnapshot
    ) throws -> Fixture {
        let scenarios = fixture.evidence.scenarios.map { scenario in
            let snapshot = mutation(scenario.snapshot)
            return AccessibilityScenarioEvidence(
                scenario: scenario.scenario,
                environment: scenario.environment,
                provenance: scenario.provenance,
                snapshot: snapshot,
                observations: scenario.observations.map { observation in
                    let expectedScenario = inventory.scenarios.first { $0.id == scenario.id }!
                    let expected = expectedObservations(expectedScenario, snapshot: snapshot)
                    return expected.first { $0.requirement == observation.requirement }!
                }
            )
        }
        let evidence = AccessibilityEvidenceBundle(
            reference: fixture.evidence.reference,
            app: fixture.evidence.app,
            build: fixture.evidence.build,
            buildBinding: fixture.evidence.buildBinding,
            inventory: fixture.evidence.inventory,
            scenarios: scenarios
        )
        return try bindAttachments(inventory: inventory, evidence: evidence)
    }

    private func replacingInventorySnapshots(
        _ inventory: AccessibilityProductionControlInventory,
        mutation: (AccessibilityCommandControlSnapshot) -> AccessibilityCommandControlSnapshot
    ) throws -> AccessibilityProductionControlInventory {
        try AccessibilityProductionControlInventory(
            app: inventory.app,
            build: inventory.build,
            buildBinding: inventory.buildBinding,
            reference: inventory.reference,
            controls: inventory.controls,
            scenarios: inventory.scenarios.map { scenario in
                let snapshot = mutation(scenario.expectedSnapshot)
                return AccessibilityEvidenceInventoryScenario(
                    reference: scenario.reference,
                    environment: scenario.environment,
                    expectedSnapshot: snapshot,
                    requiredEnvironmentChecks: scenario.requiredEnvironmentChecks,
                    actionPostconditions: [
                        AccessibilityEvidenceActionPostcondition(
                            actionID: id("save-action"),
                            snapshotSHA256: sha256(try AccessibilityAudit.exactSnapshotData(of: snapshot))
                        )
                    ]
                )
            }
        )
    }

    private func replacingEnvironment(
        _ fixture: Fixture,
        scenarioID: AccessibilityStableID,
        with environment: AccessibilityEvidenceEnvironment
    ) throws -> Fixture {
        try mapScenarios(fixture) { scenario in
            guard scenario.id == scenarioID else { return scenario }
            return AccessibilityScenarioEvidence(
                scenario: scenario.scenario,
                environment: environment,
                provenance: scenario.provenance,
                snapshot: scenario.snapshot,
                observations: scenario.observations
            )
        }
    }

    private func replacingProvenance(
        _ fixture: Fixture,
        mutation: (AccessibilityEvidenceCaptureProvenance) -> AccessibilityEvidenceCaptureProvenance
    ) -> Fixture {
        let scenarios = fixture.evidence.scenarios.map { scenario in
            AccessibilityScenarioEvidence(
                scenario: scenario.scenario,
                environment: scenario.environment,
                provenance: mutation(scenario.provenance),
                snapshot: scenario.snapshot,
                observations: scenario.observations
            )
        }
        let bundle = AccessibilityEvidenceBundle(
            reference: fixture.evidence.reference,
            app: fixture.evidence.app,
            build: fixture.evidence.build,
            buildBinding: fixture.evidence.buildBinding,
            inventory: fixture.evidence.inventory,
            scenarios: scenarios,
            attachments: fixture.evidence.attachments
        )
        return Fixture(inventory: fixture.inventory, evidence: bundle, attachmentData: fixture.attachmentData)
    }

    private func replacingScenarioReference(
        _ fixture: Fixture,
        scenarioID: AccessibilityStableID,
        with reference: AccessibilityEvidenceRevisionReference
    ) -> Fixture {
        let scenarios = fixture.evidence.scenarios.map { scenario in
            guard scenario.id == scenarioID else { return scenario }
            return AccessibilityScenarioEvidence(
                scenario: reference,
                environment: scenario.environment,
                provenance: scenario.provenance,
                snapshot: scenario.snapshot,
                observations: scenario.observations
            )
        }
        let bundle = AccessibilityEvidenceBundle(
            reference: fixture.evidence.reference,
            app: fixture.evidence.app,
            build: fixture.evidence.build,
            buildBinding: fixture.evidence.buildBinding,
            inventory: fixture.evidence.inventory,
            scenarios: scenarios,
            attachments: fixture.evidence.attachments
        )
        return Fixture(inventory: fixture.inventory, evidence: bundle, attachmentData: fixture.attachmentData)
    }

    private func replacingBundle(
        _ fixture: Fixture,
        reference: AccessibilityEvidenceRevisionReference? = nil,
        app: AccessibilityEvidenceRevisionReference? = nil,
        build: AccessibilityEvidenceRevisionReference? = nil,
        buildBinding: AccessibilityEvidenceBuildBinding? = nil,
        inventory: AccessibilityEvidenceRevisionReference? = nil
    ) -> Fixture {
        let bundle = AccessibilityEvidenceBundle(
            reference: reference ?? fixture.evidence.reference,
            app: app ?? fixture.evidence.app,
            build: build ?? fixture.evidence.build,
            buildBinding: buildBinding ?? fixture.evidence.buildBinding,
            inventory: inventory ?? fixture.evidence.inventory,
            scenarios: fixture.evidence.scenarios,
            attachments: fixture.evidence.attachments
        )
        return Fixture(inventory: fixture.inventory, evidence: bundle, attachmentData: fixture.attachmentData)
    }

    private func evaluate(
        _ fixture: Fixture,
        limits: AccessibilityEvidenceWorkflowLimits = .default
    ) throws -> AccessibilityEvidenceWorkflowResult {
        try AccessibilityEvidenceWorkflow.evaluate(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            limits: limits,
            attachmentResolver: fixture.resolver,
            cancellationCheck: { false }
        )
    }

    private func validate(_ archive: Data, _ fixture: Fixture) throws {
        try AccessibilityEvidenceWorkflow.validate(
            archive: archive,
            for: fixture.evidence,
            boundTo: fixture.inventory,
            attachmentResolver: fixture.resolver,
            cancellationCheck: { false }
        )
    }

    private func assertWorkflowError<T>(
        _ expected: AccessibilityEvidenceWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? AccessibilityEvidenceWorkflowError, expected, file: file, line: line)
        }
    }

    private func snapshot(_ suffix: String, label: String) -> AccessibilityCommandControlSnapshot {
        let saveAction = AccessibilitySemanticAction(
            id: id("save-action"),
            kind: .activate,
            label: "Activate",
            localizationExpansionEvidenceTokens: [localizationToken("action-localization")]
        )
        let saveShortcut = AccessibilityKeyboardShortcut(
            id: id("save-shortcut"),
            key: "s",
            modifiers: [.command],
            actionID: saveAction.id,
            discoverabilityTitle: "Save item",
            localizationExpansionEvidenceTokens: [localizationToken("shortcut-localization")]
        )
        let root = AccessibilitySemanticElement(id: id("root"), role: .staticText, label: "Application")
        let save = AccessibilitySemanticElement(
            id: id("save-control"),
            parentID: root.id,
            role: .button,
            label: label,
            hint: "Stores changes",
            isKeyboardFocusable: true,
            actions: [saveAction],
            keyboardShortcuts: [saveShortcut],
            requiresContrastEvidence: true,
            contrastEvidenceTokens: [contrastToken("save-contrast")],
            usesColorToConveyMeaning: true,
            differentiateWithoutColorEvidenceTokens: [nonColorToken("save-noncolor")],
            requiresLocalizationExpansionEvidence: true,
            localizationExpansionEvidenceTokens: [
                localizationToken("save-localization"), localizationToken("hint-localization")
            ]
        )
        let announcement = AccessibilityAnnouncement(
            id: id("save-announcement"),
            kind: .confirmation,
            message: "Saved",
            relatedElementID: save.id,
            triggerActionID: saveAction.id,
            localizationExpansionEvidenceTokens: [localizationToken("announcement-localization")]
        )
        let localization: [(String, AccessibilityStableID, AccessibilityLocalizedField, String)] = [
            ("save-localization", save.id, .label, label),
            ("hint-localization", save.id, .hint, "Stores changes"),
            ("action-localization", saveAction.id, .actionLabel, "Activate"),
            ("shortcut-localization", saveShortcut.id, .shortcutTitle, "Save item"),
            ("announcement-localization", announcement.id, .announcement, "Saved")
        ]
        return AccessibilityCommandControlSnapshot(
            id: id("snapshot-\(suffix)"),
            rootElementID: root.id,
            elements: [root, save],
            focusOrder: [save.id],
            announcements: [announcement],
            evidence: AccessibilityAuditEvidence(
                contrast: [
                    AccessibilityContrastEvidence(
                        token: contrastToken("save-contrast"),
                        subjectID: save.id,
                        surface: .graphicalObject,
                        measuredRatioThousandths: 4_500,
                        requiredRatioThousandths: 3_000,
                        origin: .automatedMeasurement,
                        source: "contrast-meter"
                    )
                ],
                differentiateWithoutColor: [
                    AccessibilityDifferentiateWithoutColorEvidence(
                        token: nonColorToken("save-noncolor"),
                        meaning: "Save state",
                        nonColorCues: [.icon, .text],
                        origin: .manualMeasurement,
                        source: "visual-review"
                    )
                ],
                localizationExpansion: localization.map { token, subject, field, baseline in
                    AccessibilityLocalizationExpansionEvidence(
                        token: localizationToken(token),
                        subjectID: subject,
                        field: field,
                        localeIdentifier: "de-DE",
                        baselineText: baseline,
                        expandedText: baseline + " " + baseline + " expanded",
                        outcome: .wraps,
                        origin: .automatedMeasurement,
                        source: "localization-runner"
                    )
                }
            )
        )
    }

    private func environment(_ appearance: AccessibilityEvidenceAppearance) -> AccessibilityEvidenceEnvironment {
        AccessibilityEvidenceEnvironment(
            fullKeyboardAccessEnabled: true,
            voiceOverEnabled: true,
            increasedContrastEnabled: true,
            differentiateWithoutColorEnabled: true,
            appearance: appearance,
            localeIdentifier: "de-DE",
            localizationExpansionThousandths: 2_000
        )
    }

    private func provenance(
        _ fixture: Fixture,
        timestamp: UInt64 = 1_800_000_000_000,
        nonce: [UInt8] = [UInt8](repeating: 1, count: 16)
    ) -> AccessibilityEvidenceCaptureProvenance {
        AccessibilityEvidenceCaptureProvenance(
            capturedAtUnixMilliseconds: timestamp,
            runNonce: nonce,
            collector: reference("accessibility-collector", 5),
            build: fixture.inventory.build,
            buildBinding: fixture.inventory.buildBinding
        )
    }

    private func key(
        _ scenarioID: AccessibilityStableID,
        _ kind: AccessibilityEvidenceRequirementKind,
        _ subjectID: AccessibilityStableID? = nil,
        _ discriminator: AccessibilityStableID? = nil
    ) -> AccessibilityEvidenceRequirementKey {
        AccessibilityEvidenceRequirementKey(
            scenarioID: scenarioID,
            subjectID: subjectID,
            kind: kind,
            discriminator: discriminator
        )
    }

    private func replacingElement(
        _ snapshot: AccessibilityCommandControlSnapshot,
        elementID: AccessibilityStableID,
        mutation: (AccessibilitySemanticElement) -> AccessibilitySemanticElement
    ) -> AccessibilityCommandControlSnapshot {
        snapshotWith(snapshot, elements: snapshot.elements.map { $0.id == elementID ? mutation($0) : $0 })
    }

    private func relabelSnapshot(
        _ snapshot: AccessibilityCommandControlSnapshot,
        label: String
    ) -> AccessibilityCommandControlSnapshot {
        let elements = snapshot.elements.map { element in
            element.id == id("save-control") ? elementWith(element, label: label) : element
        }
        let localization = snapshot.evidence.localizationExpansion.map { evidence in
            guard evidence.token == localizationToken("save-localization") else { return evidence }
            return AccessibilityLocalizationExpansionEvidence(
                token: evidence.token,
                subjectID: evidence.subjectID,
                field: evidence.field,
                localeIdentifier: evidence.localeIdentifier,
                baselineText: label,
                expandedText: label + " " + label + " expanded",
                outcome: evidence.outcome,
                origin: evidence.origin,
                source: evidence.source
            )
        }
        return snapshotWith(
            snapshot,
            elements: elements,
            evidence: AccessibilityAuditEvidence(
                contrast: snapshot.evidence.contrast,
                differentiateWithoutColor: snapshot.evidence.differentiateWithoutColor,
                localizationExpansion: localization
            )
        )
    }

    private func snapshotWith(
        _ snapshot: AccessibilityCommandControlSnapshot,
        id: AccessibilityStableID? = nil,
        elements: [AccessibilitySemanticElement]? = nil,
        focusOrder: [AccessibilityStableID]? = nil,
        announcements: [AccessibilityAnnouncement]? = nil,
        evidence: AccessibilityAuditEvidence? = nil
    ) -> AccessibilityCommandControlSnapshot {
        AccessibilityCommandControlSnapshot(
            id: id ?? snapshot.id,
            rootElementID: snapshot.rootElementID,
            elements: elements ?? snapshot.elements,
            focusOrder: focusOrder ?? snapshot.focusOrder,
            announcements: announcements ?? snapshot.announcements,
            evidence: evidence ?? snapshot.evidence
        )
    }

    private func elementWith(
        _ element: AccessibilitySemanticElement,
        parentID: AccessibilityStableID?? = nil,
        role: AccessibilitySemanticRole? = nil,
        label: String? = nil,
        value: String? = nil,
        hint: String? = nil,
        enabled: Bool? = nil,
        checked: AccessibilityCheckedState? = nil,
        selected: AccessibilitySelectedState? = nil,
        hidden: Bool? = nil,
        focusable: Bool? = nil,
        actions: [AccessibilitySemanticAction]? = nil,
        shortcuts: [AccessibilityKeyboardShortcut]? = nil
    ) -> AccessibilitySemanticElement {
        AccessibilitySemanticElement(
            id: element.id,
            parentID: parentID ?? element.parentID,
            role: role ?? element.role,
            label: label ?? element.label,
            value: value ?? element.value,
            hint: hint ?? element.hint,
            isEnabled: enabled ?? element.isEnabled,
            checkedState: checked ?? element.checkedState,
            selectedState: selected ?? element.selectedState,
            isHiddenFromAssistiveTechnology: hidden ?? element.isHiddenFromAssistiveTechnology,
            isKeyboardFocusable: focusable ?? element.isKeyboardFocusable,
            actions: actions ?? element.actions,
            keyboardShortcuts: shortcuts ?? element.keyboardShortcuts,
            requiresContrastEvidence: element.requiresContrastEvidence,
            contrastEvidenceTokens: element.contrastEvidenceTokens,
            usesColorToConveyMeaning: element.usesColorToConveyMeaning,
            differentiateWithoutColorEvidenceTokens: element.differentiateWithoutColorEvidenceTokens,
            requiresLocalizationExpansionEvidence: element.requiresLocalizationExpansionEvidence,
            localizationExpansionEvidenceTokens: element.localizationExpansionEvidenceTokens
        )
    }

    private func emptySnapshot(_ name: String) -> AccessibilityCommandControlSnapshot {
        let root = AccessibilitySemanticElement(id: id("\(name)-root"), role: .staticText, label: "Root")
        return AccessibilityCommandControlSnapshot(id: id(name), rootElementID: root.id, elements: [root])
    }

    private func action(
        _ identifier: String,
        _ kind: AccessibilitySemanticActionKind,
        label: String? = nil
    ) -> AccessibilitySemanticAction {
        AccessibilitySemanticAction(id: id(identifier), kind: kind, label: label)
    }

    private func shortcut(
        _ identifier: String,
        actionID: String,
        key: String
    ) -> AccessibilityKeyboardShortcut {
        AccessibilityKeyboardShortcut(id: id(identifier), key: key, modifiers: [.command], actionID: id(actionID))
    }

    private func id(_ value: String) -> AccessibilityStableID {
        AccessibilityStableID(rawValue: value)
    }

    private func reference(_ value: String, _ revision: UInt64) -> AccessibilityEvidenceRevisionReference {
        AccessibilityEvidenceRevisionReference(id: id(value), revision: AccessibilityEvidenceRevision(rawValue: revision))
    }

    private func binding(artifact: UInt8, signing: UInt8) -> AccessibilityEvidenceBuildBinding {
        AccessibilityEvidenceBuildBinding(artifactSHA256: digest(artifact), signingIdentitySHA256: digest(signing))
    }

    private func digest(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: SHA256.byteCount)
    }

    private func sha256(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func contrastToken(_ value: String) -> AccessibilityContrastEvidenceToken {
        AccessibilityContrastEvidenceToken(rawValue: value)
    }

    private func nonColorToken(_ value: String) -> AccessibilityDifferentiateWithoutColorEvidenceToken {
        AccessibilityDifferentiateWithoutColorEvidenceToken(rawValue: value)
    }

    private func localizationToken(_ value: String) -> AccessibilityLocalizationExpansionEvidenceToken {
        AccessibilityLocalizationExpansionEvidenceToken(rawValue: value)
    }

    private func limits(
        maximumControls: Int = 20_000,
        maximumScenarios: Int = 1_024,
        maximumElements: Int = 100_000,
        maximumObservations: Int = 1_000_000,
        maximumRequiredRequirements: Int = 1_000_000,
        maximumAttachments: Int = 100_000,
        maximumAttachmentTokens: Int = 1_000_000,
        maximumAttachmentTokensPerObservation: Int = 64,
        maximumTotalItems: Int = 2_000_000,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 32 * 1_024 * 1_024,
        maximumAttachmentBytes: Int = 256 * 1_024 * 1_024,
        maximumTotalAttachmentBytes: UInt64 = 1 << 32,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        maximumFindings: Int = 200_000,
        maximumArchiveBytes: Int = 128 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 256
    ) -> AccessibilityEvidenceWorkflowLimits {
        AccessibilityEvidenceWorkflowLimits(
            maximumControls: maximumControls,
            maximumScenarios: maximumScenarios,
            maximumElements: maximumElements,
            maximumObservations: maximumObservations,
            maximumRequiredRequirements: maximumRequiredRequirements,
            maximumAttachments: maximumAttachments,
            maximumAttachmentTokens: maximumAttachmentTokens,
            maximumAttachmentTokensPerObservation: maximumAttachmentTokensPerObservation,
            maximumTotalItems: maximumTotalItems,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumAttachmentBytes: maximumAttachmentBytes,
            maximumTotalAttachmentBytes: maximumTotalAttachmentBytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumFindings: maximumFindings,
            maximumArchiveBytes: maximumArchiveBytes,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func hardLimits() -> AccessibilityEvidenceWorkflowLimits {
        AccessibilityEvidenceWorkflowLimits(
            maximumControls: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumScenarios: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumElements: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumObservations: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumRequiredRequirements: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumAttachments: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumAttachmentTokens: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumAttachmentTokensPerObservation: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumTotalItems: AccessibilityEvidenceWorkflowLimits.hardMaximumTotalItems,
            maximumStringUTF8Bytes: AccessibilityEvidenceWorkflowLimits.hardMaximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: AccessibilityEvidenceWorkflowLimits.hardMaximumTotalStringUTF8Bytes,
            maximumAttachmentBytes: AccessibilityEvidenceWorkflowLimits.hardMaximumAttachmentBytes,
            maximumTotalAttachmentBytes: AccessibilityEvidenceWorkflowLimits.hardMaximumTotalAttachmentBytes,
            maximumWorkUnits: AccessibilityEvidenceWorkflowLimits.hardMaximumWorkUnits,
            maximumFindings: AccessibilityEvidenceWorkflowLimits.hardMaximumCount,
            maximumArchiveBytes: AccessibilityEvidenceWorkflowLimits.hardMaximumArchiveBytes,
            cancellationCheckInterval: AccessibilityEvidenceWorkflowLimits.hardMaximumCancellationCheckInterval
        )
    }
}
