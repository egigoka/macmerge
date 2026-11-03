import Foundation

/// Planner for the File menu's explicit File Encoding selection.
///
/// Guarded Reload and ambiguity-driven encoding selection already exist; this type covers the
/// remaining explicit menu choice: a load code page (reinterpret persisted bytes), a save code
/// page (change the encoding used by a later save), and BOM controls, applied to a pane scope.
/// It maps the menu selection to an `EncodingSelectionPolicy` intent without touching menus,
/// windows, documents, or the filesystem: no `NSMenu`, AppKit, or executor lives here. The app
/// renders this plan and forwards the resolved policy request to its existing apply path.
public enum EncodingMenuSelection: Sendable {
    public typealias CancellationCheck = @Sendable () throws -> Void
    public typealias Pane = EncodingSelectionPolicy.Pane
    public typealias PaneScope = EncodingSelectionPolicy.PaneScope
    public typealias PaneState = EncodingSelectionPolicy.PaneState
    public typealias PolicyChoice = EncodingSelectionPolicy.Choice
    public typealias PolicyResult = EncodingSelectionPolicy.Result

    /// BOM control offered beside a save code page. Load reinterprets persisted bytes, so it
    /// carries no BOM control; save with `.preserve` keeps per-pane BOM presence.
    public enum ByteOrderMarkControl: String, CaseIterable, Equatable, Hashable, Sendable {
        case preserve
        case include
        case omit

        public var policy: EncodingSelectionPolicy.ByteOrderMarkPolicy? {
            switch self {
            case .preserve: nil
            case .include: .include
            case .omit: .omit
            }
        }
    }

    /// One explicit menu choice before scope is applied.
    public enum MenuChoice: Equatable, Sendable {
        case load(TextFileEncoding)
        case save(TextFileEncoding, byteOrderMark: ByteOrderMarkControl)

        public var encoding: TextFileEncoding {
            switch self {
            case .load(let encoding), .save(let encoding, _):
                encoding
            }
        }

        public var isSave: Bool {
            switch self {
            case .load: false
            case .save: true
            }
        }

        public var byteOrderMarkControl: ByteOrderMarkControl? {
            switch self {
            case .load: nil
            case .save(_, let control): control
            }
        }

        public var policyChoice: PolicyChoice {
            switch self {
            case .load(let encoding):
                .load(encoding)
            case .save(let encoding, let control):
                .save(encoding, byteOrderMark: control.policy)
            }
        }
    }

    /// Menu choice plus the panes it targets.
    public struct MenuSelection: Equatable, Sendable {
        public let choice: MenuChoice
        public let scope: PaneScope

        public init(choice: MenuChoice, scope: PaneScope) {
            self.choice = choice
            self.scope = scope
        }
    }

    /// Owner-issued identity for one set of pane states. `generation` must advance whenever any
    /// pane state it covers changes, so a plan cannot apply to newer document revisions.
    public struct DocumentSnapshotReference: Equatable, Hashable, Sendable {
        public let identity: UUID
        public let generation: UInt64

        public init(identity: UUID, generation: UInt64) {
            self.identity = identity
            self.generation = generation
        }
    }

    /// Caller-captured pane states the menu selection applies to.
    public struct DocumentSnapshot: Equatable, Sendable {
        public let identity: UUID
        public let generation: UInt64
        public let paneStates: [PaneState]

        public init(identity: UUID, generation: UInt64, paneStates: [PaneState]) {
            self.identity = identity
            self.generation = generation
            self.paneStates = paneStates
        }

        public var reference: DocumentSnapshotReference {
            DocumentSnapshotReference(identity: identity, generation: generation)
        }
    }

    public enum Limit: String, CaseIterable, Equatable, Hashable, Sendable {
        case paneStates
        case workUnits
        case cancellationCheckInterval
    }

    public struct Limits: Equatable, Hashable, Sendable {
        public static let hardMaximumPaneStates = 3
        public static let hardMaximumWorkUnits: UInt64 = 1 << 20
        public static let hardMaximumCancellationCheckInterval: UInt64 = 65_536
        public static let `default` = Limits()

        public let maximumPaneStates: Int
        public let maximumWorkUnits: UInt64
        public let cancellationCheckInterval: UInt64

