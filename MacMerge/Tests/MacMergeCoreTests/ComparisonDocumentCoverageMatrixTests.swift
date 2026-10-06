import CryptoKit
import Foundation
import XCTest
@testable import MacMergeCore

final class ComparisonDocumentCoverageMatrixTests: XCTestCase {
    private typealias Matrix = ComparisonDocumentCoverageMatrix

    func testCanonicalInventoryIsUniqueSortedAndContainsTheExactBaseCartesianProduct() throws {
        let scenarios = Matrix.canonicalScenarios
        let actual = Set(scenarios.map(ScenarioOracleKey.init))
        let expected = try expectedScenarioOracleKeys()

        XCTAssertEqual(scenarios.count, 23_630)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(Set(scenarios).count, scenarios.count)
        XCTAssertEqual(Set(scenarios.map(\.id)).count, scenarios.count)
        XCTAssertEqual(scenarios, scenarios.sorted())
        XCTAssertEqual(Matrix.reportFormatVersion, 4)
        XCTAssertEqual(Matrix.archiveFormatVersion, 4)
        XCTAssertEqual(Matrix.canonicalMatrixRevision, 4)
        XCTAssertEqual(ComparisonDocumentSourceShape.allCases.count, 4)
        XCTAssertEqual(ComparisonDocumentDirtyState.allCases.count, 4)
        XCTAssertEqual(ComparisonDocumentSideIncident.allCases.count, 4)

        for scenario in scenarios {
            XCTAssertEqual(scenario.id.rawValue, expectedScenarioID(for: ScenarioOracleKey(scenario)))
        }
        XCTAssertEqual(
            scenarioInventorySHA256(scenarios),
            "a9f418eee714083c95001e40735533b9dc48e90eb2b7b72fafd6ae75e08cd194"
        )

        let base = scenarios.filter { $0.save == .notAttempted && $0.backup == .notApplicable }
        XCTAssertEqual(base.count, 100)
        for shape in ComparisonDocumentSourceShape.allCases {
            for dirty in ComparisonDocumentDirtyState.allCases {
                for leftIncident in ComparisonDocumentSideIncident.allCases {
                    for rightIncident in ComparisonDocumentSideIncident.allCases {
                        let expected =
                            (shape.kind(on: .left) == .file || leftIncident == .none)
                            && (shape.kind(on: .right) == .file || rightIncident == .none)
                        let matches = base.count { scenario in
                            scenario.sourceShape == shape && scenario.dirtyState == dirty
                                && scenario.incident.left == leftIncident
                                && scenario.incident.right == rightIncident
                        }
                        XCTAssertEqual(
                            matches,
                            expected ? 1 : 0,
                            "\(shape), \(dirty), \(leftIncident), \(rightIncident)"
                        )
                    }
                }
            }
        }

        XCTAssertThrowsError(
            try ComparisonDocumentScenario(
                sourceShape: .bothScratchpads,
                dirtyState: .neither,
                incident: .externalChange(.left)
            )
        ) { XCTAssertEqual($0 as? ComparisonDocumentCoverageError, .impossibleScenario) }
        XCTAssertThrowsError(
            try ComparisonDocumentSaveState(
                execution: .single(.left),
                leftOperation: .notAttempted,
                left: .committed(.applied),
                rightOperation: .notAttempted,
                right: .notAttempted
            )
        ) { XCTAssertEqual($0 as? ComparisonDocumentCoverageError, .impossibleScenario) }
    }

    func testCanonicalSaveAndBackupOutcomeInventoryIsExactAndIndependentPerSide() throws {
        let scenarios = Matrix.canonicalScenarios
        let failures: [ThreePaneSaveNonCommitReason] = [
            .cancelled,
            .sourceRevisionChanged,
            .destinationCompareFailed,
            .safetyContractUnavailable,
            .publicationFailedBeforeMutation
        ]
        let uncertainties: [ThreePaneSaveCommitUncertainty] = [
            .publicationStateUnknown,
            .committedBytesUnverified,
            .durabilityUnverified,
            .recoveryStateUnknown
        ]
        let committed: [ComparisonDocumentSideSaveOutcome] = [
            .committed(.applied),
            .committed(.rejected(.planAlreadyConsumed)),
            .committed(.rejected(.ownerRevisionChanged)),
            .committed(.rejected(.bindingChanged))
        ]
        let outcomes =
            failures.map(ComparisonDocumentSideSaveOutcome.failed)
            + uncertainties.map(ComparisonDocumentSideSaveOutcome.uncertain) + committed

        XCTAssertEqual(outcomes.count, 13)
        for side in ComparisonDocumentSide.allCases {
            for operation in ComparisonDocumentSideSaveOperation.allCases where operation != .notAttempted {
                for outcome in outcomes {
                    XCTAssertTrue(
                        scenarios.contains {
                            $0.save.operation(on: side) == operation && $0.save[side] == outcome
                        },
                        "missing \(side) \(operation) \(outcome)"
                    )
                }
            }
        }
        XCTAssertTrue(scenarios.contains { $0.save.execution == .single(.left) })
        XCTAssertTrue(scenarios.contains { $0.save.execution == .single(.right) })
        XCTAssertTrue(scenarios.contains { $0.save.execution == .batch })
        XCTAssertTrue(
            scenarios.contains {
                $0.save.execution == .batch && $0.save.left != $0.save.right
                    && $0.save.leftOperation != $0.save.rightOperation
            }
        )

        var backupOutcomesBySide: [ComparisonDocumentSide: Set<ComparisonDocumentBackupExecutionOutcome>] = [:]
        for scenario in scenarios {
            for side in ComparisonDocumentSide.allCases {
                switch scenario.backup[side] {
                case .notApplicable:
                    XCTAssertTrue(
                        scenario.save.operation(on: side) == .notAttempted
                            || scenario.save.operation(on: side) == .saveAsNewFile
                    )
                case .required(let trigger, let contract, let outcome):
                    XCTAssertEqual(trigger, .beforeSave)
                    XCTAssertEqual(contract, .required)
                    backupOutcomesBySide[side, default: []].insert(outcome)
                }
            }
        }
        for side in ComparisonDocumentSide.allCases {
            XCTAssertEqual(
                backupOutcomesBySide[side],
                Set(ComparisonDocumentBackupExecutionOutcome.allCases)
            )
        }

        for side in ComparisonDocumentSide.allCases {
            let missingInPlace = try XCTUnwrap(
                scenarios.first {
                    $0.incident[side] == .missingDiskFile
                        && $0.save.operation(on: side) == .saveInPlace
                }
            )
            XCTAssertEqual(
                missingInPlace.backup[side],
                .required(trigger: .beforeSave, contract: .required, outcome: .notStarted)
            )
            XCTAssertEqual(missingInPlace.save[side], .failed(.destinationCompareFailed))
        }
    }

    func testExpectedStateTracksCurrentStaleDiskAndPaneUpdateRulesExactly() throws {
        let scenarios = Matrix.canonicalScenarios
        for scenario in scenarios {
            let oracle = expectedStateOracle(for: scenario)
            XCTAssertEqual(scenario.expectedLifecyclePhase, oracle.lifecyclePhase, "\(scenario.id.rawValue)")
            XCTAssertEqual(scenario.expectedStaleReasons, oracle.staleReasons, "\(scenario.id.rawValue)")
            for side in ComparisonDocumentSide.allCases {
                let pane = oracle.pane(side)
                XCTAssertEqual(scenario.expectedSourceKind(on: side), pane.sourceKind, "\(scenario.id.rawValue) \(side)")
                XCTAssertEqual(scenario.expectedDiskState(on: side), pane.diskState, "\(scenario.id.rawValue) \(side)")
                XCTAssertEqual(scenario.isDirty(side), pane.isDirty, "\(scenario.id.rawValue) \(side)")
            }
        }

        let clean = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .neither
                && $0.incident == .none && $0.save == .notAttempted
        }
        XCTAssertEqual(clean.expectedLifecyclePhase, .current)
        XCTAssertEqual(clean.expectedStaleReasons, [])
        for side in ComparisonDocumentSide.allCases {
            XCTAssertFalse(clean.isDirty(side))
            XCTAssertEqual(clean.expectedDiskState(on: side), .present)
            XCTAssertEqual(clean.expectedSourceKind(on: side), .file)
        }

