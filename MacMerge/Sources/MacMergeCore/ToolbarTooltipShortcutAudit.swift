import Foundation

/// UI-independent bounded audit of WinMerge-equivalent toolbar tooltips and shortcut display.
///
/// Canonical text comes from `Src/Merge.rc` `STRINGTABLE` tooltip rows (`\n` suffix part)
/// and `Src/Merge2.rc` `IDR_MAINFRAME` order. No AppKit, AX runtime, or screenshot work occurs.
public enum ToolbarTooltipShortcutAudit: Sendable {
    public typealias Command = ToolbarConfiguration.Command
    public typealias Item = ToolbarConfiguration.Item
    public typealias Shortcut = ToolbarAuditShortcut
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let scopeStatement =
        "Static checks of caller-supplied toolbar tooltip and shortcut display values; not runtime UI or VoiceOver conformance."
    public static let canonicalRevision = ToolbarAuditManifest.canonicalRevision
    public static let winMergeItems: [Item] = ToolbarConfiguration.winMergeDefaultItems

    public static let winMergeGroups: [[Command]] = [
        [.newComparison, .openComparison, .save],
        [.undo, .redo],
        [.selectLineDifference],
        [.nextDifference, .previousDifference],
        [.nextConflict, .previousConflict],
        [.firstDifference, .currentDifference, .lastDifference],
        [.copyToRight, .copyToLeft],
        [.copyToRightAndAdvance, .copyToLeftAndAdvance],
        [.copyAllToRight, .copyAllToLeft],
        [.autoMerge],
        [.firstComparedFile, .previousComparedFile, .nextComparedFile, .lastComparedFile],
        [.options],
        [.refresh]
    ]

    public struct Entry: Hashable, Sendable {
        public let command: Command
        public let winMergeID: String
        public let tooltip: String
        public let shortcut: Shortcut?

        public init(
            command: Command,
            winMergeID: String,
            tooltip: String,
            shortcut: Shortcut? = nil
        ) {
            self.command = command
            self.winMergeID = winMergeID.precomposedStringWithCanonicalMapping
            self.tooltip = tooltip.precomposedStringWithCanonicalMapping
            self.shortcut = shortcut
        }

        public var shortcutDisplay: String? { shortcut?.display }
    }

