import CryptoKit
import Foundation

/// UI-independent toolbar state-matrix planner.
///
/// Covers every toolbar action across the ten lifecycle states required by
/// todo.md L309: empty, loading, equal, different, selected, dirty, read-only,
/// failed, untitled, and externally changed. Planning only: no UI, no AppKit,
/// no persistence, no executor. Callers supply one entry per
/// (command, state) pair with expected enabled/disabled plus a reason.
/// The planner validates full 10-state coverage per command, rejects unknown
/// commands and duplicate pairs, requires a non-empty reason when disabled,
/// enforces limits before work, and returns a deterministic SHA-256 receipt
/// over canonically sorted entries so input order never affects the digest.
public enum ToolbarStateMatrixPlan: Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias CancellationCheck = @Sendable () throws -> Void

    /// Canonical ten lifecycle states. Raw values match
    /// `ToolbarAuditLifecycleScenario` for audit cross-reference.
    public enum State: String, CaseIterable, Equatable, Hashable, Sendable {
        case empty
        case loading
        case equal
        case different
        case selected
        case dirty
        case readOnly
        case failed
        case untitled
        case externallyChanged
    }

    /// Deterministic receipt domain. Part of the SHA-256 preimage.
    public static let receiptDomain = "toolbar-state-matrix.v1"

    /// Expected enablement for one (command, state) pair.
    /// Enabled entries must carry no reason. Disabled entries must carry a
    /// non-blank reason.
    public struct Entry: Equatable, Hashable, Sendable {
        public let command: Command
        public let state: State
        public let isEnabled: Bool
        public let reason: String?

        public init(command: Command, state: State, isEnabled: Bool, reason: String? = nil) {
            self.command = command
            self.state = state
            self.isEnabled = isEnabled
            self.reason = reason
        }
    }

    /// Unchecked entry with a raw command identifier. Used to prove the known
    /// command allowlist rejects unknown identifiers with an index-only error.
    public struct RawEntry: Equatable, Hashable, Sendable {
        public let commandID: String
        public let state: State
        public let isEnabled: Bool
        public let reason: String?

        public init(commandID: String, state: State, isEnabled: Bool, reason: String? = nil) {
            self.commandID = commandID
            self.state = state
            self.isEnabled = isEnabled
            self.reason = reason
        }
    }

    public enum Limit: String, CaseIterable, Equatable, Hashable, Sendable {
        case entries
        case reasonBytes
        case totalReasonBytes
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumEntries = 4_096
        public static let hardMaximumReasonUTF8Bytes = 4_096
        public static let hardMaximumTotalReasonUTF8Bytes = 1_048_576
        public static let hardMaximumWorkUnits = 1_048_576
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        /// Default `maximumTotalReasonUTF8Bytes` covers worst-case full-disabled
        /// matrix with current catalog: 26 commands x 10 states x 1,024 bytes
        /// = 266,240 bytes. If the command catalog grows, supply custom limits
        /// up to the hard maxima; defaults are not recalculated automatically.

        public let maximumEntries: Int
        public let maximumReasonUTF8Bytes: Int
        public let maximumTotalReasonUTF8Bytes: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumEntries: Int = 1_024,
            maximumReasonUTF8Bytes: Int = 1_024,
            maximumTotalReasonUTF8Bytes: Int = 266_240,
            maximumWorkUnits: Int = 100_000,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumEntries = maximumEntries
            self.maximumReasonUTF8Bytes = maximumReasonUTF8Bytes
            self.maximumTotalReasonUTF8Bytes = maximumTotalReasonUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (1...Self.hardMaximumEntries).contains(maximumEntries) else {
                throw ToolbarStateMatrixPlanError.invalidLimit(.entries, value: maximumEntries)
            }
            guard (1...Self.hardMaximumReasonUTF8Bytes).contains(maximumReasonUTF8Bytes) else {
                throw ToolbarStateMatrixPlanError.invalidLimit(.reasonBytes, value: maximumReasonUTF8Bytes)
            }
            guard (1...Self.hardMaximumTotalReasonUTF8Bytes).contains(maximumTotalReasonUTF8Bytes) else {
                throw ToolbarStateMatrixPlanError.invalidLimit(
                    .totalReasonBytes,
                    value: maximumTotalReasonUTF8Bytes
                )
            }
            guard maximumTotalReasonUTF8Bytes >= maximumReasonUTF8Bytes else {
                throw ToolbarStateMatrixPlanError.invalidLimit(
                    .totalReasonBytes,
                    value: maximumTotalReasonUTF8Bytes
                )
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw ToolbarStateMatrixPlanError.invalidLimit(.workUnits, value: maximumWorkUnits)
            }
            guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
                throw ToolbarStateMatrixPlanError.invalidLimit(
                    .cancellationCheckInterval,
                    value: cancellationCheckInterval
                )
            }
        }
    }

    /// Deterministic SHA-256 receipt over the sorted matrix.
    public struct Receipt: Equatable, Hashable, Sendable {
        public static let byteCount = 32

        public let bytes: [UInt8]

        public init(bytes: [UInt8]) throws {
            guard bytes.count == Self.byteCount else {
                throw ToolbarStateMatrixPlanError.receiptByteCount(count: bytes.count)
            }
            self.bytes = bytes
        }

        public var hex: String {
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Validated plan with canonically sorted entries and a deterministic receipt.
    public struct Plan: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        /// Sorted by command raw value, then state raw value. Order-independent.
        public let entries: [Entry]
        public let receipt: Receipt
        public let entryCount: Int
        public let disabledCount: Int

        fileprivate init(entries: [Entry], receipt: Receipt) {
            self.entries = entries
            self.receipt = receipt
            entryCount = entries.count
            disabledCount = entries.reduce(0) { $0 + ($1.isEnabled ? 0 : 1) }
        }

        public var digestHex: String { receipt.hex }

        public var description: String {
            "ToolbarStateMatrixPlan(entries: \(entryCount), disabled: \(disabledCount), digest: \(receipt.hex))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "entryCount": entryCount,
                    "disabledCount": disabledCount,
                    "digest": receipt.hex,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    /// Expected entry count for full coverage: every known command in every state.
    public static var expectedEntryCount: Int {
        Command.allCases.count * State.allCases.count
    }

    /// Build a validated plan from typed entries. Throws on duplicates, missing
    /// coverage, bad reasons, limit violations, or cancellation.
    /// Errors carry index or count only, never reason text or command/state
    /// identities beyond the index, so reason content is not echoed into logs.
    /// Callers needing debuggability diff locally against `expectedEntryCount`.
    /// Reason length limits apply to canonical NFC bytes (`precomposedStringWithCanonicalMapping`),
    /// matching the receipt preimage, not to the raw `String.utf8` length.
    public static func make(
        entries: [Entry],
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Plan {
        try limits.validate()
        guard entries.count <= limits.maximumEntries else {
            throw ToolbarStateMatrixPlanError.entryLimitExceeded(
                count: entries.count,
                maximum: limits.maximumEntries
            )
        }
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try budget.checkCancellation()
        return try buildValidatedPlan(entries: entries, limits: limits, budget: &budget)
    }

    /// Build a validated plan from raw command identifiers. Unknown identifiers
    /// throw an index-only error before coverage checks run. The single
    /// `WorkBudget` covers both raw-identifier resolution and typed validation
    /// plus receipt hashing, so `maximumWorkUnits` bounds the total work.
    public static func make(
        rawEntries: [RawEntry],
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Plan {
        try limits.validate()
        guard rawEntries.count <= limits.maximumEntries else {
            throw ToolbarStateMatrixPlanError.entryLimitExceeded(
                count: rawEntries.count,
                maximum: limits.maximumEntries
            )
        }
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try budget.checkCancellation()

        var typed: [Entry] = []
        typed.reserveCapacity(rawEntries.count)
        for (index, raw) in rawEntries.enumerated() {
            try budget.consume()
            guard let command = Command(rawValue: raw.commandID) else {
                throw ToolbarStateMatrixPlanError.unknownCommandID(index: index)
            }
            typed.append(
                Entry(command: command, state: raw.state, isEnabled: raw.isEnabled, reason: raw.reason)
            )
        }
        return try buildValidatedPlan(entries: typed, limits: limits, budget: &budget)
    }

    /// Shared second phase for typed entries. Assumes `limits` validated and
    /// entry-count checked by the caller; consumes from the caller's budget so
    /// raw and typed paths share one work total.
    private static func buildValidatedPlan(
        entries: [Entry],
        limits: Limits,
        budget: inout WorkBudget
    ) throws -> Plan {
        var seen: [EntryKey: Int] = [:]
        seen.reserveCapacity(entries.count)
        var totalReasonBytes = 0
        for (index, entry) in entries.enumerated() {
            try budget.consume()
            let key = EntryKey(command: entry.command, state: entry.state)
            if let firstIndex = seen[key] {
                throw ToolbarStateMatrixPlanError.duplicateEntry(
                    firstIndex: firstIndex,
                    duplicateIndex: index
                )
            }
            seen[key] = index
            if entry.isEnabled {
                if entry.reason != nil {
                    throw ToolbarStateMatrixPlanError.unexpectedReason(index: index)
                }
            } else {
                guard let reason = entry.reason, !isBlank(reason) else {
                    throw ToolbarStateMatrixPlanError.reasonMissing(index: index)
                }
                let canonical = reason.precomposedStringWithCanonicalMapping
                let byteCount = canonical.utf8.count
                guard byteCount <= limits.maximumReasonUTF8Bytes else {
                    throw ToolbarStateMatrixPlanError.reasonTooLarge(
                        index: index,
                        maximum: limits.maximumReasonUTF8Bytes
                    )
                }
                guard totalReasonBytes <= limits.maximumTotalReasonUTF8Bytes - byteCount else {
                    throw ToolbarStateMatrixPlanError.totalReasonsTooLarge(
                        maximum: limits.maximumTotalReasonUTF8Bytes
                    )
                }
                totalReasonBytes += byteCount
            }
        }

        // Intentionally count-only: listing the missing (command, state) pairs
        // would aid debugging but emits plan structure into error paths. This
        // keeps errors index/count-only (no reason text). Diff locally for details.
        let missingCount = expectedEntryCount - seen.count
        guard missingCount == 0 else {
            throw ToolbarStateMatrixPlanError.missingEntries(missingCount: missingCount)
        }

        let sorted = entries.sorted(by: entryOrder)
        let receipt = try makeReceipt(sorted: sorted, budget: &budget)
        try budget.finish()
        return Plan(entries: sorted, receipt: receipt)
    }

    private struct EntryKey: Hashable {
        let command: Command
        let state: State
    }

    private static func entryOrder(left: Entry, right: Entry) -> Bool {
        if left.command.rawValue != right.command.rawValue {
            return left.command.rawValue < right.command.rawValue
        }
        return left.state.rawValue < right.state.rawValue
    }

    private static func makeReceipt(sorted: [Entry], budget: inout WorkBudget) throws -> Receipt {
        var input = Data(receiptDomain.utf8)
        input.append(0)
        for entry in sorted {
            try budget.consume()
            input.append(contentsOf: entry.command.rawValue.utf8)
            input.append(0)
            input.append(contentsOf: entry.state.rawValue.utf8)
            input.append(0)
            input.append(entry.isEnabled ? 1 : 0)
            if let reason = entry.reason {
                let canonical = reason.precomposedStringWithCanonicalMapping
                input.append(contentsOf: canonical.utf8)
            }
            input.append(0)
        }
        try budget.checkCancellation()
        let digest = SHA256.hash(data: input)
        return try Receipt(bytes: Array(digest))
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ToolbarStateMatrixPlanError: Error, Equatable, Hashable, Sendable {
    case invalidLimit(ToolbarStateMatrixPlan.Limit, value: Int)
    case entryLimitExceeded(count: Int, maximum: Int)
    case duplicateEntry(firstIndex: Int, duplicateIndex: Int)
    case unknownCommandID(index: Int)
    /// Count-only by design: listing missing pairs aids debugging but leaks
    /// plan structure into error paths. All errors here stay index/count-only
    /// and never echo reason text. Diff locally for details.
    case missingEntries(missingCount: Int)
    case reasonMissing(index: Int)
    case unexpectedReason(index: Int)
    case reasonTooLarge(index: Int, maximum: Int)
    case totalReasonsTooLarge(maximum: Int)
    case receiptByteCount(count: Int)
    case workLimitExceeded(maximum: Int)
    case cancelled
}

extension ToolbarStateMatrixPlanError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let limit, let value):
            "Toolbar state-matrix limit \(limit.rawValue) is invalid: \(value)."
        case .entryLimitExceeded(let count, let maximum):
            "Toolbar state-matrix entry count \(count) exceeds the \(maximum)-entry limit."
        case .duplicateEntry(let firstIndex, let duplicateIndex):
            "Toolbar state-matrix duplicate entry at index \(duplicateIndex) first seen at index \(firstIndex)."
        case .unknownCommandID(let index):
            "Toolbar state-matrix unknown command identifier at index \(index)."
        case .missingEntries(let missingCount):
            "Toolbar state-matrix missing \(missingCount) entries for full coverage."
        case .reasonMissing(let index):
            "Toolbar state-matrix disabled entry at index \(index) requires a reason."
        case .unexpectedReason(let index):
            "Toolbar state-matrix enabled entry at index \(index) must not carry a reason."
        case .reasonTooLarge(let index, let maximum):
            "Toolbar state-matrix reason at index \(index) exceeds the \(maximum)-byte limit."
        case .totalReasonsTooLarge(let maximum):
            "Toolbar state-matrix reasons exceed the \(maximum)-byte total limit."
        case .receiptByteCount(let count):
            "Toolbar state-matrix receipt has invalid byte count \(count)."
        case .workLimitExceeded(let maximum):
            "Toolbar state-matrix exceeds the \(maximum)-unit work limit."
        case .cancelled:
            "Toolbar state-matrix planning was cancelled."
        }
    }
}

private struct WorkBudget {
    let maximumWork: Int
    let cancellationCheckInterval: Int
    let cancellationCheck: ToolbarStateMatrixPlan.CancellationCheck
    private(set) var completed = 0
    private var workAtLastCheck = 0

    init(limits: ToolbarStateMatrixPlan.Limits, cancellationCheck: @escaping ToolbarStateMatrixPlan.CancellationCheck) {
        maximumWork = limits.maximumWorkUnits
        cancellationCheckInterval = limits.cancellationCheckInterval
        self.cancellationCheck = cancellationCheck
    }

    mutating func consume(_ amount: Int = 1) throws {
        guard amount >= 0, amount <= maximumWork else {
            try checkCancellation()
            throw ToolbarStateMatrixPlanError.workLimitExceeded(maximum: maximumWork)
        }
        guard completed <= maximumWork - amount else {
            try checkCancellation()
            throw ToolbarStateMatrixPlanError.workLimitExceeded(maximum: maximumWork)
        }
        completed += amount
        if completed - workAtLastCheck >= cancellationCheckInterval {
            try checkCancellation()
            workAtLastCheck = completed
        }
    }

    func checkCancellation() throws {
        do {
            try cancellationCheck()
        } catch {
            throw ToolbarStateMatrixPlanError.cancelled
        }
    }

    mutating func finish() throws {
        try checkCancellation()
        workAtLastCheck = completed
    }
}
