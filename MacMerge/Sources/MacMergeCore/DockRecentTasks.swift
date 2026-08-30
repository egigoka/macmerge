import Foundation

/// Caller-owned freshness token. Increment it whenever any request input changes.
public struct DockRecentTasksGeneration:
    RawRepresentable, Codable, Equatable, Hashable, Sendable
{
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public enum DockRecentTaskKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case file
    case folder
    case project
    case task
}

public enum DockRecentTaskCapability:
    String, Codable, CaseIterable, Equatable, Hashable, Sendable
{
    case compareFiles
    case compareFolders
    case compareClipboard
    case openProject
    case resolveBookmarks
}

public enum DockRecentTaskUnavailableReason: Equatable, Hashable, Sendable {
    case missing
    case stale
    case missingCapability(DockRecentTaskCapability)
}

public enum DockRecentTaskAvailability: Equatable, Hashable, Sendable {
    case available
    case unavailable(DockRecentTaskUnavailableReason)
}

public enum DockRecentTasksError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case staleGeneration(
        expected: DockRecentTasksGeneration,
        actual: DockRecentTasksGeneration
    )
    case invalidLimits
    case inputLimitExceeded(maximum: Int)
    case bookmarkBindingLimitExceeded(maximum: Int)
    case invalidResourceURL
    case resourcePathTooLong(maximumUTF8Bytes: Int)
    case duplicateBookmarkURL
    case duplicateBookmarkReference
    case unusedBookmarkReference
    case invalidHistoryEntry
    case workLimitExceeded(maximumWork: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Dock recent-task planning was cancelled."
        case .staleGeneration:
            "Dock recent-task generation is stale."
        case .invalidLimits:
            "Dock recent-task limits are invalid."
        case .inputLimitExceeded(let maximum):
            "Dock recent-task input exceeds the \(maximum)-item limit."
        case .bookmarkBindingLimitExceeded(let maximum):
            "Dock recent-task input exceeds the \(maximum)-bookmark limit."
        case .invalidResourceURL:
            "Dock recent tasks accept only absolute local file URLs without credentials."
        case .resourcePathTooLong(let maximum):
            "A Dock recent-task path exceeds the \(maximum)-byte limit."
        case .duplicateBookmarkURL:
            "Dock recent-task input contains duplicate bookmark URLs."
        case .duplicateBookmarkReference:
            "Dock recent-task input reuses a bookmark reference."
        case .unusedBookmarkReference:
            "Dock recent-task input contains a bookmark without a matching recent resource."
        case .invalidHistoryEntry:
            "Dock recent-task input contains an invalid history entry."
        case .workLimitExceeded(let maximum):
            "Dock recent-task planning exceeds the \(maximum)-unit work limit."
        }
    }
}

/// Opaque lookup key for bookmark data owned by the caller.
///
/// Keeping bookmark bytes outside the plan prevents paths or credentials embedded in those bytes
/// from reaching labels, diagnostics, or menu models.
public struct DockRecentBookmarkReference:
    RawRepresentable, Codable, Equatable, Hashable, Sendable, CustomReflectable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String { "<bookmark-reference>" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["value": "<redacted>"], displayStyle: .struct)
    }
}

/// Associates one recent local URL with caller-owned bookmark storage.
public struct DockRecentBookmarkBinding:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let url: URL
    public let reference: DockRecentBookmarkReference

    public init(url: URL, reference: DockRecentBookmarkReference) {
        self.url = url
        self.reference = reference
    }

    public var description: String { "DockRecentBookmarkBinding(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["url": "<redacted>", "reference": "<redacted>"],
            displayStyle: .struct
        )
    }
}

/// Inert resource reference. It does not resolve a bookmark or open the URL.
public struct DockRecentResourceReference:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let url: URL
    public let bookmark: DockRecentBookmarkReference?

    fileprivate init(url: URL, bookmark: DockRecentBookmarkReference?) {
        self.url = url
        self.bookmark = bookmark
    }

    public var description: String { "DockRecentResourceReference(<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["url": "<redacted>", "hasBookmark": bookmark != nil],
            displayStyle: .struct
        )
    }
}

