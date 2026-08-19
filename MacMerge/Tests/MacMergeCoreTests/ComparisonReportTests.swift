import Foundation
import XCTest
@testable import MacMergeCore

final class ComparisonReportTests: XCTestCase {
    func testRowsAndSummaryAreDeterministicAcrossInputOrder() throws {
        let orderedRows = [
            ComparisonReportRow(values: ["a", "first"], sortKey: "a"),
            ComparisonReportRow(values: ["a", "second"], sortKey: "a"),
            ComparisonReportRow(values: ["z", "third"], sortKey: "z")
        ]
        let orderedSummary = [
            ComparisonReportSummaryItem(label: "Alpha", value: "1"),
            ComparisonReportSummaryItem(label: "Alpha", value: "9"),
            ComparisonReportSummaryItem(label: "Zulu", value: "2")
        ]
        let forward = ComparisonReport(
            title: "Ordering",
            columns: ["Name", "Value"],
            rows: orderedRows,
            summary: ComparisonReportSummary(items: orderedSummary)
        )
        let reversed = ComparisonReport(
            title: "Ordering",
            columns: ["Name", "Value"],
            rows: orderedRows.reversed(),
            summary: ComparisonReportSummary(items: orderedSummary.reversed())
        )

        XCTAssertEqual(forward.summary?.items, orderedSummary)
        XCTAssertEqual(reversed.summary?.items, Array(orderedSummary.reversed()))

        for format in ComparisonReportFormat.allCases {
            XCTAssertEqual(
                try forward.data(format: format),
                try reversed.data(format: format),
                format.rawValue
            )
        }
        XCTAssertEqual(
            try reversed.string(format: .plainText),
            "Ordering\n\nSummary\nAlpha: 1\nAlpha: 9\nZulu: 2\n\n"
                + "Name\tValue\na\tfirst\na\tsecond\nz\tthird\n"
        )
    }

    func testStructuralOutputBudgetRejectsAdversarialRowsBeforeSortingAcrossFormats() throws {
        let summaryItems = [
            ComparisonReportSummaryItem(label: "Zulu", value: "2"),
            ComparisonReportSummaryItem(label: "Alpha", value: "1")
        ]
        let fixedReport = ComparisonReport(
            title: "Budget",
            columns: ["Value"],
            rows: [],
            summary: ComparisonReportSummary(items: summaryItems)
        )
        let commonPrefix = String(repeating: "x", count: 512)
        let rows = (0..<12_000).map { index in
            ComparisonReportRow(
                values: [String(index)],
                sortKey: commonPrefix + String((index * 7_919) % 12_000)
            )
        }
        let report = ComparisonReport(
            title: fixedReport.title,
            columns: fixedReport.columns,
            rows: rows,
            summary: fixedReport.summary
        )

        for format in ComparisonReportFormat.allCases {
            let minimumBytes = try fixedReport.data(format: format).count
            let sortRecorder = SortRecorder()
            try ComparisonReport.$rowSortObserver.withValue(
                { sortRecorder.record() },
                operation: {
                    XCTAssertThrowsError(
                        try report.generate(format: format, maximumOutputBytes: minimumBytes)
                    ) {
                        XCTAssertEqual(
                            $0 as? ComparisonReportError,
                            .outputTooLarge(maximumBytes: minimumBytes),
                            format.rawValue
                        )
                    }
                }
            )
            XCTAssertEqual(sortRecorder.count, 0, format.rawValue)
        }

        let sortRecorder = SortRecorder()
        try ComparisonReport.$rowSortObserver.withValue(
            { sortRecorder.record() },
            operation: {
                _ = try ComparisonReport(
                    columns: ["Value"],
                    rows: [
                        ComparisonReportRow(values: ["2"]),
                        ComparisonReportRow(values: ["1"])
                    ]
                ).generate(format: .csv)
            }
        )
        XCTAssertEqual(sortRecorder.count, 1)
    }

