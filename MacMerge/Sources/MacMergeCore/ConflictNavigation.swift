import Foundation

public enum ConflictNavigationError: Error, LocalizedError, Equatable, Sendable {
    case invalidTargetIndex(Int)
    case invalidSourceLineRange(conflictIndex: Int, lowerBound: Int, upperBound: Int)
    case overlappingSourceLineRanges(firstConflictIndex: Int, secondConflictIndex: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidTargetIndex(let index):
            "Conflict navigation target index \(index) must not be negative."
        case .invalidSourceLineRange(let index, let lowerBound, let upperBound):
            "Conflict \(index) has invalid source lines \(lowerBound)...\(upperBound)."
        case .overlappingSourceLineRanges(let firstIndex, let secondIndex):
            "Conflicts \(firstIndex) and \(secondIndex) have overlapping source lines."
        }
    }
}

public struct ConflictNavigationTarget: Identifiable, Equatable, Hashable, Sendable {
    public struct ID: Codable, Equatable, Hashable, Sendable {
        public enum Topology: String, Codable, Equatable, Hashable, Sendable {
            case twoWay
            case diff3
        }

        public let generation: UInt64
        public let ordinal: Int
        public let sourceLineRange: ClosedRange<Int>
        public let markerWidth: Int
        public let topology: Topology
        public let currentLabel: String?
        public let baseLabel: String?
        public let incomingLabel: String?

        fileprivate init(
            generation: UInt64,
            ordinal: Int,
            sourceLineRange: ClosedRange<Int>,
            markerWidth: Int,
            topology: Topology,
            currentLabel: String?,
            baseLabel: String?,
            incomingLabel: String?
        ) {
            self.generation = generation
            self.ordinal = ordinal
            self.sourceLineRange = sourceLineRange
            self.markerWidth = markerWidth
            self.topology = topology
            self.currentLabel = currentLabel
            self.baseLabel = baseLabel
            self.incomingLabel = incomingLabel
        }
    }

    /// Deterministic conflict identity scoped to a parse generation.
    public let id: ID
    /// Generation of the parse result that produced this target.
    public let generation: UInt64
    /// Zero-based position in source-line order.
    public let index: Int
    /// One-based source lines from the opening marker through the closing marker.
    public let sourceLineRange: ClosedRange<Int>

    public init(
        generation: UInt64,
        index: Int,
        sourceLineRange: ClosedRange<Int>,
        markerWidth: Int = 7,
        topology: ID.Topology,
        currentLabel: String? = nil,
        baseLabel: String? = nil,
        incomingLabel: String? = nil
    ) throws {
        guard index >= 0 else {
            throw ConflictNavigationError.invalidTargetIndex(index)
        }
        guard sourceLineRange.lowerBound > 0,
            sourceLineRange.lowerBound <= sourceLineRange.upperBound
        else {
            throw ConflictNavigationError.invalidSourceLineRange(
                conflictIndex: index,
                lowerBound: sourceLineRange.lowerBound,
                upperBound: sourceLineRange.upperBound
            )
        }
        id = ID(
            generation: generation,
            ordinal: index,
            sourceLineRange: sourceLineRange,
            markerWidth: markerWidth,
            topology: topology,
            currentLabel: currentLabel,
            baseLabel: baseLabel,
            incomingLabel: incomingLabel
        )
        self.generation = generation
        self.index = index
        self.sourceLineRange = sourceLineRange
    }

    public var firstSourceLine: Int { sourceLineRange.lowerBound }
    public var lastSourceLine: Int { sourceLineRange.upperBound }

    public func contains(sourceRow: Int) -> Bool {
        sourceLineRange.contains(sourceRow)
    }
}

/// Immutable source-line index for navigating parsed conflict-file regions.
public struct ConflictNavigationIndex: Equatable, Sendable {
    public let generation: UInt64
    public let conflicts: [ConflictNavigationTarget]

    public var sourceLineRanges: [ClosedRange<Int>] {
        conflicts.map(\.sourceLineRange)
    }

    public var count: Int { conflicts.count }
    public var isEmpty: Bool { conflicts.isEmpty }
    public var first: ConflictNavigationTarget? { conflicts.first }
    public var last: ConflictNavigationTarget? { conflicts.last }

