import Foundation

/// UI-independent folder-results presentation planner.
///
/// Projects one validated ``FolderComparisonWorkflowSnapshot`` through the exact workflow filter,
/// multi-key sort, hidden-row, and table/tree policies owned by
/// ``FolderComparisonWorkflowPlanner`` into flat row models that native table and outline views can
/// consume without filesystem, security-scope, scanner, comparator, or file-operation work.
///
/// Stable identity: ``FolderResultsPresentationRow/id`` is the content-derived
/// ``DirectoryResult/ID``. It is stable across snapshots for the same logical result, so callers
/// persist ``FolderResultsPresentationSnapshot/selectedResultIDs`` (not row ordinals) to keep
/// selection across refreshes, filter changes, and resorting. ``visibleOrdinal`` is valid only
/// within its snapshot.
///
/// Stale validation: a snapshot pins the exact ``FolderComparisonWorkflowSnapshotReference``
/// produced during planning. ``FolderResultsPresentationSnapshot/validateCurrent(_:)`` rejects an
/// identity, generation, owner, or content change before a view renders or opens pairs.
///
/// Bounds and cancellation: planning consumes a bounded work budget and honors cooperative task
/// cancellation before and during row projection. Native views, executors, and app routing remain
/// outside this file; it performs no rendering, localization, or mutation.
public enum FolderResultsPresentationLimit: String, CaseIterable, Hashable, Sendable {
    case rowCount
    case stringUTF8Bytes
    case totalStringUTF8Bytes
    case workUnits
    case cancellationCheckInterval
}

public struct FolderResultsPresentationLimits: Hashable, Sendable {
    public static let hardMaximumRowCount = 2_000_000
    public static let hardMaximumStringUTF8Bytes = 64 * 1_024
    public static let hardMaximumTotalStringUTF8Bytes = 256 * 1_024 * 1_024
    public static let hardMaximumWorkUnits: UInt64 = 4 * 1_024 * 1_024 * 1_024
    public static let hardMaximumCancellationCheckInterval = 4_096
    public static let `default` = FolderResultsPresentationLimits()

    public let maximumRowCount: Int
    public let maximumStringUTF8Bytes: Int
    public let maximumTotalStringUTF8Bytes: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: Int

    public init(
        maximumRowCount: Int = 1_000_000,
        maximumStringUTF8Bytes: Int = 16 * 1_024,
        maximumTotalStringUTF8Bytes: Int = 64 * 1_024 * 1_024,
        maximumWorkUnits: UInt64 = 512 * 1_024 * 1_024,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumRowCount = maximumRowCount
        self.maximumStringUTF8Bytes = maximumStringUTF8Bytes
        self.maximumTotalStringUTF8Bytes = maximumTotalStringUTF8Bytes
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum FolderResultsPresentationError: Error, Hashable, LocalizedError, Sendable {
    case cancelled
    case invalidLimit(FolderResultsPresentationLimit, value: String)
    case workflow(FolderComparisonWorkflowError)
    case tooManyRows(maximum: Int)
    case stringTooLarge(maximumUTF8Bytes: Int)
    case totalStringsTooLarge(maximumUTF8Bytes: Int)
    case workLimitExceeded(maximumWorkUnits: UInt64)
    case unknownSelectedResult(DirectoryResult.ID)
    case unknownCursorResult(DirectoryResult.ID)
    case staleSnapshot
    case snapshotContentsChanged

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Folder results presentation was cancelled."
        case .invalidLimit(let limit, let value):
            "Invalid folder results presentation limit \(limit.rawValue): \(value)."
        case .workflow(let error):
            error.errorDescription
        case .tooManyRows(let maximum):
            "Folder results presentation exceeds the \(maximum)-row limit."
        case .stringTooLarge(let maximum):
            "Folder results presentation string exceeds \(maximum) UTF-8 bytes."
        case .totalStringsTooLarge(let maximum):
            "Folder results presentation strings exceed \(maximum) combined UTF-8 bytes."
        case .workLimitExceeded(let maximum):
            "Folder results presentation exceeds the \(maximum)-unit work limit."
        case .unknownSelectedResult:
            "Folder results selection references an unknown result."
        case .unknownCursorResult:
            "Folder results cursor references an unknown result."
        case .staleSnapshot:
            "Folder results snapshot identity, generation, or owner is stale."
        case .snapshotContentsChanged:
            "Folder results snapshot changed without advancing generation."
        }
    }
}

