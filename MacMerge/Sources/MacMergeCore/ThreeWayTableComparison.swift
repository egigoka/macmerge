import Foundation

public enum ThreeWayTableComparisonSource: String, CaseIterable, Equatable, Hashable, Sendable {
    case base
    case left
    case right
}

public enum ThreeWayTableComparisonResolution: Equatable, Sendable {
    case unchanged
    case left
    case right
    case identical
    case merged
    case conflict

    public var isConflict: Bool { self == .conflict }
    public var isChange: Bool { self != .unchanged }
}

public struct ThreeWayTableCellComparison: Identifiable, Equatable, Sendable {
    public struct ID: Equatable, Hashable, Sendable {
        public let rowID: ThreeWayTableRowComparison.ID
        public let baseIndex: Int?
        public let leftIndex: Int?
        public let rightIndex: Int?

        public init(
            rowID: ThreeWayTableRowComparison.ID,
            baseIndex: Int?,
            leftIndex: Int?,
            rightIndex: Int?
        ) {
            self.rowID = rowID
            self.baseIndex = baseIndex
            self.leftIndex = leftIndex
            self.rightIndex = rightIndex
        }
    }

    public let id: ID
    public let index: Int
    public let base: DelimitedTableCell?
    public let left: DelimitedTableCell?
    public let right: DelimitedTableCell?
    public let resolution: ThreeWayTableComparisonResolution

    public var isConflict: Bool { resolution.isConflict }
    public var isChange: Bool { resolution.isChange }

    fileprivate init(
        id: ID,
        index: Int,
        base: DelimitedTableCell?,
        left: DelimitedTableCell?,
        right: DelimitedTableCell?,
        resolution: ThreeWayTableComparisonResolution
    ) {
        self.id = id
        self.index = index
        self.base = base
        self.left = left
        self.right = right
        self.resolution = resolution
    }
}

public struct ThreeWayTableRowComparison: Identifiable, Equatable, Sendable {
    public struct ID: Equatable, Hashable, Sendable {
        public let baseIndex: Int?
        public let leftIndex: Int?
        public let rightIndex: Int?

        public init(baseIndex: Int?, leftIndex: Int?, rightIndex: Int?) {
            self.baseIndex = baseIndex
            self.leftIndex = leftIndex
            self.rightIndex = rightIndex
        }
    }

    public let id: ID
    public let index: Int
    public let base: DelimitedTableRow?
    public let left: DelimitedTableRow?
    public let right: DelimitedTableRow?
    public let cells: [ThreeWayTableCellComparison]
    public let resolution: ThreeWayTableComparisonResolution

    public var isConflict: Bool { resolution.isConflict }
    public var isChange: Bool { resolution.isChange }

    fileprivate init(
        id: ID,
        index: Int,
        base: DelimitedTableRow?,
        left: DelimitedTableRow?,
        right: DelimitedTableRow?,
        cells: [ThreeWayTableCellComparison],
        resolution: ThreeWayTableComparisonResolution
    ) {
        self.id = id
        self.index = index
        self.base = base
        self.left = left
        self.right = right
        self.cells = cells
        self.resolution = resolution
    }
}

public enum ThreeWayTableCellChangeKind: Equatable, Sendable {
    case left
    case right
    case identical
}

public struct ThreeWayTableCellChange: Identifiable, Equatable, Sendable {
    public var id: ThreeWayTableCellComparison.ID { cell.id }
    public let cell: ThreeWayTableCellComparison
    public let kind: ThreeWayTableCellChangeKind

    fileprivate init(cell: ThreeWayTableCellComparison, kind: ThreeWayTableCellChangeKind) {
        self.cell = cell
        self.kind = kind
    }
}

public enum ThreeWayTableCellConflictKind: Equatable, Sendable {
    case divergentInsertion
    case deletionVersusChange
    case divergentChange
}

