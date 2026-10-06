import Foundation

/// Bounded, UI-independent lifecycle planning for native comparison windows and tabs.
///
/// This model owns no AppKit objects and performs no persistence or document materialization.
/// Callers retain authority over comparison content, native windows, close confirmation, and
/// restoration. Plans are pure values bound to an exact state CAS; an executor must satisfy the
/// declared contracts before replacing owner state with a plan's deterministic successor.
public enum ComparisonTabLifecycle: Sendable {
    public typealias WindowID = ComparisonWindowCommandState.WindowID
    public typealias TabID = ComparisonWindowCommandState.TabID
    public typealias SessionLineage = ComparisonWindowCommandState.SnapshotLineage
    public typealias TabbingEligibility = ComparisonWindowCommandState.TabbingEligibility
    public typealias CancellationCheck = @Sendable () throws -> Void

    public struct SessionRevision: Equatable, Hashable, Sendable {
        public let lineage: SessionLineage
        public let generation: UInt64

        public init(lineage: SessionLineage, generation: UInt64) {
            self.lineage = lineage
            self.generation = generation
        }

        fileprivate func advanced() throws -> SessionRevision {
            guard generation < UInt64.max else {
                throw ComparisonTabLifecycleError.sessionRevisionExhausted(lineage)
            }
            return SessionRevision(lineage: lineage, generation: generation + 1)
        }
    }

    /// Exact revision of one window and its tab order, selection, and tab metadata.
    public struct WindowRevision: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let generation: UInt64

        public init(windowID: WindowID, generation: UInt64) {
            self.windowID = windowID
            self.generation = generation
        }

