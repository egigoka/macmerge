import Darwin
import Foundation
import MacMergeCore

private struct Configuration {
    enum Density: String {
        case sparse
        case dense
    }

    var lineCounts = [10_000, 100_000, 250_000, 1_000_000]
    var iterations = 1
    var fixtureDirectory: URL?
    var density = Density.sparse

    init(arguments: ArraySlice<String>) throws {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--lines":
                index = arguments.index(after: index)
                guard index < arguments.endIndex else { throw ArgumentError.missingValue(argument) }
                lineCounts = try arguments[index].split(separator: ",").map {
                    guard let value = Int($0), value > 0 else {
                        throw ArgumentError.invalidValue(argument, String($0))
                    }
                    return value
                }
            case "--iterations":
                index = arguments.index(after: index)
                guard index < arguments.endIndex,
                      let value = Int(arguments[index]), value > 0 else {
                    throw ArgumentError.invalidValue(argument, index < arguments.endIndex ? arguments[index] : "")
                }
                iterations = value
            case "--fixture-directory":
                index = arguments.index(after: index)
                guard index < arguments.endIndex else { throw ArgumentError.missingValue(argument) }
                fixtureDirectory = URL(filePath: arguments[index], directoryHint: .isDirectory)
            case "--density":
                index = arguments.index(after: index)
                guard index < arguments.endIndex, let value = Density(rawValue: arguments[index]) else {
                    throw ArgumentError.invalidValue(argument, index < arguments.endIndex ? arguments[index] : "")
                }
                density = value
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ArgumentError.unknown(argument)
            }
            index = arguments.index(after: index)
        }
    }
}

private enum ArgumentError: Error, CustomStringConvertible {
    case invalidValue(String, String)
    case missingValue(String)
    case unknown(String)

    var description: String {
        switch self {
        case let .invalidValue(option, value): "Invalid value '\(value)' for \(option)."
        case let .missingValue(option): "Missing value for \(option)."
        case let .unknown(option): "Unknown option '\(option)'."
        }
    }
}

private struct Fixture {
    let left: String
    let right: String
    let expectedDifferences: Int
}

private struct Result {
    let lines: Int
    let inputBytes: Int
    let rows: Int
    let differences: Int
    let seconds: Double
    let rowStorageBytes: Int
    let residentDeltaBytes: Int64
}

private func fixture(lineCount: Int, density: Configuration.Density) -> Fixture {
    var left = ""
    var right = ""
    let estimatedBytes = lineCount * 16
    left.reserveCapacity(estimatedBytes)
    right.reserveCapacity(estimatedBytes)
    let changeStride = density == .dense ? 1 : max(1, lineCount / 10)
    var differences = 0

    for line in 0..<lineCount {
        let common = "line-\(line)"
        left += common
        if line % changeStride == changeStride / 2 {
            right += "changed-\(line)"
            differences += 1
        } else {
            right += common
        }
        if line + 1 < lineCount {
            left += "\n"
            right += "\n"
        }
    }

    return Fixture(left: left, right: right, expectedDifferences: differences)
}

private func benchmark(
    lineCount: Int,
    iterations: Int,
    fixtureDirectory: URL?,
    density: Configuration.Density
) throws -> Result {
    let input = fixture(lineCount: lineCount, density: density)
    if let fixtureDirectory {
        try write(input, lineCount: lineCount, to: fixtureDirectory)
    }
    let residentBefore = residentMemoryBytes()
    var bestSeconds = Double.greatestFiniteMagnitude
    var finalRows: [DiffRow] = []

    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        let rows = try LineDiff.compare(left: input.left, right: input.right)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        bestSeconds = min(bestSeconds, elapsed)
        finalRows = rows
    }

    let summary = DiffSummary(rows: finalRows)
    guard finalRows.count == lineCount else {
        throw BenchmarkError.unexpectedRows(expected: lineCount, actual: finalRows.count)
    }
    guard summary.differences == input.expectedDifferences else {
        throw BenchmarkError.unexpectedDifferences(
            expected: input.expectedDifferences,
            actual: summary.differences
        )
    }
    guard finalRows.first?.left?.number == 1,
          finalRows.last?.left?.number == lineCount,
          finalRows.first?.right?.number == 1,
          finalRows.last?.right?.number == lineCount else {
        throw BenchmarkError.invalidAlignment
    }

    return Result(
        lines: lineCount,
        inputBytes: input.left.utf8.count + input.right.utf8.count,
        rows: finalRows.count,
        differences: summary.differences,
        seconds: bestSeconds,
        rowStorageBytes: finalRows.count * MemoryLayout<DiffRow>.stride,
        residentDeltaBytes: Int64(residentMemoryBytes()) - Int64(residentBefore)
    )
}

