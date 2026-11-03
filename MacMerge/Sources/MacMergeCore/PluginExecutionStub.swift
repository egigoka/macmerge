import Foundation

/// UI-independent plugin execution stub.
///
/// Binds an authorization-aware `PluginManagementWorkflow` selection
/// (unpacker, prediffer, editor, or copy lane) to a one-shot execution plan
/// with exact snapshot CAS, fail-closed reload, and stale revalidation.
/// Plan-only: never loads plugins, never spawns processes, and never touches
/// the filesystem, pasteboard, UI, menus, or dialogs. Every terminal outcome
/// is a not-executed receipt; real loading and execution remain unimplemented.
public struct PluginExecutionStubLimits: Equatable, Sendable {
    public static let hardMaximumResultCount =
        PluginManagementWorkflowLimits.hardMaximumListedItemCount
    public static let hardMaximumWorkUnits =
        PluginManagementWorkflowLimits.hardMaximumWorkUnits
    public static let hardMaximumCancellationCheckInterval =
        PluginManagementWorkflowLimits.hardMaximumCancellationCheckInterval

    public static let `default` = Self(
        maximumResultCount: 1_024,
        maximumWorkUnits: 8 * 1_024 * 1_024,
        cancellationCheckInterval: 64,
        validated: ()
    )

    public let maximumResultCount: Int
    public let maximumWorkUnits: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumResultCount: Int = 1_024,
        maximumWorkUnits: Int = 8 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 64
    ) throws(PluginExecutionStubError) {
        guard
            (1...Self.hardMaximumResultCount).contains(maximumResultCount),
            (1...Self.hardMaximumWorkUnits).contains(maximumWorkUnits),
            (1...Self.hardMaximumCancellationCheckInterval).contains(
                cancellationCheckInterval
            )
        else {
            throw PluginExecutionStubError.invalidLimits
        }
        self.init(
            maximumResultCount: maximumResultCount,
            maximumWorkUnits: maximumWorkUnits,
            cancellationCheckInterval: cancellationCheckInterval,
            validated: ()
        )
    }

    private init(
        maximumResultCount: Int,
        maximumWorkUnits: Int,
        cancellationCheckInterval: Int,
        validated: Void
    ) {
        self.maximumResultCount = maximumResultCount
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

/// Execution lane derived from catalog metadata only. Transform metadata names
/// no external-tool capability and is rejected as backend-unavailable.
public enum PluginExecutionStubLane: String, CaseIterable, Equatable, Hashable, Sendable {
    case unpacker
    case prediffer
    case editor
    case copy

    fileprivate init(
        capability: PluginCapability
    ) throws(PluginExecutionStubError) {
        switch capability {
        case .unpacker: self = .unpacker
        case .prediffer: self = .prediffer
        case .editor: self = .editor
        case .copy: self = .copy
        case .transform:
            throw PluginExecutionStubError.backendUnavailable(capability: capability)
        }
    }
}

public struct PluginExecutionStubRequest: Sendable {
    public let snapshot: PluginManagementSnapshot
    public let selection: PluginManagementSelectionRequest
    public let authorizations: [PluginIdentifier: PluginAuthorization]
    public let limits: PluginExecutionStubLimits

    public init(
        snapshot: PluginManagementSnapshot,
        selection: PluginManagementSelectionRequest,
        authorizations: [PluginIdentifier: PluginAuthorization] = [:],
        limits: PluginExecutionStubLimits = .default
    ) {
        self.snapshot = snapshot
        self.selection = selection
        self.authorizations = authorizations
        self.limits = limits
    }
}

/// Execution receipt. Construction performs no loading; it echoes the exact
/// planned selection the executor validated without executing.
public struct PluginExecutionStubReceipt: Equatable, Hashable, Sendable {
    public let revision: PluginManagementRevision
    public let identifier: PluginIdentifier
    public let capability: PluginCapability
    public let lane: PluginExecutionStubLane
    public let mode: PluginInvocationMode

    fileprivate init(
        revision: PluginManagementRevision,
        identifier: PluginIdentifier,
        capability: PluginCapability,
        lane: PluginExecutionStubLane,
        mode: PluginInvocationMode
    ) {
        self.revision = revision
        self.identifier = identifier
        self.capability = capability
        self.lane = lane
        self.mode = mode
    }
}

public enum PluginExecutionStubError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case cancelled
    case staleSnapshot(expected: PluginManagementRevision, actual: PluginManagementRevision)
    case snapshotContentsChanged(revision: PluginManagementRevision)
    case workLimitExceeded(maximum: Int)
    case leaseAlreadyConsumed
    case selectionNotExecutable
    case authorizationChanged
    case backendUnavailable(capability: PluginCapability)
    case reloadUnsupported
    case inProcessLoadingUnsupported
    case workflow(PluginManagementWorkflowError)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Plugin execution stub limits are invalid."
        case .cancelled:
            "Plugin execution stub operation was cancelled."
        case .staleSnapshot:
            "Plugin execution stub plan belongs to a stale snapshot."
        case .snapshotContentsChanged:
            "Plugin execution stub snapshot changed without a matching revision change."
        case .workLimitExceeded(let maximum):
            "Plugin execution stub operation exceeds the \(maximum)-unit work limit."
        case .leaseAlreadyConsumed:
            "Plugin execution stub lease has already been consumed."
        case .selectionNotExecutable:
            "Plugin execution stub selection is not a single executable plugin."
        case .authorizationChanged:
            "Plugin execution stub selection changed after current trust or approval validation."
        case .backendUnavailable(let capability):
            "Plugin execution stub has no execution backend for \(capability.rawValue)."
        case .reloadUnsupported:
            "Plugin execution stub does not perform plugin reload."
        case .inProcessLoadingUnsupported:
            "Plugin execution stub does not perform in-process plugin loading."
        case .workflow(let error):
            error.localizedDescription
        }
    }
}

