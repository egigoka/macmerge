import Foundation
import MacMergeCore
import XCTest

final class ToolbarAccessibilityInventoryTests: XCTestCase {
    private typealias Planner = ToolbarAccessibilityInventory
    private typealias Command = ToolbarConfiguration.Command
    private typealias Input = ToolbarAccessibilityInventory.ControlInput
    private typealias Limits = ToolbarAccessibilityInventory.Limits
    private typealias InventoryError = ToolbarAccessibilityInventory.InventoryError
    private typealias Code = ToolbarAccessibilityInventory.FindingCode

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

    private func canonicalCommands() -> [Command] {
        ToolbarAuditManifest.canonical.commands
    }

    private func uniqueInputs(commands: [Command]? = nil) -> [Input] {
        let targets = commands ?? canonicalCommands()
        return targets.map { command in
            Input(
                command: command,
                label: "Label \(command.rawValue)",
                hint: "Hint \(command.rawValue)",
                tooltip: "Tip \(command.rawValue)"
            )
        }
    }

    private func valuedInputs(label base: String, sharedValue: String?, targets: [Command]) -> [Input] {
        uniqueInputs().map { input in
            guard targets.contains(input.command) else { return input }
            return Input(
                command: input.command,
                label: base,
                value: sharedValue,
                hint: "Hint \(input.command.rawValue)",
                tooltip: "Tip \(input.command.rawValue)"
            )
        }
    }

    private func plan(
        inputs: [Input]? = nil,
        focusOrder: [Command]? = nil,
        manifest: ToolbarAuditManifest = .canonical,
        limits: Limits = .default,
        cancellationCheck: @escaping Planner.CancellationCheck = {}
    ) throws -> Planner.Result {
        try Planner.plan(
            inputs: inputs ?? uniqueInputs(),
            focusOrder: focusOrder,
            manifest: manifest,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    private func codes(in result: Planner.Result) -> [Code] {
        result.findings.map(\.code)
    }

    private func findings(_ code: Code, in result: Planner.Result) -> [Planner.Finding] {
        result.findings.filter { $0.code == code }
    }

    func testHappyPathPassesWithCanonicalManifest() throws {
        let result = try plan()
        let commands = canonicalCommands()

        XCTAssertTrue(result.passed)
        XCTAssertFalse(result.containsErrors)
        XCTAssertNil(result.highestSeverity)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.inventory.bindings.count, commands.count)
        XCTAssertEqual(result.inventory.focusOrder.count, commands.count)
        XCTAssertEqual(result.receipt.controlCount, commands.count)
        XCTAssertEqual(result.receipt.focusOrderCount, commands.count)
        XCTAssertEqual(result.receipt.findingCount, 0)
        XCTAssertEqual(result.receipt.formatVersion, Planner.inventoryFormatVersion)
        XCTAssertEqual(result.inventory.manifestRevision, ToolbarAuditManifest.canonicalRevision)
        XCTAssertEqual(result.receipt.manifestRevision, ToolbarAuditManifest.canonicalRevision)
    }

    func testScopeStatementAndFormatVersionAreStable() {
        XCTAssertEqual(Planner.inventoryFormatVersion, 1)
        XCTAssertFalse(Planner.scopeStatement.isEmpty)
    }

    func testControlIDFormatsAreStable() {
        XCTAssertEqual(Planner.controlID(for: .save).rawValue, "toolbar.save")
        XCTAssertEqual(Planner.primaryActionID(for: .save).rawValue, "toolbar.save.primary")
    }

    func testBindingsHaveUniqueIDsAndActions() throws {
        let result = try plan()
        let ids = result.inventory.bindings.map(\.id)
        let actions = result.inventory.bindings.map(\.primaryActionID)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(actions).count, actions.count)
        XCTAssertTrue(Set(ids).isDisjoint(with: Set(actions)))
        for binding in result.inventory.bindings {
            XCTAssertEqual(binding.id, Planner.controlID(for: binding.command))
            XCTAssertEqual(binding.primaryActionID, Planner.primaryActionID(for: binding.command))
        }
        XCTAssertEqual(
            result.inventory.bindings.map(\.focusIndex),
            Array(0..<result.inventory.bindings.count)
        )
        let save = try XCTUnwrap(result.inventory.binding(for: .save))
        XCTAssertEqual(save.command, .save)
        XCTAssertEqual(
            result.inventory.controlRequirements().map(\.command),
            result.inventory.bindings.map(\.command)
        )
    }

