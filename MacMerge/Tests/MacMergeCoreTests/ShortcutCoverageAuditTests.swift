import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ShortcutCoverageAuditTests: XCTestCase {
    private typealias Audit = ShortcutCoverageAudit
    private typealias Policy = KeyboardShortcutPolicy
    private typealias PolicyError = KeyboardShortcutPolicyError

    func testCanonicalApplicationInventoryHasExactIndependentTuplesAndOrder() throws {
        let expected = try applicationSpecs().map(applicationProjection)
        let actual = Audit.Inventory.canonical.bindings.map(ApplicationProjection.init)

        XCTAssertEqual(Audit.Inventory.canonicalRevision, 3)
        XCTAssertEqual(Audit.Inventory.canonical.revision, 3)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(Set(actual), Set(expected))
        XCTAssertEqual(actual.count, 32)
    }

    func testCanonicalNativeInventoryAndCollisionInventoryAreExact() throws {
        let expectedNative = try nativeSpecsWithIDs().map(nativeProjection)
        let actualNative = Audit.Inventory.canonical.nativeBindings.map(NativeProjection.init)
        XCTAssertEqual(actualNative, expectedNative)
        XCTAssertEqual(Set(actualNative), Set(expectedNative))
        XCTAssertEqual(actualNative.count, expectedNative.count)
        XCTAssertEqual(Set(actualNative.map(\.id)).count, actualNative.count)

        let policy = try Policy.makeUnfinishedAudit(cancellationCheck: {})
        let actualReservations = policy.nativeTextEditingReservations.map {
            NativeTuple(command: $0.command, chord: $0.chord.canonicalDescription, applicability: $0.applicability)
        }
        let expectedReservations = nativeSpecs().map {
            NativeTuple(command: $0.command, chord: $0.chord, applicability: $0.applicability)
        }.sorted(by: nativeTuplePrecedes)
        XCTAssertEqual(actualReservations, expectedReservations)
        XCTAssertEqual(Set(actualReservations), Set(expectedReservations))

        let both = Policy.NativeTextEditingApplicability.readOnlyAndEditable
        let editable = Policy.NativeTextEditingApplicability.editable
        let expectedCollisions: [CollisionProjection] = [
            collision("f5", .refresh, .complete, editable),
            collision("command+z", .undo, .undo, editable),
            collision("option+downArrow", .nextDifference, .moveParagraphDown, both),
            collision("option+end", .lastDifference, .moveForwardToParagraphEnd, both),
            collision("option+home", .firstDifference, .moveBackwardToParagraphStart, both),
            collision("option+leftArrow", .copyToLeft, .moveWordLeft, both),
            collision("option+return", .currentDifference, .insertNewlineIgnoringFieldEditor, editable),
            collision("option+rightArrow", .copyToRight, .moveWordRight, both),
            collision("option+upArrow", .previousDifference, .moveParagraphUp, both),
            collision("command+shift+z", .redo, .redo, editable),
            collision("option+shift+downArrow", .nextConflict, .moveParagraphDownAndModifySelection, both),
            collision("option+shift+upArrow", .previousConflict, .moveParagraphUpAndModifySelection, both)
        ]
        let actualCollisions = policy.collisions.map(CollisionProjection.init)
        XCTAssertEqual(actualCollisions, expectedCollisions)
        XCTAssertEqual(policy.collisions.count, expectedCollisions.count)
    }

    func testRequiredContextsCoverEveryLifecycleAndIndependentGate() {
        let expectedIDs: [Audit.ContextID] = [
            .empty, .disabled, .loading, .selected, .dirty, .textFocused, .textFocusedClean,
            .equal, .failed,
            .readOnly, .editorReadOnly, .directionalLeft, .directionalRight,
            .leftDestinationReadOnly, .rightDestinationReadOnly,
            .leftDestinationUnloaded, .rightDestinationUnloaded,
            .lineSelectionUnavailable, .currentDifferenceUnavailable,
            .changePaneUnavailable, .changePaneBackUnavailable,
            .navigationAtStart, .navigationAtEnd, .refreshing, .stale, .canceled,
            .undoEnabled, .redoEnabled, .differencePreviousOnly, .differenceNextOnly,
            .conflictPreviousOnly, .conflictNextOnly,
            .comparedFilePreviousOnly, .comparedFileNextOnly
        ]
        XCTAssertEqual(Audit.ContextID.allCases, expectedIDs)
        XCTAssertEqual(Audit.requiredContexts.map(\.id), expectedIDs)
        for (actual, expected) in zip(
            Audit.requiredContexts.map(ContextSummary.init),
            expectedIDs.map(expectedContextSummary)
        ) {
            XCTAssertEqual(actual, expected, expected.id.rawValue)
        }

        let undo = expectedContextSummary(.undoEnabled)
        let redo = expectedContextSummary(.redoEnabled)
        XCTAssertFalse(undo.keyboardDirty)
        XCTAssertFalse(redo.keyboardDirty)
        XCTAssertTrue(undo.canUndo)
        XCTAssertFalse(undo.canRedo)
        XCTAssertFalse(redo.canUndo)
        XCTAssertTrue(redo.canRedo)

        let leftReadOnly = expectedContextSummary(.leftDestinationReadOnly)
        let rightReadOnly = expectedContextSummary(.rightDestinationReadOnly)
        XCTAssertFalse(leftReadOnly.leftEditable)
        XCTAssertTrue(leftReadOnly.rightEditable)
        XCTAssertTrue(rightReadOnly.leftEditable)
        XCTAssertFalse(rightReadOnly.rightEditable)

        XCTAssertEqual(expectedContextSummary(.differencePreviousOnly).differenceGates, [true, false])
        XCTAssertEqual(expectedContextSummary(.conflictPreviousOnly).conflictGates, [true, false])
        XCTAssertEqual(expectedContextSummary(.comparedFilePreviousOnly).fileGates, [true, false])
        XCTAssertTrue(commandStateMismatches().isEmpty, commandStateMismatches().joined(separator: "\n"))
    }

    func testCanonicalMatrixMatchesIndependentOutcomeModelForEveryBindingAndContext() throws {
        let matrix = try Audit.canonicalMatrix(cancellationCheck: { false })
        var actual: [Audit.MatrixKey: Audit.Outcome] = [:]
        for expectation in matrix {
            XCTAssertNil(actual.updateValue(expectation.outcome, forKey: expectation.key))
        }

        var expected: [Audit.MatrixKey: Audit.Outcome] = [:]
        let contexts = Audit.ContextID.allCases.map(expectedContextSummary)
        let applications = applicationSpecs()
        for application in applications {
            for context in contexts {
                expected[Audit.MatrixKey(bindingID: id(application.id), contextID: context.id)] = expectedOutcome(
                    for: application,
                    context: context
                )
            }
        }
        for native in try nativeSpecsWithIDs() {
            let application = applications.first { $0.chord == native.spec.chord }
            for context in contexts {
                expected[Audit.MatrixKey(bindingID: id(native.id), contextID: context.id)] = expectedOutcome(
                    for: native.spec,
                    application: application,
                    context: context
                )
            }
        }

        let expectedKeys =
            applicationSpecs().flatMap { application in
                Audit.ContextID.allCases.map {
                    Audit.MatrixKey(bindingID: id(application.id), contextID: $0)
                }
            }
            + (try nativeSpecsWithIDs()).flatMap { native in
                Audit.ContextID.allCases.map {
                    Audit.MatrixKey(bindingID: id(native.id), contextID: $0)
                }
            }
        XCTAssertEqual(matrix.map(\.key), expectedKeys)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(matrix.count, (applicationSpecs().count + nativeSpecs().count) * Audit.ContextID.allCases.count)
    }

    func testNativeOnlyBindingsAreFirstClassRowsAndF5FallsBackToApplication() throws {
        let matrix = try Audit.canonicalMatrix(cancellationCheck: { false })
        let selectAll = try XCTUnwrap(try nativeSpecsWithIDs().first { $0.spec.command == .selectAll })
        let selectAllRows = matrix.filter { $0.key.bindingID == id(selectAll.id) }
        XCTAssertEqual(selectAllRows.count, Audit.ContextID.allCases.count)
        XCTAssertEqual(outcome(in: selectAllRows, context: .empty).owner, .none)
        XCTAssertEqual(
            outcome(in: selectAllRows, context: .editorReadOnly),
            Audit.Outcome(
                owner: .nativeTextEditor,
                command: .nativeTextEditing(.selectAll),
                isEnabled: true,
                invocation: .invoked
            )
        )

        let complete = try XCTUnwrap(try nativeSpecsWithIDs().first { $0.spec.command == .complete && $0.spec.chord == "f5" })
        let completeRows = matrix.filter { $0.key.bindingID == id(complete.id) }
        XCTAssertEqual(
            outcome(in: completeRows, context: .empty),
            Audit.Outcome(
                owner: .application,
                command: .application(.comparison(.refresh)),
                isEnabled: false,
                invocation: .blocked
            )
        )
        XCTAssertEqual(
            outcome(in: completeRows, context: .textFocused),
            Audit.Outcome(
                owner: .nativeTextEditor,
                command: .nativeTextEditing(.complete),
                isEnabled: true,
                invocation: .invoked
            )
        )
    }

    func testHardwareCanonicalizationUsesRawCodesModifiersAndLogicalCharacters() throws {
        let f4 = Audit.HardwareKeyCapture(
            hardwareKeyCode: 118,
            inputSourceID: id("com.apple.keylayout.US"),
            charactersIgnoringModifiers: String(UnicodeScalar(0xF707)!),
            rawModifierFlags: modifierFlag(.shift) | modifierFlag(.function)
        )
        XCTAssertEqual(try f4.canonicalChord().canonicalDescription, "shift+f4")

        let nonUSLetter = Audit.HardwareKeyCapture(
            hardwareKeyCode: 0,
            inputSourceID: id("com.apple.keylayout.French"),
            charactersIgnoringModifiers: "q",
            rawModifierFlags: modifierFlag(.command)
        )
        XCTAssertEqual(try nonUSLetter.canonicalChord().canonicalDescription, "command+q")

        let shiftedPunctuation = Audit.HardwareKeyCapture(
            hardwareKeyCode: 44,
            inputSourceID: id("com.apple.keylayout.British"),
            charactersIgnoringModifiers: "?",
            rawModifierFlags: modifierFlag(.option) | (1 << 63)
        )
        XCTAssertEqual(try shiftedPunctuation.canonicalChord().canonicalDescription, "option+shift+/")

        let uppercase = Audit.HardwareKeyCapture(
            hardwareKeyCode: 45,
            inputSourceID: id("com.apple.keylayout.Dvorak"),
            charactersIgnoringModifiers: "N",
            rawModifierFlags: modifierFlag(.command)
        )
        XCTAssertEqual(try uppercase.canonicalChord().canonicalDescription, "command+n")
    }

    func testEveryMappedHardwareCodeAndShiftedPunctuationCanonicalizesIndependently() throws {
        let mappedCodes: [(UInt16, UInt32, String)] = [
            (36, 0x000D, "return"), (76, 0x0003, "return"), (48, 0x0009, "tab"),
            (49, 0x0020, "space"), (51, 0x007F, "backspace"), (53, 0x001B, "escape"),
            (122, 0xF704, "f1"), (120, 0xF705, "f2"), (99, 0xF706, "f3"),
            (118, 0xF707, "f4"), (96, 0xF708, "f5"), (97, 0xF709, "f6"),
            (98, 0xF70A, "f7"), (100, 0xF70B, "f8"), (101, 0xF70C, "f9"),
            (109, 0xF70D, "f10"), (103, 0xF70E, "f11"), (111, 0xF70F, "f12"),
            (105, 0xF710, "f13"), (107, 0xF711, "f14"), (113, 0xF712, "f15"),
            (106, 0xF713, "f16"), (64, 0xF714, "f17"), (79, 0xF715, "f18"),
            (80, 0xF716, "f19"), (90, 0xF717, "f20"), (115, 0xF729, "home"),
            (116, 0xF72C, "pageUp"), (117, 0xF728, "delete"), (119, 0xF72B, "end"),
            (121, 0xF72D, "pageDown"), (123, 0xF702, "leftArrow"),
            (124, 0xF703, "rightArrow"), (125, 0xF701, "downArrow"),
            (126, 0xF700, "upArrow")
        ]
        for (keyCode, scalar, expected) in mappedCodes {
            let capture = Audit.HardwareKeyCapture(
                hardwareKeyCode: keyCode,
                inputSourceID: id("source"),
                charactersIgnoringModifiers: String(UnicodeScalar(scalar)!),
                rawModifierFlags: modifierFlag(.function)
            )
            XCTAssertEqual(try capture.canonicalChord().canonicalDescription, expected, "keyCode \(keyCode)")
        }

        let punctuation: [(Character, Character)] = [
            ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"),
            ("^", "6"), ("&", "7"), ("*", "8"), ("(", "9"), (")", "0"),
            ("_", "-"), ("+", "="), ("{", "["), ("}", "]"), ("|", "\\"),
            (":", ";"), ("\"", "'"), ("<", ","), (">", "."), ("?", "/"), ("~", "`")
        ]
        for (shifted, base) in punctuation {
            let capture = Audit.HardwareKeyCapture(
                hardwareKeyCode: 255,
                inputSourceID: id("source"),
                charactersIgnoringModifiers: String(shifted),
                rawModifierFlags: modifierFlag(.command)
            )
            XCTAssertEqual(
                try capture.canonicalChord().canonicalDescription,
                "command+shift+\(base)",
                String(shifted)
            )
        }
    }

    func testCharactersIgnoringModifiersConflictsAndMalformedValuesAreRejected() throws {
        let cases = [
            Audit.HardwareKeyCapture(
                hardwareKeyCode: 118,
                inputSourceID: id("source"),
                charactersIgnoringModifiers: String(UnicodeScalar(0xF708)!),
                rawModifierFlags: 0
            ),
            Audit.HardwareKeyCapture(
                hardwareKeyCode: 118,
                inputSourceID: id("source"),
                charactersIgnoringModifiers: "?",
                rawModifierFlags: 0
            ),
            Audit.HardwareKeyCapture(
                hardwareKeyCode: 255,
                inputSourceID: id("source"),
                charactersIgnoringModifiers: "ab",
                rawModifierFlags: modifierFlag(.command)
            ),
            Audit.HardwareKeyCapture(
                hardwareKeyCode: 255,
                inputSourceID: id("source"),
                charactersIgnoringModifiers: "",
                rawModifierFlags: modifierFlag(.command)
            )
        ]
        for capture in cases {
            assertAuditError(.invalidEvidence(field: "observation.charactersIgnoringModifiers")) {
                try capture.canonicalChord()
            }
        }

        let invalidCharacters = ["é", "e\u{301}", " "]
        for value in invalidCharacters {
            let capture = Audit.HardwareKeyCapture(
                hardwareKeyCode: 255,
                inputSourceID: id("source"),
                charactersIgnoringModifiers: value,
                rawModifierFlags: modifierFlag(.command)
            )
            XCTAssertThrowsError(try capture.canonicalChord()) {
                guard case PolicyError.invalidCharacterKey = $0 else {
                    return XCTFail("unexpected error: \($0)")
                }
            }
        }
        let unmodified = Audit.HardwareKeyCapture(
            hardwareKeyCode: 255,
            inputSourceID: id("source"),
            charactersIgnoringModifiers: "x",
            rawModifierFlags: 0
        )
        XCTAssertThrowsError(try unmodified.canonicalChord()) {
            XCTAssertEqual($0 as? PolicyError, .printableKeyRequiresCommandModifier)
        }

        let application = try XCTUnwrap(applicationSpecs().first { $0.id == "select-line-difference-f4" })
        let observation = try assertionObservation(for: application, contextID: .selected)
        let conflictingCapture = Audit.HardwareKeyCapture(
            hardwareKeyCode: 118,
            inputSourceID: observation.hardwareKeyCapture.inputSourceID,
            charactersIgnoringModifiers: String(UnicodeScalar(0xF708)!),
            rawModifierFlags: observation.hardwareKeyCapture.rawModifierFlags
        )
        let changed = replacing(observation, hardwareKeyCapture: conflictingCapture)
        let result = try audit([changed])
        XCTAssertTrue(result.report.findings.contains { $0.code == .hardwareKeyMismatch })
        XCTAssertEqual(cell(result, key: observation.key).statuses, [.mismatched, .assertionOnly])
    }

    func testAssertionEvidenceCarriesFullExclusiveDispatchTraceAndCommandSpecificResults() throws {
        let observations = try assertionObservations()
        XCTAssertEqual(observations.count, (applicationSpecs().count + nativeSpecs().count) * Audit.ContextID.allCases.count)
        for observation in observations {
            XCTAssertEqual(observation.dispatchTrace.ownershipDecisions.count, 2)
            XCTAssertEqual(observation.dispatchTrace.ownershipDecisions.map(\.owner), [.nativeTextEditor, .application])
            XCTAssertEqual(observation.dispatchTrace.targetActions, observation.invocationReceipt.targetAction.map { [$0] } ?? [])
            XCTAssertEqual(observation.dispatchTrace.results, [observation.invocationReceipt.result])
            let claiming = observation.dispatchTrace.ownershipDecisions.filter { $0.decision == .claimed }
            XCTAssertEqual(claiming.count, observation.outcome.invocation == .invoked ? 1 : 0)
            if case .completed(let resultID) = observation.invocationReceipt.result {
                XCTAssertEqual(resultID, expectedResultID(for: try XCTUnwrap(observation.outcome.command)))
            }
        }

        let result = try audit(observations)
        XCTAssertEqual(result.report.matrix.requiredCount, observations.count)
        XCTAssertEqual(result.report.matrix.assertionOnlyCount, observations.count)
        XCTAssertEqual(result.report.matrix.invalidCount, 0)
        XCTAssertEqual(result.report.matrix.mismatchCount, 0)
        XCTAssertEqual(result.receipt.assertionOnlyObservationCount, observations.count)
        XCTAssertEqual(result.receipt.completeMeasuredObservationCount, 0)
    }

    func testEveryEvidenceOriginKeepsMeasuredAndAssertionCoverageDistinct() throws {
        for origin in [Audit.EvidenceOrigin.designSpecification, .callerAssertion] {
            let assertion = try assertionObservation(for: applicationSpecs()[0], contextID: .empty)
            let changed = replacing(
                assertion,
                provenance: Audit.EvidenceProvenance(
                    origin: origin,
                    sourceID: id("source.\(origin.rawValue)")
                )
            )
            let result = try audit([changed])
            XCTAssertEqual(cell(result, key: changed.key).statuses, [.assertionOnly], origin.rawValue)
            XCTAssertEqual(result.receipt.assertionOnlyObservationCount, 1, origin.rawValue)
            XCTAssertEqual(result.receipt.completeMeasuredObservationCount, 0, origin.rawValue)
        }

        for origin in [Audit.EvidenceOrigin.automatedMeasurement, .manualMeasurement] {
            let fixture = try singleMeasuredFixture(origin: origin)
            let result = try audit(
                [fixture.observation],
                trust: fixture.trust,
                resolver: streamingResolver([fixture.digest: fixture.capture])
            )
            XCTAssertEqual(cell(result, key: fixture.observation.key).status, .complete, origin.rawValue)
            XCTAssertEqual(result.receipt.assertionOnlyObservationCount, 0, origin.rawValue)
            XCTAssertEqual(result.receipt.completeMeasuredObservationCount, 1, origin.rawValue)
        }
    }

    func testCompleteSignedMeasurementsBindBuildInventoryCaptureAndCollector() throws {
        let fixture = try measuredFixture()
        let result = try audit(
            fixture.observations,
            trust: fixture.trust,
            resolver: streamingResolver(fixture.captures)
        )
        let count = fixture.observations.count
        XCTAssertEqual(result.report.formatVersion, 3)
        XCTAssertEqual(result.report.inventoryRevision, 3)
        XCTAssertEqual(result.report.matrix.requiredCount, count)
        XCTAssertEqual(result.report.matrix.completeCount, count)
        XCTAssertEqual(result.report.matrix.invalidCount, 0)
        XCTAssertEqual(result.report.matrix.mismatchCount, 0)
        XCTAssertEqual(result.report.matrix.cells.map(\.status), Array(repeating: .complete, count: count))
        XCTAssertEqual(result.receipt.requiredObservationCount, count)
        XCTAssertEqual(result.receipt.completeMeasuredObservationCount, count)
        XCTAssertEqual(result.receipt.assertionOnlyObservationCount, 0)
        XCTAssertTrue(
            result.report.hasMeasuredProductionCoverage,
            String(
                describing: result.report.findings.map {
                    "\($0.code.rawValue):\($0.bindingID?.rawValue ?? "-"):\($0.contextID?.rawValue ?? "-")"
                }
            ) + "\n" + commandStateMismatches().joined(separator: "\n")
        )
    }

    func testTrustFailuresAreReportedBeforeCaptureResolver() throws {
        let fixture = try singleMeasuredFixture()
        let observation = fixture.observation
        let measurement = try XCTUnwrap(observation.provenance.measurement)
        let mutations: [(Audit.FindingCode, Audit.MeasurementProvenance)] = [
            (
                .measuredBuildMismatch,
                measurementCopy(measurement, build: revision("other-build", 1))
            ),
            (
                .measuredArtifactMismatch,
                measurementCopy(measurement, executableArtifact: digest(0xFE))
            ),
            (
                .untrustedMeasurementCollector,
                measurementCopy(measurement, collector: revision("other-collector", 1))
            ),
            (
                .measuredInventoryMismatch,
                measurementCopy(measurement, inventoryRevision: measurement.inventoryRevision + 1)
            ),
            (
                .measurementCaptureMismatch,
                measurementCopy(measurement, measurementArtifact: digest(0xFD))
            ),
            (
                .measurementSignatureMismatch,
                measurementCopy(measurement, captureSignature: [UInt8](repeating: 0, count: 64))
            )
        ]

        for (code, changedMeasurement) in mutations {
            let probe = InvocationProbe()
            let changed = replacing(
                observation,
                provenance: Audit.EvidenceProvenance(
                    origin: observation.provenance.origin,
                    sourceID: observation.provenance.sourceID,
                    measurement: changedMeasurement
                )
            )
            let result = try audit(
                [changed],
                trust: fixture.trust,
                resolver: { _, _, _, _ in probe.record() }
            )
            XCTAssertTrue(result.report.findings.contains { $0.code == code }, code.rawValue)
            XCTAssertEqual(cell(result, key: observation.key).status, .invalid, code.rawValue)
            XCTAssertEqual(probe.count, 0, code.rawValue)
        }
    }

    func testMeasuredProvenanceShapeAndTrustAnchorBoundariesFailClosed() throws {
        let fixture = try singleMeasuredFixture()
        let observation = fixture.observation
        let measurement = try XCTUnwrap(observation.provenance.measurement)
        let invalidMeasurements = [
            measurementCopy(measurement, captureID: id("other-capture")),
            measurementCopy(measurement, collector: revision("trusted-shortcut-collector", 0)),
            measurementCopy(measurement, build: revision("production-shortcut-build", 0)),
            measurementCopy(measurement, executableArtifact: Audit.ArtifactDigest(bytes: [1])),
            measurementCopy(measurement, inventoryRevision: 0),
            measurementCopy(measurement, inventoryArtifact: Audit.ArtifactDigest(bytes: [2])),
            measurementCopy(measurement, measurementArtifact: Audit.ArtifactDigest(bytes: [3])),
            measurementCopy(measurement, capturedAtUnixMilliseconds: 0),
            measurementCopy(measurement, runNonce: [UInt8](repeating: 4, count: 15)),
            measurementCopy(measurement, captureSignature: [UInt8](repeating: 5, count: 63))
        ]
        for (index, invalid) in invalidMeasurements.enumerated() {
            let probe = InvocationProbe()
            let changed = replacing(
                observation,
                provenance: Audit.EvidenceProvenance(
                    origin: .automatedMeasurement,
                    sourceID: observation.provenance.sourceID,
                    measurement: invalid
                )
            )
            let result = try audit(
                [changed],
                trust: fixture.trust,
                resolver: { _, _, _, _ in probe.record() }
            )
            XCTAssertEqual(cell(result, key: observation.key).status, .invalid, "case \(index)")
            XCTAssertTrue(
                result.report.findings.contains { $0.code == .invalidMeasuredProvenance },
                "case \(index)"
            )
            XCTAssertEqual(probe.count, 0, "case \(index)")
        }

        let noTrustProbe = InvocationProbe()
        let noTrust = try audit(
            [observation],
            resolver: { _, _, _, _ in noTrustProbe.record() }
        )
        XCTAssertTrue(noTrust.report.findings.contains { $0.code == .measurementTrustMissing })
        XCTAssertEqual(noTrustProbe.count, 0)

        let staleTrusts = [
            trustCopy(fixture.trust, inventoryRevision: fixture.trust.inventoryRevision + 1),
            trustCopy(fixture.trust, inventoryArtifact: digest(0xB1))
        ]
        for trust in staleTrusts {
            let probe = InvocationProbe()
            let result = try audit(
                [observation],
                trust: trust,
                resolver: { _, _, _, _ in probe.record() }
            )
            XCTAssertTrue(result.report.findings.contains { $0.code == .measuredInventoryMismatch })
            XCTAssertEqual(probe.count, 0)
        }

        let collector = fixture.trust.trustedCollectors[0]
        let wrongRevision = Audit.TrustedCollector(
            collector: revision(collector.collector.id.rawValue, collector.collector.revision + 1),
            signingPublicKey: collector.signingPublicKey
        )
        let untrusted = try audit(
            [observation],
            trust: trustCopy(fixture.trust, trustedCollectors: [wrongRevision])
        )
        XCTAssertTrue(untrusted.report.findings.contains { $0.code == .untrustedMeasurementCollector })

        let wrongKey = Audit.TrustedCollector(
            collector: collector.collector,
            signingPublicKey: Array(try signingKey(0x24).publicKey.rawRepresentation)
        )
        let invalidSignature = try audit(
            [observation],
            trust: trustCopy(fixture.trust, trustedCollectors: [wrongKey])
        )
        XCTAssertTrue(invalidSignature.report.findings.contains { $0.code == .measurementSignatureMismatch })

        assertAuditError(.invalidInventory(field: "measurementTrust.collectors")) {
            try audit(
                [observation],
                trust: trustCopy(fixture.trust, trustedCollectors: [collector, collector])
            )
        }
        assertAuditError(.invalidInventory(field: "measurementTrust.collectors")) {
            try audit(
                [observation],
                trust: trustCopy(
                    fixture.trust,
                    trustedCollectors: [
                        Audit.TrustedCollector(
                            collector: collector.collector,
                            signingPublicKey: [0]
                        )
                    ]
                )
            )
        }
        assertAuditError(.invalidEvidence(field: "measurement.captureID")) {
            let invalidID = measurementCopy(measurement, captureID: id("invalid id"))
            _ = try audit(
                [
                    replacing(
                        observation,
                        provenance: Audit.EvidenceProvenance(
                            origin: .automatedMeasurement,
                            sourceID: observation.provenance.sourceID,
                            measurement: invalidID
                        )
                    )
                ],
                trust: fixture.trust
            )
        }
    }

    func testEvidenceFieldMismatchesAreIndependentAndSkipCaptureResolution() throws {
        let fixture = try singleMeasuredFixture()
        let observation = fixture.observation
        let otherChord = try parseChord("command+o")
        let invalidOutcome = Audit.Outcome(
            owner: .none,
            command: nil,
            isEnabled: false,
            invocation: .unhandled
        )
        let invalidReceipt = Audit.InvocationReceipt(
            source: .menuItem,
            targetAction: observation.invocationReceipt.targetAction,
            result: observation.invocationReceipt.result
        )
        let invalidTrace = Audit.DispatchTrace(
            canonicalChord: observation.dispatchTrace.canonicalChord,
            ownershipDecisions: Array(observation.dispatchTrace.ownershipDecisions.reversed()),
            targetActions: observation.dispatchTrace.targetActions,
            results: observation.dispatchTrace.results
        )
        let mutations: [(Audit.FindingCode, Audit.Observation)] = [
            (.shortcutMismatch, replacing(observation, shortcut: menuShortcut(otherChord))),
            (.contextMismatch, replacing(observation, context: try requiredContext(.disabled))),
            (.invocationReceiptMismatch, replacing(observation, invocationReceipt: invalidReceipt)),
            (.dispatchTraceMismatch, replacing(observation, dispatchTrace: invalidTrace)),
            (.outcomeMismatch, replacing(observation, outcome: invalidOutcome))
        ]
        for (expectedCode, changed) in mutations {
            let probe = InvocationProbe()
            let result = try audit(
                [changed],
                trust: fixture.trust,
                resolver: { _, _, _, _ in probe.record() }
            )
            let matchingFindings = result.report.findings.filter {
                $0.bindingID == observation.key.bindingID
                    && $0.contextID == observation.key.contextID
                    && $0.code == expectedCode
            }
            XCTAssertEqual(matchingFindings.count, 1, expectedCode.rawValue)
            XCTAssertEqual(cell(result, key: observation.key).statuses, [.mismatched, .invalid])
            XCTAssertEqual(probe.count, 0, expectedCode.rawValue)
        }
    }

    func testCaptureStreamingCancellationAndResourceFailuresRemainDistinct() throws {
        let fixture = try singleMeasuredFixture()
        let valid = try audit(
            [fixture.observation],
            trust: fixture.trust,
            resolver: streamingResolver([fixture.digest: fixture.capture], chunkSize: 7)
        )
        XCTAssertEqual(cell(valid, key: fixture.observation.key).status, .complete)

        var corrupted = fixture.capture
        corrupted[corrupted.startIndex] ^= 0x01
        let mismatch = try audit(
            [fixture.observation],
            trust: fixture.trust,
            resolver: streamingResolver([fixture.digest: corrupted], chunkSize: 11)
        )
        XCTAssertTrue(mismatch.report.findings.contains { $0.code == .measurementCaptureMismatch })

        let oversized = try audit(
            [fixture.observation],
            trust: fixture.trust,
            resolver: { _, _, _, stream in
                try stream.append(fixture.capture)
                try stream.append(Data([0]))
            }
        )
        XCTAssertTrue(oversized.report.findings.contains { $0.code == .measurementCaptureMismatch })

        enum ResourceError: Error { case unavailable }
        let unavailable = try audit(
            [fixture.observation],
            trust: fixture.trust,
            resolver: { _, _, _, _ in throw ResourceError.unavailable }
        )
        XCTAssertTrue(unavailable.report.findings.contains { $0.code == .measurementCaptureUnavailable })

        assertAuditError(.cancelled) {
            try audit(
                [fixture.observation],
                trust: fixture.trust,
                resolver: { _, _, _, _ in throw CancellationError() }
            )
        }
        assertAuditError(.cancelled) {
            try audit(
                [fixture.observation],
                trust: fixture.trust,
                resolver: { _, _, cancellationCheck, stream in
                    try stream.append(fixture.capture.prefix(fixture.capture.count / 2))
                    XCTAssertFalse(cancellationCheck())
                    throw Audit.AuditError.cancelled
                }
            )
        }
    }

    func testCaptureResolverContractTracksExactLimitPartialDataAndFinishCancellation() throws {
        let fixture = try singleMeasuredFixture()
        let observation = fixture.observation
        let maximumProbe = LockedValue<Int?>(nil)
        let valid = try audit(
            [observation],
            trust: fixture.trust,
            resolver: { _, maximum, _, stream in
                maximumProbe.set(maximum)
                try stream.append(fixture.capture)
            }
        )
        XCTAssertEqual(maximumProbe.value, fixture.capture.count)
        XCTAssertEqual(cell(valid, key: observation.key).status, .complete)

        let cases: [(String, Audit.CaptureResolver)] = [
            (
                "partial",
                { _, _, _, stream in
                    try stream.append(fixture.capture.dropLast())
                }
            ),
            (
                "empty",
                { _, _, _, _ in }
            )
        ]
        for (name, resolver) in cases {
            let result = try audit([observation], trust: fixture.trust, resolver: resolver)
            let cell = cell(result, key: observation.key)
            XCTAssertEqual(cell.statuses, [.invalid], name)
            XCTAssertNil(cell.observedOutcome, name)
            XCTAssertEqual(result.report.matrix.completeCount, 0, name)
            XCTAssertFalse(result.report.hasMeasuredProductionCoverage, name)
            XCTAssertEqual(
                Set(result.report.findings.map(\.code)),
                [.measurementCaptureMismatch, .missingObservation],
                name
            )
        }

        let checks = InvocationProbe()
        assertAuditError(.cancelled) {
            try Audit.audit(
                evidence: Audit.Evidence(inventoryRevision: 3, observations: [observation]),
                measurementTrust: fixture.trust,
                captureResolver: { _, _, cancellationCheck, stream in
                    while !cancellationCheck() {
                        checks.record()
                    }
                    try stream.append(fixture.capture)
                },
                cancellationCheck: { checks.count >= 2 }
            )
        }
    }

    func testDuplicateIDsCoordinatesAndAssertionInvalidStatusesRemainIndependent() throws {
        let first = try assertionObservation(for: applicationSpecs()[0], contextID: .empty)
        let second = try assertionObservation(for: applicationSpecs()[0], contextID: .disabled)

        let duplicateCoordinate = replacing(first, id: id("other-observation"))
        let duplicateResult = try audit([first, duplicateCoordinate])
        XCTAssertEqual(cell(duplicateResult, key: first.key).status, .duplicate)
        XCTAssertEqual(cell(duplicateResult, key: first.key).statuses, [.duplicate, .assertionOnly])
        XCTAssertEqual(cell(duplicateResult, key: first.key).evidenceCount, 2)

        let duplicateID = replacing(second, id: first.id)
        let duplicateIDResult = try audit([first, duplicateID])
        XCTAssertEqual(cell(duplicateIDResult, key: first.key).statuses, [.invalid, .assertionOnly])
        XCTAssertEqual(cell(duplicateIDResult, key: second.key).statuses, [.invalid, .assertionOnly])
        XCTAssertTrue(duplicateIDResult.report.findings.contains { $0.code == .duplicateObservationID })
        XCTAssertFalse(duplicateIDResult.report.findings.contains { $0.code == .duplicateObservation })

        let malformedMeasured = replacing(
            first,
            provenance: Audit.EvidenceProvenance(
                origin: .automatedMeasurement,
                sourceID: id("measured-source")
            )
        )
        let mixed = try audit([malformedMeasured, second])
        XCTAssertEqual(cell(mixed, key: first.key).statuses, [.invalid])
        XCTAssertEqual(cell(mixed, key: second.key).statuses, [.assertionOnly])
        XCTAssertEqual(mixed.report.matrix.invalidCount, 1)
        XCTAssertEqual(mixed.report.matrix.assertionOnlyCount, 1)
        XCTAssertEqual(mixed.receipt.completeMeasuredObservationCount, 0)
        XCTAssertEqual(mixed.receipt.assertionOnlyObservationCount, 1)
    }

    func testStaleMissingAndUnexpectedEvidenceRemainIndependent() throws {
        let observation = try assertionObservation(for: applicationSpecs()[0], contextID: .empty)
        let stale = try Audit.audit(
            evidence: Audit.Evidence(inventoryRevision: 2, observations: [observation]),
            cancellationCheck: { false }
        )
        XCTAssertEqual(stale.report.findings.filter { $0.code == .staleEvidence }.count, 1)
        XCTAssertEqual(cell(stale, key: observation.key).statuses, [.assertionOnly])

        let missing = try audit([])
        XCTAssertEqual(missing.report.matrix.missingCount, missing.report.matrix.requiredCount)
        XCTAssertEqual(
            missing.report.findings.filter { $0.code == .missingObservation }.count,
            missing.report.matrix.requiredCount
        )

        let unexpectedKey = Audit.MatrixKey(bindingID: id("unexpected-binding"), contextID: .empty)
        let unexpected = replacing(observation, id: id("unexpected-observation"), key: unexpectedKey)
        let unexpectedResult = try audit([unexpected])
        XCTAssertEqual(
            unexpectedResult.report.findings.filter { $0.code == .unexpectedObservation }.count,
            1
        )
        XCTAssertEqual(
            unexpectedResult.report.findings.first { $0.code == .unexpectedObservation }?.bindingID,
            unexpectedKey.bindingID
        )
    }

    func testCanonicalInventoryArtifactAndOrderingAreDeterministic() throws {
        let inventory = Audit.Inventory.canonical
        let artifact = try Audit.inventoryArtifact(for: inventory, cancellationCheck: { false })
        let reordered = Audit.Inventory(
            revision: inventory.revision,
            bindings: inventory.bindings.reversed(),
            nativeBindings: inventory.nativeBindings.reversed()
        )
        let reorderedArtifact = try Audit.inventoryArtifact(for: reordered, cancellationCheck: { false })
        XCTAssertEqual(artifact, reorderedArtifact)
        XCTAssertEqual(artifact.algorithm, .sha256)
        XCTAssertEqual(artifact.bytes.count, SHA256.byteCount)
        XCTAssertEqual(artifact.bytes, try independentInventoryArtifact())
        XCTAssertEqual(hex(artifact.bytes), "e3cf96c1850c9351c0d7fe399405028c29f14607a72e615dc0bc216bfcf37d14")

        XCTAssertEqual(inventory.bindings.map(\.id.rawValue), applicationSpecs().map(\.id))
        XCTAssertEqual(
            inventory.nativeBindings.map(\.id.rawValue),
            try nativeSpecsWithIDs().map(\.id)
        )
    }

    func testInventoryMutationsReportExactApplicationAndNativeDefects() throws {
        let inventory = Audit.Inventory.canonical
        let first = inventory.bindings[0]
        let second = inventory.bindings[1]
        let firstNative = inventory.nativeBindings[0]
        let extra = Audit.Binding(
            id: id("unexpected-binding"),
            command: first.command,
            shortcut: first.shortcut,
            policyChord: first.policyChord,
            winMergeReference: first.winMergeReference,
            policyRequirement: first.policyRequirement,
            focusedEditorReservation: first.focusedEditorReservation,
            invocationTargetAction: first.invocationTargetAction,
            expectedResultID: first.expectedResultID
        )
        let mismatched = Audit.Binding(
            id: first.id,
            command: second.command,
            shortcut: first.shortcut,
            policyChord: first.policyChord,
            winMergeReference: first.winMergeReference,
            policyRequirement: first.policyRequirement,
            focusedEditorReservation: first.focusedEditorReservation,
            invocationTargetAction: first.invocationTargetAction,
            expectedResultID: first.expectedResultID
        )
        let applicationCases: [(Audit.FindingCode, [Audit.Binding])] = [
            (.missingInventoryBinding, Array(inventory.bindings.dropFirst())),
            (.unexpectedInventoryBinding, inventory.bindings + [extra]),
            (.duplicateInventoryBinding, inventory.bindings + [first]),
            (.duplicateInventoryChord, inventory.bindings + [extra]),
            (.inventoryBindingMismatch, [mismatched] + Array(inventory.bindings.dropFirst()))
        ]
        for (code, bindings) in applicationCases {
            let result = try Audit.audit(
                inventory: Audit.Inventory(
                    revision: inventory.revision,
                    bindings: bindings,
                    nativeBindings: inventory.nativeBindings
                ),
                policy: try Policy.makeUnfinishedAudit(cancellationCheck: {}),
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                cancellationCheck: { false }
            )
            XCTAssertTrue(result.report.findings.contains { $0.code == code }, code.rawValue)
        }

        let mismatchedNative = Audit.NativeBinding(
            id: firstNative.id,
            shortcut: firstNative.shortcut,
            policyChord: firstNative.policyChord,
            reservation: Audit.NativeReservationRequirement(
                command: .copy,
                applicability: firstNative.reservation.applicability
            ),
            invocationTargetAction: firstNative.invocationTargetAction,
            expectedResultID: firstNative.expectedResultID
        )
        let nativeCases: [(Audit.FindingCode, [Audit.NativeBinding])] = [
            (.missingInventoryBinding, Array(inventory.nativeBindings.dropFirst())),
            (.duplicateInventoryBinding, inventory.nativeBindings + [firstNative]),
            (
                .inventoryBindingMismatch,
                [mismatchedNative] + Array(inventory.nativeBindings.dropFirst())
            )
        ]
        for (code, nativeBindings) in nativeCases {
            let result = try Audit.audit(
                inventory: Audit.Inventory(
                    revision: inventory.revision,
                    bindings: inventory.bindings,
                    nativeBindings: nativeBindings
                ),
                policy: try Policy.makeUnfinishedAudit(cancellationCheck: {}),
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                cancellationCheck: { false }
            )
            XCTAssertTrue(result.report.findings.contains { $0.code == code }, code.rawValue)
        }
    }

    func testPolicyAndTrustFingerprintsBindContentButNotCallerOrder() throws {
        let evidence = Array(try assertionObservations().prefix(3))
        let inventoryArtifact = try Audit.inventoryArtifact(for: .canonical, cancellationCheck: { false })
        let key1 = try signingKey(0x11)
        let key2 = try signingKey(0x22)
        let collector1 = Audit.TrustedCollector(
            collector: revision("collector-a", 1),
            signingPublicKey: Array(key1.publicKey.rawRepresentation)
        )
        let collector2 = Audit.TrustedCollector(
            collector: revision("collector-b", 2),
            signingPublicKey: Array(key2.publicKey.rawRepresentation)
        )
        let trust = Audit.MeasurementTrust(
            build: revision("build", 3),
            executableArtifact: digest(0xA1),
            inventoryRevision: 3,
            inventoryArtifact: inventoryArtifact,
            trustedCollectors: [collector1, collector2]
        )
        let reversedTrust = Audit.MeasurementTrust(
            build: trust.build,
            executableArtifact: trust.executableArtifact,
            inventoryRevision: trust.inventoryRevision,
            inventoryArtifact: trust.inventoryArtifact,
            trustedCollectors: [collector2, collector1]
        )
        let baseline = try audit(evidence, trust: trust)
        let reordered = try Audit.audit(
            inventory: Audit.Inventory(
                revision: 3,
                bindings: Audit.Inventory.canonical.bindings.reversed(),
                nativeBindings: Audit.Inventory.canonical.nativeBindings.reversed()
            ),
            policy: try Policy.makeUnfinishedAudit(cancellationCheck: {}),
            evidence: Audit.Evidence(inventoryRevision: 3, observations: evidence.reversed()),
            measurementTrust: reversedTrust,
            cancellationCheck: { false }
        )
        XCTAssertEqual(reordered.receipt.inventoryFingerprint, baseline.receipt.inventoryFingerprint)
        XCTAssertEqual(reordered.receipt.policyFingerprint, baseline.receipt.policyFingerprint)
        XCTAssertEqual(reordered.receipt.matrixFingerprint, baseline.receipt.matrixFingerprint)
        XCTAssertEqual(reordered.receipt.evidenceFingerprint, baseline.receipt.evidenceFingerprint)
        XCTAssertEqual(reordered.receipt.findingFingerprint, baseline.receipt.findingFingerprint)
        XCTAssertEqual(reordered.report, baseline.report)

        let changedTrust = Audit.MeasurementTrust(
            build: revision("build", 4),
            executableArtifact: trust.executableArtifact,
            inventoryRevision: trust.inventoryRevision,
            inventoryArtifact: trust.inventoryArtifact,
            trustedCollectors: trust.trustedCollectors
        )
        let trustChanged = try audit(evidence, trust: changedTrust)
        XCTAssertNotEqual(trustChanged.receipt.evidenceFingerprint, baseline.receipt.evidenceFingerprint)
        XCTAssertEqual(trustChanged.receipt.inventoryFingerprint, baseline.receipt.inventoryFingerprint)

        let changedPolicy = try Policy.makeUnfinishedAudit(
            limits: Policy.Limits(maximumWork: Policy.Limits.default.maximumWork + 1),
            cancellationCheck: {}
        )
        let policyChanged = try Audit.audit(
            inventory: .canonical,
            policy: changedPolicy,
            evidence: Audit.Evidence(inventoryRevision: 3, observations: evidence),
            measurementTrust: trust,
            cancellationCheck: { false }
        )
        XCTAssertNotEqual(policyChanged.receipt.policyFingerprint, baseline.receipt.policyFingerprint)
        XCTAssertEqual(policyChanged.receipt.evidenceFingerprint, baseline.receipt.evidenceFingerprint)
    }

    func testCaptureAndSignaturePayloadsHaveExactFramingAndByteLimits() throws {
        let assertion = try assertionObservation(for: applicationSpecs()[0], contextID: .empty)
        let capture = try Audit.canonicalCaptureData(for: assertion, cancellationCheck: { false })
        XCTAssertEqual(capture, independentCaptureData(for: assertion))
        XCTAssertEqual(
            try Audit.canonicalCaptureData(
                for: assertion,
                maximumBytes: capture.count,
                cancellationCheck: { false }
            ),
            capture
        )
        assertAuditError(.captureTooLarge(maximumBytes: capture.count - 1)) {
            try Audit.canonicalCaptureData(
                for: assertion,
                maximumBytes: capture.count - 1,
                cancellationCheck: { false }
            )
        }

        let fixture = try singleMeasuredFixture()
        let payload = try Audit.signaturePayload(for: fixture.observation, cancellationCheck: { false })
        let expectedPayload = Data(
            (frame("org.macmerge.shortcut-coverage.signature")
                + frame("2")
                + frame("sha256:" + hex(fixture.digest.bytes))).utf8
        )
        XCTAssertEqual(payload, expectedPayload)
        XCTAssertEqual(
            try Audit.signaturePayload(
                for: fixture.observation,
                maximumBytes: payload.count,
                cancellationCheck: { false }
            ),
            payload
        )
        assertAuditError(.captureTooLarge(maximumBytes: payload.count - 1)) {
            try Audit.signaturePayload(
                for: fixture.observation,
                maximumBytes: payload.count - 1,
                cancellationCheck: { false }
            )
        }
        assertAuditError(.invalidLimit(.captureBytes)) {
            try Audit.canonicalCaptureData(
                for: assertion,
                maximumBytes: Audit.Limits.hardMaximumCaptureBytes + 1
            )
        }
        assertAuditError(.cancelled) {
            try Audit.canonicalCaptureData(for: assertion, cancellationCheck: { true })
        }
    }

    func testIndependentCaptureSerializerDetectsEveryBoundFieldMutation() throws {
        let fixture = try singleMeasuredFixture()
        let observation = fixture.observation
        let measurement = try XCTUnwrap(observation.provenance.measurement)
        let alternateContext = try requiredContext(.disabled)
        let alternateChord = try parseChord("command+o")
        let alternateTarget = expectedTargetAction(
            for: Audit.RoutedCommand.application(.comparison(.openComparison))
        )
        let alternateResult = MenuCommandResult.completed(
            expectedResultID(for: .application(.comparison(.openComparison)))
        )
        let alternateOutcome = Audit.Outcome(
            owner: .none,
            command: nil,
            isEnabled: false,
            invocation: .unhandled
        )
        let alternateReceipt = Audit.InvocationReceipt(
            source: .menuItem,
            targetAction: alternateTarget,
            result: alternateResult
        )
        let alternateTrace = Audit.DispatchTrace(
            canonicalChord: alternateChord,
            ownershipDecisions: [
                Audit.OwnershipDecision(
                    owner: .application,
                    command: .application(.comparison(.openComparison)),
                    decision: .claimed
                )
            ],
            targetActions: [alternateTarget],
            results: [alternateResult]
        )
        let provenance: (Audit.MeasurementProvenance) -> Audit.EvidenceProvenance = {
            Audit.EvidenceProvenance(
                origin: observation.provenance.origin,
                sourceID: observation.provenance.sourceID,
                measurement: $0
            )
        }
        let mutations: [(String, Audit.Observation)] = [
            ("id", replacing(observation, id: id("alternate-observation"))),
            (
                "key.bindingID",
                replacing(
                    observation,
                    key: Audit.MatrixKey(bindingID: id("alternate-binding"), contextID: observation.key.contextID)
                )
            ),
            (
                "key.contextID",
                replacing(
                    observation,
                    key: Audit.MatrixKey(bindingID: observation.key.bindingID, contextID: .disabled)
                )
            ),
            ("shortcut", replacing(observation, shortcut: menuShortcut(alternateChord))),
            (
                "hardwareKeyCapture",
                replacing(
                    observation,
                    hardwareKeyCapture: Audit.HardwareKeyCapture(
                        hardwareKeyCode: 31,
                        inputSourceID: id("alternate-input-source"),
                        charactersIgnoringModifiers: "o",
                        rawModifierFlags: modifierFlag(.command) | modifierFlag(.shift)
                    )
                )
            ),
            ("context", replacing(observation, context: alternateContext)),
            ("outcome", replacing(observation, outcome: alternateOutcome)),
            ("invocationReceipt", replacing(observation, invocationReceipt: alternateReceipt)),
            ("dispatchTrace", replacing(observation, dispatchTrace: alternateTrace)),
            (
                "provenance.origin",
                replacing(
                    observation,
                    provenance: Audit.EvidenceProvenance(
                        origin: .manualMeasurement,
                        sourceID: observation.provenance.sourceID,
                        measurement: measurement
                    )
                )
            ),
            (
                "provenance.sourceID",
                replacing(
                    observation,
                    provenance: Audit.EvidenceProvenance(
                        origin: observation.provenance.origin,
                        sourceID: id("alternate-source"),
                        measurement: measurement
                    )
                )
            ),
            (
                "provenance.captureID",
                replacing(observation, provenance: provenance(measurementCopy(measurement, captureID: id("other-capture"))))
            ),
            (
                "provenance.collector",
                replacing(
                    observation,
                    provenance: provenance(
                        measurementCopy(measurement, collector: revision("other-collector", 8))
                    )
                )
            ),
            (
                "provenance.build",
                replacing(
                    observation,
                    provenance: provenance(measurementCopy(measurement, build: revision("other-build", 42)))
                )
            ),
            (
                "provenance.executableArtifact",
                replacing(
                    observation,
                    provenance: provenance(measurementCopy(measurement, executableArtifact: digest(0xA2)))
                )
            ),
            (
                "provenance.inventoryRevision",
                replacing(
                    observation,
                    provenance: provenance(
                        measurementCopy(measurement, inventoryRevision: measurement.inventoryRevision + 1)
                    )
                )
            ),
            (
                "provenance.inventoryArtifact",
                replacing(
                    observation,
                    provenance: provenance(measurementCopy(measurement, inventoryArtifact: digest(0xA3)))
                )
            ),
            (
                "provenance.capturedAt",
                replacing(
                    observation,
                    provenance: provenance(
                        measurementCopy(
                            measurement,
                            capturedAtUnixMilliseconds: measurement.capturedAtUnixMilliseconds + 1
                        )
                    )
                )
            ),
            (
                "provenance.nonce",
                replacing(
                    observation,
                    provenance: provenance(measurementCopy(measurement, runNonce: nonce(99)))
                )
            )
        ]

        XCTAssertEqual(fixture.capture, independentCaptureData(for: observation))
        let baseline = try audit(
            [observation],
            trust: fixture.trust,
            resolver: streamingResolver([fixture.digest: fixture.capture])
        )
        XCTAssertEqual(cell(baseline, key: observation.key).status, .complete)
        let captureMismatchFields: Set<String> = [
            "key.contextID", "shortcut", "hardwareKeyCapture", "context", "outcome",
            "invocationReceipt", "dispatchTrace", "provenance.origin", "provenance.sourceID",
            "provenance.capturedAt", "provenance.nonce"
        ]
        for (field, changed) in mutations {
            let independentlySerialized = independentCaptureData(for: changed)
            XCTAssertNotEqual(independentlySerialized, fixture.capture, field)
            XCTAssertEqual(try Audit.canonicalCaptureData(for: changed), independentlySerialized, field)
            let result = try audit(
                [changed],
                trust: fixture.trust,
                resolver: streamingResolver([fixture.digest: fixture.capture])
            )
            XCTAssertFalse(result.report.hasMeasuredProductionCoverage, field)
            if captureMismatchFields.contains(field) {
                XCTAssertTrue(
                    result.report.findings.contains { $0.code == .measurementCaptureMismatch },
                    field
                )
            }
        }
        XCTAssertEqual(
            try Audit.canonicalCaptureData(
                for: replacing(
                    observation,
                    provenance: Audit.EvidenceProvenance(
                        origin: observation.provenance.origin,
                        sourceID: observation.provenance.sourceID,
                        measurement: measurementCopy(measurement, measurementArtifact: digest(0xF0))
                    )
                )
            ),
            fixture.capture,
            "measurement artifact is signature-bound, not recursively capture-bound"
        )
        XCTAssertEqual(
            try Audit.canonicalCaptureData(
                for: replacing(
                    observation,
                    provenance: provenance(
                        measurementCopy(measurement, captureSignature: [UInt8](repeating: 1, count: 64))
                    )
                )
            ),
            fixture.capture,
            "signature bytes are not recursively capture-bound"
        )
    }

    func testStringCountFindingAndConfiguredLimitsFailAtExactBoundaries() throws {
        let hardCases: [(Audit.Limit, Audit.Limits)] = [
            (.bindings, limits(maximumBindings: Audit.Limits.hardMaximumBindings + 1)),
            (.contexts, limits(maximumContexts: Audit.Limits.hardMaximumContexts + 1)),
            (
                .trustedCollectors,
                limits(maximumTrustedCollectors: Audit.Limits.hardMaximumTrustedCollectors + 1)
            ),
            (.observations, limits(maximumObservations: Audit.Limits.hardMaximumObservations + 1)),
            (.findings, limits(maximumFindings: Audit.Limits.hardMaximumFindings + 1)),
            (
                .stringUTF8Bytes,
                limits(maximumStringUTF8Bytes: Audit.Limits.hardMaximumStringUTF8Bytes + 1)
            ),
            (
                .totalStringUTF8Bytes,
                limits(maximumTotalStringUTF8Bytes: Audit.Limits.hardMaximumTotalStringUTF8Bytes + 1)
            ),
            (.captureBytes, limits(maximumCaptureBytes: Audit.Limits.hardMaximumCaptureBytes + 1)),
            (.workUnits, limits(maximumWorkUnits: Audit.Limits.hardMaximumWorkUnits + 1)),
            (
                .cancellationCheckInterval,
                limits(cancellationCheckInterval: Audit.Limits.hardMaximumCancellationCheckInterval + 1)
            )
        ]
        XCTAssertEqual(Set(hardCases.map(\.0)), Set(Audit.Limit.allCases))
        for (limit, value) in hardCases {
            assertAuditError(.invalidLimit(limit)) {
                try Audit.audit(
                    evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                    limits: value,
                    cancellationCheck: { false }
                )
            }
        }

        assertAuditError(.countLimitExceeded(.bindings, maximum: 0)) {
            try Audit.audit(
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                limits: limits(maximumBindings: 0),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.countLimitExceeded(.contexts, maximum: 0)) {
            try Audit.audit(
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                limits: limits(maximumContexts: 0),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.stringTooLarge(field: "binding.id", maximumUTF8Bytes: 0)) {
            try Audit.audit(
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                limits: limits(maximumStringUTF8Bytes: 0),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.totalStringsTooLarge(maximumUTF8Bytes: 0)) {
            try Audit.audit(
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                limits: limits(maximumTotalStringUTF8Bytes: 0),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.findingLimitExceeded(maximum: 0)) {
            try Audit.audit(
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                limits: limits(maximumFindings: 0),
                cancellationCheck: { false }
            )
        }
    }

    func testLimitLowerBoundsRuntimeCapsAndCancellationPrecedenceAreExact() throws {
        let invalidLowerBounds: [(Audit.Limit, Audit.Limits)] = [
            (.bindings, limits(maximumBindings: -1)),
            (.contexts, limits(maximumContexts: -1)),
            (.trustedCollectors, limits(maximumTrustedCollectors: -1)),
            (.observations, limits(maximumObservations: -1)),
            (.findings, limits(maximumFindings: -1)),
            (.stringUTF8Bytes, limits(maximumStringUTF8Bytes: -1)),
            (.totalStringUTF8Bytes, limits(maximumTotalStringUTF8Bytes: -1)),
            (.captureBytes, limits(maximumCaptureBytes: -1)),
            (.workUnits, limits(maximumWorkUnits: 0)),
            (.cancellationCheckInterval, limits(cancellationCheckInterval: 0))
        ]
        for (limit, value) in invalidLowerBounds {
            assertAuditError(.invalidLimit(limit)) {
                try Audit.audit(
                    evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                    limits: value,
                    cancellationCheck: { false }
                )
            }
        }

        let fixture = try singleMeasuredFixture()
        XCTAssertNoThrow(
            try audit(
                [fixture.observation],
                trust: fixture.trust,
                limits: limits(maximumTrustedCollectors: 1, maximumObservations: 1),
                resolver: streamingResolver([fixture.digest: fixture.capture])
            )
        )
        assertAuditError(.countLimitExceeded(.trustedCollectors, maximum: 0)) {
            try audit(
                [fixture.observation],
                trust: fixture.trust,
                limits: limits(maximumTrustedCollectors: 0)
            )
        }
        assertAuditError(.countLimitExceeded(.observations, maximum: 0)) {
            try audit([fixture.observation], limits: limits(maximumObservations: 0))
        }
        assertAuditError(.cancelled) {
            try Audit.audit(
                evidence: Audit.Evidence(inventoryRevision: 3, observations: []),
                limits: limits(maximumWorkUnits: 1),
                cancellationCheck: { true }
            )
        }
    }

    func testInventoryHashSortingIsBudgetedAndCancellationAware() throws {
        let inventory = Audit.Inventory(
            revision: 3,
            bindings: Audit.Inventory.canonical.bindings.reversed(),
            nativeBindings: Audit.Inventory.canonical.nativeBindings.reversed()
        )
        let minimum = try minimumSuccessfulWork(upper: Audit.Limits.default.maximumWorkUnits) { work in
            try Audit.inventoryArtifact(
                for: inventory,
                limits: limits(maximumWorkUnits: work),
                cancellationCheck: { false }
            )
        }
        XCTAssertGreaterThan(minimum, UInt64(inventory.bindings.count + inventory.nativeBindings.count))
        XCTAssertNoThrow(
            try Audit.inventoryArtifact(
                for: inventory,
                limits: limits(maximumWorkUnits: minimum),
                cancellationCheck: { false }
            )
        )
        assertAuditError(.workLimitExceeded(maximum: minimum - 1)) {
            try Audit.inventoryArtifact(
                for: inventory,
                limits: limits(maximumWorkUnits: minimum - 1),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.cancelled) {
            try Audit.inventoryArtifact(for: inventory, cancellationCheck: { true })
        }
    }

    func testFullAuditWorkBudgetAcceptsMinimumAndRejectsOneLess() throws {
        let evidence = Audit.Evidence(inventoryRevision: 3, observations: [])
        let minimum = try minimumSuccessfulWork(upper: Audit.Limits.default.maximumWorkUnits) { work in
            try Audit.audit(
                evidence: evidence,
                limits: limits(maximumWorkUnits: work),
                cancellationCheck: { false }
            )
        }
        XCTAssertNoThrow(
            try Audit.audit(
                evidence: evidence,
                limits: limits(maximumWorkUnits: minimum),
                cancellationCheck: { false }
            )
        )
        assertAuditError(.workLimitExceeded(maximum: minimum - 1)) {
            try Audit.audit(
                evidence: evidence,
                limits: limits(maximumWorkUnits: minimum - 1),
                cancellationCheck: { false }
            )
        }
        assertAuditError(.cancelled) {
            try Audit.audit(
                evidence: evidence,
                limits: limits(maximumWorkUnits: minimum - 1),
                cancellationCheck: { true }
            )
        }
    }

    func testDescriptionsReflectionAndDumpRedactIDsDigestsKeysAndCaptureData() throws {
        let fixture = try singleMeasuredFixture(
            buildID: "TOP-SECRET-BUILD",
            sourceID: "TOP-SECRET-CAPTURE-SOURCE"
        )
        let result = try audit(
            [fixture.observation],
            trust: fixture.trust,
            resolver: streamingResolver([fixture.digest: fixture.capture])
        )
        let findingResult = try audit([])
        let finding = findingResult.report.findings.first!
        let expectation = try Audit.canonicalMatrix(cancellationCheck: { false })[0]
        let measurement = try XCTUnwrap(fixture.observation.provenance.measurement)
        let values: [Any] = [
            id("TOP-SECRET-STABLE-ID"),
            measurement.build,
            fixture.digest,
            fixture.trust.trustedCollectors[0],
            fixture.trust,
            Audit.Inventory.canonical,
            Audit.Inventory.canonical.bindings[0],
            Audit.Inventory.canonical.nativeBindings[0],
            fixture.observation.context,
            fixture.observation.key,
            expectation,
            fixture.observation.hardwareKeyCapture,
            fixture.observation.invocationReceipt,
            fixture.observation.dispatchTrace,
            measurement,
            fixture.observation.provenance,
            fixture.observation,
            Audit.Evidence(inventoryRevision: 3, observations: [fixture.observation]),
            finding.id,
            finding,
            result.report.matrix.cells[0],
            result.report.matrix,
            findingResult.report,
            result.receipt,
            result.receipt.inventoryFingerprint,
            findingResult
        ]
        let secrets = [
            "TOP-SECRET-STABLE-ID",
            "TOP-SECRET-BUILD",
            "TOP-SECRET-CAPTURE-SOURCE",
            fixture.observation.id.rawValue,
            measurement.captureID.rawValue,
            measurement.collector.id.rawValue,
            hex(measurement.executableArtifact.bytes),
            hex(measurement.inventoryArtifact.bytes),
            hex(fixture.trust.trustedCollectors[0].signingPublicKey),
            hex(measurement.runNonce),
            hex(measurement.captureSignature),
            Data(measurement.captureSignature).base64EncodedString(),
            measurement.captureSignature.map(String.init).joined(separator: ", "),
            fixture.capture.base64EncodedString()
        ]
        for value in values {
            let rendered = diagnostics(value)
            for secret in secrets {
                XCTAssertFalse(rendered.contains(secret), "\(type(of: value)) leaked \(secret)")
            }
        }
        XCTAssertEqual(
            Audit.Report.scopeStatement,
            "Deterministic validation of the canonical unfinished shortcut inventory, command-state matrix, native editor reservations, and caller-supplied build-bound measurements; not independent runtime UI verification."
        )
    }

    func testUnfinishedPolicyKeepsUndoAndRedoIndependentFromDirtyState() throws {
        let expected = try applicationSpecs().compactMap { spec -> PolicyTuple? in
            guard case .comparison(let command) = spec.command else { return nil }
            return PolicyTuple(
                command: command,
                chord: spec.chord,
                states: try XCTUnwrap(spec.states),
                requiresDirty: spec.requiresDirty,
                requiresSelection: spec.requiresSelection,
                allowsReadOnly: spec.allowsReadOnly
            )
        }
        let actual = Policy.unfinishedAuditCommandShortcuts.map {
            PolicyTuple(
                command: $0.command,
                chord: $0.chord.canonicalDescription,
                states: $0.enabledLifecycleStates,
                requiresDirty: $0.requiresDirty,
                requiresSelection: $0.requiresSelection,
                allowsReadOnly: $0.allowsReadOnly
            )
        }
        let initialized = try Policy.makeUnfinishedAudit(cancellationCheck: {}).commandShortcuts.map {
            PolicyTuple(
                command: $0.command,
                chord: $0.chord.canonicalDescription,
                states: $0.enabledLifecycleStates,
                requiresDirty: $0.requiresDirty,
                requiresSelection: $0.requiresSelection,
                allowsReadOnly: $0.allowsReadOnly
            )
        }
        let expectedOrder = expected.sorted { left, right in
            let leftModifiers = independentModifierBits(left.chord)
            let rightModifiers = independentModifierBits(right.chord)
            if leftModifiers != rightModifiers { return leftModifiers < rightModifiers }
            let leftKey = independentKeyOrder(left.chord)
            let rightKey = independentKeyOrder(right.chord)
            if leftKey != rightKey { return leftKey.lexicographicallyPrecedes(rightKey) }
            return left.command.rawValue < right.command.rawValue
        }
        XCTAssertEqual(initialized, expectedOrder)
        XCTAssertEqual(actual.count, expected.count)
        for expectedTuple in expected {
            let actualTuple = try XCTUnwrap(
                actual.first {
                    $0.command == expectedTuple.command && $0.chord == expectedTuple.chord
                }
            )
            XCTAssertEqual(actualTuple.states, expectedTuple.states)
            XCTAssertEqual(actualTuple.requiresSelection, expectedTuple.requiresSelection)
            XCTAssertEqual(actualTuple.allowsReadOnly, expectedTuple.allowsReadOnly)
            if expectedTuple.command == .undo || expectedTuple.command == .redo {
                XCTAssertFalse(
                    actualTuple.requiresDirty,
                    "\(expectedTuple.command.rawValue) availability must follow command state, not dirty state"
                )
            } else {
                XCTAssertEqual(actualTuple.requiresDirty, expectedTuple.requiresDirty)
            }
        }
    }

    func testPolicyConditionsRemainIndependentWhenCommandStateAllowsCommand() throws {
        let chord = try parseChord("command+s")
        let shortcut = Policy.CommandShortcut(
            command: .save,
            chord: chord,
            enabledLifecycleStates: [.different],
            requiresDirty: true,
            requiresSelection: true,
            allowsReadOnly: false
        )
        let policy = try Policy(commandShortcuts: [shortcut], cancellationCheck: {})
        let enabled: Set<Policy.Command> = [.save]
        let contexts: [(Policy.CommandConditionFailure?, Policy.Context)] = [
            (
                nil,
                Policy.Context(
                    lifecycle: .different,
                    isDirty: true,
                    hasSelection: true,
                    isReadOnly: false,
                    enabledCommands: enabled
                )
            ),
            (
                .lifecycle,
                Policy.Context(
                    lifecycle: .equal,
                    isDirty: true,
                    hasSelection: true,
                    isReadOnly: false,
                    enabledCommands: enabled
                )
            ),
            (
                .dirty,
                Policy.Context(
                    lifecycle: .different,
                    isDirty: false,
                    hasSelection: true,
                    isReadOnly: false,
                    enabledCommands: enabled
                )
            ),
            (
                .selection,
                Policy.Context(
                    lifecycle: .different,
                    isDirty: true,
                    hasSelection: false,
                    isReadOnly: false,
                    enabledCommands: enabled
                )
            ),
            (
                .readOnly,
                Policy.Context(
                    lifecycle: .different,
                    isDirty: true,
                    hasSelection: true,
                    isReadOnly: true,
                    enabledCommands: enabled
                )
            )
        ]
        for (failure, context) in contexts {
            let resolution = try policy.resolve(chord, in: context, cancellationCheck: {})
            if let failure {
                XCTAssertEqual(resolution.disabledReason, .commandConditions(.save, failure))
                XCTAssertEqual(resolution.route, .blocked)
            } else {
                XCTAssertEqual(resolution.route, .applicationCommand(.save))
                XCTAssertTrue(resolution.isEnabled)
            }
        }
    }

    func testPolicyCollisionKindsApplicabilityAndMixedOwnershipAreExact() throws {
        let chord = try parseChord("command+k")
        let commands = [
            Policy.CommandShortcut(command: .save, chord: chord),
            Policy.CommandShortcut(command: .openComparison, chord: chord)
        ]
        let reservations = [
            Policy.NativeTextEditingReservation(
                command: .copy,
                chord: chord,
                applicability: .readOnly
            ),
            Policy.NativeTextEditingReservation(
                command: .paste,
                chord: chord,
                applicability: .editable
            )
        ]
        let policy = try Policy(
            commandShortcuts: commands,
            nativeTextEditingReservations: reservations,
            cancellationCheck: {}
        )
        let collision = try XCTUnwrap(policy.collision(for: chord))
        XCTAssertEqual(collision.kinds, [.applicationCommands, .editorFocusReservation])
        XCTAssertEqual(collision.commandShortcutCount, 2)
        XCTAssertEqual(collision.nativeReservationCount, 2)
        XCTAssertFalse(collision.isConditional)

        let readOnly = try policy.resolve(
            chord,
            in: Policy.Context(lifecycle: .different, editorFocus: .readOnly),
            cancellationCheck: {}
        )
        XCTAssertEqual(readOnly.route, .nativeTextEditing(.copy))
        let editable = try policy.resolve(
            chord,
            in: Policy.Context(lifecycle: .different, editorFocus: .editable),
            cancellationCheck: {}
        )
        XCTAssertEqual(editable.route, .nativeTextEditing(.paste))

        let nativeCollision = try Policy(
            commandShortcuts: [],
            nativeTextEditingReservations: [
                Policy.NativeTextEditingReservation(command: .copy, chord: chord),
                Policy.NativeTextEditingReservation(command: .selectAll, chord: chord)
            ],
            cancellationCheck: {}
        )
        XCTAssertEqual(
            nativeCollision.collision(for: chord)?.kinds,
            [.nativeTextEditingReservations]
        )
        let blocked = try nativeCollision.resolve(
            chord,
            in: Policy.Context(lifecycle: .different, editorFocus: .readOnly),
            cancellationCheck: {}
        )
        XCTAssertEqual(blocked.route, .blocked)
    }

    private struct ApplicationSpec {
        let id: String
        let command: Audit.ApplicationCommand
        let chord: String
        let states: Set<Policy.LifecycleState>?
        let requiresDirty: Bool
        let requiresSelection: Bool
        let allowsReadOnly: Bool
        let winMergeKey: String?

        init(
            _ id: String,
            _ command: Audit.ApplicationCommand,
            _ chord: String,
            _ states: Set<Policy.LifecycleState>? = nil,
            dirty: Bool = false,
            selection: Bool = false,
            readOnly: Bool = true,
            winMergeKey: String? = nil
        ) {
            self.id = id
            self.command = command
            self.chord = chord
            self.states = states
            requiresDirty = dirty
            requiresSelection = selection
            allowsReadOnly = readOnly
            self.winMergeKey = winMergeKey
        }
    }

    private struct NativeSpec {
        let command: Policy.NativeTextEditingCommand
        let chord: String
        let applicability: Policy.NativeTextEditingApplicability
    }

    private struct NativeSpecWithID {
        let id: String
        let spec: NativeSpec
    }

    private struct ApplicationProjection: Hashable {
        let id: Audit.StableID
        let command: Audit.ApplicationCommand
        let shortcut: MenuShortcutDescriptor
        let policyChord: Policy.Chord
        let winMergeReference: MenuShortcutDescriptor?
        let policyRequirement: Audit.PolicyRequirement?
        let focusedEditorReservation: Audit.NativeReservationRequirement?
        let invocationTargetAction: MenuTargetAction
        let expectedResultID: MenuValidationResultID

        init(_ binding: Audit.Binding) {
            id = binding.id
            command = binding.command
            shortcut = binding.shortcut
            policyChord = binding.policyChord
            winMergeReference = binding.winMergeReference
            policyRequirement = binding.policyRequirement
            focusedEditorReservation = binding.focusedEditorReservation
            invocationTargetAction = binding.invocationTargetAction
            expectedResultID = binding.expectedResultID
        }
    }

    private struct NativeProjection: Hashable {
        let id: Audit.StableID
        let shortcut: MenuShortcutDescriptor
        let policyChord: Policy.Chord
        let reservation: Audit.NativeReservationRequirement
        let invocationTargetAction: MenuTargetAction
        let expectedResultID: MenuValidationResultID

        init(_ binding: Audit.NativeBinding) {
            id = binding.id
            shortcut = binding.shortcut
            policyChord = binding.policyChord
            reservation = binding.reservation
            invocationTargetAction = binding.invocationTargetAction
            expectedResultID = binding.expectedResultID
        }
    }

    private struct NativeTuple: Hashable {
        let command: Policy.NativeTextEditingCommand
        let chord: String
        let applicability: Policy.NativeTextEditingApplicability
    }

    private struct CollisionProjection: Hashable {
        let chord: String
        let kinds: Set<Policy.CollisionKind>
        let commands: [Policy.Command]
        let nativeCommands: [Policy.NativeTextEditingCommand]
        let commandShortcutCount: Int
        let nativeReservationCount: Int
        let isConditional: Bool

        init(
            chord: String,
            kinds: Set<Policy.CollisionKind>,
            commands: [Policy.Command],
            nativeCommands: [Policy.NativeTextEditingCommand],
            commandShortcutCount: Int,
            nativeReservationCount: Int,
            isConditional: Bool
        ) {
            self.chord = chord
            self.kinds = kinds
            self.commands = commands
            self.nativeCommands = nativeCommands
            self.commandShortcutCount = commandShortcutCount
            self.nativeReservationCount = nativeReservationCount
            self.isConditional = isConditional
        }

        init(_ collision: Policy.Collision) {
            chord = collision.chord.canonicalDescription
            kinds = collision.kinds
            commands = collision.commands
            nativeCommands = collision.nativeTextEditingCommands
            commandShortcutCount = collision.commandShortcutCount
            nativeReservationCount = collision.nativeReservationCount
            isConditional = collision.isConditional
        }
    }

    private struct PolicyTuple: Hashable {
        let command: Policy.Command
        let chord: String
        let states: Set<Policy.LifecycleState>
        let requiresDirty: Bool
        let requiresSelection: Bool
        let allowsReadOnly: Bool
    }

    private struct ContextSummary: Equatable {
        let id: Audit.ContextID
        var commandLifecycle: ComparisonCommandState.ComparisonLifecycle = .currentSuccess
        var policyLifecycle: Policy.LifecycleState = .different
        var keyboardDirty = false
        var hasSelection = false
        var keyboardReadOnly = false
        var editorFocus: Policy.EditorFocus = .none
        var systemCommandsEnabled = true
        var enabledCommands: Set<Policy.Command> = []
        var commandHasSelection = false
        var leftLoaded = true
        var leftEditable = true
        var leftDirty = false
        var leftUntitled = false
        var leftExternalChange = false
        var rightLoaded = true
        var rightEditable = true
        var rightDirty = false
        var rightUntitled = false
        var rightExternalChange = false
        var layout: ComparisonCommandState.Layout = .twoPane
        var visualOrder: [MergeCommandPolicy.Side] = [.left, .right]
        var activePane: MergeCommandPolicy.Side = .left
        var hasDifferences = true
        var sessionLocked = false
        var mergeMode = false
        var canUndo = false
        var canRedo = false
        var canSelectLine = true
        var canSelectPreviousLine = true
        var canSelectNextDifference = true
        var canSelectCurrent = true
        var canDifferencePrevious = true
        var canDifferenceFirst = true
        var canDifferenceNext = true
        var canDifferenceLast = true
        var conflictSupported = true
        var hasConflicts = true
        var canConflictFirst = true
        var canConflictPrevious = true
        var canConflictCurrent = true
        var canConflictNext = true
        var canConflictLast = true
        var fileNavigationSupported = true
        var canFileFirst = true
        var canFilePrevious = true
        var canFileNext = true
        var canFileLast = true
        var canChangePane = true
        var canChangePaneBack = true

        init(id: Audit.ContextID) {
            self.id = id
        }

        init(_ context: Audit.InvocationContext) {
            id = context.id
            commandLifecycle = context.commandState.comparisonLifecycle
            policyLifecycle = context.keyboardState.lifecycle
            keyboardDirty = context.keyboardState.isDirty
            hasSelection = context.keyboardState.hasSelection
            keyboardReadOnly = context.keyboardState.isReadOnly
            editorFocus = context.keyboardState.editorFocus
            systemCommandsEnabled = context.systemCommandsEnabled
            enabledCommands = context.keyboardState.enabledCommands ?? []
            commandHasSelection = context.commandState.hasSelection
            leftLoaded = context.commandState.left.isLoaded
            leftEditable = context.commandState.left.isEditable
            leftDirty = context.commandState.left.isDirty
            leftUntitled = context.commandState.left.isUntitled
            leftExternalChange = context.commandState.left.hasExternalChange
            rightLoaded = context.commandState.right.isLoaded
            rightEditable = context.commandState.right.isEditable
            rightDirty = context.commandState.right.isDirty
            rightUntitled = context.commandState.right.isUntitled
            rightExternalChange = context.commandState.right.hasExternalChange
            layout = context.commandState.layout
            visualOrder = context.commandState.layoutContext.visualOrder
            activePane = context.commandState.layoutContext.activePane
            hasDifferences = context.commandState.hasSignificantDifferences
            sessionLocked = context.commandState.isSessionLocked
            mergeMode = context.commandState.isMergeMode
            canUndo = context.commandState.canUndo
            canRedo = context.commandState.canRedo
            canSelectLine = context.commandState.differenceNavigation.canSelectLineDifference
            canSelectPreviousLine = context.commandState.differenceNavigation.canSelectPreviousLineDifference
            canSelectNextDifference = context.commandState.differenceNavigation.canSelectNextDifference
            canSelectCurrent = context.commandState.differenceNavigation.canSelectCurrentDifference
            canDifferencePrevious = context.commandState.differenceNavigation.canSelectPreviousDifference
            canDifferenceFirst = context.commandState.differenceNavigation.canSelectFirstDifference
            canDifferenceNext = context.commandState.differenceNavigation.canSelectNextDifference
            canDifferenceLast = context.commandState.differenceNavigation.canSelectLastDifference
            conflictSupported = context.commandState.conflictNavigation.isSupported
            hasConflicts = context.commandState.conflictNavigation.hasConflicts
            canConflictFirst = context.commandState.conflictNavigation.canSelectFirstConflict
            canConflictPrevious = context.commandState.conflictNavigation.canSelectPreviousConflict
            canConflictCurrent = context.commandState.conflictNavigation.canSelectCurrentConflict
            canConflictNext = context.commandState.conflictNavigation.canSelectNextConflict
            canConflictLast = context.commandState.conflictNavigation.canSelectLastConflict
            fileNavigationSupported = context.commandState.comparedFileNavigation.isSupported
            canFileFirst = context.commandState.comparedFileNavigation.canSelectFirst
            canFilePrevious = context.commandState.comparedFileNavigation.canSelectPrevious
            canFileNext = context.commandState.comparedFileNavigation.canSelectNext
            canFileLast = context.commandState.comparedFileNavigation.canSelectLast
            canChangePane = context.commandState.canChangePane
            canChangePaneBack = context.commandState.canChangePaneBack
        }

        var differenceGates: [Bool] { [canDifferencePrevious, canDifferenceNext] }
        var conflictGates: [Bool] { [canConflictPrevious, canConflictNext] }
        var fileGates: [Bool] { [canFilePrevious, canFileNext] }
    }

    private struct MeasuredFixture {
        let privateKey: Curve25519.Signing.PrivateKey
        let trust: Audit.MeasurementTrust
        let observations: [Audit.Observation]
        let captures: [Audit.ArtifactDigest: Data]
    }

    private struct SingleMeasuredFixture {
        let trust: Audit.MeasurementTrust
        let observation: Audit.Observation
        let capture: Data
        let digest: Audit.ArtifactDigest
    }

    private func applicationSpecs() -> [ApplicationSpec] {
        let workspace: Set<Policy.LifecycleState> = [.empty, .equal, .different, .failed]
        let current: Set<Policy.LifecycleState> = [.equal, .different]
        let differences: Set<Policy.LifecycleState> = [.different]
        return [
            ApplicationSpec("new-command-n", .comparison(.newComparison), "command+n", workspace),
            ApplicationSpec("open-command-o", .comparison(.openComparison), "command+o", workspace),
            ApplicationSpec("save-command-s", .comparison(.save), "command+s", workspace, dirty: true, readOnly: false),
            ApplicationSpec("quit-command-q", .quit, "command+q"),
            ApplicationSpec("close-command-w", .close, "command+w"),
            ApplicationSpec("undo-command-z", .comparison(.undo), "command+z", workspace, readOnly: false),
            ApplicationSpec("redo-command-shift-z", .comparison(.redo), "command+shift+z", workspace, readOnly: false),
            ApplicationSpec("select-line-difference-f4", .comparison(.selectLineDifference), "f4", differences),
            ApplicationSpec(
                "select-previous-line-difference-shift-f4",
                .comparison(.selectPreviousLineDifference),
                "shift+f4",
                differences
            ),
            ApplicationSpec("next-difference-f8", .comparison(.nextDifference), "f8", differences),
            ApplicationSpec(
                "next-difference-option-down",
                .comparison(.nextDifference),
                "option+downArrow",
                differences,
                winMergeKey: "down"
            ),
            ApplicationSpec("previous-difference-f7", .comparison(.previousDifference), "f7", differences),
            ApplicationSpec(
                "previous-difference-option-up",
                .comparison(.previousDifference),
                "option+upArrow",
                differences,
                winMergeKey: "up"
            ),
            ApplicationSpec("next-conflict-shift-f8", .comparison(.nextConflict), "shift+f8", differences),
            ApplicationSpec(
                "next-conflict-option-shift-down",
                .comparison(.nextConflict),
                "option+shift+downArrow",
                differences
            ),
            ApplicationSpec("previous-conflict-shift-f7", .comparison(.previousConflict), "shift+f7", differences),
            ApplicationSpec(
                "previous-conflict-option-shift-up",
                .comparison(.previousConflict),
                "option+shift+upArrow",
                differences
            ),
            ApplicationSpec(
                "first-difference-option-home",
                .comparison(.firstDifference),
                "option+home",
                differences,
                winMergeKey: "home"
            ),
            ApplicationSpec(
                "current-difference-option-return",
                .comparison(.currentDifference),
                "option+return",
                differences,
                winMergeKey: "return"
            ),
            ApplicationSpec(
                "last-difference-option-end",
                .comparison(.lastDifference),
                "option+end",
                differences,
                winMergeKey: "end"
            ),
            ApplicationSpec(
                "copy-right-option-right",
                .comparison(.copyToRight),
                "option+rightArrow",
                differences,
                selection: true,
                readOnly: false,
                winMergeKey: "right"
            ),
            ApplicationSpec(
                "copy-left-option-left",
                .comparison(.copyToLeft),
                "option+leftArrow",
                differences,
                selection: true,
                readOnly: false,
                winMergeKey: "left"
            ),
            ApplicationSpec(
                "copy-right-advance-command-option-right",
                .comparison(.copyToRightAndAdvance),
                "command+option+rightArrow",
                differences,
                selection: true,
                readOnly: false
            ),
            ApplicationSpec(
                "copy-left-advance-command-option-left",
                .comparison(.copyToLeftAndAdvance),
                "command+option+leftArrow",
                differences,
                selection: true,
                readOnly: false
            ),
            ApplicationSpec(
                "previous-compared-file-command-f7",
                .comparison(.previousComparedFile),
                "command+f7",
                current
            ),
            ApplicationSpec("next-compared-file-command-f8", .comparison(.nextComparedFile), "command+f8", current),
            ApplicationSpec("reload-command-f5", .comparison(.reloadFromDisk), "command+f5", current),
            ApplicationSpec("refresh-f5", .comparison(.refresh), "f5", current.union([.failed])),
            ApplicationSpec("change-pane-f6", .comparison(.changePane), "f6", current),
            ApplicationSpec("change-pane-back-shift-f6", .comparison(.changePaneBack), "shift+f6", current),
            ApplicationSpec("merge-mode-f9", .comparison(.mergeMode), "f9", current),
            ApplicationSpec(
                "options-command-comma",
                .comparison(.options),
                "command+,",
                Set(Policy.LifecycleState.allCases)
            )
        ]
    }

    private func nativeSpecs() -> [NativeSpec] {
        let both = Policy.NativeTextEditingApplicability.readOnlyAndEditable
        let editable = Policy.NativeTextEditingApplicability.editable
        return [
            native(.selectAll, "command+a", both),
            native(.copy, "command+c", both),
            native(.cut, "command+x", editable),
            native(.paste, "command+v", editable),
            native(.undo, "command+z", editable),
            native(.redo, "command+shift+z", editable),
            native(.find, "command+f", both),
            native(.findNext, "command+g", both),
            native(.findPrevious, "command+shift+g", both),
            native(.moveLeft, "leftArrow", both),
            native(.moveRight, "rightArrow", both),
            native(.moveUp, "upArrow", both),
            native(.moveDown, "downArrow", both),
            native(.moveLeftAndModifySelection, "shift+leftArrow", both),
            native(.moveRightAndModifySelection, "shift+rightArrow", both),
            native(.moveUpAndModifySelection, "shift+upArrow", both),
            native(.moveDownAndModifySelection, "shift+downArrow", both),
            native(.moveWordLeft, "option+leftArrow", both),
            native(.moveWordRight, "option+rightArrow", both),
            native(.moveWordLeftAndModifySelection, "option+shift+leftArrow", both),
            native(.moveWordRightAndModifySelection, "option+shift+rightArrow", both),
            native(.moveParagraphUp, "option+upArrow", both),
            native(.moveParagraphDown, "option+downArrow", both),
            native(.moveParagraphUpAndModifySelection, "option+shift+upArrow", both),
            native(.moveParagraphDownAndModifySelection, "option+shift+downArrow", both),
            native(.moveLineStart, "command+leftArrow", both),
            native(.moveLineEnd, "command+rightArrow", both),
            native(.moveLineStartAndModifySelection, "command+shift+leftArrow", both),
            native(.moveLineEndAndModifySelection, "command+shift+rightArrow", both),
            native(.moveDocumentStart, "command+upArrow", both),
            native(.moveDocumentEnd, "command+downArrow", both),
            native(.moveDocumentStartAndModifySelection, "command+shift+upArrow", both),
            native(.moveDocumentEndAndModifySelection, "command+shift+downArrow", both),
            native(.scrollDocumentStart, "home", both),
            native(.scrollDocumentEnd, "end", both),
            native(.moveDocumentStartAndModifySelection, "shift+home", both),
            native(.moveDocumentEndAndModifySelection, "shift+end", both),
            native(.moveBackwardToParagraphStart, "option+home", both),
            native(.moveForwardToParagraphEnd, "option+end", both),
            native(.moveParagraphUpAndModifySelection, "option+shift+home", both),
            native(.moveParagraphDownAndModifySelection, "option+shift+end", both),
            native(.scrollPageUp, "pageUp", both),
            native(.scrollPageDown, "pageDown", both),
            native(.movePageUp, "option+pageUp", both),
            native(.movePageDown, "option+pageDown", both),
            native(.movePageUpAndModifySelection, "shift+pageUp", both),
            native(.movePageDownAndModifySelection, "shift+pageDown", both),
            native(.scrollPageUp, "control+upArrow", both),
            native(.scrollPageDown, "control+downArrow", both),
            native(.moveLineStart, "control+leftArrow", both),
            native(.moveLineEnd, "control+rightArrow", both),
            native(.moveLineStartAndModifySelection, "control+shift+leftArrow", both),
            native(.moveLineEndAndModifySelection, "control+shift+rightArrow", both),
            native(.insertNewline, "return", editable),
            native(.insertLineBreak, "control+return", editable),
            native(.insertNewlineIgnoringFieldEditor, "option+return", editable),
            native(.insertTab, "tab", editable),
            native(.insertBacktab, "shift+tab", editable),
            native(.selectNextKeyView, "control+tab", both),
            native(.selectPreviousKeyView, "control+shift+tab", both),
            native(.insertTabIgnoringFieldEditor, "option+tab", editable),
            native(.insertSpace, "space", editable),
            native(.deleteBackward, "backspace", editable),
            native(.deleteForward, "delete", editable),
            native(.deleteWordBackward, "option+backspace", editable),
            native(.deleteWordBackward, "control+option+backspace", editable),
            native(.deleteWordForward, "option+delete", editable),
            native(.deleteToBeginningOfLine, "command+backspace", editable),
            native(.deleteToEndOfLine, "command+delete", editable),
            native(.moveToBeginningOfParagraph, "control+a", both),
            native(.moveToEndOfParagraph, "control+e", both),
            native(.moveBackward, "control+b", both),
            native(.insertNewline, "control+c", editable),
            native(.moveForward, "control+f", both),
            native(.insertNewline, "control+j", editable),
            native(.moveUp, "control+p", both),
            native(.moveDown, "control+n", both),
            native(.moveToBeginningOfParagraphAndModifySelection, "control+shift+a", both),
            native(.moveToEndOfParagraphAndModifySelection, "control+shift+e", both),
            native(.moveBackwardAndModifySelection, "control+shift+b", both),
            native(.moveForwardAndModifySelection, "control+shift+f", both),
            native(.moveUpAndModifySelection, "control+shift+p", both),
            native(.moveDownAndModifySelection, "control+shift+n", both),
            native(.scrollPageDown, "control+v", both),
            native(.movePageDownAndModifySelection, "control+shift+v", both),
            native(.moveWordLeft, "control+option+b", both),
            native(.moveWordRight, "control+option+f", both),
            native(.moveWordLeftAndModifySelection, "control+option+shift+b", both),
            native(.moveWordRightAndModifySelection, "control+option+shift+f", both),
            native(.centerSelectionInVisibleArea, "control+l", both),
            native(.deleteBackward, "control+h", editable),
            native(.deleteForward, "control+d", editable),
            native(.deleteToEndOfParagraph, "control+k", editable),
            native(.transpose, "control+t", editable),
            native(.insertNewlineIgnoringFieldEditor, "control+o", editable),
            native(.insertTab, "control+i", editable),
            native(.insertNewline, "control+m", editable),
            native(.yank, "control+y", editable),
            native(.cancelOperation, "escape", both),
            native(.cancelOperation, "command+.", both),
            native(.complete, "option+escape", editable),
            native(.complete, "f5", editable),
            native(.deleteBackwardByDecomposingPreviousCharacter, "control+backspace", editable)
        ]
    }

    private func native(
        _ command: Policy.NativeTextEditingCommand,
        _ chord: String,
        _ applicability: Policy.NativeTextEditingApplicability
    ) -> NativeSpec {
        NativeSpec(command: command, chord: chord, applicability: applicability)
    }

    private func nativeSpecsWithIDs() throws -> [NativeSpecWithID] {
        var occurrences: [String: Int] = [:]
        return nativeSpecs().map { spec in
            let identity = ["native-reservation", spec.chord, spec.command.rawValue, spec.applicability.rawValue]
            let opaque = sha256(identity.map(frame).joined())
            let occurrence = occurrences[opaque, default: 0]
            occurrences[opaque] = occurrence + 1
            return NativeSpecWithID(id: "native.\(opaque).\(occurrence)", spec: spec)
        }
    }

    private func applicationProjection(_ spec: ApplicationSpec) throws -> ApplicationProjection {
        let chord = try parseChord(spec.chord)
        let reservation = nativeSpecs().first { $0.chord == spec.chord }.map {
            Audit.NativeReservationRequirement(command: $0.command, applicability: $0.applicability)
        }
        return ApplicationProjection(
            Audit.Binding(
                id: id(spec.id),
                command: spec.command,
                shortcut: menuShortcut(chord),
                policyChord: chord,
                winMergeReference: spec.winMergeKey.map {
                    MenuShortcutDescriptor(platform: .windows, key: $0, modifiers: [.alt])
                },
                policyRequirement: spec.states.map {
                    Audit.PolicyRequirement(
                        enabledLifecycleStates: $0,
                        requiresDirty: spec.requiresDirty,
                        requiresSelection: spec.requiresSelection,
                        allowsReadOnly: spec.allowsReadOnly
                    )
                },
                focusedEditorReservation: reservation,
                invocationTargetAction: expectedTargetAction(for: spec.command),
                expectedResultID: expectedResultID(for: .application(spec.command))
            )
        )
    }

    private func nativeProjection(_ value: NativeSpecWithID) throws -> NativeProjection {
        let chord = try parseChord(value.spec.chord)
        return NativeProjection(
            Audit.NativeBinding(
                id: id(value.id),
                shortcut: menuShortcut(chord),
                policyChord: chord,
                reservation: Audit.NativeReservationRequirement(
                    command: value.spec.command,
                    applicability: value.spec.applicability
                ),
                invocationTargetAction: expectedTargetAction(for: .nativeTextEditing(value.spec.command)),
                expectedResultID: expectedResultID(for: .nativeTextEditing(value.spec.command))
            )
        )
    }

    private func collision(
        _ chord: String,
        _ command: Policy.Command,
        _ nativeCommand: Policy.NativeTextEditingCommand,
        _ applicability: Policy.NativeTextEditingApplicability
    ) -> CollisionProjection {
        CollisionProjection(
            chord: chord,
            kinds: [.editorFocusReservation],
            commands: [command],
            nativeCommands: [nativeCommand],
            commandShortcutCount: 1,
            nativeReservationCount: 1,
            isConditional: true
        )
    }

    private func nativeTuplePrecedes(_ left: NativeTuple, _ right: NativeTuple) -> Bool {
        let leftModifiers = independentModifierBits(left.chord)
        let rightModifiers = independentModifierBits(right.chord)
        if leftModifiers != rightModifiers { return leftModifiers < rightModifiers }
        let leftKey = independentKeyOrder(left.chord)
        let rightKey = independentKeyOrder(right.chord)
        if leftKey != rightKey { return leftKey.lexicographicallyPrecedes(rightKey) }
        if left.command != right.command { return left.command < right.command }
        return left.applicability.rawValue < right.applicability.rawValue
    }

    private func independentModifierBits(_ chord: String) -> Int {
        chord.split(separator: "+").dropLast().reduce(into: 0) { result, modifier in
            switch modifier {
            case "command": result |= 1 << 0
            case "control": result |= 1 << 1
            case "option": result |= 1 << 2
            case "shift": result |= 1 << 3
            case "function": result |= 1 << 4
            default: XCTFail("unknown modifier \(modifier)")
            }
        }
    }

    private func independentKeyOrder(_ chord: String) -> [UInt8] {
        let key = String(chord.split(separator: "+").last!)
        let specialOrder = [
            "backspace", "delete", "downArrow", "end", "escape", "home", "leftArrow",
            "pageDown", "pageUp", "return", "rightArrow", "space", "tab", "upArrow"
        ]
        if key.count == 1 { return [0] + Array(key.utf8) }
        if let special = specialOrder.firstIndex(of: key) {
            return [1, UInt8(special)]
        }
        return [2, UInt8(key.dropFirst())!]
    }

    private func independentInventoryArtifact() throws -> [UInt8] {
        var components = ["3"]
        for spec in applicationSpecs().sorted(by: { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) }) {
            let chord = try parseChord(spec.chord)
            let shortcut = menuShortcut(chord)
            components += [spec.id, applicationCommandIdentity(spec.command)]
            components += shortcutIdentity(shortcut)
            components.append(chord.canonicalDescription)
            components +=
                spec.winMergeKey.map {
                    shortcutIdentity(
                        MenuShortcutDescriptor(platform: .windows, key: $0, modifiers: [.alt])
                    )
                } ?? ["", "", ""]
            if let states = spec.states {
                components.append(
                    Policy.LifecycleState.allCases.filter(states.contains).map(\.rawValue).joined(separator: ",")
                )
                components += [
                    spec.requiresDirty ? "dirty" : "",
                    spec.requiresSelection ? "selection" : "",
                    spec.allowsReadOnly ? "read-only" : "editable"
                ]
            } else {
                components += ["", "", "", ""]
            }
            if let reservation = nativeSpecs().first(where: { $0.chord == spec.chord }) {
                components += [reservation.command.rawValue, reservation.applicability.rawValue]
            } else {
                components += ["", ""]
            }
            let target = expectedTargetAction(for: spec.command)
            components += [
                target.targetID.rawValue,
                target.actionID.rawValue,
                expectedResultID(for: .application(spec.command)).rawValue
            ]
        }
        for native in try nativeSpecsWithIDs().sorted(by: {
            $0.id.utf8.lexicographicallyPrecedes($1.id.utf8)
        }) {
            let chord = try parseChord(native.spec.chord)
            let shortcut = menuShortcut(chord)
            let command = Audit.RoutedCommand.nativeTextEditing(native.spec.command)
            let target = expectedTargetAction(for: command)
            components.append(native.id)
            components += shortcutIdentity(shortcut)
            components += [
                chord.canonicalDescription,
                native.spec.command.rawValue,
                native.spec.applicability.rawValue,
                target.targetID.rawValue,
                target.actionID.rawValue,
                expectedResultID(for: command).rawValue
            ]
        }
        return Array(SHA256.hash(data: Data(components.map(frame).joined().utf8)))
    }

    private func independentCaptureData(for observation: Audit.Observation) -> Data {
        var components = [
            "org.macmerge.shortcut-coverage.capture",
            "2",
            observation.id.rawValue,
            observation.key.bindingID.rawValue,
            observation.key.contextID.rawValue
        ]
        components += shortcutIdentity(observation.shortcut)
        components += [
            String(observation.hardwareKeyCapture.hardwareKeyCode),
            observation.hardwareKeyCapture.inputSourceID.rawValue,
            observation.hardwareKeyCapture.charactersIgnoringModifiers,
            String(observation.hardwareKeyCapture.rawModifierFlags)
        ]
        components += independentContextIdentity(observation.context)
        components += outcomeIdentity(observation.outcome)
        components += [
            observation.invocationReceipt.source.rawValue,
            observation.invocationReceipt.targetAction?.targetID.rawValue ?? "",
            observation.invocationReceipt.targetAction?.actionID.rawValue ?? ""
        ]
        components += commandResultIdentity(observation.invocationReceipt.result)
        components += [
            observation.dispatchTrace.canonicalChord.canonicalDescription,
            String(observation.dispatchTrace.ownershipDecisions.count)
        ]
        for decision in observation.dispatchTrace.ownershipDecisions {
            components += [
                decision.owner.rawValue,
                decision.command.map(routedCommandIdentity) ?? "",
                decision.decision.rawValue
            ]
        }
        components.append(String(observation.dispatchTrace.targetActions.count))
        for target in observation.dispatchTrace.targetActions {
            components += [target.targetID.rawValue, target.actionID.rawValue]
        }
        components.append(String(observation.dispatchTrace.results.count))
        for result in observation.dispatchTrace.results {
            components += commandResultIdentity(result)
        }
        components += [observation.provenance.origin.rawValue, observation.provenance.sourceID.rawValue]
        if let measurement = observation.provenance.measurement {
            components += [
                measurement.captureID.rawValue,
                measurement.collector.id.rawValue,
                String(measurement.collector.revision),
                measurement.build.id.rawValue,
                String(measurement.build.revision),
                digestIdentity(measurement.executableArtifact),
                String(measurement.inventoryRevision),
                digestIdentity(measurement.inventoryArtifact),
                String(measurement.capturedAtUnixMilliseconds),
                hex(measurement.runNonce)
            ]
        }
        return Data(components.map(frame).joined().utf8)
    }

    private func independentContextIdentity(_ context: Audit.InvocationContext) -> [String] {
        let enabledCommands =
            context.keyboardState.enabledCommands?
            .map(\.rawValue)
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .joined(separator: ",") ?? "*"
        let commandState = context.commandState
        var result = [
            context.id.rawValue,
            context.keyboardState.lifecycle.rawValue,
            context.keyboardState.isDirty ? "dirty" : "clean",
            context.keyboardState.hasSelection ? "selected" : "unselected",
            context.keyboardState.isReadOnly ? "read-only" : "editable",
            context.keyboardState.editorFocus.rawValue,
            enabledCommands,
            context.systemCommandsEnabled ? "system-enabled" : "system-disabled",
            paneStateIdentity(commandState.left),
            paneStateIdentity(commandState.right),
            lifecycleIdentity(commandState.comparisonLifecycle),
            commandState.hasSelection ? "selected" : "unselected",
            commandState.hasSignificantDifferences ? "differences" : "no-differences",
            commandState.canUndo ? "undo" : "no-undo",
            commandState.canRedo ? "redo" : "no-redo",
            boolBits([
                commandState.differenceNavigation.canSelectLineDifference,
                commandState.differenceNavigation.canSelectPreviousLineDifference,
                commandState.differenceNavigation.canSelectNextDifference,
                commandState.differenceNavigation.canSelectPreviousDifference,
                commandState.differenceNavigation.canSelectFirstDifference,
                commandState.differenceNavigation.canSelectCurrentDifference,
                commandState.differenceNavigation.canSelectLastDifference
            ]),
            boolBits([
                commandState.conflictNavigation.isSupported,
                commandState.conflictNavigation.hasConflicts,
                commandState.conflictNavigation.canSelectFirstConflict,
                commandState.conflictNavigation.canSelectNextConflict,
                commandState.conflictNavigation.canSelectPreviousConflict,
                commandState.conflictNavigation.canSelectCurrentConflict,
                commandState.conflictNavigation.canSelectLastConflict
            ]),
            boolBits([
                commandState.comparedFileNavigation.isSupported,
                commandState.comparedFileNavigation.canSelectFirst,
                commandState.comparedFileNavigation.canSelectPrevious,
                commandState.comparedFileNavigation.canSelectNext,
                commandState.comparedFileNavigation.canSelectLast
            ]),
            commandState.canChangePane ? "change-pane" : "no-change-pane",
            commandState.canChangePaneBack ? "change-pane-back" : "no-change-pane-back",
            commandState.isMergeMode ? "merge-mode" : "not-merge-mode",
            commandState.isSessionLocked ? "session-locked" : "session-unlocked"
        ]
        switch commandState.layout {
        case .twoPane:
            result.append("two-pane")
        case .threePane(let middle, let destination, let supported, let eligible):
            result += [
                "three-pane", paneStateIdentity(middle), sideIdentity(destination),
                supported ? "automatic-merge-supported" : "automatic-merge-unsupported",
                eligible ? "automatic-merge-eligible" : "automatic-merge-ineligible"
            ]
        }
        result += [
            commandState.layoutContext.visualOrder.map(sideIdentity).joined(separator: ","),
            sideIdentity(commandState.layoutContext.activePane)
        ]
        return result
    }

    private func paneStateIdentity(_ state: ComparisonCommandState.PaneState) -> String {
        [
            state.isLoaded ? "loaded" : "unloaded",
            state.isEditable ? "editable" : "read-only",
            state.isDirty ? "dirty" : "clean",
            state.isUntitled ? "untitled" : "titled",
            state.hasExternalChange ? "external-change" : "unchanged"
        ].joined(separator: ",")
    }

    private func lifecycleIdentity(_ lifecycle: ComparisonCommandState.ComparisonLifecycle) -> String {
        switch lifecycle {
        case .loading: "loading"
        case .refreshing: "refreshing"
        case .stale: "stale"
        case .failed: "failed"
        case .canceled: "canceled"
        case .currentSuccess: "current-success"
        }
    }

    private func sideIdentity(_ side: MergeCommandPolicy.Side) -> String {
        switch side {
        case .left: "left"
        case .middle: "middle"
        case .right: "right"
        }
    }

    private func boolBits(_ values: [Bool]) -> String {
        values.map { $0 ? "1" : "0" }.joined()
    }

    private func outcomeIdentity(_ outcome: Audit.Outcome) -> [String] {
        [
            outcome.owner.rawValue,
            outcome.command.map(routedCommandIdentity) ?? "",
            outcome.isEnabled ? "enabled" : "disabled",
            outcome.invocation.rawValue
        ]
    }

    private func routedCommandIdentity(_ command: Audit.RoutedCommand) -> String {
        switch command {
        case .application(let application): applicationCommandIdentity(application)
        case .nativeTextEditing(let native): "native.\(native.rawValue)"
        }
    }

    private func commandResultIdentity(_ result: MenuCommandResult) -> [String] {
        switch result {
        case .completed(let id): ["completed", id.rawValue]
        case .rejected(let id): ["rejected", id.rawValue]
        case .failed(let id): ["failed", id.rawValue]
        case .notInvoked: ["notInvoked"]
        }
    }

    private func digestIdentity(_ digest: Audit.ArtifactDigest) -> String {
        digest.algorithm.rawValue + ":" + hex(digest.bytes)
    }

    private func shortcutIdentity(_ shortcut: MenuShortcutDescriptor) -> [String] {
        [
            shortcut.platform.rawValue,
            shortcut.key.rawValue,
            shortcut.modifiers.sorted().map(\.rawValue).joined(separator: ",")
        ]
    }

    private func commandStateMismatches() -> [String] {
        let commands = Set(
            applicationSpecs().compactMap { spec -> Policy.Command? in
                guard case .comparison(let command) = spec.command else { return nil }
                return command
            }
        ).sorted { $0.rawValue < $1.rawValue }
        var result: [String] = []
        for context in Audit.requiredContexts {
            for command in commands {
                let expected = context.keyboardState.enabledCommands?.contains(command) ?? true
                let actual = ComparisonCommandState.resolve(command, in: context.commandState).isEnabled
                if expected != actual {
                    result.append(
                        "\(context.id.rawValue)/\(command.rawValue): expected=\(expected), actual=\(actual)"
                    )
                }
            }
        }
        return result
    }

    private func expectedContextSummary(_ contextID: Audit.ContextID) -> ContextSummary {
        var result = ContextSummary(id: contextID)
        result.enabledCommands = expectedEnabledCommands(contextID)
        result.commandHasSelection = [
            .disabled, .selected, .textFocused, .readOnly, .editorReadOnly,
            .directionalLeft, .directionalRight, .leftDestinationReadOnly,
            .rightDestinationReadOnly, .leftDestinationUnloaded,
            .rightDestinationUnloaded, .lineSelectionUnavailable,
            .currentDifferenceUnavailable, .changePaneUnavailable,
            .changePaneBackUnavailable, .navigationAtStart, .navigationAtEnd,
            .differencePreviousOnly, .differenceNextOnly, .conflictPreviousOnly,
            .conflictNextOnly
        ].contains(contextID)
        switch contextID {
        case .empty:
            result.policyLifecycle = .empty
            result.leftLoaded = false
            result.leftEditable = false
            result.rightLoaded = false
            result.rightEditable = false
            result.hasDifferences = false
            result.canSelectLine = false
            result.canSelectPreviousLine = false
            result.canSelectNextDifference = false
            result.canSelectCurrent = false
            result.canDifferencePrevious = false
            result.canDifferenceFirst = false
            result.canDifferenceNext = false
            result.canDifferenceLast = false
            result.conflictSupported = false
            result.hasConflicts = false
            result.canConflictFirst = false
            result.canConflictPrevious = false
            result.canConflictCurrent = false
            result.canConflictNext = false
            result.canConflictLast = false
            result.fileNavigationSupported = false
            result.canFileFirst = false
            result.canFilePrevious = false
            result.canFileNext = false
            result.canFileLast = false
            result.canChangePane = false
            result.canChangePaneBack = false
        case .disabled:
            result.systemCommandsEnabled = false
            result.sessionLocked = true
        case .loading:
            result.commandLifecycle = .loading
            result.policyLifecycle = .loading
        case .selected:
            result.hasSelection = true
        case .dirty:
            result.keyboardDirty = true
            result.leftDirty = true
        case .textFocused:
            result.keyboardDirty = true
            result.hasSelection = true
            result.editorFocus = .editable
            result.leftDirty = true
        case .textFocusedClean:
            result.editorFocus = .editable
        case .equal:
            result.policyLifecycle = .equal
            result.hasDifferences = false
            result.hasConflicts = false
            result.canConflictCurrent = false
        case .failed:
            result.commandLifecycle = .failed
            result.policyLifecycle = .failed
            result.hasDifferences = false
            result.hasConflicts = false
            result.canConflictCurrent = false
        case .readOnly:
            result.hasSelection = true
            result.keyboardReadOnly = true
            result.leftEditable = false
            result.rightEditable = false
        case .editorReadOnly:
            result.hasSelection = true
            result.keyboardReadOnly = true
            result.editorFocus = .readOnly
            result.leftEditable = false
            result.rightEditable = false
        case .directionalLeft:
            result.hasSelection = true
        case .directionalRight:
            result.hasSelection = true
            result.activePane = .right
        case .leftDestinationReadOnly:
            result.hasSelection = true
            result.leftEditable = false
            result.activePane = .right
        case .rightDestinationReadOnly:
            result.hasSelection = true
            result.rightEditable = false
        case .leftDestinationUnloaded:
            result.hasSelection = true
            result.leftLoaded = false
            result.activePane = .right
        case .rightDestinationUnloaded:
            result.hasSelection = true
            result.rightLoaded = false
        case .lineSelectionUnavailable:
            result.hasSelection = true
            result.canSelectLine = false
        case .currentDifferenceUnavailable:
            result.hasSelection = true
            result.canSelectCurrent = false
        case .changePaneUnavailable:
            result.hasSelection = true
            result.canChangePane = false
        case .changePaneBackUnavailable:
            result.hasSelection = true
            result.canChangePaneBack = false
        case .navigationAtStart:
            result.hasSelection = true
            result.canSelectPreviousLine = false
            result.canDifferencePrevious = false
            result.canDifferenceFirst = false
            result.canConflictFirst = false
            result.canConflictPrevious = false
            result.canFileFirst = false
            result.canFilePrevious = false
        case .navigationAtEnd:
            result.hasSelection = true
            result.canSelectNextDifference = false
            result.canDifferenceNext = false
            result.canDifferenceLast = false
            result.canConflictNext = false
            result.canConflictLast = false
            result.canFileNext = false
            result.canFileLast = false
        case .refreshing:
            result.commandLifecycle = .refreshing
            result.policyLifecycle = .loading
        case .stale:
            result.commandLifecycle = .stale
            result.policyLifecycle = .failed
        case .canceled:
            result.commandLifecycle = .canceled
            result.policyLifecycle = .failed
        case .undoEnabled:
            result.canUndo = true
        case .redoEnabled:
            result.canRedo = true
        case .differencePreviousOnly:
            result.hasSelection = true
            result.canSelectNextDifference = false
            result.canDifferenceNext = false
            result.canDifferenceLast = false
        case .differenceNextOnly:
            result.hasSelection = true
            result.canSelectPreviousLine = false
            result.canDifferencePrevious = false
            result.canDifferenceFirst = false
        case .conflictPreviousOnly:
            result.hasSelection = true
            result.canConflictNext = false
            result.canConflictLast = false
        case .conflictNextOnly:
            result.hasSelection = true
            result.canConflictFirst = false
            result.canConflictPrevious = false
        case .comparedFilePreviousOnly:
            result.canFileNext = false
            result.canFileLast = false
        case .comparedFileNextOnly:
            result.canFileFirst = false
            result.canFilePrevious = false
        }
        return result
    }

    private func expectedEnabledCommands(_ context: Audit.ContextID) -> Set<Policy.Command> {
        let workspace: Set<Policy.Command> = [.newComparison, .openComparison]
        let staticCommands: Set<Policy.Command> = [.mergeMode, .options]
        let loaded: Set<Policy.Command> = [
            .reloadFromDisk, .refresh, .changePane, .changePaneBack,
            .previousComparedFile, .nextComparedFile
        ]
        let difference: Set<Policy.Command> = [
            .selectLineDifference, .selectPreviousLineDifference,
            .nextDifference, .previousDifference,
            .firstDifference, .currentDifference, .lastDifference
        ]
        let conflict: Set<Policy.Command> = [.nextConflict, .previousConflict]
        let copy: Set<Policy.Command> = [.copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance]
        let current = workspace.union(staticCommands).union(loaded).union(difference).union(conflict)
        switch context {
        case .empty: return workspace.union(staticCommands)
        case .disabled, .loading, .refreshing: return staticCommands
        case .equal, .failed, .stale, .canceled: return workspace.union(staticCommands).union(loaded)
        case .selected, .directionalLeft, .directionalRight: return current.union(copy)
        case .textFocused: return current.union(copy).union([.save])
        case .textFocusedClean: return current
        case .leftDestinationReadOnly:
            return current.union(copy).subtracting([.copyToLeft, .copyToLeftAndAdvance])
        case .rightDestinationReadOnly:
            return current.union(copy).subtracting([.copyToRight, .copyToRightAndAdvance])
        case .leftDestinationUnloaded, .rightDestinationUnloaded:
            return workspace.union(staticCommands).union([.reloadFromDisk, .previousComparedFile, .nextComparedFile])
        case .lineSelectionUnavailable: return current.union(copy).subtracting([.selectLineDifference])
        case .currentDifferenceUnavailable: return current.union(copy).subtracting([.currentDifference])
        case .changePaneUnavailable: return current.union(copy).subtracting([.changePane])
        case .changePaneBackUnavailable: return current.union(copy).subtracting([.changePaneBack])
        case .dirty: return current.union([.save])
        case .readOnly, .editorReadOnly: return current
        case .navigationAtStart:
            return current.union(copy).subtracting([
                .selectPreviousLineDifference, .previousDifference, .firstDifference,
                .previousConflict, .previousComparedFile
            ])
        case .navigationAtEnd:
            return current.union(copy).subtracting([.nextDifference, .lastDifference, .nextConflict, .nextComparedFile])
        case .differencePreviousOnly: return current.union(copy).subtracting([.nextDifference, .lastDifference])
        case .differenceNextOnly:
            return current.union(copy).subtracting([.selectPreviousLineDifference, .previousDifference, .firstDifference])
        case .conflictPreviousOnly: return current.union(copy).subtracting([.nextConflict])
        case .conflictNextOnly: return current.union(copy).subtracting([.previousConflict])
        case .comparedFilePreviousOnly: return current.subtracting([.nextComparedFile])
        case .comparedFileNextOnly: return current.subtracting([.previousComparedFile])
        case .undoEnabled: return current.union([.undo])
        case .redoEnabled: return current.union([.redo])
        }
    }

    private func expectedOutcome(
        for application: ApplicationSpec,
        context: ContextSummary
    ) -> Audit.Outcome {
        if let reservation = nativeSpecs().first(where: { $0.chord == application.chord }),
            reservationApplies(reservation.applicability, to: context.editorFocus)
        {
            return Audit.Outcome(
                owner: .nativeTextEditor,
                command: .nativeTextEditing(reservation.command),
                isEnabled: true,
                invocation: .invoked
            )
        }
        switch application.command {
        case .quit, .close:
            return Audit.Outcome(
                owner: .application,
                command: .application(application.command),
                isEnabled: context.systemCommandsEnabled,
                invocation: context.systemCommandsEnabled ? .invoked : .blocked
            )
        case .comparison(let command):
            let enabled =
                application.states?.contains(context.policyLifecycle) == true
                && (!application.requiresDirty || context.keyboardDirty)
                && (!application.requiresSelection || context.hasSelection)
                && (application.allowsReadOnly || !context.keyboardReadOnly)
                && context.enabledCommands.contains(command)
            return Audit.Outcome(
                owner: .application,
                command: .application(application.command),
                isEnabled: enabled,
                invocation: enabled ? .invoked : .blocked
            )
        }
    }

    private func expectedOutcome(
        for native: NativeSpec,
        application: ApplicationSpec?,
        context: ContextSummary
    ) -> Audit.Outcome {
        if reservationApplies(native.applicability, to: context.editorFocus) {
            return Audit.Outcome(
                owner: .nativeTextEditor,
                command: .nativeTextEditing(native.command),
                isEnabled: true,
                invocation: .invoked
            )
        }
        if let application { return expectedOutcome(for: application, context: context) }
        return Audit.Outcome(owner: .none, command: nil, isEnabled: false, invocation: .unhandled)
    }

    private func reservationApplies(
        _ applicability: Policy.NativeTextEditingApplicability,
        to focus: Policy.EditorFocus
    ) -> Bool {
        switch (applicability, focus) {
        case (.readOnlyAndEditable, .readOnly), (.readOnlyAndEditable, .editable),
            (.readOnly, .readOnly), (.editable, .editable):
            true
        case (_, .none), (.readOnly, .editable), (.editable, .readOnly):
            false
        }
    }

    private func assertionObservations() throws -> [Audit.Observation] {
        var observations: [Audit.Observation] = []
        observations.reserveCapacity((applicationSpecs().count + nativeSpecs().count) * Audit.ContextID.allCases.count)
        for application in applicationSpecs() {
            for context in Audit.ContextID.allCases {
                observations.append(try assertionObservation(for: application, contextID: context))
            }
        }
        for native in try nativeSpecsWithIDs() {
            for context in Audit.ContextID.allCases {
                observations.append(try assertionObservation(for: native, contextID: context))
            }
        }
        return observations
    }

    private func assertionObservation(
        for application: ApplicationSpec,
        contextID: Audit.ContextID
    ) throws -> Audit.Observation {
        let chord = try parseChord(application.chord)
        let reservation = nativeSpecs().first { $0.chord == application.chord }
        return try observation(
            id: id("observation.\(application.id).\(contextID.rawValue)"),
            bindingID: id(application.id),
            chord: chord,
            contextID: contextID,
            outcome: expectedOutcome(for: application, context: expectedContextSummary(contextID)),
            nativeCandidate: reservation.map { .nativeTextEditing($0.command) },
            applicationCandidate: .application(application.command),
            provenance: Audit.EvidenceProvenance(
                origin: .callerAssertion,
                sourceID: id("assertion-source.\(contextID.rawValue)")
            )
        )
    }

    private func assertionObservation(
        for native: NativeSpecWithID,
        contextID: Audit.ContextID
    ) throws -> Audit.Observation {
        let chord = try parseChord(native.spec.chord)
        let application = applicationSpecs().first { $0.chord == native.spec.chord }
        return try observation(
            id: id("observation.\(native.id).\(contextID.rawValue)"),
            bindingID: id(native.id),
            chord: chord,
            contextID: contextID,
            outcome: expectedOutcome(
                for: native.spec,
                application: application,
                context: expectedContextSummary(contextID)
            ),
            nativeCandidate: .nativeTextEditing(native.spec.command),
            applicationCandidate: application.map { .application($0.command) },
            provenance: Audit.EvidenceProvenance(
                origin: .callerAssertion,
                sourceID: id("assertion-source.\(contextID.rawValue)")
            )
        )
    }

    private func observation(
        id observationID: Audit.StableID,
        bindingID: Audit.StableID,
        chord: Policy.Chord,
        contextID: Audit.ContextID,
        outcome: Audit.Outcome,
        nativeCandidate: Audit.RoutedCommand?,
        applicationCandidate: Audit.RoutedCommand?,
        provenance: Audit.EvidenceProvenance
    ) throws -> Audit.Observation {
        let context = try requiredContext(contextID)
        let target = outcome.invocation == .invoked ? outcome.command.map(expectedTargetAction) : nil
        let result: MenuCommandResult =
            outcome.invocation == .invoked
            ? .completed(expectedResultID(for: try XCTUnwrap(outcome.command)))
            : .notInvoked
        let receipt = Audit.InvocationReceipt(
            source: .keyboardShortcut,
            targetAction: target,
            result: result
        )
        let nativeDecision: Audit.DispatchDecision
        let applicationDecision: Audit.DispatchDecision
        switch outcome.owner {
        case .nativeTextEditor:
            nativeDecision = .claimed
            applicationDecision = .declined
        case .application:
            nativeDecision = .declined
            switch outcome.invocation {
            case .invoked: applicationDecision = .claimed
            case .blocked, .unhandled: applicationDecision = .blocked
            case .failed: applicationDecision = .failed
            }
        case .none:
            nativeDecision = .declined
            applicationDecision = .declined
        }
        return Audit.Observation(
            id: observationID,
            key: Audit.MatrixKey(bindingID: bindingID, contextID: contextID),
            shortcut: menuShortcut(chord),
            hardwareKeyCapture: hardwareCapture(chord),
            context: context,
            outcome: outcome,
            invocationReceipt: receipt,
            dispatchTrace: Audit.DispatchTrace(
                canonicalChord: chord,
                ownershipDecisions: [
                    Audit.OwnershipDecision(
                        owner: .nativeTextEditor,
                        command: outcome.owner == .nativeTextEditor ? outcome.command : nativeCandidate,
                        decision: nativeDecision
                    ),
                    Audit.OwnershipDecision(
                        owner: .application,
                        command: outcome.owner == .application ? outcome.command : applicationCandidate,
                        decision: applicationDecision
                    )
                ],
                targetActions: target.map { [$0] } ?? [],
                results: [result]
            ),
            provenance: provenance
        )
    }

    private func measuredFixture() throws -> MeasuredFixture {
        let privateKey = try signingKey(0x42)
        let inventoryArtifact = try Audit.inventoryArtifact(for: .canonical, cancellationCheck: { false })
        let collector = revision("trusted-shortcut-collector", 7)
        let trust = Audit.MeasurementTrust(
            build: revision("production-shortcut-build", 41),
            executableArtifact: digest(0xA1),
            inventoryRevision: 3,
            inventoryArtifact: inventoryArtifact,
            trustedCollectors: [
                Audit.TrustedCollector(
                    collector: collector,
                    signingPublicKey: Array(privateKey.publicKey.rawRepresentation)
                )
            ]
        )
        var observations: [Audit.Observation] = []
        var captures: [Audit.ArtifactDigest: Data] = [:]
        for (index, assertion) in try assertionObservations().enumerated() {
            let measured = try measuredObservation(
                assertion,
                index: index,
                trust: trust,
                collector: collector,
                privateKey: privateKey
            )
            observations.append(measured.observation)
            captures[measured.digest] = measured.capture
        }
        return MeasuredFixture(
            privateKey: privateKey,
            trust: trust,
            observations: observations,
            captures: captures
        )
    }

    private func singleMeasuredFixture(
        buildID: String = "production-shortcut-build",
        sourceID: String = "production-shortcut-capture",
        origin: Audit.EvidenceOrigin = .automatedMeasurement
    ) throws -> SingleMeasuredFixture {
        let privateKey = try signingKey(0x42)
        let inventoryArtifact = try Audit.inventoryArtifact(for: .canonical, cancellationCheck: { false })
        let collector = revision("trusted-shortcut-collector", 7)
        let trust = Audit.MeasurementTrust(
            build: revision(buildID, 41),
            executableArtifact: digest(0xA1),
            inventoryRevision: 3,
            inventoryArtifact: inventoryArtifact,
            trustedCollectors: [
                Audit.TrustedCollector(
                    collector: collector,
                    signingPublicKey: Array(privateKey.publicKey.rawRepresentation)
                )
            ]
        )
        let assertion = try assertionObservation(for: applicationSpecs()[0], contextID: .empty)
        let measured = try measuredObservation(
            assertion,
            index: 0,
            trust: trust,
            collector: collector,
            privateKey: privateKey,
            sourceID: sourceID,
            origin: origin
        )
        return SingleMeasuredFixture(
            trust: trust,
            observation: measured.observation,
            capture: measured.capture,
            digest: measured.digest
        )
    }

    private func measuredObservation(
        _ assertion: Audit.Observation,
        index: Int,
        trust: Audit.MeasurementTrust,
        collector: Audit.RevisionReference,
        privateKey: Curve25519.Signing.PrivateKey,
        sourceID: String = "production-shortcut-capture",
        origin: Audit.EvidenceOrigin = .automatedMeasurement
    ) throws -> (observation: Audit.Observation, capture: Data, digest: Audit.ArtifactDigest) {
        let placeholder = Audit.MeasurementProvenance(
            captureID: assertion.id,
            collector: collector,
            build: trust.build,
            executableArtifact: trust.executableArtifact,
            inventoryRevision: trust.inventoryRevision,
            inventoryArtifact: trust.inventoryArtifact,
            measurementArtifact: digest(0),
            capturedAtUnixMilliseconds: 1_900_000_000_000 + UInt64(index),
            runNonce: nonce(index),
            captureSignature: [UInt8](repeating: 0, count: 64)
        )
        let unsigned = replacing(
            assertion,
            provenance: Audit.EvidenceProvenance(
                origin: origin,
                sourceID: id(sourceID),
                measurement: placeholder
            )
        )
        let capture = try Audit.canonicalCaptureData(for: unsigned, cancellationCheck: { false })
        let captureDigest = Audit.ArtifactDigest.sha256(of: capture)
        let boundMeasurement = measurementCopy(placeholder, measurementArtifact: captureDigest)
        let bound = replacing(
            unsigned,
            provenance: Audit.EvidenceProvenance(
                origin: origin,
                sourceID: id(sourceID),
                measurement: boundMeasurement
            )
        )
        let signature = try privateKey.signature(for: Audit.signaturePayload(for: bound, cancellationCheck: { false }))
        let signed = replacing(
            bound,
            provenance: Audit.EvidenceProvenance(
                origin: origin,
                sourceID: id(sourceID),
                measurement: measurementCopy(boundMeasurement, captureSignature: Array(signature))
            )
        )
        XCTAssertEqual(try Audit.canonicalCaptureData(for: signed), capture)
        return (signed, capture, captureDigest)
    }

    private func audit(
        _ observations: [Audit.Observation],
        trust: Audit.MeasurementTrust? = nil,
        limits: Audit.Limits = .default,
        resolver: Audit.CaptureResolver? = nil
    ) throws -> Audit.Result {
        try Audit.audit(
            evidence: Audit.Evidence(inventoryRevision: 3, observations: observations),
            measurementTrust: trust,
            limits: limits,
            captureResolver: resolver,
            cancellationCheck: { false }
        )
    }

    private func streamingResolver(
        _ captures: [Audit.ArtifactDigest: Data],
        chunkSize: Int = 257
    ) -> Audit.CaptureResolver {
        { digest, maximumByteCount, cancellationCheck, stream in
            if cancellationCheck() { throw CancellationError() }
            guard let data = captures[digest], data.count <= maximumByteCount else {
                throw TestError.captureUnavailable
            }
            var offset = 0
            while offset < data.count {
                if cancellationCheck() { throw CancellationError() }
                let end = min(data.count, offset + chunkSize)
                try stream.append(data[offset..<end])
                offset = end
            }
        }
    }

    private func replacing(
        _ observation: Audit.Observation,
        id: Audit.StableID? = nil,
        key: Audit.MatrixKey? = nil,
        shortcut: MenuShortcutDescriptor? = nil,
        hardwareKeyCapture: Audit.HardwareKeyCapture? = nil,
        context: Audit.InvocationContext? = nil,
        outcome: Audit.Outcome? = nil,
        invocationReceipt: Audit.InvocationReceipt? = nil,
        dispatchTrace: Audit.DispatchTrace? = nil,
        provenance: Audit.EvidenceProvenance? = nil
    ) -> Audit.Observation {
        Audit.Observation(
            id: id ?? observation.id,
            key: key ?? observation.key,
            shortcut: shortcut ?? observation.shortcut,
            hardwareKeyCapture: hardwareKeyCapture ?? observation.hardwareKeyCapture,
            context: context ?? observation.context,
            outcome: outcome ?? observation.outcome,
            invocationReceipt: invocationReceipt ?? observation.invocationReceipt,
            dispatchTrace: dispatchTrace ?? observation.dispatchTrace,
            provenance: provenance ?? observation.provenance
        )
    }

    private func measurementCopy(
        _ measurement: Audit.MeasurementProvenance,
        captureID: Audit.StableID? = nil,
        collector: Audit.RevisionReference? = nil,
        build: Audit.RevisionReference? = nil,
        executableArtifact: Audit.ArtifactDigest? = nil,
        inventoryRevision: UInt64? = nil,
        inventoryArtifact: Audit.ArtifactDigest? = nil,
        measurementArtifact: Audit.ArtifactDigest? = nil,
        capturedAtUnixMilliseconds: UInt64? = nil,
        runNonce: [UInt8]? = nil,
        captureSignature: [UInt8]? = nil
    ) -> Audit.MeasurementProvenance {
        Audit.MeasurementProvenance(
            captureID: captureID ?? measurement.captureID,
            collector: collector ?? measurement.collector,
            build: build ?? measurement.build,
            executableArtifact: executableArtifact ?? measurement.executableArtifact,
            inventoryRevision: inventoryRevision ?? measurement.inventoryRevision,
            inventoryArtifact: inventoryArtifact ?? measurement.inventoryArtifact,
            measurementArtifact: measurementArtifact ?? measurement.measurementArtifact,
            capturedAtUnixMilliseconds: capturedAtUnixMilliseconds
                ?? measurement.capturedAtUnixMilliseconds,
            runNonce: runNonce ?? measurement.runNonce,
            captureSignature: captureSignature ?? measurement.captureSignature
        )
    }

    private func trustCopy(
        _ trust: Audit.MeasurementTrust,
        inventoryRevision: UInt64? = nil,
        inventoryArtifact: Audit.ArtifactDigest? = nil,
        trustedCollectors: [Audit.TrustedCollector]? = nil
    ) -> Audit.MeasurementTrust {
        Audit.MeasurementTrust(
            build: trust.build,
            executableArtifact: trust.executableArtifact,
            inventoryRevision: inventoryRevision ?? trust.inventoryRevision,
            inventoryArtifact: inventoryArtifact ?? trust.inventoryArtifact,
            trustedCollectors: trustedCollectors ?? trust.trustedCollectors
        )
    }

    private func cell(_ result: Audit.Result, key: Audit.MatrixKey) -> Audit.MatrixCell {
        result.report.matrix.cells.first { $0.expectation.key == key }!
    }

    private func outcome(in rows: [Audit.Expectation], context: Audit.ContextID) -> Audit.Outcome {
        rows.first { $0.key.contextID == context }!.outcome
    }

    private func requiredContext(_ id: Audit.ContextID) throws -> Audit.InvocationContext {
        try XCTUnwrap(Audit.requiredContexts.first { $0.id == id })
    }

    private func expectedTargetAction(for command: Audit.ApplicationCommand) -> MenuTargetAction {
        MenuTargetAction(
            targetID: MenuValidationTargetID(rawValue: "macmerge.application"),
            actionID: MenuValidationActionID(rawValue: applicationCommandIdentity(command))
        )
    }

    private func expectedTargetAction(for command: Audit.RoutedCommand) -> MenuTargetAction {
        switch command {
        case .application(let application): expectedTargetAction(for: application)
        case .nativeTextEditing(let native):
            MenuTargetAction(
                targetID: MenuValidationTargetID(rawValue: "macos.native-text-editor"),
                actionID: MenuValidationActionID(rawValue: "native.\(native.rawValue)")
            )
        }
    }

    private func expectedResultID(for command: Audit.RoutedCommand) -> MenuValidationResultID {
        switch command {
        case .application(let application):
            MenuValidationResultID(rawValue: "result.\(applicationCommandIdentity(application)).completed")
        case .nativeTextEditing(let native):
            MenuValidationResultID(rawValue: "result.native.\(native.rawValue).completed")
        }
    }

    private func applicationCommandIdentity(_ command: Audit.ApplicationCommand) -> String {
        switch command {
        case .comparison(let comparison): "comparison.\(comparison.rawValue)"
        case .quit: "application.quit"
        case .close: "application.close"
        }
    }

    private func menuShortcut(_ chord: Policy.Chord) -> MenuShortcutDescriptor {
        MenuShortcutDescriptor(
            platform: .macOS,
            key: menuKey(chord.key),
            modifiers: Set(chord.modifiers.map(menuModifier))
        )
    }

    private func menuKey(_ key: Policy.Key) -> String {
        switch key {
        case .character(let character): String(character)
        case .function(let number): "f\(number)"
        case .special(let special):
            switch special {
            case .backspace: "backspace"
            case .delete: "delete"
            case .downArrow: "down"
            case .end: "end"
            case .escape: "escape"
            case .home: "home"
            case .leftArrow: "left"
            case .pageDown: "pagedown"
            case .pageUp: "pageup"
            case .return: "return"
            case .rightArrow: "right"
            case .space: "space"
            case .tab: "tab"
            case .upArrow: "up"
            }
        }
    }

    private func menuModifier(_ modifier: Policy.Modifier) -> MenuShortcutModifier {
        switch modifier {
        case .command: .command
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .function: .function
        }
    }

    private func parseChord(_ value: String) throws -> Policy.Chord {
        var components = value.split(separator: "+").map(String.init)
        let keyName = try XCTUnwrap(components.popLast())
        let modifiers = try Set(
            components.map { component -> Policy.Modifier in
                switch component {
                case "command": .command
                case "control": .control
                case "option": .option
                case "shift": .shift
                case "function": .function
                default: throw TestError.invalidChord(value)
                }
            })
        let key: Policy.Key
        if keyName.first == "f", let number = Int(keyName.dropFirst()) {
            key = .function(number)
        } else {
            switch keyName {
            case "backspace": key = .special(.backspace)
            case "delete": key = .special(.delete)
            case "downArrow": key = .special(.downArrow)
            case "end": key = .special(.end)
            case "escape": key = .special(.escape)
            case "home": key = .special(.home)
            case "leftArrow": key = .special(.leftArrow)
            case "pageDown": key = .special(.pageDown)
            case "pageUp": key = .special(.pageUp)
            case "return": key = .special(.return)
            case "rightArrow": key = .special(.rightArrow)
            case "space": key = .special(.space)
            case "tab": key = .special(.tab)
            case "upArrow": key = .special(.upArrow)
            default:
                guard keyName.count == 1, let character = keyName.first else {
                    throw TestError.invalidChord(value)
                }
                key = .character(character)
            }
        }
        return try Policy.Chord(key, modifiers: modifiers)
    }

    private func hardwareCapture(_ chord: Policy.Chord) -> Audit.HardwareKeyCapture {
        let hardware: (UInt16, String)
        switch chord.key {
        case .character(let character):
            hardware = (255, String(character))
        case .function(let number):
            let keyCodes: [Int: UInt16] = [
                1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97, 7: 98, 8: 100,
                9: 101, 10: 109, 11: 103, 12: 111, 13: 105, 14: 107, 15: 113,
                16: 106, 17: 64, 18: 79, 19: 80, 20: 90
            ]
            hardware = (keyCodes[number]!, String(UnicodeScalar(0xF703 + number)!))
        case .special(let special):
            switch special {
            case .backspace: hardware = (51, String(UnicodeScalar(0x7F)!))
            case .delete: hardware = (117, String(UnicodeScalar(0xF728)!))
            case .downArrow: hardware = (125, String(UnicodeScalar(0xF701)!))
            case .end: hardware = (119, String(UnicodeScalar(0xF72B)!))
            case .escape: hardware = (53, String(UnicodeScalar(0x1B)!))
            case .home: hardware = (115, String(UnicodeScalar(0xF729)!))
            case .leftArrow: hardware = (123, String(UnicodeScalar(0xF702)!))
            case .pageDown: hardware = (121, String(UnicodeScalar(0xF72D)!))
            case .pageUp: hardware = (116, String(UnicodeScalar(0xF72C)!))
            case .return: hardware = (36, String(UnicodeScalar(0x0D)!))
            case .rightArrow: hardware = (124, String(UnicodeScalar(0xF703)!))
            case .space: hardware = (49, " ")
            case .tab: hardware = (48, "\t")
            case .upArrow: hardware = (126, String(UnicodeScalar(0xF700)!))
            }
        }
        var flags = chord.modifiers.reduce(UInt64(0)) { $0 | modifierFlag($1) }
        if case .function = chord.key { flags |= modifierFlag(.function) }
        return Audit.HardwareKeyCapture(
            hardwareKeyCode: hardware.0,
            inputSourceID: id("com.apple.keylayout.US"),
            charactersIgnoringModifiers: hardware.1,
            rawModifierFlags: flags
        )
    }

    private func modifierFlag(_ modifier: Policy.Modifier) -> UInt64 {
        switch modifier {
        case .shift: 1 << 17
        case .control: 1 << 18
        case .option: 1 << 19
        case .command: 1 << 20
        case .function: 1 << 23
        }
    }

    private func limits(
        maximumBindings: Int = 256,
        maximumContexts: Int = 64,
        maximumTrustedCollectors: Int = 256,
        maximumObservations: Int = 65_536,
        maximumFindings: Int = 100_000,
        maximumStringUTF8Bytes: Int = 64 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 16 * 1_024 * 1_024,
        maximumCaptureBytes: Int = 1 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 64 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) -> Audit.Limits {
        Audit.Limits(
            maximumBindings: maximumBindings,
            maximumContexts: maximumContexts,
            maximumTrustedCollectors: maximumTrustedCollectors,
            maximumObservations: maximumObservations,
            maximumFindings: maximumFindings,
            maximumStringUTF8Bytes: maximumStringUTF8Bytes,
            maximumTotalStringUTF8Bytes: maximumTotalStringUTF8Bytes,
            maximumCaptureBytes: maximumCaptureBytes,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval
        )
    }

    private func minimumSuccessfulWork<Result>(
        upper: UInt64,
        operation: (UInt64) throws -> Result
    ) throws -> UInt64 {
        var low: UInt64 = 1
        var high = upper
        while low < high {
            let middle = low + (high - low) / 2
            do {
                _ = try operation(middle)
                high = middle
            } catch Audit.AuditError.workLimitExceeded {
                low = middle + 1
            }
        }
        _ = try operation(low)
        return low
    }

    private func revision(_ value: String, _ revision: UInt64) -> Audit.RevisionReference {
        Audit.RevisionReference(id: id(value), revision: revision)
    }

    private func id(_ value: String) -> Audit.StableID {
        Audit.StableID(rawValue: value)
    }

    private func signingKey(_ seed: UInt8) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    private func digest(_ byte: UInt8) -> Audit.ArtifactDigest {
        Audit.ArtifactDigest(bytes: [UInt8](repeating: byte, count: SHA256.byteCount))
    }

    private func nonce(_ index: Int) -> [UInt8] {
        (0..<16).map { UInt8(truncatingIfNeeded: index &+ $0 &+ 1) }
    }

    private func frame(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func diagnostics(_ value: Any) -> String {
        var dumped = ""
        dump(value, to: &dumped)
        return [String(describing: value), String(reflecting: value), dumped].joined(separator: "\n")
    }

    private func assertAuditError<Result>(
        _ expected: Audit.AuditError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Result
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? Audit.AuditError, expected, file: file, line: line)
        }
    }
}

private enum TestError: Error {
    case invalidChord(String)
    case captureUnavailable
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

private final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }
}
