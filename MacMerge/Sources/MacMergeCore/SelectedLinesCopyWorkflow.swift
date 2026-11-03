import Foundation

/// Selected-line copy over the two-way multi-difference merge workflow.
///
/// WinMerge merge menu gap: directional copy (`ID_L2R`, `ID_R2L`, `ID_L2RNEXT`,
/// `ID_R2LNEXT`) exists, but the dedicated copy-from aliases (`ID_COPY_FROM_LEFT`,
/// `ID_COPY_FROM_RIGHT`, which call `OnCopyX2Y` into the active pane) and a
/// selected-lines copy (editor line selection expanded to full difference groups)
/// are missing. This planner is UI-independent: it resolves an alias to a
/// direction, expands a contiguous selected aligned-row interval to the maximal
/// significant difference groups intersecting it, validates comparison/generation
/// identity (comparison reference plus stable row identities), supports both
/// directions with copy-and-advance, and delegates mutation to
/// `MultiDifferenceMergeWorkflow` without modifying that type. The owner commit
/// stays atomic there; this file adds an atomic publication receipt chaining the
/// planning, commit, and publication evidence for one selected-lines copy.
public enum SelectedLinesCopyWorkflowAlias: String, CaseIterable, Equatable, Hashable, Sendable {
    case copyToRight
    case copyToLeft
    case copyToRightAndAdvance
    case copyToLeftAndAdvance
    case copyFromLeft
    case copyFromRight

    /// Merge direction the alias copies along.
    public var direction: MergeDirection {
        switch self {
        case .copyToRight, .copyToRightAndAdvance, .copyFromLeft:
            .leftToRight
        case .copyToLeft, .copyToLeftAndAdvance, .copyFromRight:
            .rightToLeft
        }
    }

    /// Whether the alias advances selection after copying.
    public var advancesSelection: Bool {
        switch self {
        case .copyToRightAndAdvance, .copyToLeftAndAdvance:
            true
        case .copyToRight, .copyToLeft, .copyFromLeft, .copyFromRight:
            false
        }
    }

    /// Canonical directional command this alias resolves to.
    public var canonicalAlias: SelectedLinesCopyWorkflowAlias {
        switch self {
        case .copyFromLeft:
            .copyToRight
        case .copyFromRight:
            .copyToLeft
        case .copyToRight, .copyToLeft, .copyToRightAndAdvance, .copyToLeftAndAdvance:
            self
        }
    }

    /// WinMerge `Src/resource.h` command identifier.
    public var winMergeCommandID: String {
        switch self {
        case .copyToRight:
            "ID_L2R"
        case .copyToLeft:
            "ID_R2L"
        case .copyToRightAndAdvance:
            "ID_L2RNEXT"
        case .copyToLeftAndAdvance:
            "ID_R2LNEXT"
        case .copyFromLeft:
            "ID_COPY_FROM_LEFT"
        case .copyFromRight:
            "ID_COPY_FROM_RIGHT"
        }
    }

    public var workflowIntent: MultiDifferenceMergeWorkflowCommandIntent {
        MultiDifferenceMergeWorkflowCommandIntent(
            direction: direction,
            advance: advancesSelection ? .advanceToNextDifference : .remain
        )
    }
}

public struct SelectedLinesCopyWorkflowLimits: Equatable, Sendable {
    public static let hardMaximumSelectedLines = 1_048_576
    public static let hardMaximumDifferenceGroups = 65_536
    public static let hardMaximumComparisonRows = 1_048_576
    public static let hardMaximumWorkUnits: UInt64 = 1 << 42
    public static let hardMaximumCancellationCheckInterval: UInt64 = 4_096
    public static let `default` = SelectedLinesCopyWorkflowLimits()

    public let maximumSelectedLines: Int
    public let maximumDifferenceGroups: Int
    public let maximumComparisonRows: Int
    public let maximumWorkUnits: UInt64
    public let cancellationCheckInterval: UInt64

