import Foundation

public enum ConflictNavigationError: Error, LocalizedError, Equatable, Sendable {
    case invalidTargetIndex(Int)
    case invalidMarkerWidth(conflictIndex: Int, width: Int)
    case invalidSourceLineRange(conflictIndex: Int, lowerBound: Int, upperBound: Int)
    case overlappingSourceLineRanges(firstConflictIndex: Int, secondConflictIndex: Int)
    case invalidPaneContributions(UInt8)
    case basePaneInTwoWayConflict(conflictIndex: Int)
    case emptyTopologyFilter

    public var errorDescription: String? {
        switch self {
        case .invalidTargetIndex(let index):
            "Conflict navigation target index \(index) must not be negative."
        case .invalidMarkerWidth(let index, let width):
            "Conflict \(index) has invalid marker width \(width)."
        case .invalidSourceLineRange(let index, let lowerBound, let upperBound):
            "Conflict \(index) has invalid source lines \(lowerBound)...\(upperBound)."
        case .overlappingSourceLineRanges(let firstIndex, let secondIndex):
            "Conflicts \(firstIndex) and \(secondIndex) have overlapping source lines."
        case .invalidPaneContributions(let rawValue):
            "Conflict pane contributions contain unsupported bits: \(rawValue)."
        case .basePaneInTwoWayConflict(let index):
            "Two-way conflict \(index) cannot contain base pane metadata."
        case .emptyTopologyFilter:
            "Conflict navigation topology filter must not be empty."
        }
    }
}

public struct ConflictNavigationTarget: Identifiable, Equatable, Hashable, Sendable {
    public struct PaneContributions: OptionSet, Codable, Equatable, Hashable, Sendable {
        public let rawValue: UInt8

        public static let current = PaneContributions(rawValue: 1 << 0)
        public static let base = PaneContributions(rawValue: 1 << 1)
        public static let incoming = PaneContributions(rawValue: 1 << 2)
        public static let all: PaneContributions = [.current, .base, .incoming]

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        fileprivate var isValid: Bool {
            rawValue & ~Self.all.rawValue == 0
        }
    }

    public struct ID: Codable, Equatable, Hashable, Sendable {
        public enum Topology: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
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
        public let paneContributions: PaneContributions

        fileprivate init(
            generation: UInt64,
            ordinal: Int,
            sourceLineRange: ClosedRange<Int>,
            markerWidth: Int,
            topology: Topology,
            currentLabel: String?,
            baseLabel: String?,
            incomingLabel: String?,
            paneContributions: PaneContributions
        ) {
            self.generation = generation
            self.ordinal = ordinal
            self.sourceLineRange = sourceLineRange
            self.markerWidth = markerWidth
            self.topology = topology
            self.currentLabel = currentLabel
            self.baseLabel = baseLabel
            self.incomingLabel = incomingLabel
            self.paneContributions = paneContributions
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
        incomingLabel: String? = nil,
        paneContributions: PaneContributions? = nil
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
        guard markerWidth >= ConflictFileParser.minimumMarkerWidth else {
            throw ConflictNavigationError.invalidMarkerWidth(
                conflictIndex: index,
                width: markerWidth
            )
        }
        let paneContributions = paneContributions
            ?? (topology == .diff3 ? .all : [.current, .incoming])
        guard paneContributions.isValid else {
            throw ConflictNavigationError.invalidPaneContributions(paneContributions.rawValue)
        }
        guard topology != .twoWay
            || (baseLabel == nil && !paneContributions.contains(.base))
        else {
            throw ConflictNavigationError.basePaneInTwoWayConflict(conflictIndex: index)
        }
        id = ID(
            generation: generation,
            ordinal: index,
            sourceLineRange: sourceLineRange,
            markerWidth: markerWidth,
            topology: topology,
            currentLabel: currentLabel,
            baseLabel: baseLabel,
            incomingLabel: incomingLabel,
            paneContributions: paneContributions
        )
        self.generation = generation
        self.index = index
        self.sourceLineRange = sourceLineRange
    }

    public var firstSourceLine: Int { sourceLineRange.lowerBound }
    public var lastSourceLine: Int { sourceLineRange.upperBound }
    public var paneContributions: PaneContributions { id.paneContributions }

    public func contains(sourceRow: Int) -> Bool {
        sourceLineRange.contains(sourceRow)
    }
}

public struct ConflictNavigationFilter: Equatable, Sendable {
    public static let all = ConflictNavigationFilter(
        validatedTopologies: Set(ConflictNavigationTarget.ID.Topology.allCases),
        paneContributions: []
    )

    public let topologies: Set<ConflictNavigationTarget.ID.Topology>
    /// Empty means topology-only filtering; otherwise any listed pane may contribute content.
    public let contributingToAnyOf: ConflictNavigationTarget.PaneContributions

    public init(
        topologies: Set<ConflictNavigationTarget.ID.Topology> = Set(
            ConflictNavigationTarget.ID.Topology.allCases
        ),
        contributingToAnyOf paneContributions: ConflictNavigationTarget.PaneContributions = []
    ) throws {
        guard !topologies.isEmpty else {
            throw ConflictNavigationError.emptyTopologyFilter
        }
        guard paneContributions.isValid else {
            throw ConflictNavigationError.invalidPaneContributions(paneContributions.rawValue)
        }
        self.topologies = topologies
        contributingToAnyOf = paneContributions
    }

    private init(
        validatedTopologies: Set<ConflictNavigationTarget.ID.Topology>,
        paneContributions: ConflictNavigationTarget.PaneContributions
    ) {
        topologies = validatedTopologies
        contributingToAnyOf = paneContributions
    }

