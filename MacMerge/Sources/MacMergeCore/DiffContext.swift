public enum DiffContextMode: Equatable, Sendable {
    case all
    case lines(Int)

    public static let supportedLineCounts = [0, 1, 3, 5, 7, 9]
    public static let zero = DiffContextMode.lines(0)
    public static let one = DiffContextMode.lines(1)
    public static let three = DiffContextMode.lines(3)
    public static let five = DiffContextMode.lines(5)
    public static let seven = DiffContextMode.lines(7)
    public static let nine = DiffContextMode.lines(9)

    public var lineCount: Int? {
        switch self {
        case .all:
            nil
        case .lines(let count):
            count
        }
    }

    public init(lineCount: Int?) {
        if let lineCount {
            precondition(lineCount >= 0, "Diff context line count must not be negative")
            self = .lines(lineCount)
        } else {
            self = .all
        }
    }
}

public struct DiffContext: Equatable, Sendable {
    public private(set) var mode: DiffContextMode
    public private(set) var isInverted: Bool
    public private(set) var lastLimitedLineCount: Int

    public init(
        mode: DiffContextMode = .all,
        isInverted: Bool = false,
        lastLimitedLineCount: Int = 0
    ) {
        precondition(lastLimitedLineCount >= 0, "Diff context line count must not be negative")
        if case .lines(let count) = mode {
            precondition(count >= 0, "Diff context line count must not be negative")
        }
        self.mode = mode
        self.isInverted = isInverted
        self.lastLimitedLineCount = mode.lineCount ?? lastLimitedLineCount
    }

    public init(
        lineCount: Int?,
        isInverted: Bool = false,
        lastLimitedLineCount: Int = 0
    ) {
        self.init(
            mode: DiffContextMode(lineCount: lineCount),
            isInverted: isInverted,
            lastLimitedLineCount: lastLimitedLineCount
        )
    }

    public var lineCount: Int? { mode.lineCount }
    public var isAll: Bool { mode == .all }
    public var canInvert: Bool { !isAll }

    public mutating func setMode(_ mode: DiffContextMode) {
        if case .lines(let count) = mode {
            precondition(count >= 0, "Diff context line count must not be negative")
            lastLimitedLineCount = count
        }
        self.mode = mode
    }

    public mutating func setLineCount(_ lineCount: Int?) {
        setMode(DiffContextMode(lineCount: lineCount))
    }

    public mutating func toggle() {
        mode = isAll ? .lines(lastLimitedLineCount) : .all
    }

    @discardableResult
    public mutating func invert() -> Bool {
        guard canInvert else { return false }
        isInverted.toggle()
        return true
    }

    public func project(_ rows: [DiffRow]) -> DiffContextProjection {
        DiffContextProjection(rows: rows, context: self)
    }
}

public struct DiffContextLineSpan: Equatable, Sendable {
    public let first: Int
    public let last: Int

    public init(first: Int, last: Int) {
        precondition(first > 0, "Diff context line span must use positive 1-based line numbers")
        precondition(first <= last, "Diff context line span must not be reversed")
        self.first = first
        self.last = last
    }

    public var count: Int { last - (first - 1) }
}

public struct DiffContextGap: Identifiable, Equatable, Sendable {
    public let sourceRange: Range<Int>
    public let insertionIndex: Int
    public let leftLines: DiffContextLineSpan?
    public let rightLines: DiffContextLineSpan?

    public init(
        sourceRange: Range<Int>,
        insertionIndex: Int,
        leftLines: DiffContextLineSpan?,
        rightLines: DiffContextLineSpan?
    ) {
        precondition(sourceRange.lowerBound >= 0, "Diff context gap source range must not be negative")
        precondition(
            sourceRange.lowerBound < sourceRange.upperBound,
            "Diff context gap must omit at least one row"
        )
        precondition(insertionIndex >= 0, "Diff context gap insertion index must not be negative")
        self.sourceRange = sourceRange
        self.insertionIndex = insertionIndex
        self.leftLines = leftLines
        self.rightLines = rightLines
    }

