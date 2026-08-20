import Foundation

public struct MultiDifferenceMergeState: Equatable, Sendable {
    public let source: ComparisonSnapshot
    public let comparisonRows: [DiffRow]
    public let left: MergeCommandPolicy.SideState
    public let right: MergeCommandPolicy.SideState
    public let comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle

    public init(
        source: ComparisonSnapshot,
        comparisonRows: [DiffRow],
        left: MergeCommandPolicy.SideState,
        right: MergeCommandPolicy.SideState,
        comparisonLifecycle: MergeCommandPolicy.ComparisonLifecycle = .currentSuccess
    ) {
        self.source = source
        self.comparisonRows = comparisonRows
        self.left = left
        self.right = right
        self.comparisonLifecycle = comparisonLifecycle
    }
}

public struct MultiDifferenceMergeOptions: Equatable, Sendable {
    public static let defaultMaximumComparedRows = 1_048_576
    public static let defaultMaximumChangeGroups = 65_536
    public static let defaultMaximumMergeOperations = 65_536
    public static let defaultMaximumOutputBytes = 256 * 1_024 * 1_024
    public static let defaultMaximumWork = 2 * 1_024 * 1_024 * 1_024

    public let lineDiff: LineDiffOptions
    public let maximumComparedRows: Int
    public let maximumChangeGroups: Int
    public let maximumMergeOperations: Int
    /// Maximum UTF-8 size of the destination, including every intermediate value.
    public let maximumOutputBytes: Int
    /// Aggregate bytes and rows submitted to comparison and merge primitives.
    public let maximumWork: Int

    public init(
        lineDiff: LineDiffOptions = LineDiffOptions(),
        maximumComparedRows: Int = MultiDifferenceMergeOptions.defaultMaximumComparedRows,
        maximumChangeGroups: Int = MultiDifferenceMergeOptions.defaultMaximumChangeGroups,
        maximumMergeOperations: Int = MultiDifferenceMergeOptions.defaultMaximumMergeOperations,
        maximumOutputBytes: Int = MultiDifferenceMergeOptions.defaultMaximumOutputBytes,
        maximumWork: Int = MultiDifferenceMergeOptions.defaultMaximumWork
    ) {
        precondition(maximumComparedRows >= 0, "Maximum compared row count must not be negative")
        precondition(maximumChangeGroups >= 0, "Maximum change group count must not be negative")
        precondition(maximumMergeOperations >= 0, "Maximum merge operation count must not be negative")
        precondition(maximumOutputBytes >= 0, "Maximum output size must not be negative")
        precondition(maximumWork >= 0, "Maximum work must not be negative")
        self.lineDiff = lineDiff
        self.maximumComparedRows = maximumComparedRows
        self.maximumChangeGroups = maximumChangeGroups
        self.maximumMergeOperations = maximumMergeOperations
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumWork = maximumWork
    }
}

public enum MultiDifferenceMergeNoOpReason: Equatable, Sendable {
    case commandDisabled(MergeCommandPolicy.DisabledReason)
    case selectionOutOfBounds(selection: Range<Int>, rowCount: Int)
    case comparisonDoesNotMatchSource
    case mergePrimitiveRejected(rowID: DiffRow.ID)
    case unchangedDestination
}

public struct MultiDifferenceMergeChangeGroup: Equatable, Sendable {
    /// Zero-based, half-open range in the aligned comparison.
    public let alignedRowRange: Range<Int>
    /// Zero-based source line range in the input snapshot.
    public let sourceLineRange: Range<Int>
    /// Zero-based destination line range in the input snapshot.
    public let destinationLineRange: Range<Int>
    /// Zero-based destination line range occupied by the source group after the merge.
    public let resultDestinationLineRange: Range<Int>

    public init(
        alignedRowRange: Range<Int>,
        sourceLineRange: Range<Int>,
        destinationLineRange: Range<Int>,
        resultDestinationLineRange: Range<Int>
    ) {
        self.alignedRowRange = alignedRowRange
        self.sourceLineRange = sourceLineRange
        self.destinationLineRange = destinationLineRange
        self.resultDestinationLineRange = resultDestinationLineRange
    }
}

public struct MultiDifferenceMergeResult: Equatable, Sendable {
    public let snapshot: ComparisonSnapshot
    /// Maximal significant groups in ascending aligned-row order.
    public let changedGroups: [MultiDifferenceMergeChangeGroup]

