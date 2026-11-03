import Foundation

/// UI-independent WinMerge tooltip and shortcut-display parity table.
///
/// Source of truth for command identity and order is
/// `ToolbarConfiguration.Command` (the same type `ToolbarCommandLayout.Command`
/// and `ToolbarAuditContract.Command` alias). WinMerge text comes from the
/// `Src/Merge.rc` `STRINGTABLE` tooltip rows and `Src/Merge2.rc` `IDR_MAINFRAME`
/// order, matching `ToolbarTooltipShortcutAudit.canonicalEntries`. Planning only:
/// no AppKit, AX runtime, screenshot, filesystem, or process inspection occurs.
///
/// Callers use `entry(for:)` for display text and `validate()` to prove the table
/// has one non-empty row per command with no stale identifiers.
public enum ToolbarTooltipParity: Sendable {
    public typealias Command = ToolbarConfiguration.Command

    /// One parity row: WinMerge command identity plus display text.
    /// `shortcutDisplay` is `nil` exactly when WinMerge shows no shortcut.
    public struct Entry: Hashable, Sendable {
        public let command: Command
        public let winMergeID: String
        public let tooltip: String
        public let shortcutDisplay: String?

        public init(command: Command, winMergeID: String, tooltip: String, shortcutDisplay: String? = nil) {
            self.command = command
            self.winMergeID = winMergeID.precomposedStringWithCanonicalMapping
            self.tooltip = tooltip.precomposedStringWithCanonicalMapping
            self.shortcutDisplay = shortcutDisplay?.precomposedStringWithCanonicalMapping
        }
    }

    public enum ValidationError: Error, Equatable, LocalizedError, Sendable {
        case duplicateCommand(Command)
        case duplicateWinMergeID(String)
        case emptyWinMergeID(Command)
        case emptyTooltip(Command)
        case emptyShortcutDisplay(Command)
        case staleWinMergeID(Command, String)
        case missingCommand(Command)
        case unexpectedCommand(Command)

        public var errorDescription: String? {
            switch self {
            case .duplicateCommand(let command):
                "Toolbar tooltip parity has a duplicate entry for \(command.rawValue)."
            case .duplicateWinMergeID(let id):
                "Toolbar tooltip parity repeats WinMerge identifier \(id)."
            case .emptyWinMergeID(let command):
                "Toolbar tooltip parity entry \(command.rawValue) has an empty WinMerge identifier."
            case .emptyTooltip(let command):
                "Toolbar tooltip parity entry \(command.rawValue) has an empty tooltip."
            case .emptyShortcutDisplay(let command):
                "Toolbar tooltip parity entry \(command.rawValue) has an empty shortcut display."
            case .staleWinMergeID(let command, let id):
                "Toolbar tooltip parity entry \(command.rawValue) carries stale WinMerge identifier \(id)."
            case .missingCommand(let command):
                "Toolbar tooltip parity has no entry for \(command.rawValue)."
            case .unexpectedCommand(let command):
                "Toolbar tooltip parity entry \(command.rawValue) is not a known toolbar command."
            }
        }
    }

