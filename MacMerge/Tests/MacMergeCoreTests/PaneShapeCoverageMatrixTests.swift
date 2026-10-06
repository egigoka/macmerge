import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class PaneShapeCoverageMatrixTests: XCTestCase {
    func testCanonicalScenarioInventoryAndMappingAreExact() throws {
        let scenarios = PaneShapeCoverageMatrix.canonicalScenarios
        let actual = scenarios.map {
            "\($0.id.rawValue):\($0.paneCount.rawValue):\(paneName($0.activePane)):\($0.isSwapped):\(orientationName($0.orientation))"
        }

        XCTAssertEqual(PaneShapeCoverageMatrix.reportFormatVersion, 5)
        XCTAssertEqual(PaneShapeCoverageMatrix.canonicalMatrixRevision, 1)
        XCTAssertEqual(
            actual,
            [
                "0:2:left:false:vertical",
                "1:2:left:false:horizontal",
                "2:2:left:true:vertical",
                "3:2:left:true:horizontal",
                "4:2:right:false:vertical",
                "5:2:right:false:horizontal",
                "6:2:right:true:vertical",
                "7:2:right:true:horizontal",
                "8:3:left:false:vertical",
                "9:3:left:false:horizontal",
                "10:3:left:true:vertical",
                "11:3:left:true:horizontal",
                "12:3:middle:false:vertical",
                "13:3:middle:false:horizontal",
                "14:3:middle:true:vertical",
                "15:3:middle:true:horizontal",
                "16:3:right:false:vertical",
                "17:3:right:false:horizontal",
                "18:3:right:true:vertical",
                "19:3:right:true:horizontal"
            ]
        )
        XCTAssertEqual(scenarios.map(\.id.rawValue), Array(0...19))

        for scenario in scenarios {
            let expectedOrder = scenario.isSwapped ? Array(scenario.paneCount.identities.reversed()) : scenario.paneCount.identities
            XCTAssertEqual(scenario.expectedVisualOrder, expectedOrder)
            XCTAssertEqual(scenario.logicalPane(atVisualIndex: scenario.activeVisualIndex), scenario.activePane)
            XCTAssertEqual(scenario.visualIndex(of: scenario.activePane), scenario.activeVisualIndex)
            XCTAssertNil(scenario.logicalPane(atVisualIndex: -1))
            XCTAssertNil(scenario.logicalPane(atVisualIndex: scenario.expectedVisualOrder.count))
        }

        var bindings = try makeBindingsByScenario()
        let signingKey = Curve25519.Signing.PrivateKey()
        let inventory = try PaneShapeCoverageInventory.canonical(
            reference: reference("inventory", 1),
            build: reference("build", 1),
            buildArtifactSHA256: digest("artifact"),
            trustedCollectors: [collector(signingKey)],
            bindingsByScenario: bindings
        )
        XCTAssertEqual(inventory.requirements.map(\.id), scenarios.map(\.id))

        bindings.removeValue(forKey: scenarios[0].id)
        assertError(.invalidInventory(field: "requirements")) {
            _ = try PaneShapeCoverageInventory.canonical(
                reference: reference("inventory", 1),
                build: reference("build", 1),
                buildArtifactSHA256: digest("artifact"),
                trustedCollectors: [collector(signingKey)],
                bindingsByScenario: bindings
            )
        }

        bindings = try makeBindingsByScenario()
        bindings[PaneShapeScenarioID(rawValue: 999)] = bindings[scenarios[0].id]
        assertError(.invalidInventory(field: "requirements")) {
            _ = try PaneShapeCoverageInventory.canonical(
                reference: reference("inventory", 1),
                build: reference("build", 1),
                buildArtifactSHA256: digest("artifact"),
                trustedCollectors: [collector(signingKey)],
                bindingsByScenario: bindings
            )
        }
    }

    func testScenarioAndObservationRejectImpossibleMalformedShapes() throws {
        assertError(.impossibleScenario) {
            _ = try PaneShapeScenario(paneCount: .two, activePane: .middle, isSwapped: false, orientation: .vertical)
        }
        assertError(.invalidObservation(field: "layout")) {
            _ = try PaneShapeLayoutObservation(
                paneCount: .two,
                visualOrder: [.left, .middle],
                activePane: .left,
                orientation: .vertical
            )
        }
        assertError(.invalidObservation(field: "layout")) {
            _ = try PaneShapeLayoutObservation(
                paneCount: .three,
                visualOrder: [.left, .left, .right],
                activePane: .left,
                orientation: .horizontal
            )
        }
        assertError(.invalidObservation(field: "layout")) {
            _ = try PaneShapeLayoutObservation(
                paneCount: .two,
                visualOrder: [.left, .right],
                activePane: .middle,
                orientation: .vertical
            )
        }
        assertError(.invalidObservation(field: "commandState")) {
            _ = try PaneShapeCommandStateObservation(visualOrder: [.left], activePane: .left)
        }
        assertError(.invalidObservation(field: "commandState")) {
            _ = try PaneShapeCommandStateObservation(visualOrder: [.left, .middle], activePane: .middle)
        }
        assertError(.invalidObservation(field: "commandState")) {
            _ = try PaneShapeCommandStateObservation(visualOrder: [.left, .right], activePane: .middle)
        }

        let duplicateSources = [
            PaneShapeSourceRevisionBinding(pane: .left, source: reference("left", 1)),
            PaneShapeSourceRevisionBinding(pane: .left, source: reference("other-left", 1))
        ]
        assertError(.inconsistentRevisionBindings) {
            _ = try PaneShapeComparisonRevisionBinding(
                comparison: reference("comparison", 1),
                inputs: reference("inputs", 1),
                result: reference("result", 1),
                sources: duplicateSources
            )
        }

        let scenario = try XCTUnwrap(PaneShapeCoverageMatrix.canonicalScenarios.first)
        let bindings = try makeBindings(for: scenario)
        let inconsistentSources = [
            PaneShapeSourceRevisionBinding(pane: .left, source: reference("changed-left", 1)),
            PaneShapeSourceRevisionBinding(pane: .right, source: bindings.sources[1].source)
        ]
        assertError(.inconsistentRevisionBindings) {
            _ = try PaneShapeRevisionBindings(
                layout: bindings.layout,
                sources: inconsistentSources,
                comparison: bindings.comparison
            )
        }
    }

    func testCanonicalInventoryAndEvidenceRequireExactRevisionContents() throws {
        let fixture = try makeFixture()
        var requirements = fixture.inventory.requirements
        let first = requirements[0]
        let second = requirements[1]
        let conflictingBindings = try replacingLayoutReference(second.bindings, with: first.bindings.layout)
        requirements[1] = PaneShapeCoverageRequirement(scenario: second.scenario, bindings: conflictingBindings)
        let conflictingInventory = replacingInventory(fixture.inventory, requirements: requirements)

        assertError(.invalidInventory(field: "revisionContents")) {
            _ = try audit(fixture, inventory: conflictingInventory, claims: ClaimRecorder())
        }

        var observations = fixture.evidence.observations
        let conflictingEvidenceBindings = try replacingLayoutReference(observations[1].bindings, with: observations[0].bindings.layout)
        observations[1] = replacingObservation(observations[1], bindings: conflictingEvidenceBindings)
        let conflictingEvidence = replacingEvidence(fixture.evidence, observations: observations)
        assertError(.invalidEvidence(field: "revisionContents")) {
            _ = try audit(fixture, evidence: conflictingEvidence, claims: ClaimRecorder())
        }

        func replacingComparison(
            comparison: PaneShapeRevisionReference? = nil,
            inputs: PaneShapeRevisionReference? = nil,
            result: PaneShapeRevisionReference? = nil,
            sources: [PaneShapeSourceRevisionBinding]? = nil
        ) throws -> PaneShapeRevisionBindings {
            let sources = sources ?? second.bindings.sources
            let comparison = try PaneShapeComparisonRevisionBinding(
                comparison: comparison ?? second.bindings.comparison.comparison,
                inputs: inputs ?? second.bindings.comparison.inputs,
                result: result ?? second.bindings.comparison.result,
                sources: sources
            )
            return try PaneShapeRevisionBindings(
                layout: second.bindings.layout,
                sources: sources,
                comparison: comparison
            )
        }

        var sourceCollision = second.bindings.sources
        sourceCollision[1] = PaneShapeSourceRevisionBinding(
            pane: sourceCollision[1].pane,
            source: first.bindings.sources[0].source
        )
        let sameRoleCollisions = try [
            replacingComparison(comparison: first.bindings.comparison.comparison),
            replacingComparison(inputs: first.bindings.comparison.inputs),
            replacingComparison(result: first.bindings.comparison.result),
            replacingComparison(sources: sourceCollision)
        ]
        let crossRoleCollisions = try [
            replacingLayoutReference(second.bindings, with: first.bindings.comparison.comparison),
            replacingComparison(comparison: first.bindings.layout),
            replacingComparison(inputs: first.bindings.layout),
            replacingComparison(result: first.bindings.layout),
            replacingComparison(
                sources: second.bindings.sources.map {
                    PaneShapeSourceRevisionBinding(pane: $0.pane, source: first.bindings.layout)
                }
            )
        ]
        for collision in sameRoleCollisions + crossRoleCollisions {
            requirements = fixture.inventory.requirements
            requirements[1] = PaneShapeCoverageRequirement(scenario: second.scenario, bindings: collision)
            assertError(.invalidInventory(field: "revisionContents")) {
                _ = try audit(
                    fixture,
                    inventory: replacingInventory(fixture.inventory, requirements: requirements),
                    claims: ClaimRecorder()
                )
            }
        }
    }

    func testSignedProductionAuditCommitsOneAtomicInventoryBoundNonceBatch() throws {
        let fixture = try makeFixture()
        let claims = ClaimRecorder()
        let resolver = CaptureResolverProbe(captures: fixture.captures)
        let result = try audit(fixture, claims: claims, captureResolver: resolver.resolver)

        XCTAssertTrue(result.report.isCompleteAndValid)
        XCTAssertFalse(result.report.containsErrors)
        XCTAssertEqual(result.report.matrix.requiredCount, 20)
        XCTAssertEqual(result.report.matrix.completeCount, 20)
        XCTAssertEqual(result.report.findings, [])
        XCTAssertEqual(result.receipt.runNonceClaimStatus, .committed)
        XCTAssertEqual(result.receipt.requiredScenarioCount, 20)
        XCTAssertEqual(result.receipt.completeScenarioCount, 20)
        XCTAssertEqual(result.receipt.findingCount, 0)
        XCTAssertEqual(result.receipt.inventorySHA256.count, SHA256.byteCount)
        XCTAssertEqual(result.receipt.evidenceSHA256.count, SHA256.byteCount)
        XCTAssertEqual(result.receipt.reportSHA256.count, SHA256.byteCount)
        XCTAssertEqual(result.receipt.auditPolicySHA256.count, SHA256.byteCount)

        let snapshot = claims.snapshot
        XCTAssertEqual(snapshot.calls.count, 1)
        XCTAssertEqual(snapshot.accepted.count, 20)
        XCTAssertEqual(snapshot.calls[0].policy, fixture.claimPolicy)
        XCTAssertEqual(snapshot.calls[0].nonces, fixture.evidence.observations.map { $0.provenance!.runNonce })
        XCTAssertEqual(snapshot.calls[0].trustedTime, fixture.trustedTime)
        XCTAssertEqual(snapshot.calls[0].deadline, fixture.deadline)
        XCTAssertGreaterThan(snapshot.calls[0].remainingWorkUnits, 0)
        XCTAssertFalse(snapshot.calls[0].cancelledAtCall)
        XCTAssertEqual(resolver.snapshot.requests.count, 20)
    }

    func testHappyPathReportReceiptAndEveryCellAreComplete() throws {
        let fixture = try makeFixture()
        let policy = makePolicy(fixture, claims: ClaimRecorder())
        let result = try PaneShapeCoverageMatrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: CaptureResolverProbe(captures: fixture.captures).resolver
        )

        XCTAssertEqual(result.report.formatVersion, PaneShapeCoverageMatrix.reportFormatVersion)
        XCTAssertEqual(result.report.inventory, fixture.inventory.reference)
        XCTAssertEqual(result.report.evidence, fixture.evidence.reference)
        XCTAssertEqual(result.report.trustedAuditTimeUnixMilliseconds, fixture.trustedTime)
        XCTAssertEqual(result.report.maximumCaptureAgeMilliseconds, 100)
        XCTAssertEqual(result.report.maximumFutureClockSkewMilliseconds, 50)
        XCTAssertEqual(result.report.runNonceClaimDeadlineUnixMilliseconds, fixture.deadline)
        XCTAssertEqual(result.report.runNonceClaimPolicy, fixture.claimPolicy)
        XCTAssertEqual(result.report.auditPolicySHA256, result.receipt.auditPolicySHA256)
        XCTAssertNil(result.report.highestSeverity)
        XCTAssertEqual(result.report.matrix.missingCount, 0)
        XCTAssertEqual(result.report.matrix.duplicateCount, 0)
        XCTAssertEqual(result.report.matrix.mismatchedCount, 0)
        XCTAssertEqual(result.report.matrix.invalidCount, 0)
        XCTAssertEqual(result.report.matrix.assertionOnlyCount, 0)
        XCTAssertTrue(result.report.matrix.isComplete)

        XCTAssertEqual(result.receipt.formatVersion, PaneShapeCoverageMatrix.reportFormatVersion)
        XCTAssertEqual(result.receipt.build, fixture.inventory.build)
        XCTAssertEqual(result.receipt.inventory, fixture.inventory.reference)
        XCTAssertEqual(result.receipt.evidence, fixture.evidence.reference)
        XCTAssertEqual(result.receipt.requiredScenarioCount, result.report.matrix.requiredCount)
        XCTAssertEqual(result.receipt.completeScenarioCount, result.report.matrix.completeCount)
        XCTAssertEqual(result.receipt.findingCount, result.report.findings.count)

        XCTAssertEqual(result.report.matrix.cells.count, fixture.inventory.requirements.count)
        for (cell, requirement) in zip(result.report.matrix.cells, fixture.inventory.requirements) {
            XCTAssertEqual(cell.scenario, requirement.scenario)
            XCTAssertEqual(cell.expectedVisualOrder, requirement.scenario.expectedVisualOrder)
            XCTAssertEqual(cell.expectedActivePane, requirement.scenario.activePane)
            XCTAssertEqual(cell.observedLayout, fixture.evidence.observations[Int(requirement.id.rawValue)].layout)
            XCTAssertEqual(cell.evidenceCount, 1)
            XCTAssertEqual(cell.status, .complete)
        }
    }

    func testIndependentCaptureEncodingMatchesProductionAndFixedVector() throws {
        let signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data((0..<32).map(UInt8.init))
        )
        let fixture = try makeFixture(signingKey: signingKey)
        let observation = fixture.evidence.observations[0]
        let independent = independentCanonicalCaptureData(for: observation)
        let production = try PaneShapeCoverageMatrix.canonicalCaptureData(for: observation)

        XCTAssertEqual(production, independent)
        XCTAssertEqual(
            hex(Array(SHA256.hash(data: independent))),
            "426929c1e6ff63b9b905dd80a7f1419d6accdbb44c27da0d0c178ba0de833528"
        )
        XCTAssertEqual(try XCTUnwrap(observation.provenance).captureSHA256, Array(SHA256.hash(data: independent)))
    }

    func testIndependentCanonicalDigestsMatchFixedVectors() throws {
        let signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data((0..<32).map(UInt8.init))
        )
        let fixture = try makeFixture(signingKey: signingKey)
        let policy = makePolicy(fixture, claims: ClaimRecorder())
        let result = try PaneShapeCoverageMatrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: CaptureResolverProbe(captures: fixture.captures).resolver
        )
        let deterministicEvidence = replacingEvidence(
            fixture.evidence,
            observations: try fixture.evidence.observations.map { observation in
                let provenance = try XCTUnwrap(observation.provenance)
                return replacingObservation(
                    observation,
                    provenance: .replace(
                        replacingProvenance(
                            provenance,
                            collectorSignature: [UInt8](repeating: 0, count: 64)
                        )
                    )
                )
            }
        )
        let evidenceResult = try audit(
            fixture,
            evidence: deterministicEvidence,
            claims: ClaimRecorder()
        )
        let vectors = [
            (
                "inventory",
                result.receipt.inventorySHA256,
                independentCanonicalInventoryData(fixture.inventory),
                "c5f209e3971b0c4acfca3695019675e3076fbcf24f37e19b203837088275d3b3"
            ),
            (
                "evidence",
                evidenceResult.receipt.evidenceSHA256,
                independentCanonicalEvidenceData(deterministicEvidence),
                "fa99f722329b7e5c3d9dc7b312ec44bd319541ee56be9e17e4cb5b9e2d3bab33"
            ),
            (
                "policy",
                result.receipt.auditPolicySHA256,
                independentCanonicalAuditPolicyData(policy),
                "0946b8af08b05e89058d21e97176373d47bb181de5bdc58ce84c5af25caf3604"
            ),
            (
                "report",
                result.receipt.reportSHA256,
                independentCanonicalReportData(result.report),
                "19a504bba21d144c951b906c6cf4aece7ff3f8def1391353a7b3786cf659f206"
            )
        ]

        for (name, productionDigest, independentData, fixedDigest) in vectors {
            let independentDigest = Array(SHA256.hash(data: independentData))
            XCTAssertEqual(productionDigest, independentDigest, name)
            XCTAssertEqual(hex(independentDigest), fixedDigest, name)
        }
    }

    func testCollectorTrustKeyParsingAndInventoryBinding() throws {
        let fixture = try makeFixture()
        let malformedKeyInventory = replacingInventory(
            fixture.inventory,
            trustedCollectors: [PaneShapeTrustedCollector(reference: fixture.collectorReference, ed25519PublicKey: [1])]
        )
        assertError(.invalidInventory(field: "trustedCollectors")) {
            _ = try audit(fixture, inventory: malformedKeyInventory, claims: ClaimRecorder())
        }

        let duplicateCollectorInventory = replacingInventory(
            fixture.inventory,
            trustedCollectors: [fixture.inventory.trustedCollectors[0], fixture.inventory.trustedCollectors[0]]
        )
        assertError(.invalidInventory(field: "trustedCollectors")) {
            _ = try audit(fixture, inventory: duplicateCollectorInventory, claims: ClaimRecorder())
        }

        let secondKey = Curve25519.Signing.PrivateKey()
        let duplicateReferenceInventory = replacingInventory(
            fixture.inventory,
            trustedCollectors: [
                fixture.inventory.trustedCollectors[0],
                PaneShapeTrustedCollector(
                    reference: fixture.collectorReference,
                    ed25519PublicKey: Array(secondKey.publicKey.rawRepresentation)
                )
            ]
        )
        assertError(.invalidInventory(field: "trustedCollectors")) {
            _ = try audit(fixture, inventory: duplicateReferenceInventory, claims: ClaimRecorder())
        }

        let original = fixture.evidence.observations[0]
        let unknownCollector = reference("collector-unknown", 1)
        let untrusted = replacingObservation(
            original,
            provenance: .replace(replacingProvenance(try XCTUnwrap(original.provenance), collector: unknownCollector))
        )
        let untrustedResult = try audit(
            fixture,
            evidence: replacingObservation(in: fixture.evidence, at: 0, with: untrusted),
            claims: ClaimRecorder()
        )
        XCTAssertEqual(codes(in: untrustedResult, scenarioID: original.scenarioID), [.untrustedCollector])
        XCTAssertEqual(untrustedResult.report.matrix.cells[0].status, .invalid)

        let otherInventory = reference("inventory-other", 1)
        let inventoryMismatched = replacingObservation(
            original,
            provenance: .replace(replacingProvenance(try XCTUnwrap(original.provenance), inventory: otherInventory))
        )
        let inventoryMismatchResult = try audit(
            fixture,
            evidence: replacingObservation(in: fixture.evidence, at: 0, with: inventoryMismatched),
            claims: ClaimRecorder()
        )
        XCTAssertEqual(codes(in: inventoryMismatchResult, scenarioID: original.scenarioID), [.provenanceInventoryMismatch])
    }

    func testMissingBuildArtifactAndUntrustedProvenanceNeverResolveOrClaim() throws {
        let fixture = try makeFixture()
        let original = fixture.evidence.observations[0]
        let provenance = try XCTUnwrap(original.provenance)
        let cases: [(PaneShapeProductionEvidence, PaneShapeFindingCode)] = [
            (
                replacingObservation(original, provenance: .replace(nil)),
                .productionProvenanceMissing
            ),
            (
                replacingObservation(
                    original,
                    provenance: .replace(replacingProvenance(provenance, build: reference("other-build", 1)))
                ),
                .provenanceBuildMismatch
            ),
            (
                replacingObservation(
                    original,
                    provenance: .replace(replacingProvenance(provenance, artifactSHA256: digest("other-artifact")))
                ),
                .provenanceArtifactMismatch
            ),
            (
                replacingObservation(
                    original,
                    provenance: .replace(replacingProvenance(provenance, collector: reference("unknown-collector", 1)))
                ),
                .untrustedCollector
            )
        ]

        for (observation, expectedCode) in cases {
            let claims = ClaimRecorder()
            let resolver = CaptureResolverProbe(captures: fixture.captures)
            let result = try audit(
                fixture,
                evidence: replacingObservation(in: fixture.evidence, at: 0, with: observation),
                claims: claims,
                captureResolver: resolver.resolver
            )
            XCTAssertEqual(codes(in: result, scenarioID: original.scenarioID), [expectedCode])
            XCTAssertEqual(result.report.matrix.cells[0].status, .invalid)
            XCTAssertEqual(result.receipt.runNonceClaimStatus, .notRequired)
            XCTAssertEqual(claims.snapshot.calls.count, 0)
            XCTAssertEqual(claims.snapshot.accepted.count, 0)
            XCTAssertFalse(resolver.snapshot.requests.contains { $0.digest == provenance.captureSHA256 })
        }
    }

    func testCollectorSignatureBindsCanonicalPayload() throws {
        let fixture = try makeFixture()
        let original = fixture.evidence.observations[0]
        let provenance = try XCTUnwrap(original.provenance)
        var changedNonce = provenance.runNonce
        changedNonce[0] ^= 0x80
        let variants = [
            replacingObservation(original, provenance: .replace(replacingProvenance(provenance, source: provenance.source + "/changed"))),
            replacingObservation(original, provenance: .replace(replacingProvenance(provenance, runNonce: changedNonce))),
            replacingObservation(
                original,
                provenance: .replace(replacingProvenance(provenance, capturedAtUnixMilliseconds: provenance.capturedAtUnixMilliseconds + 1))
            ),
            replacingObservation(original, origin: .productionManualReview)
        ]

        for variant in variants {
            let result = try audit(
                fixture,
                evidence: replacingObservation(in: fixture.evidence, at: 0, with: variant),
                claims: ClaimRecorder()
            )
            XCTAssertEqual(codes(in: result, scenarioID: original.scenarioID), [.productionCaptureMismatch])
            XCTAssertEqual(result.report.matrix.cells[0].status, .invalid)
        }

        let otherSigningKey = Curve25519.Signing.PrivateKey()
        let payload = try PaneShapeCoverageMatrix.canonicalCaptureData(for: original)
        let wrongSignature = Array(try otherSigningKey.signature(for: payload))
        let wrongSigner = replacingObservation(
            original,
            provenance: .replace(replacingProvenance(provenance, collectorSignature: wrongSignature))
        )
        let wrongSignerResult = try audit(
            fixture,
            evidence: replacingObservation(in: fixture.evidence, at: 0, with: wrongSigner),
            claims: ClaimRecorder()
        )
        XCTAssertEqual(codes(in: wrongSignerResult, scenarioID: original.scenarioID), [.productionCaptureMismatch])
    }

    func testSignatureBindsEveryCaptureFieldAndValidManualReview() throws {
        let fixture = try makeFixture()
        let original = fixture.evidence.observations[0]
        let provenance = try XCTUnwrap(original.provenance)
        let scenario = fixture.inventory.requirements[0].scenario
        let otherScenario = fixture.inventory.requirements[1].scenario
        let otherBindings = fixture.inventory.requirements[1].bindings
        let changedLayout = try PaneShapeLayoutObservation(
            paneCount: scenario.paneCount,
            visualOrder: Array(scenario.expectedVisualOrder.reversed()),
            activePane: scenario.activePane,
            orientation: scenario.orientation
        )
        let changedCommandState = try PaneShapeCommandStateObservation(
            visualOrder: Array(scenario.expectedVisualOrder.reversed()),
            activePane: scenario.activePane
        )
        let variants = [
            replacingObservation(original, scenarioID: otherScenario.id),
            replacingObservation(original, bindings: otherBindings),
            replacingObservation(original, layout: changedLayout),
            replacingObservation(original, commandState: changedCommandState),
            replacingObservation(original, comparisonPhase: .stale),
            replacingObservation(original, hasCurrentComparisonResult: false),
            replacingObservation(
                original,
                provenance: .replace(replacingProvenance(provenance, build: reference("other-build", 1)))
            ),
            replacingObservation(
                original,
                provenance: .replace(replacingProvenance(provenance, inventory: reference("other-inventory", 1)))
            ),
            replacingObservation(
                original,
                provenance: .replace(replacingProvenance(provenance, collector: reference("other-collector", 1)))
            ),
            replacingObservation(
                original,
                provenance: .replace(replacingProvenance(provenance, artifactSHA256: digest("other-artifact")))
            )
        ]
        let baseline = independentCanonicalCaptureData(for: original)
        for variant in variants {
            XCTAssertNotEqual(independentCanonicalCaptureData(for: variant), baseline)
        }

        let signedManual = try makeSignedObservation(
            scenario: scenario,
            bindings: original.bindings,
            build: fixture.inventory.build,
            inventory: fixture.inventory.reference,
            collector: fixture.collectorReference,
            capturedAt: fixture.trustedTime - 100,
            nonce: provenance.runNonce,
            artifactSHA256: fixture.inventory.buildArtifactSHA256,
            source: provenance.source,
            origin: .productionManualReview,
            signingKey: fixture.signingKey
        )
        var captures = fixture.captures
        captures[signedManual.captureSHA256] = signedManual.capture
        let manualEvidence = replacingObservation(in: fixture.evidence, at: 0, with: signedManual.observation)
        let claims = ClaimRecorder()
        let manualResult = try audit(
            fixture,
            evidence: manualEvidence,
            claims: claims,
            captureResolver: CaptureResolverProbe(captures: captures).resolver
        )
        XCTAssertTrue(PaneShapeEvidenceOrigin.productionManualReview.isProductionProof)
        XCTAssertTrue(manualResult.report.isCompleteAndValid)
        XCTAssertEqual(manualResult.receipt.runNonceClaimStatus, .committed)
    }

    func testTrustedAuditTimeAcceptsBoundariesAndRejectsOnePast() throws {
        let trustedTime: UInt64 = 1_000_000
        let maximumAge: UInt64 = 100
        let maximumSkew: UInt64 = 50
        let boundaryFixtures = try [
            makeFixture(trustedTime: trustedTime, capturedAt: trustedTime - maximumAge),
            makeFixture(trustedTime: trustedTime, capturedAt: trustedTime + maximumSkew)
        ]
        for fixture in boundaryFixtures {
            let result = try audit(
                fixture,
                claims: ClaimRecorder(),
                maximumCaptureAgeMilliseconds: maximumAge,
                maximumFutureClockSkewMilliseconds: maximumSkew
            )
            XCTAssertTrue(result.report.isCompleteAndValid)
        }

        let expired = try makeFixture(trustedTime: trustedTime, capturedAt: trustedTime - maximumAge - 1)
        let expiredResult = try audit(
            expired,
            claims: ClaimRecorder(),
            maximumCaptureAgeMilliseconds: maximumAge,
            maximumFutureClockSkewMilliseconds: maximumSkew
        )
        XCTAssertEqual(expiredResult.report.findings.map(\.code), Array(repeating: .productionCaptureExpired, count: 20))
        XCTAssertEqual(expiredResult.report.matrix.invalidCount, 20)

        let futureDated = try makeFixture(trustedTime: trustedTime, capturedAt: trustedTime + maximumSkew + 1)
        let futureResult = try audit(
            futureDated,
            claims: ClaimRecorder(),
            maximumCaptureAgeMilliseconds: maximumAge,
            maximumFutureClockSkewMilliseconds: maximumSkew
        )
        XCTAssertEqual(futureResult.report.findings.map(\.code), Array(repeating: .productionCaptureFutureDated, count: 20))
        XCTAssertEqual(futureResult.report.matrix.invalidCount, 20)
    }

    func testNonceLengthValidityReplayAndAtomicFailure() throws {
        for length in [16, 64] {
            let fixture = try makeFixture(nonce: { scenario in
                Array(repeating: UInt8(scenario.id.rawValue + 1), count: length)
            })
            let result = try audit(fixture, claims: ClaimRecorder())
            XCTAssertTrue(result.report.isCompleteAndValid)
        }

        for length in [15, 65] {
            let fixture = try makeFixture(nonce: { scenario in
                Array(repeating: UInt8(scenario.id.rawValue + 1), count: length)
            })
            assertError(.invalidEvidence(field: "provenance")) {
                _ = try audit(fixture, claims: ClaimRecorder())
            }
        }

        let zeroNonceFixture = try makeFixture(nonce: { _ in [UInt8](repeating: 0, count: 16) })
        let zeroNonceClaims = ClaimRecorder()
        let zeroNonceResult = try audit(zeroNonceFixture, claims: zeroNonceClaims)
        XCTAssertEqual(zeroNonceResult.report.findings.map(\.code), Array(repeating: .productionProvenanceInvalid, count: 20))
        XCTAssertEqual(zeroNonceClaims.snapshot.calls.count, 0)

        let fixture = try makeFixture()
        let zeroTimestampFixture = try makeFixture(capturedAt: 0)
        var zeroArtifactObservations: [PaneShapeProductionEvidence] = []
        var zeroCaptureObservations: [PaneShapeProductionEvidence] = []
        for observation in fixture.evidence.observations {
            let provenance = try XCTUnwrap(observation.provenance)
            zeroArtifactObservations.append(
                replacingObservation(
                    observation,
                    provenance: .replace(
                        replacingProvenance(
                            provenance,
                            artifactSHA256: [UInt8](repeating: 0, count: SHA256.byteCount)
                        )
                    )
                )
            )
            zeroCaptureObservations.append(
                replacingObservation(
                    observation,
                    provenance: .replace(
                        replacingProvenance(
                            provenance,
                            captureSHA256: [UInt8](repeating: 0, count: SHA256.byteCount)
                        )
                    )
                )
            )
        }
        let zeroArtifactEvidence = replacingEvidence(fixture.evidence, observations: zeroArtifactObservations)
        let zeroCaptureEvidence = replacingEvidence(fixture.evidence, observations: zeroCaptureObservations)
        let semanticInvalidCases: [(MatrixFixture, PaneShapeEvidenceBundle, Set<PaneShapeFindingCode>)] = [
            (
                zeroTimestampFixture,
                zeroTimestampFixture.evidence,
                [.productionProvenanceInvalid, .productionCaptureExpired]
            ),
            (fixture, zeroArtifactEvidence, [.productionProvenanceInvalid, .provenanceArtifactMismatch]),
            (fixture, zeroCaptureEvidence, [.productionProvenanceInvalid])
        ]
        for (invalidFixture, invalidEvidence, expectedCodes) in semanticInvalidCases {
            let claims = ClaimRecorder()
            let resolver = CaptureResolverProbe(captures: invalidFixture.captures)
            let result = try audit(
                invalidFixture,
                evidence: invalidEvidence,
                claims: claims,
                captureResolver: resolver.resolver
            )
            for scenario in PaneShapeCoverageMatrix.canonicalScenarios {
                XCTAssertEqual(Set(codes(in: result, scenarioID: scenario.id)), expectedCodes)
            }
            XCTAssertEqual(result.report.matrix.invalidCount, 20)
            XCTAssertEqual(result.receipt.runNonceClaimStatus, .notRequired)
            XCTAssertEqual(claims.snapshot.calls.count, 0)
            XCTAssertEqual(resolver.snapshot.requests.count, 0)
        }

        let replayStore = ClaimRecorder()
        let first = try audit(fixture, claims: replayStore)
        let replay = try audit(fixture, claims: replayStore)
        XCTAssertEqual(first.receipt.runNonceClaimStatus, .committed)
        XCTAssertEqual(replay.receipt.runNonceClaimStatus, .rejectedReplay)
        XCTAssertEqual(replay.report.findings.map(\.code), Array(repeating: .productionNonceReplay, count: 20))
        XCTAssertEqual(replay.report.findings.map(\.id), replay.report.findings.map(\.id).sorted())
        XCTAssertEqual(replay.report.matrix.invalidCount, 20)
        XCTAssertEqual(replayStore.snapshot.calls.count, 2)
        XCTAssertEqual(replayStore.snapshot.accepted.count, 20)

        let duplicateNonceFixture = try makeFixture(nonce: { _ in [UInt8](repeating: 0xA5, count: 16) })
        let atomicStore = ClaimRecorder()
        let duplicateResult = try audit(duplicateNonceFixture, claims: atomicStore)
        XCTAssertEqual(duplicateResult.receipt.runNonceClaimStatus, .rejectedReplay)
        XCTAssertEqual(atomicStore.snapshot.calls.count, 1)
        XCTAssertEqual(atomicStore.snapshot.accepted.count, 0)
    }

    func testPartialNonceOverlapRejectsWholeBatchAtomically() throws {
        let first = try makeFixture()
        let replayedNonce = try XCTUnwrap(first.evidence.observations.first?.provenance?.runNonce)
        let second = try makeFixture(nonce: { scenario in
            scenario.id.rawValue == 0
                ? replayedNonce
                : [UInt8](repeating: UInt8(scenario.id.rawValue + 101), count: 16)
        })
        let claims = ClaimRecorder()

        _ = try audit(first, claims: claims)
        let acceptedAfterFirst = claims.snapshot.accepted
        let replay = try audit(second, claims: claims)

        XCTAssertEqual(replay.receipt.runNonceClaimStatus, .rejectedReplay)
        XCTAssertEqual(replay.report.matrix.invalidCount, 20)
        XCTAssertEqual(replay.report.findings.map(\.code), Array(repeating: .productionNonceReplay, count: 20))
        XCTAssertEqual(claims.snapshot.calls.count, 2)
        XCTAssertEqual(claims.snapshot.accepted, acceptedAfterFirst)
    }

    func testClaimCancellationDeadlineAndBudgetOutcomes() throws {
        let fixture = try makeFixture()
        let cases: [(ClaimRecorder.Behavior, PaneShapeCoverageError)] = [
            (.forced(.cancelled), .cancelled),
            (.forced(.deadlineExceeded), .invalidAuditPolicy(field: "runNonceClaimDeadline")),
            (.forced(.workLimitExceeded), .workLimitExceeded(maximum: PaneShapeCoverageLimits.default.maximumWorkUnits))
        ]

        for (behavior, expectedError) in cases {
            let claims = ClaimRecorder(behavior: behavior)
            assertError(expectedError) {
                _ = try audit(fixture, claims: claims)
            }
            XCTAssertEqual(claims.snapshot.calls.count, 1)
            XCTAssertEqual(claims.snapshot.accepted.count, 0)
        }
    }

    func testValidateCurrentIsIdempotentAndDoesNotReclaim() throws {
        let fixture = try makeFixture()
        let claims = ClaimRecorder()
        let resolver = CaptureResolverProbe(captures: fixture.captures)
        let policy = makePolicy(fixture, claims: claims)
        let result = try PaneShapeCoverageMatrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: resolver.resolver
        )
        XCTAssertEqual(claims.snapshot.calls.count, 1)

        try result.receipt.validateCurrent(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: resolver.resolver
        )
        try result.receipt.validateCurrent(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: resolver.resolver
        )
        XCTAssertEqual(claims.snapshot.calls.count, 1)

        let replay = try PaneShapeCoverageMatrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: resolver.resolver
        )
        XCTAssertEqual(replay.receipt.runNonceClaimStatus, .rejectedReplay)
        XCTAssertEqual(claims.snapshot.calls.count, 2)
        try replay.receipt.validateCurrent(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: resolver.resolver
        )
        XCTAssertEqual(claims.snapshot.calls.count, 2)
    }

    func testValidateCurrentRejectsChangedPolicyAndResolverOutcomesWithoutReclaim() throws {
        let fixture = try makeFixture()
        let claims = ClaimRecorder()
        let policy = makePolicy(fixture, claims: claims)
        let result = try PaneShapeCoverageMatrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: CaptureResolverProbe(captures: fixture.captures).resolver
        )
        XCTAssertEqual(claims.snapshot.calls.count, 1)

        let changedPolicies = [
            makePolicy(fixture, claims: claims, trustedTime: fixture.trustedTime + 1),
            makePolicy(fixture, claims: claims, maximumCaptureAgeMilliseconds: 101),
            makePolicy(fixture, claims: claims, maximumFutureClockSkewMilliseconds: 51),
            makePolicy(fixture, claims: claims, deadline: fixture.deadline + 1),
            makePolicy(fixture, claims: claims, claimPolicy: reference("other-policy", 1))
        ]
        for changedPolicy in changedPolicies {
            assertError(.receiptMismatch) {
                try result.receipt.validateCurrent(
                    inventory: fixture.inventory,
                    evidence: fixture.evidence,
                    auditPolicy: changedPolicy,
                    captureResolver: CaptureResolverProbe(captures: fixture.captures).resolver
                )
            }
        }

        for behavior in [
            CaptureResolverProbe.Behavior.truncated,
            .wrongSameLength,
            .failure
        ] {
            let resolver = CaptureResolverProbe(captures: fixture.captures, behavior: behavior)
            assertError(.receiptMismatch) {
                try result.receipt.validateCurrent(
                    inventory: fixture.inventory,
                    evidence: fixture.evidence,
                    auditPolicy: policy,
                    captureResolver: resolver.resolver
                )
            }
        }
        let cancellationResolver = CaptureResolverProbe(captures: fixture.captures, behavior: .cancellation)
        assertError(.cancelled) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: policy,
                captureResolver: cancellationResolver.resolver
            )
        }
        XCTAssertEqual(claims.snapshot.calls.count, 1)
    }

    func testSlicedCaptureDataHashesAndResolvesCanonically() throws {
        let fixture = try makeFixture()
        let claims = ClaimRecorder()
        let resolver = CaptureResolverProbe(captures: fixture.captures, behavior: .sliced)
        let result = try audit(fixture, claims: claims, captureResolver: resolver.resolver)

        XCTAssertTrue(result.report.isCompleteAndValid)
        XCTAssertEqual(result.receipt.runNonceClaimStatus, .committed)
        XCTAssertEqual(resolver.snapshot.requests.count, 20)
        XCTAssertTrue(resolver.snapshot.returnedStartIndices.allSatisfy { $0 > 0 })
        for request in resolver.snapshot.requests {
            let capture = try XCTUnwrap(fixture.captures[request.digest])
            XCTAssertEqual(request.maximumByteCount, capture.count)
            XCTAssertEqual(Array(SHA256.hash(data: capture)), request.digest)
        }
    }

    func testResolverRejectsTruncatedOversizedWrongAndFailedCapture() throws {
        let fixture = try makeFixture()
        for behavior in [
            CaptureResolverProbe.Behavior.truncated,
            .oversized,
            .wrongSameLength,
            .failure
        ] {
            let claims = ClaimRecorder()
            let resolver = CaptureResolverProbe(captures: fixture.captures, behavior: behavior)
            let result = try audit(fixture, claims: claims, captureResolver: resolver.resolver)
            XCTAssertEqual(result.report.findings.map(\.code), Array(repeating: .productionCaptureMismatch, count: 20))
            XCTAssertEqual(result.report.matrix.invalidCount, 20)
            XCTAssertEqual(result.receipt.runNonceClaimStatus, .notRequired)
            XCTAssertEqual(claims.snapshot.calls.count, 0)
        }
    }

    func testNotRequiredReceiptValidationReplaysNoClaims() throws {
        let fixture = try makeFixture()
        let auditClaims = ClaimRecorder()
        let failedResolver = CaptureResolverProbe(captures: fixture.captures, behavior: .failure)
        let result = try audit(
            fixture,
            claims: auditClaims,
            captureResolver: failedResolver.resolver
        )
        XCTAssertEqual(result.receipt.runNonceClaimStatus, .notRequired)

        let validationClaims = ClaimRecorder()
        let policy = makePolicy(fixture, claims: validationClaims)
        try result.receipt.validateCurrent(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: policy,
            captureResolver: CaptureResolverProbe(captures: fixture.captures, behavior: .failure).resolver
        )
        assertError(.receiptMismatch) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: policy,
                captureResolver: CaptureResolverProbe(captures: fixture.captures).resolver
            )
        }
        XCTAssertEqual(auditClaims.snapshot.calls.count, 0)
        XCTAssertEqual(validationClaims.snapshot.calls.count, 0)
    }

    func testReceiptDetectsExactRevisionAndContentStaleness() throws {
        let fixture = try makeFixture()
        let claims = ClaimRecorder()
        let result = try audit(fixture, claims: claims)
        let validationClaims = ClaimRecorder()
        let policy = makePolicy(fixture, claims: validationClaims)
        let resolver = CaptureResolverProbe(captures: fixture.captures)

        let changedBuildInventory = replacingInventory(fixture.inventory, build: reference("build", 2))
        assertError(.staleBuild) {
            try result.receipt.validateCurrent(
                inventory: changedBuildInventory,
                evidence: fixture.evidence,
                auditPolicy: policy,
                captureResolver: resolver.resolver
            )
        }

        let changedInventoryReference = replacingInventory(fixture.inventory, reference: reference("inventory", 2))
        assertError(.staleInventory) {
            try result.receipt.validateCurrent(
                inventory: changedInventoryReference,
                evidence: fixture.evidence,
                auditPolicy: policy,
                captureResolver: resolver.resolver
            )
        }

        let changedEvidenceReference = replacingEvidence(fixture.evidence, reference: reference("evidence", 2))
        assertError(.staleEvidence) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: changedEvidenceReference,
                auditPolicy: policy,
                captureResolver: resolver.resolver
            )
        }

        var changedArtifact = fixture.inventory.buildArtifactSHA256
        changedArtifact[0] ^= 0xFF
        let changedInventoryContents = replacingInventory(fixture.inventory, buildArtifactSHA256: changedArtifact)
        assertError(.staleInventory) {
            try result.receipt.validateCurrent(
                inventory: changedInventoryContents,
                evidence: fixture.evidence,
                auditPolicy: policy,
                captureResolver: resolver.resolver
            )
        }

        let changedObservation = replacingObservation(
            fixture.evidence.observations[0],
            origin: .callerAssertion,
            provenance: .replace(nil)
        )
        let changedEvidenceContents = replacingObservation(in: fixture.evidence, at: 0, with: changedObservation)
        assertError(.staleEvidence) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: changedEvidenceContents,
                auditPolicy: policy,
                captureResolver: resolver.resolver
            )
        }

        let wrongBuildEvidence = replacingEvidence(fixture.evidence, build: reference("build", 2))
        assertError(.staleBuild) {
            _ = try audit(fixture, evidence: wrongBuildEvidence, claims: ClaimRecorder())
        }
        let wrongInventoryEvidence = replacingEvidence(fixture.evidence, inventory: reference("inventory", 2))
        assertError(.staleInventory) {
            _ = try audit(fixture, evidence: wrongInventoryEvidence, claims: ClaimRecorder())
        }
        XCTAssertEqual(validationClaims.snapshot.calls.count, 0)
    }

    func testReportDigestBindsObservedLayout() throws {
        let fixture = try makeFixture()
        let targetIndex = try XCTUnwrap(fixture.evidence.observations.firstIndex { $0.scenarioID.rawValue == 8 })
        let original = fixture.evidence.observations[targetIndex]
        let scenario = fixture.inventory.requirements[targetIndex].scenario
        let changedBindings = try replacingLayoutReference(original.bindings, with: reference("observed-layout", 1))

        func variant(activePane: PaneIdentity) throws -> PaneShapeProductionEvidence {
            replacingObservation(
                original,
                bindings: changedBindings,
                layout: try PaneShapeLayoutObservation(
                    paneCount: scenario.paneCount,
                    visualOrder: scenario.expectedVisualOrder,
                    activePane: activePane,
                    orientation: scenario.orientation
                ),
                origin: .callerAssertion,
                provenance: .replace(nil)
            )
        }

        let middleEvidence = replacingObservation(in: fixture.evidence, at: targetIndex, with: try variant(activePane: .middle))
        let rightEvidence = replacingObservation(in: fixture.evidence, at: targetIndex, with: try variant(activePane: .right))
        let middleResult = try audit(fixture, evidence: middleEvidence, claims: ClaimRecorder())
        let rightResult = try audit(fixture, evidence: rightEvidence, claims: ClaimRecorder())
        let middleCell = middleResult.report.matrix.cells[targetIndex]
        let rightCell = rightResult.report.matrix.cells[targetIndex]

        XCTAssertEqual(middleResult.report.findings, rightResult.report.findings)
        XCTAssertEqual(middleResult.report.matrix.cells.map(\.status), rightResult.report.matrix.cells.map(\.status))
        XCTAssertEqual(middleCell.observedLayout?.activePane, .middle)
        XCTAssertEqual(rightCell.observedLayout?.activePane, .right)
        XCTAssertNotEqual(middleResult.receipt.reportSHA256, rightResult.receipt.reportSHA256)
    }

    func testPermutationsProduceDeterministicOrderingFindingsAndHashes() throws {
        let fixture = try makeFixture()
        let secondKey = Curve25519.Signing.PrivateKey()
        let secondCollector = PaneShapeTrustedCollector(
            reference: reference("collector-second", 1),
            ed25519PublicKey: Array(secondKey.publicKey.rawRepresentation)
        )
        let collectors = [fixture.inventory.trustedCollectors[0], secondCollector]
        let firstInventory = replacingInventory(
            fixture.inventory,
            trustedCollectors: collectors,
            requirements: fixture.inventory.requirements
        )
        let secondInventory = replacingInventory(
            fixture.inventory,
            trustedCollectors: collectors.reversed(),
            requirements: fixture.inventory.requirements.reversed()
        )
        let firstResult = try audit(fixture, inventory: firstInventory, claims: ClaimRecorder())
        let secondResult = try audit(
            fixture,
            inventory: secondInventory,
            evidence: replacingEvidence(fixture.evidence, observations: fixture.evidence.observations.reversed()),
            claims: ClaimRecorder()
        )
        XCTAssertEqual(firstResult.report, secondResult.report)
        XCTAssertEqual(firstResult.receipt, secondResult.receipt)

        var malformed = fixture.evidence.observations.map {
            replacingObservation($0, origin: .callerAssertion, provenance: .replace(nil))
        }
        malformed.removeFirst()
        malformed.append(malformed[0])
        malformed.append(replacingObservation(malformed[1], scenarioID: PaneShapeScenarioID(rawValue: 999)))
        let malformedForward = replacingEvidence(fixture.evidence, observations: malformed)
        let malformedReverse = replacingEvidence(fixture.evidence, observations: malformed.reversed())
        let forwardResult = try audit(fixture, inventory: firstInventory, evidence: malformedForward, claims: ClaimRecorder())
        let reverseResult = try audit(fixture, inventory: secondInventory, evidence: malformedReverse, claims: ClaimRecorder())

        XCTAssertEqual(forwardResult.report, reverseResult.report)
        XCTAssertEqual(forwardResult.receipt, reverseResult.receipt)
        XCTAssertEqual(forwardResult.report.findings.count, 23)
        XCTAssertEqual(forwardResult.report.matrix.missingCount, 1)
        XCTAssertEqual(forwardResult.report.matrix.duplicateCount, 1)
        XCTAssertEqual(forwardResult.report.matrix.assertionOnlyCount, 18)
        XCTAssertEqual(
            forwardResult.report.findings.map { $0.code.rawValue },
            forwardResult.report.findings.map { $0.code.rawValue }.sorted()
        )
        XCTAssertEqual(forwardResult.report.matrix.cells.map(\.scenario.id.rawValue), Array(0...19))
    }

    func testSecondTrustedCollectorValidatesInEitherInventoryOrder() throws {
        let fixture = try makeFixture()
        let secondKey = Curve25519.Signing.PrivateKey()
        let secondReference = reference("collector-second", 1)
        let secondCollector = PaneShapeTrustedCollector(
            reference: secondReference,
            ed25519PublicKey: Array(secondKey.publicKey.rawRepresentation)
        )
        let original = fixture.evidence.observations[0]
        let provenance = try XCTUnwrap(original.provenance)
        let secondSigned = try makeSignedObservation(
            scenario: fixture.inventory.requirements[0].scenario,
            bindings: original.bindings,
            build: fixture.inventory.build,
            inventory: fixture.inventory.reference,
            collector: secondReference,
            capturedAt: provenance.capturedAtUnixMilliseconds,
            nonce: provenance.runNonce,
            artifactSHA256: fixture.inventory.buildArtifactSHA256,
            source: provenance.source,
            signingKey: secondKey
        )
        let evidence = replacingObservation(in: fixture.evidence, at: 0, with: secondSigned.observation)
        var captures = fixture.captures
        captures[secondSigned.captureSHA256] = secondSigned.capture
        let collectors = [fixture.inventory.trustedCollectors[0], secondCollector]

        for order in [collectors, Array(collectors.reversed())] {
            let result = try audit(
                fixture,
                inventory: replacingInventory(fixture.inventory, trustedCollectors: Array(order)),
                evidence: evidence,
                claims: ClaimRecorder(),
                captureResolver: CaptureResolverProbe(captures: captures).resolver
            )
            XCTAssertTrue(result.report.isCompleteAndValid)
            XCTAssertEqual(result.receipt.runNonceClaimStatus, .committed)
        }
    }

    func testObservationFindingCollectorAndCanonicalByteLimitsAtBoundaryAndOneUnder() throws {
        let fixture = try makeFixture()
        let observationBoundary = limits(maximumObservations: 20)
        XCTAssertNoThrow(try audit(fixture, limits: observationBoundary, claims: ClaimRecorder()))
        assertError(.observationLimitExceeded(maximum: 19)) {
            _ = try audit(fixture, limits: limits(maximumObservations: 19), claims: ClaimRecorder())
        }

        let assertionEvidence = replacingEvidence(
            fixture.evidence,
            observations: fixture.evidence.observations.map {
                replacingObservation($0, origin: .callerAssertion, provenance: .replace(nil))
            }
        )
        let exactFindingLimit = try audit(
            fixture,
            evidence: assertionEvidence,
            limits: limits(maximumFindings: 20),
            claims: ClaimRecorder()
        )
        XCTAssertEqual(exactFindingLimit.report.findings.count, 20)
        assertError(.findingLimitExceeded(maximum: 19)) {
            _ = try audit(
                fixture,
                evidence: assertionEvidence,
                limits: limits(maximumFindings: 19),
                claims: ClaimRecorder()
            )
        }

        let secondKey = Curve25519.Signing.PrivateKey()
        let twoCollectorInventory = replacingInventory(
            fixture.inventory,
            trustedCollectors: [
                fixture.inventory.trustedCollectors[0],
                PaneShapeTrustedCollector(
                    reference: reference("collector-second", 1),
                    ed25519PublicKey: Array(secondKey.publicKey.rawRepresentation)
                )
            ]
        )
        XCTAssertNoThrow(
            try audit(
                fixture,
                inventory: twoCollectorInventory,
                limits: limits(maximumTrustedCollectors: 2),
                claims: ClaimRecorder()
            )
        )
        assertError(.invalidInventory(field: "buildProvenance")) {
            _ = try audit(
                fixture,
                inventory: twoCollectorInventory,
                limits: limits(maximumTrustedCollectors: 1),
                claims: ClaimRecorder()
            )
        }

        let observation = fixture.evidence.observations[0]
        let capture = try PaneShapeCoverageMatrix.canonicalCaptureData(for: observation)
        let exactCanonicalLimit = limits(maximumCanonicalBytes: capture.count)
        XCTAssertEqual(try PaneShapeCoverageMatrix.canonicalCaptureData(for: observation, limits: exactCanonicalLimit), capture)
        assertError(.canonicalDataTooLarge(maximumBytes: capture.count - 1)) {
            _ = try PaneShapeCoverageMatrix.canonicalCaptureData(
                for: observation,
                limits: limits(maximumCanonicalBytes: capture.count - 1)
            )
        }
    }

    func testSharedStringLimitsAtExactByteBoundaryAndOneUnder() throws {
        let source = String(repeating: "é", count: 64)
        XCTAssertEqual(source.utf8.count, 128)
        let fixture = try makeFixture(source: { _ in source })
        XCTAssertNoThrow(
            try audit(
                fixture,
                limits: limits(maximumStringUTF8Bytes: 128),
                claims: ClaimRecorder()
            )
        )
        assertError(.stringTooLarge(field: "evidence.provenance.source", maximumUTF8Bytes: 127)) {
            _ = try audit(
                fixture,
                limits: limits(maximumStringUTF8Bytes: 127),
                claims: ClaimRecorder()
            )
        }

        let assertionEvidence = replacingEvidence(
            fixture.evidence,
            observations: fixture.evidence.observations.map {
                replacingObservation($0, origin: .callerAssertion, provenance: .replace(nil))
            }
        )
        let minimumTotal = try minimumPassingLimit(lowerBound: 128, upperBound: PaneShapeCoverageLimits.hardMaximumTotalStringUTF8Bytes) { value in
            do {
                _ = try audit(
                    fixture,
                    evidence: assertionEvidence,
                    limits: limits(
                        maximumStringUTF8Bytes: 128,
                        maximumTotalStringUTF8Bytes: value,
                        maximumWorkUnits: PaneShapeCoverageLimits.hardMaximumWorkUnits
                    ),
                    claims: ClaimRecorder()
                )
                return true
            } catch PaneShapeCoverageError.totalStringsTooLarge {
                return false
            }
        }
        XCTAssertGreaterThan(minimumTotal, 128)
        XCTAssertNoThrow(
            try audit(
                fixture,
                evidence: assertionEvidence,
                limits: limits(
                    maximumStringUTF8Bytes: 128,
                    maximumTotalStringUTF8Bytes: minimumTotal,
                    maximumWorkUnits: PaneShapeCoverageLimits.hardMaximumWorkUnits
                ),
                claims: ClaimRecorder()
            )
        )
        assertError(.totalStringsTooLarge(maximumUTF8Bytes: minimumTotal - 1)) {
            _ = try audit(
                fixture,
                evidence: assertionEvidence,
                limits: limits(
                    maximumStringUTF8Bytes: 128,
                    maximumTotalStringUTF8Bytes: minimumTotal - 1,
                    maximumWorkUnits: PaneShapeCoverageLimits.hardMaximumWorkUnits
                ),
                claims: ClaimRecorder()
            )
        }
    }

    func testByteBudgetedSortAndSharedWorkLimitHaveExactBoundary() throws {
        let fixture = try makeFixture()
        let base = fixture.evidence.observations[0]
        let provenance = try XCTUnwrap(base.provenance)
        let observations = (0..<12).map { index in
            replacingObservation(
                base,
                origin: .callerAssertion,
                provenance: .replace(
                    replacingProvenance(
                        provenance,
                        source: String(repeating: "x", count: 256) + String(format: "%02d", index)
                    )
                )
            )
        }
        let ascending = replacingEvidence(fixture.evidence, observations: observations)
        let descending = replacingEvidence(fixture.evidence, observations: observations.reversed())

        func minimumWork(for evidence: PaneShapeEvidenceBundle) throws -> Int {
            try minimumPassingLimit(lowerBound: 1, upperBound: PaneShapeCoverageLimits.hardMaximumWorkUnits) { value in
                do {
                    _ = try audit(
                        fixture,
                        evidence: evidence,
                        limits: limits(
                            maximumStringUTF8Bytes: 512,
                            maximumTotalStringUTF8Bytes: 32_768,
                            maximumWorkUnits: value,
                            maximumFindings: 128
                        ),
                        claims: ClaimRecorder()
                    )
                    return true
                } catch PaneShapeCoverageError.workLimitExceeded {
                    return false
                }
            }
        }

        let ascendingMinimum = try minimumWork(for: ascending)
        let descendingMinimum = try minimumWork(for: descending)
        XCTAssertGreaterThan(descendingMinimum, ascendingMinimum)
        XCTAssertNoThrow(
            try audit(
                fixture,
                evidence: descending,
                limits: limits(
                    maximumStringUTF8Bytes: 512,
                    maximumTotalStringUTF8Bytes: 32_768,
                    maximumWorkUnits: descendingMinimum,
                    maximumFindings: 128
                ),
                claims: ClaimRecorder()
            )
        )
        assertError(.workLimitExceeded(maximum: descendingMinimum - 1)) {
            _ = try audit(
                fixture,
                evidence: descending,
                limits: limits(
                    maximumStringUTF8Bytes: 512,
                    maximumTotalStringUTF8Bytes: 32_768,
                    maximumWorkUnits: descendingMinimum - 1,
                    maximumFindings: 128
                ),
                claims: ClaimRecorder()
            )
        }
    }

    func testMalformedLimitsPoliciesAndInputsAreRejectedExactly() throws {
        let fixture = try makeFixture()
        let observation = fixture.evidence.observations[0]
        let invalidLimits: [(PaneShapeCoverageLimits, PaneShapeCoverageLimit)] = [
            (limits(maximumTrustedCollectors: 0), .trustedCollectors),
            (limits(maximumTrustedCollectors: PaneShapeCoverageLimits.hardMaximumTrustedCollectors + 1), .trustedCollectors),
            (limits(maximumObservations: 0), .observations),
            (limits(maximumObservations: PaneShapeCoverageLimits.hardMaximumObservations + 1), .observations),
            (limits(maximumStringUTF8Bytes: 0), .stringUTF8Bytes),
            (limits(maximumStringUTF8Bytes: PaneShapeCoverageLimits.hardMaximumStringUTF8Bytes + 1), .stringUTF8Bytes),
            (limits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 1), .totalStringUTF8Bytes),
            (limits(maximumTotalStringUTF8Bytes: PaneShapeCoverageLimits.hardMaximumTotalStringUTF8Bytes + 1), .totalStringUTF8Bytes),
            (limits(maximumWorkUnits: 0), .workUnits),
            (limits(maximumWorkUnits: PaneShapeCoverageLimits.hardMaximumWorkUnits + 1), .workUnits),
            (limits(maximumFindings: 0), .findings),
            (limits(maximumFindings: PaneShapeCoverageLimits.hardMaximumFindings + 1), .findings),
            (limits(maximumCanonicalBytes: 0), .canonicalBytes),
            (limits(maximumCanonicalBytes: PaneShapeCoverageLimits.hardMaximumCanonicalBytes + 1), .canonicalBytes),
            (limits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (limits(cancellationCheckInterval: PaneShapeCoverageLimits.hardMaximumCancellationCheckInterval + 1), .cancellationCheckInterval)
        ]
        for (value, expectedLimit) in invalidLimits {
            assertError(.invalidLimit(expectedLimit)) {
                _ = try PaneShapeCoverageMatrix.canonicalCaptureData(for: observation, limits: value)
            }
        }

        assertError(.invalidAuditPolicy(field: "trustedAuditTime")) {
            _ = try PaneShapeCoverageMatrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: nil,
                captureResolver: CaptureResolverProbe(captures: fixture.captures).resolver
            )
        }
        for policy in [
            makePolicy(fixture, claims: ClaimRecorder(), trustedTime: 0),
            makePolicy(fixture, claims: ClaimRecorder(), maximumCaptureAgeMilliseconds: 0),
            makePolicy(fixture, claims: ClaimRecorder(), deadline: fixture.trustedTime - 1)
        ] {
            assertError(.invalidAuditPolicy(field: "freshness")) {
                _ = try PaneShapeCoverageMatrix.audit(
                    inventory: fixture.inventory,
                    evidence: fixture.evidence,
                    auditPolicy: policy,
                    captureResolver: CaptureResolverProbe(captures: fixture.captures).resolver
                )
            }
        }

        let badIdentifierInventory = replacingInventory(fixture.inventory, reference: reference("bad identifier", 1))
        assertError(.invalidInventory(field: "inventory.reference")) {
            _ = try audit(fixture, inventory: badIdentifierInventory, claims: ClaimRecorder())
        }
        let zeroArtifactInventory = replacingInventory(
            fixture.inventory,
            buildArtifactSHA256: [UInt8](repeating: 0, count: SHA256.byteCount)
        )
        assertError(.invalidInventory(field: "buildProvenance")) {
            _ = try audit(fixture, inventory: zeroArtifactInventory, claims: ClaimRecorder())
        }

        let original = fixture.evidence.observations[0]
        let provenance = try XCTUnwrap(original.provenance)
        let malformedSource = replacingObservation(
            original,
            provenance: .replace(replacingProvenance(provenance, source: "\n"))
        )
        assertError(.invalidEvidence(field: "evidence.provenance.source")) {
            _ = try audit(
                fixture,
                evidence: replacingObservation(in: fixture.evidence, at: 0, with: malformedSource),
                claims: ClaimRecorder()
            )
        }
        let malformedDigest = replacingObservation(
            original,
            provenance: .replace(replacingProvenance(provenance, captureSHA256: [1]))
        )
        assertError(.invalidEvidence(field: "provenance")) {
            _ = try audit(
                fixture,
                evidence: replacingObservation(in: fixture.evidence, at: 0, with: malformedDigest),
                claims: ClaimRecorder()
            )
        }

        for artifactCount in [31, 33] {
            let malformedArtifact = replacingObservation(
                original,
                provenance: .replace(
                    replacingProvenance(
                        provenance,
                        artifactSHA256: [UInt8](repeating: 1, count: artifactCount)
                    )
                )
            )
            assertError(.invalidEvidence(field: "provenance")) {
                _ = try audit(
                    fixture,
                    evidence: replacingObservation(in: fixture.evidence, at: 0, with: malformedArtifact),
                    claims: ClaimRecorder()
                )
            }
        }
        for signatureCount in [63, 65] {
            let malformedSignature = replacingObservation(
                original,
                provenance: .replace(
                    replacingProvenance(
                        provenance,
                        collectorSignature: [UInt8](repeating: 1, count: signatureCount)
                    )
                )
            )
            assertError(.invalidEvidence(field: "provenance")) {
                _ = try audit(
                    fixture,
                    evidence: replacingObservation(in: fixture.evidence, at: 0, with: malformedSignature),
                    claims: ClaimRecorder()
                )
            }
        }
    }

    func testCancellationCadenceAndResolverCancellationAreEnforced() throws {
        let fixture = try makeFixture()
        let cadence = CancellationProbe(cancelOnCall: 2)
        assertError(.cancelled) {
            _ = try PaneShapeCoverageMatrix.canonicalCaptureData(
                for: fixture.evidence.observations[0],
                limits: limits(cancellationCheckInterval: 8),
                cancellationCheck: cadence.cancellationCheck
            )
        }
        XCTAssertEqual(cadence.callCount, 2)

        assertError(.cancelled) {
            _ = try audit(fixture, claims: ClaimRecorder(), cancellationCheck: { true })
        }

        let resolver = CaptureResolverProbe(captures: fixture.captures, behavior: .cancellation)
        assertError(.cancelled) {
            _ = try audit(fixture, claims: ClaimRecorder(), captureResolver: resolver.resolver)
        }

        let delayed = CancellationProbe(cancelOnCall: 25)
        let claims = ClaimRecorder()
        assertError(.cancelled) {
            _ = try audit(fixture, claims: claims, cancellationCheck: delayed.cancellationCheck)
        }
        XCTAssertGreaterThanOrEqual(delayed.callCount, 25)
        XCTAssertEqual(claims.snapshot.calls.count, 0)
        XCTAssertEqual(claims.snapshot.accepted.count, 0)
    }

    func testDiagnosticsAndReflectionRemainRedacted() throws {
        let secret = "SECRET-PANE-CAPTURE-7f39"
        let fixture = try makeFixture(source: { _ in secret })
        let claims = ClaimRecorder()
        let result = try audit(fixture, claims: claims)
        let provenance = try XCTUnwrap(fixture.evidence.observations[0].provenance)
        let collector = fixture.inventory.trustedCollectors[0]
        let values: [Any] = [
            collector,
            fixture.inventory,
            provenance,
            fixture.evidence.observations[0],
            fixture.evidence,
            result.report.matrix.cells[0],
            result.report,
            result.receipt,
            PaneShapeCoverageError.invalidEvidence(field: "provenance")
        ]

        for value in values {
            let description = String(describing: value)
            let debugDescription = String(reflecting: value)
            let reflection = mirrorDescription(value)
            XCTAssertFalse(description.contains(secret))
            XCTAssertFalse(debugDescription.contains(secret))
            XCTAssertFalse(reflection.contains(secret))
            XCTAssertTrue(description.contains("redacted") || reflection.contains("redacted"))
        }

        let collectorMirror = Dictionary(
            uniqueKeysWithValues: Mirror(reflecting: collector).children.compactMap { child in
                child.label.map { ($0, String(describing: child.value)) }
            }
        )
        XCTAssertEqual(collectorMirror["key"], "<redacted>")
        XCTAssertFalse(String(describing: collector).contains(hex(collector.ed25519PublicKey)))

        let sensitiveValues = [
            fixture.collectorReference.id.rawValue,
            hex(provenance.runNonce),
            hex(provenance.artifactSHA256),
            hex(provenance.captureSHA256),
            hex(provenance.collectorSignature)
        ]
        for value in values {
            let rendered = [
                String(describing: value),
                String(reflecting: value),
                mirrorDescription(value)
            ].joined(separator: "|")
            for sensitiveValue in sensitiveValues where !sensitiveValue.isEmpty {
                XCTAssertFalse(rendered.contains(sensitiveValue))
            }
        }

        let secretField = "SECRET-FIELD-NAME"
        let fieldErrors: [PaneShapeCoverageError] = [
            .stringTooLarge(field: secretField, maximumUTF8Bytes: 1),
            .invalidAuditPolicy(field: secretField),
            .invalidInventory(field: secretField),
            .invalidEvidence(field: secretField),
            .invalidObservation(field: secretField)
        ]
        for error in fieldErrors {
            XCTAssertFalse(String(describing: error).contains(secretField))
            XCTAssertFalse(String(reflecting: error).contains(secretField))
            XCTAssertFalse(mirrorDescription(error).contains(secretField))
        }

        let assertion = replacingObservation(
            fixture.evidence.observations[0],
            origin: .callerAssertion,
            provenance: .replace(nil)
        )
        let findingResult = try audit(
            fixture,
            evidence: replacingObservation(in: fixture.evidence, at: 0, with: assertion),
            claims: ClaimRecorder()
        )
        for finding in findingResult.report.findings {
            XCTAssertFalse(finding.message.contains(secret))
            XCTAssertFalse(finding.id.rawValue.contains(secret))
        }
    }
}

