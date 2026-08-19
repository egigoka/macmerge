import Foundation

public enum DifferenceDetailNoDetailReason: Equatable, Sendable {
    case unchanged
    case unpaired
    case noIntralineDifference
    case comparisonLimitExceeded
}

public enum DifferenceDetailState: Equatable, Sendable {
    case absent
    case noDetail(DifferenceDetailNoDetailReason)
    case detail
}

public struct DifferenceDetailSource: Equatable, Sendable {
    public let rowIndex: Int
    public let id: DiffRow.ID
    public let kind: DiffKind
    public let leftLine: DiffLine?
    public let rightLine: DiffLine?

    public init(rowIndex: Int, row: DiffRow) {
        self.rowIndex = rowIndex
        id = row.id
        kind = row.kind
        leftLine = row.left
        rightLine = row.right
    }
}

public struct DifferenceDetailTextFragment: Equatable, Sendable {
    public let text: String
    public let utf16Range: NSRange
    public let isHighlighted: Bool

    public init(text: String, utf16Range: NSRange, isHighlighted: Bool) {
        self.text = text
        self.utf16Range = utf16Range
        self.isHighlighted = isHighlighted
    }
}

public struct DifferenceDetailSide: Equatable, Sendable {
    public let line: DiffLine
    public let highlightRanges: [NSRange]
    public let fragments: [DifferenceDetailTextFragment]

    public var text: String { line.text }

    public init(line: DiffLine, highlightRanges: [NSRange]) {
        self.line = line
        let text = line.text
        guard !highlightRanges.isEmpty else {
            self.highlightRanges = []
            fragments = Self.unhighlightedFragments(in: text)
            return
        }
        let ranges = Self.validatedRanges(highlightRanges, in: text)
        self.highlightRanges = ranges
        fragments = ranges.isEmpty
            ? Self.unhighlightedFragments(in: text)
            : Self.fragments(in: text, highlightRanges: ranges)
    }

    fileprivate static func validatedRanges(_ ranges: [NSRange], in text: String) -> [NSRange] {
        let textLength = text.utf16.count
        var valid: [(range: NSRange, end: Int)] = []
        valid.reserveCapacity(ranges.count)
        for range in ranges {
            guard range.location >= 0,
                  range.location != NSNotFound,
                  range.length >= 0,
                  range.location <= textLength
            else { continue }
            let (end, overflow) = range.location.addingReportingOverflow(range.length)
            guard !overflow, end <= textLength else { continue }
            valid.append((range, end))
        }
        guard !valid.isEmpty else { return [] }

        let boundaries = utf16Boundaries(in: text)
        var clamped: [NSRange] = []
        clamped.reserveCapacity(valid.count)
        for (range, end) in valid {
            let lowerBound = boundary(atOrBefore: range.location, in: boundaries)
            let upperBound = end == range.location
                ? lowerBound
                : boundary(atOrAfter: end, in: boundaries)
            let length = upperBound - lowerBound
            clamped.append(NSRange(location: lowerBound, length: length))
        }
        clamped.sort {
            $0.location == $1.location ? $0.length < $1.length : $0.location < $1.location
        }

        var result: [NSRange] = []
        result.reserveCapacity(clamped.count)
        for range in clamped {
            guard let previous = result.last else {
                result.append(range)
                continue
            }
            let previousEnd = previous.location + previous.length
            let rangeEnd = range.location + range.length
            guard range.location <= previousEnd else {
                result.append(range)
                continue
            }
            result[result.count - 1] = NSRange(
                location: previous.location,
                length: max(previousEnd, rangeEnd) - previous.location
            )
        }
        return result
    }

    private static func unhighlightedFragments(
        in text: String
    ) -> [DifferenceDetailTextFragment] {
        guard !text.isEmpty else { return [] }
        return [DifferenceDetailTextFragment(
            text: text,
            utf16Range: NSRange(location: 0, length: text.utf16.count),
            isHighlighted: false
        )]
    }

