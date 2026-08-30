import Foundation

public enum RecentWorkspaceHistoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case pathTooLong(maximumBytes: Int)
    case invalidFolderComparison
    case invalidLimits
    case entryLimitExceeded(maximumEntries: Int)
    case workLimitExceeded(maximumWork: Int)
    case persistenceDataTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case malformedPersistence
    case unknownPersistenceKey
    case duplicatePersistenceKey
    case duplicateEntry
    case nonCanonicalPersistence

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Recent workspace history accepts only absolute local file URLs without credentials."
        case .pathTooLong(let maximumBytes):
            "A recent workspace path exceeds the \(maximumBytes)-byte limit."
        case .invalidFolderComparison:
            "A recent folder comparison must contain two ordered folder URLs."
        case .invalidLimits:
            "Recent workspace history limits are invalid."
        case .entryLimitExceeded(let maximumEntries):
            "Recent workspace history exceeds the \(maximumEntries)-entry limit."
        case .workLimitExceeded(let maximumWork):
            "Recent workspace history exceeds the \(maximumWork)-unit work limit."
        case .persistenceDataTooLarge(let maximumBytes):
            "Recent workspace history persistence exceeds the \(maximumBytes)-byte limit."
        case .unsupportedSchemaVersion(let version):
            "Unsupported recent workspace history schema version: \(version)."
        case .malformedPersistence:
            "Recent workspace history persistence is malformed."
        case .unknownPersistenceKey:
            "Recent workspace history persistence contains an unknown key."
        case .duplicatePersistenceKey:
            "Recent workspace history persistence contains a duplicate key."
        case .duplicateEntry:
            "Recent workspace history persistence contains a duplicate entry."
        case .nonCanonicalPersistence:
            "Recent workspace history persistence is not in canonical form."
        }
    }
}