    public init(
        snapshot: ComparisonSnapshot,
        changedGroups: [MultiDifferenceMergeChangeGroup]
    ) {
        self.snapshot = snapshot
        self.changedGroups = changedGroups
    }
}

public enum MultiDifferenceMergeOutcome: Equatable, Sendable {
    case merged(MultiDifferenceMergeResult)
    case noChange(MultiDifferenceMergeNoOpReason)
}

public enum MultiDifferenceMergeError: Error, LocalizedError, Equatable, Sendable {
    case tooManyComparedRows(maximumRows: Int)
    case tooManyChangeGroups(maximumGroups: Int)
    case tooManyMergeOperations(maximumOperations: Int)
    case outputTooLarge(maximumBytes: Int)
    case workLimitExceeded(maximumWork: Int)

    public var errorDescription: String? {
        switch self {
        case .tooManyComparedRows(let maximumRows):
            "Multi-difference merge exceeds the \(maximumRows)-row comparison limit."
        case .tooManyChangeGroups(let maximumGroups):
            "Multi-difference merge exceeds the \(maximumGroups)-group limit."
        case .tooManyMergeOperations(let maximumOperations):
            "Multi-difference merge exceeds the \(maximumOperations)-operation limit."
        case .outputTooLarge(let maximumBytes):
            "Multi-difference merge output exceeds the \(maximumBytes)-byte limit."
        case .workLimitExceeded(let maximumWork):
            "Multi-difference merge exceeds the \(maximumWork)-unit work limit."
        }
    }
}

public enum MultiDifferenceMerge: Sendable {
    public static func apply(
        state: MultiDifferenceMergeState,
        selectedAlignedRows selection: Range<Int>,
        direction: MergeDirection,
        options: MultiDifferenceMergeOptions = MultiDifferenceMergeOptions()
    ) throws -> MultiDifferenceMergeOutcome {
        try Task.checkCancellation()

        if let reason = disabledReason(
            state: state,
            direction: direction,
            hasSelection: true,
            hasSignificantDifferences: true
        ) {
            return .noChange(.commandDisabled(reason))
        }
        guard selection.lowerBound >= 0, selection.upperBound <= state.comparisonRows.count else {
            return .noChange(
                .selectionOutOfBounds(
                    selection: selection,
                    rowCount: state.comparisonRows.count
                ))
        }
        guard !selection.isEmpty else {
            return .noChange(.commandDisabled(.noSelection))
        }

        let leftByteCount = state.source.left.utf8.count
        let rightByteCount = state.source.right.utf8.count
        var work = WorkBudget(maximum: options.maximumWork)
        try work.consume(leftByteCount)
        try work.consume(rightByteCount)

        let rows = try LineDiff.compare(
            left: state.source.left,
            right: state.source.right,
            options: options.lineDiff
        )
        try Task.checkCancellation()
        guard rows.count <= options.maximumComparedRows else {
            throw MultiDifferenceMergeError.tooManyComparedRows(
                maximumRows: options.maximumComparedRows
            )
        }
        try work.consume(rows.count)
        try work.consume(leftByteCount)
        try work.consume(rightByteCount)
        guard try rowsMatch(state.comparisonRows, rows, work: &work) else {
            return .noChange(.comparisonDoesNotMatchSource)
        }

        let alignedRanges = try significantGroups(
            in: rows,
            intersecting: selection,
            maximumGroups: options.maximumChangeGroups,
            maximumOperations: options.maximumMergeOperations
        )
        guard !alignedRanges.isEmpty else {
            return .noChange(.commandDisabled(.noSignificantDifferences))
        }

        let prefixes = try linePrefixes(rows)
        let changedGroups = changeGroups(
            alignedRanges: alignedRanges,
            prefixes: prefixes,
            direction: direction
        )

        let sourceByteCount = direction == .leftToRight ? leftByteCount : rightByteCount
        var destinationByteCount = direction == .leftToRight ? rightByteCount : leftByteCount
        guard destinationByteCount <= options.maximumOutputBytes else {
            throw MultiDifferenceMergeError.outputTooLarge(
                maximumBytes: options.maximumOutputBytes
            )
        }

        var current = state.source
        for alignedRange in alignedRanges.reversed() {
            for rowIndex in alignedRange.reversed() {
                try Task.checkCancellation()
                let row = rows[rowIndex]
                try validatePotentialOutput(
                    row: row,
                    direction: direction,
                    currentDestinationBytes: destinationByteCount,
                    maximumOutputBytes: options.maximumOutputBytes
                )
                try work.consume(sourceByteCount)
                try work.consume(destinationByteCount)
                try work.consume(rows.count)

                guard
                    let merged = try LineMerge.apply(
                        rowID: row.id,
                        direction: direction,
                        left: current.left,
                        right: current.right,
                        options: options.lineDiff
                    )
                else {
                    return .noChange(.mergePrimitiveRejected(rowID: row.id))
                }
                try Task.checkCancellation()
                current = ComparisonSnapshot(left: merged.left, right: merged.right)
                destinationByteCount =
                    direction == .leftToRight
                    ? current.right.utf8.count
                    : current.left.utf8.count
                guard destinationByteCount <= options.maximumOutputBytes else {
                    throw MultiDifferenceMergeError.outputTooLarge(
                        maximumBytes: options.maximumOutputBytes
                    )
                }
            }
        }

        let destinationChanged =
            direction == .leftToRight
            ? !current.right.utf8.elementsEqual(state.source.right.utf8)
            : !current.left.utf8.elementsEqual(state.source.left.utf8)
        guard destinationChanged else { return .noChange(.unchangedDestination) }
        return .merged(
            MultiDifferenceMergeResult(
                snapshot: current,
                changedGroups: changedGroups
            ))
    }

