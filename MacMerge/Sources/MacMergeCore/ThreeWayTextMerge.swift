import Foundation

public enum ThreeWayTextMergeSource: String, CaseIterable, Equatable, Hashable, Sendable {
    case base
    case left
    case right
}

public struct ThreeWayTextMergeLine: Identifiable, Equatable, Sendable {
    public struct ID: Equatable, Hashable, Sendable {
        public let source: ThreeWayTextMergeSource
        public let number: Int

        public init(source: ThreeWayTextMergeSource, number: Int) {
            self.source = source
            self.number = number
        }
    }

    public let id: ID
    public let text: String
    public let lineEnding: LineEnding?

    public var source: ThreeWayTextMergeSource { id.source }
    public var number: Int { id.number }
    public var hasLineEnding: Bool { lineEnding != nil }

    public init(id: ID, text: String, lineEnding: LineEnding?) {
        self.id = id
        self.text = text
        self.lineEnding = lineEnding
    }

}

public struct ThreeWayTextMergeDocument: Equatable, Sendable {
    public let source: ThreeWayTextMergeSource
    public let lines: [ThreeWayTextMergeLine]
    public let predominantLineEnding: LineEnding?
    private let serializedText: String

    public var hasFinalNewline: Bool { lines.last?.hasLineEnding == true }
    public var text: String { serializedText }

    fileprivate init(
        text: String,
        source: ThreeWayTextMergeSource,
        maximumBytes: Int,
        maximumLines: Int
    ) throws {
        guard text.utf8.count <= maximumBytes else {
            throw ThreeWayTextMergeError.inputTooLarge(source: source, maximumBytes: maximumBytes)
        }

        var lines: [ThreeWayTextMergeLine] = []
        lines.reserveCapacity(min(maximumLines, 4_096))
        let scalars = text.unicodeScalars
        var lineStart = scalars.startIndex
        var index = lineStart
        var inspectedScalars = 0

        while index < scalars.endIndex {
            if inspectedScalars.isMultiple(of: 4_096) {
                try Task.checkCancellation()
            }
            inspectedScalars += 1

            let scalar = scalars[index]
            let lineEnding: LineEnding
            let terminatorEnd: String.UnicodeScalarView.Index
            if scalar.value == 0x0D {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next].value == 0x0A {
                    lineEnding = .crlf
                    terminatorEnd = scalars.index(after: next)
                } else {
                    lineEnding = .cr
                    terminatorEnd = next
                }
            } else if scalar.value == 0x0A {
                lineEnding = .lf
                terminatorEnd = scalars.index(after: index)
            } else {
                index = scalars.index(after: index)
                continue
            }

            guard lines.count < maximumLines else {
                throw ThreeWayTextMergeError.tooManyLines(
                    source: source,
                    maximumLines: maximumLines
                )
            }
            lines.append(
                ThreeWayTextMergeLine(
                    id: .init(source: source, number: lines.count + 1),
                    text: String(scalars[lineStart..<index]),
                    lineEnding: lineEnding
                ))
            index = terminatorEnd
            lineStart = index
        }

        if lineStart < scalars.endIndex {
            guard lines.count < maximumLines else {
                throw ThreeWayTextMergeError.tooManyLines(
                    source: source,
                    maximumLines: maximumLines
                )
            }
            lines.append(
                ThreeWayTextMergeLine(
                    id: .init(source: source, number: lines.count + 1),
                    text: String(scalars[lineStart..<scalars.endIndex]),
                    lineEnding: nil
                ))
        }

        self.source = source
        self.lines = lines
        serializedText = text
        predominantLineEnding = try Self.predominantLineEnding(in: lines)
    }

    private static func predominantLineEnding(
        in lines: [ThreeWayTextMergeLine]
    ) throws -> LineEnding? {
        var counts: [LineEnding: Int] = [:]
        var firstSeen: [LineEnding] = []
        for (index, line) in lines.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard let lineEnding = line.lineEnding else { continue }
            if counts[lineEnding] == nil { firstSeen.append(lineEnding) }
            counts[lineEnding, default: 0] += 1
        }
        return firstSeen.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }
}

public struct ThreeWayTextMergeOptions: Equatable, Sendable {
    public let diffAlgorithm: DiffAlgorithm
    public let maximumInputBytes: Int
    public let maximumInputLines: Int
    public let maximumOutputBytes: Int
    public let maximumOutputLines: Int
    public let maximumRegions: Int

    public init(
        diffAlgorithm: DiffAlgorithm = .default,
        maximumInputBytes: Int = 64 * 1024 * 1024,
        maximumInputLines: Int = 1024 * 1024,
        maximumOutputBytes: Int = 192 * 1024 * 1024,
        maximumOutputLines: Int = 3 * 1024 * 1024,
        maximumRegions: Int = 3 * 1024 * 1024 + 1
    ) {
        precondition(maximumInputBytes >= 0, "Maximum input size must not be negative")
        precondition(maximumInputLines >= 0, "Maximum input line count must not be negative")
        precondition(maximumOutputBytes >= 0, "Maximum output size must not be negative")
        precondition(maximumOutputLines >= 0, "Maximum output line count must not be negative")
        precondition(maximumRegions >= 0, "Maximum region count must not be negative")
        self.diffAlgorithm = diffAlgorithm
        self.maximumInputBytes = maximumInputBytes
        self.maximumInputLines = maximumInputLines
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumOutputLines = maximumOutputLines
        self.maximumRegions = maximumRegions
    }
}