/// Bounded pinned-first MRU history for reopenable projects, folder comparisons, and tasks.
///
/// This type only canonicalizes path syntax. It never reads filesystem metadata, resolves
/// symlinks, or tests whether an item exists. Callers own availability observations.
public struct RecentWorkspaceHistory:
    Equatable, Sendable, RandomAccessCollection, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let currentSchemaVersion = 1
    public static let defaultMaximumEntries = 20
    public static let maximumSupportedEntries = 1_000
    public static let defaultMaximumPathBytes = 16 * 1_024
    public static let maximumSupportedPathBytes = 64 * 1_024
    public static let defaultMaximumWork = 8 * 1_024 * 1_024
    public static let maximumSupportedWork = 16 * 1_024 * 1_024
    public static let maximumEncodedBytes = 1 * 1_024 * 1_024

    public typealias Index = Int

    public struct Limits: Equatable, Sendable {
        public static let `default` = Limits(
            uncheckedMaximumEntries: RecentWorkspaceHistory.defaultMaximumEntries,
            maximumPathBytes: RecentWorkspaceHistory.defaultMaximumPathBytes,
            maximumWork: RecentWorkspaceHistory.defaultMaximumWork
        )

        public let maximumEntries: Int
        public let maximumPathBytes: Int
        public let maximumWork: Int

        public init(
            maximumEntries: Int = RecentWorkspaceHistory.defaultMaximumEntries,
            maximumPathBytes: Int = RecentWorkspaceHistory.defaultMaximumPathBytes,
            maximumWork: Int = RecentWorkspaceHistory.defaultMaximumWork
        ) throws {
            guard
                Self.isValid(
                    maximumEntries: maximumEntries,
                    maximumPathBytes: maximumPathBytes,
                    maximumWork: maximumWork
                )
            else {
                throw RecentWorkspaceHistoryError.invalidLimits
            }
            self.maximumEntries = maximumEntries
            self.maximumPathBytes = maximumPathBytes
            self.maximumWork = maximumWork
        }

        private init(
            uncheckedMaximumEntries maximumEntries: Int,
            maximumPathBytes: Int,
            maximumWork: Int
        ) {
            self.maximumEntries = maximumEntries
            self.maximumPathBytes = maximumPathBytes
            self.maximumWork = maximumWork
        }

        fileprivate init(validating wire: WireLimits) throws {
            guard
                Self.isValid(
                    maximumEntries: wire.maximumEntries,
                    maximumPathBytes: wire.maximumPathBytes,
                    maximumWork: wire.maximumWork
                )
            else {
                throw RecentWorkspaceHistoryError.invalidLimits
            }
            maximumEntries = wire.maximumEntries
            maximumPathBytes = wire.maximumPathBytes
            maximumWork = wire.maximumWork
        }

        private static func isValid(
            maximumEntries: Int,
            maximumPathBytes: Int,
            maximumWork: Int
        ) -> Bool {
            maximumEntries > 0
                && maximumEntries <= RecentWorkspaceHistory.maximumSupportedEntries
                && maximumPathBytes > 0
                && maximumPathBytes <= RecentWorkspaceHistory.maximumSupportedPathBytes
                && maximumWork > 0
                && maximumWork <= RecentWorkspaceHistory.maximumSupportedWork
        }
    }

    public enum Kind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case projectFile
        case folderComparison
        case commonTask
    }

    /// Caller-supplied observation. History never infers this value from disk.
    public enum Availability: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case available
        case missing
        case stale
    }

    public typealias Marker = Availability

    public enum CommonTask: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case compareFiles
        case compareFolders
        case compareClipboard
        case openProject

        public var displayMetadata: DisplayMetadata {
            switch self {
            case .compareFiles:
                DisplayMetadata(title: "Compare Files", subtitle: "Common task")
            case .compareFolders:
                DisplayMetadata(title: "Compare Folders", subtitle: "Common task")
            case .compareClipboard:
                DisplayMetadata(title: "Compare Clipboard", subtitle: "Common task")
            case .openProject:
                DisplayMetadata(title: "Open Project", subtitle: "Common task")
            }
        }
    }

    /// Exact canonical identity with a redacted deterministic description for diagnostics.
    public struct Identity:
        Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
        CustomDebugStringConvertible
    {
        fileprivate let kind: Kind
        fileprivate let primary: String
        fileprivate let secondary: String?

        public var description: String {
            "\(kind.rawValue):<redacted>"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "kind": kind.rawValue,
                    "hasSecondary": secondary != nil
                ],
                displayStyle: .struct
            )
        }

        fileprivate var workCost: Int {
            primary.utf8.count + (secondary?.utf8.count ?? 0) + 1
        }

    }

    /// Path-safe UI text. It intentionally omits parent paths and URL authority components.
    public struct DisplayMetadata: Equatable, Hashable, Sendable {
        public let title: String
        public let subtitle: String

        public init(title: String, subtitle: String) {
            self.title = title
            self.subtitle = subtitle
        }
    }

    public struct Entry:
        Identifiable, Equatable, Hashable, Sendable, CustomReflectable,
        CustomStringConvertible, CustomDebugStringConvertible
    {
        public let id: Identity
        public let kind: Kind
        public let isPinned: Bool
        public let availability: Availability
        public let projectFileURL: URL?
        public let folderComparison: RecentComparisonPair?
        public let commonTask: CommonTask?

        public var description: String {
            "\(kind.rawValue):<redacted>"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "kind": kind.rawValue,
                    "isPinned": isPinned,
                    "availability": availability.rawValue,
                    "value": "<redacted>"
                ],
                displayStyle: .struct
            )
        }

        public var displayMetadata: DisplayMetadata {
            switch kind {
            case .projectFile:
                return DisplayMetadata(
                    title: Self.safeName(projectFileURL?.lastPathComponent),
                    subtitle: "Project file"
                )
            case .folderComparison:
                let left = Self.safeName(folderComparison?.left.lastPathComponent)
                let right = Self.safeName(folderComparison?.right.lastPathComponent)
                return DisplayMetadata(title: "\(left) and \(right)", subtitle: "Folder comparison")
            case .commonTask:
                return commonTask?.displayMetadata
                    ?? DisplayMetadata(title: "Task", subtitle: "Common task")
            }
        }

        fileprivate init(
            projectFileURL: URL,
            isPinned: Bool,
            availability: Availability
        ) {
            let value = projectFileURL.absoluteString
            id = Identity(kind: .projectFile, primary: value, secondary: nil)
            kind = .projectFile
            self.isPinned = isPinned
            self.availability = availability
            self.projectFileURL = projectFileURL
            folderComparison = nil
            commonTask = nil
        }

        fileprivate init(
            folderComparison: RecentComparisonPair,
            isPinned: Bool,
            availability: Availability
        ) {
            id = Identity(
                kind: .folderComparison,
                primary: folderComparison.left.absoluteString,
                secondary: folderComparison.right.absoluteString
            )
            kind = .folderComparison
            self.isPinned = isPinned
            self.availability = availability
            projectFileURL = nil
            self.folderComparison = folderComparison
            commonTask = nil
        }

        fileprivate init(
            commonTask: CommonTask,
            isPinned: Bool,
            availability: Availability
        ) {
            id = Identity(kind: .commonTask, primary: commonTask.rawValue, secondary: nil)
            kind = .commonTask
            self.isPinned = isPinned
            self.availability = availability
            projectFileURL = nil
            folderComparison = nil
            self.commonTask = commonTask
        }

        fileprivate func replacing(
            isPinned: Bool? = nil,
            availability: Availability? = nil
        ) -> Entry {
            switch kind {
            case .projectFile:
                return Entry(
                    projectFileURL: projectFileURL!,
                    isPinned: isPinned ?? self.isPinned,
                    availability: availability ?? self.availability
                )
            case .folderComparison:
                return Entry(
                    folderComparison: folderComparison!,
                    isPinned: isPinned ?? self.isPinned,
                    availability: availability ?? self.availability
                )
            case .commonTask:
                return Entry(
                    commonTask: commonTask!,
                    isPinned: isPinned ?? self.isPinned,
                    availability: availability ?? self.availability
                )
            }
        }

        private static func safeName(_ value: String?) -> String {
            guard let value, !value.isEmpty else { return "Root" }
            var result = ""
            var byteCount = 0
            for character in value {
                let safeCharacter =
                    character.unicodeScalars.allSatisfy {
                        Self.isSafeDisplayScalar($0.value)
                    } ? String(character) : "?"
                let added = safeCharacter.utf8.count
                guard byteCount + added <= 256 else {
                    result += "..."
                    break
                }
                result += safeCharacter
                byteCount += added
            }
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
    }

    public let limits: Limits
    public private(set) var entries: [Entry]

    public var description: String {
        "RecentWorkspaceHistory(entryCount: \(entries.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "limits": limits,
                "entryCount": entries.count,
                "entries": "<redacted>"
            ],
            displayStyle: .struct
        )
    }

    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }
    public subscript(position: Int) -> Entry { entries[position] }

    public var projectFiles: [Entry] { entries.filter { $0.kind == .projectFile } }
    public var folderComparisons: [Entry] { entries.filter { $0.kind == .folderComparison } }
    public var commonTasks: [Entry] { entries.filter { $0.kind == .commonTask } }

    public init(limits: Limits = .default) {
        self.limits = limits
        entries = []
    }

    @discardableResult
    public mutating func recordProjectFile(
        _ fileURL: URL,
        pinned: Bool = false,
        availability: Availability = .available
    ) throws -> Bool {
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        let canonicalURL = try Self.canonicalURL(
            fileURL,
            isDirectory: false,
            maximumPathBytes: limits.maximumPathBytes,
            budget: &budget
        )
        return try record(
            Entry(
                projectFileURL: canonicalURL,
                isPinned: pinned,
                availability: availability
            ),
            budget: &budget
        )
    }

    @discardableResult
    public mutating func recordFolderComparison(
        left: URL,
        right: URL,
        pinned: Bool = false,
        availability: Availability = .available
    ) throws -> Bool {
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        let canonicalLeft = try Self.canonicalURL(
            left,
            isDirectory: true,
            maximumPathBytes: limits.maximumPathBytes,
            budget: &budget
        )
        let canonicalRight = try Self.canonicalURL(
            right,
            isDirectory: true,
            maximumPathBytes: limits.maximumPathBytes,
            budget: &budget
        )
        let pair = try RecentComparisonPair(
            left: canonicalLeft,
            right: canonicalRight,
            kind: .folder
        )
        return try record(
            Entry(
                folderComparison: pair,
                isPinned: pinned,
                availability: availability
            ),
            budget: &budget
        )
    }

    @discardableResult
    public mutating func recordFolderComparison(
        _ pair: RecentComparisonPair,
        pinned: Bool = false,
        availability: Availability = .available
    ) throws -> Bool {
        guard pair.kind == .folder else {
            throw RecentWorkspaceHistoryError.invalidFolderComparison
        }
        return try recordFolderComparison(
            left: pair.left,
            right: pair.right,
            pinned: pinned,
            availability: availability
        )
    }

    /// Adapts a two-sided folder project without loading or inspecting either folder.
    @discardableResult
    public mutating func recordFolderComparison(
        from project: ComparisonProject,
        pinned: Bool = false,
        availability: Availability = .available
    ) throws -> Bool {
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
            throw RecentWorkspaceHistoryError.invalidFolderComparison
        }
        return try recordFolderComparison(
            left: left,
            right: right,
            pinned: pinned,
            availability: availability
        )
    }

    @discardableResult
    public mutating func recordCommonTask(
        _ task: CommonTask,
        pinned: Bool = false,
        availability: Availability = .available
    ) throws -> Bool {
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        try budget.charge(1)
        return try record(
            Entry(commonTask: task, isPinned: pinned, availability: availability),
            budget: &budget
        )
    }

    @discardableResult
    public mutating func setPinned(_ pinned: Bool, for identity: Identity) throws -> Bool {
        try Task.checkCancellation()
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        guard let index = try index(of: identity, budget: &budget) else { return false }
        let existing = entries[index]
        guard existing.isPinned != pinned else { return false }
        let firstUnpinned = pinned ? 0 : try firstUnpinnedIndex(budget: &budget)
        let insertionIndex =
            pinned
            ? 0
            : firstUnpinned - (index < firstUnpinned ? 1 : 0)
        entries.remove(at: index)
        entries.insert(existing.replacing(isPinned: pinned), at: insertionIndex)
        do {
            try validatePersistence(budget: &budget)
        } catch {
            entries.remove(at: insertionIndex)
            entries.insert(existing, at: index)
            throw error
        }
        return true
    }

    @discardableResult
    public mutating func mark(
        _ availability: Availability,
        for identity: Identity
    ) throws -> Bool {
        try Task.checkCancellation()
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        guard let index = try index(of: identity, budget: &budget) else { return false }
        guard entries[index].availability != availability else { return false }
        let existing = entries[index]
        entries[index] = existing.replacing(availability: availability)
        do {
            try validatePersistence(budget: &budget)
        } catch {
            entries[index] = existing
            throw error
        }
        return true
    }

    @discardableResult
    public mutating func remove(_ identity: Identity) throws -> Bool {
        try Task.checkCancellation()
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        guard let index = try index(of: identity, budget: &budget) else { return false }
        entries.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func removeProjectFile(_ fileURL: URL) throws -> Bool {
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        let canonicalURL = try Self.canonicalURL(
            fileURL,
            isDirectory: false,
            maximumPathBytes: limits.maximumPathBytes,
            budget: &budget
        )
        return try remove(
            Identity(kind: .projectFile, primary: canonicalURL.absoluteString, secondary: nil),
            budget: &budget
        )
    }

    @discardableResult
    public mutating func removeFolderComparison(left: URL, right: URL) throws -> Bool {
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        let canonicalLeft = try Self.canonicalURL(
            left,
            isDirectory: true,
            maximumPathBytes: limits.maximumPathBytes,
            budget: &budget
        )
        let canonicalRight = try Self.canonicalURL(
            right,
            isDirectory: true,
            maximumPathBytes: limits.maximumPathBytes,
            budget: &budget
        )
        return try remove(
            Identity(
                kind: .folderComparison,
                primary: canonicalLeft.absoluteString,
                secondary: canonicalRight.absoluteString
            ),
            budget: &budget
        )
    }

    @discardableResult
    public mutating func removeCommonTask(_ task: CommonTask) throws -> Bool {
        try remove(Identity(kind: .commonTask, primary: task.rawValue, secondary: nil))
    }

    public mutating func clear() throws {
        try Task.checkCancellation()
        entries.removeAll(keepingCapacity: true)
    }

    @discardableResult
    public mutating func clear(_ kind: Kind) throws -> Int {
        try Task.checkCancellation()
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        var retained: [Entry] = []
        retained.reserveCapacity(entries.count)
        var removedCount = 0
        for entry in entries {
            try budget.charge(1)
            if entry.kind == kind {
                removedCount += 1
            } else {
                retained.append(entry)
            }
        }
        entries = retained
        return removedCount
    }

    /// Compact sorted-key JSON. Equal histories always produce equal bytes.
    public func encodedData() throws -> Data {
        try Task.checkCancellation()
        var writer = RecentWorkspaceCanonicalWriter(
            maximumBytes: Self.maximumEncodedBytes
        )
        var budget = WorkBudget(maximumWork: limits.maximumWork)
        try chargePersistencePathWork(budget: &budget)
        return try writer.encode(self, budget: &budget)
    }

    /// Strictly decodes only this schema's canonical representation.
    public static func decode(from data: Data) throws -> RecentWorkspaceHistory {
        guard data.count <= Self.maximumEncodedBytes else {
            throw RecentWorkspaceHistoryError.persistenceDataTooLarge(
                maximumBytes: Self.maximumEncodedBytes
            )
        }
        do {
            try Task.checkCancellation()
            let schemaVersion = try data.withUnsafeBytes { rawBuffer in
                var scanner = RecentWorkspaceSchemaVersionScanner(
                    bytes: rawBuffer.bindMemory(to: UInt8.self)
                )
                return try scanner.schemaVersion()
            }
            guard schemaVersion == Self.currentSchemaVersion else {
                throw RecentWorkspaceHistoryError.unsupportedSchemaVersion(schemaVersion)
            }
            try data.withUnsafeBytes { rawBuffer in
                var scanner = RecentWorkspaceJSONScanner(
                    bytes: rawBuffer.bindMemory(to: UInt8.self)
                )
                try scanner.validate()
            }
            let decoder = JSONDecoder()
            let wire = try decoder.decode(WireHistory.self, from: data)
            let limits = try Limits(validating: wire.limits)

            var budget = WorkBudget(maximumWork: limits.maximumWork)
            var decodedEntries: [Entry] = []
            decodedEntries.reserveCapacity(wire.entries.count)
            var identities: Set<Identity> = []
            var encounteredUnpinned = false
            for wireEntry in wire.entries {
                try budget.charge(1)
                let entry = try wireEntry.entry(limits: limits, budget: &budget)
                guard identities.insert(entry.id).inserted else {
                    throw RecentWorkspaceHistoryError.duplicateEntry
                }
                if entry.isPinned {
                    guard !encounteredUnpinned else {
                        throw RecentWorkspaceHistoryError.nonCanonicalPersistence
                    }
                } else {
                    encounteredUnpinned = true
                }
                decodedEntries.append(entry)
            }

            var result = RecentWorkspaceHistory(limits: limits)
            result.entries = decodedEntries
            var writer = RecentWorkspaceCanonicalWriter(
                maximumBytes: Self.maximumEncodedBytes
            )
            guard try writer.encode(result, budget: &budget) == data else {
                throw RecentWorkspaceHistoryError.nonCanonicalPersistence
            }
            return result
        } catch let error as RecentWorkspaceHistoryError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RecentWorkspaceHistoryError.malformedPersistence
        }
    }

    private mutating func record(_ entry: Entry, budget: inout WorkBudget) throws -> Bool {
        try Task.checkCancellation()
        let originalEntries = entries
        let existingIndex = try index(of: entry.id, budget: &budget)
        let effectiveEntry: Entry
        if let existingIndex, entries[existingIndex].isPinned, !entry.isPinned {
            effectiveEntry = entry.replacing(isPinned: true)
        } else {
            effectiveEntry = entry
        }
        let firstUnpinned = try firstUnpinnedIndex(budget: &budget)
        if let existingIndex {
            let existing = entries[existingIndex]
            let desiredIndex = effectiveEntry.isPinned ? 0 : firstUnpinned
            if existing.isPinned == effectiveEntry.isPinned,
                existing.availability == effectiveEntry.availability,
                existingIndex == desiredIndex
            {
                return false
            }
            let insertionIndex =
                effectiveEntry.isPinned
                ? 0
                : firstUnpinned - (existingIndex < firstUnpinned ? 1 : 0)
            entries.remove(at: existingIndex)
            entries.insert(effectiveEntry, at: insertionIndex)
        } else if !effectiveEntry.isPinned,
            firstUnpinned == entries.endIndex,
            entries.count == limits.maximumEntries
        {
            return false
        } else {
            entries.insert(effectiveEntry, at: effectiveEntry.isPinned ? 0 : firstUnpinned)
        }
        if entries.count > limits.maximumEntries {
            entries.removeLast(entries.count - limits.maximumEntries)
        }
        do {
            try validatePersistence(budget: &budget)
        } catch {
            entries = originalEntries
            throw error
        }
        return true
    }

    private func validatePersistence(budget: inout WorkBudget) throws {
        var writer = RecentWorkspaceCanonicalWriter(
            maximumBytes: Self.maximumEncodedBytes
        )
        try chargePersistencePathWork(budget: &budget)
        _ = try writer.encode(self, budget: &budget)
    }

    private func chargePersistencePathWork(budget: inout WorkBudget) throws {
        for entry in entries {
            try budget.charge(1)
            switch entry.kind {
            case .projectFile:
                try budget.charge(entry.projectFileURL!.path.utf8.count)
            case .folderComparison:
                try budget.charge(entry.folderComparison!.left.path.utf8.count)
                try budget.charge(entry.folderComparison!.right.path.utf8.count)
            case .commonTask:
                try budget.charge(1)
            }
        }
    }

    private func firstUnpinnedIndex(budget: inout WorkBudget) throws -> Int {
        for index in entries.indices {
            try budget.charge(1)
            if !entries[index].isPinned { return index }
        }
        return entries.endIndex
    }

    private func index(of identity: Identity, budget: inout WorkBudget) throws -> Int? {
        for index in entries.indices {
            try budget.charge(entries[index].id.workCost)
            if entries[index].id == identity { return index }
        }
        return nil
    }

    private mutating func remove(
        _ identity: Identity,
        budget: inout WorkBudget
    ) throws -> Bool {
        guard let index = try index(of: identity, budget: &budget) else { return false }
        entries.remove(at: index)
        return true
    }

    fileprivate static func canonicalURL(
        _ url: URL,
        isDirectory: Bool,
        maximumPathBytes: Int,
        budget: inout WorkBudget
    ) throws -> URL {
        try Task.checkCancellation()
        let maximumURLBytes = maximumPathBytes * 3 + 64
        guard
            try boundedUTF8Count(
                url.absoluteString,
                maximum: maximumURLBytes,
                budget: &budget
            ) <= maximumURLBytes
        else {
            throw RecentWorkspaceHistoryError.pathTooLong(maximumBytes: maximumPathBytes)
        }
        guard let path = validatedRecentFileURLPath(url) else {
            throw RecentWorkspaceHistoryError.invalidURL
        }
        guard
            try boundedUTF8Count(
                path,
                maximum: maximumPathBytes,
                budget: &budget
            ) <= maximumPathBytes
        else {
            throw RecentWorkspaceHistoryError.pathTooLong(maximumBytes: maximumPathBytes)
        }
        let canonical = URL(
            fileURLWithPath: path,
            isDirectory: isDirectory
        ).standardizedFileURL
        guard
            try boundedUTF8Count(
                canonical.path,
                maximum: maximumPathBytes,
                budget: &budget
            ) <= maximumPathBytes
        else {
            throw RecentWorkspaceHistoryError.pathTooLong(maximumBytes: maximumPathBytes)
        }
        return canonical
    }

    private static func boundedUTF8Count(
        _ value: String,
        maximum: Int,
        budget: inout WorkBudget
    ) throws -> Int {
        var count = 0
        for _ in value.utf8 {
            guard count < maximum else { return maximum + 1 }
            count += 1
            try budget.charge(1)
        }
        return count
    }
}

