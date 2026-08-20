import Foundation

public enum AutomaticMergeSide: Equatable, Sendable {
    case left
    case right
}

public struct AutomaticMergeEditability: Equatable, Sendable {
    public let left: Bool
    public let right: Bool

    public init(left: Bool, right: Bool) {
        self.left = left
        self.right = right
    }

    public subscript(side: AutomaticMergeSide) -> Bool {
        switch side {
        case .left:
            left
        case .right:
            right
        }
    }
}

public struct AutomaticMergeLimits: Equatable, Sendable {
    public let maximumRows: Int
    public let maximumRuns: Int

    public init(
        maximumRows: Int = 1_048_576,
        maximumRuns: Int = 1_048_576
    ) {
        self.maximumRows = maximumRows
        self.maximumRuns = maximumRuns
    }
}

public enum AutomaticMergeLimit: Equatable, Sendable {
    case rows
    case runs
}

public enum AutomaticMergeError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimit(AutomaticMergeLimit, value: Int)
    case tooManyRows(maximum: Int)
    case tooManyRuns(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(.rows, let value):
            "Automatic merge maximum row count must not be negative: \(value)."
        case .invalidLimit(.runs, let value):
            "Automatic merge maximum run count must not be negative: \(value)."
        case .tooManyRows(let maximum):
            "Automatic merge input exceeds the \(maximum)-row limit."
        case .tooManyRuns(let maximum):
            "Automatic merge input exceeds the \(maximum)-run limit."
        }
    }
}

public enum AutomaticMergeRowClassification: Equatable, Sendable {
    case insignificant
    case leftOnly
    case rightOnly
    case modifiedPair
    case inconsistent
}

public enum AutomaticMergeRunClassification: Equatable, Sendable {
    case leftOnly
    case rightOnly
    case modifiedPair
    case mixedDirections
    case inconsistent
}

public struct AutomaticMergeRun: Equatable, Sendable {
    /// Zero-based half-open range in the supplied aligned diff rows.
    public let rowRange: Range<Int>
    public let classification: AutomaticMergeRunClassification

    public init(
        rowRange: Range<Int>,
        classification: AutomaticMergeRunClassification
    ) {
        self.rowRange = rowRange
        self.classification = classification
    }
}

public struct AutomaticMergeOperation: Equatable, Sendable {
    public let rowRange: Range<Int>
    public let direction: MergeDirection

    public init(rowRange: Range<Int>, direction: MergeDirection) {
        self.rowRange = rowRange
        self.direction = direction
    }

    public var destination: AutomaticMergeSide {
        switch direction {
        case .leftToRight:
            .right
        case .rightToLeft:
            .left
        }
    }
}

public enum AutomaticMergeUnresolvedReason: Equatable, Sendable {
    /// At least one row contains content on both sides, so neither version is authoritative.
    case modifiedPair
    /// A contiguous change contains both left-only and right-only rows.
    case mixedDirections
    /// A significant row's kind does not match its populated sides.
    case inconsistentRows
}

public struct AutomaticMergeUnresolvedConflict: Equatable, Sendable {
    public let run: AutomaticMergeRun
    public let reason: AutomaticMergeUnresolvedReason

    public init(run: AutomaticMergeRun, reason: AutomaticMergeUnresolvedReason) {
        self.run = run
        self.reason = reason
    }
}

public struct AutomaticMergeBlockedConflict: Equatable, Sendable {
    public let run: AutomaticMergeRun
    public let direction: MergeDirection
    public let destination: AutomaticMergeSide

    public init(
        run: AutomaticMergeRun,
        direction: MergeDirection,
        destination: AutomaticMergeSide
    ) {
        self.run = run
        self.direction = direction
        self.destination = destination
    }
}

public struct AutomaticMergePlan: Equatable, Sendable {
    public let runs: [AutomaticMergeRun]
    public let operations: [AutomaticMergeOperation]
    public let unresolvedConflicts: [AutomaticMergeUnresolvedConflict]
    public let blockedConflicts: [AutomaticMergeBlockedConflict]

    public var hasConflicts: Bool {
        !unresolvedConflicts.isEmpty || !blockedConflicts.isEmpty
    }

    public init(
        runs: [AutomaticMergeRun],
        operations: [AutomaticMergeOperation],
        unresolvedConflicts: [AutomaticMergeUnresolvedConflict],
        blockedConflicts: [AutomaticMergeBlockedConflict]
    ) {
        self.runs = runs
        self.operations = operations
        self.unresolvedConflicts = unresolvedConflicts
        self.blockedConflicts = blockedConflicts
    }
}

public enum AutomaticMerge: Sendable {
    /// Classifies a row without inferring authority from editability.
    public static func classify(_ row: DiffRow) -> AutomaticMergeRowClassification {
        switch row.kind {
        case .unchanged:
            .insignificant
        case .removed:
            row.left != nil && row.right == nil ? .leftOnly : .inconsistent
        case .added:
            row.left == nil && row.right != nil ? .rightOnly : .inconsistent
        case .modified:
            row.left != nil && row.right != nil ? .modifiedPair : .inconsistent
        }
    }