    func testOversizedCellIsRejectedBeforeSortingAcrossFormats() throws {
        let viableReport = ComparisonReport(
            columns: ["Value"],
            rows: [
                ComparisonReportRow(values: ["b"]),
                ComparisonReportRow(values: ["a"])
            ]
        )
        let report = ComparisonReport(
            columns: viableReport.columns,
            rows: [
                ComparisonReportRow(values: [String(repeating: "<&\"\u{0}=,", count: 1_024)], sortKey: "b"),
                ComparisonReportRow(values: ["a"], sortKey: "a")
            ]
        )

        for format in ComparisonReportFormat.allCases {
            let maximumOutputBytes = try viableReport.data(format: format).count
            let sortRecorder = SortRecorder()
            try ComparisonReport.$rowSortObserver.withValue(
                { sortRecorder.record() },
                operation: {
                    XCTAssertThrowsError(
                        try report.generate(format: format, maximumOutputBytes: maximumOutputBytes)
                    ) {
                        XCTAssertEqual(
                            $0 as? ComparisonReportError,
                            .outputTooLarge(maximumBytes: maximumOutputBytes),
                            format.rawValue
                        )
                    }
                }
            )
            XCTAssertEqual(sortRecorder.count, 0, format.rawValue)
        }
    }

    func testExactOutputByteBoundaryAcrossFormats() throws {
        let report = ComparisonReport(
            title: "Boundary <&\n",
            columns: ["=Formula,\"<&", "Control\u{0}"],
            rows: [
                ComparisonReportRow(
                    values: ["+SUM(A1:A2)", "say \"hi\"\n<&\u{1}"],
                    sortKey: "z"
                ),
                ComparisonReportRow(values: ["\u{FEFF}\t-10", "café 🙂"], sortKey: "a")
            ],
            summary: ComparisonReportSummary(items: [
                ComparisonReportSummaryItem(label: "Zulu<&", value: "line\n2"),
                ComparisonReportSummaryItem(label: "Alpha", value: "\u{7F}\"")
            ])
        )

        for format in ComparisonReportFormat.allCases {
            let complete = try report.data(format: format)
            let exactSortRecorder = SortRecorder()
            let exact = try ComparisonReport.$rowSortObserver.withValue(
                { exactSortRecorder.record() },
                operation: {
                    try report.data(format: format, maximumOutputBytes: complete.count)
                }
            )
            XCTAssertEqual(exact, complete, format.rawValue)
            XCTAssertEqual(exactSortRecorder.count, 1, format.rawValue)

            let undersizedSortRecorder = SortRecorder()
            try ComparisonReport.$rowSortObserver.withValue(
                { undersizedSortRecorder.record() },
                operation: {
                    XCTAssertThrowsError(
                        try report.data(format: format, maximumOutputBytes: complete.count - 1)
                    ) {
                        XCTAssertEqual(
                            $0 as? ComparisonReportError,
                            .outputTooLarge(maximumBytes: complete.count - 1),
                            format.rawValue
                        )
                    }
                }
            )
            XCTAssertEqual(undersizedSortRecorder.count, 0, format.rawValue)
        }
    }

    func testCSVParsesAsFixedWidthRecords() throws {
        let report = ComparisonReport(
            columns: ["Path", "Before", "After"],
            rows: [
                ComparisonReportRow(
                    values: ["Sources/App.swift", "one,two", "line 1\nline 2"],
                    sortKey: "2"
                ),
                ComparisonReportRow(
                    values: ["README.md", "say \"hello\"", "café 🙂"],
                    sortKey: "1"
                )
            ]
        )

        let records = try parseCSV(report.string(format: .csv))

        XCTAssertEqual(records.map(\.count), [3, 3, 3])
        XCTAssertEqual(
            records,
            [
                ["Path", "Before", "After"],
                ["README.md", "say \"hello\"", "café 🙂"],
                ["Sources/App.swift", "one,two", "line 1\nline 2"]
            ])
    }

    func testCSVRejectsUnderfilledAndOverfilledRows() throws {
        let underfilled = ComparisonReport(
            columns: ["Name", "Value"],
            rows: [ComparisonReportRow(values: ["only-name"])]
        )
        XCTAssertThrowsError(try underfilled.string(format: .csv)) {
            XCTAssertEqual(
                $0 as? ComparisonReportError,
                .columnCountMismatch(rowIndex: 0, expected: 2, actual: 1)
            )
        }

        let overfilled = ComparisonReport(
            columns: ["Name", "Value"],
            rows: [ComparisonReportRow(values: ["name", "value", "extra"])]
        )
        XCTAssertThrowsError(try overfilled.string(format: .csv)) {
            XCTAssertEqual(
                $0 as? ComparisonReportError,
                .columnCountMismatch(rowIndex: 0, expected: 2, actual: 3)
            )
        }
    }