public typealias RecentWorkspaceEntry = RecentWorkspaceHistory.Entry
public typealias RecentWorkspaceIdentity = RecentWorkspaceHistory.Identity
public typealias RecentWorkspaceCommonTask = RecentWorkspaceHistory.CommonTask
public typealias RecentWorkspaceAvailability = RecentWorkspaceHistory.Availability
public typealias RecentWorkspaceDisplayMetadata = RecentWorkspaceHistory.DisplayMetadata

private struct WorkBudget {
    let maximumWork: Int
    private var completedWork = 0

    init(maximumWork: Int) {
        self.maximumWork = maximumWork
    }

    mutating func charge(_ amount: Int) throws {
        guard amount >= 0,
            completedWork <= maximumWork,
            amount <= maximumWork - completedWork
        else {
            throw RecentWorkspaceHistoryError.workLimitExceeded(maximumWork: maximumWork)
        }
        completedWork += amount
        try Task.checkCancellation()
    }
}

private struct RecentWorkspaceCanonicalWriter {
    private let maximumBytes: Int
    private var data: Data

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        data = Data()
        data.reserveCapacity(Swift.min(maximumBytes, 4 * 1_024))
    }

    mutating func encode(
        _ history: RecentWorkspaceHistory,
        budget: inout WorkBudget
    ) throws -> Data {
        try append("{\"entries\":[", budget: &budget)
        for (index, entry) in history.entries.enumerated() {
            if index > 0 { try append(",", budget: &budget) }
            try encode(entry, budget: &budget)
        }
        try append(
            "],\"limits\":{\"maximumEntries\":\(history.limits.maximumEntries),"
                + "\"maximumPathBytes\":\(history.limits.maximumPathBytes),"
                + "\"maximumWork\":\(history.limits.maximumWork)},"
                + "\"schemaVersion\":\(RecentWorkspaceHistory.currentSchemaVersion)}",
            budget: &budget
        )
        try Task.checkCancellation()
        return data
    }

    private mutating func encode(
        _ entry: RecentWorkspaceHistory.Entry,
        budget: inout WorkBudget
    ) throws {
        try append("{\"availability\":", budget: &budget)
        try appendJSONString(entry.availability.rawValue, budget: &budget)
        try append(",\"kind\":", budget: &budget)
        try appendJSONString(entry.kind.rawValue, budget: &budget)
        switch entry.kind {
        case .projectFile:
            try append(",\"path\":", budget: &budget)
            try appendJSONString(entry.projectFileURL!.absoluteString, budget: &budget)
            try append(",\"pinned\":", budget: &budget)
            try appendBoolean(entry.isPinned, budget: &budget)
        case .folderComparison:
            try append(",\"left\":", budget: &budget)
            try appendJSONString(entry.folderComparison!.left.absoluteString, budget: &budget)
            try append(",\"pinned\":", budget: &budget)
            try appendBoolean(entry.isPinned, budget: &budget)
            try append(",\"right\":", budget: &budget)
            try appendJSONString(entry.folderComparison!.right.absoluteString, budget: &budget)
        case .commonTask:
            try append(",\"pinned\":", budget: &budget)
            try appendBoolean(entry.isPinned, budget: &budget)
            try append(",\"task\":", budget: &budget)
            try appendJSONString(entry.commonTask!.rawValue, budget: &budget)
        }
        try append("}", budget: &budget)
    }

    private mutating func appendJSONString(
        _ value: String,
        budget: inout WorkBudget
    ) throws {
        try appendByte(0x22, budget: &budget)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08:
                try append("\\b", budget: &budget)
            case 0x09:
                try append("\\t", budget: &budget)
            case 0x0A:
                try append("\\n", budget: &budget)
            case 0x0C:
                try append("\\f", budget: &budget)
            case 0x0D:
                try append("\\r", budget: &budget)
            case 0x22:
                try append("\\\"", budget: &budget)
            case 0x5C:
                try append("\\\\", budget: &budget)
            case 0x00...0x1F:
                let hex = String(scalar.value, radix: 16, uppercase: false)
                try append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex, budget: &budget)
            default:
                try append(String(scalar), budget: &budget)
            }
        }
        try appendByte(0x22, budget: &budget)
    }

    private mutating func appendBoolean(
        _ value: Bool,
        budget: inout WorkBudget
    ) throws {
        try append(value ? "true" : "false", budget: &budget)
    }

    private mutating func append(_ value: String, budget: inout WorkBudget) throws {
        for byte in value.utf8 {
            try appendByte(byte, budget: &budget)
        }
    }

    private mutating func appendByte(_ byte: UInt8, budget: inout WorkBudget) throws {
        guard data.count < maximumBytes else {
            throw RecentWorkspaceHistoryError.persistenceDataTooLarge(maximumBytes: maximumBytes)
        }
        try budget.charge(1)
        data.append(byte)
    }
}

