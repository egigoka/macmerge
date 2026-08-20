import Foundation

public enum ThreeWayBinaryComparisonSource: String, CaseIterable, Equatable, Hashable, Sendable {
    case base
    case left
    case right
}

public struct ThreeWayBinaryComparisonOptions: Equatable, Sendable {
    public static let `default` = ThreeWayBinaryComparisonOptions()

    public let maximumInputBytes: Int
    public let maximumExactEditDistance: Int
    public let maximumAlignmentWork: Int
    public let maximumRegions: Int
    public let maximumOutputBytes: Int

    public init(
        maximumInputBytes: Int = 64 * 1_024 * 1_024,
        maximumExactEditDistance: Int = 2_048,
        maximumAlignmentWork: Int = 32 * 1_024 * 1_024,
        maximumRegions: Int = 1_048_576,
        maximumOutputBytes: Int = 192 * 1_024 * 1_024
    ) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumExactEditDistance = maximumExactEditDistance
        self.maximumAlignmentWork = maximumAlignmentWork
        self.maximumRegions = maximumRegions
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public enum ThreeWayBinaryComparisonError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case inputTooLarge(source: ThreeWayBinaryComparisonSource, maximumBytes: Int)
    case alignmentLimitExceeded(source: ThreeWayBinaryComparisonSource)
    case tooManyRegions(maximumRegions: Int)
    case outputTooLarge(maximumBytes: Int)
    case invalidAlignment
    case integerOverflow
    case invalidResolutionRegion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Three-way binary comparison limits must not be negative."
        case .inputTooLarge(let source, let maximumBytes):
            "Three-way binary comparison \(source.rawValue) input exceeds the \(maximumBytes)-byte limit."
        case .alignmentLimitExceeded(let source):
            "Three-way binary comparison could not align the \(source.rawValue) input within the configured limits."
        case .tooManyRegions(let maximumRegions):
            "Three-way binary comparison exceeds the \(maximumRegions)-region limit."
        case .outputTooLarge(let maximumBytes):
            "Three-way binary comparison output exceeds the \(maximumBytes)-byte limit."
        case .invalidAlignment:
            "Three-way binary comparison produced an invalid byte alignment."
        case .integerOverflow:
            "Three-way binary comparison exceeded supported integer bounds."
        case .invalidResolutionRegion(let id):
            "Three-way binary comparison region \(id) is not a conflict that can be resolved."
        }
    }
}

public enum ThreeWayBinaryComparisonResolution: Equatable, Sendable {
    case unchanged
    case left
    case right
    case identical
    case conflict

    public var isConflict: Bool { self == .conflict }
}

public enum ThreeWayBinaryComparisonConflictChoice: Equatable, Sendable {
    case base
    case left
    case right
}

public struct ThreeWayBinaryComparisonEquality: Equatable, Sendable {
    public let leftEqualsBase: Bool
    public let rightEqualsBase: Bool
    public let leftEqualsRight: Bool

    public init(
        leftEqualsBase: Bool,
        rightEqualsBase: Bool,
        leftEqualsRight: Bool
    ) {
        self.leftEqualsBase = leftEqualsBase
        self.rightEqualsBase = rightEqualsBase
        self.leftEqualsRight = leftEqualsRight
    }
}

public struct ThreeWayBinaryComparisonRegion: Identifiable, Equatable, Sendable {
    public let id: Int
    public let alignedRange: Range<Int>
    public let baseRange: Range<Int>
    public let leftRange: Range<Int>
    public let rightRange: Range<Int>
    public let resolution: ThreeWayBinaryComparisonResolution
    public let equality: ThreeWayBinaryComparisonEquality

    public var isConflict: Bool { resolution.isConflict }
    public var leftEqualsBase: Bool { equality.leftEqualsBase }
    public var rightEqualsBase: Bool { equality.rightEqualsBase }
    public var leftEqualsRight: Bool { equality.leftEqualsRight }

    public var automaticSource: ThreeWayBinaryComparisonSource? {
        switch resolution {
        case .unchanged:
            .base
        case .left, .identical:
            .left
        case .right:
            .right
        case .conflict:
            nil
        }
    }

    fileprivate init(
        id: Int,
        alignedRange: Range<Int>,
        baseRange: Range<Int>,
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        resolution: ThreeWayBinaryComparisonResolution,
        equality: ThreeWayBinaryComparisonEquality
    ) {
        self.id = id
        self.alignedRange = alignedRange
        self.baseRange = baseRange
        self.leftRange = leftRange
        self.rightRange = rightRange
        self.resolution = resolution
        self.equality = equality
    }
}

public struct ThreeWayBinaryComparisonResult: Equatable, Sendable {
    public let baseData: Data
    public let leftData: Data
    public let rightData: Data
    public let regions: [ThreeWayBinaryComparisonRegion]
    public let conflicts: [ThreeWayBinaryComparisonRegion]
    public let equality: ThreeWayBinaryComparisonEquality
    public let mergedData: Data?
    public let alignedByteCount: Int
    private let maximumOutputBytes: Int

