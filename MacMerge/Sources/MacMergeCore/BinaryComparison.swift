import Foundation

public struct BinaryComparisonOptions: Equatable, Sendable {
    public let maximumExactEditDistance: Int
    public let maximumAlignmentWork: Int

    public init(
        maximumExactEditDistance: Int = 2_048,
        maximumAlignmentWork: Int = 16 * 1_024 * 1_024
    ) {
        precondition(maximumExactEditDistance >= 0, "Maximum edit distance must not be negative")
        precondition(maximumAlignmentWork >= 0, "Maximum alignment work must not be negative")
        self.maximumExactEditDistance = maximumExactEditDistance
        self.maximumAlignmentWork = maximumAlignmentWork
    }
}

public enum BinaryComparisonAlignment: Equatable, Sendable {
    case exact
    case boundedFallback
}

public struct BinaryDiffRun: Equatable, Sendable {
    public let kind: DiffKind
    public let alignedRange: Range<Int>
    public let leftRange: Range<Int>
    public let rightRange: Range<Int>

    fileprivate init(
        kind: DiffKind,
        alignedRange: Range<Int>,
        leftRange: Range<Int>,
        rightRange: Range<Int>
    ) {
        self.kind = kind
        self.alignedRange = alignedRange
        self.leftRange = leftRange
        self.rightRange = rightRange
    }
}

public struct BinaryByteCell: Equatable, Sendable {
    public let alignedOffset: Int
    public let kind: DiffKind
    public let leftOffset: Int?
    public let rightOffset: Int?
    public let leftByte: UInt8?
    public let rightByte: UInt8?
}

public struct BinarySourceOffsets: Equatable, Sendable {
    public let left: Int
    public let right: Int
}

public struct BinaryComparisonResult: Equatable, Sendable {
    public let leftData: Data
    public let rightData: Data
    public let runs: [BinaryDiffRun]
    public let alignment: BinaryComparisonAlignment
    public let alignedByteCount: Int

    fileprivate init(
        leftData: Data,
        rightData: Data,
        runs: [BinaryDiffRun],
        alignment: BinaryComparisonAlignment
    ) {
        self.leftData = leftData
        self.rightData = rightData
        self.runs = runs
        self.alignment = alignment
        alignedByteCount = runs.last?.alignedRange.upperBound ?? 0
    }

    public func byte(atAlignedOffset offset: Int) -> BinaryByteCell? {
        guard let run = run(containing: offset) else { return nil }
        let position = offset - run.alignedRange.lowerBound
        let leftOffset = run.leftRange.isEmpty ? nil : run.leftRange.lowerBound + position
        let rightOffset = run.rightRange.isEmpty ? nil : run.rightRange.lowerBound + position
        return BinaryByteCell(
            alignedOffset: offset,
            kind: run.kind,
            leftOffset: leftOffset,
            rightOffset: rightOffset,
            leftByte: leftOffset.map { byte(in: leftData, at: $0) },
            rightByte: rightOffset.map { byte(in: rightData, at: $0) }
        )
    }

    public func sourceOffsets(atAlignedOffset offset: Int) -> BinarySourceOffsets? {
        guard let run = run(containing: offset) else { return nil }
        let position = offset - run.alignedRange.lowerBound
        switch run.kind {
        case .unchanged, .modified:
            return BinarySourceOffsets(
                left: run.leftRange.lowerBound + position,
                right: run.rightRange.lowerBound + position
            )
        case .removed:
            return BinarySourceOffsets(
                left: run.leftRange.lowerBound + position,
                right: run.rightRange.lowerBound
            )
        case .added:
            return BinarySourceOffsets(
                left: run.leftRange.lowerBound,
                right: run.rightRange.lowerBound + position
            )
        }
    }

    private func run(containing offset: Int) -> BinaryDiffRun? {
        guard offset >= 0, offset < alignedByteCount else { return nil }
        var lowerBound = 0
        var upperBound = runs.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if runs[middle].alignedRange.upperBound <= offset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        guard lowerBound < runs.count, runs[lowerBound].alignedRange.contains(offset) else { return nil }
        return runs[lowerBound]
    }

    private func byte(in data: Data, at offset: Int) -> UInt8 {
        data[data.index(data.startIndex, offsetBy: offset)]
    }
}