private struct WireHistory: Codable {
    let schemaVersion: Int
    let limits: WireLimits
    let entries: [WireEntry]

    init(schemaVersion: Int, limits: WireLimits, entries: [WireEntry]) {
        self.schemaVersion = schemaVersion
        self.limits = limits
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RecentWorkspaceCodingKey.self)
        try requireExactKeys(container, expected: ["schemaVersion", "limits", "entries"])
        schemaVersion = try container.decode(Int.self, forKey: .init("schemaVersion"))
        limits = try container.decode(WireLimits.self, forKey: .init("limits"))
        let maximumEntries = try RecentWorkspaceHistory.Limits(validating: limits).maximumEntries
        var entryContainer = try container.nestedUnkeyedContainer(forKey: .init("entries"))
        guard let entryCount = entryContainer.count else {
            throw RecentWorkspaceHistoryError.malformedPersistence
        }
        guard entryCount <= maximumEntries else {
            throw RecentWorkspaceHistoryError.entryLimitExceeded(maximumEntries: maximumEntries)
        }
        var decodedEntries: [WireEntry] = []
        decodedEntries.reserveCapacity(entryCount)
        while !entryContainer.isAtEnd {
            decodedEntries.append(try entryContainer.decode(WireEntry.self))
        }
        entries = decodedEntries
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RecentWorkspaceCodingKey.self)
        try container.encode(schemaVersion, forKey: .init("schemaVersion"))
        try container.encode(limits, forKey: .init("limits"))
        try container.encode(entries, forKey: .init("entries"))
    }
}

