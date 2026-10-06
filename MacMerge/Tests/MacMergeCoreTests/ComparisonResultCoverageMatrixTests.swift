import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ComparisonResultCoverageMatrixTests: XCTestCase {
    private typealias Matrix = ComparisonResultCoverageMatrix
    private typealias State = ComparisonLifecycleState

    func testCanonicalScenarioInventoryAndIndependentSemanticMatrix() throws {
        let scenarios: [ComparisonResultScenario] = [
            .identical,
            .differentWithoutSelection,
            .firstSelectedAtStart,
            .middleSelectedAtStart,
            .lastSelectedAtEnd,
            .cursorAtDifferenceStart,
            .cursorAtDifferenceEnd,
            .cursorBeforeFirstDifference,
            .cursorAfterLastDifference,
            .selectionVisibleWithoutCursor,
            .selectionVisibleWithCursorOnOtherDifference,
            .selectionVisibleWithCursorOnUnchangedRow,
            .selectionOffscreenWithCursorBefore,
            .selectionOffscreenWithCursorAfter,
            .selectionOffscreenWithoutCursor,
            .cursorBetweenDifferences
        ]
        XCTAssertEqual(Matrix.canonicalScenarios, scenarios)
        XCTAssertEqual(ComparisonResultScenario.allCases, scenarios)
        XCTAssertEqual(scenarios.map(\.rawValue), Array(0...15))
        XCTAssertEqual(scenarios.map(\.id.rawValue), Array(0...15))
        XCTAssertEqual(Matrix.reportFormatVersion, 3)
        XCTAssertEqual(Matrix.canonicalMatrixRevision, 3)

        let states = try scenarios.map(canonicalState)
        XCTAssertEqual(states.map(\.outcome), [.identical] + Array(repeating: .different, count: 15))
        XCTAssertEqual(states.map(\.differences.count), [0, 1] + Array(repeating: 3, count: 14))
        XCTAssertEqual(
            states.map(\.selectionVisibility),
            [
                .notApplicable, .notApplicable, .visible, .visible, .visible,
                .notApplicable, .notApplicable, .notApplicable, .notApplicable,
                .visible, .visible, .visible, .offscreen, .offscreen, .offscreen,
                .notApplicable
            ]
        )
        XCTAssertEqual(states[2].selectedDifference?.ordinal, 0)
        XCTAssertEqual(states[2].cursor.rowIndex, 2)
        XCTAssertEqual(states[3].selectedDifference?.ordinal, 1)
        XCTAssertEqual(states[3].cursor.rowIndex, 7)
        XCTAssertEqual(states[4].selectedDifference?.ordinal, 2)
        XCTAssertEqual(states[4].cursor.rowIndex, 14)
        XCTAssertEqual(states[9].cursor, .none)
        XCTAssertNotEqual(states[10].selection.differenceID, states[10].cursor.differenceID)
        XCTAssertNil(states[11].cursor.differenceID)
        XCTAssertEqual(states[11].cursor.rowIndex, 5)
        XCTAssertLessThan(try XCTUnwrap(states[12].cursor.rowIndex), try XCTUnwrap(states[12].selectedDifference?.firstRow))
        XCTAssertGreaterThan(try XCTUnwrap(states[13].cursor.rowIndex), try XCTUnwrap(states[13].selectedDifference?.lastRow))
        XCTAssertEqual(states[14].cursor, .none)
        XCTAssertEqual(states[15].cursor.rowIndex, 5)
        XCTAssertTrue(states[15].commandState.navigation.previous)
        XCTAssertTrue(states[15].commandState.navigation.next)
        XCTAssertFalse(states[15].commandState.hasResolvableDifference)
    }

    func testNavigationCommandsAreExactForEveryCanonicalScenario() throws {
        let expected: [ComparisonResultNavigationCommandState] = [
            navigation(false, false, false, false, false),
            navigation(true, false, true, true, true),
            navigation(true, true, false, true, true),
            navigation(true, true, true, true, true),
            navigation(true, true, true, false, true),
            navigation(true, true, true, true, true),
            navigation(true, true, true, true, true),
            navigation(true, false, false, true, true),
            navigation(true, false, true, false, true),
            navigation(true, true, true, true, true),
            navigation(true, true, true, true, true),
            navigation(true, true, true, true, true),
            navigation(true, true, false, true, true),
            navigation(true, true, true, false, true),
            navigation(true, true, true, true, true),
            navigation(true, false, true, true, true)
        ]
        let states = try Matrix.canonicalScenarios.map(canonicalState)
        XCTAssertEqual(states.map(\.commandState.navigation), expected)
        XCTAssertEqual(states.map(\.commandState.hasSignificantDifferences), [false] + Array(repeating: true, count: 15))
        XCTAssertEqual(
            states.map(\.commandState.hasResolvableDifference),
            [false, false, true, true, true, true, true, false, false, true, true, true, true, true, true, false]
        )
    }

    func testEveryCanonicalScenarioRejectsAValidOnePredicateNearMiss() throws {
        let issuer = try authority(0x10)
        let lifecycle = try issuer.authenticateCurrentLifecycle(makeCurrentState(LifecycleSpec(seed: 1)))
        for scenario in Matrix.canonicalScenarios {
            assertCoverageError(.invalidScenarioRequirement) {
                try ComparisonResultCoverageRequirement(
                    scenario: scenario,
                    lifecycle: lifecycle,
                    expected: scenarioNearMiss(scenario)
                )
            }
        }
    }

    func testEmptyVisibleRowsCannotClaimVisibleSelection() throws {
        let differences = try standardDifferences()
        let state = try semanticState(
            differences: differences,
            selection: .difference(differences[0].id),
            cursor: .none,
            alignedRows: 18,
            visibleRows: 2..<2,
            command: command(true, true, true, true)
        )
        XCTAssertTrue(state.viewport.visibleRows.isEmpty)
        XCTAssertEqual(state.selectionVisibility, .offscreen)

        let issuer = try authority(0x11)
        let lifecycle = try issuer.authenticateCurrentLifecycle(makeCurrentState(LifecycleSpec(seed: 1)))
        assertCoverageError(.invalidScenarioRequirement) {
            try ComparisonResultCoverageRequirement(
                scenario: .selectionVisibleWithoutCursor,
                lifecycle: lifecycle,
                expected: state
            )
        }
    }

    func testSelectionVisibilityUsesHalfOpenOverlapBoundaries() throws {
        let difference = try difference("selected", 0, 4..<7)
        for visibleRows in [0..<4, 7..<10] {
            let state = try semanticState(
                differences: [difference],
                selection: .difference(difference.id),
                alignedRows: 10,
                visibleRows: visibleRows,
                command: command(true, true, true, true)
            )
            XCTAssertEqual(state.selectionVisibility, .offscreen)
        }
        for visibleRows in [3..<5, 6..<8] {
            let state = try semanticState(
                differences: [difference],
                selection: .difference(difference.id),
                alignedRows: 10,
                visibleRows: visibleRows,
                command: command(true, true, false, false)
            )
            XCTAssertEqual(state.selectionVisibility, .visible)
        }
    }

    func testDifferenceViewportAndCursorBoundariesAreSafeAtIntExtremes() throws {
        let maximumRows = ComparisonResultCoverageLimits.hardMaximumRows
        let last = try ComparisonResultDifference(
            id: stable("last-row"),
            ordinal: Int.max,
            rowRange: (maximumRows - 1)..<maximumRows
        )
        XCTAssertEqual(last.ordinal, Int.max)
        XCTAssertEqual(last.firstRow, maximumRows - 1)
        XCTAssertEqual(last.lastRow, maximumRows - 1)
        XCTAssertEqual(
            try ComparisonResultViewportState(
                alignedRowCount: maximumRows,
                visibleRows: maximumRows..<maximumRows
            ).visibleRows,
            maximumRows..<maximumRows
        )

        let invalidDifferences: [(Int, Range<Int>)] = [
            (-1, 0..<1),
            (0, -1..<1),
            (0, 0..<0),
            (0, maximumRows..<maximumRows),
            (0, maximumRows..<(maximumRows + 1)),
            (0, Int.min..<Int.max)
        ]
        for (ordinal, range) in invalidDifferences {
            assertCoverageError(.invalidSemanticState) {
                try ComparisonResultDifference(id: stable("boundary"), ordinal: ordinal, rowRange: range)
            }
        }
        assertCoverageError(.invalidSemanticState) {
            try ComparisonResultDifference(id: stable("bad id"), ordinal: 0, rowRange: 0..<1)
        }

        let invalidViewports: [(Int, Range<Int>)] = [
            (-1, 0..<0),
            (Int.max, 0..<0),
            (1, -1..<0),
            (1, 0..<2),
            (maximumRows, maximumRows..<(maximumRows + 1)),
            (maximumRows, Int.min..<Int.max)
        ]
        for (rows, visible) in invalidViewports {
            assertCoverageError(.invalidSemanticState) {
                try ComparisonResultViewportState(alignedRowCount: rows, visibleRows: visible)
            }
        }

        let difference = try ComparisonResultDifference(id: stable("only"), ordinal: 0, rowRange: 0..<1)
        for cursor in [Int.min, -1, 1, Int.max] {
            assertCoverageError(.invalidSemanticState) {
                try semanticState(
                    differences: [difference],
                    cursor: .row(index: cursor, differenceID: nil),
                    alignedRows: 1,
                    visibleRows: 0..<1,
                    command: command(true, false, false, true)
                )
            }
        }
    }

    func testSemanticStateRejectsEveryMalformedDifferenceSelectionAndCursorRelation() throws {
        let valid = try difference("valid", 0, 2..<4)
        let malformedDifferences: [[ComparisonResultDifference]] = [
            [try difference("gap", 1, 2..<4)],
            [valid, try difference("overlap", 1, 3..<5)],
            [valid, try difference("valid", 1, 5..<6)],
            [try difference("beyond", 0, 4..<6)]
        ]
        for differences in malformedDifferences {
            assertCoverageError(.invalidSemanticState) {
                try semanticState(
                    differences: differences,
                    alignedRows: 5,
                    visibleRows: 0..<5,
                    command: command(true, false, true, true)
                )
            }
        }
        assertCoverageError(.invalidSemanticState) {
            try semanticState(
                differences: [valid],
                selection: .difference(stable("unknown")),
                alignedRows: 5,
                visibleRows: 0..<5,
                command: command(true, true, true, true)
            )
        }
        assertCoverageError(.invalidSemanticState) {
            try semanticState(
                differences: [valid],
                cursor: .row(index: 2, differenceID: nil),
                alignedRows: 5,
                visibleRows: 0..<5,
                command: command(true, false, true, true)
            )
        }
        assertCoverageError(.invalidSemanticState) {
            try semanticState(
                differences: [valid],
                cursor: .row(index: 0, differenceID: valid.id),
                alignedRows: 5,
                visibleRows: 0..<5,
                command: command(true, true, false, true)
            )
        }
    }

    func testLifecycleAuthenticationRequiresExactCurrentResultAndBindsEveryIdentityAndGeneration() throws {
        let issuer = try authority(0x31)
        let spec = LifecycleSpec(
            seed: 20,
            inputGeneration: 21,
            leftGeneration: 22,
            rightGeneration: 23
        )
        let current = try makeCurrentState(spec)
        let token = try issuer.authenticateCurrentLifecycle(current)
        let binding = token.binding
        XCTAssertEqual(binding.comparisonIdentity, comparisonIdentity(spec.seed))
        XCTAssertEqual(binding.comparisonGeneration, 2)
        XCTAssertEqual(binding.inputIdentity, inputIdentity(spec.seed + 1))
        XCTAssertEqual(binding.inputGeneration, 21)
        XCTAssertEqual(binding.operationID, operationID(spec.seed + 4))
        XCTAssertEqual(binding.operationStartedAtGeneration, 1)
        XCTAssertEqual(binding.resultIdentity, resultID(spec.seed + 5))
        XCTAssertEqual(binding.resultGeneration, 2)
        XCTAssertEqual(binding.sources.map(\.side), [.left, .right])
        XCTAssertEqual(binding.sources.map(\.identity), [sideIdentity(spec.seed + 2), sideIdentity(spec.seed + 3)])
        XCTAssertEqual(binding.sources.map(\.generation), [22, 23])

        let empty = try State(identity: comparisonIdentity(100))
        assertCoverageError(.comparisonNotCurrent) {
            try issuer.authenticateCurrentLifecycle(empty)
        }
        let loading = try beginLoading(empty, inputs: makeInputs(LifecycleSpec(seed: 100)))
        assertCoverageError(.comparisonNotCurrent) {
            try issuer.authenticateCurrentLifecycle(loading)
        }
        let staleInputs = try makeInputs(LifecycleSpec(seed: 100, inputGeneration: 1))
        let stale = try current.applying(
            .markStale(expected: current.fingerprint, currentInputs: staleInputs, reason: .optionsChanged)
        )
        assertCoverageError(.comparisonNotCurrent) {
            try issuer.authenticateCurrentLifecycle(stale)
        }
    }

    func testComparisonBindingCanonicalizesSourcesAndRejectsMalformedLayouts() throws {
        let left = source(.left, identity: 1, generation: 11)
        let middle = source(.middle, identity: 2, generation: 12)
        let right = source(.right, identity: 3, generation: 13)
        let twoWay = try binding(sources: [right, left])
        XCTAssertEqual(twoWay.sources, [left, right])
        let threeWay = try binding(sources: [right, left, middle])
        XCTAssertEqual(threeWay.sources, [left, middle, right])

        for sources in [[], [left], [left, middle], [middle, right], [left, left], [left, middle, right, left]] {
            assertCoverageError(.invalidComparisonBinding) {
                try binding(sources: sources)
            }
        }
    }

    func testCompleteSignedMeasuredFixtureBindsCollectorBuildInventoryCaptureAndAccessibility() throws {
        let fixture = try makeFixture()
        let result = try audit(fixture)
        let count = Matrix.canonicalScenarios.count
        XCTAssertEqual(result.report.formatVersion, 3)
        XCTAssertEqual(result.report.inventory, fixture.inventory.reference)
        XCTAssertEqual(result.report.evidence, fixture.evidence.reference)
        XCTAssertEqual(result.report.trustedAuditTimeUnixMilliseconds, fixture.auditTime)
        XCTAssertEqual(result.report.matrix.requiredCount, count)
        XCTAssertEqual(result.report.matrix.completeCount, count)
        XCTAssertEqual(result.report.matrix.cells.map(\.scenario), Matrix.canonicalScenarios)
        XCTAssertEqual(result.report.matrix.cells.map(\.status), Array(repeating: .complete, count: count))
        XCTAssertEqual(result.report.matrix.cells.map(\.evidenceCount), Array(repeating: 1, count: count))
        XCTAssertEqual(result.report.findings, [])
        XCTAssertNil(result.report.highestSeverity)
        XCTAssertFalse(result.report.containsErrors)
        XCTAssertTrue(result.report.isCompleteAndValid)
        XCTAssertEqual(result.receipt.formatVersion, 3)
        XCTAssertEqual(result.receipt.build, fixture.inventory.build)
        XCTAssertEqual(result.receipt.inventory, fixture.inventory.reference)
        XCTAssertEqual(result.receipt.evidence, fixture.evidence.reference)
        XCTAssertEqual(result.receipt.requiredScenarioCount, count)
        XCTAssertEqual(result.receipt.completeScenarioCount, count)
        XCTAssertEqual(result.receipt.measuredProductionEvidenceCount, count)
        XCTAssertEqual(result.receipt.callerAssertionCount, 0)
        XCTAssertEqual(result.receipt.findingCount, 0)
        XCTAssertGreaterThan(result.receipt.workUnits, 1_000)
        XCTAssertTrue(result.receipt.recordsCompleteProductionCoverage)
        XCTAssertEqual(result.receipt.inventorySHA256.count, SHA256.byteCount)
        XCTAssertEqual(result.receipt.evidenceSHA256.count, SHA256.byteCount)
        XCTAssertEqual(result.receipt.auditPolicySHA256.count, SHA256.byteCount)
        XCTAssertEqual(result.receipt.reportSHA256.count, SHA256.byteCount)
        XCTAssertNotEqual(result.receipt.inventorySHA256, result.receipt.evidenceSHA256)
        XCTAssertNotEqual(result.receipt.evidenceSHA256, result.receipt.reportSHA256)

        let firstRequirement = try XCTUnwrap(fixture.inventory.requirements.first)
        let firstObservation = try XCTUnwrap(fixture.evidence.observations.first)
        let requirementToken = try XCTUnwrap(firstRequirement.accessibility?.token)
        let evidenceToken = try XCTUnwrap(firstObservation.accessibility)
        XCTAssertEqual(evidenceToken.app, requirementToken.app)
        XCTAssertEqual(evidenceToken.build, requirementToken.build)
        XCTAssertEqual(evidenceToken.buildArtifactSHA256, fixture.inventory.buildArtifactSHA256)
        XCTAssertEqual(evidenceToken.buildSigningIdentitySHA256, requirementToken.buildSigningIdentitySHA256)
        XCTAssertEqual(evidenceToken.inventory, requirementToken.inventory)
        XCTAssertEqual(evidenceToken.evidence, requirementToken.evidence)
        XCTAssertEqual(evidenceToken.scenario, requirementToken.scenario)
        XCTAssertEqual(evidenceToken.snapshotID, requirementToken.snapshotID)
        XCTAssertTrue(evidenceToken.recordsCompleteEvidence)
    }

    func testIndependentGoldenDigestAndWorkVectorsPinCanonicalEncoding() throws {
        let fixture = try makeFixture(includesAccessibility: false)
        let result = try audit(
            fixture,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertEqual(hex(result.receipt.inventorySHA256), "1124667e0096a3cfed62a0291d5059b692145d854e2ef57e73728bcc493268dd")
        XCTAssertEqual(hex(result.receipt.evidenceSHA256), "eea24a7f5f110bf43c3fd12f824a6a32291633a3a8f3e6aa5604bbf12a78119d")
        XCTAssertEqual(hex(result.receipt.auditPolicySHA256), "38414ea33e76be6a2dfcadc27cddf31e0b6c140db9f4809c5a9a20b4aba69142")
        XCTAssertEqual(hex(result.receipt.reportSHA256), "b68bda89e185149a4976d4d8bfec97254285d0df9110e20c06baf48923e107cc")
        XCTAssertEqual(result.receipt.workUnits, 30_428)
        XCTAssertEqual(
            hex(sha256(try Matrix.canonicalCaptureData(for: fixture.evidence.observations[0]))),
            "629b5a764c6354cc4120307d86ddbd222b9a14204ac85bedd629ad4e1e7bb093"
        )
        XCTAssertEqual(
            hex(sha256(try Matrix.canonicalCaptureEnvelopeData(for: fixture.evidence.observations[0]))),
            "bab8c5d3fcbb7bb439b71f60aec3429895249448efe8863ff38388a00b9d7c66"
        )
    }

    func testCanonicalInventoryDigestAndCallerOrderAreDeterministic() throws {
        let fixture = try makeFixture()
        let baseline = try audit(fixture, policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime))
        let reversedInventory = ComparisonResultCoverageInventory(
            reference: fixture.inventory.reference,
            build: fixture.inventory.build,
            buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
            requirements: fixture.inventory.requirements.reversed()
        )
        let reversedEvidence = ComparisonResultEvidenceBundle(
            reference: fixture.evidence.reference,
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: fixture.evidence.observations.reversed()
        )
        let reordered = try Matrix.audit(
            inventory: reversedInventory,
            evidence: reversedEvidence,
            verifier: fixture.verifier,
            auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: resolver(fixture.captures),
            cancellationCheck: { false }
        )
        XCTAssertEqual(baseline.receipt.inventorySHA256, fixture.inventoryDigest)
        XCTAssertEqual(reordered.report, baseline.report)
        XCTAssertEqual(reordered.receipt, baseline.receipt)
        XCTAssertEqual(reordered.receipt.inventorySHA256, baseline.receipt.inventorySHA256)
        XCTAssertEqual(reordered.receipt.evidenceSHA256, baseline.receipt.evidenceSHA256)
        XCTAssertEqual(reordered.receipt.reportSHA256, baseline.receipt.reportSHA256)
    }

    func testInventoryRejectsMissingDuplicateAndWrongScenarioRequirementsAndCanonicalMaps() throws {
        let fixture = try makeFixture()
        let requirements = fixture.inventory.requirements
        let invalidLists = [
            Array(requirements.dropLast()),
            Array(requirements.dropLast()) + [requirements[0]]
        ]
        for invalid in invalidLists {
            let inventory = ComparisonResultCoverageInventory(
                reference: fixture.inventory.reference,
                build: fixture.inventory.build,
                buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
                requirements: invalid
            )
            assertCoverageError(.invalidInventory(.inventoryRequirements)) {
                try Matrix.audit(
                    inventory: inventory,
                    evidence: fixture.evidence,
                    verifier: fixture.verifier,
                    auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                    captureResolver: resolver(fixture.captures),
                    cancellationCheck: { false }
                )
            }
        }
        let incomplete = Dictionary(uniqueKeysWithValues: requirements.dropLast().map { ($0.scenario, $0) })
        assertCoverageError(.invalidInventory(.inventoryRequirements)) {
            try ComparisonResultCoverageInventory.canonical(
                reference: fixture.inventory.reference,
                build: fixture.inventory.build,
                buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
                requirementsByScenario: incomplete
            )
        }
        var wrongScenario = Dictionary(uniqueKeysWithValues: requirements.map { ($0.scenario, $0) })
        wrongScenario[.identical] = requirements[1]
        assertCoverageError(.invalidInventory(.inventoryRequirements)) {
            try ComparisonResultCoverageInventory.canonical(
                reference: fixture.inventory.reference,
                build: fixture.inventory.build,
                buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
                requirementsByScenario: wrongScenario
            )
        }
    }

    func testAtomicReplayClaimRejectsWholeBatchAndValidationIsIdempotent() throws {
        let ledger = ReplayLedger()
        let fixture = try makeFixture(ledger: ledger)
        let result = try audit(fixture)
        XCTAssertEqual(ledger.invocationCount, 1)
        XCTAssertEqual(ledger.claimedCount, Matrix.canonicalScenarios.count)
        XCTAssertEqual(ledger.lastPolicy, replayReference())
        XCTAssertEqual(Set(ledger.lastClaims.map(\.nonce)), Set(fixture.evidence.observations.compactMap(\.provenance?.runNonce)))

        assertCoverageError(.replayClaimRejected) {
            try audit(fixture)
        }
        XCTAssertEqual(ledger.invocationCount, 2)
        XCTAssertEqual(ledger.claimedCount, Matrix.canonicalScenarios.count)

        let validationLedger = ReplayLedger()
        let validationPolicy = policy(ledger: validationLedger, auditTime: fixture.auditTime)
        XCTAssertNoThrow(
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                verifier: fixture.verifier,
                auditPolicy: validationPolicy,
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        )
        XCTAssertNoThrow(
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                verifier: fixture.verifier,
                auditPolicy: validationPolicy,
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        )
        XCTAssertEqual(validationLedger.invocationCount, 0)
        XCTAssertEqual(validationLedger.claimedCount, 0)
    }

    func testReplayRejectsDuplicateMixedAndCrossPolicyBatchesWithoutPartialClaims() throws {
        let duplicateLedger = ReplayLedger()
        let duplicateFixture = try makeFixture(ledger: duplicateLedger)
        let firstNonce = try XCTUnwrap(duplicateFixture.evidence.observations[0].provenance).runNonce
        let duplicateNonceObservation = try resign(
            duplicateFixture.evidence.observations[1],
            fixture: duplicateFixture,
            nonce: firstNonce
        )
        assertCoverageError(.replayClaimRejected) {
            try audit(replacing(duplicateFixture, observationAt: 1, with: duplicateNonceObservation))
        }
        XCTAssertEqual(duplicateLedger.invocationCount, 0)
        XCTAssertEqual(duplicateLedger.claimedCount, 0)

        let mixedLedger = ReplayLedger()
        let mixedFixture = try makeFixture(ledger: mixedLedger)
        XCTAssertNoThrow(try audit(mixedFixture))
        let fresh = try resign(
            mixedFixture.evidence.observations[0],
            fixture: mixedFixture,
            nonce: nonce(99)
        )
        assertCoverageError(.replayClaimRejected) {
            try audit(replacing(mixedFixture, observationAt: 0, with: fresh))
        }
        XCTAssertEqual(mixedLedger.invocationCount, 2)
        XCTAssertEqual(mixedLedger.claimedCount, Matrix.canonicalScenarios.count)

        assertCoverageError(.replayClaimRejected) {
            try audit(
                mixedFixture,
                policy: policy(
                    ledger: mixedLedger,
                    auditTime: mixedFixture.auditTime,
                    replayPolicy: revision("replay-policy", 3)
                )
            )
        }
        XCTAssertEqual(mixedLedger.lastPolicy, revision("replay-policy", 3))
        XCTAssertEqual(mixedLedger.claimedCount, Matrix.canonicalScenarios.count)
    }

    func testIncompleteAuditNeverConsumesReplayClaims() throws {
        let ledger = ReplayLedger()
        let fixture = try makeFixture(ledger: ledger)
        let incomplete = replacing(
            fixture,
            evidence: bundle(fixture, observations: Array(fixture.evidence.observations.dropFirst()))
        )
        let result = try audit(incomplete)
        XCTAssertFalse(result.report.isCompleteAndValid)
        XCTAssertEqual(ledger.invocationCount, 0)
        XCTAssertEqual(ledger.claimedCount, 0)
        XCTAssertNoThrow(try audit(fixture))
        XCTAssertEqual(ledger.invocationCount, 1)
        XCTAssertEqual(ledger.claimedCount, Matrix.canonicalScenarios.count)
    }

    func testTrustedAuditTimeAgeFutureSkewAndUInt64Boundaries() throws {
        let fixture = try makeFixture()
        let first = try XCTUnwrap(fixture.evidence.observations.first)
        let earliest = fixture.auditTime - 1_000
        let latest = fixture.auditTime + 100
        for timestamp in [earliest, latest] {
            let replacement = try resign(first, fixture: fixture, capturedAt: timestamp)
            let changed = replacing(fixture, observationAt: 0, with: replacement)
            let result = try audit(
                changed,
                policy: policy(
                    ledger: ReplayLedger(),
                    auditTime: fixture.auditTime,
                    maximumAge: 1_000,
                    futureSkew: 100
                )
            )
            XCTAssertEqual(result.report.matrix.cells[0].status, .complete, "timestamp \(timestamp)")
        }
        for timestamp in [earliest - 1, latest + 1] {
            let replacement = try resign(first, fixture: fixture, capturedAt: timestamp)
            let changed = replacing(fixture, observationAt: 0, with: replacement)
            let probe = InvocationProbe()
            let result = try audit(
                changed,
                policy: policy(
                    ledger: ReplayLedger(),
                    auditTime: fixture.auditTime,
                    maximumAge: 1_000,
                    futureSkew: 100
                ),
                captureResolver: { _, _, _ in
                    probe.record()
                    return Data()
                }
            )
            XCTAssertEqual(result.report.matrix.cells[0].status, .invalid)
            XCTAssertTrue(result.report.findings.contains { $0.code == .productionProvenanceInvalid })
            XCTAssertEqual(probe.count, Matrix.canonicalScenarios.count - 1)
        }

        let nearMaximum = UInt64.max - 5
        let maximumObservation = try resign(first, fixture: fixture, capturedAt: UInt64.max)
        let maximumFixture = replacing(fixture, observationAt: 0, with: maximumObservation)
        let maximumResult = try audit(
            maximumFixture,
            policy: policy(
                ledger: ReplayLedger(),
                auditTime: nearMaximum,
                maximumAge: UInt64.max,
                futureSkew: 10
            )
        )
        XCTAssertEqual(maximumResult.report.matrix.cells[0].status, .complete)

        let saturatedObservation = try resign(first, fixture: fixture, capturedAt: 1)
        let saturated = replacing(fixture, observationAt: 0, with: saturatedObservation)
        XCTAssertEqual(
            try audit(
                saturated,
                policy: policy(ledger: ReplayLedger(), auditTime: 10, maximumAge: 20, futureSkew: 0)
            ).report.matrix.cells[0].status,
            .complete
        )
        let zeroSkewFuture = replacing(
            fixture,
            observationAt: 0,
            with: try resign(first, fixture: fixture, capturedAt: fixture.auditTime + 1)
        )
        let zeroSkewResult = try audit(
            zeroSkewFuture,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime, futureSkew: 0)
        )
        XCTAssertEqual(zeroSkewResult.report.matrix.cells[0].status, .invalid)
        XCTAssertEqual(zeroSkewResult.report.findings.map(\.code), [.productionProvenanceInvalid])
        for invalidPolicy in [
            policy(ledger: ReplayLedger(), auditTime: 0),
            policy(ledger: ReplayLedger(), auditTime: fixture.auditTime, maximumAge: 0)
        ] {
            assertCoverageError(.invalidInventory(.auditPolicy)) {
                try audit(fixture, policy: invalidPolicy)
            }
        }
    }

    func testTrustAuthenticationAndSemanticBindingFailuresOccurBeforeResolver() throws {
        let fixture = try makeFixture()
        let first = try XCTUnwrap(fixture.evidence.observations.first)
        let spec = try XCTUnwrap(fixture.lifecycleSpecs[.identical])
        let mutations: [(ComparisonResultFindingCode, ComparisonResultLifecycleIdentityToken)] = [
            (
                .comparisonIdentityMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(
                    makeCurrentState(spec.with(comparisonIdentityDelta: 100))
                )
            ),
            (
                .inputIdentityMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(spec.with(inputIdentityDelta: 100)))
            ),
            (
                .operationIdentityMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(spec.with(operationDelta: 100)))
            ),
            (
                .resultIdentityMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(spec.with(resultDelta: 100)))
            ),
            (
                .sourceIdentityMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(spec.with(leftIdentityDelta: 100)))
            ),
            (
                .generationMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(spec.with(leftGeneration: 999)))
            ),
            (
                .generationMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(spec.with(inputGeneration: 999)))
            ),
            (
                .generationMismatch,
                try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(spec.with(rightGeneration: 999)))
            )
        ]
        for (expectedCode, lifecycle) in mutations {
            let changedObservation = try resign(first, fixture: fixture, lifecycle: lifecycle)
            let changed = replacing(fixture, observationAt: 0, with: changedObservation)
            let resolverProbe = InvocationProbe()
            let validResolver = resolver(fixture.captures)
            let result = try audit(
                changed,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: { digest, maximum, cancellationCheck in
                    resolverProbe.record()
                    return try validResolver(digest, maximum, cancellationCheck)
                }
            )
            XCTAssertEqual(result.report.findings.map(\.code), [expectedCode])
            XCTAssertEqual(result.report.matrix.cells[0].status, .mismatched)
            XCTAssertEqual(resolverProbe.count, Matrix.canonicalScenarios.count - 1)
        }

        let rogueIssuer = try authority(0x7E)
        let rogueLifecycle = try rogueIssuer.authenticateCurrentLifecycle(makeCurrentState(spec))
        let untrusted = replacing(
            fixture,
            observationAt: 0,
            with: try resign(first, fixture: fixture, lifecycle: rogueLifecycle)
        )
        let resolverProbe = InvocationProbe()
        let untrustedResult = try audit(
            untrusted,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: { _, _, _ in
                resolverProbe.record()
                return Data()
            }
        )
        XCTAssertTrue(untrustedResult.report.findings.contains { $0.code == .lifecycleAuthenticationInvalid })
        XCTAssertEqual(untrustedResult.report.matrix.cells[0].status, .invalid)
        XCTAssertEqual(resolverProbe.count, Matrix.canonicalScenarios.count - 1)
    }

    func testThreeWayMiddleSourceIdentityAndGenerationAreComparedIndependently() throws {
        let fixture = try makeFixture(isThreeWay: true)
        let first = fixture.evidence.observations[0]
        let spec = try XCTUnwrap(fixture.lifecycleSpecs[.identical])
        let mutations: [(ComparisonResultFindingCode, LifecycleSpec)] = [
            (.sourceIdentityMismatch, spec.with(middleIdentityDelta: 100)),
            (.generationMismatch, spec.with(middleGeneration: 999))
        ]
        for (code, changedSpec) in mutations {
            let lifecycle = try fixture.issuer.authenticateCurrentLifecycle(makeCurrentState(changedSpec))
            let changed = replacing(
                fixture,
                observationAt: 0,
                with: try resign(first, fixture: fixture, lifecycle: lifecycle)
            )
            let resolverProbe = InvocationProbe()
            let validResolver = resolver(fixture.captures)
            let result = try audit(
                changed,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: { digest, maximum, cancellationCheck in
                    resolverProbe.record()
                    return try validResolver(digest, maximum, cancellationCheck)
                }
            )
            XCTAssertEqual(result.report.findings.map(\.code), [code])
            XCTAssertEqual(result.report.matrix.cells[0].status, .mismatched)
            XCTAssertEqual(resolverProbe.count, Matrix.canonicalScenarios.count - 1)
        }
    }

    func testResultSelectionCursorViewportVisibilityAndCommandStateAreExact() throws {
        let fixture = try makeFixture()
        let index = try XCTUnwrap(Matrix.canonicalScenarios.firstIndex(of: .middleSelectedAtStart))
        let baseline = fixture.evidence.observations[index]
        let expected = fixture.inventory.requirements[index].expected
        let differences = expected.differences
        let cases: [(ComparisonResultFindingCode, ComparisonResultSemanticState)] = [
            (
                .resultStateMismatch,
                try semanticState(
                    differences: [
                        try difference("d0", 0, 2..<4),
                        try difference("d1", 1, 7..<9),
                        try difference("d2", 2, 13..<15)
                    ],
                    selection: expected.selection,
                    cursor: expected.cursor,
                    alignedRows: 18,
                    visibleRows: 0..<18,
                    command: expected.commandState
                )
            ),
            (
                .selectionStateMismatch,
                try semanticState(
                    differences: differences,
                    selection: .difference(differences[0].id),
                    cursor: expected.cursor,
                    alignedRows: 18,
                    visibleRows: 0..<18,
                    command: expected.commandState
                )
            ),
            (
                .cursorStateMismatch,
                try semanticState(
                    differences: differences,
                    selection: expected.selection,
                    cursor: .row(index: 8, differenceID: differences[1].id),
                    alignedRows: 18,
                    visibleRows: 0..<18,
                    command: expected.commandState
                )
            ),
            (
                .viewportStateMismatch,
                try semanticState(
                    differences: differences,
                    selection: expected.selection,
                    cursor: expected.cursor,
                    alignedRows: 19,
                    visibleRows: 0..<18,
                    command: expected.commandState
                )
            ),
            (
                .selectionVisibilityMismatch,
                try semanticState(
                    differences: differences,
                    selection: expected.selection,
                    cursor: expected.cursor,
                    alignedRows: 18,
                    visibleRows: 0..<5,
                    command: expected.commandState
                )
            ),
            (
                .commandStateMismatch,
                try semanticState(
                    differences: differences,
                    selection: expected.selection,
                    cursor: expected.cursor,
                    alignedRows: 18,
                    visibleRows: 0..<18,
                    command: command(true, true, false, false)
                )
            )
        ]
        for (expectedCode, observed) in cases {
            let changed = replacing(
                fixture,
                observationAt: index,
                with: try resign(baseline, fixture: fixture, observed: observed)
            )
            let result = try audit(
                changed,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
            )
            XCTAssertTrue(result.report.findings.contains { $0.code == expectedCode }, expectedCode.rawValue)
            XCTAssertEqual(result.report.matrix.cells[index].status, .mismatched)
            XCTAssertEqual(result.receipt.measuredProductionEvidenceCount, Matrix.canonicalScenarios.count - 1)
        }
    }

    func testProvenanceSourceSignatureAndCaptureTransplantAreBound() throws {
        let fixture = try makeFixture()
        let first = try XCTUnwrap(fixture.evidence.observations.first)
        let sourceChanged = try resign(first, fixture: fixture, source: "independent-manual-station")
        XCTAssertNotEqual(sourceChanged.provenance?.source, first.provenance?.source)
        XCTAssertEqual(
            try Matrix.canonicalCaptureData(for: sourceChanged),
            try Matrix.canonicalCaptureData(for: first)
        )
        XCTAssertNotEqual(
            try Matrix.canonicalCaptureEnvelopeData(for: sourceChanged),
            try Matrix.canonicalCaptureEnvelopeData(for: first)
        )
        let changedResult = try audit(
            replacing(fixture, observationAt: 0, with: sourceChanged),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertEqual(changedResult.report.matrix.cells[0].status, .complete)

        let transplantedSignatureProvenance = ComparisonResultEvidenceProvenance(
            build: try XCTUnwrap(sourceChanged.provenance).build,
            inventory: try XCTUnwrap(sourceChanged.provenance).inventory,
            collector: try XCTUnwrap(sourceChanged.provenance).collector,
            capturedAtUnixMilliseconds: try XCTUnwrap(sourceChanged.provenance).capturedAtUnixMilliseconds,
            runNonce: try XCTUnwrap(sourceChanged.provenance).runNonce,
            artifactSHA256: try XCTUnwrap(sourceChanged.provenance).artifactSHA256,
            inventorySHA256: try XCTUnwrap(sourceChanged.provenance).inventorySHA256,
            captureSHA256: try XCTUnwrap(sourceChanged.provenance).captureSHA256,
            collectorSignature: try XCTUnwrap(first.provenance).collectorSignature,
            source: try XCTUnwrap(sourceChanged.provenance).source
        )
        let badSignature = ComparisonResultEvidence(
            scenarioID: sourceChanged.scenarioID,
            lifecycle: sourceChanged.lifecycle,
            observed: sourceChanged.observed,
            origin: sourceChanged.origin,
            provenance: transplantedSignatureProvenance,
            accessibility: sourceChanged.accessibility
        )
        let signatureProbe = InvocationProbe()
        let signatureResult = try audit(
            replacing(fixture, observationAt: 0, with: badSignature),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: { _, _, _ in
                signatureProbe.record()
                return Data()
            }
        )
        XCTAssertTrue(signatureResult.report.findings.contains { $0.code == .productionProvenanceInvalid })
        XCTAssertEqual(signatureProbe.count, Matrix.canonicalScenarios.count - 1)

        let second = fixture.evidence.observations[1]
        let transplanted = try resign(
            second,
            fixture: fixture,
            captureSHA256: try XCTUnwrap(first.provenance).captureSHA256
        )
        let transplantProbe = InvocationProbe()
        let transplantResult = try audit(
            replacing(fixture, observationAt: 1, with: transplanted),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: { _, _, _ in
                transplantProbe.record()
                return try Matrix.canonicalCaptureData(for: first)
            }
        )
        XCTAssertTrue(transplantResult.report.findings.contains { $0.code == .productionCaptureMismatch })
        XCTAssertEqual(transplantResult.report.matrix.cells[1].status, .invalid)
        XCTAssertEqual(transplantProbe.count, Matrix.canonicalScenarios.count - 1)
    }

    func testEveryProvenanceCoordinateAndSignatureTransplantFailsClosedWithoutReplay() throws {
        let fixture = try makeFixture()
        let first = fixture.evidence.observations[0]
        let provenance = try XCTUnwrap(first.provenance)
        let malformed: [(ComparisonResultEvidence, [ComparisonResultFindingCode])] = [
            (
                replacingProvenance(first, provenance, nonce: [UInt8](repeating: 1, count: 15)),
                [.productionProvenanceInvalid]
            ),
            (
                replacingProvenance(first, provenance, captureSHA256: [UInt8](repeating: 0, count: 32)),
                [.productionProvenanceInvalid]
            ),
            (
                replacingProvenance(first, provenance, collectorSignature: [UInt8](repeating: 1, count: 63)),
                [.productionProvenanceInvalid]
            ),
            (
                replacingProvenance(first, provenance, source: "invalid\nsource"),
                [.productionProvenanceInvalid]
            ),
            (
                try resign(first, fixture: fixture, build: revision("other-build", 41)),
                [.provenanceBuildMismatch]
            ),
            (
                try resign(first, fixture: fixture, inventory: revision("other-inventory", 43)),
                [.provenanceInventoryMismatch]
            ),
            (
                try resign(first, fixture: fixture, inventoryDigest: digest(0x71)),
                [.provenanceInventoryMismatch]
            ),
            (
                try resign(first, fixture: fixture, artifact: digest(0x72)),
                [.provenanceArtifactMismatch]
            ),
            (
                try resign(first, fixture: fixture, collector: revision("other-collector", 9)),
                [.untrustedCollector]
            )
        ]
        for (observation, expectedCodes) in malformed {
            let ledger = ReplayLedger()
            let result = try audit(
                replacing(fixture, observationAt: 0, with: observation),
                policy: policy(ledger: ledger, auditTime: fixture.auditTime)
            )
            XCTAssertEqual(result.report.findings.map(\.code), expectedCodes)
            XCTAssertEqual(result.report.matrix.cells[0].status, .invalid)
            XCTAssertEqual(result.receipt.measuredProductionEvidenceCount, Matrix.canonicalScenarios.count - 1)
            XCTAssertEqual(ledger.invocationCount, 0)
        }

        let signedFields: [ComparisonResultEvidence] = [
            replacingProvenance(first, provenance, nonce: nonce(99)),
            replacingProvenance(first, provenance, capturedAt: provenance.capturedAtUnixMilliseconds - 1),
            ComparisonResultEvidence(
                scenarioID: first.scenarioID,
                lifecycle: first.lifecycle,
                observed: first.observed,
                origin: .productionManualMeasurement,
                provenance: provenance,
                accessibility: first.accessibility
            )
        ]
        for observation in signedFields {
            let ledger = ReplayLedger()
            let result = try audit(
                replacing(fixture, observationAt: 0, with: observation),
                policy: policy(ledger: ledger, auditTime: fixture.auditTime)
            )
            XCTAssertEqual(result.report.findings.map(\.code), [.productionProvenanceInvalid])
            XCTAssertEqual(result.report.matrix.cells[0].status, .invalid)
            XCTAssertEqual(ledger.invocationCount, 0)
        }
    }

    func testResolverFailuresDistinguishEvidenceMismatchCancellationAndResourceErrors() throws {
        let fixture = try makeFixture()
        enum OrdinaryError: Error { case failed }
        let ordinary = try audit(
            fixture,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: { _, _, _ in throw OrdinaryError.failed }
        )
        XCTAssertEqual(ordinary.report.matrix.invalidCount, Matrix.canonicalScenarios.count)
        XCTAssertEqual(
            ordinary.report.findings.filter { $0.code == .productionCaptureMismatch }.count,
            Matrix.canonicalScenarios.count
        )

        let overflow = try audit(
            fixture,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: { _, _, _ in
                throw ComparisonResultCaptureResolutionError.exceedsMaximumByteCount
            }
        )
        XCTAssertEqual(overflow.report.matrix.invalidCount, Matrix.canonicalScenarios.count)
        XCTAssertEqual(
            overflow.report.findings.filter { $0.code == .productionCaptureMismatch }.count,
            Matrix.canonicalScenarios.count
        )

        assertSpecificError(ComparisonResultCaptureResolutionError.resourceUnavailable) {
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: { _, _, _ in
                    throw ComparisonResultCaptureResolutionError.resourceUnavailable
                }
            )
        }
        assertSpecificError(TestCaptureResourceError.unavailable) {
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: { _, _, _ in throw TestCaptureResourceError.unavailable }
            )
        }
        assertCoverageError(.cancelled) {
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: { _, _, _ in throw CancellationError() }
            )
        }
        assertCoverageError(.cancelled) {
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: { _, _, _ in throw ComparisonResultCoverageError.cancelled }
            )
        }
    }

    func testResolverEnforcesExactMaximumAndRejectsTruncatedAlteredAndOversizedCapturesWithoutReplay() throws {
        let fixture = try makeFixture()
        let first = fixture.evidence.observations[0]
        let firstDigest = try XCTUnwrap(first.provenance).captureSHA256
        let firstCapture = try XCTUnwrap(fixture.captures[firstDigest])
        let resolver = resolver(fixture.captures)
        let variants = [
            Data(firstCapture.dropLast()),
            Data(repeating: 0xA5, count: firstCapture.count),
            firstCapture + Data([0xA5])
        ]
        for variant in variants {
            let ledger = ReplayLedger()
            let maximumProbe = IntegerProbe()
            let result = try audit(
                fixture,
                policy: policy(ledger: ledger, auditTime: fixture.auditTime),
                captureResolver: { digest, maximum, cancellationCheck in
                    if cancellationCheck() { throw CancellationError() }
                    if digest == firstDigest {
                        maximumProbe.record(maximum)
                        return variant
                    }
                    return try resolver(digest, maximum, cancellationCheck)
                }
            )
            XCTAssertEqual(maximumProbe.values, [firstCapture.count])
            XCTAssertEqual(result.report.findings.map(\.code), [.productionCaptureMismatch])
            XCTAssertEqual(result.report.findings.map(\.subject), [.scenario(ComparisonResultScenario.identical.id)])
            XCTAssertEqual(result.report.matrix.cells[0].status, .invalid)
            XCTAssertEqual(ledger.invocationCount, 0)
        }
    }

    func testResolverCancellationCallbackIsForwardedAndObservedAfterReturn() throws {
        let fixture = try makeFixture()
        let resolver = resolver(fixture.captures)
        let checks = InvocationProbe()
        assertCoverageError(.cancelled) {
            try audit(
                fixture,
                captureResolver: { digest, maximum, cancellationCheck in
                    checks.record()
                    XCTAssertTrue(cancellationCheck())
                    return try resolver(digest, maximum, { false })
                },
                cancellationCheck: { checks.count > 0 }
            )
        }
        XCTAssertEqual(checks.count, 1)
    }

    func testAccessibilityTokensBindEverySignedReceiptCoordinate() throws {
        let fixture = try makeFixture()
        let index = 0
        let baseline = fixture.evidence.observations[index]
        let required = try XCTUnwrap(fixture.inventory.requirements[index].accessibility?.token)
        let receipt = try makeAccessibilityReceipt(
            artifact: fixture.inventory.buildArtifactSHA256,
            suffix: "alternate",
            signing: digest(0xD1)
        )
        let alternatives = [
            try fixture.issuer.authenticateAccessibilityEvidence(
                receipt: receipt,
                scenario: required.scenario,
                snapshotID: required.snapshotID
            ),
            try fixture.issuer.authenticateAccessibilityEvidence(
                receipt: fixture.accessibilityReceipt,
                scenario: accessibilityReference("other-matrix-scenario", 1),
                snapshotID: required.snapshotID
            ),
            try fixture.issuer.authenticateAccessibilityEvidence(
                receipt: fixture.accessibilityReceipt,
                scenario: required.scenario,
                snapshotID: accessibilityID("other-snapshot")
            )
        ]
        for alternative in alternatives {
            let changedObservation = try resign(baseline, fixture: fixture, accessibility: .some(alternative))
            let result = try audit(
                replacing(fixture, observationAt: index, with: changedObservation),
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
            )
            XCTAssertTrue(result.report.findings.contains { $0.code == .accessibilityEvidenceMismatch })
            XCTAssertEqual(result.report.matrix.cells[index].status, .mismatched)
        }

        let missing = try resign(baseline, fixture: fixture, accessibility: .some(nil))
        let missingResult = try audit(
            replacing(fixture, observationAt: index, with: missing),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertTrue(missingResult.report.findings.contains { $0.code == .accessibilityEvidenceMissing })
        XCTAssertEqual(missingResult.report.matrix.cells[index].status, .invalid)

        let rogueIssuer = try authority(0xEF)
        let rogue = try rogueIssuer.authenticateAccessibilityEvidence(
            receipt: fixture.accessibilityReceipt,
            scenario: required.scenario,
            snapshotID: required.snapshotID
        )
        let rogueObservation = try resign(baseline, fixture: fixture, accessibility: .some(rogue))
        let rogueResult = try audit(
            replacing(fixture, observationAt: index, with: rogueObservation),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertTrue(rogueResult.report.findings.contains { $0.code == .accessibilityAuthenticationInvalid })
        XCTAssertEqual(rogueResult.report.matrix.cells[index].status, .invalid)
    }

    func testAuthorityRejectsIncompleteAccessibilityReceipt() throws {
        let fixture = try makeAccessibilityFixture(
            artifact: digest(0xA1),
            suffix: "incomplete",
            signing: digest(0xA2),
            removesObservation: true
        )
        let result = try AccessibilityEvidenceWorkflow.evaluate(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            attachmentResolver: fixture.resolver,
            cancellationCheck: { false }
        )
        XCTAssertLessThan(result.receipt.completeEvidenceCount, result.receipt.requiredEvidenceCount)
        XCTAssertGreaterThan(result.receipt.findingCount, 0)
        let issuer = try authority(0x42)
        assertCoverageError(.invalidEvidence(.accessibilityBinding)) {
            try issuer.authenticateAccessibilityInventory(
                receipt: result.receipt,
                scenario: accessibilityReference("scenario", 1),
                snapshotID: accessibilityID("snapshot")
            )
        }
        assertCoverageError(.invalidEvidence(.accessibilityBinding)) {
            try issuer.authenticateAccessibilityEvidence(
                receipt: result.receipt,
                scenario: accessibilityReference("scenario", 1),
                snapshotID: accessibilityID("snapshot")
            )
        }
    }

    func testMissingDuplicateUnexpectedMalformedAndAssertionOnlyEvidenceHaveExactStatuses() throws {
        let fixture = try makeFixture()
        let baselineCount = Matrix.canonicalScenarios.count

        let missingBundle = bundle(fixture, observations: Array(fixture.evidence.observations.dropFirst()))
        let missing = try audit(
            replacing(fixture, evidence: missingBundle),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertEqual(missing.report.matrix.missingCount, 1)
        XCTAssertEqual(missing.report.matrix.cells[0].evidenceCount, 0)
        XCTAssertNil(missing.report.matrix.cells[0].observed)
        XCTAssertEqual(missing.receipt.measuredProductionEvidenceCount, baselineCount - 1)

        let duplicateBundle = bundle(
            fixture,
            observations: fixture.evidence.observations + [fixture.evidence.observations[0]]
        )
        let duplicate = try audit(
            replacing(fixture, evidence: duplicateBundle),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertEqual(duplicate.report.matrix.duplicateCount, 1)
        XCTAssertEqual(duplicate.report.matrix.cells[0].evidenceCount, 2)
        XCTAssertEqual(duplicate.receipt.measuredProductionEvidenceCount, baselineCount - 1)

        let first = fixture.evidence.observations[0]
        let unexpected = ComparisonResultEvidence(
            scenarioID: ComparisonResultScenarioID(rawValue: UInt16.max),
            lifecycle: first.lifecycle,
            observed: first.observed,
            origin: .productionAutomatedMeasurement,
            provenance: first.provenance,
            accessibility: first.accessibility
        )
        let unexpectedResult = try audit(
            replacing(
                fixture,
                evidence: bundle(fixture, observations: fixture.evidence.observations + [unexpected])
            ),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertTrue(unexpectedResult.report.findings.contains { $0.code == .unexpectedScenarioEvidence })
        XCTAssertEqual(unexpectedResult.receipt.measuredProductionEvidenceCount, baselineCount)

        let malformed = ComparisonResultEvidence(
            scenarioID: first.scenarioID,
            lifecycle: first.lifecycle,
            observed: first.observed,
            origin: .productionAutomatedMeasurement,
            provenance: nil,
            accessibility: first.accessibility
        )
        let malformedResult = try audit(
            replacing(fixture, observationAt: 0, with: malformed),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertEqual(malformedResult.report.matrix.invalidCount, 1)
        XCTAssertTrue(malformedResult.report.findings.contains { $0.code == .productionProvenanceMissing })
        XCTAssertEqual(malformedResult.receipt.measuredProductionEvidenceCount, baselineCount - 1)

        let assertion = ComparisonResultEvidence(
            scenarioID: first.scenarioID,
            lifecycle: first.lifecycle,
            observed: first.observed,
            origin: .callerAssertion,
            provenance: first.provenance,
            accessibility: first.accessibility
        )
        let assertionResult = try audit(
            replacing(fixture, observationAt: 0, with: assertion),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertEqual(assertionResult.report.matrix.assertionOnlyCount, 1)
        XCTAssertEqual(assertionResult.receipt.callerAssertionCount, 1)
        XCTAssertEqual(assertionResult.receipt.measuredProductionEvidenceCount, baselineCount - 1)
        XCTAssertTrue(assertionResult.report.findings.contains { $0.code == .assertionOnlyEvidence })
    }

    func testOnlySuccessfulUniqueMeasuredEvidenceCounts() throws {
        let fixture = try makeFixture()
        let count = Matrix.canonicalScenarios.count
        let first = fixture.evidence.observations[0]
        let variants: [([ComparisonResultEvidence], Int, Int)] = [
            (fixture.evidence.observations, count, 0),
            (Array(fixture.evidence.observations.dropFirst()), count - 1, 0),
            (fixture.evidence.observations + [first], count - 1, 0),
            (
                [
                    ComparisonResultEvidence(
                        scenarioID: first.scenarioID,
                        lifecycle: first.lifecycle,
                        observed: first.observed,
                        origin: .callerAssertion,
                        provenance: first.provenance,
                        accessibility: first.accessibility
                    )
                ] + Array(fixture.evidence.observations.dropFirst()),
                count - 1,
                1
            ),
            (
                [
                    ComparisonResultEvidence(
                        scenarioID: first.scenarioID,
                        lifecycle: first.lifecycle,
                        observed: first.observed,
                        origin: .productionManualMeasurement,
                        provenance: nil,
                        accessibility: first.accessibility
                    )
                ] + Array(fixture.evidence.observations.dropFirst()),
                count - 1,
                0
            )
        ]
        for (observations, measured, assertions) in variants {
            let result = try audit(
                replacing(fixture, evidence: bundle(fixture, observations: observations)),
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
            )
            XCTAssertEqual(result.receipt.measuredProductionEvidenceCount, measured)
            XCTAssertEqual(result.receipt.callerAssertionCount, assertions)
        }
    }

    func testValidManualMeasurementCompletesVerifiesAndClaimsReplay() throws {
        let ledger = ReplayLedger()
        let fixture = try makeFixture(ledger: ledger)
        let manual = try resign(
            fixture.evidence.observations[0],
            fixture: fixture,
            origin: .productionManualMeasurement
        )
        let result = try audit(replacing(fixture, observationAt: 0, with: manual))
        XCTAssertEqual(result.report.matrix.cells[0].status, .complete)
        XCTAssertEqual(result.receipt.measuredProductionEvidenceCount, Matrix.canonicalScenarios.count)
        XCTAssertTrue(result.receipt.recordsCompleteProductionCoverage)
        XCTAssertEqual(ledger.invocationCount, 1)
        XCTAssertTrue(ledger.lastClaims.contains { $0.nonce == manual.provenance?.runNonce })
    }

    func testReportHashBindsExpectedAndObservedStates() throws {
        let fixture = try makeFixture()
        let baseline = try audit(
            fixture,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        let index = try XCTUnwrap(Matrix.canonicalScenarios.firstIndex(of: .differentWithoutSelection))
        let observation = fixture.evidence.observations[index]
        let observedState = try semanticState(
            differences: [try difference("different-only", 0, 3..<5)],
            alignedRows: 18,
            visibleRows: 0..<18,
            command: command(true, false, true, true)
        )
        let observedFixture = replacing(
            fixture,
            observationAt: index,
            with: try resign(observation, fixture: fixture, observed: observedState)
        )
        let observedResult = try audit(
            observedFixture,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertNotEqual(observedResult.receipt.reportSHA256, baseline.receipt.reportSHA256)
        XCTAssertNotEqual(observedResult.report.matrix.cells[index].observed, baseline.report.matrix.cells[index].observed)

        var requirements = fixture.inventory.requirements
        requirements[index] = try ComparisonResultCoverageRequirement(
            scenario: .differentWithoutSelection,
            lifecycle: requirements[index].lifecycle,
            expected: observedState,
            accessibility: requirements[index].accessibility
        )
        let expectedInventory = try ComparisonResultCoverageInventory.canonical(
            reference: fixture.inventory.reference,
            build: fixture.inventory.build,
            buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
            requirementsByScenario: Dictionary(uniqueKeysWithValues: requirements.map { ($0.scenario, $0) })
        )
        let assertions = fixture.evidence.observations.map { candidate in
            ComparisonResultEvidence(
                scenarioID: candidate.scenarioID,
                lifecycle: candidate.lifecycle,
                observed: candidate.observed,
                origin: .callerAssertion,
                provenance: nil,
                accessibility: candidate.accessibility
            )
        }
        let expectedResult = try Matrix.audit(
            inventory: expectedInventory,
            evidence: bundle(fixture, observations: assertions),
            verifier: fixture.verifier,
            auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: { _, _, _ in
                XCTFail("Assertion evidence must not resolve capture")
                return Data()
            },
            cancellationCheck: { false }
        )
        let baselineAssertions = try Matrix.audit(
            inventory: fixture.inventory,
            evidence: bundle(fixture, observations: assertions),
            verifier: fixture.verifier,
            auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
            captureResolver: { _, _, _ in
                XCTFail("Assertion evidence must not resolve capture")
                return Data()
            },
            cancellationCheck: { false }
        )
        XCTAssertNotEqual(expectedResult.receipt.reportSHA256, baselineAssertions.receipt.reportSHA256)
        XCTAssertNotEqual(expectedResult.report.matrix.cells[index].expected, baselineAssertions.report.matrix.cells[index].expected)
    }

    func testFindingOrderIDsAndReceiptsAreStableAcrossMalformedInputOrder() throws {
        let fixture = try makeFixture()
        let first = fixture.evidence.observations[0]
        let assertion = ComparisonResultEvidence(
            scenarioID: first.scenarioID,
            lifecycle: first.lifecycle,
            observed: first.observed,
            origin: .callerAssertion,
            provenance: nil,
            accessibility: first.accessibility
        )
        let unexpected = ComparisonResultEvidence(
            scenarioID: ComparisonResultScenarioID(rawValue: 60_000),
            lifecycle: first.lifecycle,
            observed: first.observed,
            origin: .callerAssertion,
            provenance: nil,
            accessibility: first.accessibility
        )
        let malformed = [assertion, first, unexpected] + Array(fixture.evidence.observations.dropFirst())
        let reversed = Array(malformed.reversed())
        let firstResult = try audit(
            replacing(fixture, evidence: bundle(fixture, observations: malformed)),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        let secondResult = try audit(
            replacing(fixture, evidence: bundle(fixture, observations: reversed)),
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        XCTAssertEqual(firstResult.report, secondResult.report)
        XCTAssertEqual(firstResult.receipt, secondResult.receipt)
        XCTAssertEqual(firstResult.report.findings.map(\.id), secondResult.report.findings.map(\.id))
        XCTAssertEqual(Set(firstResult.report.findings.map(\.id)).count, firstResult.report.findings.count)
        XCTAssertEqual(
            firstResult.report.findings.map(\.severity),
            firstResult.report.findings.map(\.severity).sorted(by: >)
        )
        XCTAssertEqual(firstResult.report.highestSeverity, .error)
    }

    func testCanonicalCaptureAndEnvelopeByteLimitsAcceptExactAndRejectOneLess() throws {
        let fixture = try makeFixture()
        let observation = fixture.evidence.observations[0]
        let capture = try Matrix.canonicalCaptureData(for: observation)
        let envelope = try Matrix.canonicalCaptureEnvelopeData(for: observation)
        XCTAssertGreaterThan(capture.count, 100)
        XCTAssertGreaterThan(envelope.count, 100)
        XCTAssertNotEqual(capture, envelope)
        XCTAssertEqual(try Matrix.canonicalCaptureData(for: observation, maximumBytes: capture.count), capture)
        XCTAssertEqual(try Matrix.canonicalCaptureEnvelopeData(for: observation, maximumBytes: envelope.count), envelope)
        assertCoverageError(.canonicalDataTooLarge(maximumBytes: capture.count - 1)) {
            try Matrix.canonicalCaptureData(for: observation, maximumBytes: capture.count - 1)
        }
        assertCoverageError(.canonicalDataTooLarge(maximumBytes: envelope.count - 1)) {
            try Matrix.canonicalCaptureEnvelopeData(for: observation, maximumBytes: envelope.count - 1)
        }
        for invalid in [0, ComparisonResultCoverageLimits.hardMaximumCanonicalBytes + 1] {
            assertCoverageError(.invalidLimit(.canonicalBytes)) {
                try Matrix.canonicalCaptureData(for: observation, maximumBytes: invalid)
            }
            assertCoverageError(.invalidLimit(.canonicalBytes)) {
                try Matrix.canonicalCaptureEnvelopeData(for: observation, maximumBytes: invalid)
            }
        }
    }

    func testAuditWorkAndCanonicalLimitsHaveExactBoundariesIncludingSortingBytes() throws {
        let fixture = try makeFixture()
        let minimumWork = try minimumSuccessfulLimit(
            lower: 1,
            upper: ComparisonResultCoverageLimits.default.maximumWorkUnits
        ) { maximum in
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumWorkUnits: maximum)
            )
        }
        XCTAssertGreaterThan(minimumWork, fixture.evidence.observations.count)
        XCTAssertNoThrow(
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumWorkUnits: minimumWork)
            )
        )
        assertCoverageError(.workLimitExceeded(maximum: minimumWork - 1)) {
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumWorkUnits: minimumWork - 1)
            )
        }

        let minimumCanonical = try minimumSuccessfulLimit(
            lower: 1,
            upper: ComparisonResultCoverageLimits.default.maximumCanonicalBytes
        ) { maximum in
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumCanonicalBytes: maximum)
            )
        }
        XCTAssertGreaterThan(minimumCanonical, 100)
        XCTAssertNoThrow(
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumCanonicalBytes: minimumCanonical)
            )
        )
        assertCoverageError(.canonicalDataTooLarge(maximumBytes: minimumCanonical - 1)) {
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumCanonicalBytes: minimumCanonical - 1)
            )
        }

        let duplicate = bundle(
            fixture,
            observations: fixture.evidence.observations + [fixture.evidence.observations[0]]
        )
        let duplicateFixture = replacing(fixture, evidence: duplicate)
        let duplicateMinimum = try minimumSuccessfulLimit(
            lower: 1,
            upper: ComparisonResultCoverageLimits.default.maximumWorkUnits
        ) { maximum in
            try audit(
                duplicateFixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumWorkUnits: maximum)
            )
        }
        XCTAssertGreaterThan(duplicateMinimum, minimumWork)
        assertCoverageError(.workLimitExceeded(maximum: duplicateMinimum - 1)) {
            try audit(
                duplicateFixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumWorkUnits: duplicateMinimum - 1)
            )
        }
    }

    func testEveryConfiguredLimitRejectsZeroAndAboveHardMaximum() throws {
        let fixture = try makeFixture()
        let cases: [(ComparisonResultCoverageLimit, ComparisonResultCoverageLimits)] = [
            (.trustedCollectors, limits(maximumTrustedCollectors: 0)),
            (.observations, limits(maximumObservations: 0)),
            (.differencesPerScenario, limits(maximumDifferencesPerScenario: 0)),
            (.totalDifferences, limits(maximumTotalDifferences: 0)),
            (.rows, limits(maximumRows: 0)),
            (.stringUTF8Bytes, limits(maximumStringUTF8Bytes: 0)),
            (.totalStringUTF8Bytes, limits(maximumTotalStringUTF8Bytes: 0)),
            (.binaryMetadataBytes, limits(maximumBinaryMetadataBytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.findings, limits(maximumFindings: 0)),
            (.canonicalBytes, limits(maximumCanonicalBytes: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0)),
            (
                .trustedCollectors,
                limits(maximumTrustedCollectors: ComparisonResultCoverageLimits.hardMaximumTrustedCollectors + 1)
            ),
            (.observations, limits(maximumObservations: ComparisonResultCoverageLimits.hardMaximumObservations + 1)),
            (
                .differencesPerScenario,
                limits(maximumDifferencesPerScenario: ComparisonResultCoverageLimits.hardMaximumDifferencesPerScenario + 1)
            ),
            (
                .totalDifferences,
                limits(maximumTotalDifferences: ComparisonResultCoverageLimits.hardMaximumTotalDifferences + 1)
            ),
            (.rows, limits(maximumRows: ComparisonResultCoverageLimits.hardMaximumRows + 1)),
            (
                .stringUTF8Bytes,
                limits(maximumStringUTF8Bytes: ComparisonResultCoverageLimits.hardMaximumStringUTF8Bytes + 1)
            ),
            (
                .totalStringUTF8Bytes,
                limits(maximumTotalStringUTF8Bytes: ComparisonResultCoverageLimits.hardMaximumTotalStringUTF8Bytes + 1)
            ),
            (
                .binaryMetadataBytes,
                limits(maximumBinaryMetadataBytes: ComparisonResultCoverageLimits.hardMaximumBinaryMetadataBytes + 1)
            ),
            (.workUnits, limits(maximumWorkUnits: ComparisonResultCoverageLimits.hardMaximumWorkUnits + 1)),
            (.findings, limits(maximumFindings: ComparisonResultCoverageLimits.hardMaximumFindings + 1)),
            (
                .canonicalBytes,
                limits(maximumCanonicalBytes: ComparisonResultCoverageLimits.hardMaximumCanonicalBytes + 1)
            ),
            (
                .cancellationCheckInterval,
                limits(cancellationCheckInterval: ComparisonResultCoverageLimits.hardMaximumCancellationCheckInterval + 1)
            )
        ]
        XCTAssertEqual(Set(cases.map(\.0)), Set(ComparisonResultCoverageLimit.allCases))
        for (limit, value) in cases {
            assertCoverageError(.invalidLimit(limit)) {
                try audit(
                    fixture,
                    policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                    limits: value
                )
            }
        }
    }

    func testRuntimeCountDifferenceRowBinaryAndFindingLimitsUseExactBoundaries() throws {
        let fixture = try makeFixture()
        let scenarioCount = Matrix.canonicalScenarios.count
        XCTAssertNoThrow(
            try audit(
                fixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(
                    maximumTrustedCollectors: 1,
                    maximumObservations: scenarioCount,
                    maximumDifferencesPerScenario: 3,
                    maximumTotalDifferences: 86,
                    maximumRows: 18,
                    maximumBinaryMetadataBytes: 224
                )
            )
        )
        let failures: [(ComparisonResultCoverageError, ComparisonResultCoverageLimits)] = [
            (
                .countLimitExceeded(.observations, maximum: scenarioCount - 1),
                limits(maximumObservations: scenarioCount - 1)
            ),
            (
                .countLimitExceeded(.differencesPerScenario, maximum: 2),
                limits(maximumDifferencesPerScenario: 2)
            ),
            (
                .countLimitExceeded(.totalDifferences, maximum: 85),
                limits(maximumTotalDifferences: 85)
            ),
            (.invalidInventory(.semanticState), limits(maximumRows: 17)),
            (.binaryMetadataTooLarge(maximumBytes: 223), limits(maximumBinaryMetadataBytes: 223))
        ]
        for (error, constrainedLimits) in failures {
            assertCoverageError(error) {
                try audit(
                    fixture,
                    policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                    limits: constrainedLimits
                )
            }
        }

        let secondCollectorKey = try signingKey(0x23)
        let secondCollector = try ComparisonResultTrustedCollector(
            reference: revision("trusted-collector-2", 1),
            ed25519PublicKey: Array(secondCollectorKey.publicKey.rawRepresentation)
        )
        let twoCollectorVerifier = try ComparisonResultCoverageVerifier(
            authorityEd25519PublicKey: fixture.issuer.publicKey,
            trustedCollectors: [fixture.trustedCollector, secondCollector]
        )
        assertCoverageError(.countLimitExceeded(.trustedCollectors, maximum: 1)) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                verifier: twoCollectorVerifier,
                auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumTrustedCollectors: 1),
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        }

        let assertion = ComparisonResultEvidence(
            scenarioID: fixture.evidence.observations[0].scenarioID,
            lifecycle: fixture.evidence.observations[0].lifecycle,
            observed: fixture.evidence.observations[0].observed,
            origin: .callerAssertion,
            provenance: nil,
            accessibility: fixture.evidence.observations[0].accessibility
        )
        let twoFindingFixture = replacing(
            fixture,
            evidence: bundle(fixture, observations: fixture.evidence.observations + [assertion])
        )
        XCTAssertEqual(
            try audit(
                twoFindingFixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumFindings: 2)
            ).report.findings.count,
            2
        )
        assertCoverageError(.findingLimitExceeded(maximum: 1)) {
            try audit(
                twoFindingFixture,
                policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                limits: limits(maximumFindings: 1)
            )
        }
    }

    func testStringLimitsCountNormalizedUTF8PerValueAndInAggregate() throws {
        let exactSource = String(repeating: "é", count: 32)
        let exact = try makeFixture(source: exactSource)
        XCTAssertNoThrow(
            try audit(
                exact,
                policy: policy(ledger: ReplayLedger(), auditTime: exact.auditTime),
                limits: limits(maximumStringUTF8Bytes: 64)
            )
        )
        let decomposed = try makeFixture(source: String(repeating: "e\u{301}", count: 32))
        XCTAssertEqual(decomposed.evidence.observations[0].provenance?.source, exactSource)
        XCTAssertNoThrow(
            try audit(
                decomposed,
                policy: policy(ledger: ReplayLedger(), auditTime: decomposed.auditTime),
                limits: limits(maximumStringUTF8Bytes: 64)
            )
        )
        let tooLarge = try makeFixture(source: exactSource + "é")
        assertCoverageError(.stringTooLarge(.provenanceSource, maximumUTF8Bytes: 64)) {
            try audit(
                tooLarge,
                policy: policy(ledger: ReplayLedger(), auditTime: tooLarge.auditTime),
                limits: limits(maximumStringUTF8Bytes: 64)
            )
        }
        assertCoverageError(.totalStringsTooLarge(maximumUTF8Bytes: 1)) {
            try audit(
                exact,
                policy: policy(ledger: ReplayLedger(), auditTime: exact.auditTime),
                limits: limits(maximumStringUTF8Bytes: 64, maximumTotalStringUTF8Bytes: 1)
            )
        }
    }

    func testValidationRejectsStaleOwnersContentsAndChangedAuditPolicy() throws {
        let fixture = try makeFixture()
        let result = try audit(fixture)
        let staleBuildInventory = ComparisonResultCoverageInventory(
            reference: fixture.inventory.reference,
            build: revision("other-build", 1),
            buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
            requirements: fixture.inventory.requirements
        )
        assertCoverageError(.staleBuild) {
            try result.receipt.validateCurrent(
                inventory: staleBuildInventory,
                evidence: fixture.evidence,
                verifier: fixture.verifier,
                auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        }
        let staleInventory = ComparisonResultCoverageInventory(
            reference: revision("other-inventory", 1),
            build: fixture.inventory.build,
            buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
            requirements: fixture.inventory.requirements
        )
        assertCoverageError(.staleInventory) {
            try result.receipt.validateCurrent(
                inventory: staleInventory,
                evidence: fixture.evidence,
                verifier: fixture.verifier,
                auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        }
        let staleEvidence = ComparisonResultEvidenceBundle(
            reference: revision("other-evidence", 1),
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: fixture.evidence.observations
        )
        assertCoverageError(.staleEvidence) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: staleEvidence,
                verifier: fixture.verifier,
                auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        }

        var changedRequirements = fixture.inventory.requirements
        changedRequirements.swapAt(0, 1)
        let canonicalReorder = ComparisonResultCoverageInventory(
            reference: fixture.inventory.reference,
            build: fixture.inventory.build,
            buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
            requirements: changedRequirements
        )
        XCTAssertNoThrow(
            try result.receipt.validateCurrent(
                inventory: canonicalReorder,
                evidence: fixture.evidence,
                verifier: fixture.verifier,
                auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime),
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        )
        assertCoverageError(.receiptMismatch) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                verifier: fixture.verifier,
                auditPolicy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime + 1),
                captureResolver: resolver(fixture.captures),
                cancellationCheck: { false }
            )
        }
    }

    func testCancellationPrecedesResolverAndReplayClaim() throws {
        let ledger = ReplayLedger()
        let fixture = try makeFixture(ledger: ledger)
        let resolverProbe = InvocationProbe()
        assertCoverageError(.cancelled) {
            try audit(
                fixture,
                captureResolver: { _, _, _ in
                    resolverProbe.record()
                    return Data()
                },
                cancellationCheck: { true }
            )
        }
        XCTAssertEqual(resolverProbe.count, 0)
        XCTAssertEqual(ledger.invocationCount, 0)
        XCTAssertEqual(ledger.claimedCount, 0)
    }

    func testCancellationAfterResolverAndImmediatelyBeforeReplayNeverClaims() throws {
        let resolverLedger = ReplayLedger()
        let resolverFixture = try makeFixture(ledger: resolverLedger)
        let resolver = resolver(resolverFixture.captures)
        let didResolve = LockedFlag()
        assertCoverageError(.cancelled) {
            try audit(
                resolverFixture,
                captureResolver: { digest, maximum, cancellationCheck in
                    let data = try resolver(digest, maximum, cancellationCheck)
                    didResolve.set()
                    return data
                },
                cancellationCheck: { didResolve.value }
            )
        }
        XCTAssertEqual(resolverLedger.invocationCount, 0)

        let replayLedger = ReplayLedger()
        let replayFixture = try makeFixture(ledger: replayLedger)
        let baselineChecks = InvocationProbe()
        XCTAssertNoThrow(
            try audit(
                replayFixture,
                policy: policy(ledger: ReplayLedger(), auditTime: replayFixture.auditTime),
                limits: limits(cancellationCheckInterval: ComparisonResultCoverageLimits.hardMaximumCancellationCheckInterval),
                cancellationCheck: {
                    baselineChecks.record()
                    return false
                }
            )
        )
        let replayPolicy = ComparisonResultAuditPolicy(
            trustedAuditTimeUnixMilliseconds: replayFixture.auditTime,
            maximumCaptureAgeMilliseconds: 10_000,
            maximumFutureClockSkewMilliseconds: 500,
            replayPolicy: replayReference(),
            claimReplayNonces: { _, _ in
                XCTFail("Cancellation must precede replay authority")
                return false
            }
        )
        let checks = InvocationProbe()
        assertCoverageError(.cancelled) {
            try audit(
                replayFixture,
                policy: replayPolicy,
                limits: limits(cancellationCheckInterval: ComparisonResultCoverageLimits.hardMaximumCancellationCheckInterval),
                cancellationCheck: {
                    checks.record()
                    return checks.count >= baselineChecks.count
                }
            )
        }
        XCTAssertEqual(replayLedger.invocationCount, 0)
    }

    func testDefaultCancellationObservesCancelledTaskForAuditAndReceiptValidation() async throws {
        let fixture = try makeFixture()
        let result = try audit(
            fixture,
            policy: policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        )
        let auditPolicy = policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        let validationPolicy = policy(ledger: ReplayLedger(), auditTime: fixture.auditTime)
        let captureResolver = resolver(fixture.captures)
        let auditError = await Task { () -> ComparisonResultCoverageError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try Matrix.audit(
                    inventory: fixture.inventory,
                    evidence: fixture.evidence,
                    verifier: fixture.verifier,
                    auditPolicy: auditPolicy,
                    captureResolver: captureResolver
                )
                return nil
            } catch {
                return error as? ComparisonResultCoverageError
            }
        }.value
        XCTAssertEqual(auditError, .cancelled)

        let validationError = await Task { () -> ComparisonResultCoverageError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try result.receipt.validateCurrent(
                    inventory: fixture.inventory,
                    evidence: fixture.evidence,
                    verifier: fixture.verifier,
                    auditPolicy: validationPolicy,
                    captureResolver: captureResolver
                )
                return nil
            } catch {
                return error as? ComparisonResultCoverageError
            }
        }.value
        XCTAssertEqual(validationError, .cancelled)
    }

    func testDescriptionsReflectionAndDumpRedactSensitiveContents() throws {
        let fixture = try makeFixture(source: "TOP-SECRET-COLLECTOR-SOURCE")
        let result = try audit(fixture)
        let observation = fixture.evidence.observations[0]
        let values: [Any] = [
            fixture.issuer,
            fixture.verifier,
            fixture.trustedCollector,
            fixture.auditPolicy,
            fixture.inventory,
            fixture.inventory.requirements[0],
            try XCTUnwrap(fixture.inventory.requirements[0].accessibility),
            observation.lifecycle,
            try XCTUnwrap(observation.accessibility),
            try XCTUnwrap(observation.provenance),
            ComparisonResultReplayClaim(nonce: [UInt8](repeating: 0xA5, count: 16)),
            observation,
            fixture.evidence,
            result.report.matrix.cells[0],
            result.report,
            result.receipt,
            result
        ]
        let secrets = [
            "TOP-SECRET-COLLECTOR-SOURCE",
            hex(fixture.inventory.buildArtifactSHA256),
            hex(try XCTUnwrap(observation.provenance).runNonce),
            hex(try XCTUnwrap(observation.provenance).collectorSignature),
            try XCTUnwrap(observation.provenance).runNonce.description,
            try XCTUnwrap(observation.provenance).collectorSignature.description,
            observation.binding.comparisonIdentity.rawValue.uuidString,
            observation.lifecycle.binding.sources[0].identity.rawValue.uuidString
        ]
        for value in values {
            var dumped = ""
            dump(value, to: &dumped)
            let rendered = [String(describing: value), String(reflecting: value), dumped]
            for rendering in rendered {
                for secret in secrets {
                    XCTAssertFalse(rendering.contains(secret), "\(type(of: value)) leaked \(secret)")
                }
                XCTAssertTrue(rendering.contains("<redacted>") || rendering.contains("<opaque>"), "\(type(of: value))")
            }
        }
        XCTAssertEqual(
            ComparisonResultCoverageReport.scopeStatement,
            "Deterministic validation of bounded, caller-supplied, build- and generation-bound comparison-result measurements; not independent comparison-engine, UI, AppKit, AX, assistive-technology, or production-runtime verification."
        )
    }

    private struct Fixture {
        let issuer: ComparisonResultCoverageAuthorityIssuer
        let collectorPrivateKey: Curve25519.Signing.PrivateKey
        let trustedCollector: ComparisonResultTrustedCollector
        let verifier: ComparisonResultCoverageVerifier
        let inventory: ComparisonResultCoverageInventory
        let evidence: ComparisonResultEvidenceBundle
        let inventoryDigest: [UInt8]
        let captures: [[UInt8]: Data]
        let accessibilityReceipt: AccessibilityEvidenceReceipt
        let auditPolicy: ComparisonResultAuditPolicy
        let auditTime: UInt64
        let lifecycleSpecs: [ComparisonResultScenario: LifecycleSpec]
    }

    private struct AccessibilityFixture {
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

    private struct LifecycleSpec {
        let seed: UInt16
        let comparisonIdentityDelta: UInt16
        let inputGeneration: UInt64
        let leftGeneration: UInt64
        let middleGeneration: UInt64
        let rightGeneration: UInt64
        let inputIdentityDelta: UInt16
        let operationDelta: UInt16
        let resultDelta: UInt16
        let leftIdentityDelta: UInt16
        let middleIdentityDelta: UInt16
        let rightIdentityDelta: UInt16
        let isThreeWay: Bool

        init(
            seed: UInt16,
            comparisonIdentityDelta: UInt16 = 0,
            inputGeneration: UInt64 = 7,
            leftGeneration: UInt64 = 11,
            middleGeneration: UInt64 = 12,
            rightGeneration: UInt64 = 13,
            inputIdentityDelta: UInt16 = 1,
            operationDelta: UInt16 = 4,
            resultDelta: UInt16 = 5,
            leftIdentityDelta: UInt16 = 2,
            middleIdentityDelta: UInt16 = 6,
            rightIdentityDelta: UInt16 = 3,
            isThreeWay: Bool = false
        ) {
            self.seed = seed
            self.comparisonIdentityDelta = comparisonIdentityDelta
            self.inputGeneration = inputGeneration
            self.leftGeneration = leftGeneration
            self.middleGeneration = middleGeneration
            self.rightGeneration = rightGeneration
            self.inputIdentityDelta = inputIdentityDelta
            self.operationDelta = operationDelta
            self.resultDelta = resultDelta
            self.leftIdentityDelta = leftIdentityDelta
            self.middleIdentityDelta = middleIdentityDelta
            self.rightIdentityDelta = rightIdentityDelta
            self.isThreeWay = isThreeWay
        }

        func with(
            comparisonIdentityDelta: UInt16? = nil,
            inputIdentityDelta: UInt16? = nil,
            operationDelta: UInt16? = nil,
            resultDelta: UInt16? = nil,
            leftIdentityDelta: UInt16? = nil,
            middleIdentityDelta: UInt16? = nil,
            rightIdentityDelta: UInt16? = nil,
            inputGeneration: UInt64? = nil,
            leftGeneration: UInt64? = nil,
            middleGeneration: UInt64? = nil,
            rightGeneration: UInt64? = nil
        ) -> Self {
            Self(
                seed: seed,
                comparisonIdentityDelta: comparisonIdentityDelta ?? self.comparisonIdentityDelta,
                inputGeneration: inputGeneration ?? self.inputGeneration,
                leftGeneration: leftGeneration ?? self.leftGeneration,
                middleGeneration: middleGeneration ?? self.middleGeneration,
                rightGeneration: rightGeneration ?? self.rightGeneration,
                inputIdentityDelta: inputIdentityDelta ?? self.inputIdentityDelta,
                operationDelta: operationDelta ?? self.operationDelta,
                resultDelta: resultDelta ?? self.resultDelta,
                leftIdentityDelta: leftIdentityDelta ?? self.leftIdentityDelta,
                middleIdentityDelta: middleIdentityDelta ?? self.middleIdentityDelta,
                rightIdentityDelta: rightIdentityDelta ?? self.rightIdentityDelta,
                isThreeWay: isThreeWay
            )
        }
    }

    private func makeFixture(
        ledger: ReplayLedger = ReplayLedger(),
        source: String = "production-result-collector",
        isThreeWay: Bool = false,
        includesAccessibility: Bool = true
    ) throws -> Fixture {
        let issuer = try authority(0x11)
        let collectorKey = try signingKey(0x22)
        let collectorReference = revision("trusted-collector", 9)
        let trustedCollector = try ComparisonResultTrustedCollector(
            reference: collectorReference,
            ed25519PublicKey: Array(collectorKey.publicKey.rawRepresentation)
        )
        let verifier = try ComparisonResultCoverageVerifier(
            authorityEd25519PublicKey: issuer.publicKey,
            trustedCollectors: [trustedCollector]
        )
        let build = revision("production-build", 41)
        let inventoryReference = revision("result-inventory", 43)
        let artifact = digest(0xA1)
        let accessibilityReceipt = try makeAccessibilityReceipt(
            artifact: artifact,
            suffix: "primary",
            signing: digest(0xB2)
        )
        var requirements: [ComparisonResultCoverageRequirement] = []
        var specs: [ComparisonResultScenario: LifecycleSpec] = [:]
        for (index, scenario) in Matrix.canonicalScenarios.enumerated() {
            let spec = LifecycleSpec(seed: UInt16(100 + index * 10), isThreeWay: isThreeWay)
            specs[scenario] = spec
            let authenticatedLifecycle = try issuer.authenticateCurrentLifecycle(makeCurrentState(spec))
            let lifecycle =
                includesAccessibility
                ? authenticatedLifecycle
                : ComparisonResultLifecycleIdentityToken(
                    binding: authenticatedLifecycle.binding,
                    authorityID: issuer.authorityID,
                    signature: bytes(goldenLifecycleSignatures[index])
                )
            let accessibilityScenario = accessibilityReference("result-scenario-\(index)", UInt64(index + 1))
            let snapshotID = accessibilityID("result-snapshot-\(index)")
            let token = try issuer.authenticateAccessibilityInventory(
                receipt: accessibilityReceipt,
                scenario: accessibilityScenario,
                snapshotID: snapshotID
            )
            let accessibilityRequirement =
                includesAccessibility ? ComparisonResultAccessibilityRequirement(token: token) : nil
            requirements.append(
                try ComparisonResultCoverageRequirement(
                    scenario: scenario,
                    lifecycle: lifecycle,
                    expected: canonicalState(scenario),
                    accessibility: accessibilityRequirement
                )
            )
        }
        let inventory = try ComparisonResultCoverageInventory.canonical(
            reference: inventoryReference,
            build: build,
            buildArtifactSHA256: artifact,
            requirementsByScenario: Dictionary(uniqueKeysWithValues: requirements.map { ($0.scenario, $0) })
        )
        let preliminaryEvidence = ComparisonResultEvidenceBundle(
            reference: revision("preliminary-evidence", 1),
            inventory: inventoryReference,
            build: build,
            observations: requirements.map {
                ComparisonResultEvidence(
                    scenario: $0.scenario,
                    lifecycle: $0.lifecycle,
                    observed: $0.expected,
                    origin: .callerAssertion,
                    provenance: nil
                )
            }
        )
        let auditTime: UInt64 = 1_900_000_000_000
        let digestResult = try Matrix.audit(
            inventory: inventory,
            evidence: preliminaryEvidence,
            verifier: verifier,
            auditPolicy: policy(ledger: ReplayLedger(), auditTime: auditTime),
            captureResolver: { _, _, _ in
                XCTFail("Assertions must not resolve captures")
                return Data()
            },
            cancellationCheck: { false }
        )
        let inventoryDigest = digestResult.receipt.inventorySHA256
        var observations: [ComparisonResultEvidence] = []
        var captures: [[UInt8]: Data] = [:]
        for (index, requirement) in requirements.enumerated() {
            let accessibility: ComparisonResultAccessibilityEvidenceToken?
            if let requiredToken = requirement.accessibility?.token {
                accessibility = try issuer.authenticateAccessibilityEvidence(
                    receipt: accessibilityReceipt,
                    scenario: requiredToken.scenario,
                    snapshotID: requiredToken.snapshotID
                )
            } else {
                accessibility = nil
            }
            let observation = try measuredObservation(
                scenarioID: requirement.id,
                lifecycle: requirement.lifecycle,
                observed: requirement.expected,
                accessibility: accessibility,
                build: build,
                inventory: inventoryReference,
                inventoryDigest: inventoryDigest,
                artifact: artifact,
                collector: collectorReference,
                collectorPrivateKey: collectorKey,
                capturedAt: auditTime - UInt64(index),
                nonce: nonce(index + 1),
                source: source,
                collectorSignature: includesAccessibility
                    ? nil : bytes(goldenCollectorSignatures[index])
            )
            let capture = try Matrix.canonicalCaptureData(for: observation)
            captures[sha256(capture)] = capture
            observations.append(observation)
        }
        let evidence = ComparisonResultEvidenceBundle(
            reference: revision("result-evidence", 47),
            inventory: inventoryReference,
            build: build,
            observations: observations
        )
        let auditPolicy = policy(ledger: ledger, auditTime: auditTime)
        return Fixture(
            issuer: issuer,
            collectorPrivateKey: collectorKey,
            trustedCollector: trustedCollector,
            verifier: verifier,
            inventory: inventory,
            evidence: evidence,
            inventoryDigest: inventoryDigest,
            captures: captures,
            accessibilityReceipt: accessibilityReceipt,
            auditPolicy: auditPolicy,
            auditTime: auditTime,
            lifecycleSpecs: specs
        )
    }

    private func audit(
        _ fixture: Fixture,
        policy suppliedPolicy: ComparisonResultAuditPolicy? = nil,
        limits: ComparisonResultCoverageLimits = .default,
        captureResolver suppliedResolver: ComparisonResultCoverageMatrix.CaptureResolver? = nil,
        cancellationCheck: @escaping ComparisonResultCoverageMatrix.CancellationCheck = { false }
    ) throws -> ComparisonResultCoverageResult {
        try Matrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            verifier: fixture.verifier,
            auditPolicy: suppliedPolicy ?? fixture.auditPolicy,
            limits: limits,
            captureResolver: suppliedResolver ?? resolver(fixture.captures),
            cancellationCheck: cancellationCheck
        )
    }

    private func replacing(
        _ fixture: Fixture,
        evidence: ComparisonResultEvidenceBundle
    ) -> Fixture {
        Fixture(
            issuer: fixture.issuer,
            collectorPrivateKey: fixture.collectorPrivateKey,
            trustedCollector: fixture.trustedCollector,
            verifier: fixture.verifier,
            inventory: fixture.inventory,
            evidence: evidence,
            inventoryDigest: fixture.inventoryDigest,
            captures: fixture.captures,
            accessibilityReceipt: fixture.accessibilityReceipt,
            auditPolicy: fixture.auditPolicy,
            auditTime: fixture.auditTime,
            lifecycleSpecs: fixture.lifecycleSpecs
        )
    }

    private func replacing(
        _ fixture: Fixture,
        observationAt index: Int,
        with observation: ComparisonResultEvidence
    ) -> Fixture {
        var observations = fixture.evidence.observations
        observations[index] = observation
        var captures = fixture.captures
        if let provenance = observation.provenance {
            captures[provenance.captureSHA256] = try? Matrix.canonicalCaptureData(for: observation)
        }
        let replacement = replacing(fixture, evidence: bundle(fixture, observations: observations))
        return Fixture(
            issuer: replacement.issuer,
            collectorPrivateKey: replacement.collectorPrivateKey,
            trustedCollector: replacement.trustedCollector,
            verifier: replacement.verifier,
            inventory: replacement.inventory,
            evidence: replacement.evidence,
            inventoryDigest: replacement.inventoryDigest,
            captures: captures,
            accessibilityReceipt: replacement.accessibilityReceipt,
            auditPolicy: replacement.auditPolicy,
            auditTime: replacement.auditTime,
            lifecycleSpecs: replacement.lifecycleSpecs
        )
    }

    private func bundle(
        _ fixture: Fixture,
        observations: [ComparisonResultEvidence]
    ) -> ComparisonResultEvidenceBundle {
        ComparisonResultEvidenceBundle(
            reference: fixture.evidence.reference,
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: observations
        )
    }

    private func resign(
        _ observation: ComparisonResultEvidence,
        fixture: Fixture,
        lifecycle: ComparisonResultLifecycleIdentityToken? = nil,
        observed: ComparisonResultSemanticState? = nil,
        accessibility: ComparisonResultAccessibilityEvidenceToken?? = nil,
        origin: ComparisonResultEvidenceOrigin? = nil,
        build: ComparisonResultRevisionReference? = nil,
        inventory: ComparisonResultRevisionReference? = nil,
        inventoryDigest: [UInt8]? = nil,
        artifact: [UInt8]? = nil,
        collector: ComparisonResultRevisionReference? = nil,
        capturedAt: UInt64? = nil,
        nonce: [UInt8]? = nil,
        source: String? = nil,
        captureSHA256: [UInt8]? = nil,
        collectorPrivateKey: Curve25519.Signing.PrivateKey? = nil
    ) throws -> ComparisonResultEvidence {
        let provenance = try XCTUnwrap(observation.provenance)
        return try measuredObservation(
            scenarioID: observation.scenarioID,
            lifecycle: lifecycle ?? observation.lifecycle,
            observed: observed ?? observation.observed,
            accessibility: accessibility ?? observation.accessibility,
            origin: origin ?? observation.origin,
            build: build ?? provenance.build,
            inventory: inventory ?? provenance.inventory,
            inventoryDigest: inventoryDigest ?? provenance.inventorySHA256,
            artifact: artifact ?? provenance.artifactSHA256,
            collector: collector ?? provenance.collector,
            collectorPrivateKey: collectorPrivateKey ?? fixture.collectorPrivateKey,
            capturedAt: capturedAt ?? provenance.capturedAtUnixMilliseconds,
            nonce: nonce ?? provenance.runNonce,
            source: source ?? provenance.source,
            captureSHA256: captureSHA256
        )
    }

    private func replacingProvenance(
        _ observation: ComparisonResultEvidence,
        _ provenance: ComparisonResultEvidenceProvenance,
        capturedAt: UInt64? = nil,
        nonce: [UInt8]? = nil,
        captureSHA256: [UInt8]? = nil,
        collectorSignature: [UInt8]? = nil,
        source: String? = nil
    ) -> ComparisonResultEvidence {
        ComparisonResultEvidence(
            scenarioID: observation.scenarioID,
            lifecycle: observation.lifecycle,
            observed: observation.observed,
            origin: observation.origin,
            provenance: ComparisonResultEvidenceProvenance(
                build: provenance.build,
                inventory: provenance.inventory,
                collector: provenance.collector,
                capturedAtUnixMilliseconds: capturedAt ?? provenance.capturedAtUnixMilliseconds,
                runNonce: nonce ?? provenance.runNonce,
                artifactSHA256: provenance.artifactSHA256,
                inventorySHA256: provenance.inventorySHA256,
                captureSHA256: captureSHA256 ?? provenance.captureSHA256,
                collectorSignature: collectorSignature ?? provenance.collectorSignature,
                source: source ?? provenance.source
            ),
            accessibility: observation.accessibility
        )
    }

    private func measuredObservation(
        scenarioID: ComparisonResultScenarioID,
        lifecycle: ComparisonResultLifecycleIdentityToken,
        observed: ComparisonResultSemanticState,
        accessibility: ComparisonResultAccessibilityEvidenceToken?,
        origin: ComparisonResultEvidenceOrigin = .productionAutomatedMeasurement,
        build: ComparisonResultRevisionReference,
        inventory: ComparisonResultRevisionReference,
        inventoryDigest: [UInt8],
        artifact: [UInt8],
        collector: ComparisonResultRevisionReference,
        collectorPrivateKey: Curve25519.Signing.PrivateKey,
        capturedAt: UInt64,
        nonce: [UInt8],
        source: String,
        collectorSignature suppliedCollectorSignature: [UInt8]? = nil,
        captureSHA256 suppliedCaptureSHA256: [UInt8]? = nil
    ) throws -> ComparisonResultEvidence {
        let unsignedProvenance = ComparisonResultEvidenceProvenance(
            build: build,
            inventory: inventory,
            collector: collector,
            capturedAtUnixMilliseconds: capturedAt,
            runNonce: nonce,
            artifactSHA256: artifact,
            inventorySHA256: inventoryDigest,
            captureSHA256: suppliedCaptureSHA256 ?? digest(0xCC),
            collectorSignature: [UInt8](repeating: 0xDD, count: 64),
            source: source
        )
        var observation = ComparisonResultEvidence(
            scenarioID: scenarioID,
            lifecycle: lifecycle,
            observed: observed,
            origin: origin,
            provenance: unsignedProvenance,
            accessibility: accessibility
        )
        let canonicalCaptureDigest = sha256(try Matrix.canonicalCaptureData(for: observation))
        let captureDigest = suppliedCaptureSHA256 ?? canonicalCaptureDigest
        let provenance = ComparisonResultEvidenceProvenance(
            build: build,
            inventory: inventory,
            collector: collector,
            capturedAtUnixMilliseconds: capturedAt,
            runNonce: nonce,
            artifactSHA256: artifact,
            inventorySHA256: inventoryDigest,
            captureSHA256: captureDigest,
            collectorSignature: [UInt8](repeating: 0xDD, count: 64),
            source: source
        )
        observation = ComparisonResultEvidence(
            scenarioID: scenarioID,
            lifecycle: lifecycle,
            observed: observed,
            origin: origin,
            provenance: provenance,
            accessibility: accessibility
        )
        let signature =
            try suppliedCollectorSignature
            ?? Array(
                collectorPrivateKey.signature(
                    for: Matrix.canonicalCaptureEnvelopeData(for: observation)
                )
            )
        let signed = ComparisonResultEvidenceProvenance(
            build: build,
            inventory: inventory,
            collector: collector,
            capturedAtUnixMilliseconds: capturedAt,
            runNonce: nonce,
            artifactSHA256: artifact,
            inventorySHA256: inventoryDigest,
            captureSHA256: captureDigest,
            collectorSignature: signature,
            source: source
        )
        return ComparisonResultEvidence(
            scenarioID: scenarioID,
            lifecycle: lifecycle,
            observed: observed,
            origin: origin,
            provenance: signed,
            accessibility: accessibility
        )
    }

    private func canonicalState(
        _ scenario: ComparisonResultScenario
    ) throws -> ComparisonResultSemanticState {
        let differences = try standardDifferences()
        switch scenario {
        case .identical:
            return try semanticState(
                outcome: .identical,
                differences: [],
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(false, false, false, false)
            )
        case .differentWithoutSelection:
            return try semanticState(
                differences: [try difference("only", 0, 6..<9)],
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, false, true, true)
            )
        case .firstSelectedAtStart:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[0].id),
                cursor: .row(index: 2, differenceID: differences[0].id),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, true, false, true)
            )
        case .middleSelectedAtStart:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 7, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, true, true, true)
            )
        case .lastSelectedAtEnd:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[2].id),
                cursor: .row(index: 14, differenceID: differences[2].id),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, true, true, false)
            )
        case .cursorAtDifferenceStart:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 7, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 5..<11,
                command: command(true, true, true, true)
            )
        case .cursorAtDifferenceEnd:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 9, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 5..<11,
                command: command(true, true, true, true)
            )
        case .cursorBeforeFirstDifference:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 0, differenceID: nil),
                alignedRows: 18,
                visibleRows: 0..<2,
                command: command(true, false, false, true)
            )
        case .cursorAfterLastDifference:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 17, differenceID: nil),
                alignedRows: 18,
                visibleRows: 16..<18,
                command: command(true, false, true, false)
            )
        case .selectionVisibleWithoutCursor:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                alignedRows: 18,
                visibleRows: 6..<11,
                command: command(true, true, true, true)
            )
        case .selectionVisibleWithCursorOnOtherDifference:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 2, differenceID: differences[0].id),
                alignedRows: 18,
                visibleRows: 1..<11,
                command: command(true, true, true, true)
            )
        case .selectionVisibleWithCursorOnUnchangedRow:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 5, differenceID: nil),
                alignedRows: 18,
                visibleRows: 5..<11,
                command: command(true, true, true, true)
            )
        case .selectionOffscreenWithCursorBefore:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[2].id),
                cursor: .row(index: 2, differenceID: differences[0].id),
                alignedRows: 18,
                visibleRows: 0..<5,
                command: command(true, true, false, true)
            )
        case .selectionOffscreenWithCursorAfter:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[0].id),
                cursor: .row(index: 13, differenceID: differences[2].id),
                alignedRows: 18,
                visibleRows: 12..<16,
                command: command(true, true, true, false)
            )
        case .selectionOffscreenWithoutCursor:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                alignedRows: 18,
                visibleRows: 0..<5,
                command: command(true, true, true, true)
            )
        case .cursorBetweenDifferences:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 5, differenceID: nil),
                alignedRows: 18,
                visibleRows: 4..<7,
                command: command(true, false, true, true)
            )
        }
    }

    private func scenarioNearMiss(
        _ scenario: ComparisonResultScenario
    ) throws -> ComparisonResultSemanticState {
        let differences = try standardDifferences()
        switch scenario {
        case .identical:
            return try semanticState(
                outcome: .identical,
                differences: [],
                cursor: .row(index: 0, differenceID: nil),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(false, false, false, false)
            )
        case .differentWithoutSelection:
            return try semanticState(
                differences: [try difference("only", 0, 6..<9)],
                cursor: .row(index: 0, differenceID: nil),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, false, false, true)
            )
        case .firstSelectedAtStart:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[0].id),
                cursor: .row(index: 3, differenceID: differences[0].id),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, true, false, true)
            )
        case .middleSelectedAtStart:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 9, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, true, true, true)
            )
        case .lastSelectedAtEnd:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[2].id),
                cursor: .row(index: 13, differenceID: differences[2].id),
                alignedRows: 18,
                visibleRows: 0..<18,
                command: command(true, true, true, false)
            )
        case .cursorAtDifferenceStart:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 9, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 5..<11,
                command: command(true, true, true, true)
            )
        case .cursorAtDifferenceEnd:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 7, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 5..<11,
                command: command(true, true, true, true)
            )
        case .cursorBeforeFirstDifference:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 17, differenceID: nil),
                alignedRows: 18,
                visibleRows: 16..<18,
                command: command(true, false, true, false)
            )
        case .cursorAfterLastDifference:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 0, differenceID: nil),
                alignedRows: 18,
                visibleRows: 0..<2,
                command: command(true, false, false, true)
            )
        case .selectionVisibleWithoutCursor:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 7, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 6..<11,
                command: command(true, true, true, true)
            )
        case .selectionVisibleWithCursorOnOtherDifference:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 7, differenceID: differences[1].id),
                alignedRows: 18,
                visibleRows: 1..<11,
                command: command(true, true, true, true)
            )
        case .selectionVisibleWithCursorOnUnchangedRow:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 2, differenceID: differences[0].id),
                alignedRows: 18,
                visibleRows: 1..<11,
                command: command(true, true, true, true)
            )
        case .selectionOffscreenWithCursorBefore:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[2].id),
                cursor: .row(index: 16, differenceID: nil),
                alignedRows: 18,
                visibleRows: 16..<18,
                command: command(true, true, true, false)
            )
        case .selectionOffscreenWithCursorAfter:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[0].id),
                cursor: .row(index: 0, differenceID: nil),
                alignedRows: 18,
                visibleRows: 0..<2,
                command: command(true, true, false, true)
            )
        case .selectionOffscreenWithoutCursor:
            return try semanticState(
                differences: differences,
                selection: .difference(differences[1].id),
                cursor: .row(index: 17, differenceID: nil),
                alignedRows: 18,
                visibleRows: 16..<18,
                command: command(true, true, true, false)
            )
        case .cursorBetweenDifferences:
            return try semanticState(
                differences: differences,
                cursor: .row(index: 0, differenceID: nil),
                alignedRows: 18,
                visibleRows: 0..<2,
                command: command(true, false, false, true)
            )
        }
    }

    private func semanticState(
        outcome: ComparisonResultOutcome = .different,
        differences: [ComparisonResultDifference],
        selection: ComparisonResultSelectionState = .none,
        cursor: ComparisonResultCursorState = .none,
        alignedRows: Int,
        visibleRows: Range<Int>,
        command: ComparisonResultCommandState
    ) throws -> ComparisonResultSemanticState {
        try ComparisonResultSemanticState(
            outcome: outcome,
            differences: differences,
            selection: selection,
            cursor: cursor,
            viewport: ComparisonResultViewportState(
                alignedRowCount: alignedRows,
                visibleRows: visibleRows
            ),
            commandState: command
        )
    }

    private func standardDifferences() throws -> [ComparisonResultDifference] {
        [
            try difference("d0", 0, 2..<4),
            try difference("d1", 1, 7..<10),
            try difference("d2", 2, 13..<15)
        ]
    }

    private func difference(
        _ id: String,
        _ ordinal: Int,
        _ rows: Range<Int>
    ) throws -> ComparisonResultDifference {
        try ComparisonResultDifference(
            id: stable(id),
            ordinal: ordinal,
            rowRange: rows
        )
    }

    private func command(
        _ differences: Bool,
        _ resolvable: Bool,
        _ previous: Bool,
        _ next: Bool
    ) -> ComparisonResultCommandState {
        ComparisonResultCommandState(
            hasSignificantDifferences: differences,
            hasResolvableDifference: resolvable,
            navigation: navigation(differences, resolvable, previous, next, differences)
        )
    }

    private func navigation(
        _ first: Bool,
        _ current: Bool,
        _ previous: Bool,
        _ next: Bool,
        _ last: Bool
    ) -> ComparisonResultNavigationCommandState {
        ComparisonResultNavigationCommandState(
            first: first,
            current: current,
            previous: previous,
            next: next,
            last: last
        )
    }

    private func makeCurrentState(_ spec: LifecycleSpec) throws -> State {
        let empty = try State(identity: comparisonIdentity(spec.seed + spec.comparisonIdentityDelta))
        let loading = try empty.applying(
            .beginLoading(
                expected: empty.fingerprint,
                inputs: makeInputs(spec),
                operationID: operationID(spec.seed + spec.operationDelta),
                declaredWorkUnits: 17,
                progress: .pending
            )
        )
        return try loading.applying(
            .complete(
                expected: loading.fingerprint,
                operation: try XCTUnwrap(loading.operation?.token),
                resultID: resultID(spec.seed + spec.resultDelta)
            )
        )
    }

    private func beginLoading(
        _ state: State,
        inputs: State.InputBinding,
        operationDelta: UInt16 = 4
    ) throws -> State {
        try state.applying(
            .beginLoading(
                expected: state.fingerprint,
                inputs: inputs,
                operationID: operationID(uuidTail(inputs.identity.rawValue) - 1 + operationDelta),
                declaredWorkUnits: 17,
                progress: .pending
            )
        )
    }

    private func makeInputs(_ spec: LifecycleSpec) throws -> State.InputBinding {
        var sides = [
            State.SideBinding(
                side: .right,
                identity: sideIdentity(spec.seed + spec.rightIdentityDelta),
                generation: spec.rightGeneration
            ),
            State.SideBinding(
                side: .left,
                identity: sideIdentity(spec.seed + spec.leftIdentityDelta),
                generation: spec.leftGeneration
            )
        ]
        if spec.isThreeWay {
            sides.append(
                State.SideBinding(
                    side: .middle,
                    identity: sideIdentity(spec.seed + spec.middleIdentityDelta),
                    generation: spec.middleGeneration
                )
            )
        }
        return try State.InputBinding(
            identity: inputIdentity(spec.seed + spec.inputIdentityDelta),
            generation: spec.inputGeneration,
            sides: sides
        )
    }

    private func binding(
        sources: [ComparisonResultSourceBinding]
    ) throws -> ComparisonResultComparisonBinding {
        try ComparisonResultComparisonBinding(
            comparisonIdentity: comparisonIdentity(1),
            comparisonGeneration: 2,
            inputIdentity: inputIdentity(3),
            inputGeneration: 4,
            operationID: operationID(5),
            operationStartedAtGeneration: 6,
            resultIdentity: resultID(7),
            resultGeneration: 8,
            sources: sources
        )
    }

    private func source(
        _ side: State.Side,
        identity: UInt16,
        generation: UInt64
    ) -> ComparisonResultSourceBinding {
        ComparisonResultSourceBinding(
            side: side,
            identity: sideIdentity(identity),
            generation: generation
        )
    }

    private func makeAccessibilityReceipt(
        artifact: [UInt8],
        suffix: String,
        signing: [UInt8]
    ) throws -> AccessibilityEvidenceReceipt {
        let fixture = try makeAccessibilityFixture(
            artifact: artifact,
            suffix: suffix,
            signing: signing
        )
        let result = try AccessibilityEvidenceWorkflow.evaluate(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            attachmentResolver: fixture.resolver,
            cancellationCheck: { false }
        )
        XCTAssertTrue(result.report.isEvidenceCompleteAndValid)
        XCTAssertEqual(result.receipt.completeEvidenceCount, result.receipt.requiredEvidenceCount)
        XCTAssertEqual(result.receipt.findingCount, 0)
        return result.receipt
    }

    private func makeAccessibilityFixture(
        artifact: [UInt8],
        suffix: String,
        signing: [UInt8],
        removesObservation: Bool = false
    ) throws -> AccessibilityFixture {
        let app = accessibilityReference("app-\(suffix)", 3)
        let build = accessibilityReference("build-\(suffix)", 5)
        let inventoryReference = accessibilityReference("inventory-\(suffix)", 7)
        let buildBinding = AccessibilityEvidenceBuildBinding(
            artifactSHA256: artifact,
            signingIdentitySHA256: signing
        )
        let light = try accessibilityScenario(suffix: suffix, appearance: .light, build: build, buildBinding: buildBinding)
        let dark = try accessibilityScenario(suffix: suffix, appearance: .dark, build: build, buildBinding: buildBinding)
        let scenarios = [light.inventory, dark.inventory]
        let controlID = accessibilityID("control-\(suffix)")
        let inventory = AccessibilityProductionControlInventory(
            app: app,
            build: build,
            buildBinding: buildBinding,
            reference: inventoryReference,
            controls: [AccessibilityProductionControl(id: controlID, scenarioIDs: scenarios.map(\.id))],
            scenarios: scenarios
        )
        var evidenceScenarios = [light.evidence, dark.evidence]
        if removesObservation {
            let first = evidenceScenarios[0]
            evidenceScenarios[0] = AccessibilityScenarioEvidence(
                scenario: first.scenario,
                environment: first.environment,
                provenance: first.provenance,
                snapshot: first.snapshot,
                observations: Array(first.observations.dropFirst())
            )
        }
        let bare = AccessibilityEvidenceBundle(
            reference: accessibilityReference("evidence-\(suffix)", 11),
            app: app,
            build: build,
            buildBinding: buildBinding,
            inventory: inventoryReference,
            scenarios: evidenceScenarios
        )
        var attachmentData: [AccessibilityStableID: Data] = [:]
        var attachments: [AccessibilityEvidenceAttachment] = []
        for scenario in bare.scenarios {
            for observation in scenario.observations {
                let data = try AccessibilityEvidenceWorkflow.canonicalAttachmentData(
                    for: observation,
                    capturedIn: scenario,
                    cancellationCheck: { false }
                )
                for token in observation.attachmentTokens {
                    attachmentData[token] = data
                    attachments.append(
                        AccessibilityEvidenceAttachment(
                            id: token,
                            kind: .measurementRecord,
                            mediaType: "application/vnd.macmerge.accessibility-observation",
                            byteCount: data.count,
                            sha256: sha256(data),
                            source: "accessibility-collector-\(suffix)"
                        )
                    )
                }
            }
        }
        let evidence = AccessibilityEvidenceBundle(
            reference: bare.reference,
            app: bare.app,
            build: bare.build,
            buildBinding: bare.buildBinding,
            inventory: bare.inventory,
            scenarios: bare.scenarios,
            attachments: attachments
        )
        return AccessibilityFixture(
            inventory: inventory,
            evidence: evidence,
            attachmentData: attachmentData
        )
    }

    private func accessibilityScenario(
        suffix: String,
        appearance: AccessibilityEvidenceAppearance,
        build: AccessibilityEvidenceRevisionReference,
        buildBinding: AccessibilityEvidenceBuildBinding
    ) throws -> (
        inventory: AccessibilityEvidenceInventoryScenario,
        evidence: AccessibilityScenarioEvidence
    ) {
        let name = "\(suffix)-\(appearance.rawValue)"
        let scenarioReference = accessibilityReference("scenario-\(name)", 1)
        let controlID = accessibilityID("control-\(suffix)")
        let root = AccessibilitySemanticElement(
            id: accessibilityID("root-\(name)"),
            role: .application,
            label: "Application"
        )
        let control = AccessibilitySemanticElement(
            id: controlID,
            parentID: root.id,
            role: .button,
            label: "Compare",
            hint: "Runs comparison",
            isKeyboardFocusable: true,
            actions: [
                AccessibilitySemanticAction(
                    id: accessibilityID("action-\(suffix)"),
                    kind: .activate,
                    label: "Activate"
                )
            ],
            keyboardShortcuts: [
                AccessibilityKeyboardShortcut(
                    id: accessibilityID("shortcut-\(suffix)"),
                    key: "k",
                    modifiers: [.command],
                    actionID: accessibilityID("action-\(suffix)"),
                    discoverabilityTitle: "Compare"
                )
            ]
        )
        let snapshot = AccessibilityCommandControlSnapshot(
            id: accessibilityID("snapshot-\(name)"),
            rootElementID: root.id,
            elements: [root, control],
            focusOrder: [controlID]
        )
        let environment = AccessibilityEvidenceEnvironment(
            fullKeyboardAccessEnabled: true,
            voiceOverEnabled: true,
            increasedContrastEnabled: true,
            differentiateWithoutColorEnabled: true,
            appearance: appearance,
            localeIdentifier: "en-US",
            localizationExpansionThousandths: 2_000
        )
        let checks: Set<AccessibilityEvidenceEnvironmentCheck> =
            appearance == .dark
            ? Set(AccessibilityEvidenceEnvironmentCheck.allCases)
            : [.fullKeyboardAccess, .voiceOverActivation, .increasedContrast, .differentiateWithoutColor, .localizationExpansion]
        let inventory = AccessibilityEvidenceInventoryScenario(
            reference: scenarioReference,
            environment: environment,
            expectedSnapshot: snapshot,
            requiredEnvironmentChecks: checks,
            actionPostconditions: [
                AccessibilityEvidenceActionPostcondition(
                    actionID: accessibilityID("action-\(suffix)"),
                    snapshotSHA256: sha256(try AccessibilityAudit.exactSnapshotData(of: snapshot))
                )
            ]
        )
        let provenance = AccessibilityEvidenceCaptureProvenance(
            capturedAtUnixMilliseconds: appearance == .light ? 1_800_000_000_001 : 1_800_000_000_002,
            runNonce: [UInt8](repeating: appearance == .light ? 1 : 2, count: 16),
            collector: accessibilityReference("collector-\(suffix)", 13),
            build: build,
            buildBinding: buildBinding
        )
        let observations = accessibilityObservations(
            scenario: inventory,
            snapshot: snapshot,
            suffix: name
        )
        return (
            inventory,
            AccessibilityScenarioEvidence(
                scenario: scenarioReference,
                environment: environment,
                provenance: provenance,
                snapshot: snapshot,
                observations: observations
            )
        )
    }

    private func accessibilityObservations(
        scenario: AccessibilityEvidenceInventoryScenario,
        snapshot: AccessibilityCommandControlSnapshot,
        suffix: String
    ) -> [AccessibilityBehaviorObservation] {
        typealias Record = (
            AccessibilityEvidenceRequirementKey,
            AccessibilityEvidenceValue,
            AccessibilityCommandControlSnapshot?
        )
        var records: [Record] = [
            (accessibilityKey(scenario.id, .semanticSnapshot), .snapshot(snapshot.id), nil),
            (accessibilityKey(scenario.id, .focusOrder), .focusOrder(snapshot.focusOrder), nil)
        ]
        for element in snapshot.elements {
            records += [
                (accessibilityKey(scenario.id, .semanticRole, element.id), .semanticRole(element.role), nil),
                (accessibilityKey(scenario.id, .semanticLabel, element.id), .semanticLabel(element.label), nil),
                (accessibilityKey(scenario.id, .semanticHierarchy, element.id), .parentID(element.parentID), nil),
                (accessibilityKey(scenario.id, .hiddenState, element.id), .hidden(element.isHiddenFromAssistiveTechnology), nil),
                (accessibilityKey(scenario.id, .focusability, element.id), .focusable(element.isKeyboardFocusable), nil),
                (accessibilityKey(scenario.id, .keyboardShortcuts, element.id), .keyboardShortcuts(element.keyboardShortcuts.map(\.id)), nil),
                (accessibilityKey(scenario.id, .enabledState, element.id), .enabled(element.isEnabled), nil),
                (accessibilityKey(scenario.id, .checkedState, element.id), .checked(element.checkedState), nil),
                (accessibilityKey(scenario.id, .selectedState, element.id), .selected(element.selectedState), nil),
                (accessibilityKey(scenario.id, .value, element.id), .value(element.value), nil),
                (accessibilityKey(scenario.id, .hint, element.id), .hint(element.hint), nil)
            ]
            for action in element.actions {
                let value = AccessibilityEvidenceValue.action(
                    actionID: action.id,
                    kind: action.kind,
                    outcome: .performed
                )
                records += [
                    (accessibilityKey(scenario.id, .actionBehavior, element.id, action.id), value, snapshot),
                    (accessibilityKey(scenario.id, .fullKeyboardAccess, element.id, action.id), value, snapshot),
                    (accessibilityKey(scenario.id, .voiceOverActivation, element.id, action.id), value, snapshot)
                ]
            }
            let emptyChecks: [(AccessibilityEvidenceRequirementKind, AccessibilityEvidenceConditionOutcome)] = [
                (.increasedContrast, .notApplicable),
                (.differentiateWithoutColor, .notApplicable),
                (.localizationExpansion, .notSatisfied)
            ]
            for (kind, outcome) in emptyChecks where scenario.requiredEnvironmentChecks.contains(check(for: kind)) {
                records.append((accessibilityKey(scenario.id, kind, element.id), .condition(outcome), nil))
            }
            if scenario.requiredEnvironmentChecks.contains(.darkMode) {
                records.append((accessibilityKey(scenario.id, .darkMode, element.id), .condition(.notSatisfied), nil))
            }
            if element.actions.isEmpty {
                records.append((accessibilityKey(scenario.id, .fullKeyboardAccess, element.id), .condition(.notApplicable), nil))
                records.append((accessibilityKey(scenario.id, .voiceOverActivation, element.id), .condition(.notApplicable), nil))
            } else {
                records.append((accessibilityKey(scenario.id, .voiceOverActivation, element.id), .condition(.satisfied), nil))
            }
        }
        return records.enumerated().map { index, record in
            AccessibilityBehaviorObservation(
                id: accessibilityID("observation-\(suffix)-\(index)"),
                requirement: record.0,
                snapshotID: snapshot.id,
                value: record.1,
                origin: .automatedMeasurement,
                source: "accessibility-collector-\(suffix)",
                attachmentTokens: [accessibilityID("attachment-\(suffix)-\(index)")],
                postconditionSnapshot: record.2
            )
        }
    }

    private func check(
        for kind: AccessibilityEvidenceRequirementKind
    ) -> AccessibilityEvidenceEnvironmentCheck {
        switch kind {
        case .increasedContrast: .increasedContrast
        case .differentiateWithoutColor: .differentiateWithoutColor
        case .localizationExpansion: .localizationExpansion
        default: preconditionFailure("Unexpected scoped requirement")
        }
    }

    private func accessibilityKey(
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

    private func policy(
        ledger: ReplayLedger,
        auditTime: UInt64,
        maximumAge: UInt64 = 10_000,
        futureSkew: UInt64 = 500,
        replayPolicy: ComparisonResultRevisionReference? = nil
    ) -> ComparisonResultAuditPolicy {
        ComparisonResultAuditPolicy(
            trustedAuditTimeUnixMilliseconds: auditTime,
            maximumCaptureAgeMilliseconds: maximumAge,
            maximumFutureClockSkewMilliseconds: futureSkew,
            replayPolicy: replayPolicy ?? replayReference(),
            claimReplayNonces: { revision, claims in ledger.claim(revision, claims) }
        )
    }

    private func replayReference() -> ComparisonResultRevisionReference {
        revision("replay-policy", 2)
    }

    private func resolver(
        _ captures: [[UInt8]: Data]
    ) -> ComparisonResultCoverageMatrix.CaptureResolver {
        { digest, maximumByteCount, cancellationCheck in
            if cancellationCheck() { throw CancellationError() }
            guard let data = captures[digest] else {
                throw ComparisonResultCaptureResolutionError.resourceUnavailable
            }
            guard data.count <= maximumByteCount else {
                throw ComparisonResultCaptureResolutionError.exceedsMaximumByteCount
            }
            return data
        }
    }

    private func limits(
        maximumTrustedCollectors: Int = 64,
        maximumObservations: Int = 4_096,
        maximumDifferencesPerScenario: Int = 65_536,
        maximumTotalDifferences: Int = 262_144,
        maximumRows: Int = 1_048_576,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
        maximumBinaryMetadataBytes: Int = 512,
        maximumWorkUnits: Int = 64 * 1_048_576,
        maximumFindings: Int = 4_096,
        maximumCanonicalBytes: Int = 8 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) -> ComparisonResultCoverageLimits {
        ComparisonResultCoverageLimits(
            maximumTrustedCollectors: maximumTrustedCollectors,
            maximumObservations: maximumObservations,
            maximumDifferencesPerScenario: maximumDifferencesPerScenario,
            maximumTotalDifferences: maximumTotalDifferences,
            maximumRows: maximumRows,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumBinaryMetadataBytes: maximumBinaryMetadataBytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumFindings: maximumFindings,
            maximumCanonicalBytes: maximumCanonicalBytes,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func minimumSuccessfulLimit<Result>(
        lower: Int,
        upper: Int,
        operation: (Int) throws -> Result
    ) throws -> Int {
        var low = lower
        var high = upper
        while low < high {
            let middle = low + (high - low) / 2
            do {
                _ = try operation(middle)
                high = middle
            } catch ComparisonResultCoverageError.workLimitExceeded,
                ComparisonResultCoverageError.canonicalDataTooLarge
            {
                low = middle + 1
            }
        }
        _ = try operation(low)
        return low
    }

    private func authority(_ seed: UInt8) throws -> ComparisonResultCoverageAuthorityIssuer {
        try ComparisonResultCoverageAuthorityIssuer(
            privateKeyRawRepresentation: [UInt8](repeating: seed, count: 32)
        )
    }

    private func signingKey(_ seed: UInt8) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    private func stable(_ value: String) -> ComparisonResultStableID {
        ComparisonResultStableID(rawValue: value)
    }

    private func revision(_ value: String, _ generation: UInt64) -> ComparisonResultRevisionReference {
        ComparisonResultRevisionReference(id: stable(value), generation: generation)
    }

    private func accessibilityID(_ value: String) -> AccessibilityStableID {
        AccessibilityStableID(rawValue: value)
    }

    private func accessibilityReference(
        _ value: String,
        _ revision: UInt64
    ) -> AccessibilityEvidenceRevisionReference {
        AccessibilityEvidenceRevisionReference(
            id: accessibilityID(value),
            revision: AccessibilityEvidenceRevision(rawValue: revision)
        )
    }

    private func comparisonIdentity(_ value: UInt16) -> State.Identity {
        State.Identity(rawValue: uuid(value))
    }

    private func inputIdentity(_ value: UInt16) -> State.InputIdentity {
        State.InputIdentity(rawValue: uuid(value))
    }

    private func sideIdentity(_ value: UInt16) -> State.SideIdentity {
        State.SideIdentity(rawValue: uuid(value))
    }

    private func operationID(_ value: UInt16) -> State.OperationID {
        State.OperationID(rawValue: uuid(value))
    }

    private func resultID(_ value: UInt16) -> State.ResultID {
        State.ResultID(rawValue: uuid(value))
    }

    private func uuid(_ value: UInt16) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0,
                UInt8(value >> 8), UInt8(value & 0xFF)
            )
        )
    }

    private func uuidTail(_ value: UUID) -> UInt16 {
        let bytes = value.uuid
        return UInt16(bytes.14) << 8 | UInt16(bytes.15)
    }

    private func nonce(_ value: Int) -> [UInt8] {
        [UInt8](repeating: UInt8(value), count: 16)
    }

    private func digest(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: SHA256.byteCount)
    }

    private func sha256(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }
    }

    private var goldenLifecycleSignatures: [String] {
        [
            "f9b9b9d685a1046452bde9d4e006f2d0a6ac9d519e9151ae983bff8d263ad297c6777f7c67c4d30d4819569deceb012e6014922dbb3bd71c83a14efaeee80301",
            "5d06ef0f2a39742bb25558f8b740f7424a19b36f7597eb775e0dffe3df07652fbd4d652b0c0d998d8c0126ac9ea75ed4fed5d5c44563ec3bc127ff583b78ae02",
            "7a6ce43cc9b47518a1995faa856eaa33e2e79ac03807eb7e3c208dcd8caced6da725936e0c2ef346cc5b73fafb0d11fe8ff98fb649a2f1da1299294760bb6707",
            "cce8edd38fb4b3da5faa0039bec551692919a26a419ab5c159eb1e94ffdcaf390bad910c23a4842032dc0b9c4ad270b2a05c4cee01698cf9ce6d650e9fc53805",
            "464cbfa5e4caf64d93db6e50adffdecea4cc2f45d80779cafb585823f0b3d3195187c07c43c0f73a82a3bedd10e6e8cb522a7465026b0d99608da0f4dd081308",
            "35eb30e391dc1af35d0361d2090a9c3e31d3df1c554e03c85c8160b334f0b040bbaeedf0160ef46251ed3ffe37ffed8b14db01302650dd54dd962662e0d2c802",
            "21c81d614b71a6c51012f2b299c9369b772aadf5e078c3ac84b15ef04872c1b6523121d1bb4e5f7ca71b400983253e2e783fe8d15fbfcee05ca47453f7de8c04",
            "d48858be4917b7b14d2cbfd5f79af42b6c9f4a6e37d248eb0085e249f73550acc9ba2377eb0941445e9282605b4a2e9429a58a80cd759b15381a50a50196ab03",
            "d4157cc99cc270c986a9e75db2dad45011295d7976b46a3e1d4b2b8d8bd456d667acf16469722aa95be4e4de940708cea47a80604b1b6c608e24800fac955d07",
            "0ef13ce240bb86296ec93933574bafa54720e598687a347357d56582f95a4040b91f62182b7b570fd19ab6c27288e5ad3a0c5d4bc18af1057a5d9a44d6b1eb0d",
            "95b40f769df1c47ee50bbb158db24663cf408c8023c48b3d6a3a50da6473c86d90e54f2aa7f392bbaadbfbd36e0b0d1e8431001ce16d87a854fa29a934880605",
            "1f685da9cb141810ce71a75c750dcd092d490e58030dfa4b93e8f0e62438eea8a6c2462139f2edd96f35513d40cb98a05de205eb172aa81a15cda3af760b4706",
            "fc147715f6bbfce405d242c115fbafda8c629d29bf7d9104df79e4db6e74e473c756ec359c4790a375ec0eecf6e83b7c11f581ce7c4a3c9c718eb647a6125d01",
            "8464ed9d139d1056e39bc084b5f8db0d39bb064506c40a6bd4aec05920c309c248780635b79b70b35568f8ca9f1b5b0bc55790a178c197f196d3b06e57ed6a03",
            "8eb3a11439363dfb86c028ce536f4b6dd3da774b4b1fb8cf04d233e55c1046c9f0ee1dd818a7a7cd2a1e8f54f380462cf8ab2fa38f665dedf6e602bc9030f50d",
            "dd17180c14f40b65520b00c1ec3878e980cfb40dc64a13c6796f859039745bce6e58f43934080a2524ae4110cd754f1a5b5c0024b0319a76b9f49cfa6bf9de07"
        ]
    }

    private var goldenCollectorSignatures: [String] {
        [
            "c0fce7c8e76a20b436ac85a969bf9d25a232622f075a793c2ce790cd6f9405fba7d9c812e8e953f9b7d551ff812ed4fcb363d69dcd34cda1fc79f6326c4de200",
            "e1fd05ee8be8a0243e844c4a152da4db503808bec44a85ced7a1184a4a809fab739399c62344b909bcc9700f3105cb4949c0dede85086631b9b53f436670b500",
            "a0eaeb9de5ea18f4c9373154e8c6cfb8a28dc62be8390e1867ffe8631fb5ad00b96e69dd89a284d84b8f0c0d1727f41f6e184f0fca2032bc517175e39c8f4d0e",
            "3994a33c556d0026bfaab937b1ae355786bb00262dfc4c8b0526daf078e3cc3c1ef12cd95ce65672078652cd17bc2e7e9953cc3d4148e39a6d4cf3af3fb6ae05",
            "bc31ba0b4878edbc988c93c808124a29a8654da4ce2001f7da133774dbd49166b913a41a875d904e99c2f547a0b7ac51df2ce1fbc2a1be03e84400deab411300",
            "fed6da2d9c3dff10f39527706198ce8927b1de142efd74cabb21808ca5f158eb9bc88bc75ba8ff9bdffdfd37493094f6dfd82f4c5e0e3fa1ac346fd7d5fb6f08",
            "02e9f3967ca1d6b649f18fd5ae4653b2c69aaa040c9cbbf0790f81e141f11c9e39e4006095c477e8170c757518ad1460806076c2dbfd38403677e3125b770903",
            "b462afb3e29fd1823ee2e4d6b1930e38060b1c262b41f2beba19ac1ca18934522aab7198213c82ec062ec70577324f869ea967bdc32b020807a29bcdd4bbb903",
            "2cc7a1a6bb8153a8e58a088410e1e9501678ba442221e1647cb7155afadb9c0fc16b15e64f081bfa71e43e2f77ccab9d51dd4ab8d54bc25690442a86a873070e",
            "fa247987162ecd537380774f4adc700d12b85708311dc94d26d418cdc41cfbdc886c08b4e5c50c58bb6c1f756d76a853b7adafcd77238040ff2883cff8f29f08",
            "64831dbfb5377b0f514044662b1bfc45734c6d89a24096504c7e4df01fb412b8f858896d829d0d07ff4d9f09a921cf4ed1d01c878600fd16a0936968f09af40b",
            "30b9e76ea3ee1cc1707ad7464b4ab6da8a7a77a25f8531d89eb3f25a37fe5ada6b1fca7852275a6403763126fc5bf7bfe452f61a8e12ee40a8aad1e86060240f",
            "c1bac8012668d69d0c91bd0b1ba409ae10cd28373836df559664111556871e2c968f649d7490464d5c6ef40abffa2e1065fb4b53cd83e6e2844bdaeefa04c206",
            "08c918583ee057a49d647c3c94823f7fe3d658523ad9095f35e7c02cfe075a6a4913e9fd48087dabb8cad862f7ee4c5ca0a8b29bf1bea6c57c98f731c402b80d",
            "2192215cc413421cac11fb5bd412687ac4de7001fbab8c1be8242f7b5ba86fe9012a563127046de0b63a91343435d0480227b5667dd1f4ba1521fa4efb97e702",
            "f8d88c26fffebb64e93983e333fe3511db387c003aa5473fa2c78f142413bb73648ebbba935ae44fdc7f72abeb311ec94ea706cac86b36556190133230adb60b"
        ]
    }

    private func assertCoverageError<T>(
        _ expected: ComparisonResultCoverageError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? ComparisonResultCoverageError, expected, file: file, line: line)
        }
    }

    private func assertSpecificError<T, Failure: Error & Equatable>(
        _ expected: Failure,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? Failure, expected, file: file, line: line)
        }
    }
}