public enum PluginExecutionStubContract: String, Equatable, Hashable, Sendable {
    case planOnlyNoPluginLoading
}

/// Phased plan output. Construction performs no loading or execution.
public struct PluginExecutionStubPlan: Sendable {
    public let expectedSnapshot: PluginManagementSnapshotCAS
    public let receipt: PluginExecutionStubReceipt
    public let executorContract = PluginExecutionStubContract.planOnlyNoPluginLoading

    private let limits: PluginExecutionStubLimits
    private let request: PluginManagementSelectionRequest
    private let gate: PluginExecutionStubLeaseGate

    fileprivate init(
        expectedSnapshot: PluginManagementSnapshotCAS,
        receipt: PluginExecutionStubReceipt,
        limits: PluginExecutionStubLimits,
        request: PluginManagementSelectionRequest
    ) {
        self.expectedSnapshot = expectedSnapshot
        self.receipt = receipt
        self.limits = limits
        self.request = request
        gate = PluginExecutionStubLeaseGate()
    }

    /// Revalidates exact state and re-runs authorization-aware selection against
    /// current trust and approval. Any drift fails closed.
    public func validateCurrentSnapshot(
        _ snapshot: PluginManagementSnapshot,
        authorizations: [PluginIdentifier: PluginAuthorization]
    ) throws(PluginExecutionStubError) {
        try pluginExecutionStubCheckCancellation()
        do {
            try expectedSnapshot.validate(snapshot)
        } catch PluginManagementWorkflowError.staleSnapshot(let expected, let actual) {
            throw PluginExecutionStubError.staleSnapshot(expected: expected, actual: actual)
        } catch PluginManagementWorkflowError.snapshotContentsChanged(let revision) {
            throw PluginExecutionStubError.snapshotContentsChanged(revision: revision)
        } catch let error {
            throw PluginExecutionStubError.workflow(error)
        }
        try pluginExecutionStubCheckCancellation()
        var budget = PluginExecutionStubWorkBudget(limits: limits)
        try budget.consume(1)
        let current = try pluginExecutionStubCatalogSelect(
            request,
            snapshot: snapshot,
            authorizations: authorizations,
            limits: limits,
            budget: &budget
        )
        guard case .selected(let item) = current,
            item.id == receipt.identifier,
            item.capability == receipt.capability
        else {
            throw PluginExecutionStubError.authorizationChanged
        }
        let currentLane = try PluginExecutionStubLane(capability: item.capability)
        guard currentLane == receipt.lane else {
            throw PluginExecutionStubError.authorizationChanged
        }
        try pluginExecutionStubCheckCancellation()
    }

