import Foundation

public struct DelimitedTableSourceLocation: Equatable, Sendable {
    public let line: Int
    public let column: Int
    public let utf8Offset: Int

    public init(line: Int, column: Int, utf8Offset: Int) {
        self.line = line
        self.column = column
        self.utf8Offset = utf8Offset
    }
}

public enum DelimitedTableRowTerminator: Equatable, Sendable {
    case none
    case lineFeed
    case carriageReturn
    case carriageReturnLineFeed
}

public struct DelimitedTableCell: Equatable, Sendable {
    public let index: Int
    public let value: String
    public let sourceUTF8Range: Range<Int>
    public let sourceLocation: DelimitedTableSourceLocation
    public let wasQuoted: Bool

    public init(
        index: Int,
        value: String,
        sourceUTF8Range: Range<Int> = 0..<0,
        sourceLocation: DelimitedTableSourceLocation = DelimitedTableSourceLocation(
            line: 1,
            column: 1,
            utf8Offset: 0
        ),
        wasQuoted: Bool = false
    ) {
        self.index = index
        self.value = value
        self.sourceUTF8Range = sourceUTF8Range
        self.sourceLocation = sourceLocation
        self.wasQuoted = wasQuoted
    }
}

public struct DelimitedTableRow: Equatable, Sendable {
    public let index: Int
    public let cells: [DelimitedTableCell]
    public let sourceUTF8Range: Range<Int>
    public let sourceLine: Int
    public let terminator: DelimitedTableRowTerminator

    public var values: [String] { cells.map(\.value) }

    public init(
        index: Int,
        cells: [DelimitedTableCell],
        sourceUTF8Range: Range<Int> = 0..<0,
        sourceLine: Int = 1,
        terminator: DelimitedTableRowTerminator = .none
    ) {
        self.index = index
        self.cells = cells
        self.sourceUTF8Range = sourceUTF8Range
        self.sourceLine = sourceLine
        self.terminator = terminator
    }
}

public struct DelimitedTable: Equatable, Sendable {
    public let rows: [DelimitedTableRow]
    public let delimiter: Character
    public let quote: Character?
    public let sourceUTF8ByteCount: Int
    public let totalCellCount: Int

    public init(
        rows: [DelimitedTableRow],
        delimiter: Character,
        quote: Character?,
        sourceUTF8ByteCount: Int = 0
    ) {
        self.rows = rows
        self.delimiter = delimiter
        self.quote = quote
        self.sourceUTF8ByteCount = sourceUTF8ByteCount
        totalCellCount = rows.reduce(into: 0) { $0 += $1.cells.count }
    }
}

public struct DelimitedTableLimits: Equatable, Sendable {
    public static let `default` = DelimitedTableLimits()

    public let maximumInputBytes: Int
    public let maximumRows: Int
    public let maximumColumnsPerRow: Int
    public let maximumTotalCells: Int
    public let maximumCellBytes: Int

    public init(
        maximumInputBytes: Int = 64 * 1024 * 1024,
        maximumRows: Int = 1_048_576,
        maximumColumnsPerRow: Int = 16_384,
        maximumTotalCells: Int = 1_048_576,
        maximumCellBytes: Int = 16 * 1024 * 1024
    ) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumRows = maximumRows
        self.maximumColumnsPerRow = maximumColumnsPerRow
        self.maximumTotalCells = maximumTotalCells
        self.maximumCellBytes = maximumCellBytes
    }
}

public struct DelimitedTableParsingOptions: Equatable, Sendable {
    public static let commaSeparated = DelimitedTableParsingOptions()
    public static let tabSeparated = DelimitedTableParsingOptions(delimiter: "\t")

    public let delimiter: Character
    public let quote: Character?
    public let allowsNewlinesInQuotedCells: Bool
    public let limits: DelimitedTableLimits

    public init(
        delimiter: Character = ",",
        quote: Character? = "\"",
        allowsNewlinesInQuotedCells: Bool = true,
        limits: DelimitedTableLimits = .default
    ) {
        self.delimiter = delimiter
        self.quote = quote
        self.allowsNewlinesInQuotedCells = allowsNewlinesInQuotedCells
        self.limits = limits
    }
}