        public init(
            maximumPaneStates: Int = hardMaximumPaneStates,
            maximumWorkUnits: UInt64 = 1 << 16,
            cancellationCheckInterval: UInt64 = 1
        ) {
            self.maximumPaneStates = maximumPaneStates
            self.maximumWorkUnits = maximumWorkUnits
            self.cancellationCheckInterval = cancellationCheckInterval
        }
    }

    public enum PlanningError: Error, Equatable, Hashable, LocalizedError, Sendable {
        case cancelled
        case invalidLimit(Limit)
        case tooManyPaneStates(maximum: Int)
        case emptyPaneScope
        case duplicatePaneState(Pane)
        case staleSnapshotIdentity(expected: UUID, actual: UUID)
        case staleGeneration(expected: UInt64, actual: UInt64)
        case workLimitExceeded(maximumUnits: UInt64)

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                "File Encoding menu planning was cancelled."
            case .invalidLimit(let limit):
                "File Encoding menu planning has an invalid limit: \(limit.rawValue)."
            case .tooManyPaneStates(let maximum):
                "File Encoding menu planning exceeds the \(maximum)-pane limit."
            case .emptyPaneScope:
                "File Encoding menu planning requires at least one target pane."
            case .duplicatePaneState(let pane):
                "File Encoding menu planning received two states for one pane."
                    + " \(pane) is duplicated."
            case .staleSnapshotIdentity:
                "File Encoding menu planning belongs to another document snapshot."
            case .staleGeneration(let expected, let actual):
                "File Encoding menu plan expects document generation \(expected), not \(actual)."
            case .workLimitExceeded(let maximum):
                "File Encoding menu planning exceeded the \(maximum)-unit work limit."
            }
        }
    }

    /// Advisory warning for one scoped pane. True when a save intent would re-encode persisted
    /// bytes that are not already in canonical form, so applying the plan rewrites bytes even
    /// without an edit. Load intents never warn: reinterpreting bytes changes contents, not the
    /// persisted encoding. This never blocks planning; `EncodingSelectionPolicy` still denies a
    /// dirty noncanonical source on save, which the menu surfaces from `policyResult`.
    public struct PaneOutcome: Equatable, Sendable {
        public let pane: Pane
        public let canonicalizationWarning: Bool

        public init(pane: Pane, canonicalizationWarning: Bool) {
            self.pane = pane
            self.canonicalizationWarning = canonicalizationWarning
        }
    }

    public struct Request: Equatable, Sendable {
        public let snapshot: DocumentSnapshot
        public let selection: MenuSelection
        public let limits: Limits

        public init(
            snapshot: DocumentSnapshot,
            selection: MenuSelection,
            limits: Limits = .default
        ) {
            self.snapshot = snapshot
            self.selection = selection
            self.limits = limits
        }
    }

    /// Deterministic planning receipt. No menu, document, or filesystem state is introduced.
    public struct Plan: Equatable, Sendable {
        public let snapshotReference: DocumentSnapshotReference
        public let selection: MenuSelection
        public let policyResult: PolicyResult
        /// One entry per scoped pane with captured state, in left-middle-right order.
        public let outcomes: [PaneOutcome]

        public init(
            snapshotReference: DocumentSnapshotReference,
            selection: MenuSelection,
            policyResult: PolicyResult,
            outcomes: [PaneOutcome]
        ) {
            self.snapshotReference = snapshotReference
            self.selection = selection
            self.policyResult = policyResult
            self.outcomes = outcomes
        }

        public var requiresReload: Bool {
            policyResult.plan?.requiresReload ?? false
        }

        public var requiresRescan: Bool {
            policyResult.plan?.requiresRescan ?? false
        }

        /// True when at least one scoped pane would rewrite persisted bytes on save.
        public var requiresCanonicalizationWarning: Bool {
            outcomes.contains(where: \.canonicalizationWarning)
        }

        public func outcome(for pane: Pane) -> PaneOutcome? {
            outcomes.first { $0.pane == pane }
        }

        public func requireCurrentSnapshot(_ snapshot: DocumentSnapshot) throws {
            try EncodingMenuSelection.validate(snapshot, against: self)
        }

        public func isCurrent(for snapshot: DocumentSnapshot) throws -> Bool {
            do {
                try requireCurrentSnapshot(snapshot)
                return true
            } catch PlanningError.staleSnapshotIdentity, PlanningError.staleGeneration {
                return false
            }
        }
    }

    /// Resolves the menu selection to a policy intent, evaluates it, and attaches per-pane
    /// canonicalization warnings. Policy denial is returned as data in `Plan.policyResult` so
    /// the menu can disable or explain the choice; only stale, over-bound, cancelled, or
    /// mislimited requests throw.
    public static func plan(
        _ request: Request,
        expecting expectedSnapshot: DocumentSnapshotReference? = nil,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> Plan {
        try cancellationCheck()
        if let expectedSnapshot {
            try validateReference(request.snapshot.reference, expected: expectedSnapshot)
        }
        try validate(request.limits)
        var work: UInt64 = 0
        func charge(_ units: UInt64) throws {
            let (charged, overflow) = work.addingReportingOverflow(units)
            guard !overflow, charged <= request.limits.maximumWorkUnits else {
                throw PlanningError.workLimitExceeded(maximumUnits: request.limits.maximumWorkUnits)
            }
            work = charged
            if work % request.limits.cancellationCheckInterval == 0 {
                try cancellationCheck()
            }
        }

        guard !request.selection.scope.panes.isEmpty else {
            throw PlanningError.emptyPaneScope
        }
        guard request.snapshot.paneStates.count <= request.limits.maximumPaneStates else {
            throw PlanningError.tooManyPaneStates(maximum: request.limits.maximumPaneStates)
        }
        try charge(UInt64(request.snapshot.paneStates.count + 1))

        var seen: Set<Pane> = []
        for state in request.snapshot.paneStates {
            try charge(1)
            guard seen.insert(state.pane).inserted else {
                throw PlanningError.duplicatePaneState(state.pane)
            }
        }

        let policyRequest = EncodingSelectionPolicy.Request(
            choice: request.selection.choice.policyChoice,
            scope: request.selection.scope,
            paneStates: request.snapshot.paneStates
        )
        try cancellationCheck()
        let policyResult = EncodingSelectionPolicy.evaluate(policyRequest)
        try cancellationCheck()

        let statesByPane = Dictionary(
            uniqueKeysWithValues: request.snapshot.paneStates.map { ($0.pane, $0) }
        )
        let scopedPanes = Pane.allCases.filter(request.selection.scope.panes.contains)
        var outcomes: [PaneOutcome] = []
        for pane in scopedPanes {
            try charge(1)
            guard let state = statesByPane[pane] else { continue }
            outcomes.append(
                PaneOutcome(
                    pane: pane,
                    canonicalizationWarning: request.selection.choice.isSave
                        && !state.hasCanonicalPersistedEncoding
                ))
        }

        return Plan(
            snapshotReference: request.snapshot.reference,
            selection: request.selection,
            policyResult: policyResult,
            outcomes: outcomes
        )
    }

    public static func validate(_ snapshot: DocumentSnapshot, against plan: Plan) throws {
        guard snapshot.identity == plan.snapshotReference.identity else {
            throw PlanningError.staleSnapshotIdentity(
                expected: plan.snapshotReference.identity,
                actual: snapshot.identity
            )
        }
        guard snapshot.generation == plan.snapshotReference.generation else {
            throw PlanningError.staleGeneration(
                expected: plan.snapshotReference.generation,
                actual: snapshot.generation
            )
        }
    }

    private static func validateReference(
        _ actual: DocumentSnapshotReference,
        expected: DocumentSnapshotReference
    ) throws {
        guard actual.identity == expected.identity else {
            throw PlanningError.staleSnapshotIdentity(
                expected: expected.identity,
                actual: actual.identity
            )
        }
        guard actual.generation == expected.generation else {
            throw PlanningError.staleGeneration(
                expected: expected.generation,
                actual: actual.generation
            )
        }
    }

    private static func validate(_ limits: Limits) throws {
        guard limits.maximumPaneStates >= 1,
            limits.maximumPaneStates <= Limits.hardMaximumPaneStates
        else {
            throw PlanningError.invalidLimit(.paneStates)
        }
        guard limits.maximumWorkUnits <= Limits.hardMaximumWorkUnits else {
            throw PlanningError.invalidLimit(.workUnits)
        }
        guard limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval <= Limits.hardMaximumCancellationCheckInterval
        else {
            throw PlanningError.invalidLimit(.cancellationCheckInterval)
        }
    }
}