    public var id: Range<Int> { sourceRange }
    public var omittedRowCount: Int { sourceRange.upperBound - sourceRange.lowerBound }
}

public struct DiffContextRow: Identifiable, Equatable, Sendable {
    public let sourceIndex: Int
    public let projectedIndex: Int
    public let row: DiffRow

    public init(sourceIndex: Int, projectedIndex: Int, row: DiffRow) {
        precondition(sourceIndex >= 0, "Diff context source index must not be negative")
        precondition(projectedIndex >= 0, "Diff context projected index must not be negative")
        self.sourceIndex = sourceIndex
        self.projectedIndex = projectedIndex
        self.row = row
    }

    public var id: DiffRow.ID { row.id }
}

public enum DiffContextItem: Identifiable, Equatable, Sendable {
    public enum ID: Hashable, Sendable {
        case row(sourceIndex: Int)
        case gap(sourceRange: Range<Int>)
    }

    case row(DiffContextRow)
    case gap(DiffContextGap)

    public var id: ID {
        switch self {
        case .row(let row):
            .row(sourceIndex: row.sourceIndex)
        case .gap(let gap):
            .gap(sourceRange: gap.sourceRange)
        }
    }
}

public struct DiffContextHunk: Identifiable, Equatable, Sendable {
    public let index: Int
    public let sourceRange: Range<Int>
    public let projectedRange: Range<Int>

    public init(index: Int, sourceRange: Range<Int>, projectedRange: Range<Int>) {
        precondition(index >= 0, "Diff context hunk index must not be negative")
        precondition(sourceRange.lowerBound >= 0, "Diff context hunk source range must not be negative")
        precondition(
            sourceRange.lowerBound < sourceRange.upperBound,
            "Diff context hunk must contain at least one row"
        )
        precondition(
            projectedRange.lowerBound >= 0,
            "Diff context hunk projected range must not be negative"
        )
        precondition(!projectedRange.isEmpty, "Diff context hunk must contain at least one projected row")
        self.index = index
        self.sourceRange = sourceRange
        self.projectedRange = projectedRange
    }

    public var id: Int { index }
}

public struct DiffContextSelectionMapping: Equatable, Sendable {
    public let sourceIndex: Int
    public let projectedIndex: Int?
    public let itemIndex: Int
    public let gapIndex: Int?

    public init(
        sourceIndex: Int,
        projectedIndex: Int?,
        itemIndex: Int,
        gapIndex: Int?
    ) {
        precondition(sourceIndex >= 0, "Diff context source index must not be negative")
        precondition(projectedIndex.map { $0 >= 0 } ?? true)
        precondition(itemIndex >= 0, "Diff context item index must not be negative")
        precondition(gapIndex.map { $0 >= 0 } ?? true)
        precondition((projectedIndex == nil) != (gapIndex == nil))
        self.sourceIndex = sourceIndex
        self.projectedIndex = projectedIndex
        self.itemIndex = itemIndex
        self.gapIndex = gapIndex
    }

    public var isVisible: Bool { projectedIndex != nil }
}

public struct DiffContextProjection: Equatable, Sendable {
    public let sourceRowCount: Int
    public let context: DiffContext
    public let rows: [DiffContextRow]
    public let gaps: [DiffContextGap]
    public let hunks: [DiffContextHunk]
    public let items: [DiffContextItem]
    private let sourceIndicesByID: [DiffRow.ID: Int]
    private let usesSequentialEqualRowIDs: Bool