        let simultaneous = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .both
                && $0.incident
                    == ComparisonDocumentIncident(
                        left: .externalChange,
                        right: .missingDiskFile
                    )
                && $0.save == .notAttempted
        }
        XCTAssertEqual(simultaneous.expectedLifecyclePhase, .stale)
        XCTAssertEqual(
            Set(simultaneous.expectedStaleReasons),
            Set([
                .externalChange(.left), .sideChanged(.left),
                .externalChange(.right), .sideChanged(.right)
            ])
        )
        XCTAssertEqual(simultaneous.expectedDiskState(on: .left), .externallyChanged)
        XCTAssertEqual(simultaneous.expectedDiskState(on: .right), .missing)

        let scratchpadSaveAs = try scenario(in: scenarios) {
            $0.sourceShape == .bothScratchpads && $0.dirtyState == .left
                && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveAsNewFile
                && $0.save.left == .committed(.applied)
        }
        XCTAssertEqual(scratchpadSaveAs.expectedSourceKind(on: .left), .file)
        XCTAssertEqual(scratchpadSaveAs.expectedDiskState(on: .left), .present)
        XCTAssertFalse(scratchpadSaveAs.isDirty(.left))
        XCTAssertEqual(scratchpadSaveAs.expectedLifecyclePhase, .stale)

        let rejectedSaveAs = try scenario(in: scenarios) {
            $0.sourceShape == .bothScratchpads && $0.dirtyState == .left
                && $0.save.leftOperation == .saveAsNewFile
                && $0.save.left == .committed(.rejected(.planAlreadyConsumed))
        }
        XCTAssertEqual(rejectedSaveAs.expectedSourceKind(on: .left), .scratchpad)
        XCTAssertEqual(rejectedSaveAs.expectedDiskState(on: .left), .notApplicable)
        XCTAssertTrue(rejectedSaveAs.isDirty(.left))

        let uncertainInPlace = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save.leftOperation == .saveInPlace
                && $0.save.left == .uncertain(.publicationStateUnknown)
        }
        XCTAssertEqual(uncertainInPlace.expectedDiskState(on: .left), .commitUncertain)
        XCTAssertTrue(uncertainInPlace.isDirty(.left))

        let diskOnly = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .neither
                && $0.incident == .missingDiskFile(.right) && $0.save == .notAttempted
        }
        let bindings = try makeBindings(for: diskOnly, seed: 91)
        XCTAssertEqual(bindings[.right].document, bindings[.right].resultDocument)
        XCTAssertNil(bindings[.right].incidentSource)
        XCTAssertEqual(bindings[.right].currentSource, bindings[.right].openedSource)
        XCTAssertNoThrow(try Matrix.canonicalCaptureData(for: assertion(diskOnly, bindings)))
    }

    func testRevisionLineageAndOpaqueLocationsAreExactAndRedacted() throws {
        let current = try canonicalScenario { $0.expectedLifecyclePhase == .current }
        let currentBindings = try makeBindings(for: current, seed: 101)
        let comparison = currentBindings.comparison
        XCTAssertEqual(comparison.operation.comparison.id, comparison.comparison.id)
        XCTAssertEqual(comparison.operation.comparison.revision, comparison.operation.startedAtGeneration)
        XCTAssertEqual(comparison.operation.inputs, comparison.resultInputs)
        XCTAssertEqual(comparison.operation.sources, comparison.resultSources)
        XCTAssertEqual(comparison.resultInputs, comparison.inputs)
        XCTAssertEqual(comparison.resultSources, comparison.sources)
        XCTAssertGreaterThan(comparison.result.revision, comparison.operation.startedAtGeneration)
        XCTAssertGreaterThanOrEqual(comparison.comparison.revision, comparison.result.revision)
        XCTAssertNoThrow(try Matrix.canonicalCaptureData(for: assertion(current, currentBindings)))

        let stale = try canonicalScenario {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save == .notAttempted
        }
        let staleBindings = try makeBindings(for: stale, seed: 102)
        XCTAssertEqual(staleBindings.comparison.inputs.id, staleBindings.comparison.resultInputs.id)
        XCTAssertGreaterThan(staleBindings.comparison.inputs.revision, staleBindings.comparison.resultInputs.revision)
        XCTAssertEqual(staleBindings[.left].lifecycleSource.id, staleBindings[.left].resultLifecycleSource.id)
        XCTAssertGreaterThan(staleBindings[.left].lifecycleSource.revision, staleBindings[.left].resultLifecycleSource.revision)
        XCTAssertEqual(staleBindings[.right].lifecycleSource, staleBindings[.right].resultLifecycleSource)
        XCTAssertNoThrow(try Matrix.canonicalCaptureData(for: assertion(stale, staleBindings)))

        let badLineage = try makeBindings(
            for: stale,
            seed: 103,
            options: BindingOptions(keepsStaleInputsCurrent: true)
        )
        assertInvalidCapture(stale, badLineage)

        let lineageMutations: [BindingOptions] = [
            BindingOptions(operationComparisonIdentityChanged: true),
            BindingOptions(operationComparisonRevisionChanged: true),
            BindingOptions(operationInputsChanged: true),
            BindingOptions(operationSourcesChanged: true),
            BindingOptions(resultDoesNotFollowOperation: true),
            BindingOptions(staleInputIdentityChanged: true),
            BindingOptions(staleExpectedSourceDidNotAdvance: true),
            BindingOptions(staleAdvancedSourceIdentityChanged: true),
            BindingOptions(comparisonDoesNotFollowResult: true)
        ]
        for (offset, options) in lineageMutations.enumerated() {
            assertInvalidCapture(
                stale,
                try makeBindings(for: stale, seed: 104 + UInt64(offset), options: options)
            )
        }
        let currentMutations: [BindingOptions] = [
            BindingOptions(keepsCurrentInputsStale: true),
            BindingOptions(keepsCurrentSourcesStale: true),
            BindingOptions(comparisonDoesNotCoverCurrentResult: true),
            BindingOptions(changesCurrentSourceWithoutLifecycleChange: true)
        ]
        for (offset, options) in currentMutations.enumerated() {
            assertInvalidCapture(
                current,
                try makeBindings(for: current, seed: 114 + UInt64(offset), options: options)
            )
        }

        let secret = "secret-location-key"
        let secretKey = ComparisonDocumentStableID(rawValue: secret)
        let secretReference = ComparisonDocumentRevisionReference(id: secretKey, revision: 1)
        let secretBindings = try makeBindings(for: current, seed: 118, locationKey: secretKey)
        let location = ComparisonDocumentLocationIdentity(
            keyReference: secretKey,
            hmacSHA256: digest(0xAB)
        )
        let side = secretBindings[.left]
        let file = try XCTUnwrap(file(from: side.openedSource))
        let values: [Any] = [
            secretKey,
            secretReference,
            location,
            ComparisonDocumentFileIdentity(volumeID: 1, fileID: 2, generation: 3, location: location),
            file,
            side.document,
            side.openedSource,
            secretBindings.comparison.operation,
            secretBindings.comparison,
            side,
            secretBindings,
            ComparisonDocumentCoverageError.invalidEvidence(field: secret)
        ]
        for value in values.dropFirst() {
            var dumped = ""
            dump(value, to: &dumped)
            let rendered = [String(describing: value), String(reflecting: value), dumped]
                .joined(separator: "\n")
            XCTAssertFalse(rendered.contains(secret), "\(type(of: value)) leaked location key")
            XCTAssertTrue(rendered.contains("<redacted>"), "\(type(of: value))")
        }
        XCTAssertFalse(String(describing: secretKey).contains(secret))

        let secretScenario = try canonicalScenario {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveInPlace && $0.save.left == .committed(.applied)
        }
        let redactedBindings = try makeBindings(
            for: secretScenario,
            seed: 119,
            locationKey: secretKey
        )
        let redactedSide = redactedBindings[.left]
        let redactedProvenance = ComparisonDocumentEvidenceProvenance(
            build: secretReference,
            inventory: secretReference,
            evidence: secretReference,
            collector: secretReference,
            run: secretReference,
            capturedAtUnixMilliseconds: 1,
            runNonce: Array(secret.utf8),
            artifactSHA256: digest(1),
            captureSHA256: digest(2),
            captureByteCount: 1,
            collectorSignature: [UInt8](repeating: 1, count: 64),
            source: .automatedHarness
        )
        let redactedObservation = ComparisonDocumentProductionObservation(
            scenarioID: secretScenario.id,
            bindings: redactedBindings,
            lifecycle: ComparisonDocumentLifecycleObservation(
                phase: secretScenario.expectedLifecyclePhase,
                hasCurrentResult: false,
                hasRetainedResult: true,
                staleReason: secretScenario.expectedStaleReasons.first
            ),
            left: ComparisonDocumentCoverageInventoryRequirementProjection(secretScenario).left,
            right: ComparisonDocumentCoverageInventoryRequirementProjection(secretScenario).right,
            save: secretScenario.save,
            saveExecutorContract: .required,
            backup: secretScenario.backup,
            origin: .productionAutomation,
            provenance: redactedProvenance
        )
        let redactedEvidence = ComparisonDocumentEvidenceBundle(
            reference: secretReference,
            inventory: secretReference,
            build: secretReference,
            observations: [redactedObservation]
        )
        let redactedPolicy = ComparisonDocumentAuditPolicy(
            trustedCollectors: [
                ComparisonDocumentTrustedCollector(
                    reference: secretReference,
                    ed25519PublicKey: Array(secret.utf8)
                )
            ],
            trustedLocationKeyReferences: [secretKey],
            trustedAuditTimeUnixMilliseconds: 1,
            maximumCaptureAgeMilliseconds: 1,
            maximumFutureClockSkewMilliseconds: 1,
            replayClaimDeadlineUnixMilliseconds: 2,
            replayPolicy: secretReference,
            claimReplayNonces: { _, _, _, _, _ in .committed }
        )
        let moreValues: [Any] = [
            try XCTUnwrap(redactedSide.saveOperation),
            redactedSide.saveDestination,
            try XCTUnwrap(redactedSide.completedBackup),
            redactedProvenance,
            redactedObservation,
            redactedEvidence,
            redactedPolicy,
            ComparisonDocumentCaptureSink(maximumByteCount: secret.utf8.count, expected: Data(secret.utf8))
        ]
        for value in moreValues {
            var dumped = ""
            dump(value, to: &dumped)
            let rendered = [String(describing: value), String(reflecting: value), dumped]
                .joined(separator: "\n")
            XCTAssertFalse(rendered.contains(secret), "\(type(of: value)) leaked secret")
            XCTAssertTrue(rendered.contains("<redacted>"), "\(type(of: value))")
        }
    }

    func testDestinationPayloadPaneUpdateAliasAndBackupBindingsFailClosed() throws {
        let scenarios = Matrix.canonicalScenarios
        let committedReplacement = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveAsReplacingFile
                && $0.save.left == .committed(.applied)
        }
        let valid = try makeBindings(for: committedReplacement, seed: 111)
        let save = try XCTUnwrap(valid[.left].saveOperation)
        let transition = try self.transition(valid[.left])
        let after = try XCTUnwrap(transition.observedAfterExecution)
        XCTAssertEqual(transition.expected, transition.observedBeforePublication)
        XCTAssertNotNil(transition.expected.target)
        XCTAssertEqual(after.target, save.committedPayload)
        XCTAssertEqual(after.parent.identity, transition.expected.parent.identity)
        XCTAssertGreaterThan(after.parent.revision, transition.expected.parent.revision)
        XCTAssertEqual(after.slot.location, transition.expected.slot.location)
        XCTAssertGreaterThan(after.slot.revision, transition.expected.slot.revision)
        XCTAssertNotEqual(
            physicalKey(try XCTUnwrap(after.target)),
            physicalKey(try XCTUnwrap(transition.expected.target))
        )
        XCTAssertEqual(save.committedPayload?.byteCount, save.sourceDocument.encodedByteCount)
        XCTAssertEqual(save.committedPayload?.contentSHA256, save.sourceDocument.encodedContentSHA256)
        XCTAssertEqual(save.committedPayload?.metadataSHA256, save.sourceDocument.metadataSHA256)
        XCTAssertEqual(save.committedPayload?.contentAndMetadataSHA256, save.sourceDocument.contentAndMetadataSHA256)
        XCTAssertEqual(save.committedPayload?.encoding, save.sourceDocument.encoding)
        XCTAssertNoThrow(try Matrix.canonicalCaptureData(for: assertion(committedReplacement, valid)))

        let invalidOptions: [BindingOptions] = [
            BindingOptions(reusesOccupiedReplacementIdentity: true),
            BindingOptions(saveAsCommittedPayloadAliasesOpenedFile: true),
            BindingOptions(doesNotAdvancePublishedParent: true),
            BindingOptions(omitsRequiredPaneUpdatePlanID: true),
            BindingOptions(committedPayloadCorruption: .metadataSHA256)
        ]
        for (offset, options) in invalidOptions.enumerated() {
            assertInvalidCapture(
                committedReplacement,
                try makeBindings(for: committedReplacement, seed: 112 + UInt64(offset), options: options)
            )
        }

        let failed = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveInPlace
                && $0.save.left == .failed(.publicationFailedBeforeMutation)
        }
        assertInvalidCapture(
            failed,
            try makeBindings(
                for: failed,
                seed: 120,
                options: BindingOptions(addsPaneUpdateDataToNoncommit: true)
            )
        )

        let completedBackup = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveInPlace
                && $0.save.left == .committed(.applied)
        }
        let backupBindings = try makeBindings(for: completedBackup, seed: 121)
        let backup = try XCTUnwrap(backupBindings[.left].completedBackup)
        let saveTransition = try self.transition(backupBindings[.left])
        XCTAssertEqual(backup.sourceRevision, saveTransition.observedBeforePublication.target)
        XCTAssertNil(backup.destination.expected.target)
        XCTAssertEqual(backup.destination.expected, backup.destination.observedBeforePublication)
        XCTAssertEqual(backup.destination.observedAfterExecution?.target, backup.committedPayload)
        XCTAssertEqual(backup.committedPayload.contentSHA256, backup.sourceRevision.contentSHA256)
        XCTAssertEqual(backup.committedPayload.metadataSHA256, backup.sourceRevision.metadataSHA256)
        XCTAssertNotEqual(backup.destination.expected.slot.location, saveTransition.expected.slot.location)
        XCTAssertNotEqual(physicalKey(backup.committedPayload), physicalKey(backup.sourceRevision))
        XCTAssertNoThrow(try Matrix.canonicalCaptureData(for: assertion(completedBackup, backupBindings)))
        assertInvalidCapture(
            completedBackup,
            try makeBindings(
                for: completedBackup,
                seed: 122,
                options: BindingOptions(backupPayloadAliasesSource: true)
            )
        )
        for corruption in PayloadCorruption.allCases {
            assertInvalidCapture(
                completedBackup,
                try makeBindings(
                    for: completedBackup,
                    seed: 123 + UInt64(corruption.rawValue),
                    options: BindingOptions(backupPayloadCorruption: corruption)
                )
            )
        }
        for (offset, options) in [
            BindingOptions(backupUsesWrongOccupiedSource: true),
            BindingOptions(backupDestinationStartsOccupied: true),
            BindingOptions(backupOmitsPublishedState: true)
        ].enumerated() {
            assertInvalidCapture(
                completedBackup,
                try makeBindings(for: completedBackup, seed: 131 + UInt64(offset), options: options)
            )
        }

        let nonCompletedBackup = try scenario(in: scenarios) {
            guard case .required(_, _, .cancelledAfterPublication) = $0.backup.left else {
                return false
            }
            return $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveInPlace
                && $0.save.left == .failed(.safetyContractUnavailable)
        }
        assertInvalidCapture(
            nonCompletedBackup,
            try makeBindings(
                for: nonCompletedBackup,
                seed: 135,
                options: BindingOptions(attachesBackupEvidenceToNonCompletedOutcome: true)
            )
        )

        let bothFiles = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .neither
                && $0.incident == .none && $0.save == .notAttempted
        }
        assertInvalidCapture(
            bothFiles,
            try makeBindings(
                for: bothFiles,
                seed: 123,
                options: BindingOptions(rightOpenedFileAliasesLeft: true)
            )
        )
    }

    func testDestinationTransitionsRepresentFailuresCancellationUncertaintyAndPaneRejections() throws {
        let scenarios = Matrix.canonicalScenarios
        let representatives: [ComparisonDocumentSideSaveOutcome] = [
            .failed(.cancelled),
            .failed(.sourceRevisionChanged),
            .failed(.destinationCompareFailed),
            .failed(.safetyContractUnavailable),
            .failed(.publicationFailedBeforeMutation),
            .uncertain(.publicationStateUnknown),
            .uncertain(.committedBytesUnverified),
            .uncertain(.durabilityUnverified),
            .uncertain(.recoveryStateUnknown),
            .committed(.applied),
            .committed(.rejected(.planAlreadyConsumed)),
            .committed(.rejected(.ownerRevisionChanged)),
            .committed(.rejected(.bindingChanged))
        ]
        for (offset, outcome) in representatives.enumerated() {
            let scenario = try scenario(in: scenarios) {
                $0.sourceShape == .bothFiles && $0.dirtyState == .left
                    && $0.incident == .none && $0.save.execution == .single(.left)
                    && $0.save.leftOperation == .saveAsReplacingFile && $0.save.left == outcome
            }
            let bindings = try makeBindings(for: scenario, seed: 130 + UInt64(offset))
            let transition = try self.transition(bindings[.left])
            switch outcome {
            case .failed(.destinationCompareFailed):
                XCTAssertNotEqual(transition.expected, transition.observedBeforePublication)
                XCTAssertEqual(transition.observedAfterExecution, transition.observedBeforePublication)
            case .failed:
                XCTAssertEqual(transition.expected, transition.observedBeforePublication)
                XCTAssertEqual(transition.observedAfterExecution, transition.observedBeforePublication)
            case .uncertain:
                XCTAssertEqual(transition.expected, transition.observedBeforePublication)
                XCTAssertNil(transition.observedAfterExecution)
            case .committed:
                XCTAssertEqual(transition.expected, transition.observedBeforePublication)
                XCTAssertNotNil(transition.observedAfterExecution)
            case .notAttempted:
                XCTFail("representative must be attempted")
            }
            XCTAssertNoThrow(try Matrix.canonicalCaptureData(for: assertion(scenario, bindings)))

            let transitionMutations: [BindingOptions]
            if outcome == .failed(.destinationCompareFailed) {
                transitionMutations = [
                    BindingOptions(invalidExpectedDestination: true),
                    BindingOptions(destinationCompareDidNotChange: true),
                    BindingOptions(invalidPostExecutionShape: true)
                ]
            } else {
                transitionMutations = [
                    BindingOptions(invalidExpectedDestination: true),
                    BindingOptions(unexpectedPrepublicationChange: true),
                    BindingOptions(invalidPostExecutionShape: true)
                ]
            }
            for (mutationOffset, options) in transitionMutations.enumerated() {
                assertInvalidCapture(
                    scenario,
                    try makeBindings(
                        for: scenario,
                        seed: 200 + UInt64(offset * 10 + mutationOffset),
                        options: options
                    )
                )
            }
        }
    }

    func testSaveOperationFieldsPlanningAndPaneRejectionBranchesFailClosed() throws {
        let scenarios = Matrix.canonicalScenarios
        let replacement = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left && $0.incident == .none
                && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveAsReplacingFile
                && $0.save.left == .committed(.applied)
        }
        for corruption in PayloadCorruption.allCases {
            assertInvalidCapture(
                replacement,
                try makeBindings(
                    for: replacement,
                    seed: 350 + UInt64(corruption.rawValue),
                    options: BindingOptions(committedPayloadCorruption: corruption)
                )
            )
        }
        for (offset, options) in [
            BindingOptions(usesTooTightSaveLimits: true),
            BindingOptions(hasInvalidPlanID: true),
            BindingOptions(usesWrongSourceFile: true),
            BindingOptions(hasInvalidPathCounts: true),
            BindingOptions(hasInvalidParentPathCount: true),
            BindingOptions(hasInvalidLeafCount: true),
            BindingOptions(hasInvalidPlannedOperationCount: true),
            BindingOptions(hasInvalidTotalPathCount: true),
            BindingOptions(hasInvalidEstimatedWork: true),
            BindingOptions(sourceDocumentExceedsEncodedLimit: true),
            BindingOptions(sourceDocumentExceedsMetadataLimit: true),
            BindingOptions(corruptsPaneUpdateDocument: true),
            BindingOptions(corruptsPaneUpdateSource: true),
            BindingOptions(omitsPaneUpdateDocument: true),
            BindingOptions(omitsPaneUpdateSource: true)
        ].enumerated() {
            assertInvalidCapture(
                replacement,
                try makeBindings(for: replacement, seed: 360 + UInt64(offset), options: options)
            )
        }

        for rejection in ComparisonDocumentPaneUpdateRejection.allCases {
            let rejected = try scenario(in: scenarios) {
                $0.sourceShape == .bothFiles && $0.dirtyState == .left && $0.incident == .none
                    && $0.save.execution == .single(.left)
                    && $0.save.leftOperation == .saveInPlace
                    && $0.save.left == .committed(.rejected(rejection))
            }
            assertInvalidCapture(
                rejected,
                try makeBindings(
                    for: rejected,
                    seed: 370 + UInt64(rejection.rawValue),
                    options: BindingOptions(changesPaneUpdatePlanID: true)
                )
            )
            assertInvalidCapture(
                rejected,
                try makeBindings(
                    for: rejected,
                    seed: 380 + UInt64(rejection.rawValue),
                    options: BindingOptions(flipsPaneUpdateConsumption: true)
                )
            )
        }

        let batch = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .both && $0.incident == .none
                && $0.save.execution == .batch && $0.save.left == .committed(.applied)
                && $0.save.right == .committed(.applied)
        }
        for (offset, options) in [
            BindingOptions(changesRightBatchPlanID: true),
            BindingOptions(changesRightBatchTotalPath: true),
            BindingOptions(aliasesRightBackupSlotToLeft: true),
            BindingOptions(backupSlotAliasesSaveDestination: true),
            BindingOptions(rightBackupSlotAliasesLeftOpenedFile: true)
        ].enumerated() {
            assertInvalidCapture(
                batch,
                try makeBindings(for: batch, seed: 390 + UInt64(offset), options: options)
            )
        }

        let saveAsNew = try scenario(in: scenarios) {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left && $0.incident == .none
                && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveAsNewFile
                && $0.save.left == .committed(.applied)
        }
        for (offset, options) in [
            BindingOptions(saveAsNewStartsOccupied: true),
            BindingOptions(saveAsNewAliasesOpenedLocation: true)
        ].enumerated() {
            assertInvalidCapture(
                saveAsNew,
                try makeBindings(for: saveAsNew, seed: 400 + UInt64(offset), options: options)
            )
        }
    }

    func testSignedCompleteBundleArchiveReplayResolverAndCurrentValidation() throws {
        let fixture = try makeSignedFixture()
        let resolver = CaptureResolver(captures: fixture.captures, probesResourceBound: true)
        let result = try Matrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: fixture.policy,
            captureResolver: resolver.resolve,
            cancellationCheck: { false }
        )
        let count = Matrix.canonicalScenarios.count

        XCTAssertEqual(result.report.matrix.requiredCount, 23_630)
        XCTAssertEqual(result.report.matrix.completeCount, count)
        XCTAssertEqual(result.report.matrix.cells.map(\.status), Array(repeating: .complete, count: count))
        XCTAssertEqual(result.report.matrix.cells.map(\.evidenceCount), Array(repeating: 1, count: count))
        XCTAssertEqual(result.report.findings, [])
        XCTAssertTrue(result.report.isCompleteAndValid)
        XCTAssertFalse(result.report.containsErrors)
        for value in [fixture.inventory as Any, result.report, result.archive, result.receipt] {
            var dumped = ""
            dump(value, to: &dumped)
            let rendered = [String(describing: value), String(reflecting: value), dumped]
                .joined(separator: "\n")
            for sensitive in [
                fixture.inventory.reference.id.rawValue,
                fixture.inventory.build.id.rawValue,
                hex(fixture.inventory.buildArtifactSHA256),
                hex(result.archive.sha256)
            ] {
                XCTAssertFalse(rendered.contains(sensitive), "\(type(of: value)) leaked \(sensitive)")
            }
            XCTAssertTrue(rendered.contains("<redacted>"), "\(type(of: value))")
        }
        XCTAssertEqual(
            ComparisonDocumentCoverageReport.scopeStatement,
            "Deterministic validation of caller-supplied, revision-bound production measurements for the canonical two-document lifecycle matrix; not independent UI, filesystem, save-executor, backup-executor, or app-integration verification."
        )
        XCTAssertEqual(result.receipt.requiredScenarioCount, count)
        XCTAssertEqual(result.receipt.completeScenarioCount, count)
        XCTAssertEqual(result.receipt.findingCount, 0)
        XCTAssertGreaterThan(result.receipt.workUnits, count)
        XCTAssertEqual(resolver.invocationCount, count)
        XCTAssertTrue(resolver.didProbeResourceBound)

        XCTAssertEqual(Set(fixture.inventory.requirements.map(\.bindings.comparison.openRequest)).count, count)
        XCTAssertEqual(Set(fixture.inventory.requirements.map(\.bindings.comparison.operation.operationID)).count, count)
        XCTAssertEqual(Set(fixture.inventory.requirements.map(\.bindings.comparison.result)).count, count)
        XCTAssertEqual(
            Set(fixture.inventory.requirements.map { OperationResult($0.bindings.comparison) }).count,
            count
        )

        XCTAssertEqual(fixture.replays.invocationCount, 1)
        XCTAssertEqual(fixture.replays.lastReplayPolicy, fixture.policy.replayPolicy)
        XCTAssertEqual(fixture.replays.lastEvidence, fixture.evidence.reference)
        XCTAssertEqual(fixture.replays.lastArchiveSHA256, result.archive.sha256)
        XCTAssertEqual(fixture.replays.lastClaims.count, count)
        XCTAssertEqual(Set(fixture.replays.lastClaims.map(\.run)).count, count)
        XCTAssertEqual(Set(fixture.replays.lastClaims.map(\.nonce)).count, count)
        XCTAssertEqual(
            fixture.replays.lastClaims,
            fixture.replays.lastClaims.sorted {
                if $0.run.id.rawValue != $1.run.id.rawValue {
                    return $0.run.id.rawValue.utf8.lexicographicallyPrecedes($1.run.id.rawValue.utf8)
                }
                if $0.run.revision != $1.run.revision { return $0.run.revision < $1.run.revision }
                return $0.nonce.lexicographicallyPrecedes($1.nonce)
            }
        )
        XCTAssertEqual(fixture.replays.lastAuditTime, fixture.auditTime)
        XCTAssertEqual(fixture.replays.lastDeadline, fixture.auditTime + 10_000)
        XCTAssertGreaterThan(fixture.replays.lastRemainingWorkUnits, 0)

        let sections = try archiveSections(result.archive.data)
        XCTAssertEqual(sections.magic, Data("MMCDARC4".utf8))
        XCTAssertEqual(sections.version, UInt64(Matrix.archiveFormatVersion))
        XCTAssertEqual(sections.inventorySHA256, result.receipt.inventorySHA256)
        XCTAssertEqual(sections.evidenceSHA256, result.receipt.evidenceSHA256)
        XCTAssertEqual(sections.reportSHA256, result.receipt.reportSHA256)
        XCTAssertEqual(result.archive.sha256, sha256(result.archive.data))
        XCTAssertEqual(result.receipt.archiveSHA256, result.archive.sha256)
        XCTAssertEqual(result.receipt.archiveByteCount, result.archive.data.count)
        XCTAssertEqual(sections.trailingSHA256, sha256(result.archive.data.dropLast(SHA256.byteCount)))
        let policyByteCount =
            result.receipt.workUnits
            - sections.inventory.count - sections.evidence.count - sections.report.count
            - result.archive.data.count - fixture.evidence.observations.count
        XCTAssertEqual(policyByteCount, expectedPolicyByteCount(fixture))

        let exactLimits = limits(
            maximumWorkUnits: ComparisonDocumentCoverageLimits.default.maximumWorkUnits,
            maximumCanonicalBytes: max(
                sections.inventory.count,
                sections.evidence.count,
                sections.report.count,
                fixture.maximumCaptureByteCount,
                policyByteCount
            ),
            maximumArchiveBytes: result.archive.data.count
        )
        XCTAssertNoThrow(
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                archive: result.archive.data,
                limits: exactLimits,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        )
        XCTAssertNoThrow(
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                archive: result.archive.data,
                limits: exactLimits,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        )
        XCTAssertEqual(fixture.replays.invocationCount, 3)
        XCTAssertEqual(resolver.invocationCount, count * 3)

        assertError(.archiveTooLarge(maximumBytes: result.archive.data.count - 1)) {
            try Matrix.validate(
                archive: result.archive.data,
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                limits: limits(maximumArchiveBytes: result.archive.data.count - 1),
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }
        var corrupted = result.archive.data
        corrupted[corrupted.startIndex + 16] ^= 0x01
        assertError(.invalidArchive) {
            try Matrix.validate(
                archive: corrupted,
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }

        let bindingsByScenario = Dictionary(
            uniqueKeysWithValues: fixture.inventory.requirements.map { ($0.id, $0.bindings) }
        )
        let staleBuild = try ComparisonDocumentCoverageInventory.canonical(
            reference: fixture.inventory.reference,
            build: reference("other-build", fixture.inventory.build.revision),
            buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
            bindingsByScenario: bindingsByScenario
        )
        let staleInventory = try ComparisonDocumentCoverageInventory.canonical(
            reference: reference("other-inventory", fixture.inventory.reference.revision),
            build: fixture.inventory.build,
            buildArtifactSHA256: fixture.inventory.buildArtifactSHA256,
            bindingsByScenario: bindingsByScenario
        )
        let staleEvidence = ComparisonDocumentEvidenceBundle(
            reference: reference("other-evidence", fixture.evidence.reference.revision),
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: fixture.evidence.observations
        )
        let resolverCountBeforeStaleInputs = resolver.invocationCount
        let replayCountBeforeStaleInputs = fixture.replays.invocationCount
        assertError(.staleBuild) {
            try result.receipt.validateCurrent(
                inventory: staleBuild,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                archive: result.archive.data,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }
        assertError(.staleInventory) {
            try result.receipt.validateCurrent(
                inventory: staleInventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                archive: result.archive.data,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }
        assertError(.staleEvidence) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: staleEvidence,
                auditPolicy: fixture.policy,
                archive: result.archive.data,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }
        XCTAssertEqual(resolver.invocationCount, resolverCountBeforeStaleInputs)
        XCTAssertEqual(fixture.replays.invocationCount, replayCountBeforeStaleInputs)

        assertError(.nonCanonicalArchive) {
            try result.receipt.validateCurrent(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: policy(
                    fixture,
                    replayPolicy: reference("other-replay-policy", 1)
                ),
                archive: result.archive.data,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }
        XCTAssertEqual(fixture.replays.invocationCount, replayCountBeforeStaleInputs)

        let noncanonicalSectionArchive = canonicalArchive(
            sections,
            inventory: sections.inventory + Data([0x01])
        )
        assertError(.nonCanonicalArchive) {
            try Matrix.validate(
                archive: noncanonicalSectionArchive,
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }
        for invalid in [
            canonicalArchive(sections, magic: Data("MMCDARC5".utf8)),
            canonicalArchive(sections, version: sections.version + 1),
            canonicalArchive(sections, trailingPayload: Data([0x01])),
            canonicalArchive(sections, inventorySHA256: digest(0xF00D))
        ] {
            assertError(.invalidArchive) {
                try Matrix.validate(
                    archive: invalid,
                    inventory: fixture.inventory,
                    evidence: fixture.evidence,
                    auditPolicy: fixture.policy,
                    captureResolver: resolver.resolve,
                    cancellationCheck: { false }
                )
            }
        }
        XCTAssertEqual(fixture.replays.invocationCount, replayCountBeforeStaleInputs)

        let cancellationProbe = InvocationProbe()
        assertError(.cancelled) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                captureResolver: { _, _, _, _ in cancellationProbe.record() },
                cancellationCheck: { true }
            )
        }
        XCTAssertEqual(cancellationProbe.count, 0)
    }

    func testCanonicalEvidencePolicyBytesAndCompleteDigestsArePinned() throws {
        let fixture = try makeSignedFixture()
        let result = try Matrix.audit(
            inventory: fixture.inventory,
            evidence: fixture.evidence,
            auditPolicy: fixture.policy,
            captureResolver: CaptureResolver(
                captures: fixture.captures,
                probesResourceBound: false
            ).resolve,
            cancellationCheck: { false }
        )
        let reversedEvidence = ComparisonDocumentEvidenceBundle(
            reference: fixture.evidence.reference,
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: fixture.evidence.observations.reversed()
        )
        let fixedSignatureEvidence = ComparisonDocumentEvidenceBundle(
            reference: fixture.evidence.reference,
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: try fixture.evidence.observations.map { observation in
                replacing(
                    observation,
                    provenance: provenance(
                        try XCTUnwrap(observation.provenance),
                        collectorSignature: [UInt8](repeating: 0xD1, count: 64)
                    )
                )
            }
        )
        let secondCollector = ComparisonDocumentTrustedCollector(
            reference: reference("document-collector-z", 1),
            ed25519PublicKey: [UInt8](repeating: 0x6B, count: 32)
        )
        let secondLocationKey = ComparisonDocumentStableID(rawValue: "document-location-key-z")
        let policyForward = policy(
            fixture,
            collectors: fixture.policy.trustedCollectors + [secondCollector],
            locationKeys: fixture.policy.trustedLocationKeyReferences.union([secondLocationKey])
        )
        let policyReverse = policy(
            fixture,
            collectors: [secondCollector] + fixture.policy.trustedCollectors,
            locationKeys: Set([secondLocationKey]).union(fixture.policy.trustedLocationKeyReferences)
        )

        XCTAssertEqual(
            try comparisonDocumentCanonicalEvidenceDataForTesting(fixture.evidence),
            try comparisonDocumentCanonicalEvidenceDataForTesting(reversedEvidence)
        )
        XCTAssertEqual(
            try comparisonDocumentCanonicalAuditPolicyDataForTesting(policyForward),
            try comparisonDocumentCanonicalAuditPolicyDataForTesting(policyReverse)
        )
        let sections = try archiveSections(result.archive.data)
        let fixedEvidenceData = try comparisonDocumentCanonicalEvidenceDataForTesting(
            fixedSignatureEvidence
        )
        let fixedSignatureArchive = canonicalArchive(sections, evidence: fixedEvidenceData)
        XCTAssertEqual(
            hex(sha256(try comparisonDocumentCanonicalInventoryDataForTesting(fixture.inventory))),
            "69437f71bdc8c559e58d2e095fa8a7b7bec63fdfabe30310d83b882445e76c3c"
        )
        XCTAssertEqual(
            hex(sha256(fixedEvidenceData)),
            "08f6970e088ae17ba29666e714ecaea2f97be3b55de09bcf9bfb9457e73772ca"
        )
        XCTAssertEqual(
            hex(sha256(try comparisonDocumentCanonicalAuditPolicyDataForTesting(fixture.policy))),
            "61c25e84450b2a5c71d4c773787570efbb3e7d24d5dde1a624aa63d09b7ae5e1"
        )
        XCTAssertEqual(
            hex(sha256(sections.report)),
            "298a69a59153f943c990d9fd19dfa726456917202347a3137644d634d3165948"
        )
        XCTAssertEqual(
            hex(sha256(fixedSignatureArchive)),
            "1c8d49de895ad4380f0685501c8be36a33f6a456cc8f4b4ef02f5314563db985"
        )
        let firstCapture = try XCTUnwrap(fixture.evidence.observations.first?.provenance?.captureSHA256)
        XCTAssertEqual(
            hex(firstCapture),
            "eb144a687d6450f51bccc6e6fa1fa40faa26e0508f7c70290687c91a6996e9b2"
        )
    }

    func testReplayClaimResultsMapExactlyWithoutRepeatingFullMatrixAudits() {
        let maximum = 917
        XCTAssertNil(
            comparisonDocumentReplayClaimError(.committed, maximumWorkUnits: maximum)
        )
        XCTAssertEqual(
            comparisonDocumentReplayClaimError(.rejectedReplay, maximumWorkUnits: maximum),
            .replayClaimRejected
        )
        XCTAssertEqual(
            comparisonDocumentReplayClaimError(.cancelled, maximumWorkUnits: maximum),
            .cancelled
        )
        XCTAssertEqual(
            comparisonDocumentReplayClaimError(.deadlineExceeded, maximumWorkUnits: maximum),
            .replayClaimDeadlineExceeded
        )
        XCTAssertEqual(
            comparisonDocumentReplayClaimError(.workLimitExceeded, maximumWorkUnits: maximum),
            .workLimitExceeded(maximum: maximum)
        )
    }

    func testReplayClaimOutcomesPropagateAfterCompleteAudit() throws {
        let fixture = try makeSignedFixture()
        let resolver = CaptureResolver(captures: fixture.captures, probesResourceBound: false)
        let recorder = ReplayRecorder(result: .rejectedReplay)
        assertError(.replayClaimRejected) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: policy(fixture, replays: recorder),
                captureResolver: resolver.resolve,
                cancellationCheck: { false }
            )
        }
        XCTAssertEqual(recorder.invocationCount, 1)
        XCTAssertEqual(recorder.lastReplayPolicy, fixture.policy.replayPolicy)
        XCTAssertEqual(recorder.lastEvidence, fixture.evidence.reference)
        XCTAssertFalse(recorder.lastArchiveSHA256.isEmpty)
        XCTAssertEqual(recorder.lastClaims.count, Matrix.canonicalScenarios.count)
    }

    func testCrossRequirementLineageConflictsFailRegistration() throws {
        let current = try canonicalScenario { $0.expectedLifecyclePhase == .current }
        let clean = try makeBindings(for: current, seed: 501)
        XCTAssertNoThrow(try comparisonDocumentRegisterLineageForTesting([clean, clean]))

        let second = try makeBindings(for: current, seed: 502)
        let operationCollision = try ComparisonDocumentLifecycleOperationBinding(
            comparison: second.comparison.operation.comparison,
            operationID: clean.comparison.operation.operationID,
            startedAtGeneration: second.comparison.operation.startedAtGeneration,
            inputs: second.comparison.operation.inputs,
            sources: second.comparison.operation.sources
        )
        let operationByComparisonCollision = try ComparisonDocumentLifecycleOperationBinding(
            comparison: clean.comparison.operation.comparison,
            operationID: second.comparison.operation.operationID,
            startedAtGeneration: second.comparison.operation.startedAtGeneration,
            inputs: second.comparison.operation.inputs,
            sources: second.comparison.operation.sources
        )
        let document = clean[.left].document
        let documentCollision = contentRevision(
            identity: document.identity,
            generation: document.generation,
            payload: 502_901
        )
        let opened = try XCTUnwrap(file(from: clean[.left].openedSource))
        let fileCollision = fileRevision(
            identity: opened.identity,
            revision: opened.revision,
            content: contentRevision(identity: uuid(502_902), generation: 1, payload: 502_902)
        )
        let conflicts: [ComparisonDocumentRevisionBindings] = [
            try replacingComparison(
                clean,
                openRequest: clean.comparison.openRequest,
                comparison: reference("foreign-comparison", clean.comparison.comparison.revision)
            ),
            try replacingComparison(
                clean,
                openRequest: ComparisonOpenRequestIdentity(rawValue: uuid(501_999)),
                comparison: clean.comparison.comparison
            ),
            try replacingComparison(
                second,
                operation: operationCollision
            ),
            try replacingComparison(
                second,
                openRequest: clean.comparison.openRequest,
                comparison: clean.comparison.comparison
            ),
            try replacingComparison(
                second,
                operation: operationByComparisonCollision
            ),
            try replacingComparison(
                second,
                inputs: clean.comparison.inputs
            ),
            try replacingSide(
                second,
                side: .left,
                lifecycleSource: clean[.left].lifecycleSource
            ),
            try replacingComparison(
                second,
                result: clean.comparison.result,
                resultInputs: second.comparison.resultInputs
            ),
            try replacingSide(second, side: .left, document: documentCollision),
            try replacingSide(second, side: .left, openedSource: .file(fileCollision))
        ]
        for conflict in conflicts {
            assertError(.invalidInventory(field: "requirements.lineage")) {
                try comparisonDocumentRegisterLineageForTesting([clean, conflict])
            }
        }

        let scratchpadScenario = try canonicalScenario {
            $0.sourceShape == .bothScratchpads && $0.dirtyState == .neither
                && $0.incident == .none && $0.save == .notAttempted
        }
        let firstScratchpad = try makeBindings(for: scratchpadScenario, seed: 505)
        let secondScratchpad = try makeBindings(for: scratchpadScenario, seed: 506)
        guard case .scratchpad(let firstScratchpadRevision) = firstScratchpad[.left].openedSource
        else { return XCTFail("expected scratchpad") }
        let scratchpadCollision = ComparisonDocumentScratchpadRevision(
            identity: firstScratchpadRevision.identity,
            generation: firstScratchpadRevision.generation,
            encodedByteCount: firstScratchpadRevision.encodedByteCount,
            metadataByteCount: firstScratchpadRevision.metadataByteCount,
            encodedContentSHA256: digest(505_999),
            metadataSHA256: firstScratchpadRevision.metadataSHA256,
            contentAndMetadataSHA256: firstScratchpadRevision.contentAndMetadataSHA256,
            encoding: firstScratchpadRevision.encoding,
            isReadOnly: firstScratchpadRevision.isReadOnly
        )
        assertError(.invalidInventory(field: "requirements.lineage")) {
            try comparisonDocumentRegisterLineageForTesting([
                firstScratchpad,
                try replacingSide(
                    secondScratchpad,
                    side: .left,
                    openedSource: .scratchpad(scratchpadCollision)
                )
            ])
        }

        let saveScenario = try canonicalScenario {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left && $0.incident == .none
                && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveAsReplacingFile
                && $0.save.left == .committed(.applied)
        }
        let firstSave = try makeBindings(for: saveScenario, seed: 503)
        let secondSaveBase = try makeBindings(for: saveScenario, seed: 504)
        let firstDestination = try transition(firstSave[.left])
        let secondDestination = try transition(secondSaveBase[.left])
        let slotCollision = ComparisonDocumentSaveDestinationTransition(
            expected: ComparisonDocumentSaveDestinationSnapshot(
                parent: secondDestination.expected.parent,
                slot: firstDestination.expected.slot,
                target: secondDestination.expected.target
            ),
            observedBeforePublication: secondDestination.observedBeforePublication,
            observedAfterExecution: secondDestination.observedAfterExecution
        )
        let slotConflict = try replacingSide(
            secondSaveBase,
            side: .left,
            saveDestination: .transition(slotCollision)
        )
        assertError(.invalidInventory(field: "requirements.lineage")) {
            try comparisonDocumentRegisterLineageForTesting([firstSave, slotConflict])
        }

        let parentCollision = ComparisonDocumentDirectoryRevision(
            identity: firstDestination.expected.parent.identity,
            revision: firstDestination.expected.parent.revision,
            metadataByteCount: firstDestination.expected.parent.metadataByteCount + 1,
            metadataSHA256: firstDestination.expected.parent.metadataSHA256
        )
        let directoryConflict = try replacingSide(
            secondSaveBase,
            side: .left,
            saveDestination: .transition(
                ComparisonDocumentSaveDestinationTransition(
                    expected: ComparisonDocumentSaveDestinationSnapshot(
                        parent: parentCollision,
                        slot: secondDestination.expected.slot,
                        target: secondDestination.expected.target
                    ),
                    observedBeforePublication: secondDestination.observedBeforePublication,
                    observedAfterExecution: secondDestination.observedAfterExecution
                )
            )
        )
        assertError(.invalidInventory(field: "requirements.lineage")) {
            try comparisonDocumentRegisterLineageForTesting([firstSave, directoryConflict])
        }
        let firstOpenedFile = try XCTUnwrap(file(from: firstSave[.left].openedSource))
        let physicalRoleConflict = try replacingSide(
            secondSaveBase,
            side: .left,
            saveDestination: .transition(
                ComparisonDocumentSaveDestinationTransition(
                    expected: ComparisonDocumentSaveDestinationSnapshot(
                        parent: ComparisonDocumentDirectoryRevision(
                            identity: firstOpenedFile.identity,
                            revision: 1,
                            metadataByteCount: 4,
                            metadataSHA256: digest(506_999)
                        ),
                        slot: secondDestination.expected.slot,
                        target: secondDestination.expected.target
                    ),
                    observedBeforePublication: secondDestination.observedBeforePublication,
                    observedAfterExecution: secondDestination.observedAfterExecution
                )
            )
        )
        assertError(.invalidInventory(field: "requirements.lineage")) {
            try comparisonDocumentRegisterLineageForTesting([firstSave, physicalRoleConflict])
        }

        let sharedPlan = try XCTUnwrap(firstSave[.left].saveOperation?.planID)
        let secondSave = try replacingSaveOperation(
            secondSaveBase,
            side: .left,
            planID: sharedPlan
        )
        assertError(.invalidInventory(field: "requirements.lineage")) {
            try comparisonDocumentRegisterLineageForTesting([firstSave, secondSave])
        }
    }

    func testCaptureResolverErrorsTranslateAndFailClosed() throws {
        let expected = Data("resolver-capture".utf8)
        let digest = sha256(expected)
        func resolve(
            _ resolver: @escaping ComparisonDocumentCoverageMatrix.CaptureResolver
        ) throws -> Bool {
            try comparisonDocumentResolveCapture(
                resolver,
                digest: digest,
                declaredByteCount: expected.count,
                sink: ComparisonDocumentCaptureSink(
                    maximumByteCount: expected.count,
                    expected: expected
                ),
                cancellationCheck: { false }
            )
        }

        XCTAssertTrue(
            try resolve { _, _, sink, _ in try sink.append(expected) }
        )
        XCTAssertFalse(
            try resolve { _, _, _, _ in
                throw ComparisonDocumentCaptureResolutionError.declaredByteCountMismatch
            }
        )
        XCTAssertFalse(
            try resolve { _, _, sink, _ in try sink.append(expected.dropLast()) }
        )
        XCTAssertFalse(
            try resolve { _, _, sink, _ in
                try sink.append(expected.dropLast())
                try sink.append(Data([0xFF]))
            }
        )
        XCTAssertFalse(
            try resolve { _, _, _, _ in
                throw ComparisonDocumentCoverageError.staleInventory
            }
        )
        let prematurelyFinished = ComparisonDocumentCaptureSink(
            maximumByteCount: expected.count,
            expected: expected
        )
        _ = try prematurelyFinished.finish()
        XCTAssertFalse(
            try comparisonDocumentResolveCapture(
                { _, _, _, _ in },
                digest: digest,
                declaredByteCount: expected.count,
                sink: prematurelyFinished,
                cancellationCheck: { false }
            )
        )
        assertError(.cancelled) {
            try resolve { _, _, _, _ in throw CancellationError() }
        }
        assertError(.cancelled) {
            try resolve { _, _, _, _ in throw ComparisonDocumentCoverageError.cancelled }
        }
        assertError(.workLimitExceeded(maximum: 7)) {
            try resolve { _, _, _, _ in
                throw ComparisonDocumentCoverageError.workLimitExceeded(maximum: 7)
            }
        }
    }

    func testCaptureSinkBoundsBytesDigestCompletionAndCancellation() throws {
        let expected = Data("bounded-capture".utf8)
        let sink = ComparisonDocumentCaptureSink(
            maximumByteCount: expected.count,
            expected: expected
        )
        try sink.append(expected.prefix(4))
        try sink.append(expected.dropFirst(4))
        let result = try sink.finish()
        XCTAssertEqual(result.byteCount, expected.count)
        XCTAssertEqual(result.sha256, sha256(expected))
        XCTAssertTrue(result.matchesExpected)
        XCTAssertThrowsError(try sink.finish()) {
            XCTAssertEqual(
                $0 as? ComparisonDocumentCaptureResolutionError,
                .declaredByteCountMismatch
            )
        }

        let overflow = ComparisonDocumentCaptureSink(maximumByteCount: 2, expected: Data([1, 2]))
        XCTAssertThrowsError(try overflow.append(Data([1, 2, 3]))) {
            XCTAssertEqual(
                $0 as? ComparisonDocumentCaptureResolutionError,
                .exceedsMaximumByteCount
            )
        }
        let underfill = ComparisonDocumentCaptureSink(maximumByteCount: 2, expected: Data([1, 2]))
        try underfill.append(Data([1]))
        XCTAssertFalse(try underfill.finish().matchesExpected)
        let wrong = ComparisonDocumentCaptureSink(maximumByteCount: 2, expected: Data([1, 2]))
        try wrong.append(Data([1, 3]))
        XCTAssertFalse(try wrong.finish().matchesExpected)

        let scenario = try canonicalScenario { $0.save == .notAttempted }
        let observation = assertion(scenario, try makeBindings(for: scenario, seed: 98_001))
        let cancellation = CancellationProbe(cancelAtInvocation: 3)
        assertError(.cancelled) {
            try Matrix.canonicalCaptureData(
                for: observation,
                limits: limits(cancellationCheckInterval: 1),
                cancellationCheck: cancellation.check
            )
        }
        XCTAssertEqual(cancellation.invocationCount, 3)

        let resolverCancellation = CancellationProbe(cancelAtInvocation: 1)
        let resolverSink = ComparisonDocumentCaptureSink(
            maximumByteCount: expected.count,
            expected: expected
        )
        assertError(.cancelled) {
            try comparisonDocumentResolveCapture(
                { _, _, sink, cancellationCheck in
                    try sink.append(expected.prefix(1))
                    if cancellationCheck() { throw CancellationError() }
                    XCTFail("resolver did not cancel after first chunk")
                },
                digest: sha256(expected),
                declaredByteCount: expected.count,
                sink: resolverSink,
                cancellationCheck: resolverCancellation.check
            )
        }
        XCTAssertEqual(resolverCancellation.invocationCount, 1)

        let copyCancellation = CancellationProbe(cancelAtInvocation: 3)
        assertError(.cancelled) {
            try comparisonDocumentCanonicalDataCopyForTesting(
                Data(repeating: 0xA5, count: 64),
                limits: limits(maximumCanonicalBytes: 80, cancellationCheckInterval: 8),
                cancellationCheck: copyCancellation.check
            )
        }
        XCTAssertEqual(copyCancellation.invocationCount, 3)
    }

    func testEveryMismatchDimensionMapsToItsExactFinding() throws {
        let scenario = try canonicalScenario {
            $0.sourceShape == .bothFiles && $0.dirtyState == .left
                && $0.incident == .none && $0.save.execution == .single(.left)
                && $0.save.leftOperation == .saveInPlace && $0.save.left == .committed(.applied)
        }
        let bindings = try makeBindings(for: scenario, seed: 90_000)
        let baseline = assertion(scenario, bindings)
        func assertMismatch(
            _ expected: ComparisonDocumentFindingCode,
            observation: ComparisonDocumentProductionObservation,
            discriminator: Int = 0,
            expectedID: String? = nil
        ) {
            let result = comparisonDocumentMismatchAssessmentForTesting(
                observation,
                scenario: scenario,
                bindings: bindings,
                discriminator: discriminator
            )
            XCTAssertEqual(result.status, .mismatched)
            XCTAssertEqual(result.findingCodes, [expected])
            if let expectedID {
                XCTAssertEqual(result.findingIDs.map(\.rawValue), [expectedID])
            }
        }
        func observation(
            bindings: ComparisonDocumentRevisionBindings? = nil,
            lifecycle: ComparisonDocumentLifecycleObservation? = nil,
            left: ComparisonDocumentPaneObservation? = nil,
            save: ComparisonDocumentSaveState? = nil,
            omitSaveExecutorContract: Bool = false,
            backup: ComparisonDocumentBackupState? = nil
        ) -> ComparisonDocumentProductionObservation {
            ComparisonDocumentProductionObservation(
                scenarioID: baseline.scenarioID,
                bindings: bindings ?? baseline.bindings,
                lifecycle: lifecycle ?? baseline.lifecycle,
                left: left ?? baseline.left,
                right: baseline.right,
                save: save ?? baseline.save,
                saveExecutorContract: omitSaveExecutorContract ? nil : baseline.saveExecutorContract,
                backup: backup ?? baseline.backup,
                origin: baseline.origin,
                provenance: baseline.provenance
            )
        }
        XCTAssertEqual(
            comparisonDocumentMismatchAssessmentForTesting(
                baseline,
                scenario: scenario,
                bindings: bindings
            ).status,
            .complete
        )
        assertMismatch(
            .revisionBindingMismatch,
            observation: observation(bindings: try makeBindings(for: scenario, seed: 90_001))
        )
        assertMismatch(
            .sourceShapeMismatch,
            observation: observation(
                left: pane(baseline.left, sourceKind: baseline.left.sourceKind == .file ? .scratchpad : .file)
            ),
            discriminator: 3,
            expectedID: expectedFindingID(
                .sourceShapeMismatch,
                scenarioID: scenario.id,
                discriminator: 6
            )
        )
        let rightMismatch = ComparisonDocumentProductionObservation(
            scenarioID: baseline.scenarioID,
            bindings: baseline.bindings,
            lifecycle: baseline.lifecycle,
            left: baseline.left,
            right: pane(
                baseline.right,
                sourceKind: baseline.right.sourceKind == .file ? .scratchpad : .file
            ),
            save: baseline.save,
            saveExecutorContract: baseline.saveExecutorContract,
            backup: baseline.backup,
            origin: baseline.origin,
            provenance: baseline.provenance
        )
        assertMismatch(
            .sourceShapeMismatch,
            observation: rightMismatch,
            discriminator: 3,
            expectedID: expectedFindingID(
                .sourceShapeMismatch,
                scenarioID: scenario.id,
                discriminator: 7
            )
        )
        assertMismatch(
            .documentDirtyStateMismatch,
            observation: observation(left: pane(baseline.left, isDirty: !baseline.left.isDirty))
        )
        assertMismatch(
            .sourceAvailabilityMismatch,
            observation: observation(
                left: pane(
                    baseline.left,
                    diskState: baseline.left.diskState == .present ? .missing : .present
                )
            )
        )
        assertMismatch(
            .lifecycleMismatch,
            observation: observation(
                lifecycle: ComparisonDocumentLifecycleObservation(
                    phase: .current,
                    hasCurrentResult: true,
                    hasRetainedResult: true,
                    staleReason: baseline.lifecycle.staleReason
                )
            )
        )
        assertMismatch(
            .staleReasonMismatch,
            observation: observation(
                lifecycle: ComparisonDocumentLifecycleObservation(
                    phase: baseline.lifecycle.phase,
                    hasCurrentResult: baseline.lifecycle.hasCurrentResult,
                    hasRetainedResult: baseline.lifecycle.hasRetainedResult,
                    staleReason: .optionsChanged
                )
            )
        )
        assertMismatch(.saveStateMismatch, observation: observation(save: .notAttempted))
        assertMismatch(
            .saveContractMismatch,
            observation: observation(omitSaveExecutorContract: true)
        )
        assertMismatch(
            .backupContractMismatch,
            observation: observation(backup: .notApplicable)
        )
    }

    func testProvenanceStructureRejectsEveryMalformedFieldIndependently() throws {
        let valid = ComparisonDocumentEvidenceProvenance(
            build: reference("build", 1),
            inventory: reference("inventory", 1),
            evidence: reference("evidence", 1),
            collector: reference("collector", 1),
            run: reference("run", 1),
            capturedAtUnixMilliseconds: 1,
            runNonce: [UInt8](repeating: 1, count: 16),
            artifactSHA256: digest(1),
            captureSHA256: digest(2),
            captureByteCount: 1,
            collectorSignature: [UInt8](repeating: 3, count: 64),
            source: .automatedHarness
        )
        XCTAssertTrue(comparisonDocumentProvenanceIsValidForTesting(valid))
        let invalid = [
            provenance(valid, capturedAt: 0),
            provenance(valid, runNonce: [UInt8](repeating: 1, count: 15)),
            provenance(valid, artifactSHA256: [UInt8](repeating: 0, count: SHA256.byteCount)),
            provenance(valid, captureSHA256: [UInt8](repeating: 0, count: SHA256.byteCount)),
            provenance(valid, captureByteCount: 0),
            provenance(valid, collectorSignature: [UInt8](repeating: 3, count: 63))
        ]
        for value in invalid {
            XCTAssertFalse(comparisonDocumentProvenanceIsValidForTesting(value))
        }
    }

    func testAllCompletenessFindingAndProvenanceClassesUseIndependentMutations() throws {
        let fixture = try makeSignedFixture()
        var observations = fixture.evidence.observations
        var captures = fixture.captures
        let missing = observations.removeFirst()
        let duplicate = observations[0]
        observations.append(duplicate)
        observations.append(
            ComparisonDocumentProductionObservation(
                scenarioID: ComparisonDocumentScenarioID(rawValue: UInt32.max),
                bindings: observations[1].bindings,
                lifecycle: observations[1].lifecycle,
                left: observations[1].left,
                right: observations[1].right,
                save: observations[1].save,
                saveExecutorContract: observations[1].saveExecutorContract,
                backup: observations[1].backup,
                origin: .callerAssertion,
                provenance: nil
            )
        )

        let mismatchIndex = try XCTUnwrap(
            observations.firstIndex { observation in
                guard let requirement = fixture.inventory.requirements.first(where: { $0.id == observation.scenarioID }) else {
                    return false
                }
                return requirement.expected.lifecyclePhase == .stale
                    && requirement.expected.saveExecutorContract != nil
                    && requirement.expected.backup != .notApplicable
            }
        )
        let mismatchBase = observations[mismatchIndex]
        let mismatchScenario = try XCTUnwrap(
            fixture.inventory.requirements.first { $0.id == mismatchBase.scenarioID }?.scenario
        )
        let mismatchLeft = ComparisonDocumentPaneObservation(
            sourceKind: mismatchBase.left.sourceKind == .file ? .scratchpad : .file,
            isLoaded: !mismatchBase.left.isLoaded,
            isEditable: !mismatchBase.left.isEditable,
            isDirty: !mismatchBase.left.isDirty,
            isUntitled: !mismatchBase.left.isUntitled,
            diskState: mismatchBase.left.diskState == .present ? .missing : .present
        )
        let mismatchUnsigned = ComparisonDocumentProductionObservation(
            scenarioID: mismatchBase.scenarioID,
            bindings: try makeBindings(for: mismatchScenario, seed: 80_001, locationKey: fixture.locationKey),
            lifecycle: ComparisonDocumentLifecycleObservation(
                phase: .current,
                hasCurrentResult: false,
                hasRetainedResult: false,
                staleReason: .optionsChanged
            ),
            left: mismatchLeft,
            right: mismatchBase.right,
            save: .notAttempted,
            saveExecutorContract: nil,
            backup: .notApplicable,
            origin: .productionAutomation,
            provenance: mismatchBase.provenance
        )
        let mismatchSigned = try resign(mismatchUnsigned, fixture: fixture)
        observations[mismatchIndex] = mismatchSigned.observation
        captures[mismatchSigned.captureSHA256] = mismatchSigned.capture

        let missingProvenanceIndex = mismatchIndex + 1
        let missingProvenanceBase = observations[missingProvenanceIndex]
        observations[missingProvenanceIndex] = replacing(
            missingProvenanceBase,
            provenance: nil
        )

        let malformedIndex = mismatchIndex + 2
        let malformedBase = observations[malformedIndex]
        let malformed = try XCTUnwrap(malformedBase.provenance)
        observations[malformedIndex] = replacing(
            malformedBase,
            provenance: provenance(
                malformed,
                runNonce: [UInt8](repeating: 0xA7, count: 15),
                source: .manualProductionReview
            )
        )

        let buildIndex = mismatchIndex + 3
        let buildBase = observations[buildIndex]
        let buildProvenance = try XCTUnwrap(buildBase.provenance)
        observations[buildIndex] = replacing(
            buildBase,
            provenance: provenance(
                buildProvenance,
                build: reference("other-build", buildProvenance.build.revision)
            )
        )

        let inventoryIndex = mismatchIndex + 4
        let inventoryBase = observations[inventoryIndex]
        observations[inventoryIndex] = replacing(
            inventoryBase,
            provenance: provenance(
                try XCTUnwrap(inventoryBase.provenance),
                inventory: reference("other-inventory", 1)
            )
        )

        let evidenceIndex = mismatchIndex + 5
        let evidenceBase = observations[evidenceIndex]
        observations[evidenceIndex] = replacing(
            evidenceBase,
            provenance: provenance(
                try XCTUnwrap(evidenceBase.provenance),
                evidence: reference("other-evidence", 1)
            )
        )

        let artifactIndex = mismatchIndex + 6
        let artifactBase = observations[artifactIndex]
        observations[artifactIndex] = replacing(
            artifactBase,
            provenance: provenance(
                try XCTUnwrap(artifactBase.provenance),
                artifactSHA256: digest(0xBAD)
            )
        )

        let collectorIndex = mismatchIndex + 7
        let collectorBase = observations[collectorIndex]
        observations[collectorIndex] = replacing(
            collectorBase,
            provenance: provenance(
                try XCTUnwrap(collectorBase.provenance),
                collector: reference("untrusted-collector", 1)
            )
        )

        let oldTimeIndex = mismatchIndex + 8
        let oldTimeBase = observations[oldTimeIndex]
        observations[oldTimeIndex] = replacing(
            oldTimeBase,
            provenance: provenance(
                try XCTUnwrap(oldTimeBase.provenance),
                capturedAt: fixture.auditTime - 2
            )
        )

        let futureTimeIndex = mismatchIndex + 9
        let futureTimeBase = observations[futureTimeIndex]
        observations[futureTimeIndex] = replacing(
            futureTimeBase,
            provenance: provenance(
                try XCTUnwrap(futureTimeBase.provenance),
                capturedAt: fixture.auditTime + 2
            )
        )

        let sourceIndex = mismatchIndex + 10
        let sourceBase = observations[sourceIndex]
        observations[sourceIndex] = replacing(
            sourceBase,
            provenance: provenance(
                try XCTUnwrap(sourceBase.provenance),
                source: .manualProductionReview
            )
        )

        let captureIndex = mismatchIndex + 11
        let captureBase = observations[captureIndex]
        let capture = try XCTUnwrap(captureBase.provenance)
        observations[captureIndex] = replacing(
            captureBase,
            provenance: provenance(capture, captureSHA256: digest(0xCAFE))
        )

        let signatureIndex = mismatchIndex + 12
        let signatureBase = observations[signatureIndex]
        observations[signatureIndex] = replacing(
            signatureBase,
            provenance: provenance(
                try XCTUnwrap(signatureBase.provenance),
                collectorSignature: [UInt8](repeating: 0xEE, count: 64)
            )
        )

        let registeredProvenance = try XCTUnwrap(observations[0].provenance)
        let nonceCollisionIndex = mismatchIndex + 13
        let nonceCollisionBase = observations[nonceCollisionIndex]
        observations[nonceCollisionIndex] = replacing(
            nonceCollisionBase,
            provenance: provenance(
                try XCTUnwrap(nonceCollisionBase.provenance),
                runNonce: registeredProvenance.runNonce
            )
        )

        let runCollisionIndex = mismatchIndex + 14
        let runCollisionBase = observations[runCollisionIndex]
        observations[runCollisionIndex] = replacing(
            runCollisionBase,
            provenance: provenance(
                try XCTUnwrap(runCollisionBase.provenance),
                run: registeredProvenance.run
            )
        )

        let assertionIndex = mismatchIndex + 15
        let assertionBase = observations[assertionIndex]
        observations[assertionIndex] = replacing(
            assertionBase,
            origin: .callerAssertion,
            provenance: nil
        )

        let manualIndex = mismatchIndex + 16
        let manualBase = observations[manualIndex]
        let manualUnsigned = replacing(
            manualBase,
            origin: .productionManualMeasurement,
            provenance: provenance(
                try XCTUnwrap(manualBase.provenance),
                source: .manualProductionReview
            )
        )
        let manualSigned = try resign(manualUnsigned, fixture: fixture)
        observations[manualIndex] = manualSigned.observation
        captures[manualSigned.captureSHA256] = manualSigned.capture

        let evidence = ComparisonDocumentEvidenceBundle(
            reference: fixture.evidence.reference,
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: observations
        )
        let replay = ReplayRecorder()
        let auditPolicy = auditPolicy(fixture: fixture, replays: replay)
        let result = try Matrix.audit(
            inventory: fixture.inventory,
            evidence: evidence,
            auditPolicy: auditPolicy,
            captureResolver: CaptureResolver(captures: captures, probesResourceBound: false).resolve,
            cancellationCheck: { false }
        )

        XCTAssertEqual(result.report.matrix.missingCount, 1)
        XCTAssertEqual(result.report.matrix.duplicateCount, 1)
        XCTAssertGreaterThanOrEqual(result.report.matrix.mismatchedCount, 1)
        XCTAssertGreaterThanOrEqual(result.report.matrix.invalidCount, 4)
        XCTAssertEqual(result.report.matrix.assertionOnlyCount, 1)
        XCTAssertEqual(
            Set(result.report.findings.map(\.code)),
            Set(ComparisonDocumentFindingCode.allCases)
        )
        XCTAssertEqual(
            result.report.matrix.cells.first { $0.scenario.id == missing.scenarioID }?.status,
            .missing
        )
        XCTAssertEqual(
            result.report.matrix.cells.first { $0.scenario.id == duplicate.scenarioID }?.status,
            .duplicate
        )
        XCTAssertEqual(
            result.report.matrix.cells.first { $0.scenario.id == mismatchBase.scenarioID }?.status,
            .mismatched
        )
        XCTAssertEqual(
            result.report.matrix.cells.first { $0.scenario.id == assertionBase.scenarioID }?.status,
            .assertionOnly
        )
        XCTAssertEqual(
            result.report.matrix.cells.first { $0.scenario.id == manualBase.scenarioID }?.status,
            .complete
        )
        XCTAssertEqual(findingCodes(result, scenarioID: buildBase.scenarioID), [.provenanceBuildMismatch])
        for scenarioID in [
            inventoryBase.scenarioID,
            evidenceBase.scenarioID,
            oldTimeBase.scenarioID,
            futureTimeBase.scenarioID,
            sourceBase.scenarioID,
            nonceCollisionBase.scenarioID,
            runCollisionBase.scenarioID
        ] {
            XCTAssertEqual(findingCodes(result, scenarioID: scenarioID), [.productionProvenanceInvalid])
        }
        XCTAssertEqual(
            findingCodes(result, scenarioID: artifactBase.scenarioID),
            [.provenanceArtifactMismatch]
        )
        XCTAssertEqual(findingCodes(result, scenarioID: collectorBase.scenarioID), [.untrustedCollector])
        XCTAssertEqual(
            findingCodes(result, scenarioID: captureBase.scenarioID),
            [.productionCaptureMismatch]
        )
        XCTAssertEqual(
            findingCodes(result, scenarioID: signatureBase.scenarioID),
            [.productionCaptureMismatch]
        )
        XCTAssertEqual(replay.invocationCount, 0)

        let limitResolver = InvocationProbe()
        let invalidLimits: [(ComparisonDocumentCoverageLimit, ComparisonDocumentCoverageLimits)] = [
            (.observations, limits(maximumObservations: 0)),
            (.trustedCollectors, limits(maximumTrustedCollectors: 0)),
            (.stringUTF8Bytes, limits(maximumStringUTF8Bytes: 0)),
            (.totalStringUTF8Bytes, limits(maximumTotalStringUTF8Bytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.findings, limits(maximumFindings: 0)),
            (.canonicalBytes, limits(maximumCanonicalBytes: 0)),
            (.archiveBytes, limits(maximumArchiveBytes: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0))
        ]
        for (limit, value) in invalidLimits {
            assertError(.invalidLimit(limit)) {
                try Matrix.audit(
                    inventory: fixture.inventory,
                    evidence: fixture.evidence,
                    auditPolicy: fixture.policy,
                    limits: value,
                    captureResolver: { _, _, _, _ in limitResolver.record() },
                    cancellationCheck: { false }
                )
            }
        }
        assertError(.observationLimitExceeded(maximum: fixture.evidence.observations.count - 1)) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                limits: limits(maximumObservations: fixture.evidence.observations.count - 1),
                captureResolver: { _, _, _, _ in limitResolver.record() },
                cancellationCheck: { false }
            )
        }
        let extraCollector = ComparisonDocumentTrustedCollector(
            reference: reference("extra-collector", 1),
            ed25519PublicKey: [UInt8](repeating: 0x7A, count: 32)
        )
        assertError(.invalidInventory(field: "provenanceRoots")) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: policy(
                    fixture,
                    collectors: fixture.policy.trustedCollectors + [extraCollector]
                ),
                limits: limits(maximumTrustedCollectors: 1),
                captureResolver: { _, _, _, _ in limitResolver.record() },
                cancellationCheck: { false }
            )
        }
        assertError(.stringTooLarge(field: "inventory.reference", maximumUTF8Bytes: 1)) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                limits: limits(maximumStringUTF8Bytes: 1),
                captureResolver: { _, _, _, _ in limitResolver.record() },
                cancellationCheck: { false }
            )
        }
        assertError(.totalStringsTooLarge(maximumUTF8Bytes: 64)) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                limits: limits(maximumStringUTF8Bytes: 64, maximumTotalStringUTF8Bytes: 64),
                captureResolver: { _, _, _, _ in limitResolver.record() },
                cancellationCheck: { false }
            )
        }
        let emptyEvidence = ComparisonDocumentEvidenceBundle(
            reference: fixture.evidence.reference,
            inventory: fixture.evidence.inventory,
            build: fixture.evidence.build,
            observations: []
        )
        assertError(.findingLimitExceeded(maximum: 1)) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: emptyEvidence,
                auditPolicy: fixture.policy,
                limits: limits(maximumFindings: 1),
                captureResolver: { _, _, _, _ in limitResolver.record() },
                cancellationCheck: { false }
            )
        }
        assertError(.canonicalDataTooLarge(maximumBytes: 1)) {
            try Matrix.audit(
                inventory: fixture.inventory,
                evidence: fixture.evidence,
                auditPolicy: fixture.policy,
                limits: limits(maximumCanonicalBytes: 1, maximumArchiveBytes: 1),
                captureResolver: { _, _, _, _ in limitResolver.record() },
                cancellationCheck: { false }
            )
        }
        XCTAssertEqual(limitResolver.count, 0)
        XCTAssertEqual(fixture.replays.invocationCount, 0)
    }

    func testLimitsRejectEveryInvalidBoundaryBeforeResolvingCaptures() throws {
        let scenario = try canonicalScenario { $0.save == .notAttempted }
        let bindings = try makeBindings(for: scenario, seed: 141)
        let observation = assertion(scenario, bindings)
        let invalid: [(ComparisonDocumentCoverageLimit, ComparisonDocumentCoverageLimits)] = [
            (.observations, limits(maximumObservations: 0)),
            (.trustedCollectors, limits(maximumTrustedCollectors: 0)),
            (.stringUTF8Bytes, limits(maximumStringUTF8Bytes: 0)),
            (.totalStringUTF8Bytes, limits(maximumTotalStringUTF8Bytes: 0)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.findings, limits(maximumFindings: 0)),
            (.canonicalBytes, limits(maximumCanonicalBytes: 0)),
            (.archiveBytes, limits(maximumArchiveBytes: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0)),
            (
                .observations,
                limits(maximumObservations: ComparisonDocumentCoverageLimits.hardMaximumObservations + 1)
            ),
            (
                .trustedCollectors,
                limits(maximumTrustedCollectors: ComparisonDocumentCoverageLimits.hardMaximumTrustedCollectors + 1)
            ),
            (
                .stringUTF8Bytes,
                limits(maximumStringUTF8Bytes: ComparisonDocumentCoverageLimits.hardMaximumStringUTF8Bytes + 1)
            ),
            (
                .totalStringUTF8Bytes,
                limits(maximumTotalStringUTF8Bytes: ComparisonDocumentCoverageLimits.hardMaximumTotalStringUTF8Bytes + 1)
            ),
            (
                .workUnits,
                limits(maximumWorkUnits: ComparisonDocumentCoverageLimits.hardMaximumWorkUnits + 1)
            ),
            (
                .findings,
                limits(maximumFindings: ComparisonDocumentCoverageLimits.hardMaximumFindings + 1)
            ),
            (
                .canonicalBytes,
                limits(maximumCanonicalBytes: ComparisonDocumentCoverageLimits.hardMaximumCanonicalBytes + 1)
            ),
            (
                .archiveBytes,
                limits(maximumArchiveBytes: ComparisonDocumentCoverageLimits.hardMaximumArchiveBytes + 1)
            ),
            (
                .cancellationCheckInterval,
                limits(
                    cancellationCheckInterval: ComparisonDocumentCoverageLimits.hardMaximumCancellationCheckInterval + 1
                )
            )
        ]
        XCTAssertEqual(Set(invalid.map(\.0)), Set(ComparisonDocumentCoverageLimit.allCases))
        for (expected, value) in invalid {
            assertError(.invalidLimit(expected)) {
                try Matrix.canonicalCaptureData(for: observation, limits: value, cancellationCheck: { false })
            }
        }
        assertError(.invalidLimit(.totalStringUTF8Bytes)) {
            try Matrix.canonicalCaptureData(
                for: observation,
                limits: limits(maximumStringUTF8Bytes: 2, maximumTotalStringUTF8Bytes: 1),
                cancellationCheck: { false }
            )
        }
        assertError(.invalidLimit(.archiveBytes)) {
            try Matrix.canonicalCaptureData(
                for: observation,
                limits: limits(maximumCanonicalBytes: 2, maximumArchiveBytes: 1),
                cancellationCheck: { false }
            )
        }
        XCTAssertNoThrow(
            try Matrix.canonicalCaptureData(
                for: observation,
                limits: limits(
                    maximumObservations: 1,
                    maximumTrustedCollectors: 1,
                    maximumStringUTF8Bytes: ComparisonDocumentCoverageLimits.hardMaximumStringUTF8Bytes,
                    maximumTotalStringUTF8Bytes: ComparisonDocumentCoverageLimits.hardMaximumTotalStringUTF8Bytes,
                    maximumWorkUnits: ComparisonDocumentCoverageLimits.hardMaximumWorkUnits,
                    maximumFindings: 1,
                    maximumCanonicalBytes: ComparisonDocumentCoverageLimits.hardMaximumCanonicalBytes,
                    maximumArchiveBytes: ComparisonDocumentCoverageLimits.hardMaximumArchiveBytes,
                    cancellationCheckInterval: ComparisonDocumentCoverageLimits.hardMaximumCancellationCheckInterval
                ),
                cancellationCheck: { false }
            )
        )
        assertError(.workLimitExceeded(maximum: 1)) {
            try Matrix.canonicalCaptureData(
                for: observation,
                limits: limits(maximumWorkUnits: 1),
                cancellationCheck: { false }
            )
        }
        assertError(.cancelled) {
            try Matrix.canonicalCaptureData(for: observation, cancellationCheck: { true })
        }
    }

    private struct SaveOracleKey: Hashable {
        let execution: ComparisonDocumentSaveExecution
        let leftOperation: ComparisonDocumentSideSaveOperation
        let left: ComparisonDocumentSideSaveOutcome
        let rightOperation: ComparisonDocumentSideSaveOperation
        let right: ComparisonDocumentSideSaveOutcome

        init(_ save: ComparisonDocumentSaveState) {
            execution = save.execution
            leftOperation = save.leftOperation
            left = save.left
            rightOperation = save.rightOperation
            right = save.right
        }

        init(
            execution: ComparisonDocumentSaveExecution,
            leftOperation: ComparisonDocumentSideSaveOperation,
            left: ComparisonDocumentSideSaveOutcome,
            rightOperation: ComparisonDocumentSideSaveOperation,
            right: ComparisonDocumentSideSaveOutcome
        ) {
            self.execution = execution
            self.leftOperation = leftOperation
            self.left = left
            self.rightOperation = rightOperation
            self.right = right
        }

        func operation(on side: ComparisonDocumentSide) -> ComparisonDocumentSideSaveOperation {
            side == .left ? leftOperation : rightOperation
        }

        func outcome(on side: ComparisonDocumentSide) -> ComparisonDocumentSideSaveOutcome {
            side == .left ? left : right
        }
    }

    private struct BackupOracleKey: Hashable {
        let left: ComparisonDocumentSideBackupState
        let right: ComparisonDocumentSideBackupState

        init(_ backup: ComparisonDocumentBackupState) {
            left = backup.left
            right = backup.right
        }

        init(left: ComparisonDocumentSideBackupState, right: ComparisonDocumentSideBackupState) {
            self.left = left
            self.right = right
        }

        func state(on side: ComparisonDocumentSide) -> ComparisonDocumentSideBackupState {
            side == .left ? left : right
        }
    }

    private struct ScenarioOracleKey: Hashable {
        let sourceShape: ComparisonDocumentSourceShape
        let dirtyState: ComparisonDocumentDirtyState
        let incident: ComparisonDocumentIncident
        let save: SaveOracleKey
        let backup: BackupOracleKey

        init(_ scenario: ComparisonDocumentScenario) {
            sourceShape = scenario.sourceShape
            dirtyState = scenario.dirtyState
            incident = scenario.incident
            save = SaveOracleKey(scenario.save)
            backup = BackupOracleKey(scenario.backup)
        }

        init(
            sourceShape: ComparisonDocumentSourceShape,
            dirtyState: ComparisonDocumentDirtyState,
            incident: ComparisonDocumentIncident,
            save: SaveOracleKey,
            backup: BackupOracleKey
        ) {
            self.sourceShape = sourceShape
            self.dirtyState = dirtyState
            self.incident = incident
            self.save = save
            self.backup = backup
        }
    }

    private struct PaneStateOracle {
        let sourceKind: ComparisonDocumentSourceKind
        let diskState: ComparisonDocumentDiskState
        let isDirty: Bool
    }

    private struct ExpectedStateOracle {
        let lifecyclePhase: ComparisonLifecycleState.Phase
        let staleReasons: [ComparisonLifecycleState.StaleReason]
        let left: PaneStateOracle
        let right: PaneStateOracle

        func pane(_ side: ComparisonDocumentSide) -> PaneStateOracle {
            side == .left ? left : right
        }
    }

    private enum PayloadCorruption: UInt64, CaseIterable {
        case byteCount
        case metadataByteCount
        case contentSHA256
        case metadataSHA256
        case contentAndMetadataSHA256
        case encoding
        case readOnly
    }

    private func expectedScenarioOracleKeys() throws -> Set<ScenarioOracleKey> {
        var expected: Set<ScenarioOracleKey> = []
        let saves = expectedSaveOracleKeys()
        for sourceShape in ComparisonDocumentSourceShape.allCases {
            for dirtyState in ComparisonDocumentDirtyState.allCases {
                for leftIncident in ComparisonDocumentSideIncident.allCases {
                    for rightIncident in ComparisonDocumentSideIncident.allCases {
                        let incident = ComparisonDocumentIncident(left: leftIncident, right: rightIncident)
                        for save in saves
                        where scenarioOracleIsValid(
                            sourceShape: sourceShape,
                            dirtyState: dirtyState,
                            incident: incident,
                            save: save
                        ) {
                            for backup in expectedBackupOracleKeys(save: save, incident: incident) {
                                expected.insert(
                                    ScenarioOracleKey(
                                        sourceShape: sourceShape,
                                        dirtyState: dirtyState,
                                        incident: incident,
                                        save: save,
                                        backup: backup
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
        return expected
    }

    private func expectedSaveOracleKeys() -> Set<SaveOracleKey> {
        let failures: [ThreePaneSaveNonCommitReason] = [
            .cancelled,
            .sourceRevisionChanged,
            .destinationCompareFailed,
            .safetyContractUnavailable,
            .publicationFailedBeforeMutation
        ]
        let uncertainties: [ThreePaneSaveCommitUncertainty] = [
            .publicationStateUnknown,
            .committedBytesUnverified,
            .durabilityUnverified,
            .recoveryStateUnknown
        ]
        let outcomes =
            failures.map(ComparisonDocumentSideSaveOutcome.failed)
            + uncertainties.map(ComparisonDocumentSideSaveOutcome.uncertain)
            + [ComparisonDocumentSideSaveOutcome.committed(.applied)]
            + ComparisonDocumentPaneUpdateRejection.allCases.map {
                ComparisonDocumentSideSaveOutcome.committed(.rejected($0))
            }
        let operations = ComparisonDocumentSideSaveOperation.allCases.filter { $0 != .notAttempted }
        var saves: Set<SaveOracleKey> = [
            SaveOracleKey(
                execution: .notAttempted,
                leftOperation: .notAttempted,
                left: .notAttempted,
                rightOperation: .notAttempted,
                right: .notAttempted
            )
        ]
        for operation in operations {
            for outcome in outcomes {
                saves.insert(
                    SaveOracleKey(
                        execution: .single(.left),
                        leftOperation: operation,
                        left: outcome,
                        rightOperation: .notAttempted,
                        right: .notAttempted
                    )
                )
                saves.insert(
                    SaveOracleKey(
                        execution: .single(.right),
                        leftOperation: .notAttempted,
                        left: .notAttempted,
                        rightOperation: operation,
                        right: outcome
                    )
                )
            }
        }
        for leftOperation in operations {
            for rightOperation in operations {
                for left in outcomes {
                    for right in outcomes where batchOracleIsValid(left: left, right: right) {
                        saves.insert(
                            SaveOracleKey(
                                execution: .batch,
                                leftOperation: leftOperation,
                                left: left,
                                rightOperation: rightOperation,
                                right: right
                            )
                        )
                    }
                }
            }
        }
        return saves
    }

    private func expectedBackupOracleKeys(
        save: SaveOracleKey,
        incident: ComparisonDocumentIncident
    ) -> Set<BackupOracleKey> {
        func sideStates(_ side: ComparisonDocumentSide) -> [ComparisonDocumentSideBackupState] {
            let operation = save.operation(on: side)
            let outcome = save.outcome(on: side)
            switch operation {
            case .notAttempted, .saveAsNewFile:
                return [.notApplicable]
            case .saveInPlace, .saveAsReplacingFile:
                if outcome == .failed(.safetyContractUnavailable) {
                    return ComparisonDocumentBackupExecutionOutcome.allCases.map {
                        .required(trigger: .beforeSave, contract: .required, outcome: $0)
                    }
                }
                if operation == .saveInPlace, incident[side] == .missingDiskFile {
                    return [.required(trigger: .beforeSave, contract: .required, outcome: .notStarted)]
                }
                return [.required(trigger: .beforeSave, contract: .required, outcome: .completed)]
            }
        }
        return Set(
            sideStates(.left).flatMap { left in
                sideStates(.right).map { BackupOracleKey(left: left, right: $0) }
            }
        )
    }

    private func scenarioOracleIsValid(
        sourceShape: ComparisonDocumentSourceShape,
        dirtyState: ComparisonDocumentDirtyState,
        incident: ComparisonDocumentIncident,
        save: SaveOracleKey
    ) -> Bool {
        for side in ComparisonDocumentSide.allCases {
            let sourceKind = sourceShape.kind(on: side)
            let operation = save.operation(on: side)
            let outcome = save.outcome(on: side)
            if incident[side] != .none, sourceKind != .file { return false }
            if operation == .saveInPlace, sourceKind == .scratchpad { return false }
            if operation != .notAttempted, !dirtyState.contains(side) {
                guard save.execution == .single(side),
                    operation == .saveAsNewFile || operation == .saveAsReplacingFile
                else { return false }
            }
            if incident[side] != .none, operation == .saveInPlace,
                outcome != .failed(.destinationCompareFailed)
            {
                return false
            }
        }
        return true
    }

    private func batchOracleIsValid(
        left: ComparisonDocumentSideSaveOutcome,
        right: ComparisonDocumentSideSaveOutcome
    ) -> Bool {
        func isPreflightFailure(_ outcome: ComparisonDocumentSideSaveOutcome) -> Bool {
            switch outcome {
            case .failed(.cancelled), .failed(.sourceRevisionChanged),
                .failed(.destinationCompareFailed), .failed(.safetyContractUnavailable):
                return true
            case .notAttempted, .failed(.publicationFailedBeforeMutation), .uncertain, .committed:
                return false
            }
        }
        return !isPreflightFailure(left) && !isPreflightFailure(right)
            || isPreflightFailure(left) && isPreflightFailure(right)
    }

    private func expectedScenarioID(for key: ScenarioOracleKey) -> UInt32 {
        let sourceAndDirty = Int(key.sourceShape.rawValue) * 4 + Int(key.dirtyState.rawValue)
        let incidentRank = Int(key.incident.left.rawValue) * 4 + Int(key.incident.right.rawValue)
        let saveOffset = (sourceAndDirty * 16 + incidentRank) * 1_600 + saveOracleRank(key.save)
        let rawID = saveOffset * 64 + backupOracleRank(key.backup)
        return UInt32(rawID)
    }

    private func saveOracleRank(_ save: SaveOracleKey) -> Int {
        func sideRank(
            _ operation: ComparisonDocumentSideSaveOperation,
            _ outcome: ComparisonDocumentSideSaveOutcome
        ) -> Int {
            Int(operation.rawValue - 1) * 13 + outcomeOracleRank(outcome)
        }
        switch save.execution {
        case .notAttempted:
            return 0
        case .single(.left):
            return sideRank(save.leftOperation, save.left)
        case .single(.right):
            return 39 + sideRank(save.rightOperation, save.right)
        case .batch:
            return 78 + (sideRank(save.leftOperation, save.left) - 1) * 39
                + sideRank(save.rightOperation, save.right)
        }
    }

    private func outcomeOracleRank(_ outcome: ComparisonDocumentSideSaveOutcome) -> Int {
        switch outcome {
        case .notAttempted: 0
        case .failed(.cancelled): 1
        case .failed(.sourceRevisionChanged): 2
        case .failed(.destinationCompareFailed): 3
        case .failed(.safetyContractUnavailable): 4
        case .failed(.publicationFailedBeforeMutation): 5
        case .uncertain(.publicationStateUnknown): 6
        case .uncertain(.committedBytesUnverified): 7
        case .uncertain(.durabilityUnverified): 8
        case .uncertain(.recoveryStateUnknown): 9
        case .committed(.applied): 10
        case .committed(.rejected(.planAlreadyConsumed)): 11
        case .committed(.rejected(.ownerRevisionChanged)): 12
        case .committed(.rejected(.bindingChanged)): 13
        }
    }

    private func backupOracleRank(_ backup: BackupOracleKey) -> Int {
        func rank(_ state: ComparisonDocumentSideBackupState) -> Int {
            switch state {
            case .notApplicable: return 0
            case .required(_, _, let outcome): return 1 + Int(outcome.rawValue)
            }
        }
        return rank(backup.left) * 8 + rank(backup.right)
    }

    private func expectedStateOracle(
        for scenario: ComparisonDocumentScenario
    ) -> ExpectedStateOracle {
        func saveChangesSource(_ side: ComparisonDocumentSide) -> Bool {
            let operation = scenario.save.operation(on: side)
            switch scenario.save[side] {
            case .failed(.sourceRevisionChanged), .committed(.applied),
                .committed(.rejected(.bindingChanged)):
                return true
            case .uncertain, .committed(.rejected):
                return operation == .saveInPlace
            case .notAttempted, .failed:
                return false
            }
        }
        func pane(_ side: ComparisonDocumentSide) -> PaneStateOracle {
            let originalKind = scenario.sourceShape.kind(on: side)
            let operation = scenario.save.operation(on: side)
            let outcome = scenario.save[side]
            let applied = outcome == .committed(.applied)
            let sourceKind: ComparisonDocumentSourceKind = originalKind == .scratchpad && applied ? .file : originalKind
            let diskState: ComparisonDocumentDiskState
            if applied, operation == .saveAsNewFile || operation == .saveAsReplacingFile {
                diskState = .present
            } else {
                switch scenario.incident[side] {
                case .externalChange: diskState = .externallyChanged
                case .replacement: diskState = .replaced
                case .missingDiskFile: diskState = .missing
                case .none:
                    switch outcome {
                    case .committed(.applied): diskState = .present
                    case .uncertain where operation == .saveInPlace: diskState = .commitUncertain
                    case .notAttempted, .failed, .uncertain, .committed(.rejected):
                        diskState = originalKind == .file ? .present : .notApplicable
                    }
                }
            }
            return PaneStateOracle(
                sourceKind: sourceKind,
                diskState: diskState,
                isDirty: scenario.dirtyState.contains(side) && !applied
            )
        }
        var changedSides: [ComparisonDocumentSide] = []
        var reasons: [ComparisonLifecycleState.StaleReason] = []
        for side in ComparisonDocumentSide.allCases {
            if scenario.incident[side] != .none {
                changedSides.append(side)
                reasons.append(.externalChange(side.lifecycleSide))
            }
            if scenario.dirtyState.contains(side) || saveChangesSource(side) {
                if !changedSides.contains(side) { changedSides.append(side) }
                reasons.append(.sideChanged(side.lifecycleSide))
            }
        }
        return ExpectedStateOracle(
            lifecyclePhase: changedSides.isEmpty ? .current : .stale,
            staleReasons: reasons,
            left: pane(.left),
            right: pane(.right)
        )
    }

    private func scenarioInventorySHA256(_ scenarios: [ComparisonDocumentScenario]) -> String {
        var data = Data()
        for scenario in scenarios {
            let key = ScenarioOracleKey(scenario)
            var id = scenario.id.rawValue.bigEndian
            withUnsafeBytes(of: &id) { data.append(contentsOf: $0) }
            data.append(scenario.sourceShape.rawValue)
            data.append(scenario.dirtyState.rawValue)
            data.append(scenario.incident.left.rawValue)
            data.append(scenario.incident.right.rawValue)
            switch scenario.save.execution {
            case .notAttempted: data.append(0)
            case .single(.left): data.append(1)
            case .single(.right): data.append(2)
            case .batch: data.append(3)
            }
            data.append(scenario.save.leftOperation.rawValue)
            data.append(UInt8(outcomeOracleRank(scenario.save.left)))
            data.append(scenario.save.rightOperation.rawValue)
            data.append(UInt8(outcomeOracleRank(scenario.save.right)))
            data.append(UInt8(backupOracleRank(key.backup)))
        }
        return sha256(data).map { String(format: "%02x", $0) }.joined()
    }

    private struct BindingOptions {
        var keepsStaleInputsCurrent = false
        var operationComparisonIdentityChanged = false
        var operationComparisonRevisionChanged = false
        var operationInputsChanged = false
        var operationSourcesChanged = false
        var resultDoesNotFollowOperation = false
        var staleInputIdentityChanged = false
        var staleExpectedSourceDidNotAdvance = false
        var staleAdvancedSourceIdentityChanged = false
        var comparisonDoesNotFollowResult = false
        var keepsCurrentInputsStale = false
        var keepsCurrentSourcesStale = false
        var comparisonDoesNotCoverCurrentResult = false
        var changesCurrentSourceWithoutLifecycleChange = false
        var reusesOccupiedReplacementIdentity = false
        var saveAsCommittedPayloadAliasesOpenedFile = false
        var doesNotAdvancePublishedParent = false
        var omitsRequiredPaneUpdatePlanID = false
        var committedPayloadCorruption: PayloadCorruption?
        var addsPaneUpdateDataToNoncommit = false
        var backupPayloadAliasesSource = false
        var backupPayloadCorruption: PayloadCorruption?
        var backupUsesWrongOccupiedSource = false
        var backupDestinationStartsOccupied = false
        var backupOmitsPublishedState = false
        var attachesBackupEvidenceToNonCompletedOutcome = false
        var aliasesRightBackupSlotToLeft = false
        var backupSlotAliasesSaveDestination = false
        var rightBackupSlotAliasesLeftOpenedFile = false
        var saveAsNewStartsOccupied = false
        var saveAsNewAliasesOpenedLocation = false
        var invalidExpectedDestination = false
        var unexpectedPrepublicationChange = false
        var destinationCompareDidNotChange = false
        var invalidPostExecutionShape = false
        var usesTooTightSaveLimits = false
        var hasInvalidPlanID = false
        var usesWrongSourceFile = false
        var hasInvalidPathCounts = false
        var hasInvalidParentPathCount = false
        var hasInvalidLeafCount = false
        var hasInvalidPlannedOperationCount = false
        var hasInvalidTotalPathCount = false
        var hasInvalidEstimatedWork = false
        var sourceDocumentExceedsEncodedLimit = false
        var sourceDocumentExceedsMetadataLimit = false
        var corruptsPaneUpdateDocument = false
        var corruptsPaneUpdateSource = false
        var omitsPaneUpdateDocument = false
        var omitsPaneUpdateSource = false
        var changesPaneUpdatePlanID = false
        var flipsPaneUpdateConsumption = false
        var changesRightBatchPlanID = false
        var changesRightBatchTotalPath = false
        var rightOpenedFileAliasesLeft = false
    }

    private struct SignedFixture {
        let inventory: ComparisonDocumentCoverageInventory
        let evidence: ComparisonDocumentEvidenceBundle
        let policy: ComparisonDocumentAuditPolicy
        let captures: [[UInt8]: Data]
        let replays: ReplayRecorder
        let auditTime: UInt64
        let maximumCaptureByteCount: Int
        let collectorReference: ComparisonDocumentRevisionReference
        let locationKey: ComparisonDocumentStableID
    }

    private struct SignedObservation {
        let observation: ComparisonDocumentProductionObservation
        let capture: Data
        let captureSHA256: [UInt8]
    }

    private struct OperationResult: Hashable {
        let operation: UUID
        let result: ComparisonDocumentRevisionReference

        init(_ binding: ComparisonDocumentComparisonRevisionBinding) {
            operation = binding.operation.operationID
            result = binding.result
        }
    }

    private struct ArchiveSections {
        let magic: Data
        let version: UInt64
        let inventorySHA256: [UInt8]
        let evidenceSHA256: [UInt8]
        let reportSHA256: [UInt8]
        let inventory: Data
        let evidence: Data
        let report: Data
        let trailingSHA256: [UInt8]
    }

    private func makeSignedFixture() throws -> SignedFixture {
        let scenarios = Matrix.canonicalScenarios
        let build = reference("document-build", 17)
        let inventoryReference = reference("document-inventory", 19)
        let evidenceReference = reference("document-evidence", 23)
        let collectorReference = reference("document-collector", 29)
        let replayReference = reference("document-replay-policy", 31)
        let artifact = digest(UInt64(0xA1))
        let locationKey = ComparisonDocumentStableID(rawValue: "document-location-key")
        let signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(repeating: 0x5A, count: 32)
        )
        let collector = ComparisonDocumentTrustedCollector(
            reference: collectorReference,
            ed25519PublicKey: Array(signingKey.publicKey.rawRepresentation)
        )
        var bindingsByScenario: [ComparisonDocumentScenarioID: ComparisonDocumentRevisionBindings] = [:]
        bindingsByScenario.reserveCapacity(scenarios.count)
        for (index, scenario) in scenarios.enumerated() {
            bindingsByScenario[scenario.id] = try makeBindings(
                for: scenario,
                seed: UInt64(index + 1),
                locationKey: locationKey
            )
        }
        let inventory = try ComparisonDocumentCoverageInventory.canonical(
            reference: inventoryReference,
            build: build,
            buildArtifactSHA256: artifact,
            bindingsByScenario: bindingsByScenario
        )

        let auditTime: UInt64 = 1_900_000_000_000
        var observations: [ComparisonDocumentProductionObservation] = []
        observations.reserveCapacity(scenarios.count)
        var captures: [[UInt8]: Data] = [:]
        captures.reserveCapacity(scenarios.count)
        var maximumCaptureByteCount = 0
        for (index, requirement) in inventory.requirements.enumerated() {
            let run = reference("document-run-\(index)", 1)
            let nonce = replayNonce(index)
            var unsignedProvenance = ComparisonDocumentEvidenceProvenance(
                build: build,
                inventory: inventoryReference,
                evidence: evidenceReference,
                collector: collectorReference,
                run: run,
                capturedAtUnixMilliseconds: auditTime,
                runNonce: nonce,
                artifactSHA256: artifact,
                captureSHA256: digest(0xC1),
                captureByteCount: 1,
                collectorSignature: [UInt8](repeating: 0xD1, count: 64),
                source: .automatedHarness
            )
            var unsigned = productionObservation(requirement, provenance: unsignedProvenance)
            let provisionalCapture = try Matrix.canonicalCaptureData(
                for: unsigned,
                cancellationCheck: { false }
            )
            unsignedProvenance = ComparisonDocumentEvidenceProvenance(
                build: build,
                inventory: inventoryReference,
                evidence: evidenceReference,
                collector: collectorReference,
                run: run,
                capturedAtUnixMilliseconds: auditTime,
                runNonce: nonce,
                artifactSHA256: artifact,
                captureSHA256: digest(UInt64(0xC1)),
                captureByteCount: provisionalCapture.count,
                collectorSignature: [UInt8](repeating: 0xD1, count: 64),
                source: .automatedHarness
            )
            unsigned = productionObservation(requirement, provenance: unsignedProvenance)
            let capture = try Matrix.canonicalCaptureData(for: unsigned, cancellationCheck: { false })
            let captureSHA256 = sha256(capture)
            let signature = try signingKey.signature(for: capture)
            let provenance = ComparisonDocumentEvidenceProvenance(
                build: build,
                inventory: inventoryReference,
                evidence: evidenceReference,
                collector: collectorReference,
                run: run,
                capturedAtUnixMilliseconds: auditTime,
                runNonce: nonce,
                artifactSHA256: artifact,
                captureSHA256: captureSHA256,
                captureByteCount: capture.count,
                collectorSignature: Array(signature),
                source: .automatedHarness
            )
            let observation = productionObservation(requirement, provenance: provenance)
            if index == 0 {
                XCTAssertEqual(
                    try Matrix.canonicalCaptureData(for: observation, cancellationCheck: { false }),
                    capture
                )
            }
            captures[captureSHA256] = capture
            maximumCaptureByteCount = max(maximumCaptureByteCount, capture.count)
            observations.append(observation)
        }
        let evidence = ComparisonDocumentEvidenceBundle(
            reference: evidenceReference,
            inventory: inventoryReference,
            build: build,
            observations: observations
        )
        let replays = ReplayRecorder()
        let policy = ComparisonDocumentAuditPolicy(
            trustedCollectors: [collector],
            trustedLocationKeyReferences: [locationKey],
            trustedAuditTimeUnixMilliseconds: auditTime,
            maximumCaptureAgeMilliseconds: 1,
            maximumFutureClockSkewMilliseconds: 1,
            replayClaimDeadlineUnixMilliseconds: auditTime + 10_000,
            replayPolicy: replayReference,
            claimReplayNonces: replays.claim
        )
        return SignedFixture(
            inventory: inventory,
            evidence: evidence,
            policy: policy,
            captures: captures,
            replays: replays,
            auditTime: auditTime,
            maximumCaptureByteCount: maximumCaptureByteCount,
            collectorReference: collectorReference,
            locationKey: locationKey
        )
    }

    private func auditPolicy(
        fixture: SignedFixture,
        replays: ReplayRecorder
    ) -> ComparisonDocumentAuditPolicy {
        policy(fixture, replays: replays)
    }

    private func policy(
        _ fixture: SignedFixture,
        collectors: [ComparisonDocumentTrustedCollector]? = nil,
        locationKeys: Set<ComparisonDocumentStableID>? = nil,
        auditTime: UInt64? = nil,
        maximumCaptureAge: UInt64? = nil,
        maximumFutureClockSkew: UInt64? = nil,
        replayDeadline: UInt64? = nil,
        replayPolicy: ComparisonDocumentRevisionReference? = nil,
        replays: ReplayRecorder? = nil
    ) -> ComparisonDocumentAuditPolicy {
        ComparisonDocumentAuditPolicy(
            trustedCollectors: collectors ?? fixture.policy.trustedCollectors,
            trustedLocationKeyReferences: locationKeys
                ?? fixture.policy.trustedLocationKeyReferences,
            trustedAuditTimeUnixMilliseconds: auditTime
                ?? fixture.policy.trustedAuditTimeUnixMilliseconds,
            maximumCaptureAgeMilliseconds: maximumCaptureAge
                ?? fixture.policy.maximumCaptureAgeMilliseconds,
            maximumFutureClockSkewMilliseconds: maximumFutureClockSkew
                ?? fixture.policy.maximumFutureClockSkewMilliseconds,
            replayClaimDeadlineUnixMilliseconds: replayDeadline
                ?? fixture.policy.replayClaimDeadlineUnixMilliseconds,
            replayPolicy: replayPolicy ?? fixture.policy.replayPolicy,
            claimReplayNonces: (replays ?? fixture.replays).claim
        )
    }

    private func replacing(
        _ observation: ComparisonDocumentProductionObservation,
        bindings: ComparisonDocumentRevisionBindings? = nil,
        origin: ComparisonDocumentEvidenceOrigin? = nil,
        provenance: ComparisonDocumentEvidenceProvenance?
    ) -> ComparisonDocumentProductionObservation {
        ComparisonDocumentProductionObservation(
            scenarioID: observation.scenarioID,
            bindings: bindings ?? observation.bindings,
            lifecycle: observation.lifecycle,
            left: observation.left,
            right: observation.right,
            save: observation.save,
            saveExecutorContract: observation.saveExecutorContract,
            backup: observation.backup,
            origin: origin ?? observation.origin,
            provenance: provenance
        )
    }

    private func replacingComparison(
        _ bindings: ComparisonDocumentRevisionBindings,
        openRequest: ComparisonOpenRequestIdentity? = nil,
        comparison: ComparisonDocumentRevisionReference? = nil,
        operation: ComparisonDocumentLifecycleOperationBinding? = nil,
        inputs: ComparisonDocumentRevisionReference? = nil,
        result: ComparisonDocumentRevisionReference? = nil,
        resultInputs: ComparisonDocumentRevisionReference? = nil
    ) throws -> ComparisonDocumentRevisionBindings {
        let value = bindings.comparison
        let replacement = try ComparisonDocumentComparisonRevisionBinding(
            openRequest: openRequest ?? value.openRequest,
            comparison: comparison ?? value.comparison,
            operation: operation ?? value.operation,
            inputs: inputs ?? value.inputs,
            result: result ?? value.result,
            resultInputs: resultInputs ?? value.resultInputs,
            sources: value.sources,
            resultSources: value.resultSources
        )
        return try ComparisonDocumentRevisionBindings(
            comparison: replacement,
            sides: bindings.sides
        )
    }

    private func replacingSaveOperation(
        _ bindings: ComparisonDocumentRevisionBindings,
        side: ComparisonDocumentSide,
        planID: UUID
    ) throws -> ComparisonDocumentRevisionBindings {
        var sides = bindings.sides
        let binding = sides[Int(side.rawValue)]
        let operation = try XCTUnwrap(binding.saveOperation)
        let replacement = ComparisonDocumentSaveOperationBinding(
            planID: planID,
            sourceDocument: operation.sourceDocument,
            sourceFile: operation.sourceFile,
            limits: operation.limits,
            destinationPathUTF8ByteCount: operation.destinationPathUTF8ByteCount,
            parentPathUTF8ByteCount: operation.parentPathUTF8ByteCount,
            canonicalLeafIdentityUTF8ByteCount: operation.canonicalLeafIdentityUTF8ByteCount,
            plannedOperationCount: operation.plannedOperationCount,
            totalPathUTF8ByteCount: operation.totalPathUTF8ByteCount,
            estimatedWorkUnits: operation.estimatedWorkUnits,
            committedPayload: operation.committedPayload,
            paneUpdateObservedDocument: operation.paneUpdateObservedDocument,
            paneUpdateObservedSource: operation.paneUpdateObservedSource,
            paneUpdateObservedPlanID: planID,
            planWasConsumedBeforePaneUpdate: operation.planWasConsumedBeforePaneUpdate
        )
        sides[Int(side.rawValue)] = ComparisonDocumentSideRevisionBinding(
            side: binding.side,
            document: binding.document,
            resultDocument: binding.resultDocument,
            lifecycleSource: binding.lifecycleSource,
            resultLifecycleSource: binding.resultLifecycleSource,
            openedSource: binding.openedSource,
            saveOperation: replacement,
            saveDestination: binding.saveDestination,
            completedBackup: binding.completedBackup,
            incidentSource: binding.incidentSource,
            currentSource: binding.currentSource,
            resultSource: binding.resultSource
        )
        return try ComparisonDocumentRevisionBindings(
            comparison: bindings.comparison,
            sides: sides
        )
    }

    private func replacingSide(
        _ bindings: ComparisonDocumentRevisionBindings,
        side: ComparisonDocumentSide,
        document: ComparisonDocumentContentRevision? = nil,
        lifecycleSource: ComparisonDocumentRevisionReference? = nil,
        openedSource: ComparisonDocumentSourceRevision? = nil,
        saveDestination: ComparisonDocumentSaveDestinationBinding? = nil
    ) throws -> ComparisonDocumentRevisionBindings {
        var sides = bindings.sides
        let binding = sides[Int(side.rawValue)]
        sides[Int(side.rawValue)] = ComparisonDocumentSideRevisionBinding(
            side: binding.side,
            document: document ?? binding.document,
            resultDocument: binding.resultDocument,
            lifecycleSource: lifecycleSource ?? binding.lifecycleSource,
            resultLifecycleSource: binding.resultLifecycleSource,
            openedSource: openedSource ?? binding.openedSource,
            saveOperation: binding.saveOperation,
            saveDestination: saveDestination ?? binding.saveDestination,
            completedBackup: binding.completedBackup,
            incidentSource: binding.incidentSource,
            currentSource: binding.currentSource,
            resultSource: binding.resultSource
        )
        var sources = bindings.comparison.sources
        if let lifecycleSource {
            sources[Int(side.rawValue)] = ComparisonDocumentLifecycleSourceBinding(
                side: side,
                source: lifecycleSource
            )
        }
        let comparison = try ComparisonDocumentComparisonRevisionBinding(
            openRequest: bindings.comparison.openRequest,
            comparison: bindings.comparison.comparison,
            operation: bindings.comparison.operation,
            inputs: bindings.comparison.inputs,
            result: bindings.comparison.result,
            resultInputs: bindings.comparison.resultInputs,
            sources: sources,
            resultSources: bindings.comparison.resultSources
        )
        return try ComparisonDocumentRevisionBindings(
            comparison: comparison,
            sides: sides
        )
    }

    private func provenance(
        _ value: ComparisonDocumentEvidenceProvenance,
        build: ComparisonDocumentRevisionReference? = nil,
        inventory: ComparisonDocumentRevisionReference? = nil,
        evidence: ComparisonDocumentRevisionReference? = nil,
        collector: ComparisonDocumentRevisionReference? = nil,
        run: ComparisonDocumentRevisionReference? = nil,
        capturedAt: UInt64? = nil,
        runNonce: [UInt8]? = nil,
        artifactSHA256: [UInt8]? = nil,
        captureSHA256: [UInt8]? = nil,
        captureByteCount: Int? = nil,
        collectorSignature: [UInt8]? = nil,
        source: ComparisonDocumentProvenanceSource? = nil
    ) -> ComparisonDocumentEvidenceProvenance {
        ComparisonDocumentEvidenceProvenance(
            build: build ?? value.build,
            inventory: inventory ?? value.inventory,
            evidence: evidence ?? value.evidence,
            collector: collector ?? value.collector,
            run: run ?? value.run,
            capturedAtUnixMilliseconds: capturedAt ?? value.capturedAtUnixMilliseconds,
            runNonce: runNonce ?? value.runNonce,
            artifactSHA256: artifactSHA256 ?? value.artifactSHA256,
            captureSHA256: captureSHA256 ?? value.captureSHA256,
            captureByteCount: captureByteCount ?? value.captureByteCount,
            collectorSignature: collectorSignature ?? value.collectorSignature,
            source: source ?? value.source
        )
    }

    private func resign(
        _ observation: ComparisonDocumentProductionObservation,
        fixture: SignedFixture
    ) throws -> SignedObservation {
        let original = try XCTUnwrap(observation.provenance)
        let signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(repeating: 0x5A, count: 32)
        )
        var unsignedProvenance = ComparisonDocumentEvidenceProvenance(
            build: original.build,
            inventory: original.inventory,
            evidence: original.evidence,
            collector: original.collector,
            run: original.run,
            capturedAtUnixMilliseconds: original.capturedAtUnixMilliseconds,
            runNonce: original.runNonce,
            artifactSHA256: original.artifactSHA256,
            captureSHA256: digest(0xC1),
            captureByteCount: 1,
            collectorSignature: [UInt8](repeating: 0xD1, count: 64),
            source: original.source
        )
        var unsigned = replacing(observation, provenance: unsignedProvenance)
        let provisional = try Matrix.canonicalCaptureData(for: unsigned, cancellationCheck: { false })
        unsignedProvenance = ComparisonDocumentEvidenceProvenance(
            build: original.build,
            inventory: original.inventory,
            evidence: original.evidence,
            collector: original.collector,
            run: original.run,
            capturedAtUnixMilliseconds: original.capturedAtUnixMilliseconds,
            runNonce: original.runNonce,
            artifactSHA256: original.artifactSHA256,
            captureSHA256: digest(0xC1),
            captureByteCount: provisional.count,
            collectorSignature: [UInt8](repeating: 0xD1, count: 64),
            source: original.source
        )
        unsigned = replacing(observation, provenance: unsignedProvenance)
        let capture = try Matrix.canonicalCaptureData(for: unsigned, cancellationCheck: { false })
        let captureSHA256 = sha256(capture)
        let signature = try signingKey.signature(for: capture)
        let signed = ComparisonDocumentEvidenceProvenance(
            build: original.build,
            inventory: original.inventory,
            evidence: original.evidence,
            collector: original.collector,
            run: original.run,
            capturedAtUnixMilliseconds: original.capturedAtUnixMilliseconds,
            runNonce: original.runNonce,
            artifactSHA256: original.artifactSHA256,
            captureSHA256: captureSHA256,
            captureByteCount: capture.count,
            collectorSignature: Array(signature),
            source: original.source
        )
        return SignedObservation(
            observation: replacing(observation, provenance: signed),
            capture: capture,
            captureSHA256: captureSHA256
        )
    }

    private func productionObservation(
        _ requirement: ComparisonDocumentCoverageRequirement,
        provenance: ComparisonDocumentEvidenceProvenance
    ) -> ComparisonDocumentProductionObservation {
        ComparisonDocumentProductionObservation(
            scenarioID: requirement.id,
            bindings: requirement.bindings,
            lifecycle: ComparisonDocumentLifecycleObservation(
                phase: requirement.expected.lifecyclePhase,
                hasCurrentResult: requirement.expected.lifecyclePhase == .current,
                hasRetainedResult: requirement.expected.hasRetainedComparisonResult,
                staleReason: requirement.expected.permittedStaleReasons.first
            ),
            left: paneObservation(requirement.expected.left),
            right: paneObservation(requirement.expected.right),
            save: requirement.expected.save,
            saveExecutorContract: requirement.expected.saveExecutorContract,
            backup: requirement.expected.backup,
            origin: .productionAutomation,
            provenance: provenance
        )
    }

    private func assertion(
        _ scenario: ComparisonDocumentScenario,
        _ bindings: ComparisonDocumentRevisionBindings
    ) -> ComparisonDocumentProductionObservation {
        let expected = ComparisonDocumentCoverageInventoryRequirementProjection(scenario)
        return ComparisonDocumentProductionObservation(
            scenarioID: scenario.id,
            bindings: bindings,
            lifecycle: ComparisonDocumentLifecycleObservation(
                phase: scenario.expectedLifecyclePhase,
                hasCurrentResult: scenario.expectedLifecyclePhase == .current,
                hasRetainedResult: true,
                staleReason: scenario.expectedStaleReasons.first
            ),
            left: expected.left,
            right: expected.right,
            save: scenario.save,
            saveExecutorContract: scenario.save.execution == .notAttempted ? nil : .required,
            backup: scenario.backup,
            origin: .callerAssertion,
            provenance: nil
        )
    }

    private struct ComparisonDocumentCoverageInventoryRequirementProjection {
        let left: ComparisonDocumentPaneObservation
        let right: ComparisonDocumentPaneObservation

        init(_ scenario: ComparisonDocumentScenario) {
            left = Self.pane(scenario, .left)
            right = Self.pane(scenario, .right)
        }

        private static func pane(
            _ scenario: ComparisonDocumentScenario,
            _ side: ComparisonDocumentSide
        ) -> ComparisonDocumentPaneObservation {
            let sourceKind = scenario.expectedSourceKind(on: side)
            return ComparisonDocumentPaneObservation(
                sourceKind: sourceKind,
                isLoaded: true,
                isEditable: true,
                isDirty: scenario.isDirty(side),
                isUntitled: sourceKind == .scratchpad,
                diskState: scenario.expectedDiskState(on: side)
            )
        }
    }

    private func paneObservation(
        _ pane: ComparisonDocumentExpectedPaneState
    ) -> ComparisonDocumentPaneObservation {
        ComparisonDocumentPaneObservation(
            sourceKind: pane.sourceKind,
            isLoaded: pane.isLoaded,
            isEditable: pane.isEditable,
            isDirty: pane.isDirty,
            isUntitled: pane.isUntitled,
            diskState: pane.diskState
        )
    }

    private func pane(
        _ value: ComparisonDocumentPaneObservation,
        sourceKind: ComparisonDocumentSourceKind? = nil,
        isDirty: Bool? = nil,
        diskState: ComparisonDocumentDiskState? = nil
    ) -> ComparisonDocumentPaneObservation {
        ComparisonDocumentPaneObservation(
            sourceKind: sourceKind ?? value.sourceKind,
            isLoaded: value.isLoaded,
            isEditable: value.isEditable,
            isDirty: isDirty ?? value.isDirty,
            isUntitled: sourceKind.map { $0 == .scratchpad } ?? value.isUntitled,
            diskState: diskState ?? value.diskState
        )
    }

    private func makeBindings(
        for scenario: ComparisonDocumentScenario,
        seed: UInt64,
        locationKey: ComparisonDocumentStableID = ComparisonDocumentStableID(rawValue: "test-location-key"),
        options: BindingOptions = BindingOptions()
    ) throws -> ComparisonDocumentRevisionBindings {
        let resultInput = reference("inputs-\(seed)", 1)
        let changedSides = ComparisonDocumentSide.allCases.filter {
            scenario.expectedStaleReasons.contains(.sideChanged($0.lifecycleSide))
                || scenario.expectedStaleReasons.contains(.externalChange($0.lifecycleSide))
        }
        let isStale = scenario.expectedLifecyclePhase == .stale
        let currentInput: ComparisonDocumentRevisionReference
        if isStale, options.staleInputIdentityChanged {
            currentInput = reference("changed-inputs-\(seed)", 2)
        } else {
            currentInput = reference(
                "inputs-\(seed)",
                isStale && !options.keepsStaleInputsCurrent || options.keepsCurrentInputsStale ? 2 : 1
            )
        }
        let comparisonID = ComparisonDocumentStableID(rawValue: "comparison-\(seed)")
        let resultSources = ComparisonDocumentSide.allCases.map { side in
            ComparisonDocumentLifecycleSourceBinding(
                side: side,
                source: reference("lifecycle-\(seed)-\(side.rawValue)", 1)
            )
        }
        let currentSources = ComparisonDocumentSide.allCases.map { side in
            let expectedChanged = changedSides.contains(side)
            let revision: UInt64 =
                expectedChanged && !options.staleExpectedSourceDidNotAdvance
                    || options.keepsCurrentSourcesStale ? 2 : 1
            let identity =
                expectedChanged && options.staleAdvancedSourceIdentityChanged
                ? "changed-lifecycle-\(seed)-\(side.rawValue)"
                : "lifecycle-\(seed)-\(side.rawValue)"
            return ComparisonDocumentLifecycleSourceBinding(
                side: side,
                source: reference(identity, revision)
            )
        }
        let operation = try ComparisonDocumentLifecycleOperationBinding(
            comparison: ComparisonDocumentRevisionReference(
                id: options.operationComparisonIdentityChanged
                    ? ComparisonDocumentStableID(rawValue: "changed-comparison-\(seed)") : comparisonID,
                revision: options.operationComparisonRevisionChanged ? 2 : 1
            ),
            operationID: uuid(seed * 1_000 + 1),
            startedAtGeneration: 1,
            inputs: options.operationInputsChanged ? reference("changed-operation-inputs-\(seed)", 1) : resultInput,
            sources: options.operationSourcesChanged ? currentSources : resultSources
        )
        let comparison = try ComparisonDocumentComparisonRevisionBinding(
            openRequest: ComparisonOpenRequestIdentity(rawValue: uuid(seed * 1_000 + 2)),
            comparison: ComparisonDocumentRevisionReference(
                id: comparisonID,
                revision: options.comparisonDoesNotFollowResult
                    ? 2
                    : (options.comparisonDoesNotCoverCurrentResult ? 1 : (isStale ? 3 : 2))
            ),
            operation: operation,
            inputs: currentInput,
            result: reference("result-\(seed)", options.resultDoesNotFollowOperation ? 1 : 2),
            resultInputs: resultInput,
            sources: currentSources,
            resultSources: resultSources
        )
        let planID = uuid(seed * 1_000 + 3)
        let leftAliasIdentity =
            options.rightOpenedFileAliasesLeft
            ? fileIdentity(seed: seed, role: 10, location: location(seed, 10, locationKey)) : nil
        let sides = try ComparisonDocumentSide.allCases.map { side in
            try makeSideBinding(
                scenario: scenario,
                side: side,
                seed: seed,
                locationKey: locationKey,
                planID: planID,
                resultLifecycle: resultSources[Int(side.rawValue)].source,
                currentLifecycle: currentSources[Int(side.rawValue)].source,
                forcedOpenedIdentity: side == .right ? leftAliasIdentity : nil,
                options: options
            )
        }
        return try ComparisonDocumentRevisionBindings(comparison: comparison, sides: sides)
    }

    private func makeSideBinding(
        scenario: ComparisonDocumentScenario,
        side: ComparisonDocumentSide,
        seed: UInt64,
        locationKey: ComparisonDocumentStableID,
        planID: UUID,
        resultLifecycle: ComparisonDocumentRevisionReference,
        currentLifecycle: ComparisonDocumentRevisionReference,
        forcedOpenedIdentity: ComparisonDocumentFileIdentity?,
        options: BindingOptions
    ) throws -> ComparisonDocumentSideRevisionBinding {
        let sideOffset = UInt64(side.rawValue) * 100
        let documentID = uuid(seed * 1_000 + 10 + sideOffset)
        let resultDocument = contentRevision(
            identity: documentID,
            generation: 1,
            payload: seed * 1_000 + 10 + sideOffset
        )
        let document =
            scenario.dirtyState.contains(side)
            ? contentRevision(
                identity: documentID,
                generation: 2,
                payload: seed * 1_000 + 20 + sideOffset
            ) : resultDocument
        let openedLocation = location(seed, 10 + sideOffset, locationKey)
        let openedSource: ComparisonDocumentSourceRevision
        switch scenario.sourceKind(on: side) {
        case .file:
            let identity =
                forcedOpenedIdentity
                ?? fileIdentity(seed: seed, role: 10 + sideOffset, location: openedLocation)
            openedSource = .file(fileRevision(identity: identity, revision: 1, content: resultDocument))
        case .scratchpad:
            openedSource = .scratchpad(scratchpadRevision(from: resultDocument))
        }
        let incidentSource = makeIncidentSource(
            scenario.incident[side],
            opened: openedSource,
            seed: seed,
            sideOffset: sideOffset
        )
        let operation = scenario.save.operation(on: side)
        let outcome = scenario.save[side]
        let sourceDocument: ComparisonDocumentContentRevision
        switch outcome {
        case .failed(.sourceRevisionChanged), .committed(.rejected(.ownerRevisionChanged)):
            sourceDocument = contentRevision(
                identity: document.identity,
                generation: document.generation - 1,
                payload: document.generation == 1
                    ? seed * 1_000 + 10 + sideOffset
                    : seed * 1_000 + 10 + sideOffset
            )
        case .notAttempted, .failed, .uncertain, .committed:
            sourceDocument = document
        }
        let destinationLocation =
            options.saveAsNewAliasesOpenedLocation && operation == .saveAsNewFile
            ? openedLocation
            : operation == .saveInPlace
                ? openedLocation : location(seed, 30 + sideOffset, locationKey)
        let expectedTarget: ComparisonDocumentFileRevision?
        switch operation {
        case .notAttempted:
            expectedTarget = nil
        case .saveAsNewFile:
            expectedTarget =
                options.saveAsNewStartsOccupied
                ? fileRevision(
                    identity: fileIdentity(
                        seed: seed,
                        role: 31 + sideOffset,
                        location: destinationLocation
                    ),
                    revision: 1,
                    content: contentRevision(
                        identity: uuid(seed * 1_000 + 30 + sideOffset),
                        generation: 1,
                        payload: seed * 1_000 + 30 + sideOffset
                    )
                ) : nil
        case .saveInPlace:
            expectedTarget = file(from: openedSource)
        case .saveAsReplacingFile:
            expectedTarget = fileRevision(
                identity: fileIdentity(
                    seed: seed,
                    role: 31 + sideOffset,
                    location: destinationLocation
                ),
                revision: 1,
                content: contentRevision(
                    identity: uuid(seed * 1_000 + 30 + sideOffset),
                    generation: 1,
                    payload: seed * 1_000 + 30 + sideOffset
                )
            )
        }
        let committedPayload = makeCommittedPayload(
            operation: operation,
            sourceDocument: sourceDocument,
            openedSource: openedSource,
            expectedTarget: expectedTarget,
            destinationLocation: destinationLocation,
            seed: seed,
            sideOffset: sideOffset,
            options: options
        )
        let destination = try makeDestination(
            operation: operation,
            outcome: outcome,
            expectedTarget: expectedTarget,
            incidentSource: incidentSource,
            committedPayload: committedPayload,
            destinationLocation: destinationLocation,
            seed: seed,
            sideOffset: sideOffset,
            locationKey: locationKey,
            options: options
        )
        let rebinding = paneRebinding(
            openedSource,
            sourceDocument: sourceDocument,
            seed: seed,
            sideOffset: sideOffset
        )
        let saveOperation = makeSaveOperation(
            scenario: scenario,
            side: side,
            planID: planID,
            sourceDocument: sourceDocument,
            currentDocument: document,
            openedSource: openedSource,
            committedPayload: committedPayload,
            rebinding: rebinding,
            options: options
        )
        let currentSource = makeCurrentSource(
            operation: operation,
            outcome: outcome,
            openedSource: openedSource,
            committedPayload: committedPayload,
            rebinding: rebinding
        )
        let observedCurrentSource =
            options.changesCurrentSourceWithoutLifecycleChange
            ? rebinding : currentSource
        let completedBackup = try makeBackup(
            scenario: scenario,
            side: side,
            saveDestination: destination,
            seed: seed,
            sideOffset: sideOffset,
            locationKey: locationKey,
            options: options
        )
        return ComparisonDocumentSideRevisionBinding(
            side: side,
            document: document,
            resultDocument: resultDocument,
            lifecycleSource: currentLifecycle,
            resultLifecycleSource: resultLifecycle,
            openedSource: openedSource,
            saveOperation: saveOperation,
            saveDestination: destination,
            completedBackup: completedBackup,
            incidentSource: incidentSource,
            currentSource: observedCurrentSource,
            resultSource: openedSource
        )
    }

    private func makeIncidentSource(
        _ incident: ComparisonDocumentSideIncident,
        opened: ComparisonDocumentSourceRevision,
        seed: UInt64,
        sideOffset: UInt64
    ) -> ComparisonDocumentSourceRevision? {
        switch incident {
        case .none:
            opened
        case .externalChange:
            file(from: opened).map {
                .file(
                    fileRevision(
                        identity: $0.identity,
                        revision: $0.revision + 1,
                        content: contentRevision(
                            identity: uuid(seed * 1_000 + 40 + sideOffset),
                            generation: 1,
                            payload: seed * 1_000 + 40 + sideOffset
                        )
                    )
                )
            }
        case .replacement:
            file(from: opened).map {
                .file(
                    fileRevision(
                        identity: fileIdentity(
                            seed: seed,
                            role: 41 + sideOffset,
                            location: $0.identity.location
                        ),
                        revision: 1,
                        content: contentRevision(
                            identity: uuid(seed * 1_000 + 41 + sideOffset),
                            generation: 1,
                            payload: seed * 1_000 + 41 + sideOffset
                        )
                    )
                )
            }
        case .missingDiskFile:
            nil
        }
    }

    private func makeCommittedPayload(
        operation: ComparisonDocumentSideSaveOperation,
        sourceDocument: ComparisonDocumentContentRevision,
        openedSource: ComparisonDocumentSourceRevision,
        expectedTarget: ComparisonDocumentFileRevision?,
        destinationLocation: ComparisonDocumentLocationIdentity,
        seed: UInt64,
        sideOffset: UInt64,
        options: BindingOptions
    ) -> ComparisonDocumentFileRevision? {
        guard operation != .notAttempted else { return nil }
        let identity: ComparisonDocumentFileIdentity
        if options.reusesOccupiedReplacementIdentity, operation == .saveAsReplacingFile,
            let expectedTarget
        {
            identity = expectedTarget.identity
        } else if options.saveAsCommittedPayloadAliasesOpenedFile, operation != .saveInPlace,
            let opened = file(from: openedSource)
        {
            identity = ComparisonDocumentFileIdentity(
                volumeID: opened.identity.volumeID,
                fileID: opened.identity.fileID,
                generation: opened.identity.generation,
                location: destinationLocation
            )
        } else if operation == .saveInPlace, let opened = file(from: openedSource) {
            identity = opened.identity
        } else {
            identity = fileIdentity(
                seed: seed,
                role: 50 + sideOffset,
                location: destinationLocation
            )
        }
        return corrupt(
            fileRevision(identity: identity, revision: 10, content: sourceDocument),
            options.committedPayloadCorruption
        )
    }

    private func makeDestination(
        operation: ComparisonDocumentSideSaveOperation,
        outcome: ComparisonDocumentSideSaveOutcome,
        expectedTarget: ComparisonDocumentFileRevision?,
        incidentSource: ComparisonDocumentSourceRevision?,
        committedPayload: ComparisonDocumentFileRevision?,
        destinationLocation: ComparisonDocumentLocationIdentity,
        seed: UInt64,
        sideOffset: UInt64,
        locationKey: ComparisonDocumentStableID,
        options: BindingOptions
    ) throws -> ComparisonDocumentSaveDestinationBinding {
        guard operation != .notAttempted else { return .notApplicable }
        let parentIdentity = fileIdentity(
            seed: seed,
            role: 60 + sideOffset,
            location: location(seed, 60 + sideOffset, locationKey)
        )
        let expected = destinationSnapshot(
            parentIdentity: parentIdentity,
            parentRevision: 1,
            slotLocation: destinationLocation,
            slotRevision: 1,
            target: expectedTarget,
            seed: seed * 1_000 + 60 + sideOffset
        )
        var observed = expected
        if case .failed(.destinationCompareFailed) = outcome {
            let target: ComparisonDocumentFileRevision?
            if operation == .saveInPlace {
                target = file(from: incidentSource)
            } else if expectedTarget != nil {
                target = fileRevision(
                    identity: fileIdentity(
                        seed: seed,
                        role: 61 + sideOffset,
                        location: destinationLocation
                    ),
                    revision: 2,
                    content: contentRevision(
                        identity: uuid(seed * 1_000 + 61 + sideOffset),
                        generation: 1,
                        payload: seed * 1_000 + 61 + sideOffset
                    )
                )
            } else {
                target = expectedTarget
            }
            observed = destinationSnapshot(
                parentIdentity: parentIdentity,
                parentRevision: 2,
                slotLocation: destinationLocation,
                slotRevision: 2,
                target: target,
                seed: seed * 1_000 + 61 + sideOffset
            )
        }
        if options.destinationCompareDidNotChange { observed = expected }
        if options.unexpectedPrepublicationChange {
            observed = destinationSnapshot(
                parentIdentity: parentIdentity,
                parentRevision: 2,
                slotLocation: destinationLocation,
                slotRevision: 2,
                target: expectedTarget,
                seed: seed * 1_000 + 63 + sideOffset
            )
        }
        let invalidExpected =
            options.invalidExpectedDestination
            ? destinationSnapshot(
                parentIdentity: parentIdentity,
                parentRevision: 1,
                slotLocation: location(seed, 64 + sideOffset, locationKey),
                slotRevision: 1,
                target: expectedTarget,
                seed: seed * 1_000 + 64 + sideOffset
            )
            : expected
        let after: ComparisonDocumentSaveDestinationSnapshot?
        switch outcome {
        case .failed:
            after = observed
        case .uncertain:
            after = options.invalidPostExecutionShape ? observed : nil
        case .committed:
            let published = destinationSnapshot(
                parentIdentity: parentIdentity,
                parentRevision: options.doesNotAdvancePublishedParent ? expected.parent.revision : 2,
                slotLocation: destinationLocation,
                slotRevision: options.invalidPostExecutionShape ? expected.slot.revision : 2,
                target: committedPayload,
                seed: seed * 1_000 + 62 + sideOffset
            )
            after = published
        case .notAttempted:
            throw ComparisonDocumentCoverageError.impossibleScenario
        }
        return .transition(
            ComparisonDocumentSaveDestinationTransition(
                expected: invalidExpected,
                observedBeforePublication: observed,
                observedAfterExecution: options.invalidPostExecutionShape && isFailed(outcome)
                    ? nil : after
            )
        )
    }

    private func makeSaveOperation(
        scenario: ComparisonDocumentScenario,
        side: ComparisonDocumentSide,
        planID: UUID,
        sourceDocument: ComparisonDocumentContentRevision,
        currentDocument: ComparisonDocumentContentRevision,
        openedSource: ComparisonDocumentSourceRevision,
        committedPayload: ComparisonDocumentFileRevision?,
        rebinding: ComparisonDocumentSourceRevision,
        options: BindingOptions
    ) -> ComparisonDocumentSaveOperationBinding? {
        let operation = scenario.save.operation(on: side)
        guard operation != .notAttempted else { return nil }
        let outcome = scenario.save[side]
        var totalPathByteCount = scenario.save.execution == .batch ? 16 : 8
        if options.changesRightBatchTotalPath, side == .right { totalPathByteCount += 1 }
        let operationCount = scenario.save.execution == .batch ? 2 : 1
        var estimatedWorkUnits = UInt64(totalPathByteCount + operationCount * 2 + operationCount)
        if options.hasInvalidEstimatedWork { estimatedWorkUnits += 1 }
        let boundedSourceDocument: ComparisonDocumentContentRevision
        if options.sourceDocumentExceedsEncodedLimit || options.sourceDocumentExceedsMetadataLimit {
            boundedSourceDocument = ComparisonDocumentContentRevision(
                identity: sourceDocument.identity,
                generation: sourceDocument.generation,
                encodedByteCount: options.sourceDocumentExceedsEncodedLimit
                    ? ThreePaneSavePlanningLimits.default.maximumEncodedFileBytes + 1
                    : sourceDocument.encodedByteCount,
                metadataByteCount: options.sourceDocumentExceedsMetadataLimit
                    ? ThreePaneSavePlanningLimits.default.maximumMetadataBytes + 1
                    : sourceDocument.metadataByteCount,
                encodedContentSHA256: sourceDocument.encodedContentSHA256,
                metadataSHA256: sourceDocument.metadataSHA256,
                contentAndMetadataSHA256: sourceDocument.contentAndMetadataSHA256,
                encoding: sourceDocument.encoding,
                isReadOnly: sourceDocument.isReadOnly
            )
        } else {
            boundedSourceDocument = sourceDocument
        }
        var paneDocument: ComparisonDocumentContentRevision?
        var paneSource: ComparisonDocumentSourceRevision?
        var panePlanID: UUID?
        var consumed = false
        switch outcome {
        case .committed(.applied):
            paneDocument = sourceDocument
            paneSource = openedSource
            panePlanID = options.omitsRequiredPaneUpdatePlanID ? nil : planID
        case .committed(.rejected(.planAlreadyConsumed)):
            panePlanID = planID
            consumed = true
        case .committed(.rejected(.ownerRevisionChanged)):
            paneDocument = currentDocument
            paneSource = openedSource
            panePlanID = planID
        case .committed(.rejected(.bindingChanged)):
            paneDocument = sourceDocument
            paneSource = rebinding
            panePlanID = planID
        case .notAttempted, .failed, .uncertain:
            if options.addsPaneUpdateDataToNoncommit { paneDocument = sourceDocument }
        }
        if options.corruptsPaneUpdateDocument {
            paneDocument = contentRevision(
                identity: sourceDocument.identity,
                generation: sourceDocument.generation,
                payload: 9_999_991
            )
        }
        if options.corruptsPaneUpdateSource { paneSource = rebinding }
        if options.omitsPaneUpdateDocument { paneDocument = nil }
        if options.omitsPaneUpdateSource { paneSource = nil }
        if options.changesPaneUpdatePlanID { panePlanID = uuid(uuidTail(planID) + 1) }
        if options.flipsPaneUpdateConsumption { consumed.toggle() }
        let saveLimits: ThreePaneSavePlanningLimits =
            options.usesTooTightSaveLimits
            ? try! ThreePaneSavePlanningLimits(
                maximumPathUTF8Bytes: 4,
                maximumTotalPathUTF8Bytes: 4
            )
            : .default
        let destinationPathByteCount = options.hasInvalidPathCounts ? 0 : 4
        let parentPathByteCount = options.hasInvalidParentPathCount ? 0 : 4
        let leafByteCount = options.hasInvalidLeafCount ? 0 : 2
        let operationPlanID =
            options.hasInvalidPlanID
            ? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            : options.changesRightBatchPlanID && side == .right
                ? uuid(uuidTail(planID) + 1) : planID
        let sourceFile = file(from: openedSource).map { file in
            options.usesWrongSourceFile
                ? copyFile(
                    file,
                    identity: fileIdentity(seed: 99_999, role: 1, location: file.identity.location),
                    revision: file.revision
                ) : file
        }
        return ComparisonDocumentSaveOperationBinding(
            planID: operationPlanID,
            sourceDocument: boundedSourceDocument,
            sourceFile: sourceFile,
            limits: saveLimits,
            destinationPathUTF8ByteCount: destinationPathByteCount,
            parentPathUTF8ByteCount: parentPathByteCount,
            canonicalLeafIdentityUTF8ByteCount: leafByteCount,
            plannedOperationCount: options.hasInvalidPlannedOperationCount
                ? operationCount + 1 : operationCount,
            totalPathUTF8ByteCount: options.hasInvalidTotalPathCount
                ? totalPathByteCount + 1 : totalPathByteCount,
            estimatedWorkUnits: estimatedWorkUnits,
            committedPayload: isCommitted(outcome) ? committedPayload : nil,
            paneUpdateObservedDocument: paneDocument,
            paneUpdateObservedSource: paneSource,
            paneUpdateObservedPlanID: panePlanID,
            planWasConsumedBeforePaneUpdate: consumed
        )
    }

    private func makeCurrentSource(
        operation: ComparisonDocumentSideSaveOperation,
        outcome: ComparisonDocumentSideSaveOutcome,
        openedSource: ComparisonDocumentSourceRevision,
        committedPayload: ComparisonDocumentFileRevision?,
        rebinding: ComparisonDocumentSourceRevision
    ) -> ComparisonDocumentSourceRevision? {
        switch outcome {
        case .committed(.applied):
            committedPayload.map(ComparisonDocumentSourceRevision.file)
        case .committed(.rejected(.bindingChanged)):
            rebinding
        case .notAttempted, .failed, .uncertain, .committed(.rejected):
            openedSource
        }
    }

    private func makeBackup(
        scenario: ComparisonDocumentScenario,
        side: ComparisonDocumentSide,
        saveDestination: ComparisonDocumentSaveDestinationBinding,
        seed: UInt64,
        sideOffset: UInt64,
        locationKey: ComparisonDocumentStableID,
        options: BindingOptions
    ) throws -> ComparisonDocumentCompletedBackupEvidence? {
        let shouldAttach: Bool
        if case .required(_, _, .completed) = scenario.backup[side] {
            shouldAttach = true
        } else {
            shouldAttach = options.attachesBackupEvidenceToNonCompletedOutcome
        }
        guard shouldAttach,
            case .transition(let saveTransition) = saveDestination,
            let source = saveTransition.observedBeforePublication.target
        else { return nil }
        let slotLocation: ComparisonDocumentLocationIdentity
        if options.backupSlotAliasesSaveDestination {
            slotLocation = saveTransition.expected.slot.location
        } else if options.rightBackupSlotAliasesLeftOpenedFile, side == .right {
            slotLocation = location(seed, 10, locationKey)
        } else if options.aliasesRightBackupSlotToLeft, side == .right {
            slotLocation = location(seed, 80, locationKey)
        } else {
            slotLocation = location(seed, 80 + sideOffset, locationKey)
        }
        let parentIdentity = fileIdentity(
            seed: seed,
            role: 80 + sideOffset,
            location: location(seed, 81 + sideOffset, locationKey)
        )
        var expected = destinationSnapshot(
            parentIdentity: parentIdentity,
            parentRevision: 1,
            slotLocation: slotLocation,
            slotRevision: 1,
            target: nil,
            seed: seed * 1_000 + 80 + sideOffset
        )
        if options.backupDestinationStartsOccupied {
            expected = destinationSnapshot(
                parentIdentity: parentIdentity,
                parentRevision: 1,
                slotLocation: slotLocation,
                slotRevision: 1,
                target: copyFile(source, identity: fileIdentity(seed: seed, role: 83 + sideOffset, location: slotLocation), revision: 1),
                seed: seed * 1_000 + 83 + sideOffset
            )
        }
        let copyIdentity: ComparisonDocumentFileIdentity
        if options.backupPayloadAliasesSource {
            copyIdentity = ComparisonDocumentFileIdentity(
                volumeID: source.identity.volumeID,
                fileID: source.identity.fileID,
                generation: source.identity.generation,
                location: slotLocation
            )
        } else {
            copyIdentity = fileIdentity(seed: seed, role: 82 + sideOffset, location: slotLocation)
        }
        let copy = corrupt(
            copyFile(source, identity: copyIdentity, revision: 1),
            options.backupPayloadCorruption
        )
        let after = destinationSnapshot(
            parentIdentity: parentIdentity,
            parentRevision: 2,
            slotLocation: slotLocation,
            slotRevision: 2,
            target: copy,
            seed: seed * 1_000 + 82 + sideOffset
        )
        return ComparisonDocumentCompletedBackupEvidence(
            sourceRevision: options.backupUsesWrongOccupiedSource
                ? copyFile(source, identity: source.identity, revision: source.revision + 1) : source,
            destination: ComparisonDocumentSaveDestinationTransition(
                expected: expected,
                observedBeforePublication: expected,
                observedAfterExecution: options.backupOmitsPublishedState ? nil : after
            ),
            committedPayload: copy
        )
    }

    private func paneRebinding(
        _ opened: ComparisonDocumentSourceRevision,
        sourceDocument: ComparisonDocumentContentRevision,
        seed: UInt64,
        sideOffset: UInt64
    ) -> ComparisonDocumentSourceRevision {
        switch opened {
        case .file(let file):
            return .file(fileRevision(identity: file.identity, revision: 20, content: sourceDocument))
        case .scratchpad(let scratchpad):
            return .scratchpad(
                ComparisonDocumentScratchpadRevision(
                    identity: scratchpad.identity,
                    generation: scratchpad.generation + 10,
                    encodedByteCount: sourceDocument.encodedByteCount,
                    metadataByteCount: sourceDocument.metadataByteCount,
                    encodedContentSHA256: sourceDocument.encodedContentSHA256,
                    metadataSHA256: sourceDocument.metadataSHA256,
                    contentAndMetadataSHA256: sourceDocument.contentAndMetadataSHA256,
                    encoding: sourceDocument.encoding,
                    isReadOnly: sourceDocument.isReadOnly
                )
            )
        }
    }

    private func contentRevision(
        identity: UUID,
        generation: UInt64,
        payload: UInt64
    ) -> ComparisonDocumentContentRevision {
        ComparisonDocumentContentRevision(
            identity: identity,
            generation: generation,
            encodedByteCount: 8,
            metadataByteCount: 4,
            encodedContentSHA256: digest(payload * 3 + 1),
            metadataSHA256: digest(payload * 3 + 2),
            contentAndMetadataSHA256: digest(payload * 3 + 3),
            encoding: ThreePaneSaveEncodingMetadata(
                encoding: ThreePaneSaveTextEncoding.utf8,
                hasByteOrderMark: false
            ),
            isReadOnly: false
        )
    }

    private func scratchpadRevision(
        from content: ComparisonDocumentContentRevision
    ) -> ComparisonDocumentScratchpadRevision {
        ComparisonDocumentScratchpadRevision(
            identity: uuid(uuidTail(content.identity) + 100_000_000),
            generation: content.generation,
            encodedByteCount: content.encodedByteCount,
            metadataByteCount: content.metadataByteCount,
            encodedContentSHA256: content.encodedContentSHA256,
            metadataSHA256: content.metadataSHA256,
            contentAndMetadataSHA256: content.contentAndMetadataSHA256,
            encoding: content.encoding,
            isReadOnly: content.isReadOnly
        )
    }

    private func fileRevision(
        identity: ComparisonDocumentFileIdentity,
        revision: UInt64,
        content: ComparisonDocumentContentRevision
    ) -> ComparisonDocumentFileRevision {
        ComparisonDocumentFileRevision(
            identity: identity,
            revision: revision,
            byteCount: content.encodedByteCount,
            metadataByteCount: content.metadataByteCount,
            modificationTimeSeconds: Int64(revision),
            modificationTimeNanoseconds: 1,
            statusChangeTimeSeconds: Int64(revision),
            statusChangeTimeNanoseconds: 2,
            contentSHA256: content.encodedContentSHA256,
            metadataSHA256: content.metadataSHA256,
            contentAndMetadataSHA256: content.contentAndMetadataSHA256,
            encoding: content.encoding,
            isReadOnly: content.isReadOnly
        )
    }

    private func copyFile(
        _ source: ComparisonDocumentFileRevision,
        identity: ComparisonDocumentFileIdentity,
        revision: UInt64
    ) -> ComparisonDocumentFileRevision {
        ComparisonDocumentFileRevision(
            identity: identity,
            revision: revision,
            byteCount: source.byteCount,
            metadataByteCount: source.metadataByteCount,
            modificationTimeSeconds: source.modificationTimeSeconds,
            modificationTimeNanoseconds: source.modificationTimeNanoseconds,
            statusChangeTimeSeconds: source.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: source.statusChangeTimeNanoseconds,
            contentSHA256: source.contentSHA256,
            metadataSHA256: source.metadataSHA256,
            contentAndMetadataSHA256: source.contentAndMetadataSHA256,
            encoding: source.encoding,
            isReadOnly: source.isReadOnly
        )
    }

    private func corrupt(
        _ file: ComparisonDocumentFileRevision,
        _ corruption: PayloadCorruption?
    ) -> ComparisonDocumentFileRevision {
        guard let corruption else { return file }
        var byteCount = file.byteCount
        var metadataByteCount = file.metadataByteCount
        var contentSHA256 = file.contentSHA256
        var metadataSHA256 = file.metadataSHA256
        var contentAndMetadataSHA256 = file.contentAndMetadataSHA256
        var encoding = file.encoding
        var isReadOnly = file.isReadOnly
        switch corruption {
        case .byteCount: byteCount += 1
        case .metadataByteCount: metadataByteCount += 1
        case .contentSHA256: contentSHA256 = digest(0xF1)
        case .metadataSHA256: metadataSHA256 = digest(0xF2)
        case .contentAndMetadataSHA256: contentAndMetadataSHA256 = digest(0xF3)
        case .encoding:
            encoding = ThreePaneSaveEncodingMetadata(
                encoding: ThreePaneSaveTextEncoding.windows1252,
                hasByteOrderMark: false
            )
        case .readOnly: isReadOnly.toggle()
        }
        return ComparisonDocumentFileRevision(
            identity: file.identity,
            revision: file.revision,
            byteCount: byteCount,
            metadataByteCount: metadataByteCount,
            modificationTimeSeconds: file.modificationTimeSeconds,
            modificationTimeNanoseconds: file.modificationTimeNanoseconds,
            statusChangeTimeSeconds: file.statusChangeTimeSeconds,
            statusChangeTimeNanoseconds: file.statusChangeTimeNanoseconds,
            contentSHA256: contentSHA256,
            metadataSHA256: metadataSHA256,
            contentAndMetadataSHA256: contentAndMetadataSHA256,
            encoding: encoding,
            isReadOnly: isReadOnly
        )
    }

    private func fileIdentity(
        seed: UInt64,
        role: UInt64,
        location: ComparisonDocumentLocationIdentity
    ) -> ComparisonDocumentFileIdentity {
        ComparisonDocumentFileIdentity(
            volumeID: seed + 1,
            fileID: seed * 1_000 + role + 1,
            generation: 1,
            location: location
        )
    }

    private func location(
        _ seed: UInt64,
        _ role: UInt64,
        _ key: ComparisonDocumentStableID
    ) -> ComparisonDocumentLocationIdentity {
        ComparisonDocumentLocationIdentity(
            keyReference: key,
            hmacSHA256: digest(seed * 1_000 + role + 1)
        )
    }

    private func destinationSnapshot(
        parentIdentity: ComparisonDocumentFileIdentity,
        parentRevision: UInt64,
        slotLocation: ComparisonDocumentLocationIdentity,
        slotRevision: UInt64,
        target: ComparisonDocumentFileRevision?,
        seed: UInt64
    ) -> ComparisonDocumentSaveDestinationSnapshot {
        ComparisonDocumentSaveDestinationSnapshot(
            parent: ComparisonDocumentDirectoryRevision(
                identity: parentIdentity,
                revision: parentRevision,
                metadataByteCount: 4,
                metadataSHA256: digest(seed + parentRevision)
            ),
            slot: ComparisonDocumentDestinationSlotRevision(
                location: slotLocation,
                revision: slotRevision
            ),
            target: target
        )
    }

    private func transition(
        _ binding: ComparisonDocumentSideRevisionBinding
    ) throws -> ComparisonDocumentSaveDestinationTransition {
        guard case .transition(let transition) = binding.saveDestination else {
            throw ComparisonDocumentCoverageError.impossibleScenario
        }
        return transition
    }

    private func file(
        from source: ComparisonDocumentSourceRevision?
    ) -> ComparisonDocumentFileRevision? {
        guard case .file(let file)? = source else { return nil }
        return file
    }

    private func isCommitted(_ outcome: ComparisonDocumentSideSaveOutcome) -> Bool {
        if case .committed = outcome { return true }
        return false
    }

    private func isFailed(_ outcome: ComparisonDocumentSideSaveOutcome) -> Bool {
        if case .failed = outcome { return true }
        return false
    }

    private func physicalKey(_ file: ComparisonDocumentFileRevision) -> [UInt64] {
        [file.identity.volumeID, file.identity.fileID, file.identity.generation]
    }

    private func canonicalScenario(
        matching predicate: (ComparisonDocumentScenario) -> Bool
    ) throws -> ComparisonDocumentScenario {
        try scenario(in: Matrix.canonicalScenarios, matching: predicate)
    }

    private func scenario(
        in scenarios: [ComparisonDocumentScenario],
        matching predicate: (ComparisonDocumentScenario) -> Bool
    ) throws -> ComparisonDocumentScenario {
        try XCTUnwrap(scenarios.first(where: predicate))
    }

    private func assertInvalidCapture(
        _ scenario: ComparisonDocumentScenario,
        _ bindings: ComparisonDocumentRevisionBindings,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try Matrix.canonicalCaptureData(for: assertion(scenario, bindings)),
            file: file,
            line: line
        ) {
            XCTAssertEqual(
                $0 as? ComparisonDocumentCoverageError,
                .invalidEvidence(field: "capture.bindings"),
                file: file,
                line: line
            )
        }
    }

    private func archiveSections(_ archive: Data) throws -> ArchiveSections {
        var offset = archive.startIndex
        func read(_ count: Int) throws -> Data {
            guard count >= 0, count <= archive.distance(from: offset, to: archive.endIndex) else {
                throw ComparisonDocumentCoverageError.invalidArchive
            }
            let end = archive.index(offset, offsetBy: count)
            defer { offset = end }
            return archive[offset..<end]
        }
        func readUInt64() throws -> UInt64 {
            try read(8).reduce(into: UInt64(0)) { $0 = ($0 << 8) | UInt64($1) }
        }
        func readFrame() throws -> Data {
            let count = try readUInt64()
            guard let exact = Int(exactly: count) else {
                throw ComparisonDocumentCoverageError.invalidArchive
            }
            return try read(exact)
        }

        let magic = try readFrame()
        let version = try readUInt64()
        let inventorySHA256 = Array(try read(SHA256.byteCount))
        let evidenceSHA256 = Array(try read(SHA256.byteCount))
        let reportSHA256 = Array(try read(SHA256.byteCount))
        let inventory = try readFrame()
        let evidence = try readFrame()
        let report = try readFrame()
        let trailingSHA256 = Array(try read(SHA256.byteCount))
        XCTAssertEqual(offset, archive.endIndex)
        return ArchiveSections(
            magic: magic,
            version: version,
            inventorySHA256: inventorySHA256,
            evidenceSHA256: evidenceSHA256,
            reportSHA256: reportSHA256,
            inventory: inventory,
            evidence: evidence,
            report: report,
            trailingSHA256: trailingSHA256
        )
    }

    private func canonicalArchive(
        _ sections: ArchiveSections,
        magic: Data? = nil,
        version: UInt64? = nil,
        inventorySHA256: [UInt8]? = nil,
        inventory: Data? = nil,
        evidence: Data? = nil,
        report: Data? = nil,
        trailingPayload: Data = Data()
    ) -> Data {
        let inventoryData = inventory ?? sections.inventory
        let evidenceData = evidence ?? sections.evidence
        let reportData = report ?? sections.report
        var payload = Data()
        appendFrame(magic ?? sections.magic, to: &payload)
        appendUInt64(version ?? sections.version, to: &payload)
        payload.append(contentsOf: inventorySHA256 ?? sha256(inventoryData))
        payload.append(contentsOf: sha256(evidenceData))
        payload.append(contentsOf: sha256(reportData))
        appendFrame(inventoryData, to: &payload)
        appendFrame(evidenceData, to: &payload)
        appendFrame(reportData, to: &payload)
        payload.append(trailingPayload)
        payload.append(contentsOf: sha256(payload))
        return payload
    }

    private func appendFrame(_ value: Data, to data: inout Data) {
        appendUInt64(UInt64(value.count), to: &data)
        data.append(value)
    }

    private func appendUInt64(_ value: UInt64, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private func expectedPolicyByteCount(_ fixture: SignedFixture) -> Int {
        func framedString(_ value: String) -> Int { 8 + value.utf8.count }
        func revision(_ value: ComparisonDocumentRevisionReference) -> Int {
            framedString(value.id.rawValue) + 8
        }
        return framedString("MMCDPOL4")
            + 8
            + revision(fixture.collectorReference) + 8 + 32
            + 8
            + framedString(fixture.locationKey.rawValue)
            + 8 * 4
            + revision(reference("document-replay-policy", 31))
    }

    private func limits(
        maximumObservations: Int = 32_768,
        maximumTrustedCollectors: Int = 1_024,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumWorkUnits: Int = 512 * 1_024 * 1_024,
        maximumFindings: Int = 32 * 1_024,
        maximumCanonicalBytes: Int = 128 * 1_024 * 1_024,
        maximumArchiveBytes: Int = 384 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) -> ComparisonDocumentCoverageLimits {
        ComparisonDocumentCoverageLimits(
            maximumObservations: maximumObservations,
            maximumTrustedCollectors: maximumTrustedCollectors,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumWorkUnits: maximumWorkUnits,
            maximumFindings: maximumFindings,
            maximumCanonicalBytes: maximumCanonicalBytes,
            maximumArchiveBytes: maximumArchiveBytes,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func reference(
        _ value: String,
        _ revision: UInt64
    ) -> ComparisonDocumentRevisionReference {
        ComparisonDocumentRevisionReference(
            id: ComparisonDocumentStableID(rawValue: value),
            revision: revision
        )
    }

    private func uuid(_ value: UInt64) -> UUID {
        let string = String(format: "00000000-0000-4000-8000-%012llX", value)
        return UUID(uuidString: string)!
    }

    private func uuidTail(_ value: UUID) -> UInt64 {
        let bytes = value.uuid
        return UInt64(bytes.10) << 40 | UInt64(bytes.11) << 32 | UInt64(bytes.12) << 24
            | UInt64(bytes.13) << 16 | UInt64(bytes.14) << 8 | UInt64(bytes.15)
    }

    private func replayNonce(_ value: Int) -> [UInt8] {
        var nonce = [UInt8](repeating: 0, count: 16)
        var encoded = UInt64(value + 1).bigEndian
        withUnsafeBytes(of: &encoded) { nonce.replaceSubrange(8..<16, with: $0) }
        return nonce
    }

    private func digest(_ value: UInt64) -> [UInt8] {
        var result = [UInt8](repeating: 0xA5, count: SHA256.byteCount)
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { result.replaceSubrange(24..<32, with: $0) }
        return result
    }

    private func sha256<D: DataProtocol>(_ data: D) -> [UInt8] {
        Array(SHA256.hash(data: Data(data)))
    }

    private func hex(_ data: [UInt8]) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func assertError<T>(
        _ expected: ComparisonDocumentCoverageError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? ComparisonDocumentCoverageError, expected, file: file, line: line)
        }
    }

    private func findingCodes(
        _ result: ComparisonDocumentCoverageResult,
        scenarioID: ComparisonDocumentScenarioID
    ) -> Set<ComparisonDocumentFindingCode> {
        Set(
            result.report.findings.compactMap { finding in
                guard finding.subject == .scenario(scenarioID) else { return nil }
                return finding.code
            }
        )
    }

    private func expectedFindingID(
        _ code: ComparisonDocumentFindingCode,
        scenarioID: ComparisonDocumentScenarioID,
        discriminator: Int
    ) -> String {
        [code.rawValue, "scenario:\(scenarioID.rawValue)", String(discriminator)]
            .map { "\($0.utf8.count):\($0)" }
            .joined()
    }
}

extension ComparisonDocumentSide {
    fileprivate var lifecycleSide: ComparisonLifecycleState.Side {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}

private final class InvocationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func record() {
        lock.withLock { value += 1 }
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAtInvocation: Int
    private var invocations = 0

    init(cancelAtInvocation: Int) {
        self.cancelAtInvocation = cancelAtInvocation
    }

    var invocationCount: Int { lock.withLock { invocations } }

    func check() -> Bool {
        lock.withLock {
            invocations += 1
            return invocations >= cancelAtInvocation
        }
    }
}

private final class CaptureResolver: @unchecked Sendable {
    private let captures: [[UInt8]: Data]
    private let probesResourceBound: Bool
    private let lock = NSLock()
    private var invocations = 0
    private var probedResourceBound = false

    init(captures: [[UInt8]: Data], probesResourceBound: Bool) {
        self.captures = captures
        self.probesResourceBound = probesResourceBound
    }

    var invocationCount: Int { lock.withLock { invocations } }
    var didProbeResourceBound: Bool { lock.withLock { probedResourceBound } }

    func resolve(
        digest: [UInt8],
        declaredByteCount: Int,
        sink: ComparisonDocumentCaptureSink,
        cancellationCheck: ComparisonDocumentCoverageMatrix.CancellationCheck
    ) throws {
        let shouldProbe = lock.withLock { () -> Bool in
            invocations += 1
            if probesResourceBound && !probedResourceBound {
                probedResourceBound = true
                return true
            }
            return false
        }
        if cancellationCheck() { throw CancellationError() }
        guard let capture = captures[digest], capture.count == declaredByteCount else {
            throw ComparisonDocumentCaptureResolutionError.declaredByteCountMismatch
        }
        if shouldProbe {
            XCTAssertThrowsError(try sink.append(capture + Data([0]))) {
                XCTAssertEqual(
                    $0 as? ComparisonDocumentCaptureResolutionError,
                    .exceedsMaximumByteCount
                )
            }
        }
        try sink.append(capture.prefix(capture.count / 2))
        try sink.append(capture.suffix(capture.count - capture.count / 2))
    }
}

private final class ReplayRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let result: ComparisonDocumentAuditPolicy.ReplayClaimResult
    private var invocationValue = 0
    private var replayPolicyValue: ComparisonDocumentRevisionReference?
    private var evidenceValue: ComparisonDocumentRevisionReference?
    private var archiveValue: [UInt8] = []
    private var claimsValue: [ComparisonDocumentReplayClaim] = []
    private var auditTimeValue: UInt64 = 0
    private var deadlineValue: UInt64 = 0
    private var remainingValue = 0

    init(result: ComparisonDocumentAuditPolicy.ReplayClaimResult = .committed) {
        self.result = result
    }

    var invocationCount: Int { lock.withLock { invocationValue } }
    var lastReplayPolicy: ComparisonDocumentRevisionReference? {
        lock.withLock { replayPolicyValue }
    }
    var lastEvidence: ComparisonDocumentRevisionReference? { lock.withLock { evidenceValue } }
    var lastArchiveSHA256: [UInt8] { lock.withLock { archiveValue } }
    var lastClaims: [ComparisonDocumentReplayClaim] { lock.withLock { claimsValue } }
    var lastAuditTime: UInt64 { lock.withLock { auditTimeValue } }
    var lastDeadline: UInt64 { lock.withLock { deadlineValue } }
    var lastRemainingWorkUnits: Int { lock.withLock { remainingValue } }

    func claim(
        replayPolicy: ComparisonDocumentRevisionReference,
        evidence: ComparisonDocumentRevisionReference,
        archiveSHA256: [UInt8],
        claims: [ComparisonDocumentReplayClaim],
        context: ComparisonDocumentAuditPolicy.ReplayClaimContext
    ) -> ComparisonDocumentAuditPolicy.ReplayClaimResult {
        lock.withLock {
            invocationValue += 1
            replayPolicyValue = replayPolicy
            evidenceValue = evidence
            archiveValue = archiveSHA256
            claimsValue = claims
            auditTimeValue = context.trustedAuditTimeUnixMilliseconds
            deadlineValue = context.deadlineUnixMilliseconds
            remainingValue = context.remainingWorkUnits
        }
        if context.cancellationCheck() { return .cancelled }
        return result
    }
}
