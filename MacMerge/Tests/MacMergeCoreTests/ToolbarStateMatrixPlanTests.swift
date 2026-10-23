import CryptoKit
import Foundation
import MacMergeCore
import XCTest

final class ToolbarStateMatrixPlanTests: XCTestCase {
    private typealias Plan = ToolbarStateMatrixPlan
    private typealias PlanError = ToolbarStateMatrixPlanError
    private typealias Limits = ToolbarStateMatrixPlan.Limits

    private func fullCoverageEntries() -> [Plan.Entry] {
        var entries: [Plan.Entry] = []
        entries.reserveCapacity(Plan.expectedEntryCount)
        for command in Plan.Command.allCases {
            for state in Plan.State.allCases {
                if state == .empty || state == .loading || state == .failed {
                    entries.append(
                        Plan.Entry(
                            command: command,
                            state: state,
                            isEnabled: false,
                            reason: "unavailable in \(state.rawValue)"
                        )
                    )
                } else {
                    entries.append(Plan.Entry(command: command, state: state, isEnabled: true))
                }
            }
        }
        return entries
    }

    private func fullCoverageRawEntries() -> [Plan.RawEntry] {
        fullCoverageEntries().map {
            Plan.RawEntry(
                commandID: $0.command.rawValue,
                state: $0.state,
                isEnabled: $0.isEnabled,
                reason: $0.reason
            )
        }
    }

    func testTenStatesHaveExactRawValues() {
        XCTAssertEqual(
            Plan.State.allCases.map(\.rawValue),
            [
                "empty", "loading", "equal", "different", "selected", "dirty",
                "readOnly", "failed", "untitled", "externallyChanged"
            ]
        )
        XCTAssertEqual(Plan.State.allCases.count, 10)
    }

    func testCommandAllowlistMatchesToolbarConfiguration() {
        XCTAssertEqual(Plan.Command.allCases, ToolbarConfiguration.Command.allCases)
        XCTAssertEqual(Plan.expectedEntryCount, Plan.Command.allCases.count * 10)
    }

    func testReceiptDomainIsExact() {
        XCTAssertEqual(Plan.receiptDomain, "toolbar-state-matrix.v1")
    }

    func testFullCoveragePlanSortsAndDigests() throws {
        let plan = try Plan.make(entries: fullCoverageEntries())
        XCTAssertEqual(plan.entryCount, Plan.expectedEntryCount)
        let sorted = fullCoverageEntries().sorted {
            if $0.command.rawValue != $1.command.rawValue { return $0.command.rawValue < $1.command.rawValue }
            return $0.state.rawValue < $1.state.rawValue
        }
        XCTAssertEqual(plan.entries, sorted)
        XCTAssertEqual(plan.digestHex.count, 64)
        XCTAssertTrue(plan.digestHex.allSatisfy(\.isHexDigit))
        XCTAssertFalse(plan.description.contains("unavailable"))
    }

    func testDigestIsOrderIndependent() throws {
        let forward = try Plan.make(entries: fullCoverageEntries())
        let reversed = try Plan.make(entries: fullCoverageEntries().reversed())
        XCTAssertEqual(forward.digestHex, reversed.digestHex)
        XCTAssertEqual(forward.entries, reversed.entries)
    }

    func testDigestMatchesDomainPreimage() throws {
        let plan = try Plan.make(entries: fullCoverageEntries())
        var input = Data(Plan.receiptDomain.utf8)
        input.append(0)
        for entry in plan.entries {
            input.append(contentsOf: entry.command.rawValue.utf8)
            input.append(0)
            input.append(contentsOf: entry.state.rawValue.utf8)
            input.append(0)
            input.append(entry.isEnabled ? 1 : 0)
            if let reason = entry.reason {
                input.append(contentsOf: reason.precomposedStringWithCanonicalMapping.utf8)
            }
            input.append(0)
        }
        let expected = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(plan.digestHex, expected)
        XCTAssertEqual(plan.receipt.hex, expected)
    }

