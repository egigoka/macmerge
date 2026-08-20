/// Row-level text comparison counts. Accumulated counts saturate at `Int.max`.
public struct ComparisonStatistics: Equatable, Sendable {
    public struct SelectedSignificantDifference: Equatable, Sendable {
        /// Zero-based position among rows whose kind is not `unchanged`.
        public let index: Int
        /// One-based position suitable for presentation.
        public let position: Int
        public let totalCount: Int

        init(index: Int, totalCount: Int) {
            self.index = index
            position = Self.saturatingAdd(index, 1)
            self.totalCount = totalCount
        }

        private static func saturatingAdd(_ left: Int, _ right: Int) -> Int {
            let (sum, overflow) = left.addingReportingOverflow(right)
            return overflow ? .max : sum
        }
    }

    /// Unchanged rows whose original content and line terminators are byte-identical.
    public let equalRowCount: Int
    public let modifiedRowCount: Int
    public let addedRowCount: Int
    public let removedRowCount: Int
    /// Rows whose kind is `modified`, `added`, or `removed`.
    public let significantRowCount: Int
    /// Unchanged rows not counted as equal, including differences hidden by comparison options.
    public let trivialRowCount: Int
    public let leftSourceLineCount: Int
    public let rightSourceLineCount: Int
    /// Left-side source lines with right-side move partners, or `nil` when move analysis is unavailable.
    public let movedSourceLineCount: Int?
    /// Right-side destination lines with left-side move partners, or `nil` when move analysis is unavailable.
    public let movedDestinationLineCount: Int?
    public let movedLineAnalysisStatus: MovedLineAnalysisStatus
    public let selectedSignificantDifference: SelectedSignificantDifference?

    public init(
        result: LineDiffResult,
        selectedSignificantIndex: Int? = nil
    ) {
        self.init(
            rows: result.rows,
            movedSourceLineCount: result.movedLines.leftToRightCount,
            movedDestinationLineCount: result.movedLines.rightToLeftCount,
            movedLineAnalysisStatus: result.movedLineAnalysisStatus,
            selectedSignificantIndex: selectedSignificantIndex,
            checkCancellation: { _ in }
        )
    }

    public static func calculate(
        result: LineDiffResult,
        selectedSignificantIndex: Int? = nil
    ) throws -> ComparisonStatistics {
        try ComparisonStatistics(
            rows: result.rows,
            movedSourceLineCount: result.movedLines.leftToRightCount,
            movedDestinationLineCount: result.movedLines.rightToLeftCount,
            movedLineAnalysisStatus: result.movedLineAnalysisStatus,
            selectedSignificantIndex: selectedSignificantIndex,
            checkCancellation: { _ in try Task.checkCancellation() }
        )
    }

    /// Row-only statistics cannot include move metadata, so both moved-line counts are unavailable.
    public init(
        rows: [DiffRow],
        selectedSignificantIndex: Int? = nil
    ) {
        self.init(
            rows: rows,
            movedSourceLineCount: 0,
            movedDestinationLineCount: 0,
            movedLineAnalysisStatus: .notRequested,
            selectedSignificantIndex: selectedSignificantIndex,
            checkCancellation: { _ in }
        )
    }

    public static func calculate(
        rows: [DiffRow],
        selectedSignificantIndex: Int? = nil
    ) throws -> ComparisonStatistics {
        try calculate(
            rows: rows,
            selectedSignificantIndex: selectedSignificantIndex,
            cancellationCheckObserver: { _ in }
        )
    }

    static func calculate(
        rows: [DiffRow],
        selectedSignificantIndex: Int? = nil,
        cancellationCheckObserver: @Sendable (Int) -> Void
    ) throws -> ComparisonStatistics {
        try ComparisonStatistics(
            rows: rows,
            movedSourceLineCount: 0,
            movedDestinationLineCount: 0,
            movedLineAnalysisStatus: .notRequested,
            selectedSignificantIndex: selectedSignificantIndex,
            checkCancellation: { index in
                cancellationCheckObserver(index)
                try Task.checkCancellation()
            }
        )
    }