    private static func fragments(
        in text: String,
        highlightRanges: [NSRange]
    ) -> [DifferenceDetailTextFragment] {
        let source = text as NSString
        let textLength = source.length
        var result: [DifferenceDetailTextFragment] = []
        result.reserveCapacity(highlightRanges.count * 2 + 1)
        var cursor = 0

        for range in highlightRanges {
            if cursor < range.location {
                let unchanged = NSRange(location: cursor, length: range.location - cursor)
                result.append(DifferenceDetailTextFragment(
                    text: source.substring(with: unchanged),
                    utf16Range: unchanged,
                    isHighlighted: false
                ))
            }
            result.append(DifferenceDetailTextFragment(
                text: source.substring(with: range),
                utf16Range: range,
                isHighlighted: true
            ))
            cursor = range.location + range.length
        }

        if cursor < textLength {
            let unchanged = NSRange(location: cursor, length: textLength - cursor)
            result.append(DifferenceDetailTextFragment(
                text: source.substring(with: unchanged),
                utf16Range: unchanged,
                isHighlighted: false
            ))
        }
        return result
    }

    private static func utf16Boundaries(in text: String) -> [Int] {
        var boundaries = [0]
        boundaries.reserveCapacity(text.count + 1)
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            boundaries.append(offset)
        }
        return boundaries
    }

    private static func boundary(atOrBefore offset: Int, in boundaries: [Int]) -> Int {
        var lower = boundaries.startIndex
        var upper = boundaries.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if boundaries[middle] <= offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return boundaries[max(boundaries.startIndex, lower - 1)]
    }

    private static func boundary(atOrAfter offset: Int, in boundaries: [Int]) -> Int {
        var lower = boundaries.startIndex
        var upper = boundaries.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if boundaries[middle] < offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return boundaries[min(lower, boundaries.index(before: boundaries.endIndex))]
    }
}

public struct DifferenceDetail: Equatable, Sendable {
    private struct GraphemeCodeUnit: Equatable {
        let value: UInt16
        let graphemeOffset: Int
    }

    private static let maximumUTF8Length = 16_384
    private static let maximumUTF16Length = 8_192
    private static let maximumCharacterCount = 2_048

    public let state: DifferenceDetailState
    public let source: DifferenceDetailSource?
    public let left: DifferenceDetailSide?
    public let right: DifferenceDetailSide?
    public let leftMovedLinePair: MovedLinePair?
    public let rightMovedLinePair: MovedLinePair?

    public init(rows: [DiffRow], selectedRowIndex: Int?) {
        self.init(rows: rows, selectedRowIndex: selectedRowIndex, selectedRowID: nil)
    }

    public init(
        rows: [DiffRow],
        selectedRowIndex: Int?,
        selectedRowID: DiffRow.ID?
    ) {
        self.init(
            rows: rows,
            movedLines: MovedLines(),
            selectedRowIndex: selectedRowIndex,
            selectedRowID: selectedRowID
        )
    }

    public init(
        result: LineDiffResult,
        selectedRowIndex: Int?,
        selectedRowID: DiffRow.ID? = nil
    ) {
        self.init(
            rows: result.rows,
            movedLines: result.movedLines,
            selectedRowIndex: selectedRowIndex,
            selectedRowID: selectedRowID
        )
    }

    public init(row: DiffRow?, rowIndex: Int = 0) {
        self.init(
            row: row,
            rowIndex: rowIndex,
            leftMovedLinePair: nil,
            rightMovedLinePair: nil
        )
    }

    private init(
        rows: [DiffRow],
        movedLines: MovedLines,
        selectedRowIndex: Int?,
        selectedRowID: DiffRow.ID?
    ) {
        guard let selectedRowIndex, rows.indices.contains(selectedRowIndex) else {
            self.init(row: nil)
            return
        }
        let row = rows[selectedRowIndex]
        guard selectedRowID.map({ $0 == row.id }) ?? true else {
            self.init(row: nil)
            return
        }

        let movedLinePairs = Self.movedLinePairs(for: row, in: movedLines)
        self.init(
            row: row,
            rowIndex: selectedRowIndex,
            leftMovedLinePair: movedLinePairs.left,
            rightMovedLinePair: movedLinePairs.right
        )
    }

