import Foundation

public struct MultiDifferenceSelectionLimits: Equatable, Sendable {
    public static let defaultMaximumRows = 1_048_576
    public static let `default` = MultiDifferenceSelectionLimits()

    public let maximumRows: Int
    public let maximumSelectedRows: Int
    public let maximumDifferenceRows: Int
    public let maximumDifferenceRuns: Int
    public let maximumWork: Int

    public init(
        maximumRows: Int = MultiDifferenceSelectionLimits.defaultMaximumRows,
        maximumSelectedRows: Int = MultiDifferenceSelectionLimits.defaultMaximumRows,
        maximumDifferenceRows: Int = MultiDifferenceSelectionLimits.defaultMaximumRows,
        maximumDifferenceRuns: Int = MultiDifferenceSelectionLimits.defaultMaximumRows,
        maximumWork: Int = MultiDifferenceSelectionLimits.defaultMaximumRows * 2
    ) {
        self.maximumRows = maximumRows
        self.maximumSelectedRows = maximumSelectedRows
        self.maximumDifferenceRows = maximumDifferenceRows
        self.maximumDifferenceRuns = maximumDifferenceRuns
        self.maximumWork = maximumWork
    }
}

public enum MultiDifferenceSelectionSide: Equatable, Sendable {
    case left
    case right
}

public enum MultiDifferenceSelectionError: Error, LocalizedError, Equatable, Sendable {
    case invalidMaximumRows(Int)
    case invalidMaximumSelectedRows(Int)
    case invalidMaximumDifferenceRows(Int)
    case invalidMaximumDifferenceRuns(Int)
    case invalidMaximumWork(Int)
    case tooManyRows(maximumRows: Int)
    case selectionTooLarge(maximumRows: Int)
    case tooManyDifferenceRows(maximumRows: Int)
    case tooManyDifferenceRuns(maximumRuns: Int)
    case workLimitExceeded(maximumWork: Int)
    case invalidRowRange(requested: Range<Int>, rowCount: Int)
    case invalidSourceLine(side: MultiDifferenceSelectionSide, rowIndex: Int, line: Int)
    case sourceLinesNotStrictlyIncreasing(
        side: MultiDifferenceSelectionSide,
        previous: Int,
        next: Int,
        rowIndex: Int
    )
    case invalidRowShape(rowIndex: Int, kind: DiffKind)
    case rowIdentityMismatch
    case staleSelection

    public var errorDescription: String? {
        switch self {
        case .invalidMaximumRows(let value):
            "Maximum row count must not be negative: \(value)."
        case .invalidMaximumSelectedRows(let value):
            "Maximum selected row count must not be negative: \(value)."
        case .invalidMaximumDifferenceRows(let value):
            "Maximum difference row count must not be negative: \(value)."
        case .invalidMaximumDifferenceRuns(let value):
            "Maximum difference run count must not be negative: \(value)."
        case .invalidMaximumWork(let value):
            "Maximum selection work must not be negative: \(value)."
        case .tooManyRows(let maximumRows):
            "Comparison exceeds the \(maximumRows)-row selection limit."
        case .selectionTooLarge(let maximumRows):
            "Selection exceeds the \(maximumRows)-row limit."
        case .tooManyDifferenceRows(let maximumRows):
            "Intersecting differences exceed the \(maximumRows)-row limit."
        case .tooManyDifferenceRuns(let maximumRuns):
            "Selection exceeds the \(maximumRuns)-difference-run limit."
        case .workLimitExceeded(let maximumWork):
            "Difference selection exceeds the \(maximumWork)-unit work limit."
        case .invalidRowRange(let requested, let rowCount):
            "Selected row range \(requested.lowerBound)..<\(requested.upperBound) is outside 0..<\(rowCount) or empty."
        case .invalidSourceLine(let side, let rowIndex, let line):
            "The \(side.description) source line at row \(rowIndex) must be positive: \(line)."
        case .sourceLinesNotStrictlyIncreasing(let side, let previous, let next, let rowIndex):
            "The \(side.description) source line at row \(rowIndex) is not after \(previous): \(next)."
        case .invalidRowShape(let rowIndex, let kind):
            "Diff row \(rowIndex) has source presence inconsistent with its \(kind.description) kind."
        case .rowIdentityMismatch:
            "Selected row identities do not match the requested comparison rows."
        case .staleSelection:
            "Difference selection no longer matches the comparison rows that produced it."
        }
    }
}