public struct ThreeWayTableCellConflict: Identifiable, Equatable, Sendable {
    public var id: ThreeWayTableCellComparison.ID { cell.id }
    public let cell: ThreeWayTableCellComparison
    public let kind: ThreeWayTableCellConflictKind

    fileprivate init(cell: ThreeWayTableCellComparison, kind: ThreeWayTableCellConflictKind) {
        self.cell = cell
        self.kind = kind
    }
}

public enum ThreeWayTableRowConflictKind: Equatable, Sendable {
    case conflictingCells
    case deletionVersusChange
}

public struct ThreeWayTableRowConflict: Identifiable, Equatable, Sendable {
    public var id: ThreeWayTableRowComparison.ID { row.id }
    public let row: ThreeWayTableRowComparison
    public let kind: ThreeWayTableRowConflictKind
    public let cells: [ThreeWayTableCellConflict]

    fileprivate init(
        row: ThreeWayTableRowComparison,
        kind: ThreeWayTableRowConflictKind,
        cells: [ThreeWayTableCellConflict]
    ) {
        self.row = row
        self.kind = kind
        self.cells = cells
    }
}

public struct ThreeWayTableResolutionCounts: Equatable, Sendable {
    public let unchanged: Int
    public let left: Int
    public let right: Int
    public let identical: Int
    public let merged: Int
    public let conflicts: Int

    public var changes: Int { left + right + identical + merged + conflicts }
    public var total: Int { unchanged + changes }

    fileprivate init(
        unchanged: Int,
        left: Int,
        right: Int,
        identical: Int,
        merged: Int,
        conflicts: Int
    ) {
        self.unchanged = unchanged
        self.left = left
        self.right = right
        self.identical = identical
        self.merged = merged
        self.conflicts = conflicts
    }
}

public struct ThreeWayTableComparisonSummary: Equatable, Sendable {
    public let rows: ThreeWayTableResolutionCounts
    public let cells: ThreeWayTableResolutionCounts

    fileprivate init(
        rows: ThreeWayTableResolutionCounts,
        cells: ThreeWayTableResolutionCounts
    ) {
        self.rows = rows
        self.cells = cells
    }
}

public struct ThreeWayTableComparisonResult: Equatable, Sendable {
    public let base: DelimitedTable
    public let left: DelimitedTable
    public let right: DelimitedTable
    public let rows: [ThreeWayTableRowComparison]
    public let changes: [ThreeWayTableCellChange]
    public let conflicts: [ThreeWayTableRowConflict]
    public let cellConflicts: [ThreeWayTableCellConflict]
    public let summary: ThreeWayTableComparisonSummary
    public let baseToLeftAlignment: TableComparisonAlignment
    public let baseToRightAlignment: TableComparisonAlignment

    public var hasChanges: Bool { summary.rows.changes > 0 }
    public var hasConflicts: Bool { !conflicts.isEmpty }
    public var isUnchanged: Bool { !hasChanges }
    public var alignment: TableComparisonAlignment {
        baseToLeftAlignment == .exact && baseToRightAlignment == .exact
            ? .exact
            : .boundedFallback
    }

    fileprivate init(
        base: DelimitedTable,
        left: DelimitedTable,
        right: DelimitedTable,
        rows: [ThreeWayTableRowComparison],
        changes: [ThreeWayTableCellChange],
        conflicts: [ThreeWayTableRowConflict],
        cellConflicts: [ThreeWayTableCellConflict],
        summary: ThreeWayTableComparisonSummary,
        baseToLeftAlignment: TableComparisonAlignment,
        baseToRightAlignment: TableComparisonAlignment
    ) {
        self.base = base
        self.left = left
        self.right = right
        self.rows = rows
        self.changes = changes
        self.conflicts = conflicts
        self.cellConflicts = cellConflicts
        self.summary = summary
        self.baseToLeftAlignment = baseToLeftAlignment
        self.baseToRightAlignment = baseToRightAlignment
    }
}

public struct ThreeWayTableComparisonOptions: Equatable, Sendable {
    public static let `default` = ThreeWayTableComparisonOptions()

