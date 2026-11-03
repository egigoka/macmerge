import Foundation

/// UI-independent routing from menu/editor three-way navigation commands to the
/// ``ThreeWayDifferenceNavigationIndex`` core.
///
/// Planning only: forwards caller-owned generations, identities, filters, limits, and
/// cancellation to the core and returns what the owner reveals. It never touches a menu,
/// editor, pane, or selection; enablement rendering, focus, and scrolling remain with the
/// future menu/editor executors, which own snapshots and advance generations.
public enum ThreeWayNavigationAdoption: Sendable {
    public typealias Index = ThreeWayDifferenceNavigationIndex
    public typealias Difference = ThreeWayDifferenceNavigationDifference
    public typealias Filter = ThreeWayDifferenceNavigationFilter
    public typealias Command = ThreeWayDifferenceNavigationCommand
    public typealias Context = ThreeWayDifferenceNavigationContext
    public typealias Target = ThreeWayDifferenceNavigationTarget
    public typealias Resolution = ThreeWayDifferenceNavigationResolution
    public typealias States = ThreeWayDifferenceNavigationCommandStates
    public typealias Limits = ThreeWayDifferenceNavigationLimits
    public typealias NavigationError = ThreeWayDifferenceNavigationError
    public typealias PanePair = ThreeWayDifferencePanePair
    public typealias OneSidedType = ThreeWayOneSidedDifferenceType

    /// Builds a generation-scoped index. The core validates limits, row ranges, identity
    /// uniqueness, deterministic order, and cancellation.
    public static func makeIndex(
        generation: UInt64,
        differences: [Difference],
        limits: Limits = .default
    ) throws(NavigationError) -> Index {
        if Task.isCancelled {
            throw NavigationError.cancelled
        }
        return try Index(generation: generation, differences: differences, limits: limits)
    }

    /// Filter matching exactly one pane pair (for example left/middle).
    public static func filter(for pair: PanePair) -> Filter {
        Filter.panePair(pair)
    }

    /// Filter matching exactly one one-sided type (for example middle-only).
    public static func filter(for oneSided: OneSidedType) -> Filter {
        Filter.oneSided(oneSided)
    }

    /// Filter matching an explicit type set. Rejects the empty set.
    public static func filter(
        forTypes types: Set<ThreeWayDifferenceType>
    ) throws(NavigationError) -> Filter {
        try Filter(types: types)
    }

    /// All ordered targets matching the filter.
    public static func targets(
        in index: Index,
        matching filter: Filter = .all
    ) throws(NavigationError) -> [Target] {
        if Task.isCancelled {
            throw NavigationError.cancelled
        }
        return try index.targets(matching: filter)
    }

    /// Routes one command. Never wraps: past either end resolves to `nil`.
    public static func resolve(
        _ command: Command,
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> Resolution {
        if Task.isCancelled {
            throw NavigationError.cancelled
        }
        return try index.resolve(command, in: context, matching: filter)
    }

    public static func first(
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> Target? {
        try resolve(.first, in: index, context: context, matching: filter).target
    }

    public static func current(
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> Target? {
        try resolve(.current, in: index, context: context, matching: filter).target
    }

    public static func previous(
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> Target? {
        try resolve(.previous, in: index, context: context, matching: filter).target
    }

    public static func next(
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> Target? {
        try resolve(.next, in: index, context: context, matching: filter).target
    }

    public static func last(
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> Target? {
        try resolve(.last, in: index, context: context, matching: filter).target
    }

    /// Derives menu/editor enablement for all five commands in one pass.
    public static func commandStates(
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> States {
        if Task.isCancelled {
            throw NavigationError.cancelled
        }
        return try index.commandStates(in: context, matching: filter)
    }

    /// Derives enablement for a single command with one resolution.
    public static func isEnabled(
        _ command: Command,
        in index: Index,
        context: Context,
        matching filter: Filter = .all
    ) throws(NavigationError) -> Bool {
        try resolve(command, in: index, context: context, matching: filter).canExecute
    }
}