public enum BinaryComparison {
    public static func compare(
        left: Data,
        right: Data,
        options: BinaryComparisonOptions = BinaryComparisonOptions()
    ) -> BinaryComparisonResult {
        let commonPrefixCount = commonPrefixCount(left, right)
        let commonSuffixCount = commonSuffixCount(left, right, excludingPrefix: commonPrefixCount)
        let leftMiddleCount = left.count - commonPrefixCount - commonSuffixCount
        let rightMiddleCount = right.count - commonPrefixCount - commonSuffixCount
        var runs: [BinaryDiffRun] = []
        var alignedOffset = 0

        appendRun(
            kind: .unchanged,
            leftCount: commonPrefixCount,
            rightCount: commonPrefixCount,
            leftOffset: 0,
            rightOffset: 0,
            alignedOffset: &alignedOffset,
            to: &runs
        )

        let exactAtoms = exactEditAtoms(
            left: left,
            right: right,
            leftOffset: commonPrefixCount,
            rightOffset: commonPrefixCount,
            leftCount: leftMiddleCount,
            rightCount: rightMiddleCount,
            options: options
        )
        appendAtoms(
            exactAtoms ?? [
                EditAtom(kind: .removed, count: leftMiddleCount),
                EditAtom(kind: .added, count: rightMiddleCount)
            ],
            leftOffset: commonPrefixCount,
            rightOffset: commonPrefixCount,
            alignedOffset: &alignedOffset,
            to: &runs
        )

        appendRun(
            kind: .unchanged,
            leftCount: commonSuffixCount,
            rightCount: commonSuffixCount,
            leftOffset: left.count - commonSuffixCount,
            rightOffset: right.count - commonSuffixCount,
            alignedOffset: &alignedOffset,
            to: &runs
        )

        return BinaryComparisonResult(
            leftData: left,
            rightData: right,
            runs: runs,
            alignment: exactAtoms == nil ? .boundedFallback : .exact
        )
    }

    private enum EditKind {
        case equal
        case removed
        case added
    }

    private struct EditAtom {
        let kind: EditKind
        let count: Int
    }

