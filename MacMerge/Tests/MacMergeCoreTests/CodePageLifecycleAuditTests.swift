import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class CodePageLifecycleAuditTests: XCTestCase {
    func testCanonicalSupportedInventoryMappingsAndOracleCardinalities() throws {
        let supported = Audit.SupportedCodePage.allCases

        XCTAssertEqual(supported.map(\.rawValue), [932, 1250, 1251, 1252, 1253, 1254, 1255, 50220, 51932])
        XCTAssertEqual(supported.map(\.id.rawValue), supported.map(\.rawValue))
        XCTAssertEqual(supported.sorted(), supported)
        XCTAssertEqual(
            supported.map(\.textFileEncoding.rawValue),
            [
                "shiftJIS", "windows1250", "windows1251", "windows1252", "windows1253",
                "windows1254", "windows1255", "iso2022JP", "japaneseEUC"
            ]
        )
        XCTAssertEqual(
            supported.map(\.sessionEncoding.rawValue),
            [
                "shiftJIS", "windows1250", "windows1251", "windows1252", "windows1253",
                "windows1254", "windows1255", "iso2022JP", "japaneseEUC"
            ]
        )
        XCTAssertEqual(
            supported.map(\.expectedMappingCardinality),
            [7_915, 251, 255, 251, 239, 249, 233, 7_007, 7_070]
        )
        XCTAssertEqual(Audit.canonicalCodecSessionMappings.map(\.codePage), supported.map(\.id))
        XCTAssertEqual(
            Audit.canonicalCodecSessionMappings.map(\.codecEncodingIdentifier),
            supported.map(\.textFileEncoding.rawValue)
        )
        XCTAssertEqual(
            Audit.canonicalCodecSessionMappings.map(\.sessionEncodingIdentifier),
            supported.map(\.sessionEncoding.rawValue)
        )

        let harness = try AuditHarness()
        XCTAssertEqual(harness.fixtures.map(\.codePage), supported.map(\.id))
        for (fixture, codePage) in zip(harness.fixtures, supported) {
            let oracle = fixture.mappingOracle
            XCTAssertFalse(oracle.sourceIdentifier.isEmpty)
            XCTAssertFalse(oracle.sourceArtifactSHA256.bytes.allSatisfy { $0 == 0 })
            XCTAssertFalse(oracle.mappingTableSHA256.bytes.allSatisfy { $0 == 0 })
            XCTAssertEqual(oracle.codePage, codePage.id)
            XCTAssertEqual(oracle.mappingCardinality, codePage.expectedMappingCardinality)
            XCTAssertEqual(
                oracle.fixtureScalarCommitments,
                Audit.FixtureScalarCommitments(expectation: fixture.expectation)
            )
            XCTAssertEqual(oracle.signature.bytes.count, 64)
        }
    }

    func testVerifierAcceptsCompleteCallerSuppliedSignedLifecycleWithoutExecutingCodecs() throws {
        let harness = try AuditHarness()
        let evidence = try makeEvidence(for: harness)
        let result = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let expectedStageCount = Audit.SupportedCodePage.allCases.count * Audit.Stage.allCases.count

        XCTAssertEqual(harness.plan.requests.count, expectedStageCount)
        XCTAssertEqual(harness.plan.receipt.requestCount, expectedStageCount)
        XCTAssertEqual(harness.plan.requests.map(\.ordinal), Array(0..<expectedStageCount))
        XCTAssertEqual(
            harness.plan.requests.map(\.stage),
            Audit.SupportedCodePage.allCases.flatMap { _ in Audit.Stage.allCases }
        )
        XCTAssertTrue(harness.plan.preflightFindings.isEmpty)
        XCTAssertEqual(harness.plan.fixtureVerifications.count, Audit.SupportedCodePage.allCases.count)
        XCTAssertTrue(harness.plan.fixtureVerifications.allSatisfy(\.isSupported))
        XCTAssertTrue(harness.plan.fixtureVerifications.allSatisfy(\.isMappingOracleVerified))
        XCTAssertTrue(harness.plan.fixtureVerifications.allSatisfy(\.isFixtureValid))
        XCTAssertEqual(harness.manifest.codec, harness.trustPolicy.approvedCodecArtifact.codec)
        XCTAssertEqual(
            harness.manifest.codecArtifactSHA256,
            harness.trustPolicy.approvedCodecArtifact.artifactSHA256
        )
        XCTAssertTrue(harness.manifest.approvedExecutionLineages.contains(harness.primaryLineage))
        XCTAssertEqual(harness.primaryLineage.signerID, harness.measurementSignerID)
        XCTAssertFalse(harness.primaryLineage.buildSHA256.bytes.allSatisfy { $0 == 0 })

        XCTAssertEqual(evidence.stages.count, expectedStageCount)
        for fixture in harness.fixtures {
            let stages = evidence.stages.filter { $0.fixture == fixture.reference }
            XCTAssertEqual(stages.map(\.requestedStage), Audit.Stage.allCases)
            var priorDigest: Audit.SHA256Digest?
            for (offset, stage) in stages.enumerated() {
                let attestation = try XCTUnwrap(stage.attestation)
                XCTAssertEqual(attestation.execution.lineage, harness.primaryLineage)
                XCTAssertEqual(attestation.execution.runSHA256, harness.runSHA256)
                XCTAssertEqual(attestation.signature.signerID, harness.measurementSignerID)
                XCTAssertEqual(attestation.signature.bytes.count, 64)
                XCTAssertEqual(attestation.monotonicSequence, UInt64(offset + 1))
                XCTAssertEqual(attestation.previousEvidenceSHA256, priorDigest)
                priorDigest = try Audit.stageEvidenceSHA256(stage, cancellationCheck: { false })
            }
        }

        XCTAssertEqual(result.report.formatVersion, Audit.reportFormatVersion)
        XCTAssertEqual(
            Audit.Report.scopeStatement,
            "Deterministic validation of bounded, caller-supplied, cryptographically bound code-page lifecycle measurements; not codec, filesystem, comparison-engine, or UI execution."
        )
        XCTAssertEqual(result.receipt.formatVersion, Audit.reportFormatVersion)
        XCTAssertEqual(result.report.completeness.requiredCount, expectedStageCount)
        XCTAssertEqual(result.report.completeness.completeCount, expectedStageCount)
        XCTAssertTrue(result.report.completeness.isComplete)
        XCTAssertTrue(result.report.findings.isEmpty)
        XCTAssertTrue(result.report.isCompleteAndValid)
        XCTAssertFalse(result.report.containsErrors)
        XCTAssertNil(result.report.highestSeverity)
        XCTAssertEqual(result.receipt.manifestSHA256, harness.plan.manifestSHA256)
        XCTAssertEqual(result.receipt.requestSetSHA256, harness.plan.receipt.requestSetSHA256)
        XCTAssertEqual(result.receipt.trustPolicySHA256, harness.plan.receipt.trustPolicySHA256)
        XCTAssertEqual(result.receipt.requiredStageCount, expectedStageCount)
        XCTAssertEqual(result.receipt.completeStageCount, expectedStageCount)
        XCTAssertEqual(result.receipt.findingCount, 0)
        XCTAssertFalse(result.receipt.evidenceSHA256.bytes.allSatisfy { $0 == 0 })
        XCTAssertFalse(result.receipt.oracleSetSHA256.bytes.allSatisfy { $0 == 0 })
        XCTAssertTrue(result.receipt.recordsCompleteCoverage)
    }

    func testCanonicalPrehashAndSignatureGoldenContract() throws {
        let harness = try AuditHarness()
        let fixture = try XCTUnwrap(harness.fixtures.first)
        let oraclePrehash = try Audit.mappingOracleSigningPrehash(fixture, cancellationCheck: { false })
        let load = Audit.StageEvidence(
            bundle: reference("golden-evidence", revision: 9),
            bundleManifestSHA256: digest("golden-manifest"),
            fixture: fixture.reference,
            codePage: fixture.codePage,
            requestedStage: .load,
            requestSHA256: digest("golden-request"),
            observation: matchingObservation(for: fixture, stage: .load),
            origin: .automatedMeasurement,
            attestation: Audit.ExecutionAttestation(
                execution: Audit.ExecutionRun(
                    lineage: harness.primaryLineage,
                    runSHA256: digest("golden-run")
                ),
                monotonicSequence: 17,
                previousEvidenceSHA256: nil,
                signature: Audit.Signature(signerID: harness.measurementSignerID, bytes: [])
            )
        )
        let executionPrehash = try Audit.executionSigningPrehash(load, cancellationCheck: { false })
        let stageHash = try Audit.stageEvidenceSHA256(load, cancellationCheck: { false })

        XCTAssertEqual(
            Audit.signingPrehashContract,
            "Curve25519.Signing signature over a 32-byte SHA-256 digest of domain-separated canonical V3 payload bytes"
        )
        XCTAssertEqual(
            Audit.unicodeHashContract,
            "SHA-256 over Unicode scalar values encoded as unsigned 32-bit big-endian integers"
        )
        XCTAssertEqual(oraclePrehash.bytes.count, 32)
        XCTAssertEqual(executionPrehash.bytes.count, 32)
        XCTAssertEqual(stageHash.bytes.count, 32)
        XCTAssertTrue(
            harness.oracleKey.publicKey.isValidSignature(
                Data(fixture.mappingOracle.signature.bytes),
                for: Data(oraclePrehash.bytes)
            )
        )
        XCTAssertEqual(hex(oraclePrehash), "2e6b23cc76102a909d3671d4538d1968156ec6fbf4eda0b7137a06483a366f56")
        XCTAssertEqual(hex(executionPrehash), "eede96ec0a5d33decdcef7f88528f588f58d3f991a93aec592f92467cef16883")
        XCTAssertEqual(hex(stageHash), "5d50d9c447baf0a21df88c0b4d0ba229f5b66f7010e2041d45981b3ce46280b2")
        let replacedOracleSignature = Audit.Fixture(
            reference: fixture.reference,
            codePage: fixture.codePage,
            fixtureArtifactSHA256: fixture.fixtureArtifactSHA256,
            mappingOracle: replacingOracleSignature(fixture.mappingOracle, bytes: [0xAA]),
            expectation: fixture.expectation
        )
        XCTAssertEqual(
            try Audit.mappingOracleSigningPrehash(replacedOracleSignature, cancellationCheck: { false }),
            oraclePrehash
        )
        let replacedExecutionSignature = replacingSignature(load, bytes: [0xBB])
        XCTAssertEqual(
            try Audit.executionSigningPrehash(replacedExecutionSignature, cancellationCheck: { false }),
            executionPrehash
        )
        XCTAssertNotEqual(
            try Audit.stageEvidenceSHA256(replacedExecutionSignature, cancellationCheck: { false }),
            stageHash
        )
    }

    func testEveryStageExecutionPrehashBindsEachObservationField() throws {
        let harness = try AuditHarness()
        let fixture = try fixture(.cp932, in: harness.fixtures)
        let alternate = content(bytes: [0x5A], scalars: [0x5A])
        let alternateAfter = content(bytes: [0x41, 0x7A], scalars: [0x41, 0x7A])
        let alternateEdit = Audit.UnicodeScalarEdit(
            unchangedPrefix: [0x41],
            removedScalars: [],
            insertedScalars: [0x7A],
            unchangedSuffix: []
        )
        let otherEncoding = Audit.SupportedCodePage.cp1250.id

        for request in harness.plan.requests where request.fixture == fixture.reference {
            let original = unsignedEvidence(
                bundle: reference("prehash-evidence", revision: 1),
                request: request,
                observation: matchingObservation(for: fixture, stage: request.stage),
                lineage: harness.primaryLineage,
                runSHA256: harness.runSHA256,
                signerID: harness.measurementSignerID
            )
            let mutations: [Audit.Observation]
            switch original.observation {
            case .load(let value):
                mutations = [
                    .load(
                        Audit.LoadObservation(
                            automaticDetection: .rejected,
                            explicitlySelectedEncoding: value.explicitlySelectedEncoding,
                            source: value.source,
                            loaded: value.loaded
                        )),
                    .load(
                        Audit.LoadObservation(
                            automaticDetection: value.automaticDetection,
                            explicitlySelectedEncoding: otherEncoding,
                            source: value.source,
                            loaded: value.loaded
                        )),
                    .load(
                        Audit.LoadObservation(
                            automaticDetection: value.automaticDetection,
                            explicitlySelectedEncoding: value.explicitlySelectedEncoding,
                            source: alternate,
                            loaded: value.loaded
                        )),
                    .load(
                        Audit.LoadObservation(
                            automaticDetection: value.automaticDetection,
                            explicitlySelectedEncoding: value.explicitlySelectedEncoding,
                            source: value.source,
                            loaded: alternate
                        ))
                ]
            case .compare(let value):
                mutations = [
                    .compare(
                        Audit.CompareObservation(
                            left: alternate,
                            right: value.right,
                            unicodeEqual: value.unicodeEqual,
                            differenceCount: value.differenceCount
                        )),
                    .compare(
                        Audit.CompareObservation(
                            left: value.left,
                            right: alternate,
                            unicodeEqual: value.unicodeEqual,
                            differenceCount: value.differenceCount
                        )),
                    .compare(
                        Audit.CompareObservation(
                            left: value.left,
                            right: value.right,
                            unicodeEqual: false,
                            differenceCount: value.differenceCount
                        )),
                    .compare(
                        Audit.CompareObservation(
                            left: value.left,
                            right: value.right,
                            unicodeEqual: value.unicodeEqual,
                            differenceCount: 1
                        ))
                ]
            case .edit(let value):
                let byteOnlyAfter = Audit.ContentHash(bytes: alternate.bytes, unicode: value.after.unicode)
                mutations = [
                    .edit(
                        Audit.EditObservation(
                            before: Audit.ContentHash(
                                bytes: alternate.bytes,
                                unicode: value.before.unicode
                            ),
                            after: value.after,
                            mutationApplied: value.mutationApplied,
                            unicodeScalarDelta: value.unicodeScalarDelta
                        )),
                    .edit(
                        Audit.EditObservation(
                            before: value.before,
                            after: byteOnlyAfter,
                            mutationApplied: value.mutationApplied,
                            unicodeScalarDelta: value.unicodeScalarDelta
                        )),
                    .edit(
                        Audit.EditObservation(
                            before: value.before,
                            after: value.after,
                            mutationApplied: false,
                            unicodeScalarDelta: value.unicodeScalarDelta
                        )),
                    .edit(
                        Audit.EditObservation(
                            before: value.before,
                            after: alternateAfter,
                            mutationApplied: value.mutationApplied,
                            unicodeScalarDelta: alternateEdit
                        ))
                ]
            case .save(let value):
                mutations = [
                    .save(
                        Audit.SaveObservation(
                            edited: alternate,
                            saved: value.saved,
                            selectedEncoding: value.selectedEncoding
                        )),
                    .save(
                        Audit.SaveObservation(
                            edited: value.edited,
                            saved: alternate,
                            selectedEncoding: value.selectedEncoding
                        )),
                    .save(
                        Audit.SaveObservation(
                            edited: value.edited,
                            saved: value.saved,
                            selectedEncoding: otherEncoding
                        ))
                ]
            case .reload(let value):
                mutations = [
                    .reload(
                        Audit.ReloadObservation(
                            saved: alternate,
                            reloaded: value.reloaded,
                            selectedEncoding: value.selectedEncoding
                        )),
                    .reload(
                        Audit.ReloadObservation(
                            saved: value.saved,
                            reloaded: alternate,
                            selectedEncoding: value.selectedEncoding
                        )),
                    .reload(
                        Audit.ReloadObservation(
                            saved: value.saved,
                            reloaded: value.reloaded,
                            selectedEncoding: otherEncoding
                        ))
                ]
            case .byteComparison(let value):
                mutations = [
                    .byteComparison(
                        Audit.ByteComparisonObservation(
                            saved: alternate,
                            reloaded: value.reloaded,
                            bytesEqual: value.bytesEqual
                        )),
                    .byteComparison(
                        Audit.ByteComparisonObservation(
                            saved: value.saved,
                            reloaded: alternate,
                            bytesEqual: value.bytesEqual
                        )),
                    .byteComparison(
                        Audit.ByteComparisonObservation(
                            saved: value.saved,
                            reloaded: value.reloaded,
                            bytesEqual: false
                        ))
                ]
            }
            let originalPrehash = try Audit.executionSigningPrehash(
                original,
                cancellationCheck: { false }
            )
            for mutation in mutations {
                let changed = replacingStageEvidence(original, observation: mutation)
                XCTAssertNotEqual(
                    try Audit.executionSigningPrehash(changed, cancellationCheck: { false }),
                    originalPrehash,
                    "Missing prehash binding for \(request.stage) mutation \(mutation)"
                )
            }
        }
    }

    func testRequestAndReceiptDigestsAreSensitiveAndOrderIndependent() throws {
        let harness = try AuditHarness()
        let originalFixture = try fixture(.cp932, in: harness.fixtures)
        let changedFixture = try signedCopy(
            originalFixture,
            sourceIdentifier: "changed-independent-oracle-source",
            signerID: harness.oracleSignerID,
            key: harness.oracleKey
        )
        let changedManifest = replacingManifest(
            harness.manifest,
            fixtures: replacingFixture(originalFixture, with: changedFixture, in: harness.fixtures)
        )
        let changedPlan = try Audit.prepare(
            manifest: changedManifest,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let originalRequests = harness.plan.requests.filter { $0.codePage == originalFixture.codePage }
        let changedRequests = changedPlan.requests.filter { $0.codePage == originalFixture.codePage }

        XCTAssertEqual(originalRequests.count, Audit.Stage.allCases.count)
        XCTAssertEqual(changedRequests.count, originalRequests.count)
        XCTAssertNotEqual(originalRequests.first?.fixtureSHA256, changedRequests.first?.fixtureSHA256)
        XCTAssertNotEqual(originalRequests.first?.mappingOracleSHA256, changedRequests.first?.mappingOracleSHA256)
        XCTAssertNotEqual(originalRequests.map(\.requestSHA256), changedRequests.map(\.requestSHA256))
        XCTAssertNotEqual(harness.plan.receipt.requestSetSHA256, changedPlan.receipt.requestSetSHA256)

        let evidence = try makeEvidence(for: harness)
        let originalResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let semanticMutation = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id, request.stage == .compare
            else { return }
            if case .compare(let value) = draft.observation {
                draft.observation = .compare(
                    Audit.CompareObservation(
                        left: value.left,
                        right: value.right,
                        unicodeEqual: false,
                        differenceCount: value.differenceCount
                    ))
            }
        }
        let semanticResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: semanticMutation,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertNotEqual(originalResult.receipt.evidenceSHA256, semanticResult.receipt.evidenceSHA256)
        XCTAssertEqual(originalResult.receipt.oracleSetSHA256, semanticResult.receipt.oracleSetSHA256)

        let changedEvidence = try makeEvidence(
            for: harness,
            fixtures: changedManifest.fixtures,
            manifest: changedManifest,
            plan: changedPlan
        )
        let changedResult = try Audit.evaluate(
            plan: changedPlan,
            evidence: changedEvidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertNotEqual(originalResult.receipt.oracleSetSHA256, changedResult.receipt.oracleSetSHA256)

        let reversedManifest = replacingManifest(
            harness.manifest,
            fixtures: Array(harness.fixtures.reversed())
        )
        let reversedPlan = try Audit.prepare(
            manifest: reversedManifest,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let reversedEvidence = try makeEvidence(
            for: harness,
            fixtures: reversedManifest.fixtures,
            manifest: reversedManifest,
            plan: reversedPlan
        )
        let reversedResult = try Audit.evaluate(
            plan: reversedPlan,
            evidence: reversedEvidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertEqual(originalResult.receipt.oracleSetSHA256, reversedResult.receipt.oracleSetSHA256)
        XCTAssertEqual(
            originalResult.receipt.evidenceSHA256,
            try Audit.evaluate(
                plan: harness.plan,
                evidence: replacingStages(evidence, stages: evidence.stages.reversed()),
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            ).receipt.evidenceSHA256
        )
    }

    func testOracleSignatureCoversFixtureScalarArtifactAndCompleteExpectation() throws {
        let harness = try AuditHarness()
        let original = try XCTUnwrap(harness.fixtures.first)
        let originalPrehash = try Audit.mappingOracleSigningPrehash(original, cancellationCheck: { false })
        let changedCommitments = Audit.FixtureScalarCommitments(
            original: Audit.UnicodeHash(
                scalarCount: original.expectation.original.unicode.scalarCount,
                sha256: digest("changed-original-scalars")
            ),
            edited: original.mappingOracle.fixtureScalarCommitments.edited,
            saved: original.mappingOracle.fixtureScalarCommitments.saved,
            reloaded: original.mappingOracle.fixtureScalarCommitments.reloaded
        )
        let alternateEdited = content(bytes: [0x41, 0x3F], scalars: [0x41, 0x3F])
        let alternateExpectation = Audit.FixtureExpectation(
            original: original.expectation.original,
            edited: alternateEdited,
            saved: alternateEdited,
            reloaded: alternateEdited,
            selection: original.expectation.selection,
            intendedEdit: Audit.UnicodeScalarEdit(
                unchangedPrefix: [0x41],
                removedScalars: [],
                insertedScalars: [0x3F],
                unchangedSuffix: []
            )
        )
        let mutations = [
            Audit.Fixture(
                reference: reference("changed-fixture", revision: 1),
                codePage: original.codePage,
                fixtureArtifactSHA256: original.fixtureArtifactSHA256,
                mappingOracle: original.mappingOracle,
                expectation: original.expectation
            ),
            Audit.Fixture(
                reference: original.reference,
                codePage: original.codePage,
                fixtureArtifactSHA256: digest("changed-fixture-artifact"),
                mappingOracle: original.mappingOracle,
                expectation: original.expectation
            ),
            Audit.Fixture(
                reference: original.reference,
                codePage: original.codePage,
                fixtureArtifactSHA256: original.fixtureArtifactSHA256,
                mappingOracle: replacingOracle(
                    original.mappingOracle,
                    sourceArtifactSHA256: digest("changed-oracle-artifact")
                ),
                expectation: original.expectation
            ),
            Audit.Fixture(
                reference: original.reference,
                codePage: original.codePage,
                fixtureArtifactSHA256: original.fixtureArtifactSHA256,
                mappingOracle: replacingOracle(
                    original.mappingOracle,
                    fixtureScalarCommitments: changedCommitments
                ),
                expectation: original.expectation
            ),
            Audit.Fixture(
                reference: original.reference,
                codePage: original.codePage,
                fixtureArtifactSHA256: original.fixtureArtifactSHA256,
                mappingOracle: original.mappingOracle,
                expectation: alternateExpectation
            )
        ]

        for mutation in mutations {
            let changedPrehash = try Audit.mappingOracleSigningPrehash(mutation, cancellationCheck: { false })
            XCTAssertNotEqual(changedPrehash, originalPrehash)
            XCTAssertFalse(
                harness.oracleKey.publicKey.isValidSignature(
                    Data(mutation.mappingOracle.signature.bytes),
                    for: Data(changedPrehash.bytes)
                )
            )
            let manifest = replacingManifest(
                harness.manifest,
                fixtures: replacingFixture(original, with: mutation, in: harness.fixtures)
            )
            let plan = try Audit.prepare(
                manifest: manifest,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            XCTAssertTrue(plan.preflightFindings.contains { $0.code == .unverifiedMappingOracle })
        }
    }

    func testOraclePrehashBindsEveryIndependentProvenanceAndExpectationField() throws {
        let harness = try AuditHarness()
        let original = try fixture(.cp932, in: harness.fixtures)
        let old = original.expectation
        let changedBytes = Audit.ByteHash(byteCount: 1, sha256: digest("changed-content-bytes"))
        let contentMutations = [old.original, old.edited, old.saved, old.reloaded].map {
            Audit.ContentHash(bytes: changedBytes, unicode: $0.unicode)
        }
        let commitmentMutations = [
            Audit.FixtureScalarCommitments(
                original: Audit.UnicodeHash(
                    scalarCount: old.original.unicode.scalarCount,
                    sha256: digest("changed-original-commitment")
                ),
                edited: old.edited.unicode,
                saved: old.saved.unicode,
                reloaded: old.reloaded.unicode
            ),
            Audit.FixtureScalarCommitments(
                original: old.original.unicode,
                edited: Audit.UnicodeHash(
                    scalarCount: old.edited.unicode.scalarCount,
                    sha256: digest("changed-edited-commitment")
                ),
                saved: old.saved.unicode,
                reloaded: old.reloaded.unicode
            ),
            Audit.FixtureScalarCommitments(
                original: old.original.unicode,
                edited: old.edited.unicode,
                saved: Audit.UnicodeHash(
                    scalarCount: old.saved.unicode.scalarCount,
                    sha256: digest("changed-saved-commitment")
                ),
                reloaded: old.reloaded.unicode
            ),
            Audit.FixtureScalarCommitments(
                original: old.original.unicode,
                edited: old.edited.unicode,
                saved: old.saved.unicode,
                reloaded: Audit.UnicodeHash(
                    scalarCount: old.reloaded.unicode.scalarCount,
                    sha256: digest("changed-reloaded-commitment")
                )
            )
        ]
        let mutations =
            [
                replacingFixture(original, reference: reference("changed-fixture-reference", revision: 1)),
                replacingFixture(original, fixtureArtifactSHA256: digest("changed-fixture-artifact")),
                replacingFixture(
                    original,
                    mappingOracle: replacingOracle(
                        original.mappingOracle,
                        reference: reference("changed-oracle-reference", revision: 2)
                    )
                ),
                replacingFixture(
                    original,
                    mappingOracle: replacingOracle(
                        original.mappingOracle,
                        codePage: Audit.SupportedCodePage.cp1250.id,
                        mappingCardinality: Audit.SupportedCodePage.cp1250.expectedMappingCardinality
                    )
                ),
                replacingFixture(
                    original,
                    mappingOracle: replacingOracle(
                        original.mappingOracle,
                        sourceIdentifier: "changed-source-identifier"
                    )
                ),
                replacingFixture(
                    original,
                    mappingOracle: replacingOracle(
                        original.mappingOracle,
                        sourceArtifactSHA256: digest("changed-source-artifact")
                    )
                ),
                replacingFixture(
                    original,
                    mappingOracle: replacingOracle(
                        original.mappingOracle,
                        mappingTableSHA256: digest("changed-mapping-table")
                    )
                ),
                replacingFixture(
                    original,
                    mappingOracle: replacingOracle(
                        original.mappingOracle,
                        signerID: stableID("changed-oracle-signer")
                    )
                ),
                replacingFixture(
                    original,
                    expectation: replacingExpectation(old, original: contentMutations[0])
                ),
                replacingFixture(
                    original,
                    expectation: replacingExpectation(old, edited: contentMutations[1])
                ),
                replacingFixture(
                    original,
                    expectation: replacingExpectation(old, saved: contentMutations[2])
                ),
                replacingFixture(
                    original,
                    expectation: replacingExpectation(old, reloaded: contentMutations[3])
                ),
                replacingFixture(
                    original,
                    expectation: replacingExpectation(
                        old,
                        selection: Audit.SelectionExpectation(
                            automaticDetection: .ambiguous([
                                Audit.SupportedCodePage.cp932.id,
                                Audit.SupportedCodePage.cp1250.id
                            ]),
                            explicitSelection: old.selection.explicitSelection
                        )
                    )
                ),
                replacingFixture(
                    original,
                    expectation: replacingExpectation(
                        old,
                        selection: Audit.SelectionExpectation(
                            automaticDetection: old.selection.automaticDetection,
                            explicitSelection: Audit.SupportedCodePage.cp1250.id
                        )
                    )
                )
            ]
            + commitmentMutations.map {
                replacingFixture(
                    original,
                    mappingOracle: replacingOracle(
                        original.mappingOracle,
                        fixtureScalarCommitments: $0
                    )
                )
            }
        let originalPrehash = try Audit.mappingOracleSigningPrehash(
            original,
            cancellationCheck: { false }
        )

        for mutation in mutations {
            XCTAssertNotEqual(
                try Audit.mappingOracleSigningPrehash(mutation, cancellationCheck: { false }),
                originalPrehash
            )
        }
    }

    func testOracleRejectsEmptyProvenanceZeroDigestAndInexactCardinality() throws {
        let harness = try AuditHarness()

        for (fixture, codePage) in zip(harness.fixtures, Audit.SupportedCodePage.allCases) {
            let wrongCardinality = Audit.Fixture(
                reference: fixture.reference,
                codePage: fixture.codePage,
                fixtureArtifactSHA256: fixture.fixtureArtifactSHA256,
                mappingOracle: replacingOracle(
                    fixture.mappingOracle,
                    mappingCardinality: codePage.expectedMappingCardinality + 1
                ),
                expectation: fixture.expectation
            )
            assertAuditError(.invalidSigningInput) {
                _ = try Audit.mappingOracleSigningPrehash(wrongCardinality, cancellationCheck: { false })
            }
        }

        let fixture = try XCTUnwrap(harness.fixtures.first)
        let zero = try Audit.SHA256Digest(bytes: Array(repeating: 0, count: 32))
        for oracle in [
            replacingOracle(fixture.mappingOracle, sourceIdentifier: ""),
            replacingOracle(fixture.mappingOracle, sourceArtifactSHA256: zero),
            replacingOracle(fixture.mappingOracle, mappingTableSHA256: zero)
        ] {
            let invalid = Audit.Fixture(
                reference: fixture.reference,
                codePage: fixture.codePage,
                fixtureArtifactSHA256: fixture.fixtureArtifactSHA256,
                mappingOracle: oracle,
                expectation: fixture.expectation
            )
            assertAuditError(.invalidSigningInput) {
                _ = try Audit.mappingOracleSigningPrehash(invalid, cancellationCheck: { false })
            }
        }
        assertAuditError(.invalidSigningInput) {
            _ = try Audit.mappingOracleSigningPrehash(
                replacingFixture(fixture, fixtureArtifactSHA256: zero),
                cancellationCheck: { false }
            )
        }
    }

    func testAutomaticSelectionRejectionAndCanonicalAmbiguitySemantics() throws {
        let harness = try AuditHarness()
        let cp1250 = try fixture(.cp1250, in: harness.fixtures)
        let cp1255 = try fixture(.cp1255, in: harness.fixtures)
        let cp50220 = try fixture(.cp50220, in: harness.fixtures)
        let selected = Audit.SelectionExpectation(
            automaticDetection: .selected(Audit.SupportedCodePage.cp1250.id),
            explicitSelection: Audit.SupportedCodePage.cp1250.id
        )
        let rejected = Audit.SelectionExpectation(
            automaticDetection: .rejected,
            explicitSelection: Audit.SupportedCodePage.cp1250.id
        )
        let ambiguous = Audit.SelectionExpectation(
            automaticDetection: .ambiguous([
                Audit.SupportedCodePage.cp1250.id,
                Audit.SupportedCodePage.cp1251.id
            ]),
            explicitSelection: Audit.SupportedCodePage.cp1250.id
        )

        XCTAssertFalse(selected.requiresExplicitSelection)
        XCTAssertFalse(rejected.requiresExplicitSelection)
        XCTAssertTrue(ambiguous.requiresExplicitSelection)

        let validAmbiguous = try resignedFixture(
            cp1250,
            selection: ambiguous,
            signerID: harness.oracleSignerID,
            key: harness.oracleKey
        )
        let cp1255CanonicalCandidate = try resignedFixture(
            cp1255,
            selection: Audit.SelectionExpectation(
                automaticDetection: .ambiguous([
                    Audit.SupportedCodePage.cp1254.id,
                    Audit.SupportedCodePage.cp1255.id
                ]),
                explicitSelection: Audit.SupportedCodePage.cp1255.id
            ),
            signerID: harness.oracleSignerID,
            key: harness.oracleKey
        )
        let utf8AndISO2022 = try resignedFixture(
            cp50220,
            selection: Audit.SelectionExpectation(
                automaticDetection: .ambiguous([
                    Audit.utf8DetectionCodePage,
                    Audit.SupportedCodePage.cp50220.id
                ]),
                explicitSelection: Audit.SupportedCodePage.cp50220.id
            ),
            signerID: harness.oracleSignerID,
            key: harness.oracleKey
        )

        for replacement in [validAmbiguous, cp1255CanonicalCandidate, utf8AndISO2022] {
            let original = try XCTUnwrap(harness.fixtures.first { $0.codePage == replacement.codePage })
            let manifest = replacingManifest(
                harness.manifest,
                fixtures: replacingFixture(original, with: replacement, in: harness.fixtures)
            )
            let plan = try Audit.prepare(
                manifest: manifest,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            let verification = try XCTUnwrap(plan.fixtureVerifications.first { $0.codePage == replacement.codePage })
            XCTAssertTrue(verification.isMappingOracleVerified)
            XCTAssertTrue(verification.isFixtureValid)
        }

        let rejectedFixture = try resignedFixture(
            cp1250,
            selection: rejected,
            signerID: harness.oracleSignerID,
            key: harness.oracleKey
        )
        let rejectedManifest = replacingManifest(
            harness.manifest,
            fixtures: replacingFixture(cp1250, with: rejectedFixture, in: harness.fixtures)
        )
        let rejectedPlan = try Audit.prepare(
            manifest: rejectedManifest,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let rejectedVerification = try XCTUnwrap(
            rejectedPlan.fixtureVerifications.first { $0.codePage == cp1250.codePage }
        )
        XCTAssertTrue(rejectedVerification.isMappingOracleVerified)
        XCTAssertFalse(rejectedVerification.isFixtureValid)
        XCTAssertTrue(rejectedPlan.preflightFindings.contains { $0.code == .invalidFixtureExpectation })

        for invalidSelection in [
            Audit.SelectionExpectation(
                automaticDetection: .selected(Audit.CodePageID(rawValue: 999)),
                explicitSelection: cp1250.codePage
            ),
            Audit.SelectionExpectation(
                automaticDetection: .ambiguous([Audit.SupportedCodePage.cp1250.id]),
                explicitSelection: cp1250.codePage
            ),
            Audit.SelectionExpectation(
                automaticDetection: .ambiguous([
                    Audit.SupportedCodePage.cp1251.id,
                    Audit.SupportedCodePage.cp1250.id
                ]),
                explicitSelection: cp1250.codePage
            ),
            Audit.SelectionExpectation(
                automaticDetection: .ambiguous([
                    Audit.utf8DetectionCodePage,
                    Audit.SupportedCodePage.cp1250.id
                ]),
                explicitSelection: cp1250.codePage
            )
        ] {
            assertAuditError(.invalidSigningInput) {
                _ = try resignedFixture(
                    cp1250,
                    selection: invalidSelection,
                    signerID: harness.oracleSignerID,
                    key: harness.oracleKey
                )
            }
        }
    }

    func testCanonicalAmbiguityEvaluatesAndCoversOrderingMembershipAndDuplicates() throws {
        let harness = try AuditHarness()
        let original = try fixture(.cp932, in: harness.fixtures)
        let validCandidates: [[Audit.CodePageID]] = [
            [Audit.SupportedCodePage.cp932.id, Audit.SupportedCodePage.cp1251.id],
            [
                Audit.SupportedCodePage.cp932.id,
                Audit.SupportedCodePage.cp51932.id,
                Audit.SupportedCodePage.cp1250.id,
                Audit.SupportedCodePage.cp1251.id,
                Audit.SupportedCodePage.cp1252.id,
                Audit.SupportedCodePage.cp1253.id,
                Audit.SupportedCodePage.cp1254.id,
                Audit.SupportedCodePage.cp1255.id
            ]
        ]
        for candidates in validCandidates {
            let replacement = try resignedFixture(
                original,
                selection: Audit.SelectionExpectation(
                    automaticDetection: .ambiguous(candidates),
                    explicitSelection: original.codePage
                ),
                signerID: harness.oracleSignerID,
                key: harness.oracleKey
            )
            let manifest = replacingManifest(
                harness.manifest,
                fixtures: replacingFixture(original, with: replacement, in: harness.fixtures)
            )
            let plan = try Audit.prepare(
                manifest: manifest,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            let evidence = try makeEvidence(
                for: harness,
                fixtures: manifest.fixtures,
                manifest: manifest,
                plan: plan
            )
            let result = try Audit.evaluate(
                plan: plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            XCTAssertTrue(result.report.isCompleteAndValid)
            XCTAssertTrue(result.report.findings.isEmpty)
        }

        for candidates in [
            [Audit.SupportedCodePage.cp932.id, Audit.SupportedCodePage.cp932.id],
            [Audit.SupportedCodePage.cp1251.id, Audit.SupportedCodePage.cp932.id]
        ] {
            assertAuditError(.invalidSigningInput) {
                _ = try resignedFixture(
                    original,
                    selection: Audit.SelectionExpectation(
                        automaticDetection: .ambiguous(candidates),
                        explicitSelection: original.codePage
                    ),
                    signerID: harness.oracleSignerID,
                    key: harness.oracleKey
                )
            }
        }

        let missingFixtureCandidate = try resignedFixture(
            original,
            selection: Audit.SelectionExpectation(
                automaticDetection: .ambiguous([
                    Audit.SupportedCodePage.cp1250.id,
                    Audit.SupportedCodePage.cp1251.id
                ]),
                explicitSelection: original.codePage
            ),
            signerID: harness.oracleSignerID,
            key: harness.oracleKey
        )
        let missingCandidatePlan = try Audit.prepare(
            manifest: replacingManifest(
                harness.manifest,
                fixtures: replacingFixture(
                    original,
                    with: missingFixtureCandidate,
                    in: harness.fixtures
                )
            ),
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        assertFindingCodes(missingCandidatePlan.preflightFindings, [.invalidFixtureExpectation])
    }

    func testFixtureValidityChecksEachLifecycleInvariantIndependently() throws {
        let harness = try AuditHarness()
        let original = try fixture(.cp932, in: harness.fixtures)
        let old = original.expectation
        let changedSaved = content(bytes: [0x41, 0x62], scalars: [0x41, 0x62])
        let changedReloaded = content(bytes: [0x41, 0x63], scalars: [0x41, 0x63])
        let changedSavedExpectation = replacingExpectation(old, saved: changedSaved)
        let changedReloadedExpectation = replacingExpectation(old, reloaded: changedReloaded)
        let cases: [(Audit.Fixture, [Audit.FindingCode])] = [
            try signedCopy(
                original,
                fixtureArtifactSHA256: digest("wrong-fixture-artifact"),
                signerID: harness.oracleSignerID,
                key: harness.oracleKey
            ),
            try signedCopy(
                original,
                expectation: replacingExpectation(
                    old,
                    selection: Audit.SelectionExpectation(
                        automaticDetection: old.selection.automaticDetection,
                        explicitSelection: Audit.SupportedCodePage.cp1250.id
                    )
                ),
                signerID: harness.oracleSignerID,
                key: harness.oracleKey
            ),
            try signedCopy(
                original,
                fixtureScalarCommitments: Audit.FixtureScalarCommitments(
                    expectation: changedSavedExpectation
                ),
                expectation: changedSavedExpectation,
                signerID: harness.oracleSignerID,
                key: harness.oracleKey
            ),
            try signedCopy(
                original,
                fixtureScalarCommitments: Audit.FixtureScalarCommitments(
                    expectation: changedReloadedExpectation
                ),
                expectation: changedReloadedExpectation,
                signerID: harness.oracleSignerID,
                key: harness.oracleKey
            )
        ].map { ($0, [.invalidFixtureExpectation]) }
        let changedCommitment = Audit.FixtureScalarCommitments(
            original: old.original.unicode,
            edited: old.edited.unicode,
            saved: old.saved.unicode,
            reloaded: Audit.UnicodeHash(
                scalarCount: old.reloaded.unicode.scalarCount,
                sha256: digest("wrong-reloaded-commitment")
            )
        )
        let commitmentMismatch = try signedCopy(
            original,
            fixtureScalarCommitments: changedCommitment,
            signerID: harness.oracleSignerID,
            key: harness.oracleKey
        )

        for (replacement, expectedCodes) in cases + [
            (commitmentMismatch, [.invalidFixtureExpectation, .unverifiedMappingOracle])
        ] {
            let plan = try Audit.prepare(
                manifest: replacingManifest(
                    harness.manifest,
                    fixtures: replacingFixture(original, with: replacement, in: harness.fixtures)
                ),
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            assertFindingCodes(plan.preflightFindings, expectedCodes)
            let verification = try XCTUnwrap(
                plan.fixtureVerifications.first { $0.codePage == original.codePage }
            )
            XCTAssertFalse(verification.isFixtureValid)
        }

        let noEdit = replacingExpectation(
            old,
            edited: old.original,
            saved: old.original,
            reloaded: old.original,
            intendedEdit: Audit.UnicodeScalarEdit(
                unchangedPrefix: [0x41],
                removedScalars: [],
                insertedScalars: [],
                unchangedSuffix: []
            )
        )
        assertAuditError(.invalidSigningInput) {
            _ = try signedCopy(
                original,
                fixtureScalarCommitments: Audit.FixtureScalarCommitments(expectation: noEdit),
                expectation: noEdit,
                signerID: harness.oracleSignerID,
                key: harness.oracleKey
            )
        }
    }

    func testUnicodeScalarEditValidationCoversCanonicalInsertionDeletionAndReplacement() throws {
        let harness = try AuditHarness()
        let original = try fixture(.cp932, in: harness.fixtures)
        let insertion = original.expectation
        let deletionOriginal = content(bytes: [0x41, 0x42], scalars: [0x41, 0x42])
        let deletionEdited = content(bytes: [0x41], scalars: [0x41])
        let deletion = replacingExpectation(
            insertion,
            original: deletionOriginal,
            edited: deletionEdited,
            saved: deletionEdited,
            reloaded: deletionEdited,
            intendedEdit: Audit.UnicodeScalarEdit(
                unchangedPrefix: [0x41],
                removedScalars: [0x42],
                insertedScalars: [],
                unchangedSuffix: []
            )
        )
        let replacementEdited = content(bytes: [0x41, 0x43], scalars: [0x41, 0x43])
        let replacement = replacingExpectation(
            insertion,
            original: deletionOriginal,
            edited: replacementEdited,
            saved: replacementEdited,
            reloaded: replacementEdited,
            intendedEdit: Audit.UnicodeScalarEdit(
                unchangedPrefix: [0x41],
                removedScalars: [0x42],
                insertedScalars: [0x43],
                unchangedSuffix: []
            )
        )

        for expectation in [deletion, replacement] {
            let signed = try signedCopy(
                original,
                fixtureArtifactSHA256: expectation.original.bytes.sha256,
                fixtureScalarCommitments: Audit.FixtureScalarCommitments(expectation: expectation),
                expectation: expectation,
                signerID: harness.oracleSignerID,
                key: harness.oracleKey
            )
            let plan = try Audit.prepare(
                manifest: replacingManifest(
                    harness.manifest,
                    fixtures: replacingFixture(original, with: signed, in: harness.fixtures)
                ),
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            XCTAssertTrue(
                try XCTUnwrap(plan.fixtureVerifications.first { $0.codePage == original.codePage })
                    .isFixtureValid
            )
        }

        let malformedEdits = [
            Audit.UnicodeScalarEdit(
                unchangedPrefix: [0x41],
                removedScalars: [],
                insertedScalars: [],
                unchangedSuffix: []
            ),
            Audit.UnicodeScalarEdit(
                unchangedPrefix: [],
                removedScalars: [0x41],
                insertedScalars: [0x41, 0x61],
                unchangedSuffix: []
            ),
            Audit.UnicodeScalarEdit(
                unchangedPrefix: [0x41],
                removedScalars: [],
                insertedScalars: [0xD800],
                unchangedSuffix: []
            ),
            Audit.UnicodeScalarEdit(
                unchangedPrefix: [0x41],
                removedScalars: [],
                insertedScalars: [0x62],
                unchangedSuffix: []
            )
        ]
        for edit in malformedEdits {
            assertAuditError(.invalidSigningInput) {
                _ = try signedCopy(
                    original,
                    expectation: replacingExpectation(insertion, intendedEdit: edit),
                    signerID: harness.oracleSignerID,
                    key: harness.oracleKey
                )
            }
        }
    }

    func testUnicodeScalarEditCommitmentRejectsByteOnlyMutation() throws {
        let harness = try AuditHarness()
        let request = try XCTUnwrap(
            harness.plan.requests.first {
                $0.codePage == Audit.SupportedCodePage.cp932.id && $0.stage == .edit
            }
        )
        let fixture = try fixture(.cp932, in: harness.fixtures)
        let byteOnlyAfter = Audit.ContentHash(
            bytes: fixture.expectation.edited.bytes,
            unicode: fixture.expectation.original.unicode
        )
        let evidence = unsignedEvidence(
            bundle: reference("evidence", revision: 1),
            request: request,
            observation: .edit(
                Audit.EditObservation(
                    before: fixture.expectation.original,
                    after: byteOnlyAfter,
                    mutationApplied: true,
                    unicodeScalarDelta: fixture.expectation.intendedEdit
                )
            ),
            lineage: harness.primaryLineage,
            runSHA256: harness.runSHA256,
            signerID: harness.measurementSignerID
        )

        XCTAssertNotEqual(byteOnlyAfter.bytes, fixture.expectation.original.bytes)
        XCTAssertEqual(byteOnlyAfter.unicode, fixture.expectation.original.unicode)
        assertAuditError(.invalidSigningInput) {
            _ = try Audit.executionSigningPrehash(evidence, cancellationCheck: { false })
        }
        XCTAssertEqual(
            Audit.unicodeScalarEditContract,
            "Maximal unchanged scalar prefix, removed scalars, inserted scalars, and maximal unchanged scalar suffix; each sequence is count-framed and each scalar is unsigned 32-bit big-endian"
        )
    }

    func testStaleWrongStageAndAssertionOnlyStatusesArePreserved() throws {
        let harness = try AuditHarness()
        let evidence = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id else { return }
            switch request.stage {
            case .load:
                draft.requestSHA256 = digest("stale-request")
            case .compare:
                draft.observation = matchingObservation(for: fixture, stage: .load)
            case .edit:
                draft.origin = .callerAssertion
            case .save, .reload, .byteComparison:
                break
            }
        }
        let result = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )

        XCTAssertEqual(status(in: result, codePage: .cp932, stage: .load), .stale)
        XCTAssertEqual(status(in: result, codePage: .cp932, stage: .compare), .wrongStage)
        XCTAssertEqual(status(in: result, codePage: .cp932, stage: .edit), .assertionOnly)
        XCTAssertEqual(status(in: result, codePage: .cp932, stage: .save), .complete)
        XCTAssertTrue(result.report.findings.contains { $0.code == .staleEvidence })
        XCTAssertTrue(result.report.findings.contains { $0.code == .wrongStageEvidence })
        XCTAssertTrue(result.report.findings.contains { $0.code == .callerAssertionEvidence })
        XCTAssertFalse(result.report.findings.contains { $0.code == .unorderedStageEvidence })
    }

    func testCompletenessStatusesAndDiagnosticsAreExact() throws {
        let harness = try AuditHarness()
        let complete = try makeEvidence(for: harness)
        let targetCodePage = Audit.SupportedCodePage.cp1255.id
        let targetStage = Audit.Stage.byteComparison
        let targetIndex = try XCTUnwrap(
            complete.stages.firstIndex {
                $0.codePage == targetCodePage && $0.requestedStage == targetStage
            }
        )
        let target = complete.stages[targetIndex]

        var missingStages = complete.stages
        missingStages.remove(at: targetIndex)
        let missing = try Audit.evaluate(
            plan: harness.plan,
            evidence: replacingStages(complete, stages: missingStages),
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertEqual(status(in: missing, codePage: .cp1255, stage: targetStage), .missing)
        assertFindings(
            missing.report.findings,
            [(.missingEvidence, .stage(targetCodePage, targetStage))]
        )

        var duplicateStages = complete.stages
        duplicateStages.append(target)
        let duplicate = try Audit.evaluate(
            plan: harness.plan,
            evidence: replacingStages(complete, stages: duplicateStages),
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertEqual(status(in: duplicate, codePage: .cp1255, stage: targetStage), .duplicate)
        XCTAssertEqual(
            duplicate.report.completeness.cells.first {
                $0.codePage == .cp1255 && $0.stage == targetStage
            }?.evidenceCount,
            2
        )
        assertFindings(
            duplicate.report.findings,
            [(.duplicateEvidence, .stage(targetCodePage, targetStage))]
        )

        let unexpected = replacingStageEvidence(
            target,
            fixture: reference("unexpected-fixture", revision: 1)
        )
        let unexpectedResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: replacingStages(complete, stages: complete.stages + [unexpected]),
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertEqual(status(in: unexpectedResult, codePage: .cp1255, stage: targetStage), .complete)
        assertFindings(
            unexpectedResult.report.findings,
            [(.unexpectedEvidence, .stage(targetCodePage, targetStage))]
        )

        let noAttestation = withoutAttestation(target)
        var unattestedStages = complete.stages
        unattestedStages[targetIndex] = noAttestation
        let unattested = try Audit.evaluate(
            plan: harness.plan,
            evidence: replacingStages(complete, stages: unattestedStages),
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertEqual(status(in: unattested, codePage: .cp1255, stage: targetStage), .invalid)
        assertFindings(
            unattested.report.findings,
            [(.missingMeasurementAttestation, .stage(targetCodePage, targetStage))]
        )

        let manual = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == targetCodePage, request.stage == targetStage else { return }
            draft.origin = .manualMeasurement
        }
        let manualResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: manual,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertEqual(status(in: manualResult, codePage: .cp1255, stage: targetStage), .complete)
        XCTAssertTrue(manualResult.report.findings.isEmpty)

        let originalFixture = try fixture(.cp1255, in: harness.fixtures)
        var badSignature = originalFixture.mappingOracle.signature.bytes
        badSignature[0] ^= 0x01
        let unverifiedFixture = replacingFixture(
            originalFixture,
            mappingOracle: replacingOracleSignature(
                originalFixture.mappingOracle,
                bytes: badSignature
            )
        )
        let unverifiedManifest = replacingManifest(
            harness.manifest,
            fixtures: replacingFixture(
                originalFixture,
                with: unverifiedFixture,
                in: harness.fixtures
            )
        )
        let unverifiedPlan = try Audit.prepare(
            manifest: unverifiedManifest,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let unverifiedEvidence = try makeEvidence(
            for: harness,
            fixtures: unverifiedManifest.fixtures,
            manifest: unverifiedManifest,
            plan: unverifiedPlan
        )
        let unverified = try Audit.evaluate(
            plan: unverifiedPlan,
            evidence: unverifiedEvidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        for stage in Audit.Stage.allCases {
            XCTAssertEqual(status(in: unverified, codePage: .cp1255, stage: stage), .unverifiedMapping)
        }
        assertFindings(
            unverified.report.findings,
            [(.unverifiedMappingOracle, .fixture(targetCodePage))]
        )
    }

    func testEveryEvidenceBindingReportsExactStaleDiagnostics() throws {
        let harness = try AuditHarness()
        let targetCodePage = Audit.SupportedCodePage.cp932.id
        let targetStage = Audit.Stage.save
        for mutate in [
            { (draft: inout EvidenceDraft) in draft.requestSHA256 = digest("stale-request") },
            { (draft: inout EvidenceDraft) in draft.bundle = reference("stale-bundle", revision: 1) },
            { (draft: inout EvidenceDraft) in
                draft.bundleManifestSHA256 = digest("stale-stage-manifest")
            }
        ] {
            let evidence = try makeEvidence(for: harness) { fixture, request, draft in
                guard fixture.codePage == targetCodePage, request.stage == targetStage else { return }
                mutate(&draft)
            }
            let result = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            XCTAssertEqual(status(in: result, codePage: .cp932, stage: targetStage), .stale)
            assertFindings(
                result.report.findings,
                [(.staleEvidence, .stage(targetCodePage, targetStage))]
            )
        }

        let current = try makeEvidence(for: harness)
        for staleBundle in [
            Audit.EvidenceBundle(
                reference: current.reference,
                manifest: reference("stale-manifest", revision: 1),
                manifestSHA256: current.manifestSHA256,
                stages: current.stages
            ),
            Audit.EvidenceBundle(
                reference: current.reference,
                manifest: current.manifest,
                manifestSHA256: digest("stale-manifest-digest"),
                stages: current.stages
            )
        ] {
            let result = try Audit.evaluate(
                plan: harness.plan,
                evidence: staleBundle,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            XCTAssertEqual(
                result.report.findings.filter { $0.code == .staleEvidenceBundle }.count,
                1
            )
            XCTAssertEqual(
                result.report.findings.filter { $0.code == .staleEvidence }.count,
                harness.plan.requests.count
            )
            XCTAssertEqual(result.report.findings.count, harness.plan.requests.count + 1)
            XCTAssertTrue(result.report.completeness.cells.allSatisfy { $0.status == .stale })
        }
    }

    func testObservationMismatchFindingsAreIsolatedAndSubjectIDsAreDistinct() throws {
        let harness = try AuditHarness()
        let alternate = content(bytes: [0x5A], scalars: [0x5A])
        let cases: [(Audit.SupportedCodePage, Audit.Stage, Audit.FindingCode, (inout EvidenceDraft) -> Void)] = [
            (
                .cp932, .load, .explicitSelectionMismatch,
                { draft in
                    guard case .load(let value) = draft.observation else { return }
                    draft.observation = .load(
                        Audit.LoadObservation(
                            automaticDetection: value.automaticDetection,
                            explicitlySelectedEncoding: Audit.SupportedCodePage.cp1250.id,
                            source: value.source,
                            loaded: value.loaded
                        ))
                }
            ),
            (
                .cp932, .load, .originalHashMismatch,
                { draft in
                    guard case .load(let value) = draft.observation else { return }
                    draft.observation = .load(
                        Audit.LoadObservation(
                            automaticDetection: value.automaticDetection,
                            explicitlySelectedEncoding: value.explicitlySelectedEncoding,
                            source: Audit.ContentHash(bytes: alternate.bytes, unicode: value.source.unicode),
                            loaded: value.loaded
                        ))
                }
            ),
            (
                .cp932, .compare, .comparisonMismatch,
                { draft in
                    guard case .compare(let value) = draft.observation else { return }
                    draft.observation = .compare(
                        Audit.CompareObservation(
                            left: value.left,
                            right: value.right,
                            unicodeEqual: false,
                            differenceCount: value.differenceCount
                        ))
                }
            ),
            (
                .cp932, .edit, .editedHashMismatch,
                { draft in
                    guard case .edit(let value) = draft.observation else { return }
                    draft.observation = .edit(
                        Audit.EditObservation(
                            before: value.before,
                            after: Audit.ContentHash(bytes: alternate.bytes, unicode: value.after.unicode),
                            mutationApplied: value.mutationApplied,
                            unicodeScalarDelta: value.unicodeScalarDelta
                        ))
                }
            ),
            (
                .cp932, .save, .savedHashMismatch,
                { draft in
                    guard case .save(let value) = draft.observation else { return }
                    draft.observation = .save(
                        Audit.SaveObservation(
                            edited: value.edited,
                            saved: Audit.ContentHash(bytes: alternate.bytes, unicode: value.saved.unicode),
                            selectedEncoding: value.selectedEncoding
                        ))
                }
            ),
            (
                .cp932, .reload, .reloadedHashMismatch,
                { draft in
                    guard case .reload(let value) = draft.observation else { return }
                    draft.observation = .reload(
                        Audit.ReloadObservation(
                            saved: value.saved,
                            reloaded: Audit.ContentHash(
                                bytes: alternate.bytes,
                                unicode: value.reloaded.unicode
                            ),
                            selectedEncoding: value.selectedEncoding
                        ))
                }
            ),
            (
                .cp932, .byteComparison, .byteComparisonMismatch,
                { draft in
                    guard case .byteComparison(let value) = draft.observation else { return }
                    draft.observation = .byteComparison(
                        Audit.ByteComparisonObservation(
                            saved: value.saved,
                            reloaded: value.reloaded,
                            bytesEqual: false
                        ))
                }
            )
        ]

        for (codePage, stage, code, mutate) in cases {
            let evidence = try makeEvidence(for: harness) { fixture, request, draft in
                guard fixture.codePage == codePage.id, request.stage == stage else { return }
                mutate(&draft)
            }
            let result = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            assertFindings(result.report.findings, [(code, .stage(codePage.id, stage))])
            XCTAssertEqual(status(in: result, codePage: codePage, stage: stage), .invalid)
            XCTAssertFalse(result.report.isCompleteAndValid)
            XCTAssertTrue(result.report.containsErrors)
            XCTAssertEqual(result.report.highestSeverity, .error)
            XCTAssertEqual(result.receipt.requiredStageCount, harness.plan.requests.count)
            XCTAssertEqual(result.receipt.completeStageCount, harness.plan.requests.count - 1)
            XCTAssertEqual(result.receipt.findingCount, 1)
            XCTAssertFalse(result.receipt.recordsCompleteCoverage)
        }

        let scalarMismatch = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id, request.stage == .edit
            else { return }
            let changedAfter = content(bytes: [0x41, 0x7A], scalars: [0x41, 0x7A])
            draft.observation = .edit(
                Audit.EditObservation(
                    before: fixture.expectation.original,
                    after: changedAfter,
                    mutationApplied: true,
                    unicodeScalarDelta: Audit.UnicodeScalarEdit(
                        unchangedPrefix: [0x41],
                        removedScalars: [],
                        insertedScalars: [0x7A],
                        unchangedSuffix: []
                    )
                ))
        }
        let scalarMismatchResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: scalarMismatch,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        assertFindings(
            scalarMismatchResult.report.findings,
            [
                (.editMutationMismatch, .stage(Audit.SupportedCodePage.cp932.id, .edit)),
                (.editedHashMismatch, .stage(Audit.SupportedCodePage.cp932.id, .edit))
            ]
        )

        let repeatedCode = try makeEvidence(for: harness) { fixture, request, draft in
            let target =
                fixture.codePage == Audit.SupportedCodePage.cp932.id
                && (request.stage == .load || request.stage == .save)
            let secondCodePage =
                fixture.codePage == Audit.SupportedCodePage.cp1250.id
                && request.stage == .load
            guard target || secondCodePage else { return }
            switch draft.observation {
            case .load(let value):
                draft.observation = .load(
                    Audit.LoadObservation(
                        automaticDetection: value.automaticDetection,
                        explicitlySelectedEncoding: Audit.SupportedCodePage.cp1251.id,
                        source: value.source,
                        loaded: value.loaded
                    ))
            case .save(let value):
                draft.observation = .save(
                    Audit.SaveObservation(
                        edited: value.edited,
                        saved: value.saved,
                        selectedEncoding: Audit.SupportedCodePage.cp1251.id
                    ))
            default:
                break
            }
        }
        let repeatedResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: repeatedCode,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let repeatedFindings = repeatedResult.report.findings.filter {
            $0.code == .explicitSelectionMismatch
        }
        XCTAssertEqual(repeatedFindings.count, 3)
        XCTAssertEqual(Set(repeatedFindings.map(\.id)).count, 3)
    }

    func testSignerAutomaticAmbiguityEditAndRunFindingsRemainDistinct() throws {
        let harness = try AuditHarness()
        let changedRun = digest("changed-execution-run")
        let evidence = try makeEvidence(for: harness) { fixture, request, draft in
            if fixture.codePage == Audit.SupportedCodePage.cp932.id {
                switch request.stage {
                case .load:
                    let expected = fixture.expectation
                    draft.observation = .load(
                        Audit.LoadObservation(
                            automaticDetection: .rejected,
                            explicitlySelectedEncoding: fixture.codePage,
                            source: expected.original,
                            loaded: expected.original
                        )
                    )
                case .edit:
                    let expected = fixture.expectation
                    draft.observation = .edit(
                        Audit.EditObservation(
                            before: expected.original,
                            after: expected.edited,
                            mutationApplied: false,
                            unicodeScalarDelta: expected.intendedEdit
                        )
                    )
                case .save, .reload, .byteComparison:
                    draft.runSHA256 = changedRun
                case .compare:
                    break
                }
                if request.stage == .reload || request.stage == .byteComparison {
                    draft.signerID = harness.alternateMeasurementSignerID
                    draft.signingKey = harness.alternateMeasurementKey
                }
            }
            if fixture.codePage == Audit.SupportedCodePage.cp1250.id && request.stage == .load {
                let expected = fixture.expectation
                draft.observation = .load(
                    Audit.LoadObservation(
                        automaticDetection: .ambiguous([
                            Audit.SupportedCodePage.cp1250.id,
                            Audit.SupportedCodePage.cp1251.id
                        ]),
                        explicitlySelectedEncoding: fixture.codePage,
                        source: expected.original,
                        loaded: expected.original
                    )
                )
            }
        }
        let result = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let codes = Set(result.report.findings.map(\.code))

        XCTAssertTrue(codes.contains(.automaticDetectionMismatch))
        XCTAssertTrue(codes.contains(.ambiguityExpectationMismatch))
        XCTAssertTrue(codes.contains(.editMutationMismatch))
        XCTAssertTrue(codes.contains(.executionRunMismatch))
        XCTAssertTrue(codes.contains(.signerIdentityMismatch))
        XCTAssertTrue(codes.contains(.unstableLineageSigner))
        XCTAssertFalse(codes.contains(.unverifiedMeasurementAttestation))
        XCTAssertNotEqual(
            result.report.findings.first { $0.code == .automaticDetectionMismatch }?.id,
            result.report.findings.first { $0.code == .editMutationMismatch }?.id
        )
    }

    func testExactSignedHashChainIsIndependentOfSemanticCellValidity() throws {
        let harness = try AuditHarness()
        let semanticFailure = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id, request.stage == .compare else {
                return
            }
            let original = fixture.expectation.original
            draft.observation = .compare(
                Audit.CompareObservation(
                    left: original,
                    right: original,
                    unicodeEqual: false,
                    differenceCount: 1
                )
            )
        }
        let semanticResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: semanticFailure,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )

        XCTAssertEqual(status(in: semanticResult, codePage: .cp932, stage: .compare), .invalid)
        XCTAssertTrue(semanticResult.report.findings.contains { $0.code == .comparisonMismatch })
        XCTAssertFalse(semanticResult.report.findings.contains { $0.code == .unorderedStageEvidence })

        let compareIndex = try XCTUnwrap(
            semanticFailure.stages.firstIndex {
                $0.codePage == Audit.SupportedCodePage.cp932.id && $0.requestedStage == .compare
            }
        )
        let originalCompare = semanticFailure.stages[compareIndex]
        let attestation = try XCTUnwrap(originalCompare.attestation)
        var tamperedBytes = attestation.signature.bytes
        tamperedBytes[0] ^= 0x01
        let tamperedCompare = replacingSignature(originalCompare, bytes: tamperedBytes)
        XCTAssertNotEqual(
            try Audit.stageEvidenceSHA256(originalCompare, cancellationCheck: { false }),
            try Audit.stageEvidenceSHA256(tamperedCompare, cancellationCheck: { false })
        )
        var tamperedStages = semanticFailure.stages
        tamperedStages[compareIndex] = tamperedCompare
        let tamperedBundle = Audit.EvidenceBundle(
            reference: semanticFailure.reference,
            manifest: semanticFailure.manifest,
            manifestSHA256: semanticFailure.manifestSHA256,
            stages: tamperedStages
        )
        let tamperedResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: tamperedBundle,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )

        XCTAssertTrue(tamperedResult.report.findings.contains { $0.code == .unverifiedMeasurementAttestation })
        XCTAssertTrue(tamperedResult.report.findings.contains { $0.code == .unorderedStageEvidence })
        XCTAssertEqual(status(in: tamperedResult, codePage: .cp932, stage: .compare), .invalid)
    }

    func testHashChainRejectsEachOrderDefectAndAllowsSequenceGaps() throws {
        let harness = try AuditHarness()
        let targetCodePage = Audit.SupportedCodePage.cp932.id
        let cases: [(Audit.Stage, (Audit.Stage, inout EvidenceDraft) -> Void)] = [
            (
                .load,
                { stage, draft in
                    guard stage == .load else { return }
                    draft.previousEvidenceSHA256 = digest("unexpected-load-predecessor")
                }
            ),
            (
                .compare,
                { stage, draft in
                    guard stage == .compare else { return }
                    draft.monotonicSequence = 1
                }
            ),
            (
                .compare,
                { stage, draft in
                    guard stage == .compare else { return }
                    draft.previousEvidenceSHA256 = digest("wrong-predecessor")
                }
            )
        ]
        for (firstInvalidStage, mutate) in cases {
            let evidence = try makeEvidence(for: harness) { fixture, request, draft in
                guard fixture.codePage == targetCodePage else { return }
                mutate(request.stage, &draft)
            }
            let result = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            let expectedStages = Audit.Stage.allCases.filter { $0.rawValue >= firstInvalidStage.rawValue }
            let orderFindings = result.report.findings.filter { $0.code == .unorderedStageEvidence }
            XCTAssertEqual(orderFindings.count, expectedStages.count)
            assertFindings(
                orderFindings,
                expectedStages.map { (.unorderedStageEvidence, .stage(targetCodePage, $0)) }
            )
            for stage in expectedStages {
                XCTAssertEqual(status(in: result, codePage: .cp932, stage: stage), .invalid)
            }
        }

        let gap = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == targetCodePage else { return }
            draft.monotonicSequence = UInt64((request.stage.rawValue + 1) * 10)
        }
        let gapResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: gap,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertTrue(gapResult.report.isCompleteAndValid)
        XCTAssertFalse(gapResult.report.findings.contains { $0.code == .unorderedStageEvidence })
    }

    func testCodecArtifactBuildAndExecutorLineageAreBound() throws {
        let harness = try AuditHarness()
        let changedMappingManifest = replacingManifest(
            harness.manifest,
            codecSessionMappings: Array(Audit.canonicalCodecSessionMappings.dropLast())
        )
        let changedSchemaManifest = replacingManifest(
            harness.manifest,
            sessionEncodingSchemaVersion: ComparisonSessionState.currentSchemaVersion + 1
        )
        let changedArtifactManifest = replacingManifest(
            harness.manifest,
            codecArtifactSHA256: digest("different-codec-artifact")
        )
        let reorderedInventoryManifest = replacingManifest(
            harness.manifest,
            declaredSupportedCodePages: Array(harness.manifest.declaredSupportedCodePages.reversed())
        )
        let reorderedMappingsManifest = replacingManifest(
            harness.manifest,
            codecSessionMappings: Array(harness.manifest.codecSessionMappings.reversed())
        )

        for manifest in [
            changedMappingManifest,
            changedSchemaManifest,
            changedArtifactManifest,
            reorderedInventoryManifest,
            reorderedMappingsManifest
        ] {
            let plan = try Audit.prepare(
                manifest: manifest,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            XCTAssertTrue(plan.preflightFindings.contains { $0.code == .supportedEncodingManifestMismatch })
            XCTAssertNotEqual(plan.manifestSHA256, harness.plan.manifestSHA256)
        }

        for unapprovedLineage in [
            Audit.ExecutionLineage(
                executor: reference("unapproved-executor", revision: 1),
                buildSHA256: harness.primaryLineage.buildSHA256,
                signerID: harness.measurementSignerID
            ),
            Audit.ExecutionLineage(
                executor: harness.primaryLineage.executor,
                buildSHA256: digest("unapproved-build-artifact"),
                signerID: harness.measurementSignerID
            )
        ] {
            let evidence = try makeEvidence(for: harness) { fixture, request, draft in
                guard fixture.codePage == Audit.SupportedCodePage.cp932.id else { return }
                draft.lineage = unapprovedLineage
            }
            let result = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
            XCTAssertTrue(result.report.findings.contains { $0.code == .unapprovedExecutionLineage })
        }

        let mixedApprovedLineage = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id,
                request.stage.rawValue >= Audit.Stage.save.rawValue
            else { return }
            draft.lineage = harness.alternateLineage
            draft.signerID = harness.alternateMeasurementSignerID
            draft.signingKey = harness.alternateMeasurementKey
        }
        let mixedResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: mixedApprovedLineage,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertTrue(mixedResult.report.findings.contains { $0.code == .mixedExecutionLineage })
        XCTAssertTrue(mixedResult.report.findings.contains { $0.code == .unstableLineageSigner })
        XCTAssertFalse(mixedResult.report.findings.contains { $0.code == .unapprovedExecutionLineage })
        XCTAssertFalse(mixedResult.report.findings.contains { $0.code == .signerIdentityMismatch })

        let signerOnlyLineage = Audit.ExecutionLineage(
            executor: harness.primaryLineage.executor,
            buildSHA256: harness.primaryLineage.buildSHA256,
            signerID: harness.alternateMeasurementSignerID
        )
        let signerOnlyEvidence = try makeEvidence(for: harness) { fixture, _, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id else { return }
            draft.lineage = signerOnlyLineage
            draft.signerID = harness.alternateMeasurementSignerID
            draft.signingKey = harness.alternateMeasurementKey
        }
        let signerOnlyResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: signerOnlyEvidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertTrue(signerOnlyResult.report.findings.contains { $0.code == .unapprovedExecutionLineage })

        let ambiguousLineages = replacingManifest(
            harness.manifest,
            approvedExecutionLineages: [harness.primaryLineage, signerOnlyLineage]
        )
        assertAuditError(.invalidSigningInput) {
            _ = try Audit.prepare(
                manifest: ambiguousLineages,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { false }
            )
        }
    }

    func testTrustRolesRequireDistinctIDsKeysAndCombinedSignerCap() throws {
        let harness = try AuditHarness()
        let oracleSigner = try XCTUnwrap(harness.trustPolicy.mappingOracleSigners.first)
        let measurementSigner = try XCTUnwrap(harness.trustPolicy.measurementSigners.first)
        let conflictingID = Audit.TrustedSigner(
            id: oracleSigner.id,
            publicKey: Array(harness.measurementKey.publicKey.rawRepresentation)
        )
        let conflictingKey = Audit.TrustedSigner(
            id: reference("different-measurement-signer", revision: 1).id,
            publicKey: oracleSigner.publicKey
        )
        let duplicateOracleID = Audit.TrustedSigner(
            id: oracleSigner.id,
            publicKey: Array(harness.alternateMeasurementKey.publicKey.rawRepresentation)
        )
        let duplicateOracleKey = Audit.TrustedSigner(
            id: reference("different-oracle-signer", revision: 1).id,
            publicKey: oracleSigner.publicKey
        )

        let duplicateMeasurementID = Audit.TrustedSigner(
            id: measurementSigner.id,
            publicKey: Array(harness.alternateMeasurementKey.publicKey.rawRepresentation)
        )
        let duplicateMeasurementKey = Audit.TrustedSigner(
            id: reference("different-measurement-signer", revision: 2).id,
            publicKey: measurementSigner.publicKey
        )
        for measurementSigners in [
            [conflictingID], [conflictingKey], [measurementSigner, duplicateMeasurementID],
            [measurementSigner, duplicateMeasurementKey]
        ] {
            let policy = Audit.TrustPolicy(
                approvedCodecArtifact: harness.trustPolicy.approvedCodecArtifact,
                mappingOracleSigners: [oracleSigner],
                measurementSigners: measurementSigners
            )
            assertAuditError(.invalidSigningInput) {
                _ = try Audit.prepare(
                    manifest: harness.manifest,
                    trustPolicy: policy,
                    cancellationCheck: { false }
                )
            }
        }
        for oracleSigners in [[oracleSigner, duplicateOracleID], [oracleSigner, duplicateOracleKey]] {
            let policy = Audit.TrustPolicy(
                approvedCodecArtifact: harness.trustPolicy.approvedCodecArtifact,
                mappingOracleSigners: oracleSigners,
                measurementSigners: [measurementSigner]
            )
            assertAuditError(.invalidSigningInput) {
                _ = try Audit.prepare(
                    manifest: harness.manifest,
                    trustPolicy: policy,
                    cancellationCheck: { false }
                )
            }
        }

        assertAuditError(.countLimitExceeded(.trustedSigners, maximum: 2)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumTrustedSigners: 2),
                cancellationCheck: { false }
            )
        }

        let oracleSignedByMeasurement = try signedCopy(
            try fixture(.cp932, in: harness.fixtures),
            signerID: harness.measurementSignerID,
            key: harness.measurementKey
        )
        let wrongRolePlan = try Audit.prepare(
            manifest: replacingManifest(
                harness.manifest,
                fixtures: replacingFixture(
                    try fixture(.cp932, in: harness.fixtures),
                    with: oracleSignedByMeasurement,
                    in: harness.fixtures
                )
            ),
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        assertFindingCodes(wrongRolePlan.preflightFindings, [.unverifiedMappingOracle])

        let measurementSignedByOracle = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id, request.stage == .load
            else { return }
            draft.signerID = harness.oracleSignerID
            draft.signingKey = harness.oracleKey
        }
        let wrongMeasurementRole = try Audit.evaluate(
            plan: harness.plan,
            evidence: measurementSignedByOracle,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        assertFindings(
            wrongMeasurementRole.report.findings,
            [
                (.signerIdentityMismatch, .stage(Audit.SupportedCodePage.cp932.id, .load)),
                (.unverifiedMeasurementAttestation, .stage(Audit.SupportedCodePage.cp932.id, .load)),
                (.unstableLineageSigner, .stage(Audit.SupportedCodePage.cp932.id, .compare)),
                (.unorderedStageEvidence, .stage(Audit.SupportedCodePage.cp932.id, .compare)),
                (.unorderedStageEvidence, .stage(Audit.SupportedCodePage.cp932.id, .edit)),
                (.unorderedStageEvidence, .stage(Audit.SupportedCodePage.cp932.id, .save)),
                (.unorderedStageEvidence, .stage(Audit.SupportedCodePage.cp932.id, .reload)),
                (.unorderedStageEvidence, .stage(Audit.SupportedCodePage.cp932.id, .byteComparison))
            ]
        )
    }

    func testPreparedPlanBindsTrustPolicyAndSignerOrderingIsCanonical() throws {
        let harness = try AuditHarness()
        let evidence = try makeEvidence(for: harness)
        let reordered = Audit.TrustPolicy(
            approvedCodecArtifact: harness.trustPolicy.approvedCodecArtifact,
            mappingOracleSigners: harness.trustPolicy.mappingOracleSigners.reversed(),
            measurementSigners: harness.trustPolicy.measurementSigners.reversed()
        )
        let reorderedResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: reordered,
            cancellationCheck: { false }
        )
        XCTAssertTrue(reorderedResult.report.isCompleteAndValid)
        XCTAssertEqual(reorderedResult.receipt.trustPolicySHA256, harness.plan.receipt.trustPolicySHA256)

        let replacementKey = try signingKey(seed: 0x44)
        let changedPolicy = Audit.TrustPolicy(
            approvedCodecArtifact: harness.trustPolicy.approvedCodecArtifact,
            mappingOracleSigners: harness.trustPolicy.mappingOracleSigners,
            measurementSigners: [
                Audit.TrustedSigner(
                    id: stableID("replacement-measurement-signer"),
                    publicKey: Array(replacementKey.publicKey.rawRepresentation)
                )
            ]
        )
        assertAuditError(.invalidSigningInput) {
            _ = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: changedPolicy,
                cancellationCheck: { false }
            )
        }
    }

    func testEvidenceReportAndReceiptAreDeterministicAcrossInputOrdering() throws {
        let harness = try AuditHarness()
        let evidence = try makeEvidence(for: harness) { fixture, request, draft in
            if fixture.codePage == Audit.SupportedCodePage.cp932.id && request.stage == .edit {
                let expected = fixture.expectation
                draft.observation = .edit(
                    Audit.EditObservation(
                        before: expected.original,
                        after: expected.edited,
                        mutationApplied: false,
                        unicodeScalarDelta: expected.intendedEdit
                    ))
            }
            if fixture.codePage == Audit.SupportedCodePage.cp1250.id && request.stage == .load {
                let expected = fixture.expectation
                draft.observation = .load(
                    Audit.LoadObservation(
                        automaticDetection: .rejected,
                        explicitlySelectedEncoding: Audit.SupportedCodePage.cp1251.id,
                        source: expected.original,
                        loaded: expected.original
                    ))
            }
            if fixture.codePage == Audit.SupportedCodePage.cp1251.id && request.stage == .compare {
                let original = fixture.expectation.original
                draft.observation = .compare(
                    Audit.CompareObservation(
                        left: original,
                        right: original,
                        unicodeEqual: false,
                        differenceCount: 0
                    ))
            }
        }
        let reversed = Audit.EvidenceBundle(
            reference: evidence.reference,
            manifest: evidence.manifest,
            manifestSHA256: evidence.manifestSHA256,
            stages: evidence.stages.reversed()
        )
        let forwardResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let reverseResult = try Audit.evaluate(
            plan: harness.plan,
            evidence: reversed,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )

        XCTAssertEqual(forwardResult.report, reverseResult.report)
        XCTAssertEqual(forwardResult.receipt, reverseResult.receipt)
        XCTAssertEqual(forwardResult.receipt.evidenceSHA256, reverseResult.receipt.evidenceSHA256)
        XCTAssertEqual(forwardResult.report.findings.map(\.id), reverseResult.report.findings.map(\.id))
        XCTAssertEqual(forwardResult.report.completeness.cells, reverseResult.report.completeness.cells)
        assertFindings(
            forwardResult.report.findings,
            [
                (.automaticDetectionMismatch, .stage(Audit.SupportedCodePage.cp1250.id, .load)),
                (.comparisonMismatch, .stage(Audit.SupportedCodePage.cp1251.id, .compare)),
                (.editMutationMismatch, .stage(Audit.SupportedCodePage.cp932.id, .edit)),
                (.explicitSelectionMismatch, .stage(Audit.SupportedCodePage.cp1250.id, .load))
            ]
        )
        XCTAssertEqual(
            forwardResult.report.completeness.cells.map {
                "\($0.codePage.rawValue):\($0.stage.rawValue)"
            },
            Audit.SupportedCodePage.allCases.flatMap { codePage in
                Audit.Stage.allCases.map { "\(codePage.rawValue):\($0.rawValue)" }
            }
        )
    }

    func testLimitsExactWorkCancellationAndIdentityHashingAreMetered() throws {
        let harness = try AuditHarness()

        assertAuditError(.invalidLimit(.fixtures)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumFixtures: 0),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.countLimitExceeded(.fixtures, maximum: 8)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumFixtures: 8),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.countLimitExceeded(.evidence, maximum: 53)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumEvidence: 53),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.stringTooLarge(maximumUTF8Bytes: 5)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumStringUTF8Bytes: 5),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.totalStringsTooLarge(maximumUTF8Bytes: 64)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(
                    maximumStringUTF8Bytes: 64,
                    maximumTotalStringUTF8Bytes: 64
                ),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.invalidLimit(.cancellationCheckInterval)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(cancellationCheckInterval: 0),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.countLimitExceeded(.contentBytes, maximum: 1)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumContentBytes: 1),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.countLimitExceeded(.unicodeScalars, maximum: 1)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumUnicodeScalars: 1),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.canonicalDataTooLarge(maximumBytes: 64)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumCanonicalBytes: 64),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.cancelled) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                cancellationCheck: { true }
            )
        }

        let exactWorkLimits = Audit.Limits(maximumWorkUnits: harness.plan.workPerformed)
        let exactPlan = try Audit.prepare(
            manifest: harness.manifest,
            trustPolicy: harness.trustPolicy,
            limits: exactWorkLimits,
            cancellationCheck: { false }
        )
        XCTAssertEqual(exactPlan.workPerformed, harness.plan.workPerformed)
        assertAuditError(.workLimitExceeded(maximum: harness.plan.workPerformed - 1)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumWorkUnits: harness.plan.workPerformed - 1),
                cancellationCheck: { false }
            )
        }

        let probe = CancellationProbe(cancelAt: 3)
        assertAuditError(.cancelled) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(cancellationCheckInterval: 1),
                cancellationCheck: { probe.check() }
            )
        }
        XCTAssertEqual(probe.callCount, 3)

        let longIdentityManifest = replacingManifest(
            harness.manifest,
            reference: reference("manifest-\(String(repeating: "x", count: 180))", revision: 5)
        )
        let longIdentityPlan = try Audit.prepare(
            manifest: longIdentityManifest,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        XCTAssertGreaterThan(longIdentityPlan.workPerformed, harness.plan.workPerformed)
        XCTAssertGreaterThan(
            longIdentityPlan.stringUTF8BytesProcessed,
            harness.plan.stringUTF8BytesProcessed
        )
    }

    func testEveryLimitRejectsZeroAndAboveHardMaximum() throws {
        let harness = try AuditHarness()
        let cases: [(Audit.Limit, Audit.Limits, Audit.Limits)] = [
            (
                .fixtures,
                Audit.Limits(maximumFixtures: 0),
                Audit.Limits(maximumFixtures: Audit.Limits.hardMaximumFixtures + 1)
            ),
            (
                .evidence,
                Audit.Limits(maximumEvidence: 0),
                Audit.Limits(maximumEvidence: Audit.Limits.hardMaximumEvidence + 1)
            ),
            (
                .trustedSigners,
                Audit.Limits(maximumTrustedSigners: 0),
                Audit.Limits(
                    maximumTrustedSigners: Audit.Limits.hardMaximumTrustedSigners + 1
                )
            ),
            (
                .findings,
                Audit.Limits(maximumFindings: 0),
                Audit.Limits(maximumFindings: Audit.Limits.hardMaximumFindings + 1)
            ),
            (
                .stringUTF8Bytes,
                Audit.Limits(maximumStringUTF8Bytes: 0),
                Audit.Limits(
                    maximumStringUTF8Bytes: Audit.Limits.hardMaximumStringUTF8Bytes + 1,
                    maximumTotalStringUTF8Bytes: Audit.Limits.hardMaximumStringUTF8Bytes + 1
                )
            ),
            (
                .totalStringUTF8Bytes,
                Audit.Limits(maximumTotalStringUTF8Bytes: 0),
                Audit.Limits(
                    maximumTotalStringUTF8Bytes: Audit.Limits.hardMaximumTotalStringUTF8Bytes + 1
                )
            ),
            (
                .contentBytes,
                Audit.Limits(maximumContentBytes: 0),
                Audit.Limits(maximumContentBytes: Audit.Limits.hardMaximumContentBytes + 1)
            ),
            (
                .unicodeScalars,
                Audit.Limits(maximumUnicodeScalars: 0),
                Audit.Limits(
                    maximumUnicodeScalars: Audit.Limits.hardMaximumUnicodeScalars + 1
                )
            ),
            (
                .canonicalBytes,
                Audit.Limits(maximumCanonicalBytes: 0),
                Audit.Limits(maximumCanonicalBytes: Audit.Limits.hardMaximumCanonicalBytes + 1)
            ),
            (
                .workUnits,
                Audit.Limits(maximumWorkUnits: 0),
                Audit.Limits(maximumWorkUnits: Audit.Limits.hardMaximumWorkUnits + 1)
            ),
            (
                .cancellationCheckInterval,
                Audit.Limits(cancellationCheckInterval: 0),
                Audit.Limits(
                    cancellationCheckInterval: Audit.Limits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]
        for (limit, zero, excessive) in cases {
            assertAuditError(.invalidLimit(limit)) {
                _ = try Audit.prepare(
                    manifest: harness.manifest,
                    trustPolicy: harness.trustPolicy,
                    limits: zero,
                    cancellationCheck: { false }
                )
            }
            assertAuditError(.invalidLimit(limit)) {
                _ = try Audit.prepare(
                    manifest: harness.manifest,
                    trustPolicy: harness.trustPolicy,
                    limits: excessive,
                    cancellationCheck: { false }
                )
            }
        }
        assertAuditError(.invalidLimit(.totalStringUTF8Bytes)) {
            _ = try Audit.prepare(
                manifest: harness.manifest,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(
                    maximumStringUTF8Bytes: 65,
                    maximumTotalStringUTF8Bytes: 64
                ),
                cancellationCheck: { false }
            )
        }
    }

    func testCollectionAndFindingLimitsApplyAtEvaluationBoundaries() throws {
        let harness = try AuditHarness()
        let complete = try makeEvidence(for: harness)
        let exact = try Audit.evaluate(
            plan: harness.plan,
            evidence: complete,
            trustPolicy: harness.trustPolicy,
            limits: Audit.Limits(
                maximumFixtures: harness.fixtures.count,
                maximumEvidence: complete.stages.count,
                maximumTrustedSigners: harness.trustPolicy.mappingOracleSigners.count
                    + harness.trustPolicy.measurementSigners.count,
                maximumFindings: 1
            ),
            cancellationCheck: { false }
        )
        XCTAssertTrue(exact.report.isCompleteAndValid)
        _ = try Audit.prepare(
            manifest: harness.manifest,
            trustPolicy: harness.trustPolicy,
            limits: Audit.Limits(maximumContentBytes: 2, maximumUnicodeScalars: 2),
            cancellationCheck: { false }
        )

        let extra = replacingStageEvidence(
            try XCTUnwrap(complete.stages.first),
            fixture: reference("extra-evidence", revision: 1)
        )
        assertAuditError(.countLimitExceeded(.evidence, maximum: complete.stages.count)) {
            _ = try Audit.evaluate(
                plan: harness.plan,
                evidence: replacingStages(complete, stages: complete.stages + [extra]),
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumEvidence: complete.stages.count),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.findingLimitExceeded(maximum: complete.stages.count - 1)) {
            _ = try Audit.evaluate(
                plan: harness.plan,
                evidence: replacingStages(complete, stages: []),
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumFindings: complete.stages.count - 1),
                cancellationCheck: { false }
            )
        }
        let exactFindings = try Audit.evaluate(
            plan: harness.plan,
            evidence: replacingStages(complete, stages: []),
            trustPolicy: harness.trustPolicy,
            limits: Audit.Limits(maximumFindings: complete.stages.count),
            cancellationCheck: { false }
        )
        XCTAssertEqual(exactFindings.receipt.findingCount, complete.stages.count)

        let thirdLineage = Audit.ExecutionLineage(
            executor: reference("third-executor", revision: 1),
            buildSHA256: digest("third-build"),
            signerID: harness.measurementSignerID
        )
        assertAuditError(.countLimitExceeded(.trustedSigners, maximum: 2)) {
            _ = try Audit.prepare(
                manifest: replacingManifest(
                    harness.manifest,
                    approvedExecutionLineages: [
                        harness.primaryLineage, harness.alternateLineage, thirdLineage
                    ]
                ),
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumTrustedSigners: 2),
                cancellationCheck: { false }
            )
        }
    }

    func testPublicHashingAndEvaluationCancellationAreObservable() throws {
        let harness = try AuditHarness()
        let evidence = try makeEvidence(for: harness)
        let stage = try XCTUnwrap(evidence.stages.first)
        let fixture = try XCTUnwrap(harness.fixtures.first)
        let operations: [(@escaping Audit.CancellationCheck) throws -> Void] = [
            { check in
                _ = try Audit.mappingOracleSigningPrehash(fixture, cancellationCheck: check)
            },
            { check in _ = try Audit.executionSigningPrehash(stage, cancellationCheck: check) },
            { check in _ = try Audit.stageEvidenceSHA256(stage, cancellationCheck: check) },
            { check in _ = try Audit.manifestSHA256(harness.manifest, cancellationCheck: check) },
            { check in
                _ = try Audit.evaluate(
                    plan: harness.plan,
                    evidence: evidence,
                    trustPolicy: harness.trustPolicy,
                    cancellationCheck: check
                )
            }
        ]
        for operation in operations {
            assertAuditError(.cancelled) {
                try operation({ true })
            }
        }

        let probe = CancellationProbe(cancelAt: 3)
        assertAuditError(.cancelled) {
            _ = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(cancellationCheckInterval: 1),
                cancellationCheck: { probe.check() }
            )
        }
        XCTAssertEqual(probe.callCount, 3)
    }

    func testEvaluationUsesCumulativeExactWorkLimitIncludingLongIdentities() throws {
        let harness = try AuditHarness()
        let evidence = try makeEvidence(for: harness)
        let exactMinimum = try minimumEvaluationWork(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy
        )
        XCTAssertGreaterThan(exactMinimum, harness.plan.workPerformed)
        _ = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            limits: Audit.Limits(maximumWorkUnits: exactMinimum),
            cancellationCheck: { false }
        )
        assertAuditError(.workLimitExceeded(maximum: exactMinimum - 1)) {
            _ = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumWorkUnits: exactMinimum - 1),
                cancellationCheck: { false }
            )
        }

        let exactStringMinimum = try minimumEvaluationStringBytes(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy
        )
        _ = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            limits: Audit.Limits(
                maximumStringUTF8Bytes: Audit.maximumIdentifierUTF8Bytes,
                maximumTotalStringUTF8Bytes: exactStringMinimum
            ),
            cancellationCheck: { false }
        )
        assertAuditError(.totalStringsTooLarge(maximumUTF8Bytes: exactStringMinimum - 1)) {
            _ = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(
                    maximumStringUTF8Bytes: Audit.maximumIdentifierUTF8Bytes,
                    maximumTotalStringUTF8Bytes: exactStringMinimum - 1
                ),
                cancellationCheck: { false }
            )
        }
        let exactCanonicalMinimum = try minimumEvaluationCanonicalBytes(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy
        )
        _ = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            limits: Audit.Limits(maximumCanonicalBytes: exactCanonicalMinimum),
            cancellationCheck: { false }
        )
        assertAuditError(.canonicalDataTooLarge(maximumBytes: exactCanonicalMinimum - 1)) {
            _ = try Audit.evaluate(
                plan: harness.plan,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumCanonicalBytes: exactCanonicalMinimum - 1),
                cancellationCheck: { false }
            )
        }
        _ = try Audit.evaluate(
            manifest: harness.manifest,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            limits: Audit.Limits(maximumWorkUnits: exactMinimum),
            cancellationCheck: { false }
        )
        assertAuditError(.workLimitExceeded(maximum: exactMinimum - 1)) {
            _ = try Audit.evaluate(
                manifest: harness.manifest,
                evidence: evidence,
                trustPolicy: harness.trustPolicy,
                limits: Audit.Limits(maximumWorkUnits: exactMinimum - 1),
                cancellationCheck: { false }
            )
        }

        let padded = try AuditHarness(idPadding: String(repeating: "x", count: 128))
        let paddedEvidence = try makeEvidence(for: padded)
        let paddedMinimum = try minimumEvaluationWork(
            plan: padded.plan,
            evidence: paddedEvidence,
            trustPolicy: padded.trustPolicy
        )
        XCTAssertGreaterThan(paddedMinimum, exactMinimum)
        XCTAssertGreaterThan(padded.plan.stringUTF8BytesProcessed, harness.plan.stringUTF8BytesProcessed)
    }

    func testDescriptionsDebugMirrorsAndErrorsRedactSensitiveIdentityAndHashes() throws {
        let harness = try AuditHarness()
        let evidence = try makeEvidence(for: harness) { fixture, request, draft in
            guard fixture.codePage == Audit.SupportedCodePage.cp932.id,
                request.stage == .compare
            else { return }
            let original = fixture.expectation.original
            draft.observation = .compare(
                Audit.CompareObservation(
                    left: original,
                    right: original,
                    unicodeEqual: false,
                    differenceCount: 1
                )
            )
        }
        let result = try Audit.evaluate(
            plan: harness.plan,
            evidence: evidence,
            trustPolicy: harness.trustPolicy,
            cancellationCheck: { false }
        )
        let fixture = try XCTUnwrap(harness.fixtures.first)
        let stage = try XCTUnwrap(evidence.stages.first)
        let attestation = try XCTUnwrap(stage.attestation)
        let secrets = [
            fixture.reference.id.rawValue,
            fixture.mappingOracle.sourceIdentifier,
            hex(fixture.fixtureArtifactSHA256),
            fixture.mappingOracle.signature.signerID.rawValue,
            hex(fixture.mappingOracle.signature.bytes),
            harness.primaryLineage.executor.id.rawValue,
            hex(harness.primaryLineage.buildSHA256),
            hex(harness.runSHA256),
            hex(attestation.signature.bytes)
        ]
        let values: [Any] = [
            fixture.reference.id,
            fixture.reference,
            fixture.fixtureArtifactSHA256,
            fixture.expectation.original,
            fixture.mappingOracle.signature,
            fixture.mappingOracle,
            fixture,
            harness.manifest,
            try XCTUnwrap(harness.trustPolicy.mappingOracleSigners.first),
            harness.trustPolicy,
            harness.primaryLineage,
            attestation.execution,
            attestation,
            try XCTUnwrap(harness.plan.requests.first),
            try XCTUnwrap(harness.plan.fixtureVerifications.first),
            harness.plan.receipt,
            harness.plan,
            stage,
            evidence,
            result.report,
            try XCTUnwrap(result.report.findings.first),
            result.receipt
        ]

        for value in values {
            let rendering = render(value)
            for secret in secrets {
                XCTAssertFalse(rendering.contains(secret), "Public rendering leaked private sentinel")
            }
            XCTAssertTrue(rendering.contains("<redacted>"))
        }

        let oversized = String(repeating: "SENSITIVE", count: 100)
        let invalidOracle = replacingOracle(fixture.mappingOracle, sourceIdentifier: oversized)
        let invalidFixture = Audit.Fixture(
            reference: fixture.reference,
            codePage: fixture.codePage,
            fixtureArtifactSHA256: fixture.fixtureArtifactSHA256,
            mappingOracle: invalidOracle,
            expectation: fixture.expectation
        )
        do {
            _ = try Audit.mappingOracleSigningPrehash(
                invalidFixture,
                limits: Audit.Limits(maximumStringUTF8Bytes: 32),
                cancellationCheck: { false }
            )
            XCTFail("Expected bounded metadata rejection")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(oversized))
            XCTAssertTrue(error.localizedDescription.contains("redacted"))
        }
    }
}