    public let parsingOptions: DelimitedTableParsingOptions
    public let comparisonOptions: TableComparisonOptions
    public let maximumComparedValueBytes: Int
    public let maximumResultRows: Int
    public let maximumResultCells: Int

    public init(
        parsingOptions: DelimitedTableParsingOptions = .commaSeparated,
        comparisonOptions: TableComparisonOptions = .default,
        maximumComparedValueBytes: Int = 192 * 1024 * 1024,
        maximumResultRows: Int = 3 * 1_048_576,
        maximumResultCells: Int = 3 * 1_048_576
    ) {
        self.parsingOptions = parsingOptions
        self.comparisonOptions = comparisonOptions
        self.maximumComparedValueBytes = maximumComparedValueBytes
        self.maximumResultRows = maximumResultRows
        self.maximumResultCells = maximumResultCells
    }
}

public enum ThreeWayTableComparisonValidationIssue: Equatable, Sendable {
    case invalidSourceByteCount
    case invalidDelimiter
    case invalidQuote
    case delimiterMatchesQuote
    case invalidRowIndex(expected: Int, actual: Int)
    case emptyRow(rowIndex: Int)
    case invalidRowSourceRange(rowIndex: Int)
    case invalidRowSourceLine(rowIndex: Int)
    case invalidCellIndex(rowIndex: Int, expected: Int, actual: Int)
    case invalidCellSourceRange(rowIndex: Int, columnIndex: Int)
    case invalidCellSourceLocation(rowIndex: Int, columnIndex: Int)
}

public enum ThreeWayTableComparisonError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case invalidParsingOptions(DelimitedTableParseError)
    case invalidTable(
        source: ThreeWayTableComparisonSource,
        issue: ThreeWayTableComparisonValidationIssue
    )
    case parsingFailed(source: ThreeWayTableComparisonSource, error: DelimitedTableParseError)
    case comparisonFailed(source: ThreeWayTableComparisonSource, error: TableComparisonError)
    case comparedValuesTooLarge(maximumBytes: Int)
    case tooManyResultRows(maximumRows: Int)
    case tooManyResultCells(maximumCells: Int)
    case invalidComparisonResult(source: ThreeWayTableComparisonSource)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Three-way table-comparison limits are invalid."
        case .invalidParsingOptions(let error):
            "Three-way table parsing options are invalid: \(error.localizedDescription)"
        case .invalidTable(let source, let issue):
            "Three-way table \(source.rawValue) input is invalid: \(Self.description(of: issue))"
        case .parsingFailed(let source, let error):
            "Three-way table \(source.rawValue) input could not be parsed: \(error.localizedDescription)"
        case .comparisonFailed(let source, let error):
            "Three-way table base-to-\(source.rawValue) alignment failed: \(error.localizedDescription)"
        case .comparedValuesTooLarge(let maximumBytes):
            "Three-way table values exceed the \(maximumBytes)-byte comparison limit."
        case .tooManyResultRows(let maximumRows):
            "Three-way table comparison exceeds the \(maximumRows)-row result limit."
        case .tooManyResultCells(let maximumCells):
            "Three-way table comparison exceeds the \(maximumCells)-cell result limit."
        case .invalidComparisonResult(let source):
            "Base-to-\(source.rawValue) table comparison returned an invalid row mapping."
        case .cancelled:
            "Three-way table comparison was cancelled."
        }
    }

    private static func description(
        of issue: ThreeWayTableComparisonValidationIssue
    ) -> String {
        switch issue {
        case .invalidSourceByteCount:
            "source byte count is negative"
        case .invalidDelimiter:
            "delimiter is invalid"
        case .invalidQuote:
            "quote is invalid"
        case .delimiterMatchesQuote:
            "delimiter and quote match"
        case .invalidRowIndex(let expected, let actual):
            "row index \(actual) does not match position \(expected)"
        case .emptyRow(let rowIndex):
            "row \(rowIndex) has no cells"
        case .invalidRowSourceRange(let rowIndex):
            "row \(rowIndex) has an invalid source range"
        case .invalidRowSourceLine(let rowIndex):
            "row \(rowIndex) has an invalid source line"
        case .invalidCellIndex(let rowIndex, let expected, let actual):
            "cell index \(actual) in row \(rowIndex) does not match position \(expected)"
        case .invalidCellSourceRange(let rowIndex, let columnIndex):
            "cell \(rowIndex):\(columnIndex) has an invalid source range"
        case .invalidCellSourceLocation(let rowIndex, let columnIndex):
            "cell \(rowIndex):\(columnIndex) has an invalid source location"
        }
    }
}