    /// Exact WinMerge order, matching `winMergeItems` command order and `Command.allCases`.
    public static let canonicalEntries: [Entry] = [
        Entry(
            command: .newComparison, winMergeID: "ID_FILE_NEW", tooltip: "New Documents (Ctrl+N)",
            shortcut: Shortcut(key: "n", modifiers: [.control], display: "Ctrl+N")
        ),
        Entry(
            command: .openComparison, winMergeID: "ID_FILE_OPEN", tooltip: "Open (Ctrl+O)",
            shortcut: Shortcut(key: "o", modifiers: [.control], display: "Ctrl+O")
        ),
        Entry(
            command: .save, winMergeID: "ID_FILE_SAVE", tooltip: "Save (Ctrl+S)",
            shortcut: Shortcut(key: "s", modifiers: [.control], display: "Ctrl+S")
        ),
        Entry(
            command: .undo, winMergeID: "ID_EDIT_UNDO", tooltip: "Undo (Ctrl+Z)",
            shortcut: Shortcut(key: "z", modifiers: [.control], display: "Ctrl+Z")
        ),
        Entry(
            command: .redo, winMergeID: "ID_EDIT_REDO", tooltip: "Redo (Ctrl+Y)",
            shortcut: Shortcut(key: "y", modifiers: [.control], display: "Ctrl+Y")
        ),
        Entry(
            command: .selectLineDifference, winMergeID: "ID_SELECTLINEDIFF", tooltip: "Difference in Current Line (F4)",
            shortcut: Shortcut(key: "F4", display: "F4")
        ),
        Entry(
            command: .nextDifference, winMergeID: "ID_NEXTDIFF", tooltip: "Next Difference (Alt+Down)",
            shortcut: Shortcut(key: "Down", modifiers: [.option], display: "Alt+Down")
        ),
        Entry(
            command: .previousDifference, winMergeID: "ID_PREVDIFF", tooltip: "Previous Difference (Alt+Up)",
            shortcut: Shortcut(key: "Up", modifiers: [.option], display: "Alt+Up")
        ),
        Entry(
            command: .nextConflict, winMergeID: "ID_NEXTCONFLICT", tooltip: "Next Conflict (Alt+Shift+Down)",
            shortcut: Shortcut(key: "Down", modifiers: [.option, .shift], display: "Alt+Shift+Down")
        ),
        Entry(
            command: .previousConflict, winMergeID: "ID_PREVCONFLICT", tooltip: "Previous Conflict (Alt+Shift+Up)",
            shortcut: Shortcut(key: "Up", modifiers: [.option, .shift], display: "Alt+Shift+Up")
        ),
        Entry(
            command: .firstDifference, winMergeID: "ID_FIRSTDIFF", tooltip: "First Difference (Alt+Home)",
            shortcut: Shortcut(key: "Home", modifiers: [.option], display: "Alt+Home")
        ),
        Entry(
            command: .currentDifference, winMergeID: "ID_CURDIFF", tooltip: "Current Difference (Alt+Enter)",
            shortcut: Shortcut(key: "Enter", modifiers: [.option], display: "Alt+Enter")
        ),
        Entry(
            command: .lastDifference, winMergeID: "ID_LASTDIFF", tooltip: "Last Difference (Alt+End)",
            shortcut: Shortcut(key: "End", modifiers: [.option], display: "Alt+End")
        ),
        Entry(
            command: .copyToRight, winMergeID: "ID_L2R", tooltip: "Copy to Right (Alt+Right)",
            shortcut: Shortcut(key: "Right", modifiers: [.option], display: "Alt+Right")
        ),
        Entry(
            command: .copyToLeft, winMergeID: "ID_R2L", tooltip: "Copy to Left (Alt+Left)",
            shortcut: Shortcut(key: "Left", modifiers: [.option], display: "Alt+Left")
        ),
        Entry(
            command: .copyToRightAndAdvance, winMergeID: "ID_L2RNEXT", tooltip: "Copy to Right and Advance (Ctrl+Alt+Right)",
            shortcut: Shortcut(key: "Right", modifiers: [.control, .option], display: "Ctrl+Alt+Right")
        ),
        Entry(
            command: .copyToLeftAndAdvance, winMergeID: "ID_R2LNEXT", tooltip: "Copy to Left and Advance (Ctrl+Alt+Left)",
            shortcut: Shortcut(key: "Left", modifiers: [.control, .option], display: "Ctrl+Alt+Left")
        ),
        Entry(command: .copyAllToRight, winMergeID: "ID_ALL_RIGHT", tooltip: "Copy All to Right"),
        Entry(command: .copyAllToLeft, winMergeID: "ID_ALL_LEFT", tooltip: "Copy All to Left"),
        Entry(
            command: .autoMerge, winMergeID: "ID_AUTO_MERGE", tooltip: "Auto Merge (Ctrl+Alt+M)",
            shortcut: Shortcut(key: "m", modifiers: [.control, .option], display: "Ctrl+Alt+M")
        ),
        Entry(command: .firstComparedFile, winMergeID: "ID_FIRSTFILE", tooltip: "First File"),
        Entry(
            command: .previousComparedFile, winMergeID: "ID_PREVFILE", tooltip: "Previous File (Ctrl+F7)",
            shortcut: Shortcut(key: "F7", modifiers: [.control], display: "Ctrl+F7")
        ),
        Entry(
            command: .nextComparedFile, winMergeID: "ID_NEXTFILE", tooltip: "Next File (Ctrl+F8)",
            shortcut: Shortcut(key: "F8", modifiers: [.control], display: "Ctrl+F8")
        ),
        Entry(command: .lastComparedFile, winMergeID: "ID_LASTFILE", tooltip: "Last File"),
        Entry(command: .options, winMergeID: "ID_OPTIONS", tooltip: "Options"),
        Entry(command: .refresh, winMergeID: "ID_REFRESH", tooltip: "Refresh (F5)", shortcut: Shortcut(key: "F5", display: "F5"))
    ]