    public init(
        maximumSelectedLines: Int = hardMaximumSelectedLines,
        maximumDifferenceGroups: Int = hardMaximumDifferenceGroups,
        maximumComparisonRows: Int = hardMaximumComparisonRows,
        maximumWorkUnits: UInt64 = 4 * 1_024 * 1_024 * 1_024,
        cancellationCheckInterval: UInt64 = 1_024
    ) {
        self.maximumSelectedLines = maximumSelectedLines
        self.maximumDifferenceGroups = maximumDifferenceGroups
        self.maximumComparisonRows = maximumComparisonRows
        self.maximumWorkUnits = maximumWorkUnits
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum SelectedLinesCopyWorkflowError: Error, LocalizedError, Equatable, Sendable {
    case cancelled
    case invalidLimit(String)
    case tooManySelectedLines(maximum: Int)
    case tooManyDifferenceGroups(maximum: Int)
    case tooManyComparisonRows(maximum: Int)
    case emptySelection
    case selectionOutOfBounds(requested: Range<Int>, rowCount: Int)
    case rowIdentityMismatch
    case staleComparisonIdentity
    case staleComparisonRevision(expected: UInt64, actual: UInt64)
    case selectionChanged
    case noSignificantDifferences
    case workflow(MultiDifferenceMergeWorkflowError)
    case arithmeticOverflow
    case workLimitExceeded(maximumUnits: UInt64)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Selected-lines copy was cancelled."
        case .invalidLimit(let name):
            "Invalid selected-lines copy limit: \(name)."
        case .tooManySelectedLines(let maximum):
            "Selected lines exceed the \(maximum)-line limit."
        case .tooManyDifferenceGroups(let maximum):
            "Selected lines exceed the \(maximum)-group limit."
        case .tooManyComparisonRows(let maximum):
            "Comparison exceeds the \(maximum)-row limit."
        case .emptySelection:
            "Selected-lines copy requires a non-empty line selection."
        case .selectionOutOfBounds(let requested, let rowCount):
            "Selected lines \(requested.lowerBound)..<\(requested.upperBound) are outside 0..<\(rowCount)."
        case .rowIdentityMismatch:
            "Selected-line identities do not match the comparison rows that produced them."
        case .staleComparisonIdentity:
            "Selected-lines copy belongs to another comparison."
        case .staleComparisonRevision(let expected, let actual):
            "Selected-lines copy expected comparison revision \(expected), not \(actual)."
        case .selectionChanged:
            "Selected-lines copy selection no longer matches the planned snapshot selection."
        case .noSignificantDifferences:
            "Selected lines contain no differences to copy."
        case .workflow(let error):
            error.localizedDescription
        case .arithmeticOverflow:
            "Selected-lines copy size calculation overflowed."
        case .workLimitExceeded(let maximum):
            "Selected-lines copy exceeds \(maximum) work units."
        }
    }
}

/// Maximal significant groups intersecting the selected lines, in ascending order.
public struct SelectedLinesCopyWorkflowExpansion: Equatable, Sendable {
    public let selectedAlignedRows: Range<Int>
    public let expandedGroups: [Range<Int>]
    public let expectedComparison: MultiDifferenceMergeWorkflowComparisonReference

    fileprivate init(
        selectedAlignedRows: Range<Int>,
        expandedGroups: [Range<Int>],
        expectedComparison: MultiDifferenceMergeWorkflowComparisonReference
    ) {
        self.selectedAlignedRows = selectedAlignedRows
        self.expandedGroups = expandedGroups
        self.expectedComparison = expectedComparison
    }
}

public struct SelectedLinesCopyWorkflowPlan: Equatable, Sendable {
    public let alias: SelectedLinesCopyWorkflowAlias
    public let expectedSnapshot: MultiDifferenceMergeWorkflowSnapshotReference
    public let expansion: SelectedLinesCopyWorkflowExpansion
    public let underlying: MultiDifferenceMergeWorkflowPlan
    public let limits: SelectedLinesCopyWorkflowLimits

    fileprivate init(
        alias: SelectedLinesCopyWorkflowAlias,
        expansion: SelectedLinesCopyWorkflowExpansion,
        underlying: MultiDifferenceMergeWorkflowPlan,
        limits: SelectedLinesCopyWorkflowLimits
    ) {
        self.alias = alias
        expectedSnapshot = underlying.expectedSnapshot
        self.expansion = expansion
        self.underlying = underlying
        self.limits = limits
    }

    public var direction: MergeDirection { alias.direction }
}