private struct MatrixFixture {
    let signingKey: Curve25519.Signing.PrivateKey
    let collectorReference: PaneShapeRevisionReference
    let claimPolicy: PaneShapeRevisionReference
    let trustedTime: UInt64
    let deadline: UInt64
    let inventory: PaneShapeCoverageInventory
    let evidence: PaneShapeEvidenceBundle
    let captures: [[UInt8]: Data]
}

private enum OptionalReplacement<Value> {
    case keep
    case replace(Value?)
}

private final class ClaimRecorder: @unchecked Sendable {
    enum Behavior {
        case atomic
        case forced(PaneShapeAuditPolicy.RunNonceClaimResult)
    }

    struct Call {
        let policy: PaneShapeRevisionReference
        let nonces: [[UInt8]]
        let trustedTime: UInt64
        let deadline: UInt64
        let remainingWorkUnits: Int
        let cancelledAtCall: Bool
    }

    struct Snapshot {
        let calls: [Call]
        let accepted: Set<[UInt8]>
    }

    private let behavior: Behavior
    private let lock = NSLock()
    private var calls: [Call] = []
    private var accepted: Set<[UInt8]> = []

    init(behavior: Behavior = .atomic) {
        self.behavior = behavior
    }

    func claim(
        policy: PaneShapeRevisionReference,
        nonces: [[UInt8]],
        context: PaneShapeAuditPolicy.RunNonceClaimContext
    ) -> PaneShapeAuditPolicy.RunNonceClaimResult {
        let cancelled = context.cancellationCheck()
        lock.lock()
        defer { lock.unlock() }
        calls.append(
            Call(
                policy: policy,
                nonces: nonces,
                trustedTime: context.trustedAuditTimeUnixMilliseconds,
                deadline: context.deadlineUnixMilliseconds,
                remainingWorkUnits: context.remainingWorkUnits,
                cancelledAtCall: cancelled
            )
        )
        switch behavior {
        case .atomic:
            let proposed = Set(nonces)
            guard proposed.count == nonces.count, proposed.isDisjoint(with: accepted) else {
                return .rejectedReplay
            }
            accepted.formUnion(proposed)
            return .committed
        case .forced(let result):
            return result
        }
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(calls: calls, accepted: accepted)
    }
}