    private struct LinePrefixes {
        let left: [Int]
        let right: [Int]
    }

    private struct WorkBudget {
        let maximum: Int
        var consumed = 0

        mutating func consume(_ amount: Int) throws {
            guard amount >= 0, amount <= maximum - consumed else {
                throw MultiDifferenceMergeError.workLimitExceeded(maximumWork: maximum)
            }
            consumed += amount
        }
    }

    private static func disabledReason(
        state: MultiDifferenceMergeState,
        direction: MergeDirection,
        hasSelection: Bool,
        hasSignificantDifferences: Bool
    ) -> MergeCommandPolicy.DisabledReason? {
        let policyState = MergeCommandPolicy.State(
            left: state.left,
            right: state.right,
            comparisonLifecycle: state.comparisonLifecycle,
            hasSelection: hasSelection,
            hasSignificantDifferences: hasSignificantDifferences
        )
        let command: MergeCommandPolicy.Command =
            direction == .leftToRight
            ? .leftToRight
            : .rightToLeft
        return MergeCommandPolicy.evaluate(policyState)[command].disabledReason
    }

    private static func rowsMatch(
        _ supplied: [DiffRow],
        _ current: [DiffRow],
        work: inout WorkBudget
    ) throws -> Bool {
        guard supplied.count == current.count else { return false }
        for index in supplied.indices {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            try work.consume(1)
            let suppliedRow = supplied[index]
            let currentRow = current[index]
            guard suppliedRow.kind == currentRow.kind,
                suppliedRow.hasEqualSourceRecords == currentRow.hasEqualSourceRecords,
                try linesMatch(suppliedRow.left, currentRow.left, work: &work),
                try linesMatch(suppliedRow.right, currentRow.right, work: &work)
            else {
                return false
            }
        }
        return true
    }

    private static func linesMatch(
        _ supplied: DiffLine?,
        _ current: DiffLine?,
        work: inout WorkBudget
    ) throws -> Bool {
        guard supplied?.number == current?.number else { return false }
        switch (supplied, current) {
        case (nil, nil):
            return true
        case (.some(let supplied), .some(let current)):
            return try stringsMatch(supplied.text, current.text, work: &work)
        default:
            return false
        }
    }

    private static func stringsMatch(
        _ left: String,
        _ right: String,
        work: inout WorkBudget
    ) throws -> Bool {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        var compared = 0
        while true {
            if compared > 0, compared.isMultiple(of: 64 * 1_024) {
                try Task.checkCancellation()
                try work.consume(64 * 1_024)
            }
            let leftByte = leftIterator.next()
            let rightByte = rightIterator.next()
            guard leftByte == rightByte else { return false }
            guard leftByte != nil else {
                try work.consume(compared % (64 * 1_024))
                return true
            }
            compared += 1
        }
    }