    public var hasConflicts: Bool { !conflicts.isEmpty }
    public var isIdentical: Bool { leftEqualsBase && rightEqualsBase }
    public var leftEqualsBase: Bool { equality.leftEqualsBase }
    public var rightEqualsBase: Bool { equality.rightEqualsBase }
    public var leftEqualsRight: Bool { equality.leftEqualsRight }

    fileprivate init(
        baseData: Data,
        leftData: Data,
        rightData: Data,
        regions: [ThreeWayBinaryComparisonRegion],
        equality: ThreeWayBinaryComparisonEquality,
        maximumOutputBytes: Int
    ) throws {
        self.baseData = baseData
        self.leftData = leftData
        self.rightData = rightData
        self.regions = regions
        self.equality = equality
        self.maximumOutputBytes = maximumOutputBytes
        alignedByteCount = regions.last?.alignedRange.upperBound ?? 0

        var conflicts: [ThreeWayBinaryComparisonRegion] = []
        for (index, region) in regions.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if region.isConflict { conflicts.append(region) }
        }
        self.conflicts = conflicts
        mergedData = conflicts.isEmpty
            ? try Self.buildData(
                base: baseData,
                left: leftData,
                right: rightData,
                regions: regions,
                choices: [:],
                maximumBytes: maximumOutputBytes
            )
            : nil
    }

    public func data(
        resolvingConflictsWith choices: [Int: ThreeWayBinaryComparisonConflictChoice]
    ) throws -> Data? {
        try Task.checkCancellation()
        var minimumInvalidID: Int?
        for (index, id) in choices.keys.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if id < 0 || id >= regions.count || regions[id].id != id || !regions[id].isConflict {
                minimumInvalidID = min(minimumInvalidID ?? id, id)
            }
        }
        if let minimumInvalidID {
            throw ThreeWayBinaryComparisonError.invalidResolutionRegion(minimumInvalidID)
        }
        for (index, conflict) in conflicts.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard choices[conflict.id] != nil else { return nil }
        }
        return try Self.buildData(
            base: baseData,
            left: leftData,
            right: rightData,
            regions: regions,
            choices: choices,
            maximumBytes: maximumOutputBytes
        )
    }

    private static func buildData(
        base: Data,
        left: Data,
        right: Data,
        regions: [ThreeWayBinaryComparisonRegion],
        choices: [Int: ThreeWayBinaryComparisonConflictChoice],
        maximumBytes: Int
    ) throws -> Data {
        func selection(
            for region: ThreeWayBinaryComparisonRegion
        ) throws -> (Data, Range<Int>) {
            let selectedSource: ThreeWayBinaryComparisonSource
            if let automaticSource = region.automaticSource {
                selectedSource = automaticSource
            } else {
                guard let choice = choices[region.id] else {
                    throw ThreeWayBinaryComparisonError.invalidResolutionRegion(region.id)
                }
                selectedSource = switch choice {
                case .base: .base
                case .left: .left
                case .right: .right
                }
            }
            return switch selectedSource {
            case .base: (base, region.baseRange)
            case .left: (left, region.leftRange)
            case .right: (right, region.rightRange)
            }
        }

        var outputCount = 0
        for (index, region) in regions.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let selection = try selection(for: region)
            guard selection.1.count <= maximumBytes - outputCount else {
                throw ThreeWayBinaryComparisonError.outputTooLarge(maximumBytes: maximumBytes)
            }
            outputCount += selection.1.count
        }

        var output = Data()
        output.reserveCapacity(outputCount)
        for (index, region) in regions.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let selection = try selection(for: region)
            try append(selection.0, range: selection.1, to: &output)
        }
        guard output.count == outputCount else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        return output
    }

    private static func append(_ source: Data, range: Range<Int>, to output: inout Data) throws {
        guard range.lowerBound >= 0, range.upperBound <= source.count else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        var offset = range.lowerBound
        while offset < range.upperBound {
            try Task.checkCancellation()
            let chunkCount = min(64 * 1_024, range.upperBound - offset)
            let chunkEnd = offset + chunkCount
            let lowerIndex = source.index(source.startIndex, offsetBy: offset)
            let upperIndex = source.index(source.startIndex, offsetBy: chunkEnd)
            output.append(contentsOf: source[lowerIndex..<upperIndex])
            offset = chunkEnd
        }
    }
}