public struct MultiDifferenceSelection: Equatable, Sendable {
    public struct DifferenceRun: Identifiable, Equatable, Sendable {
        public struct ID: Equatable, Hashable, Sendable {
            public let firstRowID: DiffRow.ID
            public let lastRowID: DiffRow.ID

            fileprivate init(firstRowID: DiffRow.ID, lastRowID: DiffRow.ID) {
                self.firstRowID = firstRowID
                self.lastRowID = lastRowID
            }
        }

        public let id: ID
        /// Full maximal significant run, which can extend beyond the selected interval.
        public let rowRange: Range<Int>
        /// Portion of `rowRange` directly covered by the selected interval.
        public let selectionIntersection: Range<Int>
        /// Stable row identities in ascending source order.
        public let rowIDs: [DiffRow.ID]
        public let leftSourceRowCount: Int
        public let rightSourceRowCount: Int

        public var hasLeftSourceRows: Bool { leftSourceRowCount > 0 }
        public var hasRightSourceRows: Bool { rightSourceRowCount > 0 }

        fileprivate init(
            rowRange: Range<Int>,
            selectionIntersection: Range<Int>,
            rowIDs: [DiffRow.ID],
            leftSourceRowCount: Int,
            rightSourceRowCount: Int
        ) {
            precondition(!rowIDs.isEmpty)
            id = ID(firstRowID: rowIDs[0], lastRowID: rowIDs[rowIDs.count - 1])
            self.rowRange = rowRange
            self.selectionIntersection = selectionIntersection
            self.rowIDs = rowIDs
            self.leftSourceRowCount = leftSourceRowCount
            self.rightSourceRowCount = rightSourceRowCount
        }

        public func hasSourceRows(for direction: MergeDirection) -> Bool {
            switch direction {
            case .leftToRight:
                hasLeftSourceRows
            case .rightToLeft:
                hasRightSourceRows
            }
        }
    }

    public struct SideState: Equatable, Sendable {
        public let isPresent: Bool
        public let isEditable: Bool

        public init(isPresent: Bool, isEditable: Bool) {
            self.isPresent = isPresent
            self.isEditable = isEditable
        }

        public init(_ state: MergeCommandPolicy.SideState) {
            isPresent = state.isLoaded
            isEditable = state.isEditable
        }
    }

    public enum MergeDisabledReason: Equatable, Sendable {
        case sourceNotPresent(MultiDifferenceSelectionSide)
        case destinationNotPresent(MultiDifferenceSelectionSide)
        case destinationNotEditable(MultiDifferenceSelectionSide)
        case noSignificantDifferences
    }

    public enum MergeAvailability: Equatable, Sendable {
        case enabled
        case disabled(MergeDisabledReason)

        public var isEnabled: Bool { self == .enabled }

        public var disabledReason: MergeDisabledReason? {
            guard case .disabled(let reason) = self else { return nil }
            return reason
        }
    }

    public struct MergeEligibility: Equatable, Sendable {
        public let leftToRight: MergeAvailability
        public let rightToLeft: MergeAvailability

        public init(
            leftToRight: MergeAvailability,
            rightToLeft: MergeAvailability
        ) {
            self.leftToRight = leftToRight
            self.rightToLeft = rightToLeft
        }

        public subscript(direction: MergeDirection) -> MergeAvailability {
            switch direction {
            case .leftToRight:
                leftToRight
            case .rightToLeft:
                rightToLeft
            }
        }
    }

    /// Zero-based, half-open, contiguous row interval supplied by the caller.
    public let rowRange: Range<Int>
    /// Stable identities for every selected row, including unchanged rows.
    public let selectedRowIDs: [DiffRow.ID]
    /// Maximal significant runs intersecting `rowRange`, in source order.
    public let differenceRuns: [DifferenceRun]
    /// Row count of the comparison snapshot used to create this value.
    public let sourceRowCount: Int

    private let selectedRowsSnapshot: [DiffRow]
    private let differenceRowsSnapshots: [[DiffRow]]