/// Exact duplicate identity with path-safe diagnostics.
public struct DockRecentTaskIdentity:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let kind: DockRecentTaskKind
    private let primary: String
    private let secondary: String?

    fileprivate init(kind: DockRecentTaskKind, primary: String, secondary: String? = nil) {
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
    }

    public var description: String { "\(kind.rawValue):<redacted>" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["kind": kind.rawValue, "hasSecondary": secondary != nil],
            displayStyle: .struct
        )
    }
}

/// Stable path-redacted menu text. Titles contain only bounded leaf names, never parent paths.
public struct DockRecentTaskLabel: Equatable, Hashable, Sendable {
    public let title: String
    public let subtitle: String

    fileprivate init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

/// Intent only. Consumers decide how to materialize it after checking plan freshness.
public enum DockRecentTaskIntent:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case compareFiles(
        left: DockRecentResourceReference,
        right: DockRecentResourceReference
    )
    case compareFolders(
        left: DockRecentResourceReference,
        right: DockRecentResourceReference
    )
    case openProject(DockRecentResourceReference)
    case performTask(RecentWorkspaceCommonTask)

    public var kind: DockRecentTaskKind {
        switch self {
        case .compareFiles: .file
        case .compareFolders: .folder
        case .openProject: .project
        case .performTask: .task
        }
    }

    public var description: String { "\(kind.rawValue):<redacted>" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["kind": kind.rawValue], displayStyle: .enum)
    }
}

public struct DockRecentMenuItem:
    Identifiable, Equatable, Hashable, Sendable, CustomReflectable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let id: DockRecentTaskIdentity
    public let kind: DockRecentTaskKind
    public let label: DockRecentTaskLabel
    public let isPinned: Bool
    public let availability: DockRecentTaskAvailability
    public let requiredCapabilities: Set<DockRecentTaskCapability>
    public let intent: DockRecentTaskIntent

    fileprivate init(
        id: DockRecentTaskIdentity,
        label: DockRecentTaskLabel,
        isPinned: Bool,
        availability: DockRecentTaskAvailability,
        requiredCapabilities: Set<DockRecentTaskCapability>,
        intent: DockRecentTaskIntent
    ) {
        self.id = id
        kind = intent.kind
        self.label = label
        self.isPinned = isPinned
        self.availability = availability
        self.requiredCapabilities = requiredCapabilities
        self.intent = intent
    }

    public var description: String { "DockRecentMenuItem(\(kind.rawValue):<redacted>)" }
    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "kind": kind.rawValue,
                "isPinned": isPinned,
                "availability": availability
            ],
            displayStyle: .struct
        )
    }
}

public enum DockRecentMenuSectionKind:
    String, Codable, CaseIterable, Equatable, Hashable, Sendable
{
    case pinned
    case recent
    case tasks
}

public struct DockRecentMenuSection:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let kind: DockRecentMenuSectionKind
    public let items: [DockRecentMenuItem]

    fileprivate init(kind: DockRecentMenuSectionKind, items: [DockRecentMenuItem]) {
        self.kind = kind
        self.items = items
    }

    public var description: String {
        "DockRecentMenuSection(kind: \(kind.rawValue), itemCount: \(items.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["kind": kind.rawValue, "itemCount": items.count],
            displayStyle: .struct
        )
    }
}

public struct DockRecentTasksLimits: Equatable, Hashable, Sendable {
    public static let hardMaximumMenuItems = 256
    public static let hardMaximumInputItems =
        2 * RecentComparisonPairs.maximumCapacity + RecentWorkspaceCommonTask.allCases.count
    public static let hardMaximumBookmarkBindings = 4_096
    public static let hardMaximumPathUTF8Bytes = 64 * 1_024
    public static let hardMaximumTitleUTF8Bytes = 1_024
    public static let hardMaximumWork = 128 * 1_024 * 1_024

    public static let `default` = DockRecentTasksLimits(
        uncheckedMaximumMenuItems: 36,
        maximumPinnedItems: 12,
        maximumRecentItems: 20,
        maximumTaskItems: RecentWorkspaceCommonTask.allCases.count,
        maximumInputItems: hardMaximumInputItems,
        maximumBookmarkBindings: hardMaximumBookmarkBindings,
        maximumPathUTF8Bytes: RecentWorkspaceHistory.defaultMaximumPathBytes,
        maximumTitleUTF8Bytes: 512,
        maximumWork: 16 * 1_024 * 1_024
    )