    private init(
        rows: [DiffRow],
        movedSourceLineCount: Int,
        movedDestinationLineCount: Int,
        movedLineAnalysisStatus: MovedLineAnalysisStatus,
        selectedSignificantIndex: Int?,
        checkCancellation: (Int) throws -> Void
    ) rethrows {
        var equal = 0
        var modified = 0
        var added = 0
        var removed = 0
        var significant = 0
        var trivial = 0
        var leftSourceLines = 0
        var rightSourceLines = 0

        for (index, row) in rows.enumerated() {
            if index & 0xFFF == 0 {
                try checkCancellation(index)
            }
            let id = row.id
            if id.leftNumber != nil {
                Self.saturatingIncrement(&leftSourceLines)
            }
            if id.rightNumber != nil {
                Self.saturatingIncrement(&rightSourceLines)
            }

            switch row.kind {
            case .unchanged:
                if row.hasEqualSourceRecords {
                    Self.saturatingIncrement(&equal)
                } else {
                    Self.saturatingIncrement(&trivial)
                }
            case .modified:
                Self.saturatingIncrement(&modified)
                Self.saturatingIncrement(&significant)
            case .added:
                Self.saturatingIncrement(&added)
                Self.saturatingIncrement(&significant)
            case .removed:
                Self.saturatingIncrement(&removed)
                Self.saturatingIncrement(&significant)
            }
        }
        try checkCancellation(rows.count)

        equalRowCount = equal
        modifiedRowCount = modified
        addedRowCount = added
        removedRowCount = removed
        significantRowCount = significant
        trivialRowCount = trivial
        leftSourceLineCount = leftSourceLines
        rightSourceLineCount = rightSourceLines
        self.movedLineAnalysisStatus = movedLineAnalysisStatus
        if movedLineAnalysisStatus == .available {
            self.movedSourceLineCount = max(0, movedSourceLineCount)
            self.movedDestinationLineCount = max(0, movedDestinationLineCount)
        } else {
            self.movedSourceLineCount = nil
            self.movedDestinationLineCount = nil
        }
        if let selectedSignificantIndex,
            selectedSignificantIndex >= 0,
            selectedSignificantIndex < significant
        {
            selectedSignificantDifference = SelectedSignificantDifference(
                index: selectedSignificantIndex,
                totalCount: significant
            )
        } else {
            selectedSignificantDifference = nil
        }
    }

    private static func saturatingIncrement(_ value: inout Int) {
        let (incremented, overflow) = value.addingReportingOverflow(1)
        value = overflow ? .max : incremented
    }
}

/// Source-line and merge-outcome counts for a validated three-way text comparison.
/// Accumulated counts saturate at `Int.max`.
public struct ThreeWayComparisonStatistics: Equatable, Sendable {
    public let baseSourceLineCount: Int
    public let leftSourceLineCount: Int
    public let rightSourceLineCount: Int
    public let regionCount: Int
    public let unchangedRegionCount: Int
    /// Regions resolved by taking a change found only on the left side.
    public let leftChangeRegionCount: Int
    /// Regions resolved by taking a change found only on the right side.
    public let rightChangeRegionCount: Int
    /// Regions where both sides made the same change.
    public let identicalChangeRegionCount: Int
    public let conflictRegionCount: Int
    /// All non-unchanged regions, including conflicts.
    public let changedRegionCount: Int

    public var hasConflicts: Bool { conflictRegionCount > 0 }

    /// Validates region coverage and source identity before reporting counts.
    ///
    /// Invalid or incoherent results throw `ThreeWayTextMergeError.invalidDiffResult`.
    public init(result: ThreeWayTextMergeResult) throws {
        try self.init(result: result, checkCancellation: { _ in })
    }

    /// Cancellable variant of ``init(result:)``.
    public static func calculate(
        result: ThreeWayTextMergeResult
    ) throws -> ThreeWayComparisonStatistics {
        try calculate(result: result, cancellationCheckObserver: { _ in })
    }

    static func calculate(
        result: ThreeWayTextMergeResult,
        cancellationCheckObserver: @Sendable (Int) -> Void
    ) throws -> ThreeWayComparisonStatistics {
        try ThreeWayComparisonStatistics(
            result: result,
            checkCancellation: { index in
                cancellationCheckObserver(index)
                try Task.checkCancellation()
            }
        )
    }

