import Foundation

/// App routing groundwork for the table (delimited) workspace.
///
/// Planning authority stays in `TableWorkspacePolicy` over `TableComparison` and the
/// authoritative delimited parser. This namespace only binds the app's current comparison
/// receipt plus persisted state (headers, filters, delimiter/quote/newline settings,
/// selection), forwards one planning pass, binds the returned plan to the exact dataset
/// and state revisions it was routed from, and validates publication receipts. It performs
/// no spreadsheet rendering, menus, or source mutation: the future spreadsheet view reads
/// `TableWorkspacePresentation` directly, and the app executor owns exact source bytes,
/// lossless editing, and dataset publication.
/// Gaps stay in `TableWorkspacePolicy` (declined core scope): delimiter-newline
/// verification, filter-shape, Data-copy items.
public enum TableWorkspaceAdoption: Sendable {
    public typealias CancellationCheck = TableWorkspacePolicy.CancellationCheck
    public typealias Dataset = TableWorkspaceDatasetSnapshot
    public typealias WorkspaceState = TableWorkspaceState
    public typealias Limits = TableWorkspacePolicyLimits
    public typealias Presentation = TableWorkspacePresentation
    public typealias EditRequest = TableWorkspaceEditRequest
    public typealias EditExecutionReceipt = TableWorkspaceEditExecutionReceipt

    /// Caller-owned snapshot. The app must refresh `comparisonReceipt` and `state` from
    /// their exact owners before routing; the planner revalidates every byte it is given.
    public struct Snapshot: Equatable, Sendable {
        public let comparisonReceipt: TableWorkspaceComparisonReceipt
        public let state: TableWorkspaceState

        public init(
            comparisonReceipt: TableWorkspaceComparisonReceipt,
            state: TableWorkspaceState
        ) {
            self.comparisonReceipt = comparisonReceipt
            self.state = state
        }

        public var dataset: TableWorkspaceDatasetSnapshot {
            comparisonReceipt.dataset
        }

        public var result: TableComparisonResult {
            comparisonReceipt.result
        }
    }

    /// Planner output bound to the snapshot identity it was routed from. Receipt validation
    /// requires the same dataset and state, so a stale comparison or a changed filter,
    /// selection, header, or format setting cannot publish.
    public struct RoutedPlan: Hashable, Sendable {
        public let plan: TableWorkspacePlan
        public let expectedDataset: TableWorkspaceDatasetSnapshot
        public let expectedState: TableWorkspaceState

        public init(
            plan: TableWorkspacePlan,
            expectedDataset: TableWorkspaceDatasetSnapshot,
            expectedState: TableWorkspaceState
        ) {
            self.plan = plan
            self.expectedDataset = expectedDataset
            self.expectedState = expectedState
        }

        public var presentation: TableWorkspacePresentation {
            plan.presentation
        }

        public var editIntent: TableWorkspaceEditIntent? {
            plan.editIntent
        }
    }

    public enum DisabledReason: Hashable, Sendable {
        case stateForAnotherDataset
        case staleState(expectedRevision: UInt64, actualRevision: UInt64)
        case unsupportedSchemaVersion(Int)
        case sourceCountInvalid(Int)
        case duplicateSide(TableWorkspaceSide)
        case missingSide(TableWorkspaceSide)
        case sourceBindingChanged(TableWorkspaceSide)
        case configurationChanged
        case readOnly(TableWorkspaceSide)
    }

    public enum Availability: Equatable, Sendable {
        case ready
        case disabled(DisabledReason)
    }