    /// Plans symmetric two-way propagation. Left-only runs copy right and right-only runs copy
    /// left. Modified pairs and mixed-direction runs remain unresolved.
    public static func plan(
        rows: [DiffRow],
        editability: AutomaticMergeEditability,
        limits: AutomaticMergeLimits = AutomaticMergeLimits()
    ) throws -> AutomaticMergePlan {
        try Task.checkCancellation()
        guard limits.maximumRows >= 0 else {
            throw AutomaticMergeError.invalidLimit(.rows, value: limits.maximumRows)
        }
        guard limits.maximumRuns >= 0 else {
            throw AutomaticMergeError.invalidLimit(.runs, value: limits.maximumRuns)
        }
        guard rows.count <= limits.maximumRows else {
            throw AutomaticMergeError.tooManyRows(maximum: limits.maximumRows)
        }

        var runs: [AutomaticMergeRun] = []
        var operations: [AutomaticMergeOperation] = []
        var unresolved: [AutomaticMergeUnresolvedConflict] = []
        var blocked: [AutomaticMergeBlockedConflict] = []
        runs.reserveCapacity(min(rows.count, limits.maximumRuns))
        var rowIndex = rows.startIndex

        while rowIndex != rows.endIndex {
            if rowIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if classify(rows[rowIndex]) == .insignificant {
                rows.formIndex(after: &rowIndex)
                continue
            }

            let runStart = rowIndex
            var hasLeftOnly = false
            var hasRightOnly = false
            var hasModifiedPair = false
            var hasInconsistentRow = false

            while rowIndex != rows.endIndex {
                if rowIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
                let classification = classify(rows[rowIndex])
                guard classification != .insignificant else { break }
                switch classification {
                case .insignificant:
                    break
                case .leftOnly:
                    hasLeftOnly = true
                case .rightOnly:
                    hasRightOnly = true
                case .modifiedPair:
                    hasModifiedPair = true
                case .inconsistent:
                    hasInconsistentRow = true
                }
                rows.formIndex(after: &rowIndex)
            }

            guard runs.count < limits.maximumRuns else {
                throw AutomaticMergeError.tooManyRuns(maximum: limits.maximumRuns)
            }
            let classification: AutomaticMergeRunClassification
            if hasInconsistentRow {
                classification = .inconsistent
            } else if hasModifiedPair {
                classification = .modifiedPair
            } else if hasLeftOnly && hasRightOnly {
                classification = .mixedDirections
            } else if hasLeftOnly {
                classification = .leftOnly
            } else {
                classification = .rightOnly
            }
            let run = AutomaticMergeRun(
                rowRange: runStart..<rowIndex,
                classification: classification
            )
            runs.append(run)

            switch classification {
            case .leftOnly:
                appendOperationOrBlockedConflict(
                    run: run,
                    direction: .leftToRight,
                    destination: .right,
                    editability: editability,
                    operations: &operations,
                    blocked: &blocked
                )
            case .rightOnly:
                appendOperationOrBlockedConflict(
                    run: run,
                    direction: .rightToLeft,
                    destination: .left,
                    editability: editability,
                    operations: &operations,
                    blocked: &blocked
                )
            case .modifiedPair:
                unresolved.append(
                    AutomaticMergeUnresolvedConflict(run: run, reason: .modifiedPair)
                )
            case .mixedDirections:
                unresolved.append(
                    AutomaticMergeUnresolvedConflict(run: run, reason: .mixedDirections)
                )
            case .inconsistent:
                unresolved.append(
                    AutomaticMergeUnresolvedConflict(run: run, reason: .inconsistentRows)
                )
            }
        }

        try Task.checkCancellation()
        return AutomaticMergePlan(
            runs: runs,
            operations: operations,
            unresolvedConflicts: unresolved,
            blockedConflicts: blocked
        )
    }

    public static func plan(
        rows: [DiffRow],
        leftIsEditable: Bool,
        rightIsEditable: Bool,
        limits: AutomaticMergeLimits = AutomaticMergeLimits()
    ) throws -> AutomaticMergePlan {
        try plan(
            rows: rows,
            editability: AutomaticMergeEditability(
                left: leftIsEditable,
                right: rightIsEditable
            ),
            limits: limits
        )
    }

    private static func appendOperationOrBlockedConflict(
        run: AutomaticMergeRun,
        direction: MergeDirection,
        destination: AutomaticMergeSide,
        editability: AutomaticMergeEditability,
        operations: inout [AutomaticMergeOperation],
        blocked: inout [AutomaticMergeBlockedConflict]
    ) {
        if editability[destination] {
            operations.append(
                AutomaticMergeOperation(rowRange: run.rowRange, direction: direction)
            )
        } else {
            blocked.append(
                AutomaticMergeBlockedConflict(
                    run: run,
                    direction: direction,
                    destination: destination
                )
            )
        }
    }
}