    public init(rows sourceRows: [DiffRow], context: DiffContext) {
        sourceRowCount = sourceRows.count
        self.context = context

        let ranges = Self.visibleRanges(rows: sourceRows, context: context)
        var projectedRows: [DiffContextRow] = []
        var gaps: [DiffContextGap] = []
        var hunks: [DiffContextHunk] = []
        var items: [DiffContextItem] = []
        var sourceIndicesByID: [DiffRow.ID: Int] = [:]
        projectedRows.reserveCapacity(
            ranges.reduce(into: 0) { $0 += $1.upperBound - $1.lowerBound }
        )
        hunks.reserveCapacity(ranges.count)
        items.reserveCapacity(projectedRows.capacity + ranges.count + 1)
        let usesSequentialEqualRowIDs =
            context.lineCount == 0 && ranges.isEmpty
            && sourceRows.indices.allSatisfy { index in
                let id = sourceRows[index].id
                return id.leftNumber == index + 1 && id.rightNumber == index + 1
            }
        if !usesSequentialEqualRowIDs {
            sourceIndicesByID.reserveCapacity(sourceRows.count)
            for (index, row) in sourceRows.enumerated() where sourceIndicesByID[row.id] == nil {
                sourceIndicesByID[row.id] = index
            }
        }

        var sourceIndex = 0
        for sourceRange in ranges {
            if sourceIndex < sourceRange.lowerBound {
                let gap = Self.gap(
                    sourceRange: sourceIndex..<sourceRange.lowerBound,
                    insertionIndex: projectedRows.count,
                    rows: sourceRows
                )
                gaps.append(gap)
                items.append(.gap(gap))
            }

            let projectedStart = projectedRows.count
            for index in sourceRange {
                let row = DiffContextRow(
                    sourceIndex: index,
                    projectedIndex: projectedRows.count,
                    row: sourceRows[index]
                )
                projectedRows.append(row)
                items.append(.row(row))
            }
            hunks.append(
                DiffContextHunk(
                    index: hunks.count,
                    sourceRange: sourceRange,
                    projectedRange: projectedStart..<projectedRows.count
                )
            )
            sourceIndex = sourceRange.upperBound
        }

        if sourceIndex < sourceRows.count {
            let gap = Self.gap(
                sourceRange: sourceIndex..<sourceRows.count,
                insertionIndex: projectedRows.count,
                rows: sourceRows
            )
            gaps.append(gap)
            items.append(.gap(gap))
        }

        self.rows = projectedRows
        self.gaps = gaps
        self.hunks = hunks
        self.items = items
        self.sourceIndicesByID = sourceIndicesByID
        self.usesSequentialEqualRowIDs = usesSequentialEqualRowIDs
    }

    public var isIdentity: Bool { rows.count == sourceRowCount && gaps.isEmpty }
    public var visibleRows: [DiffRow] { rows.map(\.row) }

    public func projectedIndex(forSourceIndex sourceIndex: Int) -> Int? {
        guard sourceIndex >= 0, sourceIndex < sourceRowCount else { return nil }
        var lower = rows.startIndex
        var upper = rows.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if rows[middle].sourceIndex < sourceIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower < rows.endIndex && rows[lower].sourceIndex == sourceIndex ? lower : nil
    }

    public func sourceIndex(forProjectedIndex projectedIndex: Int) -> Int? {
        guard rows.indices.contains(projectedIndex) else { return nil }
        return rows[projectedIndex].sourceIndex
    }

    public func itemIndex(forSourceIndex sourceIndex: Int) -> Int? {
        guard sourceIndex >= 0, sourceIndex < sourceRowCount else { return nil }
        var lower = items.startIndex
        var upper = items.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if items[middle].sourceRange.upperBound <= sourceIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < items.endIndex, items[lower].sourceRange.contains(sourceIndex) else { return nil }
        return lower
    }

    public func sourceIndex(forRowID id: DiffRow.ID) -> Int? {
        if usesSequentialEqualRowIDs,
            let lineNumber = id.leftNumber,
            id.rightNumber == lineNumber,
            lineNumber > 0,
            lineNumber <= sourceRowCount
        {
            return lineNumber - 1
        }
        return sourceIndicesByID[id]
    }

    public func projectedIndex(forRowID id: DiffRow.ID) -> Int? {
        sourceIndex(forRowID: id).flatMap(projectedIndex(forSourceIndex:))
    }