    private init(
        result: ThreeWayTextMergeResult,
        checkCancellation: (Int) throws -> Void
    ) throws {
        var inspectedItemCount = 0
        func inspectItem() throws {
            if inspectedItemCount & 0xFFF == 0 {
                try checkCancellation(inspectedItemCount)
            }
            let (nextCount, overflow) = inspectedItemCount.addingReportingOverflow(1)
            guard !overflow else { throw ThreeWayTextMergeError.invalidDiffResult }
            inspectedItemCount = nextCount
        }

        guard result.base.source == .base,
            result.left.source == .left,
            result.right.source == .right
        else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
        try Self.validate(document: result.base, source: .base, inspectItem: inspectItem)
        try Self.validate(document: result.left, source: .left, inspectItem: inspectItem)
        try Self.validate(document: result.right, source: .right, inspectItem: inspectItem)

        var basePosition = 0
        var leftPosition = 0
        var rightPosition = 0
        var unchanged = 0
        var leftChanges = 0
        var rightChanges = 0
        var identicalChanges = 0
        var conflicts = 0
        var changed = 0

        for (index, region) in result.regions.enumerated() {
            try inspectItem()
            guard region.id == index,
                region.baseRange.lowerBound == basePosition,
                region.leftRange.lowerBound == leftPosition,
                region.rightRange.lowerBound == rightPosition,
                Self.isValid(region.baseRange, count: result.base.lines.count),
                Self.isValid(region.leftRange, count: result.left.lines.count),
                Self.isValid(region.rightRange, count: result.right.lines.count),
                !(region.baseRange.isEmpty
                    && region.leftRange.isEmpty
                    && region.rightRange.isEmpty)
            else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
            try Self.validate(
                regionLines: region.baseLines,
                sourceLines: result.base.lines,
                range: region.baseRange,
                inspectItem: inspectItem
            )
            try Self.validate(
                regionLines: region.leftLines,
                sourceLines: result.left.lines,
                range: region.leftRange,
                inspectItem: inspectItem
            )
            try Self.validate(
                regionLines: region.rightLines,
                sourceLines: result.right.lines,
                range: region.rightRange,
                inspectItem: inspectItem
            )
            basePosition = region.baseRange.upperBound
            leftPosition = region.leftRange.upperBound
            rightPosition = region.rightRange.upperBound

            let leftIsBase = try Self.recordsAreEquivalentToBase(
                sideLines: region.leftLines,
                baseLines: region.baseLines,
                sideRange: region.leftRange,
                baseRange: region.baseRange,
                sideLineCount: result.left.lines.count,
                baseLineCount: result.base.lines.count,
                inspectItem: inspectItem
            )
            let leftIsExactlyBase = try Self.recordsAreExactlyEqual(
                region.leftLines,
                region.baseLines,
                inspectItem: inspectItem
            )
            let rightIsBase = try Self.recordsAreEquivalentToBase(
                sideLines: region.rightLines,
                baseLines: region.baseLines,
                sideRange: region.rightRange,
                baseRange: region.baseRange,
                sideLineCount: result.right.lines.count,
                baseLineCount: result.base.lines.count,
                inspectItem: inspectItem
            )
            let leftIsRight = try Self.recordsAreExactlyEqual(
                region.leftLines,
                region.rightLines,
                inspectItem: inspectItem
            )
            let expectedResolution: ThreeWayTextMergeResolution
            if leftIsRight {
                expectedResolution = leftIsExactlyBase ? .unchanged : .identical
            } else if leftIsBase {
                expectedResolution = .right
            } else if rightIsBase {
                expectedResolution = .left
            } else {
                expectedResolution = .conflict
            }
            guard region.resolution == expectedResolution else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
            switch region.resolution {
            case .unchanged:
                Self.saturatingIncrement(&unchanged)
            case .left:
                Self.saturatingIncrement(&leftChanges)
                Self.saturatingIncrement(&changed)
            case .right:
                Self.saturatingIncrement(&rightChanges)
                Self.saturatingIncrement(&changed)
            case .identical:
                Self.saturatingIncrement(&identicalChanges)
                Self.saturatingIncrement(&changed)
            case .conflict:
                Self.saturatingIncrement(&conflicts)
                Self.saturatingIncrement(&changed)
            }
        }

        guard basePosition == result.base.lines.count,
            leftPosition == result.left.lines.count,
            rightPosition == result.right.lines.count
        else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
        try Self.validateResultState(
            result,
            conflictCount: conflicts,
            inspectItem: inspectItem
        )
        try checkCancellation(inspectedItemCount)

        baseSourceLineCount = result.base.lines.count
        leftSourceLineCount = result.left.lines.count
        rightSourceLineCount = result.right.lines.count
        regionCount = result.regions.count
        unchangedRegionCount = unchanged
        leftChangeRegionCount = leftChanges
        rightChangeRegionCount = rightChanges
        identicalChangeRegionCount = identicalChanges
        conflictRegionCount = conflicts
        changedRegionCount = changed
    }

    private static func validate(
        document: ThreeWayTextMergeDocument,
        source: ThreeWayTextMergeSource,
        inspectItem: () throws -> Void
    ) throws {
        for (index, line) in document.lines.enumerated() {
            try inspectItem()
            let (number, overflow) = index.addingReportingOverflow(1)
            guard !overflow, line.source == source, line.number == number else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
        }
    }