    public var selectedRowRange: Range<Int> { rowRange }
    public var runs: [DifferenceRun] { differenceRuns }
    public var hasSignificantDifferences: Bool { !differenceRuns.isEmpty }

    public init(
        rows: [DiffRow],
        rowRange: Range<Int>,
        limits: MultiDifferenceSelectionLimits = .default
    ) throws {
        let result = try Self.build(rows: rows, rowRange: rowRange, limits: limits)
        self.rowRange = rowRange
        selectedRowIDs = result.selectedRowIDs
        differenceRuns = result.differenceRuns
        sourceRowCount = rows.count
        selectedRowsSnapshot = result.selectedRows
        differenceRowsSnapshots = result.differenceRows
    }

    public init(
        rows: [DiffRow],
        selectedRowRange: Range<Int>,
        limits: MultiDifferenceSelectionLimits = .default
    ) throws {
        try self.init(rows: rows, rowRange: selectedRowRange, limits: limits)
    }

    public static func select(
        rows: [DiffRow],
        rowRange: Range<Int>,
        limits: MultiDifferenceSelectionLimits = .default
    ) throws -> MultiDifferenceSelection {
        try MultiDifferenceSelection(rows: rows, rowRange: rowRange, limits: limits)
    }

    /// Resolves an external range only when every supplied stable ID matches that range exactly.
    public static func resolve(
        rows: [DiffRow],
        rowRange: Range<Int>,
        rowIDs: [DiffRow.ID],
        limits: MultiDifferenceSelectionLimits = .default
    ) throws -> MultiDifferenceSelection {
        let selection = try MultiDifferenceSelection(
            rows: rows,
            rowRange: rowRange,
            limits: limits
        )
        guard selection.selectedRowIDs == rowIDs else {
            throw MultiDifferenceSelectionError.rowIdentityMismatch
        }
        return selection
    }

    /// Rechecks stable IDs, row values, run boundaries, and source order against current rows.
    /// Changes outside the comparison's row count or selected/run rows do not invalidate selection.
    public func revalidated(
        in rows: [DiffRow],
        limits: MultiDifferenceSelectionLimits = .default
    ) throws -> MultiDifferenceSelection {
        let current = try MultiDifferenceSelection(
            rows: rows,
            rowRange: rowRange,
            limits: limits
        )
        guard sourceRowCount == current.sourceRowCount,
            selectedRowIDs == current.selectedRowIDs,
            differenceRuns == current.differenceRuns,
            selectedRowsSnapshot == current.selectedRowsSnapshot,
            differenceRowsSnapshots == current.differenceRowsSnapshots
        else {
            throw MultiDifferenceSelectionError.staleSelection
        }
        return current
    }

    public func validate(
        in rows: [DiffRow],
        limits: MultiDifferenceSelectionLimits = .default
    ) throws {
        _ = try revalidated(in: rows, limits: limits)
    }

    /// Row-level source absence still represents a valid deletion. Presence here describes panes,
    /// matching `MergeCommandPolicy.SideState.isLoaded`.
    public func mergeEligibility(left: SideState, right: SideState) -> MergeEligibility {
        MergeEligibility(
            leftToRight: mergeAvailability(
                source: left,
                sourceSide: .left,
                destination: right,
                destinationSide: .right
            ),
            rightToLeft: mergeAvailability(
                source: right,
                sourceSide: .right,
                destination: left,
                destinationSide: .left
            )
        )
    }

    public func mergeEligibility(
        left: MergeCommandPolicy.SideState,
        right: MergeCommandPolicy.SideState
    ) -> MergeEligibility {
        mergeEligibility(left: SideState(left), right: SideState(right))
    }

    public func isMergeEligible(
        direction: MergeDirection,
        left: SideState,
        right: SideState
    ) -> Bool {
        mergeEligibility(left: left, right: right)[direction].isEnabled
    }

    private func mergeAvailability(
        source: SideState,
        sourceSide: MultiDifferenceSelectionSide,
        destination: SideState,
        destinationSide: MultiDifferenceSelectionSide
    ) -> MergeAvailability {
        guard source.isPresent else { return .disabled(.sourceNotPresent(sourceSide)) }
        guard destination.isPresent else {
            return .disabled(.destinationNotPresent(destinationSide))
        }
        guard destination.isEditable else {
            return .disabled(.destinationNotEditable(destinationSide))
        }
        guard hasSignificantDifferences else {
            return .disabled(.noSignificantDifferences)
        }
        return .enabled
    }

