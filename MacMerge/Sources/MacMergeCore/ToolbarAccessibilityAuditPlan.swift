import CryptoKit
import Foundation

/// UI-independent bounded audit planner for toolbar VoiceOver metadata.
///
/// Owns no AppKit, AX runtime, screenshot, filesystem, or process behavior.
/// Callers supply one static record per toolbar control; the planner rejects
/// duplicates and blanks, requires a hint when the action is ambiguous, binds
/// the enabled and focusable booleans to a lifecycle state name, and returns
/// a deterministic SHA-256 receipt over the controls sorted by command
/// identifier, so input order never changes the digest.
///
/// Coverage model: empty and subset inputs pass. The planner checks only the
/// supplied records, so incremental per-control planning stays cheap. Full
/// toolbar coverage is a separate gate (see `ToolbarStateMatrixPlan`).
/// Role model: `role` is a free-form caller-supplied AX role name. Only blank
/// roles fail; there is no role allowlist.
/// Lifecycle model: `lifecycleState` must name a known
/// `ToolbarAuditLifecycleScenario`, but `enabled`/`focusable` are not
/// cross-checked against that state. The booleans are preserved and digested;
/// semantic enablement per state lives with the caller
/// (see `ToolbarStateMatrixPlan` / `ToolbarAuditContract`).
/// Duplicate-label model: VoiceOver-collision oriented. Labels are NFC
/// normalized on init, and duplicate detection compares the trimmed,
/// case-insensitive NFC form, so `" Save "`, `"save"`, and `"SAVE"` collide.
/// Work model: hashing is counted work. The receipt digest consumes one work
/// unit per control from the same `WorkBudget` as validation.
/// Receipt model: the digest binds `receiptDomain` and `formatVersion` plus
/// the canonical controls, so a future format bump changes the digest.
public enum ToolbarAccessibilityAuditPlan: Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let scopeStatement =
        "Static planning of caller-supplied toolbar labels, values, hints, roles, enabled states, and keyboard focus; not runtime UI or VoiceOver conformance."
    public static let receiptDomain = "toolbar-ax-audit.v1"
    public static let formatVersion = 1

    /// Lifecycle state names the enabled and focusable booleans bind to.
    public static var knownLifecycleStates: [String] {
        ToolbarAuditLifecycleScenario.allCases.map(\.rawValue)
    }

    /// One static VoiceOver record for one toolbar control.
    public struct Control: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let commandID: Command
        public let label: String
        public let value: String?
        public let hint: String?
        public let isActionAmbiguous: Bool
        public let enabled: Bool
        public let focusable: Bool
        public let lifecycleState: String
        public let role: String

        public init(
            commandID: Command,
            label: String,
            role: String,
            lifecycleState: String,
            value: String? = nil,
            hint: String? = nil,
            isActionAmbiguous: Bool = false,
            enabled: Bool = true,
            focusable: Bool = true
        ) {
            self.commandID = commandID
            self.label = label.precomposedStringWithCanonicalMapping
            self.role = role.precomposedStringWithCanonicalMapping
            self.lifecycleState = lifecycleState.precomposedStringWithCanonicalMapping
            self.value = value?.precomposedStringWithCanonicalMapping
            self.hint = hint?.precomposedStringWithCanonicalMapping
            self.isActionAmbiguous = isActionAmbiguous
            self.enabled = enabled
            self.focusable = focusable
        }

        public var description: String {
            "ToolbarAccessibilityAuditPlan.Control(commandID: \(commandID.rawValue), text: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "commandID": commandID,
                    "lifecycleState": lifecycleState,
                    "enabled": enabled,
                    "focusable": focusable,
                    "text": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumControls = Command.allCases.count
        public static let hardMaximumStringUTF8Bytes = 64 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 16 * 1_024 * 1_024
        public static let hardMaximumWorkUnits = 1_000_000
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumControls: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumControls: Int = hardMaximumControls,
            maximumStringUTF8Bytes: Int = 16 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
            maximumWorkUnits: Int = 64_000,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumControls = maximumControls
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (0...Self.hardMaximumControls).contains(maximumControls) else {
                throw AuditError.invalidMaximumControls(value: maximumControls, maximum: Self.hardMaximumControls)
            }
            guard (1...Self.hardMaximumStringUTF8Bytes).contains(maximumStringUTF8Bytes) else {
                throw AuditError.invalidMaximumStringUTF8Bytes(value: maximumStringUTF8Bytes, maximum: Self.hardMaximumStringUTF8Bytes)
            }
            guard (0...Self.hardMaximumTotalStringUTF8Bytes).contains(maximumTotalStringUTF8Bytes) else {
                throw AuditError.invalidMaximumTotalStringUTF8Bytes(value: maximumTotalStringUTF8Bytes, maximum: Self.hardMaximumTotalStringUTF8Bytes)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw AuditError.invalidMaximumWorkUnits(value: maximumWorkUnits, maximum: Self.hardMaximumWorkUnits)
            }
            guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
                throw AuditError.invalidCancellationCheckInterval(value: cancellationCheckInterval, maximum: Self.hardMaximumCancellationCheckInterval)
            }
        }
    }

    /// Every payload is an input index or a byte/count bound. Caller text
    /// (labels, values, hints, roles, states) never appears in an error.
    public enum AuditError: Error, Equatable, LocalizedError, Sendable {
        case invalidMaximumControls(value: Int, maximum: Int)
        case invalidMaximumStringUTF8Bytes(value: Int, maximum: Int)
        case invalidMaximumTotalStringUTF8Bytes(value: Int, maximum: Int)
        case invalidMaximumWorkUnits(value: Int, maximum: Int)
        case invalidCancellationCheckInterval(value: Int, maximum: Int)
        case tooManyControls(count: Int, maximum: Int)
        case stringTooLarge(index: Int, maximum: Int)
        case totalStringsTooLarge(count: Int, maximum: Int)
        case workLimitExceeded(maximum: Int)
        case duplicateCommandID(index: Int)
        case duplicateLabel(index: Int)
        case emptyLabel(index: Int)
        case emptyValue(index: Int)
        case emptyHint(index: Int)
        case missingHint(index: Int)
        case emptyRole(index: Int)
        case emptyLifecycleState(index: Int)
        case unknownLifecycleState(index: Int)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .invalidMaximumControls(let value, let maximum):
                "Toolbar accessibility audit limit maximumControls is invalid (\(value)); supported maximum is \(maximum)."
            case .invalidMaximumStringUTF8Bytes(let value, let maximum):
                "Toolbar accessibility audit limit maximumStringUTF8Bytes is invalid (\(value)); supported maximum is \(maximum)."
            case .invalidMaximumTotalStringUTF8Bytes(let value, let maximum):
                "Toolbar accessibility audit limit maximumTotalStringUTF8Bytes is invalid (\(value)); supported maximum is \(maximum)."
            case .invalidMaximumWorkUnits(let value, let maximum):
                "Toolbar accessibility audit limit maximumWorkUnits is invalid (\(value)); supported maximum is \(maximum)."
            case .invalidCancellationCheckInterval(let value, let maximum):
                "Toolbar accessibility audit limit cancellationCheckInterval is invalid (\(value)); supported maximum is \(maximum)."
            case .tooManyControls(let count, let maximum):
                "Toolbar accessibility audit input holds \(count) controls; supported maximum is \(maximum)."
            case .stringTooLarge(let index, let maximum):
                "Toolbar accessibility audit control \(index) exceeds \(maximum) UTF-8 bytes in one field."
            case .totalStringsTooLarge(let count, let maximum):
                "Toolbar accessibility audit strings hold \(count) UTF-8 bytes; supported maximum is \(maximum)."
            case .workLimitExceeded(let maximum):
                "Toolbar accessibility audit exceeds the \(maximum)-unit work limit."
            case .duplicateCommandID(let index):
                "Toolbar accessibility audit control \(index) repeats a command identifier."
            case .duplicateLabel(let index):
                "Toolbar accessibility audit control \(index) repeats a VoiceOver label."
            case .emptyLabel(let index):
                "Toolbar accessibility audit control \(index) has a blank VoiceOver label."
            case .emptyValue(let index):
                "Toolbar accessibility audit control \(index) has a blank VoiceOver value."
            case .emptyHint(let index):
                "Toolbar accessibility audit control \(index) has a blank VoiceOver hint."
            case .missingHint(let index):
                "Toolbar accessibility audit control \(index) needs a VoiceOver hint for an ambiguous action."
            case .emptyRole(let index):
                "Toolbar accessibility audit control \(index) has a blank role."
            case .emptyLifecycleState(let index):
                "Toolbar accessibility audit control \(index) has a blank lifecycle state."
            case .unknownLifecycleState(let index):
                "Toolbar accessibility audit control \(index) names an unknown lifecycle state."
            case .cancelled:
                "Toolbar accessibility audit was cancelled."
            }
        }
    }

    public struct Receipt: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public static let byteCount = 32

        public let formatVersion: Int
        public let controlCount: Int
        public let workPerformed: Int
        public let bytes: [UInt8]

        fileprivate init(formatVersion: Int, controlCount: Int, workPerformed: Int, bytes: [UInt8]) {
            self.formatVersion = formatVersion
            self.controlCount = controlCount
            self.workPerformed = workPerformed
            self.bytes = bytes
        }

        public var hex: String {
            bytes.map { String(format: "%02x", $0) }.joined()
        }

        public var description: String {
            "ToolbarAccessibilityAuditPlan.Receipt(controls: \(controlCount), work: \(workPerformed), digest: \(hex))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "formatVersion": formatVersion,
                    "controlCount": controlCount,
                    "workPerformed": workPerformed,
                    "digest": hex
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Plan: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// Canonical command-identifier order. Input order never survives.
        public let controls: [Control]
        public let receipt: Receipt

        public var controlCount: Int { controls.count }

        fileprivate init(controls: [Control], receipt: Receipt) {
            self.controls = controls
            self.receipt = receipt
        }

        public var description: String {
            "ToolbarAccessibilityAuditPlan.Plan(controls: \(controls.count), digest: \(receipt.hex))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "controlCount": controls.count,
                    "digest": receipt.hex
                ],
                displayStyle: .struct
            )
        }
    }

    /// Validates caller records and returns the canonical plan plus receipt.
    /// Limits are enforced before any validation work. The digest covers the
    /// controls sorted by command identifier, so it is order-independent.
    /// Empty and subset inputs pass by design for incremental planning; `role`
    /// is free-form (non-blank passes); `lifecycleState` is name-checked only
    /// with no `enabled`/`focusable` semantic cross-check; duplicate labels
    /// collide on trimmed case-insensitive NFC form; digest hashing consumes
    /// work units and binds `formatVersion`.
    public static func plan(
        controls: [Control],
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Plan {
        try limits.validate()
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try budget.checkCancellation()
        guard controls.count <= limits.maximumControls else {
            throw AuditError.tooManyControls(count: controls.count, maximum: limits.maximumControls)
        }
        try checkStringLimits(controls: controls, limits: limits, budget: &budget)
        try budget.checkCancellation()

        let knownStates = Set(knownLifecycleStates)
        var seenCommands = Set<Command>()
        var seenLabels = Set<String>()
        for (index, control) in controls.enumerated() {
            try budget.consume()
            if isBlank(control.label) {
                throw AuditError.emptyLabel(index: index)
            }
            if isBlank(control.role) {
                throw AuditError.emptyRole(index: index)
            }
            if let value = control.value, isBlank(value) {
                throw AuditError.emptyValue(index: index)
            }
            if let hint = control.hint, isBlank(hint) {
                throw AuditError.emptyHint(index: index)
            }
            if control.isActionAmbiguous, control.hint == nil {
                throw AuditError.missingHint(index: index)
            }
            if isBlank(control.lifecycleState) {
                throw AuditError.emptyLifecycleState(index: index)
            }
            if !knownStates.contains(control.lifecycleState) {
                throw AuditError.unknownLifecycleState(index: index)
            }
            guard seenCommands.insert(control.commandID).inserted else {
                throw AuditError.duplicateCommandID(index: index)
            }
            guard seenLabels.insert(duplicateLabelKey(control.label)).inserted else {
                throw AuditError.duplicateLabel(index: index)
            }
        }

        let sorted = controls.sorted {
            compareUTF8($0.commandID.rawValue, $1.commandID.rawValue) < 0
        }
        let digest = try receiptDigest(for: sorted, budget: &budget)
        try budget.finish()
        return Plan(
            controls: sorted,
            receipt: Receipt(
                formatVersion: formatVersion,
                controlCount: sorted.count,
                workPerformed: budget.completed,
                bytes: digest
            )
        )
    }

    private static func checkStringLimits(controls: [Control], limits: Limits, budget: inout WorkBudget) throws {
        var total = 0
        for (index, control) in controls.enumerated() {
            try budget.consume()
            let fields: [String?] = [
                control.label,
                control.value,
                control.hint,
                control.role,
                control.lifecycleState
            ]
            for field in fields {
                guard let field else { continue }
                let count = field.utf8.count
                guard count <= limits.maximumStringUTF8Bytes else {
                    throw AuditError.stringTooLarge(index: index, maximum: limits.maximumStringUTF8Bytes)
                }
                let (next, overflow) = total.addingReportingOverflow(count)
                if overflow {
                    throw AuditError.totalStringsTooLarge(count: Int.max, maximum: limits.maximumTotalStringUTF8Bytes)
                }
                guard next <= limits.maximumTotalStringUTF8Bytes else {
                    throw AuditError.totalStringsTooLarge(count: next, maximum: limits.maximumTotalStringUTF8Bytes)
                }
                total = next
            }
        }
    }

    private static func receiptDigest(for controls: [Control], budget: inout WorkBudget) throws -> [UInt8] {
        var input = Data(receiptDomain.utf8)
        input.append(0)
        appendUInt64(UInt64(formatVersion), to: &input)
        appendUInt64(UInt64(controls.count), to: &input)
        for control in controls {
            try budget.consume()
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
        return Array(SHA256.hash(data: input))
    }

    /// VoiceOver-collision key: trimmed, case-insensitive NFC form.
    /// Stored labels keep original text; only duplicate detection folds.
    private static func duplicateLabelKey(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().precomposedStringWithCanonicalMapping
    }

    private static func appendUInt64(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer in
            data.append(contentsOf: buffer)
        }
    }

    private static func appendString(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        appendUInt64(UInt64(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    private static func appendOptionalString(_ value: String?, to data: inout Data) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        appendString(value, to: &data)
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct WorkBudget {
        let maximum: Int
        let interval: Int
        let check: CancellationCheck
        private(set) var completed = 0
        private var nextCheck: Int

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) {
            maximum = limits.maximumWorkUnits
            interval = limits.cancellationCheckInterval
            check = cancellationCheck
            nextCheck = limits.cancellationCheckInterval
        }

        mutating func consume(_ amount: Int = 1) throws {
            guard amount >= 0, amount <= maximum, completed <= maximum - amount else {
                throw AuditError.workLimitExceeded(maximum: maximum)
            }
            completed += amount
            if completed >= nextCheck {
                try checkCancellation()
                let (next, overflow) = completed.addingReportingOverflow(interval)
                nextCheck = overflow ? Int.max : next
            }
        }

        func checkCancellation() throws {
            do {
                try check()
            } catch {
                throw AuditError.cancelled
            }
        }

        func finish() throws {
            try checkCancellation()
        }
    }
}

private func compareUTF8(_ left: String, _ right: String) -> Int {
    var leftIterator = left.utf8.makeIterator()
    var rightIterator = right.utf8.makeIterator()
    while true {
        switch (leftIterator.next(), rightIterator.next()) {
        case (nil, nil):
            return 0
        case (nil, _?):
            return -1
        case (_?, nil):
            return 1
        case (let leftByte?, let rightByte?):
            if leftByte != rightByte {
                return leftByte < rightByte ? -1 : 1
            }
        }
    }
}
