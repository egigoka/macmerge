import Foundation

public enum ThreeWayDifferencePane:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case left
    case middle
    case right
}

public enum ThreeWayDifferencePanePair:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case leftAndMiddle
    case leftAndRight
    case middleAndRight

    public var firstPane: ThreeWayDifferencePane {
        switch self {
        case .leftAndMiddle, .leftAndRight: .left
        case .middleAndRight: .middle
        }
    }

    public var secondPane: ThreeWayDifferencePane {
        switch self {
        case .leftAndMiddle: .middle
        case .middleAndRight, .leftAndRight: .right
        }
    }

    public func contains(_ pane: ThreeWayDifferencePane) -> Bool {
        pane == firstPane || pane == secondPane
    }
}

public enum ThreeWayOneSidedDifferenceType:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case leftOnly
    case middleOnly
    case rightOnly

    public var pane: ThreeWayDifferencePane {
        switch self {
        case .leftOnly: .left
        case .middleOnly: .middle
        case .rightOnly: .right
        }
    }
}

public enum ThreeWayDifferenceType: Equatable, Hashable, Sendable {
    case panePair(ThreeWayDifferencePanePair)
    case oneSided(ThreeWayOneSidedDifferenceType)

    fileprivate static let allTypes: [ThreeWayDifferenceType] =
        ThreeWayDifferencePanePair.allCases.map(ThreeWayDifferenceType.panePair)
        + ThreeWayOneSidedDifferenceType.allCases.map(ThreeWayDifferenceType.oneSided)

    fileprivate var sortRank: Int {
        switch self {
        case .panePair(.leftAndMiddle): 0
        case .panePair(.leftAndRight): 1
        case .panePair(.middleAndRight): 2
        case .oneSided(.leftOnly): 3
        case .oneSided(.middleOnly): 4
        case .oneSided(.rightOnly): 5
        }
    }
}

public struct ThreeWayDifferenceNavigationDifference:
    Identifiable, Equatable, Hashable, Sendable
{
    public struct ID: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: UInt64

        public init(rawValue: UInt64) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let type: ThreeWayDifferenceType
    /// Zero-based, half-open aligned-row range occupied by this difference.
    public let rowRange: Range<Int>

    public init(id: ID, type: ThreeWayDifferenceType, rowRange: Range<Int>) {
        self.id = id
        self.type = type
        self.rowRange = rowRange
    }

    public init(id: UInt64, type: ThreeWayDifferenceType, rowRange: Range<Int>) {
        self.init(id: ID(rawValue: id), type: type, rowRange: rowRange)
    }
}

public struct ThreeWayDifferenceNavigationLimits: Equatable, Hashable, Sendable {
    public static let maximumSupportedRows = 1_048_576
    public static let maximumSupportedDifferences = 1_048_576
    public static let maximumSupportedWork = 64 * 1_048_576
    public static let maximumCancellationCheckInterval = 4_096
    public static let `default` = ThreeWayDifferenceNavigationLimits()

    public let maximumRows: Int
    public let maximumDifferences: Int
    public let maximumWork: Int
    public let cancellationCheckInterval: Int

    public init(
        maximumRows: Int = ThreeWayDifferenceNavigationLimits.maximumSupportedRows,
        maximumDifferences: Int = ThreeWayDifferenceNavigationLimits.maximumSupportedDifferences,
        maximumWork: Int = ThreeWayDifferenceNavigationLimits.maximumSupportedWork,
        cancellationCheckInterval: Int = 1_024
    ) {
        self.maximumRows = maximumRows
        self.maximumDifferences = maximumDifferences
        self.maximumWork = maximumWork
        self.cancellationCheckInterval = cancellationCheckInterval
    }
}

public enum ThreeWayDifferenceNavigationIdentityRole:
    String, Equatable, Hashable, Sendable
{
    case selected
    case current
}