    private init(
        row: DiffRow?,
        rowIndex: Int,
        leftMovedLinePair: MovedLinePair?,
        rightMovedLinePair: MovedLinePair?
    ) {
        guard let row, rowIndex >= 0 else {
            state = .absent
            source = nil
            left = nil
            right = nil
            self.leftMovedLinePair = nil
            self.rightMovedLinePair = nil
            return
        }

        let source = DifferenceDetailSource(rowIndex: rowIndex, row: row)
        self.source = source
        self.leftMovedLinePair = leftMovedLinePair
        self.rightMovedLinePair = rightMovedLinePair

        guard row.kind == .modified else {
            state = .noDetail(row.kind == .unchanged ? .unchanged : .unpaired)
            left = source.leftLine.map { DifferenceDetailSide(line: $0, highlightRanges: []) }
            right = source.rightLine.map { DifferenceDetailSide(line: $0, highlightRanges: []) }
            return
        }
        guard let leftLine = source.leftLine, let rightLine = source.rightLine else {
            state = .noDetail(.unpaired)
            left = source.leftLine.map { DifferenceDetailSide(line: $0, highlightRanges: []) }
            right = source.rightLine.map { DifferenceDetailSide(line: $0, highlightRanges: []) }
            return
        }
        guard !Self.exceedsComparisonLimit(leftLine.text),
              !Self.exceedsComparisonLimit(rightLine.text) else {
            state = .noDetail(.comparisonLimitExceeded)
            left = DifferenceDetailSide(line: leftLine, highlightRanges: [])
            right = DifferenceDetailSide(line: rightLine, highlightRanges: [])
            return
        }

        let (leftRanges, rightRanges) = Self.intralineRanges(
            left: leftLine.text,
            right: rightLine.text
        )
        guard !leftRanges.isEmpty || !rightRanges.isEmpty else {
            state = .noDetail(.noIntralineDifference)
            left = DifferenceDetailSide(line: leftLine, highlightRanges: [])
            right = DifferenceDetailSide(line: rightLine, highlightRanges: [])
            return
        }

        state = .detail
        left = DifferenceDetailSide(line: leftLine, highlightRanges: leftRanges)
        right = DifferenceDetailSide(line: rightLine, highlightRanges: rightRanges)
    }

    private static func movedLinePairs(
        for row: DiffRow,
        in movedLines: MovedLines
    ) -> (left: MovedLinePair?, right: MovedLinePair?) {
        let rowID = row.id
        let leftPair = rowID.leftNumber.flatMap { leftLine in
            movedLines.rightLine(forLeftLine: leftLine).map {
                MovedLinePair(leftLine: leftLine, rightLine: $0)
            }
        }
        let rightPair = rowID.rightNumber.flatMap { rightLine in
            movedLines.leftLine(forRightLine: rightLine).map {
                MovedLinePair(leftLine: $0, rightLine: rightLine)
            }
        }
        return resolveMovedLinePairs(
            rowID: rowID,
            leftPair: leftPair,
            rightPair: rightPair,
            leftToRightCount: movedLines.leftToRightCount,
            leftToRightPair: movedLines.leftToRightPair,
            rightToLeftCount: movedLines.rightToLeftCount,
            rightToLeftPair: movedLines.rightToLeftPair
        )
    }

    static func resolveMovedLinePairs(
        rowID: DiffRow.ID,
        leftPair initialLeftPair: MovedLinePair?,
        rightPair initialRightPair: MovedLinePair?,
        leftToRightCount: Int,
        leftToRightPair: (Int) -> MovedLinePair,
        rightToLeftCount: Int,
        rightToLeftPair: (Int) -> MovedLinePair
    ) -> (left: MovedLinePair?, right: MovedLinePair?) {
        var leftPair = initialLeftPair
        var rightPair = initialRightPair
        if leftPair == nil, let leftLine = rowID.leftNumber {
            for index in 0..<rightToLeftCount {
                let pair = rightToLeftPair(index)
                if pair.leftLine == leftLine {
                    leftPair = pair
                    break
                }
            }
        }
        if rightPair == nil, let rightLine = rowID.rightNumber {
            for index in 0..<leftToRightCount {
                let pair = leftToRightPair(index)
                if pair.rightLine == rightLine {
                    rightPair = pair
                    break
                }
            }
        }
        return (leftPair, rightPair)
    }