public enum DelimitedTableParseError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case invalidDelimiter
    case invalidQuote
    case delimiterMatchesQuote
    case inputTooLarge(maximumBytes: Int)
    case tooManyRows(maximumRows: Int)
    case tooManyColumns(rowIndex: Int, maximumColumns: Int)
    case tooManyCells(maximumCells: Int)
    case cellTooLarge(rowIndex: Int, columnIndex: Int, maximumBytes: Int)
    case unexpectedQuote(DelimitedTableSourceLocation)
    case unexpectedCharacterAfterClosingQuote(DelimitedTableSourceLocation)
    case newlineInQuotedCell(DelimitedTableSourceLocation)
    case unterminatedQuotedCell(DelimitedTableSourceLocation)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Delimited-table limits are invalid."
        case .invalidDelimiter:
            "Delimiter must be one Unicode scalar other than NUL, carriage return, or line feed."
        case .invalidQuote:
            "Quote must be one Unicode scalar other than NUL, carriage return, or line feed."
        case .delimiterMatchesQuote:
            "Delimiter and quote must differ."
        case .inputTooLarge(let maximumBytes):
            "Delimited-table input exceeds the \(maximumBytes)-byte limit."
        case .tooManyRows(let maximumRows):
            "Delimited-table input exceeds the \(maximumRows)-row limit."
        case .tooManyColumns(let rowIndex, let maximumColumns):
            "Delimited-table row \(rowIndex) exceeds the \(maximumColumns)-column limit."
        case .tooManyCells(let maximumCells):
            "Delimited-table input exceeds the \(maximumCells)-cell limit."
        case .cellTooLarge(let rowIndex, let columnIndex, let maximumBytes):
            "Delimited-table cell \(rowIndex):\(columnIndex) exceeds the \(maximumBytes)-byte limit."
        case .unexpectedQuote(let location):
            "Unexpected quote at line \(location.line), column \(location.column)."
        case .unexpectedCharacterAfterClosingQuote(let location):
            "Unexpected character after closing quote at line \(location.line), column \(location.column)."
        case .newlineInQuotedCell(let location):
            "Quoted newline is disabled at line \(location.line), column \(location.column)."
        case .unterminatedQuotedCell(let location):
            "Quoted cell starting at line \(location.line), column \(location.column) is unterminated."
        case .cancelled:
            "Delimited-table parsing was cancelled."
        }
    }
}