    func testDuplicatePairRejectsWithIndices() {
        var entries = fullCoverageEntries()
        entries.append(entries[0])
        XCTAssertThrowsError(try Plan.make(entries: entries)) { error in
            guard let planError = error as? PlanError else {
                XCTFail("expected plan error")
                return
            }
            if case .duplicateEntry(let firstIndex, let duplicateIndex) = planError {
                XCTAssertEqual(firstIndex, 0)
                XCTAssertEqual(duplicateIndex, entries.count - 1)
            } else {
                XCTFail("unexpected error \(planError)")
            }
        }
    }

    func testUnknownCommandIDRejectsWithIndexOnly() {
        var raw = fullCoverageRawEntries()
        raw[7] = Plan.RawEntry(commandID: "bogus-command", state: .empty, isEnabled: false, reason: "x")
        XCTAssertThrowsError(try Plan.make(rawEntries: raw)) { error in
            XCTAssertEqual(error as? PlanError, .unknownCommandID(index: 7))
        }
    }

    func testDisabledWithoutReasonRejects() {
        var entries = fullCoverageEntries()
        guard let index = entries.firstIndex(where: { !$0.isEnabled }) else {
            XCTFail("expected disabled entry")
            return
        }
        entries[index] = Plan.Entry(command: entries[index].command, state: entries[index].state, isEnabled: false)
        XCTAssertThrowsError(try Plan.make(entries: entries)) { error in
            XCTAssertEqual(error as? PlanError, .reasonMissing(index: index))
        }
    }

    func testDisabledWithBlankReasonRejects() {
        var entries = fullCoverageEntries()
        guard let index = entries.firstIndex(where: { !$0.isEnabled }) else {
            XCTFail("expected disabled entry")
            return
        }
        entries[index] = Plan.Entry(
            command: entries[index].command,
            state: entries[index].state,
            isEnabled: false,
            reason: "   "
        )
        XCTAssertThrowsError(try Plan.make(entries: entries)) { error in
            XCTAssertEqual(error as? PlanError, .reasonMissing(index: index))
        }
    }

    func testEnabledWithReasonRejects() {
        var entries = fullCoverageEntries()
        guard let index = entries.firstIndex(where: { $0.isEnabled }) else {
            XCTFail("expected enabled entry")
            return
        }
        entries[index] = Plan.Entry(
            command: entries[index].command,
            state: entries[index].state,
            isEnabled: true,
            reason: "extra"
        )
        XCTAssertThrowsError(try Plan.make(entries: entries)) { error in
            XCTAssertEqual(error as? PlanError, .unexpectedReason(index: index))
        }
    }

    func testMissingCoverageReportsCountOnly() {
        let entries = Array(fullCoverageEntries().dropLast(3))
        XCTAssertThrowsError(try Plan.make(entries: entries)) { error in
            XCTAssertEqual(error as? PlanError, .missingEntries(missingCount: 3))
        }
    }

    func testEmptyEntriesReportFullMissingCount() {
        XCTAssertThrowsError(try Plan.make(entries: [])) { error in
            XCTAssertEqual(error as? PlanError, .missingEntries(missingCount: Plan.expectedEntryCount))
        }
    }