private enum TestCaptureResourceError: ComparisonResultCaptureResourceError, Equatable {
    case unavailable
}

private final class ReplayLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed: Set<[UInt8]> = []
    private var invocations = 0
    private var policy: ComparisonResultRevisionReference?
    private var claims: [ComparisonResultReplayClaim] = []

    var invocationCount: Int {
        lock.withLock { invocations }
    }

    var claimedCount: Int {
        lock.withLock { claimed.count }
    }

    var lastPolicy: ComparisonResultRevisionReference? {
        lock.withLock { policy }
    }

    var lastClaims: [ComparisonResultReplayClaim] {
        lock.withLock { claims }
    }

    func claim(
        _ replayPolicy: ComparisonResultRevisionReference,
        _ proposed: [ComparisonResultReplayClaim]
    ) -> Bool {
        lock.withLock {
            invocations += 1
            policy = replayPolicy
            claims = proposed
            let nonces = proposed.map(\.nonce)
            guard Set(nonces).count == nonces.count,
                nonces.allSatisfy({ !claimed.contains($0) })
            else { return false }
            claimed.formUnion(nonces)
            return true
        }
    }
}

private final class InvocationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0

    var count: Int {
        lock.withLock { invocations }
    }

    func record() {
        lock.withLock { invocations += 1 }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    var value: Bool {
        lock.withLock { isSet }
    }

    func set() {
        lock.withLock { isSet = true }
    }
}

private final class IntegerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Int] = []

    var values: [Int] {
        lock.withLock { recordedValues }
    }

    func record(_ value: Int) {
        lock.withLock { recordedValues.append(value) }
    }
}