public enum DelimitedTableParser: Sendable {
    public static func parse(
        _ input: String,
        options: DelimitedTableParsingOptions = .commaSeparated
    ) throws -> DelimitedTable {
        let delimiter = try validatedScalar(options.delimiter, isDelimiter: true)
        let quote = try options.quote.map { try validatedScalar($0, isDelimiter: false) }
        guard delimiter != quote else { throw DelimitedTableParseError.delimiterMatchesQuote }
        try validate(options.limits)

        let inputByteCount = input.utf8.count
        guard inputByteCount <= options.limits.maximumInputBytes else {
            throw DelimitedTableParseError.inputTooLarge(
                maximumBytes: options.limits.maximumInputBytes
            )
        }
        if Task.isCancelled { throw DelimitedTableParseError.cancelled }
        guard !input.isEmpty else {
            return DelimitedTable(
                rows: [],
                delimiter: options.delimiter,
                quote: options.quote,
                sourceUTF8ByteCount: 0
            )
        }

        var state = ParserState.start
        var rows: [DelimitedTableRow] = []
        rows.reserveCapacity(min(options.limits.maximumRows, 4_096))
        var cells: [DelimitedTableCell] = []
        cells.reserveCapacity(min(options.limits.maximumColumnsPerRow, 64))
        var cellValue = ""
        var cellByteCount = 0
        var totalCellCount = 0
        var cellWasQuoted = false
        var quotedCellLocation: DelimitedTableSourceLocation?

        var utf8Offset = 0
        var line = 1
        var column = 1
        var rowStartOffset = 0
        var rowStartLine = 1
        var cellStartOffset = 0
        var cellStartLocation = DelimitedTableSourceLocation(line: 1, column: 1, utf8Offset: 0)
        var pendingRecord = false
        var processedScalars = 0

        let scalars = input.unicodeScalars
        var scalarIndex = scalars.startIndex

        func location() -> DelimitedTableSourceLocation {
            DelimitedTableSourceLocation(line: line, column: column, utf8Offset: utf8Offset)
        }

        func appendScalar(_ scalar: Unicode.Scalar) throws {
            let byteLength = utf8Length(of: scalar)
            let (newByteCount, overflow) = cellByteCount.addingReportingOverflow(byteLength)
            guard !overflow, newByteCount <= options.limits.maximumCellBytes else {
                throw DelimitedTableParseError.cellTooLarge(
                    rowIndex: rows.count,
                    columnIndex: cells.count,
                    maximumBytes: options.limits.maximumCellBytes
                )
            }
            cellValue.unicodeScalars.append(scalar)
            cellByteCount = newByteCount
        }

        func finishCell(at endOffset: Int) throws {
            guard cells.count < options.limits.maximumColumnsPerRow else {
                throw DelimitedTableParseError.tooManyColumns(
                    rowIndex: rows.count,
                    maximumColumns: options.limits.maximumColumnsPerRow
                )
            }
            guard totalCellCount < options.limits.maximumTotalCells else {
                throw DelimitedTableParseError.tooManyCells(
                    maximumCells: options.limits.maximumTotalCells
                )
            }
            cells.append(
                DelimitedTableCell(
                    index: cells.count,
                    value: cellValue,
                    sourceUTF8Range: cellStartOffset..<endOffset,
                    sourceLocation: cellStartLocation,
                    wasQuoted: cellWasQuoted
                )
            )
            totalCellCount += 1
            cellValue = ""
            cellByteCount = 0
            cellWasQuoted = false
            quotedCellLocation = nil
            state = .start
        }

        func finishRow(
            at endOffset: Int,
            terminator: DelimitedTableRowTerminator
        ) throws {
            guard rows.count < options.limits.maximumRows else {
                throw DelimitedTableParseError.tooManyRows(
                    maximumRows: options.limits.maximumRows
                )
            }
            try finishCell(at: endOffset)
            rows.append(
                DelimitedTableRow(
                    index: rows.count,
                    cells: cells,
                    sourceUTF8Range: rowStartOffset..<endOffset,
                    sourceLine: rowStartLine,
                    terminator: terminator
                )
            )
            cells = []
            cells.reserveCapacity(min(options.limits.maximumColumnsPerRow, 64))
        }

        while scalarIndex != scalars.endIndex {
            if processedScalars & 0xFFF == 0, Task.isCancelled {
                throw DelimitedTableParseError.cancelled
            }
            processedScalars += 1

            let scalar = scalars[scalarIndex]
            let nextIndex = scalars.index(after: scalarIndex)
            let isCarriageReturnLineFeed =
                scalar == "\r"
                && nextIndex != scalars.endIndex
                && scalars[nextIndex] == "\n"
            let isNewline = scalar == "\r" || scalar == "\n"

            if isNewline {
                if state == .quoted {
                    guard options.allowsNewlinesInQuotedCells else {
                        throw DelimitedTableParseError.newlineInQuotedCell(location())
                    }
                    try appendScalar(scalar)
                    if isCarriageReturnLineFeed {
                        try appendScalar("\n")
                    }
                } else {
                    let terminator: DelimitedTableRowTerminator =
                        if isCarriageReturnLineFeed {
                            .carriageReturnLineFeed
                        } else if scalar == "\r" {
                            .carriageReturn
                        } else {
                            .lineFeed
                        }
                    try finishRow(at: utf8Offset, terminator: terminator)
                    pendingRecord = false
                }

                utf8Offset += isCarriageReturnLineFeed ? 2 : 1
                scalarIndex = isCarriageReturnLineFeed ? scalars.index(after: nextIndex) : nextIndex
                line += 1
                column = 1
                if state != .quoted {
                    rowStartOffset = utf8Offset
                    rowStartLine = line
                    cellStartOffset = utf8Offset
                    cellStartLocation = location()
                }
                continue
            }

            pendingRecord = true
            if scalar == delimiter, state != .quoted {
                guard state != .afterQuote || quote != nil else {
                    preconditionFailure("Parser entered quoted state with quoting disabled")
                }
                try finishCell(at: utf8Offset)
                utf8Offset += utf8Length(of: scalar)
                column += 1
                scalarIndex = nextIndex
                cellStartOffset = utf8Offset
                cellStartLocation = location()
                continue
            }

            if let quote, scalar == quote {
                switch state {
                case .start:
                    state = .quoted
                    cellWasQuoted = true
                    quotedCellLocation = location()
                case .unquoted:
                    throw DelimitedTableParseError.unexpectedQuote(location())
                case .quoted:
                    state = .afterQuote
                case .afterQuote:
                    try appendScalar(quote)
                    state = .quoted
                }
                utf8Offset += utf8Length(of: scalar)
                column += 1
                scalarIndex = nextIndex
                continue
            }

            switch state {
            case .afterQuote:
                throw DelimitedTableParseError.unexpectedCharacterAfterClosingQuote(location())
            case .start:
                state = .unquoted
                try appendScalar(scalar)
            case .unquoted, .quoted:
                try appendScalar(scalar)
            }
            utf8Offset += utf8Length(of: scalar)
            column += 1
            scalarIndex = nextIndex
        }

        if state == .quoted {
            throw DelimitedTableParseError.unterminatedQuotedCell(
                quotedCellLocation ?? cellStartLocation
            )
        }
        if pendingRecord {
            try finishRow(at: inputByteCount, terminator: .none)
        }
        if Task.isCancelled { throw DelimitedTableParseError.cancelled }

        return DelimitedTable(
            rows: rows,
            delimiter: options.delimiter,
            quote: options.quote,
            sourceUTF8ByteCount: inputByteCount
        )
    }

    public static func parse(
        _ input: String,
        delimiter: Character,
        quote: Character? = "\"",
        allowsNewlinesInQuotedCells: Bool = true,
        limits: DelimitedTableLimits = .default
    ) throws -> DelimitedTable {
        try parse(
            input,
            options: DelimitedTableParsingOptions(
                delimiter: delimiter,
                quote: quote,
                allowsNewlinesInQuotedCells: allowsNewlinesInQuotedCells,
                limits: limits
            )
        )
    }

