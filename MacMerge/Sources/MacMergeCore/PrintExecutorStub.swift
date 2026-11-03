import Foundation

/// UI-independent print planning executor stub.
///
/// Binds an immutable comparison snapshot (document, validated page geometry, layout,
/// headers/footers, page range, limits) to a phased plan carrying a
/// `ComparisonPrintPreviewPlan`. Plan-only: performs no AppKit printing, page setup,
/// preview UI, or printer I/O. A future AppKit layer consumes `preview` and enforces
/// `executorContract`.
public struct ComparisonPrintExecutorSnapshot: Equatable, Sendable {
    public let identity: UUID
    public let generation: UInt64
    public let document: ComparisonPrintDocument
    public let pageSetup: ComparisonPrintPageSetup
    public let layout: ComparisonPrintLayout
    public let headerFooter: ComparisonPrintHeaderFooter
    public let pageRange: ComparisonPrintPageRange?
    public let limits: ComparisonPrintLimits

    public init(
        identity: UUID = UUID(),
        generation: UInt64,
        document: ComparisonPrintDocument,
        pageSetup: ComparisonPrintPageSetup,
        layout: ComparisonPrintLayout = .default,
        headerFooter: ComparisonPrintHeaderFooter = .default,
        pageRange: ComparisonPrintPageRange? = nil,
        limits: ComparisonPrintLimits = .default
    ) {
        self.identity = identity
        self.generation = generation
        self.document = document
        self.pageSetup = pageSetup
        self.layout = layout
        self.headerFooter = headerFooter
        self.pageRange = pageRange
        self.limits = limits
    }
}

public struct ComparisonPrintExecutorSnapshotReference: Equatable, Hashable, Sendable {
    public let identity: UUID
    public let generation: UInt64

    public init(identity: UUID, generation: UInt64) {
        self.identity = identity
        self.generation = generation
    }

    public init(_ snapshot: ComparisonPrintExecutorSnapshot) {
        identity = snapshot.identity
        generation = snapshot.generation
    }
}

public struct ComparisonPrintExecutorRequest: Equatable, Sendable {
    public let snapshot: ComparisonPrintExecutorSnapshot
    public let expectedSnapshot: ComparisonPrintExecutorSnapshotReference?

    public init(
        snapshot: ComparisonPrintExecutorSnapshot,
        expectedSnapshot: ComparisonPrintExecutorSnapshotReference? = nil
    ) {
        self.snapshot = snapshot
        self.expectedSnapshot = expectedSnapshot
    }
}

public enum ComparisonPrintExecutorPhase: Equatable, Sendable {
    case validateInputs
    case planPreview(totalPageCount: Int)
    case bindSelection(firstPage: Int, lastPage: Int)
}

public enum ComparisonPrintExecutorError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case staleIdentity(expected: UUID, actual: UUID)
    case staleGeneration(expected: UInt64, actual: UInt64)
    case snapshotContentsChanged
    case planningFailed(ComparisonPrintingError)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Print executor planning was cancelled."
        case .staleIdentity:
            "Print executor plan belongs to another snapshot."
        case .staleGeneration(let expected, let actual):
            "Print executor plan expects generation \(expected), not \(actual)."
        case .snapshotContentsChanged:
            "Print executor snapshot changed without a generation change."
        case .planningFailed(let error):
            "Print executor planning failed: \(error.localizedDescription)"
        }
    }
}

public enum ComparisonPrintExecutorContract: String, Equatable, Hashable, Sendable {
    case planOnlyNoAppKitPrinting
}

public struct ComparisonPrintExecutorReceipt: Equatable, Sendable {
    public let snapshot: ComparisonPrintExecutorSnapshotReference
    public let totalPageCount: Int
    public let firstPage: Int
    public let lastPage: Int
    public let phaseCount: Int

    fileprivate init(
        snapshot: ComparisonPrintExecutorSnapshotReference,
        totalPageCount: Int,
        firstPage: Int,
        lastPage: Int,
        phaseCount: Int
    ) {
        self.snapshot = snapshot
        self.totalPageCount = totalPageCount
        self.firstPage = firstPage
        self.lastPage = lastPage
        self.phaseCount = phaseCount
    }
}

/// Phased plan output. Construction performs no printer, panel, preview, or UI work.
public struct ComparisonPrintExecutorPlan: Equatable, Sendable {
    public let expectedSnapshot: ComparisonPrintExecutorSnapshot
    public let phases: [ComparisonPrintExecutorPhase]
    public let preview: ComparisonPrintPreviewPlan
    public let receipt: ComparisonPrintExecutorReceipt
    public let executorContract = ComparisonPrintExecutorContract.planOnlyNoAppKitPrinting

    fileprivate init(
        expectedSnapshot: ComparisonPrintExecutorSnapshot,
        phases: [ComparisonPrintExecutorPhase],
        preview: ComparisonPrintPreviewPlan,
        receipt: ComparisonPrintExecutorReceipt
    ) {
        self.expectedSnapshot = expectedSnapshot
        self.phases = phases
        self.preview = preview
        self.receipt = receipt
    }