    private static func exceedsComparisonLimit(_ text: String) -> Bool {
        text.utf8.prefix(maximumUTF8Length + 1).count > maximumUTF8Length
            || text.utf16.prefix(maximumUTF16Length + 1).count > maximumUTF16Length
            || text.prefix(maximumCharacterCount + 1).count > maximumCharacterCount
    }

    private static func intralineRanges(
        left: String,
        right: String
    ) -> (left: [NSRange], right: [NSRange]) {
        guard !left.utf8.elementsEqual(right.utf8) else { return ([], []) }

        let leftGraphemes = utf16Graphemes(in: left)
        let rightGraphemes = utf16Graphemes(in: right)
        let difference = rightGraphemes.slices
            .difference(from: leftGraphemes.slices)
            .inferringMoves()
        var leftRemovals = Array(repeating: false, count: leftGraphemes.slices.count)
        var associatedLeftRemovals = leftRemovals
        var rightInsertions = Array(repeating: false, count: rightGraphemes.slices.count)
        var associatedRightInsertions = rightInsertions
        for change in difference {
            switch change {
            case .insert(let offset, _, let associatedWith):
                guard rightInsertions.indices.contains(offset) else { return ([], []) }
                rightInsertions[offset] = true
                associatedRightInsertions[offset] = associatedWith != nil
            case .remove(let offset, _, let associatedWith):
                guard leftRemovals.indices.contains(offset) else { return ([], []) }
                leftRemovals[offset] = true
                associatedLeftRemovals[offset] = associatedWith != nil
            }
        }
        var runStart = 0
        while runStart < rightGraphemes.slices.count {
            var runEnd = runStart + 1
            while runEnd < rightGraphemes.slices.count,
                  rightGraphemes.slices[runEnd] == rightGraphemes.slices[runStart] {
                runEnd += 1
            }
            let insertionCount = rightInsertions[runStart..<runEnd].count(where: { $0 })
            let associatedCount = associatedRightInsertions[runStart..<runEnd]
                .count(where: { $0 })
            if insertionCount > 0 {
                for offset in runStart..<runEnd {
                    rightInsertions[offset] = offset >= runEnd - insertionCount
                    associatedRightInsertions[offset] = offset >= runEnd - associatedCount
                }
            }
            runStart = runEnd
        }

        var leftOffset = 0
        var rightOffset = 0
        var leftChanges: [(offset: Int, length: Int)] = []
        var rightChanges: [(offset: Int, length: Int)] = []
        while leftOffset < leftGraphemes.slices.count
            || rightOffset < rightGraphemes.slices.count {
            if associatedLeftRemovals.indices.contains(leftOffset),
               associatedLeftRemovals[leftOffset] {
                leftChanges.append((
                    leftGraphemes.boundaries[leftOffset],
                    leftGraphemes.slices[leftOffset].count
                ))
                leftOffset += 1
            } else if associatedRightInsertions.indices.contains(rightOffset),
                      associatedRightInsertions[rightOffset] {
                rightChanges.append((
                    rightGraphemes.boundaries[rightOffset],
                    rightGraphemes.slices[rightOffset].count
                ))
                rightOffset += 1
            } else if leftRemovals.indices.contains(leftOffset) && leftRemovals[leftOffset]
                || rightInsertions.indices.contains(rightOffset) && rightInsertions[rightOffset] {
                let leftStart = leftOffset
                let rightStart = rightOffset
                while leftRemovals.indices.contains(leftOffset),
                      leftRemovals[leftOffset],
                      !associatedLeftRemovals[leftOffset] {
                    leftOffset += 1
                }
                while rightInsertions.indices.contains(rightOffset),
                      rightInsertions[rightOffset],
                      !associatedRightInsertions[rightOffset] {
                    rightOffset += 1
                }
                let changes = exactCodeUnitChanges(
                    left: leftGraphemes.slices[leftStart..<leftOffset],
                    right: rightGraphemes.slices[rightStart..<rightOffset],
                    leftBase: leftGraphemes.boundaries[leftStart],
                    rightBase: rightGraphemes.boundaries[rightStart]
                )
                leftChanges.append(contentsOf: changes.left)
                rightChanges.append(contentsOf: changes.right)
            } else {
                guard leftOffset < leftGraphemes.slices.count,
                      rightOffset < rightGraphemes.slices.count,
                      leftGraphemes.slices[leftOffset] == rightGraphemes.slices[rightOffset]
                else { return ([], []) }
                leftOffset += 1
                rightOffset += 1
            }
        }

        return (
            ranges(for: leftChanges, in: left),
            ranges(for: rightChanges, in: right)
        )
    }

