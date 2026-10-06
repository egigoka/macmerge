import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ConflictComparisonWorkflowTests: XCTestCase {
    func testRoleMappingsAreExactForParserMarkersAndThreeWaySources() {
        XCTAssertEqual(ConflictComparisonRole.allCases, [.base, .theirs, .mine])
        XCTAssertEqual(ConflictComparisonTopology.allCases, [.twoWay, .diff3])

        let twoWay = ConflictComparisonRoleMapping.twoWay
        XCTAssertEqual(twoWay.topology, .twoWay)
        XCTAssertEqual(twoWay.orderedRoles, [.theirs, .mine])
        XCTAssertEqual(twoWay.twoWayLeftRole, .theirs)
        XCTAssertEqual(twoWay.twoWayRightRole, .mine)
        XCTAssertNil(twoWay.threeWayBaseRole)
        XCTAssertNil(twoWay.threeWayLeftRole)
        XCTAssertNil(twoWay.threeWayRightRole)
        XCTAssertEqual(twoWay.role(for: .current), .mine)
        XCTAssertNil(twoWay.role(for: ConflictMarkerKind.base))
        XCTAssertNil(twoWay.role(for: .separator))
        XCTAssertEqual(twoWay.role(for: .incoming), .theirs)
        for source in ThreeWayTextMergeSource.allCases {
            XCTAssertNil(twoWay.role(for: source))
        }

        let diff3 = ConflictComparisonRoleMapping.diff3
        XCTAssertEqual(diff3.topology, .diff3)
        XCTAssertEqual(diff3.orderedRoles, [.base, .theirs, .mine])
        XCTAssertEqual(diff3.threeWayBaseRole, .base)
        XCTAssertEqual(diff3.threeWayLeftRole, .theirs)
        XCTAssertEqual(diff3.threeWayRightRole, .mine)
        XCTAssertEqual(diff3.role(for: .current), .mine)
        XCTAssertEqual(diff3.role(for: ConflictMarkerKind.base), .base)
        XCTAssertNil(diff3.role(for: .separator))
        XCTAssertEqual(diff3.role(for: .incoming), .theirs)
        XCTAssertEqual(diff3.role(for: ThreeWayTextMergeSource.base), .base)
        XCTAssertEqual(diff3.role(for: .left), .theirs)
        XCTAssertEqual(diff3.role(for: .right), .mine)
    }

    func testResolutionChoicesMapExactlyToRolesAndThreeWayChoices() {
        XCTAssertEqual(ConflictComparisonResolutionChoice.allCases, [.base, .theirs, .mine])
        XCTAssertEqual(ConflictComparisonResolutionChoice.base.role, .base)
        XCTAssertEqual(ConflictComparisonResolutionChoice.theirs.role, .theirs)
        XCTAssertEqual(ConflictComparisonResolutionChoice.mine.role, .mine)
        XCTAssertEqual(ConflictComparisonResolutionChoice.base.threeWayMergeChoice, .base)
        XCTAssertEqual(ConflictComparisonResolutionChoice.theirs.threeWayMergeChoice, .left)
        XCTAssertEqual(ConflictComparisonResolutionChoice.mine.threeWayMergeChoice, .right)
        XCTAssertEqual(ConflictComparisonResolutionAction.allCases, [.choose, .apply])
    }

    func testTwoWayPlanBindsParserProjectionToExactRevisionsAndReceipts() throws {
        let snapshot = try makeSnapshot(source: Self.twoWaySource)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))

        XCTAssertEqual(plan.snapshotCAS.reference, ConflictComparisonSnapshotReference(snapshot))
        XCTAssertEqual(plan.snapshotCAS.stateSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(plan.documentSourceRevision, snapshot.documentSourceRevision)
        XCTAssertFalse(plan.isReadOnly)
        XCTAssertEqual(plan.capabilities, .all)
        XCTAssertEqual(plan.mapping, .twoWay)
        XCTAssertEqual(plan.roleReferences.map(\.role), [.theirs, .mine])
        XCTAssertEqual(plan.roleReference(for: .theirs)?.sourceRevision, snapshot.roleSnapshots[0].sourceRevision)
        XCTAssertEqual(plan.roleReference(for: .mine)?.sourceRevision, snapshot.roleSnapshots[1].sourceRevision)
        XCTAssertNil(plan.roleReference(for: .base))
        XCTAssertEqual(plan.navigation.generation, snapshot.generation)
        XCTAssertEqual(plan.navigation.sourceLineRanges, [2...6, 8...12])

        guard case .twoWay(let result) = plan.comparison else {
            return XCTFail("Expected two-way comparison")
        }
        XCTAssertEqual(result.leftRole, .theirs)
        XCTAssertEqual(result.rightRole, .mine)
        XCTAssertEqual(result.rows.count, plan.comparison.comparisonItemCount)
        XCTAssertTrue(result.rows.contains { $0.kind != .unchanged })

        XCTAssertEqual(plan.receipt.snapshot, ConflictComparisonSnapshotReference(snapshot))
        XCTAssertEqual(plan.receipt.topology, .twoWay)
        XCTAssertEqual(plan.receipt.conflictCount, 2)
        XCTAssertEqual(plan.receipt.comparisonItemCount, result.rows.count)
        XCTAssertEqual(plan.receipt.documentUTF8ByteCount, Self.twoWaySource.utf8.count)
        XCTAssertEqual(
            plan.receipt.roleUTF8ByteCount,
            snapshot.parseResult.currentText.utf8.count + snapshot.parseResult.incomingText.utf8.count
        )
        XCTAssertGreaterThan(plan.receipt.retainedByteEstimate, 0)
        XCTAssertGreaterThan(plan.receipt.estimatedWorkUnits, 0)
        XCTAssertEqual(plan.receipt.planSHA256.count, SHA256.Digest.byteCount)
        XCTAssertEqual(plan.executorContract, .required)
        XCTAssertEqual(plan.limits, .default)
    }

    func testDiff3PlanBindsBaseTheirsMineToBaseLeftRight() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))

        XCTAssertEqual(plan.mapping, .diff3)
        XCTAssertEqual(plan.roleReferences.map(\.role), [.base, .theirs, .mine])
        XCTAssertEqual(plan.roleReference(for: .base)?.sourceRevision, snapshot.roleSnapshots[0].sourceRevision)
        XCTAssertEqual(plan.roleReference(for: .theirs)?.sourceRevision, snapshot.roleSnapshots[1].sourceRevision)
        XCTAssertEqual(plan.roleReference(for: .mine)?.sourceRevision, snapshot.roleSnapshots[2].sourceRevision)

        guard case .diff3(let result) = plan.comparison else {
            return XCTFail("Expected diff3 comparison")
        }
        XCTAssertEqual(result.baseRole, .base)
        XCTAssertEqual(result.leftRole, .theirs)
        XCTAssertEqual(result.rightRole, .mine)
        XCTAssertEqual(result.merge.base.text, snapshot.parseResult.baseText)
        XCTAssertEqual(result.merge.left.text, snapshot.parseResult.incomingText)
        XCTAssertEqual(result.merge.right.text, snapshot.parseResult.currentText)
        XCTAssertEqual(result.merge.base.source, .base)
        XCTAssertEqual(result.merge.left.source, .left)
        XCTAssertEqual(result.merge.right.source, .right)
        XCTAssertEqual(result.merge.regions.count, plan.comparison.comparisonItemCount)
        XCTAssertEqual(plan.receipt.topology, .diff3)
        XCTAssertEqual(plan.receipt.conflictCount, 2)
    }

    func testPlansAndReceiptsAreDeterministicForIdenticalPublicInputs() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let request = ConflictComparisonRequest(snapshot: snapshot)

        let first = try ConflictComparisonWorkflow.prepare(request)
        let second = try ConflictComparisonWorkflow.prepare(request)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.snapshotCAS, second.snapshotCAS)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.planSHA256, second.receipt.planSHA256)

        let target = try XCTUnwrap(first.navigation.first)
        let state = ConflictComparisonSelectionState(
            snapshot: first.snapshotCAS.reference,
            selectedConflictID: target.id,
            cursorSourceLine: target.firstSourceLine
        )
        let navigationRequest = ConflictComparisonNavigationRequest(state: state, intent: .command(.current))
        XCTAssertEqual(
            try first.navigationPlan(navigationRequest),
            try second.navigationPlan(navigationRequest)
        )

        let intent = ConflictComparisonResolutionIntent(
            snapshot: first.snapshotCAS.reference,
            targetID: target.id,
            choice: .theirs,
            action: .choose
        )
        XCTAssertEqual(try first.resolutionPlan(intent), try second.resolutionPlan(intent))
    }

    func testCanonicalSnapshotPlanNavigationAndResolutionDigestsMatchGoldenVectors() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let state = ConflictComparisonSelectionState(snapshot: plan.snapshotCAS.reference)
        let navigation = try navigation(plan, state: state, intent: .command(.first))
        let resolution = try plan.resolutionPlan(
            .init(
                snapshot: plan.snapshotCAS.reference,
                targetID: target.id,
                choice: .mine,
                action: .choose
            )
        )

        XCTAssertEqual(
            hex(plan.snapshotCAS.stateSHA256),
            "575b43d78e5056c5cadaa96373a13498576cc656efd40820dcbc04fe87352ac3"
        )
        XCTAssertEqual(
            hex(plan.receipt.planSHA256),
            "c430d221f41bcaa935ae166c7b556f32194db5b1f2b7b909de0363b335901b35"
        )
        XCTAssertEqual(
            hex(navigation.receipt.receiptSHA256),
            "7f5b1fdd9ba1eae55f19a4d9573a9329af705dc4a6867908d3b91ab8d6e98ecf"
        )
        XCTAssertEqual(
            hex(resolution.receipt.planSHA256),
            "f1e9b5d88d2e5206e9a813d2a7f956d79e6d45b2cb23450aa00a3763a87653a3"
        )
    }

    func testExpectedSnapshotReferenceRejectsIdentityAndGenerationIndependently() throws {
        let snapshot = try makeSnapshot()
        let actual = ConflictComparisonSnapshotReference(snapshot)
        let otherIdentity = ConflictComparisonSnapshotIdentity(rawValue: Self.otherSnapshotUUID)

        assertWorkflowError(
            .staleSnapshotIdentity(expected: otherIdentity, actual: snapshot.identity)
        ) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot),
                expecting: .init(identity: otherIdentity, generation: actual.generation)
            )
        }
        assertWorkflowError(.staleGeneration(expected: actual.generation + 1, actual: actual.generation)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot),
                expecting: .init(identity: actual.identity, generation: actual.generation + 1)
            )
        }
    }

    func testParserResultMustBindToExactCurrentDocumentRevision() throws {
        let snapshot = try makeSnapshot()
        let changedRevision = revision(
            text: Self.twoWaySource,
            identity: snapshot.documentSourceRevision.identity,
            revision: snapshot.documentSourceRevision.revision + 1
        )
        let mismatched = rebuilding(snapshot, parseResultSourceRevision: changedRevision)

        assertWorkflowError(.parseResultSourceRevisionMismatch) {
            try ConflictComparisonWorkflow.prepare(.init(snapshot: mismatched))
        }
    }

    func testParserRevisionIdentityByteCountAndDigestMustEachMatchDocumentExactly() throws {
        let snapshot = try makeSnapshot()
        let document = snapshot.documentSourceRevision
        var changedDigest = document.contentSHA256
        changedDigest[0] ^= 0xFF
        let mismatches = [
            ConflictComparisonSourceRevision(
                identity: .init(namespace: Self.namespaceUUID, value: "other-document"),
                revision: document.revision,
                utf8ByteCount: document.utf8ByteCount,
                contentSHA256: document.contentSHA256
            ),
            ConflictComparisonSourceRevision(
                identity: document.identity,
                revision: document.revision,
                utf8ByteCount: document.utf8ByteCount + 1,
                contentSHA256: document.contentSHA256
            ),
            ConflictComparisonSourceRevision(
                identity: document.identity,
                revision: document.revision,
                utf8ByteCount: document.utf8ByteCount,
                contentSHA256: changedDigest
            )
        ]

        for mismatch in mismatches {
            assertWorkflowError(.parseResultSourceRevisionMismatch) {
                try ConflictComparisonWorkflow.prepare(
                    .init(snapshot: rebuilding(snapshot, parseResultSourceRevision: mismatch))
                )
            }
        }
    }

    func testRoleTextMustMatchParserCurrentIncomingAndBaseExactly() throws {
        let twoWay = try makeSnapshot()
        var twoWayRoles = twoWay.roleSnapshots
        twoWayRoles[0] = roleSnapshot(.theirs, text: twoWayRoles[0].text + "changed\n")
        assertWorkflowError(.parsedRoleTextMismatch(.theirs)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(twoWay, roleSnapshots: twoWayRoles))
            )
        }

        twoWayRoles = twoWay.roleSnapshots
        twoWayRoles[1] = roleSnapshot(.mine, text: twoWayRoles[1].text + "changed\n")
        assertWorkflowError(.parsedRoleTextMismatch(.mine)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(twoWay, roleSnapshots: twoWayRoles))
            )
        }

        let diff3 = try makeSnapshot(source: Self.diff3Source)
        var diff3Roles = diff3.roleSnapshots
        diff3Roles[0] = roleSnapshot(.base, text: diff3Roles[0].text + "changed\n")
        assertWorkflowError(.parsedRoleTextMismatch(.base)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(diff3, roleSnapshots: diff3Roles))
            )
        }
    }

    func testRoleRevisionByteCountAndDigestAreValidatedIndependently() throws {
        let snapshot = try makeSnapshot()
        let original = snapshot.roleSnapshots[0]
        let wrongCount = ConflictComparisonSourceRevision(
            identity: original.sourceRevision.identity,
            revision: original.sourceRevision.revision,
            utf8ByteCount: original.sourceRevision.utf8ByteCount + 1,
            contentSHA256: original.sourceRevision.contentSHA256
        )
        var roles = snapshot.roleSnapshots
        roles[0] = .init(role: original.role, sourceRevision: wrongCount, text: original.text)
        assertWorkflowError(
            .roleRevisionByteCountMismatch(
                role: .theirs,
                expected: wrongCount.utf8ByteCount,
                actual: original.text.utf8.count
            )
        ) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, roleSnapshots: roles))
            )
        }

        let wrongDigest = ConflictComparisonSourceRevision(
            identity: original.sourceRevision.identity,
            revision: original.sourceRevision.revision,
            utf8ByteCount: original.sourceRevision.utf8ByteCount,
            contentSHA256: Array(repeating: 0xA5, count: SHA256.Digest.byteCount)
        )
        roles[0] = .init(role: original.role, sourceRevision: wrongDigest, text: original.text)
        assertWorkflowError(.roleRevisionDigestMismatch(.theirs)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, roleSnapshots: roles))
            )
        }
    }

    func testSourceIdentityAndRevisionShapeGuardsAreIsolatedByRole() throws {
        let snapshot = try makeSnapshot()
        let document = snapshot.documentSourceRevision
        let invalidDocumentIdentity = ConflictComparisonSourceRevision(
            identity: .init(namespace: document.identity.namespace, value: ""),
            revision: document.revision,
            utf8ByteCount: document.utf8ByteCount,
            contentSHA256: document.contentSHA256
        )
        assertWorkflowError(.invalidSourceIdentity(nil)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: rebuilding(
                        snapshot,
                        documentSourceRevision: invalidDocumentIdentity,
                        parseResultSourceRevision: invalidDocumentIdentity
                    )
                )
            )
        }

        let invalidDocumentRevision = ConflictComparisonSourceRevision(
            identity: document.identity,
            revision: document.revision,
            utf8ByteCount: -1,
            contentSHA256: []
        )
        assertWorkflowError(.invalidSourceRevision(nil)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: rebuilding(
                        snapshot,
                        documentSourceRevision: invalidDocumentRevision,
                        parseResultSourceRevision: invalidDocumentRevision
                    )
                )
            )
        }

        let originalRole = snapshot.roleSnapshots[0]
        let invalidRoleIdentity = ConflictComparisonSourceRevision(
            identity: .init(namespace: originalRole.sourceRevision.identity.namespace, value: "bad\0id"),
            revision: originalRole.sourceRevision.revision,
            utf8ByteCount: originalRole.sourceRevision.utf8ByteCount,
            contentSHA256: originalRole.sourceRevision.contentSHA256
        )
        var roles = snapshot.roleSnapshots
        roles[0] = .init(role: .theirs, sourceRevision: invalidRoleIdentity, text: originalRole.text)
        assertWorkflowError(.invalidSourceIdentity(.theirs)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, roleSnapshots: roles))
            )
        }

        let invalidRoleRevision = ConflictComparisonSourceRevision(
            identity: originalRole.sourceRevision.identity,
            revision: originalRole.sourceRevision.revision,
            utf8ByteCount: -1,
            contentSHA256: []
        )
        roles[0] = .init(role: .theirs, sourceRevision: invalidRoleRevision, text: originalRole.text)
        assertWorkflowError(.invalidSourceRevision(.theirs)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, roleSnapshots: roles))
            )
        }
    }

    func testMalformedRoleIdentityCountAndDigestFieldsAreRejectedIndependently() throws {
        let snapshot = try makeSnapshot()
        let original = snapshot.roleSnapshots[0]
        let revision = original.sourceRevision
        let malformed: [(ConflictComparisonSourceRevision, ConflictComparisonWorkflowError)] = [
            (
                .init(
                    identity: .init(namespace: revision.identity.namespace, value: ""),
                    revision: revision.revision,
                    utf8ByteCount: revision.utf8ByteCount,
                    contentSHA256: revision.contentSHA256
                ),
                .invalidSourceIdentity(.theirs)
            ),
            (
                .init(
                    identity: .init(namespace: revision.identity.namespace, value: "bad\0identity"),
                    revision: revision.revision,
                    utf8ByteCount: revision.utf8ByteCount,
                    contentSHA256: revision.contentSHA256
                ),
                .invalidSourceIdentity(.theirs)
            ),
            (
                .init(
                    identity: revision.identity,
                    revision: revision.revision,
                    utf8ByteCount: -1,
                    contentSHA256: revision.contentSHA256
                ),
                .invalidSourceRevision(.theirs)
            ),
            (
                .init(
                    identity: revision.identity,
                    revision: revision.revision,
                    utf8ByteCount: revision.utf8ByteCount,
                    contentSHA256: Array(repeating: 0, count: SHA256.Digest.byteCount - 1)
                ),
                .invalidSourceRevision(.theirs)
            )
        ]

        for (malformedRevision, expected) in malformed {
            var roles = snapshot.roleSnapshots
            roles[0] = .init(
                role: original.role,
                sourceRevision: malformedRevision,
                text: original.text
            )
            assertWorkflowError(expected) {
                try ConflictComparisonWorkflow.prepare(
                    .init(snapshot: rebuilding(snapshot, roleSnapshots: roles))
                )
            }
        }
    }

    func testConflictingMetadataForReusedIdentityAndRevisionIsRejected() throws {
        let snapshot = try makeSnapshot()
        let original = snapshot.roleSnapshots[0]
        let conflicting = ConflictComparisonSourceRevision(
            identity: snapshot.documentSourceRevision.identity,
            revision: snapshot.documentSourceRevision.revision,
            utf8ByteCount: original.sourceRevision.utf8ByteCount,
            contentSHA256: original.sourceRevision.contentSHA256
        )
        var roles = snapshot.roleSnapshots
        roles[0] = .init(role: .theirs, sourceRevision: conflicting, text: original.text)

        assertWorkflowError(.conflictingSourceRevision) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, roleSnapshots: roles))
            )
        }
    }

    func testRoleSetRejectsDuplicateMissingAndUnexpectedRoles() throws {
        let snapshot = try makeSnapshot()
        let theirs = snapshot.roleSnapshots[0]
        let mine = snapshot.roleSnapshots[1]

        assertWorkflowError(.duplicateRole(.theirs)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, roleSnapshots: [theirs, theirs, mine]))
            )
        }
        assertWorkflowError(.missingRole(.mine)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, roleSnapshots: [theirs]))
            )
        }
        assertWorkflowError(.unexpectedRole(.base)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: rebuilding(
                        snapshot,
                        roleSnapshots: [roleSnapshot(.base, text: "base\n"), theirs, mine]
                    )
                )
            )
        }
    }

    func testNoConflictsAndMalformedNavigationMetadataFailAtTheirOwnGuards() throws {
        let snapshot = try makeSnapshot()
        let noConflicts = ConflictFileParseResult(
            currentText: snapshot.parseResult.currentText,
            baseText: nil,
            incomingText: snapshot.parseResult.incomingText,
            conflicts: []
        )
        assertWorkflowError(.noConflicts) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, parseResult: noConflicts))
            )
        }

        let original = snapshot.parseResult.conflicts[0]
        let malformed = ConflictFileParseResult(
            currentText: snapshot.parseResult.currentText,
            baseText: nil,
            incomingText: snapshot.parseResult.incomingText,
            conflicts: [
                .init(
                    sourceLineRange: original.sourceLineRange,
                    markerWidth: 0,
                    currentLabel: original.currentLabel,
                    baseLabel: nil,
                    incomingLabel: original.incomingLabel
                )
            ]
        )
        assertWorkflowError(.conflictNavigation(.invalidMarkerWidth(conflictIndex: 0, width: 0))) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, parseResult: malformed))
            )
        }
    }

    func testNavigationParserFailuresAreWrappedWithoutLosingExactCause() throws {
        let snapshot = try makeSnapshot()
        let original = snapshot.parseResult.conflicts
        let cases: [([ConflictFileConflict], ConflictNavigationError)] = [
            (
                [
                    .init(
                        sourceLineRange: 0...1,
                        markerWidth: 7,
                        currentLabel: nil,
                        baseLabel: nil,
                        incomingLabel: nil
                    )
                ],
                .invalidSourceLineRange(conflictIndex: 0, lowerBound: 0, upperBound: 1)
            ),
            (
                [
                    conflict(original[0], sourceLineRange: 2...8),
                    conflict(original[1], sourceLineRange: 8...12)
                ],
                .overlappingSourceLineRanges(firstConflictIndex: 0, secondConflictIndex: 1)
            ),
            (
                [
                    .init(
                        sourceLineRange: original[0].sourceLineRange,
                        markerWidth: original[0].markerWidth,
                        currentLabel: original[0].currentLabel,
                        baseLabel: "forged-base",
                        incomingLabel: original[0].incomingLabel,
                        hasBaseContent: true
                    )
                ],
                .basePaneInTwoWayConflict(conflictIndex: 0)
            )
        ]

        for (conflicts, expected) in cases {
            let parseResult = ConflictFileParseResult(
                currentText: snapshot.parseResult.currentText,
                baseText: nil,
                incomingText: snapshot.parseResult.incomingText,
                conflicts: conflicts
            )
            assertWorkflowError(.conflictNavigation(expected)) {
                try ConflictComparisonWorkflow.prepare(
                    .init(snapshot: rebuilding(snapshot, parseResult: parseResult))
                )
            }
        }
    }

    func testCapabilitiesRejectUnknownBitsAndCompareIsRequiredToPrepare() throws {
        let snapshot = try makeSnapshot()
        let invalid = ConflictComparisonCapability(rawValue: ConflictComparisonCapability.all.rawValue | (1 << 15))
        assertWorkflowError(.invalidCapabilities(invalid.rawValue)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, capabilities: invalid))
            )
        }

        let withoutCompare = ConflictComparisonCapability.all.subtracting(.compare)
        assertWorkflowError(.missingCapability(.compare)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: rebuilding(snapshot, capabilities: withoutCompare))
            )
        }
    }

    func testSnapshotCASDetectsReusedGenerationWithChangedState() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let firstRole = snapshot.roleSnapshots[0]
        let advancedRoleRevision = ConflictComparisonSourceRevision(
            identity: firstRole.sourceRevision.identity,
            revision: firstRole.sourceRevision.revision + 1,
            utf8ByteCount: firstRole.sourceRevision.utf8ByteCount,
            contentSHA256: firstRole.sourceRevision.contentSHA256
        )
        var changedRoles = snapshot.roleSnapshots
        changedRoles[0] = .init(role: firstRole.role, sourceRevision: advancedRoleRevision, text: firstRole.text)
        var changedConflicts = snapshot.parseResult.conflicts
        let conflict = changedConflicts[0]
        changedConflicts[0] = .init(
            sourceLineRange: conflict.sourceLineRange,
            markerWidth: conflict.markerWidth,
            currentLabel: "changed-label",
            baseLabel: conflict.baseLabel,
            incomingLabel: conflict.incomingLabel,
            hasCurrentContent: conflict.hasCurrentContent,
            hasBaseContent: conflict.hasBaseContent,
            hasIncomingContent: conflict.hasIncomingContent
        )
        let changedParseResult = ConflictFileParseResult(
            currentText: snapshot.parseResult.currentText,
            baseText: snapshot.parseResult.baseText,
            incomingText: snapshot.parseResult.incomingText,
            conflicts: changedConflicts
        )
        let changedSnapshots = [
            rebuilding(snapshot, isReadOnly: true),
            rebuilding(snapshot, capabilities: [.compare, .navigate]),
            rebuilding(snapshot, roleSnapshots: changedRoles),
            rebuilding(snapshot, parseResult: changedParseResult)
        ]

        for changed in changedSnapshots {
            assertWorkflowError(.snapshotContentsChanged) {
                try plan.validateCurrentSnapshot(changed)
            }
        }
        XCTAssertNoThrow(try plan.validateCurrentSnapshot(snapshot))
    }

    func testSnapshotValidationDistinguishesIdentityGenerationAndDocumentChange() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))

        let otherIdentity = ConflictComparisonSnapshotIdentity(rawValue: Self.otherSnapshotUUID)
        assertWorkflowError(
            .staleSnapshotIdentity(expected: snapshot.identity, actual: otherIdentity)
        ) {
            try plan.validateCurrentSnapshot(rebuilding(snapshot, identity: otherIdentity))
        }
        assertWorkflowError(.staleGeneration(expected: snapshot.generation, actual: snapshot.generation + 1)) {
            try plan.validateCurrentSnapshot(rebuilding(snapshot, generation: snapshot.generation + 1))
        }

        let changedDocument = revision(
            text: Self.diff3Source + "changed",
            identity: snapshot.documentSourceRevision.identity,
            revision: snapshot.documentSourceRevision.revision + 1
        )
        let changed = rebuilding(
            snapshot,
            documentSourceRevision: changedDocument,
            parseResultSourceRevision: changedDocument
        )
        let target = try XCTUnwrap(plan.navigation.first)
        let resolution = try plan.resolutionPlan(
            .init(
                snapshot: plan.snapshotCAS.reference,
                targetID: target.id,
                choice: .base,
                action: .choose
            )
        )
        assertWorkflowError(.documentSourceChanged) {
            try resolution.validateCurrentSnapshot(changed)
        }
    }

    func testNavigationSupportsCommandsSelectionCursorAndClearWithoutWrapping() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let first = try XCTUnwrap(plan.navigation.first)
        let last = try XCTUnwrap(plan.navigation.last)
        let empty = ConflictComparisonSelectionState(snapshot: plan.snapshotCAS.reference)

        XCTAssertEqual(try navigation(plan, state: empty, intent: .command(.first)).target, first)
        XCTAssertEqual(try navigation(plan, state: empty, intent: .command(.last)).target, last)
        XCTAssertEqual(
            try navigation(
                plan,
                state: .init(snapshot: plan.snapshotCAS.reference, cursorSourceLine: first.firstSourceLine),
                intent: .command(.current)
            ).target,
            first
        )
        XCTAssertEqual(try navigation(plan, state: empty, intent: .command(.next)).target, first)
        XCTAssertEqual(try navigation(plan, state: empty, intent: .command(.previous)).target, last)

        let selectedFirst = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: first.id
        )
        let selectedLast = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: last.id
        )
        XCTAssertEqual(try navigation(plan, state: selectedFirst, intent: .command(.next)).target, last)
        XCTAssertNil(try navigation(plan, state: selectedLast, intent: .command(.next)).target)
        XCTAssertEqual(try navigation(plan, state: selectedLast, intent: .command(.previous)).target, first)
        XCTAssertNil(try navigation(plan, state: selectedFirst, intent: .command(.previous)).target)
        XCTAssertEqual(try navigation(plan, state: empty, intent: .select(last.id)).target, last)

        let clear = try navigation(plan, state: selectedFirst, intent: .clear)
        XCTAssertNil(clear.target)
        XCTAssertNil(clear.selectedConflictID)
        XCTAssertFalse(clear.canNavigate)
        XCTAssertEqual(clear.priorState, selectedFirst)
        XCTAssertEqual(clear.receipt.snapshot, plan.snapshotCAS.reference)
        XCTAssertEqual(clear.receipt.intent, .clear)
        XCTAssertNil(clear.receipt.selectedConflictID)
        XCTAssertEqual(clear.receipt.receiptSHA256.count, SHA256.Digest.byteCount)
    }

    func testCurrentNavigationCoversBeforeInsideBetweenAfterAndSelectionPrecedence() throws {
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: makeSnapshot()))
        let first = try XCTUnwrap(plan.navigation.first)
        let last = try XCTUnwrap(plan.navigation.last)
        let positions: [(Int, ConflictNavigationTarget?)] = [
            (first.firstSourceLine - 1, nil),
            (first.firstSourceLine, first),
            (first.lastSourceLine, first),
            (first.lastSourceLine + 1, nil),
            (last.firstSourceLine, last),
            (last.lastSourceLine, last),
            (last.lastSourceLine + 1, nil)
        ]

        for (line, expected) in positions {
            let state = ConflictComparisonSelectionState(
                snapshot: plan.snapshotCAS.reference,
                cursorSourceLine: line
            )
            XCTAssertEqual(
                try navigation(plan, state: state, intent: .command(.current)).target,
                expected,
                "line=\(line)"
            )
        }

        let selected = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: last.id,
            cursorSourceLine: first.firstSourceLine
        )
        XCTAssertEqual(
            try navigation(plan, state: selected, intent: .command(.current)).target,
            last
        )
    }

    func testNavigationReceiptsAreDeterministicAndIntentBound() throws {
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: makeSnapshot()))
        let state = ConflictComparisonSelectionState(snapshot: plan.snapshotCAS.reference)
        let first = try navigation(plan, state: state, intent: .command(.first))
        let repeated = try navigation(plan, state: state, intent: .command(.first))
        let last = try navigation(plan, state: state, intent: .command(.last))

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.receipt.receiptSHA256, repeated.receipt.receiptSHA256)
        XCTAssertNotEqual(first.receipt.receiptSHA256, last.receipt.receiptSHA256)
        XCTAssertEqual(first.snapshotCAS, plan.snapshotCAS)
        XCTAssertEqual(first.selectedConflictID, plan.navigation.first?.id)
        XCTAssertTrue(first.canNavigate)
    }

    func testNavigationIntentHashSeparatesFirstFromSelectingItsSameTarget() throws {
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: makeSnapshot()))
        let target = try XCTUnwrap(plan.navigation.first)
        let state = ConflictComparisonSelectionState(snapshot: plan.snapshotCAS.reference)
        let first = try navigation(plan, state: state, intent: .command(.first))
        let selected = try navigation(plan, state: state, intent: .select(target.id))

        XCTAssertEqual(first.target, selected.target)
        XCTAssertNotEqual(first.intent, selected.intent)
        XCTAssertNotEqual(first.receipt.receiptSHA256, selected.receipt.receiptSHA256)
    }

    func testNavigationRejectsStaleSelectedIDsBeforeApplyingEveryIntent() throws {
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: makeSnapshot()))
        let target = try XCTUnwrap(plan.navigation.first)
        let stale = try ConflictNavigationTarget(
            generation: target.generation + 1,
            index: target.index,
            sourceLineRange: target.sourceLineRange,
            markerWidth: target.id.markerWidth,
            topology: target.id.topology,
            currentLabel: target.id.currentLabel,
            incomingLabel: target.id.incomingLabel,
            paneContributions: target.paneContributions
        )
        let state = ConflictComparisonSelectionState(
            snapshot: plan.snapshotCAS.reference,
            selectedConflictID: stale.id,
            cursorSourceLine: target.firstSourceLine
        )

        for intent in [
            ConflictComparisonSelectionIntent.command(.first),
            .command(.current),
            .command(.previous),
            .command(.next),
            .command(.last),
            .select(target.id),
            .clear
        ] {
            assertWorkflowError(
                .staleConflictGeneration(expected: target.generation, actual: stale.generation)
            ) {
                try navigation(plan, state: state, intent: intent)
            }
        }
    }

    func testNavigationGuardsCapabilitySnapshotGenerationLineAndConflictIdentity() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let otherIdentity = ConflictComparisonSnapshotIdentity(rawValue: Self.otherSnapshotUUID)

        let noNavigateSnapshot = rebuilding(
            snapshot,
            capabilities: ConflictComparisonCapability.all.subtracting(.navigate)
        )
        let noNavigatePlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: noNavigateSnapshot))
        assertWorkflowError(.missingCapability(.navigate)) {
            try navigation(
                noNavigatePlan,
                state: .init(snapshot: noNavigatePlan.snapshotCAS.reference),
                intent: .command(.first)
            )
        }
        assertWorkflowError(
            .staleSnapshotIdentity(expected: snapshot.identity, actual: otherIdentity)
        ) {
            try navigation(
                plan,
                state: .init(snapshot: .init(identity: otherIdentity, generation: snapshot.generation)),
                intent: .command(.first)
            )
        }
        assertWorkflowError(.staleGeneration(expected: snapshot.generation, actual: snapshot.generation + 1)) {
            try navigation(
                plan,
                state: .init(snapshot: .init(identity: snapshot.identity, generation: snapshot.generation + 1)),
                intent: .command(.first)
            )
        }
        assertWorkflowError(.invalidSelectionSourceLine(0)) {
            try navigation(
                plan,
                state: .init(snapshot: plan.snapshotCAS.reference, cursorSourceLine: 0),
                intent: .command(.current)
            )
        }

        let staleGenerationTarget = try ConflictNavigationTarget(
            generation: target.generation + 1,
            index: target.index,
            sourceLineRange: target.sourceLineRange,
            markerWidth: target.id.markerWidth,
            topology: target.id.topology,
            currentLabel: target.id.currentLabel,
            baseLabel: target.id.baseLabel,
            incomingLabel: target.id.incomingLabel,
            paneContributions: target.paneContributions
        )
        assertWorkflowError(
            .staleConflictGeneration(expected: target.generation, actual: target.generation + 1)
        ) {
            try navigation(plan, state: .init(snapshot: plan.snapshotCAS.reference), intent: .select(staleGenerationTarget.id))
        }

        let forgedTarget = try ConflictNavigationTarget(
            generation: target.generation,
            index: target.index,
            sourceLineRange: target.sourceLineRange,
            markerWidth: target.id.markerWidth,
            topology: target.id.topology,
            currentLabel: "forged",
            baseLabel: target.id.baseLabel,
            incomingLabel: target.id.incomingLabel,
            paneContributions: target.paneContributions
        )
        assertWorkflowError(.staleConflictIdentity(forgedTarget.id)) {
            try navigation(plan, state: .init(snapshot: plan.snapshotCAS.reference), intent: .select(forgedTarget.id))
        }
    }

    func testReadOnlyDocumentsCanNavigateWhenCapabilityIsPresent() throws {
        let snapshot = try makeSnapshot(
            isReadOnly: true,
            capabilities: [.compare, .navigate]
        )
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let result = try navigation(
            plan,
            state: .init(snapshot: plan.snapshotCAS.reference),
            intent: .command(.first)
        )

        XCTAssertEqual(result.target, plan.navigation.first)
    }

    func testForgedSameGenerationTargetIdentityIsRejectedForNavigationAndResolution() throws {
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: makeSnapshot()))
        let target = try XCTUnwrap(plan.navigation.first)
        let forged = try ConflictNavigationTarget(
            generation: target.generation,
            index: target.index,
            sourceLineRange: target.sourceLineRange,
            markerWidth: target.id.markerWidth + 1,
            topology: target.id.topology,
            currentLabel: target.id.currentLabel,
            baseLabel: target.id.baseLabel,
            incomingLabel: target.id.incomingLabel,
            paneContributions: target.paneContributions
        )

        assertWorkflowError(.staleConflictIdentity(forged.id)) {
            try navigation(
                plan,
                state: .init(snapshot: plan.snapshotCAS.reference),
                intent: .select(forged.id)
            )
        }
        assertWorkflowError(.staleConflictIdentity(forged.id)) {
            try plan.resolutionPlan(
                .init(
                    snapshot: plan.snapshotCAS.reference,
                    targetID: forged.id,
                    choice: .mine,
                    action: .choose
                )
            )
        }
    }

    func testResolutionPlansBindTargetChoiceActionAndSelectedRevision() throws {
        let snapshot = try makeSnapshot(source: Self.diff3Source)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)

        for choice in ConflictComparisonResolutionChoice.allCases {
            for action in ConflictComparisonResolutionAction.allCases {
                let intent = ConflictComparisonResolutionIntent(
                    snapshot: plan.snapshotCAS.reference,
                    targetID: target.id,
                    choice: choice,
                    action: action
                )
                let resolution = try plan.resolutionPlan(intent)
                let expectedRevision = try XCTUnwrap(plan.roleReference(for: choice.role)?.sourceRevision)

                XCTAssertEqual(resolution.snapshotCAS, plan.snapshotCAS)
                XCTAssertEqual(resolution.documentSourceRevision, plan.documentSourceRevision)
                XCTAssertEqual(resolution.target, target)
                XCTAssertEqual(resolution.choice, choice)
                XCTAssertEqual(resolution.action, action)
                XCTAssertEqual(resolution.authorizesMutation, action == .apply)
                XCTAssertEqual(resolution.selectedSourceRevision, expectedRevision)
                XCTAssertEqual(resolution.receipt.snapshot, plan.snapshotCAS.reference)
                XCTAssertEqual(resolution.receipt.targetID, target.id)
                XCTAssertEqual(resolution.receipt.choice, choice)
                XCTAssertEqual(resolution.receipt.action, action)
                XCTAssertEqual(resolution.receipt.selectedSourceRevision, expectedRevision)
                XCTAssertEqual(resolution.receipt.planSHA256.count, SHA256.Digest.byteCount)
                XCTAssertEqual(resolution.limits, plan.limits)
                XCTAssertEqual(resolution.executorContract, .required)
            }
        }
    }

    func testResolutionReceiptsAreDeterministicAndChoiceActionBound() throws {
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: makeSnapshot(source: Self.diff3Source)))
        let target = try XCTUnwrap(plan.navigation.first)
        func resolution(_ choice: ConflictComparisonResolutionChoice, _ action: ConflictComparisonResolutionAction) throws
            -> ConflictComparisonResolutionPlan
        {
            try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: choice, action: action)
            )
        }

        let first = try resolution(.theirs, .choose)
        XCTAssertEqual(first, try resolution(.theirs, .choose))
        XCTAssertNotEqual(first.receipt.planSHA256, try resolution(.mine, .choose).receipt.planSHA256)
        XCTAssertNotEqual(first.receipt.planSHA256, try resolution(.theirs, .apply).receipt.planSHA256)
    }

    func testResolutionHashSeparatesEachChoiceTargetAndActionIndependently() throws {
        let plan = try ConflictComparisonWorkflow.prepare(
            .init(snapshot: makeSnapshot(source: Self.diff3Source))
        )
        let first = try XCTUnwrap(plan.navigation.first)
        let second = try XCTUnwrap(plan.navigation.last)
        func hash(
            target: ConflictNavigationTarget = first,
            choice: ConflictComparisonResolutionChoice = .base,
            action: ConflictComparisonResolutionAction = .choose
        ) throws -> [UInt8] {
            try plan.resolutionPlan(
                .init(
                    snapshot: plan.snapshotCAS.reference,
                    targetID: target.id,
                    choice: choice,
                    action: action
                )
            ).receipt.planSHA256
        }

        let baseline = try hash()
        XCTAssertNotEqual(baseline, try hash(choice: .theirs))
        XCTAssertNotEqual(baseline, try hash(choice: .mine))
        XCTAssertNotEqual(baseline, try hash(target: second))
        XCTAssertNotEqual(baseline, try hash(action: .apply))
    }

    func testTwoWayBaseResolutionIsUnavailableButTheirsAndMineRemainAvailable() throws {
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: makeSnapshot()))
        let target = try XCTUnwrap(plan.navigation.first)

        assertWorkflowError(.baseUnavailableInTwoWayComparison) {
            try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .base, action: .choose)
            )
        }
        XCTAssertNoThrow(
            try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .theirs, action: .choose)
            )
        )
        XCTAssertNoThrow(
            try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
            )
        )
    }

    func testReadOnlyAndCapabilitiesPermitChoiceButGateApplyAndNavigation() throws {
        let capabilities: ConflictComparisonCapability = [.compare, .navigate, .chooseTheirs]
        let snapshot = try makeSnapshot(isReadOnly: true, capabilities: capabilities)
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let choose = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .theirs, action: .choose)
        )

        XCTAssertNoThrow(try choose.authorizeChoice(validating: snapshot))
        assertWorkflowError(.missingCapability(.chooseMine)) {
            try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
            )
        }
        assertWorkflowError(.missingCapability(.applyResolution)) {
            try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .theirs, action: .apply)
            )
        }

        let readOnlyWithApply = try makeSnapshot(
            isReadOnly: true,
            capabilities: [.compare, .chooseTheirs, .applyResolution]
        )
        let readOnlyPlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: readOnlyWithApply))
        let readOnlyTarget = try XCTUnwrap(readOnlyPlan.navigation.first)
        assertWorkflowError(.readOnlyDocument) {
            try readOnlyPlan.resolutionPlan(
                .init(
                    snapshot: readOnlyPlan.snapshotCAS.reference,
                    targetID: readOnlyTarget.id,
                    choice: .theirs,
                    action: .apply
                )
            )
        }
    }

    func testDiff3BaseChoiceRequiresBaseCapabilityAtPlanningAndAuthorization() throws {
        let capabilities = ConflictComparisonCapability.all.subtracting(.chooseBase)
        let snapshot = try makeSnapshot(
            source: Self.diff3Source,
            capabilities: capabilities
        )
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        assertWorkflowError(.missingCapability(.chooseBase)) {
            try plan.resolutionPlan(
                .init(
                    snapshot: plan.snapshotCAS.reference,
                    targetID: target.id,
                    choice: .base,
                    action: .choose
                )
            )
        }

        let fullSnapshot = try makeSnapshot(source: Self.diff3Source)
        let fullPlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: fullSnapshot))
        let fullTarget = try XCTUnwrap(fullPlan.navigation.first)
        let resolution = try fullPlan.resolutionPlan(
            .init(
                snapshot: fullPlan.snapshotCAS.reference,
                targetID: fullTarget.id,
                choice: .base,
                action: .choose
            )
        )
        assertWorkflowError(.missingCapability(.chooseBase)) {
            try resolution.authorizeChoice(
                validating: rebuilding(fullSnapshot, capabilities: capabilities)
            )
        }
    }

    func testResolutionPlanningRejectsStaleSnapshotAndConflictReferences() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let otherIdentity = ConflictComparisonSnapshotIdentity(rawValue: Self.otherSnapshotUUID)

        assertWorkflowError(.staleSnapshotIdentity(expected: snapshot.identity, actual: otherIdentity)) {
            try plan.resolutionPlan(
                .init(
                    snapshot: .init(identity: otherIdentity, generation: snapshot.generation),
                    targetID: target.id,
                    choice: .mine,
                    action: .choose
                )
            )
        }
        assertWorkflowError(.staleGeneration(expected: snapshot.generation, actual: snapshot.generation + 1)) {
            try plan.resolutionPlan(
                .init(
                    snapshot: .init(identity: snapshot.identity, generation: snapshot.generation + 1),
                    targetID: target.id,
                    choice: .mine,
                    action: .choose
                )
            )
        }

        let stale = try ConflictNavigationTarget(
            generation: target.generation + 1,
            index: target.index,
            sourceLineRange: target.sourceLineRange,
            topology: .twoWay
        )
        assertWorkflowError(
            .staleConflictGeneration(expected: target.generation, actual: target.generation + 1)
        ) {
            try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: stale.id, choice: .mine, action: .choose)
            )
        }
    }

    func testApplyPlanningRejectsExhaustedGenerationAndDocumentRevision() throws {
        let maxGeneration = try makeSnapshot(generation: .max)
        let maxGenerationPlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: maxGeneration))
        let maxGenerationTarget = try XCTUnwrap(maxGenerationPlan.navigation.first)
        assertWorkflowError(.successorGenerationExhausted) {
            try maxGenerationPlan.resolutionPlan(
                .init(
                    snapshot: maxGenerationPlan.snapshotCAS.reference,
                    targetID: maxGenerationTarget.id,
                    choice: .mine,
                    action: .apply
                )
            )
        }

        let ordinary = try makeSnapshot()
        let maxDocumentRevision = ConflictComparisonSourceRevision(
            identity: ordinary.documentSourceRevision.identity,
            revision: .max,
            utf8ByteCount: ordinary.documentSourceRevision.utf8ByteCount,
            contentSHA256: ordinary.documentSourceRevision.contentSHA256
        )
        let exhausted = rebuilding(
            ordinary,
            documentSourceRevision: maxDocumentRevision,
            parseResultSourceRevision: maxDocumentRevision
        )
        let exhaustedPlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: exhausted))
        let exhaustedTarget = try XCTUnwrap(exhaustedPlan.navigation.first)
        assertWorkflowError(.successorSourceRevisionExhausted) {
            try exhaustedPlan.resolutionPlan(
                .init(
                    snapshot: exhaustedPlan.snapshotCAS.reference,
                    targetID: exhaustedTarget.id,
                    choice: .mine,
                    action: .apply
                )
            )
        }
    }

    func testMaximumPredecessorGenerationAndRevisionMinusOnePermitSuccessThenExhaust() throws {
        let nearMaximum = try makeSnapshot(generation: UInt64.max - 1)
        let nearMaximumDocument = ConflictComparisonSourceRevision(
            identity: nearMaximum.documentSourceRevision.identity,
            revision: UInt64.max - 1,
            utf8ByteCount: nearMaximum.documentSourceRevision.utf8ByteCount,
            contentSHA256: nearMaximum.documentSourceRevision.contentSHA256
        )
        let snapshot = rebuilding(
            nearMaximum,
            documentSourceRevision: nearMaximumDocument,
            parseResultSourceRevision: nearMaximumDocument
        )
        let comparison = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(comparison.navigation.first)
        let resolution = try comparison.resolutionPlan(
            .init(
                snapshot: comparison.snapshotCAS.reference,
                targetID: target.id,
                choice: .mine,
                action: .apply
            )
        )
        let permit = try resolution.authorizeApply(validating: snapshot)
        let successor = ConflictComparisonAppliedSuccessor(
            snapshot: .init(identity: snapshot.identity, generation: .max),
            documentSourceRevision: revision(
                text: "resolved\n",
                identity: nearMaximumDocument.identity,
                revision: .max
            )
        )
        let receipt = ConflictComparisonApplyCASReceipt.executorAttestedCommitted(
            permit: permit,
            successor: successor
        )
        guard
            case .completed(.applied) = ConflictComparisonExecutionOutcomeFactory.applied(
                plan: resolution,
                casReceipt: receipt
            )
        else {
            return XCTFail("Expected maximum successor to apply")
        }

        let exhaustedSnapshot = rebuilding(
            snapshot,
            generation: .max,
            documentSourceRevision: successor.documentSourceRevision,
            parseResultSourceRevision: successor.documentSourceRevision
        )
        let exhaustedPlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: exhaustedSnapshot))
        let exhaustedTarget = try XCTUnwrap(exhaustedPlan.navigation.first)
        assertWorkflowError(.successorGenerationExhausted) {
            try exhaustedPlan.resolutionPlan(
                .init(
                    snapshot: exhaustedPlan.snapshotCAS.reference,
                    targetID: exhaustedTarget.id,
                    choice: .mine,
                    action: .apply
                )
            )
        }
    }

    func testChoiceAndApplyAuthorizationRequireMatchingIntent() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let choose = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
        )
        let apply = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .apply)
        )

        XCTAssertNoThrow(try choose.authorizeChoice(validating: snapshot))
        assertWorkflowError(.applyAuthorizationRequiresApplyIntent) {
            try choose.authorizeApply(validating: snapshot)
        }
        XCTAssertNoThrow(try apply.authorizeApply(validating: snapshot))
        assertWorkflowError(.choiceAuthorizationRequiresChooseIntent) {
            try apply.authorizeChoice(validating: snapshot)
        }
    }

    func testAuthorizationRevalidatesCapabilitiesReadOnlyAndExactCAS() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let choose = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
        )
        let apply = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .apply)
        )

        assertWorkflowError(.missingCapability(.chooseMine)) {
            try choose.authorizeChoice(
                validating: rebuilding(
                    snapshot,
                    capabilities: ConflictComparisonCapability.all.subtracting(.chooseMine)
                )
            )
        }
        assertWorkflowError(.readOnlyDocument) {
            try apply.authorizeApply(validating: rebuilding(snapshot, isReadOnly: true))
        }
        assertWorkflowError(.missingCapability(.applyResolution)) {
            try apply.authorizeApply(
                validating: rebuilding(
                    snapshot,
                    capabilities: ConflictComparisonCapability.all.subtracting(.applyResolution)
                )
            )
        }

        let firstRole = snapshot.roleSnapshots[0]
        let changedRevision = ConflictComparisonSourceRevision(
            identity: firstRole.sourceRevision.identity,
            revision: firstRole.sourceRevision.revision + 1,
            utf8ByteCount: firstRole.sourceRevision.utf8ByteCount,
            contentSHA256: firstRole.sourceRevision.contentSHA256
        )
        var roles = snapshot.roleSnapshots
        roles[0] = .init(role: firstRole.role, sourceRevision: changedRevision, text: firstRole.text)
        assertWorkflowError(.snapshotContentsChanged) {
            try choose.authorizeChoice(validating: rebuilding(snapshot, roleSnapshots: roles))
        }
    }

    func testChoiceOutcomeRequiresPermitFromExactPlan() throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let mine = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
        )
        let theirs = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .theirs, action: .choose)
        )
        let permit = try mine.authorizeChoice(validating: snapshot)

        guard
            case .completed(.choiceRecorded(let receipt)) = ConflictComparisonExecutionOutcomeFactory.choiceRecorded(
                plan: mine,
                permit: permit
            )
        else {
            return XCTFail("Expected recorded choice")
        }
        XCTAssertEqual(receipt.planningReceipt, mine.receipt)
        assertInvalidPlan(
            ConflictComparisonExecutionOutcomeFactory.choiceRecorded(plan: theirs, permit: permit)
        )
    }

    func testAppliedOutcomeCarriesExactPredecessorAndSuccessorReceipts() throws {
        let fixture = try applyFixture()
        let successor = validSuccessor(for: fixture.plan)
        let casReceipt = ConflictComparisonApplyCASReceipt.executorAttestedCommitted(
            permit: fixture.permit,
            successor: successor
        )

        guard
            case .completed(.applied(let receipt)) = ConflictComparisonExecutionOutcomeFactory.applied(
                plan: fixture.plan,
                casReceipt: casReceipt
            )
        else {
            return XCTFail("Expected applied outcome")
        }
        XCTAssertEqual(receipt.planningReceipt, fixture.plan.receipt)
        XCTAssertEqual(receipt.predecessorCAS, fixture.plan.snapshotCAS)
        XCTAssertEqual(receipt.successor, successor)
    }

    func testAppliedOutcomeRejectsReceiptFromAnotherPlan() throws {
        let snapshot = try makeSnapshot()
        let comparison = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(comparison.navigation.first)
        let mine = try comparison.resolutionPlan(
            .init(snapshot: comparison.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .apply)
        )
        let theirs = try comparison.resolutionPlan(
            .init(snapshot: comparison.snapshotCAS.reference, targetID: target.id, choice: .theirs, action: .apply)
        )
        let minePermit = try mine.authorizeApply(validating: snapshot)
        let receipt = ConflictComparisonApplyCASReceipt.executorAttestedCommitted(
            permit: minePermit,
            successor: validSuccessor(for: mine)
        )

        assertInvalidPlan(
            ConflictComparisonExecutionOutcomeFactory.applied(plan: theirs, casReceipt: receipt)
        )
    }

    func testInvalidAppliedSuccessorStatesAreMutationUncertain() throws {
        let fixture = try applyFixture()
        let plan = fixture.plan
        let valid = validSuccessor(for: plan)
        let unchangedBytes = ConflictComparisonSourceRevision(
            identity: plan.documentSourceRevision.identity,
            revision: plan.documentSourceRevision.revision + 1,
            utf8ByteCount: plan.documentSourceRevision.utf8ByteCount,
            contentSHA256: plan.documentSourceRevision.contentSHA256
        )
        let wrongIdentity = ConflictComparisonSnapshotIdentity(rawValue: Self.otherSnapshotUUID)
        let wrongSourceIdentity = ConflictComparisonSourceIdentity(
            namespace: Self.namespaceUUID,
            value: "other-document"
        )
        let invalidSuccessors = [
            ConflictComparisonAppliedSuccessor(
                snapshot: valid.snapshot,
                documentSourceRevision: unchangedBytes
            ),
            ConflictComparisonAppliedSuccessor(
                snapshot: .init(identity: wrongIdentity, generation: valid.snapshot.generation),
                documentSourceRevision: valid.documentSourceRevision
            ),
            ConflictComparisonAppliedSuccessor(
                snapshot: .init(identity: valid.snapshot.identity, generation: plan.snapshotCAS.reference.generation),
                documentSourceRevision: valid.documentSourceRevision
            ),
            ConflictComparisonAppliedSuccessor(
                snapshot: valid.snapshot,
                documentSourceRevision: revision(text: "resolved\n", identity: wrongSourceIdentity, revision: valid.documentSourceRevision.revision)
            ),
            ConflictComparisonAppliedSuccessor(
                snapshot: valid.snapshot,
                documentSourceRevision: revision(
                    text: "resolved\n",
                    identity: plan.documentSourceRevision.identity,
                    revision: plan.documentSourceRevision.revision
                )
            ),
            ConflictComparisonAppliedSuccessor(
                snapshot: valid.snapshot,
                documentSourceRevision: .init(
                    identity: plan.documentSourceRevision.identity,
                    revision: valid.documentSourceRevision.revision,
                    utf8ByteCount: valid.documentSourceRevision.utf8ByteCount,
                    contentSHA256: []
                )
            ),
            ConflictComparisonAppliedSuccessor(
                snapshot: valid.snapshot,
                documentSourceRevision: .init(
                    identity: plan.documentSourceRevision.identity,
                    revision: valid.documentSourceRevision.revision,
                    utf8ByteCount: -1,
                    contentSHA256: valid.documentSourceRevision.contentSHA256
                )
            )
        ]

        for successor in invalidSuccessors {
            let receipt = ConflictComparisonApplyCASReceipt.executorAttestedCommitted(
                permit: fixture.permit,
                successor: successor
            )
            guard
                case .mutationUncertain(let uncertainty) = ConflictComparisonExecutionOutcomeFactory.applied(
                    plan: plan,
                    casReceipt: receipt
                )
            else {
                XCTFail("Expected mutation uncertainty for \(successor)")
                continue
            }
            XCTAssertEqual(uncertainty.planningReceipt, plan.receipt)
            XCTAssertEqual(uncertainty.snapshot, plan.receipt.snapshot)
            XCTAssertEqual(uncertainty.targetID, plan.target.id)
        }
    }

    func testSuccessorMayAdvanceGenerationAndRevisionByMoreThanOne() throws {
        let fixture = try applyFixture()
        let successor = ConflictComparisonAppliedSuccessor(
            snapshot: .init(
                identity: fixture.plan.snapshotCAS.reference.identity,
                generation: fixture.plan.snapshotCAS.reference.generation + 2
            ),
            documentSourceRevision: revision(
                text: "resolved by later owner state\n",
                identity: fixture.plan.documentSourceRevision.identity,
                revision: fixture.plan.documentSourceRevision.revision + 2
            )
        )
        let receipt = ConflictComparisonApplyCASReceipt.executorAttestedCommitted(
            permit: fixture.permit,
            successor: successor
        )

        guard
            case .completed(.applied(let applied)) = ConflictComparisonExecutionOutcomeFactory.applied(
                plan: fixture.plan,
                casReceipt: receipt
            )
        else {
            return XCTFail("Expected +2 successor to apply")
        }
        XCTAssertEqual(applied.successor, successor)
    }

    func testSuccessorInvalidByteCountAndDigestShapesAreIndependentlyUncertain() throws {
        let fixture = try applyFixture()
        let valid = validSuccessor(for: fixture.plan)
        let invalid = [
            ConflictComparisonAppliedSuccessor(
                snapshot: valid.snapshot,
                documentSourceRevision: .init(
                    identity: valid.documentSourceRevision.identity,
                    revision: valid.documentSourceRevision.revision,
                    utf8ByteCount: -1,
                    contentSHA256: valid.documentSourceRevision.contentSHA256
                )
            ),
            ConflictComparisonAppliedSuccessor(
                snapshot: valid.snapshot,
                documentSourceRevision: .init(
                    identity: valid.documentSourceRevision.identity,
                    revision: valid.documentSourceRevision.revision,
                    utf8ByteCount: valid.documentSourceRevision.utf8ByteCount,
                    contentSHA256: Array(repeating: 0, count: SHA256.Digest.byteCount - 1)
                )
            )
        ]

        for successor in invalid {
            let receipt = ConflictComparisonApplyCASReceipt.executorAttestedCommitted(
                permit: fixture.permit,
                successor: successor
            )
            guard
                case .mutationUncertain = ConflictComparisonExecutionOutcomeFactory.applied(
                    plan: fixture.plan,
                    casReceipt: receipt
                )
            else {
                XCTFail("Expected malformed successor uncertainty")
                continue
            }
        }
    }

    func testExplicitMutationUncertaintyRequiresExactApplyPermit() throws {
        let fixture = try applyFixture()
        guard
            case .mutationUncertain(let uncertainty) = ConflictComparisonExecutionOutcomeFactory.mutationUncertain(
                plan: fixture.plan,
                permit: fixture.permit
            )
        else {
            return XCTFail("Expected mutation uncertainty")
        }
        XCTAssertEqual(uncertainty.planningReceipt, fixture.plan.receipt)

        let other = try applyFixture(choice: .theirs)
        assertInvalidPlan(
            ConflictComparisonExecutionOutcomeFactory.mutationUncertain(
                plan: fixture.plan,
                permit: other.permit
            )
        )
    }

    func testFailureAndCancellationFactoriesEnforceActionContracts() throws {
        let snapshot = try makeSnapshot()
        let comparison = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(comparison.navigation.first)
        let choose = try comparison.resolutionPlan(
            .init(snapshot: comparison.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
        )
        let apply = try comparison.resolutionPlan(
            .init(snapshot: comparison.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .apply)
        )
        let allowedChoiceFailures: Set<ConflictComparisonExecutionFailureCode> = [
            .staleSnapshot, .sourceRevisionChanged, .missingCapability, .invalidPlan, .contractUnsupported
        ]

        for code in ConflictComparisonExecutionFailureCode.allCases {
            let chooseOutcome = ConflictComparisonExecutionOutcomeFactory.failed(plan: choose, code: code)
            if allowedChoiceFailures.contains(code) {
                assertFailure(chooseOutcome, code: code)
            } else {
                assertInvalidPlan(chooseOutcome)
            }
            assertFailure(
                ConflictComparisonExecutionOutcomeFactory.failed(plan: apply, code: code),
                code: code
            )
        }

        guard
            case .cancelled(let receipt) = ConflictComparisonExecutionOutcomeFactory.cancelledBeforeApplyAuthorization(
                plan: apply
            )
        else {
            return XCTFail("Expected cancellation receipt")
        }
        XCTAssertEqual(receipt.planningReceipt, apply.receipt)
        assertInvalidPlan(
            ConflictComparisonExecutionOutcomeFactory.cancelledBeforeApplyAuthorization(plan: choose)
        )
    }

    func testExecutorContractPublishesAllMandatoryBoundarySemantics() {
        let contract = ConflictComparisonExecutorContract.required
        XCTAssertEqual(contract.sourceLease, .exactDocumentAndRoleRevisionsHeldThroughApplyCommit)
        XCTAssertEqual(contract.apply, .resolveExactlyOneTargetFromCurrentConflictDocumentWithoutReinterpretingPlan)
        XCTAssertEqual(contract.compareAndSwap, .serializedOwnerGenerationAndDocumentRevisionCompareAndSwap)
        XCTAssertEqual(contract.capability, .revalidateCapabilitiesAndReadOnlyStateBeforeMutation)
        XCTAssertEqual(contract.cancellation, .cancellableBeforeMutationCommittedOrUncertainAfterCASStarts)
        XCTAssertEqual(contract, ConflictComparisonExecutorContract())
    }

    func testSafeSubstitutionChangesComparisonAndBindsDeterministicReceipt() throws {
        let source = Self.substitutionSource
        let snapshot = try makeSnapshot(source: source)
        let ordinary = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let options = ConflictComparisonOptions(
            twoWay: .init(
                ignoreLineEndings: false,
                substitutions: [.init(pattern: "[0-9]", replacement: "#")]
            )
        )
        let transformed = try ConflictComparisonWorkflow.prepare(
            .init(snapshot: snapshot, options: options)
        )
        let repeated = try ConflictComparisonWorkflow.prepare(
            .init(snapshot: snapshot, options: options)
        )

        guard case .twoWay(let ordinaryResult) = ordinary.comparison,
            case .twoWay(let transformedResult) = transformed.comparison
        else {
            return XCTFail("Expected two-way results")
        }
        XCTAssertTrue(ordinaryResult.rows.contains { $0.kind != .unchanged })
        XCTAssertTrue(transformedResult.rows.allSatisfy { $0.kind == .unchanged })
        XCTAssertNotEqual(ordinary.receipt.planSHA256, transformed.receipt.planSHA256)
        XCTAssertEqual(transformed, repeated)
        XCTAssertEqual(transformed.receipt.planSHA256, repeated.receipt.planSHA256)
    }

    func testLineFilterBlankAndCommentTransformsRespectEnabledAndSyntaxState() throws {
        let cases: [(source: String, active: LineDiffOptions, inactive: LineDiffOptions)] = [
            (
                twoWaySource(mine: "# old", theirs: "# new"),
                .init(lineFilters: [.init(pattern: #"^# "#)]),
                .init(
                    lineFiltersEnabled: false,
                    lineFilters: [.init(pattern: #"^# "#)]
                )
            ),
            (
                twoWaySource(mine: "", theirs: " "),
                .init(ignoreBlankLines: true),
                .init(ignoreBlankLines: false)
            ),
            (
                twoWaySource(mine: "// old", theirs: "// new"),
                .init(ignoreComments: true, commentSyntax: .cFamily),
                .init(ignoreComments: true, commentSyntax: nil)
            ),
            (
                twoWaySource(mine: "// old", theirs: "// new"),
                .init(ignoreComments: true, commentSyntax: .cFamily),
                .init(ignoreComments: false, commentSyntax: .cFamily)
            )
        ]

        for testCase in cases {
            let snapshot = try makeSnapshot(source: testCase.source)
            XCTAssertEqual(
                try comparisonDifferenceCount(snapshot: snapshot, options: testCase.active),
                0
            )
            XCTAssertGreaterThan(
                try comparisonDifferenceCount(snapshot: snapshot, options: testCase.inactive),
                0
            )
        }
    }

    func testUnsafeSubstitutionReplacementIsRejectedOnlyWhenActiveAndNonempty() throws {
        let snapshot = try makeSnapshot()
        for replacement in ["$1", "\\1", "line\nnext", "line\rnext"] {
            let options = ConflictComparisonOptions(
                twoWay: .init(substitutions: [.init(pattern: "x", replacement: replacement)])
            )
            assertWorkflowError(.unsafeSubstitutionReplacement) {
                try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot, options: options))
            }
        }

        XCTAssertNoThrow(
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: .init(
                        twoWay: .init(
                            substitutionsEnabled: false,
                            substitutions: [.init(pattern: "x", replacement: "$1")]
                        )
                    )
                )
            )
        )
        XCTAssertNoThrow(
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: .init(
                        twoWay: .init(substitutions: [.init(pattern: "", replacement: "$1")])
                    )
                )
            )
        )
    }

    func testSubstitutionExpansionBoundRejectsBeforeNativeComparison() throws {
        let payload = String(repeating: "a", count: 1_024)
        let source = ["<<<<<<< mine", payload, "=======", payload, ">>>>>>> theirs"].joined(separator: "\n")
        let snapshot = try makeSnapshot(source: source)
        let replacement = String(repeating: "z", count: 65_536)
        let options = ConflictComparisonOptions(
            twoWay: .init(
                ignoreLineEndings: false,
                substitutions: [.init(pattern: "a", replacement: replacement)]
            )
        )
        let roomyLimits = limits(
            maximumOptionStringUTF8Bytes: replacement.utf8.count,
            maximumTotalOptionUTF8Bytes: replacement.utf8.count + 1,
            maximumWorkUnits: ConflictComparisonLimits.hardMaximumWorkUnits
        )

        assertWorkflowError(
            .lineDiff(.inputTooLarge(maximumBytes: ConflictComparisonLimits.maximumNativeComparisonInputBytes))
        ) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, options: options, limits: roomyLimits)
            )
        }
    }

    func testReservedTransformMarkerIsRejectedOnlyWhenTransformIsActive() throws {
        let source = [
            "<<<<<<< mine", "!MACMERGE-FILTERED-user", "=======", "theirs", ">>>>>>> incoming"
        ].joined(separator: "\n")
        let snapshot = try makeSnapshot(source: source)

        XCTAssertNoThrow(try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot)))
        assertWorkflowError(.reservedTransformMarkerCollision) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: .init(twoWay: .init(ignoreBlankLines: true))
                )
            )
        }
    }

    func testReservedMarkerCollisionCoversBothRolesAndEveryTransformActivationSwitch() throws {
        let marker = "!MACMERGE-FILTERED-user"
        let roleSources = [
            twoWaySource(mine: marker, theirs: "ordinary"),
            twoWaySource(mine: "ordinary", theirs: marker)
        ]
        let active = [
            LineDiffOptions(ignoreBlankLines: true),
            .init(lineFilters: [.init(pattern: "ordinary")]),
            .init(substitutions: [.init(pattern: "ordinary", replacement: "same")]),
            .init(ignoreComments: true, commentSyntax: .cFamily)
        ]
        let inactive = [
            LineDiffOptions(ignoreBlankLines: false),
            .init(
                lineFiltersEnabled: false,
                lineFilters: [.init(pattern: "ordinary")]
            ),
            .init(
                substitutionsEnabled: false,
                substitutions: [.init(pattern: "ordinary", replacement: "same")]
            ),
            .init(substitutions: [.init(pattern: "", replacement: "same")]),
            .init(ignoreComments: true, commentSyntax: nil),
            .init(ignoreComments: false, commentSyntax: .cFamily)
        ]

        for source in roleSources {
            let snapshot = try makeSnapshot(source: source)
            for options in active {
                assertWorkflowError(.reservedTransformMarkerCollision) {
                    try ConflictComparisonWorkflow.prepare(
                        .init(snapshot: snapshot, options: .init(twoWay: options))
                    )
                }
            }
            for options in inactive {
                XCTAssertNoThrow(
                    try ConflictComparisonWorkflow.prepare(
                        .init(snapshot: snapshot, options: .init(twoWay: options))
                    )
                )
            }
        }
    }

    func testDiff3InputBoundsReportExactBaseLeftRightSources() throws {
        let cases: [(source: String, expected: ThreeWayTextMergeSource)] = [
            (diff3Source(mine: "m", base: "bbbb", theirs: "t"), .base),
            (diff3Source(mine: "m", base: "b", theirs: "tttt"), .left),
            (diff3Source(mine: "mmmm", base: "b", theirs: "t"), .right)
        ]
        for testCase in cases {
            let snapshot = try makeSnapshot(source: testCase.source)
            let options = ConflictComparisonOptions(diff3: .init(maximumInputBytes: 2))
            assertWorkflowError(
                .threeWayMerge(.inputTooLarge(source: testCase.expected, maximumBytes: 2))
            ) {
                try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot, options: options))
            }
            XCTAssertNoThrow(
                try ConflictComparisonWorkflow.prepare(
                    .init(
                        snapshot: snapshot,
                        options: .init(diff3: .init(maximumInputBytes: 5))
                    )
                )
            )
        }
    }

    func testDiff3InputLineBoundsReportExactBaseLeftRightSourcesAndAcceptEquality() throws {
        let cases: [(source: String, expected: ThreeWayTextMergeSource)] = [
            (diff3Source(mine: "m", base: "b1\nb2", theirs: "t"), .base),
            (diff3Source(mine: "m", base: "b", theirs: "t1\nt2"), .left),
            (diff3Source(mine: "m1\nm2", base: "b", theirs: "t"), .right)
        ]
        for testCase in cases {
            let snapshot = try makeSnapshot(source: testCase.source)
            assertWorkflowError(
                .threeWayMerge(.tooManyLines(source: testCase.expected, maximumLines: 1))
            ) {
                try ConflictComparisonWorkflow.prepare(
                    .init(
                        snapshot: snapshot,
                        options: .init(diff3: .init(maximumInputLines: 1))
                    )
                )
            }
            XCTAssertNoThrow(
                try ConflictComparisonWorkflow.prepare(
                    .init(
                        snapshot: snapshot,
                        options: .init(diff3: .init(maximumInputLines: 2))
                    )
                )
            )
        }
    }

    func testDiff3OutputByteLineAndRegionBoundsRejectBelowAndAcceptExact() throws {
        let source = diff3Source(mine: "a", base: "a", theirs: "a\nb")
        let snapshot = try makeSnapshot(source: source)
        let exactOutputBytes = "a\nb\n".utf8.count

        assertWorkflowError(.threeWayMerge(.outputTooLarge(maximumBytes: exactOutputBytes - 1))) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: .init(
                        diff3: .init(
                            maximumOutputBytes: exactOutputBytes - 1,
                            maximumOutputLines: 2,
                            maximumRegions: 2
                        )
                    )
                )
            )
        }
        assertWorkflowError(.threeWayMerge(.tooManyOutputLines(maximumLines: 1))) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: .init(
                        diff3: .init(
                            maximumOutputBytes: exactOutputBytes,
                            maximumOutputLines: 1,
                            maximumRegions: 2
                        )
                    )
                )
            )
        }
        assertWorkflowError(.threeWayMerge(.tooManyRegions(maximumRegions: 0))) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: .init(
                        diff3: .init(
                            maximumOutputBytes: exactOutputBytes,
                            maximumOutputLines: 2,
                            maximumRegions: 0
                        )
                    )
                )
            )
        }

        let exact = try ConflictComparisonWorkflow.prepare(
            .init(
                snapshot: snapshot,
                options: .init(
                    diff3: .init(
                        maximumOutputBytes: exactOutputBytes,
                        maximumOutputLines: 2,
                        maximumRegions: 2
                    )
                )
            )
        )
        guard case .diff3(let result) = exact.comparison else {
            return XCTFail("Expected diff3 result")
        }
        XCTAssertEqual(result.merge.mergedText, "a\nb\n")
    }

    func testInvalidLimitMatrixReportsExactLimitField() throws {
        let snapshot = try makeSnapshot()
        let invalid: [(ConflictComparisonLimit, ConflictComparisonLimits)] = [
            (.documentBytes, limits(maximumDocumentBytes: -1)),
            (.roleBytes, limits(maximumRoleBytes: -1)),
            (.combinedRoleBytes, limits(maximumRoleBytes: 2, maximumCombinedRoleBytes: 1)),
            (.sourceIdentityUTF8Bytes, limits(maximumSourceIdentityUTF8Bytes: 0)),
            (.markerLabelUTF8Bytes, limits(maximumMarkerLabelUTF8Bytes: -1)),
            (.optionItems, limits(maximumOptionItems: -1)),
            (.optionStringUTF8Bytes, limits(maximumOptionStringUTF8Bytes: -1)),
            (.totalOptionUTF8Bytes, limits(maximumOptionStringUTF8Bytes: 2, maximumTotalOptionUTF8Bytes: 1)),
            (.conflictCount, limits(maximumConflictCount: 0)),
            (.comparisonItems, limits(maximumComparisonItems: 0)),
            (.totalItems, limits(maximumComparisonItems: 2, maximumTotalItems: 1)),
            (.retainedBytes, limits(maximumRetainedBytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0))
        ]

        for (field, value) in invalid {
            assertWorkflowError(.invalidLimit(field)) {
                try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot, limits: value))
            }
        }
    }

    func testEveryHardMaximumPlusOneReportsItsExactLimitField() throws {
        let snapshot = try makeSnapshot()
        let invalid: [(ConflictComparisonLimit, ConflictComparisonLimits)] = [
            (
                .documentBytes,
                limits(
                    maximumDocumentBytes: ConflictComparisonLimits.hardMaximumDocumentBytes + 1
                )
            ),
            (
                .roleBytes,
                limits(
                    maximumRoleBytes: ConflictComparisonLimits.hardMaximumRoleBytes + 1,
                    maximumCombinedRoleBytes: ConflictComparisonLimits.hardMaximumCombinedRoleBytes
                )
            ),
            (
                .combinedRoleBytes,
                limits(
                    maximumCombinedRoleBytes:
                        ConflictComparisonLimits.hardMaximumCombinedRoleBytes + 1
                )
            ),
            (
                .sourceIdentityUTF8Bytes,
                limits(
                    maximumSourceIdentityUTF8Bytes:
                        ConflictComparisonLimits.hardMaximumSourceIdentityUTF8Bytes + 1
                )
            ),
            (
                .markerLabelUTF8Bytes,
                limits(
                    maximumMarkerLabelUTF8Bytes:
                        ConflictComparisonLimits.hardMaximumMarkerLabelUTF8Bytes + 1
                )
            ),
            (
                .optionItems,
                limits(
                    maximumOptionItems: ConflictComparisonLimits.hardMaximumOptionItems + 1
                )
            ),
            (
                .optionStringUTF8Bytes,
                limits(
                    maximumOptionStringUTF8Bytes:
                        ConflictComparisonLimits.hardMaximumOptionStringUTF8Bytes + 1,
                    maximumTotalOptionUTF8Bytes:
                        ConflictComparisonLimits.hardMaximumTotalOptionUTF8Bytes
                )
            ),
            (
                .totalOptionUTF8Bytes,
                limits(
                    maximumTotalOptionUTF8Bytes:
                        ConflictComparisonLimits.hardMaximumTotalOptionUTF8Bytes + 1
                )
            ),
            (
                .conflictCount,
                limits(
                    maximumConflictCount: ConflictComparisonLimits.hardMaximumConflictCount + 1
                )
            ),
            (
                .comparisonItems,
                limits(
                    maximumComparisonItems:
                        ConflictComparisonLimits.hardMaximumComparisonItems + 1,
                    maximumTotalItems: ConflictComparisonLimits.hardMaximumTotalItems
                )
            ),
            (
                .totalItems,
                limits(
                    maximumTotalItems: ConflictComparisonLimits.hardMaximumTotalItems + 1
                )
            ),
            (
                .retainedBytes,
                limits(
                    maximumRetainedBytes: ConflictComparisonLimits.hardMaximumRetainedBytes + 1
                )
            ),
            (
                .workUnits,
                limits(
                    maximumWorkUnits: ConflictComparisonLimits.hardMaximumWorkUnits + 1
                )
            ),
            (
                .cancellationCheckInterval,
                limits(
                    cancellationCheckInterval:
                        ConflictComparisonLimits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]

        for (field, value) in invalid {
            assertWorkflowError(.invalidLimit(field)) {
                try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot, limits: value))
            }
        }
    }

    func testDocumentRoleCombinedConflictItemMemoryAndWorkLimitsAreIsolated() throws {
        let snapshot = try makeSnapshot()
        let firstRoleCount = snapshot.roleSnapshots[0].text.utf8.count
        let combinedCount = snapshot.roleSnapshots.reduce(0) { $0 + $1.text.utf8.count }
        let maximumRoleCount = snapshot.roleSnapshots.map { $0.text.utf8.count }.max()!
        let totalRecords = snapshot.roleSnapshots.reduce(0) { $0 + $1.text.utf8.filter { $0 == 0x0A }.count }

        assertWorkflowError(.documentTooLarge(maximumBytes: snapshot.documentSourceRevision.utf8ByteCount - 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    limits: limits(maximumDocumentBytes: snapshot.documentSourceRevision.utf8ByteCount - 1)
                )
            )
        }
        assertWorkflowError(.roleTooLarge(role: .theirs, maximumBytes: firstRoleCount - 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, limits: limits(maximumRoleBytes: firstRoleCount - 1))
            )
        }
        assertWorkflowError(.combinedRolesTooLarge(maximumBytes: combinedCount - 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    limits: limits(maximumRoleBytes: maximumRoleCount, maximumCombinedRoleBytes: combinedCount - 1)
                )
            )
        }
        assertWorkflowError(.tooManyConflicts(maximum: 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, limits: limits(maximumConflictCount: 1))
            )
        }
        assertWorkflowError(.tooManyComparisonItems(maximum: 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, limits: limits(maximumComparisonItems: 1))
            )
        }
        assertWorkflowError(.tooManyItems(maximum: totalRecords)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    limits: limits(
                        maximumComparisonItems: totalRecords,
                        maximumTotalItems: totalRecords
                    )
                )
            )
        }
        assertWorkflowError(.retainedDataTooLarge(maximumBytes: 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, limits: limits(maximumRetainedBytes: 1))
            )
        }
        assertWorkflowError(.workLimitExceeded(maximumUnits: 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, limits: limits(maximumWorkUnits: 1))
            )
        }
    }

    func testIdentityLabelAndOptionStringLimitsUseUTF8Bytes() throws {
        let snapshot = try makeSnapshot()
        let documentIdentityBytes = snapshot.documentSourceRevision.identity.value.utf8.count
        assertWorkflowError(.invalidSourceIdentity(nil)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    limits: limits(maximumSourceIdentityUTF8Bytes: documentIdentityBytes - 1)
                )
            )
        }

        let conflict = snapshot.parseResult.conflicts[0]
        let labeledResult = ConflictFileParseResult(
            currentText: snapshot.parseResult.currentText,
            baseText: nil,
            incomingText: snapshot.parseResult.incomingText,
            conflicts: [
                .init(
                    sourceLineRange: conflict.sourceLineRange,
                    markerWidth: conflict.markerWidth,
                    currentLabel: "é",
                    baseLabel: nil,
                    incomingLabel: conflict.incomingLabel
                )
            ]
        )
        assertWorkflowError(.markerLabelTooLarge(maximumBytes: 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: rebuilding(snapshot, parseResult: labeledResult),
                    limits: limits(maximumMarkerLabelUTF8Bytes: 1)
                )
            )
        }

        let option = ConflictComparisonOptions(
            twoWay: .init(lineFilters: [.init(pattern: "é")])
        )
        assertWorkflowError(.optionStringTooLarge(maximumBytes: 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, options: option, limits: limits(maximumOptionStringUTF8Bytes: 1))
            )
        }
        let aggregateOption = ConflictComparisonOptions(
            twoWay: .init(lineFilters: [.init(pattern: "é"), .init(pattern: "é")])
        )
        assertWorkflowError(.optionsTooLarge(maximumBytes: 2)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: aggregateOption,
                    limits: limits(maximumOptionStringUTF8Bytes: 2, maximumTotalOptionUTF8Bytes: 2)
                )
            )
        }
        assertWorkflowError(.tooManyOptionItems(maximum: 2)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: snapshot, options: option, limits: limits(maximumOptionItems: 2))
            )
        }
    }

    func testMultibyteDocumentAndRoleIdentitiesUseExactUTF8Boundaries() throws {
        let snapshot = try makeSnapshot()
        let documentIdentity = ConflictComparisonSourceIdentity(
            namespace: Self.namespaceUUID,
            value: "文"
        )
        let documentRevision = revision(
            text: Self.twoWaySource,
            identity: documentIdentity,
            revision: snapshot.documentSourceRevision.revision
        )
        var roles = snapshot.roleSnapshots
        let original = roles[0]
        roles[0] = .init(
            role: original.role,
            sourceRevision: revision(
                text: original.text,
                identity: .init(namespace: Self.namespaceUUID, value: "役"),
                revision: original.sourceRevision.revision
            ),
            text: original.text
        )
        let mine = roles[1]
        roles[1] = .init(
            role: mine.role,
            sourceRevision: revision(
                text: mine.text,
                identity: .init(namespace: Self.namespaceUUID, value: "m"),
                revision: mine.sourceRevision.revision
            ),
            text: mine.text
        )
        let multibyte = rebuilding(
            snapshot,
            documentSourceRevision: documentRevision,
            parseResultSourceRevision: documentRevision,
            roleSnapshots: roles
        )

        XCTAssertNoThrow(
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: multibyte, limits: limits(maximumSourceIdentityUTF8Bytes: 3))
            )
        )
        assertWorkflowError(.invalidSourceIdentity(nil)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: multibyte, limits: limits(maximumSourceIdentityUTF8Bytes: 2))
            )
        }

        let shortDocument = revision(
            text: Self.twoWaySource,
            identity: .init(namespace: Self.namespaceUUID, value: "d"),
            revision: snapshot.documentSourceRevision.revision
        )
        let roleOnly = rebuilding(
            snapshot,
            documentSourceRevision: shortDocument,
            parseResultSourceRevision: shortDocument,
            roleSnapshots: roles
        )
        assertWorkflowError(.invalidSourceIdentity(.theirs)) {
            try ConflictComparisonWorkflow.prepare(
                .init(snapshot: roleOnly, limits: limits(maximumSourceIdentityUTF8Bytes: 2))
            )
        }
    }

    func testExactResourceLimitsAreAcceptedAndRecorded() throws {
        let snapshot = try makeSnapshot()
        let totalRecords = snapshot.roleSnapshots.reduce(0) { $0 + $1.text.utf8.filter { $0 == 0x0A }.count }
        let preflightRetainedBytes = preflightRetainedByteEstimate(snapshot)
        let exact = limits(
            maximumDocumentBytes: snapshot.documentSourceRevision.utf8ByteCount,
            maximumRoleBytes: snapshot.roleSnapshots.map { $0.text.utf8.count }.max()!,
            maximumCombinedRoleBytes: snapshot.roleSnapshots.reduce(0) { $0 + $1.text.utf8.count },
            maximumConflictCount: snapshot.parseResult.conflicts.count,
            maximumComparisonItems: totalRecords,
            maximumTotalItems: totalRecords * 2 + snapshot.parseResult.conflicts.count,
            maximumRetainedBytes: preflightRetainedBytes,
            maximumWorkUnits: ConflictComparisonLimits.default.maximumWorkUnits,
            cancellationCheckInterval: 1
        )
        let exactPlan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot, limits: exact))

        XCTAssertEqual(exactPlan.limits, exact)
        XCTAssertEqual(exactPlan.receipt.documentUTF8ByteCount, snapshot.documentSourceRevision.utf8ByteCount)
        XCTAssertEqual(exactPlan.receipt.conflictCount, snapshot.parseResult.conflicts.count)
        XCTAssertLessThanOrEqual(exactPlan.comparison.comparisonItemCount, exact.maximumComparisonItems)
        XCTAssertLessThanOrEqual(exactPlan.receipt.retainedByteEstimate, exact.maximumRetainedBytes)
        XCTAssertLessThanOrEqual(exactPlan.receipt.estimatedWorkUnits, exact.maximumWorkUnits)
    }

    func testExactWorkOptionItemAndRetainedEqualityBoundariesSucceedThenRejectOneLess() throws {
        let snapshot = try makeSnapshot()
        let options = ConflictComparisonOptions(
            twoWay: .init(
                lineFilters: [.init(pattern: "nomatch")],
                substitutions: [.init(pattern: "x", replacement: "y")]
            )
        )
        let baseline = try ConflictComparisonWorkflow.prepare(
            .init(snapshot: snapshot, options: options)
        )
        let optionItems = options.twoWay.lineFilters.count + options.twoWay.substitutions.count + 2
        let optionBytes =
            options.twoWay.lineFilters.reduce(0) {
                $0 + $1.pattern.utf8.count
            }
            + options.twoWay.substitutions.reduce(0) {
                $0 + $1.pattern.utf8.count + $1.replacement.utf8.count
            }
        let exactRetainedBytes = preflightRetainedByteEstimate(snapshot)
        let exactLimits = limits(
            maximumOptionItems: optionItems,
            maximumOptionStringUTF8Bytes: "nomatch".utf8.count,
            maximumTotalOptionUTF8Bytes: optionBytes,
            maximumRetainedBytes: exactRetainedBytes,
            maximumWorkUnits: baseline.receipt.estimatedWorkUnits
        )
        let exact = try ConflictComparisonWorkflow.prepare(
            .init(snapshot: snapshot, options: options, limits: exactLimits)
        )
        XCTAssertEqual(exact.receipt.estimatedWorkUnits, exactLimits.maximumWorkUnits)
        XCTAssertEqual(exactLimits.maximumRetainedBytes, preflightRetainedByteEstimate(snapshot))
        XCTAssertLessThanOrEqual(exact.receipt.retainedByteEstimate, exactLimits.maximumRetainedBytes)

        assertWorkflowError(.tooManyOptionItems(maximum: optionItems - 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: options,
                    limits: limits(maximumOptionItems: optionItems - 1)
                )
            )
        }
        assertWorkflowError(.optionsTooLarge(maximumBytes: optionBytes - 1)) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: options,
                    limits: limits(
                        maximumOptionStringUTF8Bytes: "nomatch".utf8.count,
                        maximumTotalOptionUTF8Bytes: optionBytes - 1
                    )
                )
            )
        }
        assertWorkflowError(
            .retainedDataTooLarge(maximumBytes: exactRetainedBytes - 1)
        ) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: options,
                    limits: limits(
                        maximumRetainedBytes: exactRetainedBytes - 1
                    )
                )
            )
        }
        assertWorkflowError(
            .workLimitExceeded(maximumUnits: baseline.receipt.estimatedWorkUnits - 1)
        ) {
            try ConflictComparisonWorkflow.prepare(
                .init(
                    snapshot: snapshot,
                    options: options,
                    limits: limits(
                        maximumWorkUnits: baseline.receipt.estimatedWorkUnits - 1
                    )
                )
            )
        }
    }

    func testPreCancelledTasksMapEveryPublicCheckpointToWorkflowCancellation() async throws {
        let snapshot = try makeSnapshot()
        let plan = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(plan.navigation.first)
        let navigationRequest = ConflictComparisonNavigationRequest(
            state: .init(snapshot: plan.snapshotCAS.reference),
            intent: .command(.first)
        )
        let choose = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
        )
        let apply = try plan.resolutionPlan(
            .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .apply)
        )

        let prepareError = await cancelledWorkflowError {
            _ = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        }
        let navigationError = await cancelledWorkflowError {
            _ = try plan.navigationPlan(navigationRequest)
        }
        let resolutionError = await cancelledWorkflowError {
            _ = try plan.resolutionPlan(
                .init(snapshot: plan.snapshotCAS.reference, targetID: target.id, choice: .mine, action: .choose)
            )
        }
        let validationError = await cancelledWorkflowError {
            try plan.validateCurrentSnapshot(snapshot)
        }
        let choiceAuthorizationError = await cancelledWorkflowError {
            _ = try choose.authorizeChoice(validating: snapshot)
        }
        let applyAuthorizationError = await cancelledWorkflowError {
            _ = try apply.authorizeApply(validating: snapshot)
        }

        XCTAssertEqual(prepareError, .cancelled)
        XCTAssertEqual(navigationError, .cancelled)
        XCTAssertEqual(resolutionError, .cancelled)
        XCTAssertEqual(validationError, .cancelled)
        XCTAssertEqual(choiceAuthorizationError, .cancelled)
        XCTAssertEqual(applyAuthorizationError, .cancelled)
    }

    func testCancellationInterruptsDeterministicallyAfterPlanningStarts() async throws {
        let payload = String(repeating: "x", count: 16 * 1_024 * 1_024)
        let source = twoWaySource(mine: payload, theirs: payload)
        let snapshot = try makeSnapshot(source: source)
        let request = ConflictComparisonRequest(
            snapshot: snapshot,
            limits: limits(
                maximumRoleBytes: payload.utf8.count + 1,
                maximumCombinedRoleBytes: 2 * (payload.utf8.count + 1),
                maximumWorkUnits: ConflictComparisonLimits.hardMaximumWorkUnits,
                cancellationCheckInterval: 1
            )
        )
        let probe = StartProbe()
        let task = Task {
            await probe.markStarted()
            return try ConflictComparisonWorkflow.prepare(request)
        }

        await probe.waitUntilStarted()
        try? await Task.sleep(for: .milliseconds(1))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Mid-planning cancellation unexpectedly returned a plan")
        } catch {
            XCTAssertEqual(error as? ConflictComparisonWorkflowError, .cancelled)
        }
    }

    private struct ApplyFixture: Sendable {
        let plan: ConflictComparisonResolutionPlan
        let permit: ConflictComparisonApplyPermit
    }

    private actor StartProbe {
        private var started = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func markStarted() {
            started = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }

        func waitUntilStarted() async {
            guard !started else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private static let namespaceUUID = uuid("00000000-0000-0000-0000-000000000001")
    private static let snapshotUUID = uuid("00000000-0000-0000-0000-000000000002")
    private static let otherSnapshotUUID = uuid("00000000-0000-0000-0000-000000000003")

    private static let twoWaySource =
        [
            "before",
            "<<<<<<< mine-one",
            "mine one",
            "=======",
            "theirs one",
            ">>>>>>> theirs-one",
            "between",
            "<<<<<<< mine-two",
            "mine two",
            "=======",
            "theirs two",
            ">>>>>>> theirs-two",
            "after"
        ].joined(separator: "\n") + "\n"

    private static let diff3Source =
        [
            "before",
            "<<<<<<< mine-one",
            "mine one",
            "||||||| base-one",
            "base one",
            "=======",
            "theirs one",
            ">>>>>>> theirs-one",
            "between",
            "<<<<<<< mine-two",
            "mine two",
            "||||||| base-two",
            "base two",
            "=======",
            "theirs two",
            ">>>>>>> theirs-two",
            "after"
        ].joined(separator: "\n") + "\n"

    private static let substitutionSource =
        [
            "<<<<<<< mine", "version=2", "=======", "version=1", ">>>>>>> theirs"
        ].joined(separator: "\n") + "\n"

    private func makeSnapshot(
        source: String = ConflictComparisonWorkflowTests.twoWaySource,
        identity: ConflictComparisonSnapshotIdentity = .init(
            rawValue: ConflictComparisonWorkflowTests.snapshotUUID
        ),
        generation: UInt64 = 42,
        isReadOnly: Bool = false,
        capabilities: ConflictComparisonCapability = .all
    ) throws -> ConflictComparisonParsedDocumentSnapshot {
        let parseResult = try ConflictFileParser.parse(source)
        let documentRevision = revision(
            text: source,
            identity: .init(namespace: Self.namespaceUUID, value: "document"),
            revision: 7
        )
        var roles: [ConflictComparisonRoleSnapshot] = []
        if let base = parseResult.baseText {
            roles.append(roleSnapshot(.base, text: base))
        }
        roles.append(roleSnapshot(.theirs, text: parseResult.incomingText))
        roles.append(roleSnapshot(.mine, text: parseResult.currentText))
        return ConflictComparisonParsedDocumentSnapshot(
            identity: identity,
            generation: generation,
            documentSourceRevision: documentRevision,
            parseResultSourceRevision: documentRevision,
            parseResult: parseResult,
            roleSnapshots: roles,
            isReadOnly: isReadOnly,
            capabilities: capabilities
        )
    }

    private func rebuilding(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot,
        identity: ConflictComparisonSnapshotIdentity? = nil,
        generation: UInt64? = nil,
        documentSourceRevision: ConflictComparisonSourceRevision? = nil,
        parseResultSourceRevision: ConflictComparisonSourceRevision? = nil,
        parseResult: ConflictFileParseResult? = nil,
        roleSnapshots: [ConflictComparisonRoleSnapshot]? = nil,
        isReadOnly: Bool? = nil,
        capabilities: ConflictComparisonCapability? = nil
    ) -> ConflictComparisonParsedDocumentSnapshot {
        ConflictComparisonParsedDocumentSnapshot(
            identity: identity ?? snapshot.identity,
            generation: generation ?? snapshot.generation,
            documentSourceRevision: documentSourceRevision ?? snapshot.documentSourceRevision,
            parseResultSourceRevision: parseResultSourceRevision ?? snapshot.parseResultSourceRevision,
            parseResult: parseResult ?? snapshot.parseResult,
            roleSnapshots: roleSnapshots ?? snapshot.roleSnapshots,
            isReadOnly: isReadOnly ?? snapshot.isReadOnly,
            capabilities: capabilities ?? snapshot.capabilities
        )
    }

    private func roleSnapshot(
        _ role: ConflictComparisonRole,
        text: String,
        revision revisionNumber: UInt64? = nil
    ) -> ConflictComparisonRoleSnapshot {
        let number = revisionNumber ?? roleRevisionNumber(role)
        return ConflictComparisonRoleSnapshot(
            role: role,
            sourceRevision: revision(
                text: text,
                identity: .init(namespace: Self.namespaceUUID, value: "role.\(role.rawValue)"),
                revision: number
            ),
            text: text
        )
    }

    private func roleRevisionNumber(_ role: ConflictComparisonRole) -> UInt64 {
        switch role {
        case .base: 10
        case .theirs: 11
        case .mine: 12
        }
    }

    private func revision(
        text: String,
        identity: ConflictComparisonSourceIdentity,
        revision: UInt64
    ) -> ConflictComparisonSourceRevision {
        ConflictComparisonSourceRevision(
            identity: identity,
            revision: revision,
            utf8ByteCount: text.utf8.count,
            contentSHA256: Array(SHA256.hash(data: Data(text.utf8)))
        )
    }

    private func navigation(
        _ plan: ConflictComparisonPlan,
        state: ConflictComparisonSelectionState,
        intent: ConflictComparisonSelectionIntent
    ) throws -> ConflictComparisonNavigationPlan {
        try plan.navigationPlan(.init(state: state, intent: intent))
    }

    private func applyFixture(
        choice: ConflictComparisonResolutionChoice = .mine
    ) throws -> ApplyFixture {
        let snapshot = try makeSnapshot()
        let comparison = try ConflictComparisonWorkflow.prepare(.init(snapshot: snapshot))
        let target = try XCTUnwrap(comparison.navigation.first)
        let plan = try comparison.resolutionPlan(
            .init(
                snapshot: comparison.snapshotCAS.reference,
                targetID: target.id,
                choice: choice,
                action: .apply
            )
        )
        return ApplyFixture(plan: plan, permit: try plan.authorizeApply(validating: snapshot))
    }

    private func validSuccessor(
        for plan: ConflictComparisonResolutionPlan
    ) -> ConflictComparisonAppliedSuccessor {
        ConflictComparisonAppliedSuccessor(
            snapshot: .init(
                identity: plan.snapshotCAS.reference.identity,
                generation: plan.snapshotCAS.reference.generation + 1
            ),
            documentSourceRevision: revision(
                text: "resolved\n",
                identity: plan.documentSourceRevision.identity,
                revision: plan.documentSourceRevision.revision + 1
            )
        )
    }

    private func diff3Source(mine: String, base: String, theirs: String) -> String {
        [
            "<<<<<<< mine", mine, "||||||| base", base, "=======", theirs, ">>>>>>> theirs"
        ].joined(separator: "\n") + "\n"
    }

    private func twoWaySource(mine: String, theirs: String) -> String {
        [
            "<<<<<<< mine", mine, "=======", theirs, ">>>>>>> theirs"
        ].joined(separator: "\n") + "\n"
    }

    private func conflict(
        _ conflict: ConflictFileConflict,
        sourceLineRange: ClosedRange<Int>
    ) -> ConflictFileConflict {
        ConflictFileConflict(
            sourceLineRange: sourceLineRange,
            markerWidth: conflict.markerWidth,
            currentLabel: conflict.currentLabel,
            baseLabel: conflict.baseLabel,
            incomingLabel: conflict.incomingLabel,
            hasCurrentContent: conflict.hasCurrentContent,
            hasBaseContent: conflict.hasBaseContent,
            hasIncomingContent: conflict.hasIncomingContent
        )
    }

    private func comparisonDifferenceCount(
        snapshot: ConflictComparisonParsedDocumentSnapshot,
        options: LineDiffOptions
    ) throws -> Int {
        let plan = try ConflictComparisonWorkflow.prepare(
            .init(snapshot: snapshot, options: .init(twoWay: options))
        )
        guard case .twoWay(let result) = plan.comparison else {
            XCTFail("Expected two-way result")
            return 0
        }
        return result.rows.filter { $0.kind != .unchanged }.count
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func preflightRetainedByteEstimate(
        _ snapshot: ConflictComparisonParsedDocumentSnapshot
    ) -> Int {
        let combinedRoleBytes = snapshot.roleSnapshots.reduce(0) { $0 + $1.text.utf8.count }
        let totalRecords = snapshot.roleSnapshots.reduce(0) { $0 + $1.text.utf8.filter { $0 == 0x0A }.count }
        let markerLabelBytes = snapshot.parseResult.conflicts.reduce(0) { result, conflict in
            result
                + (conflict.currentLabel?.utf8.count ?? 0)
                + (conflict.baseLabel?.utf8.count ?? 0)
                + (conflict.incomingLabel?.utf8.count ?? 0)
        }
        let sourceIdentityBytes = snapshot.roleSnapshots.reduce(
            snapshot.documentSourceRevision.identity.value.utf8.count
        ) { result, role in
            result + role.sourceRevision.identity.value.utf8.count
        }
        return (snapshot.roleSnapshots.count + 1) * 256
            + snapshot.parseResult.conflicts.count * 256
            + combinedRoleBytes
            + markerLabelBytes
            + sourceIdentityBytes
            + totalRecords * 192
    }

    private func limits(
        maximumDocumentBytes: Int = ConflictComparisonLimits.default.maximumDocumentBytes,
        maximumRoleBytes: Int = ConflictComparisonLimits.default.maximumRoleBytes,
        maximumCombinedRoleBytes: Int = ConflictComparisonLimits.default.maximumCombinedRoleBytes,
        maximumSourceIdentityUTF8Bytes: Int = ConflictComparisonLimits.default.maximumSourceIdentityUTF8Bytes,
        maximumMarkerLabelUTF8Bytes: Int = ConflictComparisonLimits.default.maximumMarkerLabelUTF8Bytes,
        maximumOptionItems: Int = ConflictComparisonLimits.default.maximumOptionItems,
        maximumOptionStringUTF8Bytes: Int = ConflictComparisonLimits.default.maximumOptionStringUTF8Bytes,
        maximumTotalOptionUTF8Bytes: Int = ConflictComparisonLimits.default.maximumTotalOptionUTF8Bytes,
        maximumConflictCount: Int = ConflictComparisonLimits.default.maximumConflictCount,
        maximumComparisonItems: Int = ConflictComparisonLimits.default.maximumComparisonItems,
        maximumTotalItems: Int = ConflictComparisonLimits.default.maximumTotalItems,
        maximumRetainedBytes: Int = ConflictComparisonLimits.default.maximumRetainedBytes,
        maximumWorkUnits: UInt64 = ConflictComparisonLimits.default.maximumWorkUnits,
        cancellationCheckInterval: Int = ConflictComparisonLimits.default.cancellationCheckInterval
    ) -> ConflictComparisonLimits {
        ConflictComparisonLimits(
            maximumDocumentBytes: maximumDocumentBytes,
            maximumRoleBytes: maximumRoleBytes,
            maximumCombinedRoleBytes: maximumCombinedRoleBytes,
            maximumSourceIdentityUTF8Bytes: maximumSourceIdentityUTF8Bytes,
            maximumMarkerLabelUTF8Bytes: maximumMarkerLabelUTF8Bytes,
            maximumOptionItems: maximumOptionItems,
            maximumOptionStringUTF8Bytes: maximumOptionStringUTF8Bytes,
            maximumTotalOptionUTF8Bytes: maximumTotalOptionUTF8Bytes,
            maximumConflictCount: maximumConflictCount,
            maximumComparisonItems: maximumComparisonItems,
            maximumTotalItems: maximumTotalItems,
            maximumRetainedBytes: maximumRetainedBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func assertWorkflowError<T>(
        _ expected: ConflictComparisonWorkflowError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ConflictComparisonWorkflowError, expected, file: file, line: line)
        }
    }

    private func assertInvalidPlan(
        _ outcome: ConflictComparisonExecutionOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFailure(outcome, code: .invalidPlan, file: file, line: line)
    }

    private func assertFailure(
        _ outcome: ConflictComparisonExecutionOutcome,
        code: ConflictComparisonExecutionFailureCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failed(let failure) = outcome else {
            return XCTFail("Expected failure, got \(outcome)", file: file, line: line)
        }
        XCTAssertEqual(failure.code, code, file: file, line: line)
    }

    private func cancelledWorkflowError(
        _ operation: @escaping @Sendable () throws -> Void
    ) async -> ConflictComparisonWorkflowError? {
        let task = Task { () -> ConflictComparisonWorkflowError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try operation()
                return nil
            } catch {
                return error as? ConflictComparisonWorkflowError
            }
        }
        return await task.value
    }

    private static func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