    public let maximumMenuItems: Int
    public let maximumPinnedItems: Int
    public let maximumRecentItems: Int
    public let maximumTaskItems: Int
    public let maximumInputItems: Int
    public let maximumBookmarkBindings: Int
    public let maximumPathUTF8Bytes: Int
    public let maximumTitleUTF8Bytes: Int
    public let maximumWork: Int

    public init(
        maximumMenuItems: Int = 36,
        maximumPinnedItems: Int = 12,
        maximumRecentItems: Int = 20,
        maximumTaskItems: Int = RecentWorkspaceCommonTask.allCases.count,
        maximumInputItems: Int = DockRecentTasksLimits.hardMaximumInputItems,
        maximumBookmarkBindings: Int = DockRecentTasksLimits.hardMaximumBookmarkBindings,
        maximumPathUTF8Bytes: Int = RecentWorkspaceHistory.defaultMaximumPathBytes,
        maximumTitleUTF8Bytes: Int = 512,
        maximumWork: Int = 16 * 1_024 * 1_024
    ) throws {
        guard
            Self.valid(
                maximumMenuItems: maximumMenuItems,
                maximumPinnedItems: maximumPinnedItems,
                maximumRecentItems: maximumRecentItems,
                maximumTaskItems: maximumTaskItems,
                maximumInputItems: maximumInputItems,
                maximumBookmarkBindings: maximumBookmarkBindings,
                maximumPathUTF8Bytes: maximumPathUTF8Bytes,
                maximumTitleUTF8Bytes: maximumTitleUTF8Bytes,
                maximumWork: maximumWork
            )
        else {
            throw DockRecentTasksError.invalidLimits
        }
        self.maximumMenuItems = maximumMenuItems
        self.maximumPinnedItems = maximumPinnedItems
        self.maximumRecentItems = maximumRecentItems
        self.maximumTaskItems = maximumTaskItems
        self.maximumInputItems = maximumInputItems
        self.maximumBookmarkBindings = maximumBookmarkBindings
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTitleUTF8Bytes = maximumTitleUTF8Bytes
        self.maximumWork = maximumWork
    }

    private init(
        uncheckedMaximumMenuItems maximumMenuItems: Int,
        maximumPinnedItems: Int,
        maximumRecentItems: Int,
        maximumTaskItems: Int,
        maximumInputItems: Int,
        maximumBookmarkBindings: Int,
        maximumPathUTF8Bytes: Int,
        maximumTitleUTF8Bytes: Int,
        maximumWork: Int
    ) {
        self.maximumMenuItems = maximumMenuItems
        self.maximumPinnedItems = maximumPinnedItems
        self.maximumRecentItems = maximumRecentItems
        self.maximumTaskItems = maximumTaskItems
        self.maximumInputItems = maximumInputItems
        self.maximumBookmarkBindings = maximumBookmarkBindings
        self.maximumPathUTF8Bytes = maximumPathUTF8Bytes
        self.maximumTitleUTF8Bytes = maximumTitleUTF8Bytes
        self.maximumWork = maximumWork
    }

    private static func valid(
        maximumMenuItems: Int,
        maximumPinnedItems: Int,
        maximumRecentItems: Int,
        maximumTaskItems: Int,
        maximumInputItems: Int,
        maximumBookmarkBindings: Int,
        maximumPathUTF8Bytes: Int,
        maximumTitleUTF8Bytes: Int,
        maximumWork: Int
    ) -> Bool {
        maximumMenuItems > 0 && maximumMenuItems <= hardMaximumMenuItems
            && maximumPinnedItems >= 0 && maximumPinnedItems <= hardMaximumMenuItems
            && maximumRecentItems >= 0 && maximumRecentItems <= hardMaximumMenuItems
            && maximumTaskItems >= 0 && maximumTaskItems <= hardMaximumMenuItems
            && maximumInputItems > 0 && maximumInputItems <= hardMaximumInputItems
            && maximumBookmarkBindings >= 0
            && maximumBookmarkBindings <= hardMaximumBookmarkBindings
            && maximumPathUTF8Bytes > 0
            && maximumPathUTF8Bytes <= hardMaximumPathUTF8Bytes
            && maximumTitleUTF8Bytes >= 16
            && maximumTitleUTF8Bytes <= hardMaximumTitleUTF8Bytes
            && maximumWork > 0 && maximumWork <= hardMaximumWork
    }
}

