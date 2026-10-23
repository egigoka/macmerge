import CryptoKit
import Foundation

/// UI-independent audit planning for toolbar tooltip text and shortcut display.
///
/// Planning only. No AppKit, AX runtime, screenshot, filesystem, or process inspection occurs.
/// Callers supply candidate audit rows; the planner validates bounds, allowlist membership,
/// shortcut canonicalization, and verdict consistency, then binds a deterministic receipt.
public enum ToolbarTooltipAuditPlan: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void

    public static let scopeStatement =
        "Static planning of caller-supplied toolbar tooltip and shortcut display rows; not runtime UI or VoiceOver conformance."
    public static let planFormatVersion = 1
    public static let receiptDomain = "toolbar-tooltip-audit.v1"

    /// Stable WinMerge command identities from `Src/Merge.rc` tooltip rows.
    public static let allowedCommandIDs: Set<String> = [
        "ID_FILE_NEW",
        "ID_FILE_OPEN",
        "ID_FILE_SAVE",
        "ID_EDIT_UNDO",
        "ID_EDIT_REDO",
        "ID_SELECTLINEDIFF",
        "ID_NEXTDIFF",
        "ID_PREVDIFF",
        "ID_NEXTCONFLICT",
        "ID_PREVCONFLICT",
        "ID_FIRSTDIFF",
        "ID_CURDIFF",
        "ID_LASTDIFF",
        "ID_L2R",
        "ID_R2L",
        "ID_L2RNEXT",
        "ID_R2LNEXT",
        "ID_ALL_RIGHT",
        "ID_ALL_LEFT",
        "ID_AUTO_MERGE",
        "ID_FIRSTFILE",
        "ID_PREVFILE",
        "ID_NEXTFILE",
        "ID_LASTFILE",
        "ID_OPTIONS",
        "ID_REFRESH"
    ]

    public static func canonicalWinMergeTooltip(for commandID: String) -> String? {
        let trimmed = commandID.trimmingCharacters(in: .whitespacesAndNewlines)
        for entry in ToolbarTooltipShortcutAudit.canonicalEntries where entry.winMergeID == trimmed {
            return entry.tooltip
        }
        return nil
    }

    public static func canonicalWinMergeShortcutDisplay(for commandID: String) -> String? {
        let trimmed = commandID.trimmingCharacters(in: .whitespacesAndNewlines)
        for entry in ToolbarTooltipShortcutAudit.canonicalEntries where entry.winMergeID == trimmed {
            return entry.shortcut?.display
        }
        return nil
    }

    public enum Verdict: String, CaseIterable, Hashable, Sendable {
        case match
        case documentedGap = "documented-gap"
    }

    public struct Entry: Hashable, Sendable {
        public let commandID: String
        public let winMergeTooltip: String
        public let macTooltip: String
        public let shortcutDisplay: String?
        public let verdict: Verdict

        public init(
            commandID: String,
            winMergeTooltip: String,
            macTooltip: String,
            shortcutDisplay: String? = nil,
            verdict: Verdict
        ) {
            self.commandID = commandID.precomposedStringWithCanonicalMapping
            self.winMergeTooltip = winMergeTooltip.precomposedStringWithCanonicalMapping
            self.macTooltip = macTooltip.precomposedStringWithCanonicalMapping
            self.shortcutDisplay = shortcutDisplay?.precomposedStringWithCanonicalMapping
            self.verdict = verdict
        }
    }

    public struct Binding: Hashable, Sendable {
        public let commandID: String
        public let winMergeTooltip: String
        public let macTooltip: String
        public let canonicalShortcutDisplay: String?
        public let verdict: Verdict
        public let generation: UInt64

        fileprivate init(
            commandID: String,
            winMergeTooltip: String,
            macTooltip: String,
            canonicalShortcutDisplay: String?,
            verdict: Verdict,
            generation: UInt64
        ) {
            self.commandID = commandID
            self.winMergeTooltip = winMergeTooltip
            self.macTooltip = macTooltip
            self.canonicalShortcutDisplay = canonicalShortcutDisplay
            self.verdict = verdict
            self.generation = generation
        }
    }

    public enum Limit: String, CaseIterable, Hashable, Sendable {
        case entries
        case stringUTF8Bytes
        case totalStringUTF8Bytes
        case workUnits
        case findings
        case cancellationCheckInterval
    }

    public struct Limits: Hashable, Sendable {
        public static let hardMaximumEntries = 26
        public static let hardMaximumStringUTF8Bytes = 4 * 1_024
        public static let hardMaximumTotalStringUTF8Bytes = 256 * 1_024
        public static let hardMaximumWorkUnits = 1_024 * 1_024
        public static let hardMaximumFindings = 4_096
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumEntries: Int
        public let maximumStringUTF8Bytes: Int
        public let maximumTotalStringUTF8Bytes: Int
        public let maximumWorkUnits: Int
        public let maximumFindings: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumEntries: Int = hardMaximumEntries,
            maximumStringUTF8Bytes: Int = 1_024,
            maximumTotalStringUTF8Bytes: Int = 64 * 1_024,
            maximumWorkUnits: Int = 65_536,
            maximumFindings: Int = 256,
            cancellationCheckInterval: Int = 16
        ) {
            self.maximumEntries = maximumEntries
            self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
            self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
            self.maximumWorkUnits = maximumWorkUnits
            self.maximumFindings = maximumFindings
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (0...Self.hardMaximumEntries).contains(maximumEntries) else {
                throw PlanError.invalidLimit(.entries, value: maximumEntries)
            }
            guard (1...Self.hardMaximumStringUTF8Bytes).contains(maximumStringUTF8Bytes) else {
                throw PlanError.invalidLimit(.stringUTF8Bytes, value: maximumStringUTF8Bytes)
            }
            guard (1...Self.hardMaximumTotalStringUTF8Bytes).contains(maximumTotalStringUTF8Bytes) else {
                throw PlanError.invalidLimit(.totalStringUTF8Bytes, value: maximumTotalStringUTF8Bytes)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw PlanError.invalidLimit(.workUnits, value: maximumWorkUnits)
            }
            guard (0...Self.hardMaximumFindings).contains(maximumFindings) else {
                throw PlanError.invalidLimit(.findings, value: maximumFindings)
            }
            guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
                throw PlanError.invalidLimit(.cancellationCheckInterval, value: cancellationCheckInterval)
            }
        }
    }

    public enum PlanError: Error, Equatable, LocalizedError, Sendable {
        case invalidLimit(Limit, value: Int)
        case countLimitExceeded(count: Int, maximum: Int)
        case stringTooLarge(index: Int, maximumUTF8Bytes: Int)
        case totalStringsTooLarge(maximumUTF8Bytes: Int)
        case workLimitExceeded(maximum: Int)
        case findingLimitExceeded(maximum: Int)
        case emptyCommandID(index: Int)
        case unknownCommandID(index: Int)
        case duplicateCommandID(index: Int)
        case emptyWinMergeTooltip(index: Int)
        case emptyMacTooltip(index: Int)
        case invalidShortcut(index: Int)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .invalidLimit(let limit, let value):
                "Toolbar tooltip audit plan limit \(limit.rawValue) is invalid (\(value))."
            case .countLimitExceeded(let count, let maximum):
                "Toolbar tooltip audit plan has \(count) entries; limit is \(maximum)."
            case .stringTooLarge(let index, let maximum):
                "Toolbar tooltip audit plan entry \(index) exceeds \(maximum) UTF-8 bytes."
            case .totalStringsTooLarge(let maximum):
                "Toolbar tooltip audit plan strings exceed \(maximum) UTF-8 bytes."
            case .workLimitExceeded(let maximum):
                "Toolbar tooltip audit plan exceeds the \(maximum)-unit work limit."
            case .findingLimitExceeded(let maximum):
                "Toolbar tooltip audit plan exceeds the \(maximum)-finding limit."
            case .emptyCommandID(let index):
                "Toolbar tooltip audit plan entry \(index) has an empty command identifier."
            case .unknownCommandID(let index):
                "Toolbar tooltip audit plan entry \(index) is outside the allowlist."
            case .duplicateCommandID(let index):
                "Toolbar tooltip audit plan entry \(index) repeats a command identifier."
            case .emptyWinMergeTooltip(let index):
                "Toolbar tooltip audit plan entry \(index) has an empty WinMerge tooltip."
            case .emptyMacTooltip(let index):
                "Toolbar tooltip audit plan entry \(index) has an empty Mac tooltip."
            case .invalidShortcut(let index):
                "Toolbar tooltip audit plan entry \(index) has an invalid shortcut display."
            case .cancelled:
                "Toolbar tooltip audit plan was cancelled."
            }
        }
    }

    public enum FindingCode: String, CaseIterable, Hashable, Sendable {
        case winMergeTooltipMismatch
        case winMergeShortcutMismatch
        case tooltipMismatch
        case unnecessaryGap
        case missingCommand
    }

    public struct Finding: Hashable, Sendable {
        public let code: FindingCode
        public let entryIndex: Int?
        public let commandID: String
        public let message: String

        fileprivate init(code: FindingCode, entryIndex: Int?, commandID: String, message: String) {
            self.code = code
            self.entryIndex = entryIndex
            self.commandID = commandID.precomposedStringWithCanonicalMapping
            self.message = message
        }
    }

    public struct Receipt: Equatable, Hashable, Sendable {
        public static let byteCount = 32

        public let formatVersion: Int
        public let generation: UInt64
        public let entryCount: Int
        public let findingCount: Int
        public let bytes: [UInt8]

        fileprivate init(
            formatVersion: Int,
            generation: UInt64,
            entryCount: Int,
            findingCount: Int,
            bytes: [UInt8]
        ) {
            self.formatVersion = formatVersion
            self.generation = generation
            self.entryCount = entryCount
            self.findingCount = findingCount
            self.bytes = bytes
        }

        public var hex: String {
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    public struct Result: Equatable, Sendable {
        public let generation: UInt64
        public let bindings: [Binding]
        public let findings: [Finding]
        public let receipt: Receipt
        public let workPerformed: Int

        public var passed: Bool { findings.isEmpty }
        public var entryCount: Int { bindings.count }

        fileprivate init(
            generation: UInt64,
            bindings: [Binding],
            findings: [Finding],
            receipt: Receipt,
            workPerformed: Int
        ) {
            self.generation = generation
            self.bindings = bindings
            self.findings = findings
            self.receipt = receipt
            self.workPerformed = workPerformed
        }

        public func binding(for commandID: String) -> Binding? {
            let trimmed = commandID.trimmingCharacters(in: .whitespacesAndNewlines)
            return bindings.first { $0.commandID == trimmed }
        }
    }

    public static func plan(
        entries: [Entry],
        generation: UInt64,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Result {
        try limits.validate()
        var budget = WorkBudget(limits: limits, cancellationCheck: cancellationCheck)
        try budget.checkCancellation()
        guard entries.count <= limits.maximumEntries else {
            throw PlanError.countLimitExceeded(count: entries.count, maximum: limits.maximumEntries)
        }
        try checkStringLimits(entries: entries, limits: limits, budget: &budget)
        try budget.checkCancellation()

        var seen: Set<String> = []
        var normalizedIDs: [String] = []
        normalizedIDs.reserveCapacity(entries.count)
        var canonicalShortcuts: [String?] = []
        canonicalShortcuts.reserveCapacity(entries.count)
        // Command identity uses trimmed form throughout: empty check, allowlist,
        // dedup, canonical lookup, findings, presence, and bindings all use
        // trimmedID so padded duplicates cannot bypass membership/dedup.
        for (index, entry) in entries.enumerated() {
            try budget.consume()
            let trimmedID = entry.commandID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                throw PlanError.emptyCommandID(index: index)
            }
            guard allowedCommandIDs.contains(trimmedID) else {
                throw PlanError.unknownCommandID(index: index)
            }
            guard seen.insert(trimmedID).inserted else {
                throw PlanError.duplicateCommandID(index: index)
            }
            normalizedIDs.append(trimmedID)
            guard !entry.winMergeTooltip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlanError.emptyWinMergeTooltip(index: index)
            }
            guard !entry.macTooltip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlanError.emptyMacTooltip(index: index)
            }
            if let raw = entry.shortcutDisplay {
                guard let canonical = canonicalShortcutDisplay(raw) else {
                    throw PlanError.invalidShortcut(index: index)
                }
                canonicalShortcuts.append(canonical)
            } else {
                canonicalShortcuts.append(nil)
            }
        }

        var findings: [Finding] = []
        func addFinding(_ code: FindingCode, entryIndex: Int?, commandID: String, message: String) throws {
            try budget.consume()
            guard findings.count < limits.maximumFindings else {
                throw PlanError.findingLimitExceeded(maximum: limits.maximumFindings)
            }
            findings.append(Finding(code: code, entryIndex: entryIndex, commandID: commandID, message: message))
        }

        for (index, entry) in entries.enumerated() {
            try budget.consume()
            let commandID = normalizedIDs[index]
            if let canonical = canonicalWinMergeTooltip(for: commandID), canonical != entry.winMergeTooltip {
                try addFinding(
                    .winMergeTooltipMismatch,
                    entryIndex: index,
                    commandID: commandID,
                    message: "WinMerge tooltip does not match the canonical text for this command."
                )
            }
            if canonicalWinMergeShortcutDisplay(for: commandID) != canonicalShortcuts[index] {
                try addFinding(
                    .winMergeShortcutMismatch,
                    entryIndex: index,
                    commandID: commandID,
                    message: "Shortcut display does not match the canonical shortcut for this command."
                )
            }
            switch entry.verdict {
            case .match:
                if entry.macTooltip != entry.winMergeTooltip {
                    try addFinding(
                        .tooltipMismatch,
                        entryIndex: index,
                        commandID: commandID,
                        message: "Mac tooltip differs from WinMerge text but verdict claims match."
                    )
                }
            case .documentedGap:
                if entry.macTooltip == entry.winMergeTooltip {
                    try addFinding(
                        .unnecessaryGap,
                        entryIndex: index,
                        commandID: commandID,
                        message: "Mac tooltip equals WinMerge text but verdict claims a documented gap."
                    )
                }
            }
        }

        let present = Set(normalizedIDs)
        for commandID in allowedCommandIDs.sorted(by: { compareUTF8($0, $1) < 0 }) {
            try budget.consume()
            if !present.contains(commandID) {
                try addFinding(
                    .missingCommand,
                    entryIndex: nil,
                    commandID: commandID,
                    message: "Allowlisted command has no audit entry."
                )
            }
        }

        let sortedPairs = entries.indices.sorted { normalizedIDs[$0] < normalizedIDs[$1] }
        var bindings: [Binding] = []
        bindings.reserveCapacity(entries.count)
        for sortedIndex in sortedPairs {
            try budget.consume()
            let entry = entries[sortedIndex]
            bindings.append(
                Binding(
                    commandID: normalizedIDs[sortedIndex],
                    winMergeTooltip: entry.winMergeTooltip,
                    macTooltip: entry.macTooltip,
                    canonicalShortcutDisplay: canonicalShortcuts[sortedIndex],
                    verdict: entry.verdict,
                    generation: generation
                )
            )
        }

        let sortedFindings = stableSorted(findings)
        guard sortedFindings.count <= limits.maximumFindings else {
            throw PlanError.findingLimitExceeded(maximum: limits.maximumFindings)
        }
        let receipt = makeReceipt(bindings: bindings, generation: generation, findingCount: sortedFindings.count)
        try budget.finish()
        return Result(
            generation: generation,
            bindings: bindings,
            findings: sortedFindings,
            receipt: receipt,
            workPerformed: budget.completed
        )
    }

    /// Canonicalizes caller-supplied shortcut display text to `Ctrl/Alt/Shift/Cmd+Key` or `F<n>` form.
    /// Symbol expansion is separator-aware: `⌘`/`⌃`/`⌥`/`⇧` expand with `+`,
    /// then runs of `+` (with optional whitespace between) collapse to one,
    /// so `⌘+N` and `⌘ + N` both canonicalize to `Cmd+N`.
    public static func canonicalShortcutDisplay(_ raw: String) -> String? {
        var normalized = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        normalized =
            normalized
            .replacingOccurrences(of: "⌘", with: "Cmd+")
            .replacingOccurrences(of: "⌃", with: "Ctrl+")
            .replacingOccurrences(of: "⌥", with: "Alt+")
            .replacingOccurrences(of: "⇧", with: "Shift+")
        normalized = collapsePlusSeparators(normalized)
        let parts = normalized.split(separator: "+", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else { return nil }
        let keyRaw = String(parts.last ?? "")
        let modifierRaws = parts.dropLast()
        var modifiers: [String] = []
        for modifier in modifierRaws {
            let canonical: String
            switch modifier.lowercased() {
            case "cmd", "command":
                canonical = "Cmd"
            case "ctrl", "control", "ctl":
                canonical = "Ctrl"
            case "alt", "option", "opt":
                canonical = "Alt"
            case "shift":
                canonical = "Shift"
            default:
                return nil
            }
            guard !modifiers.contains(canonical) else { return nil }
            modifiers.append(canonical)
        }
        guard let key = canonicalKey(keyRaw) else { return nil }
        guard !modifiers.isEmpty else { return key }
        let order = ["Ctrl", "Alt", "Shift", "Cmd"]
        let sorted = modifiers.sorted {
            (order.firstIndex(of: $0) ?? Int.max) < (order.firstIndex(of: $1) ?? Int.max)
        }
        return (sorted + [key]).joined(separator: "+")
    }

    private static func collapsePlusSeparators(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "+" {
                if !output.hasSuffix("+") {
                    output.append("+")
                }
                index = value.index(after: index)
                var lookahead = index
                while lookahead < value.endIndex && value[lookahead].isWhitespace {
                    lookahead = value.index(after: lookahead)
                }
                if lookahead < value.endIndex && value[lookahead] == "+" {
                    index = lookahead
                }
            } else {
                output.append(value[index])
                index = value.index(after: index)
            }
        }
        return output
    }

    private static func canonicalKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("F"), upper.count >= 2, upper.count <= 3 {
            let number = String(upper.dropFirst())
            guard let value = Int(number), (1...24).contains(value) else { return nil }
            return upper
        }
        if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
            return upper
        }
        switch trimmed.lowercased() {
        case "down", "up", "left", "right", "home", "end", "enter":
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst().lowercased()
        case "return":
            return "Enter"
        case "delete", "backspace", "tab", "space", "escape", "insert":
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst().lowercased()
        case "esc":
            return "Escape"
        case "pageup":
            return "PageUp"
        case "pagedown":
            return "PageDown"
        default:
            return nil
        }
    }

    private static func checkStringLimits(entries: [Entry], limits: Limits, budget: inout WorkBudget) throws {
        var total = 0
        for (index, entry) in entries.enumerated() {
            try budget.consume()
            let fields: [String?] = [entry.commandID, entry.winMergeTooltip, entry.macTooltip, entry.shortcutDisplay]
            for text in fields {
                guard let text else { continue }
                let count = text.utf8.count
                guard count <= limits.maximumStringUTF8Bytes else {
                    throw PlanError.stringTooLarge(index: index, maximumUTF8Bytes: limits.maximumStringUTF8Bytes)
                }
                guard total <= limits.maximumTotalStringUTF8Bytes - count else {
                    throw PlanError.totalStringsTooLarge(maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes)
                }
                total += count
            }
        }
    }

    private static func makeReceipt(bindings: [Binding], generation: UInt64, findingCount: Int) -> Receipt {
        var input = Data(receiptDomain.utf8)
        input.append(0)
        var version = UInt32(planFormatVersion).bigEndian
        withUnsafeBytes(of: &version) { input.append(contentsOf: $0) }
        var generationBig = generation.bigEndian
        withUnsafeBytes(of: &generationBig) { input.append(contentsOf: $0) }
        for binding in bindings {
            appendLengthPrefixed(binding.commandID, to: &input)
            appendLengthPrefixed(binding.winMergeTooltip, to: &input)
            appendLengthPrefixed(binding.macTooltip, to: &input)
            appendLengthPrefixed(binding.canonicalShortcutDisplay ?? "", to: &input)
            appendLengthPrefixed(binding.verdict.rawValue, to: &input)
        }
        var countBig = UInt64(findingCount).bigEndian
        withUnsafeBytes(of: &countBig) { input.append(contentsOf: $0) }
        let digest = Array(SHA256.hash(data: input))
        return Receipt(
            formatVersion: planFormatVersion,
            generation: generation,
            entryCount: bindings.count,
            findingCount: findingCount,
            bytes: digest
        )
    }

    private static func appendLengthPrefixed(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        var count = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(contentsOf: bytes)
        data.append(0)
    }

    private static func stableSorted(_ findings: [Finding]) -> [Finding] {
        findings.sorted {
            if $0.code.rawValue != $1.code.rawValue { return $0.code.rawValue < $1.code.rawValue }
            if $0.commandID != $1.commandID { return compareUTF8($0.commandID, $1.commandID) < 0 }
            switch ($0.entryIndex, $1.entryIndex) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case (let left?, let right?): return left < right
            }
        }
    }

    private static func compareUTF8(_ left: String, _ right: String) -> Int {
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
                throw PlanError.workLimitExceeded(maximum: maximum)
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
                throw PlanError.cancelled
            }
        }

        func finish() throws {
            try checkCancellation()
        }
    }
}