    fileprivate func claimLease() -> Bool {
        gate.claim()
    }
}

private final class PluginExecutionStubLeaseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

public enum PluginExecutionStubOutcome: Equatable, Sendable {
    case notExecuted(PluginExecutionStubReceipt)
    case failed(PluginExecutionStubError)
    case cancelled
}

/// Side-effect implementation supplied by a future owner layer. It must call
/// `plan.validateCurrentSnapshot` before any execution effect and must enforce
/// `PluginExecutionStubContract.planOnlyNoPluginLoading` until native
/// unpacker, prediffer, editor, and copy execution exists.
public protocol PluginExecutionPlanExecutor: Sendable {
    func execute(
        _ plan: PluginExecutionStubPlan,
        validating currentSnapshot: PluginManagementSnapshot,
        authorizations: [PluginIdentifier: PluginAuthorization]
    ) async -> PluginExecutionStubOutcome
}

public enum PluginExecutionStub: Sendable {
    public static func plan(
        _ request: PluginExecutionStubRequest
    ) throws(PluginExecutionStubError) -> PluginExecutionStubPlan {
        try pluginExecutionStubCheckCancellation()
        let workflow = try pluginExecutionStubWorkflow(limits: request.limits)
        var budget = PluginExecutionStubWorkBudget(limits: request.limits)
        try budget.consume(1)
        let outcome = try pluginExecutionStubCatalogSelect(
            request.selection,
            snapshot: request.snapshot,
            authorizations: request.authorizations,
            limits: request.limits,
            budget: &budget
        )
        guard case .selected(let item) = outcome else {
            throw PluginExecutionStubError.selectionNotExecutable
        }
        try budget.consume(item.id.rawValue.utf8.count + 1)
        let lane = try PluginExecutionStubLane(capability: item.capability)
        try budget.consume(1)
        try pluginExecutionStubCheckCancellation()
        return PluginExecutionStubPlan(
            expectedSnapshot: request.snapshot.cas(
                limits: workflow.limits
            ),
            receipt: PluginExecutionStubReceipt(
                revision: request.snapshot.revision,
                identifier: item.id,
                capability: item.capability,
                lane: lane,
                mode: request.selection.mode
            ),
            limits: request.limits,
            request: request.selection
        )
    }
}

/// Plan-only stub executor: revalidates exact state, authorization, and
/// fail-closed reload posture, then returns the not-executed receipt without
/// loading or running any plugin.
public struct PluginExecutionStubExecutor: PluginExecutionPlanExecutor {
    public init() {}

    public func execute(
        _ plan: PluginExecutionStubPlan,
        validating currentSnapshot: PluginManagementSnapshot,
        authorizations: [PluginIdentifier: PluginAuthorization]
    ) async -> PluginExecutionStubOutcome {
        if Task.isCancelled {
            return .cancelled
        }
        guard plan.claimLease() else {
            return .failed(.leaseAlreadyConsumed)
        }
        do {
            try plan.validateCurrentSnapshot(currentSnapshot, authorizations: authorizations)
            if Task.isCancelled {
                return .cancelled
            }
            let reload = currentSnapshot.catalog.reloadOutcome(
                externalToolPolicy: currentSnapshot.externalToolPolicy
            )
            guard !reload.isSupported else {
                return .failed(.reloadUnsupported)
            }
            let inProcess = currentSnapshot.catalog.inProcessLoadingOutcome(
                externalToolPolicy: currentSnapshot.externalToolPolicy
            )
            guard !inProcess.isSupported else {
                return .failed(.inProcessLoadingUnsupported)
            }
            if Task.isCancelled {
                return .cancelled
            }
        } catch let error {
            return error == .cancelled ? .cancelled : .failed(error)
        }
        // Never loads or runs plugins: no process, filesystem, pasteboard, or UI mutation.
        return .notExecuted(plan.receipt)
    }
}

