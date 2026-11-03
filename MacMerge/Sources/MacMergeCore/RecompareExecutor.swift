import Foundation

/// UI-independent Recompare As executor stub.
///
/// Binds an owner-supplied source snapshot (identity/revision/kind per pane), the
/// source/capability matrix in `RecompareModePlanner`, and exact caller-chosen
/// `RecompareModeOptions` to a phased `RecompareModePlan`. Plan-only: performs no
/// menu, document, parser, comparison-engine, filesystem, clipboard, network, or UI
/// work. Menu/document executor adoption remains missing; a future owner layer
/// consumes `modePlan` and enforces `executorContract`.
public struct RecompareExecutorRequest: Equatable, Hashable, Sendable {
    public let request: RecompareModeRequest
    public let expectedSources: RecompareModeSourceSnapshotReference?

    public init(
        request: RecompareModeRequest,
        expectedSources: RecompareModeSourceSnapshotReference? = nil
    ) {
        self.request = request
        self.expectedSources = expectedSources
    }
}

public enum RecompareExecutorPhase: Equatable, Hashable, Sendable {
    case validateSources
    case validateCapabilities(currentMode: RecompareMode, targetMode: RecompareMode)
    case bindOptions(mode: RecompareMode)
    case freezeReceipt
}

public enum RecompareExecutorError: Error, Equatable, Hashable, LocalizedError, Sendable {
    case cancelled
    case planningFailed(RecompareModePlanningError)
    case validationFailed

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Recompare executor planning was cancelled."
        case .planningFailed(let error):
            "Recompare executor planning failed: \(error.localizedDescription)"
        case .validationFailed:
            "Recompare executor source validation failed."
        }
    }
}

public enum RecompareExecutorContract: String, Equatable, Hashable, Sendable {
    case planOnlyNoMenuDocumentExecution
}

/// Deterministic executor receipt. The planning receipt stays authoritative;
/// `phaseCount` records the frozen phased binding with no clock or UI state.
public struct RecompareExecutorReceipt: Equatable, Hashable, Sendable {
    public let modeReceipt: RecompareModePlanReceipt
    public let phaseCount: Int

    fileprivate init(modeReceipt: RecompareModePlanReceipt, phaseCount: Int) {
        self.modeReceipt = modeReceipt
        self.phaseCount = phaseCount
    }

    public var sourceReference: RecompareModeSourceSnapshotReference { modeReceipt.sourceReference }
    public var sources: [RecompareModeSourceBinding] { modeReceipt.sources }
    public var currentMode: RecompareMode { modeReceipt.currentMode }
    public var targetMode: RecompareMode { modeReceipt.targetMode }
    public var options: RecompareModeOptions { modeReceipt.options }
    public var declaredWorkUnits: UInt64 { modeReceipt.declaredWorkUnits }
    public var planningWorkUnits: Int { modeReceipt.planningWorkUnits }
    public var limits: RecompareModePlanLimits { modeReceipt.limits }
}

/// Phased plan output. Construction performs no comparison, I/O, or UI work.
public struct RecompareExecutorPlan: Equatable, Hashable, Sendable {
    public let expectedSources: RecompareModeSourceSnapshot
    public let phases: [RecompareExecutorPhase]
    public let modePlan: RecompareModePlan
    public let receipt: RecompareExecutorReceipt
    public let executorContract = RecompareExecutorContract.planOnlyNoMenuDocumentExecution

    fileprivate init(
        expectedSources: RecompareModeSourceSnapshot,
        phases: [RecompareExecutorPhase],
        modePlan: RecompareModePlan,
        receipt: RecompareExecutorReceipt
    ) {
        self.expectedSources = expectedSources
        self.phases = phases
        self.modePlan = modePlan
        self.receipt = receipt
    }

    public func requireCurrentSources(_ snapshot: RecompareModeSourceSnapshot) throws {
        try modePlan.requireCurrentSources(snapshot)
    }

    public func isCurrent(for snapshot: RecompareModeSourceSnapshot) throws -> Bool {
        try modePlan.isCurrent(for: snapshot)
    }
}

public enum RecompareExecutorOutcome: Equatable, Hashable, Sendable {
    case completed(RecompareExecutorReceipt)
    case failed(RecompareExecutorError)
    case cancelled
}

/// Side-effect implementation supplied by a future owner layer. It must call
/// `plan.requireCurrentSources` before any recompare effect and must enforce
/// `RecompareExecutorContract.planOnlyNoMenuDocumentExecution` until native
/// menu/document execution exists.
public protocol RecomparePlanExecutor: Sendable {
    func execute(
        _ plan: RecompareExecutorPlan,
        validating currentSources: RecompareModeSourceSnapshot
    ) async -> RecompareExecutorOutcome
}

public enum RecompareExecutor: Sendable {
    public static func plan(_ request: RecompareExecutorRequest) throws -> RecompareExecutorPlan {
        do {
            return try makePlan(request)
        } catch is CancellationError {
            throw RecompareExecutorError.cancelled
        } catch let error as RecompareExecutorError {
            throw error
        } catch let error as RecompareModePlanningError {
            if error == .cancelled {
                throw RecompareExecutorError.cancelled
            }
            throw RecompareExecutorError.planningFailed(error)
        }
    }

    fileprivate static func makePlan(_ request: RecompareExecutorRequest) throws -> RecompareExecutorPlan {
        try Task.checkCancellation()
        let modePlan = try RecompareModePlanner.plan(request.request, expecting: request.expectedSources)
        try Task.checkCancellation()
        let phases: [RecompareExecutorPhase] = [
            .validateSources,
            .validateCapabilities(currentMode: modePlan.currentMode, targetMode: modePlan.targetMode),
            .bindOptions(mode: modePlan.targetMode),
            .freezeReceipt
        ]
        return RecompareExecutorPlan(
            expectedSources: request.request.sources,
            phases: phases,
            modePlan: modePlan,
            receipt: RecompareExecutorReceipt(modeReceipt: modePlan.receipt, phaseCount: phases.count)
        )
    }
}

/// Plan-only stub executor: revalidates the source snapshot and returns the
/// planning receipt without performing any recompare. Menu/document execution
/// remains unimplemented.
public struct RecompareStubExecutor: RecomparePlanExecutor {
    public init() {}

    public func execute(
        _ plan: RecompareExecutorPlan,
        validating currentSources: RecompareModeSourceSnapshot
    ) async -> RecompareExecutorOutcome {
        if Task.isCancelled {
            return .cancelled
        }
        do {
            try plan.requireCurrentSources(currentSources)
        } catch is CancellationError {
            return .cancelled
        } catch let error as RecompareModePlanningError {
            if error == .cancelled {
                return .cancelled
            }
            return .failed(.planningFailed(error))
        } catch {
            return .failed(.validationFailed)
        }
        if Task.isCancelled {
            return .cancelled
        }
        return .completed(plan.receipt)
    }
}