public enum ThreeWayTableComparison: Sendable {
    public static func compare(
        base: DelimitedTable,
        left: DelimitedTable,
        right: DelimitedTable,
        options: ThreeWayTableComparisonOptions = .default
    ) throws -> ThreeWayTableComparisonResult {
        try validate(options)
        try checkCancellation()
        let comparedValueBytes = try validate(
            tables: [(.base, base), (.left, left), (.right, right)],
            maximumComparedValueBytes: options.maximumComparedValueBytes
        )
        guard comparedValueBytes <= options.maximumComparedValueBytes else {
            throw ThreeWayTableComparisonError.comparedValuesTooLarge(
                maximumBytes: options.maximumComparedValueBytes
            )
        }

        let leftComparison = try pairComparison(
            base: base,
            side: left,
            source: .left,
            options: options.comparisonOptions
        )
        let rightComparison = try pairComparison(
            base: base,
            side: right,
            source: .right,
            options: options.comparisonOptions
        )
        let leftAlignment = try sideAlignment(
            result: leftComparison,
            baseRowCount: base.rows.count,
            sideRowCount: left.rows.count,
            source: .left
        )
        let rightAlignment = try sideAlignment(
            result: rightComparison,
            baseRowCount: base.rows.count,
            sideRowCount: right.rows.count,
            source: .right
        )

        var rows: [ThreeWayTableRowComparison] = []
        rows.reserveCapacity(min(options.maximumResultRows, max(base.rows.count, left.rows.count, right.rows.count)))
        var resultCellCount = 0

        func appendRow(
            baseRow: DelimitedTableRow?,
            leftRow: DelimitedTableRow?,
            rightRow: DelimitedTableRow?
        ) throws {
            guard rows.count < options.maximumResultRows else {
                throw ThreeWayTableComparisonError.tooManyResultRows(
                    maximumRows: options.maximumResultRows
                )
            }
            let cellCount = max(
                baseRow?.cells.count ?? 0,
                leftRow?.cells.count ?? 0,
                rightRow?.cells.count ?? 0
            )
            guard cellCount > 0 else {
                throw ThreeWayTableComparisonError.invalidComparisonResult(
                    source: baseRow == nil ? (leftRow == nil ? .right : .left) : .base
                )
            }
            guard cellCount <= options.maximumResultCells - resultCellCount else {
                throw ThreeWayTableComparisonError.tooManyResultCells(
                    maximumCells: options.maximumResultCells
                )
            }

            let rowID = ThreeWayTableRowComparison.ID(
                baseIndex: baseRow?.index,
                leftIndex: leftRow?.index,
                rightIndex: rightRow?.index
            )
            var cells: [ThreeWayTableCellComparison] = []
            cells.reserveCapacity(cellCount)
            for cellIndex in 0..<cellCount {
                if cellIndex.isMultiple(of: 4_096) { try checkCancellation() }
                let baseCell = cell(baseRow, at: cellIndex)
                let leftCell = cell(leftRow, at: cellIndex)
                let rightCell = cell(rightRow, at: cellIndex)
                let resolution = resolution(
                    base: baseCell?.value,
                    left: leftCell?.value,
                    right: rightCell?.value
                )
                cells.append(
                    ThreeWayTableCellComparison(
                        id: .init(
                            rowID: rowID,
                            baseIndex: baseCell?.index,
                            leftIndex: leftCell?.index,
                            rightIndex: rightCell?.index
                        ),
                        index: cellIndex,
                        base: baseCell,
                        left: leftCell,
                        right: rightCell,
                        resolution: resolution
                    )
                )
            }
            resultCellCount += cellCount
            rows.append(
                ThreeWayTableRowComparison(
                    id: rowID,
                    index: rows.count,
                    base: baseRow,
                    left: leftRow,
                    right: rightRow,
                    cells: cells,
                    resolution: rowResolution(
                        base: baseRow,
                        left: leftRow,
                        right: rightRow,
                        cells: cells
                    )
                )
            )
        }

        for boundary in 0...base.rows.count {
            try checkCancellation()
            let leftInsertions = leftAlignment.insertions[boundary]
            let rightInsertions = rightAlignment.insertions[boundary]
            let insertionCount = max(leftInsertions.count, rightInsertions.count)
            for offset in 0..<insertionCount {
                try appendRow(
                    baseRow: nil,
                    leftRow: optionalElement(leftInsertions, at: offset),
                    rightRow: optionalElement(rightInsertions, at: offset)
                )
            }
            if boundary < base.rows.count {
                try appendRow(
                    baseRow: base.rows[boundary],
                    leftRow: leftAlignment.rows[boundary],
                    rightRow: rightAlignment.rows[boundary]
                )
            }
        }
        try checkCancellation()

        let classifications = try classifications(rows)
        return ThreeWayTableComparisonResult(
            base: base,
            left: left,
            right: right,
            rows: rows,
            changes: classifications.changes,
            conflicts: classifications.conflicts,
            cellConflicts: classifications.cellConflicts,
            summary: classifications.summary,
            baseToLeftAlignment: leftComparison.alignment,
            baseToRightAlignment: rightComparison.alignment
        )
    }

