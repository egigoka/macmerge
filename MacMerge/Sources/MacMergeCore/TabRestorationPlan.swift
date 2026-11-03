import Foundation

/// Bounded, UI-independent restoration mapping from persisted comparison-tab snapshots to reopen intents.
///
/// This model owns no AppKit objects, claims no native tab bar, and performs no persistence,
/// document materialization, window management, or close confirmation. Callers retain authority
/// over stored bytes, comparison content, native windows, close authorization, and publication.
/// Mapping is a pure value transform bound to an exact owner/epoch publication CAS and an exact
/// session revision; an executor must revalidate both before publishing any restored state.
///
/// Deterministic order: stable persisted window order, then left-to-right tab order. Close
/// preflight order is the exact reverse, matching `ComparisonTabLifecycle` close-target order so
/// an executor can authorize every target before any owner-state mutation. Dirty and veto marks
/// are advisory snapshots; the executor still requests current owner authorization per step.
public enum TabRestorationPlan: Sendable {
    public typealias WindowID = ComparisonTabLifecycle.WindowID
    public typealias TabID = ComparisonTabLifecycle.TabID
    public typealias SessionLineage = ComparisonTabLifecycle.SessionLineage
    public typealias CloseVeto = ComparisonTabLifecycle.CloseVeto
    public typealias CloseVetoReason = ComparisonTabLifecycle.CloseVetoReason
    public typealias TabbingEligibility = ComparisonTabLifecycle.TabbingEligibility
    public typealias IneligibilityReason = ComparisonWindowCommandState.TabbingIneligibilityReason
    public typealias OwnerID = ComparisonTabLifecycle.RestorationOwnerID
    public typealias SessionRevision = ComparisonTabLifecycle.SessionRevision
    public typealias WindowRevision = ComparisonTabLifecycle.WindowRevision
    public typealias PublicationCAS = ComparisonTabLifecycle.RestorationPublicationCAS
    public typealias TabWidthPreference = ComparisonTabLifecycle.TabWidthPreference
    public typealias Limits = ComparisonTabLifecycle.Limits
    public typealias CancellationCheck = ComparisonTabLifecycle.CancellationCheck

    public static let currentSchemaVersion = 1
    public static let decodeCancellationCheckInterval = 16

    /// Hard cap for persisted snapshot input. Reuses the session persistence bound so one
    /// snapshot can hold at least one maximum-size session; per-tab session bytes still apply.
    public static var maximumSnapshotBytes: Int {
        ComparisonSessionState.maximumPersistedBytes
    }

    /// Persisted per-tab snapshot. `session` holds `ComparisonSessionState.encodedData()` bytes.
    public struct SnapshotTab: Codable, Equatable, Sendable {
        public let id: TabID
        public let title: String
        public let session: Data
        public let isDirty: Bool
        public let vetoReason: CloseVetoReason?
        public let isRestorable: Bool
        public let tabbingReason: IneligibilityReason?

        public var veto: CloseVeto {
            guard let vetoReason else { return .none }
            return .vetoed(vetoReason)
        }

        public var tabbingEligibility: TabbingEligibility {
            guard let tabbingReason else { return .eligible }
            return .ineligible(tabbingReason)
        }

