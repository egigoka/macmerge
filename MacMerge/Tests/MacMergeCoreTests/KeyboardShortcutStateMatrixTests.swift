import MacMergeCore
import XCTest

final class KeyboardShortcutStateMatrixTests: XCTestCase {
    private typealias Matrix = KeyboardShortcutStateMatrix
    private typealias Policy = KeyboardShortcutPolicy

    private func descriptor(for id: Matrix.ShortcutID) throws -> Matrix.ShortcutDescriptor {
        try XCTUnwrap(Matrix.canonicalDescriptors.first { $0.id == id })
    }

    private func lookup(
        _ expectations: [Matrix.Expectation],
        shortcut: Matrix.ShortcutID,
        context: Matrix.MatrixContextID
    ) throws -> Matrix.Expectation {
        try XCTUnwrap(
            expectations.first {
                $0.key.shortcutID == shortcut && $0.key.contextID == context
            })
    }

    private func driftedPolicyWithoutSave() throws -> Policy {
        let shortcuts = Policy.unfinishedAuditCommandShortcuts.filter { $0.command != .save }
        return try Policy(
            commandShortcuts: shortcuts,
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations,
            cancellationCheck: {}
        )
    }

    private func driftedPolicyWithoutUndoReservation() throws -> Policy {
        let reservations = Policy.standardNativeTextEditingReservations.filter { $0.command != .undo }
        return try Policy(
            commandShortcuts: Policy.unfinishedAuditCommandShortcuts,
            nativeTextEditingReservations: reservations,
            cancellationCheck: {}
        )
    }

