import Foundation
import MacMergeCore
import XCTest

final class ToolbarTooltipAuditPlanTests: XCTestCase {
    private typealias Planner = ToolbarTooltipAuditPlan
    private typealias Entry = ToolbarTooltipAuditPlan.Entry
    private typealias Limits = ToolbarTooltipAuditPlan.Limits
    private typealias PlanError = ToolbarTooltipAuditPlan.PlanError
    private typealias Code = ToolbarTooltipAuditPlan.FindingCode

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

    private func canonicalEntries() -> [Entry] {
        ToolbarTooltipShortcutAudit.canonicalEntries.map { auditEntry in
            Entry(
                commandID: auditEntry.winMergeID,
                winMergeTooltip: auditEntry.tooltip,
                macTooltip: auditEntry.tooltip,
                shortcutDisplay: auditEntry.shortcut?.display,
                verdict: .match
            )
        }
    }

    private func makePlan(
        entries: [Entry]? = nil,
        generation: UInt64 = 7,
        limits: Limits = .default,
        cancellationCheck: @escaping Planner.CancellationCheck = {}
    ) throws -> Planner.Result {
        try Planner.plan(
            entries: entries ?? canonicalEntries(),
            generation: generation,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    func testScopeAndDomainAreStable() {
        XCTAssertEqual(Planner.planFormatVersion, 1)
        XCTAssertEqual(Planner.receiptDomain, "toolbar-tooltip-audit.v1")
        XCTAssertFalse(Planner.scopeStatement.isEmpty)
    }

    func testAllowlistCovers26WinMergeCommands() {
        XCTAssertEqual(Planner.allowedCommandIDs.count, 26)
        XCTAssertTrue(Planner.allowedCommandIDs.contains("ID_NEXTDIFF"))
        XCTAssertEqual(
            Set(ToolbarTooltipShortcutAudit.canonicalEntries.map(\.winMergeID)),
            Planner.allowedCommandIDs
        )
    }

    func testHappyPathPassesWithCanonicalTooltips() throws {
        let result = try makePlan()
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.bindings.count, 26)
        XCTAssertEqual(result.entryCount, 26)
        XCTAssertEqual(result.generation, 7)
        XCTAssertEqual(result.receipt.generation, 7)
        XCTAssertEqual(result.receipt.entryCount, 26)
        XCTAssertEqual(result.receipt.findingCount, 0)
        XCTAssertEqual(result.receipt.bytes.count, 32)
        XCTAssertEqual(result.receipt.hex.count, 64)
        XCTAssertEqual(result.bindings.map(\.commandID), result.bindings.map(\.commandID).sorted())
        XCTAssertTrue(result.workPerformed > 0)
    }

    func testReceiptIsOrderIndependent() throws {
        let forward = try makePlan(entries: canonicalEntries(), generation: 9)
        let reversed = try makePlan(entries: Array(canonicalEntries().reversed()), generation: 9)
        XCTAssertEqual(forward.receipt.hex, reversed.receipt.hex)
        XCTAssertEqual(forward.bindings.map(\.commandID), reversed.bindings.map(\.commandID))
    }

    func testReceiptBindsGeneration() throws {
        let first = try makePlan(generation: 1)
        let second = try makePlan(generation: 2)
        XCTAssertNotEqual(first.receipt.hex, second.receipt.hex)
        XCTAssertEqual(first.bindings.first?.generation, 1)
        XCTAssertEqual(second.bindings.first?.generation, 2)
    }

    func testMatchVerdictWithDifferingMacTooltipFindsMismatch() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }) else {
            XCTFail("missing ID_NEXTDIFF")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: original.commandID,
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: "Next Difference (Cmd+Down)",
            shortcutDisplay: original.shortcutDisplay,
            verdict: .match
        )
        let result = try makePlan(entries: entries)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.findings.contains { $0.code == .tooltipMismatch && $0.commandID == "ID_NEXTDIFF" })
        XCTAssertEqual(result.receipt.findingCount, result.findings.count)
    }

    func testDocumentedGapAllowsDifferingMacTooltip() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }) else {
            XCTFail("missing ID_NEXTDIFF")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: original.commandID,
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: "Next Difference (Cmd+Down)",
            shortcutDisplay: "Cmd+Down",
            verdict: .documentedGap
        )
        let result = try makePlan(entries: entries)
        XCTAssertFalse(result.findings.contains { $0.code == .tooltipMismatch })
        XCTAssertFalse(result.findings.contains { $0.code == .unnecessaryGap && $0.commandID == "ID_NEXTDIFF" })
    }

    func testUnnecessaryGapWhenTooltipsEqual() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_REFRESH" }) else {
            XCTFail("missing ID_REFRESH")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: original.commandID,
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: original.winMergeTooltip,
            shortcutDisplay: original.shortcutDisplay,
            verdict: .documentedGap
        )
        let result = try makePlan(entries: entries)
        XCTAssertTrue(result.findings.contains { $0.code == .unnecessaryGap && $0.commandID == "ID_REFRESH" })
    }

    func testMissingCommandProducesFinding() throws {
        let entries = canonicalEntries().filter { $0.commandID != "ID_OPTIONS" }
        let result = try makePlan(entries: entries)
        XCTAssertTrue(result.findings.contains { $0.code == .missingCommand && $0.commandID == "ID_OPTIONS" })
    }

    func testWinMergeTooltipMismatchProducesFinding() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        entries[index] = Entry(
            commandID: "ID_FILE_SAVE",
            winMergeTooltip: "Wrong text",
            macTooltip: "Wrong text",
            shortcutDisplay: "Ctrl+S",
            verdict: .match
        )
        let result = try makePlan(entries: entries)
        XCTAssertTrue(result.findings.contains { $0.code == .winMergeTooltipMismatch })
    }

    func testShortcutCanonicalizationCmdAndFKeyForms() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Cmd+N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("command+n"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘+N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘ + N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌃+C"), "Ctrl+C")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌥+Down"), "Alt+Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⇧+Cmd+Z"), "Shift+Cmd+Z")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("f5"), "F5")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("ctrl+f7"), "Ctrl+F7")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Shift+Cmd+Z"), "Shift+Cmd+Z")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Ctrl+Alt+Right"), "Ctrl+Alt+Right")
        XCTAssertNil(Planner.canonicalShortcutDisplay("Cmd+Cmd+N"))
        XCTAssertNil(Planner.canonicalShortcutDisplay("Cmd+"))
        XCTAssertNil(Planner.canonicalShortcutDisplay("   "))
        XCTAssertNil(Planner.canonicalShortcutDisplay("Cmd+BogusKey"))
    }

    func testTrimmedCommandIDAcceptedAndNormalized() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_FILE_NEW" }) else {
            XCTFail("missing ID_FILE_NEW")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: "  ID_FILE_NEW  ",
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: original.macTooltip,
            shortcutDisplay: original.shortcutDisplay,
            verdict: .match
        )
        let result = try makePlan(entries: entries)
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.bindings.contains { $0.commandID == "ID_FILE_NEW" })
        XCTAssertFalse(result.bindings.contains { $0.commandID == "  ID_FILE_NEW  " })
        XCTAssertFalse(result.findings.contains { $0.code == .missingCommand })
        XCTAssertNotNil(result.binding(for: "  ID_FILE_NEW  "))
    }

    func testPaddedDuplicateCommandRejected() {
        var entries = canonicalEntries()
        guard
            let first = entries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }),
            let second = entries.firstIndex(where: { $0.commandID == "ID_PREVDIFF" })
        else {
            XCTFail("missing diff commands")
            return
        }
        entries[second] = Entry(
            commandID: "  ID_NEXTDIFF ",
            winMergeTooltip: entries[first].winMergeTooltip,
            macTooltip: entries[first].macTooltip,
            shortcutDisplay: entries[first].shortcutDisplay,
            verdict: .match
        )
        do {
            _ = try makePlan(entries: entries)
            XCTFail("expected duplicate")
        } catch let error as PlanError {
            XCTAssertEqual(error, .duplicateCommandID(index: second))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testWrongShortcutProducesFinding() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: original.commandID,
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: original.macTooltip,
            shortcutDisplay: "Ctrl+O",
            verdict: original.verdict
        )
        let result = try makePlan(entries: entries)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(
            result.findings.contains { $0.code == .winMergeShortcutMismatch && $0.commandID == "ID_FILE_SAVE" }
        )
        XCTAssertFalse(result.findings.contains { $0.code == .winMergeTooltipMismatch })
    }

    func testMissingAndExtraShortcutProduceFindings() throws {
        var entries = canonicalEntries()
        guard
            let withShortcut = entries.firstIndex(where: { $0.commandID == "ID_FILE_NEW" }),
            let withoutShortcut = entries.firstIndex(where: { $0.commandID == "ID_ALL_RIGHT" })
        else {
            XCTFail("missing commands")
            return
        }
        let kept = entries[withShortcut]
        entries[withShortcut] = Entry(
            commandID: kept.commandID,
            winMergeTooltip: kept.winMergeTooltip,
            macTooltip: kept.macTooltip,
            shortcutDisplay: nil,
            verdict: kept.verdict
        )
        let dropped = entries[withoutShortcut]
        entries[withoutShortcut] = Entry(
            commandID: dropped.commandID,
            winMergeTooltip: dropped.winMergeTooltip,
            macTooltip: dropped.macTooltip,
            shortcutDisplay: "Ctrl+M",
            verdict: dropped.verdict
        )
        let result = try makePlan(entries: entries)
        XCTAssertTrue(
            result.findings.contains { $0.code == .winMergeShortcutMismatch && $0.commandID == "ID_FILE_NEW" }
        )
        XCTAssertTrue(
            result.findings.contains { $0.code == .winMergeShortcutMismatch && $0.commandID == "ID_ALL_RIGHT" }
        )
    }

    func testDuplicateCommandRejectsWithIndexOnly() {
        let entries = [canonicalEntries()[0], canonicalEntries()[0]]
        do {
            _ = try makePlan(entries: entries)
            XCTFail("expected duplicate")
        } catch let error as PlanError {
            XCTAssertEqual(error, .duplicateCommandID(index: 1))
            XCTAssertFalse(String(describing: error).contains(entries[0].winMergeTooltip))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testUnknownCommandRejectsWithIndexOnly() {
        var entries = canonicalEntries()
        entries[3] = Entry(
            commandID: "ID_NOPE",
            winMergeTooltip: "Tip",
            macTooltip: "Tip",
            verdict: .match
        )
        do {
            _ = try makePlan(entries: entries)
            XCTFail("expected unknown")
        } catch let error as PlanError {
            XCTAssertEqual(error, .unknownCommandID(index: 3))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testEmptyFieldsRejectWithIndexOnly() {
        let cases: [(Entry, PlanError)] = [
            (Entry(commandID: "", winMergeTooltip: "W", macTooltip: "M", verdict: .match), .emptyCommandID(index: 0)),
            (
                Entry(commandID: "ID_NEXTDIFF", winMergeTooltip: "  ", macTooltip: "M", verdict: .match),
                .emptyWinMergeTooltip(index: 0)
            ),
            (
                Entry(commandID: "ID_NEXTDIFF", winMergeTooltip: "W", macTooltip: "", verdict: .match),
                .emptyMacTooltip(index: 0)
            ),
            (
                Entry(
                    commandID: "ID_NEXTDIFF",
                    winMergeTooltip: "W",
                    macTooltip: "M",
                    shortcutDisplay: "???",
                    verdict: .match
                ),
                .invalidShortcut(index: 0)
            )
        ]
        for (entry, expected) in cases {
            do {
                _ = try makePlan(entries: [entry])
                XCTFail("expected \(expected)")
            } catch let error as PlanError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("wrong error \(error)")
            }
        }
    }

    func testErrorDescriptionsCarryIndexAndCountOnly() {
        let secret = "Secret Tooltip XYZZY-12345"
        let entry = Entry(
            commandID: "ID_NEXTDIFF",
            winMergeTooltip: secret,
            macTooltip: secret,
            shortcutDisplay: "???",
            verdict: .match
        )
        do {
            _ = try makePlan(entries: [entry])
            XCTFail("expected invalid shortcut")
        } catch let error as PlanError {
            XCTAssertEqual(error, .invalidShortcut(index: 0))
            XCTAssertFalse(error.localizedDescription.contains(secret))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testEntryCountLimitEnforcedBeforeWork() {
        let limits = Limits(
            maximumEntries: 1,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 65_536,
            maximumFindings: 256,
            cancellationCheckInterval: 16
        )
        do {
            _ = try makePlan(entries: canonicalEntries(), limits: limits)
            XCTFail("expected count limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .countLimitExceeded(count: 26, maximum: 1))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testStringLimitsEnforced() {
        let oversized = String(repeating: "a", count: 2_000)
        let entry = Entry(
            commandID: "ID_NEXTDIFF",
            winMergeTooltip: oversized,
            macTooltip: "M",
            verdict: .match
        )
        do {
            _ = try makePlan(entries: [entry])
            XCTFail("expected string limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .stringTooLarge(index: 0, maximumUTF8Bytes: 1_024))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testTotalStringLimitEnforced() {
        let limits = Limits(
            maximumEntries: 26,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 10,
            maximumWorkUnits: 65_536,
            maximumFindings: 256,
            cancellationCheckInterval: 16
        )
        do {
            _ = try makePlan(entries: canonicalEntries(), limits: limits)
            XCTFail("expected total limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .totalStringsTooLarge(maximumUTF8Bytes: 10))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testWorkLimitEnforcedOverflowSafe() {
        let limits = Limits(
            maximumEntries: 26,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 1,
            maximumFindings: 256,
            cancellationCheckInterval: 16
        )
        do {
            _ = try makePlan(entries: canonicalEntries(), limits: limits)
            XCTFail("expected work limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .workLimitExceeded(maximum: 1))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testFindingLimitEnforced() {
        let limits = Limits(
            maximumEntries: 26,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 65_536,
            maximumFindings: 0,
            cancellationCheckInterval: 16
        )
        let entries = canonicalEntries().filter { $0.commandID != "ID_OPTIONS" }
        do {
            _ = try makePlan(entries: entries, limits: limits)
            XCTFail("expected finding limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .findingLimitExceeded(maximum: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testInvalidLimitsRejectedBeforeWork() {
        let limits = Limits(
            maximumEntries: 999,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 65_536,
            maximumFindings: 256,
            cancellationCheckInterval: 16
        )
        do {
            _ = try makePlan(entries: [], limits: limits)
            XCTFail("expected invalid limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .invalidLimit(.entries, value: 999))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testCancellationAtInterval() {
        let counter = CallCounter()
        do {
            _ = try makePlan(
                entries: canonicalEntries(),
                limits: .default,
                cancellationCheck: {
                    if counter.next() >= 2 { throw TestCancellation() }
                }
            )
            XCTFail("expected cancellation")
        } catch let error as PlanError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testTrimmedIDWithTabsAndNewlinesAccepted() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_FILE_OPEN" }) else {
            XCTFail("missing ID_FILE_OPEN")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: " \tID_FILE_OPEN\n ",
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: original.macTooltip,
            shortcutDisplay: original.shortcutDisplay,
            verdict: .match
        )
        let result = try makePlan(entries: entries)
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.bindings.contains { $0.commandID == "ID_FILE_OPEN" })
        XCTAssertFalse(result.bindings.contains { $0.commandID == " \tID_FILE_OPEN\n " })
        XCTAssertFalse(result.findings.contains { $0.code == .missingCommand })
        XCTAssertNotNil(result.binding(for: " \tID_FILE_OPEN\n "))
    }

    func testPaddedDuplicateWithMixedWhitespaceRejected() {
        var entries = canonicalEntries()
        guard
            let first = entries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }),
            let second = entries.firstIndex(where: { $0.commandID == "ID_PREVDIFF" })
        else {
            XCTFail("missing diff commands")
            return
        }
        entries[second] = Entry(
            commandID: "\n  ID_NEXTDIFF\t ",
            winMergeTooltip: entries[first].winMergeTooltip,
            macTooltip: entries[first].macTooltip,
            shortcutDisplay: entries[first].shortcutDisplay,
            verdict: .match
        )
        do {
            _ = try makePlan(entries: entries)
            XCTFail("expected duplicate")
        } catch let error as PlanError {
            XCTAssertEqual(error, .duplicateCommandID(index: second))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testCmdSymbolExpansionSpacedAndCompact() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘+N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘ + N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘+ N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘ +N"), "Cmd+N")
    }

    func testControlAndOptionSymbolExpansionForms() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌃+N"), "Ctrl+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌃ + N"), "Ctrl+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌥+Down"), "Alt+Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌥ + Down"), "Alt+Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌥+Up"), "Alt+Up")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌃+C"), "Ctrl+C")
    }

    func testWrongShortcutMismatchAgainstCanonicalMap() throws {
        XCTAssertEqual(Planner.canonicalWinMergeShortcutDisplay(for: "ID_FILE_SAVE"), "Ctrl+S")
        XCTAssertEqual(Planner.canonicalWinMergeShortcutDisplay(for: "  ID_FILE_SAVE  "), "Ctrl+S")
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: original.commandID,
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: original.macTooltip,
            shortcutDisplay: "Ctrl+O",
            verdict: original.verdict
        )
        let wrong = try makePlan(entries: entries)
        XCTAssertFalse(wrong.passed)
        XCTAssertTrue(
            wrong.findings.contains { $0.code == .winMergeShortcutMismatch && $0.commandID == "ID_FILE_SAVE" }
        )
        var equivalent = canonicalEntries()
        guard let same = equivalent.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        let kept = equivalent[same]
        equivalent[same] = Entry(
            commandID: kept.commandID,
            winMergeTooltip: kept.winMergeTooltip,
            macTooltip: kept.macTooltip,
            shortcutDisplay: "ctrl + s",
            verdict: kept.verdict
        )
        let matched = try makePlan(entries: equivalent)
        XCTAssertFalse(matched.findings.contains { $0.code == .winMergeShortcutMismatch })
    }

    func testMissingAndExtraShortcutsEachProduceMismatch() throws {
        XCTAssertEqual(Planner.canonicalWinMergeShortcutDisplay(for: "ID_FILE_NEW"), "Ctrl+N")
        XCTAssertNil(Planner.canonicalWinMergeShortcutDisplay(for: "ID_ALL_RIGHT"))
        var missingEntries = canonicalEntries()
        guard let withShortcut = missingEntries.firstIndex(where: { $0.commandID == "ID_FILE_NEW" }) else {
            XCTFail("missing ID_FILE_NEW")
            return
        }
        let kept = missingEntries[withShortcut]
        missingEntries[withShortcut] = Entry(
            commandID: kept.commandID,
            winMergeTooltip: kept.winMergeTooltip,
            macTooltip: kept.macTooltip,
            shortcutDisplay: nil,
            verdict: kept.verdict
        )
        let missing = try makePlan(entries: missingEntries)
        XCTAssertFalse(missing.passed)
        XCTAssertTrue(
            missing.findings.contains { $0.code == .winMergeShortcutMismatch && $0.commandID == "ID_FILE_NEW" }
        )
        var extraEntries = canonicalEntries()
        guard let withoutShortcut = extraEntries.firstIndex(where: { $0.commandID == "ID_ALL_RIGHT" }) else {
            XCTFail("missing ID_ALL_RIGHT")
            return
        }
        let dropped = extraEntries[withoutShortcut]
        extraEntries[withoutShortcut] = Entry(
            commandID: dropped.commandID,
            winMergeTooltip: dropped.winMergeTooltip,
            macTooltip: dropped.macTooltip,
            shortcutDisplay: "Ctrl+M",
            verdict: dropped.verdict
        )
        let extra = try makePlan(entries: extraEntries)
        XCTAssertFalse(extra.passed)
        XCTAssertTrue(
            extra.findings.contains { $0.code == .winMergeShortcutMismatch && $0.commandID == "ID_ALL_RIGHT" }
        )
    }

    // MARK: - Wave5 yellows

    func testBareSymbolsWithoutPlus() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌃N"), "Ctrl+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌥Down"), "Alt+Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⇧Z"), "Shift+Z")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("⌘N"), "Cmd+N")
    }

    func testWordSynonymModifiers() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("control+N"), "Ctrl+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("ctl+N"), "Ctrl+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("CTRL+N"), "Ctrl+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("option+Down"), "Alt+Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("opt+Down"), "Alt+Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("OPT+Down"), "Alt+Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("command+N"), "Cmd+N")
    }

    func testNamedKeysAndFunctionKeyEdges() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Return"), "Enter")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Ctrl+Return"), "Ctrl+Enter")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Esc"), "Escape")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Ctrl+Esc"), "Ctrl+Escape")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("PageUp"), "PageUp")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("PageDown"), "PageDown")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Delete"), "Delete")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Tab"), "Tab")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Space"), "Space")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Insert"), "Insert")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Home"), "Home")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("End"), "End")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Ctrl+PageUp"), "Ctrl+PageUp")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Alt+Delete"), "Alt+Delete")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("F1"), "F1")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("F24"), "F24")
        XCTAssertNil(Planner.canonicalShortcutDisplay("F0"))
        XCTAssertNil(Planner.canonicalShortcutDisplay("F25"))
        XCTAssertNil(Planner.canonicalShortcutDisplay("Ctrl+F0"))
        XCTAssertNil(Planner.canonicalShortcutDisplay("Ctrl+F25"))
    }

    func testSymbolEquivalentMatchesCanonical() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        let kept = entries[index]
        entries[index] = Entry(
            commandID: kept.commandID,
            winMergeTooltip: kept.winMergeTooltip,
            macTooltip: kept.macTooltip,
            shortcutDisplay: "⌃+S",
            verdict: kept.verdict
        )
        let matched = try makePlan(entries: entries)
        XCTAssertFalse(matched.findings.contains { $0.code == .winMergeShortcutMismatch })
        XCTAssertEqual(matched.bindings.first { $0.commandID == "ID_FILE_SAVE" }?.canonicalShortcutDisplay, "Ctrl+S")
    }

    func testCanonicalWinMergeTooltipTrimsCommandID() {
        XCTAssertEqual(Planner.canonicalWinMergeTooltip(for: "ID_FILE_SAVE"), "Save (Ctrl+S)")
        XCTAssertEqual(Planner.canonicalWinMergeTooltip(for: "  ID_FILE_SAVE  "), "Save (Ctrl+S)")
        XCTAssertEqual(Planner.canonicalWinMergeTooltip(for: "\tID_FILE_SAVE\n"), "Save (Ctrl+S)")
        XCTAssertNil(Planner.canonicalWinMergeTooltip(for: "ID_NOPE"))
        XCTAssertNil(Planner.canonicalWinMergeTooltip(for: "  ID_NOPE  "))
    }

    func testInvalidLimitsRejectAllSixKinds() {
        let cases: [(Limits, ToolbarTooltipAuditPlan.Limit)] = [
            (Limits(maximumEntries: 999), .entries),
            (Limits(maximumStringUTF8Bytes: 0), .stringUTF8Bytes),
            (Limits(maximumTotalStringUTF8Bytes: 0), .totalStringUTF8Bytes),
            (Limits(maximumWorkUnits: 0), .workUnits),
            (Limits(maximumFindings: 4_097), .findings),
            (Limits(cancellationCheckInterval: 0), .cancellationCheckInterval),
            (Limits(maximumStringUTF8Bytes: 4_097), .stringUTF8Bytes),
            (Limits(maximumTotalStringUTF8Bytes: 300_000), .totalStringUTF8Bytes),
            (Limits(maximumWorkUnits: 2_000_000), .workUnits),
            (Limits(cancellationCheckInterval: 4_097), .cancellationCheckInterval),
        ]
        for (limits, kind) in cases {
            do {
                _ = try makePlan(entries: [], limits: limits)
                XCTFail("expected invalid \(kind)")
            } catch let error as PlanError {
                switch error {
                case .invalidLimit(let actual, _):
                    XCTAssertEqual(actual, kind)
                default:
                    XCTFail("wrong error \(error) for \(kind)")
                }
            } catch {
                XCTFail("wrong error type \(error)")
            }
        }
    }

    func testLimitsValidationWinsOverCountLimit() {
        let competing = Limits(
            maximumEntries: 1,
            maximumStringUTF8Bytes: 0,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 65_536,
            maximumFindings: 256,
            cancellationCheckInterval: 16
        )
        do {
            _ = try makePlan(entries: canonicalEntries(), limits: competing)
            XCTFail("expected invalid limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .invalidLimit(.stringUTF8Bytes, value: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testIntMaxLimitsRejectedWithoutOverflow() {
        let kinds: [(Limits, ToolbarTooltipAuditPlan.Limit)] = [
            (Limits(maximumEntries: Int.max), .entries),
            (Limits(maximumStringUTF8Bytes: Int.max), .stringUTF8Bytes),
            (Limits(maximumTotalStringUTF8Bytes: Int.max), .totalStringUTF8Bytes),
            (Limits(maximumWorkUnits: Int.max), .workUnits),
            (Limits(maximumFindings: Int.max), .findings),
            (Limits(cancellationCheckInterval: Int.max), .cancellationCheckInterval),
        ]
        for (limits, kind) in kinds {
            do {
                _ = try makePlan(entries: [], limits: limits)
                XCTFail("expected invalid \(kind)")
            } catch let error as PlanError {
                XCTAssertEqual(error, .invalidLimit(kind, value: Int.max))
            } catch {
                XCTFail("wrong error \(error)")
            }
        }
        XCTAssertNoThrow(try makePlan(entries: [], generation: UInt64.max))
        XCTAssertNoThrow(try makePlan(entries: [], limits: Limits(cancellationCheckInterval: 4_096)))
    }

    func testErrorDescriptionsRedactAllCodes() {
        let secret = "Secret XYZZY-98765 tooltip"
        let secretShortcut = "SecretChord-XYZZY-123"
        func assertRedacted(_ error: PlanError, file: StaticString = #filePath, line: UInt = #line) {
            let text = (error.errorDescription ?? "") + String(describing: error)
            XCTAssertFalse(text.contains(secret), "\(error)", file: file, line: line)
            XCTAssertFalse(text.contains(secretShortcut), "\(error)", file: file, line: line)
            XCTAssertFalse(text.contains("ID_NOPE"), "\(error)", file: file, line: line)
        }
        assertRedacted(.invalidLimit(.entries, value: 999))
        assertRedacted(.countLimitExceeded(count: 26, maximum: 1))
        assertRedacted(.stringTooLarge(index: 0, maximumUTF8Bytes: 1_024))
        assertRedacted(.totalStringsTooLarge(maximumUTF8Bytes: 10))
        assertRedacted(.workLimitExceeded(maximum: 1))
        assertRedacted(.findingLimitExceeded(maximum: 0))
        assertRedacted(.emptyCommandID(index: 0))
        assertRedacted(.unknownCommandID(index: 3))
        assertRedacted(.duplicateCommandID(index: 1))
        assertRedacted(.emptyWinMergeTooltip(index: 0))
        assertRedacted(.emptyMacTooltip(index: 0))
        assertRedacted(.invalidShortcut(index: 0))
        assertRedacted(.cancelled)
        do {
            _ = try makePlan(entries: [Entry(commandID: "ID_NOPE", winMergeTooltip: secret, macTooltip: secret, shortcutDisplay: secretShortcut, verdict: .match)])
            XCTFail("expected unknown")
        } catch let error as PlanError {
            assertRedacted(error)
            XCTAssertEqual(error, .unknownCommandID(index: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
        do {
            _ = try makePlan(entries: [Entry(commandID: "ID_NEXTDIFF", winMergeTooltip: secret, macTooltip: secret, shortcutDisplay: secretShortcut, verdict: .match)])
            XCTFail("expected invalid shortcut")
        } catch let error as PlanError {
            assertRedacted(error)
            XCTAssertEqual(error, .invalidShortcut(index: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testFindingMessagesExactWording() throws {
        let missingEntries = canonicalEntries().filter { $0.commandID != "ID_OPTIONS" }
        let missingResult = try makePlan(entries: missingEntries)
        XCTAssertEqual(
            missingResult.findings.first { $0.code == .missingCommand }?.message,
            "Allowlisted command has no audit entry."
        )
        var tooltipEntries = canonicalEntries()
        guard let saveIndex = tooltipEntries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        let saved = tooltipEntries[saveIndex]
        tooltipEntries[saveIndex] = Entry(
            commandID: saved.commandID,
            winMergeTooltip: "Wrong text",
            macTooltip: "Wrong text",
            shortcutDisplay: "Ctrl+S",
            verdict: .match
        )
        let tooltipResult = try makePlan(entries: tooltipEntries)
        XCTAssertEqual(
            tooltipResult.findings.first { $0.code == .winMergeTooltipMismatch }?.message,
            "WinMerge tooltip does not match the canonical text for this command."
        )
        var shortcutEntries = canonicalEntries()
        shortcutEntries[saveIndex] = Entry(
            commandID: saved.commandID,
            winMergeTooltip: saved.winMergeTooltip,
            macTooltip: saved.macTooltip,
            shortcutDisplay: "Ctrl+O",
            verdict: saved.verdict
        )
        let shortcutResult = try makePlan(entries: shortcutEntries)
        XCTAssertEqual(
            shortcutResult.findings.first { $0.code == .winMergeShortcutMismatch }?.message,
            "Shortcut display does not match the canonical shortcut for this command."
        )
        var mismatchEntries = canonicalEntries()
        guard let diffIndex = mismatchEntries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }) else {
            XCTFail("missing ID_NEXTDIFF")
            return
        }
        let diff = mismatchEntries[diffIndex]
        mismatchEntries[diffIndex] = Entry(
            commandID: diff.commandID,
            winMergeTooltip: diff.winMergeTooltip,
            macTooltip: "Different",
            shortcutDisplay: diff.shortcutDisplay,
            verdict: .match
        )
        let mismatchResult = try makePlan(entries: mismatchEntries)
        XCTAssertEqual(
            mismatchResult.findings.first { $0.code == .tooltipMismatch }?.message,
            "Mac tooltip differs from WinMerge text but verdict claims match."
        )
        var gapEntries = canonicalEntries()
        guard let refreshIndex = gapEntries.firstIndex(where: { $0.commandID == "ID_REFRESH" }) else {
            XCTFail("missing ID_REFRESH")
            return
        }
        let refresh = gapEntries[refreshIndex]
        gapEntries[refreshIndex] = Entry(
            commandID: refresh.commandID,
            winMergeTooltip: refresh.winMergeTooltip,
            macTooltip: refresh.winMergeTooltip,
            shortcutDisplay: refresh.shortcutDisplay,
            verdict: .documentedGap
        )
        let gapResult = try makePlan(entries: gapEntries)
        XCTAssertEqual(
            gapResult.findings.first { $0.code == .unnecessaryGap }?.message,
            "Mac tooltip equals WinMerge text but verdict claims a documented gap."
        )
        let secret = "Secret XYZZY-555"
        var secretEntries = canonicalEntries()
        secretEntries[saveIndex] = Entry(
            commandID: saved.commandID,
            winMergeTooltip: "Wrong \(secret)",
            macTooltip: "Wrong \(secret)",
            shortcutDisplay: "Ctrl+S",
            verdict: .match
        )
        let secretResult = try makePlan(entries: secretEntries)
        for finding in secretResult.findings {
            XCTAssertFalse(finding.message.contains(secret))
        }
    }

    func testFindingLimitEnforcedInTooltipAndShortcutLoops() {
        let zeroFindings = Limits(
            maximumEntries: 26,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 65_536,
            maximumFindings: 0,
            cancellationCheckInterval: 16
        )
        var tooltipEntries = canonicalEntries()
        guard let saveIndex = tooltipEntries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        let saved = tooltipEntries[saveIndex]
        tooltipEntries[saveIndex] = Entry(
            commandID: saved.commandID,
            winMergeTooltip: "Wrong text",
            macTooltip: "Wrong text",
            shortcutDisplay: "Ctrl+S",
            verdict: .match
        )
        do {
            _ = try makePlan(entries: tooltipEntries, limits: zeroFindings)
            XCTFail("expected finding limit in tooltip loop")
        } catch let error as PlanError {
            XCTAssertEqual(error, .findingLimitExceeded(maximum: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
        var shortcutEntries = canonicalEntries()
        shortcutEntries[saveIndex] = Entry(
            commandID: saved.commandID,
            winMergeTooltip: saved.winMergeTooltip,
            macTooltip: saved.macTooltip,
            shortcutDisplay: "Ctrl+O",
            verdict: saved.verdict
        )
        do {
            _ = try makePlan(entries: shortcutEntries, limits: zeroFindings)
            XCTFail("expected finding limit in shortcut loop")
        } catch let error as PlanError {
            XCTAssertEqual(error, .findingLimitExceeded(maximum: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testCustomCancellationIntervalAndValidation() throws {
        do {
            _ = try makePlan(entries: [], limits: Limits(cancellationCheckInterval: 0))
            XCTFail("expected invalid interval")
        } catch let error as PlanError {
            XCTAssertEqual(error, .invalidLimit(.cancellationCheckInterval, value: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
        do {
            _ = try makePlan(entries: [], limits: Limits(cancellationCheckInterval: 4_097))
            XCTFail("expected invalid interval")
        } catch let error as PlanError {
            XCTAssertEqual(error, .invalidLimit(.cancellationCheckInterval, value: 4_097))
        } catch {
            XCTFail("wrong error \(error)")
        }
        let custom = Limits(
            maximumEntries: 26,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 65_536,
            maximumFindings: 256,
            cancellationCheckInterval: 1
        )
        let ok = try makePlan(entries: canonicalEntries(), limits: custom, cancellationCheck: {})
        XCTAssertTrue(ok.passed)
        let counter = CallCounter()
        do {
            _ = try makePlan(
                entries: canonicalEntries(),
                limits: custom,
                cancellationCheck: {
                    if counter.next() >= 1 { throw TestCancellation() }
                }
            )
            XCTFail("expected cancellation with interval 1")
        } catch let error as PlanError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testReceiptBindsCounts() throws {
        let happy = try makePlan()
        XCTAssertEqual(happy.receipt.entryCount, 26)
        XCTAssertEqual(happy.receipt.findingCount, 0)
        XCTAssertEqual(happy.receipt.findingCount, happy.findings.count)
        XCTAssertEqual(happy.receipt.entryCount, happy.bindings.count)
        let missing = try makePlan(entries: canonicalEntries().filter { $0.commandID != "ID_OPTIONS" })
        XCTAssertEqual(missing.receipt.entryCount, 25)
        XCTAssertEqual(missing.receipt.findingCount, 1)
        XCTAssertEqual(missing.receipt.findingCount, missing.findings.count)
        XCTAssertNotEqual(happy.receipt.hex, missing.receipt.hex)
        var tooltipEntries = canonicalEntries()
        guard let index = tooltipEntries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        let saved = tooltipEntries[index]
        tooltipEntries[index] = Entry(
            commandID: saved.commandID,
            winMergeTooltip: "Wrong text",
            macTooltip: "Wrong text",
            shortcutDisplay: "Ctrl+S",
            verdict: .match
        )
        let oneFinding = try makePlan(entries: tooltipEntries)
        XCTAssertEqual(oneFinding.receipt.entryCount, 26)
        XCTAssertEqual(oneFinding.receipt.findingCount, 1)
        XCTAssertNotEqual(happy.receipt.hex, oneFinding.receipt.hex)
        XCTAssertEqual(oneFinding.receipt.bytes.count, 32)
        XCTAssertEqual(oneFinding.receipt.hex.count, 64)
    }

    func testAllowlistLiteral26IDs() {
        // WinMerge Src/Merge2.rc IDR_MAINFRAME order plus Src/Merge.rc tooltip rows.
        let literal: [String] = [
            "ID_FILE_NEW", "ID_FILE_OPEN", "ID_FILE_SAVE",
            "ID_EDIT_UNDO", "ID_EDIT_REDO",
            "ID_SELECTLINEDIFF",
            "ID_NEXTDIFF", "ID_PREVDIFF",
            "ID_NEXTCONFLICT", "ID_PREVCONFLICT",
            "ID_FIRSTDIFF", "ID_CURDIFF", "ID_LASTDIFF",
            "ID_L2R", "ID_R2L", "ID_L2RNEXT", "ID_R2LNEXT",
            "ID_ALL_RIGHT", "ID_ALL_LEFT",
            "ID_AUTO_MERGE",
            "ID_FIRSTFILE", "ID_PREVFILE", "ID_NEXTFILE", "ID_LASTFILE",
            "ID_OPTIONS", "ID_REFRESH",
        ]
        XCTAssertEqual(literal.count, 26)
        XCTAssertEqual(Set(literal), Planner.allowedCommandIDs)
        XCTAssertEqual(Set(literal), Set(ToolbarTooltipShortcutAudit.canonicalEntries.map(\.winMergeID)))
        XCTAssertEqual(Planner.allowedCommandIDs.count, 26)
    }

    // MARK: - Wave6 lane8

    func testLimitsDefaultsAndHardMaximumsLocked() {
        let defaults = Limits()
        XCTAssertEqual(defaults.maximumEntries, 26)
        XCTAssertEqual(defaults.maximumStringUTF8Bytes, 1_024)
        XCTAssertEqual(defaults.maximumTotalStringUTF8Bytes, 64 * 1_024)
        XCTAssertEqual(defaults.maximumWorkUnits, 65_536)
        XCTAssertEqual(defaults.maximumFindings, 256)
        XCTAssertEqual(defaults.cancellationCheckInterval, 16)
        XCTAssertEqual(Limits.hardMaximumEntries, 26)
        XCTAssertEqual(Limits.hardMaximumStringUTF8Bytes, 4 * 1_024)
        XCTAssertEqual(Limits.hardMaximumTotalStringUTF8Bytes, 256 * 1_024)
        XCTAssertEqual(Limits.hardMaximumWorkUnits, 1_024 * 1_024)
        XCTAssertEqual(Limits.hardMaximumFindings, 4_096)
        XCTAssertEqual(Limits.hardMaximumCancellationCheckInterval, 4_096)
        XCTAssertEqual(Planner.Receipt.byteCount, 32)
    }

    func testEnumCaseCountsLocked() {
        XCTAssertEqual(Planner.Verdict.allCases.count, 2)
        XCTAssertEqual(Planner.FindingCode.allCases.count, 5)
        XCTAssertEqual(Planner.Limit.allCases.count, 6)
    }

    func testEmptyPlanReportsAll26MissingCommands() throws {
        let result = try makePlan(entries: [], generation: 3)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.entryCount, 0)
        XCTAssertTrue(result.bindings.isEmpty)
        XCTAssertEqual(result.findings.count, 26)
        XCTAssertTrue(result.findings.allSatisfy { $0.code == .missingCommand && $0.entryIndex == nil })
        XCTAssertEqual(result.findings.map(\.commandID), result.findings.map(\.commandID).sorted())
        XCTAssertEqual(result.receipt.entryCount, 0)
        XCTAssertEqual(result.receipt.findingCount, 26)
        XCTAssertEqual(result.receipt.formatVersion, Planner.planFormatVersion)
        XCTAssertEqual(result.receipt.hex, result.receipt.hex.lowercased())
    }

    func testFindingsSortByCodeThenCommandID() throws {
        var entries = canonicalEntries().filter { $0.commandID != "ID_OPTIONS" }
        guard
            let refreshIndex = entries.firstIndex(where: { $0.commandID == "ID_REFRESH" }),
            let diffIndex = entries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }),
            let saveIndex = entries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }),
            let openIndex = entries.firstIndex(where: { $0.commandID == "ID_FILE_OPEN" })
        else {
            XCTFail("missing commands")
            return
        }
        let refresh = entries[refreshIndex]
        entries[refreshIndex] = Entry(
            commandID: refresh.commandID,
            winMergeTooltip: refresh.winMergeTooltip,
            macTooltip: refresh.winMergeTooltip,
            shortcutDisplay: refresh.shortcutDisplay,
            verdict: .documentedGap
        )
        let diff = entries[diffIndex]
        entries[diffIndex] = Entry(
            commandID: diff.commandID,
            winMergeTooltip: diff.winMergeTooltip,
            macTooltip: "Different",
            shortcutDisplay: diff.shortcutDisplay,
            verdict: .match
        )
        let saved = entries[saveIndex]
        entries[saveIndex] = Entry(
            commandID: saved.commandID,
            winMergeTooltip: saved.winMergeTooltip,
            macTooltip: saved.macTooltip,
            shortcutDisplay: "Ctrl+O",
            verdict: saved.verdict
        )
        let opened = entries[openIndex]
        entries[openIndex] = Entry(
            commandID: opened.commandID,
            winMergeTooltip: "Wrong text",
            macTooltip: "Wrong text",
            shortcutDisplay: opened.shortcutDisplay,
            verdict: .match
        )
        let result = try makePlan(entries: entries)
        XCTAssertEqual(
            result.findings.map(\.code),
            [
                .missingCommand,
                .tooltipMismatch,
                .unnecessaryGap,
                .winMergeShortcutMismatch,
                .winMergeTooltipMismatch,
            ]
        )
    }

    func testBindingLookupMissesAndPassthrough() throws {
        let result = try makePlan()
        XCTAssertNil(result.binding(for: "ID_NOPE"))
        XCTAssertNil(result.binding(for: ""))
        XCTAssertNil(result.binding(for: "   "))
        XCTAssertEqual(result.binding(for: "ID_FILE_SAVE")?.canonicalShortcutDisplay, "Ctrl+S")
        XCTAssertNil(result.binding(for: "ID_ALL_RIGHT")?.canonicalShortcutDisplay)
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }) else {
            XCTFail("missing ID_NEXTDIFF")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: original.commandID,
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: "Next Difference (Cmd+Down)",
            shortcutDisplay: original.shortcutDisplay,
            verdict: .documentedGap
        )
        let gap = try makePlan(entries: entries)
        XCTAssertEqual(gap.binding(for: "ID_NEXTDIFF")?.verdict, .documentedGap)
        XCTAssertEqual(gap.binding(for: "ID_NEXTDIFF")?.macTooltip, "Next Difference (Cmd+Down)")
        XCTAssertTrue(gap.bindings.allSatisfy { $0.generation == gap.generation })
    }

    func testWorkPerformedDeterministic() throws {
        let first = try makePlan(entries: canonicalEntries(), generation: 11)
        let second = try makePlan(entries: canonicalEntries(), generation: 11)
        XCTAssertEqual(first.workPerformed, second.workPerformed)
        let reversed = try makePlan(entries: Array(canonicalEntries().reversed()), generation: 11)
        XCTAssertEqual(first.workPerformed, reversed.workPerformed)
    }

    func testShortcutDisplayRejectsUnknownModifierAndCaseInsensitiveDuplicate() {
        XCTAssertNil(Planner.canonicalShortcutDisplay("Foo+N"))
        XCTAssertNil(Planner.canonicalShortcutDisplay("Ctrl+ctrl+C"))
        XCTAssertNil(Planner.canonicalShortcutDisplay("Cmd+Shift+Cmd+Z"))
    }

    func testShortcutDisplayBareKeys() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("N"), "N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("n"), "N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Enter"), "Enter")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("down"), "Down")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("up"), "Up")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("left"), "Left")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("pageup"), "PageUp")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("pagedown"), "PageDown")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("backspace"), "Backspace")
    }

    func testShortcutDisplayReordersModifiersAndCollapsesPlus() {
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Cmd+Ctrl+N"), "Ctrl+Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Cmd+Shift+Z"), "Shift+Cmd+Z")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Cmd+Alt+Ctrl+N"), "Ctrl+Alt+Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Cmd++N"), "Cmd+N")
        XCTAssertEqual(Planner.canonicalShortcutDisplay("Cmd+ +N"), "Cmd+N")
    }

    func testDecomposedUnicodeNormalizesAndStabilizesReceipt() throws {
        let decomposedTip = "Cafe\u{301}"
        let precomposedTip = "Caf\u{E9}"
        XCTAssertEqual(decomposedTip.utf8.count, 6)
        XCTAssertEqual(precomposedTip.utf8.count, 5)
        let decomposed = Entry(
            commandID: "ID_NEXTDIFF",
            winMergeTooltip: decomposedTip,
            macTooltip: decomposedTip,
            verdict: .match
        )
        XCTAssertEqual(Array(decomposed.winMergeTooltip.utf8), Array(precomposedTip.utf8))
        let precomposed = Entry(
            commandID: "ID_NEXTDIFF",
            winMergeTooltip: precomposedTip,
            macTooltip: precomposedTip,
            verdict: .match
        )
        let first = try makePlan(entries: [decomposed])
        let second = try makePlan(entries: [precomposed])
        XCTAssertEqual(first.receipt.hex, second.receipt.hex)
    }

    func testByteCountingUsesUTF8NotCharacters() {
        let multibyte = String(repeating: "é", count: 600)
        XCTAssertEqual(multibyte.count, 600)
        XCTAssertEqual(multibyte.utf8.count, 1_200)
        let entry = Entry(
            commandID: "ID_NEXTDIFF",
            winMergeTooltip: multibyte,
            macTooltip: "M",
            verdict: .match
        )
        do {
            _ = try makePlan(entries: [entry])
            XCTFail("expected string limit")
        } catch let error as PlanError {
            XCTAssertEqual(error, .stringTooLarge(index: 0, maximumUTF8Bytes: 1_024))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testExactByteBoundaryPasses() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_NEXTDIFF" }) else {
            XCTFail("missing ID_NEXTDIFF")
            return
        }
        let original = entries[index]
        entries[index] = Entry(
            commandID: original.commandID,
            winMergeTooltip: original.winMergeTooltip,
            macTooltip: String(repeating: "a", count: 1_024),
            shortcutDisplay: original.shortcutDisplay,
            verdict: .documentedGap
        )
        let result = try makePlan(entries: [entries[index]])
        XCTAssertEqual(result.bindings.count, 1)
        XCTAssertEqual(result.bindings.first?.macTooltip.count, 1_024)
    }

    func testUnknownBeatsDuplicateForRepeatedUnknownID() {
        let entry = Entry(commandID: "ID_NOPE", winMergeTooltip: "W", macTooltip: "M", verdict: .match)
        do {
            _ = try makePlan(entries: [entry, entry])
            XCTFail("expected unknown")
        } catch let error as PlanError {
            XCTAssertEqual(error, .unknownCommandID(index: 0))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testCancellationWinsOverCountLimit() {
        let limits = Limits(
            maximumEntries: 1,
            maximumStringUTF8Bytes: 1_024,
            maximumTotalStringUTF8Bytes: 64 * 1_024,
            maximumWorkUnits: 65_536,
            maximumFindings: 256,
            cancellationCheckInterval: 16
        )
        do {
            _ = try makePlan(
                entries: canonicalEntries(),
                limits: limits,
                cancellationCheck: { throw TestCancellation() }
            )
            XCTFail("expected cancellation")
        } catch let error as PlanError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testCanonicalLookupsRejectUnknownAndBlank() {
        XCTAssertNil(Planner.canonicalWinMergeTooltip(for: ""))
        XCTAssertNil(Planner.canonicalWinMergeTooltip(for: "   "))
        XCTAssertNil(Planner.canonicalWinMergeShortcutDisplay(for: "ID_NOPE"))
        XCTAssertNil(Planner.canonicalWinMergeShortcutDisplay(for: "  ID_NOPE  "))
        XCTAssertNil(Planner.canonicalWinMergeShortcutDisplay(for: ""))
    }

    func testFindingUsesTrimmedCommandID() throws {
        var entries = canonicalEntries()
        guard let index = entries.firstIndex(where: { $0.commandID == "ID_FILE_SAVE" }) else {
            XCTFail("missing ID_FILE_SAVE")
            return
        }
        entries[index] = Entry(
            commandID: "  ID_FILE_SAVE  ",
            winMergeTooltip: "Wrong text",
            macTooltip: "Wrong text",
            shortcutDisplay: "Ctrl+S",
            verdict: .match
        )
        let result = try makePlan(entries: entries)
        let finding = result.findings.first { $0.code == .winMergeTooltipMismatch }
        XCTAssertEqual(finding?.commandID, "ID_FILE_SAVE")
        XCTAssertEqual(finding?.entryIndex, index)
    }
}