private struct WireLimits: Codable {
    let maximumEntries: Int
    let maximumPathBytes: Int
    let maximumWork: Int

    init(_ limits: RecentWorkspaceHistory.Limits) {
        maximumEntries = limits.maximumEntries
        maximumPathBytes = limits.maximumPathBytes
        maximumWork = limits.maximumWork
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RecentWorkspaceCodingKey.self)
        try requireExactKeys(
            container,
            expected: ["maximumEntries", "maximumPathBytes", "maximumWork"]
        )
        maximumEntries = try container.decode(Int.self, forKey: .init("maximumEntries"))
        maximumPathBytes = try container.decode(Int.self, forKey: .init("maximumPathBytes"))
        maximumWork = try container.decode(Int.self, forKey: .init("maximumWork"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RecentWorkspaceCodingKey.self)
        try container.encode(maximumEntries, forKey: .init("maximumEntries"))
        try container.encode(maximumPathBytes, forKey: .init("maximumPathBytes"))
        try container.encode(maximumWork, forKey: .init("maximumWork"))
    }
}

private struct WireEntry: Codable {
    let kind: RecentWorkspaceHistory.Kind
    let pinned: Bool
    let availability: RecentWorkspaceHistory.Availability
    let path: String?
    let left: String?
    let right: String?
    let task: RecentWorkspaceHistory.CommonTask?

    init(
        entry: RecentWorkspaceHistory.Entry,
        limits: RecentWorkspaceHistory.Limits,
        budget: inout WorkBudget
    ) throws {
        kind = entry.kind
        pinned = entry.isPinned
        availability = entry.availability
        switch entry.kind {
        case .projectFile:
            let value = entry.projectFileURL!.absoluteString
            try budget.charge(value.utf8.count)
            guard entry.projectFileURL!.path.utf8.count <= limits.maximumPathBytes else {
                throw RecentWorkspaceHistoryError.pathTooLong(
                    maximumBytes: limits.maximumPathBytes
                )
            }
            path = value
            left = nil
            right = nil
            task = nil
        case .folderComparison:
            let pair = entry.folderComparison!
            try budget.charge(pair.left.absoluteString.utf8.count)
            try budget.charge(pair.right.absoluteString.utf8.count)
            guard pair.left.path.utf8.count <= limits.maximumPathBytes,
                pair.right.path.utf8.count <= limits.maximumPathBytes
            else {
                throw RecentWorkspaceHistoryError.pathTooLong(
                    maximumBytes: limits.maximumPathBytes
                )
            }
            path = nil
            left = pair.left.absoluteString
            right = pair.right.absoluteString
            task = nil
        case .commonTask:
            path = nil
            left = nil
            right = nil
            task = entry.commonTask!
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RecentWorkspaceCodingKey.self)
        kind = try container.decode(RecentWorkspaceHistory.Kind.self, forKey: .init("kind"))
        let commonKeys: Set<String> = ["kind", "pinned", "availability"]
        switch kind {
        case .projectFile:
            try requireExactKeys(container, expected: commonKeys.union(["path"]))
            path = try container.decode(String.self, forKey: .init("path"))
            left = nil
            right = nil
            task = nil
        case .folderComparison:
            try requireExactKeys(container, expected: commonKeys.union(["left", "right"]))
            path = nil
            left = try container.decode(String.self, forKey: .init("left"))
            right = try container.decode(String.self, forKey: .init("right"))
            task = nil
        case .commonTask:
            try requireExactKeys(container, expected: commonKeys.union(["task"]))
            path = nil
            left = nil
            right = nil
            task = try container.decode(
                RecentWorkspaceHistory.CommonTask.self,
                forKey: .init("task")
            )
        }
        pinned = try container.decode(Bool.self, forKey: .init("pinned"))
        availability = try container.decode(
            RecentWorkspaceHistory.Availability.self,
            forKey: .init("availability")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RecentWorkspaceCodingKey.self)
        try container.encode(kind, forKey: .init("kind"))
        try container.encode(pinned, forKey: .init("pinned"))
        try container.encode(availability, forKey: .init("availability"))
        switch kind {
        case .projectFile:
            try container.encode(path!, forKey: .init("path"))
        case .folderComparison:
            try container.encode(left!, forKey: .init("left"))
            try container.encode(right!, forKey: .init("right"))
        case .commonTask:
            try container.encode(task!, forKey: .init("task"))
        }
    }