    func testBindingsExposeButtonAXMetadata() throws {
        let result = try plan()

        for binding in result.inventory.bindings {
            XCTAssertEqual(binding.accessibility.identifier, binding.id)
            XCTAssertEqual(binding.accessibility.role, .button)
            XCTAssertNil(binding.accessibility.value)
            XCTAssertTrue(binding.accessibility.isKeyboardFocusable)
            XCTAssertEqual(binding.accessibility.actions, [.activate])
            XCTAssertFalse(binding.accessibility.label.isEmpty)
            XCTAssertFalse(binding.accessibility.hint.isEmpty)
            XCTAssertFalse(binding.tooltip.isEmpty)
        }
        let save = try XCTUnwrap(result.inventory.binding(for: .save))
        XCTAssertEqual(save.accessibility.label, "Label save")
        XCTAssertEqual(save.accessibility.hint, "Hint save")
        XCTAssertEqual(save.tooltip, "Tip save")
    }

    func testDefaultFocusOrderMatchesManifestOrder() throws {
        let result = try plan()
        let commands = canonicalCommands()

        XCTAssertEqual(result.inventory.bindings.map(\.command), commands)
        XCTAssertEqual(result.inventory.focusOrder, commands.map(Planner.controlID))
    }

    func testCallerFocusOrderHonoredInResolvedOrder() throws {
        let commands = canonicalCommands()
        let reversed = Array(commands.reversed())
        let result = try plan(inputs: uniqueInputs(), focusOrder: reversed)

        XCTAssertEqual(result.inventory.focusOrder, reversed.map(Planner.controlID))
        XCTAssertEqual(result.inventory.bindings.map(\.command), reversed)
        XCTAssertEqual(result.inventory.bindings.map(\.focusIndex), Array(0..<commands.count))
        XCTAssertTrue(codes(in: result).contains(.focusOrderMismatch))
    }

    func testPartialFocusOrderAppendsRemainingManifestCommands() throws {
        let commands = canonicalCommands()
        let head = Array(commands.prefix(2))
        let result = try plan(inputs: uniqueInputs(), focusOrder: head)
        let expected = head + commands.filter { !head.contains($0) }

        XCTAssertEqual(result.inventory.bindings.map(\.command), expected)
        XCTAssertEqual(result.inventory.focusOrder, expected.map(Planner.controlID))
        XCTAssertFalse(findings(.focusOrderMissing, in: result).isEmpty)
        XCTAssertTrue(findings(.focusOrderUnexpected, in: result).isEmpty)
    }