private func write(_ fixture: Fixture, lineCount: Int, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try fixture.left.write(
        to: directory.appending(path: "macmerge-\(lineCount)-left.txt"),
        atomically: true,
        encoding: .utf8
    )
    try fixture.right.write(
        to: directory.appending(path: "macmerge-\(lineCount)-right.txt"),
        atomically: true,
        encoding: .utf8
    )
}

private enum BenchmarkError: Error, CustomStringConvertible {
    case invalidAlignment
    case semanticCheckFailed(String)
    case unexpectedDifferences(expected: Int, actual: Int)
    case unexpectedRows(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .invalidAlignment:
            "Comparison produced non-monotonic boundary line numbers."
        case let .semanticCheckFailed(name):
            "Comparison semantic check failed: \(name)."
        case let .unexpectedDifferences(expected, actual):
            "Expected \(expected) differences, got \(actual)."
        case let .unexpectedRows(expected, actual):
            "Expected \(expected) rows, got \(actual)."
        }
    }
}

private func validateComparisonSemantics() throws {
    let normalized = try LineDiff.compare(left: "a\r\nb\r\n", right: "a\nb\n")
    guard DiffSummary(rows: normalized).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("normalized line endings")
    }

    let strict = try LineDiff.compare(
        left: "a\r\nb\r\n",
        right: "a\nb\n",
        options: LineDiffOptions(ignoreLineEndings: false)
    )
    guard DiffSummary(rows: strict).differences == 2 else {
        throw BenchmarkError.semanticCheckFailed("strict line endings")
    }

    let filtered = try LineDiff.compare(
        left: "head\n# old\nreal-left\ntail",
        right: "head\n# new\nreal-right\ntail",
        options: LineDiffOptions(lineFilters: [LineFilterRule(pattern: #"^# "#)])
    )
    guard DiffSummary(rows: filtered).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("line filters")
    }

    let substituted = try LineDiff.compare(
        left: "build 123",
        right: "build 456",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: #"\d+"#, replacement: "number"),
        ])
    )
    guard DiffSummary(rows: substituted).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("substitutions")
    }

    let mergeRows = try LineDiff.compare(left: "left", right: "right")
    guard let rowID = mergeRows.first?.id,
          let merged = try LineMerge.apply(
            rowID: rowID,
            direction: .leftToRight,
            left: "left",
            right: "right"
          ),
          merged.right == "left" else {
        throw BenchmarkError.semanticCheckFailed("directional merge")
    }

    let separated = try LineDiff.compare(
        left: "head\nleft-one\nseparator\nleft-two\ntail",
        right: "head\nright-one\nseparator\nright-two\ntail"
    )
    guard separated.map(\.kind) == [
        .unchanged, .modified, .unchanged, .modified, .unchanged,
    ] else {
        throw BenchmarkError.semanticCheckFailed("separated hunks")
    }

    let ordered = try LineDiff.compare(
        left: "build 123",
        right: "version",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "build", replacement: "release"),
            SubstitutionRule(pattern: "release \\d+", replacement: "version"),
        ])
    )
    guard DiffSummary(rows: ordered).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("substitution order")
    }

    for blank in ["\n", "\r", "\r\n", " \n", "\t\r\n"] {
        for whitespace in [WhitespaceComparison.compareAll, .ignoreChanges, .ignoreAll] {
            let blankRows = try LineDiff.compare(
                left: "head\n\(blank)tail",
                right: "head\ntail",
                options: LineDiffOptions(
                    whitespace: whitespace,
                    ignoreBlankLines: true
                )
            )
            guard DiffSummary(rows: blankRows).differences == 0 else {
                throw BenchmarkError.semanticCheckFailed("blank-line matrix")
            }
        }
    }

    let rawBytes = try LineDiff.compare(
        left: "def",
        right: "ghi",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "def", replacement: #"\x01\xEF\xab\x"#),
            SubstitutionRule(pattern: "ghi", replacement: #"\x01\xEF\xab\x"#),
        ])
    )
    guard DiffSummary(rows: rawBytes).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("raw-byte substitutions")
    }
    let differentRawBytes = try LineDiff.compare(
        left: "def",
        right: "ghi",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "def", replacement: #"\xEF"#),
            SubstitutionRule(pattern: "ghi", replacement: #"\xEE"#),
        ])
    )
    guard DiffSummary(rows: differentRawBytes).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("distinct raw-byte substitutions")
    }
    let rawByteLiteral = try LineDiff.compare(
        left: "literal",
        right: "byte",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "literal", replacement: "\u{F0000}"),
            SubstitutionRule(pattern: "byte", replacement: #"\x80"#),
        ])
    )
    guard DiffSummary(rows: rawByteLiteral).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("raw-byte literal collision")
    }
    let chainedRawBytes = try LineDiff.compare(
        left: "left",
        right: "right",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "left", replacement: #"\xEF"#),
            SubstitutionRule(pattern: "right", replacement: #"\xEE"#),
            SubstitutionRule(pattern: #"\xEF"#, replacement: "same"),
            SubstitutionRule(pattern: #"\x{EE}"#, replacement: "same"),
        ])
    )
    guard DiffSummary(rows: chainedRawBytes).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("chained raw-byte substitutions")
    }
    let rawByteLiteralPattern = try LineDiff.compare(
        left: "left",
        right: "right",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "left", replacement: #"\x80"#),
            SubstitutionRule(pattern: "right", replacement: "same"),
            SubstitutionRule(pattern: "\u{F0000}", replacement: "same"),
        ])
    )
    guard DiffSummary(rows: rawByteLiteralPattern).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("raw-byte literal-pattern collision")
    }
    let rawByteRange = try LineDiff.compare(
        left: "left",
        right: "right",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: "left", replacement: #"\x80"#),
            SubstitutionRule(pattern: "right", replacement: #"\x81"#),
            SubstitutionRule(pattern: #"[\x80-\x81]"#, replacement: "same"),
        ])
    )
    guard DiffSummary(rows: rawByteRange).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("raw-byte pattern range")
    }
    let crAnchors = try LineDiff.compare(
        left: "value=left\rnext",
        right: "value=right\rnext",
        options: LineDiffOptions(substitutions: [
            SubstitutionRule(pattern: #"^value=.*$"#, replacement: "same"),
        ])
    )
    guard DiffSummary(rows: crAnchors).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("PCRE ANYCRLF anchors")
    }
    let terminalEmptyMatch = try LineDiff.compare(
        left: "same",
        right: "same!",
        options: LineDiffOptions(substitutions: [SubstitutionRule(pattern: "$", replacement: "!")])
    )
    guard DiffSummary(rows: terminalEmptyMatch).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("terminal empty substitution")
    }

    let comments = try LineDiff.compare(
        left: "value(); // left\n/* old */",
        right: "value(); // right\n/* new */",
        options: LineDiffOptions(ignoreComments: true, commentSyntax: .cFamily)
    )
    guard DiffSummary(rows: comments).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("C-family comments")
    }
    let syntaxComments: [(String, String, CommentSyntax, String)] = [
        ("value = 1 # left", "value = 1 # right", .hashLine, "hash-line comments"),
        ("SELECT 1; -- left", "SELECT 1; -- right", .sql, "SQL comments"),
        ("<root><!-- left --></root>", "<root><!-- right --></root>", .markup, "markup comments"),
        ("value = 1; % left", "value = 1; % right", .matlab, "MATLAB comments"),
        ("# left", "# right", .properties, "Properties comments"),
        ("value = 1 # left", "value = 1 # right", .toml, "TOML comments"),
        ("value: 1 # left", "value: 1 # right", .yaml, "YAML comments"),
        ("value = 1 ' left", "value = 1 ' right", .basic, "Basic comments"),
        ("a {/* left */ color:red}", "a {/* right */ color:red}", .css, "CSS comments"),
        ("; left", "; right", .ini, "INI comments"),
        ("value % left", "value % right", .tex, "TeX comments"),
        ("value -- left", "value -- right", .adaVhdl, "Ada/VHDL comments"),
    ]
    for (left, right, syntax, name) in syntaxComments {
        let rows = try LineDiff.compare(
            left: left,
            right: right,
            options: LineDiffOptions(ignoreComments: true, commentSyntax: syntax)
        )
        guard DiffSummary(rows: rows).differences == 0 else {
            throw BenchmarkError.semanticCheckFailed(name)
        }
    }
    let pythonString = try LineDiff.compare(
        left: "\"\"\"\n# left\n\"\"\"",
        right: "\"\"\"\n# right\n\"\"\"",
        options: LineDiffOptions(ignoreComments: true, commentSyntax: .python)
    )
    guard DiffSummary(rows: pythonString).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("Python triple-quoted strings")
    }
    let removedComment = try LineDiff.compare(
        left: "prefix/* comment */suffix",
        right: "prefixsuffix",
        options: LineDiffOptions(ignoreComments: true, commentSyntax: .cFamily)
    )
    guard DiffSummary(rows: removedComment).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("comment removal")
    }
    let markupProse = try LineDiff.compare(
        left: "don't <!-- left --> change",
        right: "don't <!-- right --> change",
        options: LineDiffOptions(ignoreComments: true, commentSyntax: .markup)
    )
    guard DiffSummary(rows: markupProse).differences == 0 else {
        throw BenchmarkError.semanticCheckFailed("markup prose")
    }
    let tomlString = try LineDiff.compare(
        left: "key = \"\"\"\n# left\n\"\"\"",
        right: "key = \"\"\"\n# right\n\"\"\"",
        options: LineDiffOptions(ignoreComments: true, commentSyntax: .toml)
    )
    guard DiffSummary(rows: tomlString).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("TOML multiline strings")
    }
    let yamlBlock = try LineDiff.compare(
        left: "key: |\n  # left",
        right: "key: |\n  # right",
        options: LineDiffOptions(ignoreComments: true, commentSyntax: .yaml)
    )
    guard DiffSummary(rows: yamlBlock).differences == 1 else {
        throw BenchmarkError.semanticCheckFailed("YAML block scalars")
    }
}