    public init(parseResult: ConflictFileParseResult, generation: UInt64) throws {
        let orderedConflicts = parseResult.conflicts.enumerated().map { offset, conflict in
            (originalIndex: offset, conflict: conflict)
        }.sorted { left, right in
            if left.conflict.sourceLineRange.lowerBound
                != right.conflict.sourceLineRange.lowerBound
            {
                return left.conflict.sourceLineRange.lowerBound
                    < right.conflict.sourceLineRange.lowerBound
            }
            if left.conflict.sourceLineRange.upperBound
                != right.conflict.sourceLineRange.upperBound
            {
                return left.conflict.sourceLineRange.upperBound
                    < right.conflict.sourceLineRange.upperBound
            }
            return left.originalIndex < right.originalIndex
        }

        var targets: [ConflictNavigationTarget] = []
        targets.reserveCapacity(orderedConflicts.count)
        var previous: (originalIndex: Int, range: ClosedRange<Int>)?
        let topology: ConflictNavigationTarget.ID.Topology =
            parseResult.isThreeWay ? .diff3 : .twoWay

        for entry in orderedConflicts {
            let range = entry.conflict.sourceLineRange
            guard range.lowerBound > 0,
                range.lowerBound <= range.upperBound
            else {
                throw ConflictNavigationError.invalidSourceLineRange(
                    conflictIndex: entry.originalIndex,
                    lowerBound: range.lowerBound,
                    upperBound: range.upperBound
                )
            }
            if let previous, range.lowerBound <= previous.range.upperBound {
                throw ConflictNavigationError.overlappingSourceLineRanges(
                    firstConflictIndex: previous.originalIndex,
                    secondConflictIndex: entry.originalIndex
                )
            }

            targets.append(
                try ConflictNavigationTarget(
                    generation: generation,
                    index: targets.count,
                    sourceLineRange: range,
                    markerWidth: entry.conflict.markerWidth,
                    topology: topology,
                    currentLabel: entry.conflict.currentLabel,
                    baseLabel: entry.conflict.baseLabel,
                    incomingLabel: entry.conflict.incomingLabel
                )
            )
            previous = (entry.originalIndex, range)
        }

        self.generation = generation
        conflicts = targets
    }

    public func conflict(at index: Int) -> ConflictNavigationTarget? {
        guard conflicts.indices.contains(index) else { return nil }
        return conflicts[index]
    }

    /// Resolves a selection from this parse generation, or the conflict containing the cursor row.
    public func current(
        selectedConflict: ConflictNavigationTarget? = nil,
        cursorRow: Int? = nil
    ) -> ConflictNavigationTarget? {
        if let selectedConflict, let selected = validated(selectedConflict) {
            return selected
        }
        guard let cursorRow else { return nil }

        let insertion = firstIndex(startingAtOrAfter: cursorRow)
        let candidate = insertion - 1
        guard conflicts.indices.contains(candidate), conflicts[candidate].contains(sourceRow: cursorRow)
        else {
            return insertion < conflicts.count && conflicts[insertion].contains(sourceRow: cursorRow)
                ? conflicts[insertion]
                : nil
        }
        return conflicts[candidate]
    }

    /// Returns the conflict after the selection. Without one, uses the first start at or after
    /// `cursorRow`; a missing cursor starts at the first conflict. Never wraps.
    public func next(
        after selectedConflict: ConflictNavigationTarget? = nil,
        cursorRow: Int? = nil
    ) -> ConflictNavigationTarget? {
        if let selectedConflict {
            guard let selected = validated(selectedConflict) else {
                guard let cursorRow else { return nil }
                return conflict(at: firstIndex(startingAtOrAfter: cursorRow))
            }
            guard selected.index < conflicts.index(before: conflicts.endIndex) else { return nil }
            return conflicts[conflicts.index(after: selected.index)]
        }
        guard let cursorRow else { return first }
        return conflict(at: firstIndex(startingAtOrAfter: cursorRow))
    }

    /// Returns the conflict before the selection. Without one, uses the last end at or before
    /// `cursorRow`; a missing cursor starts at the last conflict. Never wraps.
    public func previous(
        before selectedConflict: ConflictNavigationTarget? = nil,
        cursorRow: Int? = nil
    ) -> ConflictNavigationTarget? {
        if let selectedConflict {
            guard let selected = validated(selectedConflict) else {
                guard let cursorRow else { return nil }
                return conflict(at: lastIndex(endingAtOrBefore: cursorRow))
            }
            guard selected.index > conflicts.startIndex else { return nil }
            return conflicts[conflicts.index(before: selected.index)]
        }
        guard let cursorRow else { return last }
        return conflict(at: lastIndex(endingAtOrBefore: cursorRow))
    }

    private func validated(
        _ selectedConflict: ConflictNavigationTarget
    ) -> ConflictNavigationTarget? {
        guard selectedConflict.generation == generation,
            let current = conflict(at: selectedConflict.index),
            current.id == selectedConflict.id,
            current.sourceLineRange == selectedConflict.sourceLineRange
        else {
            return nil
        }
        return current
    }

    private func firstIndex(startingAtOrAfter sourceRow: Int) -> Int {
        var lower = conflicts.startIndex
        var upper = conflicts.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if conflicts[middle].firstSourceLine < sourceRow {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func lastIndex(endingAtOrBefore sourceRow: Int) -> Int {
        var lower = conflicts.startIndex
        var upper = conflicts.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if conflicts[middle].lastSourceLine <= sourceRow {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower - 1
    }
}

public typealias ConflictNavigation = ConflictNavigationIndex