public enum ThreeWayTextMergeError: Error, LocalizedError, Equatable, Sendable {
    case inputTooLarge(source: ThreeWayTextMergeSource, maximumBytes: Int)
    case tooManyLines(source: ThreeWayTextMergeSource, maximumLines: Int)
    case outputTooLarge(maximumBytes: Int)
    case tooManyOutputLines(maximumLines: Int)
    case tooManyRegions(maximumRegions: Int)
    case invalidDiffResult

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge(let source, let maximumBytes):
            "Three-way merge \(source.rawValue) input exceeds the \(maximumBytes)-byte limit."
        case .tooManyLines(let source, let maximumLines):
            "Three-way merge \(source.rawValue) input exceeds the \(maximumLines)-line limit."
        case .outputTooLarge(let maximumBytes):
            "Three-way merge output exceeds the \(maximumBytes)-byte limit."
        case .tooManyOutputLines(let maximumLines):
            "Three-way merge output exceeds the \(maximumLines)-line limit."
        case .tooManyRegions(let maximumRegions):
            "Three-way merge exceeds the \(maximumRegions)-region limit."
        case .invalidDiffResult:
            "Text comparison returned an invalid line mapping for three-way merge."
        }
    }
}

public enum ThreeWayTextMergeResolution: Equatable, Sendable {
    case unchanged
    case left
    case right
    case identical
    case conflict

    public var isConflict: Bool { self == .conflict }
}

public enum ThreeWayTextMergeConflictChoice: Equatable, Sendable {
    case base
    case left
    case right
}

public struct ThreeWayTextMergeRegion: Identifiable, Equatable, Sendable {
    public let id: Int
    public let baseRange: Range<Int>
    public let leftRange: Range<Int>
    public let rightRange: Range<Int>
    public let baseLines: [ThreeWayTextMergeLine]
    public let leftLines: [ThreeWayTextMergeLine]
    public let rightLines: [ThreeWayTextMergeLine]
    public let resolution: ThreeWayTextMergeResolution

    public var isConflict: Bool { resolution.isConflict }

    public var automaticallyMergedLines: [ThreeWayTextMergeLine]? {
        switch resolution {
        case .unchanged:
            baseLines
        case .left, .identical:
            leftLines
        case .right:
            rightLines
        case .conflict:
            nil
        }
    }

    fileprivate init(
        id: Int,
        baseRange: Range<Int>,
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        baseLines: [ThreeWayTextMergeLine],
        leftLines: [ThreeWayTextMergeLine],
        rightLines: [ThreeWayTextMergeLine],
        resolution: ThreeWayTextMergeResolution
    ) {
        self.id = id
        self.baseRange = baseRange
        self.leftRange = leftRange
        self.rightRange = rightRange
        self.baseLines = baseLines
        self.leftLines = leftLines
        self.rightLines = rightLines
        self.resolution = resolution
    }

    fileprivate func lines(for choice: ThreeWayTextMergeConflictChoice) -> [ThreeWayTextMergeLine] {
        switch choice {
        case .base: baseLines
        case .left: leftLines
        case .right: rightLines
        }
    }
}

public struct ThreeWayTextMergeResult: Equatable, Sendable {
    public let base: ThreeWayTextMergeDocument
    public let left: ThreeWayTextMergeDocument
    public let right: ThreeWayTextMergeDocument
    public let regions: [ThreeWayTextMergeRegion]
    public let mergedLines: [ThreeWayTextMergeLine]?
    public let mergedText: String?

    public let conflicts: [ThreeWayTextMergeRegion]
    public var hasConflicts: Bool { mergedLines == nil }

    fileprivate init(
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        regions: [ThreeWayTextMergeRegion]
    ) throws {
        self.base = base
        self.left = left
        self.right = right
        self.regions = regions
        var conflicts: [ThreeWayTextMergeRegion] = []
        for (index, region) in regions.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if region.isConflict { conflicts.append(region) }
        }
        self.conflicts = conflicts
        if !conflicts.isEmpty {
            mergedLines = nil
            mergedText = nil
        } else {
            var lines: [ThreeWayTextMergeLine] = []
            for (regionIndex, region) in regions.enumerated() {
                if regionIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
                guard let regionLines = region.automaticallyMergedLines else { continue }
                try Self.append(regionLines, to: &lines)
            }
            mergedLines = lines
            mergedText = try Self.serializedText(lines)
        }
    }

    public func lines(
        resolvingConflictsWith choices: [Int: ThreeWayTextMergeConflictChoice]
    ) throws -> [ThreeWayTextMergeLine]? {
        for (conflictIndex, conflict) in conflicts.enumerated() {
            if conflictIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard choices[conflict.id] != nil else { return nil }
        }

        var result: [ThreeWayTextMergeLine] = []
        for (regionIndex, region) in regions.enumerated() {
            if regionIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if let lines = region.automaticallyMergedLines {
                try Self.append(lines, to: &result)
            } else {
                guard let choice = choices[region.id] else { return nil }
                try Self.append(region.lines(for: choice), to: &result)
            }
        }
        return result
    }

    public func text(
        resolvingConflictsWith choices: [Int: ThreeWayTextMergeConflictChoice]
    ) throws -> String? {
        guard let lines = try lines(resolvingConflictsWith: choices) else { return nil }
        return try Self.serializedText(lines)
    }

    private static func append(
        _ source: [ThreeWayTextMergeLine],
        to destination: inout [ThreeWayTextMergeLine]
    ) throws {
        for (index, line) in source.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            destination.append(line)
        }
    }

    private static func serializedText(_ lines: [ThreeWayTextMergeLine]) throws -> String {
        var result = ""
        for (index, line) in lines.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            try append(line.text, to: &result)
            if let lineEnding = line.lineEnding {
                result.append(lineEnding.rawValue)
            }
        }
        return result
    }

    private static func append(_ source: String, to destination: inout String) throws {
        let scalars = source.unicodeScalars
        var chunkStart = scalars.startIndex
        var index = chunkStart
        var chunkBytes = 0
        while index < scalars.endIndex {
            let next = scalars.index(after: index)
            chunkBytes += scalars[index].utf8.count
            if chunkBytes >= 64 * 1_024 {
                destination.append(contentsOf: source[chunkStart..<next])
                try Task.checkCancellation()
                chunkStart = next
                chunkBytes = 0
            }
            index = next
        }
        destination.append(contentsOf: source[chunkStart..<scalars.endIndex])
    }
}

