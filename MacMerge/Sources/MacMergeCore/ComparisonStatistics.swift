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
           selectedSignificantIndex < significant {
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
