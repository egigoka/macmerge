import Foundation

/// Bounded, UI-independent arrangement planning for native comparison windows and tabs.
///
/// This model owns no AppKit objects and performs no persistence, document
/// materialization, or tab-bar wiring. Callers retain authority over native
/// windows, close confirmation, and restoration. Plans are pure values bound
/// to an exact owner/session CAS; an executor must satisfy the declared
/// contracts before replacing owner state with a plan successor.
///
/// MDI mapping: WinMerge MDI tile/cascade becomes native document windows
/// and tabs. Tile plans stable window order plus a validated grid; cascade
/// plans stable window order plus a validated stride; tab/merge plans group
/// windows into one native tab group. No geometry is computed here.
///
/// Split mapping: a comparison already owns its pane layout, so split plans
/// only a per-window split fraction/orientation change. Split never creates
/// comparison content and never allocates window identity.
public enum WindowArrangementPlan: Sendable {
    public typealias WindowID = ComparisonWindowCommandState.WindowID
    public typealias TabID = ComparisonWindowCommandState.TabID
    public typealias SessionLineage = ComparisonWindowCommandState.SnapshotLineage
    public typealias TabbingEligibility = ComparisonWindowCommandState.TabbingEligibility
    public typealias IneligibilityReason = ComparisonWindowCommandState.TabbingIneligibilityReason
    public typealias CancellationCheck = @Sendable () throws -> Void