public enum ThreeWayTextMerge: Sendable {
    public static func merge(
        base baseText: String,
        left leftText: String,
        right rightText: String,
        options: ThreeWayTextMergeOptions = ThreeWayTextMergeOptions()
    ) throws -> ThreeWayTextMergeResult {
        try Task.checkCancellation()
        let base = try ThreeWayTextMergeDocument(
            text: baseText,
            source: .base,
            maximumBytes: options.maximumInputBytes,
            maximumLines: options.maximumInputLines
        )
        let left = try ThreeWayTextMergeDocument(
            text: leftText,
            source: .left,
            maximumBytes: options.maximumInputBytes,
            maximumLines: options.maximumInputLines
        )
        let right = try ThreeWayTextMergeDocument(
            text: rightText,
            source: .right,
            maximumBytes: options.maximumInputBytes,
            maximumLines: options.maximumInputLines
        )

        let diffOptions = LineDiffOptions(
            algorithm: options.diffAlgorithm,
            ignoreLineEndings: true,
            lineFiltersEnabled: false,
            substitutionsEnabled: false
        )
        try Task.checkCancellation()
        let leftRows = try LineDiff.compare(left: baseText, right: leftText, options: diffOptions)
        try Task.checkCancellation()
        let rightRows = try LineDiff.compare(left: baseText, right: rightText, options: diffOptions)
        try Task.checkCancellation()

        let leftDiff = try changes(base: base, side: left, rows: leftRows)
        let rightDiff = try changes(base: base, side: right, rows: rightRows)
        let regions = try regions(
            base: base,
            left: left,
            right: right,
            leftDiff: leftDiff,
            rightDiff: rightDiff,
            options: options
        )
        return try ThreeWayTextMergeResult(
            base: base,
            left: left,
            right: right,
            regions: regions
        )
    }

    private struct Change {
        let baseRange: Range<Int>
        let sideRange: Range<Int>
    }

    private struct SideDiff {
        let changes: [Change]
        let insertions: [Range<Int>]
        let lines: [Range<Int>]
        let linesCoveredByCardinalitySurplus: [Bool]
        let basePositionBeforeSideLine: [Int]
        let basePositionAfterSideLine: [Int]
    }

    private static func changes(
        base: ThreeWayTextMergeDocument,
        side: ThreeWayTextMergeDocument,
        rows: [DiffRow]
    ) throws -> SideDiff {
        var changes: [Change] = []
        var insertions = Array(repeating: 0..<0, count: base.lines.count + 1)
        var lineRanges = Array(repeating: 0..<0, count: base.lines.count)
        var basePositionBeforeSideLine = Array(repeating: 0, count: side.lines.count)
        var basePositionAfterSideLine = Array(repeating: 0, count: side.lines.count)
        var baseIndex = 0
        var sideIndex = 0
        var changeStart: (base: Int, side: Int)?

        func finishChange() {
            guard let start = changeStart else { return }
            changes.append(
                Change(
                    baseRange: start.base..<baseIndex,
                    sideRange: start.side..<sideIndex
                ))
            changeStart = nil
        }

        for (rowIndex, row) in rows.enumerated() {
            if rowIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let hasBase = row.left != nil
            let hasSide = row.right != nil
            guard !hasBase || baseIndex < base.lines.count,
                !hasSide || sideIndex < side.lines.count
            else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }

            if hasBase {
                lineRanges[baseIndex] = sideIndex..<(sideIndex + (hasSide ? 1 : 0))
            } else if hasSide {
                let insertion = insertions[baseIndex]
                insertions[baseIndex] =
                    insertion.isEmpty
                    ? sideIndex..<(sideIndex + 1)
                    : insertion.lowerBound..<(sideIndex + 1)
            }
            if hasSide {
                basePositionBeforeSideLine[sideIndex] = baseIndex
                basePositionAfterSideLine[sideIndex] = baseIndex + (hasBase ? 1 : 0)
            }

            let isExactMatch = try row.kind == .unchanged && hasBase && hasSide && linesAreExactlyEqual(base.lines[baseIndex], side.lines[sideIndex])
            if isExactMatch {
                finishChange()
            } else if changeStart == nil {
                changeStart = (baseIndex, sideIndex)
            }

            if hasBase { baseIndex += 1 }
            if hasSide { sideIndex += 1 }
        }
        finishChange()

