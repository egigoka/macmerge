import Foundation

/// App routing groundwork for three-pane Save Middle and Save As Middle.
///
/// Planning authority stays in `ThreePaneSavePlanner`. This namespace only binds the app's current
/// middle-pane snapshot (identity, revision, encoding/BOM) plus sibling panes for alias/collision
/// rejection, runs a pure availability preflight, forwards caller-resolved destinations as authority,
/// and validates publication receipts. It performs no filesystem, UI, or pane-mutation work.
public enum ThreePaneSaveMiddleAdoption: Sendable {
    public typealias CancellationCheck = ThreePaneSavePlanner.CancellationCheck

    public static let maximumMiddleOperations = 1

    public enum Command: String, CaseIterable, Hashable, Sendable {
        case saveMiddle
        case saveAsMiddle
    }

    public struct SnapshotIdentity: Hashable, Sendable {
        public let lineage: UUID
        public let generation: UInt64

        public init(lineage: UUID, generation: UInt64) {
            self.lineage = lineage
            self.generation = generation
        }
    }

    /// Caller-owned snapshot. The app must refresh `middle` (and siblings) from the exact owner
    /// revisions before routing; the planner revalidates every byte it is given.
    public struct Snapshot: Hashable, Sendable {
        public let identity: SnapshotIdentity
        public let left: ThreePaneSavePaneState
        public let middle: ThreePaneSavePaneState
        public let right: ThreePaneSavePaneState

        public init(
            identity: SnapshotIdentity,
            left: ThreePaneSavePaneState,
            middle: ThreePaneSavePaneState,
            right: ThreePaneSavePaneState
        ) {
            self.identity = identity
            self.left = left
            self.middle = middle
            self.right = right
        }

        public var panes: [ThreePaneSavePane] {
            [
                ThreePaneSavePane(side: .left, state: left),
                ThreePaneSavePane(side: .middle, state: middle),
                ThreePaneSavePane(side: .right, state: right)
            ]
        }

        /// Exact owner revision plus encoding/BOM bound for publication. Nil when unloaded.
        public var middleContent: ThreePaneSaveContentRevision? {
            middle.content
        }

        /// Exact persisted file binding for a loaded middle pane. Nil when untitled.
        public var middleSourceFile: ThreePaneSaveFileBinding? {
            if case .loaded(_, let file) = middle { file } else { nil }
        }
    }

    public enum DisabledReason: String, Hashable, Sendable {
        case paneNotLoaded
        case paneNotDirty
        case paneReadOnly
    }

    public enum Availability: Hashable, Sendable {
        case enabled
        case disabled(DisabledReason)
    }

    /// Planner output bound to the snapshot identity it was routed from. Receipt validation
    /// requires the same identity, so a stale three-way comparison cannot publish.
    public struct RoutedPlan: Hashable, Sendable {
        public let plan: ThreePaneSavePlan
        public let expectedIdentity: SnapshotIdentity
        public let command: Command

        public init(plan: ThreePaneSavePlan, expectedIdentity: SnapshotIdentity, command: Command) {
            self.plan = plan
            self.expectedIdentity = expectedIdentity
            self.command = command
        }
    }

    public enum AdoptionError: Error, LocalizedError, Hashable, Sendable {
        case staleSnapshot(expected: SnapshotIdentity, actual: SnapshotIdentity)
        case unexpectedOperationCount(Int)
        case executorContractMismatch(ThreePaneSaveSide)

        public var errorDescription: String? {
            switch self {
            case .staleSnapshot:
                "The middle-pane snapshot changed before the save plan could be used."
            case .unexpectedOperationCount(let count):
                "A middle-pane save plan must hold exactly one operation, not \(count)."
            case .executorContractMismatch(let side):
                "The \(side.rawValue) save operation uses an unexpected executor contract."
            }
        }
    }

    /// Pure enablement preflight. The planner remains authoritative; this only drives menus.
    /// Save As preserves encoding, BOM, and read-only state, so it stays enabled for clean and
    /// read-only middle panes. Save Middle requires dirty (or untitled) non-read-only content.
    public static func availability(for command: Command, in snapshot: Snapshot) -> Availability {
        guard let content = snapshot.middle.content else {
            return .disabled(.paneNotLoaded)
        }
        switch command {
        case .saveMiddle:
            if snapshot.middle.isUntitled {
                return content.isReadOnly ? .disabled(.paneReadOnly) : .enabled
            }
            if content.isReadOnly { return .disabled(.paneReadOnly) }
            return content.isDirty ? .enabled : .disabled(.paneNotDirty)
        case .saveAsMiddle:
            return .enabled
        }
    }