        fileprivate func advanced() throws -> WindowRevision {
            guard generation < UInt64.max else {
                throw ComparisonTabLifecycleError.windowRevisionExhausted(windowID)
            }
            return WindowRevision(windowID: windowID, generation: generation + 1)
        }
    }

    public struct MaterializationID: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: MaterializationID, right: MaterializationID) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    /// Opaque owner-issued identity for materialized comparison content. No content is retained.
    public struct MaterializationReference: Equatable, Hashable, Sendable {
        public let identity: MaterializationID
        public let revision: UInt64

        public init(identity: MaterializationID, revision: UInt64) {
            self.identity = identity
            self.revision = revision
        }
    }

    /// Stable identity of the owner that exclusively publishes restoration results. Independent
    /// owners must never reuse an identity while an earlier publication token can remain live.
    public struct RestorationOwnerID: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: RestorationOwnerID, right: RestorationOwnerID) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    /// Exact owner/epoch transition required to publish one restoration result.
    public struct RestorationPublicationCAS: Equatable, Hashable, Sendable {
        public let ownerID: RestorationOwnerID
        public let expectedEpoch: UInt64
        public let successorEpoch: UInt64

        public init(ownerID: RestorationOwnerID, expectedEpoch: UInt64) throws {
            guard expectedEpoch < UInt64.max else {
                throw ComparisonTabLifecycleError.restorationPublicationEpochExhausted(ownerID)
            }
            self.ownerID = ownerID
            self.expectedEpoch = expectedEpoch
            successorEpoch = expectedEpoch + 1
        }

        public func matches(ownerID: RestorationOwnerID, epoch: UInt64) -> Bool {
            self.ownerID == ownerID && expectedEpoch == epoch
        }

        public func validate(ownerID: RestorationOwnerID, epoch: UInt64) throws {
            guard matches(ownerID: ownerID, epoch: epoch) else {
                throw ComparisonTabLifecycleError.staleRestorationPublication(
                    expectedOwnerID: self.ownerID,
                    expectedEpoch: expectedEpoch,
                    actualOwnerID: ownerID,
                    actualEpoch: epoch
                )
            }
        }
    }

    public enum CloseVetoReason: String, CaseIterable, Codable, Hashable, Sendable {
        case activeOperation
        case ownerRejected
        case policyRestricted
    }

    /// Snapshot close status is advisory. Executors still request current owner authorization.
    public enum CloseVeto: Equatable, Hashable, Sendable {
        case none
        case vetoed(CloseVetoReason)

        public var isVetoed: Bool {
            if case .vetoed = self { true } else { false }
        }

        public var reason: CloseVetoReason? {
            guard case .vetoed(let reason) = self else { return nil }
            return reason
        }
    }

    public struct TabState: Identifiable, Equatable, Hashable, Sendable {
        public let id: TabID
        public let title: String
        public let materialization: MaterializationReference
        public let isDirty: Bool
        public let closeVeto: CloseVeto
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility

        public var isCloseVetoed: Bool { closeVeto.isVetoed }
        public var requiresCloseConfirmation: Bool { isDirty }

        public init(
            id: TabID,
            title: String,
            materialization: MaterializationReference,
            isDirty: Bool = false,
            closeVeto: CloseVeto = .none,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible
        ) throws {
            self.id = id
            self.title = try ComparisonTabLifecycle.normalizedTitle(title)
            self.materialization = materialization
            self.isDirty = isDirty
            self.closeVeto = closeVeto
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }

        fileprivate init(
            validatedID id: TabID,
            title: String,
            materialization: MaterializationReference,
            isDirty: Bool,
            closeVeto: CloseVeto,
            isRestorable: Bool,
            tabbingEligibility: TabbingEligibility
        ) {
            self.id = id
            self.title = title
            self.materialization = materialization
            self.isDirty = isDirty
            self.closeVeto = closeVeto
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }
    }

    public struct WindowState: Identifiable, Equatable, Hashable, Sendable {
        public let id: WindowID
        public let revision: WindowRevision
        /// Stable visual left-to-right order.
        public let tabs: [TabState]
        public let selectedTabID: TabID
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility

        public var selectedTab: TabState? { tabs.first { $0.id == selectedTabID } }

        public init(
            id: WindowID,
            revision: WindowRevision,
            tabs: [TabState],
            selectedTabID: TabID,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible
        ) throws {
            try ComparisonTabLifecycle.checkTaskCancellation()
            guard revision.windowID == id else {
                throw ComparisonTabLifecycleError.windowRevisionIdentityMismatch(
                    expected: id,
                    actual: revision.windowID
                )
            }
            guard !tabs.isEmpty else {
                throw ComparisonTabLifecycleError.emptyWindow(id)
            }
            guard tabs.count <= Limits.hardMaximumTabsPerWindow else {
                throw ComparisonTabLifecycleError.tooManyTabs(
                    windowID: id,
                    maximum: Limits.hardMaximumTabsPerWindow
                )
            }
            var identifiers: Set<TabID> = []
            identifiers.reserveCapacity(tabs.count)
            var foundSelection = false
            for (offset, tab) in tabs.enumerated() {
                if offset % Limits.hardMaximumCancellationCheckInterval == 0 {
                    try ComparisonTabLifecycle.checkTaskCancellation()
                }
                guard identifiers.insert(tab.id).inserted else {
                    throw ComparisonTabLifecycleError.duplicateTabID(tab.id)
                }
                if tab.id == selectedTabID { foundSelection = true }
            }
            guard foundSelection else {
                throw ComparisonTabLifecycleError.selectedTabNotFound(
                    windowID: id,
                    tabID: selectedTabID
                )
            }
            self.id = id
            self.revision = revision
            self.tabs = tabs
            self.selectedTabID = selectedTabID
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }

        fileprivate init(
            validatedID id: WindowID,
            revision: WindowRevision,
            tabs: [TabState],
            selectedTabID: TabID,
            isRestorable: Bool,
            tabbingEligibility: TabbingEligibility
        ) {
            self.id = id
            self.revision = revision
            self.tabs = tabs
            self.selectedTabID = selectedTabID
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }
    }

    public enum TabWidthPreference: Equatable, Hashable, Sendable {
        case automatic
        case fixed(Double)

        public var fixedWidth: Double? {
            guard case .fixed(let width) = self else { return nil }
            return width
        }
    }

    public enum Limit: String, CaseIterable, Equatable, Hashable, Sendable {
        case windows
        case tabsPerWindow
        case totalTabs
        case restorationItems
        case titleUTF8Bytes
        case restorationCodeUTF8Bytes
        case restorationMessageUTF8Bytes
        case aggregateStringUTF8Bytes
        case tabWidthRange
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumWindowCount = 1_024
        public static let hardMaximumTabsPerWindow = 1_024
        public static let hardMaximumTotalTabCount = 16_384
        public static let hardMaximumRestorationItemCount = 16_384
        public static let hardMaximumTitleUTF8Bytes = 64 * 1_024
        public static let hardMaximumRestorationCodeUTF8Bytes = 1_024
        public static let hardMaximumRestorationMessageUTF8Bytes = 64 * 1_024
        public static let hardMaximumAggregateStringUTF8Bytes = 64 * 1_024 * 1_024
        public static let hardMinimumTabWidth = 24.0
        public static let hardMaximumTabWidth = 4_096.0
        public static let hardMaximumWorkUnits = 64 * 1_024 * 1_024
        public static let hardMaximumCancellationCheckInterval = 4_096
        public static let `default` = Limits()

        public let maximumWindowCount: Int
        public let maximumTabsPerWindow: Int
        public let maximumTotalTabCount: Int
        public let maximumRestorationItemCount: Int
        public let maximumTitleUTF8Bytes: Int
        public let maximumRestorationCodeUTF8Bytes: Int
        public let maximumRestorationMessageUTF8Bytes: Int
        public let maximumAggregateStringUTF8Bytes: Int
        public let minimumTabWidth: Double
        public let maximumTabWidth: Double
        public let maximumWorkUnits: Int
        public let cancellationCheckInterval: Int

        public init(
            maximumWindowCount: Int = 256,
            maximumTabsPerWindow: Int = 256,
            maximumTotalTabCount: Int = 4_096,
            maximumRestorationItemCount: Int = 4_096,
            maximumTitleUTF8Bytes: Int = 4 * 1_024,
            maximumRestorationCodeUTF8Bytes: Int = 256,
            maximumRestorationMessageUTF8Bytes: Int = 16 * 1_024,
            maximumAggregateStringUTF8Bytes: Int = 8 * 1_024 * 1_024,
            minimumTabWidth: Double = 72,
            maximumTabWidth: Double = 320,
            maximumWorkUnits: Int = 4 * 1_024 * 1_024,
            cancellationCheckInterval: Int = 1_024
        ) {
            self.maximumWindowCount = maximumWindowCount
            self.maximumTabsPerWindow = maximumTabsPerWindow
            self.maximumTotalTabCount = maximumTotalTabCount
            self.maximumRestorationItemCount = maximumRestorationItemCount
            self.maximumTitleUTF8Bytes = maximumTitleUTF8Bytes
            self.maximumRestorationCodeUTF8Bytes = maximumRestorationCodeUTF8Bytes
            self.maximumRestorationMessageUTF8Bytes = maximumRestorationMessageUTF8Bytes
            self.maximumAggregateStringUTF8Bytes = maximumAggregateStringUTF8Bytes
            self.minimumTabWidth = minimumTabWidth
            self.maximumTabWidth = maximumTabWidth
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (1...Self.hardMaximumWindowCount).contains(maximumWindowCount) else {
                throw ComparisonTabLifecycleError.invalidLimit(.windows)
            }
            guard (1...Self.hardMaximumTabsPerWindow).contains(maximumTabsPerWindow) else {
                throw ComparisonTabLifecycleError.invalidLimit(.tabsPerWindow)
            }
            guard (1...Self.hardMaximumTotalTabCount).contains(maximumTotalTabCount) else {
                throw ComparisonTabLifecycleError.invalidLimit(.totalTabs)
            }
            guard maximumTabsPerWindow <= maximumTotalTabCount else {
                throw ComparisonTabLifecycleError.invalidLimit(.tabsPerWindow)
            }
            guard
                (1...Self.hardMaximumRestorationItemCount).contains(maximumRestorationItemCount)
            else {
                throw ComparisonTabLifecycleError.invalidLimit(.restorationItems)
            }
            guard (1...Self.hardMaximumTitleUTF8Bytes).contains(maximumTitleUTF8Bytes) else {
                throw ComparisonTabLifecycleError.invalidLimit(.titleUTF8Bytes)
            }
            guard
                (1...Self.hardMaximumRestorationCodeUTF8Bytes).contains(
                    maximumRestorationCodeUTF8Bytes
                )
            else {
                throw ComparisonTabLifecycleError.invalidLimit(.restorationCodeUTF8Bytes)
            }
            guard
                (1...Self.hardMaximumRestorationMessageUTF8Bytes).contains(
                    maximumRestorationMessageUTF8Bytes
                )
            else {
                throw ComparisonTabLifecycleError.invalidLimit(.restorationMessageUTF8Bytes)
            }
            guard
                (1...Self.hardMaximumAggregateStringUTF8Bytes).contains(
                    maximumAggregateStringUTF8Bytes
                ),
                maximumAggregateStringUTF8Bytes >= maximumTitleUTF8Bytes,
                maximumAggregateStringUTF8Bytes >= maximumRestorationCodeUTF8Bytes,
                maximumAggregateStringUTF8Bytes >= maximumRestorationMessageUTF8Bytes
            else {
                throw ComparisonTabLifecycleError.invalidLimit(.aggregateStringUTF8Bytes)
            }
            guard minimumTabWidth.isFinite, maximumTabWidth.isFinite,
                minimumTabWidth >= Self.hardMinimumTabWidth,
                maximumTabWidth <= Self.hardMaximumTabWidth,
                minimumTabWidth <= maximumTabWidth
            else {
                throw ComparisonTabLifecycleError.invalidLimit(.tabWidthRange)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw ComparisonTabLifecycleError.invalidLimit(.workUnits)
            }
            guard
                (1...Self.hardMaximumCancellationCheckInterval).contains(
                    cancellationCheckInterval
                )
            else {
                throw ComparisonTabLifecycleError.invalidLimit(.cancellationCheckInterval)
            }
        }
    }

    /// Validated immutable owner state. Window order is stable native window-cycle order.
    public struct State: Equatable, Hashable, Sendable {
        public let revision: SessionRevision
        public let windows: [WindowState]
        public let selectedWindowID: WindowID?
        public let tabWidthPreference: TabWidthPreference
        public let limits: Limits
        public let totalTabCount: Int

        public var selectedWindow: WindowState? {
            guard let selectedWindowID else { return nil }
            return windows.first { $0.id == selectedWindowID }
        }

        public var selectedTab: TabState? { selectedWindow?.selectedTab }
        public var cas: StateCAS { StateCAS(state: self) }

        public init(
            revision: SessionRevision,
            windows: [WindowState],
            selectedWindowID: WindowID?,
            tabWidthPreference: TabWidthPreference = .automatic,
            limits: Limits = .default
        ) throws {
            var work = Work(
                limits: limits,
                cancellationCheck: {
                    try ComparisonTabLifecycle.checkTaskCancellation()
                })
            try work.checkCancellation()
            try limits.validate()
            try ComparisonTabLifecycle.validate(
                tabWidthPreference,
                limits: limits
            )
            guard windows.count <= limits.maximumWindowCount else {
                throw ComparisonTabLifecycleError.tooManyWindows(
                    maximum: limits.maximumWindowCount
                )
            }

            var windowIDs: Set<WindowID> = []
            var tabIDs: Set<TabID> = []
            windowIDs.reserveCapacity(windows.count)
            tabIDs.reserveCapacity(min(limits.maximumTotalTabCount, 256))
            var totalTabs = 0
            var totalStringBytes = 0

            for window in windows {
                try work.consume()
                guard windowIDs.insert(window.id).inserted else {
                    throw ComparisonTabLifecycleError.duplicateWindowID(window.id)
                }
                guard window.revision.windowID == window.id else {
                    throw ComparisonTabLifecycleError.windowRevisionIdentityMismatch(
                        expected: window.id,
                        actual: window.revision.windowID
                    )
                }
                guard !window.tabs.isEmpty else {
                    throw ComparisonTabLifecycleError.emptyWindow(window.id)
                }
                guard window.tabs.count <= limits.maximumTabsPerWindow else {
                    throw ComparisonTabLifecycleError.tooManyTabs(
                        windowID: window.id,
                        maximum: limits.maximumTabsPerWindow
                    )
                }
                guard totalTabs <= limits.maximumTotalTabCount - window.tabs.count else {
                    throw ComparisonTabLifecycleError.tooManyTotalTabs(
                        maximum: limits.maximumTotalTabCount
                    )
                }
                totalTabs += window.tabs.count
                var foundSelection = false
                for tab in window.tabs {
                    try work.consume()
                    guard tabIDs.insert(tab.id).inserted else {
                        throw ComparisonTabLifecycleError.duplicateTabID(tab.id)
                    }
                    if tab.id == window.selectedTabID { foundSelection = true }
                    let byteCount = try ComparisonTabLifecycle.validatedStringByteCount(
                        tab.title,
                        field: .title,
                        maximum: limits.maximumTitleUTF8Bytes,
                        allowsEmpty: false,
                        work: &work
                    )
                    guard
                        totalStringBytes <= limits.maximumAggregateStringUTF8Bytes - byteCount
                    else {
                        throw ComparisonTabLifecycleError.aggregateStringsTooLarge(
                            maximumUTF8Bytes: limits.maximumAggregateStringUTF8Bytes
                        )
                    }
                    totalStringBytes += byteCount
                }
                guard foundSelection else {
                    throw ComparisonTabLifecycleError.selectedTabNotFound(
                        windowID: window.id,
                        tabID: window.selectedTabID
                    )
                }
            }

            if windows.isEmpty {
                if let selectedWindowID {
                    throw ComparisonTabLifecycleError.selectedWindowNotFound(selectedWindowID)
                }
            } else {
                guard let selectedWindowID else {
                    throw ComparisonTabLifecycleError.missingSelectedWindow
                }
                guard windowIDs.contains(selectedWindowID) else {
                    throw ComparisonTabLifecycleError.selectedWindowNotFound(selectedWindowID)
                }
            }
            try work.finish()
            self.revision = revision
            self.windows = windows
            self.selectedWindowID = selectedWindowID
            self.tabWidthPreference = tabWidthPreference
            self.limits = limits
            totalTabCount = totalTabs
        }

        fileprivate init(
            validatedRevision revision: SessionRevision,
            windows: [WindowState],
            selectedWindowID: WindowID?,
            tabWidthPreference: TabWidthPreference,
            limits: Limits,
            totalTabCount: Int
        ) {
            self.revision = revision
            self.windows = windows
            self.selectedWindowID = selectedWindowID
            self.tabWidthPreference = tabWidthPreference
            self.limits = limits
            self.totalTabCount = totalTabCount
        }

        /// Adapter for existing menu/toolbar command-state resolution. Lifecycle planning does not
        /// duplicate next/previous window, arrangement, or command availability policy.
        public func commandStateSnapshot() throws -> ComparisonWindowCommandState.Snapshot {
            var work = Work(
                limits: limits,
                cancellationCheck: {
                    try ComparisonTabLifecycle.checkTaskCancellation()
                })
            try work.checkCancellation()
            let commandLimits = ComparisonWindowCommandState.Limits(
                maximumWindowCount: limits.maximumWindowCount,
                maximumTabsPerWindow: limits.maximumTabsPerWindow,
                maximumTotalTabCount: limits.maximumTotalTabCount,
                maximumWorkUnits: limits.maximumWorkUnits,
                cancellationCheckInterval: limits.cancellationCheckInterval
            )
            var commandWindows: [ComparisonWindowCommandState.WindowState] = []
            commandWindows.reserveCapacity(windows.count)
            for window in windows {
                try work.consume()
                var commandTabs: [ComparisonWindowCommandState.TabState] = []
                commandTabs.reserveCapacity(window.tabs.count)
                for tab in window.tabs {
                    try work.consume()
                    commandTabs.append(
                        ComparisonWindowCommandState.TabState(
                            id: tab.id,
                            isSelected: tab.id == window.selectedTabID,
                            isDirty: tab.isDirty,
                            isCloseVetoed: tab.isCloseVetoed,
                            isRestorable: tab.isRestorable,
                            tabbingEligibility: tab.tabbingEligibility
                        )
                    )
                }
                commandWindows.append(
                    ComparisonWindowCommandState.WindowState(
                        id: window.id,
                        tabs: commandTabs,
                        isKey: window.id == selectedWindowID,
                        isRestorable: window.isRestorable,
                        tabbingEligibility: window.tabbingEligibility
                    )
                )
            }
            try work.finish()
            return try ComparisonWindowCommandState.Snapshot(
                lineage: revision.lineage,
                generation: revision.generation,
                windows: commandWindows,
                limits: commandLimits
            )
        }
    }

    /// Collision-free CAS: public revisions aid diagnostics; private snapshot comparison also
    /// rejects callers that failed to advance a revision after changing structural state.
    public struct StateCAS: Equatable, Hashable, Sendable {
        public let sessionRevision: SessionRevision
        public let windowRevisions: [WindowRevision]
        fileprivate let snapshot: State

        fileprivate init(state: State) {
            sessionRevision = state.revision
            var revisions: [WindowRevision] = []
            revisions.reserveCapacity(state.windows.count)
            for window in state.windows { revisions.append(window.revision) }
            windowRevisions = revisions
            snapshot = state
        }

        public func matches(_ state: State) throws -> Bool {
            var work = Work(
                limits: state.limits,
                cancellationCheck: {
                    try ComparisonTabLifecycle.checkTaskCancellation()
                })
            let result = try matches(state, work: &work)
            try work.finish()
            return result
        }

        public func validate(_ state: State) throws {
            guard try matches(state) else {
                throw ComparisonTabLifecycleError.staleState(
                    expected: self,
                    actual: state.cas
                )
            }
        }

        fileprivate func matches(_ state: State, work: inout Work) throws -> Bool {
            guard sessionRevision == state.revision,
                snapshot.selectedWindowID == state.selectedWindowID,
                snapshot.tabWidthPreference == state.tabWidthPreference,
                snapshot.limits == state.limits,
                snapshot.totalTabCount == state.totalTabCount,
                snapshot.windows.count == state.windows.count
            else { return false }
            for (expectedWindow, actualWindow) in zip(snapshot.windows, state.windows) {
                try work.consume()
                guard expectedWindow.id == actualWindow.id,
                    expectedWindow.revision == actualWindow.revision,
                    expectedWindow.selectedTabID == actualWindow.selectedTabID,
                    expectedWindow.isRestorable == actualWindow.isRestorable,
                    expectedWindow.tabbingEligibility == actualWindow.tabbingEligibility,
                    expectedWindow.tabs.count == actualWindow.tabs.count
                else { return false }
                for (expectedTab, actualTab) in zip(expectedWindow.tabs, actualWindow.tabs) {
                    try work.consume()
                    guard expectedTab.id == actualTab.id,
                        expectedTab.materialization == actualTab.materialization,
                        expectedTab.isDirty == actualTab.isDirty,
                        expectedTab.closeVeto == actualTab.closeVeto,
                        expectedTab.isRestorable == actualTab.isRestorable,
                        expectedTab.tabbingEligibility == actualTab.tabbingEligibility,
                        try ComparisonTabLifecycle.stringsMatch(
                            expectedTab.title,
                            actualTab.title,
                            work: &work
                        )
                    else { return false }
                }
            }
            return true
        }
    }

    public enum CloseScope: String, CaseIterable, Codable, Hashable, Sendable {
        case current
        case others
        case left
        case right
    }

    /// Destination identity must be reserved by the owning registry before planning.
    public struct WindowReservation: Equatable, Hashable, Sendable {
        public let id: WindowID
        public let initialRevision: WindowRevision

        public init(id: WindowID, initialRevision: WindowRevision) throws {
            guard initialRevision.windowID == id else {
                throw ComparisonTabLifecycleError.windowRevisionIdentityMismatch(
                    expected: id,
                    actual: initialRevision.windowID
                )
            }
            guard initialRevision.generation == 0 else {
                throw ComparisonTabLifecycleError.invalidInitialWindowRevision(id)
            }
            self.id = id
            self.initialRevision = initialRevision
        }
    }

    public struct DetachRequest: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let tabID: TabID
        public let destination: WindowReservation

        public init(
            sourceWindowID: WindowID,
            tabID: TabID,
            destination: WindowReservation
        ) {
            self.sourceWindowID = sourceWindowID
            self.tabID = tabID
            self.destination = destination
        }
    }

    public struct MoveRequest: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let destinationWindowID: WindowID
        public let tabID: TabID
        /// Index in destination order after removing `tabID` when source and destination match.
        public let insertionIndex: Int
        public let selectsMovedTab: Bool

        public init(
            sourceWindowID: WindowID,
            destinationWindowID: WindowID,
            tabID: TabID,
            insertionIndex: Int,
            selectsMovedTab: Bool = true
        ) {
            self.sourceWindowID = sourceWindowID
            self.destinationWindowID = destinationWindowID
            self.tabID = tabID
            self.insertionIndex = insertionIndex
            self.selectsMovedTab = selectsMovedTab
        }
    }

    public enum Command: Equatable, Hashable, Sendable {
        case select(windowID: WindowID, tabID: TabID)
        case close(CloseScope)
        case setTabWidthPreference(TabWidthPreference)
        case detach(DetachRequest)
        case move(MoveRequest)
    }

    public struct CloseTarget: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let tabID: TabID
        public let materialization: MaterializationReference
        public let isDirty: Bool
        public let closeVeto: CloseVeto
        public let isRestorable: Bool

        public var requiresConfirmation: Bool { isDirty }
        public var isCloseVetoed: Bool { closeVeto.isVetoed }

        fileprivate init(window: WindowState, tab: TabState) {
            windowID = window.id
            tabID = tab.id
            materialization = tab.materialization
            isDirty = tab.isDirty
            closeVeto = tab.closeVeto
            isRestorable = window.isRestorable && tab.isRestorable
        }
    }

    public struct SelectionIntent: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let tabID: TabID
    }

    public struct CloseIntent: Equatable, Hashable, Sendable {
        public let scope: CloseScope
        /// Reverse visual order. Executor preflights every target before any owner-state mutation.
        public let targets: [CloseTarget]
    }

    public struct DetachIntent: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let destinationWindowID: WindowID
        public let tabID: TabID
        public let replacementSourceTabID: TabID
    }

    public struct MoveIntent: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let destinationWindowID: WindowID
        public let tabID: TabID
        public let destinationInsertionIndex: Int
        public let resultingSourceTabOrder: [TabID]
        public let resultingDestinationTabOrder: [TabID]
        public let resultingSourceSelection: TabID?
        public let resultingDestinationSelection: TabID
    }

    public enum Effect: Equatable, Hashable, Sendable {
        case selection(SelectionIntent)
        case close(CloseIntent)
        case tabWidthPreference(TabWidthPreference)
        case detach(DetachIntent)
        case move(MoveIntent)
    }

    public enum StateCASExecutionContract: String, Hashable, Sendable {
        case compareExactSnapshotThenReplaceOnce
    }

    public enum CloseExecutionContract: String, Hashable, Sendable {
        case authorizeAllTargetsBeforeAtomicStateReplacement
    }

    public enum MaterializationExecutionContract: String, Hashable, Sendable {
        case materializeNativeWindowWithoutOwningComparisonContent
    }

    public enum ExecutionCancellationContract: String, Hashable, Sendable {
        case cancellationBeforeMutationLeavesOwnerStateUnchanged
    }

    /// Mandatory boundary for platform integration. This module intentionally supplies no executor.
    public struct ExecutorContract: Equatable, Hashable, Sendable {
        public static let required = ExecutorContract()

        public let stateCAS = StateCASExecutionContract.compareExactSnapshotThenReplaceOnce
        public let closing =
            CloseExecutionContract.authorizeAllTargetsBeforeAtomicStateReplacement
        public let materialization =
            MaterializationExecutionContract.materializeNativeWindowWithoutOwningComparisonContent
        public let cancellation =
            ExecutionCancellationContract.cancellationBeforeMutationLeavesOwnerStateUnchanged

        public init() {}
    }

    public struct PlanningReceipt: Equatable, Hashable, Sendable {
        public let expectedStateCAS: StateCAS
        public let successorStateCAS: StateCAS
        public let effect: Effect

        fileprivate init(expectedStateCAS: StateCAS, successor: State, effect: Effect) {
            self.expectedStateCAS = expectedStateCAS
            successorStateCAS = successor.cas
            self.effect = effect
        }
    }

    public struct Plan: Equatable, Hashable, Sendable {
        public let command: Command
        public let expectedStateCAS: StateCAS
        public let effect: Effect
        public let successor: State
        public let receipt: PlanningReceipt
        public let workPerformed: Int
        public let executorContract: ExecutorContract

        fileprivate init(
            command: Command,
            expectedStateCAS: StateCAS,
            effect: Effect,
            successor: State,
            workPerformed: Int
        ) {
            self.command = command
            self.expectedStateCAS = expectedStateCAS
            self.effect = effect
            self.successor = successor
            receipt = PlanningReceipt(
                expectedStateCAS: expectedStateCAS,
                successor: successor,
                effect: effect
            )
            self.workPerformed = workPerformed
            executorContract = .required
        }

        public func validateCurrentState(_ state: State) throws {
            try expectedStateCAS.validate(state)
        }
    }

    public static func plan(
        _ command: Command,
        in state: State,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Plan {
        var work = Work(limits: state.limits, cancellationCheck: cancellationCheck)
        do {
            try work.checkCancellation()
            let draft: Draft
            switch command {
            case .select(let windowID, let tabID):
                draft = try planSelection(
                    windowID: windowID,
                    tabID: tabID,
                    state: state,
                    work: &work
                )
            case .close(let scope):
                draft = try planClose(scope: scope, state: state, work: &work)
            case .setTabWidthPreference(let preference):
                draft = try planTabWidth(preference, state: state, work: &work)
            case .detach(let request):
                draft = try planDetach(request, state: state, work: &work)
            case .move(let request):
                draft = try planMove(request, state: state, work: &work)
            }
            try work.finish()
            return Plan(
                command: command,
                expectedStateCAS: state.cas,
                effect: draft.effect,
                successor: draft.successor,
                workPerformed: work.completed
            )
        } catch let error as ComparisonTabLifecycleError {
            throw error
        } catch {
            throw ComparisonTabLifecycleError.cancelled
        }
    }

    public struct RestorationTab: Equatable, Sendable {
        public let id: TabID
        public let title: String
        /// Already validated by `ComparisonSessionState`; this planner never encodes or persists it.
        public let sessionState: ComparisonSessionState
        public let isDirty: Bool
        public let closeVeto: CloseVeto
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility

        public init(
            id: TabID,
            title: String,
            sessionState: ComparisonSessionState,
            isDirty: Bool = false,
            closeVeto: CloseVeto = .none,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible
        ) throws {
            self.id = id
            self.title = try ComparisonTabLifecycle.normalizedTitle(title)
            self.sessionState = sessionState
            self.isDirty = isDirty
            self.closeVeto = closeVeto
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }
    }

    public struct RestorationWindow: Equatable, Sendable {
        public let id: WindowID
        public let revision: WindowRevision
        public let tabs: [RestorationTab]
        public let selectedTabID: TabID
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility

        public init(
            id: WindowID,
            revision: WindowRevision,
            tabs: [RestorationTab],
            selectedTabID: TabID,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible
        ) throws {
            guard revision.windowID == id else {
                throw ComparisonTabLifecycleError.windowRevisionIdentityMismatch(
                    expected: id,
                    actual: revision.windowID
                )
            }
            guard !tabs.isEmpty else {
                throw ComparisonTabLifecycleError.emptyWindow(id)
            }
            guard tabs.count <= Limits.hardMaximumTabsPerWindow else {
                throw ComparisonTabLifecycleError.tooManyTabs(
                    windowID: id,
                    maximum: Limits.hardMaximumTabsPerWindow
                )
            }
            var identifiers: Set<TabID> = []
            identifiers.reserveCapacity(tabs.count)
            var foundSelection = false
            for (offset, tab) in tabs.enumerated() {
                if offset % Limits.hardMaximumCancellationCheckInterval == 0 {
                    try ComparisonTabLifecycle.checkTaskCancellation()
                }
                guard identifiers.insert(tab.id).inserted else {
                    throw ComparisonTabLifecycleError.duplicateTabID(tab.id)
                }
                if tab.id == selectedTabID { foundSelection = true }
            }
            guard foundSelection else {
                throw ComparisonTabLifecycleError.selectedTabNotFound(
                    windowID: id,
                    tabID: selectedTabID
                )
            }
            self.id = id
            self.revision = revision
            self.tabs = tabs
            self.selectedTabID = selectedTabID
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
        }
    }

    public struct RestorationRequest: Equatable, Sendable {
        public let publicationCAS: RestorationPublicationCAS
        public let sessionRevision: SessionRevision
        public let windows: [RestorationWindow]
        public let selectedWindowID: WindowID?
        public let tabWidthPreference: TabWidthPreference
        public let limits: Limits

        public init(
            publicationCAS: RestorationPublicationCAS,
            sessionRevision: SessionRevision,
            windows: [RestorationWindow],
            selectedWindowID: WindowID?,
            tabWidthPreference: TabWidthPreference = .automatic,
            limits: Limits = .default
        ) {
            self.publicationCAS = publicationCAS
            self.sessionRevision = sessionRevision
            self.windows = windows
            self.selectedWindowID = selectedWindowID
            self.tabWidthPreference = tabWidthPreference
            self.limits = limits
        }
    }

    public enum RestorationMaterializationContract: String, Hashable, Sendable {
        case materializeValidatedSessionStateWithoutPersistenceOrUIAssumptions
    }

    public enum RestorationPublicationContract: String, Hashable, Sendable {
        case atomicallyCompareOwnerAndEpochThenPublishCanonicalReceiptOrderOnceAfterAllOutcomes
    }

    public struct MaterializationContract: Equatable, Hashable, Sendable {
        public static let required = MaterializationContract()

        public let materialization = RestorationMaterializationContract
            .materializeValidatedSessionStateWithoutPersistenceOrUIAssumptions
        public let publication = RestorationPublicationContract
            .atomicallyCompareOwnerAndEpochThenPublishCanonicalReceiptOrderOnceAfterAllOutcomes

        public init() {}
    }

    public struct MaterializationRequest: Equatable, Sendable {
        public let ordinal: Int
        public let expectedPublicationCAS: RestorationPublicationCAS
        public let expectedSessionRevision: SessionRevision
        public let expectedWindowRevision: WindowRevision
        public let windowID: WindowID
        public let tabID: TabID
        public let sessionState: ComparisonSessionState
        public let contract: MaterializationContract

        fileprivate init(
            publicationCAS: RestorationPublicationCAS,
            sessionRevision: SessionRevision,
            windowRevision: WindowRevision,
            windowID: WindowID,
            ordinal: Int,
            tab: RestorationTab
        ) {
            self.ordinal = ordinal
            expectedPublicationCAS = publicationCAS
            expectedSessionRevision = sessionRevision
            expectedWindowRevision = windowRevision
            self.windowID = windowID
            tabID = tab.id
            sessionState = tab.sessionState
            contract = .required
        }
    }

    public struct RestorationPlan: Equatable, Sendable {
        public let request: RestorationRequest
        /// Owner must atomically compare this token before publishing `restoredState`.
        public let publicationCAS: RestorationPublicationCAS
        /// Stable window order, then left-to-right tab order.
        public let materializations: [MaterializationRequest]
        /// Validated UTF-8 bytes retained by all tab titles in this plan.
        public let retainedStringUTF8Bytes: Int
        public let workPerformed: Int
        public let materializationContract: MaterializationContract

        fileprivate init(
            request: RestorationRequest,
            materializations: [MaterializationRequest],
            retainedStringUTF8Bytes: Int,
            workPerformed: Int
        ) {
            self.request = request
            publicationCAS = request.publicationCAS
            self.materializations = materializations
            self.retainedStringUTF8Bytes = retainedStringUTF8Bytes
            self.workPerformed = workPerformed
            materializationContract = .required
        }

        public func receipt(
            _ itemReceipts: [RestorationItemReceipt],
            cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
        ) throws -> RestorationReceipt {
            try ComparisonTabLifecycle.makeRestorationReceipt(
                plan: self,
                itemReceipts: itemReceipts,
                cancellationCheck: cancellationCheck
            )
        }
    }

    public enum RestorationSkipReason: String, CaseIterable, Hashable, Sendable {
        case userDeclined
        case unsupportedContent
        case unavailableSource
        case policyRestricted
    }

    public struct RestorationFailure: Equatable, Hashable, Sendable {
        public let code: String
        public let message: String
        public let isRetryable: Bool

        public init(code: String, message: String, isRetryable: Bool = false) throws {
            try ComparisonTabLifecycle.validateStandaloneRestorationMessage(message)
            let normalizedMessage = message.precomposedStringWithCanonicalMapping
            try ComparisonTabLifecycle.validateStandaloneFailureCode(code)
            try ComparisonTabLifecycle.validateStandaloneRestorationMessage(normalizedMessage)
            self.code = code
            self.message = normalizedMessage
            self.isRetryable = isRetryable
        }
    }

    public enum RestorationItemOutcome: Equatable, Hashable, Sendable {
        case restored(MaterializationReference)
        case skipped(RestorationSkipReason)
        case failed(RestorationFailure)
    }

    public struct RestorationItemReceipt: Equatable, Sendable {
        public let request: MaterializationRequest
        public let outcome: RestorationItemOutcome

        public var tabID: TabID { request.tabID }

        public init(request: MaterializationRequest, outcome: RestorationItemOutcome) {
            self.request = request
            self.outcome = outcome
        }
    }

    public struct WindowRestorationOutcome: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let restoredTabIDs: [TabID]
        public let skippedTabIDs: [TabID]
        public let failedTabIDs: [TabID]
        public let wasOmitted: Bool
    }

    public struct RestorationReceipt: Equatable, Sendable {
        public let plan: RestorationPlan
        /// Exact owner/epoch transition consumed by atomic publication of this receipt and state.
        public let publicationCAS: RestorationPublicationCAS
        /// Canonicalized to plan order, independent of executor return order.
        public let itemReceipts: [RestorationItemReceipt]
        public let windowOutcomes: [WindowRestorationOutcome]
        public let restoredState: State
        public let workPerformed: Int

        public var restoredTabIDs: [TabID] {
            itemReceipts.compactMap { receipt in
                if case .restored = receipt.outcome { receipt.tabID } else { nil }
            }
        }

        public var skippedTabIDs: [TabID] {
            itemReceipts.compactMap { receipt in
                if case .skipped = receipt.outcome { receipt.tabID } else { nil }
            }
        }

        public var failedTabIDs: [TabID] {
            itemReceipts.compactMap { receipt in
                if case .failed = receipt.outcome { receipt.tabID } else { nil }
            }
        }

        fileprivate init(
            plan: RestorationPlan,
            itemReceipts: [RestorationItemReceipt],
            windowOutcomes: [WindowRestorationOutcome],
            restoredState: State,
            workPerformed: Int
        ) {
            self.plan = plan
            publicationCAS = plan.publicationCAS
            self.itemReceipts = itemReceipts
            self.windowOutcomes = windowOutcomes
            self.restoredState = restoredState
            self.workPerformed = workPerformed
        }
    }

    public static func planRestoration(
        _ request: RestorationRequest,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> RestorationPlan {
        var work = Work(limits: request.limits, cancellationCheck: cancellationCheck)
        do {
            try work.checkCancellation()
            try request.limits.validate()
            try validate(request.tabWidthPreference, limits: request.limits)
            guard request.windows.count <= request.limits.maximumWindowCount else {
                throw ComparisonTabLifecycleError.tooManyWindows(
                    maximum: request.limits.maximumWindowCount
                )
            }

            var windowIDs: Set<WindowID> = []
            var tabIDs: Set<TabID> = []
            var materializations: [MaterializationRequest] = []
            var totalStringBytes = 0
            windowIDs.reserveCapacity(request.windows.count)
            materializations.reserveCapacity(
                min(request.limits.maximumRestorationItemCount, 256)
            )

            for window in request.windows {
                try work.consume()
                guard windowIDs.insert(window.id).inserted else {
                    throw ComparisonTabLifecycleError.duplicateWindowID(window.id)
                }
                guard window.revision.windowID == window.id else {
                    throw ComparisonTabLifecycleError.windowRevisionIdentityMismatch(
                        expected: window.id,
                        actual: window.revision.windowID
                    )
                }
                guard !window.tabs.isEmpty else {
                    throw ComparisonTabLifecycleError.emptyWindow(window.id)
                }
                guard window.tabs.count <= request.limits.maximumTabsPerWindow else {
                    throw ComparisonTabLifecycleError.tooManyTabs(
                        windowID: window.id,
                        maximum: request.limits.maximumTabsPerWindow
                    )
                }
                guard
                    materializations.count <= request.limits.maximumTotalTabCount
                        - window.tabs.count
                else {
                    throw ComparisonTabLifecycleError.tooManyTotalTabs(
                        maximum: request.limits.maximumTotalTabCount
                    )
                }
                guard
                    materializations.count <= request.limits.maximumRestorationItemCount
                        - window.tabs.count
                else {
                    throw ComparisonTabLifecycleError.tooManyRestorationItems(
                        maximum: request.limits.maximumRestorationItemCount
                    )
                }
                var foundSelection = false
                for tab in window.tabs {
                    try work.consume()
                    guard tabIDs.insert(tab.id).inserted else {
                        throw ComparisonTabLifecycleError.duplicateTabID(tab.id)
                    }
                    if tab.id == window.selectedTabID { foundSelection = true }
                    let byteCount = try validatedStringByteCount(
                        tab.title,
                        field: .title,
                        maximum: request.limits.maximumTitleUTF8Bytes,
                        allowsEmpty: false,
                        work: &work
                    )
                    guard
                        totalStringBytes <= request.limits.maximumAggregateStringUTF8Bytes
                            - byteCount
                    else {
                        throw ComparisonTabLifecycleError.aggregateStringsTooLarge(
                            maximumUTF8Bytes: request.limits.maximumAggregateStringUTF8Bytes
                        )
                    }
                    totalStringBytes += byteCount
                    materializations.append(
                        MaterializationRequest(
                            publicationCAS: request.publicationCAS,
                            sessionRevision: request.sessionRevision,
                            windowRevision: window.revision,
                            windowID: window.id,
                            ordinal: materializations.count,
                            tab: tab
                        )
                    )
                }
                guard foundSelection else {
                    throw ComparisonTabLifecycleError.selectedTabNotFound(
                        windowID: window.id,
                        tabID: window.selectedTabID
                    )
                }
            }

            if request.windows.isEmpty {
                if let selectedWindowID = request.selectedWindowID {
                    throw ComparisonTabLifecycleError.selectedWindowNotFound(selectedWindowID)
                }
            } else {
                guard let selectedWindowID = request.selectedWindowID else {
                    throw ComparisonTabLifecycleError.missingSelectedWindow
                }
                guard windowIDs.contains(selectedWindowID) else {
                    throw ComparisonTabLifecycleError.selectedWindowNotFound(selectedWindowID)
                }
            }
            try work.finish()
            return RestorationPlan(
                request: request,
                materializations: materializations,
                retainedStringUTF8Bytes: totalStringBytes,
                workPerformed: work.completed
            )
        } catch let error as ComparisonTabLifecycleError {
            throw error
        } catch {
            throw ComparisonTabLifecycleError.cancelled
        }
    }

    private struct Draft {
        let effect: Effect
        let successor: State
    }

    private enum StringField {
        case title
        case restorationCode
        case restorationMessage
    }

    private static func planSelection(
        windowID: WindowID,
        tabID: TabID,
        state: State,
        work: inout Work
    ) throws -> Draft {
        let windowIndex = try index(of: windowID, in: state, work: &work)
        let window = state.windows[windowIndex]
        _ = try tabIndex(of: tabID, in: window, work: &work)
        guard state.selectedWindowID != windowID || window.selectedTabID != tabID else {
            throw ComparisonTabLifecycleError.noStateChange
        }

        var windows = state.windows
        if window.selectedTabID != tabID {
            windows[windowIndex] = WindowState(
                validatedID: window.id,
                revision: try window.revision.advanced(),
                tabs: window.tabs,
                selectedTabID: tabID,
                isRestorable: window.isRestorable,
                tabbingEligibility: window.tabbingEligibility
            )
        }
        let successor = try successor(
            of: state,
            windows: windows,
            selectedWindowID: windowID,
            totalTabCount: state.totalTabCount
        )
        return Draft(
            effect: .selection(SelectionIntent(windowID: windowID, tabID: tabID)),
            successor: successor
        )
    }

    private static func planClose(
        scope: CloseScope,
        state: State,
        work: inout Work
    ) throws -> Draft {
        guard let selectedWindowID = state.selectedWindowID else {
            throw ComparisonTabLifecycleError.noSelectedWindow
        }
        let windowIndex = try index(of: selectedWindowID, in: state, work: &work)
        let window = state.windows[windowIndex]
        let selectedIndex = try tabIndex(
            of: window.selectedTabID,
            in: window,
            work: &work
        )
        let targetIndices: [Int]
        switch scope {
        case .current:
            targetIndices = [selectedIndex]
        case .others:
            var indices: [Int] = []
            indices.reserveCapacity(window.tabs.count - 1)
            for index in window.tabs.indices {
                try work.consume()
                if index != selectedIndex { indices.append(index) }
            }
            targetIndices = indices
        case .left:
            targetIndices = Array(window.tabs.startIndex..<selectedIndex)
        case .right:
            targetIndices = Array(window.tabs.index(after: selectedIndex)..<window.tabs.endIndex)
        }
        guard !targetIndices.isEmpty else {
            throw ComparisonTabLifecycleError.noCloseTargets(scope)
        }

        var targetSet: Set<Int> = []
        targetSet.reserveCapacity(targetIndices.count)
        for index in targetIndices {
            try work.consume()
            targetSet.insert(index)
        }
        var targets: [CloseTarget] = []
        targets.reserveCapacity(targetIndices.count)
        for index in targetIndices.reversed() {
            try work.consume()
            targets.append(CloseTarget(window: window, tab: window.tabs[index]))
        }
        var remaining: [TabState] = []
        remaining.reserveCapacity(window.tabs.count - targetIndices.count)
        for index in window.tabs.indices {
            try work.consume()
            if !targetSet.contains(index) { remaining.append(window.tabs[index]) }
        }

        var windows = state.windows
        let nextSelectedWindowID: WindowID?
        if remaining.isEmpty {
            windows.remove(at: windowIndex)
            if windows.isEmpty {
                nextSelectedWindowID = nil
            } else {
                nextSelectedWindowID = windows[min(windowIndex, windows.count - 1)].id
            }
        } else {
            let selection: TabID
            var retainedSelection = false
            for tab in remaining {
                try work.consume()
                if tab.id == window.selectedTabID { retainedSelection = true }
            }
            if retainedSelection {
                selection = window.selectedTabID
            } else {
                selection = remaining[min(selectedIndex, remaining.count - 1)].id
            }
            windows[windowIndex] = WindowState(
                validatedID: window.id,
                revision: try window.revision.advanced(),
                tabs: remaining,
                selectedTabID: selection,
                isRestorable: window.isRestorable,
                tabbingEligibility: window.tabbingEligibility
            )
            nextSelectedWindowID = selectedWindowID
        }
        let successor = try successor(
            of: state,
            windows: windows,
            selectedWindowID: nextSelectedWindowID,
            totalTabCount: state.totalTabCount - targets.count
        )
        return Draft(
            effect: .close(CloseIntent(scope: scope, targets: targets)),
            successor: successor
        )
    }

    private static func planTabWidth(
        _ preference: TabWidthPreference,
        state: State,
        work: inout Work
    ) throws -> Draft {
        try work.consume()
        try validate(preference, limits: state.limits)
        guard preference != state.tabWidthPreference else {
            throw ComparisonTabLifecycleError.noStateChange
        }
        let successor = State(
            validatedRevision: try state.revision.advanced(),
            windows: state.windows,
            selectedWindowID: state.selectedWindowID,
            tabWidthPreference: preference,
            limits: state.limits,
            totalTabCount: state.totalTabCount
        )
        return Draft(effect: .tabWidthPreference(preference), successor: successor)
    }

    private static func planDetach(
        _ request: DetachRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        guard state.windows.count < state.limits.maximumWindowCount else {
            throw ComparisonTabLifecycleError.tooManyWindows(
                maximum: state.limits.maximumWindowCount
            )
        }
        guard request.destination.initialRevision.windowID == request.destination.id,
            request.destination.initialRevision.generation == 0
        else {
            throw ComparisonTabLifecycleError.invalidInitialWindowRevision(
                request.destination.id
            )
        }
        for window in state.windows {
            try work.consume()
            guard window.id != request.destination.id else {
                throw ComparisonTabLifecycleError.duplicateWindowID(request.destination.id)
            }
        }
        let sourceIndex = try index(of: request.sourceWindowID, in: state, work: &work)
        let source = state.windows[sourceIndex]
        let sourceTabIndex = try tabIndex(of: request.tabID, in: source, work: &work)
        guard source.tabs.count > 1 else {
            throw ComparisonTabLifecycleError.onlyTabCannotDetach(request.tabID)
        }
        try validateTabbing(window: source, tabIndex: sourceTabIndex)
        let tab = source.tabs[sourceTabIndex]
        var sourceTabs = source.tabs
        sourceTabs.remove(at: sourceTabIndex)
        let replacement = sourceTabs[min(sourceTabIndex, sourceTabs.count - 1)].id
        let sourceWindow = WindowState(
            validatedID: source.id,
            revision: try source.revision.advanced(),
            tabs: sourceTabs,
            selectedTabID: source.selectedTabID == tab.id ? replacement : source.selectedTabID,
            isRestorable: source.isRestorable,
            tabbingEligibility: source.tabbingEligibility
        )
        let destinationWindow = WindowState(
            validatedID: request.destination.id,
            revision: request.destination.initialRevision,
            tabs: [tab],
            selectedTabID: tab.id,
            isRestorable: source.isRestorable,
            tabbingEligibility: source.tabbingEligibility
        )
        var windows = state.windows
        windows[sourceIndex] = sourceWindow
        windows.insert(destinationWindow, at: sourceIndex + 1)
        let successor = try successor(
            of: state,
            windows: windows,
            selectedWindowID: destinationWindow.id,
            totalTabCount: state.totalTabCount
        )
        return Draft(
            effect: .detach(
                DetachIntent(
                    sourceWindowID: source.id,
                    destinationWindowID: destinationWindow.id,
                    tabID: tab.id,
                    replacementSourceTabID: sourceWindow.selectedTabID
                )
            ),
            successor: successor
        )
    }

    private static func planMove(
        _ request: MoveRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        let sourceIndex = try index(of: request.sourceWindowID, in: state, work: &work)
        let destinationIndex = try index(
            of: request.destinationWindowID,
            in: state,
            work: &work
        )
        let source = state.windows[sourceIndex]
        let destination = state.windows[destinationIndex]
        let sourceTabIndex = try tabIndex(of: request.tabID, in: source, work: &work)
        try validateTabbing(window: source, tabIndex: sourceTabIndex)
        if source.id != destination.id,
            let reason = destination.tabbingEligibility.ineligibilityReason
        {
            throw ComparisonTabLifecycleError.windowTabbingIneligible(destination.id, reason)
        }
        let movedTab = source.tabs[sourceTabIndex]

        if source.id == destination.id {
            var tabs = source.tabs
            tabs.remove(at: sourceTabIndex)
            guard (0...tabs.count).contains(request.insertionIndex) else {
                throw ComparisonTabLifecycleError.invalidInsertionIndex(
                    request.insertionIndex,
                    windowID: destination.id
                )
            }
            tabs.insert(movedTab, at: request.insertionIndex)
            let selection = request.selectsMovedTab ? movedTab.id : source.selectedTabID
            var orderChanged = tabs.count != source.tabs.count
            if !orderChanged {
                for (actual, previous) in zip(tabs, source.tabs) {
                    try work.consume()
                    if actual.id != previous.id { orderChanged = true }
                }
            }
            guard orderChanged || selection != source.selectedTabID else {
                throw ComparisonTabLifecycleError.noStateChange
            }
            var windows = state.windows
            windows[sourceIndex] = WindowState(
                validatedID: source.id,
                revision: try source.revision.advanced(),
                tabs: tabs,
                selectedTabID: selection,
                isRestorable: source.isRestorable,
                tabbingEligibility: source.tabbingEligibility
            )
            let selectedWindowID = request.selectsMovedTab ? source.id : state.selectedWindowID
            let successor = try successor(
                of: state,
                windows: windows,
                selectedWindowID: selectedWindowID,
                totalTabCount: state.totalTabCount
            )
            var order: [TabID] = []
            order.reserveCapacity(tabs.count)
            for tab in tabs {
                try work.consume()
                order.append(tab.id)
            }
            return Draft(
                effect: .move(
                    MoveIntent(
                        sourceWindowID: source.id,
                        destinationWindowID: destination.id,
                        tabID: movedTab.id,
                        destinationInsertionIndex: request.insertionIndex,
                        resultingSourceTabOrder: order,
                        resultingDestinationTabOrder: order,
                        resultingSourceSelection: selection,
                        resultingDestinationSelection: selection
                    )
                ),
                successor: successor
            )
        }

        guard destination.tabs.count < state.limits.maximumTabsPerWindow else {
            throw ComparisonTabLifecycleError.tooManyTabs(
                windowID: destination.id,
                maximum: state.limits.maximumTabsPerWindow
            )
        }
        guard (0...destination.tabs.count).contains(request.insertionIndex) else {
            throw ComparisonTabLifecycleError.invalidInsertionIndex(
                request.insertionIndex,
                windowID: destination.id
            )
        }
        var sourceTabs = source.tabs
        sourceTabs.remove(at: sourceTabIndex)
        var destinationTabs = destination.tabs
        destinationTabs.insert(movedTab, at: request.insertionIndex)
        let destinationSelection =
            request.selectsMovedTab
            ? movedTab.id : destination.selectedTabID
        let sourceSelection: TabID? =
            sourceTabs.isEmpty
            ? nil
            : (source.selectedTabID == movedTab.id
                ? sourceTabs[min(sourceTabIndex, sourceTabs.count - 1)].id
                : source.selectedTabID)

        var windows = state.windows
        let updatedDestination = WindowState(
            validatedID: destination.id,
            revision: try destination.revision.advanced(),
            tabs: destinationTabs,
            selectedTabID: destinationSelection,
            isRestorable: destination.isRestorable,
            tabbingEligibility: destination.tabbingEligibility
        )
        if sourceTabs.isEmpty {
            windows.remove(at: sourceIndex)
            let adjustedDestinationIndex =
                sourceIndex < destinationIndex
                ? destinationIndex - 1 : destinationIndex
            windows[adjustedDestinationIndex] = updatedDestination
        } else {
            guard let sourceSelection else {
                throw ComparisonTabLifecycleError.missingSourceSelection(source.id)
            }
            windows[sourceIndex] = WindowState(
                validatedID: source.id,
                revision: try source.revision.advanced(),
                tabs: sourceTabs,
                selectedTabID: sourceSelection,
                isRestorable: source.isRestorable,
                tabbingEligibility: source.tabbingEligibility
            )
            windows[destinationIndex] = updatedDestination
        }
        let selectedWindowID: WindowID?
        if request.selectsMovedTab || (sourceTabs.isEmpty && state.selectedWindowID == source.id) {
            selectedWindowID = destination.id
        } else {
            selectedWindowID = state.selectedWindowID
        }
        let successor = try successor(
            of: state,
            windows: windows,
            selectedWindowID: selectedWindowID,
            totalTabCount: state.totalTabCount
        )
        var resultingSourceOrder: [TabID] = []
        resultingSourceOrder.reserveCapacity(sourceTabs.count)
        for tab in sourceTabs {
            try work.consume()
            resultingSourceOrder.append(tab.id)
        }
        var resultingDestinationOrder: [TabID] = []
        resultingDestinationOrder.reserveCapacity(destinationTabs.count)
        for tab in destinationTabs {
            try work.consume()
            resultingDestinationOrder.append(tab.id)
        }
        return Draft(
            effect: .move(
                MoveIntent(
                    sourceWindowID: source.id,
                    destinationWindowID: destination.id,
                    tabID: movedTab.id,
                    destinationInsertionIndex: request.insertionIndex,
                    resultingSourceTabOrder: resultingSourceOrder,
                    resultingDestinationTabOrder: resultingDestinationOrder,
                    resultingSourceSelection: sourceSelection,
                    resultingDestinationSelection: destinationSelection
                )
            ),
            successor: successor
        )
    }

    private static func makeRestorationReceipt(
        plan: RestorationPlan,
        itemReceipts: [RestorationItemReceipt],
        cancellationCheck: @escaping CancellationCheck
    ) throws -> RestorationReceipt {
        var work = Work(limits: plan.request.limits, cancellationCheck: cancellationCheck)
        do {
            try work.checkCancellation()
            guard itemReceipts.count == plan.materializations.count else {
                throw ComparisonTabLifecycleError.restorationReceiptCountMismatch(
                    expected: plan.materializations.count,
                    actual: itemReceipts.count
                )
            }
            var byTabID: [TabID: RestorationItemReceipt] = [:]
            byTabID.reserveCapacity(itemReceipts.count)
            var expectedRequests: [TabID: MaterializationRequest] = [:]
            expectedRequests.reserveCapacity(plan.materializations.count)
            for materialization in plan.materializations {
                try work.consume()
                expectedRequests[materialization.tabID] = materialization
            }
            var aggregateStringBytes = plan.retainedStringUTF8Bytes
            for receipt in itemReceipts {
                try work.consume()
                guard let expected = expectedRequests[receipt.tabID],
                    expected.ordinal == receipt.request.ordinal,
                    expected.expectedPublicationCAS
                        == receipt.request.expectedPublicationCAS,
                    expected.expectedPublicationCAS == plan.publicationCAS,
                    expected.expectedSessionRevision
                        == receipt.request.expectedSessionRevision,
                    expected.expectedWindowRevision == receipt.request.expectedWindowRevision,
                    expected.windowID == receipt.request.windowID,
                    expected.tabID == receipt.request.tabID,
                    try restorationSessionsMatch(
                        expected.sessionState,
                        receipt.request.sessionState,
                        work: &work
                    )
                else {
                    throw ComparisonTabLifecycleError.unknownRestorationReceipt(receipt.tabID)
                }
                guard byTabID.updateValue(receipt, forKey: receipt.tabID) == nil else {
                    throw ComparisonTabLifecycleError.duplicateRestorationReceipt(receipt.tabID)
                }
                if case .failed(let failure) = receipt.outcome {
                    let codeBytes = try validatedStringByteCount(
                        failure.code,
                        field: .restorationCode,
                        maximum: plan.request.limits.maximumRestorationCodeUTF8Bytes,
                        allowsEmpty: false,
                        work: &work
                    )
                    let messageBytes = try validatedStringByteCount(
                        failure.message,
                        field: .restorationMessage,
                        maximum: plan.request.limits.maximumRestorationMessageUTF8Bytes,
                        allowsEmpty: false,
                        work: &work
                    )
                    guard
                        aggregateStringBytes <= plan.request.limits.maximumAggregateStringUTF8Bytes
                            - codeBytes,
                        aggregateStringBytes + codeBytes
                            <= plan.request.limits.maximumAggregateStringUTF8Bytes - messageBytes
                    else {
                        throw ComparisonTabLifecycleError.aggregateStringsTooLarge(
                            maximumUTF8Bytes: plan.request.limits.maximumAggregateStringUTF8Bytes
                        )
                    }
                    aggregateStringBytes += codeBytes + messageBytes
                }
            }
            let orderedReceipts = try plan.materializations.map { materialization in
                try work.consume()
                guard let receipt = byTabID[materialization.tabID] else {
                    throw ComparisonTabLifecycleError.missingRestorationReceipt(
                        materialization.tabID
                    )
                }
                return receipt
            }

            var restoredWindows: [WindowState] = []
            var windowOutcomes: [WindowRestorationOutcome] = []
            var restoredTotalTabCount = 0
            var requestedWindowSelectionInsertionIndex: Int?
            restoredWindows.reserveCapacity(plan.request.windows.count)
            windowOutcomes.reserveCapacity(plan.request.windows.count)
            for requestedWindow in plan.request.windows {
                try work.consume()
                if requestedWindow.id == plan.request.selectedWindowID {
                    requestedWindowSelectionInsertionIndex = restoredWindows.count
                }
                var tabs: [TabState] = []
                var skipped: [TabID] = []
                var failed: [TabID] = []
                var requestedTabSelectionInsertionIndex: Int?
                tabs.reserveCapacity(requestedWindow.tabs.count)
                for requestedTab in requestedWindow.tabs {
                    try work.consume()
                    if requestedTab.id == requestedWindow.selectedTabID {
                        requestedTabSelectionInsertionIndex = tabs.count
                    }
                    guard let receipt = byTabID[requestedTab.id] else {
                        throw ComparisonTabLifecycleError.missingRestorationReceipt(
                            requestedTab.id
                        )
                    }
                    switch receipt.outcome {
                    case .restored(let materialization):
                        tabs.append(
                            TabState(
                                validatedID: requestedTab.id,
                                title: requestedTab.title,
                                materialization: materialization,
                                isDirty: requestedTab.isDirty,
                                closeVeto: requestedTab.closeVeto,
                                isRestorable: requestedTab.isRestorable,
                                tabbingEligibility: requestedTab.tabbingEligibility
                            )
                        )
                    case .skipped:
                        skipped.append(requestedTab.id)
                    case .failed:
                        failed.append(requestedTab.id)
                    }
                }
                var restoredIDs: [TabID] = []
                restoredIDs.reserveCapacity(tabs.count)
                var requestedSelectionWasRestored = false
                for tab in tabs {
                    try work.consume()
                    restoredIDs.append(tab.id)
                    if tab.id == requestedWindow.selectedTabID {
                        requestedSelectionWasRestored = true
                    }
                }
                if !tabs.isEmpty {
                    guard let requestedTabSelectionInsertionIndex else {
                        throw ComparisonTabLifecycleError.selectedTabNotFound(
                            windowID: requestedWindow.id,
                            tabID: requestedWindow.selectedTabID
                        )
                    }
                    let selectedTabID =
                        requestedSelectionWasRestored
                        ? requestedWindow.selectedTabID
                        : tabs[min(requestedTabSelectionInsertionIndex, tabs.count - 1)].id
                    let revision =
                        tabs.count == requestedWindow.tabs.count
                        ? requestedWindow.revision : try requestedWindow.revision.advanced()
                    restoredWindows.append(
                        WindowState(
                            validatedID: requestedWindow.id,
                            revision: revision,
                            tabs: tabs,
                            selectedTabID: selectedTabID,
                            isRestorable: requestedWindow.isRestorable,
                            tabbingEligibility: requestedWindow.tabbingEligibility
                        )
                    )
                    restoredTotalTabCount += tabs.count
                }
                windowOutcomes.append(
                    WindowRestorationOutcome(
                        windowID: requestedWindow.id,
                        restoredTabIDs: restoredIDs,
                        skippedTabIDs: skipped,
                        failedTabIDs: failed,
                        wasOmitted: tabs.isEmpty
                    )
                )
            }
            var restoredWindowIDs: Set<WindowID> = []
            restoredWindowIDs.reserveCapacity(restoredWindows.count)
            for window in restoredWindows {
                try work.consume()
                restoredWindowIDs.insert(window.id)
            }
            let selectedWindowID: WindowID?
            if let requestedSelection = plan.request.selectedWindowID,
                restoredWindowIDs.contains(requestedSelection)
            {
                selectedWindowID = requestedSelection
            } else if !restoredWindows.isEmpty,
                let requestedWindowSelectionInsertionIndex
            {
                selectedWindowID =
                    restoredWindows[
                        min(requestedWindowSelectionInsertionIndex, restoredWindows.count - 1)
                    ].id
            } else {
                selectedWindowID = nil
            }
            var hasPartialOutcome = false
            for receipt in orderedReceipts {
                try work.consume()
                if case .restored = receipt.outcome {} else { hasPartialOutcome = true }
            }
            let restoredRevision =
                hasPartialOutcome
                ? try plan.request.sessionRevision.advanced()
                : plan.request.sessionRevision
            let restoredState = State(
                validatedRevision: restoredRevision,
                windows: restoredWindows,
                selectedWindowID: selectedWindowID,
                tabWidthPreference: plan.request.tabWidthPreference,
                limits: plan.request.limits,
                totalTabCount: restoredTotalTabCount
            )
            try work.finish()
            return RestorationReceipt(
                plan: plan,
                itemReceipts: orderedReceipts,
                windowOutcomes: windowOutcomes,
                restoredState: restoredState,
                workPerformed: work.completed
            )
        } catch let error as ComparisonTabLifecycleError {
            throw error
        } catch {
            throw ComparisonTabLifecycleError.cancelled
        }
    }

    private static func successor(
        of state: State,
        windows: [WindowState],
        selectedWindowID: WindowID?,
        totalTabCount: Int
    ) throws -> State {
        State(
            validatedRevision: try state.revision.advanced(),
            windows: windows,
            selectedWindowID: selectedWindowID,
            tabWidthPreference: state.tabWidthPreference,
            limits: state.limits,
            totalTabCount: totalTabCount
        )
    }

    private static func index(
        of windowID: WindowID,
        in state: State,
        work: inout Work
    ) throws -> Int {
        for index in state.windows.indices {
            try work.consume()
            if state.windows[index].id == windowID { return index }
        }
        throw ComparisonTabLifecycleError.windowNotFound(windowID)
    }

    private static func tabIndex(
        of tabID: TabID,
        in window: WindowState,
        work: inout Work
    ) throws -> Int {
        for index in window.tabs.indices {
            try work.consume()
            if window.tabs[index].id == tabID { return index }
        }
        throw ComparisonTabLifecycleError.tabNotFound(tabID)
    }

    private static func validateTabbing(
        window: WindowState,
        tabIndex: Int
    ) throws {
        if let reason = window.tabbingEligibility.ineligibilityReason {
            throw ComparisonTabLifecycleError.windowTabbingIneligible(window.id, reason)
        }
        let tab = window.tabs[tabIndex]
        if let reason = tab.tabbingEligibility.ineligibilityReason {
            throw ComparisonTabLifecycleError.tabTabbingIneligible(tab.id, reason)
        }
    }

    private static func validate(
        _ preference: TabWidthPreference,
        limits: Limits
    ) throws {
        guard case .fixed(let width) = preference else { return }
        guard width.isFinite,
            width >= limits.minimumTabWidth,
            width <= limits.maximumTabWidth
        else {
            throw ComparisonTabLifecycleError.invalidTabWidth
        }
    }

    private static func normalizedTitle(_ title: String) throws -> String {
        var rawWork = Work(
            maximum: Limits.hardMaximumTitleUTF8Bytes * 2 + 2,
            cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval,
            cancellationCheck: { try checkTaskCancellation() }
        )
        _ = try validatedStringByteCount(
            title,
            field: .title,
            maximum: Limits.hardMaximumTitleUTF8Bytes,
            allowsEmpty: false,
            work: &rawWork
        )
        try rawWork.finish()
        let normalized = title.precomposedStringWithCanonicalMapping
        var work = Work(
            maximum: Limits.hardMaximumTitleUTF8Bytes * 2 + 2,
            cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval,
            cancellationCheck: { try checkTaskCancellation() }
        )
        _ = try validatedStringByteCount(
            normalized,
            field: .title,
            maximum: Limits.hardMaximumTitleUTF8Bytes,
            allowsEmpty: false,
            work: &work
        )
        try work.finish()
        return normalized
    }

    private static func validateStandaloneFailureCode(_ code: String) throws {
        guard !code.isEmpty else {
            throw ComparisonTabLifecycleError.invalidRestorationFailureCode
        }
        var count = 0
        for byte in code.utf8 {
            if count % Limits.hardMaximumCancellationCheckInterval == 0 {
                try checkTaskCancellation()
            }
            guard count < Limits.hardMaximumRestorationCodeUTF8Bytes else {
                throw ComparisonTabLifecycleError.restorationFailureCodeTooLarge(
                    maximumUTF8Bytes: Limits.hardMaximumRestorationCodeUTF8Bytes
                )
            }
            guard
                (0x30...0x39).contains(byte)
                    || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte)
                    || byte == 0x2D || byte == 0x2E || byte == 0x5F
            else {
                throw ComparisonTabLifecycleError.invalidRestorationFailureCode
            }
            count += 1
        }
    }

    private static func validateStandaloneRestorationMessage(_ message: String) throws {
        var work = Work(
            maximum: Limits.hardMaximumRestorationMessageUTF8Bytes * 2 + 2,
            cancellationCheckInterval: Limits.hardMaximumCancellationCheckInterval,
            cancellationCheck: { try checkTaskCancellation() }
        )
        _ = try validatedStringByteCount(
            message,
            field: .restorationMessage,
            maximum: Limits.hardMaximumRestorationMessageUTF8Bytes,
            allowsEmpty: false,
            work: &work
        )
        try work.finish()
    }

    private static func validatedStringByteCount(
        _ value: String,
        field: StringField,
        maximum: Int,
        allowsEmpty: Bool,
        work: inout Work
    ) throws -> Int {
        guard allowsEmpty || !value.isEmpty else {
            throw invalidStringError(field)
        }
        var byteCount = 0
        var hasNonWhitespace = allowsEmpty
        for _ in value.utf8 {
            guard byteCount < maximum else { throw stringLimitError(field, maximum: maximum) }
            byteCount += 1
            try work.consume()
        }
        for scalar in value.unicodeScalars {
            try work.consume()
            if !scalar.properties.isWhitespace { hasNonWhitespace = true }
            let raw = scalar.value
            guard raw != 0, raw >= 0x20 || raw == 0x09 || raw == 0x0A || raw == 0x0D,
                !(0x7F...0x9F).contains(raw)
            else {
                throw invalidStringError(field)
            }
        }
        guard hasNonWhitespace else { throw invalidStringError(field) }
        return byteCount
    }

    private static func stringsMatch(
        _ expected: String,
        _ actual: String,
        work: inout Work
    ) throws -> Bool {
        var expectedIterator = expected.utf8.makeIterator()
        var actualIterator = actual.utf8.makeIterator()
        while true {
            try work.consume()
            switch (expectedIterator.next(), actualIterator.next()) {
            case (nil, nil): return true
            case (let expectedByte?, let actualByte?):
                guard expectedByte == actualByte else { return false }
            default: return false
            }
        }
    }

    /// Compares exact canonical wire fields directly so variable-size work remains cancellable.
    private static func restorationSessionsMatch(
        _ expected: ComparisonSessionState,
        _ actual: ComparisonSessionState,
        work: inout Work
    ) throws -> Bool {
        try work.consume()
        guard expected.schemaVersion == actual.schemaVersion,
            expected.leftReadOnly == actual.leftReadOnly,
            expected.rightReadOnly == actual.rightReadOnly,
            expected.leftEncoding == actual.leftEncoding,
            expected.rightEncoding == actual.rightEncoding,
            expected.selectedRow == actual.selectedRow,
            expected.activeSide == actual.activeSide,
            expected.windowFrame.x.bitPattern == actual.windowFrame.x.bitPattern,
            expected.windowFrame.y.bitPattern == actual.windowFrame.y.bitPattern,
            expected.windowFrame.width.bitPattern == actual.windowFrame.width.bitPattern,
            expected.windowFrame.height.bitPattern == actual.windowFrame.height.bitPattern,
            expected.splitOrientation == actual.splitOrientation,
            expected.splitFraction.bitPattern == actual.splitFraction.bitPattern,
            expected.locationPaneVisible == actual.locationPaneVisible,
            expected.locationPaneWidth.bitPattern == actual.locationPaneWidth.bitPattern,
            try restorationSidesMatch(expected.left, actual.left, work: &work),
            try restorationSidesMatch(expected.right, actual.right, work: &work)
        else { return false }
        return true
    }

    private static func restorationSidesMatch(
        _ expected: ComparisonSessionState.SideIdentity,
        _ actual: ComparisonSessionState.SideIdentity,
        work: inout Work
    ) throws -> Bool {
        switch (expected, actual) {
        case (.file(let expectedURL), .file(let actualURL)):
            return try stringsMatch(
                expectedURL.absoluteString,
                actualURL.absoluteString,
                work: &work
            )
        case (.scratchpad(let expectedText), .scratchpad(let actualText)):
            return try stringsMatch(expectedText, actualText, work: &work)
        default:
            try work.consume()
            return false
        }
    }

    private static func invalidStringError(_ field: StringField) -> ComparisonTabLifecycleError {
        switch field {
        case .title: .invalidTitle
        case .restorationCode: .invalidRestorationFailureCode
        case .restorationMessage: .invalidRestorationFailureMessage
        }
    }

    private static func stringLimitError(
        _ field: StringField,
        maximum: Int
    ) -> ComparisonTabLifecycleError {
        switch field {
        case .title: .titleTooLarge(maximumUTF8Bytes: maximum)
        case .restorationCode: .restorationFailureCodeTooLarge(maximumUTF8Bytes: maximum)
        case .restorationMessage:
            .restorationFailureMessageTooLarge(maximumUTF8Bytes: maximum)
        }
    }

    fileprivate static func checkTaskCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw ComparisonTabLifecycleError.cancelled
        }
    }

    fileprivate struct Work {
        let maximum: Int
        let cancellationCheckInterval: Int
        let cancellationCheck: CancellationCheck
        private(set) var completed = 0
        private var completedAtLastCheck = 0

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) {
            maximum = limits.maximumWorkUnits
            cancellationCheckInterval = limits.cancellationCheckInterval
            self.cancellationCheck = cancellationCheck
        }

        init(
            maximum: Int,
            cancellationCheckInterval: Int,
            cancellationCheck: @escaping CancellationCheck
        ) {
            self.maximum = maximum
            self.cancellationCheckInterval = cancellationCheckInterval
            self.cancellationCheck = cancellationCheck
        }

        mutating func consume(_ amount: Int = 1) throws {
            guard amount >= 0, amount <= maximum, completed <= maximum - amount else {
                try checkCancellation()
                throw ComparisonTabLifecycleError.workLimitExceeded(maximum: maximum)
            }
            completed += amount
            if completed - completedAtLastCheck >= cancellationCheckInterval {
                try checkCancellation()
            }
        }

        mutating func checkCancellation() throws {
            do {
                try cancellationCheck()
                completedAtLastCheck = completed
            } catch let error as ComparisonTabLifecycleError {
                throw error
            } catch is CancellationError {
                throw ComparisonTabLifecycleError.cancelled
            } catch {
                throw ComparisonTabLifecycleError.cancellationCheckFailed
            }
        }

        mutating func finish() throws {
            try checkCancellation()
        }
    }
}