    public struct OwnerID: RawRepresentable, Codable, Comparable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (left: OwnerID, right: OwnerID) -> Bool {
            left.rawValue < right.rawValue
        }
    }

    public struct SessionRevision: Equatable, Hashable, Sendable {
        public let lineage: SessionLineage
        public let generation: UInt64

        public init(lineage: SessionLineage, generation: UInt64) {
            self.lineage = lineage
            self.generation = generation
        }

        fileprivate func advanced() throws -> SessionRevision {
            guard generation < UInt64.max else {
                throw WindowArrangementPlanError.sessionRevisionExhausted(lineage)
            }
            return SessionRevision(lineage: lineage, generation: generation + 1)
        }
    }

    public struct WindowRevision: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let generation: UInt64

        public init(windowID: WindowID, generation: UInt64) {
            self.windowID = windowID
            self.generation = generation
        }

        fileprivate func advanced() throws -> WindowRevision {
            guard generation < UInt64.max else {
                throw WindowArrangementPlanError.windowRevisionExhausted(windowID)
            }
            return WindowRevision(windowID: windowID, generation: generation + 1)
        }
    }

    /// Exact owner/epoch transition required to publish one restoration result.
    public struct RestorationPublicationCAS: Equatable, Hashable, Sendable {
        public let ownerID: OwnerID
        public let expectedEpoch: UInt64
        public let successorEpoch: UInt64

        public init(ownerID: OwnerID, expectedEpoch: UInt64) throws {
            guard expectedEpoch < UInt64.max else {
                throw WindowArrangementPlanError.restorationPublicationEpochExhausted(ownerID)
            }
            self.ownerID = ownerID
            self.expectedEpoch = expectedEpoch
            successorEpoch = expectedEpoch + 1
        }

        public func matches(ownerID: OwnerID, epoch: UInt64) -> Bool {
            self.ownerID == ownerID && expectedEpoch == epoch
        }

        public func validate(ownerID: OwnerID, epoch: UInt64) throws {
            guard matches(ownerID: ownerID, epoch: epoch) else {
                throw WindowArrangementPlanError.staleRestorationPublication(
                    expectedOwnerID: self.ownerID,
                    expectedEpoch: expectedEpoch,
                    actualOwnerID: ownerID,
                    actualEpoch: epoch
                )
            }
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

    public enum CloseVetoReason: String, CaseIterable, Codable, Hashable, Sendable {
        case activeOperation
        case ownerRejected
        case policyRestricted
    }

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

    public enum TabWidthPreference: Equatable, Hashable, Sendable {
        case automatic
        case fixed(Double)

        public var fixedWidth: Double? {
            guard case .fixed(let width) = self else { return nil }
            return width
        }
    }

    public enum SplitOrientation: String, CaseIterable, Codable, Hashable, Sendable {
        case horizontal
        case vertical
    }

    /// Plan-only per-window split configuration. Fraction is the leading pane share.
    public struct SplitConfiguration: Equatable, Hashable, Sendable {
        public let orientation: SplitOrientation
        public let fraction: Double

        public init(orientation: SplitOrientation, fraction: Double) throws {
            guard fraction.isFinite else {
                throw WindowArrangementPlanError.invalidSplitFraction(fraction)
            }
            guard fraction >= Limits.hardMinimumSplitFraction,
                fraction <= Limits.hardMaximumSplitFraction
            else {
                throw WindowArrangementPlanError.invalidSplitFraction(fraction)
            }
            self.orientation = orientation
            self.fraction = fraction
        }

        fileprivate init(validatedOrientation orientation: SplitOrientation, validatedFraction fraction: Double) {
            self.orientation = orientation
            self.fraction = fraction
        }
    }

    /// Plan-only native arrangement. Tile and cascade preserve stable window order.
    /// Tabbed groups every window into one native tab group. Separate leaves order unchanged.
    public enum Arrangement: Equatable, Hashable, Sendable {
        case separateWindows
        case tiled(columns: Int)
        case cascaded(stride: Double)
        case tabbed(destinationWindowID: WindowID)
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
        case splitFractionRange
        case tileColumns
        case cascadeStrideRange
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
        public static let hardMinimumSplitFraction = 0.05
        public static let hardMaximumSplitFraction = 0.95
        public static let hardMaximumTileColumns = 64
        public static let hardMinimumCascadeStride = 8.0
        public static let hardMaximumCascadeStride = 512.0
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
        public let minimumSplitFraction: Double
        public let maximumSplitFraction: Double
        public let maximumTileColumns: Int
        public let minimumCascadeStride: Double
        public let maximumCascadeStride: Double
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
            minimumSplitFraction: Double = 0.2,
            maximumSplitFraction: Double = 0.8,
            maximumTileColumns: Int = 8,
            minimumCascadeStride: Double = 16,
            maximumCascadeStride: Double = 64,
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
            self.minimumSplitFraction = minimumSplitFraction
            self.maximumSplitFraction = maximumSplitFraction
            self.maximumTileColumns = maximumTileColumns
            self.minimumCascadeStride = minimumCascadeStride
            self.maximumCascadeStride = maximumCascadeStride
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }

        public func validate() throws {
            guard (1...Self.hardMaximumWindowCount).contains(maximumWindowCount) else {
                throw WindowArrangementPlanError.invalidLimit(.windows)
            }
            guard (1...Self.hardMaximumTabsPerWindow).contains(maximumTabsPerWindow) else {
                throw WindowArrangementPlanError.invalidLimit(.tabsPerWindow)
            }
            guard (1...Self.hardMaximumTotalTabCount).contains(maximumTotalTabCount) else {
                throw WindowArrangementPlanError.invalidLimit(.totalTabs)
            }
            guard maximumTabsPerWindow <= maximumTotalTabCount else {
                throw WindowArrangementPlanError.invalidLimit(.tabsPerWindow)
            }
            guard (1...Self.hardMaximumRestorationItemCount).contains(maximumRestorationItemCount) else {
                throw WindowArrangementPlanError.invalidLimit(.restorationItems)
            }
            guard (1...Self.hardMaximumTitleUTF8Bytes).contains(maximumTitleUTF8Bytes) else {
                throw WindowArrangementPlanError.invalidLimit(.titleUTF8Bytes)
            }
            guard (1...Self.hardMaximumRestorationCodeUTF8Bytes).contains(maximumRestorationCodeUTF8Bytes) else {
                throw WindowArrangementPlanError.invalidLimit(.restorationCodeUTF8Bytes)
            }
            guard (1...Self.hardMaximumRestorationMessageUTF8Bytes).contains(maximumRestorationMessageUTF8Bytes) else {
                throw WindowArrangementPlanError.invalidLimit(.restorationMessageUTF8Bytes)
            }
            guard (1...Self.hardMaximumAggregateStringUTF8Bytes).contains(maximumAggregateStringUTF8Bytes),
                maximumAggregateStringUTF8Bytes >= maximumTitleUTF8Bytes,
                maximumAggregateStringUTF8Bytes >= maximumRestorationCodeUTF8Bytes,
                maximumAggregateStringUTF8Bytes >= maximumRestorationMessageUTF8Bytes
            else {
                throw WindowArrangementPlanError.invalidLimit(.aggregateStringUTF8Bytes)
            }
            guard minimumTabWidth.isFinite, maximumTabWidth.isFinite,
                minimumTabWidth >= Self.hardMinimumTabWidth,
                maximumTabWidth <= Self.hardMaximumTabWidth,
                minimumTabWidth <= maximumTabWidth
            else {
                throw WindowArrangementPlanError.invalidLimit(.tabWidthRange)
            }
            guard minimumSplitFraction.isFinite, maximumSplitFraction.isFinite,
                minimumSplitFraction >= Self.hardMinimumSplitFraction,
                maximumSplitFraction <= Self.hardMaximumSplitFraction,
                minimumSplitFraction <= maximumSplitFraction
            else {
                throw WindowArrangementPlanError.invalidLimit(.splitFractionRange)
            }
            guard (1...Self.hardMaximumTileColumns).contains(maximumTileColumns) else {
                throw WindowArrangementPlanError.invalidLimit(.tileColumns)
            }
            guard minimumCascadeStride.isFinite, maximumCascadeStride.isFinite,
                minimumCascadeStride >= Self.hardMinimumCascadeStride,
                maximumCascadeStride <= Self.hardMaximumCascadeStride,
                minimumCascadeStride <= maximumCascadeStride
            else {
                throw WindowArrangementPlanError.invalidLimit(.cascadeStrideRange)
            }
            guard (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits) else {
                throw WindowArrangementPlanError.invalidLimit(.workUnits)
            }
            guard (1...Self.hardMaximumCancellationCheckInterval).contains(cancellationCheckInterval) else {
                throw WindowArrangementPlanError.invalidLimit(.cancellationCheckInterval)
            }
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
            self.title = try WindowArrangementPlan.normalizedTitle(title)
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
        public let tabs: [TabState]
        public let selectedTabID: TabID
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility
        public let split: SplitConfiguration?

        public var selectedTab: TabState? { tabs.first { $0.id == selectedTabID } }

        public init(
            id: WindowID,
            revision: WindowRevision,
            tabs: [TabState],
            selectedTabID: TabID,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible,
            split: SplitConfiguration? = nil
        ) throws {
            try WindowArrangementPlan.checkTaskCancellation()
            guard revision.windowID == id else {
                throw WindowArrangementPlanError.windowRevisionIdentityMismatch(
                    expected: id,
                    actual: revision.windowID
                )
            }
            guard !tabs.isEmpty else {
                throw WindowArrangementPlanError.emptyWindow(id)
            }
            guard tabs.count <= Limits.hardMaximumTabsPerWindow else {
                throw WindowArrangementPlanError.tooManyTabs(
                    windowID: id,
                    maximum: Limits.hardMaximumTabsPerWindow
                )
            }
            var identifiers: Set<TabID> = []
            identifiers.reserveCapacity(tabs.count)
            var foundSelection = false
            for (offset, tab) in tabs.enumerated() {
                if offset % Limits.hardMaximumCancellationCheckInterval == 0 {
                    try WindowArrangementPlan.checkTaskCancellation()
                }
                guard identifiers.insert(tab.id).inserted else {
                    throw WindowArrangementPlanError.duplicateTabID(tab.id)
                }
                if tab.id == selectedTabID { foundSelection = true }
            }
            guard foundSelection else {
                throw WindowArrangementPlanError.selectedTabNotFound(
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
            self.split = split
        }

        fileprivate init(
            validatedID id: WindowID,
            revision: WindowRevision,
            tabs: [TabState],
            selectedTabID: TabID,
            isRestorable: Bool,
            tabbingEligibility: TabbingEligibility,
            split: SplitConfiguration?
        ) {
            self.id = id
            self.revision = revision
            self.tabs = tabs
            self.selectedTabID = selectedTabID
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
            self.split = split
        }
    }

    /// Validated immutable owner state. Window order is stable native window-cycle order.
    public struct State: Equatable, Hashable, Sendable {
        public let revision: SessionRevision
        public let ownerID: OwnerID
        public let windows: [WindowState]
        public let selectedWindowID: WindowID?
        public let arrangement: Arrangement
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
            ownerID: OwnerID,
            windows: [WindowState],
            selectedWindowID: WindowID?,
            arrangement: Arrangement = .separateWindows,
            tabWidthPreference: TabWidthPreference = .automatic,
            limits: Limits = .default
        ) throws {
            var work = Work(
                limits: limits,
                cancellationCheck: { try WindowArrangementPlan.checkTaskCancellation() }
            )
            try work.checkCancellation()
            try limits.validate()
            try WindowArrangementPlan.validate(tabWidthPreference, limits: limits)
            guard windows.count <= limits.maximumWindowCount else {
                throw WindowArrangementPlanError.tooManyWindows(maximum: limits.maximumWindowCount)
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
                    throw WindowArrangementPlanError.duplicateWindowID(window.id)
                }
                guard window.revision.windowID == window.id else {
                    throw WindowArrangementPlanError.windowRevisionIdentityMismatch(
                        expected: window.id,
                        actual: window.revision.windowID
                    )
                }
                guard !window.tabs.isEmpty else {
                    throw WindowArrangementPlanError.emptyWindow(window.id)
                }
                guard window.tabs.count <= limits.maximumTabsPerWindow else {
                    throw WindowArrangementPlanError.tooManyTabs(
                        windowID: window.id,
                        maximum: limits.maximumTabsPerWindow
                    )
                }
                guard totalTabs <= limits.maximumTotalTabCount - window.tabs.count else {
                    throw WindowArrangementPlanError.tooManyTotalTabs(maximum: limits.maximumTotalTabCount)
                }
                totalTabs += window.tabs.count
                if let split = window.split {
                    try WindowArrangementPlan.validate(split, limits: limits, work: &work)
                }
                var foundSelection = false
                for tab in window.tabs {
                    try work.consume()
                    guard tabIDs.insert(tab.id).inserted else {
                        throw WindowArrangementPlanError.duplicateTabID(tab.id)
                    }
                    if tab.id == window.selectedTabID { foundSelection = true }
                    let byteCount = try WindowArrangementPlan.validatedStringByteCount(
                        tab.title,
                        field: .title,
                        maximum: limits.maximumTitleUTF8Bytes,
                        allowsEmpty: false,
                        work: &work
                    )
                    guard totalStringBytes <= limits.maximumAggregateStringUTF8Bytes - byteCount else {
                        throw WindowArrangementPlanError.aggregateStringsTooLarge(
                            maximumUTF8Bytes: limits.maximumAggregateStringUTF8Bytes
                        )
                    }
                    totalStringBytes += byteCount
                }
                guard foundSelection else {
                    throw WindowArrangementPlanError.selectedTabNotFound(
                        windowID: window.id,
                        tabID: window.selectedTabID
                    )
                }
            }
            if windows.isEmpty {
                if let selectedWindowID {
                    throw WindowArrangementPlanError.selectedWindowNotFound(selectedWindowID)
                }
                guard arrangement == .separateWindows else {
                    throw WindowArrangementPlanError.invalidArrangement("empty session must use separate windows")
                }
            } else {
                guard let selectedWindowID else {
                    throw WindowArrangementPlanError.missingSelectedWindow
                }
                guard windowIDs.contains(selectedWindowID) else {
                    throw WindowArrangementPlanError.selectedWindowNotFound(selectedWindowID)
                }
                try WindowArrangementPlan.validate(
                    arrangement,
                    windows: windows,
                    limits: limits,
                    work: &work
                )
            }
            try work.finish()
            self.revision = revision
            self.ownerID = ownerID
            self.windows = windows
            self.selectedWindowID = selectedWindowID
            self.arrangement = arrangement
            self.tabWidthPreference = tabWidthPreference
            self.limits = limits
            totalTabCount = totalTabs
        }

        fileprivate init(
            validatedRevision revision: SessionRevision,
            ownerID: OwnerID,
            windows: [WindowState],
            selectedWindowID: WindowID?,
            arrangement: Arrangement,
            tabWidthPreference: TabWidthPreference,
            limits: Limits,
            totalTabCount: Int
        ) {
            self.revision = revision
            self.ownerID = ownerID
            self.windows = windows
            self.selectedWindowID = selectedWindowID
            self.arrangement = arrangement
            self.tabWidthPreference = tabWidthPreference
            self.limits = limits
            self.totalTabCount = totalTabCount
        }

        /// Redacted projection omits tab titles and keeps only counts, order, and dirty state.
        public func redacted() -> RedactedState {
            var windowSummaries: [RedactedState.WindowSummary] = []
            windowSummaries.reserveCapacity(windows.count)
            for window in windows {
                windowSummaries.append(
                    RedactedState.WindowSummary(
                        windowID: window.id,
                        tabCount: window.tabs.count,
                        selectedTabID: window.selectedTabID,
                        hasDirtyTabs: window.tabs.contains(where: \.isDirty),
                        hasSplit: window.split != nil
                    )
                )
            }
            return RedactedState(
                windowCount: windows.count,
                totalTabCount: totalTabCount,
                arrangement: arrangement,
                selectedWindowID: selectedWindowID,
                windows: windowSummaries
            )
        }

        public var redactedDescription: String {
            "windows=\(windows.count) tabs=\(totalTabCount) arrangement=\(arrangement)"
        }
    }

    /// Redacted owner state without titles or materialization detail.
    public struct RedactedState: Equatable, Hashable, Sendable {
        public struct WindowSummary: Equatable, Hashable, Sendable {
            public let windowID: WindowID
            public let tabCount: Int
            public let selectedTabID: TabID
            public let hasDirtyTabs: Bool
            public let hasSplit: Bool
        }

        public let windowCount: Int
        public let totalTabCount: Int
        public let arrangement: Arrangement
        public let selectedWindowID: WindowID?
        public let windows: [WindowSummary]
    }

    /// Collision-free CAS: public revisions aid diagnostics; private snapshot comparison
    /// also rejects callers that failed to advance a revision after changing structural state.
    public struct StateCAS: Equatable, Hashable, Sendable {
        public let ownerID: OwnerID
        public let sessionRevision: SessionRevision
        public let windowRevisions: [WindowRevision]
        fileprivate let snapshot: State

        fileprivate init(state: State) {
            ownerID = state.ownerID
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
                cancellationCheck: { try WindowArrangementPlan.checkTaskCancellation() }
            )
            let result = try matches(state, work: &work)
            try work.finish()
            return result
        }

        public func validate(_ state: State) throws {
            guard try matches(state) else {
                throw WindowArrangementPlanError.staleState(expected: self, actual: state.cas)
            }
        }

        fileprivate func matches(_ state: State, work: inout Work) throws -> Bool {
            guard ownerID == state.ownerID,
                sessionRevision == state.revision,
                snapshot.selectedWindowID == state.selectedWindowID,
                snapshot.arrangement == state.arrangement,
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
                    expectedWindow.split == actualWindow.split,
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
                        try WindowArrangementPlan.stringsMatch(expectedTab.title, actualTab.title, work: &work)
                    else { return false }
                }
            }
            return true
        }
    }

    /// Destination identity must be reserved by the owning registry before planning.
    public struct WindowReservation: Equatable, Hashable, Sendable {
        public let id: WindowID
        public let initialRevision: WindowRevision

        public init(id: WindowID, initialRevision: WindowRevision) throws {
            guard initialRevision.windowID == id else {
                throw WindowArrangementPlanError.windowRevisionIdentityMismatch(
                    expected: id,
                    actual: initialRevision.windowID
                )
            }
            guard initialRevision.generation == 0 else {
                throw WindowArrangementPlanError.invalidInitialWindowRevision(id)
            }
            self.id = id
            self.initialRevision = initialRevision
        }
    }

    /// Plan-only split change for one window. A nil configuration clears the split.
    public struct SplitRequest: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let configuration: SplitConfiguration?

        public init(windowID: WindowID, configuration: SplitConfiguration? = nil) {
            self.windowID = windowID
            self.configuration = configuration
        }
    }

    /// Plan-only selective tab grouping. Sources are appended to the destination
    /// in stable window order; tabs within each source remain left-to-right.
    public struct TabRequest: Equatable, Hashable, Sendable {
        public let sourceWindowIDs: [WindowID]
        public let destinationWindowID: WindowID

        public init(sourceWindowIDs: [WindowID], destinationWindowID: WindowID) {
            self.sourceWindowIDs = sourceWindowIDs
            self.destinationWindowID = destinationWindowID
        }
    }

    /// Plan-only MDI tile adaptation. Columns lay stable window order out row-major.
    public struct TileRequest: Equatable, Hashable, Sendable {
        public let columns: Int

        public init(columns: Int) {
            self.columns = columns
        }
    }

    /// Plan-only MDI cascade adaptation. Stride offsets successive windows diagonally.
    public struct CascadeRequest: Equatable, Hashable, Sendable {
        public let stride: Double

        public init(stride: Double) {
            self.stride = stride
        }
    }

    public struct DetachRequest: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let tabID: TabID
        public let destination: WindowReservation

        public init(sourceWindowID: WindowID, tabID: TabID, destination: WindowReservation) {
            self.sourceWindowID = sourceWindowID
            self.tabID = tabID
            self.destination = destination
        }
    }

    public struct MoveRequest: Equatable, Hashable, Sendable {
        public let sourceWindowID: WindowID
        public let destinationWindowID: WindowID
        public let tabID: TabID
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

    /// Plan-only full merge. Every tab moves into the destination in stable window order.
    public struct MergeRequest: Equatable, Hashable, Sendable {
        public let destinationWindowID: WindowID

        public init(destinationWindowID: WindowID) {
            self.destinationWindowID = destinationWindowID
        }
    }

    public enum Command: Equatable, Hashable, Sendable {
        case split(SplitRequest)
        case tab(TabRequest)
        case tile(TileRequest)
        case cascade(CascadeRequest)
        case detach(DetachRequest)
        case move(MoveRequest)
        case merge(MergeRequest)
    }

    public struct SplitIntent: Equatable, Hashable, Sendable {
        public let windowID: WindowID
        public let configuration: SplitConfiguration?
    }

    public struct TabIntent: Equatable, Hashable, Sendable {
        public let destinationWindowID: WindowID
        public let movedTabIDs: [TabID]
        public let resultingTabOrder: [TabID]
        public let resultingSelection: TabID
    }

    public struct TileIntent: Equatable, Hashable, Sendable {
        public let columns: Int
        public let rows: Int
        /// Stable window order laid out row-major.
        public let windowIDs: [WindowID]
        public let restoreMinimizedWindowIDs: [WindowID]
    }

    public struct CascadeIntent: Equatable, Hashable, Sendable {
        public let stride: Double
        /// Stable front-to-back window order.
        public let windowIDs: [WindowID]
        public let restoreMinimizedWindowIDs: [WindowID]
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

    public struct MergeIntent: Equatable, Hashable, Sendable {
        public let destinationWindowID: WindowID
        public let movedTabCount: Int
        public let resultingTabOrder: [TabID]
        public let resultingSelection: TabID
        public let closedWindowIDs: [WindowID]
    }

    public enum Effect: Equatable, Hashable, Sendable {
        case split(SplitIntent)
        case tab(TabIntent)
        case tile(TileIntent)
        case cascade(CascadeIntent)
        case detach(DetachIntent)
        case move(MoveIntent)
        case merge(MergeIntent)
    }

    public enum StateCASExecutionContract: String, Hashable, Sendable {
        case compareExactSnapshotThenReplaceOnce
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
        public let materialization = MaterializationExecutionContract.materializeNativeWindowWithoutOwningComparisonContent
        public let cancellation = ExecutionCancellationContract.cancellationBeforeMutationLeavesOwnerStateUnchanged

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

        /// Redacted receipt keeps only counts, IDs, and arrangement; titles are never included.
        public var redactedDescription: String {
            "expected=\(expectedStateCAS.sessionRevision.generation) successor=\(successorStateCAS.sessionRevision.generation) effect=\(effect)"
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
            receipt = PlanningReceipt(expectedStateCAS: expectedStateCAS, successor: successor, effect: effect)
            self.workPerformed = workPerformed
            executorContract = .required
        }

        public func validateCurrentState(_ state: State) throws {
            try expectedStateCAS.validate(state)
        }

        /// Redacted plan description omits titles, codes, and messages.
        public var redactedDescription: String {
            "command=\(command) windows=\(successor.windows.count) tabs=\(successor.totalTabCount)"
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
            case .split(let request):
                draft = try planSplit(request, state: state, work: &work)
            case .tab(let request):
                draft = try planTab(request, state: state, work: &work)
            case .tile(let request):
                draft = try planTile(request, state: state, work: &work)
            case .cascade(let request):
                draft = try planCascade(request, state: state, work: &work)
            case .detach(let request):
                draft = try planDetach(request, state: state, work: &work)
            case .move(let request):
                draft = try planMove(request, state: state, work: &work)
            case .merge(let request):
                draft = try planMerge(request, state: state, work: &work)
            }
            try work.finish()
            return Plan(
                command: command,
                expectedStateCAS: state.cas,
                effect: draft.effect,
                successor: draft.successor,
                workPerformed: work.completed
            )
        } catch let error as WindowArrangementPlanError {
            throw error
        } catch {
            throw WindowArrangementPlanError.cancelled
        }
    }

    public struct RestorationTab: Equatable, Sendable {
        public let id: TabID
        public let title: String
        public let materialization: MaterializationReference
        public let isDirty: Bool
        public let closeVeto: CloseVeto
        public let isRestorable: Bool
        public let tabbingEligibility: TabbingEligibility

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
            self.title = try WindowArrangementPlan.normalizedTitle(title)
            self.materialization = materialization
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
        public let split: SplitConfiguration?

        public init(
            id: WindowID,
            revision: WindowRevision,
            tabs: [RestorationTab],
            selectedTabID: TabID,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible,
            split: SplitConfiguration? = nil
        ) throws {
            guard revision.windowID == id else {
                throw WindowArrangementPlanError.windowRevisionIdentityMismatch(
                    expected: id,
                    actual: revision.windowID
                )
            }
            guard !tabs.isEmpty else {
                throw WindowArrangementPlanError.emptyWindow(id)
            }
            guard tabs.count <= Limits.hardMaximumTabsPerWindow else {
                throw WindowArrangementPlanError.tooManyTabs(
                    windowID: id,
                    maximum: Limits.hardMaximumTabsPerWindow
                )
            }
            var identifiers: Set<TabID> = []
            identifiers.reserveCapacity(tabs.count)
            var foundSelection = false
            for (offset, tab) in tabs.enumerated() {
                if offset % Limits.hardMaximumCancellationCheckInterval == 0 {
                    try WindowArrangementPlan.checkTaskCancellation()
                }
                guard identifiers.insert(tab.id).inserted else {
                    throw WindowArrangementPlanError.duplicateTabID(tab.id)
                }
                if tab.id == selectedTabID { foundSelection = true }
            }
            guard foundSelection else {
                throw WindowArrangementPlanError.selectedTabNotFound(windowID: id, tabID: selectedTabID)
            }
            self.id = id
            self.revision = revision
            self.tabs = tabs
            self.selectedTabID = selectedTabID
            self.isRestorable = isRestorable
            self.tabbingEligibility = tabbingEligibility
            self.split = split
        }
    }

    public struct RestorationRequest: Equatable, Sendable {
        public let publicationCAS: RestorationPublicationCAS
        public let sessionRevision: SessionRevision
        public let ownerID: OwnerID
        public let windows: [RestorationWindow]
        public let selectedWindowID: WindowID?
        public let arrangement: Arrangement
        public let tabWidthPreference: TabWidthPreference
        public let limits: Limits

        public init(
            publicationCAS: RestorationPublicationCAS,
            sessionRevision: SessionRevision,
            ownerID: OwnerID,
            windows: [RestorationWindow],
            selectedWindowID: WindowID?,
            arrangement: Arrangement = .separateWindows,
            tabWidthPreference: TabWidthPreference = .automatic,
            limits: Limits = .default
        ) {
            self.publicationCAS = publicationCAS
            self.sessionRevision = sessionRevision
            self.ownerID = ownerID
            self.windows = windows
            self.selectedWindowID = selectedWindowID
            self.arrangement = arrangement
            self.tabWidthPreference = tabWidthPreference
            self.limits = limits
        }
    }

    public enum RestorationMaterializationContract: String, Hashable, Sendable {
        case materializeValidatedArrangementWithoutPersistenceOrUIAssumptions
    }

    public enum RestorationPublicationContract: String, Hashable, Sendable {
        case atomicallyCompareOwnerAndEpochThenPublishCanonicalReceiptOrderOnceAfterAllOutcomes
    }

    public struct MaterializationContract: Equatable, Hashable, Sendable {
        public static let required = MaterializationContract()

        public let materialization = RestorationMaterializationContract.materializeValidatedArrangementWithoutPersistenceOrUIAssumptions
        public let publication = RestorationPublicationContract.atomicallyCompareOwnerAndEpochThenPublishCanonicalReceiptOrderOnceAfterAllOutcomes

        public init() {}
    }

    public struct MaterializationRequest: Equatable, Sendable {
        public let ordinal: Int
        public let expectedPublicationCAS: RestorationPublicationCAS
        public let expectedSessionRevision: SessionRevision
        public let expectedWindowRevision: WindowRevision
        public let windowID: WindowID
        public let tabID: TabID
        public let materialization: MaterializationReference
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
            materialization = tab.materialization
            contract = .required
        }
    }

    public struct RestorationPlan: Equatable, Sendable {
        public let request: RestorationRequest
        public let publicationCAS: RestorationPublicationCAS
        public let materializations: [MaterializationRequest]
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
            try WindowArrangementPlan.makeRestorationReceipt(
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
            try WindowArrangementPlan.validateStandaloneRestorationMessage(message)
            let normalizedMessage = message.precomposedStringWithCanonicalMapping
            try WindowArrangementPlan.validateStandaloneFailureCode(code)
            try WindowArrangementPlan.validateStandaloneRestorationMessage(normalizedMessage)
            self.code = code
            self.message = normalizedMessage
            self.isRetryable = isRetryable
        }

        /// Redacted failure keeps retryability and byte counts; code and message are omitted.
        public var redactedDescription: String {
            "retryable=\(isRetryable)"
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
        public let publicationCAS: RestorationPublicationCAS
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

        /// Redacted receipt keeps IDs, counts, and arrangement; titles, codes, and messages omitted.
        public var redactedDescription: String {
            "windows=\(windowOutcomes.count) restored=\(restoredTabIDs.count) skipped=\(skippedTabIDs.count) failed=\(failedTabIDs.count)"
        }

        public func redacted() -> RedactedState {
            restoredState.redacted()
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
                throw WindowArrangementPlanError.tooManyWindows(maximum: request.limits.maximumWindowCount)
            }
            var windowIDs: Set<WindowID> = []
            var tabIDs: Set<TabID> = []
            var materializations: [MaterializationRequest] = []
            var totalStringBytes = 0
            windowIDs.reserveCapacity(request.windows.count)
            materializations.reserveCapacity(min(request.limits.maximumRestorationItemCount, 256))
            for window in request.windows {
                try work.consume()
                guard windowIDs.insert(window.id).inserted else {
                    throw WindowArrangementPlanError.duplicateWindowID(window.id)
                }
                guard window.revision.windowID == window.id else {
                    throw WindowArrangementPlanError.windowRevisionIdentityMismatch(
                        expected: window.id,
                        actual: window.revision.windowID
                    )
                }
                guard !window.tabs.isEmpty else {
                    throw WindowArrangementPlanError.emptyWindow(window.id)
                }
                guard window.tabs.count <= request.limits.maximumTabsPerWindow else {
                    throw WindowArrangementPlanError.tooManyTabs(
                        windowID: window.id,
                        maximum: request.limits.maximumTabsPerWindow
                    )
                }
                guard materializations.count <= request.limits.maximumTotalTabCount - window.tabs.count else {
                    throw WindowArrangementPlanError.tooManyTotalTabs(maximum: request.limits.maximumTotalTabCount)
                }
                guard materializations.count <= request.limits.maximumRestorationItemCount - window.tabs.count else {
                    throw WindowArrangementPlanError.tooManyRestorationItems(maximum: request.limits.maximumRestorationItemCount)
                }
                if let split = window.split {
                    try validate(split, limits: request.limits, work: &work)
                }
                var foundSelection = false
                for tab in window.tabs {
                    try work.consume()
                    guard tabIDs.insert(tab.id).inserted else {
                        throw WindowArrangementPlanError.duplicateTabID(tab.id)
                    }
                    if tab.id == window.selectedTabID { foundSelection = true }
                    let byteCount = try validatedStringByteCount(
                        tab.title,
                        field: .title,
                        maximum: request.limits.maximumTitleUTF8Bytes,
                        allowsEmpty: false,
                        work: &work
                    )
                    guard totalStringBytes <= request.limits.maximumAggregateStringUTF8Bytes - byteCount else {
                        throw WindowArrangementPlanError.aggregateStringsTooLarge(
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
                    throw WindowArrangementPlanError.selectedTabNotFound(windowID: window.id, tabID: window.selectedTabID)
                }
            }
            if request.windows.isEmpty {
                if let selectedWindowID = request.selectedWindowID {
                    throw WindowArrangementPlanError.selectedWindowNotFound(selectedWindowID)
                }
                guard request.arrangement == .separateWindows else {
                    throw WindowArrangementPlanError.invalidArrangement("empty restoration must use separate windows")
                }
            } else {
                guard let selectedWindowID = request.selectedWindowID else {
                    throw WindowArrangementPlanError.missingSelectedWindow
                }
                guard windowIDs.contains(selectedWindowID) else {
                    throw WindowArrangementPlanError.selectedWindowNotFound(selectedWindowID)
                }
                let proxyWindows = try proxyWindowStates(request.windows, work: &work)
                try validate(request.arrangement, windows: proxyWindows, limits: request.limits, work: &work)
            }
            try work.finish()
            return RestorationPlan(
                request: request,
                materializations: materializations,
                retainedStringUTF8Bytes: totalStringBytes,
                workPerformed: work.completed
            )
        } catch let error as WindowArrangementPlanError {
            throw error
        } catch {
            throw WindowArrangementPlanError.cancelled
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

    private static func planSplit(
        _ request: SplitRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        let windowIndex = try index(of: request.windowID, in: state, work: &work)
        let window = state.windows[windowIndex]
        if let configuration = request.configuration {
            try validate(configuration, limits: state.limits, work: &work)
        }
        guard window.split != request.configuration else {
            throw WindowArrangementPlanError.noStateChange
        }
        var windows = state.windows
        windows[windowIndex] = WindowState(
            validatedID: window.id,
            revision: try window.revision.advanced(),
            tabs: window.tabs,
            selectedTabID: window.selectedTabID,
            isRestorable: window.isRestorable,
            tabbingEligibility: window.tabbingEligibility,
            split: request.configuration
        )
        let successor = try successor(
            of: state,
            windows: windows,
            selectedWindowID: state.selectedWindowID,
            arrangement: state.arrangement,
            totalTabCount: state.totalTabCount
        )
        return Draft(
            effect: .split(SplitIntent(windowID: window.id, configuration: request.configuration)),
            successor: successor
        )
    }

    private static func planTab(
        _ request: TabRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        guard !state.windows.isEmpty else {
            throw WindowArrangementPlanError.noSelectedWindow
        }
        let destinationIndex = try index(of: request.destinationWindowID, in: state, work: &work)
        let destination = state.windows[destinationIndex]
        guard !request.sourceWindowIDs.isEmpty else {
            throw WindowArrangementPlanError.emptyTabGroup
        }
        var seenSources: Set<WindowID> = []
        seenSources.reserveCapacity(request.sourceWindowIDs.count)
        for sourceID in request.sourceWindowIDs {
            try work.consume()
            guard seenSources.insert(sourceID).inserted else {
                throw WindowArrangementPlanError.duplicateWindowID(sourceID)
            }
            guard sourceID != request.destinationWindowID else {
                throw WindowArrangementPlanError.tabGroupIncludesDestination(sourceID)
            }
        }
        var sourceIndices: [Int] = []
        sourceIndices.reserveCapacity(request.sourceWindowIDs.count)
        for sourceID in state.windows.map(\.id) {
            try work.consume()
            if seenSources.contains(sourceID) {
                sourceIndices.append(try index(of: sourceID, in: state, work: &work))
            }
        }
        guard sourceIndices.count == seenSources.count else {
            guard let firstSourceID = request.sourceWindowIDs.first else {
                throw WindowArrangementPlanError.emptyTabGroup
            }
            throw WindowArrangementPlanError.windowNotFound(firstSourceID)
        }
        try validateTabbing(window: destination, tabCount: destination.tabs.count)
        for sourceIndex in sourceIndices {
            try work.consume()
            try validateTabbing(window: state.windows[sourceIndex], tabCount: state.windows[sourceIndex].tabs.count)
        }
        var movedCount = 0
        for sourceIndex in sourceIndices {
            try work.consume()
            movedCount += state.windows[sourceIndex].tabs.count
        }
        guard destination.tabs.count <= state.limits.maximumTabsPerWindow - movedCount else {
            throw WindowArrangementPlanError.tooManyTabs(
                windowID: destination.id,
                maximum: state.limits.maximumTabsPerWindow
            )
        }
        var destinationTabs = destination.tabs
        destinationTabs.reserveCapacity(destination.tabs.count + movedCount)
        var movedTabIDs: [TabID] = []
        movedTabIDs.reserveCapacity(movedCount)
        for sourceID in state.windows.map(\.id) {
            try work.consume()
            guard let sourceIndex = sourceIndices.first(where: { state.windows[$0].id == sourceID }) else {
                continue
            }
            for tab in state.windows[sourceIndex].tabs {
                try work.consume()
                destinationTabs.append(tab)
                movedTabIDs.append(tab.id)
            }
        }
        var resultingOrder: [TabID] = []
        resultingOrder.reserveCapacity(destinationTabs.count)
        for tab in destinationTabs {
            try work.consume()
            resultingOrder.append(tab.id)
        }
        var windows: [WindowState] = []
        windows.reserveCapacity(state.windows.count - sourceIndices.count)
        let sourceSet = Set(request.sourceWindowIDs)
        for window in state.windows {
            try work.consume()
            if sourceSet.contains(window.id) { continue }
            if window.id == destination.id {
                windows.append(
                    WindowState(
                        validatedID: window.id,
                        revision: try window.revision.advanced(),
                        tabs: destinationTabs,
                        selectedTabID: window.selectedTabID,
                        isRestorable: window.isRestorable,
                        tabbingEligibility: window.tabbingEligibility,
                        split: window.split
                    )
                )
            } else {
                windows.append(window)
            }
        }
        let successor = try successor(
            of: state,
            windows: windows,
            selectedWindowID: destination.id,
            arrangement: .tabbed(destinationWindowID: destination.id),
            totalTabCount: state.totalTabCount
        )
        return Draft(
            effect: .tab(
                TabIntent(
                    destinationWindowID: destination.id,
                    movedTabIDs: movedTabIDs,
                    resultingTabOrder: resultingOrder,
                    resultingSelection: destination.selectedTabID
                )
            ),
            successor: successor
        )
    }

    private static func planTile(
        _ request: TileRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        guard !state.windows.isEmpty else {
            throw WindowArrangementPlanError.noSelectedWindow
        }
        guard request.columns >= 1, request.columns <= state.limits.maximumTileColumns else {
            throw WindowArrangementPlanError.invalidTileColumns(
                request.columns,
                maximum: state.limits.maximumTileColumns
            )
        }
        guard request.columns <= Limits.hardMaximumTileColumns else {
            throw WindowArrangementPlanError.invalidTileColumns(
                request.columns,
                maximum: Limits.hardMaximumTileColumns
            )
        }
        for window in state.windows {
            try work.consume()
            guard !window.isMinimizedEquivalentFullScreen else {
                throw WindowArrangementPlanError.contradictoryPresentationState(window.id)
            }
        }
        let rows = (state.windows.count + request.columns - 1) / request.columns
        var windowIDs: [WindowID] = []
        windowIDs.reserveCapacity(state.windows.count)
        var restoreIDs: [WindowID] = []
        for window in state.windows {
            try work.consume()
            windowIDs.append(window.id)
            if window.isMinimizedForArrangement { restoreIDs.append(window.id) }
        }
        let arrangement = Arrangement.tiled(columns: request.columns)
        try validate(arrangement, windows: state.windows, limits: state.limits, work: &work)
        guard arrangement != state.arrangement else {
            throw WindowArrangementPlanError.noStateChange
        }
        let successor = try successor(
            of: state,
            windows: state.windows,
            selectedWindowID: state.selectedWindowID,
            arrangement: arrangement,
            totalTabCount: state.totalTabCount
        )
        return Draft(
            effect: .tile(
                TileIntent(
                    columns: request.columns,
                    rows: rows,
                    windowIDs: windowIDs,
                    restoreMinimizedWindowIDs: restoreIDs
                )
            ),
            successor: successor
        )
    }

    private static func planCascade(
        _ request: CascadeRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        guard !state.windows.isEmpty else {
            throw WindowArrangementPlanError.noSelectedWindow
        }
        try validate(request.stride, field: .cascadeStride, limits: state.limits, work: &work)
        for window in state.windows {
            try work.consume()
            guard !window.isMinimizedEquivalentFullScreen else {
                throw WindowArrangementPlanError.contradictoryPresentationState(window.id)
            }
        }
        var windowIDs: [WindowID] = []
        windowIDs.reserveCapacity(state.windows.count)
        var restoreIDs: [WindowID] = []
        for window in state.windows {
            try work.consume()
            windowIDs.append(window.id)
            if window.isMinimizedForArrangement { restoreIDs.append(window.id) }
        }
        let arrangement = Arrangement.cascaded(stride: request.stride)
        try validate(arrangement, windows: state.windows, limits: state.limits, work: &work)
        guard arrangement != state.arrangement else {
            throw WindowArrangementPlanError.noStateChange
        }
        let successor = try successor(
            of: state,
            windows: state.windows,
            selectedWindowID: state.selectedWindowID,
            arrangement: arrangement,
            totalTabCount: state.totalTabCount
        )
        return Draft(
            effect: .cascade(
                CascadeIntent(
                    stride: request.stride,
                    windowIDs: windowIDs,
                    restoreMinimizedWindowIDs: restoreIDs
                )
            ),
            successor: successor
        )
    }

    private static func planDetach(
        _ request: DetachRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        guard state.windows.count < state.limits.maximumWindowCount else {
            throw WindowArrangementPlanError.tooManyWindows(maximum: state.limits.maximumWindowCount)
        }
        guard request.destination.initialRevision.windowID == request.destination.id,
            request.destination.initialRevision.generation == 0
        else {
            throw WindowArrangementPlanError.invalidInitialWindowRevision(request.destination.id)
        }
        for window in state.windows {
            try work.consume()
            guard window.id != request.destination.id else {
                throw WindowArrangementPlanError.duplicateWindowID(request.destination.id)
            }
        }
        let sourceIndex = try index(of: request.sourceWindowID, in: state, work: &work)
        let source = state.windows[sourceIndex]
        let sourceTabIndex = try tabIndex(of: request.tabID, in: source, work: &work)
        guard source.tabs.count > 1 else {
            throw WindowArrangementPlanError.onlyTabCannotDetach(request.tabID)
        }
        try validateTabbing(window: source, tabCount: source.tabs.count)
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
            tabbingEligibility: source.tabbingEligibility,
            split: source.split
        )
        let destinationWindow = WindowState(
            validatedID: request.destination.id,
            revision: request.destination.initialRevision,
            tabs: [tab],
            selectedTabID: tab.id,
            isRestorable: source.isRestorable,
            tabbingEligibility: source.tabbingEligibility,
            split: nil
        )
        var windows = state.windows
        windows[sourceIndex] = sourceWindow
        windows.insert(destinationWindow, at: sourceIndex + 1)
        try validate(state.arrangement, windows: windows, limits: state.limits, work: &work)
        let successor = try successor(
            of: state,
            windows: windows,
            selectedWindowID: destinationWindow.id,
            arrangement: state.arrangement,
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
        let destinationIndex = try index(of: request.destinationWindowID, in: state, work: &work)
        let source = state.windows[sourceIndex]
        let destination = state.windows[destinationIndex]
        let sourceTabIndex = try tabIndex(of: request.tabID, in: source, work: &work)
        try validateTabbing(window: source, tabCount: source.tabs.count)
        if source.id != destination.id,
            let reason = destination.tabbingEligibility.ineligibilityReason
        {
            throw WindowArrangementPlanError.windowTabbingIneligible(destination.id, reason)
        }
        let movedTab = source.tabs[sourceTabIndex]
        if source.id == destination.id {
            var tabs = source.tabs
            tabs.remove(at: sourceTabIndex)
            guard (0...tabs.count).contains(request.insertionIndex) else {
                throw WindowArrangementPlanError.invalidInsertionIndex(request.insertionIndex, windowID: destination.id)
            }
            tabs.insert(movedTab, at: request.insertionIndex)
            let selection = request.selectsMovedTab ? movedTab.id : source.selectedTabID
            var orderChanged = false
            for (actual, previous) in zip(tabs, source.tabs) {
                try work.consume()
                if actual.id != previous.id { orderChanged = true }
            }
            guard orderChanged || selection != source.selectedTabID else {
                throw WindowArrangementPlanError.noStateChange
            }
            var windows = state.windows
            windows[sourceIndex] = WindowState(
                validatedID: source.id,
                revision: try source.revision.advanced(),
                tabs: tabs,
                selectedTabID: selection,
                isRestorable: source.isRestorable,
                tabbingEligibility: source.tabbingEligibility,
                split: source.split
            )
            let selectedWindowID = request.selectsMovedTab ? source.id : state.selectedWindowID
            let successor = try successor(
                of: state,
                windows: windows,
                selectedWindowID: selectedWindowID,
                arrangement: state.arrangement,
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
            throw WindowArrangementPlanError.tooManyTabs(
                windowID: destination.id,
                maximum: state.limits.maximumTabsPerWindow
            )
        }
        guard (0...destination.tabs.count).contains(request.insertionIndex) else {
            throw WindowArrangementPlanError.invalidInsertionIndex(request.insertionIndex, windowID: destination.id)
        }
        var sourceTabs = source.tabs
        sourceTabs.remove(at: sourceTabIndex)
        var destinationTabs = destination.tabs
        destinationTabs.insert(movedTab, at: request.insertionIndex)
        let destinationSelection = request.selectsMovedTab ? movedTab.id : destination.selectedTabID
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
            tabbingEligibility: destination.tabbingEligibility,
            split: destination.split
        )
        if sourceTabs.isEmpty {
            windows.remove(at: sourceIndex)
            let adjustedDestinationIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
            windows[adjustedDestinationIndex] = updatedDestination
            try validate(state.arrangement, windows: windows, limits: state.limits, work: &work)
        } else {
            guard let sourceSelection else {
                throw WindowArrangementPlanError.missingSourceSelection(source.id)
            }
            windows[sourceIndex] = WindowState(
                validatedID: source.id,
                revision: try source.revision.advanced(),
                tabs: sourceTabs,
                selectedTabID: sourceSelection,
                isRestorable: source.isRestorable,
                tabbingEligibility: source.tabbingEligibility,
                split: source.split
            )
            windows[destinationIndex] = updatedDestination
            try validate(state.arrangement, windows: windows, limits: state.limits, work: &work)
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
            arrangement: state.arrangement,
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

    private static func planMerge(
        _ request: MergeRequest,
        state: State,
        work: inout Work
    ) throws -> Draft {
        guard state.windows.count > 1 else {
            throw WindowArrangementPlanError.noOtherWindows
        }
        let destinationIndex = try index(of: request.destinationWindowID, in: state, work: &work)
        let destination = state.windows[destinationIndex]
        try validateTabbing(window: destination, tabCount: destination.tabs.count)
        guard state.totalTabCount <= state.limits.maximumTabsPerWindow else {
            throw WindowArrangementPlanError.tooManyTabs(
                windowID: destination.id,
                maximum: state.limits.maximumTabsPerWindow
            )
        }
        var mergedTabs = destination.tabs
        mergedTabs.reserveCapacity(state.totalTabCount)
        var movedTabIDs: [TabID] = []
        movedTabIDs.reserveCapacity(state.totalTabCount - destination.tabs.count)
        var closedWindowIDs: [WindowID] = []
        closedWindowIDs.reserveCapacity(state.windows.count - 1)
        for window in state.windows {
            try work.consume()
            if window.id == destination.id { continue }
            try validateTabbing(window: window, tabCount: window.tabs.count)
            for tab in window.tabs {
                try work.consume()
                mergedTabs.append(tab)
                movedTabIDs.append(tab.id)
            }
            closedWindowIDs.append(window.id)
        }
        var resultingOrder: [TabID] = []
        resultingOrder.reserveCapacity(mergedTabs.count)
        for tab in mergedTabs {
            try work.consume()
            resultingOrder.append(tab.id)
        }
        let mergedWindow = WindowState(
            validatedID: destination.id,
            revision: try destination.revision.advanced(),
            tabs: mergedTabs,
            selectedTabID: destination.selectedTabID,
            isRestorable: destination.isRestorable,
            tabbingEligibility: destination.tabbingEligibility,
            split: destination.split
        )
        let successor = try successor(
            of: state,
            windows: [mergedWindow],
            selectedWindowID: destination.id,
            arrangement: .separateWindows,
            totalTabCount: state.totalTabCount
        )
        return Draft(
            effect: .merge(
                MergeIntent(
                    destinationWindowID: destination.id,
                    movedTabCount: movedTabIDs.count,
                    resultingTabOrder: resultingOrder,
                    resultingSelection: destination.selectedTabID,
                    closedWindowIDs: closedWindowIDs
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
                throw WindowArrangementPlanError.restorationReceiptCountMismatch(
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
                    expected.expectedPublicationCAS == receipt.request.expectedPublicationCAS,
                    expected.expectedPublicationCAS == plan.publicationCAS,
                    expected.expectedSessionRevision == receipt.request.expectedSessionRevision,
                    expected.expectedWindowRevision == receipt.request.expectedWindowRevision,
                    expected.windowID == receipt.request.windowID,
                    expected.tabID == receipt.request.tabID,
                    expected.materialization == receipt.request.materialization
                else {
                    throw WindowArrangementPlanError.unknownRestorationReceipt(receipt.tabID)
                }
                guard byTabID.updateValue(receipt, forKey: receipt.tabID) == nil else {
                    throw WindowArrangementPlanError.duplicateRestorationReceipt(receipt.tabID)
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
                    guard aggregateStringBytes <= plan.request.limits.maximumAggregateStringUTF8Bytes - codeBytes,
                        aggregateStringBytes + codeBytes <= plan.request.limits.maximumAggregateStringUTF8Bytes - messageBytes
                    else {
                        throw WindowArrangementPlanError.aggregateStringsTooLarge(
                            maximumUTF8Bytes: plan.request.limits.maximumAggregateStringUTF8Bytes
                        )
                    }
                    aggregateStringBytes += codeBytes + messageBytes
                }
            }
            let orderedReceipts = try plan.materializations.map { materialization in
                try work.consume()
                guard let receipt = byTabID[materialization.tabID] else {
                    throw WindowArrangementPlanError.missingRestorationReceipt(materialization.tabID)
                }
                return receipt
            }
            var restoredWindows: [WindowState] = []
            var windowOutcomes: [WindowRestorationOutcome] = []
            var restoredTotalTabCount = 0
            restoredWindows.reserveCapacity(plan.request.windows.count)
            windowOutcomes.reserveCapacity(plan.request.windows.count)
            for requestedWindow in plan.request.windows {
                try work.consume()
                var tabs: [TabState] = []
                var skipped: [TabID] = []
                var failed: [TabID] = []
                var requestedTabSelectionOrdinal: Int?
                tabs.reserveCapacity(requestedWindow.tabs.count)
                for requestedTab in requestedWindow.tabs {
                    try work.consume()
                    if requestedTab.id == requestedWindow.selectedTabID {
                        requestedTabSelectionOrdinal = tabs.count
                    }
                    guard let receipt = byTabID[requestedTab.id] else {
                        throw WindowArrangementPlanError.missingRestorationReceipt(requestedTab.id)
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
                    guard let requestedTabSelectionOrdinal else {
                        throw WindowArrangementPlanError.selectedTabNotFound(
                            windowID: requestedWindow.id,
                            tabID: requestedWindow.selectedTabID
                        )
                    }
                    let selectedTabID =
                        requestedSelectionWasRestored
                        ? requestedWindow.selectedTabID
                        : tabs[min(requestedTabSelectionOrdinal, tabs.count - 1)].id
                    let revision =
                        tabs.count == requestedWindow.tabs.count
                        ? requestedWindow.revision
                        : try requestedWindow.revision.advanced()
                    restoredWindows.append(
                        WindowState(
                            validatedID: requestedWindow.id,
                            revision: revision,
                            tabs: tabs,
                            selectedTabID: selectedTabID,
                            isRestorable: requestedWindow.isRestorable,
                            tabbingEligibility: requestedWindow.tabbingEligibility,
                            split: requestedWindow.split
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
            } else {
                selectedWindowID = restoredWindows.first?.id
            }
            let arrangement: Arrangement
            switch plan.request.arrangement {
            case .separateWindows:
                arrangement = .separateWindows
            case .tiled(let columns):
                arrangement = restoredWindows.isEmpty ? .separateWindows : .tiled(columns: columns)
            case .cascaded(let stride):
                arrangement = restoredWindows.isEmpty ? .separateWindows : .cascaded(stride: stride)
            case .tabbed(let destination):
                arrangement = restoredWindowIDs.contains(destination) ? .tabbed(destinationWindowID: destination) : .separateWindows
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
            if restoredWindows.isEmpty {
                guard arrangement == .separateWindows else {
                    throw WindowArrangementPlanError.invalidArrangement("empty restoration must use separate windows")
                }
                if let selectedWindowID {
                    throw WindowArrangementPlanError.selectedWindowNotFound(selectedWindowID)
                }
            }
            let restoredState = State(
                validatedRevision: restoredRevision,
                ownerID: plan.request.ownerID,
                windows: restoredWindows,
                selectedWindowID: selectedWindowID,
                arrangement: arrangement,
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
        } catch let error as WindowArrangementPlanError {
            throw error
        } catch {
            throw WindowArrangementPlanError.cancelled
        }
    }

    private static func successor(
        of state: State,
        windows: [WindowState],
        selectedWindowID: WindowID?,
        arrangement: Arrangement,
        totalTabCount: Int
    ) throws -> State {
        State(
            validatedRevision: try state.revision.advanced(),
            ownerID: state.ownerID,
            windows: windows,
            selectedWindowID: selectedWindowID,
            arrangement: arrangement,
            tabWidthPreference: state.tabWidthPreference,
            limits: state.limits,
            totalTabCount: totalTabCount
        )
    }

    private static func proxyWindowStates(
        _ windows: [RestorationWindow],
        work: inout Work
    ) throws -> [WindowState] {
        var proxy: [WindowState] = []
        proxy.reserveCapacity(windows.count)
        for window in windows {
            try work.consume()
            var tabs: [TabState] = []
            tabs.reserveCapacity(window.tabs.count)
            for tab in window.tabs {
                try work.consume()
                tabs.append(
                    TabState(
                        validatedID: tab.id,
                        title: tab.title,
                        materialization: tab.materialization,
                        isDirty: tab.isDirty,
                        closeVeto: tab.closeVeto,
                        isRestorable: tab.isRestorable,
                        tabbingEligibility: tab.tabbingEligibility
                    )
                )
            }
            proxy.append(
                WindowState(
                    validatedID: window.id,
                    revision: window.revision,
                    tabs: tabs,
                    selectedTabID: window.selectedTabID,
                    isRestorable: window.isRestorable,
                    tabbingEligibility: window.tabbingEligibility,
                    split: window.split
                )
            )
        }
        return proxy
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
        throw WindowArrangementPlanError.windowNotFound(windowID)
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
        throw WindowArrangementPlanError.tabNotFound(tabID)
    }

    private static func validateTabbing(window: WindowState, tabCount: Int) throws {
        if let reason = window.tabbingEligibility.ineligibilityReason {
            throw WindowArrangementPlanError.windowTabbingIneligible(window.id, reason)
        }
        for tab in window.tabs {
            if let reason = tab.tabbingEligibility.ineligibilityReason {
                throw WindowArrangementPlanError.tabTabbingIneligible(tab.id, reason)
            }
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
            throw WindowArrangementPlanError.invalidTabWidth(width)
        }
    }

    private static func validate(
        _ split: SplitConfiguration,
        limits: Limits,
        work: inout Work
    ) throws {
        try work.consume()
        guard split.fraction.isFinite,
            split.fraction >= limits.minimumSplitFraction,
            split.fraction <= limits.maximumSplitFraction
        else {
            throw WindowArrangementPlanError.invalidSplitFraction(split.fraction)
        }
    }

    private enum WidthField {
        case cascadeStride
    }

    private static func validate(
        _ value: Double,
        field: WidthField,
        limits: Limits,
        work: inout Work
    ) throws {
        try work.consume()
        switch field {
        case .cascadeStride:
            guard value.isFinite,
                value >= limits.minimumCascadeStride,
                value <= limits.maximumCascadeStride
            else {
                throw WindowArrangementPlanError.invalidCascadeStride(
                    value,
                    minimum: limits.minimumCascadeStride,
                    maximum: limits.maximumCascadeStride
                )
            }
        }
    }

    private static func validate(
        _ arrangement: Arrangement,
        windows: [WindowState],
        limits: Limits,
        work: inout Work
    ) throws {
        switch arrangement {
        case .separateWindows:
            try work.consume()
        case .tiled(let columns):
            try work.consume()
            guard columns >= 1, columns <= limits.maximumTileColumns else {
                throw WindowArrangementPlanError.invalidTileColumns(columns, maximum: limits.maximumTileColumns)
            }
        case .cascaded(let stride):
            try validate(stride, field: .cascadeStride, limits: limits, work: &work)
        case .tabbed(let destination):
            var found = false
            for window in windows {
                try work.consume()
                if window.id == destination { found = true }
            }
            guard found else {
                throw WindowArrangementPlanError.selectedWindowNotFound(destination)
            }
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
            throw WindowArrangementPlanError.invalidRestorationFailureCode
        }
        var count = 0
        for byte in code.utf8 {
            if count % Limits.hardMaximumCancellationCheckInterval == 0 {
                try checkTaskCancellation()
            }
            guard count < Limits.hardMaximumRestorationCodeUTF8Bytes else {
                throw WindowArrangementPlanError.restorationFailureCodeTooLarge(
                    maximumUTF8Bytes: Limits.hardMaximumRestorationCodeUTF8Bytes
                )
            }
            guard
                (0x30...0x39).contains(byte)
                    || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte)
                    || byte == 0x2D || byte == 0x2E || byte == 0x5F
            else {
                throw WindowArrangementPlanError.invalidRestorationFailureCode
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

    private static func invalidStringError(_ field: StringField) -> WindowArrangementPlanError {
        switch field {
        case .title: .invalidTitle
        case .restorationCode: .invalidRestorationFailureCode
        case .restorationMessage: .invalidRestorationFailureMessage
        }
    }

    private static func stringLimitError(
        _ field: StringField,
        maximum: Int
    ) -> WindowArrangementPlanError {
        switch field {
        case .title: .titleTooLarge(maximumUTF8Bytes: maximum)
        case .restorationCode: .restorationFailureCodeTooLarge(maximumUTF8Bytes: maximum)
        case .restorationMessage: .restorationFailureMessageTooLarge(maximumUTF8Bytes: maximum)
        }
    }

    fileprivate static func checkTaskCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw WindowArrangementPlanError.cancelled
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
                throw WindowArrangementPlanError.workLimitExceeded(maximum: maximum)
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
            } catch let error as WindowArrangementPlanError {
                throw error
            } catch is CancellationError {
                throw WindowArrangementPlanError.cancelled
            } catch {
                throw WindowArrangementPlanError.cancellationCheckFailed
            }
        }

        mutating func finish() throws {
            try checkCancellation()
        }
    }
}

extension WindowArrangementPlan.WindowState {
    fileprivate var isMinimizedForArrangement: Bool { false }

    fileprivate var isMinimizedEquivalentFullScreen: Bool { false }
}

public enum WindowArrangementPlanError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case cancellationCheckFailed
    case invalidLimit(WindowArrangementPlan.Limit)
    case workLimitExceeded(maximum: Int)
    case tooManyWindows(maximum: Int)
    case tooManyTabs(windowID: WindowArrangementPlan.WindowID, maximum: Int)
    case tooManyTotalTabs(maximum: Int)
    case tooManyRestorationItems(maximum: Int)
    case emptyWindow(WindowArrangementPlan.WindowID)
    case duplicateWindowID(WindowArrangementPlan.WindowID)
    case duplicateTabID(WindowArrangementPlan.TabID)
    case missingSelectedWindow
    case selectedWindowNotFound(WindowArrangementPlan.WindowID)
    case selectedTabNotFound(windowID: WindowArrangementPlan.WindowID, tabID: WindowArrangementPlan.TabID)
    case windowNotFound(WindowArrangementPlan.WindowID)
    case tabNotFound(WindowArrangementPlan.TabID)
    case windowRevisionIdentityMismatch(
        expected: WindowArrangementPlan.WindowID,
        actual: WindowArrangementPlan.WindowID
    )
    case invalidInitialWindowRevision(WindowArrangementPlan.WindowID)
    case sessionRevisionExhausted(WindowArrangementPlan.SessionLineage)
    case windowRevisionExhausted(WindowArrangementPlan.WindowID)
    case restorationPublicationEpochExhausted(WindowArrangementPlan.OwnerID)
    case staleRestorationPublication(
        expectedOwnerID: WindowArrangementPlan.OwnerID,
        expectedEpoch: UInt64,
        actualOwnerID: WindowArrangementPlan.OwnerID,
        actualEpoch: UInt64
    )
    case staleState(expected: WindowArrangementPlan.StateCAS, actual: WindowArrangementPlan.StateCAS)
    case noSelectedWindow
    case noOtherWindows
    case noStateChange
    case onlyTabCannotDetach(WindowArrangementPlan.TabID)
    case missingSourceSelection(WindowArrangementPlan.WindowID)
    case invalidInsertionIndex(Int, windowID: WindowArrangementPlan.WindowID)
    case windowTabbingIneligible(
        WindowArrangementPlan.WindowID,
        WindowArrangementPlan.IneligibilityReason
    )
    case tabTabbingIneligible(
        WindowArrangementPlan.TabID,
        WindowArrangementPlan.IneligibilityReason
    )
    case invalidTabWidth(Double)
    case invalidSplitFraction(Double)
    case invalidTileColumns(Int, maximum: Int)
    case invalidCascadeStride(Double, minimum: Double, maximum: Double)
    case invalidArrangement(String)
    case contradictoryPresentationState(WindowArrangementPlan.WindowID)
    case emptyTabGroup
    case tabGroupIncludesDestination(WindowArrangementPlan.WindowID)
    case invalidTitle
    case titleTooLarge(maximumUTF8Bytes: Int)
    case aggregateStringsTooLarge(maximumUTF8Bytes: Int)
    case restorationReceiptCountMismatch(expected: Int, actual: Int)
    case unknownRestorationReceipt(WindowArrangementPlan.TabID)
    case duplicateRestorationReceipt(WindowArrangementPlan.TabID)
    case missingRestorationReceipt(WindowArrangementPlan.TabID)
    case invalidRestorationFailureCode
    case invalidRestorationFailureMessage
    case restorationFailureCodeTooLarge(maximumUTF8Bytes: Int)
    case restorationFailureMessageTooLarge(maximumUTF8Bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Window arrangement planning was cancelled."
        case .cancellationCheckFailed:
            "Window arrangement cancellation check failed."
        case .invalidLimit(let limit):
            "Invalid window arrangement limit: \(limit.rawValue)."
        case .workLimitExceeded(let maximum):
            "Window arrangement planning exceeds the \(maximum)-unit work limit."
        case .tooManyWindows(let maximum):
            "Window arrangement exceeds the \(maximum)-window limit."
        case .tooManyTabs(let windowID, let maximum):
            "Window \(windowID.rawValue) exceeds the \(maximum)-tab limit."
        case .tooManyTotalTabs(let maximum):
            "Window arrangement exceeds the \(maximum)-tab total limit."
        case .tooManyRestorationItems(let maximum):
            "Window arrangement restoration exceeds the \(maximum)-item limit."
        case .emptyWindow(let windowID):
            "Window \(windowID.rawValue) contains no tabs."
        case .duplicateWindowID(let windowID):
            "Window identity \(windowID.rawValue) is duplicated."
        case .duplicateTabID(let tabID):
            "Tab identity \(tabID.rawValue) is duplicated."
        case .missingSelectedWindow:
            "A nonempty arrangement session requires a selected window."
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
            "Arrangement session lineage \(lineage.rawValue) exhausted its generation space."
        case .windowRevisionExhausted(let windowID):
            "Window \(windowID.rawValue) exhausted its generation space."
        case .restorationPublicationEpochExhausted(let ownerID):
            "Restoration owner \(ownerID.rawValue) exhausted its publication epoch space."
        case .staleRestorationPublication(let expectedOwnerID, let expectedEpoch, let actualOwnerID, let actualEpoch):
            "Restoration publication expected owner \(expectedOwnerID.rawValue) epoch \(expectedEpoch), not owner \(actualOwnerID.rawValue) epoch \(actualEpoch)."
        case .staleState(let expected, let actual):
            "Arrangement state changed from session generation \(expected.sessionRevision.generation) to \(actual.sessionRevision.generation)."
        case .noSelectedWindow:
            "Window arrangement command requires a selected window."
        case .noOtherWindows:
            "Window arrangement command requires another window."
        case .noStateChange:
            "Window arrangement command would not change state."
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
        case .invalidTabWidth(let width):
            "Preferred tab width \(width) is non-finite or outside configured bounds."
        case .invalidSplitFraction(let fraction):
            "Split fraction \(fraction) is non-finite or outside configured bounds."
        case .invalidTileColumns(let columns, let maximum):
            "Tile column count \(columns) exceeds the \(maximum)-column limit."
        case .invalidCascadeStride(let stride, let minimum, let maximum):
            "Cascade stride \(stride) is outside \(minimum)-\(maximum) bounds."
        case .invalidArrangement(let reason):
            "Invalid window arrangement: \(reason)."
        case .contradictoryPresentationState(let windowID):
            "Window \(windowID.rawValue) has contradictory presentation state."
        case .emptyTabGroup:
            "Tab grouping requires at least one source window."
        case .tabGroupIncludesDestination(let windowID):
            "Tab grouping source \(windowID.rawValue) must not name the destination."
        case .invalidTitle:
            "Arrangement tab title is empty or contains unsupported control characters."
        case .titleTooLarge(let maximum):
            "Arrangement tab title exceeds \(maximum) UTF-8 bytes."
        case .aggregateStringsTooLarge(let maximum):
            "Arrangement strings exceed \(maximum) aggregate UTF-8 bytes."
        case .restorationReceiptCountMismatch(let expected, let actual):
            "Arrangement restoration expected \(expected) item receipts but received \(actual)."
        case .unknownRestorationReceipt(let tabID):
            "Arrangement restoration receipt names unknown tab \(tabID.rawValue)."
        case .duplicateRestorationReceipt(let tabID):
            "Arrangement restoration receipt repeats tab \(tabID.rawValue)."
        case .missingRestorationReceipt(let tabID):
            "Arrangement restoration receipt omits tab \(tabID.rawValue)."
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