public enum ThreeWayBinaryComparison: Sendable {
    public static func compare(
        base: Data,
        left: Data,
        right: Data,
        options: ThreeWayBinaryComparisonOptions = .default
    ) throws -> ThreeWayBinaryComparisonResult {
        try validate(options)
        try Task.checkCancellation()
        try validateInput(base, source: .base, maximumBytes: options.maximumInputBytes)
        try validateInput(left, source: .left, maximumBytes: options.maximumInputBytes)
        try validateInput(right, source: .right, maximumBytes: options.maximumInputBytes)

        var remainingWork = options.maximumAlignmentWork
        let leftDiff = try sideDiff(
            base: base,
            side: left,
            source: .left,
            maximumDistance: options.maximumExactEditDistance,
            remainingWork: &remainingWork
        )
        let rightDiff = try sideDiff(
            base: base,
            side: right,
            source: .right,
            maximumDistance: options.maximumExactEditDistance,
            remainingWork: &remainingWork
        )
        let regionBuilders = try regionBuilders(
            base: base,
            left: left,
            right: right,
            leftDiff: leftDiff,
            rightDiff: rightDiff,
            options: options
        )

        var regions: [ThreeWayBinaryComparisonRegion] = []
        regions.reserveCapacity(regionBuilders.count)
        var potentialOutputBytes = 0
        for (index, builder) in regionBuilders.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let candidateByteCount: Int = switch builder.resolution {
            case .unchanged:
                builder.baseRange.count
            case .left, .identical:
                builder.leftRange.count
            case .right:
                builder.rightRange.count
            case .conflict:
                max(builder.baseRange.count, builder.leftRange.count, builder.rightRange.count)
            }
            guard candidateByteCount <= options.maximumOutputBytes - potentialOutputBytes else {
                throw ThreeWayBinaryComparisonError.outputTooLarge(
                    maximumBytes: options.maximumOutputBytes
                )
            }
            potentialOutputBytes += candidateByteCount
            regions.append(
                ThreeWayBinaryComparisonRegion(
                    id: index,
                    alignedRange: builder.alignedRange,
                    baseRange: builder.baseRange,
                    leftRange: builder.leftRange,
                    rightRange: builder.rightRange,
                    resolution: builder.resolution,
                    equality: builder.equality
                ))
        }