private typealias Audit = CodePageLifecycleAudit
private typealias SigningKey = Curve25519.Signing.PrivateKey

private struct AuditHarness {
    let oracleKey: SigningKey
    let measurementKey: SigningKey
    let alternateMeasurementKey: SigningKey
    let oracleSignerID: Audit.StableID
    let measurementSignerID: Audit.StableID
    let alternateMeasurementSignerID: Audit.StableID
    let primaryLineage: Audit.ExecutionLineage
    let alternateLineage: Audit.ExecutionLineage
    let runSHA256: Audit.SHA256Digest
    let fixtures: [Audit.Fixture]
    let manifest: Audit.Manifest
    let trustPolicy: Audit.TrustPolicy
    let plan: Audit.Plan

    init(idPadding: String = "") throws {
        let oracleKey = try signingKey(seed: 0x11)
        let measurementKey = try signingKey(seed: 0x22)
        let alternateMeasurementKey = try signingKey(seed: 0x33)
        let oracleSignerID = stableID("oracle-signer\(idPadding)")
        let measurementSignerID = stableID("measurement-signer\(idPadding)")
        let alternateMeasurementSignerID = stableID("alternate-signer\(idPadding)")
        self.oracleKey = oracleKey
        self.measurementKey = measurementKey
        self.alternateMeasurementKey = alternateMeasurementKey
        self.oracleSignerID = oracleSignerID
        self.measurementSignerID = measurementSignerID
        self.alternateMeasurementSignerID = alternateMeasurementSignerID

        let executor = reference("private-executor-token\(idPadding)", revision: 7)
        primaryLineage = Audit.ExecutionLineage(
            executor: executor,
            buildSHA256: digest("primary-build\(idPadding)"),
            signerID: measurementSignerID
        )
        alternateLineage = Audit.ExecutionLineage(
            executor: executor,
            buildSHA256: digest("alternate-build\(idPadding)"),
            signerID: alternateMeasurementSignerID
        )
        runSHA256 = digest("execution-run\(idPadding)")
        fixtures = try Audit.SupportedCodePage.allCases.enumerated().map { offset, codePage in
            try makeFixture(
                codePage: codePage,
                offset: offset,
                oracleSignerID: oracleSignerID,
                oracleKey: oracleKey,
                idPadding: idPadding
            )
        }

        let codec = reference("codec\(idPadding)", revision: 3)
        let codecArtifactSHA256 = digest("codec-artifact\(idPadding)")
        manifest = Audit.Manifest(
            reference: reference("manifest\(idPadding)", revision: 5),
            codec: codec,
            codecArtifactSHA256: codecArtifactSHA256,
            approvedExecutionLineages: [primaryLineage, alternateLineage],
            fixtures: fixtures
        )
        trustPolicy = Audit.TrustPolicy(
            approvedCodecArtifact: Audit.CodecArtifactIdentity(
                codec: codec,
                artifactSHA256: codecArtifactSHA256
            ),
            mappingOracleSigners: [
                Audit.TrustedSigner(
                    id: oracleSignerID,
                    publicKey: Array(oracleKey.publicKey.rawRepresentation)
                )
            ],
            measurementSigners: [
                Audit.TrustedSigner(
                    id: measurementSignerID,
                    publicKey: Array(measurementKey.publicKey.rawRepresentation)
                ),
                Audit.TrustedSigner(
                    id: alternateMeasurementSignerID,
                    publicKey: Array(alternateMeasurementKey.publicKey.rawRepresentation)
                )
            ]
        )
        plan = try Audit.prepare(
            manifest: manifest,
            trustPolicy: trustPolicy,
            cancellationCheck: { false }
        )
    }
}