/// One visible row in exact projected order. Table mode rows all have a nil parent; tree mode rows
/// arrive in preorder with parent links and depths assigned by the workflow planner.
public struct FolderResultsPresentationRow: Identifiable, Hashable, Sendable {
    public let id: DirectoryResult.ID
    public let relativePath: String
    public let status: DirectoryComparisonStatus
    public let kind: DirectoryEntryKind?
    public let stateIcon: FolderComparisonStateIcon
    public let left: FolderComparisonPresentationSideValue?
    public let right: FolderComparisonPresentationSideValue?
    public let treeParentID: DirectoryResult.ID?
    public let treeDepth: Int
    /// Zero-based position in ``FolderResultsPresentationSnapshot/rows``.
    public let visibleOrdinal: Int
    public let isSelected: Bool
    public let isCursor: Bool

    public var isHidden: Bool {
        left?.isHidden == true || right?.isHidden == true
    }

    fileprivate init(
        planRow: FolderComparisonPresentationRow,
        visibleOrdinal: Int,
        isSelected: Bool,
        isCursor: Bool
    ) {
        id = planRow.id
        relativePath = planRow.relativePath
        status = planRow.status
        kind = planRow.kind
        stateIcon = planRow.stateIcon
        left = planRow.left
        right = planRow.right
        treeParentID = planRow.treeParentID
        treeDepth = planRow.treeDepth
        self.visibleOrdinal = visibleOrdinal
        self.isSelected = isSelected
        self.isCursor = isCursor
    }
}

public struct FolderResultsPresentationReceipt: Hashable, Sendable {
    public let inputResultCount: Int
    public let outputRowCount: Int
    public let filteredOutResultCount: Int
    public let estimatedWorkUnits: UInt64

    fileprivate init(
        inputResultCount: Int,
        outputRowCount: Int,
        filteredOutResultCount: Int,
        estimatedWorkUnits: UInt64
    ) {
        self.inputResultCount = inputResultCount
        self.outputRowCount = outputRowCount
        self.filteredOutResultCount = filteredOutResultCount
        self.estimatedWorkUnits = estimatedWorkUnits
    }
}

public struct FolderResultsPresentationRequest: Hashable, Sendable {
    public let snapshot: FolderComparisonWorkflowSnapshot
    public let configuration: FolderComparisonPresentationConfiguration
    /// Retained across refreshes by result ID; IDs absent from the snapshot are rejected.
    public let selectedResultIDs: Set<DirectoryResult.ID>
    public let cursorResultID: DirectoryResult.ID?
    public let capabilities: FolderComparisonWorkflowCapabilities
    public let workflowLimits: FolderComparisonWorkflowLimits
    public let presentationLimits: FolderResultsPresentationLimits

    public init(
        snapshot: FolderComparisonWorkflowSnapshot,
        configuration: FolderComparisonPresentationConfiguration = FolderComparisonPresentationConfiguration(),
        selectedResultIDs: Set<DirectoryResult.ID> = [],
        cursorResultID: DirectoryResult.ID? = nil,
        capabilities: FolderComparisonWorkflowCapabilities,
        workflowLimits: FolderComparisonWorkflowLimits = .default,
        presentationLimits: FolderResultsPresentationLimits = .default
    ) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.selectedResultIDs = selectedResultIDs
        self.cursorResultID = cursorResultID
        self.capabilities = capabilities
        self.workflowLimits = workflowLimits
        self.presentationLimits = presentationLimits
    }
}