private func pluginExecutionStubWorkflow(
    limits: PluginExecutionStubLimits
) throws(PluginExecutionStubError) -> PluginManagementWorkflow {
    do {
        return try PluginManagementWorkflow(
            limits: PluginManagementWorkflowLimits(
                maximumListedItemCount: limits.maximumResultCount,
                maximumWorkUnits: limits.maximumWorkUnits,
                cancellationCheckInterval: limits.cancellationCheckInterval
            )
        )
    } catch {
        throw PluginExecutionStubError.invalidLimits
    }
}

private struct PluginExecutionStubWorkBudget {
    let limits: PluginExecutionStubLimits
    private var consumed = 0

    init(limits: PluginExecutionStubLimits) {
        self.limits = limits
    }

    mutating func consume(_ amount: Int = 1) throws(PluginExecutionStubError) {
        guard amount >= 0, amount <= limits.maximumWorkUnits - consumed else {
            throw PluginExecutionStubError.workLimitExceeded(
                maximum: limits.maximumWorkUnits
            )
        }
        var remaining = amount
        while remaining > 0 {
            let untilCheckpoint =
                limits.cancellationCheckInterval
                - consumed % limits.cancellationCheckInterval
            let step = min(remaining, untilCheckpoint)
            consumed += step
            remaining -= step
            if consumed.isMultiple(of: limits.cancellationCheckInterval) {
                try pluginExecutionStubCheckCancellation()
            }
        }
    }
}

private func pluginExecutionStubCheckCancellation() throws(PluginExecutionStubError) {
    if Task.isCancelled {
        throw PluginExecutionStubError.cancelled
    }
}

private func pluginExecutionStubCatalogSelect(
    _ request: PluginManagementSelectionRequest,
    snapshot: PluginManagementSnapshot,
    authorizations: [PluginIdentifier: PluginAuthorization],
    limits: PluginExecutionStubLimits,
    budget: inout PluginExecutionStubWorkBudget
) throws(PluginExecutionStubError) -> PluginCatalogSelectionOutcome {
    try pluginExecutionStubCheckCancellation()
    let candidates: [PluginCatalogItem]
    do {
        candidates = try snapshot.catalog.items(matching: request.filter)
    } catch is CancellationError {
        throw PluginExecutionStubError.cancelled
    } catch let error as PluginCatalogError {
        throw PluginExecutionStubError.workflow(.catalog(error))
    } catch {
        throw PluginExecutionStubError.workflow(.unexpectedCatalogFailure)
    }
    guard candidates.count <= limits.maximumResultCount else {
        throw PluginExecutionStubError.workflow(
            .resultLimitExceeded(maximum: limits.maximumResultCount)
        )
    }
    try budget.consume(candidates.count)
    let outcome: PluginCatalogSelectionOutcome
    do {
        outcome = try snapshot.catalog.select(
            matching: request.filter,
            mode: request.mode,
            authorizations: authorizations,
            preferences: snapshot.preferences,
            externalToolPolicy: snapshot.externalToolPolicy
        )
    } catch is CancellationError {
        throw PluginExecutionStubError.cancelled
    } catch let error as PluginCatalogError {
        throw PluginExecutionStubError.workflow(.catalog(error))
    } catch {
        throw PluginExecutionStubError.workflow(.unexpectedCatalogFailure)
    }
    if case .ambiguous(let identifiers) = outcome,
        identifiers.count > limits.maximumResultCount
    {
        throw PluginExecutionStubError.workflow(
            .resultLimitExceeded(maximum: limits.maximumResultCount)
        )
    }
    try pluginExecutionStubCheckCancellation()
    return outcome
}