public enum ComparisonTabLifecycleError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case cancellationCheckFailed
    case invalidLimit(ComparisonTabLifecycle.Limit)
    case workLimitExceeded(maximum: Int)
    case tooManyWindows(maximum: Int)
    case tooManyTabs(windowID: ComparisonTabLifecycle.WindowID, maximum: Int)
    case tooManyTotalTabs(maximum: Int)
    case tooManyRestorationItems(maximum: Int)
    case emptyWindow(ComparisonTabLifecycle.WindowID)
    case duplicateWindowID(ComparisonTabLifecycle.WindowID)
    case duplicateTabID(ComparisonTabLifecycle.TabID)
    case missingSelectedWindow
    case selectedWindowNotFound(ComparisonTabLifecycle.WindowID)
    case selectedTabNotFound(
        windowID: ComparisonTabLifecycle.WindowID,
        tabID: ComparisonTabLifecycle.TabID
    )
    case windowNotFound(ComparisonTabLifecycle.WindowID)
    case tabNotFound(ComparisonTabLifecycle.TabID)
    case windowRevisionIdentityMismatch(
        expected: ComparisonTabLifecycle.WindowID,
        actual: ComparisonTabLifecycle.WindowID
    )
    case invalidInitialWindowRevision(ComparisonTabLifecycle.WindowID)
    case sessionRevisionExhausted(ComparisonTabLifecycle.SessionLineage)
    case windowRevisionExhausted(ComparisonTabLifecycle.WindowID)
    case restorationPublicationEpochExhausted(ComparisonTabLifecycle.RestorationOwnerID)
    case staleRestorationPublication(
        expectedOwnerID: ComparisonTabLifecycle.RestorationOwnerID,
        expectedEpoch: UInt64,
        actualOwnerID: ComparisonTabLifecycle.RestorationOwnerID,
        actualEpoch: UInt64
    )
    case staleState(
        expected: ComparisonTabLifecycle.StateCAS,
        actual: ComparisonTabLifecycle.StateCAS
    )
    case noSelectedWindow
    case noCloseTargets(ComparisonTabLifecycle.CloseScope)
    case noStateChange
    case onlyTabCannotDetach(ComparisonTabLifecycle.TabID)
    case missingSourceSelection(ComparisonTabLifecycle.WindowID)
    case invalidInsertionIndex(Int, windowID: ComparisonTabLifecycle.WindowID)
    case windowTabbingIneligible(
        ComparisonTabLifecycle.WindowID,
        ComparisonWindowCommandState.TabbingIneligibilityReason
    )
    case tabTabbingIneligible(
        ComparisonTabLifecycle.TabID,
        ComparisonWindowCommandState.TabbingIneligibilityReason
    )
    case invalidTabWidth
    case invalidTitle
    case titleTooLarge(maximumUTF8Bytes: Int)
    case aggregateStringsTooLarge(maximumUTF8Bytes: Int)
    case restorationReceiptCountMismatch(expected: Int, actual: Int)
    case unknownRestorationReceipt(ComparisonTabLifecycle.TabID)
    case duplicateRestorationReceipt(ComparisonTabLifecycle.TabID)
    case missingRestorationReceipt(ComparisonTabLifecycle.TabID)
    case invalidRestorationSessionState(ComparisonTabLifecycle.TabID)
    case invalidRestorationFailureCode
    case invalidRestorationFailureMessage
    case restorationFailureCodeTooLarge(maximumUTF8Bytes: Int)
    case restorationFailureMessageTooLarge(maximumUTF8Bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Comparison tab lifecycle planning was cancelled."
        case .cancellationCheckFailed:
            "Comparison tab lifecycle cancellation check failed."
        case .invalidLimit(let limit):
            "Invalid comparison tab lifecycle limit: \(limit.rawValue)."
        case .workLimitExceeded(let maximum):
            "Comparison tab lifecycle planning exceeds the \(maximum)-unit work limit."
        case .tooManyWindows(let maximum):
            "Comparison tab lifecycle exceeds the \(maximum)-window limit."
        case .tooManyTabs(let windowID, let maximum):
            "Window \(windowID.rawValue) exceeds the \(maximum)-tab limit."
        case .tooManyTotalTabs(let maximum):
            "Comparison tab lifecycle exceeds the \(maximum)-tab total limit."
        case .tooManyRestorationItems(let maximum):
            "Comparison session restoration exceeds the \(maximum)-item limit."
        case .emptyWindow(let windowID):
            "Window \(windowID.rawValue) contains no tabs."
        case .duplicateWindowID(let windowID):
            "Window identity \(windowID.rawValue) is duplicated."
        case .duplicateTabID(let tabID):
            "Tab identity \(tabID.rawValue) is duplicated."
        case .missingSelectedWindow:
            "A nonempty comparison session requires a selected window."
        case .selectedWindowNotFound(let windowID):
            "Selected window \(windowID.rawValue) is not present."
        case .selectedTabNotFound(let windowID, let tabID):
            "Selected tab \(tabID.rawValue) is not present in window \(windowID.rawValue)."
        case .windowNotFound(let windowID):
            "Window \(windowID.rawValue) is not present."
        case .tabNotFound(let tabID):
            "Tab \(tabID.rawValue) is not present at the requested location."
        case .windowRevisionIdentityMismatch(let expected, let actual):
            "Window revision identifies \(actual.rawValue), not \(expected.rawValue)."
        case .invalidInitialWindowRevision(let windowID):
            "New window \(windowID.rawValue) requires generation zero."
        case .sessionRevisionExhausted(let lineage):
            "Comparison session lineage \(lineage.rawValue) exhausted its generation space."
        case .windowRevisionExhausted(let windowID):
            "Window \(windowID.rawValue) exhausted its generation space."
        case .restorationPublicationEpochExhausted(let ownerID):
            "Restoration owner \(ownerID.rawValue) exhausted its publication epoch space."
        case .staleRestorationPublication(
            let expectedOwnerID,
            let expectedEpoch,
            let actualOwnerID,
            let actualEpoch
        ):
            "Restoration publication expected owner \(expectedOwnerID.rawValue) epoch \(expectedEpoch), not owner \(actualOwnerID.rawValue) epoch \(actualEpoch)."
        case .staleState(let expected, let actual):
            "Comparison tab state changed from session generation \(expected.sessionRevision.generation) to \(actual.sessionRevision.generation)."
        case .noSelectedWindow:
            "Comparison tab command requires a selected window."
        case .noCloseTargets(let scope):
            "No tabs match the \(scope.rawValue) close scope."
        case .noStateChange:
            "Comparison tab command would not change state."
        case .onlyTabCannotDetach(let tabID):
            "Tab \(tabID.rawValue) is already the only tab in its window."
        case .missingSourceSelection(let windowID):
            "Moved-tab source window \(windowID.rawValue) has no replacement selection."
        case .invalidInsertionIndex(let index, let windowID):
            "Tab insertion index \(index) is invalid for window \(windowID.rawValue)."
        case .windowTabbingIneligible(let windowID, let reason):
            "Window \(windowID.rawValue) cannot participate in native tabbing: \(reason.rawValue)."
        case .tabTabbingIneligible(let tabID, let reason):
            "Tab \(tabID.rawValue) cannot participate in native tabbing: \(reason.rawValue)."
        case .invalidTabWidth:
            "Preferred tab width is non-finite or outside configured bounds."
        case .invalidTitle:
            "Comparison tab title is empty or contains unsupported control characters."
        case .titleTooLarge(let maximum):
            "Comparison tab title exceeds \(maximum) UTF-8 bytes."
        case .aggregateStringsTooLarge(let maximum):
            "Comparison tab lifecycle strings exceed \(maximum) aggregate UTF-8 bytes."
        case .restorationReceiptCountMismatch(let expected, let actual):
            "Session restoration expected \(expected) item receipts but received \(actual)."
        case .unknownRestorationReceipt(let tabID):
            "Session restoration receipt names unknown tab \(tabID.rawValue)."
        case .duplicateRestorationReceipt(let tabID):
            "Session restoration receipt repeats tab \(tabID.rawValue)."
        case .missingRestorationReceipt(let tabID):
            "Session restoration receipt omits tab \(tabID.rawValue)."
        case .invalidRestorationSessionState(let tabID):
            "Session restoration could not verify the bounded state for tab \(tabID.rawValue)."
        case .invalidRestorationFailureCode:
            "Restoration failure code must use nonempty ASCII letters, digits, period, underscore, or hyphen."
        case .invalidRestorationFailureMessage:
            "Restoration failure message is empty or contains unsupported control characters."
        case .restorationFailureCodeTooLarge(let maximum):
            "Restoration failure code exceeds \(maximum) UTF-8 bytes."
        case .restorationFailureMessageTooLarge(let maximum):
            "Restoration failure message exceeds \(maximum) UTF-8 bytes."
        }
    }
}