/// Immutable projected rows plus the retained selection. Views render `rows` directly: table views
/// use flat order, outline views use `rootRows` and `children(of:)`; both key rows by `id`.
public struct FolderResultsPresentationSnapshot: Hashable, Sendable {
    public let snapshot: FolderComparisonWorkflowSnapshotReference
    public let configuration: FolderComparisonPresentationConfiguration
    public let rows: [FolderResultsPresentationRow]
    /// Requested selection intersected with snapshot IDs, including filtered-out rows.
    public let selectedResultIDs: Set<DirectoryResult.ID>
    public let cursorResultID: DirectoryResult.ID?
    public let totalResultCount: Int
    public let workflowLimits: FolderComparisonWorkflowLimits
    public let presentationLimits: FolderResultsPresentationLimits
    public let receipt: FolderResultsPresentationReceipt

    private let rowsByID: [DirectoryResult.ID: FolderResultsPresentationRow]
    private let childIDsByParentID: [DirectoryResult.ID: [DirectoryResult.ID]]
    private let rootIDs: [DirectoryResult.ID]

    public var filteredOutResultCount: Int {
        totalResultCount - rows.count
    }

    public var visibleSelectedRows: [FolderResultsPresentationRow] {
        rows.filter(\.isSelected)
    }

    /// Selected IDs with no visible row, kept so filter or sort changes restore them.
    public var hiddenSelectedResultIDs: Set<DirectoryResult.ID> {
        selectedResultIDs.subtracting(rows.map(\.id))
    }

    public var rootRows: [FolderResultsPresentationRow] {
        rootIDs.compactMap { rowsByID[$0] }
    }

    public func row(withID id: DirectoryResult.ID) -> FolderResultsPresentationRow? {
        rowsByID[id]
    }

    public func children(of id: DirectoryResult.ID) -> [FolderResultsPresentationRow] {
        (childIDsByParentID[id] ?? []).compactMap { rowsByID[$0] }
    }

    public func validateCurrent(_ current: FolderComparisonWorkflowSnapshot) throws {
        do {
            guard current.identity == snapshot.identity,
                current.generation == snapshot.generation,
                current.owner == snapshot.owner
            else {
                throw FolderResultsPresentationError.staleSnapshot
            }
            let currentReference = try FolderComparisonWorkflowPlanner.reference(
                to: current,
                limits: workflowLimits
            )
            guard currentReference.contentSHA256 == snapshot.contentSHA256 else {
                throw FolderResultsPresentationError.snapshotContentsChanged
            }
        } catch FolderComparisonWorkflowError.cancelled, is CancellationError {
            throw FolderResultsPresentationError.cancelled
        } catch let error as FolderComparisonWorkflowError {
            throw FolderResultsPresentationError.workflow(error)
        }
    }

    /// Non-throwing freshness check for view update paths. False covers stale, changed, invalid,
    /// and cancelled validation; use `validateCurrent(_:)` for the exact reason.
    public func isCurrent(for current: FolderComparisonWorkflowSnapshot) -> Bool {
        do {
            try validateCurrent(current)
            return true
        } catch {
            return false
        }
    }

    fileprivate init(
        snapshot: FolderComparisonWorkflowSnapshotReference,
        configuration: FolderComparisonPresentationConfiguration,
        rows: [FolderResultsPresentationRow],
        selectedResultIDs: Set<DirectoryResult.ID>,
        cursorResultID: DirectoryResult.ID?,
        totalResultCount: Int,
        workflowLimits: FolderComparisonWorkflowLimits,
        presentationLimits: FolderResultsPresentationLimits,
        receipt: FolderResultsPresentationReceipt
    ) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.rows = rows
        self.selectedResultIDs = selectedResultIDs
        self.cursorResultID = cursorResultID
        self.totalResultCount = totalResultCount
        self.workflowLimits = workflowLimits
        self.presentationLimits = presentationLimits
        self.receipt = receipt
        var rowsByID: [DirectoryResult.ID: FolderResultsPresentationRow] = [:]
        rowsByID.reserveCapacity(rows.count)
        var childIDsByParentID: [DirectoryResult.ID: [DirectoryResult.ID]] = [:]
        var rootIDs: [DirectoryResult.ID] = []
        rootIDs.reserveCapacity(rows.count)
        for row in rows {
            rowsByID[row.id] = row
            if let parentID = row.treeParentID {
                childIDsByParentID[parentID, default: []].append(row.id)
            } else {
                rootIDs.append(row.id)
            }
        }
        self.rowsByID = rowsByID
        self.childIDsByParentID = childIDsByParentID
        self.rootIDs = rootIDs
    }
}

