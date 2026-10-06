import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class VerificationEvidenceLedgerTests: XCTestCase {
    func testApplicableRowsRequireCompleteEvidenceOrExplicitNotApplicable() throws {
        XCTAssertEqual(
            VerificationRoadmapApplicability.applicable(statefulness: .stateless).requiredEvidenceKinds,
            [.modelOrUnit, .uiInteraction, .semanticAccessibility, .packagedAppSmoke]
        )
        XCTAssertEqual(
            VerificationRoadmapApplicability.applicable(statefulness: .stateful).requiredEvidenceKinds,
            [.modelOrUnit, .uiInteraction, .semanticAccessibility, .persistence, .packagedAppSmoke]
        )
        XCTAssertEqual(VerificationRoadmapApplicability.notApplicable.requiredEvidenceKinds, [])

        let fixture = try makeFixture()
        let signed = try signedAudit(fixture)
        let stateful = try row(named: "row-stateful", in: signed.result.report)
        let stateless = try row(named: "row-stateless", in: signed.result.report)
        let notApplicable = try row(named: "row-na", in: signed.result.report)

        XCTAssertEqual(stateful.status, .complete)
        XCTAssertEqual(
            stateful.cells.map(\.kind),
            [
                .modelOrUnit, .uiInteraction, .semanticAccessibility, .persistence,
                .packagedAppSmoke
            ])
        XCTAssertTrue(stateful.cells.allSatisfy { $0.status == .complete && $0.evidenceCount == 1 })
        XCTAssertEqual(stateless.status, .complete)
        XCTAssertEqual(
            stateless.cells.map(\.kind),
            [
                .modelOrUnit, .uiInteraction, .semanticAccessibility, .packagedAppSmoke
            ])
        XCTAssertTrue(stateless.cells.allSatisfy { $0.status == .complete && $0.evidenceCount == 1 })
        XCTAssertEqual(notApplicable.status, .notApplicable)
        XCTAssertEqual(notApplicable.cells, [])
        XCTAssertTrue(signed.result.report.isLedgerCompleteAndValid)
        XCTAssertEqual(Set(signed.result.report.validatedCompleteRowIDs.map(\.rawValue)), ["row-stateful", "row-stateless"])
        XCTAssertEqual(signed.result.receipt.completedRowCount, 2)
        XCTAssertEqual(signed.result.receipt.requiredEvidenceCount, 9)
        XCTAssertEqual(signed.result.receipt.completeEvidenceCount, 9)
        XCTAssertEqual(signed.result.receipt.findingCount, 0)

        for citation in fixture.ledger.citations {
            let reducedLedger = replacingCitations(
                fixture.ledger,
                with: fixture.ledger.citations.filter { $0.id != citation.id }
            )
            let reduced = replacingLedger(fixture, with: reducedLedger)
            let report = try signedAudit(reduced).result.report
            let reducedRow = try row(named: citation.row.id.rawValue, in: report)
            XCTAssertEqual(reducedRow.status, .invalid, citation.id.rawValue)
            XCTAssertEqual(
                reducedRow.cells.first { $0.kind == citation.kind }?.status,
                .missing,
                citation.id.rawValue
            )
            XCTAssertTrue(
                report.findings.contains {
                    $0.code == .missingEvidence
                        && $0.subject == .requirement(rowID: citation.row.id, kind: citation.kind)
                },
                citation.id.rawValue
            )
        }
    }

    func testIncompleteUnclaimedRowsCannotCompleteOrAcceptEvidence() throws {
        let fixture = try makeFixture()
        let unclaimed = requirement("row-unclaimed", statefulness: .stateless, completionClaimed: false)
        let manifest = replacingRows(fixture.manifest, with: fixture.manifest.rows + [unclaimed])
        let incompleteFixture = replacingManifest(fixture, with: manifest)
        let incomplete = try signedAudit(incompleteFixture).result

        let incompleteRow = try row(named: "row-unclaimed", in: incomplete.report)
        XCTAssertEqual(incompleteRow.status, .incomplete)
        XCTAssertFalse(incompleteRow.completionClaimed)
        XCTAssertEqual(incompleteRow.cells, [])
        XCTAssertFalse(incomplete.report.isLedgerCompleteAndValid)
        XCTAssertEqual(incomplete.receipt.completedRowCount, 2)
        XCTAssertEqual(incomplete.receipt.requiredEvidenceCount, 13)
        XCTAssertEqual(incomplete.receipt.completeEvidenceCount, 9)

        let template = try XCTUnwrap(fixture.ledger.citations.first { $0.kind == .modelOrUnit })
        var unexpected = citationCopy(
            template,
            id: citationID("citation-unclaimed-model"),
            row: unclaimed.reference
        )
        unexpected = try signCitation(
            unexpected,
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        let ledger = replacingCitations(fixture.ledger, with: fixture.ledger.citations + [unexpected])
        let suppliedFixture = replacingLedger(replacingManifest(fixture, with: manifest), with: ledger)
        let supplied = try signedAudit(suppliedFixture).result

        XCTAssertEqual(try row(named: "row-unclaimed", in: supplied.report).status, .invalid)
        XCTAssertTrue(
            supplied.report.findings.contains {
                $0.code == .unexpectedEvidence && $0.subject == .citation(unexpected.id)
            }
        )
        XCTAssertEqual(try row(named: "row-unclaimed", in: supplied.report).cells, [])
        XCTAssertEqual(supplied.report.validatedCompleteRowIDs, [])
        XCTAssertEqual(supplied.receipt.completedRowCount, 0)
        XCTAssertEqual(supplied.receipt.requiredEvidenceCount, 13)
        XCTAssertEqual(supplied.receipt.completeEvidenceCount, 9)
        XCTAssertEqual(supplied.receipt.findingCount, 1)
        XCTAssertTrue(supplied.report.containsErrors)
        XCTAssertFalse(supplied.report.isLedgerCompleteAndValid)
    }

    func testNotApplicableRowsHaveExactValidAndInvalidSemantics() throws {
        let fixture = try makeFixture()
        let notApplicable = try XCTUnwrap(fixture.manifest.rows.first { $0.id.rawValue == "row-na" })
        let manifest = replacingRows(fixture.manifest, with: [notApplicable])
        let ledger = replacingCitations(
            replacingManifest(fixture, with: manifest).ledger,
            with: []
        )
        let onlyNotApplicable = replacingLedger(replacingManifest(fixture, with: manifest), with: ledger)
        let valid = try signedAudit(onlyNotApplicable).result

        XCTAssertEqual(valid.report.rows.count, 1)
        XCTAssertEqual(valid.report.rows[0].status, .notApplicable)
        XCTAssertEqual(valid.report.rows[0].cells, [])
        XCTAssertEqual(valid.report.findings, [])
        XCTAssertEqual(valid.report.validatedCompleteRowIDs, [])
        XCTAssertTrue(valid.report.isLedgerCompleteAndValid)
        XCTAssertEqual(valid.receipt.completedRowCount, 0)
        XCTAssertEqual(valid.receipt.requiredEvidenceCount, 0)
        XCTAssertEqual(valid.receipt.completeEvidenceCount, 0)
        XCTAssertEqual(valid.receipt.findingCount, 0)

        let claimed = VerificationRoadmapRowRequirement(
            reference: notApplicable.reference,
            applicability: .notApplicable,
            completionClaimed: true
        )
        let claimedManifest = replacingRows(manifest, with: [claimed])
        let claimedFixture = replacingLedger(
            replacingManifest(onlyNotApplicable, with: claimedManifest),
            with: replacingCitations(ledger, with: [])
        )
        let invalidClaim = try signedAudit(claimedFixture).result
        XCTAssertEqual(invalidClaim.report.rows[0].status, .invalid)
        XCTAssertEqual(invalidClaim.report.rows[0].cells, [])
        XCTAssertEqual(
            findingPairs(invalidClaim.report),
            [findingPair(.invalidManifest, .row(notApplicable.id))]
        )
        assertGloballyInvalid(invalidClaim, requiredEvidenceCount: 0, completeEvidenceCount: 0)

        let template = try XCTUnwrap(fixture.ledger.citations.first)
        let citation = try signCitation(
            citationCopy(
                template,
                id: citationID("citation-not-applicable"),
                row: notApplicable.reference
            ),
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        let supplied = try signedAudit(
            replacingLedger(
                onlyNotApplicable,
                with: replacingCitations(ledger, with: [citation])
            )
        ).result
        XCTAssertEqual(supplied.report.rows[0].status, .invalid)
        XCTAssertEqual(supplied.report.rows[0].cells, [])
        XCTAssertEqual(
            findingPairs(supplied.report),
            [findingPair(.unexpectedEvidence, .citation(citation.id))]
        )
        assertGloballyInvalid(supplied, requiredEvidenceCount: 0, completeEvidenceCount: 0)
    }

    func testSignedMutationMatrixHasExactCellRowReportAndReceiptSemantics() throws {
        let fixture = try makeFixture()
        let original = try XCTUnwrap(
            fixture.ledger.citations.first {
                $0.row.id.rawValue == "row-stateless" && $0.kind == .modelOrUnit
            }
        )

        let duplicate = try resignedCitation(
            citationCopy(original, id: citationID("citation-duplicate-model")),
            fixture: fixture
        )
        let duplicateResult = try signedAudit(
            replacingLedger(
                fixture,
                with: replacingCitations(fixture.ledger, with: fixture.ledger.citations + [duplicate])
            )
        ).result
        try assertInvalidCell(
            duplicateResult,
            citation: original,
            status: .duplicate,
            evidenceCount: 2,
            citationIDs: [duplicate.id, original.id].sorted(),
            completeEvidenceCount: 8,
            findings: [
                findingPair(
                    .duplicateEvidenceKind,
                    .requirement(rowID: original.row.id, kind: original.kind)
                )
            ]
        )

        let asserted = try resignedCitation(
            citationCopy(original, basis: .asserted),
            fixture: fixture
        )
        let assertedResult = try signedAudit(replacingCitation(fixture, original.id, with: asserted)).result
        try assertInvalidCell(
            assertedResult,
            citation: original,
            status: .asserted,
            completeEvidenceCount: 8,
            findings: [findingPair(.assertedEvidence, .citation(original.id))]
        )

        let unsuccessful = try resignedCitation(
            citationCopy(original, outcome: .failed),
            fixture: fixture
        )
        let unsuccessfulResult = try signedAudit(
            replacingCitation(fixture, original.id, with: unsuccessful)
        ).result
        try assertInvalidCell(
            unsuccessfulResult,
            citation: original,
            status: .unsuccessful,
            completeEvidenceCount: 8,
            findings: [findingPair(.unsuccessfulEvidence, .citation(original.id))]
        )

        let mismatchedReference = VerificationRoadmapRowReference(
            id: original.row.id,
            revision: VerificationEvidenceRevision(rawValue: original.row.revision.rawValue + 1)
        )
        let mismatched = try resignedCitation(
            citationCopy(original, row: mismatchedReference),
            fixture: fixture
        )
        let mismatchedResult = try signedAudit(
            replacingCitation(fixture, original.id, with: mismatched)
        ).result
        try assertInvalidCell(
            mismatchedResult,
            citation: original,
            status: .mismatched,
            completeEvidenceCount: 8,
            findings: [findingPair(.rowRevisionMismatch, .citation(original.id))]
        )

        let unexpectedTemplate = try XCTUnwrap(
            fixture.ledger.citations.first {
                $0.row.id.rawValue == "row-stateless" && $0.kind == .packagedAppSmoke
            }
        )
        let unexpected = try resignedCitation(
            citationCopy(
                unexpectedTemplate,
                id: citationID("citation-unexpected-persistence"),
                kind: .persistence
            ),
            fixture: fixture
        )
        let unexpectedResult = try signedAudit(
            replacingLedger(
                fixture,
                with: replacingCitations(fixture.ledger, with: fixture.ledger.citations + [unexpected])
            )
        ).result
        XCTAssertEqual(try row(named: "row-stateless", in: unexpectedResult.report).status, .invalid)
        XCTAssertTrue(
            try row(named: "row-stateless", in: unexpectedResult.report).cells.allSatisfy {
                $0.status == .complete
            }
        )
        XCTAssertEqual(
            findingPairs(unexpectedResult.report),
            [findingPair(.unexpectedEvidenceKind, .citation(unexpected.id))]
        )
        assertGloballyInvalid(unexpectedResult, requiredEvidenceCount: 9, completeEvidenceCount: 9)

        let rejected = replacingReviews(
            original,
            with: [
                try signedReview(
                    for: original,
                    reviewerID: fixture.reviewerID,
                    reviewerKey: fixture.keys.reviewer,
                    verdict: .rejected
                )
            ]
        )
        let rejectedResult = try signedAudit(replacingCitation(fixture, original.id, with: rejected)).result
        try assertInvalidCell(
            rejectedResult,
            citation: original,
            status: .untrusted,
            completeEvidenceCount: 8,
            findings: [findingPair(.rejectedReview, .citation(original.id))]
        )

        let invalidRun = replacingTestRun(
            original.testRun,
            reference: testRunReference("test-run-wrong-role"),
            testRunner: artifact("wrong-role-runner", role: .testBundle)
        )
        let invalidProvenance = try resignedCitation(
            citationCopy(original, testRun: invalidRun),
            fixture: fixture
        )
        let invalidProvenanceResult = try signedAudit(
            replacingCitation(fixture, original.id, with: invalidProvenance)
        ).result
        try assertInvalidCell(
            invalidProvenanceResult,
            citation: original,
            status: .invalid,
            completeEvidenceCount: 8,
            findings: [findingPair(.artifactProvenanceMismatch, .citation(original.id))]
        )
    }

    func testCitationAttachmentAndReviewLinkageIsExact() throws {
        let fixture = try makeFixture()
        let result = try signedAudit(fixture).result
        let citationsByID = Dictionary(uniqueKeysWithValues: fixture.ledger.citations.map { ($0.id, $0) })

        for auditedRow in result.report.rows where auditedRow.status == .complete {
            for cell in auditedRow.cells {
                let citationID = try XCTUnwrap(cell.citationIDs.only)
                let citation = try XCTUnwrap(citationsByID[citationID])
                XCTAssertEqual(citation.row.id, auditedRow.id)
                XCTAssertEqual(citation.kind, cell.kind)
                XCTAssertEqual(citation.attachments.count, 1)
                XCTAssertEqual(citation.attachments[0].kind, requiredAttachmentKind(for: cell.kind))
                XCTAssertEqual(citation.attachments[0].artifact.role, .evidenceAttachment)
                XCTAssertEqual(citation.reviews.count, 1)
                XCTAssertEqual(citation.reviews[0].verdict, .accepted)
                XCTAssertEqual(
                    citation.reviews[0].evidenceClaimSHA256,
                    independentEvidenceClaimSHA256(for: citation)
                )
                XCTAssertEqual(
                    try VerificationEvidenceAuditor.evidenceClaimSHA256(for: citation),
                    independentEvidenceClaimSHA256(for: citation)
                )
            }
        }

        let original = try XCTUnwrap(fixture.ledger.citations.first)
        let noAttachment = try signCitation(
            replacingAttachments(original, with: []),
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        let missingResult = try signedAudit(replacingCitation(fixture, original.id, with: noAttachment)).result
        try assertInvalidCell(
            missingResult,
            citation: original,
            status: .invalid,
            completeEvidenceCount: 8,
            findings: [findingPair(.requiredAttachmentRecordMissing, .citation(original.id))]
        )

        let wrongDigest = VerificationEvidenceDigest(bytes: [UInt8](repeating: 0xEE, count: SHA256.byteCount))
        var wrongReview = VerificationEvidenceReviewAttestation(
            reviewerID: fixture.reviewerID,
            verdict: .accepted,
            reviewedAtUnixMilliseconds: reviewerTime,
            evidenceClaimSHA256: wrongDigest,
            signature: []
        )
        let reviewData = independentReviewerSigningData(for: original, review: wrongReview)
        wrongReview = VerificationEvidenceReviewAttestation(
            reviewerID: wrongReview.reviewerID,
            verdict: wrongReview.verdict,
            reviewedAtUnixMilliseconds: wrongReview.reviewedAtUnixMilliseconds,
            evidenceClaimSHA256: wrongReview.evidenceClaimSHA256,
            signature: Array(try fixture.keys.reviewer.signature(for: reviewData))
        )
        let mismatch = replacingReviews(original, with: [wrongReview])
        let mismatchResult = try signedAudit(replacingCitation(fixture, original.id, with: mismatch)).result
        try assertInvalidCell(
            mismatchResult,
            citation: original,
            status: .mismatched,
            completeEvidenceCount: 8,
            findings: [findingPair(.reviewDigestMismatch, .citation(original.id))]
        )

        let noReview = replacingReviews(original, with: [])
        let noReviewResult = try signedAudit(replacingCitation(fixture, original.id, with: noReview)).result
        try assertInvalidCell(
            noReviewResult,
            citation: original,
            status: .untrusted,
            completeEvidenceCount: 8,
            findings: [findingPair(.missingReviewer, .citation(original.id))]
        )
    }

    func testEd25519CollectorReviewerAndAuditorSignaturesAreRequired() throws {
        let fixture = try makeFixture()
        let signed = try signedAudit(fixture)
        let citation = try XCTUnwrap(fixture.ledger.citations.first)
        let review = try XCTUnwrap(citation.reviews.first)
        let collectorSigningData = independentCollectorSigningData(for: citation)
        let reviewerSigningData = independentReviewerSigningData(for: citation, review: review)
        let auditorSigningData = independentAuditSigningData(signed.envelope)

        XCTAssertEqual(
            try VerificationEvidenceAuditor.collectorSigningData(for: citation),
            collectorSigningData
        )
        XCTAssertTrue(
            fixture.keys.collector.publicKey.isValidSignature(
                Data(citation.collectorAttestation.signature),
                for: collectorSigningData
            )
        )
        XCTAssertEqual(
            try VerificationEvidenceAuditor.reviewerSigningData(for: citation, review: review),
            reviewerSigningData
        )
        XCTAssertTrue(
            fixture.keys.reviewer.publicKey.isValidSignature(
                Data(review.signature),
                for: reviewerSigningData
            )
        )
        XCTAssertEqual(signed.envelope.signingData, auditorSigningData)
        XCTAssertEqual(
            try VerificationEvidenceAuditor.auditSigningData(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                auditorID: fixture.auditorID,
                submitterID: fixture.submitterID,
                auditedAtUnixMilliseconds: fixture.auditedTime,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            ),
            auditorSigningData
        )
        XCTAssertTrue(
            fixture.keys.auditor.publicKey.isValidSignature(
                Data(signed.attestation.signature),
                for: auditorSigningData
            )
        )

        let corruptCollector = replacingCollector(
            citation,
            with: VerificationEvidenceCollectorAttestation(
                collectorID: citation.collectorAttestation.collectorID,
                attestedAtUnixMilliseconds: citation.collectorAttestation.attestedAtUnixMilliseconds,
                signature: corrupting(citation.collectorAttestation.signature)
            )
        )
        let collectorResult = try signedAudit(
            replacingCitation(fixture, citation.id, with: corruptCollector)
        ).result
        try assertInvalidCell(
            collectorResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 8,
            findings: [findingPair(.invalidCollectorSignature, .citation(citation.id))]
        )

        let corruptReview = VerificationEvidenceReviewAttestation(
            reviewerID: review.reviewerID,
            verdict: review.verdict,
            reviewedAtUnixMilliseconds: review.reviewedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: review.expiresAtUnixMilliseconds,
            evidenceClaimSHA256: review.evidenceClaimSHA256,
            signature: corrupting(review.signature)
        )
        let reviewerResult = try signedAudit(
            replacingCitation(fixture, citation.id, with: replacingReviews(citation, with: [corruptReview]))
        ).result
        try assertInvalidCell(
            reviewerResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 8,
            findings: [findingPair(.invalidReviewerSignature, .citation(citation.id))]
        )

        let corruptAudit = signed.envelope.attestation(signature: corrupting(signed.attestation.signature))
        assertLedgerError(.invalidAuditAttestation) {
            _ = try fixture.ledger.audit(
                against: fixture.manifest,
                trustPolicy: fixture.trustPolicy,
                auditAttestation: corruptAudit,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        }
    }

    func testEveryAuditAttestationDigestIsValidatedAfterResigning() throws {
        let fixture = try makeFixture()
        let signed = try signedAudit(fixture)
        let changedDigest = VerificationEvidenceDigest(
            bytes: [UInt8](repeating: 0xA5, count: SHA256.byteCount)
        )
        let attestations = [
            replacingAuditAttestation(signed.attestation, manifestSHA256: changedDigest),
            replacingAuditAttestation(signed.attestation, ledgerSHA256: changedDigest),
            replacingAuditAttestation(signed.attestation, trustPolicySHA256: changedDigest),
            replacingAuditAttestation(signed.attestation, reportSHA256: changedDigest),
            replacingAuditAttestation(signed.attestation, archiveSHA256: changedDigest)
        ]

        for attestation in attestations {
            let resigned = try signedAuditAttestation(attestation, key: fixture.keys.auditor)
            assertLedgerError(.invalidAuditAttestation) {
                _ = try VerificationEvidenceAuditor.audit(
                    manifest: fixture.manifest,
                    ledger: fixture.ledger,
                    trustPolicy: fixture.trustPolicy,
                    auditAttestation: resigned,
                    trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
                )
            }
        }
    }

    func testAuditorIsSeparatedFromCollectorAndReviewerByPrincipalAndKey() throws {
        let fixture = try makeFixture()
        let parties: [(VerificationEvidencePrincipalID, Curve25519.Signing.PrivateKey)] = [
            (fixture.submitterID, fixture.keys.submitter),
            (fixture.collectorID, fixture.keys.collector),
            (fixture.reviewerID, fixture.keys.reviewer)
        ]

        for (principalID, key) in parties {
            let roots =
                fixture.trustPolicy.roots.filter {
                    $0.principalID != fixture.auditorID && $0.principalID != principalID
                } + [
                    trustRoot(principalID, roles: [.submitter, .collector, .reviewer, .auditor], key: key)
                ]
            let samePrincipal = replacingAuditor(
                replacingTrustPolicy(fixture, with: VerificationEvidenceTrustPolicy(roots: roots)),
                id: principalID,
                key: key
            )
            assertLedgerError(.invalidAuditAttestation) {
                _ = try auditEnvelope(samePrincipal)
            }
        }

        for key in [fixture.keys.submitter, fixture.keys.collector, fixture.keys.reviewer] {
            let roots =
                fixture.trustPolicy.roots.filter { $0.principalID != fixture.auditorID } + [
                    trustRoot(fixture.auditorID, roles: [.auditor], key: key)
                ]
            let sharedKey = replacingAuditor(
                replacingTrustPolicy(fixture, with: VerificationEvidenceTrustPolicy(roots: roots)),
                id: fixture.auditorID,
                key: key
            )
            assertLedgerError(.invalidAuditAttestation) {
                _ = try auditEnvelope(sharedKey)
            }
        }
    }

    func testEveryTrustRoleAndPairwiseEvidenceSeparationIsRequired() throws {
        let fixture = try makeFixture()
        let citation = try XCTUnwrap(fixture.ledger.citations.first)
        let wrongRoles: [(VerificationEvidencePrincipalID, Set<VerificationEvidenceTrustRole>)] = [
            (fixture.submitterID, [.collector]),
            (fixture.auditorID, [.submitter])
        ]
        for (principal, roles) in wrongRoles {
            let policy = replacingRoot(fixture.trustPolicy, principalID: principal, roles: roles)
            assertLedgerError(.invalidAuditAttestation) {
                _ = try auditEnvelope(replacingTrustPolicy(fixture, with: policy))
            }
        }

        let evidenceRoleCases:
            [(
                VerificationEvidencePrincipalID, Set<VerificationEvidenceTrustRole>,
                VerificationEvidenceFindingCode
            )] = [
                (fixture.collectorID, [.reviewer], .untrustedCollector),
                (fixture.reviewerID, [.collector], .untrustedReviewer)
            ]
        for (principal, roles, expected) in evidenceRoleCases {
            let changed = replacingTrustPolicy(
                fixture,
                with: replacingRoot(fixture.trustPolicy, principalID: principal, roles: roles)
            )
            let result = try signedAudit(changed).result
            try assertInvalidCell(
                result,
                citation: citation,
                status: .untrusted,
                completeEvidenceCount: 0,
                findings: [findingPair(expected, .principal(principal))]
            )
        }

        let submitterCollector = try signCitation(
            replacingCollector(
                citation,
                with: VerificationEvidenceCollectorAttestation(
                    collectorID: fixture.submitterID,
                    attestedAtUnixMilliseconds: collectorTime,
                    signature: []
                )
            ),
            collectorKey: fixture.keys.submitter,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        let submitterCollectorResult = try signedAudit(
            replacingTrustPolicy(
                replacingCitation(fixture, citation.id, with: submitterCollector),
                with: replacingRoot(
                    fixture.trustPolicy,
                    principalID: fixture.submitterID,
                    roles: [.submitter, .collector]
                )
            )
        ).result
        try assertInvalidCell(
            submitterCollectorResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 8,
            findings: [findingPair(.selfAttestation, .citation(citation.id))]
        )

        let submitterReviewer = try signCitation(
            citation,
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.submitter,
            reviewerID: fixture.submitterID
        )
        let submitterReviewerResult = try signedAudit(
            replacingTrustPolicy(
                replacingCitation(fixture, citation.id, with: submitterReviewer),
                with: replacingRoot(
                    fixture.trustPolicy,
                    principalID: fixture.submitterID,
                    roles: [.submitter, .reviewer]
                )
            )
        ).result
        try assertInvalidCell(
            submitterReviewerResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 8,
            findings: [findingPair(.selfAttestation, .citation(citation.id))]
        )

        let collectorReviewer = try signCitation(
            citation,
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.collector,
            reviewerID: fixture.collectorID
        )
        let collectorReviewerResult = try signedAudit(
            replacingTrustPolicy(
                replacingCitation(fixture, citation.id, with: collectorReviewer),
                with: replacingRoot(
                    fixture.trustPolicy,
                    principalID: fixture.collectorID,
                    roles: [.collector, .reviewer]
                )
            )
        ).result
        try assertInvalidCell(
            collectorReviewerResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 8,
            findings: [
                findingPair(.selfAttestation, .citation(citation.id)),
                findingPair(.selfAttestation, .citation(citation.id))
            ]
        )

        let sharedReviewerKeyCitations = try fixture.ledger.citations.map {
            try signCitation(
                $0,
                collectorKey: fixture.keys.collector,
                reviewerKey: fixture.keys.collector,
                reviewerID: fixture.reviewerID
            )
        }
        let sharedReviewerKeyResult = try signedAudit(
            replacingTrustPolicy(
                replacingLedger(
                    fixture,
                    with: replacingCitations(fixture.ledger, with: sharedReviewerKeyCitations)
                ),
                with: replacingRoot(
                    fixture.trustPolicy,
                    principalID: fixture.reviewerID,
                    roles: [.reviewer],
                    key: fixture.keys.collector
                )
            )
        ).result
        let sharedKeyRow = try row(named: citation.row.id.rawValue, in: sharedReviewerKeyResult.report)
        XCTAssertEqual(sharedKeyRow.status, .invalid)
        XCTAssertEqual(sharedKeyRow.cells.first { $0.kind == citation.kind }?.status, .untrusted)
        XCTAssertEqual(sharedReviewerKeyResult.report.findings.count, 9)
        XCTAssertEqual(
            Set(sharedReviewerKeyResult.report.findings.map(\.subject)),
            Set(fixture.ledger.citations.map { .citation($0.id) })
        )
        XCTAssertTrue(
            sharedReviewerKeyResult.report.findings.allSatisfy {
                $0.code == .selfAttestation
                    && $0.severity == .error
                    && isCitationSubject($0.subject)
            }
        )
        assertGloballyInvalid(
            sharedReviewerKeyResult,
            requiredEvidenceCount: 9,
            completeEvidenceCount: 0
        )
    }

    func testNonOverlappingKeyRotationIsAllowedButOverlapIsAmbiguous() throws {
        let fixture = try makeFixture()
        let oldKey = try privateKey(seed: 0x61)
        let rootsWithoutCollector = fixture.trustPolicy.roots.filter { $0.principalID != fixture.collectorID }
        let oldRoot = trustRoot(
            fixture.collectorID,
            roles: [.collector],
            key: oldKey,
            validFrom: 500,
            validThrough: collectorTime - 1
        )
        let currentRoot = trustRoot(
            fixture.collectorID,
            roles: [.collector],
            key: fixture.keys.collector,
            validFrom: collectorTime,
            validThrough: 5_000
        )
        let rotated = replacingTrustPolicy(
            fixture,
            with: VerificationEvidenceTrustPolicy(roots: rootsWithoutCollector + [oldRoot, currentRoot])
        )
        let rotatedResult = try signedAudit(rotated).result
        XCTAssertTrue(rotatedResult.report.isLedgerCompleteAndValid)
        XCTAssertFalse(rotatedResult.report.findings.contains { $0.code == .invalidTrustPolicy })

        let overlap = trustRoot(
            fixture.collectorID,
            roles: [.collector],
            key: oldKey,
            validFrom: 500,
            validThrough: fixture.trustedTime
        )
        let ambiguous = replacingTrustPolicy(
            fixture,
            with: VerificationEvidenceTrustPolicy(roots: rootsWithoutCollector + [overlap, currentRoot])
        )
        let ambiguousResult = try signedAudit(ambiguous).result
        XCTAssertFalse(ambiguousResult.report.isLedgerCompleteAndValid)
        XCTAssertTrue(
            ambiguousResult.report.findings.contains {
                $0.code == .invalidTrustPolicy && $0.subject == .principal(fixture.collectorID)
            }
        )
        XCTAssertTrue(
            ambiguousResult.report.findings.contains {
                $0.code == .untrustedCollector && $0.subject == .principal(fixture.collectorID)
            }
        )
    }

    func testTrustRootSigningAndVerificationTimeEndpointsAreInclusive() throws {
        let fixture = try makeFixture()
        let citation = try XCTUnwrap(fixture.ledger.citations.first)

        let collectorAtSigningStart = replacingRoot(
            fixture.trustPolicy,
            principalID: fixture.collectorID,
            validFrom: collectorTime,
            validThrough: fixture.trustedTime
        )
        XCTAssertTrue(
            try signedAudit(replacingTrustPolicy(fixture, with: collectorAtSigningStart))
                .result.report.isLedgerCompleteAndValid
        )
        let collectorAfterSigning = replacingTrustPolicy(
            fixture,
            with: replacingRoot(
                fixture.trustPolicy,
                principalID: fixture.collectorID,
                validFrom: collectorTime + 1,
                validThrough: fixture.trustedTime
            )
        )
        let collectorAfterSigningResult = try signedAudit(collectorAfterSigning).result
        try assertInvalidCell(
            collectorAfterSigningResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 0,
            findings: [findingPair(.untrustedCollector, .principal(fixture.collectorID))]
        )

        let reviewerAtSigningStart = replacingRoot(
            fixture.trustPolicy,
            principalID: fixture.reviewerID,
            validFrom: reviewerTime,
            validThrough: fixture.trustedTime
        )
        XCTAssertTrue(
            try signedAudit(replacingTrustPolicy(fixture, with: reviewerAtSigningStart))
                .result.report.isLedgerCompleteAndValid
        )
        let reviewerAfterSigning = replacingTrustPolicy(
            fixture,
            with: replacingRoot(
                fixture.trustPolicy,
                principalID: fixture.reviewerID,
                validFrom: reviewerTime + 1,
                validThrough: fixture.trustedTime
            )
        )
        let reviewerAfterSigningResult = try signedAudit(reviewerAfterSigning).result
        try assertInvalidCell(
            reviewerAfterSigningResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 0,
            findings: [findingPair(.untrustedReviewer, .principal(fixture.reviewerID))]
        )

        for principal in [fixture.submitterID, fixture.auditorID] {
            let valid = replacingTrustPolicy(
                fixture,
                with: replacingRoot(
                    fixture.trustPolicy,
                    principalID: principal,
                    validFrom: fixture.auditedTime,
                    validThrough: fixture.trustedTime
                )
            )
            XCTAssertNoThrow(try auditEnvelope(valid))

            let startsLate = replacingTrustPolicy(
                fixture,
                with: replacingRoot(
                    fixture.trustPolicy,
                    principalID: principal,
                    validFrom: fixture.auditedTime + 1,
                    validThrough: fixture.trustedTime
                )
            )
            assertLedgerError(.invalidAuditAttestation) {
                _ = try auditEnvelope(startsLate)
            }

            let endsEarly = replacingTrustPolicy(
                fixture,
                with: replacingRoot(
                    fixture.trustPolicy,
                    principalID: principal,
                    validFrom: 500,
                    validThrough: fixture.trustedTime - 1
                )
            )
            assertLedgerError(.invalidAuditAttestation) {
                _ = try auditEnvelope(endsEarly)
            }
        }
    }

    func testTrustedVerificationTimeEnforcesExpiryRevocationAndNoBackdating() throws {
        let fixture = try makeFixture()
        let citation = try XCTUnwrap(fixture.ledger.citations.first)
        let expiring = VerificationEvidenceCitation(
            id: citation.id,
            row: citation.row,
            kind: citation.kind,
            basis: citation.basis,
            outcome: citation.outcome,
            collectedAtUnixMilliseconds: citation.collectedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: fixture.trustedTime,
            testRun: citation.testRun,
            attachments: citation.attachments,
            collectorAttestation: citation.collectorAttestation,
            reviews: citation.reviews
        )
        let signedExpiring = try signCitation(
            expiring,
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        let expiredResult = try signedAudit(replacingCitation(fixture, citation.id, with: signedExpiring)).result
        try assertInvalidCell(
            expiredResult,
            citation: citation,
            status: .stale,
            completeEvidenceCount: 8,
            findings: [findingPair(.expiredEvidence, .citation(citation.id))]
        )

        let revokedRoots = fixture.trustPolicy.roots.map { root in
            guard root.principalID == fixture.collectorID else { return root }
            return VerificationEvidenceTrustRoot(
                principalID: root.principalID,
                roles: root.roles,
                ed25519PublicKey: root.ed25519PublicKey,
                validFromUnixMilliseconds: root.validFromUnixMilliseconds,
                validThroughUnixMilliseconds: root.validThroughUnixMilliseconds,
                revokedAtUnixMilliseconds: fixture.trustedTime
            )
        }
        let revoked = replacingTrustPolicy(
            fixture,
            with: VerificationEvidenceTrustPolicy(roots: revokedRoots, freshness: fixture.trustPolicy.freshness)
        )
        let revokedResult = try signedAudit(revoked).result
        try assertInvalidCell(
            revokedResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 0,
            findings: [findingPair(.untrustedCollector, .principal(fixture.collectorID))]
        )

        let reviewExpiring = try signCitation(
            citation,
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID,
            reviewExpiresAt: fixture.trustedTime
        )
        let reviewExpiredResult = try signedAudit(
            replacingCitation(fixture, citation.id, with: reviewExpiring)
        ).result
        try assertInvalidCell(
            reviewExpiredResult,
            citation: citation,
            status: .stale,
            completeEvidenceCount: 8,
            findings: [findingPair(.expiredEvidence, .citation(citation.id))]
        )

        let reviewerRevokedRoots = fixture.trustPolicy.roots.map { root in
            guard root.principalID == fixture.reviewerID else { return root }
            return VerificationEvidenceTrustRoot(
                principalID: root.principalID,
                roles: root.roles,
                ed25519PublicKey: root.ed25519PublicKey,
                validFromUnixMilliseconds: root.validFromUnixMilliseconds,
                validThroughUnixMilliseconds: root.validThroughUnixMilliseconds,
                revokedAtUnixMilliseconds: fixture.trustedTime
            )
        }
        let reviewerRevoked = replacingTrustPolicy(
            fixture,
            with: VerificationEvidenceTrustPolicy(
                roots: reviewerRevokedRoots,
                freshness: fixture.trustPolicy.freshness
            )
        )
        let reviewerRevokedResult = try signedAudit(reviewerRevoked).result
        try assertInvalidCell(
            reviewerRevokedResult,
            citation: citation,
            status: .untrusted,
            completeEvidenceCount: 0,
            findings: [findingPair(.untrustedReviewer, .principal(fixture.reviewerID))]
        )

        let signed = try signedAudit(fixture)
        assertLedgerError(.invalidAuditAttestation) {
            _ = try VerificationEvidenceAuditor.audit(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                auditAttestation: signed.attestation,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime - 1
            )
        }
        assertLedgerError(.receiptMismatch) {
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime - 1
            )
        }
        assertLedgerError(.receiptMismatch) {
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime - 1,
                limits: limits(maximumRows: 0),
                cancellationCheck: { true }
            )
        }
        assertLedgerError(.invalidAuditAttestation) {
            _ = try VerificationEvidenceAuditor.auditSigningEnvelope(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                auditorID: fixture.auditorID,
                submitterID: fixture.submitterID,
                auditedAtUnixMilliseconds: fixture.trustedTime + 1,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        }
    }

    func testEveryRoleHonorsFutureAndEffectiveRevocation() throws {
        let fixture = try makeFixture()
        for principal in [
            fixture.submitterID, fixture.collectorID, fixture.reviewerID, fixture.auditorID
        ] {
            let futurePolicy = replacingRoot(
                fixture.trustPolicy,
                principalID: principal,
                revokedAt: fixture.trustedTime + 1,
                replaceRevocation: true
            )
            let futureFixture = replacingTrustPolicy(fixture, with: futurePolicy)
            let signed = try signedAudit(futureFixture)
            XCTAssertTrue(signed.result.report.isLedgerCompleteAndValid, principal.rawValue)

            if principal == fixture.submitterID || principal == fixture.auditorID {
                assertLedgerError(.invalidAuditAttestation) {
                    try signed.result.receipt.validateCurrent(
                        manifest: futureFixture.manifest,
                        ledger: futureFixture.ledger,
                        trustPolicy: futureFixture.trustPolicy,
                        trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 1
                    )
                }
            } else {
                assertLedgerError(.receiptMismatch) {
                    try signed.result.receipt.validateCurrent(
                        manifest: futureFixture.manifest,
                        ledger: futureFixture.ledger,
                        trustPolicy: futureFixture.trustPolicy,
                        trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 1
                    )
                }
            }

            let effectivePolicy = replacingRoot(
                fixture.trustPolicy,
                principalID: principal,
                revokedAt: fixture.trustedTime,
                replaceRevocation: true
            )
            let effectiveFixture = replacingTrustPolicy(fixture, with: effectivePolicy)
            if principal == fixture.submitterID || principal == fixture.auditorID {
                assertLedgerError(.invalidAuditAttestation) {
                    _ = try auditEnvelope(effectiveFixture)
                }
            } else {
                let result = try signedAudit(effectiveFixture).result
                XCTAssertFalse(result.report.isLedgerCompleteAndValid)
                XCTAssertEqual(result.report.validatedCompleteRowIDs, [])
                XCTAssertEqual(result.receipt.completedRowCount, 0)
                let code: VerificationEvidenceFindingCode =
                    principal == fixture.collectorID ? .untrustedCollector : .untrustedReviewer
                XCTAssertTrue(
                    result.report.findings.contains {
                        $0.code == code && $0.subject == .principal(principal)
                    }
                )
            }
        }
    }

    func testRunCollectionReviewChronologyLagAndPerKindFreshnessBoundaries() throws {
        let fixture = try makeFixture()
        let citation = try XCTUnwrap(fixture.ledger.citations.first)

        let reversedRun = replacingTestRun(citation.testRun, startedAt: runFinishedTime + 1)
        let reversedCitation = try resignedCitation(
            citationCopy(citation, testRun: reversedRun),
            fixture: fixture
        )
        let reversedResult = try signedAudit(
            replacingCitation(fixture, citation.id, with: reversedCitation)
        ).result
        try assertInvalidCell(
            reversedResult,
            citation: citation,
            status: .mismatched,
            completeEvidenceCount: 8,
            findings: [
                findingPair(.testRunMismatch, .citation(citation.id)),
                findingPair(.testRunMismatch, .citation(citation.id))
            ]
        )

        let collectionBeforeRun = try resignedCitation(
            citationCopy(citation, collectedAt: runFinishedTime - 1),
            fixture: fixture
        )
        let collectionBeforeRunResult = try signedAudit(
            replacingCitation(fixture, citation.id, with: collectionBeforeRun)
        ).result
        try assertInvalidCell(
            collectionBeforeRunResult,
            citation: citation,
            status: .mismatched,
            completeEvidenceCount: 8,
            findings: [findingPair(.testRunMismatch, .citation(citation.id))]
        )

        let exactLagPolicy = VerificationEvidenceTrustPolicy(
            roots: fixture.trustPolicy.roots,
            freshness: freshnessPolicy(maximumAge: 1_000, maximumCollectionLag: 100)
        )
        XCTAssertTrue(
            try signedAudit(replacingTrustPolicy(fixture, with: exactLagPolicy))
                .result.report.isLedgerCompleteAndValid
        )
        let shortLagPolicy = VerificationEvidenceTrustPolicy(
            roots: fixture.trustPolicy.roots,
            freshness: freshnessPolicy(maximumAge: 1_000, maximumCollectionLag: 99)
        )
        let shortLagResult = try signedAudit(
            replacingTrustPolicy(fixture, with: shortLagPolicy)
        ).result
        XCTAssertEqual(shortLagResult.report.validatedCompleteRowIDs, [])
        XCTAssertEqual(shortLagResult.receipt.completedRowCount, 0)
        XCTAssertEqual(shortLagResult.receipt.completeEvidenceCount, 0)
        XCTAssertEqual(shortLagResult.report.findings.count, 9)
        XCTAssertTrue(shortLagResult.report.findings.allSatisfy { $0.code == .testRunMismatch })

        for kind in VerificationEvidenceKind.allCases {
            let candidate = try XCTUnwrap(fixture.ledger.citations.first { $0.kind == kind })
            let exactPolicy = VerificationEvidenceTrustPolicy(
                roots: fixture.trustPolicy.roots,
                freshness: freshnessPolicy(kind: kind, maximumAge: 1_000)
            )
            XCTAssertTrue(
                try signedAudit(replacingTrustPolicy(fixture, with: exactPolicy))
                    .result.report.isLedgerCompleteAndValid,
                kind.rawValue
            )
            let stalePolicy = VerificationEvidenceTrustPolicy(
                roots: fixture.trustPolicy.roots,
                freshness: freshnessPolicy(kind: kind, maximumAge: 999)
            )
            let staleResult = try signedAudit(
                replacingTrustPolicy(fixture, with: stalePolicy)
            ).result
            let staleCell = try XCTUnwrap(
                try row(named: candidate.row.id.rawValue, in: staleResult.report).cells.first {
                    $0.kind == kind
                }
            )
            XCTAssertEqual(staleCell.status, .stale, kind.rawValue)
            XCTAssertTrue(
                staleResult.report.findings.contains {
                    $0.code == .staleEvidence && $0.subject == .citation(candidate.id)
                },
                kind.rawValue
            )
        }

        let futureReview = replacingReviews(
            citation,
            with: [
                try signedReview(
                    for: citation,
                    reviewerID: fixture.reviewerID,
                    reviewerKey: fixture.keys.reviewer,
                    reviewedAt: fixture.trustedTime + 1
                )
            ]
        )
        let futureReviewResult = try signedAudit(
            replacingCitation(fixture, citation.id, with: futureReview)
        ).result
        try assertInvalidCell(
            futureReviewResult,
            citation: citation,
            status: .invalid,
            completeEvidenceCount: 8,
            findings: [findingPair(.invalidReviewerProvenance, .citation(citation.id))]
        )
    }

    func testSigningPayloadCapPreservesExactError() throws {
        let fixture = try makeFixture()
        let citation = try XCTUnwrap(fixture.ledger.citations.first)
        let review = try XCTUnwrap(citation.reviews.first)
        let capped = limits(maximumSigningPayloadBytes: 32)

        assertLedgerError(.signingPayloadTooLarge(maximumBytes: 32)) {
            _ = try VerificationEvidenceAuditor.collectorSigningData(for: citation, limits: capped)
        }
        assertLedgerError(.signingPayloadTooLarge(maximumBytes: 32)) {
            _ = try VerificationEvidenceAuditor.reviewerSigningData(for: citation, review: review, limits: capped)
        }
        assertLedgerError(.signingPayloadTooLarge(maximumBytes: 32)) {
            _ = try auditEnvelope(fixture, limits: capped)
        }
    }

    func testSignedEnvelopeReportReceiptAndStreamedArchiveFraming() throws {
        let fixture = try makeFixture()
        let signed = try signedAudit(fixture)
        let result = signed.result

        XCTAssertEqual(signed.envelope.schemaVersion, 2)
        XCTAssertEqual(result.report.schemaVersion, 2)
        XCTAssertEqual(result.receipt.schemaVersion, 2)
        XCTAssertEqual(signed.envelope.auditorID, fixture.auditorID)
        XCTAssertEqual(signed.envelope.submitterID, fixture.submitterID)
        XCTAssertEqual(signed.envelope.auditedAtUnixMilliseconds, fixture.auditedTime)
        XCTAssertEqual(
            signed.envelope.trustedVerificationTimeUnixMilliseconds,
            fixture.trustedTime
        )
        XCTAssertEqual(result.report.manifest, fixture.manifest.reference)
        XCTAssertEqual(result.report.ledger, fixture.ledger.reference)
        XCTAssertEqual(result.report.auditedAtUnixMilliseconds, fixture.trustedTime)
        XCTAssertEqual(result.receipt.manifest, fixture.manifest.reference)
        XCTAssertEqual(result.receipt.ledger, fixture.ledger.reference)
        XCTAssertEqual(result.receipt.targetBuild, fixture.ledger.targetBuild)
        XCTAssertEqual(result.receipt.trustedVerificationTimeUnixMilliseconds, fixture.trustedTime)
        XCTAssertEqual(signed.envelope.manifestSHA256, result.receipt.manifestSHA256)
        XCTAssertEqual(signed.envelope.ledgerSHA256, result.receipt.ledgerSHA256)
        XCTAssertEqual(signed.envelope.trustPolicySHA256, result.receipt.trustPolicySHA256)
        XCTAssertEqual(signed.envelope.reportSHA256, result.receipt.reportSHA256)
        XCTAssertEqual(signed.envelope.archiveSHA256, result.receipt.archiveSHA256)
        XCTAssertEqual(result.receipt.auditAttestation, signed.attestation)
        XCTAssertEqual(result.receipt.archiveByteCount, result.archive.data.count)
        XCTAssertEqual(signed.envelope.signingData, independentAuditSigningData(signed.envelope))
        XCTAssertEqual(
            result.receipt.evaluationSHA256,
            rawSHA256(independentReportEvaluationSection(result.report))
        )

        var reader = ArchiveReader(result.archive.data)
        XCTAssertEqual(try reader.readData(count: 8), Data("MMVEL002".utf8))
        XCTAssertEqual(try reader.readString(), "org.macmerge.verification-evidence-ledger.archive.v2")
        XCTAssertEqual(try reader.readUInt16(), 2)
        let headerDigests = try (0..<4).map { _ in try reader.readDigest() }
        let sections = try (0..<4).map { _ in try reader.readLengthPrefixedData() }
        XCTAssertTrue(reader.isAtEnd)

        XCTAssertEqual(
            headerDigests,
            [
                result.receipt.manifestSHA256,
                result.receipt.ledgerSHA256,
                result.receipt.trustPolicySHA256,
                result.receipt.reportSHA256
            ])
        XCTAssertEqual(sections, independentArchiveSections(fixture: fixture, report: result.report))
        XCTAssertEqual(sections.map(rawSHA256), headerDigests)
        let expectedSectionHeaders = [
            ("org.macmerge.verification-evidence-ledger.manifest.v2", UInt16(2)),
            ("org.macmerge.verification-evidence-ledger.ledger.v2", UInt16(2)),
            ("org.macmerge.verification-evidence-ledger.trust-policy.v2", UInt16(2)),
            ("org.macmerge.verification-evidence-ledger.report.v2", UInt16(2))
        ]
        for (section, expected) in zip(sections, expectedSectionHeaders) {
            var sectionReader = ArchiveReader(section)
            XCTAssertEqual(try sectionReader.readString(), expected.0)
            XCTAssertEqual(try sectionReader.readUInt16(), expected.1)
        }

        let independentlyFramed = framedSHA256(
            domain: "org.macmerge.verification-evidence-ledger.archive.v2",
            data: result.archive.data,
            chunkSize: 7
        )
        XCTAssertEqual(result.archive.sha256, independentlyFramed)
        XCTAssertEqual(result.receipt.archiveSHA256, independentlyFramed)
        XCTAssertNotEqual(result.archive.sha256, rawSHA256(result.archive.data))
    }

    func testCurrentValidationAndReauditAreDeterministic() throws {
        let fixture = try makeFixture()
        let signed = try signedAudit(fixture)

        XCTAssertNoThrow(
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        )
        XCTAssertNoThrow(
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 100
            )
        )
        let staticReaudit = try VerificationEvidenceAuditor.audit(
            manifest: fixture.manifest,
            ledger: fixture.ledger,
            trustPolicy: fixture.trustPolicy,
            auditAttestation: signed.attestation,
            trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
        )
        let ledgerReaudit = try fixture.ledger.audit(
            against: fixture.manifest,
            trustPolicy: fixture.trustPolicy,
            auditAttestation: signed.attestation,
            trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
        )
        XCTAssertEqual(staticReaudit, signed.result)
        XCTAssertEqual(ledgerReaudit, signed.result)

        let changedRows = fixture.manifest.rows.map { row in
            guard row.id.rawValue == "row-stateful" else { return row }
            return VerificationRoadmapRowRequirement(
                reference: row.reference,
                applicability: row.applicability,
                completionClaimed: false
            )
        }
        let changedManifest = replacingRows(fixture.manifest, with: changedRows)
        assertLedgerError(.receiptMismatch) {
            try signed.result.receipt.validateCurrent(
                manifest: changedManifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        }

        let changedLedger = replacingCitations(
            fixture.ledger,
            with: fixture.ledger.citations.dropLast()
        )
        assertLedgerError(.receiptMismatch) {
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: changedLedger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        }

        let changedPolicy = VerificationEvidenceTrustPolicy(
            roots: fixture.trustPolicy.roots,
            freshness: freshnessPolicy(maximumAge: 2_000, maximumCollectionLag: 100)
        )
        assertLedgerError(.receiptMismatch) {
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: changedPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        }

        let first = try XCTUnwrap(fixture.ledger.citations.first)
        let expiring = VerificationEvidenceCitation(
            id: first.id,
            row: first.row,
            kind: first.kind,
            basis: first.basis,
            outcome: first.outcome,
            collectedAtUnixMilliseconds: first.collectedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: fixture.trustedTime + 1,
            testRun: first.testRun,
            attachments: first.attachments,
            collectorAttestation: first.collectorAttestation,
            reviews: first.reviews
        )
        let signedExpiring = try signCitation(
            expiring,
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        let expiringFixture = replacingCitation(fixture, first.id, with: signedExpiring)
        let expiringInitial = try signedAudit(expiringFixture).result
        XCTAssertTrue(expiringInitial.report.isLedgerCompleteAndValid)
        XCTAssertNoThrow(
            try expiringInitial.receipt.validateCurrent(
                manifest: expiringFixture.manifest,
                ledger: expiringFixture.ledger,
                trustPolicy: expiringFixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        )
        assertLedgerError(.receiptMismatch) {
            try expiringInitial.receipt.validateCurrent(
                manifest: expiringFixture.manifest,
                ledger: expiringFixture.ledger,
                trustPolicy: expiringFixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 1
            )
        }

        let revokingRoots = fixture.trustPolicy.roots.map { root in
            guard root.principalID == fixture.collectorID else { return root }
            return VerificationEvidenceTrustRoot(
                principalID: root.principalID,
                roles: root.roles,
                ed25519PublicKey: root.ed25519PublicKey,
                validFromUnixMilliseconds: root.validFromUnixMilliseconds,
                validThroughUnixMilliseconds: root.validThroughUnixMilliseconds,
                revokedAtUnixMilliseconds: fixture.trustedTime + 1
            )
        }
        let revokingFixture = replacingTrustPolicy(
            fixture,
            with: VerificationEvidenceTrustPolicy(
                roots: revokingRoots,
                freshness: fixture.trustPolicy.freshness
            )
        )
        let revokingInitial = try signedAudit(revokingFixture).result
        XCTAssertTrue(revokingInitial.report.isLedgerCompleteAndValid)
        XCTAssertNoThrow(
            try revokingInitial.receipt.validateCurrent(
                manifest: revokingFixture.manifest,
                ledger: revokingFixture.ledger,
                trustPolicy: revokingFixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime
            )
        )
        assertLedgerError(.receiptMismatch) {
            try revokingInitial.receipt.validateCurrent(
                manifest: revokingFixture.manifest,
                ledger: revokingFixture.ledger,
                trustPolicy: revokingFixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 1
            )
        }

        let reviewExpiring = try signCitation(
            first,
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID,
            reviewExpiresAt: fixture.trustedTime + 1
        )
        let reviewExpiringFixture = replacingCitation(fixture, first.id, with: reviewExpiring)
        let reviewExpiringInitial = try signedAudit(reviewExpiringFixture).result
        XCTAssertTrue(reviewExpiringInitial.report.isLedgerCompleteAndValid)
        assertLedgerError(.receiptMismatch) {
            try reviewExpiringInitial.receipt.validateCurrent(
                manifest: reviewExpiringFixture.manifest,
                ledger: reviewExpiringFixture.ledger,
                trustPolicy: reviewExpiringFixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 1
            )
        }

        let stalePolicy = VerificationEvidenceTrustPolicy(
            roots: fixture.trustPolicy.roots,
            freshness: freshnessPolicy(maximumAge: 1_000)
        )
        let staleFixture = replacingTrustPolicy(fixture, with: stalePolicy)
        let staleInitial = try signedAudit(staleFixture).result
        XCTAssertTrue(staleInitial.report.isLedgerCompleteAndValid)
        assertLedgerError(.receiptMismatch) {
            try staleInitial.receipt.validateCurrent(
                manifest: staleFixture.manifest,
                ledger: staleFixture.ledger,
                trustPolicy: staleFixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 1
            )
        }

        let auditorRevokingPolicy = replacingRoot(
            expiringFixture.trustPolicy,
            principalID: fixture.auditorID,
            revokedAt: fixture.trustedTime + 1,
            replaceRevocation: true
        )
        let expiringAuthorityFixture = replacingTrustPolicy(
            expiringFixture,
            with: auditorRevokingPolicy
        )
        let expiringAuthorityInitial = try signedAudit(expiringAuthorityFixture).result
        XCTAssertTrue(expiringAuthorityInitial.report.isLedgerCompleteAndValid)
        assertLedgerError(.invalidAuditAttestation) {
            try expiringAuthorityInitial.receipt.validateCurrent(
                manifest: expiringAuthorityFixture.manifest,
                ledger: expiringAuthorityFixture.ledger,
                trustPolicy: expiringAuthorityFixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime + 1
            )
        }
    }

    func testFindingSubjectsRecoverRowRequirementCitationAttachmentAndPrincipal() throws {
        let fixture = try makeFixture()
        let first = try XCTUnwrap(fixture.ledger.citations.first)
        let attachment = try XCTUnwrap(first.attachments.first)
        var duplicateAttachment = try signCitation(
            replacingAttachments(first, with: [attachment, attachment]),
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        duplicateAttachment = replacingReviews(duplicateAttachment, with: [])
        let omitted = try XCTUnwrap(
            fixture.ledger.citations.first {
                $0.row.id.rawValue == "row-stateless" && $0.kind == .packagedAppSmoke
            }
        )
        let citations = fixture.ledger.citations.filter { $0.id != omitted.id }.map {
            $0.id == first.id ? duplicateAttachment : $0
        }
        let ledger = replacingCitations(fixture.ledger, with: citations)
        let manifest = replacingRows(fixture.manifest, with: fixture.manifest.rows + [fixture.manifest.rows[0]])
        let policy = VerificationEvidenceTrustPolicy(
            roots: fixture.trustPolicy.roots.filter { $0.principalID != fixture.collectorID },
            freshness: fixture.trustPolicy.freshness
        )
        let changed = replacingTrustPolicy(
            replacingLedger(replacingManifest(fixture, with: manifest), with: ledger),
            with: policy
        )
        let report = try signedAudit(changed).result.report

        let firstCell = try XCTUnwrap(
            try row(named: first.row.id.rawValue, in: report).cells.first { $0.kind == first.kind }
        )
        XCTAssertEqual(firstCell.status, .invalid)

        XCTAssertTrue(
            report.findings.contains {
                $0.code == .duplicateRoadmapRow && $0.subject == .row(fixture.manifest.rows[0].id)
            }
        )
        XCTAssertTrue(
            report.findings.contains {
                $0.code == .missingEvidence
                    && $0.subject == .requirement(rowID: omitted.row.id, kind: omitted.kind)
            }
        )
        XCTAssertTrue(
            report.findings.contains {
                $0.code == .missingReviewer && $0.subject == .citation(first.id)
            }
        )
        XCTAssertTrue(
            report.findings.contains {
                $0.code == .duplicateAttachmentReference && $0.subject == .attachment(attachment.id)
            }
        )
        XCTAssertTrue(
            report.findings.contains {
                $0.code == .untrustedCollector && $0.subject == .principal(fixture.collectorID)
            }
        )
        XCTAssertEqual(Set(report.findings.map(\.id)).count, report.findings.count)
        XCTAssertTrue(
            report.findings.allSatisfy {
                $0.id.rawValue.count == 64 && $0.id.rawValue.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            }
        )
        XCTAssertEqual(
            findingPairs(report),
            [
                findingPair(.duplicateAttachmentReference, .attachment(attachment.id)),
                findingPair(.duplicateRoadmapRow, .row(fixture.manifest.rows[0].id)),
                findingPair(.missingEvidence, .requirement(rowID: omitted.row.id, kind: omitted.kind)),
                findingPair(.missingReviewer, .citation(first.id)),
                findingPair(.untrustedCollector, .principal(fixture.collectorID))
            ]
        )
        let expectedIDs: [(VerificationEvidenceFindingCode, VerificationEvidenceFindingSubject, String)] = [
            (.duplicateRoadmapRow, .row(fixture.manifest.rows[0].id), "2"),
            (.missingEvidence, .requirement(rowID: omitted.row.id, kind: omitted.kind), ""),
            (.missingReviewer, .citation(first.id), ""),
            (.duplicateAttachmentReference, .attachment(attachment.id), "2"),
            (.untrustedCollector, .principal(fixture.collectorID), "")
        ]
        for (code, subject, discriminator) in expectedIDs {
            let finding = try XCTUnwrap(
                report.findings.first { $0.code == code && $0.subject == subject }
            )
            XCTAssertEqual(
                finding.id,
                independentFindingID(code: code, subject: subject, discriminator: discriminator)
            )
        }
    }

    func testTopLevelFindingSubjectsIDsOrderAndMultiFindingArchiveAreExact() throws {
        let fixture = try makeFixture()
        let invalidManifest = VerificationRoadmapManifest(
            reference: manifestReference(""),
            rows: []
        )
        let invalidLedger = VerificationEvidenceLedger(
            reference: ledgerReference(""),
            manifest: invalidManifest.reference,
            targetBuild: fixture.ledger.targetBuild,
            citations: []
        )
        let invalidPolicy = VerificationEvidenceTrustPolicy(
            roots: fixture.trustPolicy.roots,
            freshness: VerificationEvidenceFreshnessPolicy(
                modelOrUnitMaximumAgeMilliseconds: 0
            )
        )
        let invalidFixture = replacingTrustPolicy(
            replacingLedger(replacingManifest(fixture, with: invalidManifest), with: invalidLedger),
            with: invalidPolicy
        )
        let baseline = try signedAudit(invalidFixture)
        let expected = [
            findingPair(.invalidLedger, .ledger),
            findingPair(.invalidManifest, .manifest),
            findingPair(.invalidTrustPolicy, .trustPolicy)
        ]
        XCTAssertEqual(findingPairs(baseline.result.report), expected)
        XCTAssertEqual(baseline.result.report.findings.count, 3)
        for finding in baseline.result.report.findings {
            XCTAssertEqual(
                finding.id,
                independentFindingID(
                    code: finding.code,
                    subject: finding.subject,
                    discriminator: finding.code == .invalidTrustPolicy ? "modelOrUnit" : ""
                )
            )
        }
        XCTAssertEqual(
            independentArchiveSections(fixture: invalidFixture, report: baseline.result.report),
            archiveSections(baseline.result.archive.data)
        )
        XCTAssertEqual(
            baseline.result.receipt.evaluationSHA256,
            rawSHA256(independentReportEvaluationSection(baseline.result.report))
        )

        let reordered = replacingTrustPolicy(
            replacingLedger(
                replacingManifest(
                    invalidFixture,
                    with: replacingRows(invalidManifest, with: invalidManifest.rows.reversed())
                ),
                with: replacingCitations(invalidLedger, with: invalidLedger.citations.reversed())
            ),
            with: VerificationEvidenceTrustPolicy(
                roots: invalidPolicy.roots.reversed(),
                freshness: invalidPolicy.freshness
            )
        )
        let reorderedEnvelope = try auditEnvelope(reordered)
        let reorderedResult = try VerificationEvidenceAuditor.audit(
            manifest: reordered.manifest,
            ledger: reordered.ledger,
            trustPolicy: reordered.trustPolicy,
            auditAttestation: baseline.attestation,
            trustedVerificationTimeUnixMilliseconds: reordered.trustedTime
        )
        XCTAssertEqual(reorderedEnvelope.signingData, baseline.envelope.signingData)
        XCTAssertEqual(reorderedResult.report, baseline.result.report)
        XCTAssertEqual(reorderedResult.archive, baseline.result.archive)
        XCTAssertEqual(reorderedResult.receipt, baseline.result.receipt)
    }

    func testAggregateLiveStringRetainedByteAndWorkBudgetsPreserveErrors() throws {
        let fixture = try makeFixture()

        assertLedgerError(.countLimitExceeded(kind: .rows, maximum: 2)) {
            _ = try auditEnvelope(fixture, limits: limits(maximumRows: 2))
        }
        assertLedgerError(.totalStringsTooLarge(maximumUTF8Bytes: 128)) {
            _ = try auditEnvelope(
                fixture,
                limits: limits(maximumStringUTF8Bytes: 64, maximumTotalStringUTF8Bytes: 128)
            )
        }
        assertLedgerError(.workLimitExceeded(maximum: 1)) {
            _ = try auditEnvelope(fixture, limits: limits(maximumWorkUnits: 1))
        }

        let citation = try XCTUnwrap(fixture.ledger.citations.first)
        let oversizedSignature = replacingCollector(
            citation,
            with: VerificationEvidenceCollectorAttestation(
                collectorID: citation.collectorAttestation.collectorID,
                attestedAtUnixMilliseconds: citation.collectorAttestation.attestedAtUnixMilliseconds,
                signature: [UInt8](repeating: 0, count: 65)
            )
        )
        assertLedgerError(.binaryFieldTooLarge(maximumBytes: 64)) {
            _ = try VerificationEvidenceAuditor.collectorSigningData(
                for: oversizedSignature,
                limits: limits(maximumBinaryFieldBytes: 64)
            )
        }

        let retainedLimit = limits(maximumCanonicalRecordBytes: 4_096, maximumArchiveBytes: 4_096)
        for candidate in fixture.ledger.citations {
            XCTAssertNoThrow(try VerificationEvidenceAuditor.collectorSigningData(for: candidate, limits: retainedLimit))
        }
        assertLedgerError(.archiveTooLarge(maximumBytes: 4_096)) {
            _ = try auditEnvelope(fixture, limits: retainedLimit)
        }
    }

    func testExactArchiveMemoryAndWorkBoundariesSucceedThenFailByOne() throws {
        let fixture = try makeFixture()
        let baseline = try signedAudit(fixture)
        let archiveByteCount = baseline.result.archive.data.count
        let archiveCap = try minimumSuccessfulArchiveBytes(
            for: fixture,
            startingAt: archiveByteCount
        )
        let exactArchiveLimits = limits(
            maximumCanonicalRecordBytes: archiveCap,
            maximumArchiveBytes: archiveCap
        )
        let exactArchive = try signedAudit(fixture, limits: exactArchiveLimits)
        XCTAssertEqual(exactArchive.result.archive.data.count, archiveByteCount)
        XCTAssertGreaterThan(archiveCap, archiveByteCount)
        XCTAssertNoThrow(
            try exactArchive.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
                limits: exactArchiveLimits
            )
        )
        assertLedgerError(.archiveTooLarge(maximumBytes: archiveCap - 1)) {
            let belowLimit = limits(
                maximumCanonicalRecordBytes: archiveCap - 1,
                maximumArchiveBytes: archiveCap - 1
            )
            let signed = try signedAudit(
                fixture,
                limits: belowLimit
            )
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
                limits: belowLimit
            )
        }

        let requiredWork = try minimumSuccessfulWorkUnits(for: fixture)
        XCTAssertNoThrow(
            try auditEnvelope(fixture, limits: limits(maximumWorkUnits: requiredWork))
        )
        assertLedgerError(.workLimitExceeded(maximum: requiredWork - 1)) {
            _ = try auditEnvelope(fixture, limits: limits(maximumWorkUnits: requiredWork - 1))
        }

        let emptyManifest = replacingRows(fixture.manifest, with: [])
        let emptyFixture = replacingLedger(
            replacingManifest(fixture, with: emptyManifest),
            with: replacingCitations(fixture.ledger, with: [])
        )
        let emptyWork = try minimumSuccessfulWorkUnits(for: emptyFixture)
        XCTAssertGreaterThan(requiredWork, emptyWork)
    }

    func testCancellationDeadlineAndConfiguredPollingPreserveCancellation() throws {
        let fixture = try makeFixture()
        let citation = try XCTUnwrap(fixture.ledger.citations.first)
        let polling = CancellationProbe(cancelOnCall: 4)

        assertLedgerError(.cancelled) {
            _ = try VerificationEvidenceAuditor.collectorSigningData(
                for: citation,
                limits: limits(cancellationCheckInterval: 1),
                cancellationCheck: { polling.check() }
            )
        }
        XCTAssertEqual(polling.callCount, 4)

        let expiredDeadline = CancellationProbe(cancelOnCall: 1)
        assertLedgerError(.cancelled) {
            _ = try auditEnvelope(fixture, cancellationCheck: { expiredDeadline.check() })
        }
        XCTAssertEqual(expiredDeadline.callCount, 1)

        for operation in 0..<4 {
            let delayed = CancellationProbe(cancelOnCall: 5)
            assertLedgerError(.cancelled) {
                switch operation {
                case 0:
                    _ = try auditEnvelope(
                        fixture,
                        limits: limits(cancellationCheckInterval: 1),
                        cancellationCheck: { delayed.check() }
                    )
                case 1:
                    let signed = try signedAudit(fixture)
                    _ = try VerificationEvidenceAuditor.audit(
                        manifest: fixture.manifest,
                        ledger: fixture.ledger,
                        trustPolicy: fixture.trustPolicy,
                        auditAttestation: signed.attestation,
                        trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
                        limits: limits(cancellationCheckInterval: 1),
                        cancellationCheck: { delayed.check() }
                    )
                case 2:
                    let signed = try signedAudit(fixture)
                    _ = try fixture.ledger.audit(
                        against: fixture.manifest,
                        trustPolicy: fixture.trustPolicy,
                        auditAttestation: signed.attestation,
                        trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
                        limits: limits(cancellationCheckInterval: 1),
                        cancellationCheck: { delayed.check() }
                    )
                default:
                    let signed = try signedAudit(fixture)
                    try signed.result.receipt.validateCurrent(
                        manifest: fixture.manifest,
                        ledger: fixture.ledger,
                        trustPolicy: fixture.trustPolicy,
                        trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
                        limits: limits(cancellationCheckInterval: 1),
                        cancellationCheck: { delayed.check() }
                    )
                }
            }
            XCTAssertEqual(delayed.callCount, 5)
        }
    }

    func testEmptyAndMalformedSortInputsDoNotTrap() throws {
        let fixture = try makeFixture()
        let emptyManifest = replacingRows(fixture.manifest, with: [])
        let emptyLedger = replacingCitations(fixture.ledger, with: [])
        let empty = replacingLedger(replacingManifest(fixture, with: emptyManifest), with: emptyLedger)
        let emptyResult = try signedAudit(empty).result

        XCTAssertEqual(emptyResult.report.rows, [])
        XCTAssertEqual(emptyResult.report.findings, [])
        XCTAssertEqual(emptyResult.receipt.requiredEvidenceCount, 0)
        XCTAssertFalse(emptyResult.report.isLedgerCompleteAndValid)

        let malformedRows = [
            VerificationRoadmapRowRequirement(
                reference: rowReference(""),
                applicability: .applicable(statefulness: .stateless),
                completionClaimed: true
            ),
            VerificationRoadmapRowRequirement(
                reference: rowReference("\u{1F}"),
                applicability: .applicable(statefulness: .stateful),
                completionClaimed: true
            )
        ]
        let malformedRoots =
            fixture.trustPolicy.roots + [
                VerificationEvidenceTrustRoot(
                    principalID: principalID(""),
                    roles: [],
                    ed25519PublicKey: [],
                    validFromUnixMilliseconds: 2,
                    validThroughUnixMilliseconds: 1
                ),
                VerificationEvidenceTrustRoot(
                    principalID: principalID("\u{1F}"),
                    roles: [.collector],
                    ed25519PublicKey: [1],
                    validFromUnixMilliseconds: 1,
                    validThroughUnixMilliseconds: 2
                )
            ]
        let malformed = replacingTrustPolicy(
            replacingLedger(
                replacingManifest(fixture, with: replacingRows(fixture.manifest, with: malformedRows)),
                with: emptyLedger
            ),
            with: VerificationEvidenceTrustPolicy(roots: malformedRoots)
        )
        let malformedResult = try signedAudit(malformed).result

        XCTAssertEqual(malformedResult.report.rows.count, 2)
        XCTAssertTrue(malformedResult.report.findings.contains { $0.code == .invalidManifest })
        XCTAssertTrue(malformedResult.report.findings.contains { $0.code == .invalidTrustPolicy })
        XCTAssertTrue(malformedResult.report.containsErrors)
    }

    func testDescriptionsDebugDescriptionsAndReflectionRedactSubmittedValues() throws {
        let fixture = try makeFixture()
        let signed = try signedAudit(fixture)
        let citation = try XCTUnwrap(fixture.ledger.citations.first)
        let attachment = try XCTUnwrap(citation.attachments.first)
        let subject = VerificationEvidenceFindingSubject.principal(principalID("principal-secret-value"))
        let missingLedger = replacingCitations(
            fixture.ledger,
            with: fixture.ledger.citations.dropLast()
        )
        let missingReport = try signedAudit(replacingLedger(fixture, with: missingLedger)).result.report
        let finding = try XCTUnwrap(missingReport.findings.first)
        let incompleteRow = try XCTUnwrap(missingReport.rows.first { $0.status == .invalid })
        let incompleteCell = try XCTUnwrap(incompleteRow.cells.first { $0.status == .missing })
        let secrets = [
            "manifest-secret", "row-stateful", "ledger-secret", "application-secret",
            "build-secret", "citation-row-stateful-modelOrUnit", "attachment-row-stateful-modelOrUnit",
            "collector-secret", "reviewer-secret", "auditor-secret", "submitter-secret",
            "principal-secret-value", "application-bundle", "executable", "signing-identity",
            "test-run-secret", "test-runner", "test-bundle", "test-configuration",
            "application/octet-stream"
        ]
        let values: [Any] = [
            fixture.manifest,
            fixture.manifest.rows[0],
            fixture.ledger,
            fixture.ledger.targetBuild,
            citation,
            citation.collectorAttestation,
            citation.reviews[0],
            attachment,
            attachment.artifact,
            fixture.trustPolicy,
            fixture.trustPolicy.roots[0],
            signed.envelope,
            signed.attestation,
            signed.result.report,
            signed.result.archive,
            signed.result.receipt,
            signed.result,
            citation.attachments[0].artifact.digest,
            finding,
            incompleteRow,
            incompleteCell,
            subject
        ]

        for value in values {
            let rendered = [
                String(describing: value),
                String(reflecting: value),
                mirrorText(value)
            ].joined(separator: "\n")
            XCTAssertTrue(rendered.contains("<redacted>"), String(describing: type(of: value)))
            for secret in secrets {
                XCTAssertFalse(rendered.contains(secret), "\(type(of: value)) leaked \(secret)")
            }
        }
        let errorSecret = String(repeating: "private-value-", count: 6)
        let oversizedManifest = VerificationRoadmapManifest(
            reference: manifestReference(errorSecret),
            rows: fixture.manifest.rows
        )
        let oversized = replacingManifest(fixture, with: oversizedManifest)
        let error = captureLedgerError {
            _ = try auditEnvelope(
                oversized,
                limits: limits(maximumStringUTF8Bytes: 64)
            )
        }
        XCTAssertEqual(error, .stringTooLarge(field: "reference.id", maximumUTF8Bytes: 64))
        XCTAssertFalse(error.localizedDescription.contains(errorSecret))
    }

    func testArchiveReportReceiptAndAttestationIgnoreInsertionOrder() throws {
        let fixture = try makeFixture()
        let first = try XCTUnwrap(fixture.ledger.citations.first)
        let secondReviewerID = principalID("second-reviewer")
        let secondReviewerKey = try privateKey(seed: 0x55)
        let expanded = try signCitation(
            replacingAttachments(
                first,
                with: first.attachments + [attachment("auxiliary-log", kind: .log)]
            ),
            collectorKey: fixture.keys.collector,
            reviewerKey: fixture.keys.reviewer,
            reviewerID: fixture.reviewerID
        )
        let secondReview = try signedReview(
            for: expanded,
            reviewerID: secondReviewerID,
            reviewerKey: secondReviewerKey
        )
        let multiValueCitation = replacingReviews(
            expanded,
            with: expanded.reviews + [secondReview]
        )
        let expandedLedger = replacingCitations(
            fixture.ledger,
            with: fixture.ledger.citations.map { $0.id == first.id ? multiValueCitation : $0 }
        )
        let expandedPolicy = VerificationEvidenceTrustPolicy(
            roots: fixture.trustPolicy.roots + [
                trustRoot(secondReviewerID, roles: [.reviewer], key: secondReviewerKey)
            ],
            freshness: fixture.trustPolicy.freshness
        )
        let expandedFixture = replacingTrustPolicy(
            replacingLedger(fixture, with: expandedLedger),
            with: expandedPolicy
        )
        let baseline = try signedAudit(expandedFixture)
        let baselineCell = try XCTUnwrap(
            try row(named: first.row.id.rawValue, in: baseline.result.report).cells.first {
                $0.kind == first.kind
            }
        )
        XCTAssertEqual(baselineCell.status, .untrusted)
        XCTAssertEqual(
            findingPairs(baseline.result.report),
            [findingPair(.duplicateReview, .citation(first.id))]
        )
        assertGloballyInvalid(
            baseline.result,
            requiredEvidenceCount: 9,
            completeEvidenceCount: 8
        )
        let citations = expandedFixture.ledger.citations.reversed().map { citation in
            replacingReviews(
                replacingAttachments(citation, with: citation.attachments.reversed()),
                with: citation.reviews.reversed()
            )
        }
        let reordered = replacingTrustPolicy(
            replacingLedger(
                replacingManifest(
                    expandedFixture,
                    with: replacingRows(
                        expandedFixture.manifest,
                        with: expandedFixture.manifest.rows.reversed()
                    )
                ),
                with: replacingCitations(expandedFixture.ledger, with: citations)
            ),
            with: VerificationEvidenceTrustPolicy(
                roots: expandedFixture.trustPolicy.roots.reversed(),
                freshness: expandedFixture.trustPolicy.freshness
            )
        )
        let reorderedEnvelope = try auditEnvelope(reordered)
        let reorderedResult = try VerificationEvidenceAuditor.audit(
            manifest: reordered.manifest,
            ledger: reordered.ledger,
            trustPolicy: reordered.trustPolicy,
            auditAttestation: baseline.attestation,
            trustedVerificationTimeUnixMilliseconds: reordered.trustedTime
        )

        XCTAssertEqual(reorderedEnvelope.signingData, baseline.envelope.signingData)
        XCTAssertEqual(reorderedResult.report, baseline.result.report)
        XCTAssertEqual(reorderedResult.archive, baseline.result.archive)
        XCTAssertEqual(reorderedResult.receipt, baseline.result.receipt)
        XCTAssertEqual(reorderedResult, baseline.result)
    }
}

private let runStartedTime: UInt64 = 900
private let runFinishedTime: UInt64 = 1_000
private let collectedTime: UInt64 = 1_100
private let collectorTime: UInt64 = 1_200
private let reviewerTime: UInt64 = 1_300
private let auditedTime: UInt64 = 1_900
private let trustedTime: UInt64 = 2_000

private struct SigningKeys {
    let submitter: Curve25519.Signing.PrivateKey
    let collector: Curve25519.Signing.PrivateKey
    let reviewer: Curve25519.Signing.PrivateKey
    let auditor: Curve25519.Signing.PrivateKey
}

private struct LedgerFixture {
    let manifest: VerificationRoadmapManifest
    let ledger: VerificationEvidenceLedger
    let trustPolicy: VerificationEvidenceTrustPolicy
    let submitterID: VerificationEvidencePrincipalID
    let collectorID: VerificationEvidencePrincipalID
    let reviewerID: VerificationEvidencePrincipalID
    let auditorID: VerificationEvidencePrincipalID
    let keys: SigningKeys
    let auditedTime: UInt64
    let trustedTime: UInt64
}

private struct SignedAudit {
    let envelope: VerificationEvidenceAuditSigningEnvelope
    let attestation: VerificationEvidenceAuditAttestation
    let result: VerificationEvidenceAuditResult
}

private struct FindingPair: Equatable {
    let code: VerificationEvidenceFindingCode
    let subject: VerificationEvidenceFindingSubject
}

private enum ArchiveReaderError: Error {
    case truncated
    case invalidUTF8
    case integerOverflow
}

private struct ArchiveReader {
    let data: Data
    private(set) var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { offset == data.count }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count, count <= data.count - offset else {
            throw ArchiveReaderError.truncated
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = [UInt8](try readData(count: 2))
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = [UInt8](try readData(count: 4))
        return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    mutating func readString() throws -> String {
        let bytes = try readLengthPrefixedData()
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw ArchiveReaderError.invalidUTF8
        }
        return value
    }

    mutating func readDigest() throws -> VerificationEvidenceDigest {
        let algorithm = try readString()
        guard algorithm == "sha256" else { throw ArchiveReaderError.invalidUTF8 }
        return VerificationEvidenceDigest(bytes: [UInt8](try readLengthPrefixedData()))
    }

    mutating func readLengthPrefixedData() throws -> Data {
        let count = try readUInt32()
        guard let exact = Int(exactly: count) else { throw ArchiveReaderError.integerOverflow }
        return try readData(count: exact)
    }
}

private struct IndependentWriter {
    private(set) var data = Data()

    mutating func appendRaw(_ value: Data) {
        data.append(value)
    }

    mutating func appendUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        data.append(contentsOf: (0..<2).map { UInt8((value >> UInt16($0 * 8)) & 0xFF) })
    }

    mutating func appendUInt32(_ value: UInt32) {
        data.append(contentsOf: (0..<4).map { UInt8((value >> UInt32($0 * 8)) & 0xFF) })
    }

    mutating func appendUInt64(_ value: UInt64) {
        data.append(contentsOf: (0..<8).map { UInt8((value >> UInt64($0 * 8)) & 0xFF) })
    }

    mutating func appendBool(_ value: Bool) {
        appendUInt8(value ? 1 : 0)
    }

    mutating func appendCount(_ value: Int) {
        appendUInt32(UInt32(value))
    }

    mutating func appendString(_ value: String) {
        appendData(Data(value.utf8))
    }

    mutating func appendBytes(_ value: [UInt8]) {
        appendData(Data(value))
    }

    mutating func appendData(_ value: Data) {
        appendCount(value.count)
        appendRaw(value)
    }

    mutating func appendOptionalUInt64(_ value: UInt64?) {
        guard let value else {
            appendUInt8(0)
            return
        }
        appendUInt8(1)
        appendUInt64(value)
    }

    mutating func appendDigest(_ digest: VerificationEvidenceDigest) {
        appendString(digest.algorithm.rawValue)
        appendBytes(digest.bytes)
    }

    mutating func appendReference<Domain>(_ reference: VerificationEvidenceRevisionReference<Domain>) {
        appendString(reference.id.rawValue)
        appendUInt64(reference.revision.rawValue)
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelOnCall: Int
    private var calls = 0

    init(cancelOnCall: Int) {
        self.cancelOnCall = cancelOnCall
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func check() -> Bool {
        lock.withLock {
            calls += 1
            return calls >= cancelOnCall
        }
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

private func makeFixture() throws -> LedgerFixture {
    let keys = SigningKeys(
        submitter: try privateKey(seed: 0x11),
        collector: try privateKey(seed: 0x22),
        reviewer: try privateKey(seed: 0x33),
        auditor: try privateKey(seed: 0x44)
    )
    let submitter = principalID("submitter-secret")
    let collector = principalID("collector-secret")
    let reviewer = principalID("reviewer-secret")
    let auditor = principalID("auditor-secret")
    let rows = [
        requirement("row-stateful", statefulness: .stateful, completionClaimed: true),
        requirement("row-stateless", statefulness: .stateless, completionClaimed: true),
        VerificationRoadmapRowRequirement(
            reference: rowReference("row-na"),
            applicability: .notApplicable,
            completionClaimed: false
        )
    ]
    let manifest = VerificationRoadmapManifest(
        reference: manifestReference("manifest-secret"),
        rows: rows
    )
    let build = buildProvenance()
    let run = testRun(build: build)
    var citations: [VerificationEvidenceCitation] = []
    for row in rows where row.completionClaimed {
        for kind in expectedKinds(for: row.applicability) {
            let token = "\(row.id.rawValue)-\(kind.rawValue)"
            let unsigned = VerificationEvidenceCitation(
                id: citationID("citation-\(token)"),
                row: row.reference,
                kind: kind,
                basis: .measured,
                outcome: .passed,
                collectedAtUnixMilliseconds: collectedTime,
                testRun: run,
                attachments: [attachment(token, kind: requiredAttachmentKind(for: kind))],
                collectorAttestation: VerificationEvidenceCollectorAttestation(
                    collectorID: collector,
                    attestedAtUnixMilliseconds: collectorTime,
                    signature: []
                ),
                reviews: []
            )
            citations.append(
                try signCitation(
                    unsigned,
                    collectorKey: keys.collector,
                    reviewerKey: keys.reviewer,
                    reviewerID: reviewer
                )
            )
        }
    }
    let ledger = VerificationEvidenceLedger(
        reference: ledgerReference("ledger-secret"),
        manifest: manifest.reference,
        targetBuild: build,
        citations: citations
    )
    let trustPolicy = VerificationEvidenceTrustPolicy(roots: [
        trustRoot(submitter, roles: [.submitter], key: keys.submitter),
        trustRoot(collector, roles: [.collector], key: keys.collector),
        trustRoot(reviewer, roles: [.reviewer], key: keys.reviewer),
        trustRoot(auditor, roles: [.auditor], key: keys.auditor)
    ])
    return LedgerFixture(
        manifest: manifest,
        ledger: ledger,
        trustPolicy: trustPolicy,
        submitterID: submitter,
        collectorID: collector,
        reviewerID: reviewer,
        auditorID: auditor,
        keys: keys,
        auditedTime: auditedTime,
        trustedTime: trustedTime
    )
}

private func signedAudit(
    _ fixture: LedgerFixture,
    limits: VerificationEvidenceLedgerLimits = .default
) throws -> SignedAudit {
    let envelope = try auditEnvelope(fixture, limits: limits)
    let signature = try fixture.keys.auditor.signature(for: independentAuditSigningData(envelope))
    let attestation = envelope.attestation(signature: Array(signature))
    let result = try VerificationEvidenceAuditor.audit(
        manifest: fixture.manifest,
        ledger: fixture.ledger,
        trustPolicy: fixture.trustPolicy,
        auditAttestation: attestation,
        trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
        limits: limits
    )
    return SignedAudit(envelope: envelope, attestation: attestation, result: result)
}

private func auditEnvelope(
    _ fixture: LedgerFixture,
    limits: VerificationEvidenceLedgerLimits = .default,
    cancellationCheck: @escaping VerificationEvidenceAuditor.CancellationCheck = { false }
) throws -> VerificationEvidenceAuditSigningEnvelope {
    try VerificationEvidenceAuditor.auditSigningEnvelope(
        manifest: fixture.manifest,
        ledger: fixture.ledger,
        trustPolicy: fixture.trustPolicy,
        auditorID: fixture.auditorID,
        submitterID: fixture.submitterID,
        auditedAtUnixMilliseconds: fixture.auditedTime,
        trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
        limits: limits,
        cancellationCheck: cancellationCheck
    )
}

private func signCitation(
    _ citation: VerificationEvidenceCitation,
    collectorKey: Curve25519.Signing.PrivateKey,
    reviewerKey: Curve25519.Signing.PrivateKey,
    reviewerID: VerificationEvidencePrincipalID,
    reviewExpiresAt: UInt64? = nil
) throws -> VerificationEvidenceCitation {
    let unsigned = replacingCollector(
        replacingReviews(citation, with: []),
        with: VerificationEvidenceCollectorAttestation(
            collectorID: citation.collectorAttestation.collectorID,
            attestedAtUnixMilliseconds: citation.collectorAttestation.attestedAtUnixMilliseconds,
            signature: []
        )
    )
    let collectorData = independentCollectorSigningData(for: unsigned)
    let collected = replacingCollector(
        unsigned,
        with: VerificationEvidenceCollectorAttestation(
            collectorID: unsigned.collectorAttestation.collectorID,
            attestedAtUnixMilliseconds: unsigned.collectorAttestation.attestedAtUnixMilliseconds,
            signature: Array(try collectorKey.signature(for: collectorData))
        )
    )
    let claimDigest = independentEvidenceClaimSHA256(for: collected)
    let unsignedReview = VerificationEvidenceReviewAttestation(
        reviewerID: reviewerID,
        verdict: .accepted,
        reviewedAtUnixMilliseconds: reviewerTime,
        expiresAtUnixMilliseconds: reviewExpiresAt,
        evidenceClaimSHA256: claimDigest,
        signature: []
    )
    let reviewData = independentReviewerSigningData(for: collected, review: unsignedReview)
    let review = VerificationEvidenceReviewAttestation(
        reviewerID: reviewerID,
        verdict: .accepted,
        reviewedAtUnixMilliseconds: reviewerTime,
        expiresAtUnixMilliseconds: reviewExpiresAt,
        evidenceClaimSHA256: claimDigest,
        signature: Array(try reviewerKey.signature(for: reviewData))
    )
    return replacingReviews(collected, with: [review])
}

private func signedReview(
    for citation: VerificationEvidenceCitation,
    reviewerID: VerificationEvidencePrincipalID,
    reviewerKey: Curve25519.Signing.PrivateKey,
    verdict: VerificationEvidenceReviewVerdict = .accepted,
    reviewedAt: UInt64 = reviewerTime,
    expiresAt: UInt64? = nil
) throws -> VerificationEvidenceReviewAttestation {
    let unsigned = VerificationEvidenceReviewAttestation(
        reviewerID: reviewerID,
        verdict: verdict,
        reviewedAtUnixMilliseconds: reviewedAt,
        expiresAtUnixMilliseconds: expiresAt,
        evidenceClaimSHA256: independentEvidenceClaimSHA256(for: citation),
        signature: []
    )
    return VerificationEvidenceReviewAttestation(
        reviewerID: unsigned.reviewerID,
        verdict: unsigned.verdict,
        reviewedAtUnixMilliseconds: unsigned.reviewedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: unsigned.expiresAtUnixMilliseconds,
        evidenceClaimSHA256: unsigned.evidenceClaimSHA256,
        signature: Array(
            try reviewerKey.signature(
                for: independentReviewerSigningData(for: citation, review: unsigned)
            )
        )
    )
}

private func requirement(
    _ name: String,
    statefulness: VerificationRoadmapStatefulness,
    completionClaimed: Bool
) -> VerificationRoadmapRowRequirement {
    VerificationRoadmapRowRequirement(
        reference: rowReference(name),
        applicability: .applicable(statefulness: statefulness),
        completionClaimed: completionClaimed
    )
}

private func expectedKinds(
    for applicability: VerificationRoadmapApplicability
) -> [VerificationEvidenceKind] {
    switch applicability {
    case .notApplicable:
        []
    case .applicable(.stateless):
        [.modelOrUnit, .uiInteraction, .semanticAccessibility, .packagedAppSmoke]
    case .applicable(.stateful):
        [.modelOrUnit, .uiInteraction, .semanticAccessibility, .persistence, .packagedAppSmoke]
    }
}

private func requiredAttachmentKind(
    for kind: VerificationEvidenceKind
) -> VerificationEvidenceAttachmentKind {
    switch kind {
    case .modelOrUnit: .modelOrUnitRecord
    case .uiInteraction: .uiInteractionRecord
    case .semanticAccessibility: .semanticAccessibilityRecord
    case .persistence: .persistenceRecord
    case .packagedAppSmoke: .packagedAppSmokeRecord
    }
}

private func buildProvenance() -> VerificationEvidenceAppBuildProvenance {
    VerificationEvidenceAppBuildProvenance(
        application: applicationReference("application-secret"),
        build: buildReference("build-secret"),
        applicationBundle: artifact("application-bundle", role: .applicationBundle),
        executable: artifact("executable", role: .executable),
        signingIdentity: artifact("signing-identity", role: .signingIdentity)
    )
}

private func testRun(build: VerificationEvidenceAppBuildProvenance) -> VerificationEvidenceTestRunProvenance {
    VerificationEvidenceTestRunProvenance(
        reference: testRunReference("test-run-secret"),
        build: build,
        testRunner: artifact("test-runner", role: .testRunner),
        testBundle: artifact("test-bundle", role: .testBundle),
        configuration: artifact("test-configuration", role: .testConfiguration),
        startedAtUnixMilliseconds: runStartedTime,
        finishedAtUnixMilliseconds: runFinishedTime,
        outcome: .passed
    )
}

private func attachment(
    _ name: String,
    kind: VerificationEvidenceAttachmentKind
) -> VerificationEvidenceAttachmentReference {
    VerificationEvidenceAttachmentReference(
        kind: kind,
        artifact: artifact("attachment-\(name)", role: .evidenceAttachment)
    )
}

private func artifact(
    _ name: String,
    role: VerificationEvidenceArtifactRole
) -> VerificationEvidenceArtifactReference {
    let bytes = Data("artifact-payload:\(name)".utf8)
    return VerificationEvidenceArtifactReference(
        id: artifactID(name),
        role: role,
        mediaType: "application/octet-stream",
        byteCount: UInt64(bytes.count),
        digest: rawSHA256(bytes)
    )
}

private func trustRoot(
    _ id: VerificationEvidencePrincipalID,
    roles: Set<VerificationEvidenceTrustRole>,
    key: Curve25519.Signing.PrivateKey,
    validFrom: UInt64 = 500,
    validThrough: UInt64 = 5_000,
    revokedAt: UInt64? = nil
) -> VerificationEvidenceTrustRoot {
    VerificationEvidenceTrustRoot(
        principalID: id,
        roles: roles,
        ed25519PublicKey: Array(key.publicKey.rawRepresentation),
        validFromUnixMilliseconds: validFrom,
        validThroughUnixMilliseconds: validThrough,
        revokedAtUnixMilliseconds: revokedAt
    )
}

private func freshnessPolicy(
    kind: VerificationEvidenceKind? = nil,
    maximumAge: UInt64,
    maximumCollectionLag: UInt64 = VerificationEvidenceFreshnessPolicy.dayMilliseconds
) -> VerificationEvidenceFreshnessPolicy {
    let otherAge = maximumAge + 1
    return VerificationEvidenceFreshnessPolicy(
        modelOrUnitMaximumAgeMilliseconds: kind == nil || kind == .modelOrUnit ? maximumAge : otherAge,
        uiInteractionMaximumAgeMilliseconds: kind == nil || kind == .uiInteraction ? maximumAge : otherAge,
        semanticAccessibilityMaximumAgeMilliseconds: kind == nil || kind == .semanticAccessibility
            ? maximumAge : otherAge,
        persistenceMaximumAgeMilliseconds: kind == nil || kind == .persistence ? maximumAge : otherAge,
        packagedAppSmokeMaximumAgeMilliseconds: kind == nil || kind == .packagedAppSmoke ? maximumAge : otherAge,
        maximumCollectionLagMilliseconds: maximumCollectionLag
    )
}

private func privateKey(seed: UInt8) throws -> Curve25519.Signing.PrivateKey {
    try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
}

private func row(
    named name: String,
    in report: VerificationEvidenceAuditReport
) throws -> VerificationEvidenceRowCompleteness {
    try XCTUnwrap(report.rows.first { $0.id.rawValue == name })
}

private func findingPairs(_ report: VerificationEvidenceAuditReport) -> [FindingPair] {
    report.findings.map { FindingPair(code: $0.code, subject: $0.subject) }
}

private func findingPair(
    _ code: VerificationEvidenceFindingCode,
    _ subject: VerificationEvidenceFindingSubject
) -> FindingPair {
    FindingPair(code: code, subject: subject)
}

private func isCitationSubject(_ subject: VerificationEvidenceFindingSubject) -> Bool {
    if case .citation = subject { return true }
    return false
}

private func assertGloballyInvalid(
    _ result: VerificationEvidenceAuditResult,
    requiredEvidenceCount: Int,
    completeEvidenceCount: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(result.report.containsErrors, file: file, line: line)
    XCTAssertFalse(result.report.isLedgerCompleteAndValid, file: file, line: line)
    XCTAssertEqual(result.report.validatedCompleteRowIDs, [], file: file, line: line)
    XCTAssertEqual(result.receipt.completedRowCount, 0, file: file, line: line)
    XCTAssertEqual(result.receipt.requiredEvidenceCount, requiredEvidenceCount, file: file, line: line)
    XCTAssertEqual(result.receipt.completeEvidenceCount, completeEvidenceCount, file: file, line: line)
    XCTAssertEqual(result.receipt.findingCount, result.report.findings.count, file: file, line: line)
}

private func assertInvalidCell(
    _ result: VerificationEvidenceAuditResult,
    citation: VerificationEvidenceCitation,
    status: VerificationEvidenceCompletenessStatus,
    evidenceCount: Int = 1,
    citationIDs: [VerificationEvidenceCitationID]? = nil,
    completeEvidenceCount: Int,
    findings: [FindingPair],
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let auditedRow = try row(named: citation.row.id.rawValue, in: result.report)
    let cell = try XCTUnwrap(
        auditedRow.cells.first { $0.kind == citation.kind },
        file: file,
        line: line
    )
    XCTAssertEqual(auditedRow.status, .invalid, file: file, line: line)
    XCTAssertEqual(cell.status, status, file: file, line: line)
    XCTAssertEqual(cell.evidenceCount, evidenceCount, file: file, line: line)
    XCTAssertEqual(cell.citationIDs, citationIDs ?? [citation.id], file: file, line: line)
    XCTAssertEqual(findingPairs(result.report), findings, file: file, line: line)
    assertGloballyInvalid(
        result,
        requiredEvidenceCount: 9,
        completeEvidenceCount: completeEvidenceCount,
        file: file,
        line: line
    )
}

private func replacingRows(
    _ manifest: VerificationRoadmapManifest,
    with rows: some Sequence<VerificationRoadmapRowRequirement>
) -> VerificationRoadmapManifest {
    VerificationRoadmapManifest(reference: manifest.reference, rows: Array(rows))
}

private func replacingCitations(
    _ ledger: VerificationEvidenceLedger,
    with citations: some Sequence<VerificationEvidenceCitation>
) -> VerificationEvidenceLedger {
    VerificationEvidenceLedger(
        reference: ledger.reference,
        manifest: ledger.manifest,
        targetBuild: ledger.targetBuild,
        citations: Array(citations)
    )
}

private func replacingManifest(
    _ fixture: LedgerFixture,
    with manifest: VerificationRoadmapManifest
) -> LedgerFixture {
    let ledger = VerificationEvidenceLedger(
        reference: fixture.ledger.reference,
        manifest: manifest.reference,
        targetBuild: fixture.ledger.targetBuild,
        citations: fixture.ledger.citations
    )
    return LedgerFixture(
        manifest: manifest,
        ledger: ledger,
        trustPolicy: fixture.trustPolicy,
        submitterID: fixture.submitterID,
        collectorID: fixture.collectorID,
        reviewerID: fixture.reviewerID,
        auditorID: fixture.auditorID,
        keys: fixture.keys,
        auditedTime: fixture.auditedTime,
        trustedTime: fixture.trustedTime
    )
}

private func replacingLedger(
    _ fixture: LedgerFixture,
    with ledger: VerificationEvidenceLedger
) -> LedgerFixture {
    LedgerFixture(
        manifest: fixture.manifest,
        ledger: ledger,
        trustPolicy: fixture.trustPolicy,
        submitterID: fixture.submitterID,
        collectorID: fixture.collectorID,
        reviewerID: fixture.reviewerID,
        auditorID: fixture.auditorID,
        keys: fixture.keys,
        auditedTime: fixture.auditedTime,
        trustedTime: fixture.trustedTime
    )
}

private func replacingTrustPolicy(
    _ fixture: LedgerFixture,
    with trustPolicy: VerificationEvidenceTrustPolicy
) -> LedgerFixture {
    LedgerFixture(
        manifest: fixture.manifest,
        ledger: fixture.ledger,
        trustPolicy: trustPolicy,
        submitterID: fixture.submitterID,
        collectorID: fixture.collectorID,
        reviewerID: fixture.reviewerID,
        auditorID: fixture.auditorID,
        keys: fixture.keys,
        auditedTime: fixture.auditedTime,
        trustedTime: fixture.trustedTime
    )
}

private func replacingRoot(
    _ policy: VerificationEvidenceTrustPolicy,
    principalID: VerificationEvidencePrincipalID,
    roles: Set<VerificationEvidenceTrustRole>? = nil,
    key: Curve25519.Signing.PrivateKey? = nil,
    validFrom: UInt64? = nil,
    validThrough: UInt64? = nil,
    revokedAt: UInt64? = nil,
    replaceRevocation: Bool = false
) -> VerificationEvidenceTrustPolicy {
    VerificationEvidenceTrustPolicy(
        roots: policy.roots.map { root in
            guard root.principalID == principalID else { return root }
            return VerificationEvidenceTrustRoot(
                principalID: root.principalID,
                roles: roles ?? root.roles,
                ed25519PublicKey: key.map { Array($0.publicKey.rawRepresentation) }
                    ?? root.ed25519PublicKey,
                validFromUnixMilliseconds: validFrom ?? root.validFromUnixMilliseconds,
                validThroughUnixMilliseconds: validThrough ?? root.validThroughUnixMilliseconds,
                revokedAtUnixMilliseconds: replaceRevocation ? revokedAt : root.revokedAtUnixMilliseconds
            )
        },
        freshness: policy.freshness
    )
}

private func replacingAuditor(
    _ fixture: LedgerFixture,
    id: VerificationEvidencePrincipalID,
    key: Curve25519.Signing.PrivateKey
) -> LedgerFixture {
    LedgerFixture(
        manifest: fixture.manifest,
        ledger: fixture.ledger,
        trustPolicy: fixture.trustPolicy,
        submitterID: fixture.submitterID,
        collectorID: fixture.collectorID,
        reviewerID: fixture.reviewerID,
        auditorID: id,
        keys: SigningKeys(
            submitter: fixture.keys.submitter,
            collector: fixture.keys.collector,
            reviewer: fixture.keys.reviewer,
            auditor: key
        ),
        auditedTime: fixture.auditedTime,
        trustedTime: fixture.trustedTime
    )
}

private func replacingCitation(
    _ fixture: LedgerFixture,
    _ id: VerificationEvidenceCitationID,
    with replacement: VerificationEvidenceCitation
) -> LedgerFixture {
    let citations = fixture.ledger.citations.map { $0.id == id ? replacement : $0 }
    return replacingLedger(fixture, with: replacingCitations(fixture.ledger, with: citations))
}

private func citationCopy(
    _ citation: VerificationEvidenceCitation,
    id: VerificationEvidenceCitationID? = nil,
    row: VerificationRoadmapRowReference? = nil,
    kind: VerificationEvidenceKind? = nil,
    basis: VerificationEvidenceObservationBasis? = nil,
    outcome: VerificationEvidenceObservationOutcome? = nil,
    collectedAt: UInt64? = nil,
    expiresAt: UInt64? = nil,
    testRun: VerificationEvidenceTestRunProvenance? = nil
) -> VerificationEvidenceCitation {
    VerificationEvidenceCitation(
        id: id ?? citation.id,
        row: row ?? citation.row,
        kind: kind ?? citation.kind,
        basis: basis ?? citation.basis,
        outcome: outcome ?? citation.outcome,
        collectedAtUnixMilliseconds: collectedAt ?? citation.collectedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: expiresAt ?? citation.expiresAtUnixMilliseconds,
        testRun: testRun ?? citation.testRun,
        attachments: citation.attachments,
        collectorAttestation: citation.collectorAttestation,
        reviews: citation.reviews
    )
}

private func resignedCitation(
    _ citation: VerificationEvidenceCitation,
    fixture: LedgerFixture,
    reviewerID: VerificationEvidencePrincipalID? = nil,
    collectorKey: Curve25519.Signing.PrivateKey? = nil,
    reviewerKey: Curve25519.Signing.PrivateKey? = nil
) throws -> VerificationEvidenceCitation {
    try signCitation(
        citation,
        collectorKey: collectorKey ?? fixture.keys.collector,
        reviewerKey: reviewerKey ?? fixture.keys.reviewer,
        reviewerID: reviewerID ?? fixture.reviewerID
    )
}

private func replacingTestRun(
    _ run: VerificationEvidenceTestRunProvenance,
    reference: VerificationEvidenceTestRunReference? = nil,
    testRunner: VerificationEvidenceArtifactReference? = nil,
    startedAt: UInt64? = nil,
    finishedAt: UInt64? = nil,
    outcome: VerificationEvidenceTestRunOutcome? = nil
) -> VerificationEvidenceTestRunProvenance {
    VerificationEvidenceTestRunProvenance(
        reference: reference ?? run.reference,
        build: run.build,
        testRunner: testRunner ?? run.testRunner,
        testBundle: run.testBundle,
        configuration: run.configuration,
        startedAtUnixMilliseconds: startedAt ?? run.startedAtUnixMilliseconds,
        finishedAtUnixMilliseconds: finishedAt ?? run.finishedAtUnixMilliseconds,
        outcome: outcome ?? run.outcome
    )
}

private func replacingAttachments(
    _ citation: VerificationEvidenceCitation,
    with attachments: some Sequence<VerificationEvidenceAttachmentReference>
) -> VerificationEvidenceCitation {
    VerificationEvidenceCitation(
        id: citation.id,
        row: citation.row,
        kind: citation.kind,
        basis: citation.basis,
        outcome: citation.outcome,
        collectedAtUnixMilliseconds: citation.collectedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: citation.expiresAtUnixMilliseconds,
        testRun: citation.testRun,
        attachments: Array(attachments),
        collectorAttestation: citation.collectorAttestation,
        reviews: citation.reviews
    )
}

private func replacingCollector(
    _ citation: VerificationEvidenceCitation,
    with collector: VerificationEvidenceCollectorAttestation
) -> VerificationEvidenceCitation {
    VerificationEvidenceCitation(
        id: citation.id,
        row: citation.row,
        kind: citation.kind,
        basis: citation.basis,
        outcome: citation.outcome,
        collectedAtUnixMilliseconds: citation.collectedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: citation.expiresAtUnixMilliseconds,
        testRun: citation.testRun,
        attachments: citation.attachments,
        collectorAttestation: collector,
        reviews: citation.reviews
    )
}

private func replacingReviews(
    _ citation: VerificationEvidenceCitation,
    with reviews: some Sequence<VerificationEvidenceReviewAttestation>
) -> VerificationEvidenceCitation {
    VerificationEvidenceCitation(
        id: citation.id,
        row: citation.row,
        kind: citation.kind,
        basis: citation.basis,
        outcome: citation.outcome,
        collectedAtUnixMilliseconds: citation.collectedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: citation.expiresAtUnixMilliseconds,
        testRun: citation.testRun,
        attachments: citation.attachments,
        collectorAttestation: citation.collectorAttestation,
        reviews: Array(reviews)
    )
}

private func corrupting(_ bytes: [UInt8]) -> [UInt8] {
    guard !bytes.isEmpty else { return [1] }
    var changed = bytes
    changed[0] ^= 0x80
    return changed
}

private func replacingAuditAttestation(
    _ attestation: VerificationEvidenceAuditAttestation,
    manifestSHA256: VerificationEvidenceDigest? = nil,
    ledgerSHA256: VerificationEvidenceDigest? = nil,
    trustPolicySHA256: VerificationEvidenceDigest? = nil,
    reportSHA256: VerificationEvidenceDigest? = nil,
    archiveSHA256: VerificationEvidenceDigest? = nil
) -> VerificationEvidenceAuditAttestation {
    VerificationEvidenceAuditAttestation(
        auditorID: attestation.auditorID,
        submitterID: attestation.submitterID,
        auditedAtUnixMilliseconds: attestation.auditedAtUnixMilliseconds,
        trustedVerificationTimeUnixMilliseconds: attestation.trustedVerificationTimeUnixMilliseconds,
        manifestSHA256: manifestSHA256 ?? attestation.manifestSHA256,
        ledgerSHA256: ledgerSHA256 ?? attestation.ledgerSHA256,
        trustPolicySHA256: trustPolicySHA256 ?? attestation.trustPolicySHA256,
        reportSHA256: reportSHA256 ?? attestation.reportSHA256,
        archiveSHA256: archiveSHA256 ?? attestation.archiveSHA256,
        signature: []
    )
}

private func signedAuditAttestation(
    _ attestation: VerificationEvidenceAuditAttestation,
    key: Curve25519.Signing.PrivateKey
) throws -> VerificationEvidenceAuditAttestation {
    let signature = try key.signature(for: independentAuditSigningData(attestation))
    return VerificationEvidenceAuditAttestation(
        auditorID: attestation.auditorID,
        submitterID: attestation.submitterID,
        auditedAtUnixMilliseconds: attestation.auditedAtUnixMilliseconds,
        trustedVerificationTimeUnixMilliseconds: attestation.trustedVerificationTimeUnixMilliseconds,
        manifestSHA256: attestation.manifestSHA256,
        ledgerSHA256: attestation.ledgerSHA256,
        trustPolicySHA256: attestation.trustPolicySHA256,
        reportSHA256: attestation.reportSHA256,
        archiveSHA256: attestation.archiveSHA256,
        signature: Array(signature)
    )
}

private func independentEvidenceClaimSHA256(
    for citation: VerificationEvidenceCitation
) -> VerificationEvidenceDigest {
    rawSHA256(independentCollectorClaimData(for: citation))
}

private func independentCollectorSigningData(
    for citation: VerificationEvidenceCitation
) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.collector-signature.v2")
    writer.appendUInt16(2)
    writer.appendDigest(independentEvidenceClaimSHA256(for: citation))
    return writer.data
}

private func independentReviewerSigningData(
    for citation: VerificationEvidenceCitation,
    review: VerificationEvidenceReviewAttestation
) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.reviewer-claim.v2")
    writer.appendUInt16(2)
    writer.appendString(citation.id.rawValue)
    writer.appendString(review.reviewerID.rawValue)
    writer.appendString(review.verdict.rawValue)
    writer.appendUInt64(review.reviewedAtUnixMilliseconds)
    writer.appendOptionalUInt64(review.expiresAtUnixMilliseconds)
    writer.appendDigest(review.evidenceClaimSHA256)
    return writer.data
}

private func independentAuditSigningData(
    _ envelope: VerificationEvidenceAuditSigningEnvelope
) -> Data {
    independentAuditSigningData(
        auditorID: envelope.auditorID,
        submitterID: envelope.submitterID,
        auditedAtUnixMilliseconds: envelope.auditedAtUnixMilliseconds,
        trustedVerificationTimeUnixMilliseconds: envelope.trustedVerificationTimeUnixMilliseconds,
        manifestSHA256: envelope.manifestSHA256,
        ledgerSHA256: envelope.ledgerSHA256,
        trustPolicySHA256: envelope.trustPolicySHA256,
        reportSHA256: envelope.reportSHA256,
        archiveSHA256: envelope.archiveSHA256
    )
}

private func independentAuditSigningData(
    _ attestation: VerificationEvidenceAuditAttestation
) -> Data {
    independentAuditSigningData(
        auditorID: attestation.auditorID,
        submitterID: attestation.submitterID,
        auditedAtUnixMilliseconds: attestation.auditedAtUnixMilliseconds,
        trustedVerificationTimeUnixMilliseconds: attestation.trustedVerificationTimeUnixMilliseconds,
        manifestSHA256: attestation.manifestSHA256,
        ledgerSHA256: attestation.ledgerSHA256,
        trustPolicySHA256: attestation.trustPolicySHA256,
        reportSHA256: attestation.reportSHA256,
        archiveSHA256: attestation.archiveSHA256
    )
}

private func independentAuditSigningData(
    auditorID: VerificationEvidencePrincipalID,
    submitterID: VerificationEvidencePrincipalID,
    auditedAtUnixMilliseconds: UInt64,
    trustedVerificationTimeUnixMilliseconds: UInt64,
    manifestSHA256: VerificationEvidenceDigest,
    ledgerSHA256: VerificationEvidenceDigest,
    trustPolicySHA256: VerificationEvidenceDigest,
    reportSHA256: VerificationEvidenceDigest,
    archiveSHA256: VerificationEvidenceDigest
) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.audit-claim.v2")
    writer.appendUInt16(2)
    writer.appendString(auditorID.rawValue)
    writer.appendString(submitterID.rawValue)
    writer.appendUInt64(auditedAtUnixMilliseconds)
    writer.appendUInt64(trustedVerificationTimeUnixMilliseconds)
    writer.appendDigest(manifestSHA256)
    writer.appendDigest(ledgerSHA256)
    writer.appendDigest(trustPolicySHA256)
    writer.appendDigest(reportSHA256)
    writer.appendDigest(archiveSHA256)
    return writer.data
}

private func independentCollectorClaimData(
    for citation: VerificationEvidenceCitation
) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.collector-claim.v2")
    writer.appendUInt16(2)
    appendIndependentCitationClaim(citation, to: &writer)
    return writer.data
}

private func appendIndependentCitationClaim(
    _ citation: VerificationEvidenceCitation,
    to writer: inout IndependentWriter
) {
    writer.appendString(citation.id.rawValue)
    writer.appendReference(citation.row)
    writer.appendString(citation.kind.rawValue)
    writer.appendString(citation.basis.rawValue)
    writer.appendString(citation.outcome.rawValue)
    writer.appendUInt64(citation.collectedAtUnixMilliseconds)
    writer.appendOptionalUInt64(citation.expiresAtUnixMilliseconds)
    appendIndependentTestRun(citation.testRun, to: &writer)
    let attachmentRecords = citation.attachments.map(independentAttachmentRecord).sorted(by: dataPrecedes)
    writer.appendCount(attachmentRecords.count)
    for record in attachmentRecords { writer.appendData(record) }
    writer.appendString(citation.collectorAttestation.collectorID.rawValue)
    writer.appendUInt64(citation.collectorAttestation.attestedAtUnixMilliseconds)
}

private func independentArchiveSections(
    fixture: LedgerFixture,
    report: VerificationEvidenceAuditReport
) -> [Data] {
    [
        independentManifestSection(fixture.manifest),
        independentLedgerSection(fixture.ledger),
        independentTrustPolicySection(fixture.trustPolicy),
        independentReportSection(report)
    ]
}

private func archiveSections(_ archive: Data) -> [Data] {
    do {
        var reader = ArchiveReader(archive)
        _ = try reader.readData(count: 8)
        _ = try reader.readString()
        _ = try reader.readUInt16()
        for _ in 0..<4 { _ = try reader.readDigest() }
        let sections = try (0..<4).map { _ in try reader.readLengthPrefixedData() }
        XCTAssertTrue(reader.isAtEnd)
        return sections
    } catch {
        XCTFail("Invalid archive: \(error)")
        return []
    }
}

private func independentManifestSection(_ manifest: VerificationRoadmapManifest) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.manifest.v2")
    writer.appendUInt16(2)
    writer.appendReference(manifest.reference)
    let records = manifest.rows.map(independentRowRecord).sorted(by: digestThenDataPrecedes)
    writer.appendCount(records.count)
    for record in records { writer.appendData(record) }
    return writer.data
}

private func independentLedgerSection(_ ledger: VerificationEvidenceLedger) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.ledger.v2")
    writer.appendUInt16(2)
    writer.appendReference(ledger.reference)
    writer.appendReference(ledger.manifest)
    appendIndependentBuild(ledger.targetBuild, to: &writer)
    let records = ledger.citations.map(independentCitationRecord).sorted(by: digestThenDataPrecedes)
    writer.appendCount(records.count)
    for record in records { writer.appendData(record) }
    return writer.data
}

private func independentTrustPolicySection(_ policy: VerificationEvidenceTrustPolicy) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.trust-policy.v2")
    writer.appendUInt16(2)
    for kind in VerificationEvidenceKind.allCases {
        writer.appendString(kind.rawValue)
        writer.appendUInt64(policy.freshness.maximumAgeMilliseconds(for: kind))
    }
    writer.appendUInt64(policy.freshness.maximumCollectionLagMilliseconds)
    let records = policy.roots.map(independentTrustRootRecord).sorted(by: digestThenDataPrecedes)
    writer.appendCount(records.count)
    for record in records { writer.appendData(record) }
    return writer.data
}

private func independentReportSection(_ report: VerificationEvidenceAuditReport) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.report.v2")
    writer.appendUInt16(UInt16(report.schemaVersion))
    writer.appendReference(report.manifest)
    writer.appendReference(report.ledger)
    writer.appendUInt64(report.auditedAtUnixMilliseconds)
    writer.appendCount(report.rows.count)
    for row in report.rows {
        writer.appendString(row.id.rawValue)
        writer.appendUInt64(row.rowRevision.rawValue)
        writer.appendBool(row.completionClaimed)
        writer.appendString(row.status.rawValue)
        writer.appendCount(row.cells.count)
        for cell in row.cells {
            writer.appendString(cell.kind.rawValue)
            writer.appendCount(cell.evidenceCount)
            writer.appendString(cell.status.rawValue)
            writer.appendCount(cell.citationIDs.count)
            for id in cell.citationIDs { writer.appendString(id.rawValue) }
        }
    }
    writer.appendCount(report.findings.count)
    for finding in report.findings {
        writer.appendString(finding.id.rawValue)
        writer.appendString(finding.severity.rawValue)
        writer.appendString(finding.code.rawValue)
        let components = findingSubjectComponents(finding.subject)
        writer.appendString(components[0])
        writer.appendCount(components.count - 1)
        for component in components.dropFirst() { writer.appendString(component) }
    }
    return writer.data
}

private func independentReportEvaluationSection(_ report: VerificationEvidenceAuditReport) -> Data {
    var writer = IndependentWriter()
    writer.appendString("org.macmerge.verification-evidence-ledger.report-evaluation.v2")
    writer.appendUInt16(UInt16(report.schemaVersion))
    writer.appendReference(report.manifest)
    writer.appendReference(report.ledger)
    appendIndependentReportBody(report, to: &writer)
    return writer.data
}

private func appendIndependentReportBody(
    _ report: VerificationEvidenceAuditReport,
    to writer: inout IndependentWriter
) {
    writer.appendCount(report.rows.count)
    for row in report.rows {
        writer.appendString(row.id.rawValue)
        writer.appendUInt64(row.rowRevision.rawValue)
        writer.appendBool(row.completionClaimed)
        writer.appendString(row.status.rawValue)
        writer.appendCount(row.cells.count)
        for cell in row.cells {
            writer.appendString(cell.kind.rawValue)
            writer.appendCount(cell.evidenceCount)
            writer.appendString(cell.status.rawValue)
            writer.appendCount(cell.citationIDs.count)
            for id in cell.citationIDs { writer.appendString(id.rawValue) }
        }
    }
    writer.appendCount(report.findings.count)
    for finding in report.findings {
        writer.appendString(finding.id.rawValue)
        writer.appendString(finding.severity.rawValue)
        writer.appendString(finding.code.rawValue)
        let components = findingSubjectComponents(finding.subject)
        writer.appendString(components[0])
        writer.appendCount(components.count - 1)
        for component in components.dropFirst() { writer.appendString(component) }
    }
}

private func independentRowRecord(_ row: VerificationRoadmapRowRequirement) -> Data {
    var writer = IndependentWriter()
    writer.appendReference(row.reference)
    switch row.applicability {
    case .notApplicable:
        writer.appendUInt8(0)
    case .applicable(let statefulness):
        writer.appendUInt8(1)
        writer.appendString(statefulness.rawValue)
    }
    writer.appendBool(row.completionClaimed)
    let kinds = VerificationEvidenceKind.allCases.filter(row.requiredEvidenceKinds.contains)
    writer.appendCount(kinds.count)
    for kind in kinds { writer.appendString(kind.rawValue) }
    return writer.data
}

private func independentCitationRecord(_ citation: VerificationEvidenceCitation) -> Data {
    var writer = IndependentWriter()
    appendIndependentCitationClaim(citation, to: &writer)
    writer.appendBytes(citation.collectorAttestation.signature)
    let reviews = citation.reviews.map(independentReviewRecord).sorted(by: dataPrecedes)
    writer.appendCount(reviews.count)
    for review in reviews { writer.appendData(review) }
    return writer.data
}

private func independentTrustRootRecord(_ root: VerificationEvidenceTrustRoot) -> Data {
    var writer = IndependentWriter()
    writer.appendString(root.principalID.rawValue)
    let roles = VerificationEvidenceTrustRole.allCases.filter(root.roles.contains)
    writer.appendCount(roles.count)
    for role in roles { writer.appendString(role.rawValue) }
    writer.appendBytes(root.ed25519PublicKey)
    writer.appendUInt64(root.validFromUnixMilliseconds)
    writer.appendUInt64(root.validThroughUnixMilliseconds)
    writer.appendOptionalUInt64(root.revokedAtUnixMilliseconds)
    return writer.data
}

private func independentAttachmentRecord(_ attachment: VerificationEvidenceAttachmentReference) -> Data {
    var writer = IndependentWriter()
    writer.appendString(attachment.kind.rawValue)
    appendIndependentArtifact(attachment.artifact, to: &writer)
    return writer.data
}

private func independentReviewRecord(_ review: VerificationEvidenceReviewAttestation) -> Data {
    var writer = IndependentWriter()
    writer.appendString(review.reviewerID.rawValue)
    writer.appendString(review.verdict.rawValue)
    writer.appendUInt64(review.reviewedAtUnixMilliseconds)
    writer.appendOptionalUInt64(review.expiresAtUnixMilliseconds)
    writer.appendDigest(review.evidenceClaimSHA256)
    writer.appendBytes(review.signature)
    return writer.data
}

private func appendIndependentTestRun(
    _ run: VerificationEvidenceTestRunProvenance,
    to writer: inout IndependentWriter
) {
    writer.appendReference(run.reference)
    appendIndependentBuild(run.build, to: &writer)
    appendIndependentArtifact(run.testRunner, to: &writer)
    appendIndependentArtifact(run.testBundle, to: &writer)
    appendIndependentArtifact(run.configuration, to: &writer)
    writer.appendUInt64(run.startedAtUnixMilliseconds)
    writer.appendUInt64(run.finishedAtUnixMilliseconds)
    writer.appendString(run.outcome.rawValue)
}

private func appendIndependentBuild(
    _ build: VerificationEvidenceAppBuildProvenance,
    to writer: inout IndependentWriter
) {
    writer.appendReference(build.application)
    writer.appendReference(build.build)
    appendIndependentArtifact(build.applicationBundle, to: &writer)
    appendIndependentArtifact(build.executable, to: &writer)
    appendIndependentArtifact(build.signingIdentity, to: &writer)
}

private func appendIndependentArtifact(
    _ artifact: VerificationEvidenceArtifactReference,
    to writer: inout IndependentWriter
) {
    writer.appendString(artifact.id.rawValue)
    writer.appendString(artifact.role.rawValue)
    writer.appendString(artifact.mediaType)
    writer.appendUInt64(artifact.byteCount)
    writer.appendDigest(artifact.digest)
}

private func independentFindingID(
    code: VerificationEvidenceFindingCode,
    subject: VerificationEvidenceFindingSubject,
    discriminator: String
) -> VerificationEvidenceFinding.ID {
    var hasher = SHA256()
    for component in [code.rawValue] + findingSubjectComponents(subject) + [discriminator] {
        hasher.update(data: Data("\(component.utf8.count):\(component)".utf8))
    }
    return VerificationEvidenceFinding.ID(
        rawValue: hasher.finalize().map { String(format: "%02x", $0) }.joined()
    )
}

private func findingSubjectComponents(_ subject: VerificationEvidenceFindingSubject) -> [String] {
    switch subject {
    case .manifest: ["manifest"]
    case .ledger: ["ledger"]
    case .trustPolicy: ["trust-policy"]
    case .row(let id): ["row", id.rawValue]
    case .requirement(let rowID, let kind): ["requirement", rowID.rawValue, kind.rawValue]
    case .citation(let id): ["citation", id.rawValue]
    case .attachment(let id): ["attachment", id.rawValue]
    case .principal(let id): ["principal", id.rawValue]
    }
}

private func digestThenDataPrecedes(_ left: Data, _ right: Data) -> Bool {
    let leftDigest = Data(SHA256.hash(data: left))
    let rightDigest = Data(SHA256.hash(data: right))
    return leftDigest == rightDigest ? dataPrecedes(left, right) : dataPrecedes(leftDigest, rightDigest)
}

private func dataPrecedes(_ left: Data, _ right: Data) -> Bool {
    left.lexicographicallyPrecedes(right)
}

private func rawSHA256(_ data: Data) -> VerificationEvidenceDigest {
    VerificationEvidenceDigest(bytes: Array(SHA256.hash(data: data)))
}

private func framedSHA256(
    domain: String,
    data: Data,
    chunkSize: Int
) -> VerificationEvidenceDigest {
    var hasher = SHA256()
    let domainData = Data(domain.utf8)
    hasher.update(data: littleEndianUInt32(UInt32(domainData.count)))
    hasher.update(data: domainData)
    hasher.update(data: littleEndianUInt32(UInt32(data.count)))
    var offset = 0
    while offset < data.count {
        let end = min(offset + chunkSize, data.count)
        hasher.update(data: data[offset..<end])
        offset = end
    }
    return VerificationEvidenceDigest(bytes: Array(hasher.finalize()))
}

private func littleEndianUInt32(_ value: UInt32) -> Data {
    Data((0..<4).map { UInt8((value >> UInt32($0 * 8)) & 0xFF) })
}

private func mirrorText(_ value: Any) -> String {
    Mirror(reflecting: value).children.map {
        "\($0.label ?? "_")=\(String(describing: $0.value))"
    }.joined(separator: ",")
}

private func assertLedgerError(
    _ expected: VerificationEvidenceLedgerError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> Void
) {
    XCTAssertThrowsError(try operation(), file: file, line: line) { error in
        XCTAssertEqual(error as? VerificationEvidenceLedgerError, expected, file: file, line: line)
    }
}

private func minimumSuccessfulWorkUnits(for fixture: LedgerFixture) throws -> UInt64 {
    var lower: UInt64 = 1
    var upper: UInt64 = VerificationEvidenceLedgerLimits.default.maximumWorkUnits
    while lower < upper {
        let midpoint = lower + (upper - lower) / 2
        do {
            _ = try auditEnvelope(fixture, limits: limits(maximumWorkUnits: midpoint))
            upper = midpoint
        } catch VerificationEvidenceLedgerError.workLimitExceeded {
            lower = midpoint + 1
        }
    }
    return lower
}

private func minimumSuccessfulArchiveBytes(
    for fixture: LedgerFixture,
    startingAt minimum: Int
) throws -> Int {
    func succeeds(at maximum: Int) throws -> Bool {
        let candidateLimits = limits(
            maximumCanonicalRecordBytes: maximum,
            maximumArchiveBytes: maximum
        )
        do {
            let signed = try signedAudit(fixture, limits: candidateLimits)
            try signed.result.receipt.validateCurrent(
                manifest: fixture.manifest,
                ledger: fixture.ledger,
                trustPolicy: fixture.trustPolicy,
                trustedVerificationTimeUnixMilliseconds: fixture.trustedTime,
                limits: candidateLimits
            )
            return true
        } catch VerificationEvidenceLedgerError.archiveTooLarge {
            return false
        }
    }

    var lower = minimum
    var upper = minimum
    while try !succeeds(at: upper) {
        guard upper < VerificationEvidenceLedgerLimits.hardMaximumCanonicalRecordBytes else {
            throw VerificationEvidenceLedgerError.archiveTooLarge(maximumBytes: upper)
        }
        upper = min(upper * 2, VerificationEvidenceLedgerLimits.hardMaximumCanonicalRecordBytes)
    }
    while lower < upper {
        let midpoint = lower + (upper - lower) / 2
        if try succeeds(at: midpoint) {
            upper = midpoint
        } else {
            lower = midpoint + 1
        }
    }
    return lower
}

private func captureLedgerError(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> Void
) -> VerificationEvidenceLedgerError {
    do {
        try operation()
        XCTFail("Expected VerificationEvidenceLedgerError", file: file, line: line)
        return .cancelled
    } catch let error as VerificationEvidenceLedgerError {
        return error
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
        return .cancelled
    }
}

private func limits(
    maximumRows: Int = 100_000,
    maximumCitations: Int = 500_000,
    maximumAttachments: Int = 1_000_000,
    maximumAttachmentsPerCitation: Int = 32,
    maximumReviews: Int = 1_000_000,
    maximumReviewsPerCitation: Int = 8,
    maximumTrustRoots: Int = 10_000,
    maximumStringUTF8Bytes: Int = 64 * 1_024,
    maximumTotalStringUTF8Bytes: Int = 32 * 1_024 * 1_024,
    maximumBinaryFieldBytes: Int = 1_024,
    maximumSigningPayloadBytes: Int = 4 * 1_024 * 1_024,
    maximumCanonicalRecordBytes: Int = 16 * 1_024 * 1_024,
    maximumTotalItems: Int = 4_000_000,
    maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
    maximumFindings: Int = 500_000,
    maximumArchiveBytes: Int = 256 * 1_024 * 1_024,
    cancellationCheckInterval: Int = 256
) -> VerificationEvidenceLedgerLimits {
    VerificationEvidenceLedgerLimits(
        maximumRows: maximumRows,
        maximumCitations: maximumCitations,
        maximumAttachments: maximumAttachments,
        maximumAttachmentsPerCitation: maximumAttachmentsPerCitation,
        maximumReviews: maximumReviews,
        maximumReviewsPerCitation: maximumReviewsPerCitation,
        maximumTrustRoots: maximumTrustRoots,
        maximumStringUTF8Bytes: maximumStringUTF8Bytes,
        maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
        maximumBinaryFieldBytes: maximumBinaryFieldBytes,
        maximumSigningPayloadBytes: maximumSigningPayloadBytes,
        maximumCanonicalRecordBytes: maximumCanonicalRecordBytes,
        maximumTotalItems: maximumTotalItems,
        maximumWorkUnits: maximumWorkUnits,
        maximumFindings: maximumFindings,
        maximumArchiveBytes: maximumArchiveBytes,
        cancellationCheckInterval: cancellationCheckInterval
    )
}

private func manifestReference(_ value: String) -> VerificationRoadmapManifestReference {
    VerificationRoadmapManifestReference(id: VerificationRoadmapManifestID(rawValue: value), revision: revision())
}

private func rowReference(_ value: String) -> VerificationRoadmapRowReference {
    VerificationRoadmapRowReference(id: VerificationRoadmapRowID(rawValue: value), revision: revision())
}

private func ledgerReference(_ value: String) -> VerificationEvidenceLedgerReference {
    VerificationEvidenceLedgerReference(id: VerificationEvidenceLedgerID(rawValue: value), revision: revision())
}

private func applicationReference(_ value: String) -> VerificationEvidenceApplicationReference {
    VerificationEvidenceApplicationReference(id: VerificationEvidenceApplicationID(rawValue: value), revision: revision())
}

private func buildReference(_ value: String) -> VerificationEvidenceBuildReference {
    VerificationEvidenceBuildReference(id: VerificationEvidenceBuildID(rawValue: value), revision: revision())
}

private func testRunReference(_ value: String) -> VerificationEvidenceTestRunReference {
    VerificationEvidenceTestRunReference(id: VerificationEvidenceTestRunID(rawValue: value), revision: revision())
}

private func citationID(_ value: String) -> VerificationEvidenceCitationID {
    VerificationEvidenceCitationID(rawValue: value)
}

private func artifactID(_ value: String) -> VerificationEvidenceArtifactID {
    VerificationEvidenceArtifactID(rawValue: value)
}

private func principalID(_ value: String) -> VerificationEvidencePrincipalID {
    VerificationEvidencePrincipalID(rawValue: value)
}

private func revision() -> VerificationEvidenceRevision {
    VerificationEvidenceRevision(rawValue: 1)
}