/// Immutable, UI-independent inputs for one deterministic menu generation.
public struct DockRecentTasksRequest:
    Equatable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let generation: DockRecentTasksGeneration
    public let recentComparisons: RecentComparisonPairs
    public let workspaceHistory: RecentWorkspaceHistory
    public let commonTasks: [RecentWorkspaceCommonTask]
    public let bookmarkBindings: [DockRecentBookmarkBinding]
    public let capabilities: Set<DockRecentTaskCapability>
    public let limits: DockRecentTasksLimits

    public init(
        generation: DockRecentTasksGeneration,
        recentComparisons: RecentComparisonPairs = RecentComparisonPairs(),
        workspaceHistory: RecentWorkspaceHistory = RecentWorkspaceHistory(),
        commonTasks: [RecentWorkspaceCommonTask] = RecentWorkspaceCommonTask.allCases,
        bookmarkBindings: [DockRecentBookmarkBinding] = [],
        capabilities: Set<DockRecentTaskCapability> = [],
        limits: DockRecentTasksLimits = .default
    ) {
        self.generation = generation
        self.recentComparisons = recentComparisons
        self.workspaceHistory = workspaceHistory
        self.commonTasks = commonTasks
        self.bookmarkBindings = bookmarkBindings
        self.capabilities = capabilities
        self.limits = limits
    }

    public var description: String {
        "DockRecentTasksRequest(generation: \(generation.rawValue), inputCount: \(inputCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "generation": generation.rawValue,
                "inputCount": inputCount,
                "bookmarkCount": bookmarkBindings.count
            ],
            displayStyle: .struct
        )
    }

    fileprivate var inputCount: Int {
        recentComparisons.count + workspaceHistory.count + commonTasks.count
    }
}

/// Bounded menu model. Sections always appear in pinned, recent, task order when nonempty.
public struct DockRecentTasksPlan:
    Equatable, Hashable, Sendable, CustomReflectable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let generation: DockRecentTasksGeneration
    public let sections: [DockRecentMenuSection]
    public let duplicateIdentityCount: Int
    public let omittedItemCount: Int

    fileprivate init(
        generation: DockRecentTasksGeneration,
        sections: [DockRecentMenuSection],
        duplicateIdentityCount: Int,
        omittedItemCount: Int
    ) {
        self.generation = generation
        self.sections = sections
        self.duplicateIdentityCount = duplicateIdentityCount
        self.omittedItemCount = omittedItemCount
    }

    public var items: [DockRecentMenuItem] {
        sections.flatMap(\.items)
    }

    public var wasTruncated: Bool { omittedItemCount > 0 }

    public func isCurrent(generation: DockRecentTasksGeneration) -> Bool {
        self.generation == generation
    }

    public func requireCurrent(generation: DockRecentTasksGeneration) throws {
        guard isCurrent(generation: generation) else {
            throw DockRecentTasksError.staleGeneration(
                expected: generation,
                actual: self.generation
            )
        }
    }

    public var description: String {
        "DockRecentTasksPlan(generation: \(generation.rawValue), itemCount: \(items.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "generation": generation.rawValue,
                "itemCount": items.count,
                "duplicateIdentityCount": duplicateIdentityCount,
                "omittedItemCount": omittedItemCount
            ],
            displayStyle: .struct
        )
    }
}

/// Pure planner for native recent comparisons and common Dock tasks.
public enum DockRecentTasksPlanner: Sendable {
    public static func plan(
        _ request: DockRecentTasksRequest,
        expecting expectedGeneration: DockRecentTasksGeneration? = nil
    ) throws -> DockRecentTasksPlan {
        do {
            try Task.checkCancellation()
            if let expectedGeneration, expectedGeneration != request.generation {
                throw DockRecentTasksError.staleGeneration(
                    expected: expectedGeneration,
                    actual: request.generation
                )
            }
            return try makePlan(request)
        } catch is CancellationError {
            throw DockRecentTasksError.cancelled
        }
    }