    /// Pure coherence preflight between receipt and state. The planner remains
    /// authoritative; this only drives stale banners and command enablement without
    /// spending planning work units.
    public static func availability(in snapshot: Snapshot) -> Availability {
        let dataset = snapshot.comparisonReceipt.dataset
        let state = snapshot.state
        guard state.schemaVersion == TableWorkspaceState.currentSchemaVersion else {
            return .disabled(.unsupportedSchemaVersion(state.schemaVersion))
        }
        guard state.sources.count == 2 else {
            return .disabled(.sourceCountInvalid(state.sources.count))
        }
        guard dataset.sources.count == 2 else {
            return .disabled(.sourceCountInvalid(dataset.sources.count))
        }
        for side in TableWorkspaceSide.allCases {
            guard state.sources.filter({ $0.side == side }).count <= 1 else {
                return .disabled(.duplicateSide(side))
            }
            guard dataset.sources.filter({ $0.side == side }).count <= 1 else {
                return .disabled(.duplicateSide(side))
            }
        }
        for side in TableWorkspaceSide.allCases {
            guard state.source(side) != nil else {
                return .disabled(.missingSide(side))
            }
            guard dataset.source(side) != nil else {
                return .disabled(.missingSide(side))
            }
        }
        guard state.datasetReference.identity == dataset.reference.identity else {
            return .disabled(.stateForAnotherDataset)
        }
        guard state.datasetReference.revision == dataset.reference.revision else {
            return .disabled(
                .staleState(
                    expectedRevision: dataset.reference.revision,
                    actualRevision: state.datasetReference.revision
                )
            )
        }
        for side in TableWorkspaceSide.allCases {
            guard state.source(side) == dataset.source(side) else {
                return .disabled(.sourceBindingChanged(side))
            }
        }
        guard state.configuration == dataset.configuration else {
            return .disabled(.configurationChanged)
        }
        return .ready
    }

    /// Edit preflight for one side. Coherence comes first; a coherent but read-only
    /// source stays disabled without running the planner.
    public static func availabilityForEdit(
        _ side: TableWorkspaceSide,
        in snapshot: Snapshot
    ) -> Availability {
        let coherence = availability(in: snapshot)
        guard coherence == .ready else {
            return coherence
        }
        guard let binding = snapshot.comparisonReceipt.dataset.source(side) else {
            return .disabled(.sourceBindingChanged(side))
        }
        guard binding.isEditable else {
            return .disabled(.readOnly(side))
        }
        return .ready
    }

