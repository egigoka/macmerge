import Foundation

public enum ComparisonReportFormat: String, CaseIterable, Equatable, Sendable {
    case plainText
    case csv
    case html

    public var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .csv: "csv"
        case .html: "html"
        }
    }

    public var mimeType: String {
        switch self {
        case .plainText: "text/plain; charset=utf-8"
        case .csv: "text/csv; charset=utf-8"
        case .html: "text/html; charset=utf-8"
        }
    }
}

public struct ComparisonReportRow: Equatable, Sendable {
    public let values: [String]
    public let sortKey: String

    /// `sortKey` defaults to the first value. Equal keys are ordered by all values.
    public init(values: [String], sortKey: String? = nil) {
        self.values = values
        self.sortKey = sortKey ?? values.first ?? ""
    }
}

public struct ComparisonReportSummaryItem: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ComparisonReportSummary: Equatable, Sendable {
    public let items: [ComparisonReportSummaryItem]

    public init(items: [ComparisonReportSummaryItem]) {
        self.items = items
    }

    public init(values: [String: String]) {
        self.init(items: values.map { ComparisonReportSummaryItem(label: $0.key, value: $0.value) })
    }
}

public struct ComparisonReportOutput: Equatable, Sendable {
    public let format: ComparisonReportFormat
    public let data: Data

    public var string: String { String(decoding: data, as: UTF8.self) }
    public var fileExtension: String { format.fileExtension }
    public var mimeType: String { format.mimeType }

    fileprivate init(format: ComparisonReportFormat, data: Data) {
        self.format = format
        self.data = data
    }
}

public enum ComparisonReportError: Error, LocalizedError, Equatable, Sendable {
    case invalidMaximumOutputBytes(Int)
    case noColumns
    case columnCountMismatch(rowIndex: Int, expected: Int, actual: Int)
    case tooManyRows(maximum: Int)
    case tooManyInputValues(maximum: Int)
    case inputTooLarge(maximumBytes: Int)
    case outputTooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidMaximumOutputBytes(let value):
            "Report output limit must be positive, not \(value)."
        case .noColumns:
            "A comparison report requires at least one column."
        case .columnCountMismatch(let rowIndex, let expected, let actual):
            "Report row \(rowIndex + 1) has \(actual) values; expected \(expected)."
        case .tooManyRows(let maximum):
            "Comparison report exceeds the \(maximum)-row input limit."
        case .tooManyInputValues(let maximum):
            "Comparison report exceeds the \(maximum)-value input limit."
        case .inputTooLarge(let maximumBytes):
            "Comparison report input exceeds the \(maximumBytes)-byte limit."
        case .outputTooLarge(let maximumBytes):
            "Comparison report exceeds the \(maximumBytes)-byte output limit."
        }
    }
}

public struct ComparisonReport: Equatable, Sendable {
    public static let defaultMaximumOutputBytes = 32 * 1024 * 1024
    public static let maximumInputBytes = 64 * 1024 * 1024
    public static let maximumInputValueCount = 4_000_000
    public static let maximumRowCount = 1_000_000

    @TaskLocal
    static var rowSortObserver: (@Sendable () -> Void)?

    public let title: String
    public let columns: [String]
    public let rows: [ComparisonReportRow]
    public let summary: ComparisonReportSummary?