    /// Routes Save Middle. A destination is required only for untitled panes; loaded dirty panes
    /// save in place. The destination is caller-resolved authority: side is checked here, while
    /// canonical shape, vacancy-or-full-revision CAS, and alias/collision rejection stay in the planner.
    public static func planSaveMiddle(
        _ snapshot: Snapshot,
        destination: ThreePaneSaveDestination? = nil,
        limits: ThreePaneSavePlanningLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> RoutedPlan {
        do {
            try cancellationCheck()
        } catch {
            throw ThreePaneSavePlanningError.cancelled
        }
        if let destination, destination.side != .middle {
            throw ThreePaneSavePlanningError.wrongDestinationSide(
                expected: .middle,
                actual: destination.side
            )
        }
        let request = ThreePaneSaveRequest(
            panes: snapshot.panes,
            action: .saveMiddle(destination: destination),
            limits: limits
        )
        let plan = try ThreePaneSavePlanner.plan(request, cancellationCheck: cancellationCheck)
        return try bind(plan: plan, command: .saveMiddle, identity: snapshot.identity)
    }

    /// Routes Save As Middle for loaded, untitled, clean, dirty, and read-only middle panes.
    /// The full destination revision is the publication CAS: `.vacant` publishes only when the
    /// canonical leaf is absent, `.existing` replaces only that exact revision.
    public static func planSaveAsMiddle(
        _ snapshot: Snapshot,
        destination: ThreePaneSaveDestination,
        limits: ThreePaneSavePlanningLimits = .default,
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> RoutedPlan {
        do {
            try cancellationCheck()
        } catch {
            throw ThreePaneSavePlanningError.cancelled
        }
        guard destination.side == .middle else {
            throw ThreePaneSavePlanningError.wrongDestinationSide(
                expected: .middle,
                actual: destination.side
            )
        }
        let request = ThreePaneSaveRequest(
            panes: snapshot.panes,
            action: .saveAsMiddle(destination: destination),
            limits: limits
        )
        let plan = try ThreePaneSavePlanner.plan(request, cancellationCheck: cancellationCheck)
        return try bind(plan: plan, command: .saveAsMiddle, identity: snapshot.identity)
    }

    /// Validates publication receipts against a fresh snapshot. Rejects stale snapshots before
    /// touching receipts, requires the publication contract on every operation, then delegates
    /// per-operation outcomes and payload checks to the plan. Caller must bump generation on
    /// every middle/sibling revision change; identity equality is the stale gate.
    public static func validateReceipts(
        _ routedPlan: RoutedPlan,
        currentSnapshot: Snapshot,
        receipts: [ThreePaneSaveOperationReceipt],
        cancellationCheck: @escaping CancellationCheck = { try Task.checkCancellation() }
    ) throws -> ThreePaneSaveExecutionReceipt {
        try cancellationCheck()
        guard currentSnapshot.identity == routedPlan.expectedIdentity else {
            throw AdoptionError.staleSnapshot(
                expected: routedPlan.expectedIdentity,
                actual: currentSnapshot.identity
            )
        }
        for receipt in receipts {
            guard receipt.operation.executorContract == .required else {
                throw AdoptionError.executorContractMismatch(receipt.operation.side)
            }
        }
        try cancellationCheck()
        return try routedPlan.plan.validate(receipts: receipts)
    }

    private static func bind(
        plan: ThreePaneSavePlan,
        command: Command,
        identity: SnapshotIdentity
    ) throws -> RoutedPlan {
        guard plan.operations.count == maximumMiddleOperations else {
            throw AdoptionError.unexpectedOperationCount(plan.operations.count)
        }
        for operation in plan.operations {
            guard operation.side == .middle else {
                throw ThreePaneSavePlanningError.wrongDestinationSide(
                    expected: .middle,
                    actual: operation.side
                )
            }
            guard operation.preservesEncoding == operation.source.encoding else {
                throw ThreePaneSavePlanningError.invalidEncodingMetadata(.middle)
            }
            guard operation.preservesReadOnlyState == operation.source.isReadOnly else {
                throw ThreePaneSavePlanningError.invalidContentRevision(.middle)
            }
            guard operation.executorContract == .required else {
                throw AdoptionError.executorContractMismatch(operation.side)
            }
        }
        return RoutedPlan(plan: plan, expectedIdentity: identity, command: command)
    }
}