    private static func isValid(_ range: Range<Int>, count: Int) -> Bool {
        range.lowerBound >= 0
            && range.upperBound >= range.lowerBound
            && range.upperBound <= count
    }

    private static func validate(
        regionLines: [ThreeWayTextMergeLine],
        sourceLines: [ThreeWayTextMergeLine],
        range: Range<Int>,
        inspectItem: () throws -> Void
    ) throws {
        guard regionLines.count == range.count else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
        for (regionLine, sourceLine) in zip(regionLines, sourceLines[range]) {
            try inspectItem()
            guard regionLine.id == sourceLine.id,
                try recordsAreExactlyEqual(
                    regionLine,
                    sourceLine,
                    inspectItem: inspectItem
                )
            else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
        }
    }

    private static func validateResultState(
        _ result: ThreeWayTextMergeResult,
        conflictCount: Int,
        inspectItem: () throws -> Void
    ) throws {
        guard result.conflicts.count == conflictCount else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
        var conflictIndex = 0
        for region in result.regions where region.isConflict {
            try inspectItem()
            guard result.conflicts[conflictIndex].id == region.id else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
            conflictIndex += 1
        }

        if conflictCount > 0 {
            guard result.mergedLines == nil, result.mergedText == nil else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
            return
        }
        guard let mergedLines = result.mergedLines, result.mergedText != nil else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }

        var mergedIndex = 0
        for region in result.regions {
            guard let regionLines = region.automaticallyMergedLines else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
            guard regionLines.count <= mergedLines.count - mergedIndex else {
                throw ThreeWayTextMergeError.invalidDiffResult
            }
            for regionLine in regionLines {
                try inspectItem()
                guard
                    try recordsAreExactlyEqual(
                        regionLine,
                        mergedLines[mergedIndex],
                        inspectItem: inspectItem
                    )
                else {
                    throw ThreeWayTextMergeError.invalidDiffResult
                }
                mergedIndex += 1
            }
        }
        guard mergedIndex == mergedLines.count else {
            throw ThreeWayTextMergeError.invalidDiffResult
        }
    }

    private static func recordsAreEquivalentToBase(
        sideLines: [ThreeWayTextMergeLine],
        baseLines: [ThreeWayTextMergeLine],
        sideRange: Range<Int>,
        baseRange: Range<Int>,
        sideLineCount: Int,
        baseLineCount: Int,
        inspectItem: () throws -> Void
    ) throws -> Bool {
        if try recordsAreExactlyEqual(sideLines, baseLines, inspectItem: inspectItem) {
            return true
        }
        guard sideLines.count == 1,
            baseLines.count == 1,
            baseRange.lowerBound + 1 < baseLineCount,
            sideRange.upperBound == sideLineCount,
            sideLines[0].lineEnding == nil,
            baseLines[0].lineEnding != nil
        else {
            return false
        }
        return try textIsExactlyEqual(
            sideLines[0].text,
            baseLines[0].text,
            inspectItem: inspectItem
        )
    }

    private static func recordsAreExactlyEqual(
        _ left: [ThreeWayTextMergeLine],
        _ right: [ThreeWayTextMergeLine],
        inspectItem: () throws -> Void
    ) throws -> Bool {
        guard left.count == right.count else { return false }
        for (leftLine, rightLine) in zip(left, right) {
            try inspectItem()
            if try !recordsAreExactlyEqual(
                leftLine,
                rightLine,
                inspectItem: inspectItem
            ) {
                return false
            }
        }
        return true
    }

    private static func recordsAreExactlyEqual(
        _ left: ThreeWayTextMergeLine,
        _ right: ThreeWayTextMergeLine,
        inspectItem: () throws -> Void
    ) throws -> Bool {
        guard left.lineEnding == right.lineEnding else { return false }
        return try textIsExactlyEqual(left.text, right.text, inspectItem: inspectItem)
    }

    private static func textIsExactlyEqual(
        _ left: String,
        _ right: String,
        inspectItem: () throws -> Void
    ) throws -> Bool {
        var leftBytes = left.utf8.makeIterator()
        var rightBytes = right.utf8.makeIterator()
        var bytesUntilCheck = 64 * 1_024
        while true {
            let leftByte = leftBytes.next()
            let rightByte = rightBytes.next()
            guard leftByte == rightByte else { return false }
            guard leftByte != nil else { return true }
            bytesUntilCheck -= 1
            if bytesUntilCheck == 0 {
                try inspectItem()
                bytesUntilCheck = 64 * 1_024
            }
        }
    }

    private static func saturatingIncrement(_ value: inout Int) {
        let (incremented, overflow) = value.addingReportingOverflow(1)
        value = overflow ? .max : incremented
    }
}