    func testCSVUsesRFC4180EscapingAndCRLFRecords() throws {
        let report = ComparisonReport(
            columns: ["plain", "comma", "quote", "LF", "CR", "CRLF"],
            rows: [
                ComparisonReportRow(values: [
                    "alpha",
                    "a,b",
                    "say \"hi\"",
                    "line1\nline2",
                    "left\rright",
                    "a\r\nb"
                ])
            ]
        )
        let expected =
            "plain,comma,quote,LF,CR,CRLF\r\n"
            + "alpha,\"a,b\",\"say \"\"hi\"\"\",\"line1\nline2\","
            + "\"left\rright\",\"a\r\nb\"\r\n"

        let csv = try report.string(format: .csv)

        XCTAssertEqual(Array(csv.utf8), Array(expected.utf8))
        XCTAssertEqual(
            try parseCSV(csv),
            [
                ["plain", "comma", "quote", "LF", "CR", "CRLF"],
                ["alpha", "a,b", "say \"hi\"", "line1\nline2", "left\rright", "a\r\nb"]
            ]
        )
    }

    func testCSVNeutralizesSpreadsheetFormulaPrefixesInColumnsAndCells() throws {
        let columns = [
            "=Column", "+Column", "-Column", "@Column",
            "\tColumn", "\nColumn", "\rColumn", " Safe"
        ]
        let values = [
            "=1+1", "+SUM(A1:A2)", "-10", "@command",
            "\tTabbed", "\nLine", "\rLine", " =safe"
        ]
        let report = ComparisonReport(
            columns: columns,
            rows: [ComparisonReportRow(values: values)]
        )
        let expected =
            "'=Column,'+Column,'-Column,'@Column,'\tColumn,\"'\nColumn\",\"'\rColumn\", Safe\r\n"
            + "'=1+1,'+SUM(A1:A2),'-10,'@command,'\tTabbed,\"'\nLine\",\"'\rLine\", =safe\r\n"

        let csv = try report.string(format: .csv)

        XCTAssertEqual(csv, expected)
        XCTAssertEqual(
            try parseCSV(csv),
            [
                [
                    "'=Column", "'+Column", "'-Column", "'@Column",
                    "'\tColumn", "'\nColumn", "'\rColumn", " Safe"
                ],
                [
                    "'=1+1", "'+SUM(A1:A2)", "'-10", "'@command",
                    "'\tTabbed", "'\nLine", "'\rLine", " =safe"
                ]
            ]
        )
    }