/// Atomic publication receipt chaining one selected-lines copy from planning
/// through owner commit to ordered publication. Executors must publish in
/// `completedEffects` order and never report completion with a prefix omitted.
public struct SelectedLinesCopyWorkflowAtomicReceipt: Equatable, Sendable {
    public let planningReceipt: MultiDifferenceMergeWorkflowPlanningReceipt
    public let commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt
    public let publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    public let completedEffects: [MultiDifferenceMergeWorkflowRequiredEffect]
    public let alias: SelectedLinesCopyWorkflowAlias
    public let expansion: SelectedLinesCopyWorkflowExpansion

    private init(
        plan: SelectedLinesCopyWorkflowPlan,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    ) {
        planningReceipt = plan.underlying.receipt
        self.commitReceipt = commitReceipt
        self.publicationReceipts = publicationReceipts
        completedEffects = plan.underlying.requiredEffects
        alias = plan.alias
        expansion = plan.expansion
    }

    /// Attests the full ordered effect chain after commit and publication complete.
    /// Throws `SelectedLinesCopyWorkflowError.workflow` when receipts do not
    /// belong to `plan`.
    public static func attestCompleted(
        plan: SelectedLinesCopyWorkflowPlan,
        commitReceipt: MultiDifferenceMergeWorkflowCommitReceipt,
        publicationReceipts: [MultiDifferenceMergeWorkflowPublicationReceipt]
    ) throws -> SelectedLinesCopyWorkflowAtomicReceipt {
        do {
            let outcome = try MultiDifferenceMergeWorkflowExecutionOutcomeFactory.completed(
                plan: plan.underlying,
                commitReceipt: commitReceipt,
                publicationReceipts: publicationReceipts
            )
            guard case .completed = outcome else {
                throw MultiDifferenceMergeWorkflowError.invalidExecutionOutcome
            }
        } catch let error as MultiDifferenceMergeWorkflowError {
            throw SelectedLinesCopyWorkflowError.workflow(error)
        } catch is CancellationError {
            throw SelectedLinesCopyWorkflowError.cancelled
        } catch {
            throw SelectedLinesCopyWorkflowError.workflow(.invalidExecutionOutcome)
        }
        return SelectedLinesCopyWorkflowAtomicReceipt(
            plan: plan,
            commitReceipt: commitReceipt,
            publicationReceipts: publicationReceipts
        )
    }
}

public enum SelectedLinesCopyWorkflow: Sendable {
    /// Availability of `alias` for the snapshot selection, via the shared workflow.
    public static func commandState(
        for alias: SelectedLinesCopyWorkflowAlias,
        in snapshot: MultiDifferenceMergeWorkflowSnapshot,
        limits: MultiDifferenceMergeWorkflowLimits = .default
    ) throws -> MultiDifferenceMergeWorkflowCommandState {
        do {
            return try MultiDifferenceMergeWorkflow.commandState(
                for: alias.workflowIntent,
                in: snapshot,
                limits: limits
            )
        } catch let error as MultiDifferenceMergeWorkflowError {
            throw SelectedLinesCopyWorkflowError.workflow(error)
        } catch is CancellationError {
            throw SelectedLinesCopyWorkflowError.cancelled
        }
    }