    private struct BuildResult {
        var selectedRowIDs: [DiffRow.ID]
        var selectedRows: [DiffRow]
        var differenceRuns: [DifferenceRun]
        var differenceRows: [[DiffRow]]
    }

    private static func build(
        rows: [DiffRow],
        rowRange: Range<Int>,
        limits: MultiDifferenceSelectionLimits
    ) throws -> BuildResult {
        try Task.checkCancellation()
        try validate(limits)
        guard rows.count <= limits.maximumRows else {
            throw MultiDifferenceSelectionError.tooManyRows(maximumRows: limits.maximumRows)
        }
        guard rowRange.lowerBound >= 0,
            rowRange.lowerBound < rowRange.upperBound,
            rowRange.upperBound <= rows.count
        else {
            throw MultiDifferenceSelectionError.invalidRowRange(
                requested: rowRange,
                rowCount: rows.count
            )
        }
        let selectedRowCount = rowRange.upperBound - rowRange.lowerBound
        guard selectedRowCount <= limits.maximumSelectedRows else {
            throw MultiDifferenceSelectionError.selectionTooLarge(
                maximumRows: limits.maximumSelectedRows
            )
        }

        var result = BuildResult(
            selectedRowIDs: [],
            selectedRows: [],
            differenceRuns: [],
            differenceRows: []
        )
        result.selectedRowIDs.reserveCapacity(selectedRowCount)
        result.selectedRows.reserveCapacity(selectedRowCount)
        result.differenceRuns.reserveCapacity(min(selectedRowCount, limits.maximumDifferenceRuns))
        result.differenceRows.reserveCapacity(min(selectedRowCount, limits.maximumDifferenceRuns))

        var budget = WorkBudget(maximumWork: limits.maximumWork)
        var previousLeftLine: Int?
        var previousRightLine: Int?
        var runStart: Int?
        var selectedDifferenceRowCount = 0

        for (rowIndex, row) in rows.enumerated() {
            try budget.consume()
            try validate(
                row,
                at: rowIndex,
                previousLeftLine: &previousLeftLine,
                previousRightLine: &previousRightLine
            )
            if rowRange.contains(rowIndex) {
                result.selectedRowIDs.append(row.id)
                result.selectedRows.append(row)
            }

            if row.kind != .unchanged {
                if runStart == nil { runStart = rowIndex }
            } else if let start = runStart {
                try appendRun(
                    start..<rowIndex,
                    rows: rows,
                    selection: rowRange,
                    limits: limits,
                    selectedDifferenceRowCount: &selectedDifferenceRowCount,
                    budget: &budget,
                    result: &result
                )
                runStart = nil
            }
        }
        if let runStart {
            try appendRun(
                runStart..<rows.count,
                rows: rows,
                selection: rowRange,
                limits: limits,
                selectedDifferenceRowCount: &selectedDifferenceRowCount,
                budget: &budget,
                result: &result
            )
        }
        try Task.checkCancellation()
        return result
    }

    private static func appendRun(
        _ runRange: Range<Int>,
        rows: [DiffRow],
        selection: Range<Int>,
        limits: MultiDifferenceSelectionLimits,
        selectedDifferenceRowCount: inout Int,
        budget: inout WorkBudget,
        result: inout BuildResult
    ) throws {
        let intersection = max(runRange.lowerBound, selection.lowerBound)
            ..< min(runRange.upperBound, selection.upperBound)
        guard !intersection.isEmpty else { return }
        guard result.differenceRuns.count < limits.maximumDifferenceRuns else {
            throw MultiDifferenceSelectionError.tooManyDifferenceRuns(
                maximumRuns: limits.maximumDifferenceRuns
            )
        }

        let runCount = runRange.upperBound - runRange.lowerBound
        guard runCount <= limits.maximumDifferenceRows - selectedDifferenceRowCount else {
            throw MultiDifferenceSelectionError.tooManyDifferenceRows(
                maximumRows: limits.maximumDifferenceRows
            )
        }
        selectedDifferenceRowCount += runCount

        var rowIDs: [DiffRow.ID] = []
        var runRows: [DiffRow] = []
        rowIDs.reserveCapacity(runCount)
        runRows.reserveCapacity(runCount)
        var leftSourceRowCount = 0
        var rightSourceRowCount = 0
        for rowIndex in runRange {
            try budget.consume()
            let row = rows[rowIndex]
            rowIDs.append(row.id)
            runRows.append(row)
            if row.id.leftNumber != nil { leftSourceRowCount += 1 }
            if row.id.rightNumber != nil { rightSourceRowCount += 1 }
        }
        result.differenceRuns.append(
            DifferenceRun(
                rowRange: runRange,
                selectionIntersection: intersection,
                rowIDs: rowIDs,
                leftSourceRowCount: leftSourceRowCount,
                rightSourceRowCount: rightSourceRowCount
            )
        )
        result.differenceRows.append(runRows)
    }