    public static func compare(
        base: String,
        left: String,
        right: String,
        options: ThreeWayTableComparisonOptions = .default
    ) throws -> ThreeWayTableComparisonResult {
        try validate(options)
        let baseTable = try parse(base, source: .base, options: options.parsingOptions)
        let leftTable = try parse(left, source: .left, options: options.parsingOptions)
        let rightTable = try parse(right, source: .right, options: options.parsingOptions)
        return try compare(base: baseTable, left: leftTable, right: rightTable, options: options)
    }

    private struct SideAlignment {
        let insertions: [[DelimitedTableRow]]
        let rows: [DelimitedTableRow?]
    }

    private struct Classifications {
        let changes: [ThreeWayTableCellChange]
        let conflicts: [ThreeWayTableRowConflict]
        let cellConflicts: [ThreeWayTableCellConflict]
        let summary: ThreeWayTableComparisonSummary
    }

    private struct MutableCounts {
        var unchanged = 0
        var left = 0
        var right = 0
        var identical = 0
        var merged = 0
        var conflicts = 0

        mutating func add(_ resolution: ThreeWayTableComparisonResolution) {
            switch resolution {
            case .unchanged: unchanged += 1
            case .left: left += 1
            case .right: right += 1
            case .identical: identical += 1
            case .merged: merged += 1
            case .conflict: conflicts += 1
            }
        }

        var result: ThreeWayTableResolutionCounts {
            ThreeWayTableResolutionCounts(
                unchanged: unchanged,
                left: left,
                right: right,
                identical: identical,
                merged: merged,
                conflicts: conflicts
            )
        }
    }