    fileprivate func includes(_ target: ConflictNavigationTarget) -> Bool {
        guard topologies.contains(target.id.topology) else { return false }
        return contributingToAnyOf.isEmpty
            || !target.paneContributions.intersection(contributingToAnyOf).isEmpty
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
            guard entry.conflict.markerWidth >= ConflictFileParser.minimumMarkerWidth else {
                throw ConflictNavigationError.invalidMarkerWidth(
                    conflictIndex: entry.originalIndex,
                    width: entry.conflict.markerWidth
                )
            }
            guard topology != .twoWay
                || (entry.conflict.baseLabel == nil && !entry.conflict.hasBaseContent)
            else {
                throw ConflictNavigationError.basePaneInTwoWayConflict(
                    conflictIndex: entry.originalIndex
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
                    incomingLabel: entry.conflict.incomingLabel,
                    paneContributions: Self.paneContributions(for: entry.conflict)
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

    public func conflicts(
        matching filter: ConflictNavigationFilter
    ) -> [ConflictNavigationTarget] {
        conflicts.filter(filter.includes)
    }

    public func first(matching filter: ConflictNavigationFilter) -> ConflictNavigationTarget? {
        firstConflict(atOrAfter: conflicts.startIndex, matching: filter)
    }

    public func last(matching filter: ConflictNavigationFilter) -> ConflictNavigationTarget? {
        guard let index = conflicts.indices.last else { return nil }
        return lastConflict(atOrBefore: index, matching: filter)
    }

    /// Resolves a selection from this parse generation, or the conflict containing the cursor row.
    public func current(
        selectedConflict: ConflictNavigationTarget? = nil,
        cursorRow: Int? = nil,
        matching filter: ConflictNavigationFilter = .all
    ) -> ConflictNavigationTarget? {
        if let selectedConflict,
            let selected = validated(selectedConflict),
            filter.includes(selected)
        {
            return selected
        }
        guard let cursorRow else { return nil }

        let insertion = firstIndex(startingAtOrAfter: cursorRow)
        let candidate = insertion - 1
        if conflicts.indices.contains(candidate),
            conflicts[candidate].contains(sourceRow: cursorRow),
            filter.includes(conflicts[candidate])
        {
            return conflicts[candidate]
        }
        guard conflicts.indices.contains(insertion),
            conflicts[insertion].contains(sourceRow: cursorRow),
            filter.includes(conflicts[insertion])
        else { return nil }
        return conflicts[insertion]
    }

    /// Returns the conflict after the selection. Without one, uses the first start at or after
    /// `cursorRow`; a missing cursor starts at the first conflict. Never wraps.
    public func next(
        after selectedConflict: ConflictNavigationTarget? = nil,
        cursorRow: Int? = nil,
        matching filter: ConflictNavigationFilter = .all
    ) -> ConflictNavigationTarget? {
        if let selectedConflict {
            guard let selected = validated(selectedConflict) else {
                guard let cursorRow else { return nil }
                return firstConflict(
                    atOrAfter: firstIndex(startingAtOrAfter: cursorRow),
                    matching: filter
                )
            }
            return firstConflict(
                atOrAfter: conflicts.index(after: selected.index),
                matching: filter
            )
        }
        guard let cursorRow else { return first(matching: filter) }
        return firstConflict(
            atOrAfter: firstIndex(startingAtOrAfter: cursorRow),
            matching: filter
        )
    }

    /// Returns the conflict before the selection. Without one, uses the last end at or before
    /// `cursorRow`; a missing cursor starts at the last conflict. Never wraps.
    public func previous(
        before selectedConflict: ConflictNavigationTarget? = nil,
        cursorRow: Int? = nil,
        matching filter: ConflictNavigationFilter = .all
    ) -> ConflictNavigationTarget? {
        if let selectedConflict {
            guard let selected = validated(selectedConflict) else {
                guard let cursorRow else { return nil }
                return lastConflict(
                    atOrBefore: lastIndex(endingAtOrBefore: cursorRow),
                    matching: filter
                )
            }
            guard selected.index > conflicts.startIndex else { return nil }
            return lastConflict(
                atOrBefore: conflicts.index(before: selected.index),
                matching: filter
            )
        }
        guard let cursorRow else { return last(matching: filter) }
        return lastConflict(
            atOrBefore: lastIndex(endingAtOrBefore: cursorRow),
            matching: filter
        )
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

    private func firstConflict(
        atOrAfter index: Int,
        matching filter: ConflictNavigationFilter
    ) -> ConflictNavigationTarget? {
        var index = index
        while index != conflicts.endIndex {
            guard conflicts.indices.contains(index) else { return nil }
            if filter.includes(conflicts[index]) {
                return conflicts[index]
            }
            conflicts.formIndex(after: &index)
        }
        return nil
    }

    private func lastConflict(
        atOrBefore index: Int,
        matching filter: ConflictNavigationFilter
    ) -> ConflictNavigationTarget? {
        guard conflicts.indices.contains(index) else { return nil }
        var index = index
        while true {
            if filter.includes(conflicts[index]) {
                return conflicts[index]
            }
            guard index != conflicts.startIndex else { return nil }
            conflicts.formIndex(before: &index)
        }
    }

    private static func paneContributions(
        for conflict: ConflictFileConflict
    ) -> ConflictNavigationTarget.PaneContributions {
        var contributions: ConflictNavigationTarget.PaneContributions = []
        if conflict.hasCurrentContent { contributions.insert(.current) }
        if conflict.hasBaseContent { contributions.insert(.base) }
        if conflict.hasIncomingContent { contributions.insert(.incoming) }
        return contributions
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