    func testCSVNeutralizesBOMAndDangerousWhitespacePrefixChains() throws {
        let prefixes = [
            "\u{FEFF}=1+1",
            "\u{FEFF}\u{FEFF}+SUM(A1:A2)",
            "\u{FEFF}\t-10",
            "\u{FEFF}\r\n@command"
        ]
        let report = ComparisonReport(
            columns: prefixes,
            rows: [ComparisonReportRow(values: prefixes)]
        )

        let records = try parseCSV(report.string(format: .csv))

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0], prefixes.map { "'" + $0 })
        XCTAssertEqual(records[1], prefixes.map { "'" + $0 })
        for field in records.flatMap({ $0 }) {
            XCTAssertEqual(field.first, "'")
            XCTAssertEqual(field.filter { $0 == "'" }.count, 1)
        }
    }

    func testEveryUnsupportedC0ScalarAndDELEscapesInEveryFormat() throws {
        let controls =
            "\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{B}\u{C}"
            + "\u{E}\u{F}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}"
            + "\u{18}\u{19}\u{1A}\u{1B}\u{1C}\u{1D}\u{1E}\u{1F}\u{7F}"
        let visible =
            "\\u{0}\\u{1}\\u{2}\\u{3}\\u{4}\\u{5}\\u{6}\\u{7}\\u{8}\\u{B}\\u{C}"
            + "\\u{E}\\u{F}\\u{10}\\u{11}\\u{12}\\u{13}\\u{14}\\u{15}\\u{16}\\u{17}"
            + "\\u{18}\\u{19}\\u{1A}\\u{1B}\\u{1C}\\u{1D}\\u{1E}\\u{1F}\\u{7F}"
        let unsupportedBytes =
            Array(UInt8(0x00)...UInt8(0x08))
            + [UInt8(0x0B), UInt8(0x0C)]
            + Array(UInt8(0x0E)...UInt8(0x1F))
            + [UInt8(0x7F)]
        let report = ComparisonReport(
            columns: ["Value"],
            rows: [ComparisonReportRow(values: [controls])]
        )

        for format in ComparisonReportFormat.allCases {
            let output = try report.generate(format: format)
            XCTAssertTrue(output.string.contains(visible), format.rawValue)
            for byte in unsupportedBytes {
                XCTAssertFalse(output.data.contains(byte), "\(format.rawValue) contains 0x\(String(byte, radix: 16))")
            }
        }
    }

    func testEveryC1ControlEscapesAndNoBreakSpaceIsPreservedInEveryFormat() throws {
        let controls = (0x80...0x9F).map { String(UnicodeScalar($0)!) }.joined()
        let visible = (0x80...0x9F).map {
            "\\u{" + String($0, radix: 16, uppercase: true) + "}"
        }.joined()
        let noBreakSpace = "\u{A0}"
        let expectedValue = visible + noBreakSpace
        let report = ComparisonReport(
            columns: ["Value"],
            rows: [ComparisonReportRow(values: [controls + noBreakSpace])]
        )

        let plainText = try report.string(format: .plainText)
        let csv = try report.string(format: .csv)
        let html = try report.string(format: .html)

        XCTAssertTrue(plainText.contains(expectedValue))
        XCTAssertEqual(try parseCSV(csv), [["Value"], [expectedValue]])
        XCTAssertTrue(html.contains("<td>\(expectedValue)</td>"))
        for (format, output) in [
            (ComparisonReportFormat.plainText, plainText),
            (.csv, csv),
            (.html, html)
        ] {
            XCTAssertFalse(
                output.unicodeScalars.contains { (0x80...0x9F).contains(Int($0.value)) },
                format.rawValue
            )
            XCTAssertTrue(output.contains(noBreakSpace), format.rawValue)
        }
    }

    func testHTMLTreatsAllReportValuesAsText() throws {
        let report = ComparisonReport(
            title: "<script>alert(\"x\")</script>&'",
            columns: ["<img src=x onerror=alert(1)>", "\"quoted\""],
            rows: [ComparisonReportRow(values: ["<b>unsafe</b>", "Tom & 'Jerry'"])],
            summary: ComparisonReportSummary(items: [
                ComparisonReportSummaryItem(label: "A<dt>", value: "</dd><script>bad()</script>")
            ])
        )

        let html = try report.string(format: .html)

        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertFalse(html.contains("<b>unsafe</b>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;&#39;"))
        XCTAssertTrue(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
        XCTAssertTrue(html.contains("&quot;quoted&quot;"))
        XCTAssertTrue(html.contains("&lt;b&gt;unsafe&lt;/b&gt;"))
        XCTAssertTrue(html.contains("Tom &amp; &#39;Jerry&#39;"))
        XCTAssertTrue(html.contains("A&lt;dt&gt;"))
        XCTAssertTrue(html.contains("&lt;/dd&gt;&lt;script&gt;bad()&lt;/script&gt;"))
    }

    func testPlainTextHasStableReadableEscaping() throws {
        let report = ComparisonReport(
            title: "Plain\nReport",
            columns: ["Left\tSide", "Right"],
            rows: [ComparisonReportRow(values: ["a\\b", "line1\r\nline2"])]
        )

        XCTAssertEqual(
            try report.string(format: .plainText),
            "Plain\\nReport\n\nLeft\\tSide\tRight\na\\\\b\tline1\\r\\nline2\n"
        )
    }

    func testValidationBoundsWinBeforeRowTraversalAndOutputGrowth() throws {
        let oversizedRows = Array(
            repeating: ComparisonReportRow(values: []),
            count: ComparisonReport.maximumRowCount + 1
        )
        let oversizedReport = ComparisonReport(columns: ["Value"], rows: oversizedRows)

        let boundedReport = ComparisonReport(
            columns: ["Value"],
            rows: [ComparisonReportRow(values: ["content"])]
        )

        for format in ComparisonReportFormat.allCases {
            XCTAssertThrowsError(try oversizedReport.generate(format: format, maximumOutputBytes: 1)) {
                XCTAssertEqual(
                    $0 as? ComparisonReportError,
                    .tooManyRows(maximum: ComparisonReport.maximumRowCount),
                    format.rawValue
                )
            }

            let complete = try boundedReport.data(format: format)
            XCTAssertEqual(
                try boundedReport.data(format: format, maximumOutputBytes: complete.count),
                complete,
                format.rawValue
            )
            XCTAssertThrowsError(
                try boundedReport.data(format: format, maximumOutputBytes: complete.count - 1)
            ) {
                XCTAssertEqual(
                    $0 as? ComparisonReportError,
                    .outputTooLarge(maximumBytes: complete.count - 1),
                    format.rawValue
                )
            }
        }
    }

    func testUnicodeAndEmbeddedNewlinesSurviveEachFormat() throws {
        let value = "café 🙂\n東京\r\nمرحبا"
        let report = ComparisonReport(
            title: "Résumé 東京",
            columns: ["Text"],
            rows: [ComparisonReportRow(values: [value])]
        )

        XCTAssertTrue(
            try report.string(format: .plainText).contains("café 🙂\\n東京\\r\\nمرحبا")
        )
        XCTAssertEqual(try parseCSV(report.string(format: .csv)), [["Text"], [value]])
        let html = try report.string(format: .html)
        XCTAssertTrue(html.contains("Résumé 東京"))
        XCTAssertTrue(html.contains(value))
    }

    func testGeneratedDataCarriesFormatMetadata() throws {
        let report = ComparisonReport(
            columns: ["Value"],
            rows: [ComparisonReportRow(values: ["café 🙂"])]
        )
        let metadata: [(ComparisonReportFormat, String, String)] = [
            (.plainText, "txt", "text/plain; charset=utf-8"),
            (.csv, "csv", "text/csv; charset=utf-8"),
            (.html, "html", "text/html; charset=utf-8")
        ]

        for (format, fileExtension, mimeType) in metadata {
            let output = try report.generate(format: format)

            XCTAssertEqual(output.format, format)
            XCTAssertEqual(output.fileExtension, fileExtension)
            XCTAssertEqual(output.mimeType, mimeType)
            XCTAssertEqual(output.data, Data(output.string.utf8))
            XCTAssertEqual(output.data, try report.data(format: format))
            XCTAssertEqual(output.string, try report.string(format: format))
        }
    }

    private func parseCSV(_ input: String) throws -> [[String]] {
        let scalars = Array(input.unicodeScalars)
        var records: [[String]] = []
        var fields: [String] = []
        var field = ""
        var index = 0
        var isQuoted = false

        while index < scalars.count {
            let scalar = scalars[index]
            if isQuoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                    } else {
                        isQuoted = false
                        index += 1
                    }
                } else {
                    field.append(contentsOf: String(scalar))
                    index += 1
                }
            } else {
                switch scalar {
                case "\"" where field.isEmpty:
                    isQuoted = true
                    index += 1
                case ",":
                    fields.append(field)
                    field = ""
                    index += 1
                case "\r":
                    guard index + 1 < scalars.count, scalars[index + 1] == "\n" else {
                        throw CSVParserError.invalidRecordSeparator
                    }
                    fields.append(field)
                    records.append(fields)
                    fields = []
                    field = ""
                    index += 2
                case "\n":
                    throw CSVParserError.invalidRecordSeparator
                default:
                    field.append(contentsOf: String(scalar))
                    index += 1
                }
            }
        }

        guard !isQuoted else { throw CSVParserError.unterminatedQuotedField }
        guard fields.isEmpty, field.isEmpty else { throw CSVParserError.missingTerminalRecordSeparator }
        return records
    }

    private enum CSVParserError: Error {
        case invalidRecordSeparator
        case missingTerminalRecordSeparator
        case unterminatedQuotedField
    }

    private final class SortRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func record() {
            lock.lock()
            storage += 1
            lock.unlock()
        }
    }
}