    private static func validate(_ options: ThreeWayTableComparisonOptions) throws {
        guard options.maximumComparedValueBytes >= 0,
            options.maximumResultRows >= 0,
            options.maximumResultCells >= 0,
            options.comparisonOptions.maximumExactEditDistance >= 0,
            options.comparisonOptions.maximumAlignmentWork >= 0,
            options.comparisonOptions.maximumComparedRows >= 0,
            options.comparisonOptions.maximumComparedCells >= 0
        else {
            throw ThreeWayTableComparisonError.invalidLimits
        }
        do {
            _ = try DelimitedTableParser.parse("", options: options.parsingOptions)
        } catch DelimitedTableParseError.cancelled {
            throw ThreeWayTableComparisonError.cancelled
        } catch let error as DelimitedTableParseError {
            throw ThreeWayTableComparisonError.invalidParsingOptions(error)
        }
    }

    private static func validate(
        tables: [(ThreeWayTableComparisonSource, DelimitedTable)],
        maximumComparedValueBytes: Int
    ) throws -> Int {
        var valueBytes = 0
        for (source, table) in tables {
            try validate(table, source: source)
            for (rowIndex, row) in table.rows.enumerated() {
                if rowIndex.isMultiple(of: 4_096) { try checkCancellation() }
                for cell in row.cells {
                    let byteCount = cell.value.utf8.count
                    guard byteCount <= maximumComparedValueBytes - valueBytes else {
                        throw ThreeWayTableComparisonError.comparedValuesTooLarge(
                            maximumBytes: maximumComparedValueBytes
                        )
                    }
                    valueBytes += byteCount
                }
            }
        }
        return valueBytes
    }

    private static func validate(
        _ table: DelimitedTable,
        source: ThreeWayTableComparisonSource
    ) throws {
        guard table.sourceUTF8ByteCount >= 0 else {
            throw invalidTable(source, .invalidSourceByteCount)
        }
        guard validStructuralCharacter(table.delimiter) else {
            throw invalidTable(source, .invalidDelimiter)
        }
        if let quote = table.quote {
            guard validStructuralCharacter(quote) else {
                throw invalidTable(source, .invalidQuote)
            }
            guard quote != table.delimiter else {
                throw invalidTable(source, .delimiterMatchesQuote)
            }
        }

        var previousRowRangeEnd = 0
        var previousRowSourceLine = 1
        for (rowIndex, row) in table.rows.enumerated() {
            if rowIndex.isMultiple(of: 4_096) { try checkCancellation() }
            guard row.index == rowIndex else {
                throw invalidTable(
                    source,
                    .invalidRowIndex(expected: rowIndex, actual: row.index)
                )
            }
            guard !row.cells.isEmpty else {
                throw invalidTable(source, .emptyRow(rowIndex: rowIndex))
            }
            guard row.sourceUTF8Range.lowerBound >= previousRowRangeEnd,
                row.sourceUTF8Range.upperBound <= table.sourceUTF8ByteCount
            else {
                throw invalidTable(source, .invalidRowSourceRange(rowIndex: rowIndex))
            }
            guard row.sourceLine >= previousRowSourceLine, row.sourceLine > 0 else {
                throw invalidTable(source, .invalidRowSourceLine(rowIndex: rowIndex))
            }

            for (columnIndex, cell) in row.cells.enumerated() {
                if columnIndex != 0, columnIndex.isMultiple(of: 4_096) {
                    try checkCancellation()
                }
                guard cell.index == columnIndex else {
                    throw invalidTable(
                        source,
                        .invalidCellIndex(
                            rowIndex: rowIndex,
                            expected: columnIndex,
                            actual: cell.index
                        )
                    )
                }
                guard cell.sourceUTF8Range.lowerBound >= row.sourceUTF8Range.lowerBound,
                    cell.sourceUTF8Range.upperBound <= row.sourceUTF8Range.upperBound
                else {
                    throw invalidTable(
                        source,
                        .invalidCellSourceRange(rowIndex: rowIndex, columnIndex: columnIndex)
                    )
                }
                let location = cell.sourceLocation
                guard location.line >= row.sourceLine,
                    location.column > 0,
                    location.utf8Offset == cell.sourceUTF8Range.lowerBound
                else {
                    throw invalidTable(
                        source,
                        .invalidCellSourceLocation(rowIndex: rowIndex, columnIndex: columnIndex)
                    )
                }
            }
            previousRowRangeEnd = row.sourceUTF8Range.upperBound
            previousRowSourceLine = row.sourceLine
        }
    }

