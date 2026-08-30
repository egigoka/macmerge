/// UI-independent command state for native comparison windows and tabs.
///
/// Callers provide an immutable, lineage- and generation-stamped snapshot in stable window-cycle order.
/// Resolution never mutates that snapshot; it returns an ordered plan that a platform layer may
/// execute only after revalidating the exact snapshot fingerprint.
public enum ComparisonWindowCommandState: Sendable {
    public struct WindowID: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: WindowID, right: WindowID) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public struct TabID: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: TabID, right: TabID) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    /// Stable identity of the owning window registry. A registry must retain its lineage across
    /// generations and allocate a new lineage before generation numbers can be reused.
    public struct SnapshotLineage: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: SnapshotLineage, right: SnapshotLineage) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public enum Identifier: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
        /// Closes every comparison tab in reverse window-cycle and right-to-left tab order.
        case closeAll
        /// Closes every tab except the selected tab in the key window.
        case closeOthers
        case closeLeft
        case closeRight
        case nextTab
        case previousTab
        case nextWindow
        case previousWindow
        case moveToNewWindow
        case mergeAllWindows
        case split
        case tile

        public static var closeAllWindows: Identifier { .closeAll }
        public static var closeOtherTabs: Identifier { .closeOthers }
        public static var closeTabsToLeft: Identifier { .closeLeft }
        public static var closeTabsToRight: Identifier { .closeRight }
        public static var selectNextTab: Identifier { .nextTab }
        public static var selectPreviousTab: Identifier { .previousTab }
        public static var selectNextWindow: Identifier { .nextWindow }
        public static var selectPreviousWindow: Identifier { .previousWindow }
        public static var moveSelectedTabToNewWindow: Identifier { .moveToNewWindow }
        public static var splitWindow: Identifier { .split }
        public static var tileWindows: Identifier { .tile }
    }

    public typealias Command = Identifier

    /// Semantic reason a window or document cannot participate in native tabbing.
    public enum TabbingIneligibilityReason: String, Codable, Equatable, Hashable, Sendable {
        case unsupportedContent
        case transientWindow
        case modalWorkflow
        case policyRestricted
    }

    public enum TabbingEligibility: Equatable, Hashable, Sendable {
        case eligible
        case ineligible(TabbingIneligibilityReason)

        public var isEligible: Bool {
            self == .eligible
        }

        public var ineligibilityReason: TabbingIneligibilityReason? {
            guard case .ineligible(let reason) = self else { return nil }
            return reason
        }
    }

    public struct TabState: Identifiable, Equatable, Hashable, Sendable {
        public let id: TabID
        public let isSelected: Bool
        public let isDirty: Bool
        /// True only when the owner currently refuses a close request. Dirty tabs that can
        /// present confirmation remain closable and are marked separately in close plans.
        public let isCloseVetoed: Bool
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility

        public init(
            id: TabID,
            isSelected: Bool = false,
            isDirty: Bool = false,
            isCloseVetoed: Bool = false,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible
        ) {
            self.id = id
            self.isSelected = isSelected
            self.isDirty = isDirty
            self.isCloseVetoed = isCloseVetoed
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }

        public var isEligibleForTabbing: Bool { tabbingEligibility.isEligible }
    }

    public struct WindowState: Identifiable, Equatable, Hashable, Sendable {
        public let id: WindowID
        /// Tabs are stored in visual left-to-right order.
        public let tabs: [TabState]
        public let isKey: Bool
        public let isMinimized: Bool
        public let isFullScreen: Bool
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility

        public init(
            id: WindowID,
            tabs: [TabState],
            isKey: Bool = false,
            isMinimized: Bool = false,
            isFullScreen: Bool = false,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible
        ) {
            self.id = id
            self.tabs = tabs
            self.isKey = isKey
            self.isMinimized = isMinimized
            self.isFullScreen = isFullScreen
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }

        public var selectedTab: TabState? {
            tabs.first(where: \.isSelected)
        }

        public var selectedTabID: TabID? { selectedTab?.id }
        public var isDirty: Bool { tabs.contains(where: \.isDirty) }
        public var isCloseVetoed: Bool { tabs.contains(where: \.isCloseVetoed) }
        public var isEligibleForTabbing: Bool { tabbingEligibility.isEligible }
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let `default` = Limits()

        public let maximumWindowCount: Int
        public let maximumTabsPerWindow: Int
        public let maximumTotalTabCount: Int
        public let maximumWorkUnits: Int
        public let maximumAggregateWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumWindowCount: Int = 256,
            maximumTabsPerWindow: Int = 256,
            maximumTotalTabCount: Int = 4_096,
            maximumWorkUnits: Int = 32_768,
            maximumAggregateWorkUnits: Int? = nil,
            cancellationCheckInterval: Int = 64
        ) {
            self.maximumWindowCount = maximumWindowCount
            self.maximumTabsPerWindow = maximumTabsPerWindow
            self.maximumTotalTabCount = maximumTotalTabCount
            self.maximumWorkUnits = maximumWorkUnits
            self.maximumAggregateWorkUnits =
                maximumAggregateWorkUnits
                ?? Self.derivedMaximumAggregateWorkUnits(
                    maximumWindowCount: maximumWindowCount,
                    maximumTotalTabCount: maximumTotalTabCount,
                    maximumWorkUnits: maximumWorkUnits
                )
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        /// A safe aggregate bound for resolving every current command. Each resolver performs at
        /// most two window passes and three tab passes, while its own work limit remains authoritative.
        public static func derivedMaximumAggregateWorkUnits(
            maximumWindowCount: Int,
            maximumTotalTabCount: Int,
            maximumWorkUnits: Int
        ) -> Int {
            let maximumShapeWork = saturatingAdd(
                saturatingMultiply(maximumWindowCount, by: 2),
                saturatingMultiply(maximumTotalTabCount, by: 3)
            )
            let commandCount = Identifier.allCases.count
            return min(
                saturatingMultiply(maximumShapeWork, by: commandCount),
                saturatingMultiply(maximumWorkUnits, by: commandCount)
            )
        }

        private static func saturatingAdd(_ left: Int, _ right: Int) -> Int {
            let (result, overflow) = left.addingReportingOverflow(right)
            return overflow ? Int.max : result
        }

        private static func saturatingMultiply(_ value: Int, by multiplier: Int) -> Int {
            let (result, overflow) = value.multipliedReportingOverflow(by: multiplier)
            return overflow ? Int.max : result
        }
    }

    public enum Limit: String, Equatable, Hashable, Sendable {
        case windows
        case tabsPerWindow
        case totalTabs
        case work
        case aggregateWork
        case cancellationCheckInterval
    }

    public enum StateError: Error, Equatable, Sendable {
        case invalidLimit(Limit, value: Int)
        case tooManyWindows(maximum: Int)
        case emptyWindow(WindowID)
        case tooManyTabs(windowID: WindowID, maximum: Int)
        case tooManyTotalTabs(maximum: Int)
        case duplicateWindowID(WindowID)
        case duplicateTabID(TabID)
        case invalidSelectedTabCount(windowID: WindowID, count: Int)
        case multipleKeyWindows(first: WindowID, second: WindowID)
        case keyWindowMinimized(WindowID)
        case contradictoryPresentationState(WindowID)
        case workLimitExceeded(maximum: Int)
        case cancelled
        case staleSnapshot(expected: SnapshotFingerprint, actual: SnapshotFingerprint)
        case commandDisabled(DisabledReason)
    }

    /// Exact structural identity used to reject plans from another registry, generation, or state.
    public struct SnapshotFingerprint: Equatable, Hashable, Sendable {
        public let lineage: SnapshotLineage
        public let generation: UInt64
        private let windows: [WindowState]
        private let limits: Limits

        fileprivate init(
            lineage: SnapshotLineage,
            generation: UInt64,
            windows: [WindowState],
            limits: Limits
        ) {
            self.lineage = lineage
            self.generation = generation
            self.windows = windows
            self.limits = limits
        }

        fileprivate func matches(
            _ snapshot: Snapshot,
            budget: inout WorkBudget
        ) throws -> Bool {
            guard lineage == snapshot.lineage,
                generation == snapshot.generation,
                limits == snapshot.limits,
                windows.count == snapshot.windows.count
            else {
                return false
            }

            for (expectedWindow, actualWindow) in zip(windows, snapshot.windows) {
                try budget.charge()
                guard expectedWindow.id == actualWindow.id,
                    expectedWindow.tabs.count == actualWindow.tabs.count,
                    expectedWindow.isKey == actualWindow.isKey,
                    expectedWindow.isMinimized == actualWindow.isMinimized,
                    expectedWindow.isFullScreen == actualWindow.isFullScreen,
                    expectedWindow.isRestorable == actualWindow.isRestorable,
                    expectedWindow.tabbingEligibility == actualWindow.tabbingEligibility
                else {
                    return false
                }

                for (expectedTab, actualTab) in zip(expectedWindow.tabs, actualWindow.tabs) {
                    try budget.charge()
                    guard expectedTab == actualTab else { return false }
                }
            }
            return true
        }
    }

    /// Validated immutable state. `windows` establishes deterministic next/previous order and
    /// must not be reordered when key-window z-order changes.
    public struct Snapshot: Equatable, Hashable, Sendable {
        public let lineage: SnapshotLineage
        public let generation: UInt64
        public let windows: [WindowState]
        public let keyWindowID: WindowID?
        public let totalTabCount: Int
        public let limits: Limits

        public init(
            lineage: SnapshotLineage,
            generation: UInt64,
            windows: [WindowState],
            limits: Limits = .default
        ) throws {
            try ComparisonWindowCommandState.checkCancellation()
            try Self.validate(limits)
            guard windows.count <= limits.maximumWindowCount else {
                throw StateError.tooManyWindows(maximum: limits.maximumWindowCount)
            }

            var budget = WorkBudget(limits: limits)
            var windowIDs: Set<WindowID> = []
            var tabIDs: Set<TabID> = []
            windowIDs.reserveCapacity(windows.count)
            tabIDs.reserveCapacity(min(limits.maximumTotalTabCount, 256))
            var keyWindowID: WindowID?
            var totalTabCount = 0

            for window in windows {
                try budget.charge()
                guard windowIDs.insert(window.id).inserted else {
                    throw StateError.duplicateWindowID(window.id)
                }
                guard !window.tabs.isEmpty else {
                    throw StateError.emptyWindow(window.id)
                }
                guard window.tabs.count <= limits.maximumTabsPerWindow else {
                    throw StateError.tooManyTabs(
                        windowID: window.id,
                        maximum: limits.maximumTabsPerWindow
                    )
                }
                guard totalTabCount <= limits.maximumTotalTabCount - window.tabs.count else {
                    throw StateError.tooManyTotalTabs(maximum: limits.maximumTotalTabCount)
                }
                totalTabCount += window.tabs.count

                if window.isMinimized && window.isFullScreen {
                    throw StateError.contradictoryPresentationState(window.id)
                }
                if window.isKey {
                    if let keyWindowID {
                        throw StateError.multipleKeyWindows(
                            first: keyWindowID,
                            second: window.id
                        )
                    }
                    guard !window.isMinimized else {
                        throw StateError.keyWindowMinimized(window.id)
                    }
                    keyWindowID = window.id
                }

                var selectedTabCount = 0
                for tab in window.tabs {
                    try budget.charge()
                    guard tabIDs.insert(tab.id).inserted else {
                        throw StateError.duplicateTabID(tab.id)
                    }
                    if tab.isSelected { selectedTabCount += 1 }
                }
                guard selectedTabCount == 1 else {
                    throw StateError.invalidSelectedTabCount(
                        windowID: window.id,
                        count: selectedTabCount
                    )
                }
            }
            try budget.finish()

            self.lineage = lineage
            self.generation = generation
            self.windows = windows
            self.keyWindowID = keyWindowID
            self.totalTabCount = totalTabCount
            self.limits = limits
        }

        public var keyWindow: WindowState? {
            guard let keyWindowID else { return nil }
            return windows.first { $0.id == keyWindowID }
        }

        public var fingerprint: SnapshotFingerprint {
            SnapshotFingerprint(
                lineage: lineage,
                generation: generation,
                windows: windows,
                limits: limits
            )
        }

        public var isEmpty: Bool { windows.isEmpty }
        public var dirtyTabIDs: [TabID] {
            windows.flatMap { $0.tabs.filter(\.isDirty).map(\.id) }
        }
        public var closeVetoedTabIDs: [TabID] {
            windows.flatMap { $0.tabs.filter(\.isCloseVetoed).map(\.id) }
        }
        public var nonRestorableWindowIDs: [WindowID] {
            windows.filter { !$0.isRestorable }.map(\.id)
        }
        public var nonRestorableTabIDs: [TabID] {
            windows.flatMap { $0.tabs.filter { !$0.isRestorable }.map(\.id) }
        }

        public func window(withID id: WindowID) -> WindowState? {
            windows.first { $0.id == id }
        }

        public func tab(withID id: TabID) -> TabState? {
            for window in windows {
                if let tab = window.tabs.first(where: { $0.id == id }) { return tab }
            }
            return nil
        }

        private static func validate(_ limits: Limits) throws {
            guard limits.maximumWindowCount > 0 else {
                throw StateError.invalidLimit(.windows, value: limits.maximumWindowCount)
            }
            guard limits.maximumTabsPerWindow > 0 else {
                throw StateError.invalidLimit(
                    .tabsPerWindow,
                    value: limits.maximumTabsPerWindow
                )
            }
            guard limits.maximumTotalTabCount > 0 else {
                throw StateError.invalidLimit(.totalTabs, value: limits.maximumTotalTabCount)
            }
            guard limits.maximumWorkUnits > 0 else {
                throw StateError.invalidLimit(.work, value: limits.maximumWorkUnits)
            }
            guard limits.maximumAggregateWorkUnits > 0 else {
                throw StateError.invalidLimit(
                    .aggregateWork,
                    value: limits.maximumAggregateWorkUnits
                )
            }
            guard limits.cancellationCheckInterval > 0 else {
                throw StateError.invalidLimit(
                    .cancellationCheckInterval,
                    value: limits.cancellationCheckInterval
                )
            }
        }
    }

    public typealias Context = Snapshot

    public enum MacOSAdaptation: String, Codable, Equatable, Hashable, Sendable {
        /// WinMerge MDI arrangement maps to native document windows and tab groups.
        case nativeDocumentWindowsAndTabs
    }

    public enum UnsupportedFeature: String, Codable, Equatable, Hashable, Sendable {
        /// A comparison already owns its pane layout; no separate MDI child split exists.
        case comparisonWindowSplit
    }

    public enum PlatformOutcome: Equatable, Hashable, Sendable {
        case native
        case macOSAdaptation(MacOSAdaptation)
        case unsupported(UnsupportedFeature)
    }

    public enum EnabledReason: Equatable, Hashable, Sendable {
        case closeTargets(
            targetCount: Int,
            dirtyTargetCount: Int,
            nonRestorableTargetCount: Int
        )
        case tabNavigation(target: TabID)
        case windowNavigation(target: WindowID)
        case moveToNewWindow(tabID: TabID)
        case mergeAllWindows(destination: WindowID, movedTabCount: Int)
        case macOSAdaptation(MacOSAdaptation)
    }

    public enum DisabledReason: Equatable, Hashable, Sendable {
        case noWindows
        case noKeyWindow
        case noOtherTabs
        case noTabsToLeft
        case noTabsToRight
        case noOtherWindows
        case windowLimitReached(maximum: Int)
        case tabLimitReached(windowID: WindowID, maximum: Int)
        case fullScreenWindow(WindowID)
        case windowTabbingIneligible(WindowID, TabbingIneligibilityReason)
        case tabTabbingIneligible(TabID, TabbingIneligibilityReason)
        case unsupportedCommand(Identifier)
    }

    public enum Availability: Equatable, Hashable, Sendable {
        case enabled
        case disabled(DisabledReason)

        public var isEnabled: Bool { self == .enabled }
        public var disabledReason: DisabledReason? {
            guard case .disabled(let reason) = self else { return nil }
            return reason
        }
    }

    public enum AvailabilityReason: Equatable, Hashable, Sendable {
        case enabled(EnabledReason)
        case disabled(DisabledReason)

        public var availability: Availability {
            switch self {
            case .enabled: .enabled
            case .disabled(let reason): .disabled(reason)
            }
        }
    }

    public struct CloseTarget: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let tabID: TabID
        public let isDirty: Bool
        public let isCloseVetoed: Bool
        public let isWindowRestorable: Bool
        public let isTabRestorable: Bool

        public var requiresConfirmation: Bool { isDirty }
        public var isFullyRestorable: Bool { isWindowRestorable && isTabRestorable }

        public init(
            windowID: WindowID,
            tabID: TabID,
            isDirty: Bool,
            isCloseVetoed: Bool,
            isWindowRestorable: Bool,
            isTabRestorable: Bool
        ) {
            self.windowID = windowID
            self.tabID = tabID
            self.isDirty = isDirty
            self.isCloseVetoed = isCloseVetoed
            self.isWindowRestorable = isWindowRestorable
            self.isTabRestorable = isTabRestorable
        }
    }

    public struct ClosePlan: Equatable, Hashable, Sendable {
        /// Request order. Snapshot veto flags are advisory prompt metadata; platform code must
        /// preserve every target and stop only when a close request actually returns a veto.
        public let targets: [CloseTarget]

        public var dirtyTargets: [CloseTarget] { targets.filter(\.isDirty) }
        public var vetoedTargets: [CloseTarget] { targets.filter(\.isCloseVetoed) }
        public var nonRestorableTargets: [CloseTarget] {
            targets.filter { !$0.isFullyRestorable }
        }

        public init(targets: [CloseTarget]) {
            self.targets = targets
        }
    }

    public struct TabNavigationPlan: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let sourceTabID: TabID
        public let targetTabID: TabID

        public init(windowID: WindowID, sourceTabID: TabID, targetTabID: TabID) {
            self.windowID = windowID
            self.sourceTabID = sourceTabID
            self.targetTabID = targetTabID
        }
    }

    public struct WindowNavigationPlan: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let targetWindowID: WindowID
        public let targetTabID: TabID
        public let restoresMinimizedWindow: Bool

        public init(
            sourceWindowID: WindowID,
            targetWindowID: WindowID,
            targetTabID: TabID,
            restoresMinimizedWindow: Bool
        ) {
            self.sourceWindowID = sourceWindowID
            self.targetWindowID = targetWindowID
            self.targetTabID = targetTabID
            self.restoresMinimizedWindow = restoresMinimizedWindow
        }
    }

    public struct MoveToNewWindowPlan: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        /// The owning registry must reserve the destination identity atomically during execution.
        /// Snapshot contents are observations and never an identity-allocation authority.
        public let destinationWindowIDAllocation: DestinationWindowIDAllocation
        public let tabID: TabID
        /// Deterministic source selection after detaching `tabID`.
        public let replacementSourceTabID: TabID
        public let isDirty: Bool
        public let isRestorable: Bool

        public init(
            sourceWindowID: WindowID,
            tabID: TabID,
            replacementSourceTabID: TabID,
            isDirty: Bool,
            isRestorable: Bool
        ) {
            self.sourceWindowID = sourceWindowID
            self.destinationWindowIDAllocation = .owningRegistry
            self.tabID = tabID
            self.replacementSourceTabID = replacementSourceTabID
            self.isDirty = isDirty
            self.isRestorable = isRestorable
        }
    }

    public enum DestinationWindowIDAllocation: Equatable, Hashable, Sendable {
        case owningRegistry
    }

    public struct WindowTabMove: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let tabIDs: [TabID]

        public init(sourceWindowID: WindowID, tabIDs: [TabID]) {
            self.sourceWindowID = sourceWindowID
            self.tabIDs = tabIDs
        }
    }

    public struct MergeAllWindowsPlan: Equatable, Hashable, Sendable {
        public let destinationWindowID: WindowID
        public let destinationSelectedTabID: TabID
        /// Sources follow stable snapshot window order; tabs remain left-to-right.
        public let sources: [WindowTabMove]
        /// Windows to restore before moving tabs, in stable snapshot order.
        public let restoreMinimizedWindowIDs: [WindowID]
        /// Final left-to-right tab order after appending every source to the destination.
        public let resultingTabOrder: [TabID]
        public let nonRestorableTabIDs: [TabID]

        public init(
            destinationWindowID: WindowID,
            destinationSelectedTabID: TabID,
            sources: [WindowTabMove],
            restoreMinimizedWindowIDs: [WindowID],
            resultingTabOrder: [TabID],
            nonRestorableTabIDs: [TabID]
        ) {
            self.destinationWindowID = destinationWindowID
            self.destinationSelectedTabID = destinationSelectedTabID
            self.sources = sources
            self.restoreMinimizedWindowIDs = restoreMinimizedWindowIDs
            self.resultingTabOrder = resultingTabOrder
            self.nonRestorableTabIDs = nonRestorableTabIDs
        }
    }

    public struct NativeWindowArrangementPlan: Equatable, Hashable, Sendable {
        /// Stable window order supplied by the snapshot.
        public let windowIDs: [WindowID]
        public let restoreMinimizedWindowIDs: [WindowID]

        public init(windowIDs: [WindowID], restoreMinimizedWindowIDs: [WindowID]) {
            self.windowIDs = windowIDs
            self.restoreMinimizedWindowIDs = restoreMinimizedWindowIDs
        }
    }

    public enum TargetPlan: Equatable, Hashable, Sendable {
        case none
        case close(ClosePlan)
        case navigateTab(TabNavigationPlan)
        case navigateWindow(WindowNavigationPlan)
        case moveToNewWindow(MoveToNewWindowPlan)
        case mergeAllWindows(MergeAllWindowsPlan)
        case nativeWindowArrangement(NativeWindowArrangementPlan)
    }

    public struct Plan: Equatable, Hashable, Sendable {
        public let command: Identifier
        public let expectedSnapshotFingerprint: SnapshotFingerprint
        public let target: TargetPlan
        public let platformOutcome: PlatformOutcome
        public let plannedWorkUnits: Int
        public let availabilityReason: AvailabilityReason

        fileprivate init(
            command: Identifier,
            expectedSnapshotFingerprint: SnapshotFingerprint,
            target: TargetPlan,
            platformOutcome: PlatformOutcome,
            plannedWorkUnits: Int,
            availabilityReason: AvailabilityReason
        ) {
            self.command = command
            self.expectedSnapshotFingerprint = expectedSnapshotFingerprint
            self.target = target
            self.platformOutcome = platformOutcome
            self.plannedWorkUnits = plannedWorkUnits
            self.availabilityReason = availabilityReason
        }

        public var expectedGeneration: UInt64 {
            expectedSnapshotFingerprint.generation
        }

        public func isCurrent(snapshot: Snapshot) throws -> Bool {
            try ComparisonWindowCommandState.checkCancellation()
            var budget = WorkBudget(limits: snapshot.limits)
            let matches = try expectedSnapshotFingerprint.matches(snapshot, budget: &budget)
            try budget.finish()
            return matches
        }

        public func validate(against snapshot: Snapshot) throws {
            try ComparisonWindowCommandState.checkCancellation()
            guard try isCurrent(snapshot: snapshot) else {
                throw StateError.staleSnapshot(
                    expected: expectedSnapshotFingerprint,
                    actual: snapshot.fingerprint
                )
            }
            if case .disabled(let reason) = availabilityReason {
                throw StateError.commandDisabled(reason)
            }
        }
    }

    public struct Resolution: Equatable, Hashable, Sendable {
        public let plan: Plan

        fileprivate init(plan: Plan) {
            self.plan = plan
        }

        public var command: Identifier { plan.command }
        public var expectedSnapshotFingerprint: SnapshotFingerprint {
            plan.expectedSnapshotFingerprint
        }
        public var expectedGeneration: UInt64 { plan.expectedGeneration }
        public var targetPlan: TargetPlan { plan.target }
        public var platformOutcome: PlatformOutcome { plan.platformOutcome }
        public var plannedWorkUnits: Int { plan.plannedWorkUnits }
        public var availabilityReason: AvailabilityReason { plan.availabilityReason }
        public var availability: Availability { availabilityReason.availability }
        public var isEnabled: Bool { availability.isEnabled }
        public var canExecute: Bool { isEnabled }
        public var disabledReason: DisabledReason? { availability.disabledReason }
        public var enabledReason: EnabledReason? {
            guard case .enabled(let reason) = availabilityReason else { return nil }
            return reason
        }

        public func validate(against snapshot: Snapshot) throws {
            try ComparisonWindowCommandState.checkCancellation()
            try plan.validate(against: snapshot)
        }
    }

    public static func resolve(
        _ command: Identifier,
        in snapshot: Snapshot
    ) throws -> Resolution {
        try checkCancellation()
        var budget = WorkBudget(limits: snapshot.limits)
        let resolution = try resolve(command, in: snapshot, budget: &budget)
        try budget.finish()
        return resolution
    }

    private static func resolve(
        _ command: Identifier,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Resolution {
        let startingWork = budget.completedWork
        let draft: ResolutionDraft

        switch command {
        case .closeAll:
            draft = try closeAll(in: snapshot, budget: &budget)
        case .closeOthers:
            draft = try closeRelative(
                .others,
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .closeLeft:
            draft = try closeRelative(
                .left,
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .closeRight:
            draft = try closeRelative(
                .right,
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .nextTab:
            draft = try navigateTab(
                forward: true,
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .previousTab:
            draft = try navigateTab(
                forward: false,
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .nextWindow:
            draft = try navigateWindow(
                forward: true,
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .previousWindow:
            draft = try navigateWindow(
                forward: false,
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .moveToNewWindow:
            draft = try moveToNewWindow(
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .mergeAllWindows:
            draft = try mergeAllWindows(
                command: command,
                in: snapshot,
                budget: &budget
            )
        case .split:
            draft = ResolutionDraft(
                target: .none,
                reason: .disabled(.unsupportedCommand(command)),
                platformOutcome: .unsupported(.comparisonWindowSplit)
            )
        case .tile:
            draft = try tile(command: command, in: snapshot, budget: &budget)
        }

        return Resolution(
            plan: Plan(
                command: command,
                expectedSnapshotFingerprint: snapshot.fingerprint,
                target: draft.target,
                platformOutcome: draft.platformOutcome,
                plannedWorkUnits: budget.completedWork - startingWork,
                availabilityReason: draft.reason
            )
        )
    }

    /// Commands resolve in stable `Identifier.allCases` order.
    public static func resolveAll(in snapshot: Snapshot) throws -> [Resolution] {
        try checkCancellation()
        var overallBudget = WorkBudget(
            maximumWork: snapshot.limits.maximumAggregateWorkUnits,
            cancellationCheckInterval: snapshot.limits.cancellationCheckInterval,
            maximumCommandWork: snapshot.limits.maximumWorkUnits
        )
        var resolutions: [Resolution] = []
        resolutions.reserveCapacity(Identifier.allCases.count)
        for command in Identifier.allCases {
            try checkCancellation()
            overallBudget.beginCommand()
            let resolution = try resolve(command, in: snapshot, budget: &overallBudget)
            try overallBudget.finish()
            resolutions.append(resolution)
        }
        try overallBudget.finish()
        return resolutions
    }

    public static func canExecute(
        _ command: Identifier,
        in snapshot: Snapshot
    ) throws -> Bool {
        try checkCancellation()
        return try resolve(command, in: snapshot).canExecute
    }

    public static func validate(_ plan: Plan, against snapshot: Snapshot) throws {
        try checkCancellation()
        try plan.validate(against: snapshot)
    }

    public static func validate(_ resolution: Resolution, against snapshot: Snapshot) throws {
        try checkCancellation()
        try resolution.validate(against: snapshot)
    }

    private enum RelativeClose {
        case others
        case left
        case right
    }

    private struct ResolutionDraft {
        let target: TargetPlan
        let reason: AvailabilityReason
        let platformOutcome: PlatformOutcome

        init(
            target: TargetPlan,
            reason: AvailabilityReason,
            platformOutcome: PlatformOutcome = .native
        ) {
            self.target = target
            self.reason = reason
            self.platformOutcome = platformOutcome
        }
    }

    private static func closeAll(
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        guard !snapshot.windows.isEmpty else {
            return ResolutionDraft(target: .close(ClosePlan(targets: [])), reason: .disabled(.noWindows))
        }

        var targets: [CloseTarget] = []
        targets.reserveCapacity(snapshot.totalTabCount)
        for window in snapshot.windows.reversed() {
            try budget.charge()
            for tab in window.tabs.reversed() {
                try budget.charge()
                targets.append(closeTarget(tab, in: window))
            }
        }
        return try closeDraft(targets: targets, budget: &budget)
    }

    private static func closeRelative(
        _ relativeClose: RelativeClose,
        command: Identifier,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        guard let window = try keyWindow(in: snapshot, budget: &budget) else {
            return ResolutionDraft(target: .close(ClosePlan(targets: [])), reason: noWindowReason(snapshot))
        }
        let selectedIndex = try selectedTabIndex(in: window, budget: &budget)

        let indices: Range<Int>
        let emptyReason: DisabledReason
        switch relativeClose {
        case .others:
            indices = window.tabs.indices
            emptyReason = .noOtherTabs
        case .left:
            indices = window.tabs.startIndex..<selectedIndex
            emptyReason = .noTabsToLeft
        case .right:
            indices = window.tabs.index(after: selectedIndex)..<window.tabs.endIndex
            emptyReason = .noTabsToRight
        }

        var targets: [CloseTarget] = []
        targets.reserveCapacity(indices.count)
        for index in indices.reversed() {
            try budget.charge()
            if command == .closeOthers && index == selectedIndex { continue }
            targets.append(closeTarget(window.tabs[index], in: window))
        }
        guard !targets.isEmpty else {
            return ResolutionDraft(
                target: .close(ClosePlan(targets: [])),
                reason: .disabled(emptyReason)
            )
        }
        return try closeDraft(targets: targets, budget: &budget)
    }

    private static func closeDraft(
        targets: [CloseTarget],
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        var dirtyTargetCount = 0
        var nonRestorableTargetCount = 0
        for target in targets {
            try budget.charge()
            if target.isDirty { dirtyTargetCount += 1 }
            if !target.isFullyRestorable { nonRestorableTargetCount += 1 }
        }
        let plan = ClosePlan(targets: targets)
        return ResolutionDraft(
            target: .close(plan),
            reason: .enabled(
                .closeTargets(
                    targetCount: targets.count,
                    dirtyTargetCount: dirtyTargetCount,
                    nonRestorableTargetCount: nonRestorableTargetCount
                )
            )
        )
    }

    private static func closeTarget(_ tab: TabState, in window: WindowState) -> CloseTarget {
        CloseTarget(
            windowID: window.id,
            tabID: tab.id,
            isDirty: tab.isDirty,
            isCloseVetoed: tab.isCloseVetoed,
            isWindowRestorable: window.isRestorable,
            isTabRestorable: tab.isRestorable
        )
    }

    private static func navigateTab(
        forward: Bool,
        command: Identifier,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        guard let window = try keyWindow(in: snapshot, budget: &budget) else {
            return ResolutionDraft(target: .none, reason: noWindowReason(snapshot))
        }
        guard window.tabs.count > 1 else {
            return ResolutionDraft(target: .none, reason: .disabled(.noOtherTabs))
        }
        let selectedIndex = try selectedTabIndex(in: window, budget: &budget)
        let sourceTabID = window.tabs[selectedIndex].id

        let targetIndex: Int
        if forward {
            targetIndex =
                window.tabs.index(after: selectedIndex) == window.tabs.endIndex
                ? window.tabs.startIndex
                : window.tabs.index(after: selectedIndex)
        } else {
            targetIndex =
                selectedIndex == window.tabs.startIndex
                ? window.tabs.index(before: window.tabs.endIndex)
                : window.tabs.index(before: selectedIndex)
        }
        let targetTabID = window.tabs[targetIndex].id
        return ResolutionDraft(
            target: .navigateTab(
                TabNavigationPlan(
                    windowID: window.id,
                    sourceTabID: sourceTabID,
                    targetTabID: targetTabID
                )
            ),
            reason: .enabled(.tabNavigation(target: targetTabID))
        )
    }

    private static func navigateWindow(
        forward: Bool,
        command: Identifier,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        guard let keyWindowID = snapshot.keyWindowID else {
            return ResolutionDraft(target: .none, reason: noWindowReason(snapshot))
        }
        guard snapshot.windows.count > 1 else {
            return ResolutionDraft(target: .none, reason: .disabled(.noOtherWindows))
        }

        let sourceIndex = try windowIndex(
            withID: keyWindowID,
            in: snapshot,
            budget: &budget
        )
        let targetIndex: Int
        if forward {
            targetIndex =
                snapshot.windows.index(after: sourceIndex) == snapshot.windows.endIndex
                ? snapshot.windows.startIndex
                : snapshot.windows.index(after: sourceIndex)
        } else {
            targetIndex =
                sourceIndex == snapshot.windows.startIndex
                ? snapshot.windows.index(before: snapshot.windows.endIndex)
                : snapshot.windows.index(before: sourceIndex)
        }
        let targetWindow = snapshot.windows[targetIndex]
        let targetTabIndex = try selectedTabIndex(in: targetWindow, budget: &budget)
        let targetTabID = targetWindow.tabs[targetTabIndex].id
        return ResolutionDraft(
            target: .navigateWindow(
                WindowNavigationPlan(
                    sourceWindowID: keyWindowID,
                    targetWindowID: targetWindow.id,
                    targetTabID: targetTabID,
                    restoresMinimizedWindow: targetWindow.isMinimized
                )
            ),
            reason: .enabled(.windowNavigation(target: targetWindow.id))
        )
    }

    private static func moveToNewWindow(
        command: Identifier,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        guard let window = try keyWindow(in: snapshot, budget: &budget) else {
            return ResolutionDraft(target: .none, reason: noWindowReason(snapshot))
        }
        guard window.tabs.count > 1 else {
            return ResolutionDraft(target: .none, reason: .disabled(.noOtherTabs))
        }
        guard snapshot.windows.count < snapshot.limits.maximumWindowCount else {
            return ResolutionDraft(
                target: .none,
                reason: .disabled(
                    .windowLimitReached(maximum: snapshot.limits.maximumWindowCount)
                )
            )
        }
        if window.isFullScreen {
            return ResolutionDraft(
                target: .none,
                reason: .disabled(.fullScreenWindow(window.id))
            )
        }
        if let reason = window.tabbingEligibility.ineligibilityReason {
            return ResolutionDraft(
                target: .none,
                reason: .disabled(.windowTabbingIneligible(window.id, reason))
            )
        }
        let selectedIndex = try selectedTabIndex(in: window, budget: &budget)
        let selectedTab = window.tabs[selectedIndex]
        if let reason = selectedTab.tabbingEligibility.ineligibilityReason {
            return ResolutionDraft(
                target: .none,
                reason: .disabled(.tabTabbingIneligible(selectedTab.id, reason))
            )
        }
        let replacementIndex =
            window.tabs.index(after: selectedIndex) == window.tabs.endIndex
            ? window.tabs.index(before: selectedIndex)
            : window.tabs.index(after: selectedIndex)
        let plan = MoveToNewWindowPlan(
            sourceWindowID: window.id,
            tabID: selectedTab.id,
            replacementSourceTabID: window.tabs[replacementIndex].id,
            isDirty: selectedTab.isDirty,
            isRestorable: window.isRestorable && selectedTab.isRestorable
        )
        return ResolutionDraft(
            target: .moveToNewWindow(plan),
            reason: .enabled(.moveToNewWindow(tabID: selectedTab.id))
        )
    }

    private static func mergeAllWindows(
        command: Identifier,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        guard let destination = try keyWindow(in: snapshot, budget: &budget) else {
            return ResolutionDraft(target: .none, reason: noWindowReason(snapshot))
        }
        guard snapshot.windows.count > 1 else {
            return ResolutionDraft(target: .none, reason: .disabled(.noOtherWindows))
        }
        if destination.isFullScreen {
            return ResolutionDraft(
                target: .none,
                reason: .disabled(.fullScreenWindow(destination.id))
            )
        }
        if let reason = destination.tabbingEligibility.ineligibilityReason {
            return ResolutionDraft(
                target: .none,
                reason: .disabled(.windowTabbingIneligible(destination.id, reason))
            )
        }
        guard snapshot.totalTabCount <= snapshot.limits.maximumTabsPerWindow else {
            return ResolutionDraft(
                target: .none,
                reason: .disabled(
                    .tabLimitReached(
                        windowID: destination.id,
                        maximum: snapshot.limits.maximumTabsPerWindow
                    )
                )
            )
        }

        var sources: [WindowTabMove] = []
        sources.reserveCapacity(snapshot.windows.count - 1)
        var restoreMinimizedWindowIDs: [WindowID] = []
        var destinationTabIDs: [TabID] = []
        destinationTabIDs.reserveCapacity(destination.tabs.count)
        var nonRestorableTabIDs: [TabID] = []
        var movedTabCount = 0

        for window in snapshot.windows {
            try budget.charge()
            if window.isFullScreen {
                return ResolutionDraft(
                    target: .none,
                    reason: .disabled(.fullScreenWindow(window.id))
                )
            }
            if let reason = window.tabbingEligibility.ineligibilityReason {
                return ResolutionDraft(
                    target: .none,
                    reason: .disabled(.windowTabbingIneligible(window.id, reason))
                )
            }
            if window.isMinimized { restoreMinimizedWindowIDs.append(window.id) }

            var tabIDs: [TabID] = []
            if window.id != destination.id { tabIDs.reserveCapacity(window.tabs.count) }
            for tab in window.tabs {
                try budget.charge()
                if let reason = tab.tabbingEligibility.ineligibilityReason {
                    return ResolutionDraft(
                        target: .none,
                        reason: .disabled(.tabTabbingIneligible(tab.id, reason))
                    )
                }
                if !window.isRestorable || !tab.isRestorable {
                    nonRestorableTabIDs.append(tab.id)
                }
                if window.id != destination.id {
                    tabIDs.append(tab.id)
                    movedTabCount += 1
                } else {
                    destinationTabIDs.append(tab.id)
                }
            }
            if window.id != destination.id {
                sources.append(WindowTabMove(sourceWindowID: window.id, tabIDs: tabIDs))
            }
        }
        let destinationSelectedTabIndex = try selectedTabIndex(
            in: destination,
            budget: &budget
        )
        let destinationSelectedTabID = destination.tabs[destinationSelectedTabIndex].id
        var resultingTabOrder = destinationTabIDs
        resultingTabOrder.reserveCapacity(snapshot.totalTabCount)
        for source in sources {
            for tabID in source.tabIDs {
                try budget.charge()
                resultingTabOrder.append(tabID)
            }
        }
        let plan = MergeAllWindowsPlan(
            destinationWindowID: destination.id,
            destinationSelectedTabID: destinationSelectedTabID,
            sources: sources,
            restoreMinimizedWindowIDs: restoreMinimizedWindowIDs,
            resultingTabOrder: resultingTabOrder,
            nonRestorableTabIDs: nonRestorableTabIDs
        )
        return ResolutionDraft(
            target: .mergeAllWindows(plan),
            reason: .enabled(
                .mergeAllWindows(
                    destination: destination.id,
                    movedTabCount: movedTabCount
                )
            )
        )
    }

    private static func tile(
        command: Identifier,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> ResolutionDraft {
        guard !snapshot.windows.isEmpty else {
            return ResolutionDraft(
                target: .nativeWindowArrangement(
                    NativeWindowArrangementPlan(
                        windowIDs: [],
                        restoreMinimizedWindowIDs: []
                    )
                ),
                reason: .disabled(.noWindows),
                platformOutcome: .macOSAdaptation(.nativeDocumentWindowsAndTabs)
            )
        }
        guard snapshot.windows.count > 1 else {
            try budget.charge()
            return ResolutionDraft(
                target: .nativeWindowArrangement(
                    NativeWindowArrangementPlan(
                        windowIDs: [snapshot.windows[0].id],
                        restoreMinimizedWindowIDs: []
                    )
                ),
                reason: .disabled(.noOtherWindows),
                platformOutcome: .macOSAdaptation(.nativeDocumentWindowsAndTabs)
            )
        }

        var windowIDs: [WindowID] = []
        var minimizedWindowIDs: [WindowID] = []
        windowIDs.reserveCapacity(snapshot.windows.count)
        for window in snapshot.windows {
            try budget.charge()
            if window.isFullScreen {
                return ResolutionDraft(
                    target: .none,
                    reason: .disabled(.fullScreenWindow(window.id)),
                    platformOutcome: .macOSAdaptation(.nativeDocumentWindowsAndTabs)
                )
            }
            windowIDs.append(window.id)
            if window.isMinimized { minimizedWindowIDs.append(window.id) }
        }
        return ResolutionDraft(
            target: .nativeWindowArrangement(
                NativeWindowArrangementPlan(
                    windowIDs: windowIDs,
                    restoreMinimizedWindowIDs: minimizedWindowIDs
                )
            ),
            reason: .enabled(.macOSAdaptation(.nativeDocumentWindowsAndTabs)),
            platformOutcome: .macOSAdaptation(.nativeDocumentWindowsAndTabs)
        )
    }

    private static func keyWindow(
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> WindowState? {
        guard let keyWindowID = snapshot.keyWindowID else { return nil }
        for window in snapshot.windows {
            try budget.charge()
            if window.id == keyWindowID { return window }
        }
        preconditionFailure("Validated snapshot has an unknown key window")
    }

    private static func windowIndex(
        withID id: WindowID,
        in snapshot: Snapshot,
        budget: inout WorkBudget
    ) throws -> Int {
        for index in snapshot.windows.indices {
            try budget.charge()
            if snapshot.windows[index].id == id { return index }
        }
        preconditionFailure("Validated snapshot has an unknown window")
    }

    private static func selectedTabIndex(
        in window: WindowState,
        budget: inout WorkBudget
    ) throws -> Int {
        for index in window.tabs.indices {
            try budget.charge()
            if window.tabs[index].isSelected { return index }
        }
        preconditionFailure("Validated snapshot has no selected tab")
    }

    private static func noWindowReason(_ snapshot: Snapshot) -> AvailabilityReason {
        snapshot.windows.isEmpty ? .disabled(.noWindows) : .disabled(.noKeyWindow)
    }

    private static func checkCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw StateError.cancelled
        }
    }

    fileprivate struct WorkBudget {
        let maximumWork: Int
        let cancellationCheckInterval: Int
        let maximumCommandWork: Int?
        private(set) var completedWork = 0
        private var completedCommandWork = 0
        private var workAtLastCancellationCheck = 0

        init(limits: Limits) {
            self.init(
                maximumWork: limits.maximumWorkUnits,
                cancellationCheckInterval: limits.cancellationCheckInterval,
                maximumCommandWork: nil
            )
        }

        init(
            maximumWork: Int,
            cancellationCheckInterval: Int,
            maximumCommandWork: Int?
        ) {
            self.maximumWork = maximumWork
            self.cancellationCheckInterval = cancellationCheckInterval
            self.maximumCommandWork = maximumCommandWork
        }

        mutating func beginCommand() {
            precondition(maximumCommandWork != nil)
            completedCommandWork = 0
        }

        mutating func charge(_ amount: Int = 1) throws {
            precondition(amount >= 0)
            if let maximumCommandWork,
                amount > maximumCommandWork
                    || completedCommandWork > maximumCommandWork - amount
            {
                try ComparisonWindowCommandState.checkCancellation()
                throw StateError.workLimitExceeded(maximum: maximumCommandWork)
            }
            if amount > maximumWork || completedWork > maximumWork - amount {
                try ComparisonWindowCommandState.checkCancellation()
                throw StateError.workLimitExceeded(maximum: maximumWork)
            }
            completedWork += amount
            completedCommandWork += amount
            if completedWork - workAtLastCancellationCheck >= cancellationCheckInterval {
                try ComparisonWindowCommandState.checkCancellation()
                workAtLastCancellationCheck = completedWork
            }
        }

        mutating func finish() throws {
            try ComparisonWindowCommandState.checkCancellation()
            workAtLastCancellationCheck = completedWork
        }
    }
}