    private static func significantGroups(
        in rows: [DiffRow],
        intersecting selection: Range<Int>,
        maximumGroups: Int,
        maximumOperations: Int
    ) throws -> [Range<Int>] {
        var groups: [Range<Int>] = []
        groups.reserveCapacity(min(maximumGroups, 64))
        var operationCount = 0
        var index = selection.lowerBound
        while index < selection.upperBound {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            guard rows[index].kind != .unchanged else {
                index += 1
                continue
            }

            var lowerBound = index
            while lowerBound > 0, rows[lowerBound - 1].kind != .unchanged {
                lowerBound -= 1
                if lowerBound.isMultiple(of: 1_024) { try Task.checkCancellation() }
            }
            var upperBound = index + 1
            while upperBound < rows.count, rows[upperBound].kind != .unchanged {
                upperBound += 1
                if upperBound.isMultiple(of: 1_024) { try Task.checkCancellation() }
            }
            guard groups.count < maximumGroups else {
                throw MultiDifferenceMergeError.tooManyChangeGroups(
                    maximumGroups: maximumGroups
                )
            }
            let operationIncrease = upperBound - lowerBound
            guard operationIncrease <= maximumOperations - operationCount else {
                throw MultiDifferenceMergeError.tooManyMergeOperations(
                    maximumOperations: maximumOperations
                )
            }
            groups.append(lowerBound..<upperBound)
            operationCount += operationIncrease
            index = upperBound
        }
        return groups
    }

    private static func linePrefixes(_ rows: [DiffRow]) throws -> LinePrefixes {
        var left = Array(repeating: 0, count: rows.count + 1)
        var right = Array(repeating: 0, count: rows.count + 1)
        for index in rows.indices {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            left[index + 1] = left[index] + (rows[index].left == nil ? 0 : 1)
            right[index + 1] = right[index] + (rows[index].right == nil ? 0 : 1)
        }
        return LinePrefixes(left: left, right: right)
    }

    private static func changeGroups(
        alignedRanges: [Range<Int>],
        prefixes: LinePrefixes,
        direction: MergeDirection
    ) -> [MultiDifferenceMergeChangeGroup] {
        var result: [MultiDifferenceMergeChangeGroup] = []
        result.reserveCapacity(alignedRanges.count)
        var precedingDestinationDelta = 0
        for alignedRange in alignedRanges {
            let leftRange = prefixes.left[alignedRange.lowerBound]..<prefixes.left[alignedRange.upperBound]
            let rightRange = prefixes.right[alignedRange.lowerBound]..<prefixes.right[alignedRange.upperBound]
            let sourceRange = direction == .leftToRight ? leftRange : rightRange
            let destinationRange = direction == .leftToRight ? rightRange : leftRange
            let resultLowerBound = destinationRange.lowerBound + precedingDestinationDelta
            let resultDestinationRange = resultLowerBound..<(resultLowerBound + sourceRange.count)
            result.append(
                MultiDifferenceMergeChangeGroup(
                    alignedRowRange: alignedRange,
                    sourceLineRange: sourceRange,
                    destinationLineRange: destinationRange,
                    resultDestinationLineRange: resultDestinationRange
                ))
            precedingDestinationDelta += sourceRange.count - destinationRange.count
        }
        return result
    }

    private static func validatePotentialOutput(
        row: DiffRow,
        direction: MergeDirection,
        currentDestinationBytes: Int,
        maximumOutputBytes: Int
    ) throws {
        let sourceIsLeft = direction == .leftToRight
        let sourceLine = sourceIsLeft ? row.left : row.right
        let destinationLine = sourceIsLeft ? row.right : row.left
        guard let sourceLine else { return }
        let sourceBytes =
            row.sourceTextUTF8Count(onLeft: sourceIsLeft)
            ?? sourceLine.text.utf8.count
        let destinationBytes = destinationLine.map { $0.text.utf8.count } ?? 0
        let terminatorAllowance = 2
        let possibleIncrease = max(0, sourceBytes + terminatorAllowance - destinationBytes)
        guard possibleIncrease <= maximumOutputBytes - currentDestinationBytes else {
            throw MultiDifferenceMergeError.outputTooLarge(maximumBytes: maximumOutputBytes)
        }
    }
}