    private static func validStructuralCharacter(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        return scalar != "\0" && scalar != "\r" && scalar != "\n"
    }

    private static func invalidTable(
        _ source: ThreeWayTableComparisonSource,
        _ issue: ThreeWayTableComparisonValidationIssue
    ) -> ThreeWayTableComparisonError {
        .invalidTable(source: source, issue: issue)
    }

    private static func parse(
        _ input: String,
        source: ThreeWayTableComparisonSource,
        options: DelimitedTableParsingOptions
    ) throws -> DelimitedTable {
        do {
            return try DelimitedTableParser.parse(input, options: options)
        } catch DelimitedTableParseError.cancelled {
            throw ThreeWayTableComparisonError.cancelled
        } catch let error as DelimitedTableParseError {
            throw ThreeWayTableComparisonError.parsingFailed(source: source, error: error)
        }
    }

    private static func pairComparison(
        base: DelimitedTable,
        side: DelimitedTable,
        source: ThreeWayTableComparisonSource,
        options: TableComparisonOptions
    ) throws -> TableComparisonResult {
        do {
            return try TableComparison.compare(left: base, right: side, options: options)
        } catch TableComparisonError.cancelled {
            throw ThreeWayTableComparisonError.cancelled
        } catch let error as TableComparisonError {
            throw ThreeWayTableComparisonError.comparisonFailed(source: source, error: error)
        }
    }

    private static func sideAlignment(
        result: TableComparisonResult,
        baseRowCount: Int,
        sideRowCount: Int,
        source: ThreeWayTableComparisonSource
    ) throws -> SideAlignment {
        var insertions = Array(repeating: [DelimitedTableRow](), count: baseRowCount + 1)
        var rows = [DelimitedTableRow?](repeating: nil, count: baseRowCount)
        var basePosition = 0
        var sidePosition = 0

        for (resultIndex, row) in result.rows.enumerated() {
            if resultIndex.isMultiple(of: 4_096) { try checkCancellation() }
            guard row.index == resultIndex else {
                throw ThreeWayTableComparisonError.invalidComparisonResult(source: source)
            }
            if let baseRow = row.left {
                guard basePosition < baseRowCount,
                    row.leftIndex == basePosition,
                    baseRow.index == basePosition
                else {
                    throw ThreeWayTableComparisonError.invalidComparisonResult(source: source)
                }
                if let sideRow = row.right {
                    guard sidePosition < sideRowCount,
                        row.rightIndex == sidePosition,
                        sideRow.index == sidePosition
                    else {
                        throw ThreeWayTableComparisonError.invalidComparisonResult(source: source)
                    }
                    rows[basePosition] = sideRow
                    sidePosition += 1
                } else if row.rightIndex != nil {
                    throw ThreeWayTableComparisonError.invalidComparisonResult(source: source)
                }
                basePosition += 1
            } else {
                guard row.leftIndex == nil,
                    let sideRow = row.right,
                    basePosition <= baseRowCount,
                    sidePosition < sideRowCount,
                    row.rightIndex == sidePosition,
                    sideRow.index == sidePosition
                else {
                    throw ThreeWayTableComparisonError.invalidComparisonResult(source: source)
                }
                insertions[basePosition].append(sideRow)
                sidePosition += 1
            }
        }
        guard basePosition == baseRowCount, sidePosition == sideRowCount else {
            throw ThreeWayTableComparisonError.invalidComparisonResult(source: source)
        }
        return SideAlignment(insertions: insertions, rows: rows)
    }

    private static func cell(
        _ row: DelimitedTableRow?,
        at index: Int
    ) -> DelimitedTableCell? {
        guard let row, index < row.cells.count else { return nil }
        return row.cells[index]
    }