public enum ThreeWayDifferenceNavigationError:
    Error, LocalizedError, Equatable, Hashable, Sendable
{
    case cancelled
    case invalidLimits
    case tooManyDifferences(maximum: Int)
    case invalidRowRange(
        id: ThreeWayDifferenceNavigationDifference.ID,
        range: Range<Int>,
        maximumRows: Int
    )
    case duplicateDifferenceID(ThreeWayDifferenceNavigationDifference.ID)
    case overlappingDifferences(
        type: ThreeWayDifferenceType,
        first: ThreeWayDifferenceNavigationDifference.ID,
        second: ThreeWayDifferenceNavigationDifference.ID
    )
    case emptyFilter
    case staleGeneration(expected: UInt64, actual: UInt64)
    case staleIdentity(
        role: ThreeWayDifferenceNavigationIdentityRole,
        id: ThreeWayDifferenceNavigationTarget.ID
    )
    case workLimitExceeded(maximumWork: Int)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Three-way difference navigation was cancelled."
        case .invalidLimits:
            "Three-way difference navigation limits are invalid."
        case .tooManyDifferences(let maximum):
            "Three-way difference navigation exceeds the \(maximum)-difference limit."
        case .invalidRowRange(let id, let range, let maximumRows):
            "Three-way difference \(id.rawValue) has row range "
                + "\(range.lowerBound)..<\(range.upperBound) outside 0..<\(maximumRows)."
        case .duplicateDifferenceID(let id):
            "Three-way difference ID \(id.rawValue) is duplicated."
        case .overlappingDifferences(let type, let first, let second):
            "Three-way differences \(first.rawValue) and \(second.rawValue) overlap "
                + "within \(Self.description(of: type))."
        case .emptyFilter:
            "Three-way difference navigation filter must not be empty."
        case .staleGeneration(let expected, let actual):
            "Three-way difference navigation expected generation \(expected), not \(actual)."
        case .staleIdentity(let role, let id):
            "Three-way difference \(role.rawValue) identity \(id.sourceID.rawValue) is stale."
        case .workLimitExceeded(let maximumWork):
            "Three-way difference navigation exceeds the \(maximumWork)-unit work limit."
        }
    }

    private static func description(of type: ThreeWayDifferenceType) -> String {
        switch type {
        case .panePair(let pair): pair.rawValue
        case .oneSided(let oneSided): oneSided.rawValue
        }
    }
}

public struct ThreeWayDifferenceNavigationTarget:
    Identifiable, Equatable, Hashable, Sendable
{
    public struct ID: Equatable, Hashable, Sendable {
        public let generation: UInt64
        public let sourceID: ThreeWayDifferenceNavigationDifference.ID
        public let type: ThreeWayDifferenceType
        public let rowRange: Range<Int>

        fileprivate init(
            generation: UInt64,
            sourceID: ThreeWayDifferenceNavigationDifference.ID,
            type: ThreeWayDifferenceType,
            rowRange: Range<Int>
        ) {
            self.generation = generation
            self.sourceID = sourceID
            self.type = type
            self.rowRange = rowRange
        }
    }

    public let id: ID
    public let generation: UInt64
    /// Zero-based position in deterministic navigation order.
    public let index: Int
    public let type: ThreeWayDifferenceType
    public let rowRange: Range<Int>

    public var sourceID: ThreeWayDifferenceNavigationDifference.ID { id.sourceID }
    public var firstRow: Int { rowRange.lowerBound }
    public var lastRow: Int { rowRange.upperBound - 1 }

    fileprivate init(
        generation: UInt64,
        index: Int,
        difference: ThreeWayDifferenceNavigationDifference
    ) {
        id = ID(
            generation: generation,
            sourceID: difference.id,
            type: difference.type,
            rowRange: difference.rowRange
        )
        self.generation = generation
        self.index = index
        type = difference.type
        rowRange = difference.rowRange
    }

    public func contains(row: Int) -> Bool {
        rowRange.contains(row)
    }
}

public struct ThreeWayDifferenceNavigationFilter: Equatable, Hashable, Sendable {
    public static let all = ThreeWayDifferenceNavigationFilter(
        validatedTypes: Set(ThreeWayDifferenceType.allTypes)
    )

    public let types: Set<ThreeWayDifferenceType>