private func residentMemoryBytes() -> UInt64 {
    var information = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let status = withUnsafeMutablePointer(to: &information) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? UInt64(information.resident_size) : 0
}

private func printUsage() {
    print("""
    Usage: MacMergeBenchmark [--lines 10000,100000,250000,1000000] [--iterations 1]
                             [--fixture-directory PATH] [--density sparse|dense]

    Runs deterministic text comparisons and reports best elapsed time,
    throughput, shallow DiffRow storage, and resident-memory growth.
    """)
}

private func mebibytes(_ bytes: Int64) -> String {
    String(format: "%.1f", Double(bytes) / 1_048_576)
}

do {
    let configuration = try Configuration(arguments: CommandLine.arguments.dropFirst())
    try validateComparisonSemantics()
    print("density,lines,input_mib,rows,differences,seconds,rows_per_second,row_storage_mib,resident_delta_mib")
    for lineCount in configuration.lineCounts {
        let result = try benchmark(
            lineCount: lineCount,
            iterations: configuration.iterations,
            fixtureDirectory: configuration.fixtureDirectory,
            density: configuration.density
        )
        print([
            configuration.density.rawValue,
            String(result.lines),
            mebibytes(Int64(result.inputBytes)),
            String(result.rows),
            String(result.differences),
            String(format: "%.3f", result.seconds),
            String(format: "%.0f", Double(result.rows) / result.seconds),
            mebibytes(Int64(result.rowStorageBytes)),
            mebibytes(result.residentDeltaBytes),
        ].joined(separator: ","))
    }
} catch {
    fputs("MacMergeBenchmark: \(error)\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}