    private static func optionalElement<Element>(_ elements: [Element], at index: Int) -> Element? {
        index < elements.count ? elements[index] : nil
    }

    private static func resolution(
        base: String?,
        left: String?,
        right: String?
    ) -> ThreeWayTableComparisonResolution {
        if left == right { return left == base ? .unchanged : .identical }
        if left == base { return .right }
        if right == base { return .left }
        return .conflict
    }

    private static func rowResolution(
        base: DelimitedTableRow?,
        left: DelimitedTableRow?,
        right: DelimitedTableRow?,
        cells: [ThreeWayTableCellComparison]
    ) -> ThreeWayTableComparisonResolution {
        let baseValues = base?.values
        let leftValues = left?.values
        let rightValues = right?.values
        if leftValues == rightValues { return leftValues == baseValues ? .unchanged : .identical }
        if leftValues == baseValues { return .right }
        if rightValues == baseValues { return .left }
        if base != nil, left == nil || right == nil { return .conflict }

        var hasLeft = false
        var hasRight = false
        var hasIdentical = false
        for cell in cells {
            switch cell.resolution {
            case .unchanged:
                break
            case .left:
                hasLeft = true
            case .right:
                hasRight = true
            case .identical:
                hasIdentical = true
            case .merged:
                return .merged
            case .conflict:
                return .conflict
            }
        }
        if hasIdentical {
            return hasLeft || hasRight ? .merged : .identical
        }
        if hasLeft, hasRight { return .merged }
        if hasLeft { return .left }
        if hasRight { return .right }
        return .unchanged
    }

    private static func classifications(
        _ rows: [ThreeWayTableRowComparison]
    ) throws -> Classifications {
        var changes: [ThreeWayTableCellChange] = []
        var conflicts: [ThreeWayTableRowConflict] = []
        var allCellConflicts: [ThreeWayTableCellConflict] = []
        var rowCounts = MutableCounts()
        var cellCounts = MutableCounts()

        for (rowIndex, row) in rows.enumerated() {
            if rowIndex.isMultiple(of: 4_096) { try checkCancellation() }
            rowCounts.add(row.resolution)
            var rowCellConflicts: [ThreeWayTableCellConflict] = []
            for cell in row.cells {
                cellCounts.add(cell.resolution)
                switch cell.resolution {
                case .unchanged:
                    break
                case .left:
                    changes.append(ThreeWayTableCellChange(cell: cell, kind: .left))
                case .right:
                    changes.append(ThreeWayTableCellChange(cell: cell, kind: .right))
                case .identical:
                    changes.append(ThreeWayTableCellChange(cell: cell, kind: .identical))
                case .merged:
                    preconditionFailure("Individual table cells cannot have a merged resolution")
                case .conflict:
                    let kind: ThreeWayTableCellConflictKind
                    if cell.base == nil {
                        kind = .divergentInsertion
                    } else if cell.left == nil || cell.right == nil {
                        kind = .deletionVersusChange
                    } else {
                        kind = .divergentChange
                    }
                    rowCellConflicts.append(ThreeWayTableCellConflict(cell: cell, kind: kind))
                }
            }
            allCellConflicts.append(contentsOf: rowCellConflicts)
            if row.isConflict {
                let kind: ThreeWayTableRowConflictKind =
                    row.base != nil && (row.left == nil || row.right == nil)
                    ? .deletionVersusChange
                    : .conflictingCells
                conflicts.append(
                    ThreeWayTableRowConflict(
                        row: row,
                        kind: kind,
                        cells: rowCellConflicts
                    )
                )
            }
        }
        return Classifications(
            changes: changes,
            conflicts: conflicts,
            cellConflicts: allCellConflicts,
            summary: ThreeWayTableComparisonSummary(
                rows: rowCounts.result,
                cells: cellCounts.result
            )
        )
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw ThreeWayTableComparisonError.cancelled }
    }
}