    public init(
        types: Set<ThreeWayDifferenceType>
    ) throws(ThreeWayDifferenceNavigationError) {
        guard !types.isEmpty else {
            throw ThreeWayDifferenceNavigationError.emptyFilter
        }
        self.types = types
    }

    public static func panePair(
        _ pair: ThreeWayDifferencePanePair
    ) -> ThreeWayDifferenceNavigationFilter {
        ThreeWayDifferenceNavigationFilter(validatedTypes: [.panePair(pair)])
    }

    public static func oneSided(
        _ type: ThreeWayOneSidedDifferenceType
    ) -> ThreeWayDifferenceNavigationFilter {
        ThreeWayDifferenceNavigationFilter(validatedTypes: [.oneSided(type)])
    }

    private init(validatedTypes: Set<ThreeWayDifferenceType>) {
        types = validatedTypes
    }

    fileprivate func includes(_ target: ThreeWayDifferenceNavigationTarget) -> Bool {
        types.contains(target.type)
    }
}

public enum ThreeWayDifferenceNavigationCommand:
    String, CaseIterable, Equatable, Hashable, Sendable
{
    case first
    case current
    case previous
    case next
    case last
}

public enum ThreeWayDifferenceSelectionVisibility:
    String, Equatable, Hashable, Sendable
{
    case visible
    case offscreen
}

/// Caller snapshot used to resolve command origin without retaining UI state.
public struct ThreeWayDifferenceNavigationContext: Equatable, Hashable, Sendable {
    public let generation: UInt64
    public let selectedTargetID: ThreeWayDifferenceNavigationTarget.ID?
    public let selectionVisibility: ThreeWayDifferenceSelectionVisibility
    public let currentTargetID: ThreeWayDifferenceNavigationTarget.ID?
    /// Zero-based current row. It may identify an unchanged row or lie outside document bounds.
    public let cursorRow: Int?

    public var selectedDifferenceID: ThreeWayDifferenceNavigationTarget.ID? {
        selectedTargetID
    }

    public var currentDifferenceID: ThreeWayDifferenceNavigationTarget.ID? {
        currentTargetID
    }

    public init(
        generation: UInt64,
        selectedTargetID: ThreeWayDifferenceNavigationTarget.ID? = nil,
        selectionVisibility: ThreeWayDifferenceSelectionVisibility = .visible,
        currentTargetID: ThreeWayDifferenceNavigationTarget.ID? = nil,
        cursorRow: Int? = nil
    ) {
        self.generation = generation
        self.selectedTargetID = selectedTargetID
        self.selectionVisibility = selectionVisibility
        self.currentTargetID = currentTargetID
        self.cursorRow = cursorRow
    }

    public init(
        generation: UInt64,
        selectedTarget: ThreeWayDifferenceNavigationTarget?,
        selectionVisibility: ThreeWayDifferenceSelectionVisibility = .visible,
        currentTarget: ThreeWayDifferenceNavigationTarget? = nil,
        cursorRow: Int? = nil
    ) {
        self.init(
            generation: generation,
            selectedTargetID: selectedTarget?.id,
            selectionVisibility: selectionVisibility,
            currentTargetID: currentTarget?.id,
            cursorRow: cursorRow
        )
    }
}

public struct ThreeWayDifferenceNavigationResolution:
    Equatable, Hashable, Sendable
{
    public let command: ThreeWayDifferenceNavigationCommand
    public let expectedGeneration: UInt64
    public let target: ThreeWayDifferenceNavigationTarget?

    public var canExecute: Bool { target != nil }
    public var isEnabled: Bool { canExecute }

    public init(
        command: ThreeWayDifferenceNavigationCommand,
        expectedGeneration: UInt64,
        target: ThreeWayDifferenceNavigationTarget?
    ) {
        self.command = command
        self.expectedGeneration = expectedGeneration
        self.target = target
    }
}