    func testMissingControlFinding() throws {
        var inputs = uniqueInputs()
        inputs.removeAll { $0.command == .save }
        let result = try plan(inputs: inputs)
        let missing = findings(.missingControl, in: result)

        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.command, .save)
        XCTAssertEqual(missing.first?.subjectID, Planner.controlID(for: .save))
        XCTAssertEqual(missing.first?.severity, .error)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.containsErrors)
        XCTAssertEqual(result.highestSeverity, .error)
    }

    func testUnexpectedControlFinding() throws {
        let manifest = ToolbarAuditManifest(
            revision: ToolbarAuditRevision(rawValue: 7),
            items: [.command(.save), .command(.undo)]
        )
        let result = try plan(inputs: uniqueInputs(commands: [.save, .undo, .redo]), manifest: manifest)
        let unexpected = findings(.unexpectedControl, in: result)

        XCTAssertEqual(unexpected.count, 1)
        XCTAssertEqual(unexpected.first?.command, .redo)
        XCTAssertEqual(unexpected.first?.severity, .error)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(result.inventory.bindings.count, 2)
        XCTAssertEqual(result.inventory.manifestRevision, ToolbarAuditRevision(rawValue: 7))
    }

    func testDuplicateControlFinding() throws {
        let manifest = ToolbarAuditManifest(
            revision: ToolbarAuditRevision(rawValue: 11),
            items: [.command(.save), .command(.undo)]
        )
        var inputs = uniqueInputs(commands: [.save, .undo])
        let save = try XCTUnwrap(inputs.first { $0.command == .save })
        inputs.append(save)
        let result = try plan(inputs: inputs, manifest: manifest)
        let duplicates = findings(.duplicateControl, in: result)

        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.command, .save)
        XCTAssertEqual(duplicates.first?.subjectID, Planner.controlID(for: .save))
        XCTAssertTrue(findings(.missingControl, in: result).isEmpty)
    }

    func testBlankTextFindings() throws {
        let commands = canonicalCommands()
        let inputs: [Input] = uniqueInputs().map { input in
            if input.command == commands[0] {
                return Input(
                    command: input.command,
                    label: "   ",
                    hint: "Hint \(input.command.rawValue)",
                    tooltip: "Tip \(input.command.rawValue)"
                )
            }
            if input.command == commands[1] {
                return Input(
                    command: input.command,
                    label: "Label \(input.command.rawValue)",
                    hint: " \t ",
                    tooltip: "Tip \(input.command.rawValue)"
                )
            }
            if input.command == commands[2] {
                return Input(
                    command: input.command,
                    label: "Label \(input.command.rawValue)",
                    hint: "Hint \(input.command.rawValue)",
                    tooltip: "\n"
                )
            }
            return input
        }
        let result = try plan(inputs: inputs)

        XCTAssertEqual(findings(.blankLabel, in: result).count, 1)
        XCTAssertEqual(findings(.blankLabel, in: result).first?.command, commands[0])
        XCTAssertEqual(findings(.blankHint, in: result).count, 1)
        XCTAssertEqual(findings(.blankHint, in: result).first?.command, commands[1])
        XCTAssertEqual(findings(.blankTooltip, in: result).count, 1)
        XCTAssertEqual(findings(.blankTooltip, in: result).first?.command, commands[2])
    }

    func testDuplicateLabelFinding() throws {
        let commands = canonicalCommands()
        let targets = Array(commands.prefix(2))
        let inputs = uniqueInputs().map { input in
            guard targets.contains(input.command) else { return input }
            return Input(
                command: input.command,
                label: "Shared Label",
                hint: "Hint \(input.command.rawValue)",
                tooltip: "Tip \(input.command.rawValue)"
            )
        }
        let result = try plan(inputs: inputs)
        let duplicates = findings(.duplicateLabel, in: result)

        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(Set(duplicates.compactMap(\.command)), Set(targets))
    }

    func testNonNilValueFinding() throws {
        let target = canonicalCommands()[0]
        let inputs = valuedInputs(label: "Label \(target.rawValue)", sharedValue: "Only Here", targets: [target])
        let result = try plan(inputs: inputs)

        XCTAssertEqual(findings(.nonNilValue, in: result).count, 1)
        XCTAssertEqual(findings(.nonNilValue, in: result).first?.command, target)
        XCTAssertTrue(findings(.duplicateValue, in: result).isEmpty)
    }

    func testDuplicateValueFinding() throws {
        let commands = canonicalCommands()
        let targets = Array(commands.prefix(2))
        var inputs = uniqueInputs()
        inputs = inputs.map { input in
            guard targets.contains(input.command) else { return input }
            return Input(
                command: input.command,
                label: "Label \(input.command.rawValue)",
                value: "Shared Value",
                hint: "Hint \(input.command.rawValue)",
                tooltip: "Tip \(input.command.rawValue)"
            )
        }
        let result = try plan(inputs: inputs)

        XCTAssertEqual(findings(.duplicateValue, in: result).count, 2)
        XCTAssertEqual(findings(.nonNilValue, in: result).count, 2)
    }

    func testDuplicateHintFinding() throws {
        let commands = canonicalCommands()
        let targets = Array(commands.prefix(2))
        let inputs = uniqueInputs().map { input in
            guard targets.contains(input.command) else { return input }
            return Input(
                command: input.command,
                label: "Label \(input.command.rawValue)",
                hint: "Shared Hint",
                tooltip: "Tip \(input.command.rawValue)"
            )
        }
        let result = try plan(inputs: inputs)
        let duplicates = findings(.duplicateHint, in: result)

        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(Set(duplicates.compactMap(\.command)), Set(targets))
    }

    func testDuplicateTooltipFinding() throws {
        let commands = canonicalCommands()
        let targets = Array(commands.prefix(2))
        let inputs = uniqueInputs().map { input in
            guard targets.contains(input.command) else { return input }
            return Input(
                command: input.command,
                label: "Label \(input.command.rawValue)",
                hint: "Hint \(input.command.rawValue)",
                tooltip: "Shared Tip"
            )
        }
        let result = try plan(inputs: inputs)
        let duplicates = findings(.duplicateTooltip, in: result)

        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(Set(duplicates.compactMap(\.command)), Set(targets))
    }

    func testFocusOrderMissingAndUnexpectedFindings() throws {
        let manifest = ToolbarAuditManifest(
            revision: ToolbarAuditRevision(rawValue: 9),
            items: [.command(.save), .command(.undo), .command(.redo)]
        )
        let inputs = uniqueInputs(commands: [.save, .undo, .redo])
        let result = try plan(inputs: inputs, focusOrder: [.save, .refresh], manifest: manifest)
        let missing = findings(.focusOrderMissing, in: result)
        let unexpected = findings(.focusOrderUnexpected, in: result)

        XCTAssertEqual(Set(missing.compactMap(\.command)), Set([.undo, .redo]))
        XCTAssertEqual(unexpected.count, 1)
        XCTAssertEqual(unexpected.first?.command, .refresh)
        XCTAssertEqual(result.findings.count, 3)
        XCTAssertEqual(result.inventory.bindings.map(\.command), [.save, .undo, .redo])
    }

    func testFocusOrderDuplicateFinding() throws {
        let manifest = ToolbarAuditManifest(
            revision: ToolbarAuditRevision(rawValue: 13),
            items: [.command(.save), .command(.undo), .command(.redo)]
        )
        let inputs = uniqueInputs(commands: [.save, .undo, .redo])
        let result = try plan(inputs: inputs, focusOrder: [.save, .undo, .save], manifest: manifest)
        let duplicates = findings(.focusOrderUnexpected, in: result)

        XCTAssertEqual(duplicates.count, 1)
        XCTAssertNil(duplicates.first?.command)
    }

    func testFocusOrderMismatchFinding() throws {
        let commands = canonicalCommands()
        var order = commands
        order.swapAt(0, 1)
        let result = try plan(inputs: uniqueInputs(), focusOrder: order)
        let mismatch = findings(.focusOrderMismatch, in: result)

        XCTAssertEqual(mismatch.count, 1)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(result.inventory.bindings.map(\.command), order)
    }

    func testReceiptDeterministicAcrossRepeatedPlans() throws {
        let first = try plan()
        let second = try plan()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.findings.map(\.id), second.findings.map(\.id))
        XCTAssertEqual(first.inventory.bindings, second.inventory.bindings)
    }

    func testReceiptDeterministicAcrossShuffledInputs() throws {
        let forward = try plan(inputs: uniqueInputs())
        let backward = try plan(inputs: Array(uniqueInputs().reversed()))

        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward.receipt.contentDigest, backward.receipt.contentDigest)
    }

    func testInvalidLimitsRejected() throws {
        XCTAssertThrowsError(try plan(limits: Limits(maximumControls: -1))) { error in
            XCTAssertEqual(
                error as? InventoryError,
                .invalidLimit(
                    name: "maximumControls",
                    value: -1,
                    maximum: Limits.hardMaximumControls
                )
            )
        }
        XCTAssertThrowsError(try plan(limits: Limits(maximumWorkUnits: 0))) { error in
            XCTAssertEqual(
                error as? InventoryError,
                .invalidLimit(name: "maximumWorkUnits", value: 0, maximum: Limits.hardMaximumWorkUnits)
            )
        }
        XCTAssertThrowsError(try plan(limits: Limits(cancellationCheckInterval: 0))) { error in
            XCTAssertEqual(
                error as? InventoryError,
                .invalidLimit(
                    name: "cancellationCheckInterval",
                    value: 0,
                    maximum: Limits.hardMaximumCancellationCheckInterval
                )
            )
        }
        XCTAssertThrowsError(
            try plan(limits: Limits(maximumControls: Limits.hardMaximumControls + 1))
        ) { error in
            XCTAssertEqual(
                error as? InventoryError,
                .invalidLimit(
                    name: "maximumControls",
                    value: Limits.hardMaximumControls + 1,
                    maximum: Limits.hardMaximumControls
                )
            )
        }
    }

    func testCountLimitsEnforced() throws {
        let commands = canonicalCommands()
        let tight = Limits(maximumControls: commands.count - 1)
        XCTAssertThrowsError(try plan(inputs: uniqueInputs(), limits: tight)) { error in
            XCTAssertEqual(
                error as? InventoryError,
                .countLimitExceeded(kind: "controls", maximum: commands.count - 1)
            )
        }
        XCTAssertNoThrow(try plan(inputs: uniqueInputs(), limits: Limits(maximumControls: commands.count)))
        XCTAssertThrowsError(try plan(focusOrder: commands + [commands[0]])) { error in
            XCTAssertEqual(
                error as? InventoryError,
                .countLimitExceeded(kind: "focusOrder", maximum: commands.count)
            )
        }
    }

    func testStringTooLargeRejected() throws {
        let target = canonicalCommands()[0]
        let big = String(repeating: "a", count: 17 * 1_024)
        let inputs = uniqueInputs().map { input in
            guard input.command == target else { return input }
            return Input(
                command: input.command,
                label: big,
                hint: "Hint \(input.command.rawValue)",
                tooltip: "Tip \(input.command.rawValue)"
            )
        }
        XCTAssertThrowsError(try plan(inputs: inputs)) { error in
            XCTAssertEqual(
                error as? InventoryError,
                .stringTooLarge(field: "label.\(target.rawValue)", maximumUTF8Bytes: 16 * 1_024)
            )
        }
    }

    func testTotalStringsTooLargeRejected() throws {
        XCTAssertThrowsError(try plan(limits: Limits(maximumTotalStringUTF8Bytes: 8))) { error in
            XCTAssertEqual(error as? InventoryError, .totalStringsTooLarge(maximumUTF8Bytes: 8))
        }
    }

    func testWorkLimitExceeded() throws {
        XCTAssertThrowsError(try plan(limits: Limits(maximumWorkUnits: 1))) { error in
            XCTAssertEqual(error as? InventoryError, .workLimitExceeded(maximum: 1))
        }
    }

    func testFindingLimitExceeded() throws {
        XCTAssertThrowsError(try plan(inputs: [], limits: Limits(maximumFindings: 0))) { error in
            XCTAssertEqual(error as? InventoryError, .findingLimitExceeded(maximum: 0))
        }
    }

    func testCancellationThrowsCancelled() throws {
        XCTAssertThrowsError(try plan(cancellationCheck: { throw TestCancellation() })) { error in
            XCTAssertEqual(error as? InventoryError, .cancelled)
        }
        let counter = CallCounter()
        do {
            _ = try plan(cancellationCheck: {
                if counter.next() > 2 { throw TestCancellation() }
            })
            XCTFail("Expected mid-plan cancellation")
        } catch let error as InventoryError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testDescriptionsRedactCallerText() throws {
        let result = try plan()
        let first = try XCTUnwrap(uniqueInputs().first)
        let binding = try XCTUnwrap(result.inventory.bindings.first)

        XCTAssertTrue(first.description.contains("<redacted>"))
        XCTAssertFalse(first.description.contains(first.label))
        XCTAssertTrue(first.debugDescription.contains("<redacted>"))
        XCTAssertTrue(binding.description.contains("<redacted>"))
        XCTAssertFalse(binding.description.contains(binding.accessibility.label))
        XCTAssertTrue(result.description.contains("<redacted>"))
        XCTAssertTrue(result.inventory.description.contains("<redacted>"))
        XCTAssertTrue(result.receipt.description.contains("<redacted>"))
    }
}