/// Pure projector. It performs no filesystem, security-scope, comparison, rendering, or
/// owner-state mutation; filtering, sorting, and tree parenting come from the workflow planner.
public enum FolderResultsPresentationPlanner: Sendable {
    public static func project(
        _ request: FolderResultsPresentationRequest
    ) throws -> FolderResultsPresentationSnapshot {
        do {
            try validate(request.presentationLimits)
            var work = FolderResultsPresentationWork(limits: request.presentationLimits)
            let plan = try planPresentation(
                snapshot: request.snapshot,
                configuration: request.configuration,
                capabilities: request.capabilities,
                workflowLimits: request.workflowLimits
            )
            guard plan.rows.count <= request.presentationLimits.maximumRowCount else {
                throw FolderResultsPresentationError.tooManyRows(
                    maximum: request.presentationLimits.maximumRowCount
                )
            }
            var availableIDs = Set<DirectoryResult.ID>(minimumCapacity: request.snapshot.results.count)
            for result in request.snapshot.results {
                try work.consume(1)
                availableIDs.insert(result.id)
            }
            for id in request.selectedResultIDs {
                try work.measure(id)
                guard availableIDs.contains(id) else {
                    throw FolderResultsPresentationError.unknownSelectedResult(id)
                }
            }
            if let cursor = request.cursorResultID {
                try work.measure(cursor)
                guard availableIDs.contains(cursor) else {
                    throw FolderResultsPresentationError.unknownCursorResult(cursor)
                }
            }
            var rows: [FolderResultsPresentationRow] = []
            rows.reserveCapacity(plan.rows.count)
            for (ordinal, planRow) in plan.rows.enumerated() {
                try work.consume(1)
                try work.checkCancellation()
                rows.append(
                    FolderResultsPresentationRow(
                        planRow: planRow,
                        visibleOrdinal: ordinal,
                        isSelected: request.selectedResultIDs.contains(planRow.id),
                        isCursor: request.cursorResultID == planRow.id
                    )
                )
            }
            try work.checkCancellation()
            return FolderResultsPresentationSnapshot(
                snapshot: plan.snapshot,
                configuration: request.configuration,
                rows: rows,
                selectedResultIDs: request.selectedResultIDs,
                cursorResultID: request.cursorResultID,
                totalResultCount: request.snapshot.results.count,
                workflowLimits: request.workflowLimits,
                presentationLimits: request.presentationLimits,
                receipt: FolderResultsPresentationReceipt(
                    inputResultCount: request.snapshot.results.count,
                    outputRowCount: rows.count,
                    filteredOutResultCount: request.snapshot.results.count - rows.count,
                    estimatedWorkUnits: work.consumed
                )
            )
        } catch FolderComparisonWorkflowError.cancelled, is CancellationError {
            throw FolderResultsPresentationError.cancelled
        } catch let error as FolderComparisonWorkflowError {
            throw FolderResultsPresentationError.workflow(error)
        }
    }

    private static func planPresentation(
        snapshot: FolderComparisonWorkflowSnapshot,
        configuration: FolderComparisonPresentationConfiguration,
        capabilities: FolderComparisonWorkflowCapabilities,
        workflowLimits: FolderComparisonWorkflowLimits
    ) throws -> FolderComparisonPresentationPlan {
        try FolderComparisonWorkflowPlanner.planPresentation(
            FolderComparisonPresentationRequest(
                snapshot: snapshot,
                configuration: configuration,
                capabilities: capabilities,
                limits: workflowLimits
            )
        )
    }