public struct ThreeWayDifferenceNavigationCommandStates:
    Equatable, Hashable, Sendable
{
    public let first: Bool
    public let current: Bool
    public let previous: Bool
    public let next: Bool
    public let last: Bool

    public init(first: Bool, current: Bool, previous: Bool, next: Bool, last: Bool) {
        self.first = first
        self.current = current
        self.previous = previous
        self.next = next
        self.last = last
    }

    public subscript(command: ThreeWayDifferenceNavigationCommand) -> Bool {
        switch command {
        case .first: first
        case .current: current
        case .previous: previous
        case .next: next
        case .last: last
        }
    }
}

/// Immutable, generation-scoped index for advanced three-pane difference navigation.
public struct ThreeWayDifferenceNavigationIndex: Equatable, Hashable, Sendable {
    public let generation: UInt64
    /// Source-row ordered targets. Pair categories precede one-sided categories on equal ranges.
    public let targets: [ThreeWayDifferenceNavigationTarget]

    private let sourceIDOrderedTargetIndices: [Int]
    private let limits: ThreeWayDifferenceNavigationLimits

    public var differences: [ThreeWayDifferenceNavigationTarget] { targets }
    public var count: Int { targets.count }
    public var isEmpty: Bool { targets.isEmpty }
    public var first: ThreeWayDifferenceNavigationTarget? { targets.first }
    public var last: ThreeWayDifferenceNavigationTarget? { targets.last }

    public init(
        generation: UInt64,
        differences: [ThreeWayDifferenceNavigationDifference],
        limits: ThreeWayDifferenceNavigationLimits = .default
    ) throws(ThreeWayDifferenceNavigationError) {
        try Self.validate(limits)
        try Self.checkCancellation()
        guard differences.count <= limits.maximumDifferences else {
            throw ThreeWayDifferenceNavigationError.tooManyDifferences(
                maximum: limits.maximumDifferences
            )
        }

        var budget = ThreeWayDifferenceNavigationWorkBudget(limits: limits)
        var seenIDs: Set<ThreeWayDifferenceNavigationDifference.ID> = []
        seenIDs.reserveCapacity(differences.count)
        for difference in differences {
            try budget.consume()
            guard difference.rowRange.lowerBound >= 0,
                difference.rowRange.lowerBound < difference.rowRange.upperBound,
                difference.rowRange.upperBound <= limits.maximumRows
            else {
                throw ThreeWayDifferenceNavigationError.invalidRowRange(
                    id: difference.id,
                    range: difference.rowRange,
                    maximumRows: limits.maximumRows
                )
            }
            guard seenIDs.insert(difference.id).inserted else {
                throw ThreeWayDifferenceNavigationError.duplicateDifferenceID(difference.id)
            }
        }

        let ordered = try Self.deterministicallySorted(differences, budget: &budget)
        var previousByType = [ThreeWayDifferenceNavigationDifference?](
            repeating: nil,
            count: ThreeWayDifferenceType.allTypes.count
        )
        var targets: [ThreeWayDifferenceNavigationTarget] = []
        targets.reserveCapacity(ordered.count)
        for difference in ordered {
            try budget.consume()
            let typeIndex = difference.type.sortRank
            if let previous = previousByType[typeIndex],
                difference.rowRange.lowerBound < previous.rowRange.upperBound
            {
                throw ThreeWayDifferenceNavigationError.overlappingDifferences(
                    type: difference.type,
                    first: previous.id,
                    second: difference.id
                )
            }
            previousByType[typeIndex] = difference
            targets.append(
                ThreeWayDifferenceNavigationTarget(
                    generation: generation,
                    index: targets.count,
                    difference: difference
                )
            )
        }

        var sourceIDOrderedTargetIndices = Array(targets.indices)
        sourceIDOrderedTargetIndices = try Self.deterministicallySortedIndices(
            sourceIDOrderedTargetIndices,
            targets: targets,
            budget: &budget
        )
        try budget.finish()

        self.generation = generation
        self.targets = targets
        self.sourceIDOrderedTargetIndices = sourceIDOrderedTargetIndices
        self.limits = limits
    }