    private static func makePlan(_ request: DockRecentTasksRequest) throws -> DockRecentTasksPlan {
        guard request.inputCount <= request.limits.maximumInputItems else {
            throw DockRecentTasksError.inputLimitExceeded(
                maximum: request.limits.maximumInputItems
            )
        }
        guard request.bookmarkBindings.count <= request.limits.maximumBookmarkBindings else {
            throw DockRecentTasksError.bookmarkBindingLimitExceeded(
                maximum: request.limits.maximumBookmarkBindings
            )
        }

        var work = DockRecentTasksWork(maximum: request.limits.maximumWork)
        let bookmarks = try bookmarkMap(
            request.bookmarkBindings,
            limits: request.limits,
            work: &work
        )
        var usedBookmarkKeys: Set<String> = []
        var seenIdentities: Set<DockRecentTaskIdentity> = []
        var pinnedItems: [DockRecentMenuItem] = []
        var recentItems: [DockRecentMenuItem] = []
        var taskItems: [DockRecentMenuItem] = []
        var duplicateIdentityCount = 0
        var omittedItemCount = 0
        var totalItemCount = 0

        func append(
            _ item: DockRecentMenuItem,
            to items: inout [DockRecentMenuItem],
            sectionLimit: Int
        ) throws {
            try work.charge(1)
            guard seenIdentities.insert(item.id).inserted else {
                duplicateIdentityCount += 1
                return
            }
            guard items.count < sectionLimit,
                totalItemCount < request.limits.maximumMenuItems
            else {
                omittedItemCount += 1
                return
            }
            items.append(item)
            totalItemCount += 1
        }

        for entry in request.workspaceHistory where entry.isPinned {
            let item = try menuItem(
                entry,
                bookmarks: bookmarks,
                usedBookmarkKeys: &usedBookmarkKeys,
                request: request,
                work: &work
            )
            try append(
                item,
                to: &pinnedItems,
                sectionLimit: request.limits.maximumPinnedItems
            )
        }

        for entry in request.workspaceHistory where !entry.isPinned && entry.kind != .commonTask {
            let item = try menuItem(
                entry,
                bookmarks: bookmarks,
                usedBookmarkKeys: &usedBookmarkKeys,
                request: request,
                work: &work
            )
            try append(
                item,
                to: &recentItems,
                sectionLimit: request.limits.maximumRecentItems
            )
        }

        for pair in request.recentComparisons {
            let item = try menuItem(
                pair,
                bookmarks: bookmarks,
                usedBookmarkKeys: &usedBookmarkKeys,
                request: request,
                work: &work
            )
            try append(
                item,
                to: &recentItems,
                sectionLimit: request.limits.maximumRecentItems
            )
        }

        for entry in request.workspaceHistory where !entry.isPinned && entry.kind == .commonTask {
            let item = try menuItem(
                entry,
                bookmarks: bookmarks,
                usedBookmarkKeys: &usedBookmarkKeys,
                request: request,
                work: &work
            )
            try append(
                item,
                to: &taskItems,
                sectionLimit: request.limits.maximumTaskItems
            )
        }

        for task in request.commonTasks {
            let item = try menuItem(
                task,
                marker: .available,
                pinned: false,
                request: request,
                work: &work
            )
            try append(
                item,
                to: &taskItems,
                sectionLimit: request.limits.maximumTaskItems
            )
        }

        for binding in request.bookmarkBindings {
            let key = try canonicalResource(
                binding.url,
                isDirectory: binding.url.hasDirectoryPath,
                limits: request.limits,
                work: &work
            ).key
            guard usedBookmarkKeys.contains(key) else {
                throw DockRecentTasksError.unusedBookmarkReference
            }
        }

        var sections: [DockRecentMenuSection] = []
        sections.reserveCapacity(DockRecentMenuSectionKind.allCases.count)
        if !pinnedItems.isEmpty {
            sections.append(.init(kind: .pinned, items: pinnedItems))
        }
        if !recentItems.isEmpty {
            sections.append(.init(kind: .recent, items: recentItems))
        }
        if !taskItems.isEmpty {
            sections.append(.init(kind: .tasks, items: taskItems))
        }
        try Task.checkCancellation()
        return DockRecentTasksPlan(
            generation: request.generation,
            sections: sections,
            duplicateIdentityCount: duplicateIdentityCount,
            omittedItemCount: omittedItemCount
        )
    }

