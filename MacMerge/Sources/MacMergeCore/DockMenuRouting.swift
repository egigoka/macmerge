import Foundation

/// UI-independent routing over ``DockRecentTasksPlanner`` for Dock, recents, shortcut, and app surfaces.
///
/// Planning only: validates one immutable owner snapshot per call, delegates section planning
/// (file/folder/project/task kinds, capabilities, bookmark references, availability,
/// deduplication, redacted labels, stale generation, limits, cancellation) to
/// ``DockRecentTasksPlanner``, then projects the resulting plan into kind-grouped rows the
/// adopter renders. This file claims no `NSDockTile`, `NSMenu`, `NSRecentDocuments`,
/// key-equivalent delivery, bookmark resolution, or window routing: the app owns snapshots,
/// renders returned rows, resolves bookmark references through its own security-scoped store,
/// and dispatches returned intents through its existing open executor.
public enum DockMenuRouting: Sendable {
    public typealias Generation = DockRecentTasksGeneration
    public typealias Kind = DockRecentTaskKind
    public typealias Capability = DockRecentTaskCapability
    public typealias OriginSection = DockRecentMenuSectionKind

    /// Caller surface consuming a projected row. Advisory only; routing never presents UI.
    public enum InvocationKind: String, CaseIterable, Equatable, Hashable, Sendable {
        case dockMenu
        case recentsMenu
        case keyboardShortcut
        case appRouting
    }

    /// Immutable owner inputs for one deterministic routing pass.
    public struct Snapshot: Equatable, Sendable {
        public let generation: Generation
        public let recentComparisons: RecentComparisonPairs
        public let workspaceHistory: RecentWorkspaceHistory
        public let commonTasks: [RecentWorkspaceCommonTask]
        public let bookmarkBindings: [DockRecentBookmarkBinding]
        public let capabilities: Set<Capability>
        public let limits: DockRecentTasksLimits

        public init(
            generation: Generation,
            recentComparisons: RecentComparisonPairs = RecentComparisonPairs(),
            workspaceHistory: RecentWorkspaceHistory = RecentWorkspaceHistory(),
            commonTasks: [RecentWorkspaceCommonTask] = RecentWorkspaceCommonTask.allCases,
            bookmarkBindings: [DockRecentBookmarkBinding] = [],
            capabilities: Set<Capability> = [],
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

        fileprivate var request: DockRecentTasksRequest {
            DockRecentTasksRequest(
                generation: generation,
                recentComparisons: recentComparisons,
                workspaceHistory: workspaceHistory,
                commonTasks: commonTasks,
                bookmarkBindings: bookmarkBindings,
                capabilities: capabilities,
                limits: limits
            )
        }
    }

    /// Bounds for the routing projection. Planning bounds live in `DockRecentTasksLimits`;
    /// routing only caps how many enabled rows receive a stable shortcut index.
    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumShortcutItems = 9
        public static let `default` = Limits()

        public let maximumShortcutItems: Int

        public init(maximumShortcutItems: Int = hardMaximumShortcutItems) {
            self.maximumShortcutItems = maximumShortcutItems
        }

        fileprivate func validate() throws {
            guard
                maximumShortcutItems >= 0
                    && maximumShortcutItems <= Self.hardMaximumShortcutItems
            else {
                throw DockMenuRoutingError.invalidLimits
            }
        }
    }

    /// One planned row projected for Dock, recents, shortcut, and app surfaces.
    /// Labels are bounded leaf names only; URLs and bookmark bytes never appear here.
    public struct Row: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let item: DockRecentMenuItem
        public let origin: OriginSection
        public let shortcutIndex: Int?

        fileprivate init(item: DockRecentMenuItem, origin: OriginSection, shortcutIndex: Int?) {
            self.item = item
            self.origin = origin
            self.shortcutIndex = shortcutIndex
        }

        public var id: DockRecentTaskIdentity { item.id }
        public var kind: Kind { item.kind }
        public var label: DockRecentTaskLabel { item.label }
        public var isPinned: Bool { item.isPinned }
        public var availability: DockRecentTaskAvailability { item.availability }
        public var requiredCapabilities: Set<Capability> { item.requiredCapabilities }
        public var intent: DockRecentTaskIntent { item.intent }
        public var isEnabled: Bool { item.availability == .available }
        public var hasBookmarkReference: Bool {
            switch item.intent {
            case .compareFiles(let left, let right), .compareFolders(let left, let right):
                left.bookmark != nil || right.bookmark != nil
            case .openProject(let resource):
                resource.bookmark != nil
            case .performTask:
                false
            }
        }