    public init(
        title: String = "Comparison Report",
        columns: [String],
        rows: [ComparisonReportRow],
        summary: ComparisonReportSummary? = nil
    ) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.summary = summary
    }

    public func generate(
        format: ComparisonReportFormat,
        maximumOutputBytes: Int = ComparisonReport.defaultMaximumOutputBytes
    ) throws -> ComparisonReportOutput {
        guard maximumOutputBytes > 0 else {
            throw ComparisonReportError.invalidMaximumOutputBytes(maximumOutputBytes)
        }
        guard !columns.isEmpty else {
            throw ComparisonReportError.noColumns
        }
        guard rows.count <= Self.maximumRowCount else {
            throw ComparisonReportError.tooManyRows(maximum: Self.maximumRowCount)
        }
        for (index, row) in rows.enumerated() where row.values.count != columns.count {
            throw ComparisonReportError.columnCountMismatch(
                rowIndex: index,
                expected: columns.count,
                actual: row.values.count
            )
        }
        try preflightInputBudget()
        try preflightOutputBudget(format: format, maximumOutputBytes: maximumOutputBytes)

        Self.rowSortObserver?()
        let orderedRows = rows.enumerated().sorted(by: Self.rowsAreOrdered).map(\.element)
        let orderedSummary: [ComparisonReportSummaryItem]?
        switch format {
        case .plainText, .html:
            orderedSummary = summary?.items.sorted(by: Self.summaryItemsAreOrdered)
        case .csv:
            orderedSummary = nil
        }
        var output = BoundedUTF8Output(maximumBytes: maximumOutputBytes)
        try render(format: format, rows: orderedRows, summaryItems: orderedSummary, to: &output)

        return ComparisonReportOutput(format: format, data: output.data)
    }

    public func string(
        format: ComparisonReportFormat,
        maximumOutputBytes: Int = ComparisonReport.defaultMaximumOutputBytes
    ) throws -> String {
        try generate(format: format, maximumOutputBytes: maximumOutputBytes).string
    }

    public func data(
        format: ComparisonReportFormat,
        maximumOutputBytes: Int = ComparisonReport.defaultMaximumOutputBytes
    ) throws -> Data {
        try generate(format: format, maximumOutputBytes: maximumOutputBytes).data
    }

    private func preflightInputBudget() throws {
        var remainingValues = Self.maximumInputValueCount
        var remainingBytes = Self.maximumInputBytes

        func consume(_ value: String) throws {
            guard remainingValues > 0 else {
                throw ComparisonReportError.tooManyInputValues(maximum: Self.maximumInputValueCount)
            }
            remainingValues -= 1

            let byteCount = value.utf8.count
            guard byteCount <= remainingBytes else {
                throw ComparisonReportError.inputTooLarge(maximumBytes: Self.maximumInputBytes)
            }
            remainingBytes -= byteCount
        }

        try consume(title)
        for column in columns { try consume(column) }
        for row in rows {
            try consume(row.sortKey)
            for value in row.values { try consume(value) }
        }
        for item in summary?.items ?? [] {
            try consume(item.label)
            try consume(item.value)
        }
    }

    private func preflightOutputBudget(
        format: ComparisonReportFormat,
        maximumOutputBytes: Int
    ) throws {
        var output = BoundedUTF8Output(maximumBytes: maximumOutputBytes, storesBytes: false)
        try render(format: format, rows: rows, summaryItems: summary?.items, to: &output)
    }

    private func render(
        format: ComparisonReportFormat,
        rows: [ComparisonReportRow],
        summaryItems: [ComparisonReportSummaryItem]?,
        to output: inout BoundedUTF8Output
    ) throws {
        switch format {
        case .plainText:
            try renderPlainText(rows: rows, summaryItems: summaryItems, to: &output)
        case .csv:
            try renderCSV(rows: rows, to: &output)
        case .html:
            try renderHTML(rows: rows, summaryItems: summaryItems, to: &output)
        }
    }

    private func renderPlainText(
        rows: [ComparisonReportRow],
        summaryItems: [ComparisonReportSummaryItem]?,
        to output: inout BoundedUTF8Output
    ) throws {
        try output.appendPlainEscaped(title)
        try output.append("\n")

        if let summaryItems {
            try output.append("\nSummary\n")
            for item in summaryItems {
                try output.appendPlainEscaped(item.label)
                try output.append(": ")
                try output.appendPlainEscaped(item.value)
                try output.append("\n")
            }
        }

        try output.append("\n")
        try appendPlainTextRecord(columns, to: &output)
        for row in rows {
            try appendPlainTextRecord(row.values, to: &output)
        }
    }

    private func appendPlainTextRecord(
        _ values: [String],
        to output: inout BoundedUTF8Output
    ) throws {
        for (index, value) in values.enumerated() {
            if index != 0 { try output.append("\t") }
            try output.appendPlainEscaped(value)
        }
        try output.append("\n")
    }

    private func renderCSV(
        rows: [ComparisonReportRow],
        to output: inout BoundedUTF8Output
    ) throws {
        try appendCSVRecord(columns, to: &output)
        for row in rows {
            try appendCSVRecord(row.values, to: &output)
        }
    }

    private func appendCSVRecord(
        _ values: [String],
        to output: inout BoundedUTF8Output
    ) throws {
        for (index, value) in values.enumerated() {
            if index != 0 { try output.append(",") }
            try output.appendCSVField(value)
        }
        try output.append("\r\n")
    }

    private func renderHTML(
        rows: [ComparisonReportRow],
        summaryItems: [ComparisonReportSummaryItem]?,
        to output: inout BoundedUTF8Output
    ) throws {
        try output.append(
            """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>
            """
        )
        try output.appendHTMLEscaped(title)
        try output.append(
            """
            </title>
            <style>
            :root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}body{margin:2rem;background:Canvas;color:CanvasText}main{max-width:100%;overflow:auto}h1{font-size:1.5rem}.summary{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:.35rem 1rem}.summary dt{font-weight:600}.summary dd{margin:0}table{border-collapse:collapse;width:100%}th,td{border:1px solid color-mix(in srgb,CanvasText 30%,transparent);padding:.4rem .55rem;text-align:left;vertical-align:top;white-space:pre-wrap;overflow-wrap:anywhere}th{background:color-mix(in srgb,CanvasText 8%,Canvas)}tbody tr:nth-child(even){background:color-mix(in srgb,CanvasText 4%,Canvas)}
            </style>
            </head>
            <body>
            <main>
            <h1>
            """
        )
        try output.appendHTMLEscaped(title)
        try output.append("</h1>\n")

        if let summaryItems {
            try output.append("<section aria-labelledby=\"summary-heading\">\n<h2 id=\"summary-heading\">Summary</h2>\n<dl class=\"summary\">\n")
            for item in summaryItems {
                try output.append("<dt>")
                try output.appendHTMLEscaped(item.label)
                try output.append("</dt><dd>")
                try output.appendHTMLEscaped(item.value)
                try output.append("</dd>\n")
            }
            try output.append("</dl>\n</section>\n")
        }

        try output.append("<table>\n<thead><tr>")
        for column in columns {
            try output.append("<th scope=\"col\">")
            try output.appendHTMLEscaped(column)
            try output.append("</th>")
        }
        try output.append("</tr></thead>\n<tbody>\n")
        for row in rows {
            try output.append("<tr>")
            for value in row.values {
                try output.append("<td>")
                try output.appendHTMLEscaped(value)
                try output.append("</td>")
            }
            try output.append("</tr>\n")
        }
        try output.append("</tbody>\n</table>\n</main>\n</body>\n</html>\n")
    }

    private static func rowsAreOrdered(
        _ left: EnumeratedSequence<[ComparisonReportRow]>.Element,
        _ right: EnumeratedSequence<[ComparisonReportRow]>.Element
    ) -> Bool {
        let keyOrder = compareUTF8(left.element.sortKey, right.element.sortKey)
        if keyOrder != 0 { return keyOrder < 0 }

        for (leftValue, rightValue) in zip(left.element.values, right.element.values) {
            let valueOrder = compareUTF8(leftValue, rightValue)
            if valueOrder != 0 { return valueOrder < 0 }
        }
        if left.element.values.count != right.element.values.count {
            return left.element.values.count < right.element.values.count
        }
        return left.offset < right.offset
    }

    fileprivate static func summaryItemsAreOrdered(
        _ left: ComparisonReportSummaryItem,
        _ right: ComparisonReportSummaryItem
    ) -> Bool {
        let labelOrder = compareUTF8(left.label, right.label)
        if labelOrder != 0 { return labelOrder < 0 }
        return compareUTF8(left.value, right.value) < 0
    }

    private static func compareUTF8(_ left: String, _ right: String) -> Int {
        var leftIterator = left.utf8.makeIterator()
        var rightIterator = right.utf8.makeIterator()
        while true {
            switch (leftIterator.next(), rightIterator.next()) {
            case (let leftByte?, let rightByte?):
                if leftByte != rightByte { return leftByte < rightByte ? -1 : 1 }
            case (nil, nil):
                return 0
            case (nil, _?):
                return -1
            case (_?, nil):
                return 1
            }
        }
    }
}

