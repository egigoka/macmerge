import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ToolbarAccessibilityAuditPlanTests: XCTestCase {
    private typealias Planner = ToolbarAccessibilityAuditPlan
    private typealias Command = ToolbarConfiguration.Command
    private typealias Control = ToolbarAccessibilityAuditPlan.Control
    private typealias Limits = ToolbarAccessibilityAuditPlan.Limits
    private typealias AuditError = ToolbarAccessibilityAuditPlan.AuditError

    private struct TestCancellation: Error {}

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    private func control(
        for command: Command,
        label: String? = nil,
        role: String = "button",
        lifecycleState: String = "different",
        value: String? = nil,
        hint: String?? = nil,
        isActionAmbiguous: Bool = false,
        enabled: Bool = true,
        focusable: Bool = true
    ) -> Control {
        Control(
            commandID: command,
            label: label ?? "Label \(command.rawValue)",
            role: role,
            lifecycleState: lifecycleState,
            value: value,
            hint: hint ?? "Hint \(command.rawValue)",
            isActionAmbiguous: isActionAmbiguous,
            enabled: enabled,
            focusable: focusable
        )
    }

    private func plan(
        controls: [Control]? = nil,
        limits: Limits = .default,
        cancellationCheck: @escaping Planner.CancellationCheck = {}
    ) throws -> Planner.Plan {
        try Planner.plan(
            controls: controls ?? [control(for: .save)],
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    private func shuffledCommands() -> [Command] {
        [.refresh, .save, .newComparison, .undo, .options, .openComparison]
    }

    // MARK: - Identity

    func testScopeStatementIsStaticAndNonEmpty() {
        XCTAssertFalse(Planner.scopeStatement.isEmpty)
        XCTAssertTrue(Planner.scopeStatement.contains("Static planning"))
    }

    func testReceiptDomainAndFormatVersionAreStable() {
        XCTAssertEqual(Planner.receiptDomain, "toolbar-ax-audit.v1")
        XCTAssertEqual(Planner.formatVersion, 1)
    }

    func testKnownLifecycleStatesMatchAuditScenarios() {
        let expected = Set(ToolbarAuditLifecycleScenario.allCases.map(\.rawValue))
        XCTAssertEqual(Set(Planner.knownLifecycleStates), expected)
        XCTAssertEqual(Planner.knownLifecycleStates.count, 10)
    }

    // MARK: - Happy path

    func testEmptyPlanHasZeroControlsAndStableReceipt() throws {
        let first = try Planner.plan(controls: [], cancellationCheck: {})
        let second = try Planner.plan(controls: [], cancellationCheck: {})
        XCTAssertEqual(first.controlCount, 0)
        XCTAssertTrue(first.controls.isEmpty)
        XCTAssertEqual(first.receipt.controlCount, 0)
        XCTAssertEqual(first.receipt.formatVersion, Planner.formatVersion)
        XCTAssertEqual(first.receipt.bytes.count, Planner.Receipt.byteCount)
        XCTAssertEqual(first.receipt.bytes, second.receipt.bytes)
        XCTAssertEqual(first.receipt.hex, second.receipt.hex)
    }

    func testHappyPathSortsByCommandID() throws {
        let inputs = shuffledCommands().map { control(for: $0) }
        let result = try Planner.plan(controls: inputs, cancellationCheck: {})
        let expected = shuffledCommands().map(\.rawValue).sorted()
        XCTAssertEqual(result.controls.map { $0.commandID.rawValue }, expected)
        XCTAssertEqual(result.controlCount, inputs.count)
        XCTAssertEqual(result.receipt.controlCount, inputs.count)
    }

    func testDigestIsOrderIndependent() throws {
        let forward = shuffledCommands().map { control(for: $0) }
        let backward = shuffledCommands().reversed().map { control(for: $0) }
        let first = try Planner.plan(controls: Array(forward), cancellationCheck: {})
        let second = try Planner.plan(controls: Array(backward), cancellationCheck: {})
        XCTAssertEqual(first.controls, second.controls)
        XCTAssertEqual(first.receipt.bytes, second.receipt.bytes)
        XCTAssertEqual(first.receipt.hex, second.receipt.hex)
    }

    func testDigestIsDeterministicAcrossRuns() throws {
        let inputs = shuffledCommands().map { control(for: $0) }
        let first = try Planner.plan(controls: inputs, cancellationCheck: {})
        let second = try Planner.plan(controls: inputs, cancellationCheck: {})
        XCTAssertEqual(first, second)
    }

    func testDigestChangesWhenAnyFieldDiffers() throws {
        let base = control(for: .save)
        let baseline = try Planner.plan(controls: [base], cancellationCheck: {}).receipt.hex
        let variants: [Control] = [
            control(for: .save, label: "Other label"),
            control(for: .save, role: "checkBox"),
            control(for: .save, lifecycleState: "empty"),
            control(for: .save, value: "half"),
            control(for: .save, hint: "Other hint"),
            control(for: .save, hint: "Hint save", isActionAmbiguous: true),
            control(for: .save, enabled: false),
            control(for: .save, focusable: false)
        ]
        for variant in variants {
            let hex = try Planner.plan(controls: [variant], cancellationCheck: {}).receipt.hex
            XCTAssertNotEqual(hex, baseline, variant.commandID.rawValue)
        }
    }

    func testEnabledFocusableAndLifecycleBindingSurvive() throws {
        let inputs = [
            control(for: .save, lifecycleState: "empty", enabled: false, focusable: false),
            control(for: .undo, lifecycleState: "readOnly", enabled: true, focusable: true)
        ]
        let result = try Planner.plan(controls: inputs, cancellationCheck: {})
        let byCommand = Dictionary(uniqueKeysWithValues: result.controls.map { ($0.commandID, $0) })
        XCTAssertEqual(byCommand[.save]?.enabled, false)
        XCTAssertEqual(byCommand[.save]?.focusable, false)
        XCTAssertEqual(byCommand[.save]?.lifecycleState, "empty")
        XCTAssertEqual(byCommand[.undo]?.enabled, true)
        XCTAssertEqual(byCommand[.undo]?.focusable, true)
        XCTAssertEqual(byCommand[.undo]?.lifecycleState, "readOnly")
    }

    func testFullToolbarSetPassesWithUniqueLabels() throws {
        let inputs = Command.allCases.map { control(for: $0, hint: "Hint \($0.rawValue)") }
        let result = try Planner.plan(controls: inputs.reversed(), cancellationCheck: {})
        XCTAssertEqual(result.controlCount, Command.allCases.count)
        XCTAssertEqual(result.controls.map(\.commandID), Command.allCases.sorted { $0.rawValue < $1.rawValue })
    }

    // MARK: - Duplicates and blanks

    func testDuplicateCommandIDRejectedWithIndexOnly() {
        let inputs = [control(for: .save), control(for: .undo), control(for: .save, label: "Other")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .duplicateCommandID(index: 2))
        }
    }

    func testDuplicateLabelRejectedWithIndexOnly() {
        let inputs = [control(for: .save, label: "Shared"), control(for: .undo, label: "Shared")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .duplicateLabel(index: 1))
        }
    }

    func testSubsetPassesForIncrementalPlanning() throws {
        let inputs = [control(for: .save), control(for: .undo)]
        let result = try Planner.plan(controls: inputs, cancellationCheck: {})
        XCTAssertEqual(result.controlCount, 2)
    }

    func testFreeFormRolePassesWithoutAllowlist() throws {
        let result = try plan(controls: [control(for: .save, role: "custom-role-xyz")])
        XCTAssertEqual(result.controls.first?.role, "custom-role-xyz")
    }

    func testLifecycleStateDoesNotCrossCheckEnabledFocusable() throws {
        let inputs = [
            control(for: .save, lifecycleState: "empty", enabled: true, focusable: true),
            control(for: .undo, lifecycleState: "different", enabled: false, focusable: false)
        ]
        let result = try Planner.plan(controls: inputs, cancellationCheck: {})
        XCTAssertEqual(result.controlCount, 2)
    }

    func testDuplicateLabelCollidesCaseAndWhitespaceInsensitive() {
        let inputs = [control(for: .save, label: "Shared"), control(for: .undo, label: "  shared ")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .duplicateLabel(index: 1))
        }
        let cased = [control(for: .save, label: "SAVE"), control(for: .undo, label: "save")]
        XCTAssertThrowsError(try Planner.plan(controls: cased, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .duplicateLabel(index: 1))
        }
    }

    func testDigestWorkCountedInBudget() {
        XCTAssertThrowsError(
            try plan(controls: [control(for: .save)], limits: Limits(maximumWorkUnits: 2))
        ) { error in
            XCTAssertEqual(error as? AuditError, .workLimitExceeded(maximum: 2))
        }
    }

    func testDigestWorkReportedInReceipt() throws {
        let result = try plan(controls: [control(for: .save)], limits: Limits(maximumWorkUnits: 3))
        XCTAssertEqual(result.receipt.workPerformed, 3)
    }

    func testDigestBindsFormatVersion() throws {
        let result = try plan(controls: [control(for: .save)])
        let expected = expectedDigestHex(controls: result.controls)
        XCTAssertEqual(result.receipt.hex, expected)
        XCTAssertEqual(result.receipt.formatVersion, Planner.formatVersion)
        let legacy = legacyDigestHexWithoutVersion(controls: result.controls)
        XCTAssertNotEqual(result.receipt.hex, legacy)
    }

    func testEmptyAndBlankLabelsRejected() {
        for label in ["", "   ", "\n\t "] {
            let inputs = [control(for: .save, label: label)]
            XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
                XCTAssertEqual(error as? AuditError, .emptyLabel(index: 0), label.debugDescription)
            }
        }
    }

    func testEmptyRoleRejected() {
        let inputs = [control(for: .save, role: "  ")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .emptyRole(index: 0))
        }
    }

    func testBlankValueRejectedWhileNilValuePasses() throws {
        let blank = [control(for: .save, value: " ")]
        XCTAssertThrowsError(try Planner.plan(controls: blank, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .emptyValue(index: 0))
        }
        let result = try plan(controls: [control(for: .save, value: nil)])
        XCTAssertNil(result.controls.first?.value)
        let valued = try plan(controls: [control(for: .save, value: "half")])
        XCTAssertEqual(valued.controls.first?.value, "half")
    }

    func testBlankHintRejected() {
        let inputs = [control(for: .save, hint: " ")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .emptyHint(index: 0))
        }
    }

    func testMissingHintWhenActionAmbiguous() {
        let inputs = [control(for: .save, hint: .some(nil), isActionAmbiguous: true)]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .missingHint(index: 0))
        }
    }

    func testNilHintPassesWhenActionUnambiguous() throws {
        let result = try plan(controls: [control(for: .save, hint: .some(nil))])
        XCTAssertNil(result.controls.first?.hint)
    }

    func testAmbiguousActionWithHintPasses() throws {
        let result = try plan(controls: [control(for: .save, hint: "Pick a side", isActionAmbiguous: true)])
        XCTAssertEqual(result.controls.first?.hint, "Pick a side")
    }

    func testEmptyLifecycleStateRejected() {
        let inputs = [control(for: .save, lifecycleState: "  ")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .emptyLifecycleState(index: 0))
        }
    }

    func testUnknownLifecycleStateRejected() {
        let inputs = [control(for: .save, lifecycleState: "bogus")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .unknownLifecycleState(index: 0))
        }
    }

    func testEveryKnownLifecycleStateAccepted() throws {
        for state in Planner.knownLifecycleStates {
            let result = try plan(controls: [control(for: .save, lifecycleState: state)])
            XCTAssertEqual(result.controls.first?.lifecycleState, state, state)
        }
    }

    // MARK: - Limits before work

    func testInvalidLimitsRejected() {
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumControls: -1))
        ) { error in
            XCTAssertEqual(error as? AuditError, .invalidMaximumControls(value: -1, maximum: Limits.hardMaximumControls))
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumControls: Limits.hardMaximumControls + 1))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidMaximumControls(value: Limits.hardMaximumControls + 1, maximum: Limits.hardMaximumControls)
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumStringUTF8Bytes: 0))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidMaximumStringUTF8Bytes(value: 0, maximum: Limits.hardMaximumStringUTF8Bytes)
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumStringUTF8Bytes: Limits.hardMaximumStringUTF8Bytes + 1))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidMaximumStringUTF8Bytes(
                    value: Limits.hardMaximumStringUTF8Bytes + 1,
                    maximum: Limits.hardMaximumStringUTF8Bytes
                )
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumTotalStringUTF8Bytes: -1))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidMaximumTotalStringUTF8Bytes(value: -1, maximum: Limits.hardMaximumTotalStringUTF8Bytes)
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumTotalStringUTF8Bytes: Limits.hardMaximumTotalStringUTF8Bytes + 1))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidMaximumTotalStringUTF8Bytes(
                    value: Limits.hardMaximumTotalStringUTF8Bytes + 1,
                    maximum: Limits.hardMaximumTotalStringUTF8Bytes
                )
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumWorkUnits: 0))
        ) { error in
            XCTAssertEqual(error as? AuditError, .invalidMaximumWorkUnits(value: 0, maximum: Limits.hardMaximumWorkUnits))
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumWorkUnits: Limits.hardMaximumWorkUnits + 1))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidMaximumWorkUnits(value: Limits.hardMaximumWorkUnits + 1, maximum: Limits.hardMaximumWorkUnits)
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(cancellationCheckInterval: 0))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidCancellationCheckInterval(value: 0, maximum: Limits.hardMaximumCancellationCheckInterval)
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval + 1))
        ) { error in
            XCTAssertEqual(
                error as? AuditError,
                .invalidCancellationCheckInterval(
                    value: Limits.hardMaximumCancellationCheckInterval + 1,
                    maximum: Limits.hardMaximumCancellationCheckInterval
                )
            )
        }
    }

    func testTooManyControlsRejectedBeforeWork() {
        let duplicated = (0...Limits.hardMaximumControls).map { index in
            control(for: .save, label: "Label \(index)")
        }
        XCTAssertEqual(duplicated.count, Limits.hardMaximumControls + 1)
        XCTAssertThrowsError(try Planner.plan(controls: duplicated, cancellationCheck: {})) { error in
            XCTAssertEqual(
                error as? AuditError,
                .tooManyControls(count: duplicated.count, maximum: Limits.hardMaximumControls)
            )
        }
    }

    func testStringTooLargeCarriesIndexOnly() {
        let oversized = String(repeating: "a", count: Limits.default.maximumStringUTF8Bytes + 1)
        let inputs = [control(for: .save, label: oversized)]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .stringTooLarge(index: 0, maximum: Limits.default.maximumStringUTF8Bytes))
        }
    }

    func testTotalStringsTooLargeCarriesCountsOnly() {
        // Current behavior: count is the running prefix sum through the failing
        // field (label 6 + hint 5 = 11), not the full input total (which would
        // add role "button" 6 + lifecycle "different" 9 = 26). Production reword
        // is a later cycle; this test documents the existing prefix-sum value.
        let limits = Limits(maximumTotalStringUTF8Bytes: 10)
        let inputs = [control(for: .save, label: "123456", hint: "78901")]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, limits: limits, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .totalStringsTooLarge(count: 11, maximum: 10))
            XCTAssertEqual(
                (error as? AuditError)?.errorDescription,
                "Toolbar accessibility audit strings hold 11 UTF-8 bytes; supported maximum is 10."
            )
        }
    }

    func testWorkLimitExceeded() {
        let inputs = shuffledCommands().map { control(for: $0) }
        XCTAssertThrowsError(
            try Planner.plan(controls: inputs, limits: Limits(maximumWorkUnits: 2), cancellationCheck: {})
        ) { error in
            XCTAssertEqual(error as? AuditError, .workLimitExceeded(maximum: 2))
        }
    }

    func testLimitsRejectedBeforeWorkBudgetAndOrder() throws {
        // Invalid limits win over content errors: validate() runs first.
        let dupes = [control(for: .save), control(for: .save, label: "Other")]
        XCTAssertThrowsError(try Planner.plan(controls: dupes, limits: Limits(maximumControls: -1), cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .invalidMaximumControls(value: -1, maximum: Limits.hardMaximumControls))
        }
        // Invalid limits win even when no work is needed (empty input would pass).
        XCTAssertThrowsError(try Planner.plan(controls: [], limits: Limits(maximumWorkUnits: 0), cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .invalidMaximumWorkUnits(value: 0, maximum: Limits.hardMaximumWorkUnits))
        }
        // Count check beats string checks and work budget: 27 controls with
        // oversized labels and a 1-unit budget still report tooManyControls.
        let oversizedMany = (0...Limits.hardMaximumControls).map { _ in
            control(for: .save, label: "12345")
        }
        XCTAssertEqual(oversizedMany.count, Limits.hardMaximumControls + 1)
        let tinyLimits = Limits(maximumStringUTF8Bytes: 4, maximumWorkUnits: 1)
        XCTAssertThrowsError(try Planner.plan(controls: oversizedMany, limits: tinyLimits, cancellationCheck: {})) { error in
            XCTAssertEqual(
                error as? AuditError,
                .tooManyControls(count: oversizedMany.count, maximum: Limits.hardMaximumControls)
            )
        }
        // String checks beat validation: oversized first control wins over the
        // duplicate at index 1.
        let stringVsDupe = [
            control(for: .save, label: "12345"),
            control(for: .save, label: "ok")
        ]
        XCTAssertThrowsError(
            try Planner.plan(controls: stringVsDupe, limits: Limits(maximumStringUTF8Bytes: 4), cancellationCheck: {})
        ) { error in
            XCTAssertEqual(error as? AuditError, .stringTooLarge(index: 0, maximum: 4))
        }
        // Total-strings check beats validation: prefix-sum failure at index 0
        // wins over the duplicate at index 1.
        let totalVsDupe = [
            control(for: .save, label: "123456", hint: "78901"),
            control(for: .save, label: "ok", hint: .some(nil))
        ]
        XCTAssertThrowsError(
            try Planner.plan(
                controls: totalVsDupe,
                limits: Limits(maximumTotalStringUTF8Bytes: 10),
                cancellationCheck: {}
            )
        ) { error in
            XCTAssertEqual(error as? AuditError, .totalStringsTooLarge(count: 11, maximum: 10))
        }
        // Budget boundary is explicit: one control costs 3 units
        // (string 1 + validation 1 + digest 1).
        XCTAssertThrowsError(
            try plan(controls: [control(for: .save)], limits: Limits(maximumWorkUnits: 2))
        ) { error in
            XCTAssertEqual(error as? AuditError, .workLimitExceeded(maximum: 2))
        }
        let budgeted = try plan(controls: [control(for: .save)], limits: Limits(maximumWorkUnits: 3))
        XCTAssertEqual(budgeted.receipt.workPerformed, 3)
    }

    // MARK: - Cancellation

    func testImmediateCancellationThrowsCancelled() {
        XCTAssertThrowsError(
            try plan(cancellationCheck: { throw TestCancellation() })
        ) { error in
            XCTAssertEqual(error as? AuditError, .cancelled)
        }
    }

    func testMidPlanCancellationThrowsCancelled() {
        let counter = CallCounter()
        let inputs = Command.allCases.map { control(for: $0) }
        XCTAssertThrowsError(
            try Planner.plan(
                controls: inputs,
                limits: Limits(cancellationCheckInterval: 1),
                cancellationCheck: {
                    if counter.next() > 2 { throw TestCancellation() }
                }
            )
        ) { error in
            XCTAssertEqual(error as? AuditError, .cancelled)
        }
    }

    // MARK: - Error hygiene

    func testErrorDescriptionsNeverEchoCallerText() throws {
        let secret = "SupercalifragilisticSecretLabel"
        let errors: [AuditError] = [
            .duplicateCommandID(index: 3),
            .duplicateLabel(index: 3),
            .emptyLabel(index: 3),
            .emptyValue(index: 3),
            .emptyHint(index: 3),
            .missingHint(index: 3),
            .emptyRole(index: 3),
            .emptyLifecycleState(index: 3),
            .unknownLifecycleState(index: 3),
            .stringTooLarge(index: 3, maximum: Limits.default.maximumStringUTF8Bytes),
            .totalStringsTooLarge(count: 11, maximum: 10),
            .tooManyControls(count: Limits.hardMaximumControls + 1, maximum: Limits.hardMaximumControls),
            .workLimitExceeded(maximum: 2),
            .invalidMaximumControls(value: -1, maximum: Limits.hardMaximumControls),
            .invalidMaximumStringUTF8Bytes(value: 0, maximum: Limits.hardMaximumStringUTF8Bytes),
            .invalidMaximumTotalStringUTF8Bytes(value: -1, maximum: Limits.hardMaximumTotalStringUTF8Bytes),
            .invalidMaximumWorkUnits(value: 0, maximum: Limits.hardMaximumWorkUnits),
            .invalidCancellationCheckInterval(value: 0, maximum: Limits.hardMaximumCancellationCheckInterval)
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.contains(secret) ?? true)
        }
        let dupes = [control(for: .save, label: secret), control(for: .undo, label: secret)]
        XCTAssertThrowsError(try Planner.plan(controls: dupes, cancellationCheck: {})) { error in
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
        let result = try Planner.plan(controls: [control(for: .save, label: secret)], cancellationCheck: {})
        XCTAssertFalse(result.description.contains(secret))
        XCTAssertFalse(result.debugDescription.contains(secret))
        XCTAssertFalse(result.receipt.description.contains(secret))
        XCTAssertFalse(String(describing: result.controls.first?.customMirror).contains(secret))
    }

    // MARK: - Lock hardening

    func testAllEnabledFocusableCombinationsPassForSameLifecycleState() throws {
        let combinations: [(Bool, Bool)] = [(true, true), (true, false), (false, true), (false, false)]
        for (enabled, focusable) in combinations {
            let result = try plan(controls: [
                control(for: .save, lifecycleState: "empty", enabled: enabled, focusable: focusable)
            ])
            XCTAssertEqual(result.controls.first?.enabled, enabled)
            XCTAssertEqual(result.controls.first?.focusable, focusable)
            XCTAssertEqual(result.controls.first?.lifecycleState, "empty")
        }
        let inputs = [
            control(for: .save, lifecycleState: "empty", enabled: true, focusable: true),
            control(for: .undo, lifecycleState: "empty", enabled: true, focusable: false),
            control(for: .refresh, lifecycleState: "empty", enabled: false, focusable: true),
            control(for: .options, lifecycleState: "empty", enabled: false, focusable: false)
        ]
        let result = try Planner.plan(controls: inputs, cancellationCheck: {})
        XCTAssertEqual(result.controlCount, 4)
    }

    func testDuplicateLabelCollidesOnNFCForm() {
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
        XCTAssertEqual(
            composed.precomposedStringWithCanonicalMapping,
            decomposed.precomposedStringWithCanonicalMapping
        )
        let inputs = [control(for: .save, label: composed), control(for: .undo, label: decomposed)]
        XCTAssertThrowsError(try Planner.plan(controls: inputs, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .duplicateLabel(index: 1))
        }
    }

    func testStoredLabelKeepsOriginalSpacingWhileDetectionFolds() throws {
        let spaced = "  Save  "
        let result = try plan(controls: [control(for: .save, label: spaced, hint: .some(nil))])
        XCTAssertEqual(result.controls.first?.label, spaced)
        let folded = [control(for: .save, label: spaced), control(for: .undo, label: "save")]
        XCTAssertThrowsError(try Planner.plan(controls: folded, cancellationCheck: {})) { error in
            XCTAssertEqual(error as? AuditError, .duplicateLabel(index: 1))
        }
    }

    func testDigestWorkScalesWithControlCount() throws {
        let empty = try plan(controls: [])
        XCTAssertEqual(empty.receipt.workPerformed, 0)
        let two = try plan(controls: [control(for: .save), control(for: .undo)])
        XCTAssertEqual(two.receipt.workPerformed, 6)
    }

    func testTotalStringsCountsRoleAndIncludesFailingField() {
        let inputs = [
            control(
                for: .save,
                label: "1234",
                role: "1234567",
                lifecycleState: "empty",
                hint: .some(nil)
            )
        ]
        XCTAssertThrowsError(
            try Planner.plan(
                controls: inputs,
                limits: Limits(maximumTotalStringUTF8Bytes: 10),
                cancellationCheck: {}
            )
        ) { error in
            XCTAssertEqual(error as? AuditError, .totalStringsTooLarge(count: 11, maximum: 10))
        }
    }

    func testTotalStringsCountsValueAndIncludesFailingField() {
        // Isolation: label 4 + value 7 = 11 fails at value; without value the
        // remaining prefix (label 4 + role 1 + lifecycle 5 = 10) would pass.
        let inputs = [
            control(
                for: .save,
                label: "1234",
                role: "r",
                lifecycleState: "empty",
                value: "1234567",
                hint: .some(nil)
            )
        ]
        XCTAssertThrowsError(
            try Planner.plan(
                controls: inputs,
                limits: Limits(maximumTotalStringUTF8Bytes: 10),
                cancellationCheck: {}
            )
        ) { error in
            XCTAssertEqual(error as? AuditError, .totalStringsTooLarge(count: 11, maximum: 10))
        }
    }

    func testTotalStringsCountsLifecycleStateAndIncludesFailingField() {
        // Isolation: label 2 + role 4 + lifecycle "empty" 5 = 11 fails at the
        // lifecycle field; without lifecycle the prefix (2 + 4 = 6) passes.
        let inputs = [
            control(
                for: .save,
                label: "12",
                role: "abcd",
                lifecycleState: "empty",
                hint: .some(nil)
            )
        ]
        XCTAssertThrowsError(
            try Planner.plan(
                controls: inputs,
                limits: Limits(maximumTotalStringUTF8Bytes: 10),
                cancellationCheck: {}
            )
        ) { error in
            XCTAssertEqual(error as? AuditError, .totalStringsTooLarge(count: 11, maximum: 10))
        }
    }

    // MARK: - Digest helpers

    private func expectedDigestHex(controls: [Control]) -> String {
        var input = Data(Planner.receiptDomain.utf8)
        input.append(0)
        appendUInt64(UInt64(Planner.formatVersion), to: &input)
        appendUInt64(UInt64(controls.count), to: &input)
        for control in controls {
            appendString(control.commandID.rawValue, to: &input)
            appendString(control.label, to: &input)
            appendOptionalString(control.value, to: &input)
            appendOptionalString(control.hint, to: &input)
            input.append(control.isActionAmbiguous ? 1 : 0)
            input.append(control.enabled ? 1 : 0)
            input.append(control.focusable ? 1 : 0)
            appendString(control.lifecycleState, to: &input)
            appendString(control.role, to: &input)
        }
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private func legacyDigestHexWithoutVersion(controls: [Control]) -> String {
        var input = Data(Planner.receiptDomain.utf8)
        input.append(0)
        appendUInt64(UInt64(controls.count), to: &input)
        for control in controls {
            appendString(control.commandID.rawValue, to: &input)
            appendString(control.label, to: &input)
            appendOptionalString(control.value, to: &input)
            appendOptionalString(control.hint, to: &input)
            input.append(control.isActionAmbiguous ? 1 : 0)
            input.append(control.enabled ? 1 : 0)
            input.append(control.focusable ? 1 : 0)
            appendString(control.lifecycleState, to: &input)
            appendString(control.role, to: &input)
        }
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private func appendUInt64(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        appendUInt64(UInt64(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    private func appendOptionalString(_ value: String?, to data: inout Data) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        appendString(value, to: &data)
    }
}