    public static func entry(for command: Command) -> Entry {
        guard let found = canonicalEntries.first(where: { $0.command == command }) else {
            preconditionFailure("Canonical tooltip entry is missing")
        }
        return found
    }

    public static func tooltip(for command: Command) -> String {
        entry(for: command).tooltip
    }

    public static func shortcut(for command: Command) -> Shortcut? {
        entry(for: command).shortcut
    }

    public static func shortcutDisplay(for command: Command) -> String? {
        entry(for: command).shortcutDisplay
    }

    public static func winMergeID(for command: Command) -> String {
        entry(for: command).winMergeID
    }

    /// Deterministic `Command.allCases` order, matching WinMerge toolbar order.
    public static var orderedCommands: [Command] { canonicalEntries.map(\.command) }

    public static func canonicalObservations() -> [Observation] {
        canonicalEntries.map {
            Observation(command: $0.command, tooltip: $0.tooltip, shortcut: $0.shortcut)
        }
    }

    public struct Observation: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let command: Command
        public let tooltip: String?
        public let shortcut: Shortcut?

        public init(command: Command, tooltip: String?, shortcut: Shortcut? = nil) {
            self.command = command
            self.tooltip = tooltip?.precomposedStringWithCanonicalMapping
            self.shortcut = shortcut
        }