    private static func validate(_ limits: MultiDifferenceSelectionLimits) throws {
        guard limits.maximumRows >= 0 else {
            throw MultiDifferenceSelectionError.invalidMaximumRows(limits.maximumRows)
        }
        guard limits.maximumSelectedRows >= 0 else {
            throw MultiDifferenceSelectionError.invalidMaximumSelectedRows(
                limits.maximumSelectedRows
            )
        }
        guard limits.maximumDifferenceRows >= 0 else {
            throw MultiDifferenceSelectionError.invalidMaximumDifferenceRows(
                limits.maximumDifferenceRows
            )
        }
        guard limits.maximumDifferenceRuns >= 0 else {
            throw MultiDifferenceSelectionError.invalidMaximumDifferenceRuns(
                limits.maximumDifferenceRuns
            )
        }
        guard limits.maximumWork >= 0 else {
            throw MultiDifferenceSelectionError.invalidMaximumWork(limits.maximumWork)
        }
    }

    private static func validate(
        _ row: DiffRow,
        at rowIndex: Int,
        previousLeftLine: inout Int?,
        previousRightLine: inout Int?
    ) throws {
        let id = row.id
        try validate(
            line: id.leftNumber,
            side: .left,
            at: rowIndex,
            previous: &previousLeftLine
        )
        try validate(
            line: id.rightNumber,
            side: .right,
            at: rowIndex,
            previous: &previousRightLine
        )

        let hasLeft = id.leftNumber != nil
        let hasRight = id.rightNumber != nil
        let hasValidShape = switch row.kind {
        case .unchanged:
            hasLeft || hasRight
        case .modified:
            hasLeft && hasRight
        case .removed:
            hasLeft && !hasRight
        case .added:
            !hasLeft && hasRight
        }
        guard hasValidShape else {
            throw MultiDifferenceSelectionError.invalidRowShape(
                rowIndex: rowIndex,
                kind: row.kind
            )
        }
    }

    private static func validate(
        line: Int?,
        side: MultiDifferenceSelectionSide,
        at rowIndex: Int,
        previous: inout Int?
    ) throws {
        guard let line else { return }
        guard line > 0 else {
            throw MultiDifferenceSelectionError.invalidSourceLine(
                side: side,
                rowIndex: rowIndex,
                line: line
            )
        }
        if let previous, line <= previous {
            throw MultiDifferenceSelectionError.sourceLinesNotStrictlyIncreasing(
                side: side,
                previous: previous,
                next: line,
                rowIndex: rowIndex
            )
        }
        previous = line
    }
}

private struct WorkBudget {
    let maximumWork: Int
    private(set) var completedWork = 0

    mutating func consume() throws {
        guard completedWork < maximumWork else {
            throw MultiDifferenceSelectionError.workLimitExceeded(maximumWork: maximumWork)
        }
        completedWork += 1
        if completedWork.isMultiple(of: 1_024) {
            try Task.checkCancellation()
        }
    }
}

private extension MultiDifferenceSelectionSide {
    var description: String {
        switch self {
        case .left: "left"
        case .right: "right"
        }
    }
}

private extension DiffKind {
    var description: String {
        switch self {
        case .unchanged: "unchanged"
        case .modified: "modified"
        case .removed: "removed"
        case .added: "added"
        }
    }
}