private final class CaptureResolverProbe: @unchecked Sendable {
    enum Behavior {
        case canonical
        case sliced
        case truncated
        case oversized
        case wrongSameLength
        case failure
        case cancellation
    }

    struct Request {
        let digest: [UInt8]
        let maximumByteCount: Int
    }

    struct Snapshot {
        let requests: [Request]
        let returnedStartIndices: [Int]
    }

    private let captures: [[UInt8]: Data]
    private let behavior: Behavior
    private let lock = NSLock()
    private var requests: [Request] = []
    private var returnedStartIndices: [Int] = []

    init(captures: [[UInt8]: Data], behavior: Behavior = .canonical) {
        self.captures = captures
        self.behavior = behavior
    }

    func resolve(
        digest: [UInt8],
        maximumByteCount: Int,
        cancellationCheck: PaneShapeCoverageMatrix.CancellationCheck
    ) throws -> Data {
        if cancellationCheck() { throw PaneShapeCoverageError.cancelled }
        lock.lock()
        requests.append(Request(digest: digest, maximumByteCount: maximumByteCount))
        lock.unlock()
        guard let canonical = captures[digest] else { throw PaneShapeCaptureResolutionError.exceedsMaximumByteCount }

        let value: Data
        switch behavior {
        case .canonical:
            value = canonical
        case .sliced:
            var padded = Data([0xA5])
            padded.append(canonical)
            padded.append(0x5A)
            value = padded[padded.index(after: padded.startIndex)..<padded.index(before: padded.endIndex)]
        case .truncated:
            value = canonical.dropLast()
        case .oversized:
            value = canonical + Data([0])
        case .wrongSameLength:
            var changed = canonical
            changed[changed.startIndex] ^= 0xFF
            value = changed
        case .failure:
            throw PaneShapeCaptureResolutionError.exceedsMaximumByteCount
        case .cancellation:
            throw CancellationError()
        }

        lock.lock()
        returnedStartIndices.append(value.startIndex)
        lock.unlock()
        return value
    }