    /// Routes one presentation plan. Headers, filters, delimiter/quote/newline settings,
    /// and selection ride inside `snapshot.state` and `snapshot.dataset.configuration`;
    /// an optional cell edit becomes an exact-CAS `TableWorkspaceEditIntent` or nothing.
    /// The executor must still honor `TableWorkspaceExecutorContract.required`.
    public static func plan(
        _ snapshot: Snapshot,
        editRequest: TableWorkspaceEditRequest? = nil,
        limits: TableWorkspacePolicyLimits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            try TableWorkspacePolicy.checkCancellation()
        }
    ) throws -> RoutedPlan {
        do {
            try cancellationCheck()
        } catch {
            throw TableWorkspaceAdoptionError.cancelled
        }
        if case .disabled(let reason) = availability(in: snapshot) {
            throw disabledError(reason, snapshot: snapshot)
        }
        let request = TableWorkspaceRequest(
            comparisonReceipt: snapshot.comparisonReceipt,
            state: snapshot.state,
            editRequest: editRequest,
            limits: limits
        )
        let planned: TableWorkspacePlan
        do {
            planned = try TableWorkspacePolicy.plan(
                request,
                cancellationCheck: cancellationCheck
            )
        } catch is CancellationError {
            throw TableWorkspaceAdoptionError.cancelled
        } catch let error as TableWorkspacePolicyError {
            if error == .cancelled {
                throw TableWorkspaceAdoptionError.cancelled
            }
            throw TableWorkspaceAdoptionError.policy(error)
        }
        guard planned.executorContract == .required else {
            throw TableWorkspaceAdoptionError.executorContractMismatch
        }
        do {
            try cancellationCheck()
        } catch {
            throw TableWorkspaceAdoptionError.cancelled
        }
        return RoutedPlan(
            plan: planned,
            expectedDataset: snapshot.comparisonReceipt.dataset,
            expectedState: snapshot.state
        )
    }

    /// Rejects a stale snapshot before any publication. Requires the same dataset
    /// identity and revision plus the exact state the plan was routed from, so changed
    /// filters, selection, headers, or format settings invalidate the plan.
    public static func requireCurrent(
        _ routedPlan: RoutedPlan,
        currentSnapshot: Snapshot
    ) throws {
        let expected = routedPlan.expectedDataset.reference
        let actual = currentSnapshot.comparisonReceipt.dataset.reference
        guard expected == actual else {
            throw TableWorkspaceAdoptionError.staleSnapshot(expected: expected, actual: actual)
        }
        guard currentSnapshot.comparisonReceipt.dataset == routedPlan.expectedDataset else {
            throw TableWorkspaceAdoptionError.staleSnapshot(expected: expected, actual: actual)
        }
        guard currentSnapshot.state == routedPlan.expectedState else {
            throw TableWorkspaceAdoptionError.staleState
        }
    }

    /// Validates an executor publication receipt against the routed plan. Rejects stale
    /// snapshots before touching receipts, requires the publication contract, then
    /// delegates per-source CAS checks to the plan.
    public static func validate(
        _ executionReceipt: TableWorkspaceEditExecutionReceipt,
        for routedPlan: RoutedPlan,
        currentSnapshot: Snapshot
    ) throws -> TableWorkspaceDatasetSnapshot {
        try requireCurrent(routedPlan, currentSnapshot: currentSnapshot)
        guard routedPlan.plan.executorContract == .required else {
            throw TableWorkspaceAdoptionError.executorContractMismatch
        }
        do {
            return try routedPlan.plan.validate(executionReceipt)
        } catch is CancellationError {
            throw TableWorkspaceAdoptionError.cancelled
        } catch let error as TableWorkspacePolicyError {
            if error == .cancelled {
                throw TableWorkspaceAdoptionError.cancelled
            }
            throw TableWorkspaceAdoptionError.policy(error)
        }
    }

    /// Encodes persistable policy state. The receipt round-trips the exact dataset
    /// revision, bindings, configuration, filters, and selection.
    public static func encode(
        _ state: TableWorkspaceState,
        limits: TableWorkspacePolicyLimits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            try TableWorkspacePolicy.checkCancellation()
        }
    ) throws -> TableWorkspacePersistenceReceipt {
        do {
            return try state.encoded(limits: limits, cancellationCheck: cancellationCheck)
        } catch is CancellationError {
            throw TableWorkspaceAdoptionError.cancelled
        } catch let error as TableWorkspacePolicyError {
            if error == .cancelled {
                throw TableWorkspaceAdoptionError.cancelled
            }
            throw TableWorkspaceAdoptionError.policy(error)
        }
    }

    /// Decodes persistable policy state with strict validation, hostile-input rejection,
    /// limits, and cancellation.
    public static func decode(
        _ data: Data,
        limits: TableWorkspacePolicyLimits = .default,
        cancellationCheck: @escaping CancellationCheck = {
            try TableWorkspacePolicy.checkCancellation()
        }
    ) throws -> TableWorkspacePersistenceReceipt {
        do {
            return try TableWorkspaceState.decode(
                from: data,
                limits: limits,
                cancellationCheck: cancellationCheck
            )
        } catch is CancellationError {
            throw TableWorkspaceAdoptionError.cancelled
        } catch let error as TableWorkspacePolicyError {
            if error == .cancelled {
                throw TableWorkspaceAdoptionError.cancelled
            }
            throw TableWorkspaceAdoptionError.policy(error)
        }
    }

    private static func disabledError(
        _ reason: DisabledReason,
        snapshot: Snapshot
    ) -> TableWorkspaceAdoptionError {
        switch reason {
        case .stateForAnotherDataset, .staleState:
            TableWorkspaceAdoptionError.staleSnapshot(
                expected: snapshot.comparisonReceipt.dataset.reference,
                actual: snapshot.state.datasetReference
            )
        case .sourceBindingChanged(let side):
            TableWorkspaceAdoptionError.policy(.sourceBindingChanged(side))
        case .unsupportedSchemaVersion(let version):
            TableWorkspaceAdoptionError.policy(.unsupportedSchemaVersion(version))
        case .sourceCountInvalid(let count):
            TableWorkspaceAdoptionError.policy(.sourceCountInvalid(count))
        case .duplicateSide(let side):
            TableWorkspaceAdoptionError.policy(.duplicateSide(side))
        case .missingSide(let side):
            TableWorkspaceAdoptionError.policy(.missingSide(side))
        case .configurationChanged:
            TableWorkspaceAdoptionError.policy(.configurationChanged)
        case .readOnly(let side):
            TableWorkspaceAdoptionError.policy(.editTargetReadOnly(side))
        }
    }
}

public enum TableWorkspaceAdoptionError: Error, LocalizedError, Hashable, Sendable {
    case cancelled
    case staleSnapshot(
        expected: TableWorkspaceDatasetReference,
        actual: TableWorkspaceDatasetReference
    )
    case staleState
    case executorContractMismatch
    case policy(TableWorkspacePolicyError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Table workspace adoption was cancelled."
        case .staleSnapshot:
            "The table workspace snapshot changed before the plan could be used."
        case .staleState:
            "The table workspace state changed before the plan could be used."
        case .executorContractMismatch:
            "The table workspace plan uses an unexpected executor contract."
        case .policy(let error):
            error.errorDescription
        }
    }
}