        let leftEqualsBase = leftDiff.changes.isEmpty
        let rightEqualsBase = rightDiff.changes.isEmpty
        let leftEqualsRight = leftEqualsBase && rightEqualsBase
            ? true
            : try rangesAreEqual(left, 0..<left.count, right, 0..<right.count)
        return try ThreeWayBinaryComparisonResult(
            baseData: base,
            leftData: left,
            rightData: right,
            regions: regions,
            equality: ThreeWayBinaryComparisonEquality(
                leftEqualsBase: leftEqualsBase,
                rightEqualsBase: rightEqualsBase,
                leftEqualsRight: leftEqualsRight
            ),
            maximumOutputBytes: options.maximumOutputBytes
        )
    }

    private enum EditKind: Equatable {
        case equal
        case removed
        case added
    }

    private struct EditAtom {
        let kind: EditKind
        let count: Int
    }

    private struct Change {
        let baseRange: Range<Int>
        let sideRange: Range<Int>
    }

    private struct SideDiff {
        let changes: [Change]
        let insertionBoundaries: Set<Int>
    }

    private struct SideMap {
        let insertions: [Range<Int>]
        let bytes: [Range<Int>]
    }

    private struct RegionBuilder {
        let alignedRange: Range<Int>
        let baseRange: Range<Int>
        let leftRange: Range<Int>
        let rightRange: Range<Int>
        let resolution: ThreeWayBinaryComparisonResolution
        let equality: ThreeWayBinaryComparisonEquality
    }

    private static func validate(_ options: ThreeWayBinaryComparisonOptions) throws {
        guard options.maximumInputBytes >= 0,
              options.maximumExactEditDistance >= 0,
              options.maximumAlignmentWork >= 0,
              options.maximumRegions >= 0,
              options.maximumOutputBytes >= 0 else {
            throw ThreeWayBinaryComparisonError.invalidLimits
        }
    }

    private static func validateInput(
        _ data: Data,
        source: ThreeWayBinaryComparisonSource,
        maximumBytes: Int
    ) throws {
        guard data.count <= maximumBytes else {
            throw ThreeWayBinaryComparisonError.inputTooLarge(
                source: source,
                maximumBytes: maximumBytes
            )
        }
    }

    private static func sideDiff(
        base: Data,
        side: Data,
        source: ThreeWayBinaryComparisonSource,
        maximumDistance: Int,
        remainingWork: inout Int
    ) throws -> SideDiff {
        let prefixCount = try commonPrefixCount(base, side)
        let suffixCount = try commonSuffixCount(base, side, excludingPrefix: prefixCount)
        let baseMiddleCount = try subtract(base.count, prefixCount, suffixCount)
        let sideMiddleCount = try subtract(side.count, prefixCount, suffixCount)
        guard baseMiddleCount > 0 || sideMiddleCount > 0 else {
            return SideDiff(changes: [], insertionBoundaries: [])
        }

        let atoms = try exactEditAtoms(
            base: base,
            side: side,
            baseOffset: prefixCount,
            sideOffset: prefixCount,
            baseCount: baseMiddleCount,
            sideCount: sideMiddleCount,
            source: source,
            maximumDistance: maximumDistance,
            remainingWork: &remainingWork
        )
        var changes: [Change] = []
        var baseOffset = prefixCount
        var sideOffset = prefixCount
        var changeStart: (base: Int, side: Int)?

        func finishChange() {
            guard let start = changeStart else { return }
            changes.append(
                Change(
                    baseRange: start.base..<baseOffset,
                    sideRange: start.side..<sideOffset
                ))
            changeStart = nil
        }

        for (index, atom) in atoms.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if atom.kind == .equal {
                finishChange()
            } else if changeStart == nil {
                changeStart = (baseOffset, sideOffset)
            }
            switch atom.kind {
            case .equal:
                baseOffset = try add(baseOffset, atom.count)
                sideOffset = try add(sideOffset, atom.count)
            case .removed:
                baseOffset = try add(baseOffset, atom.count)
            case .added:
                sideOffset = try add(sideOffset, atom.count)
            }
        }
        finishChange()
        let expectedBaseOffset = try subtract(base.count, suffixCount)
        let expectedSideOffset = try subtract(side.count, suffixCount)
        guard baseOffset == expectedBaseOffset, sideOffset == expectedSideOffset else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }

        var insertionBoundaries: Set<Int> = []
        insertionBoundaries.reserveCapacity(changes.count)
        for change in changes where change.sideRange.count > change.baseRange.count {
            insertionBoundaries.insert(change.baseRange.upperBound)
        }
        return SideDiff(changes: changes, insertionBoundaries: insertionBoundaries)
    }

    private static func exactEditAtoms(
        base: Data,
        side: Data,
        baseOffset: Int,
        sideOffset: Int,
        baseCount: Int,
        sideCount: Int,
        source: ThreeWayBinaryComparisonSource,
        maximumDistance: Int,
        remainingWork: inout Int
    ) throws -> [EditAtom] {
        let totalCount = try add(baseCount, sideCount)
        let maximumDistance = min(maximumDistance, totalCount)
        let minimumDistance = abs(baseCount - sideCount)
        guard minimumDistance <= maximumDistance else {
            throw ThreeWayBinaryComparisonError.alignmentLimitExceeded(source: source)
        }
        if baseCount == 0 || sideCount == 0 {
            let editCount = max(baseCount, sideCount)
            guard editCount <= maximumDistance, remainingWork > 0 else {
                throw ThreeWayBinaryComparisonError.alignmentLimitExceeded(source: source)
            }
            remainingWork -= 1
            try Task.checkCancellation()
            return [EditAtom(kind: baseCount == 0 ? .added : .removed, count: editCount)]
        }

        var trace: [[Int]] = []
        var previous: [Int] = []
        for distance in 0...maximumDistance {
            try Task.checkCancellation()
            let frontierCount = try add(distance, 1)
            var current = [Int](repeating: 0, count: frontierCount)
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                guard remainingWork > 0 else {
                    throw ThreeWayBinaryComparisonError.alignmentLimitExceeded(source: source)
                }
                remainingWork -= 1

                var x: Int
                if distance == 0 {
                    x = 0
                } else if diagonal == -distance {
                    x = try frontierValue(previous, distance: distance - 1, diagonal: diagonal + 1)
                } else if diagonal == distance {
                    x = try add(
                        try frontierValue(previous, distance: distance - 1, diagonal: diagonal - 1),
                        1
                    )
                } else {
                    let removedX = try frontierValue(
                        previous,
                        distance: distance - 1,
                        diagonal: diagonal - 1
                    )
                    let addedX = try frontierValue(
                        previous,
                        distance: distance - 1,
                        diagonal: diagonal + 1
                    )
                    x = removedX < addedX ? addedX : try add(removedX, 1)
                }
                let y = try subtract(x, diagonal)
                guard x >= 0, y >= 0 else {
                    throw ThreeWayBinaryComparisonError.invalidAlignment
                }
                var matchedCount = 0
                var scanX = x
                var scanY = y
                while scanX < baseCount, scanY < sideCount {
                    if matchedCount.isMultiple(of: 64 * 1_024) {
                        try Task.checkCancellation()
                    }
                    guard remainingWork > 0 else {
                        throw ThreeWayBinaryComparisonError.alignmentLimitExceeded(source: source)
                    }
                    remainingWork -= 1
                    guard byte(in: base, at: try add(baseOffset, scanX))
                        == byte(in: side, at: try add(sideOffset, scanY)) else { break }
                    scanX = try add(scanX, 1)
                    scanY = try add(scanY, 1)
                    matchedCount += 1
                }
                let frontierIndex = try add(diagonal, distance) / 2
                guard current.indices.contains(frontierIndex) else {
                    throw ThreeWayBinaryComparisonError.invalidAlignment
                }
                current[frontierIndex] = scanX
                if scanX >= baseCount, scanY >= sideCount {
                    trace.append(current)
                    return try backtrack(trace: trace, baseCount: baseCount, sideCount: sideCount)
                }
            }
            trace.append(current)
            previous = current
        }
        throw ThreeWayBinaryComparisonError.alignmentLimitExceeded(source: source)
    }

    private static func backtrack(
        trace: [[Int]],
        baseCount: Int,
        sideCount: Int
    ) throws -> [EditAtom] {
        guard !trace.isEmpty else { throw ThreeWayBinaryComparisonError.invalidAlignment }
        var x = baseCount
        var y = sideCount
        var reversed: [EditAtom] = []
        let finalDistance = trace.count - 1

        if finalDistance > 0 {
            for distance in stride(from: finalDistance, through: 1, by: -1) {
                if distance.isMultiple(of: 4_096) { try Task.checkCancellation() }
                let previous = trace[distance - 1]
                let diagonal = try subtract(x, y)
                let previousDiagonal: Int
                if diagonal == -distance {
                    previousDiagonal = diagonal + 1
                } else if diagonal == distance {
                    previousDiagonal = diagonal - 1
                } else {
                    let removedX = try frontierValue(
                        previous,
                        distance: distance - 1,
                        diagonal: diagonal - 1
                    )
                    let addedX = try frontierValue(
                        previous,
                        distance: distance - 1,
                        diagonal: diagonal + 1
                    )
                    previousDiagonal = removedX < addedX ? diagonal + 1 : diagonal - 1
                }
                let previousX = try frontierValue(
                    previous,
                    distance: distance - 1,
                    diagonal: previousDiagonal
                )
                let previousY = try subtract(previousX, previousDiagonal)
                guard previousX >= 0, previousY >= 0, previousX <= x, previousY <= y else {
                    throw ThreeWayBinaryComparisonError.invalidAlignment
                }
                let equalCount = min(x - previousX, y - previousY)
                try appendReversedAtom(kind: .equal, count: equalCount, to: &reversed)
                x -= equalCount
                y -= equalCount

                if x == previousX {
                    guard y > 0 else { throw ThreeWayBinaryComparisonError.invalidAlignment }
                    try appendReversedAtom(kind: .added, count: 1, to: &reversed)
                    y -= 1
                } else {
                    guard x > 0 else { throw ThreeWayBinaryComparisonError.invalidAlignment }
                    try appendReversedAtom(kind: .removed, count: 1, to: &reversed)
                    x -= 1
                }
            }
        }
        guard x == y, x >= 0 else { throw ThreeWayBinaryComparisonError.invalidAlignment }
        try appendReversedAtom(kind: .equal, count: x, to: &reversed)
        return reversed.reversed()
    }

    private static func appendReversedAtom(
        kind: EditKind,
        count: Int,
        to atoms: inout [EditAtom]
    ) throws {
        guard count > 0 else { return }
        if let last = atoms.last, last.kind == kind {
            atoms[atoms.count - 1] = EditAtom(kind: kind, count: try add(last.count, count))
        } else {
            atoms.append(EditAtom(kind: kind, count: count))
        }
    }

    private static func regionBuilders(
        base: Data,
        left: Data,
        right: Data,
        leftDiff: SideDiff,
        rightDiff: SideDiff,
        options: ThreeWayBinaryComparisonOptions
    ) throws -> [RegionBuilder] {
        let leftChanges = leftDiff.changes
        let rightChanges = rightDiff.changes
        var builders: [RegionBuilder] = []
        var alignedOffset = 0
        var leftChangeIndex = 0
        var rightChangeIndex = 0
        var basePosition = 0
        var leftPosition = 0
        var rightPosition = 0

        func appendRegion(
            baseRange: Range<Int>,
            leftRange: Range<Int>,
            rightRange: Range<Int>,
            knownResolution: ThreeWayBinaryComparisonResolution? = nil
        ) throws {
            guard valid(baseRange, in: base), valid(leftRange, in: left), valid(rightRange, in: right) else {
                throw ThreeWayBinaryComparisonError.invalidAlignment
            }
            let classification = try classify(
                base: base,
                baseRange: baseRange,
                left: left,
                leftRange: leftRange,
                right: right,
                rightRange: rightRange
            )
            if let knownResolution, classification.0 != knownResolution {
                throw ThreeWayBinaryComparisonError.invalidAlignment
            }
            let alignedCount = max(baseRange.count, leftRange.count, rightRange.count)
            guard alignedCount > 0 else { return }
            let alignedEnd = try add(alignedOffset, alignedCount)

            if let last = builders.last,
               last.resolution == classification.0,
               last.baseRange.count == last.leftRange.count,
               last.baseRange.count == last.rightRange.count,
               baseRange.count == leftRange.count,
               baseRange.count == rightRange.count,
               last.baseRange.upperBound == baseRange.lowerBound,
               last.leftRange.upperBound == leftRange.lowerBound,
               last.rightRange.upperBound == rightRange.lowerBound,
               last.alignedRange.upperBound == alignedOffset {
                builders[builders.count - 1] = RegionBuilder(
                    alignedRange: last.alignedRange.lowerBound..<alignedEnd,
                    baseRange: last.baseRange.lowerBound..<baseRange.upperBound,
                    leftRange: last.leftRange.lowerBound..<leftRange.upperBound,
                    rightRange: last.rightRange.lowerBound..<rightRange.upperBound,
                    resolution: classification.0,
                    equality: classification.1
                )
            } else {
                guard builders.count < options.maximumRegions else {
                    throw ThreeWayBinaryComparisonError.tooManyRegions(
                        maximumRegions: options.maximumRegions
                    )
                }
                builders.append(
                    RegionBuilder(
                        alignedRange: alignedOffset..<alignedEnd,
                        baseRange: baseRange,
                        leftRange: leftRange,
                        rightRange: rightRange,
                        resolution: classification.0,
                        equality: classification.1
                    ))
            }
            alignedOffset = alignedEnd
        }

        func appendResolvedCluster(
            baseRange: Range<Int>,
            leftRange: Range<Int>,
            rightRange: Range<Int>,
            leftChanges: [Change],
            rightChanges: [Change]
        ) throws {
            let classification = try classify(
                base: base,
                baseRange: baseRange,
                left: left,
                leftRange: leftRange,
                right: right,
                rightRange: rightRange
            )
            guard classification.0 == .conflict else {
                try appendRegion(
                    baseRange: baseRange,
                    leftRange: leftRange,
                    rightRange: rightRange,
                    knownResolution: classification.0
                )
                return
            }

            let leftMap = try sideMap(
                baseRange: baseRange,
                sideRange: leftRange,
                changes: leftChanges
            )
            let rightMap = try sideMap(
                baseRange: baseRange,
                sideRange: rightRange,
                changes: rightChanges
            )
            for boundaryOffset in 0...baseRange.count {
                if boundaryOffset.isMultiple(of: 4_096) { try Task.checkCancellation() }
                let boundary = baseRange.lowerBound + boundaryOffset
                let leftInsertion = leftMap.insertions[boundaryOffset]
                let rightInsertion = rightMap.insertions[boundaryOffset]
                if !leftInsertion.isEmpty || !rightInsertion.isEmpty {
                    try appendRegion(
                        baseRange: boundary..<boundary,
                        leftRange: leftInsertion,
                        rightRange: rightInsertion
                    )
                }
                guard boundaryOffset < baseRange.count else { continue }
                try appendRegion(
                    baseRange: boundary..<(boundary + 1),
                    leftRange: leftMap.bytes[boundaryOffset],
                    rightRange: rightMap.bytes[boundaryOffset]
                )
            }
        }

        while leftChangeIndex < leftChanges.count || rightChangeIndex < rightChanges.count {
            try Task.checkCancellation()
            let chooseLeft = nextChangeIsLeft(
                left: element(leftChanges, at: leftChangeIndex),
                right: element(rightChanges, at: rightChangeIndex)
            )
            let first: Change
            var clusterLeftChanges: [Change] = []
            var clusterRightChanges: [Change] = []
            if chooseLeft {
                first = leftChanges[leftChangeIndex]
                clusterLeftChanges.append(first)
                leftChangeIndex += 1
            } else {
                first = rightChanges[rightChangeIndex]
                clusterRightChanges.append(first)
                rightChangeIndex += 1
            }

            let clusterStart = first.baseRange.lowerBound
            var clusterEnd = first.baseRange.upperBound
            guard clusterStart >= basePosition else {
                throw ThreeWayBinaryComparisonError.invalidAlignment
            }
            let gapCount = clusterStart - basePosition
            if gapCount > 0 {
                let leftEnd = try add(leftPosition, gapCount)
                let rightEnd = try add(rightPosition, gapCount)
                try appendRegion(
                    baseRange: basePosition..<clusterStart,
                    leftRange: leftPosition..<leftEnd,
                    rightRange: rightPosition..<rightEnd,
                    knownResolution: .unchanged
                )
                basePosition = clusterStart
                leftPosition = leftEnd
                rightPosition = rightEnd
            }

            var addedChange = true
            while addedChange {
                addedChange = false
                if let change = element(leftChanges, at: leftChangeIndex),
                   overlapsOrSharesInsertion(
                    change.baseRange,
                    clusterStart..<clusterEnd,
                    leftInsertions: leftDiff.insertionBoundaries,
                    rightInsertions: rightDiff.insertionBoundaries
                   ) {
                    clusterLeftChanges.append(change)
                    clusterEnd = max(clusterEnd, change.baseRange.upperBound)
                    leftChangeIndex += 1
                    addedChange = true
                }
                if let change = element(rightChanges, at: rightChangeIndex),
                   overlapsOrSharesInsertion(
                    change.baseRange,
                    clusterStart..<clusterEnd,
                    leftInsertions: leftDiff.insertionBoundaries,
                    rightInsertions: rightDiff.insertionBoundaries
                   ) {
                    clusterRightChanges.append(change)
                    clusterEnd = max(clusterEnd, change.baseRange.upperBound)
                    rightChangeIndex += 1
                    addedChange = true
                }
            }

            let baseRange = clusterStart..<clusterEnd
            let leftEnd = try sideEnd(
                start: leftPosition,
                baseRange: baseRange,
                changes: clusterLeftChanges,
                sideCount: left.count
            )
            let rightEnd = try sideEnd(
                start: rightPosition,
                baseRange: baseRange,
                changes: clusterRightChanges,
                sideCount: right.count
            )
            try appendResolvedCluster(
                baseRange: baseRange,
                leftRange: leftPosition..<leftEnd,
                rightRange: rightPosition..<rightEnd,
                leftChanges: clusterLeftChanges,
                rightChanges: clusterRightChanges
            )
            basePosition = clusterEnd
            leftPosition = leftEnd
            rightPosition = rightEnd
        }

        let trailingCount = base.count - basePosition
        guard trailingCount >= 0,
              leftPosition <= left.count - trailingCount,
              rightPosition <= right.count - trailingCount,
              leftPosition + trailingCount == left.count,
              rightPosition + trailingCount == right.count else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        if trailingCount > 0 {
            try appendRegion(
                baseRange: basePosition..<base.count,
                leftRange: leftPosition..<left.count,
                rightRange: rightPosition..<right.count,
                knownResolution: .unchanged
            )
        }
        return builders
    }

    private static func sideMap(
        baseRange: Range<Int>,
        sideRange: Range<Int>,
        changes: [Change]
    ) throws -> SideMap {
        let insertionCount = try add(baseRange.count, 1)
        var insertions = [Range<Int>?](repeating: nil, count: insertionCount)
        var bytes = [Range<Int>?](repeating: nil, count: baseRange.count)
        var basePosition = baseRange.lowerBound
        var sidePosition = sideRange.lowerBound

        func mapUnchangedByte() throws {
            let localIndex = basePosition - baseRange.lowerBound
            guard bytes.indices.contains(localIndex), sidePosition < sideRange.upperBound else {
                throw ThreeWayBinaryComparisonError.invalidAlignment
            }
            if insertions[localIndex] == nil {
                insertions[localIndex] = sidePosition..<sidePosition
            }
            bytes[localIndex] = sidePosition..<(sidePosition + 1)
            basePosition += 1
            sidePosition += 1
        }

        for (index, change) in changes.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard change.baseRange.lowerBound >= basePosition,
                  change.baseRange.upperBound <= baseRange.upperBound,
                  change.sideRange.lowerBound >= sidePosition,
                  change.sideRange.upperBound <= sideRange.upperBound else {
                throw ThreeWayBinaryComparisonError.invalidAlignment
            }
            while basePosition < change.baseRange.lowerBound {
                try mapUnchangedByte()
            }
            guard sidePosition == change.sideRange.lowerBound else {
                throw ThreeWayBinaryComparisonError.invalidAlignment
            }

            let pairedCount = min(change.baseRange.count, change.sideRange.count)
            for pairOffset in 0..<pairedCount {
                let localIndex = basePosition - baseRange.lowerBound
                if pairOffset.isMultiple(of: 4_096) { try Task.checkCancellation() }
                if insertions[localIndex] == nil {
                    insertions[localIndex] = sidePosition..<sidePosition
                }
                bytes[localIndex] = sidePosition..<(sidePosition + 1)
                basePosition += 1
                sidePosition += 1
            }
            while basePosition < change.baseRange.upperBound {
                let localIndex = basePosition - baseRange.lowerBound
                if insertions[localIndex] == nil {
                    insertions[localIndex] = sidePosition..<sidePosition
                }
                bytes[localIndex] = sidePosition..<sidePosition
                basePosition += 1
            }
            let insertionIndex = basePosition - baseRange.lowerBound
            guard insertions.indices.contains(insertionIndex) else {
                throw ThreeWayBinaryComparisonError.invalidAlignment
            }
            insertions[insertionIndex] = sidePosition..<change.sideRange.upperBound
            sidePosition = change.sideRange.upperBound
        }
        while basePosition < baseRange.upperBound {
            try mapUnchangedByte()
        }
        let finalInsertionIndex = basePosition - baseRange.lowerBound
        if insertions[finalInsertionIndex] == nil {
            insertions[finalInsertionIndex] = sidePosition..<sidePosition
        }
        guard sidePosition == sideRange.upperBound,
              insertions.allSatisfy({ $0 != nil }),
              bytes.allSatisfy({ $0 != nil }) else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        return SideMap(
            insertions: insertions.map { $0 ?? 0..<0 },
            bytes: bytes.map { $0 ?? 0..<0 }
        )
    }

    private static func classify(
        base: Data,
        baseRange: Range<Int>,
        left: Data,
        leftRange: Range<Int>,
        right: Data,
        rightRange: Range<Int>
    ) throws -> (ThreeWayBinaryComparisonResolution, ThreeWayBinaryComparisonEquality) {
        let leftEqualsBase = try rangesAreEqual(left, leftRange, base, baseRange)
        let rightEqualsBase = try rangesAreEqual(right, rightRange, base, baseRange)
        let leftEqualsRight = try rangesAreEqual(left, leftRange, right, rightRange)
        let resolution: ThreeWayBinaryComparisonResolution
        if leftEqualsRight {
            resolution = leftEqualsBase ? .unchanged : .identical
        } else if leftEqualsBase {
            resolution = .right
        } else if rightEqualsBase {
            resolution = .left
        } else {
            resolution = .conflict
        }
        return (
            resolution,
            ThreeWayBinaryComparisonEquality(
                leftEqualsBase: leftEqualsBase,
                rightEqualsBase: rightEqualsBase,
                leftEqualsRight: leftEqualsRight
            )
        )
    }

    private static func rangesAreEqual(
        _ left: Data,
        _ leftRange: Range<Int>,
        _ right: Data,
        _ rightRange: Range<Int>
    ) throws -> Bool {
        guard valid(leftRange, in: left), valid(rightRange, in: right) else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        guard leftRange.count == rightRange.count else { return false }
        for offset in 0..<leftRange.count {
            if offset.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
            if byte(in: left, at: leftRange.lowerBound + offset)
                != byte(in: right, at: rightRange.lowerBound + offset) {
                return false
            }
        }
        return true
    }

    private static func sideEnd(
        start: Int,
        baseRange: Range<Int>,
        changes: [Change],
        sideCount: Int
    ) throws -> Int {
        var count = baseRange.count
        for (index, change) in changes.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let delta = change.sideRange.count - change.baseRange.count
            let result = count.addingReportingOverflow(delta)
            guard !result.overflow else { throw ThreeWayBinaryComparisonError.integerOverflow }
            count = result.partialValue
        }
        guard count >= 0, start >= 0, start <= sideCount - count else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        return try add(start, count)
    }

    private static func nextChangeIsLeft(left: Change?, right: Change?) -> Bool {
        guard let left else { return false }
        guard let right else { return true }
        if left.baseRange.lowerBound != right.baseRange.lowerBound {
            return left.baseRange.lowerBound < right.baseRange.lowerBound
        }
        if left.baseRange.isEmpty != right.baseRange.isEmpty {
            return left.baseRange.isEmpty
        }
        return true
    }

    private static func overlapsOrSharesInsertion(
        _ change: Range<Int>,
        _ cluster: Range<Int>,
        leftInsertions: Set<Int>,
        rightInsertions: Set<Int>
    ) -> Bool {
        if cluster.isEmpty { return change.lowerBound == cluster.lowerBound }
        if change.isEmpty {
            return change.lowerBound >= cluster.lowerBound && change.lowerBound <= cluster.upperBound
        }
        if change.lowerBound < cluster.upperBound && change.upperBound > cluster.lowerBound {
            return true
        }
        guard change.lowerBound == cluster.upperBound else { return false }
        return leftInsertions.contains(change.lowerBound) || rightInsertions.contains(change.lowerBound)
    }

    private static func commonPrefixCount(_ left: Data, _ right: Data) throws -> Int {
        let maximum = min(left.count, right.count)
        var count = 0
        while count < maximum {
            if count.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
            guard byte(in: left, at: count) == byte(in: right, at: count) else { break }
            count += 1
        }
        return count
    }

    private static func commonSuffixCount(
        _ left: Data,
        _ right: Data,
        excludingPrefix prefixCount: Int
    ) throws -> Int {
        let maximum = min(left.count, right.count) - prefixCount
        var count = 0
        while count < maximum {
            if count.isMultiple(of: 64 * 1_024) { try Task.checkCancellation() }
            guard byte(in: left, at: left.count - count - 1)
                == byte(in: right, at: right.count - count - 1) else { break }
            count += 1
        }
        return count
    }

    private static func frontierValue(
        _ frontier: [Int],
        distance: Int,
        diagonal: Int
    ) throws -> Int {
        guard distance >= 0,
              diagonal >= -distance,
              diagonal <= distance,
              try add(diagonal, distance).isMultiple(of: 2) else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        let index = try add(diagonal, distance) / 2
        guard frontier.indices.contains(index) else {
            throw ThreeWayBinaryComparisonError.invalidAlignment
        }
        return frontier[index]
    }

    private static func valid(_ range: Range<Int>, in data: Data) -> Bool {
        range.lowerBound >= 0
            && range.upperBound >= range.lowerBound
            && range.upperBound <= data.count
    }

    private static func element<T>(_ values: [T], at index: Int) -> T? {
        values.indices.contains(index) ? values[index] : nil
    }

    private static func byte(in data: Data, at offset: Int) -> UInt8 {
        data[data.index(data.startIndex, offsetBy: offset)]
    }

    private static func add(_ left: Int, _ right: Int) throws -> Int {
        let result = left.addingReportingOverflow(right)
        guard !result.overflow else { throw ThreeWayBinaryComparisonError.integerOverflow }
        return result.partialValue
    }

    private static func subtract(_ left: Int, _ right: Int) throws -> Int {
        let result = left.subtractingReportingOverflow(right)
        guard !result.overflow else { throw ThreeWayBinaryComparisonError.integerOverflow }
        return result.partialValue
    }

    private static func subtract(_ value: Int, _ first: Int, _ second: Int) throws -> Int {
        try subtract(subtract(value, first), second)
    }
}