    private static func validate(_ limits: FolderResultsPresentationLimits) throws {
        guard (0...FolderResultsPresentationLimits.hardMaximumRowCount).contains(limits.maximumRowCount) else {
            throw FolderResultsPresentationError.invalidLimit(
                .rowCount,
                value: String(limits.maximumRowCount)
            )
        }
        guard
            (1...FolderResultsPresentationLimits.hardMaximumStringUTF8Bytes).contains(
                limits.maximumStringUTF8Bytes
            )
        else {
            throw FolderResultsPresentationError.invalidLimit(
                .stringUTF8Bytes,
                value: String(limits.maximumStringUTF8Bytes)
            )
        }
        guard
            (1...FolderResultsPresentationLimits.hardMaximumTotalStringUTF8Bytes).contains(
                limits.maximumTotalStringUTF8Bytes
            )
        else {
            throw FolderResultsPresentationError.invalidLimit(
                .totalStringUTF8Bytes,
                value: String(limits.maximumTotalStringUTF8Bytes)
            )
        }
        guard limits.maximumWorkUnits > 0,
            limits.maximumWorkUnits <= FolderResultsPresentationLimits.hardMaximumWorkUnits
        else {
            throw FolderResultsPresentationError.invalidLimit(
                .workUnits,
                value: String(limits.maximumWorkUnits)
            )
        }
        guard
            (1...FolderResultsPresentationLimits.hardMaximumCancellationCheckInterval).contains(
                limits.cancellationCheckInterval
            )
        else {
            throw FolderResultsPresentationError.invalidLimit(
                .cancellationCheckInterval,
                value: String(limits.cancellationCheckInterval)
            )
        }
    }
}

private struct FolderResultsPresentationWork {
    let limits: FolderResultsPresentationLimits
    private(set) var consumed: UInt64 = 0
    private var stringsUTF8Bytes = 0
    private var unitsSinceCancellationCheck = 0

    init(limits: FolderResultsPresentationLimits) {
        self.limits = limits
    }

    mutating func consume(_ units: Int) throws {
        guard units >= 0, let units = UInt64(exactly: units) else {
            throw FolderResultsPresentationError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        let sum = consumed.addingReportingOverflow(units)
        guard !sum.overflow, sum.partialValue <= limits.maximumWorkUnits else {
            throw FolderResultsPresentationError.workLimitExceeded(
                maximumWorkUnits: limits.maximumWorkUnits
            )
        }
        consumed = sum.partialValue
        unitsSinceCancellationCheck += min(Int(units), limits.cancellationCheckInterval)
        if unitsSinceCancellationCheck >= limits.cancellationCheckInterval {
            try checkCancellation()
            unitsSinceCancellationCheck = 0
        }
    }

    mutating func measure(_ id: DirectoryResult.ID) throws {
        if let left = id.leftRelativePath {
            try consumeString(left)
        }
        if let right = id.rightRelativePath {
            try consumeString(right)
        }
    }

    mutating func consumeString(_ value: String) throws {
        var count = 0
        for _ in value.utf8 {
            guard count < limits.maximumStringUTF8Bytes else {
                throw FolderResultsPresentationError.stringTooLarge(
                    maximumUTF8Bytes: limits.maximumStringUTF8Bytes
                )
            }
            count += 1
            try consume(1)
        }
        guard stringsUTF8Bytes <= limits.maximumTotalStringUTF8Bytes - count else {
            throw FolderResultsPresentationError.totalStringsTooLarge(
                maximumUTF8Bytes: limits.maximumTotalStringUTF8Bytes
            )
        }
        stringsUTF8Bytes += count
    }

    mutating func checkCancellation() throws {
        try Task.checkCancellation()
    }
}
