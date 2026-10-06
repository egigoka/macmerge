import Foundation

/// UI-independent bounded inventory planner for toolbar VoiceOver metadata.
/// No AppKit, AX runtime, screenshot, filesystem, or process inspection occurs.
public enum ToolbarAccessibilityInventory: Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let scopeStatement =
        "Static planning of caller-supplied toolbar labels, values, hints, tooltips, and focus order; not runtime UI or VoiceOver conformance."
    public static let inventoryFormatVersion = 1

    public static func controlID(for command: Command) -> ToolbarAuditStableID {
        ToolbarAuditStableID(rawValue: "toolbar." + command.rawValue)
    }

    public static func primaryActionID(for command: Command) -> ToolbarAuditStableID {
        ToolbarAuditStableID(rawValue: "toolbar." + command.rawValue + ".primary")
    }

    public struct ControlInput: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let command: Command
        public let label: String
        public let value: String?
        public let hint: String
        public let tooltip: String

        public init(command: Command, label: String, value: String? = nil, hint: String, tooltip: String) {
            self.command = command
            self.label = label.precomposedStringWithCanonicalMapping
            self.value = value?.precomposedStringWithCanonicalMapping
            self.hint = hint.precomposedStringWithCanonicalMapping
            self.tooltip = tooltip.precomposedStringWithCanonicalMapping
        }

        public var description: String {
            "ToolbarAccessibilityInventory.ControlInput(command: \(command.rawValue), text: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["command": command, "text": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumControls = ToolbarAuditLimits.hardMaximumControls
        public static let hardMaximumStringUTF8Bytes = ToolbarAuditLimits.hardMaximumStringUTF8Bytes
        public static let hardMaximumTotalStringUTF8Bytes = ToolbarAuditLimits.hardMaximumTotalStringUTF8Bytes
        public static let hardMaximumWorkUnits = 1_000_000
        public static let hardMaximumFindings = 4_096
        public static let hardMaximumCancellationCheckInterval = ToolbarAuditLimits.hardMaximumCancellationCheckInterval
        public static let `default` = Limits()

        public let maximumControls: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumWorkUnits: Int
        public let maximumFindings: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumControls: Int = hardMaximumControls,
            maximumStringUTF8Bytes: Int = 16 * 1_024,
            maximumTotalStringUTF8Bytes: Int = 4 * 1_024 * 1_024,
            maximumWorkUnits: Int = 64_000,
            maximumFindings: Int = 1_024,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumControls = maximumControls
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.maximumFindings = maximumFindings
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            try check(maximumControls, name: "maximumControls", maximum: Self.hardMaximumControls)
            try check(maximumStringUTF8Bytes, name: "maximumStringUTF8Bytes", maximum: Self.hardMaximumStringUTF8Bytes)
            try check(maximumTotalStringUTF8Bytes, name: "maximumTotalStringUTF8Bytes", maximum: Self.hardMaximumTotalStringUTF8Bytes)
            try check(maximumWorkUnits, name: "maximumWorkUnits", maximum: Self.hardMaximumWorkUnits)
            try check(maximumFindings, name: "maximumFindings", maximum: Self.hardMaximumFindings)
            try check(cancellationCheckInterval, name: "cancellationCheckInterval", maximum: Self.hardMaximumCancellationCheckInterval)
        }

        private func check(_ value: Int, name: String, maximum: Int) throws {
            guard value >= 0, value <= maximum else {
                throw InventoryError.invalidLimit(name: name, value: value, maximum: maximum)
            }
            if name == "maximumWorkUnits" || name == "cancellationCheckInterval" {
                guard value >= 1 else {
                    throw InventoryError.invalidLimit(name: name, value: value, maximum: maximum)
                }
            }
        }
    }

    public enum InventoryError: Error, Equatable, LocalizedError, Sendable {
        case invalidLimit(name: String, value: Int, maximum: Int)
        case countLimitExceeded(kind: String, maximum: Int)
        case stringTooLarge(field: String, maximumUTF8Bytes: Int)
        case totalStringsTooLarge(maximumUTF8Bytes: Int)
        case workLimitExceeded(maximum: Int)
        case findingLimitExceeded(maximum: Int)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .invalidLimit(let name, let value, let maximum):
                "Toolbar accessibility inventory limit \(name) is invalid (\(value)); supported maximum is \(maximum)."
            case .countLimitExceeded(let kind, let maximum):
                "Toolbar accessibility inventory exceeds the \(maximum)-\(kind) limit."
            case .stringTooLarge(let field, let maximumUTF8Bytes):
                "Toolbar accessibility inventory field \(field) exceeds \(maximumUTF8Bytes) UTF-8 bytes."
            case .totalStringsTooLarge(let maximumUTF8Bytes):
                "Toolbar accessibility inventory strings exceed \(maximumUTF8Bytes) UTF-8 bytes."
            case .workLimitExceeded(let maximum):
                "Toolbar accessibility inventory exceeds the \(maximum)-unit work limit."
            case .findingLimitExceeded(let maximum):
                "Toolbar accessibility inventory exceeds the \(maximum)-finding limit."
            case .cancelled:
                "Toolbar accessibility inventory was cancelled."
            }
        }
    }

    public enum FindingSeverity: String, CaseIterable, Comparable, Hashable, Sendable {
        case advisory
        case warning
        case error

        public static func < (left: Self, right: Self) -> Bool {
            rank(left) < rank(right)
        }
    }

    public enum FindingCode: String, CaseIterable, Hashable, Sendable {
        case missingControl
        case unexpectedControl
        case duplicateControl
        case blankLabel
        case duplicateLabel
        case nonNilValue
        case duplicateValue
        case blankHint
        case duplicateHint
        case blankTooltip
        case duplicateTooltip
        case focusOrderMissing
        case focusOrderUnexpected
        case focusOrderMismatch
    }

    public struct Finding: Identifiable, Hashable, Sendable {
        public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue.precomposedStringWithCanonicalMapping
            }

            public static func < (left: Self, right: Self) -> Bool {
                compareUTF8(left.rawValue, right.rawValue) < 0
            }
        }

        public let id: ID
        public let severity: FindingSeverity
        public let code: FindingCode
        public let command: Command?
        public let subjectID: ToolbarAuditStableID?
        public let message: String

        fileprivate init(
            severity: FindingSeverity,
            code: FindingCode,
            command: Command? = nil,
            subjectID: ToolbarAuditStableID? = nil,
            discriminator: String = "",
            message: String
        ) {
            self.severity = severity
            self.code = code
            self.command = command
            self.subjectID = subjectID
            self.message = message
            id = ID(
                rawValue: [
                    code.rawValue,
                    command?.rawValue ?? "",
                    subjectID?.rawValue ?? "",
                    discriminator
                ].map(lengthPrefixed).joined()
            )
        }
    }

    public struct ControlBinding: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let id: ToolbarAuditStableID
        public let command: Command
        public let primaryActionID: ToolbarAuditStableID
        public let accessibility: ToolbarAuditAXMetadata
        public let tooltip: String
        public let focusIndex: Int

        fileprivate init(
            id: ToolbarAuditStableID,
            command: Command,
            primaryActionID: ToolbarAuditStableID,
            accessibility: ToolbarAuditAXMetadata,
            tooltip: String,
            focusIndex: Int
        ) {
            self.id = id
            self.command = command
            self.primaryActionID = primaryActionID
            self.accessibility = accessibility
            self.tooltip = tooltip
            self.focusIndex = focusIndex
        }

        public var description: String {
            "ToolbarAccessibilityInventory.ControlBinding(command: \(command.rawValue), focusIndex: \(focusIndex), text: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["command": command, "focusIndex": focusIndex, "text": "<redacted>"], displayStyle: .struct)
        }
    }

    public struct Inventory: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let manifestRevision: ToolbarAuditRevision
        public let bindings: [ControlBinding]
        public let focusOrder: [ToolbarAuditStableID]

        fileprivate init(
            manifestRevision: ToolbarAuditRevision,
            bindings: [ControlBinding],
            focusOrder: [ToolbarAuditStableID]
        ) {
            self.manifestRevision = manifestRevision
            self.bindings = bindings
            self.focusOrder = focusOrder
        }

        public func binding(for command: Command) -> ControlBinding? {
            bindings.first { $0.command == command }
        }

        public func controlRequirements() -> [ToolbarAuditControlRequirement] {
            bindings.map { binding in
                ToolbarAuditControlRequirement(
                    id: binding.id,
                    command: binding.command,
                    behavior: ToolbarAuditControlBehavior(primaryActionID: binding.primaryActionID),
                    tooltip: binding.tooltip,
                    accessibility: binding.accessibility
                )
            }
        }

        public var description: String {
            "ToolbarAccessibilityInventory.Inventory(controls: \(bindings.count), focus: \(focusOrder.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "manifestRevision": manifestRevision.rawValue,
                    "controlCount": bindings.count,
                    "focusOrderCount": focusOrder.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Receipt: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let formatVersion: Int
        public let manifestRevision: ToolbarAuditRevision
        public let controlCount: Int
        public let focusOrderCount: Int
        public let findingCount: Int
        public let contentDigest: UInt64

        fileprivate init(
            formatVersion: Int,
            manifestRevision: ToolbarAuditRevision,
            controlCount: Int,
            focusOrderCount: Int,
            findingCount: Int,
            contentDigest: UInt64
        ) {
            self.formatVersion = formatVersion
            self.manifestRevision = manifestRevision
            self.controlCount = controlCount
            self.focusOrderCount = focusOrderCount
            self.findingCount = findingCount
            self.contentDigest = contentDigest
        }

        public var description: String {
            "ToolbarAccessibilityInventory.Receipt(controls: \(controlCount), findings: \(findingCount), digest: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "formatVersion": formatVersion,
                    "manifestRevision": manifestRevision.rawValue,
                    "controlCount": controlCount,
                    "focusOrderCount": focusOrderCount,
                    "findingCount": findingCount,
                    "digest": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public struct Result: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let inventory: Inventory
        public let findings: [Finding]
        public let receipt: Receipt

        public var passed: Bool { findings.isEmpty }
        public var containsErrors: Bool { findings.contains { $0.severity == .error } }
        public var highestSeverity: FindingSeverity? { findings.first?.severity }

        fileprivate init(inventory: Inventory, findings: [Finding], receipt: Receipt) {
            self.inventory = inventory
            self.findings = findings
            self.receipt = receipt
        }

        public var description: String {
            "ToolbarAccessibilityInventory.Result(controls: \(inventory.bindings.count), findings: \(findings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "controlCount": inventory.bindings.count,
                    "findingCount": findings.count,
                    "contents": "<redacted>"
                ],
                displayStyle: .struct
            )
        }
    }

    public static func plan(
        inputs: [ControlInput],
        focusOrder: [Command]? = nil,
        manifest: ToolbarAuditManifest = .canonical,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Result {
        try limits.validate()
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try budget.checkCancellation()
        guard inputs.count <= limits.maximumControls else {
            throw InventoryError.countLimitExceeded(kind: "controls", maximum: limits.maximumControls)
        }
        if let focusOrder {
            guard focusOrder.count <= limits.maximumControls else {
                throw InventoryError.countLimitExceeded(kind: "focusOrder", maximum: limits.maximumControls)
            }
        }
        try checkStringLimits(inputs: inputs, limits: limits, budget: &budget)
        try budget.checkCancellation()

        var findings: [Finding] = []
        let manifestCommands = manifest.commands
        let manifestSet = Set(manifestCommands)
        var firstInputByCommand: [Command: ControlInput] = [:]
        var duplicateCommands: Set<Command> = []
        for input in inputs {
            try budget.consume()
            if firstInputByCommand[input.command] == nil {
                firstInputByCommand[input.command] = input
            } else {
                duplicateCommands.insert(input.command)
            }
        }
        let inputCommands = Set(firstInputByCommand.keys)
        for command in manifestCommands.sorted(by: { rank($0) < rank($1) }) {
            try budget.consume()
            if !inputCommands.contains(command) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .missingControl,
                        command: command,
                        subjectID: controlID(for: command),
                        message: "Toolbar command has no accessibility inventory entry."
                    )
                )
            }
        }
        for command in inputCommands.sorted(by: { rank($0) < rank($1) }) {
            try budget.consume()
            if !manifestSet.contains(command) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .unexpectedControl,
                        command: command,
                        subjectID: controlID(for: command),
                        message: "Inventory entry does not belong to the toolbar manifest."
                    )
                )
            }
        }
        for command in duplicateCommands.sorted(by: { rank($0) < rank($1) }) {
            try budget.consume()
            findings.append(
                Finding(
                    severity: .error,
                    code: .duplicateControl,
                    command: command,
                    subjectID: controlID(for: command),
                    message: "Toolbar command has duplicate inventory entries."
                )
            )
        }

        var labelCounts: [String: Int] = [:]
        var hintCounts: [String: Int] = [:]
        var tooltipCounts: [String: Int] = [:]
        var valueCounts: [String: Int] = [:]
        for command in manifestCommands {
            try budget.consume()
            guard let input = firstInputByCommand[command] else { continue }
            labelCounts[input.label, default: 0] += 1
            hintCounts[input.hint, default: 0] += 1
            tooltipCounts[input.tooltip, default: 0] += 1
            if let value = input.value {
                valueCounts[value, default: 0] += 1
            }
        }
        for command in manifestCommands {
            try budget.consume()
            guard let input = firstInputByCommand[command] else { continue }
            let subjectID = controlID(for: command)
            if isBlank(input.label) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .blankLabel,
                        command: command,
                        subjectID: subjectID,
                        message: "Toolbar control has no nonblank VoiceOver label."
                    )
                )
            } else if (labelCounts[input.label] ?? 0) > 1 {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .duplicateLabel,
                        command: command,
                        subjectID: subjectID,
                        message: "VoiceOver label is not unique in this toolbar."
                    )
                )
            }
            if let value = input.value {
                if (valueCounts[value] ?? 0) > 1 {
                    findings.append(
                        Finding(
                            severity: .error,
                            code: .duplicateValue,
                            command: command,
                            subjectID: subjectID,
                            message: "VoiceOver value is not unique in this toolbar."
                        )
                    )
                }
                findings.append(
                    Finding(
                        severity: .error,
                        code: .nonNilValue,
                        command: command,
                        subjectID: subjectID,
                        message: "Toolbar button value must be nil; buttons expose label and hint only."
                    )
                )
            }
            if isBlank(input.hint) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .blankHint,
                        command: command,
                        subjectID: subjectID,
                        message: "Toolbar control has no nonblank VoiceOver hint."
                    )
                )
            } else if (hintCounts[input.hint] ?? 0) > 1 {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .duplicateHint,
                        command: command,
                        subjectID: subjectID,
                        message: "VoiceOver hint is not unique in this toolbar."
                    )
                )
            }
            if isBlank(input.tooltip) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .blankTooltip,
                        command: command,
                        subjectID: subjectID,
                        message: "Toolbar control has no nonblank tooltip text."
                    )
                )
            } else if (tooltipCounts[input.tooltip] ?? 0) > 1 {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .duplicateTooltip,
                        command: command,
                        subjectID: subjectID,
                        message: "Toolbar tooltip text is not unique in this toolbar."
                    )
                )
            }
        }

        if let focusOrder {
            try checkFocusOrder(
                focusOrder,
                manifestCommands: manifestCommands,
                findings: &findings,
                budget: &budget
            )
        }

        let resolvedFocus: [Command] = {
            guard let focusOrder else { return manifestCommands }
            var seen: Set<Command> = []
            var ordered: [Command] = []
            for command in focusOrder where manifestSet.contains(command) {
                if seen.insert(command).inserted { ordered.append(command) }
            }
            for command in manifestCommands where !seen.contains(command) {
                ordered.append(command)
            }
            return ordered
        }()

        var bindings: [ControlBinding] = []
        var focusIDs: [ToolbarAuditStableID] = []
        for (focusIndex, command) in resolvedFocus.enumerated() {
            try budget.consume()
            guard let input = firstInputByCommand[command] else { continue }
            let id = controlID(for: command)
            let primary = primaryActionID(for: command)
            let accessibility = ToolbarAuditAXMetadata(
                identifier: id,
                role: .button,
                label: input.label,
                value: input.value,
                hint: input.hint,
                isEnabled: nil,
                checkedState: .notApplicable,
                selectedState: .notApplicable,
                isKeyboardFocusable: true,
                actions: [.activate]
            )
            bindings.append(
                ControlBinding(
                    id: id,
                    command: command,
                    primaryActionID: primary,
                    accessibility: accessibility,
                    tooltip: input.tooltip,
                    focusIndex: focusIndex
                )
            )
            focusIDs.append(id)
        }

        let sortedFindings = try stableSorted(findings, budget: &budget)
        guard sortedFindings.count <= limits.maximumFindings else {
            throw InventoryError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        let inventory = Inventory(
            manifestRevision: manifest.revision,
            bindings: bindings,
            focusOrder: focusIDs
        )
        let digest = contentDigest(
            bindings: bindings,
            manifestRevision: manifest.revision
        )
        let receipt = Receipt(
            formatVersion: inventoryFormatVersion,
            manifestRevision: manifest.revision,
            controlCount: bindings.count,
            focusOrderCount: focusIDs.count,
            findingCount: sortedFindings.count,
            contentDigest: digest
        )
        try budget.finish()
        return Result(inventory: inventory, findings: sortedFindings, receipt: receipt)
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
                throw InventoryError.workLimitExceeded(maximum: maximum)
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
                throw InventoryError.cancelled
            }
        }

        func finish() throws {
            try checkCancellation()
        }
    }

    private static func checkStringLimits(inputs: [ControlInput], limits: Limits, budget: inout WorkBudget) throws {
        var total = 0
        for input in inputs {
            try budget.consume()
            let fields: [(String, String?)] = [
                ("label." + input.command.rawValue, input.label),
                ("hint." + input.command.rawValue, input.hint),
                ("tooltip." + input.command.rawValue, input.tooltip),
                ("value." + input.command.rawValue, input.value)
            ]
            for (field, text) in fields {
                guard let text else { continue }
                let count = text.utf8.count
                guard count <= limits.maximumStringUTF8Bytes else {
                    throw InventoryError.stringTooLarge(field: field, maximumUTF8Bytes: limits.maximumStringUTF8Bytes)
                }
                guard total <= limits.maximumTotalStringUTF8Bytes - count else {
                    throw InventoryError.totalStringsTooLarge(maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes)
                }
                total += count
            }
        }
    }

    private static func checkFocusOrder(
        _ focusOrder: [Command],
        manifestCommands: [Command],
        findings: inout [Finding],
        budget: inout WorkBudget
    ) throws {
        let manifestSet = Set(manifestCommands)
        let focusSet = Set(focusOrder)
        var seen: Set<Command> = []
        var hasDuplicate = false
        for command in focusOrder {
            try budget.consume()
            if !seen.insert(command).inserted {
                hasDuplicate = true
            }
        }
        for command in manifestCommands.sorted(by: { rank($0) < rank($1) }) {
            try budget.consume()
            if !focusSet.contains(command) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .focusOrderMissing,
                        command: command,
                        subjectID: controlID(for: command),
                        message: "Toolbar focus order is missing this command."
                    )
                )
            }
        }
        for command in focusSet.sorted(by: { rank($0) < rank($1) }) {
            try budget.consume()
            if !manifestSet.contains(command) {
                findings.append(
                    Finding(
                        severity: .error,
                        code: .focusOrderUnexpected,
                        command: command,
                        subjectID: controlID(for: command),
                        message: "Toolbar focus order contains an entry outside the manifest."
                    )
                )
            }
        }
        if hasDuplicate {
            findings.append(
                Finding(
                    severity: .error,
                    code: .focusOrderUnexpected,
                    discriminator: "duplicate",
                    message: "Toolbar focus order contains a duplicate command."
                )
            )
        }
        if focusSet == manifestSet, !hasDuplicate, focusOrder != manifestCommands {
            findings.append(
                Finding(
                    severity: .error,
                    code: .focusOrderMismatch,
                    discriminator: "order",
                    message: "Toolbar focus order differs from manifest command order."
                )
            )
        }
    }

    private static func rank(_ command: Command) -> Int {
        Command.allCases.firstIndex(of: command) ?? Int.max
    }

    private static func rank(_ severity: FindingSeverity) -> Int {
        switch severity {
        case .advisory: 0
        case .warning: 1
        case .error: 2
        }
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func lengthPrefixed(_ value: String) -> String {
        String(value.utf8.count) + ":" + value
    }

    private static func findingLess(_ left: Finding, _ right: Finding) -> Bool {
        if left.severity != right.severity {
            return rank(left.severity) > rank(right.severity)
        }
        if left.code.rawValue != right.code.rawValue {
            return compareUTF8(left.code.rawValue, right.code.rawValue) < 0
        }
        let leftRank = left.command.map(rank) ?? Int.max
        let rightRank = right.command.map(rank) ?? Int.max
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        let leftSubject = left.subjectID?.rawValue ?? ""
        let rightSubject = right.subjectID?.rawValue ?? ""
        if leftSubject != rightSubject {
            return compareUTF8(leftSubject, rightSubject) < 0
        }
        return compareUTF8(left.id.rawValue, right.id.rawValue) < 0
    }

    private static func stableSorted(_ values: [Finding], budget: inout WorkBudget) throws -> [Finding] {
        guard values.count > 1 else {
            try budget.consume(values.count)
            return values
        }
        var source = values
        var destination = values
        var width = 1
        while width < values.count {
            var start = 0
            while start < values.count {
                let middle = min(start + width, values.count)
                let end = min(middle + width, values.count)
                var left = start
                var right = middle
                var output = start
                while left < middle || right < end {
                    try budget.consume()
                    let takeLeft: Bool
                    if right >= end {
                        takeLeft = true
                    } else if left >= middle {
                        takeLeft = false
                    } else {
                        takeLeft = !findingLess(source[right], source[left])
                    }
                    if takeLeft {
                        destination[output] = source[left]
                        left += 1
                    } else {
                        destination[output] = source[right]
                        right += 1
                    }
                    output += 1
                }
                start = end
            }
            swap(&source, &destination)
            let (nextWidth, overflow) = width.multipliedReportingOverflow(by: 2)
            width = overflow ? values.count : nextWidth
        }
        return source
    }

    private static func contentDigest(bindings: [ControlBinding], manifestRevision: ToolbarAuditRevision) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func feed(_ text: String) {
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            hash ^= UInt64(0xff)
            hash &*= 1_099_511_628_211
        }
        feed(String(manifestRevision.rawValue))
        for binding in bindings {
            feed(binding.id.rawValue)
            feed(binding.command.rawValue)
            feed(binding.primaryActionID.rawValue)
            feed(binding.accessibility.label)
            feed(binding.accessibility.value ?? "")
            feed(binding.accessibility.hint)
            feed(binding.tooltip)
            feed(String(binding.focusIndex))
        }
        return hash
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