    private static func bookmarkMap(
        _ bindings: [DockRecentBookmarkBinding],
        limits: DockRecentTasksLimits,
        work: inout DockRecentTasksWork
    ) throws -> [String: DockRecentBookmarkReference] {
        var result: [String: DockRecentBookmarkReference] = [:]
        result.reserveCapacity(bindings.count)
        var references: Set<DockRecentBookmarkReference> = []
        references.reserveCapacity(bindings.count)
        for binding in bindings {
            try work.charge(1)
            let resource = try canonicalResource(
                binding.url,
                isDirectory: binding.url.hasDirectoryPath,
                limits: limits,
                work: &work
            )
            guard result[resource.key] == nil else {
                throw DockRecentTasksError.duplicateBookmarkURL
            }
            guard references.insert(binding.reference).inserted else {
                throw DockRecentTasksError.duplicateBookmarkReference
            }
            result[resource.key] = binding.reference
        }
        return result
    }

    private static func menuItem(
        _ entry: RecentWorkspaceEntry,
        bookmarks: [String: DockRecentBookmarkReference],
        usedBookmarkKeys: inout Set<String>,
        request: DockRecentTasksRequest,
        work: inout DockRecentTasksWork
    ) throws -> DockRecentMenuItem {
        switch entry.kind {
        case .projectFile:
            guard let url = entry.projectFileURL else {
                throw DockRecentTasksError.invalidHistoryEntry
            }
            let resource = try resourceReference(
                url,
                isDirectory: false,
                bookmarks: bookmarks,
                usedBookmarkKeys: &usedBookmarkKeys,
                limits: request.limits,
                work: &work
            )
            return try menuItem(
                kind: .project,
                primary: resource.url.absoluteString,
                secondary: nil,
                title: leafName(resource.url, limits: request.limits, work: &work),
                subtitle: "Project file",
                pinned: entry.isPinned,
                marker: entry.availability,
                intent: .openProject(resource),
                baseCapabilities: [.openProject],
                request: request,
                work: &work
            )
        case .folderComparison:
            guard let pair = entry.folderComparison, pair.kind == .folder else {
                throw DockRecentTasksError.invalidHistoryEntry
            }
            return try menuItem(
                pair,
                pinned: entry.isPinned,
                marker: entry.availability,
                bookmarks: bookmarks,
                usedBookmarkKeys: &usedBookmarkKeys,
                request: request,
                work: &work
            )
        case .commonTask:
            guard let task = entry.commonTask else {
                throw DockRecentTasksError.invalidHistoryEntry
            }
            return try menuItem(
                task,
                marker: entry.availability,
                pinned: entry.isPinned,
                request: request,
                work: &work
            )
        }
    }

    private static func menuItem(
        _ pair: RecentComparisonPair,
        pinned: Bool = false,
        marker: RecentWorkspaceAvailability = .available,
        bookmarks: [String: DockRecentBookmarkReference],
        usedBookmarkKeys: inout Set<String>,
        request: DockRecentTasksRequest,
        work: inout DockRecentTasksWork
    ) throws -> DockRecentMenuItem {
        let isDirectory = pair.kind == .folder
        let left = try resourceReference(
            pair.left,
            isDirectory: isDirectory,
            bookmarks: bookmarks,
            usedBookmarkKeys: &usedBookmarkKeys,
            limits: request.limits,
            work: &work
        )
        let right = try resourceReference(
            pair.right,
            isDirectory: isDirectory,
            bookmarks: bookmarks,
            usedBookmarkKeys: &usedBookmarkKeys,
            limits: request.limits,
            work: &work
        )
        let title = try pairTitle(
            left.url,
            right.url,
            limits: request.limits,
            work: &work
        )
        switch pair.kind {
        case .file:
            return try menuItem(
                kind: .file,
                primary: left.url.absoluteString,
                secondary: right.url.absoluteString,
                title: title,
                subtitle: "File comparison",
                pinned: pinned,
                marker: marker,
                intent: .compareFiles(left: left, right: right),
                baseCapabilities: [.compareFiles],
                request: request,
                work: &work
            )
        case .folder:
            return try menuItem(
                kind: .folder,
                primary: left.url.absoluteString,
                secondary: right.url.absoluteString,
                title: title,
                subtitle: "Folder comparison",
                pinned: pinned,
                marker: marker,
                intent: .compareFolders(left: left, right: right),
                baseCapabilities: [.compareFolders],
                request: request,
                work: &work
            )
        }
    }