        guard baseIndex == base.lines.count, sideIndex == side.lines.count else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
        var linesCoveredByCardinalitySurplus = Array(repeating: false, count: base.lines.count)
        for (changeIndex, change) in changes.enumerated() {
            if changeIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard change.sideRange.count > change.baseRange.count else { continue }
            for (offset, baseIndex) in change.baseRange.enumerated() {
                if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
                linesCoveredByCardinalitySurplus[baseIndex] = true
            }
        }
        return SideDiff(
            changes: changes,
            insertions: insertions,
            lines: lineRanges,
            linesCoveredByCardinalitySurplus: linesCoveredByCardinalitySurplus,
            basePositionBeforeSideLine: basePositionBeforeSideLine,
            basePositionAfterSideLine: basePositionAfterSideLine
        )
    }

    private static func regions(
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        leftDiff: SideDiff,
        rightDiff: SideDiff,
        options: ThreeWayTextMergeOptions
    ) throws -> [ThreeWayTextMergeRegion] {
        let leftChanges = leftDiff.changes
        let rightChanges = rightDiff.changes
        var regions: [ThreeWayTextMergeRegion] = []
        var leftChangeIndex = 0
        var rightChangeIndex = 0
        var basePosition = 0
        var leftPosition = 0
        var rightPosition = 0
        var potentialOutputBytes = 0
        var potentialOutputLines = 0

        func appendRegion(
            baseRange: Range<Int>,
            leftRange: Range<Int>,
            rightRange: Range<Int>,
            knownResolution: ThreeWayTextMergeResolution? = nil
        ) throws {
            guard regions.count < options.maximumRegions else {
                throw ThreeWayTextMergeError.tooManyRegions(
                    maximumRegions: options.maximumRegions
                )
            }
            guard baseRange.upperBound <= base.lines.count,
                leftRange.upperBound <= left.lines.count,
                rightRange.upperBound <= right.lines.count
            else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }

            let resolution =
                try knownResolution
                ?? self.resolution(
                    base: base.lines[baseRange],
                    left: left.lines[leftRange],
                    right: right.lines[rightRange]
                )
            let addedLineCount: Int
            let addedByteCount: Int
            if resolution == .conflict {
                addedLineCount = max(baseRange.count, leftRange.count, rightRange.count)
                addedByteCount = max(
                    try serializedUTF8Count(base.lines[baseRange]),
                    try serializedUTF8Count(left.lines[leftRange]),
                    try serializedUTF8Count(right.lines[rightRange])
                )
            } else {
                let selected: ArraySlice<ThreeWayTextMergeLine> =
                    switch resolution {
                    case .unchanged: base.lines[baseRange]
                    case .left, .identical: left.lines[leftRange]
                    case .right: right.lines[rightRange]
                    case .conflict: []
                    }
                addedLineCount = selected.count
                addedByteCount = try serializedUTF8Count(selected)
            }

            guard addedLineCount <= options.maximumOutputLines - potentialOutputLines else {
                throw ThreeWayTextMergeError.tooManyOutputLines(
                    maximumLines: options.maximumOutputLines
                )
            }
            guard addedByteCount <= options.maximumOutputBytes - potentialOutputBytes else {
                throw ThreeWayTextMergeError.outputTooLarge(
                    maximumBytes: options.maximumOutputBytes
                )
            }
            potentialOutputLines += addedLineCount
            potentialOutputBytes += addedByteCount
            let baseLines = try copiedLines(base.lines, in: baseRange)
            let leftLines = try copiedLines(left.lines, in: leftRange)
            let rightLines = try copiedLines(right.lines, in: rightRange)
            regions.append(
                ThreeWayTextMergeRegion(
                    id: regions.count,
                    baseRange: baseRange,
                    leftRange: leftRange,
                    rightRange: rightRange,
                    baseLines: baseLines,
                    leftLines: leftLines,
                    rightLines: rightLines,
                    resolution: resolution
                ))
        }

        func appendResolvedCluster(
            baseRange: Range<Int>,
            leftRange: Range<Int>,
            rightRange: Range<Int>
        ) throws {
            let wholeResolution = try resolution(
                base: base.lines[baseRange],
                left: left.lines[leftRange],
                right: right.lines[rightRange]
            )
            guard wholeResolution == .conflict else {
                try appendRegion(
                    baseRange: baseRange,
                    leftRange: leftRange,
                    rightRange: rightRange,
                    knownResolution: wholeResolution
                )
                return
            }

            if try hasDeleteVersusModification(
                base: base,
                left: left,
                right: right,
                baseRange: baseRange,
                leftRange: leftRange,
                rightRange: rightRange,
                leftDiff: leftDiff,
                rightDiff: rightDiff
            ) {
                try appendRegion(
                    baseRange: baseRange,
                    leftRange: leftRange,
                    rightRange: rightRange,
                    knownResolution: .conflict
                )
                return
            }

            if try hasFinalLineEndingDependency(
                base: base,
                left: left,
                right: right,
                baseRange: baseRange,
                leftRange: leftRange,
                rightRange: rightRange,
                leftDiff: leftDiff,
                rightDiff: rightDiff
            ) {
                try appendRegion(
                    baseRange: baseRange,
                    leftRange: leftRange,
                    rightRange: rightRange,
                    knownResolution: .conflict
                )
                return
            }

            let commonPrefix = try commonPrefixCount(
                left.lines[leftRange],
                right.lines[rightRange]
            )
            if commonPrefix > 0 {
                let leftPrefixEnd = leftRange.lowerBound + commonPrefix
                let rightPrefixEnd = rightRange.lowerBound + commonPrefix
                let leftBaseEnd = leftDiff.basePositionAfterSideLine[leftPrefixEnd - 1]
                let rightBaseEnd = rightDiff.basePositionAfterSideLine[rightPrefixEnd - 1]
                let commonBaseEnd = min(
                    baseRange.upperBound,
                    max(baseRange.lowerBound, min(leftBaseEnd, rightBaseEnd))
                )
                try appendRegion(
                    baseRange: baseRange.lowerBound..<commonBaseEnd,
                    leftRange: leftRange.lowerBound..<leftPrefixEnd,
                    rightRange: rightRange.lowerBound..<rightPrefixEnd
                )
                try appendResolvedCluster(
                    baseRange: commonBaseEnd..<baseRange.upperBound,
                    leftRange: leftPrefixEnd..<leftRange.upperBound,
                    rightRange: rightPrefixEnd..<rightRange.upperBound
                )
                return
            }

            let commonSuffix = try commonSuffixCount(
                left.lines[leftRange],
                right.lines[rightRange]
            )
            if commonSuffix > 0 {
                let leftSuffixStart = leftRange.upperBound - commonSuffix
                let rightSuffixStart = rightRange.upperBound - commonSuffix
                let leftBaseStart = leftDiff.basePositionBeforeSideLine[leftSuffixStart]
                let rightBaseStart = rightDiff.basePositionBeforeSideLine[rightSuffixStart]
                let commonBaseStart = max(
                    baseRange.lowerBound,
                    min(baseRange.upperBound, max(leftBaseStart, rightBaseStart))
                )
                try appendResolvedCluster(
                    baseRange: baseRange.lowerBound..<commonBaseStart,
                    leftRange: leftRange.lowerBound..<leftSuffixStart,
                    rightRange: rightRange.lowerBound..<rightSuffixStart
                )
                try appendRegion(
                    baseRange: commonBaseStart..<baseRange.upperBound,
                    leftRange: leftSuffixStart..<leftRange.upperBound,
                    rightRange: rightSuffixStart..<rightRange.upperBound
                )
                return
            }

            var leftAtomPosition = leftRange.lowerBound
            var rightAtomPosition = rightRange.lowerBound

            func atomRange(_ range: Range<Int>, position: Int, limit: Int) -> Range<Int> {
                let lowerBound = min(limit, max(position, range.lowerBound))
                let upperBound = min(limit, max(lowerBound, range.upperBound))
                return lowerBound..<upperBound
            }

            for baseIndex in baseRange {
                try Task.checkCancellation()
                var leftInsertion = atomRange(
                    leftDiff.insertions[baseIndex],
                    position: leftAtomPosition,
                    limit: leftRange.upperBound
                )
                var rightInsertion = atomRange(
                    rightDiff.insertions[baseIndex],
                    position: rightAtomPosition,
                    limit: rightRange.upperBound
                )
                var leftLine = atomRange(
                    leftDiff.lines[baseIndex],
                    position: leftInsertion.upperBound,
                    limit: leftRange.upperBound
                )
                var rightLine = atomRange(
                    rightDiff.lines[baseIndex],
                    position: rightInsertion.upperBound,
                    limit: rightRange.upperBound
                )
                let baseLine = base.lines[baseIndex]
                let leftInsertionMatchesRightLine =
                    try
                    (rightInsertion.isEmpty
                    && !leftInsertion.isEmpty
                    && rightDiff.linesCoveredByCardinalitySurplus[baseIndex]
                    && !lineRange(
                        rightLine,
                        in: right,
                        isEquivalentTo: baseLine,
                        baseIndex: baseIndex,
                        baseLineCount: base.lines.count
                    )
                    && linesAreExactlyEqual(
                        left.lines[leftInsertion],
                        right.lines[rightLine]
                    ))
                let rightInsertionMatchesLeftLine =
                    try
                    (leftInsertion.isEmpty
                    && !rightInsertion.isEmpty
                    && leftDiff.linesCoveredByCardinalitySurplus[baseIndex]
                    && !lineRange(
                        leftLine,
                        in: left,
                        isEquivalentTo: baseLine,
                        baseIndex: baseIndex,
                        baseLineCount: base.lines.count
                    )
                    && linesAreExactlyEqual(
                        right.lines[rightInsertion],
                        left.lines[leftLine]
                    ))
                if leftInsertionMatchesRightLine {
                    try appendRegion(
                        baseRange: baseIndex..<baseIndex,
                        leftRange: leftInsertion,
                        rightRange: rightLine,
                        knownResolution: .identical
                    )
                    leftAtomPosition = leftInsertion.upperBound
                    rightAtomPosition = rightLine.upperBound
                    leftInsertion = leftAtomPosition..<leftAtomPosition
                    rightLine = rightAtomPosition..<rightAtomPosition
                } else if rightInsertionMatchesLeftLine {
                    try appendRegion(
                        baseRange: baseIndex..<baseIndex,
                        leftRange: leftLine,
                        rightRange: rightInsertion,
                        knownResolution: .identical
                    )
                    leftAtomPosition = leftLine.upperBound
                    rightAtomPosition = rightInsertion.upperBound
                    leftLine = leftAtomPosition..<leftAtomPosition
                    rightInsertion = rightAtomPosition..<rightAtomPosition
                }
                if !leftInsertion.isEmpty || !rightInsertion.isEmpty {
                    try appendRegion(
                        baseRange: baseIndex..<baseIndex,
                        leftRange: leftInsertion,
                        rightRange: rightInsertion
                    )
                    leftAtomPosition = leftInsertion.upperBound
                    rightAtomPosition = rightInsertion.upperBound
                }

                let lineResolution = try atomResolution(
                    baseIndex: baseIndex,
                    base: base,
                    left: left,
                    right: right,
                    leftRange: leftLine,
                    rightRange: rightLine
                )
                try appendRegion(
                    baseRange: baseIndex..<(baseIndex + 1),
                    leftRange: leftLine,
                    rightRange: rightLine,
                    knownResolution: lineResolution
                )
                leftAtomPosition = leftLine.upperBound
                rightAtomPosition = rightLine.upperBound
            }

            let boundary = baseRange.upperBound
            let leftInsertion = atomRange(
                leftDiff.insertions[boundary],
                position: leftAtomPosition,
                limit: leftRange.upperBound
            )
            let rightInsertion = atomRange(
                rightDiff.insertions[boundary],
                position: rightAtomPosition,
                limit: rightRange.upperBound
            )
            leftAtomPosition = leftInsertion.upperBound
            rightAtomPosition = rightInsertion.upperBound
            if !leftInsertion.isEmpty || !rightInsertion.isEmpty {
                try appendRegion(
                    baseRange: boundary..<boundary,
                    leftRange: leftInsertion,
                    rightRange: rightInsertion
                )
            }

            if leftAtomPosition < leftRange.upperBound || rightAtomPosition < rightRange.upperBound {
                try appendRegion(
                    baseRange: boundary..<boundary,
                    leftRange: leftAtomPosition..<leftRange.upperBound,
                    rightRange: rightAtomPosition..<rightRange.upperBound
                )
            }
        }

        while leftChangeIndex < leftChanges.count || rightChangeIndex < rightChanges.count {
            try Task.checkCancellation()
            let chooseLeft = nextChangeIsLeft(
                left: leftChanges[safe: leftChangeIndex],
                right: rightChanges[safe: rightChangeIndex]
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
                throw ThreeWayTextMergeError.invalidDiffResult
            }

            let gapCount = clusterStart - basePosition
            if gapCount > 0 {
                try appendRegion(
                    baseRange: basePosition..<clusterStart,
                    leftRange: leftPosition..<(leftPosition + gapCount),
                    rightRange: rightPosition..<(rightPosition + gapCount)
                )
                basePosition = clusterStart
                leftPosition += gapCount
                rightPosition += gapCount
            }

            var addedChange = true
            var expandedChangeCount = 0
            while addedChange {
                addedChange = false
                if let change = leftChanges[safe: leftChangeIndex],
                    overlapsOrSharesBoundaryInsertion(
                        change.baseRange,
                        clusterStart..<clusterEnd,
                        leftDiff: leftDiff,
                        rightDiff: rightDiff
                    )
                {
                    clusterLeftChanges.append(change)
                    clusterEnd = max(clusterEnd, change.baseRange.upperBound)
                    leftChangeIndex += 1
                    addedChange = true
                    expandedChangeCount += 1
                    if expandedChangeCount.isMultiple(of: 4_096) {
                        try Task.checkCancellation()
                    }
                }
                if let change = rightChanges[safe: rightChangeIndex],
                    overlapsOrSharesBoundaryInsertion(
                        change.baseRange,
                        clusterStart..<clusterEnd,
                        leftDiff: leftDiff,
                        rightDiff: rightDiff
                    )
                {
                    clusterRightChanges.append(change)
                    clusterEnd = max(clusterEnd, change.baseRange.upperBound)
                    rightChangeIndex += 1
                    addedChange = true
                    expandedChangeCount += 1
                    if expandedChangeCount.isMultiple(of: 4_096) {
                        try Task.checkCancellation()
                    }
                }
            }

            let baseRange = clusterStart..<clusterEnd
            let leftEnd = try sideEnd(
                start: leftPosition,
                baseRange: baseRange,
                changes: clusterLeftChanges,
                lineCount: left.lines.count
            )
            let rightEnd = try sideEnd(
                start: rightPosition,
                baseRange: baseRange,
                changes: clusterRightChanges,
                lineCount: right.lines.count
            )
            try appendResolvedCluster(
                baseRange: baseRange,
                leftRange: leftPosition..<leftEnd,
                rightRange: rightPosition..<rightEnd
            )
            basePosition = clusterEnd
            leftPosition = leftEnd
            rightPosition = rightEnd
        }

        let trailingCount = base.lines.count - basePosition
        guard trailingCount >= 0,
            leftPosition + trailingCount == left.lines.count,
            rightPosition + trailingCount == right.lines.count
        else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
        if trailingCount > 0 {
            try appendRegion(
                baseRange: basePosition..<base.lines.count,
                leftRange: leftPosition..<left.lines.count,
                rightRange: rightPosition..<right.lines.count
            )
        }
        return regions
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

    private static func overlaps(_ change: Range<Int>, _ cluster: Range<Int>) -> Bool {
        if cluster.isEmpty {
            return change.lowerBound == cluster.lowerBound
        }
        if change.isEmpty {
            return change.lowerBound >= cluster.lowerBound && change.lowerBound <= cluster.upperBound
        }
        return change.lowerBound < cluster.upperBound && change.upperBound > cluster.lowerBound
    }

    private static func overlapsOrSharesBoundaryInsertion(
        _ change: Range<Int>,
        _ cluster: Range<Int>,
        leftDiff: SideDiff,
        rightDiff: SideDiff
    ) -> Bool {
        if overlaps(change, cluster) { return true }
        guard !change.isEmpty, !cluster.isEmpty,
            change.lowerBound == cluster.upperBound
        else {
            return false
        }
        let boundary = change.lowerBound
        return !leftDiff.insertions[boundary].isEmpty
            || !rightDiff.insertions[boundary].isEmpty
    }

    private static func sideEnd(
        start: Int,
        baseRange: Range<Int>,
        changes: [Change],
        lineCount: Int
    ) throws -> Int {
        var count = baseRange.count
        for (index, change) in changes.enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            count += change.sideRange.count - change.baseRange.count
        }
        guard count >= 0, start <= lineCount - count else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
        return start + count
    }

    private static func resolution(
        base: ArraySlice<ThreeWayTextMergeLine>,
        left: ArraySlice<ThreeWayTextMergeLine>,
        right: ArraySlice<ThreeWayTextMergeLine>
    ) throws -> ThreeWayTextMergeResolution {
        if try linesAreExactlyEqual(left, right) {
            return try linesAreExactlyEqual(left, base) ? .unchanged : .identical
        }
        if try linesAreExactlyEqual(left, base) { return .right }
        if try linesAreExactlyEqual(right, base) { return .left }
        return .conflict
    }

    private static func linesAreExactlyEqual(
        _ left: ArraySlice<ThreeWayTextMergeLine>,
        _ right: ArraySlice<ThreeWayTextMergeLine>
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for (index, pair) in zip(left, right).enumerated() {
            if index.isMultiple(of: 4_096) { try Task.checkCancellation() }
            if try !linesAreExactlyEqual(pair.0, pair.1) { return false }
        }
        return true
    }

    private static func linesAreExactlyEqual(
        _ left: ThreeWayTextMergeLine,
        _ right: ThreeWayTextMergeLine
    ) throws -> Bool {
        guard left.lineEnding == right.lineEnding else { return false }
        return try textIsExactlyEqual(left.text, right.text)
    }

    private static func copiedLines(
        _ lines: [ThreeWayTextMergeLine],
        in range: Range<Int>
    ) throws -> [ThreeWayTextMergeLine] {
        var result: [ThreeWayTextMergeLine] = []
        result.reserveCapacity(range.count)
        for (offset, index) in range.enumerated() {
            if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
            result.append(lines[index])
        }
        return result
    }

    private static func serializedUTF8Count(
        _ lines: ArraySlice<ThreeWayTextMergeLine>
    ) throws -> Int {
        var result = 0
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex.isMultiple(of: 4_096) { try Task.checkCancellation() }
            var byteIndex = 0
            for _ in line.text.utf8 {
                if byteIndex > 0, byteIndex.isMultiple(of: 64 * 1_024) {
                    try Task.checkCancellation()
                }
                byteIndex += 1
            }
            result += byteIndex + (line.lineEnding?.rawValue.utf8.count ?? 0)
        }
        return result
    }

    private static func commonPrefixCount(
        _ left: ArraySlice<ThreeWayTextMergeLine>,
        _ right: ArraySlice<ThreeWayTextMergeLine>
    ) throws -> Int {
        var result = 0
        for pair in zip(left, right) {
            if result.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard try linesAreExactlyEqual(pair.0, pair.1) else { break }
            result += 1
        }
        return result
    }

    private static func commonSuffixCount(
        _ left: ArraySlice<ThreeWayTextMergeLine>,
        _ right: ArraySlice<ThreeWayTextMergeLine>
    ) throws -> Int {
        var result = 0
        while result < left.count, result < right.count {
            if result.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let leftIndex = left.index(left.endIndex, offsetBy: -result - 1)
            let rightIndex = right.index(right.endIndex, offsetBy: -result - 1)
            guard try linesAreExactlyEqual(left[leftIndex], right[rightIndex]) else { break }
            result += 1
        }
        return result
    }

    private static func atomResolution(
        baseIndex: Int,
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        leftRange: Range<Int>,
        rightRange: Range<Int>
    ) throws -> ThreeWayTextMergeResolution {
        let baseLine = base.lines[baseIndex]
        let leftIsBase = try lineRange(
            leftRange,
            in: left,
            isEquivalentTo: baseLine,
            baseIndex: baseIndex,
            baseLineCount: base.lines.count
        )
        let rightIsBase = try lineRange(
            rightRange,
            in: right,
            isEquivalentTo: baseLine,
            baseIndex: baseIndex,
            baseLineCount: base.lines.count
        )
        if leftIsBase, rightIsBase {
            if try linesAreExactlyEqual(left.lines[leftRange], right.lines[rightRange]) {
                return try linesAreExactlyEqual(left.lines[leftRange], base.lines[baseIndex...baseIndex])
                    ? .unchanged : .identical
            }
            return .conflict
        }
        if leftIsBase { return .right }
        if rightIsBase { return .left }
        return try resolution(
            base: base.lines[baseIndex...baseIndex],
            left: left.lines[leftRange],
            right: right.lines[rightRange]
        )
    }

    private static func hasDeleteVersusModification(
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        baseRange: Range<Int>,
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        leftDiff: SideDiff,
        rightDiff: SideDiff
    ) throws -> Bool {
        for (offset, baseIndex) in baseRange.enumerated() {
            if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let baseLine = base.lines[baseIndex]
            let leftLine = leftDiff.lines[baseIndex].clamped(to: leftRange)
            let rightLine = rightDiff.lines[baseIndex].clamped(to: rightRange)
            if leftLine.isEmpty, !rightLine.isEmpty,
                !(try lineRange(
                    rightLine,
                    in: right,
                    isEquivalentTo: baseLine,
                    baseIndex: baseIndex,
                    baseLineCount: base.lines.count
                ))
            {
                return true
            }
            if rightLine.isEmpty, !leftLine.isEmpty,
                !(try lineRange(
                    leftLine,
                    in: left,
                    isEquivalentTo: baseLine,
                    baseIndex: baseIndex,
                    baseLineCount: base.lines.count
                ))
            {
                return true
            }
        }
        return false
    }

    private static func lineRange(
        _ range: Range<Int>,
        in side: ThreeWayTextMergeDocument,
        isEquivalentTo baseLine: ThreeWayTextMergeLine,
        baseIndex: Int,
        baseLineCount: Int
    ) throws -> Bool {
        guard range.count == 1 else { return false }
        let sideLine = side.lines[range.lowerBound]
        if try linesAreExactlyEqual(sideLine, baseLine) { return true }
        guard baseIndex + 1 < baseLineCount,
            range.upperBound == side.lines.count,
            sideLine.lineEnding == nil,
            baseLine.lineEnding != nil
        else {
            return false
        }
        return try textIsExactlyEqual(sideLine.text, baseLine.text)
    }

    private static func hasFinalLineEndingDependency(
        base: ThreeWayTextMergeDocument,
        left: ThreeWayTextMergeDocument,
        right: ThreeWayTextMergeDocument,
        baseRange: Range<Int>,
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        leftDiff: SideDiff,
        rightDiff: SideDiff
    ) throws -> Bool {
        let lineCount = base.lines.count
        guard lineCount > 0, baseRange.upperBound == lineCount else { return false }
        let leftInsertion = leftDiff.insertions[lineCount].clamped(to: leftRange)
        let rightInsertion = rightDiff.insertions[lineCount].clamped(to: rightRange)
        var leftDeletesSuffix = false
        var rightDeletesSuffix = false
        if baseRange.lowerBound + 1 < lineCount {
            for (offset, baseIndex) in ((baseRange.lowerBound + 1)..<lineCount).enumerated() {
                if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
                leftDeletesSuffix = leftDeletesSuffix || leftDiff.lines[baseIndex].isEmpty
                rightDeletesSuffix = rightDeletesSuffix || rightDiff.lines[baseIndex].isEmpty
            }
        }
        guard !leftInsertion.isEmpty || !rightInsertion.isEmpty || leftDeletesSuffix || rightDeletesSuffix else {
            return false
        }

        for offset in 0..<baseRange.count {
            if offset.isMultiple(of: 4_096) { try Task.checkCancellation() }
            let baseIndex = baseRange.upperBound - offset - 1
            let leftLineRange = leftDiff.lines[baseIndex].clamped(to: leftRange)
            let rightLineRange = rightDiff.lines[baseIndex].clamped(to: rightRange)
            guard leftLineRange.count == 1, rightLineRange.count == 1 else { continue }
            let leftEnding = left.lines[leftLineRange.lowerBound].lineEnding
            let rightEnding = right.lines[rightLineRange.lowerBound].lineEnding
            return leftEnding != rightEnding
        }
        return false
    }

    private static func textIsExactlyEqual(_ left: String, _ right: String) throws -> Bool {
        let leftBytes = left.utf8
        let rightBytes = right.utf8
        var leftIndex = leftBytes.startIndex
        var rightIndex = rightBytes.startIndex
        var comparedByteCount = 0
        while leftIndex < leftBytes.endIndex, rightIndex < rightBytes.endIndex {
            if comparedByteCount > 0, comparedByteCount.isMultiple(of: 64 * 1_024) {
                try Task.checkCancellation()
            }
            guard leftBytes[leftIndex] == rightBytes[rightIndex] else { return false }
            leftIndex = leftBytes.index(after: leftIndex)
            rightIndex = rightBytes.index(after: rightIndex)
            comparedByteCount += 1
        }
        return leftIndex == leftBytes.endIndex && rightIndex == rightBytes.endIndex
    }
}

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Range where Bound == Int {
    fileprivate func clamped(to limits: Range<Int>) -> Range<Int> {
        let lowerBound = Swift.max(self.lowerBound, limits.lowerBound)
        let upperBound = Swift.max(lowerBound, Swift.min(self.upperBound, limits.upperBound))
        return lowerBound..<upperBound
    }
}