    private static func utf16Graphemes(
        in text: String
    ) -> (slices: [[UInt16]], boundaries: [Int]) {
        var slices: [[UInt16]] = []
        var boundaries = [0]
        slices.reserveCapacity(text.count)
        boundaries.reserveCapacity(text.count + 1)
        for character in text {
            let slice = Array(String(character).utf16)
            slices.append(slice)
            boundaries.append(boundaries[boundaries.count - 1] + slice.count)
        }
        return (slices, boundaries)
    }

    private static func exactCodeUnitChanges(
        left: ArraySlice<[UInt16]>,
        right: ArraySlice<[UInt16]>,
        leftBase: Int,
        rightBase: Int
    ) -> (left: [(offset: Int, length: Int)], right: [(offset: Int, length: Int)]) {
        let leftCodeUnits = left.enumerated().flatMap { graphemeOffset, slice in
            slice.map { GraphemeCodeUnit(value: $0, graphemeOffset: graphemeOffset) }
        }
        let rightCodeUnits = right.enumerated().flatMap { graphemeOffset, slice in
            slice.map { GraphemeCodeUnit(value: $0, graphemeOffset: graphemeOffset) }
        }
        let difference = rightCodeUnits.difference(from: leftCodeUnits)
        var leftRemovals = Array(repeating: false, count: leftCodeUnits.count)
        var rightInsertions = Array(repeating: false, count: rightCodeUnits.count)
        for change in difference {
            switch change {
            case .insert(let offset, _, _):
                rightInsertions[offset] = true
            case .remove(let offset, _, _):
                leftRemovals[offset] = true
            }
        }

        var leftOffset = 0
        var rightOffset = 0
        var leftChanges: [(offset: Int, length: Int)] = []
        var rightChanges: [(offset: Int, length: Int)] = []
        while leftOffset < leftCodeUnits.count || rightOffset < rightCodeUnits.count {
            if leftRemovals.indices.contains(leftOffset), leftRemovals[leftOffset] {
                leftChanges.append((leftBase + leftOffset, 1))
                rightChanges.append((rightBase + rightOffset, 0))
                leftOffset += 1
            } else if rightInsertions.indices.contains(rightOffset), rightInsertions[rightOffset] {
                leftChanges.append((leftBase + leftOffset, 0))
                rightChanges.append((rightBase + rightOffset, 1))
                rightOffset += 1
            } else {
                guard leftOffset < leftCodeUnits.count,
                      rightOffset < rightCodeUnits.count,
                      leftCodeUnits[leftOffset] == rightCodeUnits[rightOffset]
                else { return ([], []) }
                leftOffset += 1
                rightOffset += 1
            }
        }
        return (leftChanges, rightChanges)
    }

    private static func ranges(
        for changes: [(offset: Int, length: Int)],
        in text: String
    ) -> [NSRange] {
        let textLength = text.utf16.count
        var ranges: [NSRange] = []
        var rangeStart: Int?
        var rangeEnd = 0
        func appendRange() {
            guard let rangeStart else { return }
            ranges.append(NSRange(location: rangeStart, length: rangeEnd - rangeStart))
        }
        for change in changes {
            guard change.offset >= 0, change.length >= 0 else { return [] }
            let (end, overflow) = change.offset.addingReportingOverflow(change.length)
            guard !overflow, end <= textLength else { return [] }
            if rangeStart != nil {
                if change.offset <= rangeEnd {
                    rangeEnd = max(rangeEnd, end)
                } else {
                    appendRange()
                    rangeStart = change.offset
                    rangeEnd = end
                }
            } else {
                rangeStart = change.offset
                rangeEnd = end
            }
        }
        appendRange()
        return DifferenceDetailSide.validatedRanges(ranges, in: text)
    }
}