        public var description: String {
            "DockMenuRouting.Row(\(kind.rawValue):<redacted>)"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "kind": kind.rawValue,
                    "origin": origin.rawValue,
                    "isEnabled": isEnabled,
                    "shortcutIndex": shortcutIndex as Any
                ],
                displayStyle: .struct
            )
        }
    }

    /// Kind-grouped rows in fixed file/folder/project/task order. Empty groups are omitted.
    public struct Section: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let kind: Kind
        public let rows: [Row]

        fileprivate init(kind: Kind, rows: [Row]) {
            self.kind = kind
            self.rows = rows
        }

        public var description: String {
            "DockMenuRouting.Section(kind: \(kind.rawValue), rowCount: \(rows.count))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: ["kind": kind.rawValue, "rowCount": rows.count],
                displayStyle: .struct
            )
        }
    }

    /// Generation-bound projection. The app renders sections and dispatches intents only
    /// after checking freshness against its current generation.
    public struct Presentation: Equatable, Hashable, Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let generation: Generation
        public let sections: [Section]
        public let duplicateIdentityCount: Int
        public let omittedItemCount: Int

        fileprivate init(
            generation: Generation,
            sections: [Section],
            duplicateIdentityCount: Int,
            omittedItemCount: Int
        ) {
            self.generation = generation
            self.sections = sections
            self.duplicateIdentityCount = duplicateIdentityCount
            self.omittedItemCount = omittedItemCount
        }

        public var rows: [Row] { sections.flatMap(\.rows) }
        public var wasTruncated: Bool { omittedItemCount > 0 }

        public func section(for kind: Kind) -> Section? {
            sections.first { $0.kind == kind }
        }

        public func row(for id: DockRecentTaskIdentity) -> Row? {
            rows.first { $0.id == id }
        }

        public func isCurrent(generation: Generation) -> Bool {
            self.generation == generation
        }

        public func requireCurrent(generation: Generation) throws {
            guard isCurrent(generation: generation) else {
                throw DockMenuRoutingError.staleGeneration(
                    expected: generation,
                    actual: self.generation
                )
            }
        }

        public var description: String {
            "DockMenuRouting.Presentation(generation: \(generation.rawValue), rowCount: \(rows.count))"
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "generation": generation.rawValue,
                    "rowCount": rows.count,
                    "duplicateIdentityCount": duplicateIdentityCount,
                    "omittedItemCount": omittedItemCount
                ],
                displayStyle: .struct
            )
        }
    }

    /// Plans the snapshot and projects it into kind-grouped rows with stable shortcut indices.
    /// Shortcut indices 1...N are assigned in plan order to the first N enabled rows.
    public static func plan(
        _ snapshot: Snapshot,
        expecting expectedGeneration: Generation? = nil,
        limits: Limits = .default
    ) throws -> Presentation {
        do {
            try Task.checkCancellation()
            try limits.validate()
            if let expectedGeneration, expectedGeneration != snapshot.generation {
                throw DockMenuRoutingError.staleGeneration(
                    expected: expectedGeneration,
                    actual: snapshot.generation
                )
            }
            let planned = try DockRecentTasksPlanner.plan(
                snapshot.request,
                expecting: expectedGeneration
            )
            try Task.checkCancellation()
            return project(planned, shortcutBudget: limits.maximumShortcutItems)
        } catch is CancellationError {
            throw DockMenuRoutingError.cancelled
        } catch let error as DockMenuRoutingError {
            throw error
        } catch let error as DockRecentTasksError {
            if error == .cancelled {
                throw DockMenuRoutingError.cancelled
            }
            throw DockMenuRoutingError.core(error)
        }
    }

    /// Resolves a 1-based shortcut index to its row. The app owns key-equivalent delivery.
    public static func shortcut(
        _ shortcutIndex: Int,
        in presentation: Presentation
    ) throws -> Row {
        do {
            try Task.checkCancellation()
            guard
                let row = presentation.rows.first(where: { $0.shortcutIndex == shortcutIndex })
            else {
                throw DockMenuRoutingError.unknownShortcut(shortcutIndex)
            }
            guard row.isEnabled else {
                throw DockMenuRoutingError.unavailableItem(row.id)
            }
            return row
        } catch is CancellationError {
            throw DockMenuRoutingError.cancelled
        }
    }

    /// Resolves a row identity to the app-routing intent. The app validates freshness,
    /// resolves bookmark references, and opens the comparison or performs the task.
    public static func appRoute(
        for id: DockRecentTaskIdentity,
        in presentation: Presentation
    ) throws -> DockRecentTaskIntent {
        do {
            try Task.checkCancellation()
            guard let row = presentation.row(for: id) else {
                throw DockMenuRoutingError.unknownItem
            }
            guard row.isEnabled else {
                throw DockMenuRoutingError.unavailableItem(id)
            }
            return row.intent
        } catch is CancellationError {
            throw DockMenuRoutingError.cancelled
        }
    }

    private static func project(
        _ planned: DockRecentTasksPlan,
        shortcutBudget: Int
    ) -> Presentation {
        var originByID: [DockRecentTaskIdentity: OriginSection] = [:]
        for section in planned.sections {
            for item in section.items {
                originByID[item.id] = section.kind
            }
        }
        var nextShortcut = 1
        var rowsByKind: [Kind: [Row]] = [:]
        for item in planned.items {
            let shortcutIndex: Int?
            if item.availability == .available, nextShortcut <= shortcutBudget {
                shortcutIndex = nextShortcut
                nextShortcut += 1
            } else {
                shortcutIndex = nil
            }
            // Dead code: items flatten sections above, origin always present.
            let row = Row(
                item: item,
                origin: originByID[item.id] ?? .recent,
                shortcutIndex: shortcutIndex
            )
            rowsByKind[item.kind, default: []].append(row)
        }
        let sections = Kind.allCases.compactMap { kind in
            rowsByKind[kind].map { Section(kind: kind, rows: $0) }
        }
        return Presentation(
            generation: planned.generation,
            sections: sections,
            duplicateIdentityCount: planned.duplicateIdentityCount,
            omittedItemCount: planned.omittedItemCount
        )
    }
}

public enum DockMenuRoutingError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case invalidLimits
    case staleGeneration(expected: DockRecentTasksGeneration, actual: DockRecentTasksGeneration)
    case unknownShortcut(Int)
    case unknownItem
    case unavailableItem(DockRecentTaskIdentity)
    case core(DockRecentTasksError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Dock menu routing was cancelled."
        case .invalidLimits:
            "Dock menu routing limits are invalid."
        case .staleGeneration:
            "Dock menu routing generation is stale."
        case .unknownShortcut(let index):
            "No Dock menu row uses shortcut \(index)."
        case .unknownItem:
            "The Dock menu row is no longer in the plan."
        case .unavailableItem:
            "The Dock menu row is currently unavailable."
        case .core(let error):
            error.localizedDescription
        }
    }
}
