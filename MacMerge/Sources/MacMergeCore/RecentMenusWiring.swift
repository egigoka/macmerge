import Foundation

/// UI-independent wiring planner for recent workspace/pair menu rows.
///
/// Planning only: projects one immutable owner snapshot into capped rows.
/// History entries come first in pinned-MRU order using their redacted
/// `displayMetadata`; pair entries follow in MRU order with leaf-only labels
/// and folder dedup. Traversal inputs fail closed through
/// `validatedRecentFileURLPath`. Callers own snapshot freshness, menu
/// rendering, security-scope resolution, and restoration execution. This file
/// claims no menus, no restoration, no bookmark resolution, and no UI.
public enum RecentMenusWiring: Sendable {
    /// Caller-owned freshness token. Bump it whenever any snapshot input changes.
    public struct Generation: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }
    }

    /// Bounds for one planning pass. Planning caps rows; titles stay bounded.
    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumRows = 256
        public static let hardMaximumWork = 4 * 1_024 * 1_024
        public static let hardMaximumTitleBytes = 1_024

        public static let `default` = Limits(
            uncheckedMaximumRows: 40,
            uncheckedMaximumWork: 1 * 1_024 * 1_024,
            uncheckedMaximumTitleBytes: 256
        )

        public let maximumRows: Int
        public let maximumWork: Int
        public let maximumTitleBytes: Int

        public init(maximumRows: Int = 40, maximumWork: Int = 1 * 1_024 * 1_024, maximumTitleBytes: Int = 256) throws {
            guard Self.isValid(
                maximumRows: maximumRows,
                maximumWork: maximumWork,
                maximumTitleBytes: maximumTitleBytes
            ) else {
                throw RecentMenusWiringError.invalidLimits
            }
            self.maximumRows = maximumRows
            self.maximumWork = maximumWork
            self.maximumTitleBytes = maximumTitleBytes
        }

        private init(uncheckedMaximumRows maximumRows: Int, uncheckedMaximumWork maximumWork: Int, uncheckedMaximumTitleBytes maximumTitleBytes: Int) {
            self.maximumRows = maximumRows
            self.maximumWork = maximumWork
            self.maximumTitleBytes = maximumTitleBytes
        }

        fileprivate func validate() throws {
            guard Self.isValid(
                maximumRows: maximumRows,
                maximumWork: maximumWork,
                maximumTitleBytes: maximumTitleBytes
            ) else {
                throw RecentMenusWiringError.invalidLimits
            }
        }

        private static func isValid(maximumRows: Int, maximumWork: Int, maximumTitleBytes: Int) -> Bool {
            maximumRows > 0 && maximumRows <= hardMaximumRows
                && maximumWork > 0 && maximumWork <= hardMaximumWork
                && maximumTitleBytes >= 16 && maximumTitleBytes <= hardMaximumTitleBytes
        }
    }

    /// Immutable owner inputs for one deterministic wiring pass.
    public struct Snapshot: Equatable, Sendable {
        public let generation: Generation
        public let history: RecentWorkspaceHistory
        public let pairs: RecentComparisonPairs

        public init(
            generation: Generation,
            history: RecentWorkspaceHistory = RecentWorkspaceHistory(),
            pairs: RecentComparisonPairs = RecentComparisonPairs()
        ) {
            self.generation = generation
            self.history = history
            self.pairs = pairs
        }
    }

    public enum RowKind: String, Equatable, Hashable, Sendable {
        case projectFile
        case folderComparison
        case pairFile
        case pairFolder
        case commonTask
    }

    /// Exact duplicate identity with redacted diagnostics.
    public struct RowID: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let kind: RowKind
        private let primary: String
        private let secondary: String?

        fileprivate init(kind: RowKind, primary: String, secondary: String? = nil) {
            self.kind = kind
            self.primary = primary
            self.secondary = secondary
        }

        public var description: String { "\(kind.rawValue):<redacted>" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["kind": kind.rawValue, "hasSecondary": secondary != nil], displayStyle: .struct)
        }
    }

    /// One planned row. Titles are redacted leaf-only text; URLs live in `intent`.
    public struct Row: Identifiable, Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let id: RowID
        public let kind: RowKind
        public let title: String
        public let subtitle: String
        public let isPinned: Bool
        public let availability: RecentWorkspaceAvailability
        public let intent: RestorationIntent

        fileprivate init(id: RowID, kind: RowKind, title: String, subtitle: String, isPinned: Bool, availability: RecentWorkspaceAvailability, intent: RestorationIntent) {
            self.id = id
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.isPinned = isPinned
            self.availability = availability
            self.intent = intent
        }

        public var isEnabled: Bool { availability == .available }

        public var description: String { "RecentMenusWiring.Row(\(kind.rawValue):<redacted>)" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["kind": kind.rawValue, "isPinned": isPinned, "availability": availability], displayStyle: .struct)
        }
    }

    /// Intent only. The caller checks freshness, resolves security scope, and opens.
    public enum RestorationIntent: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        case openProject(URL)
        case compareFiles(left: URL, right: URL)
        case compareFolders(left: URL, right: URL)
        case performTask(RecentWorkspaceCommonTask)

        /// File-backed intents need caller-side security-scope resolution.
        public var requiresSecurityScopeResolution: Bool {
            switch self {
            case .openProject, .compareFiles, .compareFolders:
                true
            case .performTask:
                false
            }
        }

        public var description: String { "<redacted>" }
        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["requiresSecurityScopeResolution": requiresSecurityScopeResolution], displayStyle: .enum)
        }
    }

    /// Generation-bound row projection. Render only after checking freshness.
    public struct Presentation: Equatable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let generation: Generation
        public let rows: [Row]
        public let omittedRowCount: Int

        fileprivate init(generation: Generation, rows: [Row], omittedRowCount: Int) {
            self.generation = generation
            self.rows = rows
            self.omittedRowCount = omittedRowCount
        }

        public var wasTruncated: Bool { omittedRowCount > 0 }

        public func row(for id: RowID) -> Row? {
            rows.first { $0.id == id }
        }

        public func isCurrent(generation: Generation) -> Bool {
            self.generation == generation
        }

        public func requireCurrent(generation: Generation) throws {
            guard isCurrent(generation: generation) else {
                throw RecentMenusWiringError.staleGeneration(expected: generation, actual: self.generation)
            }
        }

        public var description: String {
            "RecentMenusWiring.Presentation(generation: \(generation.rawValue), rowCount: \(rows.count))"
        }

        public var debugDescription: String { description }
        public var customMirror: Mirror {
            Mirror(self, children: ["generation": generation.rawValue, "rowCount": rows.count, "omittedRowCount": omittedRowCount], displayStyle: .struct)
        }
    }

    /// Projects history entries (pinned-MRU, redacted displayMetadata) then pair
    /// entries (MRU, leaf-only labels, folder dedup) into capped rows.
    public static func plan(
        _ snapshot: Snapshot,
        expecting expectedGeneration: Generation? = nil,
        limits: Limits = .default
    ) throws -> Presentation {
        do {
            try Task.checkCancellation()
            try limits.validate()
            if let expectedGeneration, expectedGeneration != snapshot.generation {
                throw RecentMenusWiringError.staleGeneration(expected: expectedGeneration, actual: snapshot.generation)
            }
            var work = Work(maximum: limits.maximumWork)
            var rows: [Row] = []
            rows.reserveCapacity(min(snapshot.history.count + snapshot.pairs.count, limits.maximumRows))
            var seen: Set<RowID> = []
            var folderKeys: Set<String> = []
            var omittedRowCount = 0

            for entry in snapshot.history {
                try Task.checkCancellation()
                guard let row = try historyRow(entry, limits: limits, work: &work) else {
                    continue
                }
                if let key = folderKey(for: entry) {
                    folderKeys.insert(key)
                }
                try append(row, to: &rows, seen: &seen, omittedRowCount: &omittedRowCount, limits: limits, work: &work)
            }

            for pair in snapshot.pairs {
                try Task.checkCancellation()
                if pair.kind == .folder {
                    let key = folderKey(left: pair.left.absoluteString, right: pair.right.absoluteString)
                    guard !folderKeys.contains(key) else {
                        continue
                    }
                    guard let row = try pairRow(pair, limits: limits, work: &work) else {
                        continue
                    }
                    folderKeys.insert(key)
                    try append(row, to: &rows, seen: &seen, omittedRowCount: &omittedRowCount, limits: limits, work: &work)
                } else {
                    guard let row = try pairRow(pair, limits: limits, work: &work) else {
                        continue
                    }
                    try append(row, to: &rows, seen: &seen, omittedRowCount: &omittedRowCount, limits: limits, work: &work)
                }
            }

            try Task.checkCancellation()
            return Presentation(generation: snapshot.generation, rows: rows, omittedRowCount: omittedRowCount)
        } catch is CancellationError {
            throw RecentMenusWiringError.cancelled
        }
    }

    /// Resolves one row identity to its restoration intent. Rejects unknown rows,
    /// stale presentations, and unavailable rows fail-closed.
    public static func restorationIntent(
        for id: RowID,
        in presentation: Presentation,
        expecting expectedGeneration: Generation? = nil
    ) throws -> RestorationIntent {
        do {
            try Task.checkCancellation()
            if let expectedGeneration, expectedGeneration != presentation.generation {
                throw RecentMenusWiringError.staleGeneration(expected: expectedGeneration, actual: presentation.generation)
            }
            guard let row = presentation.row(for: id) else {
                throw RecentMenusWiringError.unknownRow
            }
            guard row.isEnabled else {
                throw RecentMenusWiringError.unavailableRow
            }
            return row.intent
        } catch is CancellationError {
            throw RecentMenusWiringError.cancelled
        }
    }

    /// Adapts a two-sided folder project, mirroring
    /// `RecentWorkspaceHistory.recordFolderComparison(from:)` predicates.
    public static func adaptFolderProject(_ project: ComparisonProject) throws -> RecentComparisonPair {
        do {
            try Task.checkCancellation()
            guard project.mode == .folder,
                !project.isThreeWay,
                !project.recursive,
                project.filter == nil,
                project.lineDiffOptions == LineDiffOptions(),
                let left = project.side(.left)?.path,
                let right = project.side(.right)?.path,
                project.side(.left)?.readOnly == false,
                project.side(.right)?.readOnly == false
            else {
                throw RecentMenusWiringError.invalidFolderProject
            }
            do {
                return try RecentComparisonPair(left: left, right: right, kind: .folder)
            } catch {
                throw RecentMenusWiringError.invalidURL
            }
        } catch is CancellationError {
            throw RecentMenusWiringError.cancelled
        }
    }

    private static func append(
        _ row: Row,
        to rows: inout [Row],
        seen: inout Set<RowID>,
        omittedRowCount: inout Int,
        limits: Limits,
        work: inout Work
    ) throws {
        try work.charge(1)
        guard seen.insert(row.id).inserted else {
            return
        }
        guard rows.count < limits.maximumRows else {
            omittedRowCount += 1
            return
        }
        rows.append(row)
    }

    private static func historyRow(
        _ entry: RecentWorkspaceHistory.Entry,
        limits: Limits,
        work: inout Work
    ) throws -> Row? {
        switch entry.kind {
        case .projectFile:
            guard let url = entry.projectFileURL else { return nil }
            let canonical = try canonicalURL(url, isDirectory: false, limits: limits, work: &work)
            let metadata = entry.displayMetadata
            let title = try boundedTitle(metadata.title, limits: limits, work: &work)
            return Row(
                id: RowID(kind: .projectFile, primary: canonical.absoluteString),
                kind: .projectFile,
                title: title,
                subtitle: metadata.subtitle,
                isPinned: entry.isPinned,
                availability: entry.availability,
                intent: .openProject(canonical)
            )
        case .folderComparison:
            guard let pair = entry.folderComparison, pair.kind == .folder else { return nil }
            let left = try canonicalURL(pair.left, isDirectory: true, limits: limits, work: &work)
            let right = try canonicalURL(pair.right, isDirectory: true, limits: limits, work: &work)
            let metadata = entry.displayMetadata
            let title = try boundedTitle(metadata.title, limits: limits, work: &work)
            return Row(
                id: RowID(kind: .folderComparison, primary: left.absoluteString, secondary: right.absoluteString),
                kind: .folderComparison,
                title: title,
                subtitle: metadata.subtitle,
                isPinned: entry.isPinned,
                availability: entry.availability,
                intent: .compareFolders(left: left, right: right)
            )
        case .commonTask:
            guard let task = entry.commonTask else { return nil }
            try work.charge(1)
            let metadata = entry.displayMetadata
            let title = try boundedTitle(metadata.title, limits: limits, work: &work)
            return Row(
                id: RowID(kind: .commonTask, primary: task.rawValue),
                kind: .commonTask,
                title: title,
                subtitle: metadata.subtitle,
                isPinned: entry.isPinned,
                availability: entry.availability,
                intent: .performTask(task)
            )
        }
    }

    private static func pairRow(
        _ pair: RecentComparisonPair,
        limits: Limits,
        work: inout Work
    ) throws -> Row? {
        let isDirectory = pair.kind == .folder
        let left = try canonicalURL(pair.left, isDirectory: isDirectory, limits: limits, work: &work)
        let right = try canonicalURL(pair.right, isDirectory: isDirectory, limits: limits, work: &work)
        let title = try pairTitle(left: left, right: right, limits: limits, work: &work)
        switch pair.kind {
        case .file:
            return Row(
                id: RowID(kind: .pairFile, primary: left.absoluteString, secondary: right.absoluteString),
                kind: .pairFile,
                title: title,
                subtitle: "File comparison",
                isPinned: false,
                availability: .available,
                intent: .compareFiles(left: left, right: right)
            )
        case .folder:
            return Row(
                id: RowID(kind: .pairFolder, primary: left.absoluteString, secondary: right.absoluteString),
                kind: .pairFolder,
                title: title,
                subtitle: "Folder comparison",
                isPinned: false,
                availability: .available,
                intent: .compareFolders(left: left, right: right)
            )
        }
    }

    private static func folderKey(for entry: RecentWorkspaceHistory.Entry) -> String? {
        guard entry.kind == .folderComparison, let pair = entry.folderComparison else {
            return nil
        }
        return folderKey(left: pair.left.absoluteString, right: pair.right.absoluteString)
    }

    private static func folderKey(left: String, right: String) -> String {
        "\(left.count):\(left)\n\(right.count):\(right)"
    }

    private static func canonicalURL(
        _ url: URL,
        isDirectory: Bool,
        limits: Limits,
        work: inout Work
    ) throws -> URL {
        let maximumURLBytes = limits.maximumTitleBytes * 64 + 64
        guard try boundedUTF8Count(url.absoluteString, maximum: maximumURLBytes, work: &work) != nil else {
            throw RecentMenusWiringError.invalidURL
        }
        guard let path = validatedRecentFileURLPath(url) else {
            throw RecentMenusWiringError.invalidURL
        }
        guard try boundedUTF8Count(path, maximum: limits.maximumTitleBytes * 64, work: &work) != nil else {
            throw RecentMenusWiringError.invalidURL
        }
        let canonical = URL(fileURLWithPath: path, isDirectory: isDirectory).standardizedFileURL
        guard validatedRecentFileURLPath(canonical) != nil else {
            throw RecentMenusWiringError.invalidURL
        }
        return canonical
    }

    private static func pairTitle(left: URL, right: URL, limits: Limits, work: inout Work) throws -> String {
        let componentLimit = max(4, (limits.maximumTitleBytes - 5) / 2)
        let leftName = try leafTitle(left, maximumBytes: componentLimit, work: &work)
        let rightName = try leafTitle(right, maximumBytes: componentLimit, work: &work)
        return try boundedTitle("\(leftName) and \(rightName)", limits: limits, work: &work)
    }

    private static func leafTitle(_ url: URL, maximumBytes: Int, work: inout Work) throws -> String {
        let leaf = url.lastPathComponent
        return try boundedTitle(leaf.isEmpty ? "Root" : leaf, maximumBytes: maximumBytes, limits: nil, work: &work)
    }

    private static func boundedTitle(_ value: String, limits: Limits, work: inout Work) throws -> String {
        try boundedTitle(value, maximumBytes: limits.maximumTitleBytes, limits: limits, work: &work)
    }

    private static func boundedTitle(_ value: String, maximumBytes: Int, limits: Limits?, work: inout Work) throws -> String {
        var pieces: [String] = []
        pieces.reserveCapacity(min(value.count, maximumBytes))
        var byteCount = 0
        var truncated = false
        for character in value {
            try work.charge(character.utf8.count)
            let piece = character.unicodeScalars.allSatisfy { isSafeDisplayScalar($0.value) } ? String(character) : "?"
            let added = piece.utf8.count
            guard byteCount <= maximumBytes - added else {
                truncated = true
                break
            }
            pieces.append(piece)
            byteCount += added
        }
        if truncated {
            while byteCount > maximumBytes - 3, let removed = pieces.popLast() {
                byteCount -= removed.utf8.count
            }
            pieces.append("...")
            _ = limits
        }
        let result = pieces.joined()
        return result.isEmpty ? "Unnamed" : result
    }

    private static func isSafeDisplayScalar(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator:
            return false
        default:
            return !scalar.properties.isDefaultIgnorableCodePoint
        }
    }

    private static func boundedUTF8Count(_ value: String, maximum: Int, work: inout Work) throws -> Int? {
        var count = 0
        for _ in value.utf8 {
            guard count < maximum else { return nil }
            count += 1
            try work.charge(1)
        }
        return count
    }

    private struct Work {
        let maximum: Int
        private var completed = 0

        init(maximum: Int) {
            self.maximum = maximum
        }

        mutating func charge(_ amount: Int) throws {
            guard amount >= 0, completed <= maximum, amount <= maximum - completed else {
                throw RecentMenusWiringError.workLimitExceeded(maximum: maximum)
            }
            completed += amount
        }
    }
}

public enum RecentMenusWiringError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case staleGeneration(expected: RecentMenusWiring.Generation, actual: RecentMenusWiring.Generation)
    case invalidLimits
    case invalidURL
    case unknownRow
    case unavailableRow
    case invalidFolderProject
    case workLimitExceeded(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Recent menu wiring was cancelled."
        case .staleGeneration:
            "Recent menu wiring generation is stale."
        case .invalidLimits:
            "Recent menu wiring limits are invalid."
        case .invalidURL:
            "Recent menu wiring accepts only absolute local file URLs without credentials."
        case .unknownRow:
            "The recent menu row is no longer in the plan."
        case .unavailableRow:
            "The recent menu row is currently unavailable."
        case .invalidFolderProject:
            "A recent folder wiring project must contain two ordered folder URLs."
        case .workLimitExceeded(let maximum):
            "Recent menu wiring exceeds the \(maximum)-unit work limit."
        }
    }
}