    func entry(
        limits: RecentWorkspaceHistory.Limits,
        budget: inout WorkBudget
    ) throws -> RecentWorkspaceHistory.Entry {
        switch kind {
        case .projectFile:
            guard let path, let url = URL(string: path) else {
                throw RecentWorkspaceHistoryError.malformedPersistence
            }
            let canonical = try canonicalURL(
                url,
                isDirectory: false,
                limits: limits,
                budget: &budget
            )
            guard canonical.absoluteString == path else {
                throw RecentWorkspaceHistoryError.nonCanonicalPersistence
            }
            return RecentWorkspaceHistory.Entry(
                projectFileURL: canonical,
                isPinned: pinned,
                availability: availability
            )
        case .folderComparison:
            guard let left, let right,
                let leftURL = URL(string: left),
                let rightURL = URL(string: right)
            else {
                throw RecentWorkspaceHistoryError.malformedPersistence
            }
            let canonicalLeft = try canonicalURL(
                leftURL,
                isDirectory: true,
                limits: limits,
                budget: &budget
            )
            let canonicalRight = try canonicalURL(
                rightURL,
                isDirectory: true,
                limits: limits,
                budget: &budget
            )
            guard canonicalLeft.absoluteString == left,
                canonicalRight.absoluteString == right
            else {
                throw RecentWorkspaceHistoryError.nonCanonicalPersistence
            }
            let pair = try RecentComparisonPair(
                left: canonicalLeft,
                right: canonicalRight,
                kind: .folder
            )
            return RecentWorkspaceHistory.Entry(
                folderComparison: pair,
                isPinned: pinned,
                availability: availability
            )
        case .commonTask:
            guard let task else { throw RecentWorkspaceHistoryError.malformedPersistence }
            try budget.charge(1)
            return RecentWorkspaceHistory.Entry(
                commonTask: task,
                isPinned: pinned,
                availability: availability
            )
        }
    }

    private func canonicalURL(
        _ url: URL,
        isDirectory: Bool,
        limits: RecentWorkspaceHistory.Limits,
        budget: inout WorkBudget
    ) throws -> URL {
        try RecentWorkspaceHistory.canonicalURL(
            url,
            isDirectory: isDirectory,
            maximumPathBytes: limits.maximumPathBytes,
            budget: &budget
        )
    }
}

private struct RecentWorkspaceCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

private func requireExactKeys<Value>(
    _ container: KeyedDecodingContainer<Value>,
    expected: Set<String>
) throws where Value: CodingKey {
    let actual = Set(container.allKeys.map(\.stringValue))
    guard actual.subtracting(expected).isEmpty else {
        throw RecentWorkspaceHistoryError.unknownPersistenceKey
    }
    guard actual == expected else {
        throw RecentWorkspaceHistoryError.malformedPersistence
    }
}

private struct RecentWorkspaceSchemaVersionScanner {
    private static let maximumDepth = 64
    private static let cancellationInterval = 4 * 1_024

    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0
    private var lastCancellationIndex = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func schemaVersion() throws -> Int {
        try checkCancellation(force: true)
        try skipWhitespace()
        try consume(0x7B)
        try skipWhitespace()
        var result: Int?
        if !consumeIfPresent(0x7D) {
            while true {
                try checkCancellation(force: false)
                let key = try parseString(capture: true)
                try skipWhitespace()
                try consume(0x3A)
                try skipWhitespace()
                if key == "schemaVersion" {
                    guard result == nil else {
                        throw RecentWorkspaceHistoryError.duplicatePersistenceKey
                    }
                    result = try parseInteger()
                } else {
                    try parseValue(depth: 1)
                }
                try skipWhitespace()
                if consumeIfPresent(0x7D) { break }
                try consume(0x2C)
                try skipWhitespace()
            }
        }
        try skipWhitespace()
        guard index == bytes.count, let result else { throw malformed() }
        try checkCancellation(force: true)
        return result
    }