    private enum ParserState {
        case start
        case unquoted
        case quoted
        case afterQuote
    }

    private static func validatedScalar(
        _ character: Character,
        isDelimiter: Bool
    ) throws -> Unicode.Scalar {
        let scalars = character.unicodeScalars
        guard scalars.count == 1,
            let scalar = scalars.first,
            scalar != "\0",
            scalar != "\r",
            scalar != "\n"
        else {
            throw isDelimiter
                ? DelimitedTableParseError.invalidDelimiter
                : DelimitedTableParseError.invalidQuote
        }
        return scalar
    }

    private static func validate(_ limits: DelimitedTableLimits) throws {
        guard limits.maximumInputBytes >= 0,
            limits.maximumRows > 0,
            limits.maximumColumnsPerRow > 0,
            limits.maximumTotalCells > 0,
            limits.maximumCellBytes >= 0
        else {
            throw DelimitedTableParseError.invalidLimits
        }
    }

    private static func utf8Length(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0...0x7F: 1
        case 0x80...0x7FF: 2
        case 0x800...0xFFFF: 3
        default: 4
        }
    }
}

public enum TableComparisonStatus: Equatable, Sendable {
    case equal
    case modified
    case removed
    case added
}

public struct TableCellComparison: Equatable, Sendable {
    public let index: Int
    public let leftIndex: Int?
    public let rightIndex: Int?
    public let left: DelimitedTableCell?
    public let right: DelimitedTableCell?
    public let status: TableComparisonStatus

    public init(
        index: Int,
        leftIndex: Int?,
        rightIndex: Int?,
        left: DelimitedTableCell?,
        right: DelimitedTableCell?,
        status: TableComparisonStatus
    ) {
        self.index = index
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.left = left
        self.right = right
        self.status = status
    }
}

public struct TableRowComparison: Equatable, Sendable {
    public let index: Int
    public let leftIndex: Int?
    public let rightIndex: Int?
    public let left: DelimitedTableRow?
    public let right: DelimitedTableRow?
    public let cells: [TableCellComparison]
    public let status: TableComparisonStatus

    public init(
        index: Int,
        leftIndex: Int?,
        rightIndex: Int?,
        left: DelimitedTableRow?,
        right: DelimitedTableRow?,
        cells: [TableCellComparison],
        status: TableComparisonStatus
    ) {
        self.index = index
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.left = left
        self.right = right
        self.cells = cells
        self.status = status
    }
}

public enum TableComparisonAlignment: Equatable, Sendable {
    case exact
    case boundedFallback
}

public struct TableComparisonSummary: Equatable, Sendable {
    public let equal: Int
    public let modified: Int
    public let removed: Int
    public let added: Int

    public var differences: Int { modified + removed + added }

    public init(rows: [TableRowComparison]) {
        var equal = 0
        var modified = 0
        var removed = 0
        var added = 0
        for row in rows {
            switch row.status {
            case .equal: equal += 1
            case .modified: modified += 1
            case .removed: removed += 1
            case .added: added += 1
            }
        }
        self.equal = equal
        self.modified = modified
        self.removed = removed
        self.added = added
    }

    fileprivate init(equal: Int, modified: Int, removed: Int, added: Int) {
        self.equal = equal
        self.modified = modified
        self.removed = removed
        self.added = added
    }
}

public struct TableComparisonResult: Equatable, Sendable {
    public let left: DelimitedTable
    public let right: DelimitedTable
    public let rows: [TableRowComparison]
    public let summary: TableComparisonSummary
    public let alignment: TableComparisonAlignment

    public var isEqual: Bool { summary.differences == 0 }

    public init(
        left: DelimitedTable,
        right: DelimitedTable,
        rows: [TableRowComparison],
        alignment: TableComparisonAlignment
    ) {
        self.left = left
        self.right = right
        self.rows = rows
        summary = TableComparisonSummary(rows: rows)
        self.alignment = alignment
    }

    fileprivate init(
        left: DelimitedTable,
        right: DelimitedTable,
        rows: [TableRowComparison],
        summary: TableComparisonSummary,
        alignment: TableComparisonAlignment
    ) {
        self.left = left
        self.right = right
        self.rows = rows
        self.summary = summary
        self.alignment = alignment
    }
}

public struct TableComparisonOptions: Equatable, Sendable {
    public static let `default` = TableComparisonOptions()

    public let maximumExactEditDistance: Int
    public let maximumAlignmentWork: Int
    public let maximumComparedRows: Int
    public let maximumComparedCells: Int

    public init(
        maximumExactEditDistance: Int = 2_048,
        maximumAlignmentWork: Int = 16 * 1_024 * 1_024,
        maximumComparedRows: Int = 2_097_152,
        maximumComparedCells: Int = 2_097_152
    ) {
        self.maximumExactEditDistance = maximumExactEditDistance
        self.maximumAlignmentWork = maximumAlignmentWork
        self.maximumComparedRows = maximumComparedRows
        self.maximumComparedCells = maximumComparedCells
    }
}