    public func target(
        withID id: ThreeWayDifferenceNavigationTarget.ID
    ) -> ThreeWayDifferenceNavigationTarget? {
        guard id.generation == generation else { return nil }
        var lower = sourceIDOrderedTargetIndices.startIndex
        var upper = sourceIDOrderedTargetIndices.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let candidate = targets[sourceIDOrderedTargetIndices[middle]]
            if candidate.sourceID.rawValue < id.sourceID.rawValue {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard sourceIDOrderedTargetIndices.indices.contains(lower) else { return nil }
        let target = targets[sourceIDOrderedTargetIndices[lower]]
        return target.id == id ? target : nil
    }

    public func targets(
        matching filter: ThreeWayDifferenceNavigationFilter
    ) throws(ThreeWayDifferenceNavigationError) -> [ThreeWayDifferenceNavigationTarget] {
        var budget = ThreeWayDifferenceNavigationWorkBudget(limits: limits)
        var result: [ThreeWayDifferenceNavigationTarget] = []
        result.reserveCapacity(min(targets.count, 4_096))
        for target in targets {
            try budget.consume()
            if filter.includes(target) { result.append(target) }
        }
        try budget.finish()
        return result
    }

    public func resolve(
        _ command: ThreeWayDifferenceNavigationCommand,
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter = .all
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationResolution {
        var budget = ThreeWayDifferenceNavigationWorkBudget(limits: limits)
        let resolution = try resolution(
            command,
            in: context,
            matching: filter,
            budget: &budget
        )
        try budget.finish()
        return resolution
    }

    public func commandStates(
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter = .all
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationCommandStates {
        var budget = ThreeWayDifferenceNavigationWorkBudget(limits: limits)
        var states: [ThreeWayDifferenceNavigationCommand: Bool] = [:]
        states.reserveCapacity(ThreeWayDifferenceNavigationCommand.allCases.count)
        for command in ThreeWayDifferenceNavigationCommand.allCases {
            states[command] = try resolution(
                command,
                in: context,
                matching: filter,
                budget: &budget
            ).canExecute
        }
        try budget.finish()
        return ThreeWayDifferenceNavigationCommandStates(
            first: states[.first] == true,
            current: states[.current] == true,
            previous: states[.previous] == true,
            next: states[.next] == true,
            last: states[.last] == true
        )
    }

    public func first(
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter = .all
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        try resolve(.first, in: context, matching: filter).target
    }

    public func current(
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter = .all
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        try resolve(.current, in: context, matching: filter).target
    }

    public func previous(
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter = .all
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        try resolve(.previous, in: context, matching: filter).target
    }

    public func next(
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter = .all
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        try resolve(.next, in: context, matching: filter).target
    }

    public func last(
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter = .all
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        try resolve(.last, in: context, matching: filter).target
    }

    private func resolution(
        _ command: ThreeWayDifferenceNavigationCommand,
        in context: ThreeWayDifferenceNavigationContext,
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationResolution {
        try Self.checkCancellation()
        guard context.generation == generation else {
            throw ThreeWayDifferenceNavigationError.staleGeneration(
                expected: generation,
                actual: context.generation
            )
        }
        let selected = try validated(
            context.selectedTargetID,
            role: .selected,
            budget: &budget
        )
        let current = try validated(
            context.currentTargetID,
            role: .current,
            budget: &budget
        )
        let target: ThreeWayDifferenceNavigationTarget?
        switch command {
        case .first:
            target = try firstTarget(matching: filter, budget: &budget)
        case .current:
            // Current reveals stable selection even when it is offscreen; visibility only changes
            // the origin of Previous and Next.
            if let selected, filter.includes(selected) {
                target = selected
            } else if let current, filter.includes(current) {
                target = current
            } else if let cursorRow = context.cursorRow {
                target = try currentTarget(
                    containing: cursorRow,
                    matching: filter,
                    budget: &budget
                )
            } else {
                target = nil
            }
        case .previous:
            target = try adjacentTarget(
                forward: false,
                selected: selected,
                selectionVisibility: context.selectionVisibility,
                current: current,
                cursorRow: context.cursorRow,
                matching: filter,
                budget: &budget
            )
        case .next:
            target = try adjacentTarget(
                forward: true,
                selected: selected,
                selectionVisibility: context.selectionVisibility,
                current: current,
                cursorRow: context.cursorRow,
                matching: filter,
                budget: &budget
            )
        case .last:
            target = try lastTarget(matching: filter, budget: &budget)
        }
        return ThreeWayDifferenceNavigationResolution(
            command: command,
            expectedGeneration: generation,
            target: target
        )
    }

    private func adjacentTarget(
        forward: Bool,
        selected: ThreeWayDifferenceNavigationTarget?,
        selectionVisibility: ThreeWayDifferenceSelectionVisibility,
        current: ThreeWayDifferenceNavigationTarget?,
        cursorRow: Int?,
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        let origin = selectionVisibility == .visible ? selected ?? current : current
        if let origin {
            return try scannedTarget(
                from: origin.index,
                forward: forward,
                matching: filter,
                budget: &budget
            )
        }
        if let cursorRow {
            return forward
                ? try firstTarget(
                    startingAtOrAfter: cursorRow,
                    matching: filter,
                    budget: &budget
                )
                : try lastTarget(
                    endingAtOrBefore: cursorRow,
                    matching: filter,
                    budget: &budget
                )
        }
        return forward
            ? try firstTarget(matching: filter, budget: &budget)
            : try lastTarget(matching: filter, budget: &budget)
    }

    private func scannedTarget(
        from originIndex: Int,
        forward: Bool,
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        var index = forward ? originIndex + 1 : originIndex - 1
        while targets.indices.contains(index) {
            try budget.consume()
            if filter.includes(targets[index]) { return targets[index] }
            index += forward ? 1 : -1
        }
        return nil
    }

    private func currentTarget(
        containing row: Int,
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        for target in targets {
            try budget.consume()
            if target.firstRow > row { return nil }
            if target.contains(row: row), filter.includes(target) { return target }
        }
        return nil
    }

    private func firstTarget(
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        try firstTarget(
            startingAtOrAfter: Int.min,
            matching: filter,
            budget: &budget
        )
    }

    private func firstTarget(
        startingAtOrAfter row: Int,
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        for target in targets {
            try budget.consume()
            if target.firstRow >= row, filter.includes(target) { return target }
        }
        return nil
    }

    private func lastTarget(
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        try lastTarget(
            endingAtOrBefore: Int.max,
            matching: filter,
            budget: &budget
        )
    }

    private func lastTarget(
        endingAtOrBefore row: Int,
        matching filter: ThreeWayDifferenceNavigationFilter,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        for target in targets.reversed() {
            try budget.consume()
            if target.lastRow <= row, filter.includes(target) { return target }
        }
        return nil
    }

    private func validated(
        _ id: ThreeWayDifferenceNavigationTarget.ID?,
        role: ThreeWayDifferenceNavigationIdentityRole,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> ThreeWayDifferenceNavigationTarget? {
        guard let id else { return nil }
        guard id.generation == generation else {
            throw ThreeWayDifferenceNavigationError.staleGeneration(
                expected: generation,
                actual: id.generation
            )
        }

        var lower = sourceIDOrderedTargetIndices.startIndex
        var upper = sourceIDOrderedTargetIndices.endIndex
        while lower < upper {
            try budget.consume()
            let middle = lower + (upper - lower) / 2
            let candidate = targets[sourceIDOrderedTargetIndices[middle]]
            if candidate.sourceID.rawValue < id.sourceID.rawValue {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if sourceIDOrderedTargetIndices.indices.contains(lower) {
            let target = targets[sourceIDOrderedTargetIndices[lower]]
            if target.id == id { return target }
        }
        throw ThreeWayDifferenceNavigationError.staleIdentity(role: role, id: id)
    }

    private static func validate(
        _ limits: ThreeWayDifferenceNavigationLimits
    ) throws(ThreeWayDifferenceNavigationError) {
        guard limits.maximumRows >= 0,
            limits.maximumRows <= ThreeWayDifferenceNavigationLimits.maximumSupportedRows,
            limits.maximumDifferences >= 0,
            limits.maximumDifferences
                <= ThreeWayDifferenceNavigationLimits.maximumSupportedDifferences,
            limits.maximumWork >= 0,
            limits.maximumWork <= ThreeWayDifferenceNavigationLimits.maximumSupportedWork,
            limits.cancellationCheckInterval > 0,
            limits.cancellationCheckInterval
                <= ThreeWayDifferenceNavigationLimits.maximumCancellationCheckInterval
        else {
            throw ThreeWayDifferenceNavigationError.invalidLimits
        }
    }

    private static func deterministicallySorted(
        _ differences: [ThreeWayDifferenceNavigationDifference],
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> [ThreeWayDifferenceNavigationDifference] {
        try stableMergeSort(differences, precedes: differencePrecedes, budget: &budget)
    }

    private static func deterministicallySortedIndices(
        _ indices: [Int],
        targets: [ThreeWayDifferenceNavigationTarget],
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> [Int] {
        try stableMergeSort(
            indices,
            precedes: {
                targets[$0].sourceID.rawValue < targets[$1].sourceID.rawValue
            },
            budget: &budget
        )
    }

    private static func stableMergeSort<Element>(
        _ elements: [Element],
        precedes: (Element, Element) -> Bool,
        budget: inout ThreeWayDifferenceNavigationWorkBudget
    ) throws(ThreeWayDifferenceNavigationError) -> [Element] {
        guard elements.count > 1 else { return elements }
        var source = elements
        var destination = elements
        var width = 1
        while width < source.count {
            var lowerBound = source.startIndex
            while lowerBound < source.endIndex {
                let middle = min(lowerBound + width, source.endIndex)
                let upperBound = min(middle + width, source.endIndex)
                var left = lowerBound
                var right = middle
                var output = lowerBound
                while left < middle, right < upperBound {
                    try budget.consume()
                    if precedes(source[right], source[left]) {
                        destination[output] = source[right]
                        right += 1
                    } else {
                        destination[output] = source[left]
                        left += 1
                    }
                    output += 1
                }
                while left < middle {
                    try budget.consume()
                    destination[output] = source[left]
                    left += 1
                    output += 1
                }
                while right < upperBound {
                    try budget.consume()
                    destination[output] = source[right]
                    right += 1
                    output += 1
                }
                lowerBound = upperBound
            }
            swap(&source, &destination)
            let halfCountRoundedUp = source.count / 2 + source.count % 2
            width = width >= halfCountRoundedUp ? source.count : width * 2
        }
        return source
    }

    private static func differencePrecedes(
        _ left: ThreeWayDifferenceNavigationDifference,
        _ right: ThreeWayDifferenceNavigationDifference
    ) -> Bool {
        if left.rowRange.lowerBound != right.rowRange.lowerBound {
            return left.rowRange.lowerBound < right.rowRange.lowerBound
        }
        if left.rowRange.upperBound != right.rowRange.upperBound {
            return left.rowRange.upperBound < right.rowRange.upperBound
        }
        if left.type.sortRank != right.type.sortRank {
            return left.type.sortRank < right.type.sortRank
        }
        return left.id.rawValue < right.id.rawValue
    }

    fileprivate static func checkCancellation() throws(ThreeWayDifferenceNavigationError) {
        if Task.isCancelled {
            throw ThreeWayDifferenceNavigationError.cancelled
        }
    }
}

public typealias ThreeWayDifferenceNavigation = ThreeWayDifferenceNavigationIndex

private struct ThreeWayDifferenceNavigationWorkBudget {
    let limits: ThreeWayDifferenceNavigationLimits
    private(set) var completedWork = 0

    mutating func consume() throws(ThreeWayDifferenceNavigationError) {
        guard completedWork < limits.maximumWork else {
            throw ThreeWayDifferenceNavigationError.workLimitExceeded(
                maximumWork: limits.maximumWork
            )
        }
        completedWork += 1
        if completedWork.isMultiple(of: limits.cancellationCheckInterval) {
            try ThreeWayDifferenceNavigationIndex.checkCancellation()
        }
    }

    func finish() throws(ThreeWayDifferenceNavigationError) {
        try ThreeWayDifferenceNavigationIndex.checkCancellation()
    }
}