    var resolver: PaneShapeCoverageMatrix.CaptureResolver {
        { [self] digest, maximumByteCount, cancellationCheck in
            try resolve(
                digest: digest,
                maximumByteCount: maximumByteCount,
                cancellationCheck: cancellationCheck
            )
        }
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(requests: requests, returnedStartIndices: returnedStartIndices)
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let cancelOnCall: Int
    private let lock = NSLock()
    private var calls = 0

    init(cancelOnCall: Int) {
        self.cancelOnCall = cancelOnCall
    }

    func check() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return calls >= cancelOnCall
    }

    var cancellationCheck: PaneShapeCoverageMatrix.CancellationCheck {
        { [self] in check() }
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

private func makeFixture(
    trustedTime: UInt64 = 1_000_000,
    capturedAt: UInt64 = 999_900,
    source: (PaneShapeScenario) -> String = { "production://pane-shape/\($0.id.rawValue)" },
    nonce: (PaneShapeScenario) -> [UInt8] = { scenario in
        [UInt8](repeating: UInt8(scenario.id.rawValue + 1), count: 16)
    },
    signingKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey()
) throws -> MatrixFixture {
    let collectorReference = reference("collector", 1)
    let inventoryReference = reference("inventory", 1)
    let buildReference = reference("build", 1)
    let artifact = digest("build-artifact")
    let bindingsByScenario = try makeBindingsByScenario()
    let inventory = try PaneShapeCoverageInventory.canonical(
        reference: inventoryReference,
        build: buildReference,
        buildArtifactSHA256: artifact,
        trustedCollectors: [
            PaneShapeTrustedCollector(
                reference: collectorReference,
                ed25519PublicKey: Array(signingKey.publicKey.rawRepresentation)
            )
        ],
        bindingsByScenario: bindingsByScenario
    )
    var observations: [PaneShapeProductionEvidence] = []
    var captures: [[UInt8]: Data] = [:]
    for requirement in inventory.requirements {
        let scenario = requirement.scenario
        let signed = try makeSignedObservation(
            scenario: scenario,
            bindings: requirement.bindings,
            build: buildReference,
            inventory: inventoryReference,
            collector: collectorReference,
            capturedAt: capturedAt,
            nonce: nonce(scenario),
            artifactSHA256: artifact,
            source: source(scenario),
            signingKey: signingKey
        )
        observations.append(signed.observation)
        captures[signed.captureSHA256] = signed.capture
    }
    let evidence = PaneShapeEvidenceBundle(
        reference: reference("evidence", 1),
        inventory: inventoryReference,
        build: buildReference,
        observations: observations
    )
    return MatrixFixture(
        signingKey: signingKey,
        collectorReference: collectorReference,
        claimPolicy: reference("nonce-policy", 1),
        trustedTime: trustedTime,
        deadline: trustedTime + 1_000,
        inventory: inventory,
        evidence: evidence,
        captures: captures
    )
}

private func makeSignedObservation(
    scenario: PaneShapeScenario,
    bindings: PaneShapeRevisionBindings,
    build: PaneShapeRevisionReference,
    inventory: PaneShapeRevisionReference,
    collector: PaneShapeRevisionReference,
    capturedAt: UInt64,
    nonce: [UInt8],
    artifactSHA256: [UInt8],
    source: String,
    origin: PaneShapeEvidenceOrigin = .productionAutomation,
    signingKey: Curve25519.Signing.PrivateKey
) throws -> (observation: PaneShapeProductionEvidence, capture: Data, captureSHA256: [UInt8]) {
    let layout = try PaneShapeLayoutObservation(
        paneCount: scenario.paneCount,
        visualOrder: scenario.expectedVisualOrder,
        activePane: scenario.activePane,
        orientation: scenario.orientation
    )
    let commandState = try PaneShapeCommandStateObservation(
        visualOrder: scenario.expectedVisualOrder,
        activePane: scenario.activePane
    )
    let unsignedProvenance = PaneShapeEvidenceProvenance(
        build: build,
        inventory: inventory,
        collector: collector,
        capturedAtUnixMilliseconds: capturedAt,
        runNonce: nonce,
        artifactSHA256: artifactSHA256,
        captureSHA256: [UInt8](repeating: 0, count: SHA256.byteCount),
        collectorSignature: [UInt8](repeating: 0, count: 64),
        source: source
    )
    let unsignedObservation = PaneShapeProductionEvidence(
        scenarioID: scenario.id,
        bindings: bindings,
        layout: layout,
        commandState: commandState,
        comparisonPhase: .current,
        hasCurrentComparisonResult: true,
        origin: origin,
        provenance: unsignedProvenance
    )
    let capture = independentCanonicalCaptureData(for: unsignedObservation)
    let captureSHA256 = Array(SHA256.hash(data: capture))
    let signature = Array(try signingKey.signature(for: capture))
    let provenance = replacingProvenance(
        unsignedProvenance,
        captureSHA256: captureSHA256,
        collectorSignature: signature
    )
    return (
        replacingObservation(unsignedObservation, provenance: .replace(provenance)),
        capture,
        captureSHA256
    )
}

private func independentCanonicalCaptureData(for observation: PaneShapeProductionEvidence) -> Data {
    var result = Data()
    appendIndependent("MMPSCAP2", to: &result)
    appendIndependent(observation.scenarioID.rawValue, to: &result)
    appendIndependent(observation.bindings, to: &result)
    result.append(observation.layout.paneCount.rawValue)
    appendIndependent(observation.layout.visualOrder, to: &result)
    result.append(independentPaneRank(observation.layout.activePane))
    result.append(observation.layout.orientation.rawValue)
    appendIndependent(observation.commandState.visualOrder, to: &result)
    result.append(independentPaneRank(observation.commandState.activePane))
    result.append(independentLifecycleRank(observation.comparisonPhase))
    result.append(observation.hasCurrentComparisonResult ? 1 : 0)
    result.append(observation.origin.rawValue)
    guard let provenance = observation.provenance else {
        result.append(0)
        return result
    }
    result.append(1)
    appendIndependent(provenance.build, to: &result)
    appendIndependent(provenance.inventory, to: &result)
    appendIndependent(provenance.collector, to: &result)
    appendIndependent(provenance.capturedAtUnixMilliseconds, to: &result)
    appendIndependent(provenance.runNonce.count, to: &result)
    result.append(contentsOf: provenance.runNonce)
    appendIndependent(provenance.artifactSHA256.count, to: &result)
    result.append(contentsOf: provenance.artifactSHA256)
    appendIndependent(provenance.source, to: &result)
    return result
}

private func independentCanonicalInventoryData(_ inventory: PaneShapeCoverageInventory) -> Data {
    var result = Data()
    appendIndependent("MMPSINV1", to: &result)
    appendIndependent(UInt64(PaneShapeCoverageMatrix.canonicalMatrixRevision), to: &result)
    appendIndependent(inventory.reference, to: &result)
    appendIndependent(inventory.build, to: &result)
    appendIndependent(inventory.buildArtifactSHA256.count, to: &result)
    result.append(contentsOf: inventory.buildArtifactSHA256)
    let collectors = inventory.trustedCollectors.map { collector in
        var record = Data()
        appendIndependent(collector.reference, to: &record)
        appendIndependent(collector.ed25519PublicKey.count, to: &record)
        record.append(contentsOf: collector.ed25519PublicKey)
        return record
    }.sorted { $0.lexicographicallyPrecedes($1) }
    appendIndependent(collectors.count, to: &result)
    for record in collectors {
        result.append(record)
    }
    let requirements = inventory.requirements.sorted { $0.id < $1.id }
    appendIndependent(requirements.count, to: &result)
    for requirement in requirements {
        appendIndependent(requirement.scenario, to: &result)
        appendIndependent(requirement.bindings, to: &result)
    }
    return result
}

private func independentCanonicalEvidenceData(_ evidence: PaneShapeEvidenceBundle) -> Data {
    var result = Data()
    appendIndependent("MMPSEVD2", to: &result)
    appendIndependent(evidence.reference, to: &result)
    appendIndependent(evidence.inventory, to: &result)
    appendIndependent(evidence.build, to: &result)
    let observations = evidence.observations.map(independentCanonicalObservationData).sorted {
        $0.lexicographicallyPrecedes($1)
    }
    appendIndependent(observations.count, to: &result)
    for observation in observations {
        appendIndependent(observation.count, to: &result)
        result.append(observation)
    }
    return result
}

private func independentCanonicalObservationData(_ observation: PaneShapeProductionEvidence) -> Data {
    var result = Data()
    appendIndependent(observation.scenarioID.rawValue, to: &result)
    appendIndependent(observation.bindings, to: &result)
    result.append(observation.layout.paneCount.rawValue)
    appendIndependent(observation.layout.visualOrder, to: &result)
    result.append(independentPaneRank(observation.layout.activePane))
    result.append(observation.layout.orientation.rawValue)
    appendIndependent(observation.commandState.visualOrder, to: &result)
    result.append(independentPaneRank(observation.commandState.activePane))
    result.append(independentLifecycleRank(observation.comparisonPhase))
    result.append(observation.hasCurrentComparisonResult ? 1 : 0)
    result.append(observation.origin.rawValue)
    guard let provenance = observation.provenance else {
        result.append(0)
        return result
    }
    result.append(1)
    appendIndependent(provenance.build, to: &result)
    appendIndependent(provenance.inventory, to: &result)
    appendIndependent(provenance.collector, to: &result)
    appendIndependent(provenance.capturedAtUnixMilliseconds, to: &result)
    appendIndependent(provenance.runNonce.count, to: &result)
    result.append(contentsOf: provenance.runNonce)
    appendIndependent(provenance.artifactSHA256.count, to: &result)
    result.append(contentsOf: provenance.artifactSHA256)
    appendIndependent(provenance.captureSHA256.count, to: &result)
    result.append(contentsOf: provenance.captureSHA256)
    appendIndependent(provenance.collectorSignature.count, to: &result)
    result.append(contentsOf: provenance.collectorSignature)
    appendIndependent(provenance.source, to: &result)
    return result
}

private func independentCanonicalAuditPolicyData(_ policy: PaneShapeAuditPolicy) -> Data {
    var result = Data()
    appendIndependent("MMPSPOL3", to: &result)
    appendIndependent(policy.trustedAuditTimeUnixMilliseconds, to: &result)
    appendIndependent(policy.maximumCaptureAgeMilliseconds, to: &result)
    appendIndependent(policy.maximumFutureClockSkewMilliseconds, to: &result)
    appendIndependent(policy.runNonceClaimDeadlineUnixMilliseconds, to: &result)
    appendIndependent(policy.runNonceClaimPolicy, to: &result)
    return result
}

private func independentCanonicalReportData(_ report: PaneShapeCoverageReport) -> Data {
    var result = Data()
    appendIndependent("MMPSRPT5", to: &result)
    appendIndependent(report.formatVersion, to: &result)
    appendIndependent(report.inventory, to: &result)
    appendIndependent(report.evidence, to: &result)
    appendIndependent(report.trustedAuditTimeUnixMilliseconds, to: &result)
    appendIndependent(report.maximumCaptureAgeMilliseconds, to: &result)
    appendIndependent(report.maximumFutureClockSkewMilliseconds, to: &result)
    appendIndependent(report.runNonceClaimDeadlineUnixMilliseconds, to: &result)
    appendIndependent(report.runNonceClaimPolicy, to: &result)
    appendIndependent(report.auditPolicySHA256.count, to: &result)
    result.append(contentsOf: report.auditPolicySHA256)
    result.append(report.highestSeverity == nil ? 0 : 1)
    if let highestSeverity = report.highestSeverity {
        result.append(highestSeverity.rawValue)
    }
    result.append(report.containsErrors ? 1 : 0)
    result.append(report.isCompleteAndValid ? 1 : 0)
    appendIndependent(report.matrix.requiredCount, to: &result)
    appendIndependent(report.matrix.completeCount, to: &result)
    appendIndependent(report.matrix.missingCount, to: &result)
    appendIndependent(report.matrix.duplicateCount, to: &result)
    appendIndependent(report.matrix.mismatchedCount, to: &result)
    appendIndependent(report.matrix.invalidCount, to: &result)
    appendIndependent(report.matrix.assertionOnlyCount, to: &result)
    result.append(report.matrix.isComplete ? 1 : 0)
    appendIndependent(report.matrix.cells.count, to: &result)
    for cell in report.matrix.cells {
        appendIndependent(cell.scenario, to: &result)
        appendIndependent(cell.expectedVisualOrder, to: &result)
        result.append(independentPaneRank(cell.expectedActivePane))
        result.append(cell.observedLayout == nil ? 0 : 1)
        if let observedLayout = cell.observedLayout {
            result.append(observedLayout.paneCount.rawValue)
            appendIndependent(observedLayout.visualOrder, to: &result)
            result.append(independentPaneRank(observedLayout.activePane))
            result.append(observedLayout.orientation.rawValue)
        }
        appendIndependent(cell.evidenceCount, to: &result)
        result.append(cell.status.rawValue)
    }
    appendIndependent(report.findings.count, to: &result)
    for finding in report.findings {
        appendIndependent(finding.id.rawValue, to: &result)
        result.append(finding.severity.rawValue)
        appendIndependent(finding.code.rawValue, to: &result)
        switch finding.subject {
        case .matrix:
            result.append(0)
        case .scenario(let scenarioID):
            result.append(1)
            appendIndependent(scenarioID.rawValue, to: &result)
        }
        appendIndependent(finding.message, to: &result)
    }
    return result
}

private func appendIndependent(_ scenario: PaneShapeScenario, to data: inout Data) {
    appendIndependent(scenario.id.rawValue, to: &data)
    data.append(scenario.paneCount.rawValue)
    data.append(independentPaneRank(scenario.activePane))
    data.append(scenario.isSwapped ? 1 : 0)
    data.append(scenario.orientation.rawValue)
}

private func appendIndependent(
    _ bindings: PaneShapeRevisionBindings,
    to data: inout Data
) {
    appendIndependent(bindings.layout, to: &data)
    appendIndependent(bindings.sources, to: &data)
    appendIndependent(bindings.comparison.comparison, to: &data)
    appendIndependent(bindings.comparison.inputs, to: &data)
    appendIndependent(bindings.comparison.result, to: &data)
    appendIndependent(bindings.comparison.sources, to: &data)
}

private func appendIndependent(
    _ sources: [PaneShapeSourceRevisionBinding],
    to data: inout Data
) {
    appendIndependent(sources.count, to: &data)
    for source in sources {
        data.append(independentPaneRank(source.pane))
        appendIndependent(source.source, to: &data)
    }
}

private func appendIndependent(_ panes: [PaneIdentity], to data: inout Data) {
    appendIndependent(panes.count, to: &data)
    data.append(contentsOf: panes.map(independentPaneRank))
}

private func appendIndependent(_ reference: PaneShapeRevisionReference, to data: inout Data) {
    appendIndependent(reference.id.rawValue, to: &data)
    appendIndependent(reference.revision, to: &data)
}

private func appendIndependent(_ value: String, to data: inout Data) {
    appendIndependent(value.utf8.count, to: &data)
    data.append(contentsOf: value.utf8)
}

private func appendIndependent(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value))
}