    /// Expands `selectedAlignedRows` to maximal significant groups, validating
    /// comparison identity/revision and stable row identities.
    public static func expansion(
        in snapshot: MultiDifferenceMergeWorkflowSnapshot,
        selectedAlignedRows: Range<Int>,
        selectedRowIDs: [DiffRow.ID]? = nil,
        expectedComparison: MultiDifferenceMergeWorkflowComparisonReference? = nil,
        limits: SelectedLinesCopyWorkflowLimits = .default
    ) throws -> SelectedLinesCopyWorkflowExpansion {
        do {
            var work = try WorkBudget(limits: limits)
            try validate(limits)
            try work.checkCancellation()
            let rows = snapshot.comparisonRows
            guard rows.count <= limits.maximumComparisonRows else {
                throw SelectedLinesCopyWorkflowError.tooManyComparisonRows(
                    maximum: limits.maximumComparisonRows
                )
            }
            if let expectedComparison {
                guard snapshot.comparisonReference.identity == expectedComparison.identity else {
                    throw SelectedLinesCopyWorkflowError.staleComparisonIdentity
                }
                guard snapshot.comparisonReference.source == expectedComparison.source else {
                    throw SelectedLinesCopyWorkflowError.staleComparisonIdentity
                }
                guard snapshot.comparisonReference.revision == expectedComparison.revision else {
                    throw SelectedLinesCopyWorkflowError.staleComparisonRevision(
                        expected: expectedComparison.revision,
                        actual: snapshot.comparisonReference.revision
                    )
                }
            }
            guard !selectedAlignedRows.isEmpty else {
                throw SelectedLinesCopyWorkflowError.emptySelection
            }
            guard selectedAlignedRows.lowerBound >= 0,
                selectedAlignedRows.upperBound <= rows.count
            else {
                throw SelectedLinesCopyWorkflowError.selectionOutOfBounds(
                    requested: selectedAlignedRows,
                    rowCount: rows.count
                )
            }
            guard selectedAlignedRows.count <= limits.maximumSelectedLines else {
                throw SelectedLinesCopyWorkflowError.tooManySelectedLines(
                    maximum: limits.maximumSelectedLines
                )
            }
            if let selectedRowIDs {
                try work.consume(UInt64(selectedRowIDs.count))
                let currentIDs = try rowIDs(in: rows, range: selectedAlignedRows, work: &work)
                guard currentIDs == selectedRowIDs else {
                    throw SelectedLinesCopyWorkflowError.rowIdentityMismatch
                }
            }
            let groups = try expandedGroups(
                in: rows,
                selection: selectedAlignedRows,
                limits: limits,
                work: &work
            )
            guard !groups.isEmpty else {
                throw SelectedLinesCopyWorkflowError.noSignificantDifferences
            }
            try work.finish()
            return SelectedLinesCopyWorkflowExpansion(
                selectedAlignedRows: selectedAlignedRows,
                expandedGroups: groups,
                expectedComparison: snapshot.comparisonReference
            )
        } catch is CancellationError {
            throw SelectedLinesCopyWorkflowError.cancelled
        } catch let error as SelectedLinesCopyWorkflowError {
            throw error
        } catch {
            throw error
        }
    }

    /// Plans one selected-lines copy. The snapshot selection must already cover
    /// exactly `selectedAlignedRows` with matching stable identities: this keeps
    /// the delegated `MultiDifferenceMergeWorkflow` owner CAS exact instead of
    /// forging a new selection identity. Throws `selectionChanged` otherwise.
    public static func plan(
        for alias: SelectedLinesCopyWorkflowAlias,
        in snapshot: MultiDifferenceMergeWorkflowSnapshot,
        selectedAlignedRows: Range<Int>,
        selectedRowIDs: [DiffRow.ID]? = nil,
        expectedComparison: MultiDifferenceMergeWorkflowComparisonReference? = nil,
        limits: SelectedLinesCopyWorkflowLimits = .default,
        workflowLimits: MultiDifferenceMergeWorkflowLimits = .default
    ) throws -> SelectedLinesCopyWorkflowPlan {
        let expansion = try expansion(
            in: snapshot,
            selectedAlignedRows: selectedAlignedRows,
            selectedRowIDs: selectedRowIDs,
            expectedComparison: expectedComparison,
            limits: limits
        )
        let liveSelectedIDs = snapshot.comparisonRows[selectedAlignedRows].map(\.id)
        let liveRunIDs = expansion.expandedGroups.map({ snapshot.comparisonRows[$0].map(\.id) })
        guard snapshot.selection.rowRange == selectedAlignedRows,
            snapshot.selection.differenceRuns.map(\.rowRange) == expansion.expandedGroups,
            snapshot.selection.selectedRowIDs == liveSelectedIDs,
            snapshot.selection.differenceRuns.map(\.rowIDs) == liveRunIDs
        else {
            throw SelectedLinesCopyWorkflowError.selectionChanged
        }
        do {
            let underlying = try MultiDifferenceMergeWorkflow.plan(
                intent: alias.workflowIntent,
                in: snapshot,
                limits: workflowLimits
            )
            return SelectedLinesCopyWorkflowPlan(
                alias: alias,
                expansion: expansion,
                underlying: underlying,
                limits: limits
            )
        } catch let error as MultiDifferenceMergeWorkflowError {
            throw SelectedLinesCopyWorkflowError.workflow(error)
        } catch is CancellationError {
            throw SelectedLinesCopyWorkflowError.cancelled
        }
    }