public enum TableComparisonError: Error, LocalizedError, Equatable, Sendable {
    case invalidLimits
    case tooManyRows(maximumRows: Int)
    case tooManyCells(maximumCells: Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Table-comparison limits are invalid."
        case .tooManyRows(let maximumRows):
            "Table comparison exceeds the \(maximumRows)-row limit."
        case .tooManyCells(let maximumCells):
            "Table comparison exceeds the \(maximumCells)-cell limit."
        case .cancelled:
            "Table comparison was cancelled."
        }
    }
}

public enum TableComparison: Sendable {
    public static func compare(
        left: DelimitedTable,
        right: DelimitedTable,
        options: TableComparisonOptions = .default
    ) throws -> TableComparisonResult {
        try validate(options)
        try checkCancellation()
        try preflight(left: left, right: right, options: options)

        let leftFingerprints = try fingerprints(for: left.rows)
        let rightFingerprints = try fingerprints(for: right.rows)
        var remainingAlignmentWork = options.maximumAlignmentWork
        var workSinceCancellationCheck = 0

        func consumeAlignmentWork(_ amount: Int) throws -> Bool {
            guard amount <= remainingAlignmentWork else { return false }
            remainingAlignmentWork -= amount
            workSinceCancellationCheck = saturatingAdd(workSinceCancellationCheck, amount)
            if workSinceCancellationCheck >= 0x1000 {
                try checkCancellation()
                workSinceCancellationCheck = 0
            }
            return true
        }

        var commonPrefixCount = 0
        let maximumPrefixCount = min(left.rows.count, right.rows.count)
        while commonPrefixCount < maximumPrefixCount {
            if commonPrefixCount & 0xFFF == 0 { try checkCancellation() }
            let leftFingerprint = leftFingerprints[commonPrefixCount]
            let rightFingerprint = rightFingerprints[commonPrefixCount]
            guard
                try consumeAlignmentWork(
                    rowComparisonWork(
                        leftFingerprint: leftFingerprint,
                        rightFingerprint: rightFingerprint
                    )
                )
            else {
                break
            }
            guard
                try rowsEqual(
                    left.rows[commonPrefixCount],
                    right.rows[commonPrefixCount],
                    leftFingerprint: leftFingerprint,
                    rightFingerprint: rightFingerprint
                )
            else {
                break
            }
            commonPrefixCount += 1
        }

        var commonSuffixCount = 0
        let maximumSuffixCount = min(left.rows.count, right.rows.count) - commonPrefixCount
        while commonSuffixCount < maximumSuffixCount {
            if commonSuffixCount & 0xFFF == 0 { try checkCancellation() }
            let leftIndex = left.rows.count - commonSuffixCount - 1
            let rightIndex = right.rows.count - commonSuffixCount - 1
            let leftFingerprint = leftFingerprints[leftIndex]
            let rightFingerprint = rightFingerprints[rightIndex]
            guard
                try consumeAlignmentWork(
                    rowComparisonWork(
                        leftFingerprint: leftFingerprint,
                        rightFingerprint: rightFingerprint
                    )
                )
            else {
                break
            }
            guard
                try rowsEqual(
                    left.rows[leftIndex],
                    right.rows[rightIndex],
                    leftFingerprint: leftFingerprint,
                    rightFingerprint: rightFingerprint
                )
            else {
                break
            }
            commonSuffixCount += 1
        }

        let leftMiddleCount = left.rows.count - commonPrefixCount - commonSuffixCount
        let rightMiddleCount = right.rows.count - commonPrefixCount - commonSuffixCount
        let exactAtoms = try exactEditAtoms(
            left: left.rows,
            right: right.rows,
            leftFingerprints: leftFingerprints,
            rightFingerprints: rightFingerprints,
            leftOffset: commonPrefixCount,
            rightOffset: commonPrefixCount,
            leftCount: leftMiddleCount,
            rightCount: rightMiddleCount,
            maximumExactEditDistance: options.maximumExactEditDistance,
            consumeAlignmentWork: consumeAlignmentWork
        )
        let middleAtoms =
            exactAtoms ?? [
                EditAtom(kind: .removed, count: leftMiddleCount),
                EditAtom(kind: .added, count: rightMiddleCount)
            ]

        var rows: [TableRowComparison] = []
        rows.reserveCapacity(
            try resultRowCount(
                prefixCount: commonPrefixCount,
                suffixCount: commonSuffixCount,
                middleAtoms: middleAtoms
            )
        )
        try appendEqualRows(
            count: commonPrefixCount,
            leftOffset: 0,
            rightOffset: 0,
            left: left.rows,
            right: right.rows,
            to: &rows
        )
        try appendAtoms(
            middleAtoms,
            leftOffset: commonPrefixCount,
            rightOffset: commonPrefixCount,
            left: left.rows,
            right: right.rows,
            to: &rows
        )
        try appendEqualRows(
            count: commonSuffixCount,
            leftOffset: left.rows.count - commonSuffixCount,
            rightOffset: right.rows.count - commonSuffixCount,
            left: left.rows,
            right: right.rows,
            to: &rows
        )
        let summary = try comparisonSummary(for: rows)

        return TableComparisonResult(
            left: left,
            right: right,
            rows: rows,
            summary: summary,
            alignment: exactAtoms == nil ? .boundedFallback : .exact
        )
    }