    public func itemIndex(forRowID id: DiffRow.ID) -> Int? {
        sourceIndex(forRowID: id).flatMap(itemIndex(forSourceIndex:))
    }

    public func selection(forSourceIndex sourceIndex: Int) -> DiffContextSelectionMapping? {
        guard let itemIndex = itemIndex(forSourceIndex: sourceIndex) else { return nil }
        if let projectedIndex = projectedIndex(forSourceIndex: sourceIndex) {
            return DiffContextSelectionMapping(
                sourceIndex: sourceIndex,
                projectedIndex: projectedIndex,
                itemIndex: itemIndex,
                gapIndex: nil
            )
        }
        guard let gapIndex = gapIndex(forSourceIndex: sourceIndex) else { return nil }
        return DiffContextSelectionMapping(
            sourceIndex: sourceIndex,
            projectedIndex: nil,
            itemIndex: itemIndex,
            gapIndex: gapIndex
        )
    }

    public func selection(forRowID id: DiffRow.ID) -> DiffContextSelectionMapping? {
        sourceIndex(forRowID: id).flatMap(selection(forSourceIndex:))
    }

    private func gapIndex(forSourceIndex sourceIndex: Int) -> Int? {
        var lower = gaps.startIndex
        var upper = gaps.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if gaps[middle].sourceRange.upperBound <= sourceIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower < gaps.endIndex && gaps[lower].sourceRange.contains(sourceIndex) ? lower : nil
    }

    private static func visibleRanges(rows: [DiffRow], context: DiffContext) -> [Range<Int>] {
        guard !rows.isEmpty else { return [] }
        guard let lineCount = context.lineCount else { return [rows.indices] }

        var ranges: [Range<Int>] = []
        for index in rows.indices where isAnchor(rows[index], inverted: context.isInverted) {
            let linesBefore = index - rows.startIndex
            let linesAfter = rows.endIndex - index - 1
            let lowerBound = lineCount >= linesBefore ? rows.startIndex : index - lineCount
            let upperBound = lineCount >= linesAfter ? rows.endIndex : index + lineCount + 1
            if let lastIndex = ranges.indices.last, lowerBound <= ranges[lastIndex].upperBound {
                ranges[lastIndex] = ranges[lastIndex].lowerBound..<max(ranges[lastIndex].upperBound, upperBound)
            } else {
                ranges.append(lowerBound..<upperBound)
            }
        }
        return ranges
    }

    private static func isAnchor(_ row: DiffRow, inverted: Bool) -> Bool {
        let isDifference = row.kind != .unchanged
        return inverted ? !isDifference : isDifference
    }

    private static func gap(
        sourceRange: Range<Int>,
        insertionIndex: Int,
        rows: [DiffRow]
    ) -> DiffContextGap {
        DiffContextGap(
            sourceRange: sourceRange,
            insertionIndex: insertionIndex,
            leftLines: lineSpan(in: sourceRange, rows: rows, onLeft: true),
            rightLines: lineSpan(in: sourceRange, rows: rows, onLeft: false)
        )
    }

    private static func lineSpan(
        in range: Range<Int>,
        rows: [DiffRow],
        onLeft: Bool
    ) -> DiffContextLineSpan? {
        var first: Int?
        var last: Int?
        for index in range {
            let number = onLeft ? rows[index].id.leftNumber : rows[index].id.rightNumber
            guard let number, number > 0 else { continue }
            first = first.map { min($0, number) } ?? number
            last = last.map { max($0, number) } ?? number
        }
        guard let first, let last else { return nil }
        return DiffContextLineSpan(first: first, last: last)
    }
}

extension DiffContextItem {
    fileprivate var sourceRange: Range<Int> {
        switch self {
        case .row(let row):
            row.sourceIndex..<(row.sourceIndex + 1)
        case .gap(let gap):
            gap.sourceRange
        }
    }
}