    private static func menuItem(
        _ task: RecentWorkspaceCommonTask,
        marker: RecentWorkspaceAvailability,
        pinned: Bool,
        request: DockRecentTasksRequest,
        work: inout DockRecentTasksWork
    ) throws -> DockRecentMenuItem {
        let metadata = task.displayMetadata
        let capability: DockRecentTaskCapability
        switch task {
        case .compareFiles: capability = .compareFiles
        case .compareFolders: capability = .compareFolders
        case .compareClipboard: capability = .compareClipboard
        case .openProject: capability = .openProject
        }
        return try menuItem(
            kind: .task,
            primary: task.rawValue,
            secondary: nil,
            title: metadata.title,
            subtitle: metadata.subtitle,
            pinned: pinned,
            marker: marker,
            intent: .performTask(task),
            baseCapabilities: [capability],
            request: request,
            work: &work
        )
    }

    private static func menuItem(
        kind: DockRecentTaskKind,
        primary: String,
        secondary: String?,
        title: String,
        subtitle: String,
        pinned: Bool,
        marker: RecentWorkspaceAvailability,
        intent: DockRecentTaskIntent,
        baseCapabilities: Set<DockRecentTaskCapability>,
        request: DockRecentTasksRequest,
        work: inout DockRecentTasksWork
    ) throws -> DockRecentMenuItem {
        var requiredCapabilities = baseCapabilities
        switch intent {
        case .compareFiles(let left, let right), .compareFolders(let left, let right):
            if left.bookmark != nil || right.bookmark != nil {
                requiredCapabilities.insert(.resolveBookmarks)
            }
        case .openProject(let resource):
            if resource.bookmark != nil {
                requiredCapabilities.insert(.resolveBookmarks)
            }
        case .performTask:
            break
        }
        let boundedTitle = try safeLabel(
            title,
            maximumUTF8Bytes: request.limits.maximumTitleUTF8Bytes,
            work: &work
        )
        try work.charge(subtitle.utf8.count)
        return DockRecentMenuItem(
            id: DockRecentTaskIdentity(kind: kind, primary: primary, secondary: secondary),
            label: DockRecentTaskLabel(title: boundedTitle, subtitle: subtitle),
            isPinned: pinned,
            availability: availability(
                marker: marker,
                requiredCapabilities: requiredCapabilities,
                availableCapabilities: request.capabilities
            ),
            requiredCapabilities: requiredCapabilities,
            intent: intent
        )
    }

    private static func availability(
        marker: RecentWorkspaceAvailability,
        requiredCapabilities: Set<DockRecentTaskCapability>,
        availableCapabilities: Set<DockRecentTaskCapability>
    ) -> DockRecentTaskAvailability {
        switch marker {
        case .missing:
            return .unavailable(.missing)
        case .stale:
            return .unavailable(.stale)
        case .available:
            break
        }
        for capability in DockRecentTaskCapability.allCases
        where requiredCapabilities.contains(capability)
            && !availableCapabilities.contains(capability)
        {
            return .unavailable(.missingCapability(capability))
        }
        return .available
    }

    private static func resourceReference(
        _ url: URL,
        isDirectory: Bool,
        bookmarks: [String: DockRecentBookmarkReference],
        usedBookmarkKeys: inout Set<String>,
        limits: DockRecentTasksLimits,
        work: inout DockRecentTasksWork
    ) throws -> DockRecentResourceReference {
        let resource = try canonicalResource(
            url,
            isDirectory: isDirectory,
            limits: limits,
            work: &work
        )
        let bookmark = bookmarks[resource.key]
        if bookmark != nil {
            usedBookmarkKeys.insert(resource.key)
        }
        return DockRecentResourceReference(url: resource.url, bookmark: bookmark)
    }