    private static func exactEditAtoms(
        left: Data,
        right: Data,
        leftOffset: Int,
        rightOffset: Int,
        leftCount: Int,
        rightCount: Int,
        options: BinaryComparisonOptions
    ) -> [EditAtom]? {
        if leftCount == 0 { return rightCount == 0 ? [] : [EditAtom(kind: .added, count: rightCount)] }
        if rightCount == 0 { return [EditAtom(kind: .removed, count: leftCount)] }

        let maximumDistance = min(options.maximumExactEditDistance, leftCount + rightCount)
        var trace: [[Int]] = []
        var previous: [Int] = []
        var remainingWork = options.maximumAlignmentWork

        for distance in 0...maximumDistance {
            var current = [Int](repeating: 0, count: distance + 1)
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                guard remainingWork > 0 else { return nil }
                remainingWork -= 1

                var x: Int
                if distance == 0 {
                    x = 0
                } else if diagonal == -distance {
                    x = frontierValue(previous, distance: distance - 1, diagonal: diagonal + 1)
                } else if diagonal == distance {
                    x = frontierValue(previous, distance: distance - 1, diagonal: diagonal - 1) + 1
                } else {
                    let removedX = frontierValue(previous, distance: distance - 1, diagonal: diagonal - 1)
                    let addedX = frontierValue(previous, distance: distance - 1, diagonal: diagonal + 1)
                    x = removedX < addedX ? addedX : removedX + 1
                }
                var y = x - diagonal

                while x < leftCount, y < rightCount {
                    guard remainingWork > 0 else { return nil }
                    remainingWork -= 1
                    guard byte(in: left, at: leftOffset + x) == byte(in: right, at: rightOffset + y) else { break }
                    x += 1
                    y += 1
                }
                current[(diagonal + distance) / 2] = x
                if x >= leftCount, y >= rightCount {
                    trace.append(current)
                    return backtrack(trace: trace, leftCount: leftCount, rightCount: rightCount)
                }
            }
            trace.append(current)
            previous = current
        }
        return nil
    }

    private static func backtrack(
        trace: [[Int]],
        leftCount: Int,
        rightCount: Int
    ) -> [EditAtom] {
        var x = leftCount
        var y = rightCount
        var reversed: [EditAtom] = []
        let finalDistance = trace.count - 1

        if finalDistance > 0 {
            for distance in stride(from: finalDistance, through: 1, by: -1) {
                let previous = trace[distance - 1]
                let diagonal = x - y
                let previousDiagonal: Int
                if diagonal == -distance
                    || (diagonal != distance
                        && frontierValue(previous, distance: distance - 1, diagonal: diagonal - 1)
                            < frontierValue(previous, distance: distance - 1, diagonal: diagonal + 1))
                {
                    previousDiagonal = diagonal + 1
                } else {
                    previousDiagonal = diagonal - 1
                }
                let previousX = frontierValue(previous, distance: distance - 1, diagonal: previousDiagonal)
                let previousY = previousX - previousDiagonal
                let equalCount = min(x - previousX, y - previousY)
                appendReversedAtom(kind: .equal, count: equalCount, to: &reversed)
                x -= equalCount
                y -= equalCount

                if x == previousX {
                    appendReversedAtom(kind: .added, count: 1, to: &reversed)
                    y -= 1
                } else {
                    appendReversedAtom(kind: .removed, count: 1, to: &reversed)
                    x -= 1
                }
            }
        }
        appendReversedAtom(kind: .equal, count: min(x, y), to: &reversed)
        return reversed.reversed()
    }

    private static func appendReversedAtom(
        kind: EditKind,
        count: Int,
        to atoms: inout [EditAtom]
    ) {
        guard count > 0 else { return }
        if let last = atoms.last, last.kind == kind {
            atoms[atoms.count - 1] = EditAtom(kind: kind, count: last.count + count)
        } else {
            atoms.append(EditAtom(kind: kind, count: count))
        }
    }

    private static func appendAtoms(
        _ atoms: [EditAtom],
        leftOffset: Int,
        rightOffset: Int,
        alignedOffset: inout Int,
        to runs: inout [BinaryDiffRun]
    ) {
        var leftOffset = leftOffset
        var rightOffset = rightOffset
        var index = 0
        while index < atoms.count {
            let atom = atoms[index]
            if atom.kind == .equal {
                appendRun(
                    kind: .unchanged,
                    leftCount: atom.count,
                    rightCount: atom.count,
                    leftOffset: leftOffset,
                    rightOffset: rightOffset,
                    alignedOffset: &alignedOffset,
                    to: &runs
                )
                leftOffset += atom.count
                rightOffset += atom.count
                index += 1
                continue
            }

            var removedCount = 0
            var addedCount = 0
            while index < atoms.count, atoms[index].kind != .equal {
                switch atoms[index].kind {
                case .equal:
                    break
                case .removed:
                    removedCount += atoms[index].count
                case .added:
                    addedCount += atoms[index].count
                }
                index += 1
            }
            let modifiedCount = min(removedCount, addedCount)
            appendRun(
                kind: .modified,
                leftCount: modifiedCount,
                rightCount: modifiedCount,
                leftOffset: leftOffset,
                rightOffset: rightOffset,
                alignedOffset: &alignedOffset,
                to: &runs
            )
            leftOffset += modifiedCount
            rightOffset += modifiedCount
            appendRun(
                kind: .removed,
                leftCount: removedCount - modifiedCount,
                rightCount: 0,
                leftOffset: leftOffset,
                rightOffset: rightOffset,
                alignedOffset: &alignedOffset,
                to: &runs
            )
            leftOffset += removedCount - modifiedCount
            appendRun(
                kind: .added,
                leftCount: 0,
                rightCount: addedCount - modifiedCount,
                leftOffset: leftOffset,
                rightOffset: rightOffset,
                alignedOffset: &alignedOffset,
                to: &runs
            )
            rightOffset += addedCount - modifiedCount
        }
    }

    private static func appendRun(
        kind: DiffKind,
        leftCount: Int,
        rightCount: Int,
        leftOffset: Int,
        rightOffset: Int,
        alignedOffset: inout Int,
        to runs: inout [BinaryDiffRun]
    ) {
        let alignedCount = max(leftCount, rightCount)
        guard alignedCount > 0 else { return }
        let run = BinaryDiffRun(
            kind: kind,
            alignedRange: alignedOffset..<(alignedOffset + alignedCount),
            leftRange: leftOffset..<(leftOffset + leftCount),
            rightRange: rightOffset..<(rightOffset + rightCount)
        )
        if let last = runs.last,
            last.kind == run.kind,
            last.alignedRange.upperBound == run.alignedRange.lowerBound,
            last.leftRange.upperBound == run.leftRange.lowerBound,
            last.rightRange.upperBound == run.rightRange.lowerBound
        {
            runs[runs.count - 1] = BinaryDiffRun(
                kind: kind,
                alignedRange: last.alignedRange.lowerBound..<run.alignedRange.upperBound,
                leftRange: last.leftRange.lowerBound..<run.leftRange.upperBound,
                rightRange: last.rightRange.lowerBound..<run.rightRange.upperBound
            )
        } else {
            runs.append(run)
        }
        alignedOffset += alignedCount
    }

    private static func commonPrefixCount(_ left: Data, _ right: Data) -> Int {
        let maximum = min(left.count, right.count)
        var count = 0
        while count < maximum, byte(in: left, at: count) == byte(in: right, at: count) {
            count += 1
        }
        return count
    }

    private static func commonSuffixCount(
        _ left: Data,
        _ right: Data,
        excludingPrefix prefixCount: Int
    ) -> Int {
        let maximum = min(left.count, right.count) - prefixCount
        var count = 0
        while count < maximum,
            byte(in: left, at: left.count - count - 1) == byte(in: right, at: right.count - count - 1)
        {
            count += 1
        }
        return count
    }

    private static func frontierValue(
        _ frontier: [Int],
        distance: Int,
        diagonal: Int
    ) -> Int {
        frontier[(diagonal + distance) / 2]
    }

    private static func byte(in data: Data, at offset: Int) -> UInt8 {
        data[data.index(data.startIndex, offsetBy: offset)]
    }
}