    private static func expandedGroups(
        in rows: [DiffRow],
        selection: Range<Int>,
        limits: SelectedLinesCopyWorkflowLimits,
        work: inout WorkBudget
    ) throws -> [Range<Int>] {
        var groups: [Range<Int>] = []
        var index = selection.lowerBound
        while index < selection.upperBound {
            try work.consume()
            guard rows[index].kind != .unchanged else {
                index += 1
                continue
            }
            var lowerBound = index
            while lowerBound > 0, rows[lowerBound - 1].kind != .unchanged {
                try work.consume()
                lowerBound -= 1
            }
            var upperBound = index + 1
            while upperBound < rows.count, rows[upperBound].kind != .unchanged {
                try work.consume()
                upperBound += 1
            }
            guard groups.count < limits.maximumDifferenceGroups else {
                throw SelectedLinesCopyWorkflowError.tooManyDifferenceGroups(
                    maximum: limits.maximumDifferenceGroups
                )
            }
            groups.append(lowerBound..<upperBound)
            index = upperBound
        }
        return groups
    }

    private static func rowIDs(
        in rows: [DiffRow],
        range: Range<Int>,
        work: inout WorkBudget
    ) throws -> [DiffRow.ID] {
        var ids: [DiffRow.ID] = []
        ids.reserveCapacity(range.count)
        for index in range {
            try work.consume()
            ids.append(rows[index].id)
        }
        return ids
    }

    private static func validate(_ limits: SelectedLinesCopyWorkflowLimits) throws {
        guard (0...SelectedLinesCopyWorkflowLimits.hardMaximumSelectedLines).contains(
            limits.maximumSelectedLines
        ) else {
            throw SelectedLinesCopyWorkflowError.invalidLimit("selectedLines")
        }
        guard (0...SelectedLinesCopyWorkflowLimits.hardMaximumDifferenceGroups).contains(
            limits.maximumDifferenceGroups
        ) else {
            throw SelectedLinesCopyWorkflowError.invalidLimit("differenceGroups")
        }
        guard (0...SelectedLinesCopyWorkflowLimits.hardMaximumComparisonRows).contains(
            limits.maximumComparisonRows
        ) else {
            throw SelectedLinesCopyWorkflowError.invalidLimit("comparisonRows")
        }
        guard limits.maximumWorkUnits <= SelectedLinesCopyWorkflowLimits.hardMaximumWorkUnits else {
            throw SelectedLinesCopyWorkflowError.invalidLimit("workUnits")
        }
        guard (1...SelectedLinesCopyWorkflowLimits.hardMaximumCancellationCheckInterval).contains(
            limits.cancellationCheckInterval
        ) else {
            throw SelectedLinesCopyWorkflowError.invalidLimit("cancellationCheckInterval")
        }
    }

    private struct WorkBudget {
        let maximum: UInt64
        let cancellationCheckInterval: UInt64
        private(set) var consumed: UInt64 = 0
        private var unitsSinceCancellationCheck: UInt64 = 0

        init(limits: SelectedLinesCopyWorkflowLimits) throws {
            try SelectedLinesCopyWorkflow.validate(limits)
            maximum = limits.maximumWorkUnits
            cancellationCheckInterval = limits.cancellationCheckInterval
            try Task<Never, Never>.checkCancellation()
        }

        mutating func consume(_ amount: UInt64 = 1) throws {
            guard amount <= maximum - consumed else {
                throw SelectedLinesCopyWorkflowError.workLimitExceeded(maximumUnits: maximum)
            }
            consumed += amount
            let unitsUntilCheck = cancellationCheckInterval - unitsSinceCancellationCheck
            if amount >= unitsUntilCheck {
                try Task<Never, Never>.checkCancellation()
                unitsSinceCancellationCheck = (amount - unitsUntilCheck) % cancellationCheckInterval
            } else {
                unitsSinceCancellationCheck += amount
            }
        }

        mutating func checkCancellation() throws {
            try Task<Never, Never>.checkCancellation()
            unitsSinceCancellationCheck = 0
        }

        mutating func finish() throws {
            try checkCancellation()
        }
    }
}

extension SelectedLinesCopyWorkflowLimits: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public var description: String {
        "SelectedLinesCopyWorkflowLimits(selectedLines: \(maximumSelectedLines), differenceGroups: \(maximumDifferenceGroups))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "maximumSelectedLines": maximumSelectedLines,
                "maximumDifferenceGroups": maximumDifferenceGroups,
                "maximumComparisonRows": maximumComparisonRows,
                "maximumWorkUnits": maximumWorkUnits,
                "cancellationCheckInterval": cancellationCheckInterval
            ],
            displayStyle: .struct
        )
    }
}