    private static func canonicalResource(
        _ url: URL,
        isDirectory: Bool,
        limits: DockRecentTasksLimits,
        work: inout DockRecentTasksWork
    ) throws -> DockRecentTasksCanonicalResource {
        let maximumURLBytes = limits.maximumPathUTF8Bytes * 3 + 64
        guard
            try boundedUTF8Count(url.absoluteString, maximum: maximumURLBytes, work: &work)
                != nil
        else {
            throw DockRecentTasksError.resourcePathTooLong(
                maximumUTF8Bytes: limits.maximumPathUTF8Bytes
            )
        }
        guard let path = validatedRecentFileURLPath(url) else {
            throw DockRecentTasksError.invalidResourceURL
        }
        guard
            try boundedUTF8Count(path, maximum: limits.maximumPathUTF8Bytes, work: &work)
                != nil
        else {
            throw DockRecentTasksError.resourcePathTooLong(
                maximumUTF8Bytes: limits.maximumPathUTF8Bytes
            )
        }
        let canonicalURL = URL(
            fileURLWithPath: path,
            isDirectory: isDirectory
        ).standardizedFileURL
        guard
            try boundedUTF8Count(
                canonicalURL.path,
                maximum: limits.maximumPathUTF8Bytes,
                work: &work
            ) != nil
        else {
            throw DockRecentTasksError.resourcePathTooLong(
                maximumUTF8Bytes: limits.maximumPathUTF8Bytes
            )
        }
        return DockRecentTasksCanonicalResource(url: canonicalURL, key: canonicalURL.path)
    }

    private static func pairTitle(
        _ left: URL,
        _ right: URL,
        limits: DockRecentTasksLimits,
        work: inout DockRecentTasksWork
    ) throws -> String {
        let componentLimit = Swift.max(4, (limits.maximumTitleUTF8Bytes - 5) / 2)
        let leftName = try safeLabel(
            leafValue(left),
            maximumUTF8Bytes: componentLimit,
            work: &work
        )
        let rightName = try safeLabel(
            leafValue(right),
            maximumUTF8Bytes: componentLimit,
            work: &work
        )
        return try safeLabel(
            "\(leftName) and \(rightName)",
            maximumUTF8Bytes: limits.maximumTitleUTF8Bytes,
            work: &work
        )
    }

    private static func leafName(
        _ url: URL,
        limits: DockRecentTasksLimits,
        work: inout DockRecentTasksWork
    ) throws -> String {
        try safeLabel(
            leafValue(url),
            maximumUTF8Bytes: limits.maximumTitleUTF8Bytes,
            work: &work
        )
    }

    private static func leafValue(_ url: URL) -> String {
        let value = url.lastPathComponent
        return value.isEmpty ? "Root" : value
    }

    private static func safeLabel(
        _ value: String,
        maximumUTF8Bytes: Int,
        work: inout DockRecentTasksWork
    ) throws -> String {
        var pieces: [String] = []
        pieces.reserveCapacity(Swift.min(value.count, maximumUTF8Bytes))
        var byteCount = 0
        var truncated = false
        for character in value {
            try work.charge(character.utf8.count)
            let piece =
                character.unicodeScalars.allSatisfy { safeDisplayScalar($0) }
                ? String(character)
                : "?"
            let pieceBytes = piece.utf8.count
            guard byteCount <= maximumUTF8Bytes - pieceBytes else {
                truncated = true
                break
            }
            pieces.append(piece)
            byteCount += pieceBytes
        }
        if truncated {
            while byteCount > maximumUTF8Bytes - 3, let removed = pieces.popLast() {
                byteCount -= removed.utf8.count
            }
            pieces.append("...")
        }
        let result = pieces.joined()
        return result.isEmpty ? "Unnamed" : result
    }

    private static func safeDisplayScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator:
            return false
        default:
            return !scalar.properties.isDefaultIgnorableCodePoint
        }
    }

    private static func boundedUTF8Count(
        _ value: String,
        maximum: Int,
        work: inout DockRecentTasksWork
    ) throws -> Int? {
        var count = 0
        for _ in value.utf8 {
            guard count < maximum else { return nil }
            count += 1
            try work.charge(1)
        }
        return count
    }
}

private struct DockRecentTasksCanonicalResource {
    let url: URL
    let key: String
}

private struct DockRecentTasksWork {
    private static let cancellationInterval = 4 * 1_024

    let maximum: Int
    private var completed = 0
    private var workSinceCancellationCheck = 0

    init(maximum: Int) {
        self.maximum = maximum
    }

    mutating func charge(_ amount: Int) throws {
        guard amount >= 0, completed <= maximum, amount <= maximum - completed else {
            throw DockRecentTasksError.workLimitExceeded(maximumWork: maximum)
        }
        completed += amount
        workSinceCancellationCheck += amount
        if workSinceCancellationCheck >= Self.cancellationInterval {
            workSinceCancellationCheck %= Self.cancellationInterval
            try Task.checkCancellation()
        }
    }
}