    /// Exact WinMerge order, matching `Command.allCases` and `winMergeDefaultItems` command order.
    public static let entries: [Entry] = [
        Entry(command: .newComparison, winMergeID: "ID_FILE_NEW", tooltip: "New Documents (Ctrl+N)", shortcutDisplay: "Ctrl+N"),
        Entry(command: .openComparison, winMergeID: "ID_FILE_OPEN", tooltip: "Open (Ctrl+O)", shortcutDisplay: "Ctrl+O"),
        Entry(command: .save, winMergeID: "ID_FILE_SAVE", tooltip: "Save (Ctrl+S)", shortcutDisplay: "Ctrl+S"),
        Entry(command: .undo, winMergeID: "ID_EDIT_UNDO", tooltip: "Undo (Ctrl+Z)", shortcutDisplay: "Ctrl+Z"),
        Entry(command: .redo, winMergeID: "ID_EDIT_REDO", tooltip: "Redo (Ctrl+Y)", shortcutDisplay: "Ctrl+Y"),
        Entry(command: .selectLineDifference, winMergeID: "ID_SELECTLINEDIFF", tooltip: "Difference in Current Line (F4)", shortcutDisplay: "F4"),
        Entry(command: .nextDifference, winMergeID: "ID_NEXTDIFF", tooltip: "Next Difference (Alt+Down)", shortcutDisplay: "Alt+Down"),
        Entry(command: .previousDifference, winMergeID: "ID_PREVDIFF", tooltip: "Previous Difference (Alt+Up)", shortcutDisplay: "Alt+Up"),
        Entry(command: .nextConflict, winMergeID: "ID_NEXTCONFLICT", tooltip: "Next Conflict (Alt+Shift+Down)", shortcutDisplay: "Alt+Shift+Down"),
        Entry(command: .previousConflict, winMergeID: "ID_PREVCONFLICT", tooltip: "Previous Conflict (Alt+Shift+Up)", shortcutDisplay: "Alt+Shift+Up"),
        Entry(command: .firstDifference, winMergeID: "ID_FIRSTDIFF", tooltip: "First Difference (Alt+Home)", shortcutDisplay: "Alt+Home"),
        Entry(command: .currentDifference, winMergeID: "ID_CURDIFF", tooltip: "Current Difference (Alt+Enter)", shortcutDisplay: "Alt+Enter"),
        Entry(command: .lastDifference, winMergeID: "ID_LASTDIFF", tooltip: "Last Difference (Alt+End)", shortcutDisplay: "Alt+End"),
        Entry(command: .copyToRight, winMergeID: "ID_L2R", tooltip: "Copy to Right (Alt+Right)", shortcutDisplay: "Alt+Right"),
        Entry(command: .copyToLeft, winMergeID: "ID_R2L", tooltip: "Copy to Left (Alt+Left)", shortcutDisplay: "Alt+Left"),
        Entry(
            command: .copyToRightAndAdvance, winMergeID: "ID_L2RNEXT", tooltip: "Copy to Right and Advance (Ctrl+Alt+Right)",
            shortcutDisplay: "Ctrl+Alt+Right"),
        Entry(
            command: .copyToLeftAndAdvance, winMergeID: "ID_R2LNEXT", tooltip: "Copy to Left and Advance (Ctrl+Alt+Left)",
            shortcutDisplay: "Ctrl+Alt+Left"),
        Entry(command: .copyAllToRight, winMergeID: "ID_ALL_RIGHT", tooltip: "Copy All to Right"),
        Entry(command: .copyAllToLeft, winMergeID: "ID_ALL_LEFT", tooltip: "Copy All to Left"),
        Entry(command: .autoMerge, winMergeID: "ID_AUTO_MERGE", tooltip: "Auto Merge (Ctrl+Alt+M)", shortcutDisplay: "Ctrl+Alt+M"),
        Entry(command: .firstComparedFile, winMergeID: "ID_FIRSTFILE", tooltip: "First File"),
        Entry(command: .previousComparedFile, winMergeID: "ID_PREVFILE", tooltip: "Previous File (Ctrl+F7)", shortcutDisplay: "Ctrl+F7"),
        Entry(command: .nextComparedFile, winMergeID: "ID_NEXTFILE", tooltip: "Next File (Ctrl+F8)", shortcutDisplay: "Ctrl+F8"),
        Entry(command: .lastComparedFile, winMergeID: "ID_LASTFILE", tooltip: "Last File"),
        Entry(command: .options, winMergeID: "ID_OPTIONS", tooltip: "Options"),
        Entry(command: .refresh, winMergeID: "ID_REFRESH", tooltip: "Refresh (F5)", shortcutDisplay: "F5")
    ]

    /// Deterministic `Command.allCases` order, matching WinMerge toolbar order.
    public static var orderedCommands: [Command] { entries.map(\.command) }

    public static func entry(for command: Command) -> Entry? {
        entries.first { $0.command == command }
    }

    public static func winMergeID(for command: Command) -> String? {
        entry(for: command)?.winMergeID
    }

    public static func tooltip(for command: Command) -> String? {
        entry(for: command)?.tooltip
    }

    public static func shortcutDisplay(for command: Command) -> String? {
        entry(for: command)?.shortcutDisplay
    }

    /// Commands in `Command.allCases` with no parity row, in canonical order. Empty when complete.
    public static func gaps(in candidates: [Entry] = entries) -> [Command] {
        let present = Set(candidates.map(\.command))
        return Command.allCases.filter { !present.contains($0) }
    }

    /// Validates uniqueness, non-empty text, exact coverage, and WinMerge identity freshness.
    /// Bounded by `Command.allCases.count` rows; deterministic first-violation order.
    public static func validate(_ candidates: [Entry] = entries) throws {
        let known = Set(Command.allCases)
        var seenCommands = Set<Command>()
        var seenIDs = Set<String>()
        for candidate in candidates {
            guard known.contains(candidate.command) else {
                throw ValidationError.unexpectedCommand(candidate.command)
            }
            guard seenCommands.insert(candidate.command).inserted else {
                throw ValidationError.duplicateCommand(candidate.command)
            }
            let trimmedID = candidate.winMergeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                throw ValidationError.emptyWinMergeID(candidate.command)
            }
            guard seenIDs.insert(trimmedID).inserted else {
                throw ValidationError.duplicateWinMergeID(trimmedID)
            }
            guard !candidate.tooltip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyTooltip(candidate.command)
            }
            if let display = candidate.shortcutDisplay {
                guard !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError.emptyShortcutDisplay(candidate.command)
                }
            }
            let expectedID = ToolbarTooltipShortcutAudit.winMergeID(for: candidate.command)
            guard trimmedID == expectedID else {
                throw ValidationError.staleWinMergeID(candidate.command, candidate.winMergeID)
            }
        }
        for command in Command.allCases where !seenCommands.contains(command) {
            throw ValidationError.missingCommand(command)
        }
    }
}