private struct BoundedUTF8Output {
    private var bytes: [UInt8] = []
    private var byteCount = 0
    private let maximumBytes: Int
    private let storesBytes: Bool

    init(maximumBytes: Int, storesBytes: Bool = true) {
        self.maximumBytes = maximumBytes
        self.storesBytes = storesBytes
        if storesBytes {
            bytes.reserveCapacity(min(maximumBytes, 4_096))
        }
    }

    var data: Data { Data(bytes) }

    mutating func append(_ string: String) throws {
        let count = string.utf8.count
        guard count <= maximumBytes - byteCount else {
            throw ComparisonReportError.outputTooLarge(maximumBytes: maximumBytes)
        }
        byteCount += count
        guard storesBytes else { return }
        bytes.append(contentsOf: string.utf8)
    }

    mutating func appendPlainEscaped(_ string: String) throws {
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x09: try append("\\t")
            case 0x0A: try append("\\n")
            case 0x0D: try append("\\r")
            case 0x5C: try append("\\\\")
            case let value where Self.isUnsupportedControl(value):
                try appendControlEscape(value)
            default:
                try append(String(scalar))
            }
        }
    }

    mutating func appendCSVField(_ string: String) throws {
        let requiresQuotes = string.unicodeScalars.contains {
            $0.value == 0x22 || $0.value == 0x2C || $0.value == 0x0A || $0.value == 0x0D
        }
        if requiresQuotes { try append("\"") }
        if Self.requiresSpreadsheetNeutralization(string) {
            try append("'")
        }
        for scalar in string.unicodeScalars {
            if scalar.value == 0x22 {
                try append("\"")
            }
            if Self.isUnsupportedControl(scalar.value) {
                try appendControlEscape(scalar.value)
            } else {
                try append(String(scalar))
            }
        }
        if requiresQuotes { try append("\"") }
    }

    mutating func appendHTMLEscaped(_ string: String) throws {
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x26: try append("&amp;")
            case 0x3C: try append("&lt;")
            case 0x3E: try append("&gt;")
            case 0x22: try append("&quot;")
            case 0x27: try append("&#39;")
            case let value where Self.isUnsupportedControl(value):
                try appendControlEscape(value)
            default:
                try append(String(scalar))
            }
        }
    }

    private mutating func appendControlEscape(_ value: UInt32) throws {
        try append("\\u{" + String(value, radix: 16, uppercase: true) + "}")
    }

    private static func isUnsupportedControl(_ value: UInt32) -> Bool {
        value <= 0x08 || value == 0x0B || value == 0x0C || (0x0E...0x1F).contains(value)
            || (0x7F...0x9F).contains(value)
    }

    private static func requiresSpreadsheetNeutralization(_ string: String) -> Bool {
        var foundStrippedPrefix = false
        for scalar in string.unicodeScalars {
            if isDangerousSpreadsheetFormulaPrefix(scalar.value) {
                return true
            }
            guard isSpreadsheetStrippedPrefix(scalar.value) else {
                return foundStrippedPrefix
            }
            foundStrippedPrefix = true
        }
        return foundStrippedPrefix
    }

    private static func isDangerousSpreadsheetFormulaPrefix(_ value: UInt32) -> Bool {
        value == 0x2B || value == 0x2D || value == 0x3D || value == 0x40
    }

    private static func isSpreadsheetStrippedPrefix(_ value: UInt32) -> Bool {
        value == 0x09 || value == 0x0A || value == 0x0D || value == 0xFEFF
    }
}