        public var description: String {
            "ToolbarTooltipShortcutAudit.Observation(command: \(command.rawValue), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(self, children: ["command": command, "contents": "<redacted>"], displayStyle: .struct)
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case entries
        case items
        case stringUTF8Bytes
        case totalStringUTF8Bytes
        case workUnits
        case findings
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumEntries = Command.allCases.count
        public static let hardMaximumItems = ToolbarConfiguration.maximumItemCount
        public static let hardMaximumStringUTF8Bytes = 4 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 256 * 1_024
        public static let hardMaximumWorkUnits = 1_024 * 1_024
        public static let hardMaximumFindings = 4_096
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumEntries: Int
        public let maximumItems: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumWorkUnits: Int
        public let maximumFindings: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumEntries: Int = hardMaximumEntries,
            maximumItems: Int = hardMaximumItems,
            maximumStringUTF8Bytes: Int = 1_024,
            maximumTotalStringUTF8Bytes: Int = 64 * 1_024,
            maximumWorkUnits: Int = 65_536,
            maximumFindings: Int = 256,
            cancellationCheckInterval: Int = 16
        ) {
            self.maximumEntries = maximumEntries
            self.maximumItems = maximumItems
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.maximumFindings = maximumFindings
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (0...Self.hardMaximumEntries).contains(maximumEntries) else {
                throw AuditError.invalidLimit(name: "maximumEntries", value: maximumEntries, maximum: Self.hardMaximumEntries)
            }
            guard (0...Self.hardMaximumItems).contains(maximumItems) else {
                throw AuditError.invalidLimit(name: "maximumItems", value: maximumItems, maximum: Self.hardMaximumItems)
            }
            guard (1...Self.hardMaximumStringUTF8Bytes).contains(maximumStringUTF8Bytes) else {
                throw AuditError.invalidLimit(name: "maximumStringUTF8Bytes", value: maximumStringUTF8Bytes, maximum: Self.hardMaximumStringUTF8Bytes)
            }
            guard (1...Self.hardMaximumTotalStringUTF8Bytes).contains(maximumTotalStringUTF8Bytes) else {
                throw AuditError.invalidLimit(
                    name: "maximumTotalStringUTF8Bytes", value: maximumTotalStringUTF8Bytes, maximum: Self.hardMaximumTotalStringUTF8Bytes)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw AuditError.invalidLimit(name: "maximumWorkUnits", value: maximumWorkUnits, maximum: Self.hardMaximumWorkUnits)
            }
            guard (0...Self.hardMaximumFindings).contains(maximumFindings) else {
                throw AuditError.invalidLimit(name: "maximumFindings", value: maximumFindings, maximum: Self.hardMaximumFindings)
            }
            guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
                throw AuditError.invalidLimit(
                    name: "cancellationCheckInterval", value: cancellationCheckInterval, maximum: Self.hardMaximumCancellationCheckInterval)
            }
        }
    }

    public enum AuditError: Error, Equatable, LocalizedError, Sendable {
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
                "Toolbar tooltip audit limit \(name) is invalid (\(value)); supported maximum is \(maximum)."
            case .countLimitExceeded(let kind, let maximum):
                "Toolbar tooltip audit exceeds the \(maximum)-\(kind) limit."
            case .stringTooLarge(let field, let maximumUTF8Bytes):
                "Toolbar tooltip audit field \(field) exceeds \(maximumUTF8Bytes) UTF-8 bytes."
            case .totalStringsTooLarge(let maximumUTF8Bytes):
                "Toolbar tooltip audit strings exceed \(maximumUTF8Bytes) UTF-8 bytes."
            case .workLimitExceeded(let maximum):
                "Toolbar tooltip audit exceeds the \(maximum)-unit work limit."
            case .findingLimitExceeded(let maximum):
                "Toolbar tooltip audit exceeds the \(maximum)-finding limit."
            case .cancelled:
                "Toolbar tooltip audit was cancelled."
            }
        }
    }

    public enum FindingCode: String, CaseIterable, Hashable, Sendable {
        case missingEntry
        case unexpectedEntry
        case duplicateEntry
        case tooltipMissing
        case tooltipMismatch
        case shortcutMissing
        case shortcutMismatch
        case duplicateShortcut
        case orderMismatch
        case groupingMismatch
    }

    public struct Finding: Hashable, Sendable {
        public struct ID: RawRepresentable, Comparable, Hashable, Sendable {
            public let rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue.precomposedStringWithCanonicalMapping
            }

            public static func < (left: Self, right: Self) -> Bool {
                left.rawValue.utf8.lexicographicallyPrecedes(right.rawValue.utf8)
            }
        }

        public let id: ID
        public let code: FindingCode
        public let command: Command?
        /// Fixed wording only. Observed tooltip, shortcut, and path text stays redacted.
        public let message: String

        fileprivate init(code: FindingCode, command: Command? = nil) {
            self.code = code
            self.command = command
            message = Self.fixedMessage(code)
            let commandPart = command?.rawValue ?? ""
            let framed = "\(code.rawValue.utf8.count):\(code.rawValue)\(commandPart.utf8.count):\(commandPart)"
            id = ID(rawValue: framed)
        }

        private static func fixedMessage(_ code: FindingCode) -> String {
            switch code {
            case .missingEntry:
                "Canonical toolbar command has no observation."
            case .unexpectedEntry:
                "Observation does not belong to canonical WinMerge order."
            case .duplicateEntry:
                "Duplicate observation for canonical toolbar command."
            case .tooltipMissing:
                "Toolbar tooltip evidence is missing."
            case .tooltipMismatch:
                "Toolbar tooltip differs from exact WinMerge-equivalent text."
            case .shortcutMissing:
                "Toolbar shortcut evidence is missing."
            case .shortcutMismatch:
                "Toolbar shortcut chord or display differs from WinMerge equivalent."
            case .duplicateShortcut:
                "Keyboard shortcut is assigned to multiple toolbar controls."
            case .orderMismatch:
                "Observed toolbar command order differs from WinMerge order."
            case .groupingMismatch:
                "Observed toolbar separator grouping differs from WinMerge."
            }
        }
    }

    public struct Receipt: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let revision: ToolbarAuditRevision
        public let checkedCommands: Int
        public let findingCount: Int
        public let workPerformed: Int
        public let passed: Bool

        fileprivate init(revision: ToolbarAuditRevision, checkedCommands: Int, findingCount: Int, workPerformed: Int) {
            self.revision = revision
            self.checkedCommands = checkedCommands
            self.findingCount = findingCount
            self.workPerformed = workPerformed
            passed = findingCount == 0
        }

        public var description: String {
            "ToolbarTooltipShortcutAudit.Receipt(checked: \(checkedCommands), findings: \(findingCount), work: \(workPerformed), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self, children: ["checkedCommands": checkedCommands, "findingCount": findingCount, "workPerformed": workPerformed, "contents": "<redacted>"],
                displayStyle: .struct)
        }
    }

    public struct Report: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let revision: ToolbarAuditRevision
        public let findings: [Finding]
        public let checkedCommands: Int
        public let workPerformed: Int
        public let receipt: Receipt

        public var passed: Bool { findings.isEmpty }
        public var mismatchCount: Int { findings.count }

        fileprivate init(revision: ToolbarAuditRevision, findings: [Finding], checkedCommands: Int, workPerformed: Int) {
            self.revision = revision
            self.findings = findings
            self.checkedCommands = checkedCommands
            self.workPerformed = workPerformed
            receipt = Receipt(revision: revision, checkedCommands: checkedCommands, findingCount: findings.count, workPerformed: workPerformed)
        }

        public var description: String {
            "ToolbarTooltipShortcutAudit.Report(checked: \(checkedCommands), findings: \(findings.count), contents: <redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self, children: ["checkedCommands": checkedCommands, "findingCount": findings.count, "workPerformed": workPerformed, "contents": "<redacted>"],
                displayStyle: .struct)
        }
    }

    /// Audits caller-supplied observations against canonical WinMerge tooltips and shortcuts.
    /// `items`, when provided, is checked for exact command order and separator grouping.
    public static func audit(
        observations: [Observation],
        items: [Item]? = nil,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Report {
        try limits.validate()
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try budget.checkCancellation()
        guard observations.count <= limits.maximumEntries else {
            throw AuditError.countLimitExceeded(kind: "observation", maximum: limits.maximumEntries)
        }
        if let items {
            guard items.count <= limits.maximumItems else {
                throw AuditError.countLimitExceeded(kind: "item", maximum: limits.maximumItems)
            }
        }
        var strings = StringBudget(limits: limits)
        for observation in observations {
            try budget.consume()
            if let tooltip = observation.tooltip {
                try strings.add(tooltip, field: "observation.tooltip")
            }
            if let shortcut = observation.shortcut {
                try strings.add(shortcut.key, field: "observation.shortcut.key")
                try strings.add(shortcut.display, field: "observation.shortcut.display")
            }
        }
        for entry in canonicalEntries {
            try budget.consume()
            try strings.add(entry.tooltip, field: "canonical.tooltip")
            try strings.add(entry.winMergeID, field: "canonical.id")
            if let shortcut = entry.shortcut {
                try strings.add(shortcut.key, field: "canonical.shortcut.key")
                try strings.add(shortcut.display, field: "canonical.shortcut.display")
            }
        }

        let canonicalByCommand = Dictionary(uniqueKeysWithValues: canonicalEntries.map { ($0.command, $0) })
        var findings: [Finding] = []
        func add(_ code: FindingCode, command: Command? = nil) throws {
            try budget.consume()
            guard findings.count < limits.maximumFindings else {
                throw AuditError.findingLimitExceeded(maximum: limits.maximumFindings)
            }
            findings.append(Finding(code: code, command: command))
        }

        var seen: Set<Command> = []
        for observation in observations {
            try budget.consume()
            guard seen.insert(observation.command).inserted else {
                try add(.duplicateEntry, command: observation.command)
                continue
            }
            guard canonicalByCommand[observation.command] != nil else {
                try add(.unexpectedEntry, command: observation.command)
                continue
            }
        }

        for entry in canonicalEntries {
            try budget.consume()
            guard let observed = observations.first(where: { $0.command == entry.command }) else {
                try add(.missingEntry, command: entry.command)
                continue
            }
            if let tooltip = observed.tooltip {
                if tooltip != entry.tooltip {
                    try add(.tooltipMismatch, command: entry.command)
                }
            } else {
                try add(.tooltipMissing, command: entry.command)
            }
            if let expected = entry.shortcut {
                guard let actual = observed.shortcut else {
                    try add(.shortcutMissing, command: entry.command)
                    continue
                }
                if actual != expected {
                    try add(.shortcutMismatch, command: entry.command)
                }
            } else if observed.shortcut != nil {
                try add(.shortcutMismatch, command: entry.command)
            }
        }

        var chordOwners: [String: [Command]] = [:]
        for observation in observations {
            try budget.consume()
            guard let chord = observation.shortcut?.canonicalChord else { continue }
            chordOwners[chord, default: []].append(observation.command)
        }
        for (_, owners) in chordOwners {
            try budget.consume()
            guard owners.count > 1 else { continue }
            for command in owners.sorted(by: { rank($0) < rank($1) }) {
                try add(.duplicateShortcut, command: command)
            }
        }

        let observedRanks = observations.map { rank($0.command) }
        var lastRank = -1
        var outOfOrder = false
        for current in observedRanks {
            try budget.consume()
            if current <= lastRank {
                outOfOrder = true
                break
            }
            lastRank = current
        }
        if outOfOrder {
            try add(.orderMismatch)
        }

        if let items {
            try budget.consume(items.count)
            if items.compactMap(\.command) != winMergeItems.compactMap(\.command) {
                try add(.orderMismatch)
            } else if separatorBoundaries(items) != separatorBoundaries(winMergeItems) {
                try add(.groupingMismatch)
            }
        }

        try budget.finish()
        let sorted = findings.sorted {
            if $0.code != $1.code { return codeRank($0.code) < codeRank($1.code) }
            switch ($0.command, $1.command) {
            case (nil, nil): return $0.id < $1.id
            case (nil, _): return true
            case (_, nil): return false
            case (let left?, let right?):
                if left != right { return rank(left) < rank(right) }
                return $0.id < $1.id
            }
        }
        return Report(revision: canonicalRevision, findings: sorted, checkedCommands: observations.count, workPerformed: budget.completed)
    }

    /// Convenience mapping from full toolbar surface observations. Availability and AX state are ignored.
    public static func auditControls(
        _ controls: [ToolbarAuditControlObservation],
        items: [Item]? = nil,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Report {
        try audit(
            observations: controls.map { Observation(command: $0.command, tooltip: $0.tooltip, shortcut: $0.shortcut) },
            items: items,
            limits: limits,
            cancellationCheck: cancellationCheck
        )
    }

    private static func rank(_ command: Command) -> Int {
        Command.allCases.firstIndex(of: command) ?? Int.max
    }

    private static func codeRank(_ code: FindingCode) -> Int {
        FindingCode.allCases.firstIndex(of: code) ?? Int.max
    }

    private static func separatorBoundaries(_ items: [Item]) -> [Int] {
        var result: [Int] = []
        var count = 0
        for item in items {
            switch item {
            case .command:
                count += 1
            case .separator:
                result.append(count)
            }
        }
        return result
    }

    private struct WorkBudget {
        let maximum: Int
        let interval: Int
        let cancellationCheck: CancellationCheck
        private(set) var completed = 0
        private var nextCheck: Int

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) {
            maximum = limits.maximumWorkUnits
            interval = limits.cancellationCheckInterval
            self.cancellationCheck = cancellationCheck
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
                try cancellationCheck()
            } catch {
                throw AuditError.cancelled
            }
        }

        func finish() throws {
            try checkCancellation()
        }
    }

    private struct StringBudget {
        let limits: Limits
        private var total = 0

        init(limits: Limits) {
            self.limits = limits
        }

        mutating func add(_ value: String, field: String) throws {
            let count = value.utf8.count
            guard count <= limits.maximumStringUTF8Bytes else {
                throw AuditError.stringTooLarge(field: field, maximumUTF8Bytes: limits.maximumStringUTF8Bytes)
            }
            guard total <= limits.maximumTotalStringUTF8Bytes - count else {
                throw AuditError.totalStringsTooLarge(maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes)
            }
            total += count
        }
    }
}