    public static func compare(
        left: String,
        right: String,
        parsingOptions: DelimitedTableParsingOptions = .commaSeparated,
        comparisonOptions: TableComparisonOptions = .default
    ) throws -> TableComparisonResult {
        let leftTable = try DelimitedTableParser.parse(left, options: parsingOptions)
        let rightTable = try DelimitedTableParser.parse(right, options: parsingOptions)
        return try compare(left: leftTable, right: rightTable, options: comparisonOptions)
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

    private struct RowFingerprint {
        let value: Int
        let comparisonWork: Int
    }

    private static func validate(_ options: TableComparisonOptions) throws {
        guard options.maximumExactEditDistance >= 0,
            options.maximumAlignmentWork >= 0,
            options.maximumComparedRows >= 0,
            options.maximumComparedCells >= 0
        else {
            throw TableComparisonError.invalidLimits
        }
    }

    private static func preflight(
        left: DelimitedTable,
        right: DelimitedTable,
        options: TableComparisonOptions
    ) throws {
        let (rowCount, rowOverflow) = left.rows.count.addingReportingOverflow(right.rows.count)
        guard !rowOverflow, rowCount <= options.maximumComparedRows else {
            throw TableComparisonError.tooManyRows(maximumRows: options.maximumComparedRows)
        }

        var cellCount = 0
        var processedRows = 0
        for row in left.rows {
            if processedRows & 0xFFF == 0 { try checkCancellation() }
            let (newCellCount, overflow) = cellCount.addingReportingOverflow(row.cells.count)
            guard !overflow, newCellCount <= options.maximumComparedCells else {
                throw TableComparisonError.tooManyCells(maximumCells: options.maximumComparedCells)
            }
            cellCount = newCellCount
            processedRows += 1
        }
        for row in right.rows {
            if processedRows & 0xFFF == 0 { try checkCancellation() }
            let (newCellCount, overflow) = cellCount.addingReportingOverflow(row.cells.count)
            guard !overflow, newCellCount <= options.maximumComparedCells else {
                throw TableComparisonError.tooManyCells(maximumCells: options.maximumComparedCells)
            }
            cellCount = newCellCount
            processedRows += 1
        }
    }

    private static func fingerprints(
        for rows: [DelimitedTableRow]
    ) throws -> [RowFingerprint] {
        var result: [RowFingerprint] = []
        result.reserveCapacity(rows.count)
        for (index, row) in rows.enumerated() {
            if index & 0xFFF == 0 { try checkCancellation() }
            result.append(try fingerprint(row))
        }
        return result
    }

    private static func fingerprint(_ row: DelimitedTableRow) throws -> RowFingerprint {
        var hasher = Hasher()
        hasher.combine(row.cells.count)
        var utf8ByteCount = 0
        for (index, cell) in row.cells.enumerated() {
            if index != 0, index & 0x3FF == 0 { try checkCancellation() }
            hasher.combine(cell.value)
            utf8ByteCount = saturatingAdd(utf8ByteCount, cell.value.utf8.count)
        }
        return RowFingerprint(
            value: hasher.finalize(),
            comparisonWork: saturatingAdd(1, saturatingAdd(row.cells.count, utf8ByteCount))
        )
    }

    private static func rowsEqual(
        _ left: DelimitedTableRow,
        _ right: DelimitedTableRow,
        leftFingerprint: RowFingerprint,
        rightFingerprint: RowFingerprint
    ) throws -> Bool {
        guard leftFingerprint.value == rightFingerprint.value else { return false }
        return try rowValuesEqual(left, right)
    }

    private static func rowValuesEqual(
        _ left: DelimitedTableRow,
        _ right: DelimitedTableRow
    ) throws -> Bool {
        guard left.cells.count == right.cells.count else { return false }
        for index in left.cells.indices {
            if index != 0, index & 0x3FF == 0 { try checkCancellation() }
            if left.cells[index].value != right.cells[index].value { return false }
        }
        return true
    }

    private static func exactEditAtoms(
        left: [DelimitedTableRow],
        right: [DelimitedTableRow],
        leftFingerprints: [RowFingerprint],
        rightFingerprints: [RowFingerprint],
        leftOffset: Int,
        rightOffset: Int,
        leftCount: Int,
        rightCount: Int,
        maximumExactEditDistance: Int,
        consumeAlignmentWork: (Int) throws -> Bool
    ) throws -> [EditAtom]? {
        if leftCount == 0 {
            return rightCount == 0 ? [] : [EditAtom(kind: .added, count: rightCount)]
        }
        if rightCount == 0 { return [EditAtom(kind: .removed, count: leftCount)] }

        let (totalCount, overflow) = leftCount.addingReportingOverflow(rightCount)
        guard !overflow else { return nil }
        let maximumDistance = min(maximumExactEditDistance, totalCount)
        var trace: [[Int]] = []
        var previous: [Int] = []

        for distance in 0...maximumDistance {
            var current = [Int](repeating: 0, count: distance + 1)
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                guard try consumeAlignmentWork(1) else { return nil }

                var x: Int
                if distance == 0 {
                    x = 0
                } else if diagonal == -distance {
                    x = frontierValue(previous, distance: distance - 1, diagonal: diagonal + 1)
                } else if diagonal == distance {
                    x = frontierValue(previous, distance: distance - 1, diagonal: diagonal - 1) + 1
                } else {
                    let removedX = frontierValue(
                        previous,
                        distance: distance - 1,
                        diagonal: diagonal - 1
                    )
                    let addedX = frontierValue(
                        previous,
                        distance: distance - 1,
                        diagonal: diagonal + 1
                    )
                    x = removedX < addedX ? addedX : removedX + 1
                }
                var y = x - diagonal

                while x < leftCount, y < rightCount {
                    let leftFingerprint = leftFingerprints[leftOffset + x]
                    let rightFingerprint = rightFingerprints[rightOffset + y]
                    guard
                        try consumeAlignmentWork(
                            rowComparisonWork(
                                leftFingerprint: leftFingerprint,
                                rightFingerprint: rightFingerprint
                            )
                        )
                    else {
                        return nil
                    }
                    guard
                        try rowsEqual(
                            left[leftOffset + x],
                            right[rightOffset + y],
                            leftFingerprint: leftFingerprint,
                            rightFingerprint: rightFingerprint
                        )
                    else {
                        break
                    }
                    x += 1
                    y += 1
                }
                current[(diagonal + distance) / 2] = x
                if x >= leftCount, y >= rightCount {
                    trace.append(current)
                    return try backtrack(
                        trace: trace,
                        leftCount: leftCount,
                        rightCount: rightCount
                    )
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
    ) throws -> [EditAtom] {
        var x = leftCount
        var y = rightCount
        var reversed: [EditAtom] = []
        let finalDistance = trace.count - 1

        if finalDistance > 0 {
            for distance in stride(from: finalDistance, through: 1, by: -1) {
                if distance & 0x3FF == 0 { try checkCancellation() }
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
                let previousX = frontierValue(
                    previous,
                    distance: distance - 1,
                    diagonal: previousDiagonal
                )
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
        left: [DelimitedTableRow],
        right: [DelimitedTableRow],
        to rows: inout [TableRowComparison]
    ) throws {
        var leftOffset = leftOffset
        var rightOffset = rightOffset
        var atomIndex = 0
        while atomIndex < atoms.count {
            if atomIndex & 0x3FF == 0 { try checkCancellation() }
            let atom = atoms[atomIndex]
            if atom.kind == .equal {
                try appendEqualRows(
                    count: atom.count,
                    leftOffset: leftOffset,
                    rightOffset: rightOffset,
                    left: left,
                    right: right,
                    to: &rows
                )
                leftOffset += atom.count
                rightOffset += atom.count
                atomIndex += 1
                continue
            }

            var removedCount = 0
            var addedCount = 0
            while atomIndex < atoms.count, atoms[atomIndex].kind != .equal {
                if atomIndex & 0x3FF == 0 { try checkCancellation() }
                switch atoms[atomIndex].kind {
                case .equal: break
                case .removed: removedCount += atoms[atomIndex].count
                case .added: addedCount += atoms[atomIndex].count
                }
                atomIndex += 1
            }

            let modifiedCount = min(removedCount, addedCount)
            for offset in 0..<modifiedCount {
                if offset & 0x3FF == 0 { try checkCancellation() }
                let leftRow = left[leftOffset + offset]
                let rightRow = right[rightOffset + offset]
                rows.append(
                    try rowComparison(
                        index: rows.count,
                        left: leftRow,
                        right: rightRow,
                        status: try rowValuesEqual(leftRow, rightRow) ? .equal : .modified
                    )
                )
            }
            leftOffset += modifiedCount
            rightOffset += modifiedCount

            for offset in 0..<(removedCount - modifiedCount) {
                if offset & 0x3FF == 0 { try checkCancellation() }
                rows.append(
                    try rowComparison(
                        index: rows.count,
                        left: left[leftOffset + offset],
                        right: nil,
                        status: .removed
                    )
                )
            }
            leftOffset += removedCount - modifiedCount

            for offset in 0..<(addedCount - modifiedCount) {
                if offset & 0x3FF == 0 { try checkCancellation() }
                rows.append(
                    try rowComparison(
                        index: rows.count,
                        left: nil,
                        right: right[rightOffset + offset],
                        status: .added
                    )
                )
            }
            rightOffset += addedCount - modifiedCount
        }
    }

    private static func appendEqualRows(
        count: Int,
        leftOffset: Int,
        rightOffset: Int,
        left: [DelimitedTableRow],
        right: [DelimitedTableRow],
        to rows: inout [TableRowComparison]
    ) throws {
        for offset in 0..<count {
            if offset & 0x3FF == 0 { try checkCancellation() }
            rows.append(
                try rowComparison(
                    index: rows.count,
                    left: left[leftOffset + offset],
                    right: right[rightOffset + offset],
                    status: .equal
                )
            )
        }
    }

    private static func rowComparison(
        index: Int,
        left: DelimitedTableRow?,
        right: DelimitedTableRow?,
        status: TableComparisonStatus
    ) throws -> TableRowComparison {
        let cellCount = max(left?.cells.count ?? 0, right?.cells.count ?? 0)
        var cells: [TableCellComparison] = []
        cells.reserveCapacity(cellCount)
        for cellIndex in 0..<cellCount {
            if cellIndex != 0, cellIndex & 0x3FF == 0 { try checkCancellation() }
            let leftCell = left.flatMap { cellIndex < $0.cells.count ? $0.cells[cellIndex] : nil }
            let rightCell = right.flatMap { cellIndex < $0.cells.count ? $0.cells[cellIndex] : nil }
            let cellStatus: TableComparisonStatus
            switch (leftCell, rightCell) {
            case (.none, .some): cellStatus = .added
            case (.some, .none): cellStatus = .removed
            case (.some(let leftCell), .some(let rightCell)):
                cellStatus =
                    status == .equal || leftCell.value == rightCell.value
                    ? .equal
                    : .modified
            case (.none, .none):
                preconditionFailure("Cell comparison index is outside both rows")
            }
            cells.append(
                TableCellComparison(
                    index: cellIndex,
                    leftIndex: leftCell?.index,
                    rightIndex: rightCell?.index,
                    left: leftCell,
                    right: rightCell,
                    status: cellStatus
                )
            )
        }
        return TableRowComparison(
            index: index,
            leftIndex: left?.index,
            rightIndex: right?.index,
            left: left,
            right: right,
            cells: cells,
            status: status
        )
    }

    private static func resultRowCount(
        prefixCount: Int,
        suffixCount: Int,
        middleAtoms: [EditAtom]
    ) throws -> Int {
        var result = prefixCount + suffixCount
        var atomIndex = 0
        while atomIndex < middleAtoms.count {
            if atomIndex & 0x3FF == 0 { try checkCancellation() }
            if middleAtoms[atomIndex].kind == .equal {
                result += middleAtoms[atomIndex].count
                atomIndex += 1
                continue
            }

            var removedCount = 0
            var addedCount = 0
            while atomIndex < middleAtoms.count, middleAtoms[atomIndex].kind != .equal {
                if atomIndex & 0x3FF == 0 { try checkCancellation() }
                switch middleAtoms[atomIndex].kind {
                case .equal: break
                case .removed: removedCount += middleAtoms[atomIndex].count
                case .added: addedCount += middleAtoms[atomIndex].count
                }
                atomIndex += 1
            }
            result += max(removedCount, addedCount)
        }
        return result
    }

    private static func comparisonSummary(
        for rows: [TableRowComparison]
    ) throws -> TableComparisonSummary {
        var equal = 0
        var modified = 0
        var removed = 0
        var added = 0
        for (index, row) in rows.enumerated() {
            if index & 0xFFF == 0 { try checkCancellation() }
            switch row.status {
            case .equal: equal += 1
            case .modified: modified += 1
            case .removed: removed += 1
            case .added: added += 1
            }
        }
        return TableComparisonSummary(
            equal: equal,
            modified: modified,
            removed: removed,
            added: added
        )
    }

    private static func rowComparisonWork(
        leftFingerprint: RowFingerprint,
        rightFingerprint: RowFingerprint
    ) -> Int {
        guard leftFingerprint.value == rightFingerprint.value else { return 1 }
        return max(leftFingerprint.comparisonWork, rightFingerprint.comparisonWork)
    }

    private static func saturatingAdd(_ left: Int, _ right: Int) -> Int {
        let (result, overflow) = left.addingReportingOverflow(right)
        return overflow ? Int.max : result
    }

    private static func frontierValue(
        _ frontier: [Int],
        distance: Int,
        diagonal: Int
    ) -> Int {
        frontier[(diagonal + distance) / 2]
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw TableComparisonError.cancelled }
    }
}