    private mutating func parseValue(depth: Int) throws {
        guard depth <= Self.maximumDepth, let byte = currentByte else { throw malformed() }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(capture: false)
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw malformed()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw malformed() }
        try consume(0x7B)
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return }
        while true {
            try checkCancellation(force: false)
            _ = try parseString(capture: false)
            try skipWhitespace()
            try consume(0x3A)
            try skipWhitespace()
            try parseValue(depth: depth)
            try skipWhitespace()
            if consumeIfPresent(0x7D) { return }
            try consume(0x2C)
            try skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw malformed() }
        try consume(0x5B)
        try skipWhitespace()
        if consumeIfPresent(0x5D) { return }
        while true {
            try checkCancellation(force: false)
            try parseValue(depth: depth)
            try skipWhitespace()
            if consumeIfPresent(0x5D) { return }
            try consume(0x2C)
            try skipWhitespace()
        }
    }

    private mutating func parseString(capture: Bool) throws -> String {
        try consume(0x22)
        var decoded: [UInt8] = []
        if capture { decoded.reserveCapacity(16) }
        while let byte = currentByte {
            try checkCancellation(force: false)
            if byte == 0x22 {
                index += 1
                guard !capture || String(bytes: decoded, encoding: .utf8) != nil else {
                    throw malformed()
                }
                return capture ? String(decoding: decoded, as: UTF8.self) : ""
            }
            if byte <= 0x1F { throw malformed() }
            if byte == 0x5C {
                index += 1
                let scalar = try parseEscape()
                if capture { decoded.append(contentsOf: Self.utf8Bytes(for: scalar)) }
                continue
            }
            let start = index
            let length = try consumeRawUTF8Scalar()
            if capture { decoded.append(contentsOf: bytes[start..<(start + length)]) }
        }
        throw malformed()
    }

    private mutating func parseEscape() throws -> UInt32 {
        guard let escaped = currentByte else { throw malformed() }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            return UInt32(escaped)
        case 0x62:
            return 0x08
        case 0x66:
            return 0x0C
        case 0x6E:
            return 0x0A
        case 0x72:
            return 0x0D
        case 0x74:
            return 0x09
        case 0x75:
            return try parseUnicodeScalar()
        default:
            throw malformed()
        }
    }

    private mutating func consumeRawUTF8Scalar() throws -> Int {
        guard let first = currentByte else { throw malformed() }
        let length: Int
        let secondRange: ClosedRange<UInt8>
        switch first {
        case 0x20...0x7F:
            index += 1
            return 1
        case 0xC2...0xDF:
            length = 2
            secondRange = 0x80...0xBF
        case 0xE0:
            length = 3
            secondRange = 0xA0...0xBF
        case 0xE1...0xEC, 0xEE...0xEF:
            length = 3
            secondRange = 0x80...0xBF
        case 0xED:
            length = 3
            secondRange = 0x80...0x9F
        case 0xF0:
            length = 4
            secondRange = 0x90...0xBF
        case 0xF1...0xF3:
            length = 4
            secondRange = 0x80...0xBF
        case 0xF4:
            length = 4
            secondRange = 0x80...0x8F
        default:
            throw malformed()
        }
        guard index <= bytes.count - length,
            secondRange.contains(bytes[index + 1])
        else {
            throw malformed()
        }
        for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
            throw malformed()
        }
        index += length
        return length
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consumeIfPresent(0x5C), consumeIfPresent(0x75) else { throw malformed() }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw malformed() }
            return 0x10000
                + (UInt32(first - 0xD800) << 10)
                + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else { throw malformed() }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw malformed()
            }
            value = value * 16 + UInt16(digit)
            index += 1
        }
        return value
    }

    private mutating func parseInteger() throws -> Int {
        let start = index
        _ = consumeIfPresent(0x2D)
        guard let first = currentByte else { throw malformed() }
        if first == 0x30 {
            index += 1
            if currentByte.map({ (0x30...0x39).contains($0) }) == true { throw malformed() }
        } else {
            guard (0x31...0x39).contains(first) else { throw malformed() }
            repeat {
                index += 1
                try checkCancellation(force: false)
            } while currentByte.map {
                (0x30...0x39).contains($0)
            } == true
        }
        guard let value = Int(String(decoding: bytes[start..<index], as: UTF8.self)) else {
            throw malformed()
        }
        return value
    }

    private mutating func parseNumber() throws {
        _ = try parseIntegerPrefix()
        if consumeIfPresent(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformed()
            }
            repeat {
                index += 1
                try checkCancellation(force: false)
            } while currentByte.map {
                (0x30...0x39).contains($0)
            } == true
        }
        if consumeIfPresent(0x65) || consumeIfPresent(0x45) {
            _ = consumeIfPresent(0x2B) || consumeIfPresent(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformed()
            }
            repeat {
                index += 1
                try checkCancellation(force: false)
            } while currentByte.map {
                (0x30...0x39).contains($0)
            } == true
        }
    }

    private mutating func parseIntegerPrefix() throws -> Int {
        let start = index
        _ = consumeIfPresent(0x2D)
        guard let first = currentByte else { throw malformed() }
        if first == 0x30 {
            index += 1
            if currentByte.map({ (0x30...0x39).contains($0) }) == true { throw malformed() }
        } else {
            guard (0x31...0x39).contains(first) else { throw malformed() }
            repeat {
                index += 1
                try checkCancellation(force: false)
            } while currentByte.map {
                (0x30...0x39).contains($0)
            } == true
        }
        return start
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard literalBytes.count <= bytes.count - index else { throw malformed() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformed() }
            index += 1
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
            try checkCancellation(force: false)
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard consumeIfPresent(byte) else { throw malformed() }
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private mutating func checkCancellation(force: Bool) throws {
        guard force || index - lastCancellationIndex >= Self.cancellationInterval else { return }
        lastCancellationIndex = index
        try Task.checkCancellation()
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func malformed() -> RecentWorkspaceHistoryError {
        .malformedPersistence
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            byte - 0x30
        case 0x41...0x46:
            byte - 0x41 + 10
        case 0x61...0x66:
            byte - 0x61 + 10
        default:
            nil
        }
    }

    private static func utf8Bytes(for scalar: UInt32) -> [UInt8] {
        switch scalar {
        case 0...0x7F:
            [UInt8(scalar)]
        case 0x80...0x7FF:
            [
                0xC0 | UInt8(scalar >> 6),
                0x80 | UInt8(scalar & 0x3F)
            ]
        case 0x800...0xFFFF:
            [
                0xE0 | UInt8(scalar >> 12),
                0x80 | UInt8((scalar >> 6) & 0x3F),
                0x80 | UInt8(scalar & 0x3F)
            ]
        default:
            [
                0xF0 | UInt8(scalar >> 18),
                0x80 | UInt8((scalar >> 12) & 0x3F),
                0x80 | UInt8((scalar >> 6) & 0x3F),
                0x80 | UInt8(scalar & 0x3F)
            ]
        }
    }
}

private struct RecentWorkspaceJSONScanner {
    private static let maximumDepth = 8
    private static let maximumObjectMembers = 16
    private static let maximumArrayElements =
        RecentWorkspaceHistory.maximumSupportedEntries + 1
    private static let maximumValues =
        RecentWorkspaceHistory.maximumSupportedEntries * 8 + 16
    private static let maximumKeyBytes = 64
    private static let maximumStringBytes =
        RecentWorkspaceHistory.maximumSupportedPathBytes * 3 + 32
    private static let maximumNumberBytes = 32
    private static let cancellationInterval = 4 * 1_024

    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0
    private var valueCount = 0
    private var lastCancellationIndex = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func validate() throws {
        try checkCancellation(force: true)
        try skipWhitespace()
        try parseValue(depth: 0)
        try skipWhitespace()
        guard index == bytes.count else { throw malformed() }
        try checkCancellation(force: true)
    }

    private mutating func parseValue(depth: Int) throws {
        try checkCancellation(force: true)
        guard valueCount < Self.maximumValues else { throw malformed() }
        valueCount += 1
        guard let byte = currentByte else { throw malformed() }
        switch byte {
        case 0x7B:
            try parseObject(depth: depth + 1)
        case 0x5B:
            try parseArray(depth: depth + 1)
        case 0x22:
            _ = try parseString(maximumBytes: Self.maximumStringBytes, capture: false)
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw malformed()
        }
    }