        public init(
            id: TabID,
            title: String,
            session: Data,
            isDirty: Bool = false,
            veto: CloseVeto = .none,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible
        ) {
            self.id = id
            self.title = title
            self.session = session
            self.isDirty = isDirty
            vetoReason = veto.reason
            self.isRestorable = isRestorable
            tabbingReason = tabbingEligibility.ineligibilityReason
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: WireKey.self)
            try WireKey.requireExactKeys(
                container,
                expected: ["id", "title", "session", "isDirty", "isRestorable"],
                optional: ["vetoReason", "tabbingReason"]
            )
            id = try container.decode(TabID.self, forKey: WireKey("id"))
            title = try container.decode(String.self, forKey: WireKey("title"))
            session = try container.decode(Data.self, forKey: WireKey("session"))
            isDirty = try container.decode(Bool.self, forKey: WireKey("isDirty"))
            vetoReason = try container.decodeIfPresent(CloseVetoReason.self, forKey: WireKey("vetoReason"))
            isRestorable = try container.decode(Bool.self, forKey: WireKey("isRestorable"))
            tabbingReason = try container.decodeIfPresent(IneligibilityReason.self, forKey: WireKey("tabbingReason"))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: WireKey.self)
            try container.encode(id, forKey: WireKey("id"))
            try container.encode(title, forKey: WireKey("title"))
            try container.encode(session, forKey: WireKey("session"))
            try container.encode(isDirty, forKey: WireKey("isDirty"))
            try container.encodeIfPresent(vetoReason, forKey: WireKey("vetoReason"))
            try container.encode(isRestorable, forKey: WireKey("isRestorable"))
            try container.encodeIfPresent(tabbingReason, forKey: WireKey("tabbingReason"))
        }
    }

    /// Persisted per-window snapshot. Tabs are stored in visual left-to-right order.
    public struct SnapshotWindow: Codable, Equatable, Sendable {
        public let id: WindowID
        public let generation: UInt64
        public let selectedTabID: TabID
        public let isRestorable: Bool
        public let tabbingReason: IneligibilityReason?
        public let tabs: [SnapshotTab]

        public var revision: WindowRevision {
            WindowRevision(windowID: id, generation: generation)
        }

        public var tabbingEligibility: TabbingEligibility {
            guard let tabbingReason else { return .eligible }
            return .ineligible(tabbingReason)
        }

        public init(
            id: WindowID,
            generation: UInt64,
            selectedTabID: TabID,
            isRestorable: Bool = true,
            tabbingEligibility: TabbingEligibility = .eligible,
            tabs: [SnapshotTab]
        ) {
            self.id = id
            self.generation = generation
            self.selectedTabID = selectedTabID
            self.isRestorable = isRestorable
            tabbingReason = tabbingEligibility.ineligibilityReason
            self.tabs = tabs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: WireKey.self)
            try WireKey.requireExactKeys(
                container,
                expected: ["id", "generation", "selectedTabID", "isRestorable", "tabs"],
                optional: ["tabbingReason"]
            )
            id = try container.decode(WindowID.self, forKey: WireKey("id"))
            generation = try container.decode(UInt64.self, forKey: WireKey("generation"))
            selectedTabID = try container.decode(TabID.self, forKey: WireKey("selectedTabID"))
            isRestorable = try container.decode(Bool.self, forKey: WireKey("isRestorable"))
            tabbingReason = try container.decodeIfPresent(IneligibilityReason.self, forKey: WireKey("tabbingReason"))
            var tabsContainer = try container.nestedUnkeyedContainer(forKey: WireKey("tabs"))
            guard let count = tabsContainer.count else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: container.codingPath, debugDescription: "Tab list is not countable.")
                )
            }
            guard count >= 1, count <= Limits.hardMaximumTabsPerWindow else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: container.codingPath, debugDescription: "Tab list is not bounded.")
                )
            }
            var decoded: [SnapshotTab] = []
            decoded.reserveCapacity(count)
            while !tabsContainer.isAtEnd {
                decoded.append(try tabsContainer.decode(SnapshotTab.self))
            }
            tabs = decoded
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: WireKey.self)
            try container.encode(id, forKey: WireKey("id"))
            try container.encode(generation, forKey: WireKey("generation"))
            try container.encode(selectedTabID, forKey: WireKey("selectedTabID"))
            try container.encode(isRestorable, forKey: WireKey("isRestorable"))
            try container.encodeIfPresent(tabbingReason, forKey: WireKey("tabbingReason"))
            try container.encode(tabs, forKey: WireKey("tabs"))
        }
    }

    /// Versioned persisted snapshot of every restorable comparison tab.
    public struct Snapshot: Codable, Equatable, Sendable {
        public let schemaVersion: Int
        public let ownerID: OwnerID
        public let expectedEpoch: UInt64
        public let lineage: SessionLineage
        public let sessionGeneration: UInt64
        public let selectedWindowID: WindowID?
        public let tabWidth: Double?
        public let windows: [SnapshotWindow]

        public var sessionRevision: SessionRevision {
            SessionRevision(lineage: lineage, generation: sessionGeneration)
        }

        public var tabWidthPreference: TabWidthPreference {
            guard let tabWidth else { return .automatic }
            return .fixed(tabWidth)
        }

        public init(
            ownerID: OwnerID,
            expectedEpoch: UInt64,
            sessionRevision: SessionRevision,
            selectedWindowID: WindowID?,
            tabWidthPreference: TabWidthPreference = .automatic,
            windows: [SnapshotWindow]
        ) {
            schemaVersion = TabRestorationPlan.currentSchemaVersion
            self.ownerID = ownerID
            self.expectedEpoch = expectedEpoch
            lineage = sessionRevision.lineage
            sessionGeneration = sessionRevision.generation
            self.selectedWindowID = selectedWindowID
            switch tabWidthPreference {
            case .automatic:
                tabWidth = nil
            case .fixed(let width):
                tabWidth = width
            }
            self.windows = windows
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: WireKey.self)
            try WireKey.requireExactKeys(
                container,
                expected: ["schemaVersion", "ownerID", "expectedEpoch", "lineage", "sessionGeneration", "windows"],
                optional: ["selectedWindowID", "tabWidth"]
            )
            let decodedVersion = try container.decode(Int.self, forKey: WireKey("schemaVersion"))
            guard decodedVersion == TabRestorationPlan.currentSchemaVersion else {
                throw TabRestorationPlanError.unsupportedSchemaVersion(decodedVersion)
            }
            schemaVersion = decodedVersion
            ownerID = try container.decode(OwnerID.self, forKey: WireKey("ownerID"))
            expectedEpoch = try container.decode(UInt64.self, forKey: WireKey("expectedEpoch"))
            lineage = try container.decode(SessionLineage.self, forKey: WireKey("lineage"))
            sessionGeneration = try container.decode(UInt64.self, forKey: WireKey("sessionGeneration"))
            selectedWindowID = try container.decodeIfPresent(WindowID.self, forKey: WireKey("selectedWindowID"))
            tabWidth = try container.decodeIfPresent(Double.self, forKey: WireKey("tabWidth"))
            var windowsContainer = try container.nestedUnkeyedContainer(forKey: WireKey("windows"))
            guard let count = windowsContainer.count else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: container.codingPath, debugDescription: "Window list is not countable.")
                )
            }
            guard count <= Limits.hardMaximumWindowCount else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: container.codingPath, debugDescription: "Window list is not bounded.")
                )
            }
            var decoded: [SnapshotWindow] = []
            decoded.reserveCapacity(count)
            while !windowsContainer.isAtEnd {
                decoded.append(try windowsContainer.decode(SnapshotWindow.self))
            }
            windows = decoded
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: WireKey.self)
            try container.encode(schemaVersion, forKey: WireKey("schemaVersion"))
            try container.encode(ownerID, forKey: WireKey("ownerID"))
            try container.encode(expectedEpoch, forKey: WireKey("expectedEpoch"))
            try container.encode(lineage, forKey: WireKey("lineage"))
            try container.encode(sessionGeneration, forKey: WireKey("sessionGeneration"))
            try container.encodeIfPresent(selectedWindowID, forKey: WireKey("selectedWindowID"))
            try container.encodeIfPresent(tabWidth, forKey: WireKey("tabWidth"))
            try container.encode(windows, forKey: WireKey("windows"))
        }
    }

    /// One deterministic reopen step. Dirty and veto marks are advisory; the executor must
    /// request current owner authorization before mutating owner state.
    public struct ReopenIntent: Equatable, Sendable {
        /// Zero-based position in deterministic reopen order.
        public let ordinal: Int
        public let windowID: WindowID
        public let tabID: TabID
        public let title: String
        public let sessionState: ComparisonSessionState
        public let isDirty: Bool
        public let veto: CloseVeto
        public let isSelectedTab: Bool
        public let isSelectedWindow: Bool

        public var requiresConfirmation: Bool { isDirty }
        public var isVetoed: Bool { veto.isVetoed }

        /// Fail-closed live dirty recheck. Executor must call per step before closing.
        public func liveRequiresConfirmation(liveDirtyTabIDs: Set<TabID>) -> Bool {
            requiresConfirmation || liveDirtyTabIDs.contains(tabID)
        }
    }

    /// Planner output: reopen intents in stable window order, then left-to-right tab order.
    public struct ReopenPlan: Equatable, Sendable {
        public let publicationCAS: PublicationCAS
        public let sessionRevision: SessionRevision
        public let selectedWindowID: WindowID?
        public let tabWidthPreference: TabWidthPreference
        /// Stable window order, then left-to-right tab order. Executor reopens in this order.
        public let intents: [ReopenIntent]
        /// Exact reverse of `intents`, matching lifecycle close-target order. Executor
        /// preflights every target before any owner-state mutation.
        public let closePreflightTabIDs: [TabID]
        /// Sorted ascending for stable diagnostics.
        public let dirtyTabIDs: [TabID]
        /// Sorted ascending for stable diagnostics.
        public let vetoedTabIDs: [TabID]
        public let restoration: ComparisonTabLifecycle.RestorationPlan
        public let workPerformed: Int

        public var isEmpty: Bool { intents.isEmpty }
        public var requiresConfirmationCount: Int { dirtyTabIDs.count }
        public var vetoedCount: Int { vetoedTabIDs.count }

        /// Exact owner/epoch revalidation. Executor must call before publishing restored state.
        public func validate(ownerID: OwnerID, epoch: UInt64) throws {
            do {
                try publicationCAS.validate(ownerID: ownerID, epoch: epoch)
            } catch let error as ComparisonTabLifecycleError {
                throw TabRestorationPlanError.restoration(error)
            } catch {
                throw TabRestorationPlanError.cancelled
            }
        }

        /// Validates exact session revision equality against the snapshot revision. This does not
        /// accept a lifecycle-advanced receipt revision; the caller must pass the snapshot revision.
        public func validate(sessionRevision: SessionRevision) throws {
            guard sessionRevision == self.sessionRevision else {
                throw TabRestorationPlanError.staleSessionRevision(
                    expected: self.sessionRevision,
                    actual: sessionRevision
                )
            }
        }

        /// Fail-closed live dirty recheck for one intent. Executor must call per step.
        public func liveRequiresConfirmation(
            for intent: ReopenIntent,
            liveDirtyTabIDs: Set<TabID>
        ) -> Bool {
            intent.liveRequiresConfirmation(liveDirtyTabIDs: liveDirtyTabIDs)
        }
    }

    /// Canonical snapshot encoder: sorted keys, no escaped slashes.
    public static func encodeSnapshot(_ snapshot: Snapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(snapshot)
        } catch let error as TabRestorationPlanError {
            throw error
        } catch {
            throw TabRestorationPlanError.malformedPersistence
        }
    }

    /// Hostile-decode fail-closed snapshot read: size preflight, exact keys, pinned schema
    /// version, hard-cap counts, hard-cap title bytes, and per-tab session byte caps.
    public static func decodeSnapshot(
        from data: Data,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Snapshot {
        try checked(cancellationCheck)
        guard data.count <= maximumSnapshotBytes else {
            throw TabRestorationPlanError.snapshotTooLarge(maximumBytes: maximumSnapshotBytes)
        }
        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch let error as TabRestorationPlanError {
            throw error
        } catch {
            throw TabRestorationPlanError.malformedPersistence
        }
        try checked(cancellationCheck)
        var totalTabs = 0
        for (windowIndex, window) in snapshot.windows.enumerated() {
            if windowIndex % decodeCancellationCheckInterval == 0 {
                try checked(cancellationCheck)
            }
            guard totalTabs <= Limits.hardMaximumRestorationItemCount - window.tabs.count else {
                throw TabRestorationPlanError.tooManyRestorationItems(
                    maximum: Limits.hardMaximumRestorationItemCount
                )
            }
            totalTabs += window.tabs.count
            for tab in window.tabs {
                guard tab.session.count <= ComparisonSessionState.maximumEncodedBytes else {
                    throw TabRestorationPlanError.sessionStateTooLarge(
                        maximumBytes: ComparisonSessionState.maximumEncodedBytes
                    )
                }
                guard tab.title.utf8.count <= Limits.hardMaximumTitleUTF8Bytes else {
                    throw TabRestorationPlanError.titleTooLarge(
                        maximumUTF8Bytes: Limits.hardMaximumTitleUTF8Bytes
                    )
                }
            }
        }
        try checked(cancellationCheck)
        return snapshot
    }

    /// Maps persisted snapshot bytes to ordered reopen intents plus the lifecycle
    /// restoration plan an executor materializes. Pure value transform; no UI or mutation.
    public static func plan(
        snapshotData: Data,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ReopenPlan {
        let snapshot = try decodeSnapshot(from: snapshotData, cancellationCheck: cancellationCheck)
        return try plan(snapshot, limits: limits, cancellationCheck: cancellationCheck)
    }

    /// Maps an already-decoded snapshot to ordered reopen intents.
    public static func plan(
        _ snapshot: Snapshot,
        limits: Limits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ReopenPlan {
        var work = Work(limits: limits, cancellationCheck: cancellationCheck)
        do {
            try work.checkCancellation()
            let publicationCAS = try mapLifecycle {
                try PublicationCAS(ownerID: snapshot.ownerID, expectedEpoch: snapshot.expectedEpoch)
            }
            var restorationWindows: [ComparisonTabLifecycle.RestorationWindow] = []
            restorationWindows.reserveCapacity(snapshot.windows.count)
            var sessionsByTabID: [TabID: ComparisonSessionState] = [:]
            sessionsByTabID.reserveCapacity(min(limits.maximumRestorationItemCount, 256))
            for window in snapshot.windows {
                try work.consume()
                var restorationTabs: [ComparisonTabLifecycle.RestorationTab] = []
                restorationTabs.reserveCapacity(window.tabs.count)
                for tab in window.tabs {
                    try work.consume()
                    guard sessionsByTabID[tab.id] == nil else {
                        throw TabRestorationPlanError.duplicateTabID(tab.id)
                    }
                    guard tab.title.utf8.count <= Limits.hardMaximumTitleUTF8Bytes else {
                        throw TabRestorationPlanError.restoration(
                            .titleTooLarge(maximumUTF8Bytes: Limits.hardMaximumTitleUTF8Bytes)
                        )
                    }
                    guard !tab.title.isEmpty else {
                        throw TabRestorationPlanError.restoration(.invalidTitle)
                    }
                    try work.consume((tab.session.count / 4_096) + 1)
                    let sessionState: ComparisonSessionState
                    do {
                        sessionState = try ComparisonSessionState.decode(from: tab.session)
                    } catch {
                        throw TabRestorationPlanError.invalidSessionState(tab.id)
                    }
                    guard sessionsByTabID.updateValue(sessionState, forKey: tab.id) == nil else {
                        throw TabRestorationPlanError.duplicateTabID(tab.id)
                    }
                    restorationTabs.append(
                        try mapLifecycle {
                            try ComparisonTabLifecycle.RestorationTab(
                                id: tab.id,
                                title: tab.title,
                                sessionState: sessionState,
                                isDirty: tab.isDirty,
                                closeVeto: tab.veto,
                                isRestorable: tab.isRestorable,
                                tabbingEligibility: tab.tabbingEligibility
                            )
                        }
                    )
                }
                restorationWindows.append(
                    try mapLifecycle {
                        try ComparisonTabLifecycle.RestorationWindow(
                            id: window.id,
                            revision: window.revision,
                            tabs: restorationTabs,
                            selectedTabID: window.selectedTabID,
                            isRestorable: window.isRestorable,
                            tabbingEligibility: window.tabbingEligibility
                        )
                    }
                )
            }
            let request = ComparisonTabLifecycle.RestorationRequest(
                publicationCAS: publicationCAS,
                sessionRevision: snapshot.sessionRevision,
                windows: restorationWindows,
                selectedWindowID: snapshot.selectedWindowID,
                tabWidthPreference: snapshot.tabWidthPreference,
                limits: limits
            )
            let restoration = try mapLifecycle {
                try ComparisonTabLifecycle.planRestoration(request, cancellationCheck: cancellationCheck)
            }
            var intents: [ReopenIntent] = []
            intents.reserveCapacity(sessionsByTabID.count)
            var dirtyTabIDs: [TabID] = []
            var vetoedTabIDs: [TabID] = []
            for window in snapshot.windows {
                try work.consume()
                let isSelectedWindow = window.id == snapshot.selectedWindowID
                for tab in window.tabs {
                    try work.consume()
                    guard let sessionState = sessionsByTabID[tab.id] else {
                        throw TabRestorationPlanError.missingTabState(tab.id)
                    }
                    if tab.isDirty { dirtyTabIDs.append(tab.id) }
                    if tab.veto.isVetoed { vetoedTabIDs.append(tab.id) }
                    intents.append(
                        ReopenIntent(
                            ordinal: intents.count,
                            windowID: window.id,
                            tabID: tab.id,
                            title: tab.title,
                            sessionState: sessionState,
                            isDirty: tab.isDirty,
                            veto: tab.veto,
                            isSelectedTab: tab.id == window.selectedTabID,
                            isSelectedWindow: isSelectedWindow
                        )
                    )
                }
            }
            try work.finish()
            return ReopenPlan(
                publicationCAS: publicationCAS,
                sessionRevision: snapshot.sessionRevision,
                selectedWindowID: snapshot.selectedWindowID,
                tabWidthPreference: snapshot.tabWidthPreference,
                intents: intents,
                closePreflightTabIDs: intents.map(\.tabID).reversed(),
                dirtyTabIDs: dirtyTabIDs.sorted(),
                vetoedTabIDs: vetoedTabIDs.sorted(),
                restoration: restoration,
                workPerformed: work.completed
            )
        } catch let error as TabRestorationPlanError {
            throw error
        } catch {
            throw TabRestorationPlanError.cancelled
        }
    }

    private static func mapLifecycle<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ComparisonTabLifecycleError {
            throw TabRestorationPlanError.restoration(error)
        } catch let error as TabRestorationPlanError {
            throw error
        } catch {
            throw TabRestorationPlanError.cancelled
        }
    }

    private static func checked(_ cancellationCheck: @escaping CancellationCheck) throws {
        do {
            try cancellationCheck()
        } catch let error as TabRestorationPlanError {
            throw error
        } catch {
            throw TabRestorationPlanError.cancelled
        }
    }

    private struct Work {
        let maximum: Int
        let checkInterval: Int
        let cancellationCheck: CancellationCheck
        private(set) var completed = 0
        private var completedAtLastCheck = 0

        init(limits: Limits, cancellationCheck: @escaping CancellationCheck) {
            maximum = limits.maximumWorkUnits
            checkInterval = limits.cancellationCheckInterval
            self.cancellationCheck = cancellationCheck
        }

        mutating func consume(_ amount: Int = 1) throws {
            guard amount >= 0, amount <= maximum, completed <= maximum - amount else {
                try checkCancellation()
                throw TabRestorationPlanError.workLimitExceeded(maximum: maximum)
            }
            completed += amount
            if completed - completedAtLastCheck >= checkInterval {
                try checkCancellation()
            }
        }

        mutating func checkCancellation() throws {
            do {
                try cancellationCheck()
                completedAtLastCheck = completed
            } catch let error as TabRestorationPlanError {
                throw error
            } catch {
                throw TabRestorationPlanError.cancelled
            }
        }

        mutating func finish() throws {
            try checkCancellation()
        }
    }

    private struct WireKey: CodingKey, Hashable {
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

        static func requireExactKeys<Value>(
            _ container: KeyedDecodingContainer<Value>,
            expected: Set<String>,
            optional: Set<String> = []
        ) throws where Value: CodingKey {
            let actual = Set(container.allKeys.map(\.stringValue))
            guard expected.isSubset(of: actual), actual.isSubset(of: expected.union(optional)) else {
                throw TabRestorationPlanError.malformedPersistence
            }
        }
    }
}

public enum TabRestorationPlanError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case snapshotTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case malformedPersistence
    case tooManyRestorationItems(maximum: Int)
    case duplicateTabID(TabRestorationPlan.TabID)
    case missingTabState(TabRestorationPlan.TabID)
    case titleTooLarge(maximumUTF8Bytes: Int)
    case aggregateStringsTooLarge(maximumUTF8Bytes: Int)
    case sessionStateTooLarge(maximumBytes: Int)
    case invalidSessionState(TabRestorationPlan.TabID)
    case staleSessionRevision(
        expected: TabRestorationPlan.SessionRevision,
        actual: TabRestorationPlan.SessionRevision
    )
    case workLimitExceeded(maximum: Int)
    case restoration(ComparisonTabLifecycleError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Comparison tab restoration planning was cancelled."
        case .snapshotTooLarge(let maximumBytes):
            "Comparison tab restoration snapshot exceeds \(maximumBytes) bytes."
        case .unsupportedSchemaVersion(let version):
            "Comparison tab restoration snapshot uses unsupported schema version \(version)."
        case .malformedPersistence:
            "Comparison tab restoration snapshot is malformed."
        case .tooManyRestorationItems(let maximum):
            "Comparison tab restoration exceeds the \(maximum)-item limit."
        case .duplicateTabID(let tabID):
            "Comparison tab restoration repeats tab \(tabID.rawValue)."
        case .missingTabState(let tabID):
            "Comparison tab restoration is missing decoded state for tab \(tabID.rawValue)."
        case .titleTooLarge(let maximum):
            "Comparison tab restoration title exceeds \(maximum) UTF-8 bytes."
        case .aggregateStringsTooLarge(let maximum):
            "Comparison tab restoration strings exceed \(maximum) aggregate UTF-8 bytes."
        case .sessionStateTooLarge(let maximumBytes):
            "Comparison tab restoration session exceeds \(maximumBytes) bytes."
        case .invalidSessionState(let tabID):
            "Comparison tab restoration session for tab \(tabID.rawValue) is invalid."
        case .staleSessionRevision(let expected, let actual):
            "Comparison tab restoration expected session generation \(expected.generation), not \(actual.generation)."
        case .workLimitExceeded(let maximum):
            "Comparison tab restoration planning exceeds the \(maximum)-unit work limit."
        case .restoration(let error):
            error.errorDescription
        }
    }
}