    func testLimitsValidateBeforeWork() {
        let limits = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 1_024,
            maximumTotalReasonUTF8Bytes: 262_144,
            maximumWorkUnits: 0,
            cancellationCheckInterval: 64
        )
        XCTAssertThrowsError(try Plan.make(entries: fullCoverageEntries(), limits: limits)) { error in
            XCTAssertEqual(error as? PlanError, .invalidLimit(.workUnits, value: 0))
        }
    }

    func testEntryLimitExceededReportsCounts() {
        let limits = Limits(
            maximumEntries: 10,
            maximumReasonUTF8Bytes: 1_024,
            maximumTotalReasonUTF8Bytes: 262_144,
            maximumWorkUnits: 100_000,
            cancellationCheckInterval: 64
        )
        XCTAssertThrowsError(try Plan.make(entries: fullCoverageEntries(), limits: limits)) { error in
            XCTAssertEqual(
                error as? PlanError,
                .entryLimitExceeded(count: Plan.expectedEntryCount, maximum: 10)
            )
        }
    }

    func testReasonTooLargeReportsIndex() {
        let entries = fullCoverageEntries()
        guard let expectedIndex = entries.firstIndex(where: { !$0.isEnabled }) else {
            XCTFail("expected disabled entry")
            return
        }
        let limits = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 4,
            maximumTotalReasonUTF8Bytes: 262_144,
            maximumWorkUnits: 100_000,
            cancellationCheckInterval: 64
        )
        XCTAssertThrowsError(try Plan.make(entries: entries, limits: limits)) { error in
            if case .reasonTooLarge(let thrownIndex, let maximum) = error as? PlanError {
                XCTAssertEqual(thrownIndex, expectedIndex)
                XCTAssertEqual(maximum, 4)
            } else {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    func testWorkLimitExceeded() {
        let limits = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 1_024,
            maximumTotalReasonUTF8Bytes: 262_144,
            maximumWorkUnits: 10,
            cancellationCheckInterval: 64
        )
        XCTAssertThrowsError(try Plan.make(entries: fullCoverageEntries(), limits: limits)) { error in
            XCTAssertEqual(error as? PlanError, .workLimitExceeded(maximum: 10))
        }
    }

    func testCancellationMapsToCancelled() {
        XCTAssertThrowsError(
            try Plan.make(entries: fullCoverageEntries(), cancellationCheck: { throw CancellationError() })
        ) { error in
            XCTAssertEqual(error as? PlanError, .cancelled)
        }
    }

    func testErrorsCarryIndexOrCountOnly() {
        let secret = "super-secret-reason-text"
        var entries = fullCoverageEntries()
        guard let index = entries.firstIndex(where: { !$0.isEnabled }) else {
            XCTFail("expected disabled entry")
            return
        }
        entries[index] = Plan.Entry(
            command: entries[index].command,
            state: entries[index].state,
            isEnabled: false,
            reason: secret
        )
        let limits = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 4,
            maximumTotalReasonUTF8Bytes: 262_144,
            maximumWorkUnits: 100_000,
            cancellationCheckInterval: 64
        )
        do {
            _ = try Plan.make(entries: entries, limits: limits)
            XCTFail("expected failure")
        } catch let error as PlanError {
            XCTAssertFalse("\(error)".contains(secret))
            XCTAssertFalse((error.errorDescription ?? "").contains(secret))
        } catch {
            XCTFail("unexpected error type")
        }
    }

    func testDefaultTotalBudgetCoversWorstCaseFullDisabled() {
        XCTAssertEqual(Plan.Command.allCases.count, 26)
        XCTAssertEqual(Plan.State.allCases.count, 10)
        XCTAssertEqual(Plan.expectedEntryCount, 260)
        XCTAssertEqual(Limits.default.maximumReasonUTF8Bytes, 1_024)
        XCTAssertEqual(Limits.default.maximumTotalReasonUTF8Bytes, 26 * 10 * 1_024)
        XCTAssertEqual(Limits.default.maximumTotalReasonUTF8Bytes, 266_240)
        XCTAssertGreaterThanOrEqual(Limits.default.maximumEntries, Plan.expectedEntryCount)
        let maxReason = String(repeating: "a", count: Limits.default.maximumReasonUTF8Bytes)
        XCTAssertEqual(maxReason.precomposedStringWithCanonicalMapping.utf8.count, 1_024)
        var entries: [Plan.Entry] = []
        entries.reserveCapacity(Plan.expectedEntryCount)
        for command in Plan.Command.allCases {
            for state in Plan.State.allCases {
                entries.append(Plan.Entry(command: command, state: state, isEnabled: false, reason: maxReason))
            }
        }
        let total = entries.reduce(0) {
            $0 + ($1.reason?.precomposedStringWithCanonicalMapping.utf8.count ?? 0)
        }
        XCTAssertEqual(total, 266_240)
        XCTAssertNoThrow(try Plan.make(entries: entries))
    }

    func testReasonPerEntryLimitUsesCanonicalNFCBytes() {
        let decomposed = "é"
        XCTAssertEqual(decomposed.utf8.count, 3)
        XCTAssertEqual(decomposed.precomposedStringWithCanonicalMapping.utf8.count, 2)
        var tiny: [Plan.Entry] = []
        tiny.reserveCapacity(Plan.expectedEntryCount)
        for command in Plan.Command.allCases {
            for state in Plan.State.allCases {
                if state == .empty || state == .loading || state == .failed {
                    tiny.append(Plan.Entry(command: command, state: state, isEnabled: false, reason: "ok"))
                } else {
                    tiny.append(Plan.Entry(command: command, state: state, isEnabled: true))
                }
            }
        }
        guard let index = tiny.firstIndex(where: { !$0.isEnabled }) else {
            XCTFail("expected disabled entry")
            return
        }
        tiny[index] = Plan.Entry(command: tiny[index].command, state: tiny[index].state, isEnabled: false, reason: decomposed)
        let limits = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 2,
            maximumTotalReasonUTF8Bytes: 266_240,
            maximumWorkUnits: 100_000,
            cancellationCheckInterval: 64
        )
        XCTAssertNoThrow(try Plan.make(entries: tiny, limits: limits))
        let strict = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 1,
            maximumTotalReasonUTF8Bytes: 266_240,
            maximumWorkUnits: 100_000,
            cancellationCheckInterval: 64
        )
        XCTAssertThrowsError(try Plan.make(entries: tiny, limits: strict)) { error in
            if case .reasonTooLarge(let thrownIndex, let maximum) = error as? PlanError {
                XCTAssertEqual(thrownIndex, index)
                XCTAssertEqual(maximum, 1)
            } else {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    func testTotalReasonLimitUsesCanonicalNFCBytes() {
        let decomposed = "é"
        XCTAssertEqual(decomposed.utf8.count, 3)
        XCTAssertEqual(decomposed.precomposedStringWithCanonicalMapping.utf8.count, 2)
        let entries = Plan.Command.allCases.flatMap { command in
            Plan.State.allCases.map { state in
                Plan.Entry(command: command, state: state, isEnabled: false, reason: decomposed)
            }
        }
        XCTAssertEqual(entries.count, Plan.expectedEntryCount)
        let rawTotal = entries.reduce(0) { $0 + ($1.reason?.utf8.count ?? 0) }
        let canonicalTotal = entries.reduce(0) {
            $0 + ($1.reason?.precomposedStringWithCanonicalMapping.utf8.count ?? 0)
        }
        XCTAssertEqual(rawTotal, 780)
        XCTAssertEqual(canonicalTotal, 520)
        let limits = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 4,
            maximumTotalReasonUTF8Bytes: 520,
            maximumWorkUnits: 100_000,
            cancellationCheckInterval: 64
        )
        XCTAssertNoThrow(try Plan.make(entries: entries, limits: limits))
        let tight = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 4,
            maximumTotalReasonUTF8Bytes: 519,
            maximumWorkUnits: 100_000,
            cancellationCheckInterval: 64
        )
        XCTAssertThrowsError(try Plan.make(entries: entries, limits: tight)) { error in
            XCTAssertEqual(error as? PlanError, .totalReasonsTooLarge(maximum: 519))
        }
    }

    func testWorkBudgetIsSingleTotalAcrossRawAndTypedPhases() {
        let expected = Plan.expectedEntryCount
        XCTAssertEqual(expected, 260)
        let shared = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 1_024,
            maximumTotalReasonUTF8Bytes: 266_240,
            maximumWorkUnits: expected * 2,
            cancellationCheckInterval: 64
        )
        XCTAssertNoThrow(try Plan.make(entries: fullCoverageEntries(), limits: shared))
        XCTAssertThrowsError(try Plan.make(rawEntries: fullCoverageRawEntries(), limits: shared)) { error in
            XCTAssertEqual(error as? PlanError, .workLimitExceeded(maximum: expected * 2))
        }
        let generous = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 1_024,
            maximumTotalReasonUTF8Bytes: 266_240,
            maximumWorkUnits: expected * 3,
            cancellationCheckInterval: 64
        )
        XCTAssertNoThrow(try Plan.make(rawEntries: fullCoverageRawEntries(), limits: generous))
    }

    func testMissingEntriesErrorIsCountOnly() {
        let full = fullCoverageEntries()
        let missingBack = Array(full.dropLast(3))
        XCTAssertThrowsError(try Plan.make(entries: missingBack)) { error in
            XCTAssertEqual(error as? PlanError, .missingEntries(missingCount: 3))
            let text = "\(error)" + ((error as? PlanError)?.errorDescription ?? "")
            XCTAssertTrue(text.contains("3"))
            for dropped in full.suffix(3) {
                XCTAssertFalse(text.contains(dropped.command.rawValue))
                XCTAssertFalse(text.contains(dropped.state.rawValue))
            }
        }
        var frontError: PlanError?
        var backError: PlanError?
        do {
            _ = try Plan.make(entries: Array(full.dropFirst(3)))
            XCTFail("expected failure")
        } catch let error as PlanError {
            frontError = error
        } catch {
            XCTFail("unexpected error type")
        }
        do {
            _ = try Plan.make(entries: Array(full.dropLast(3)))
            XCTFail("expected failure")
        } catch let error as PlanError {
            backError = error
        } catch {
            XCTFail("unexpected error type")
        }
        XCTAssertEqual(frontError, backError)
        XCTAssertEqual(frontError, .missingEntries(missingCount: 3))
    }

    func testStateAllowlistMatchesAuditScenariosSetEquality() {
        XCTAssertEqual(
            Set(Plan.State.allCases.map(\.rawValue)),
            Set(ToolbarAuditLifecycleScenario.allCases.map(\.rawValue))
        )
        XCTAssertEqual(Plan.State.allCases.count, ToolbarAuditLifecycleScenario.allCases.count)
        XCTAssertEqual(Plan.State.allCases.count, 10)
    }

    func testFullCoverageDisabledCountIs78AndMirrorRedacted() throws {
        let plan = try Plan.make(entries: fullCoverageEntries())
        XCTAssertEqual(plan.entryCount, 260)
        XCTAssertEqual(plan.disabledCount, 78)
        XCTAssertEqual(plan.entryCount - plan.disabledCount, 182)
        XCTAssertTrue(plan.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
        XCTAssertNil(
            plan.customMirror.children.first(where: { "\($0.value)".contains("unavailable") })
        )
        XCTAssertFalse(plan.description.contains("unavailable"))
        XCTAssertFalse(plan.debugDescription.contains("unavailable"))
        var secretEntries = fullCoverageEntries()
        guard let index = secretEntries.firstIndex(where: { !$0.isEnabled }) else {
            XCTFail("expected disabled entry")
            return
        }
        let secret = "super-secret-reason-XYZZY-78"
        secretEntries[index] = Plan.Entry(
            command: secretEntries[index].command,
            state: secretEntries[index].state,
            isEnabled: false,
            reason: secret
        )
        let secretPlan = try Plan.make(entries: secretEntries)
        XCTAssertEqual(secretPlan.disabledCount, 78)
        XCTAssertFalse(secretPlan.description.contains(secret))
        XCTAssertFalse(secretPlan.debugDescription.contains(secret))
        XCTAssertFalse(String(describing: secretPlan.customMirror).contains(secret))
        XCTAssertTrue(secretPlan.customMirror.children.contains(where: { "\($0.value)" == "<redacted>" }))
    }

    func testDuplicateSamePairDifferentPayloadRejects() {
        var entries = fullCoverageEntries()
        let first = entries[0]
        entries.append(
            Plan.Entry(command: first.command, state: first.state, isEnabled: true)
        )
        XCTAssertThrowsError(try Plan.make(entries: entries)) { error in
            XCTAssertEqual(
                error as? PlanError,
                .duplicateEntry(firstIndex: 0, duplicateIndex: entries.count - 1)
            )
        }
        var reasonVariant = fullCoverageEntries()
        let base = reasonVariant[0]
        reasonVariant.append(
            Plan.Entry(
                command: base.command,
                state: base.state,
                isEnabled: false,
                reason: "different-payload-reason"
            )
        )
        XCTAssertThrowsError(try Plan.make(entries: reasonVariant)) { error in
            XCTAssertEqual(
                error as? PlanError,
                .duplicateEntry(firstIndex: 0, duplicateIndex: reasonVariant.count - 1)
            )
        }
    }

    func testDuplicateRawEntriesRejects() {
        var raw = fullCoverageRawEntries()
        raw.append(raw[0])
        XCTAssertThrowsError(try Plan.make(rawEntries: raw)) { error in
            XCTAssertEqual(
                error as? PlanError,
                .duplicateEntry(firstIndex: 0, duplicateIndex: raw.count - 1)
            )
        }
        var payloadVariant = fullCoverageRawEntries()
        let base = payloadVariant[0]
        payloadVariant.append(
            Plan.RawEntry(
                commandID: base.commandID,
                state: base.state,
                isEnabled: true,
                reason: nil
            )
        )
        XCTAssertThrowsError(try Plan.make(rawEntries: payloadVariant)) { error in
            XCTAssertEqual(
                error as? PlanError,
                .duplicateEntry(firstIndex: 0, duplicateIndex: payloadVariant.count - 1)
            )
        }
    }

    func testUnknownCommandDescriptionOmitsBogusID() {
        var raw = fullCoverageRawEntries()
        raw[7] = Plan.RawEntry(commandID: "bogus-command", state: .empty, isEnabled: false, reason: "x")
        XCTAssertThrowsError(try Plan.make(rawEntries: raw)) { error in
            XCTAssertEqual(error as? PlanError, .unknownCommandID(index: 7))
            guard let planError = error as? PlanError else {
                XCTFail("expected plan error")
                return
            }
            XCTAssertFalse("\(planError)".contains("bogus-command"))
            XCTAssertFalse((planError.errorDescription ?? "").contains("bogus-command"))
        }
    }

    func testDisabledEmptyAndWhitespaceReasonsReject() {
        for reason in ["", "   ", "\n\t", "\n\t "] {
            var entries = fullCoverageEntries()
            guard let index = entries.firstIndex(where: { !$0.isEnabled }) else {
                XCTFail("expected disabled entry")
                return
            }
            entries[index] = Plan.Entry(
                command: entries[index].command,
                state: entries[index].state,
                isEnabled: false,
                reason: reason
            )
            XCTAssertThrowsError(try Plan.make(entries: entries), reason.debugDescription) { error in
                XCTAssertEqual(error as? PlanError, .reasonMissing(index: index))
            }
        }
    }

    func testReceiptByteCountGuard() {
        XCTAssertThrowsError(try Plan.Receipt(bytes: [])) { error in
            XCTAssertEqual(error as? PlanError, .receiptByteCount(count: 0))
        }
        XCTAssertThrowsError(try Plan.Receipt(bytes: [UInt8](repeating: 0, count: 31))) { error in
            XCTAssertEqual(error as? PlanError, .receiptByteCount(count: 31))
        }
        XCTAssertThrowsError(try Plan.Receipt(bytes: [UInt8](repeating: 0, count: 33))) { error in
            XCTAssertEqual(error as? PlanError, .receiptByteCount(count: 33))
        }
        XCTAssertNoThrow(try Plan.Receipt(bytes: [UInt8](repeating: 0, count: 32)))
    }

    func testLimitsValidateBeforeWorkFullMatrix() {
        let entries = fullCoverageEntries()
        let cases: [(Limits, PlanError)] = [
            (
                Limits(
                    maximumEntries: 0,
                    maximumReasonUTF8Bytes: 1_024,
                    maximumTotalReasonUTF8Bytes: 266_240,
                    maximumWorkUnits: 100_000,
                    cancellationCheckInterval: 64
                ),
                .invalidLimit(.entries, value: 0)
            ),
            (
                Limits(
                    maximumEntries: 1_024,
                    maximumReasonUTF8Bytes: 0,
                    maximumTotalReasonUTF8Bytes: 266_240,
                    maximumWorkUnits: 100_000,
                    cancellationCheckInterval: 64
                ),
                .invalidLimit(.reasonBytes, value: 0)
            ),
            (
                Limits(
                    maximumEntries: 1_024,
                    maximumReasonUTF8Bytes: 1_024,
                    maximumTotalReasonUTF8Bytes: 0,
                    maximumWorkUnits: 100_000,
                    cancellationCheckInterval: 64
                ),
                .invalidLimit(.totalReasonBytes, value: 0)
            ),
            (
                Limits(
                    maximumEntries: 1_024,
                    maximumReasonUTF8Bytes: 1_024,
                    maximumTotalReasonUTF8Bytes: 266_240,
                    maximumWorkUnits: 0,
                    cancellationCheckInterval: 64
                ),
                .invalidLimit(.workUnits, value: 0)
            ),
            (
                Limits(
                    maximumEntries: 1_024,
                    maximumReasonUTF8Bytes: 1_024,
                    maximumTotalReasonUTF8Bytes: 266_240,
                    maximumWorkUnits: 100_000,
                    cancellationCheckInterval: 0
                ),
                .invalidLimit(.cancellationCheckInterval, value: 0)
            ),
            (
                Limits(
                    maximumEntries: 1_024,
                    maximumReasonUTF8Bytes: 1_024,
                    maximumTotalReasonUTF8Bytes: 512,
                    maximumWorkUnits: 100_000,
                    cancellationCheckInterval: 64
                ),
                .invalidLimit(.totalReasonBytes, value: 512)
            )
        ]
        for (limits, expected) in cases {
            XCTAssertThrowsError(try Plan.make(entries: entries, limits: limits)) { error in
                XCTAssertEqual(error as? PlanError, expected)
            }
            XCTAssertThrowsError(try Plan.make(rawEntries: fullCoverageRawEntries(), limits: limits)) { error in
                XCTAssertEqual(error as? PlanError, expected)
            }
        }
    }

    func testCancellationMidLoopWithInterval() {
        let counter = CancellationCounter()
        XCTAssertThrowsError(
            try Plan.make(
                entries: fullCoverageEntries(),
                limits: Limits(
                    maximumEntries: 1_024,
                    maximumReasonUTF8Bytes: 1_024,
                    maximumTotalReasonUTF8Bytes: 266_240,
                    maximumWorkUnits: 100_000,
                    cancellationCheckInterval: 1
                ),
                cancellationCheck: {
                    if counter.next() > 2 { throw CancellationError() }
                }
            )
        ) { error in
            XCTAssertEqual(error as? PlanError, .cancelled)
        }
    }

    func testCancellationWinsOverWorkLimit() {
        let tight = Limits(
            maximumEntries: 1_024,
            maximumReasonUTF8Bytes: 1_024,
            maximumTotalReasonUTF8Bytes: 266_240,
            maximumWorkUnits: 1,
            cancellationCheckInterval: 64
        )
        XCTAssertThrowsError(
            try Plan.make(
                entries: fullCoverageEntries(),
                limits: tight,
                cancellationCheck: { throw CancellationError() }
            )
        ) { error in
            XCTAssertEqual(error as? PlanError, .cancelled)
        }
        let counter = CancellationCounter()
        XCTAssertThrowsError(
            try Plan.make(
                entries: fullCoverageEntries(),
                limits: tight,
                cancellationCheck: {
                    if counter.next() >= 1 { throw CancellationError() }
                }
            )
        ) { error in
            XCTAssertEqual(error as? PlanError, .cancelled)
        }
    }

    private final class CancellationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    private struct CancellationError: Error {}
}