    func testCanonicalDescriptorInventoryIsBoundedAndUnique() {
        XCTAssertEqual(Matrix.canonicalDescriptors.count, 32)
        XCTAssertEqual(Matrix.ShortcutID.allCases.count, 32)
        let ids = Matrix.canonicalDescriptors.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(Matrix.ShortcutID.allCases))
    }

    func testCanonicalContextInventoryCoversEveryGate() {
        XCTAssertEqual(Matrix.canonicalContexts.count, 7)
        XCTAssertEqual(Matrix.MatrixContextID.allCases.count, 7)
        XCTAssertEqual(
            Matrix.canonicalContexts.map { $0.id },
            [.empty, .disabled, .loading, .selected, .dirty, .textFocused, .readOnly]
        )
        XCTAssertEqual(Matrix.canonicalContexts.first { $0.id == .disabled }?.systemCommandsEnabled, false)
        XCTAssertEqual(Matrix.canonicalContexts.first { $0.id == .empty }?.systemCommandsEnabled, true)
        XCTAssertEqual(
            Matrix.canonicalContexts.first { $0.id == .readOnly }?.policyContext.isReadOnly,
            true
        )
        XCTAssertEqual(
            Matrix.canonicalContexts.first { $0.id == .textFocused }?.policyContext.editorFocus,
            .editable
        )
        XCTAssertEqual(
            Matrix.canonicalContexts.first { $0.id == .empty }?.policyContext.lifecycle,
            .empty
        )
    }

    func testCanonicalExpectationsCoverEveryDescriptorContextPair() throws {
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        XCTAssertEqual(expectations.count, 224)
        let keys = expectations.map { $0.key }
        XCTAssertEqual(Set(keys).count, keys.count)
        for descriptor in Matrix.canonicalDescriptors {
            for context in Matrix.canonicalContexts {
                let match = expectations.first {
                    $0.key.shortcutID == descriptor.id && $0.key.contextID == context.id
                }
                XCTAssertNotNil(match, "\(descriptor.id.rawValue)|\(context.id.rawValue)")
            }
        }
    }

    func testChordCanonicalsMatchPolicyDescriptionsForSpotChecks() throws {
        XCTAssertEqual(try descriptor(for: .newCommandN).chord.canonicalDescription, "command+n")
        XCTAssertEqual(try descriptor(for: .nextDifferenceF8).chord.canonicalDescription, "f8")
        XCTAssertEqual(
            try descriptor(for: .nextDifferenceOptionDown).chord.canonicalDescription,
            "option+downArrow"
        )
        XCTAssertEqual(
            try descriptor(for: .copyRightAdvanceCommandOptionRight).chord.canonicalDescription,
            "command+option+rightArrow"
        )
        XCTAssertEqual(
            try descriptor(for: .redoCommandShiftZ).chord.canonicalDescription,
            "command+shift+z"
        )
        XCTAssertEqual(try descriptor(for: .optionsCommandComma).chord.canonicalDescription, "command+,")
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        let next = try lookup(expectations, shortcut: .nextDifferenceF8, context: .selected)
        XCTAssertEqual(next.chordCanonical, "f8")
    }

    func testSystemCommandsFollowSystemEnablementGate() throws {
        let quit = try descriptor(for: .quitCommandQ)
        XCTAssertTrue(quit.isSystemCommand)
        XCTAssertNil(quit.applicationCommand)
        XCTAssertNil(quit.requirement)
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        for context in Matrix.MatrixContextID.allCases {
            let quitRow = try lookup(expectations, shortcut: .quitCommandQ, context: context)
            let closeRow = try lookup(expectations, shortcut: .closeCommandW, context: context)
            XCTAssertEqual(quitRow.owner, .system)
            XCTAssertEqual(closeRow.owner, .system)
            XCTAssertNil(quitRow.applicationCommand)
            XCTAssertNil(quitRow.nativeCommand)
            if context == .disabled {
                XCTAssertFalse(quitRow.isEnabled)
                XCTAssertEqual(quitRow.invocation, .blocked)
                XCTAssertFalse(closeRow.isEnabled)
            } else {
                XCTAssertTrue(quitRow.isEnabled)
                XCTAssertEqual(quitRow.invocation, .invoked)
            }
        }
    }

    func testPreservesNativeEditingMarksExactlyReservedChords() throws {
        let expected: Set<Matrix.ShortcutID> = [
            .undoCommandZ, .redoCommandShiftZ,
            .nextDifferenceOptionDown, .previousDifferenceOptionUp,
            .nextConflictOptionShiftDown, .previousConflictOptionShiftUp,
            .firstDifferenceOptionHome, .currentDifferenceOptionReturn,
            .lastDifferenceOptionEnd, .copyRightOptionRight, .copyLeftOptionLeft, .refreshF5
        ]
        let actual = Set(Matrix.canonicalDescriptors.filter { $0.preservesNativeEditing }.map { $0.id })
        XCTAssertEqual(actual, expected)
        XCTAssertFalse(try descriptor(for: .nextDifferenceF8).preservesNativeEditing)
        XCTAssertFalse(try descriptor(for: .copyRightAdvanceCommandOptionRight).preservesNativeEditing)
    }

    func testWinMergeAcceleratorsAreBoundForOptionEquivalents() throws {
        XCTAssertEqual(try descriptor(for: .nextDifferenceOptionDown).winMergeAccelerator, "Alt+Down")
        XCTAssertEqual(try descriptor(for: .previousDifferenceOptionUp).winMergeAccelerator, "Alt+Up")
        XCTAssertEqual(
            try descriptor(for: .nextConflictOptionShiftDown).winMergeAccelerator,
            "Alt+Shift+Down"
        )
        XCTAssertEqual(
            try descriptor(for: .previousConflictOptionShiftUp).winMergeAccelerator,
            "Alt+Shift+Up"
        )
        XCTAssertEqual(try descriptor(for: .firstDifferenceOptionHome).winMergeAccelerator, "Alt+Home")
        XCTAssertEqual(
            try descriptor(for: .currentDifferenceOptionReturn).winMergeAccelerator,
            "Alt+Enter"
        )
        XCTAssertEqual(try descriptor(for: .lastDifferenceOptionEnd).winMergeAccelerator, "Alt+End")
        XCTAssertEqual(try descriptor(for: .copyRightOptionRight).winMergeAccelerator, "Alt+Right")
        XCTAssertEqual(try descriptor(for: .copyLeftOptionLeft).winMergeAccelerator, "Alt+Left")
        XCTAssertNil(try descriptor(for: .nextDifferenceF8).winMergeAccelerator)
        XCTAssertNil(try descriptor(for: .copyRightAdvanceCommandOptionRight).winMergeAccelerator)
    }

    func testRequirementGatesBindDirtySelectionAndReadOnly() throws {
        let saveRequirement = try XCTUnwrap(try descriptor(for: .saveCommandS).requirement)
        XCTAssertTrue(saveRequirement.requiresDirty)
        XCTAssertFalse(saveRequirement.allowsReadOnly)
        XCTAssertFalse(saveRequirement.requiresSelection)
        let copyRequirement = try XCTUnwrap(try descriptor(for: .copyRightOptionRight).requirement)
        XCTAssertTrue(copyRequirement.requiresSelection)
        XCTAssertFalse(copyRequirement.allowsReadOnly)
        let optionsRequirement = try XCTUnwrap(try descriptor(for: .optionsCommandComma).requirement)
        XCTAssertEqual(optionsRequirement.enabledLifecycleStates, Set(Policy.LifecycleState.allCases))
        XCTAssertEqual(try descriptor(for: .newCommandN).applicationCommand, .newComparison)
        XCTAssertEqual(try descriptor(for: .optionsCommandComma).applicationCommand, .options)
    }

    func testDefaultAuditIsCompleteAndValid() throws {
        let result = try Matrix.audit()
        XCTAssertTrue(result.report.matrix.isComplete)
        XCTAssertTrue(result.report.findings.isEmpty)
        XCTAssertTrue(result.report.isCompleteAndValid)
        XCTAssertFalse(result.report.containsErrors)
        XCTAssertEqual(result.report.formatVersion, Matrix.reportFormatVersion)
        XCTAssertEqual(result.report.formatVersion, 1)
        XCTAssertEqual(result.report.matrix.requiredCount, 224)
        XCTAssertEqual(result.report.matrix.completeCount, 224)
        XCTAssertEqual(result.report.matrix.mismatchedCount, 0)
    }

    func testAuditCellsAreSortedAndCounted() throws {
        let result = try Matrix.audit()
        let keys = result.report.matrix.cells.map { $0.expectation.key }
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertEqual(result.report.matrix.cells.count, result.report.matrix.requiredCount)
        XCTAssertEqual(result.receipt.requiredCellCount, result.report.matrix.requiredCount)
        XCTAssertEqual(result.receipt.completeCellCount, result.report.matrix.completeCount)
        XCTAssertEqual(result.receipt.findingCount, result.report.findings.count)
    }

    func testCollisionInventoryMatchesPreservedChords() throws {
        let policy = try Policy.makeUnfinishedAudit(cancellationCheck: {})
        let expected = Set(
            Matrix.canonicalDescriptors.filter { $0.preservesNativeEditing }.map {
                $0.chord.canonicalDescription
            })
        let actual = Set(
            policy.collisions.filter { $0.kinds.contains(.editorFocusReservation) }.map {
                $0.chord.canonicalDescription
            })
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(policy.collisions.allSatisfy { !$0.kinds.contains(.applicationCommands) })
        XCTAssertEqual(policy.collisions.count, expected.count)
    }

    func testFindingIdentifiersAreUniqueWithoutDedupCollapse() throws {
        let clean = try Matrix.audit()
        XCTAssertTrue(clean.report.findings.isEmpty)
        let drifted = try Matrix.audit(policy: driftedPolicyWithoutUndoReservation())
        XCTAssertFalse(drifted.report.findings.isEmpty)
        let ids = drifted.report.findings.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        let collisions = drifted.report.findings.filter { $0.code == .missingCollision }
        XCTAssertEqual(collisions.count, 1)
        XCTAssertNil(collisions.first?.shortcutID)
        XCTAssertNil(collisions.first?.contextID)
        XCTAssertNotNil(
            drifted.report.findings.first {
                $0.code == .nativePreservationMismatch && $0.shortcutID == .undoCommandZ
            }
        )
    }

    func testMissingPolicyBindingCarriesShortcutIdentity() throws {
        let result = try Matrix.audit(policy: driftedPolicyWithoutSave())
        XCTAssertFalse(result.report.findings.isEmpty)
        let missing = result.report.findings.filter { $0.code == .missingPolicyBinding }
        XCTAssertTrue(missing.contains { $0.shortcutID == .saveCommandS })
        XCTAssertTrue(missing.allSatisfy { $0.severity == .error })
        XCTAssertTrue(result.report.containsErrors)
        XCTAssertFalse(result.report.isCompleteAndValid)
    }

    func testDisabledContextBlocksApplicationAndSystemCommands() throws {
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        let blocked = try lookup(expectations, shortcut: .newCommandN, context: .disabled)
        XCTAssertFalse(blocked.isEnabled)
        XCTAssertEqual(blocked.invocation, .blocked)
        XCTAssertEqual(blocked.owner, .application)
        let options = try lookup(expectations, shortcut: .optionsCommandComma, context: .disabled)
        XCTAssertTrue(options.isEnabled)
        XCTAssertEqual(options.invocation, .invoked)
    }

    func testReadOnlyContextBlocksMutatingCommands() throws {
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        for shortcut in [Matrix.ShortcutID.saveCommandS, .copyRightOptionRight, .undoCommandZ] {
            let row = try lookup(expectations, shortcut: shortcut, context: .readOnly)
            XCTAssertFalse(row.isEnabled, shortcut.rawValue)
            XCTAssertEqual(row.invocation, .blocked, shortcut.rawValue)
        }
        let navigation = try lookup(expectations, shortcut: .nextDifferenceF8, context: .readOnly)
        XCTAssertTrue(navigation.isEnabled)
        XCTAssertEqual(navigation.invocation, .invoked)
        XCTAssertEqual(navigation.owner, .application)
    }

    func testDirtyGateControlsSaveEnablement() throws {
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        let clean = try lookup(expectations, shortcut: .saveCommandS, context: .selected)
        XCTAssertFalse(clean.isEnabled)
        XCTAssertEqual(clean.invocation, .blocked)
        let dirty = try lookup(expectations, shortcut: .saveCommandS, context: .dirty)
        XCTAssertTrue(dirty.isEnabled)
        XCTAssertEqual(dirty.invocation, .invoked)
    }

    func testSelectionGateControlsCopyCommands() throws {
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        let unselected = try lookup(expectations, shortcut: .copyRightOptionRight, context: .loading)
        XCTAssertFalse(unselected.isEnabled)
        let selected = try lookup(expectations, shortcut: .copyRightOptionRight, context: .selected)
        XCTAssertTrue(selected.isEnabled)
        XCTAssertEqual(selected.invocation, .invoked)
        let advance = try lookup(
            expectations,
            shortcut: .copyLeftAdvanceCommandOptionLeft,
            context: .selected
        )
        XCTAssertTrue(advance.isEnabled)
    }

    func testLifecycleGatesForNavigationVersusWorkspaceCommands() throws {
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        let emptyNavigation = try lookup(expectations, shortcut: .nextDifferenceF8, context: .empty)
        XCTAssertFalse(emptyNavigation.isEnabled)
        let loadingNavigation = try lookup(expectations, shortcut: .nextDifferenceF8, context: .loading)
        XCTAssertFalse(loadingNavigation.isEnabled)
        let selectedNavigation = try lookup(expectations, shortcut: .nextDifferenceF8, context: .selected)
        XCTAssertTrue(selectedNavigation.isEnabled)
        let emptyOptions = try lookup(expectations, shortcut: .optionsCommandComma, context: .empty)
        XCTAssertTrue(emptyOptions.isEnabled)
        let loadingReload = try lookup(expectations, shortcut: .reloadCommandF5, context: .loading)
        XCTAssertFalse(loadingReload.isEnabled)
        let selectedReload = try lookup(expectations, shortcut: .reloadCommandF5, context: .selected)
        XCTAssertTrue(selectedReload.isEnabled)
    }

    func testTextFocusedContextRoutesReservedChordsToNativeEditor() throws {
        let expectations = try Matrix.canonicalExpectations(cancellationCheck: { false })
        let focused = try lookup(expectations, shortcut: .undoCommandZ, context: .textFocused)
        XCTAssertEqual(focused.owner, .nativeTextEditor)
        XCTAssertEqual(focused.nativeCommand, .undo)
        XCTAssertNil(focused.applicationCommand)
        XCTAssertTrue(focused.isEnabled)
        XCTAssertEqual(focused.invocation, .invoked)
        let unfocused = try lookup(expectations, shortcut: .undoCommandZ, context: .selected)
        XCTAssertEqual(unfocused.owner, .application)
        XCTAssertEqual(unfocused.applicationCommand, .undo)
        XCTAssertNil(unfocused.nativeCommand)
        let plain = try lookup(expectations, shortcut: .nextDifferenceF8, context: .textFocused)
        XCTAssertEqual(plain.owner, .application)
        XCTAssertEqual(plain.applicationCommand, .nextDifference)
    }

    func testReceiptCountsBindReportAndFingerprintsAreStable() throws {
        let first = try Matrix.audit()
        let second = try Matrix.audit()
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.formatVersion, Matrix.reportFormatVersion)
        XCTAssertEqual(first.receipt.requiredCellCount, 224)
        XCTAssertEqual(first.receipt.completeCellCount, 224)
        XCTAssertEqual(first.receipt.findingCount, 0)
        try first.receipt.validateCurrent()
        try Matrix.validate(receipt: first.receipt)
    }

    func testFindingFingerprintBindsPolicyCommandIdentity() throws {
        let baseline = try Matrix.audit()
        let drifted = try Matrix.audit(policy: driftedPolicyWithoutSave())
        XCTAssertEqual(
            baseline.receipt.descriptorFingerprint,
            drifted.receipt.descriptorFingerprint
        )
        XCTAssertNotEqual(
            baseline.receipt.findingFingerprint,
            drifted.receipt.findingFingerprint
        )
        XCTAssertNotEqual(baseline.receipt, drifted.receipt)
    }

    func testValidateCurrentAcceptsFreshReceiptAndRejectsDrift() throws {
        let baseline = try Matrix.audit()
        let driftedPolicy = try driftedPolicyWithoutSave()
        let drifted = try Matrix.audit(policy: driftedPolicy)
        try drifted.receipt.validateCurrent(policy: driftedPolicy)
        XCTAssertThrowsError(try Matrix.validate(receipt: baseline.receipt, policy: driftedPolicy)) {
            error in
            XCTAssertEqual(error as? Matrix.StateError, .receiptMismatch)
        }
        XCTAssertThrowsError(try baseline.receipt.validateCurrent(policy: driftedPolicy)) { error in
            XCTAssertEqual(error as? Matrix.StateError, .receiptMismatch)
        }
    }

    func testInvalidLimitsAreRejected() {
        let invalid: [(Matrix.Limits, Matrix.Limit)] = [
            (Matrix.Limits(maximumShortcuts: 0), .shortcuts),
            (Matrix.Limits(maximumContexts: 0), .contexts),
            (Matrix.Limits(maximumCells: 0), .cells),
            (Matrix.Limits(maximumFindings: 0), .findings),
            (Matrix.Limits(maximumWorkUnits: 0), .workUnits),
            (Matrix.Limits(cancellationCheckInterval: 0), .cancellationCheckInterval)
        ]
        for (limits, limit) in invalid {
            XCTAssertThrowsError(try Matrix.audit(limits: limits)) { error in
                XCTAssertEqual(error as? Matrix.StateError, .invalidLimit(limit, value: 0))
            }
        }
        XCTAssertThrowsError(try Matrix.audit(limits: Matrix.Limits(maximumShortcuts: 257))) {
            error in
            XCTAssertEqual(error as? Matrix.StateError, .invalidLimit(.shortcuts, value: 257))
        }
    }

    func testInventoryAndCellLimitsAreEnforced() {
        XCTAssertThrowsError(try Matrix.audit(limits: Matrix.Limits(maximumShortcuts: 31))) {
            error in
            XCTAssertEqual(error as? Matrix.StateError, .shortcutLimitExceeded(maximum: 31))
        }
        XCTAssertThrowsError(try Matrix.audit(limits: Matrix.Limits(maximumContexts: 6))) { error in
            XCTAssertEqual(error as? Matrix.StateError, .contextLimitExceeded(maximum: 6))
        }
        XCTAssertThrowsError(try Matrix.audit(limits: Matrix.Limits(maximumCells: 223))) { error in
            XCTAssertEqual(error as? Matrix.StateError, .cellLimitExceeded(maximum: 223))
        }
    }

    func testFindingAndWorkLimitsAreEnforced() throws {
        let empty = try Policy(
            commandShortcuts: [],
            nativeTextEditingReservations: Policy.standardNativeTextEditingReservations,
            cancellationCheck: {}
        )
        XCTAssertThrowsError(
            try Matrix.audit(policy: empty, limits: Matrix.Limits(maximumFindings: 1))
        ) { error in
            XCTAssertEqual(error as? Matrix.StateError, .findingLimitExceeded(maximum: 1))
        }
        XCTAssertThrowsError(try Matrix.audit(limits: Matrix.Limits(maximumWorkUnits: 1))) {
            error in
            XCTAssertEqual(error as? Matrix.StateError, .workLimitExceeded(maximum: 1))
        }
    }

    func testCancellationAbortsExpectationsAuditAndValidation() throws {
        XCTAssertThrowsError(try Matrix.audit(cancellationCheck: { true })) { error in
            XCTAssertEqual(error as? Matrix.StateError, .cancelled)
        }
        XCTAssertThrowsError(try Matrix.canonicalExpectations(cancellationCheck: { true })) {
            error in
            XCTAssertEqual(error as? Matrix.StateError, .cancelled)
        }
        let receipt = try Matrix.audit().receipt
        XCTAssertThrowsError(try Matrix.validate(receipt: receipt, cancellationCheck: { true })) {
            error in
            XCTAssertEqual(error as? Matrix.StateError, .cancelled)
        }
    }

    func testRedactionAndScopeContractsHold() throws {
        XCTAssertFalse(Matrix.Report.scopeStatement.isEmpty)
        XCTAssertTrue(Matrix.Report.scopeStatement.contains("Deterministic"))
        XCTAssertEqual(Matrix.FindingCode.allCases.count, 10)
        XCTAssertEqual(Matrix.FindingSeverity.allCases.count, 3)
        XCTAssertEqual(Matrix.Limit.allCases.count, 6)
        let clean = try Matrix.audit()
        XCTAssertTrue(clean.report.description.contains("<redacted>"))
        XCTAssertTrue(clean.receipt.description.contains("<redacted>"))
        XCTAssertTrue(clean.report.matrix.cells.allSatisfy { $0.description.contains("<redacted>") })
        let drifted = try Matrix.audit(policy: driftedPolicyWithoutSave())
        XCTAssertFalse(drifted.report.findings.isEmpty)
        XCTAssertTrue(drifted.report.findings.allSatisfy { $0.description.contains("<redacted>") })
        XCTAssertTrue(drifted.report.findings.allSatisfy { !$0.message.isEmpty })
    }
}