    public func validateCurrentSnapshot(_ snapshot: ComparisonPrintExecutorSnapshot) throws {
        guard snapshot.identity == expectedSnapshot.identity else {
            throw ComparisonPrintExecutorError.staleIdentity(
                expected: expectedSnapshot.identity,
                actual: snapshot.identity
            )
        }
        guard snapshot.generation == expectedSnapshot.generation else {
            throw ComparisonPrintExecutorError.staleGeneration(
                expected: expectedSnapshot.generation,
                actual: snapshot.generation
            )
        }
        guard snapshot == expectedSnapshot else {
            throw ComparisonPrintExecutorError.snapshotContentsChanged
        }
    }

    public func isCurrent(_ snapshot: ComparisonPrintExecutorSnapshot) -> Bool {
        do {
            try validateCurrentSnapshot(snapshot)
            return true
        } catch {
            return false
        }
    }
}

public enum ComparisonPrintExecutorOutcome: Equatable, Sendable {
    case completed(ComparisonPrintExecutorReceipt)
    case failed(ComparisonPrintExecutorError)
    case cancelled
}

/// Side-effect implementation supplied by a future AppKit layer. It must call
/// `plan.validateCurrentSnapshot` before any printing effect and must enforce
/// `ComparisonPrintExecutorContract.planOnlyNoAppKitPrinting` until native
/// print/page-setup/preview UI exists.
public protocol ComparisonPrintPlanExecutor: Sendable {
    func execute(
        _ plan: ComparisonPrintExecutorPlan,
        validating currentSnapshot: ComparisonPrintExecutorSnapshot
    ) async -> ComparisonPrintExecutorOutcome
}

public enum ComparisonPrintExecutor: Sendable {
    public static func plan(_ request: ComparisonPrintExecutorRequest) throws -> ComparisonPrintExecutorPlan {
        do {
            return try makePlan(request)
        } catch is CancellationError {
            throw ComparisonPrintExecutorError.cancelled
        } catch let error as ComparisonPrintingError {
            throw ComparisonPrintExecutorError.planningFailed(error)
        }
    }

    fileprivate static func makePlan(_ request: ComparisonPrintExecutorRequest) throws -> ComparisonPrintExecutorPlan {
        try Task.checkCancellation()
        if let expected = request.expectedSnapshot {
            guard expected.identity == request.snapshot.identity else {
                throw ComparisonPrintExecutorError.staleIdentity(
                    expected: expected.identity,
                    actual: request.snapshot.identity
                )
            }
            guard expected.generation == request.snapshot.generation else {
                throw ComparisonPrintExecutorError.staleGeneration(
                    expected: expected.generation,
                    actual: request.snapshot.generation
                )
            }
        }
        try Task.checkCancellation()
        let snapshot = request.snapshot
        let preview = try ComparisonPrintPlanner.planPreview(
            document: snapshot.document,
            pageSetup: snapshot.pageSetup,
            layout: snapshot.layout,
            headerFooter: snapshot.headerFooter,
            pageRange: snapshot.pageRange,
            limits: snapshot.limits
        )
        try Task.checkCancellation()
        let phases: [ComparisonPrintExecutorPhase] = [
            .validateInputs,
            .planPreview(totalPageCount: preview.totalPageCount),
            .bindSelection(
                firstPage: preview.selectedPageRange.firstPage,
                lastPage: preview.selectedPageRange.lastPage
            )
        ]
        let reference = ComparisonPrintExecutorSnapshotReference(snapshot)
        return ComparisonPrintExecutorPlan(
            expectedSnapshot: snapshot,
            phases: phases,
            preview: preview,
            receipt: ComparisonPrintExecutorReceipt(
                snapshot: reference,
                totalPageCount: preview.totalPageCount,
                firstPage: preview.selectedPageRange.firstPage,
                lastPage: preview.selectedPageRange.lastPage,
                phaseCount: phases.count
            )
        )
    }
}

/// Plan-only stub executor: revalidates the snapshot and returns the planning receipt
/// without performing any printing. Native AppKit printing remains unimplemented.
public struct ComparisonPrintStubExecutor: ComparisonPrintPlanExecutor {
    public init() {}

    public func execute(
        _ plan: ComparisonPrintExecutorPlan,
        validating currentSnapshot: ComparisonPrintExecutorSnapshot
    ) async -> ComparisonPrintExecutorOutcome {
        if Task.isCancelled {
            return .cancelled
        }
        do {
            try plan.validateCurrentSnapshot(currentSnapshot)
        } catch let error as ComparisonPrintExecutorError {
            return .failed(error)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(.snapshotContentsChanged)
        }
        if Task.isCancelled {
            return .cancelled
        }
        return .completed(plan.receipt)
    }
}