    private mutating func parseObject(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw malformed() }
        try consume(0x7B)
        try skipWhitespace()
        if consumeIfPresent(0x7D) { return }
        var memberCount = 0
        var keys: Set<String> = []
        while true {
            try checkCancellation(force: false)
            guard memberCount < Self.maximumObjectMembers else { throw malformed() }
            memberCount += 1
            let key = try parseString(maximumBytes: Self.maximumKeyBytes, capture: true)
            guard keys.insert(key).inserted else {
                throw RecentWorkspaceHistoryError.duplicatePersistenceKey
            }
            try skipWhitespace()
            try consume(0x3A)
            try skipWhitespace()
            try parseValue(depth: depth)
            try skipWhitespace()
            if consumeIfPresent(0x7D) { return }
            try consume(0x2C)
            try skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw malformed() }
        try consume(0x5B)
        try skipWhitespace()
        if consumeIfPresent(0x5D) { return }
        var elementCount = 0
        while true {
            try checkCancellation(force: true)
            guard elementCount < Self.maximumArrayElements else { throw malformed() }
            elementCount += 1
            try parseValue(depth: depth)
            try skipWhitespace()
            if consumeIfPresent(0x5D) { return }
            try consume(0x2C)
            try skipWhitespace()
        }
    }

    private mutating func parseString(maximumBytes: Int, capture: Bool) throws -> String {
        try consume(0x22)
        var decoded: [UInt8] = []
        if capture { decoded.reserveCapacity(16) }
        var decodedCount = 0
        while let byte = currentByte {
            try checkCancellation(force: false)
            if byte == 0x22 {
                index += 1
                guard !capture || String(bytes: decoded, encoding: .utf8) != nil else {
                    throw malformed()
                }
                return capture ? String(decoding: decoded, as: UTF8.self) : ""
            }
            if byte <= 0x1F { throw malformed() }
            if byte == 0x5C {
                index += 1
                let scalar = try parseEscape()
                let scalarBytes = Self.utf8Bytes(for: scalar)
                guard decodedCount <= maximumBytes - scalarBytes.count else {
                    throw malformed()
                }
                decodedCount += scalarBytes.count
                if capture { decoded.append(contentsOf: scalarBytes) }
                continue
            }
            let start = index
            let length = try consumeRawUTF8Scalar()
            guard decodedCount <= maximumBytes - length else { throw malformed() }
            decodedCount += length
            if capture { decoded.append(contentsOf: bytes[start..<(start + length)]) }
        }
        throw malformed()
    }

    private mutating func parseEscape() throws -> UInt32 {
        guard let escaped = currentByte else { throw malformed() }
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            return UInt32(escaped)
        case 0x62:
            return 0x08
        case 0x66:
            return 0x0C
        case 0x6E:
            return 0x0A
        case 0x72:
            return 0x0D
        case 0x74:
            return 0x09
        case 0x75:
            return try parseUnicodeScalar()
        default:
            throw malformed()
        }
    }

    private mutating func consumeRawUTF8Scalar() throws -> Int {
        guard let first = currentByte else { throw malformed() }
        let length: Int
        let secondRange: ClosedRange<UInt8>
        switch first {
        case 0x20...0x7F:
            index += 1
            return 1
        case 0xC2...0xDF:
            length = 2
            secondRange = 0x80...0xBF
        case 0xE0:
            length = 3
            secondRange = 0xA0...0xBF
        case 0xE1...0xEC, 0xEE...0xEF:
            length = 3
            secondRange = 0x80...0xBF
        case 0xED:
            length = 3
            secondRange = 0x80...0x9F
        case 0xF0:
            length = 4
            secondRange = 0x90...0xBF
        case 0xF1...0xF3:
            length = 4
            secondRange = 0x80...0xBF
        case 0xF4:
            length = 4
            secondRange = 0x80...0x8F
        default:
            throw malformed()
        }
        guard index <= bytes.count - length,
            secondRange.contains(bytes[index + 1])
        else {
            throw malformed()
        }
        for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
            throw malformed()
        }
        index += length
        return length
    }

    private mutating func parseUnicodeScalar() throws -> UInt32 {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            guard consumeIfPresent(0x5C), consumeIfPresent(0x75) else { throw malformed() }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw malformed() }
            return 0x10000
                + (UInt32(first - 0xD800) << 10)
                + UInt32(second - 0xDC00)
        }
        guard !(0xDC00...0xDFFF).contains(first) else { throw malformed() }
        return UInt32(first)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = Self.hexValue(byte) else {
                throw malformed()
            }
            value = value * 16 + UInt16(digit)
            index += 1
        }
        return value
    }

    private mutating func parseNumber() throws {
        let start = index
        _ = consumeIfPresent(0x2D)
        guard let first = currentByte else { throw malformed() }
        if first == 0x30 {
            try advanceNumber(start: start)
            if currentByte.map({ (0x30...0x39).contains($0) }) == true { throw malformed() }
        } else {
            guard (0x31...0x39).contains(first) else { throw malformed() }
            repeat {
                try advanceNumber(start: start)
            } while currentByte.map {
                (0x30...0x39).contains($0)
            } == true
        }
        if consumeIfPresent(0x2E) {
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformed()
            }
            repeat {
                try advanceNumber(start: start)
            } while currentByte.map {
                (0x30...0x39).contains($0)
            } == true
        }
        if consumeIfPresent(0x65) || consumeIfPresent(0x45) {
            _ = consumeIfPresent(0x2B) || consumeIfPresent(0x2D)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw malformed()
            }
            repeat {
                try advanceNumber(start: start)
            } while currentByte.map {
                (0x30...0x39).contains($0)
            } == true
        }
        guard index - start <= Self.maximumNumberBytes else { throw malformed() }
    }

    private mutating func advanceNumber(start: Int) throws {
        guard index - start < Self.maximumNumberBytes else { throw malformed() }
        index += 1
        try checkCancellation(force: false)
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let literalBytes = literal.withUTF8Buffer { Array($0) }
        guard literalBytes.count <= bytes.count - index else { throw malformed() }
        for byte in literalBytes {
            guard bytes[index] == byte else { throw malformed() }
            index += 1
        }
    }

    private mutating func skipWhitespace() throws {
        while let byte = currentByte,
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        {
            index += 1
            try checkCancellation(force: false)
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard consumeIfPresent(byte) else { throw malformed() }
    }

    private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private mutating func checkCancellation(force: Bool) throws {
        guard force || index - lastCancellationIndex >= Self.cancellationInterval else { return }
        lastCancellationIndex = index
        try Task.checkCancellation()
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func malformed() -> RecentWorkspaceHistoryError {
        .malformedPersistence
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            byte - 0x30
        case 0x41...0x46:
            byte - 0x41 + 10
        case 0x61...0x66:
            byte - 0x61 + 10
        default:
            nil
        }
    }

    private static func utf8Bytes(for scalar: UInt32) -> [UInt8] {
        switch scalar {
        case 0...0x7F:
            [UInt8(scalar)]
        case 0x80...0x7FF:
            [
                0xC0 | UInt8(scalar >> 6),
                0x80 | UInt8(scalar & 0x3F)
            ]
        case 0x800...0xFFFF:
            [
                0xE0 | UInt8(scalar >> 12),
                0x80 | UInt8((scalar >> 6) & 0x3F),
                0x80 | UInt8(scalar & 0x3F)
            ]
        default:
            [
                0xF0 | UInt8(scalar >> 18),
                0x80 | UInt8((scalar >> 12) & 0x3F),
                0x80 | UInt8((scalar >> 6) & 0x3F),
                0x80 | UInt8(scalar & 0x3F)
            ]
        }
    }
}