private func appendIndependent(_ value: UInt64, to data: inout Data) {
    for shift in stride(from: 56, through: 0, by: -8) {
        data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
}

private func appendIndependent(_ value: Int, to data: inout Data) {
    appendIndependent(UInt64(value), to: &data)
}

private func independentPaneRank(_ pane: PaneIdentity) -> UInt8 {
    switch pane {
    case .left: 0
    case .middle: 1
    case .right: 2
    }
}

private func independentLifecycleRank(_ phase: ComparisonLifecycleState.Phase) -> UInt8 {
    switch phase {
    case .empty: 0
    case .oneSideLoaded: 1
    case .loading: 2
    case .current: 3
    case .stale: 4
    case .refreshing: 5
    case .failed: 6
    case .canceled: 7
    }
}

private func makeBindingsByScenario() throws -> [PaneShapeScenarioID: PaneShapeRevisionBindings] {
    try Dictionary(
        uniqueKeysWithValues: PaneShapeCoverageMatrix.canonicalScenarios.map { scenario in
            (scenario.id, try makeBindings(for: scenario))
        }
    )
}

private func makeBindings(for scenario: PaneShapeScenario) throws -> PaneShapeRevisionBindings {
    let suffix = String(scenario.id.rawValue)
    let sources = scenario.paneCount.identities.map { pane in
        PaneShapeSourceRevisionBinding(
            pane: pane,
            source: reference("source-\(suffix)-\(paneName(pane))", 1)
        )
    }
    let comparison = try PaneShapeComparisonRevisionBinding(
        comparison: reference("comparison-\(suffix)", 1),
        inputs: reference("inputs-\(suffix)", 1),
        result: reference("result-\(suffix)", 1),
        sources: sources
    )
    return try PaneShapeRevisionBindings(
        layout: reference("layout-\(suffix)", 1),
        sources: sources,
        comparison: comparison
    )
}

private func audit(
    _ fixture: MatrixFixture,
    inventory: PaneShapeCoverageInventory? = nil,
    evidence: PaneShapeEvidenceBundle? = nil,
    limits: PaneShapeCoverageLimits = .default,
    claims: ClaimRecorder,
    maximumCaptureAgeMilliseconds: UInt64 = 100,
    maximumFutureClockSkewMilliseconds: UInt64 = 50,
    captureResolver: PaneShapeCoverageMatrix.CaptureResolver? = nil,
    cancellationCheck: @escaping PaneShapeCoverageMatrix.CancellationCheck = { false }
) throws -> PaneShapeCoverageResult {
    let resolver = captureResolver ?? CaptureResolverProbe(captures: fixture.captures).resolver
    return try PaneShapeCoverageMatrix.audit(
        inventory: inventory ?? fixture.inventory,
        evidence: evidence ?? fixture.evidence,
        limits: limits,
        auditPolicy: makePolicy(
            fixture,
            claims: claims,
            maximumCaptureAgeMilliseconds: maximumCaptureAgeMilliseconds,
            maximumFutureClockSkewMilliseconds: maximumFutureClockSkewMilliseconds
        ),
        captureResolver: resolver,
        cancellationCheck: cancellationCheck
    )
}

private func makePolicy(
    _ fixture: MatrixFixture,
    claims: ClaimRecorder,
    trustedTime: UInt64? = nil,
    maximumCaptureAgeMilliseconds: UInt64 = 100,
    maximumFutureClockSkewMilliseconds: UInt64 = 50,
    deadline: UInt64? = nil,
    claimPolicy: PaneShapeRevisionReference? = nil
) -> PaneShapeAuditPolicy {
    PaneShapeAuditPolicy(
        trustedAuditTimeUnixMilliseconds: trustedTime ?? fixture.trustedTime,
        maximumCaptureAgeMilliseconds: maximumCaptureAgeMilliseconds,
        maximumFutureClockSkewMilliseconds: maximumFutureClockSkewMilliseconds,
        runNonceClaimDeadlineUnixMilliseconds: deadline ?? fixture.deadline,
        runNonceClaimPolicy: claimPolicy ?? fixture.claimPolicy,
        claimRunNonces: { policy, nonces, context in
            claims.claim(policy: policy, nonces: nonces, context: context)
        }
    )
}

private func replacingInventory(
    _ inventory: PaneShapeCoverageInventory,
    reference: PaneShapeRevisionReference? = nil,
    build: PaneShapeRevisionReference? = nil,
    buildArtifactSHA256: [UInt8]? = nil,
    trustedCollectors: [PaneShapeTrustedCollector]? = nil,
    requirements: [PaneShapeCoverageRequirement]? = nil
) -> PaneShapeCoverageInventory {
    PaneShapeCoverageInventory(
        reference: reference ?? inventory.reference,
        build: build ?? inventory.build,
        buildArtifactSHA256: buildArtifactSHA256 ?? inventory.buildArtifactSHA256,
        trustedCollectors: trustedCollectors ?? inventory.trustedCollectors,
        requirements: requirements ?? inventory.requirements
    )
}

private func replacingEvidence(
    _ evidence: PaneShapeEvidenceBundle,
    reference: PaneShapeRevisionReference? = nil,
    inventory: PaneShapeRevisionReference? = nil,
    build: PaneShapeRevisionReference? = nil,
    observations: [PaneShapeProductionEvidence]? = nil
) -> PaneShapeEvidenceBundle {
    PaneShapeEvidenceBundle(
        reference: reference ?? evidence.reference,
        inventory: inventory ?? evidence.inventory,
        build: build ?? evidence.build,
        observations: observations ?? evidence.observations
    )
}

private func replacingObservation(
    in evidence: PaneShapeEvidenceBundle,
    at index: Int,
    with observation: PaneShapeProductionEvidence
) -> PaneShapeEvidenceBundle {
    var observations = evidence.observations
    observations[index] = observation
    return replacingEvidence(evidence, observations: observations)
}

private func replacingObservation(
    _ observation: PaneShapeProductionEvidence,
    scenarioID: PaneShapeScenarioID? = nil,
    bindings: PaneShapeRevisionBindings? = nil,
    layout: PaneShapeLayoutObservation? = nil,
    commandState: PaneShapeCommandStateObservation? = nil,
    comparisonPhase: ComparisonLifecycleState.Phase? = nil,
    hasCurrentComparisonResult: Bool? = nil,
    origin: PaneShapeEvidenceOrigin? = nil,
    provenance: OptionalReplacement<PaneShapeEvidenceProvenance> = .keep
) -> PaneShapeProductionEvidence {
    let replacementProvenance: PaneShapeEvidenceProvenance?
    switch provenance {
    case .keep:
        replacementProvenance = observation.provenance
    case .replace(let value):
        replacementProvenance = value
    }
    return PaneShapeProductionEvidence(
        scenarioID: scenarioID ?? observation.scenarioID,
        bindings: bindings ?? observation.bindings,
        layout: layout ?? observation.layout,
        commandState: commandState ?? observation.commandState,
        comparisonPhase: comparisonPhase ?? observation.comparisonPhase,
        hasCurrentComparisonResult: hasCurrentComparisonResult ?? observation.hasCurrentComparisonResult,
        origin: origin ?? observation.origin,
        provenance: replacementProvenance
    )
}

private func replacingProvenance(
    _ provenance: PaneShapeEvidenceProvenance,
    build: PaneShapeRevisionReference? = nil,
    inventory: PaneShapeRevisionReference? = nil,
    collector: PaneShapeRevisionReference? = nil,
    capturedAtUnixMilliseconds: UInt64? = nil,
    runNonce: [UInt8]? = nil,
    artifactSHA256: [UInt8]? = nil,
    captureSHA256: [UInt8]? = nil,
    collectorSignature: [UInt8]? = nil,
    source: String? = nil
) -> PaneShapeEvidenceProvenance {
    PaneShapeEvidenceProvenance(
        build: build ?? provenance.build,
        inventory: inventory ?? provenance.inventory,
        collector: collector ?? provenance.collector,
        capturedAtUnixMilliseconds: capturedAtUnixMilliseconds ?? provenance.capturedAtUnixMilliseconds,
        runNonce: runNonce ?? provenance.runNonce,
        artifactSHA256: artifactSHA256 ?? provenance.artifactSHA256,
        captureSHA256: captureSHA256 ?? provenance.captureSHA256,
        collectorSignature: collectorSignature ?? provenance.collectorSignature,
        source: source ?? provenance.source
    )
}

private func replacingLayoutReference(
    _ bindings: PaneShapeRevisionBindings,
    with layout: PaneShapeRevisionReference
) throws -> PaneShapeRevisionBindings {
    try PaneShapeRevisionBindings(
        layout: layout,
        sources: bindings.sources,
        comparison: bindings.comparison
    )
}

private func limits(
    maximumTrustedCollectors: Int = PaneShapeCoverageLimits.default.maximumTrustedCollectors,
    maximumObservations: Int = PaneShapeCoverageLimits.default.maximumObservations,
    maximumStringUTF8Bytes: Int = PaneShapeCoverageLimits.default.maximumStringUTF8Bytes,
    maximumTotalStringUTF8Bytes: Int = PaneShapeCoverageLimits.default.maximumTotalStringUTF8Bytes,
    maximumWorkUnits: Int = PaneShapeCoverageLimits.default.maximumWorkUnits,
    maximumFindings: Int = PaneShapeCoverageLimits.default.maximumFindings,
    maximumCanonicalBytes: Int = PaneShapeCoverageLimits.default.maximumCanonicalBytes,
    cancellationCheckInterval: Int = PaneShapeCoverageLimits.default.cancellationCheckInterval
) -> PaneShapeCoverageLimits {
    PaneShapeCoverageLimits(
        maximumTrustedCollectors: maximumTrustedCollectors,
        maximumObservations: maximumObservations,
        maximumStringUTF8Bytes: maximumStringUTF8Bytes,
        maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
        maximumWorkUnits: maximumWorkUnits,
        maximumFindings: maximumFindings,
        maximumCanonicalBytes: maximumCanonicalBytes,
        cancellationCheckInterval: cancellationCheckInterval
    )
}

private func minimumPassingLimit(
    lowerBound: Int,
    upperBound: Int,
    passes: (Int) throws -> Bool
) throws -> Int {
    var lower = lowerBound
    var upper = upperBound
    guard try passes(upper) else {
        XCTFail("Upper bound must pass")
        return upper
    }
    while lower < upper {
        let midpoint = lower + (upper - lower) / 2
        if try passes(midpoint) {
            upper = midpoint
        } else {
            lower = midpoint + 1
        }
    }
    return lower
}

private func codes(
    in result: PaneShapeCoverageResult,
    scenarioID: PaneShapeScenarioID
) -> [PaneShapeFindingCode] {
    result.report.findings.compactMap { finding in
        guard case .scenario(scenarioID) = finding.subject else { return nil }
        return finding.code
    }
}

private func collector(_ key: Curve25519.Signing.PrivateKey) -> PaneShapeTrustedCollector {
    PaneShapeTrustedCollector(
        reference: reference("collector", 1),
        ed25519PublicKey: Array(key.publicKey.rawRepresentation)
    )
}

private func reference(_ id: String, _ revision: UInt64) -> PaneShapeRevisionReference {
    PaneShapeRevisionReference(id: PaneShapeStableID(rawValue: id), revision: revision)
}

private func digest(_ value: String) -> [UInt8] {
    Array(SHA256.hash(data: Data(value.utf8)))
}

private func paneName(_ pane: PaneIdentity) -> String {
    switch pane {
    case .left: "left"
    case .middle: "middle"
    case .right: "right"
    }
}

private func orientationName(_ orientation: PaneShapeOrientation) -> String {
    switch orientation {
    case .vertical: "vertical"
    case .horizontal: "horizontal"
    }
}

private func mirrorDescription(_ value: Any) -> String {
    Mirror(reflecting: value).children.map { child in
        "\(child.label ?? "")=\(String(describing: child.value))"
    }.joined(separator: ",")
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func assertError(
    _ expected: PaneShapeCoverageError,
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: () throws -> Void
) {
    XCTAssertThrowsError(try operation(), file: file, line: line) { error in
        XCTAssertEqual(error as? PaneShapeCoverageError, expected, file: file, line: line)
    }
}