private struct EvidenceDraft {
    var bundle: Audit.RevisionReference
    var bundleManifestSHA256: Audit.SHA256Digest
    var requestSHA256: Audit.SHA256Digest
    var observation: Audit.Observation
    var origin: Audit.EvidenceOrigin
    var lineage: Audit.ExecutionLineage
    var runSHA256: Audit.SHA256Digest
    var monotonicSequence: UInt64
    var previousEvidenceSHA256: Audit.SHA256Digest?
    var signerID: Audit.StableID
    var signingKey: SigningKey
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAt: Int
    private var calls = 0

    init(cancelAt: Int) {
        self.cancelAt = cancelAt
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func check() -> Bool {
        lock.withLock {
            calls += 1
            return calls >= cancelAt
        }
    }
}

private func signingKey(seed: UInt8) throws -> SigningKey {
    try SigningKey(rawRepresentation: Data(repeating: seed, count: 32))
}

private func stableID(_ value: String) -> Audit.StableID {
    Audit.StableID(rawValue: value)
}

private func reference(_ value: String, revision: UInt64) -> Audit.RevisionReference {
    Audit.RevisionReference(id: stableID(value), revision: revision)
}

private func digest(_ label: String) -> Audit.SHA256Digest {
    digest(Array(label.utf8))
}

private func digest(_ bytes: [UInt8]) -> Audit.SHA256Digest {
    try! Audit.SHA256Digest(bytes: Array(SHA256.hash(data: Data(bytes))))
}

private func scalarDigest(_ scalars: [UInt32]) -> Audit.SHA256Digest {
    var data = Data()
    data.reserveCapacity(scalars.count * MemoryLayout<UInt32>.size)
    for scalar in scalars {
        var bigEndian = scalar.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    return digest(Array(data))
}

private func content(bytes: [UInt8], scalars: [UInt32]) -> Audit.ContentHash {
    Audit.ContentHash(
        bytes: Audit.ByteHash(byteCount: bytes.count, sha256: digest(bytes)),
        unicode: Audit.UnicodeHash(scalarCount: scalars.count, sha256: scalarDigest(scalars))
    )
}

private func makeFixture(
    codePage: Audit.SupportedCodePage,
    offset: Int,
    oracleSignerID: Audit.StableID,
    oracleKey: SigningKey,
    idPadding: String
) throws -> Audit.Fixture {
    let originalByte = UInt8(0x41 + offset)
    let originalScalar = UInt32(originalByte)
    let insertedByte = UInt8(0x61 + offset)
    let insertedScalar = UInt32(insertedByte)
    let original = content(bytes: [originalByte], scalars: [originalScalar])
    let edited = content(
        bytes: [originalByte, insertedByte],
        scalars: [originalScalar, insertedScalar]
    )
    let expectation = Audit.FixtureExpectation(
        original: original,
        edited: edited,
        saved: edited,
        reloaded: edited,
        selection: Audit.SelectionExpectation(
            automaticDetection: .selected(codePage.id),
            explicitSelection: codePage.id
        ),
        intendedEdit: Audit.UnicodeScalarEdit(
            unchangedPrefix: [originalScalar],
            removedScalars: [],
            insertedScalars: [insertedScalar],
            unchangedSuffix: []
        )
    )
    return try signedFixture(
        reference: reference("fixture-\(codePage.rawValue)\(idPadding)", revision: 1),
        codePage: codePage.id,
        fixtureArtifactSHA256: original.bytes.sha256,
        oracleReference: reference("oracle-\(codePage.rawValue)\(idPadding)", revision: 2),
        sourceIdentifier: "test-oracle-source-\(codePage.rawValue)\(idPadding)",
        sourceArtifactSHA256: digest("oracle-source-\(codePage.rawValue)\(idPadding)"),
        mappingTableSHA256: digest("mapping-table-\(codePage.rawValue)\(idPadding)"),
        mappingCardinality: codePage.expectedMappingCardinality,
        fixtureScalarCommitments: Audit.FixtureScalarCommitments(expectation: expectation),
        expectation: expectation,
        signerID: oracleSignerID,
        key: oracleKey
    )
}

private func signedFixture(
    reference: Audit.RevisionReference,
    codePage: Audit.CodePageID,
    oracleCodePage: Audit.CodePageID? = nil,
    fixtureArtifactSHA256: Audit.SHA256Digest,
    oracleReference: Audit.RevisionReference,
    sourceIdentifier: String,
    sourceArtifactSHA256: Audit.SHA256Digest,
    mappingTableSHA256: Audit.SHA256Digest,
    mappingCardinality: Int,
    fixtureScalarCommitments: Audit.FixtureScalarCommitments,
    expectation: Audit.FixtureExpectation,
    signerID: Audit.StableID,
    key: SigningKey
) throws -> Audit.Fixture {
    let unsignedOracle = Audit.MappingOracle(
        reference: oracleReference,
        codePage: oracleCodePage ?? codePage,
        sourceIdentifier: sourceIdentifier,
        sourceArtifactSHA256: sourceArtifactSHA256,
        mappingTableSHA256: mappingTableSHA256,
        mappingCardinality: mappingCardinality,
        fixtureScalarCommitments: fixtureScalarCommitments,
        signature: Audit.Signature(signerID: signerID, bytes: [])
    )
    let unsignedFixture = Audit.Fixture(
        reference: reference,
        codePage: codePage,
        fixtureArtifactSHA256: fixtureArtifactSHA256,
        mappingOracle: unsignedOracle,
        expectation: expectation
    )
    let prehash = try Audit.mappingOracleSigningPrehash(unsignedFixture, cancellationCheck: { false })
    let signature = try key.signature(for: Data(prehash.bytes))
    let signedOracle = Audit.MappingOracle(
        reference: oracleReference,
        codePage: oracleCodePage ?? codePage,
        sourceIdentifier: sourceIdentifier,
        sourceArtifactSHA256: sourceArtifactSHA256,
        mappingTableSHA256: mappingTableSHA256,
        mappingCardinality: mappingCardinality,
        fixtureScalarCommitments: fixtureScalarCommitments,
        signature: Audit.Signature(signerID: signerID, bytes: Array(signature))
    )
    return Audit.Fixture(
        reference: reference,
        codePage: codePage,
        fixtureArtifactSHA256: fixtureArtifactSHA256,
        mappingOracle: signedOracle,
        expectation: expectation
    )
}

private func resignedFixture(
    _ fixture: Audit.Fixture,
    selection: Audit.SelectionExpectation,
    signerID: Audit.StableID,
    key: SigningKey
) throws -> Audit.Fixture {
    let old = fixture.expectation
    let expectation = Audit.FixtureExpectation(
        original: old.original,
        edited: old.edited,
        saved: old.saved,
        reloaded: old.reloaded,
        selection: selection,
        intendedEdit: old.intendedEdit
    )
    let oracle = fixture.mappingOracle
    return try signedFixture(
        reference: fixture.reference,
        codePage: fixture.codePage,
        fixtureArtifactSHA256: fixture.fixtureArtifactSHA256,
        oracleReference: oracle.reference,
        sourceIdentifier: oracle.sourceIdentifier,
        sourceArtifactSHA256: oracle.sourceArtifactSHA256,
        mappingTableSHA256: oracle.mappingTableSHA256,
        mappingCardinality: oracle.mappingCardinality,
        fixtureScalarCommitments: Audit.FixtureScalarCommitments(expectation: expectation),
        expectation: expectation,
        signerID: signerID,
        key: key
    )
}

private func signedCopy(
    _ fixture: Audit.Fixture,
    reference: Audit.RevisionReference? = nil,
    codePage: Audit.CodePageID? = nil,
    fixtureArtifactSHA256: Audit.SHA256Digest? = nil,
    oracleReference: Audit.RevisionReference? = nil,
    oracleCodePage: Audit.CodePageID? = nil,
    sourceIdentifier: String? = nil,
    sourceArtifactSHA256: Audit.SHA256Digest? = nil,
    mappingTableSHA256: Audit.SHA256Digest? = nil,
    mappingCardinality: Int? = nil,
    fixtureScalarCommitments: Audit.FixtureScalarCommitments? = nil,
    expectation: Audit.FixtureExpectation? = nil,
    signerID: Audit.StableID,
    key: SigningKey
) throws -> Audit.Fixture {
    let oracle = fixture.mappingOracle
    return try signedFixture(
        reference: reference ?? fixture.reference,
        codePage: codePage ?? fixture.codePage,
        oracleCodePage: oracleCodePage ?? oracle.codePage,
        fixtureArtifactSHA256: fixtureArtifactSHA256 ?? fixture.fixtureArtifactSHA256,
        oracleReference: oracleReference ?? oracle.reference,
        sourceIdentifier: sourceIdentifier ?? oracle.sourceIdentifier,
        sourceArtifactSHA256: sourceArtifactSHA256 ?? oracle.sourceArtifactSHA256,
        mappingTableSHA256: mappingTableSHA256 ?? oracle.mappingTableSHA256,
        mappingCardinality: mappingCardinality ?? oracle.mappingCardinality,
        fixtureScalarCommitments: fixtureScalarCommitments ?? oracle.fixtureScalarCommitments,
        expectation: expectation ?? fixture.expectation,
        signerID: signerID,
        key: key
    )
}

private func replacingOracle(
    _ oracle: Audit.MappingOracle,
    reference: Audit.RevisionReference? = nil,
    codePage: Audit.CodePageID? = nil,
    sourceIdentifier: String? = nil,
    sourceArtifactSHA256: Audit.SHA256Digest? = nil,
    mappingTableSHA256: Audit.SHA256Digest? = nil,
    mappingCardinality: Int? = nil,
    fixtureScalarCommitments: Audit.FixtureScalarCommitments? = nil,
    signerID: Audit.StableID? = nil
) -> Audit.MappingOracle {
    Audit.MappingOracle(
        reference: reference ?? oracle.reference,
        codePage: codePage ?? oracle.codePage,
        sourceIdentifier: sourceIdentifier ?? oracle.sourceIdentifier,
        sourceArtifactSHA256: sourceArtifactSHA256 ?? oracle.sourceArtifactSHA256,
        mappingTableSHA256: mappingTableSHA256 ?? oracle.mappingTableSHA256,
        mappingCardinality: mappingCardinality ?? oracle.mappingCardinality,
        fixtureScalarCommitments: fixtureScalarCommitments ?? oracle.fixtureScalarCommitments,
        signature: Audit.Signature(
            signerID: signerID ?? oracle.signature.signerID,
            bytes: oracle.signature.bytes
        )
    )
}

private func replacingExpectation(
    _ expectation: Audit.FixtureExpectation,
    original: Audit.ContentHash? = nil,
    edited: Audit.ContentHash? = nil,
    saved: Audit.ContentHash? = nil,
    reloaded: Audit.ContentHash? = nil,
    selection: Audit.SelectionExpectation? = nil,
    intendedEdit: Audit.UnicodeScalarEdit? = nil
) -> Audit.FixtureExpectation {
    Audit.FixtureExpectation(
        original: original ?? expectation.original,
        edited: edited ?? expectation.edited,
        saved: saved ?? expectation.saved,
        reloaded: reloaded ?? expectation.reloaded,
        selection: selection ?? expectation.selection,
        intendedEdit: intendedEdit ?? expectation.intendedEdit
    )
}

private func replacingFixture(
    _ fixture: Audit.Fixture,
    reference: Audit.RevisionReference? = nil,
    codePage: Audit.CodePageID? = nil,
    fixtureArtifactSHA256: Audit.SHA256Digest? = nil,
    mappingOracle: Audit.MappingOracle? = nil,
    expectation: Audit.FixtureExpectation? = nil
) -> Audit.Fixture {
    Audit.Fixture(
        reference: reference ?? fixture.reference,
        codePage: codePage ?? fixture.codePage,
        fixtureArtifactSHA256: fixtureArtifactSHA256 ?? fixture.fixtureArtifactSHA256,
        mappingOracle: mappingOracle ?? fixture.mappingOracle,
        expectation: expectation ?? fixture.expectation
    )
}

private func replacingOracleSignature(
    _ oracle: Audit.MappingOracle,
    bytes: [UInt8]
) -> Audit.MappingOracle {
    Audit.MappingOracle(
        reference: oracle.reference,
        codePage: oracle.codePage,
        sourceIdentifier: oracle.sourceIdentifier,
        sourceArtifactSHA256: oracle.sourceArtifactSHA256,
        mappingTableSHA256: oracle.mappingTableSHA256,
        mappingCardinality: oracle.mappingCardinality,
        fixtureScalarCommitments: oracle.fixtureScalarCommitments,
        signature: Audit.Signature(signerID: oracle.signature.signerID, bytes: bytes)
    )
}

private func replacingManifest(
    _ manifest: Audit.Manifest,
    reference: Audit.RevisionReference? = nil,
    codecArtifactSHA256: Audit.SHA256Digest? = nil,
    sessionEncodingSchemaVersion: Int? = nil,
    declaredSupportedCodePages: [Audit.CodePageID]? = nil,
    codecSessionMappings: [Audit.CodecSessionMapping]? = nil,
    approvedExecutionLineages: [Audit.ExecutionLineage]? = nil,
    fixtures: [Audit.Fixture]? = nil
) -> Audit.Manifest {
    Audit.Manifest(
        reference: reference ?? manifest.reference,
        codec: manifest.codec,
        codecArtifactSHA256: codecArtifactSHA256 ?? manifest.codecArtifactSHA256,
        sessionEncodingSchemaVersion: sessionEncodingSchemaVersion ?? manifest.sessionEncodingSchemaVersion,
        declaredSupportedCodePages: declaredSupportedCodePages ?? manifest.declaredSupportedCodePages,
        codecSessionMappings: codecSessionMappings ?? manifest.codecSessionMappings,
        approvedExecutionLineages: approvedExecutionLineages ?? manifest.approvedExecutionLineages,
        fixtures: fixtures ?? manifest.fixtures
    )
}

private func replacingFixture(
    _ original: Audit.Fixture,
    with replacement: Audit.Fixture,
    in fixtures: [Audit.Fixture]
) -> [Audit.Fixture] {
    fixtures.map { $0.reference == original.reference && $0.codePage == original.codePage ? replacement : $0 }
}

private func fixture(
    _ codePage: Audit.SupportedCodePage,
    in fixtures: [Audit.Fixture]
) throws -> Audit.Fixture {
    try XCTUnwrap(fixtures.first { $0.codePage == codePage.id })
}

private func matchingObservation(
    for fixture: Audit.Fixture,
    stage: Audit.Stage
) -> Audit.Observation {
    let expected = fixture.expectation
    switch stage {
    case .load:
        return .load(
            Audit.LoadObservation(
                automaticDetection: expected.selection.automaticDetection,
                explicitlySelectedEncoding: expected.selection.explicitSelection,
                source: expected.original,
                loaded: expected.original
            )
        )
    case .compare:
        return .compare(
            Audit.CompareObservation(
                left: expected.original,
                right: expected.original,
                unicodeEqual: true,
                differenceCount: 0
            )
        )
    case .edit:
        return .edit(
            Audit.EditObservation(
                before: expected.original,
                after: expected.edited,
                mutationApplied: true,
                unicodeScalarDelta: expected.intendedEdit
            )
        )
    case .save:
        return .save(
            Audit.SaveObservation(
                edited: expected.edited,
                saved: expected.saved,
                selectedEncoding: expected.selection.explicitSelection
            )
        )
    case .reload:
        return .reload(
            Audit.ReloadObservation(
                saved: expected.saved,
                reloaded: expected.reloaded,
                selectedEncoding: expected.selection.explicitSelection
            )
        )
    case .byteComparison:
        return .byteComparison(
            Audit.ByteComparisonObservation(
                saved: expected.saved,
                reloaded: expected.reloaded,
                bytesEqual: true
            )
        )
    }
}

private func makeEvidence(
    for harness: AuditHarness,
    fixtures suppliedFixtures: [Audit.Fixture]? = nil,
    manifest suppliedManifest: Audit.Manifest? = nil,
    plan suppliedPlan: Audit.Plan? = nil,
    mutate: (Audit.Fixture, Audit.StageRequest, inout EvidenceDraft) -> Void = { _, _, _ in }
) throws -> Audit.EvidenceBundle {
    let fixtures = suppliedFixtures ?? harness.fixtures
    let manifest = suppliedManifest ?? harness.manifest
    let plan = suppliedPlan ?? harness.plan
    let bundleReference = reference("evidence-bundle", revision: 1)
    var stages: [Audit.StageEvidence] = []
    for fixture in fixtures {
        let requests = plan.requests.filter {
            $0.fixture == fixture.reference && $0.codePage == fixture.codePage
        }.sorted { $0.stage < $1.stage }
        var previousEvidenceSHA256: Audit.SHA256Digest?
        for (offset, request) in requests.enumerated() {
            var draft = EvidenceDraft(
                bundle: bundleReference,
                bundleManifestSHA256: plan.manifestSHA256,
                requestSHA256: request.requestSHA256,
                observation: matchingObservation(for: fixture, stage: request.stage),
                origin: .automatedMeasurement,
                lineage: harness.primaryLineage,
                runSHA256: harness.runSHA256,
                monotonicSequence: UInt64(offset + 1),
                previousEvidenceSHA256: previousEvidenceSHA256,
                signerID: harness.measurementSignerID,
                signingKey: harness.measurementKey
            )
            mutate(fixture, request, &draft)
            let unsigned = Audit.StageEvidence(
                bundle: draft.bundle,
                bundleManifestSHA256: draft.bundleManifestSHA256,
                fixture: fixture.reference,
                codePage: fixture.codePage,
                requestedStage: request.stage,
                requestSHA256: draft.requestSHA256,
                observation: draft.observation,
                origin: draft.origin,
                attestation: Audit.ExecutionAttestation(
                    execution: Audit.ExecutionRun(
                        lineage: draft.lineage,
                        runSHA256: draft.runSHA256
                    ),
                    monotonicSequence: draft.monotonicSequence,
                    previousEvidenceSHA256: draft.previousEvidenceSHA256,
                    signature: Audit.Signature(signerID: draft.signerID, bytes: [])
                )
            )
            let prehash = try Audit.executionSigningPrehash(unsigned, cancellationCheck: { false })
            let signature = try draft.signingKey.signature(for: Data(prehash.bytes))
            let signed = Audit.StageEvidence(
                bundle: unsigned.bundle,
                bundleManifestSHA256: unsigned.bundleManifestSHA256,
                fixture: unsigned.fixture,
                codePage: unsigned.codePage,
                requestedStage: unsigned.requestedStage,
                requestSHA256: unsigned.requestSHA256,
                observation: unsigned.observation,
                origin: unsigned.origin,
                attestation: Audit.ExecutionAttestation(
                    execution: try XCTUnwrap(unsigned.attestation).execution,
                    monotonicSequence: draft.monotonicSequence,
                    previousEvidenceSHA256: draft.previousEvidenceSHA256,
                    signature: Audit.Signature(signerID: draft.signerID, bytes: Array(signature))
                )
            )
            stages.append(signed)
            previousEvidenceSHA256 = try Audit.stageEvidenceSHA256(signed, cancellationCheck: { false })
        }
    }
    return Audit.EvidenceBundle(
        reference: bundleReference,
        manifest: manifest.reference,
        manifestSHA256: plan.manifestSHA256,
        stages: stages
    )
}

private func replacingStageEvidence(
    _ evidence: Audit.StageEvidence,
    bundle: Audit.RevisionReference? = nil,
    bundleManifestSHA256: Audit.SHA256Digest? = nil,
    fixture: Audit.RevisionReference? = nil,
    codePage: Audit.CodePageID? = nil,
    requestedStage: Audit.Stage? = nil,
    requestSHA256: Audit.SHA256Digest? = nil,
    observation: Audit.Observation? = nil,
    origin: Audit.EvidenceOrigin? = nil,
    attestation: Audit.ExecutionAttestation? = nil
) -> Audit.StageEvidence {
    Audit.StageEvidence(
        bundle: bundle ?? evidence.bundle,
        bundleManifestSHA256: bundleManifestSHA256 ?? evidence.bundleManifestSHA256,
        fixture: fixture ?? evidence.fixture,
        codePage: codePage ?? evidence.codePage,
        requestedStage: requestedStage ?? evidence.requestedStage,
        requestSHA256: requestSHA256 ?? evidence.requestSHA256,
        observation: observation ?? evidence.observation,
        origin: origin ?? evidence.origin,
        attestation: attestation ?? evidence.attestation
    )
}

private func replacingAttestation(
    _ evidence: Audit.StageEvidence,
    execution: Audit.ExecutionRun? = nil,
    monotonicSequence: UInt64? = nil,
    previousEvidenceSHA256: Audit.SHA256Digest?? = nil,
    signerID: Audit.StableID? = nil,
    signatureBytes: [UInt8]? = nil
) -> Audit.StageEvidence {
    let old = evidence.attestation!
    return replacingStageEvidence(
        evidence,
        attestation: Audit.ExecutionAttestation(
            execution: execution ?? old.execution,
            monotonicSequence: monotonicSequence ?? old.monotonicSequence,
            previousEvidenceSHA256: previousEvidenceSHA256 ?? old.previousEvidenceSHA256,
            signature: Audit.Signature(
                signerID: signerID ?? old.signature.signerID,
                bytes: signatureBytes ?? old.signature.bytes
            )
        )
    )
}

private func withoutAttestation(_ evidence: Audit.StageEvidence) -> Audit.StageEvidence {
    Audit.StageEvidence(
        bundle: evidence.bundle,
        bundleManifestSHA256: evidence.bundleManifestSHA256,
        fixture: evidence.fixture,
        codePage: evidence.codePage,
        requestedStage: evidence.requestedStage,
        requestSHA256: evidence.requestSHA256,
        observation: evidence.observation,
        origin: evidence.origin,
        attestation: nil
    )
}

private func replacingStages(
    _ evidence: Audit.EvidenceBundle,
    stages: [Audit.StageEvidence]
) -> Audit.EvidenceBundle {
    Audit.EvidenceBundle(
        reference: evidence.reference,
        manifest: evidence.manifest,
        manifestSHA256: evidence.manifestSHA256,
        stages: stages
    )
}

private func unsignedEvidence(
    bundle: Audit.RevisionReference,
    request: Audit.StageRequest,
    observation: Audit.Observation,
    lineage: Audit.ExecutionLineage,
    runSHA256: Audit.SHA256Digest,
    signerID: Audit.StableID
) -> Audit.StageEvidence {
    Audit.StageEvidence(
        bundle: bundle,
        bundleManifestSHA256: request.manifestSHA256,
        fixture: request.fixture,
        codePage: request.codePage,
        requestedStage: request.stage,
        requestSHA256: request.requestSHA256,
        observation: observation,
        origin: .automatedMeasurement,
        attestation: Audit.ExecutionAttestation(
            execution: Audit.ExecutionRun(lineage: lineage, runSHA256: runSHA256),
            monotonicSequence: 1,
            previousEvidenceSHA256: nil,
            signature: Audit.Signature(signerID: signerID, bytes: [])
        )
    )
}

private func replacingSignature(
    _ evidence: Audit.StageEvidence,
    bytes: [UInt8]
) -> Audit.StageEvidence {
    let attestation = evidence.attestation!
    return Audit.StageEvidence(
        bundle: evidence.bundle,
        bundleManifestSHA256: evidence.bundleManifestSHA256,
        fixture: evidence.fixture,
        codePage: evidence.codePage,
        requestedStage: evidence.requestedStage,
        requestSHA256: evidence.requestSHA256,
        observation: evidence.observation,
        origin: evidence.origin,
        attestation: Audit.ExecutionAttestation(
            execution: attestation.execution,
            monotonicSequence: attestation.monotonicSequence,
            previousEvidenceSHA256: attestation.previousEvidenceSHA256,
            signature: Audit.Signature(signerID: attestation.signature.signerID, bytes: bytes)
        )
    )
}

private func status(
    in result: Audit.Result,
    codePage: Audit.SupportedCodePage,
    stage: Audit.Stage
) -> Audit.CompletenessStatus? {
    result.report.completeness.cells.first {
        $0.codePage == codePage && $0.stage == stage
    }?.status
}

private func assertAuditError<T>(
    _ expected: Audit.AuditError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> T
) {
    XCTAssertThrowsError(try operation(), file: file, line: line) { error in
        XCTAssertEqual(error as? Audit.AuditError, expected, file: file, line: line)
    }
}

private func minimumEvaluationWork(
    plan: Audit.Plan,
    evidence: Audit.EvidenceBundle,
    trustPolicy: Audit.TrustPolicy
) throws -> UInt64 {
    var lower = plan.workPerformed
    var upper = Audit.Limits.default.maximumWorkUnits
    while lower < upper {
        let midpoint = lower + (upper - lower) / 2
        do {
            _ = try Audit.evaluate(
                plan: plan,
                evidence: evidence,
                trustPolicy: trustPolicy,
                limits: Audit.Limits(maximumWorkUnits: midpoint),
                cancellationCheck: { false }
            )
            upper = midpoint
        } catch Audit.AuditError.workLimitExceeded {
            lower = midpoint + 1
        }
    }
    return lower
}

private func minimumEvaluationStringBytes(
    plan: Audit.Plan,
    evidence: Audit.EvidenceBundle,
    trustPolicy: Audit.TrustPolicy
) throws -> Int {
    var lower = max(Audit.maximumIdentifierUTF8Bytes, plan.stringUTF8BytesProcessed)
    var upper = Audit.Limits.default.maximumTotalStringUTF8Bytes
    while lower < upper {
        let midpoint = lower + (upper - lower) / 2
        do {
            _ = try Audit.evaluate(
                plan: plan,
                evidence: evidence,
                trustPolicy: trustPolicy,
                limits: Audit.Limits(
                    maximumStringUTF8Bytes: Audit.maximumIdentifierUTF8Bytes,
                    maximumTotalStringUTF8Bytes: midpoint
                ),
                cancellationCheck: { false }
            )
            upper = midpoint
        } catch Audit.AuditError.totalStringsTooLarge {
            lower = midpoint + 1
        }
    }
    return lower
}

private func minimumEvaluationCanonicalBytes(
    plan: Audit.Plan,
    evidence: Audit.EvidenceBundle,
    trustPolicy: Audit.TrustPolicy
) throws -> Int {
    var lower = 1
    var upper = Audit.Limits.default.maximumCanonicalBytes
    while lower < upper {
        let midpoint = lower + (upper - lower) / 2
        do {
            _ = try Audit.evaluate(
                plan: plan,
                evidence: evidence,
                trustPolicy: trustPolicy,
                limits: Audit.Limits(maximumCanonicalBytes: midpoint),
                cancellationCheck: { false }
            )
            upper = midpoint
        } catch Audit.AuditError.canonicalDataTooLarge {
            lower = midpoint + 1
        }
    }
    return lower
}

private func assertFindingCodes(
    _ findings: [Audit.Finding],
    _ expected: [Audit.FindingCode],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(findings.map(\.code).sorted(by: findingCodeLess), expected.sorted(by: findingCodeLess), file: file, line: line)
    assertCanonicalFindingOrder(findings, file: file, line: line)
}

private func assertFindings(
    _ findings: [Audit.Finding],
    _ expected: [(Audit.FindingCode, Audit.FindingSubject)],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(findings.count, expected.count, file: file, line: line)
    XCTAssertTrue(findings.allSatisfy { $0.severity == .error }, file: file, line: line)
    for (code, subject) in expected {
        XCTAssertEqual(
            findings.filter { $0.code == code && $0.subject == subject }.count,
            1,
            "Missing or duplicate finding \(code) for \(subject)",
            file: file,
            line: line
        )
    }
    assertCanonicalFindingOrder(findings, file: file, line: line)
}

private func assertCanonicalFindingOrder(
    _ findings: [Audit.Finding],
    file: StaticString,
    line: UInt
) {
    for (left, right) in zip(findings, findings.dropFirst()) {
        let ordered: Bool
        if left.severity != right.severity {
            ordered = left.severity > right.severity
        } else if left.code != right.code {
            ordered = findingCodeLess(left.code, right.code)
        } else {
            ordered = left.id < right.id
        }
        XCTAssertTrue(ordered, "Findings are not in canonical order", file: file, line: line)
    }
}

private func findingCodeLess(_ left: Audit.FindingCode, _ right: Audit.FindingCode) -> Bool {
    left.rawValue.utf8.lexicographicallyPrecedes(right.rawValue.utf8)
}

private func hex(_ digest: Audit.SHA256Digest) -> String {
    hex(digest.bytes)
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func bytes(hex: String) -> [UInt8] {
    stride(from: 0, to: hex.utf8.count, by: 2).map { offset in
        let start = hex.index(hex.startIndex, offsetBy: offset)
        let end = hex.index(start, offsetBy: 2)
        return UInt8(hex[start..<end], radix: 16)!
    }
}

private func render(_ value: Any) -> String {
    var dumped = ""
    dump(value, to: &dumped)
    let mirrored = Mirror(reflecting: value).children.map { String(describing: $0.value) }.joined()
    return [String(describing: value), String(reflecting: value), mirrored, dumped].joined(separator: "\n")
}
