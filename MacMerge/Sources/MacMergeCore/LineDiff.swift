import CXDiff
import Foundation

public enum DiffKind: Equatable, Sendable {
    case unchanged
    case modified
    case removed
    case added
}

public enum DiffAlgorithm: Equatable, Sendable {
    case `default`
    case minimal
    case patience
    case histogram
    case none
}

public enum WhitespaceComparison: Equatable, Sendable {
    case compareAll
    case ignoreChanges
    case ignoreAll
}

public struct LineFilterRule: Equatable, Sendable {
    public var pattern: String
    public var caseSensitive: Bool

    public init(pattern: String, caseSensitive: Bool = true) {
        self.pattern = pattern
        self.caseSensitive = caseSensitive
    }
}

public struct SubstitutionRule: Equatable, Sendable {
    public var pattern: String
    public var replacement: String
    public var caseSensitive: Bool

    public init(pattern: String, replacement: String, caseSensitive: Bool = true) {
        self.pattern = pattern
        self.replacement = replacement
        self.caseSensitive = caseSensitive
    }
}

public struct LineDiffOptions: Equatable, Sendable {
    public var algorithm: DiffAlgorithm
    public var whitespace: WhitespaceComparison
    public var ignoreCase: Bool
    public var ignoreNumbers: Bool
    public var ignoreBlankLines: Bool
    public var ignoreLineEndings: Bool
    public var indentHeuristic: Bool
    public var lineFilters: [LineFilterRule]
    public var substitutions: [SubstitutionRule]

    public init(
        algorithm: DiffAlgorithm = .default,
        whitespace: WhitespaceComparison = .compareAll,
        ignoreCase: Bool = false,
        ignoreNumbers: Bool = false,
        ignoreBlankLines: Bool = false,
        ignoreLineEndings: Bool = true,
        indentHeuristic: Bool = false,
        lineFilters: [LineFilterRule] = [],
        substitutions: [SubstitutionRule] = []
    ) {
        self.algorithm = algorithm
        self.whitespace = whitespace
        self.ignoreCase = ignoreCase
        self.ignoreNumbers = ignoreNumbers
        self.ignoreBlankLines = ignoreBlankLines
        self.ignoreLineEndings = ignoreLineEndings
        self.indentHeuristic = indentHeuristic
        self.lineFilters = lineFilters
        self.substitutions = substitutions
    }
}

public enum LineDiffError: Error, LocalizedError, Equatable, Sendable {
    case nativeEngineFailure(Int32)
    case inputTooLarge(maximumBytes: Int)
    case tooManyLines(maximumLines: Int)
    case invalidRegularExpression(String)
    case filterChangedLineStructure
    case unsupportedSubstitutionByte(Int)
    case invalidNativeResult

    public var errorDescription: String? {
        switch self {
        case let .nativeEngineFailure(code):
            "WinMerge comparison engine failed with code \(code)."
        case let .inputTooLarge(maximumBytes):
            "Text comparison is limited to \(maximumBytes / 1_048_576) MiB per file."
        case let .tooManyLines(maximumLines):
            "Text comparison is limited to \(maximumLines.formatted()) lines per file."
        case let .invalidRegularExpression(pattern):
            "Invalid comparison filter regular expression: \(pattern)"
        case .filterChangedLineStructure:
            "A substitution inserted a line ending. Comparison substitutions must preserve line structure."
        case let .unsupportedSubstitutionByte(byte):
            "Substitution byte \\x\(String(byte, radix: 16, uppercase: true)) is not valid UTF-8 text. Raw-byte substitutions are not supported yet."
        case .invalidNativeResult:
            "WinMerge comparison engine returned invalid line ranges."
        }
    }
}

public struct DiffLine: Equatable, Sendable {
    public let number: Int
    public let text: String

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

public struct DiffRow: Identifiable, Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        public let leftNumber: Int?
        public let rightNumber: Int?

        public init(leftNumber: Int?, rightNumber: Int?) {
            self.leftNumber = leftNumber
            self.rightNumber = rightNumber
        }
    }

    public let id: ID
    public let left: DiffLine?
    public let right: DiffLine?
    public let kind: DiffKind

    public init(id: ID, left: DiffLine?, right: DiffLine?, kind: DiffKind) {
        self.id = id
        self.left = left
        self.right = right
        self.kind = kind
    }
}

public struct DiffSummary: Equatable, Sendable {
    public let unchanged: Int
    public let modified: Int
    public let removed: Int
    public let added: Int

    public var differences: Int {
        modified + removed + added
    }

    public init(rows: [DiffRow]) {
        var unchanged = 0
        var modified = 0
        var removed = 0
        var added = 0

        for row in rows {
            switch row.kind {
            case .unchanged:
                unchanged += 1
            case .modified:
                modified += 1
            case .removed:
                removed += 1
            case .added:
                added += 1
            }
        }

        self.unchanged = unchanged
        self.modified = modified
        self.removed = removed
        self.added = added
    }
}

public enum LineDiff {
    public static func compare(
        left leftText: String,
        right rightText: String,
        options: LineDiffOptions = LineDiffOptions()
    ) throws -> [DiffRow] {
        try validateInput(leftText)
        try validateInput(rightText)
        let leftDocument = TextDocument(text: leftText)
        let rightDocument = TextDocument(text: rightText)
        let transform = try ComparisonTransform(options: options)
        let left = leftDocument.lines
        let right = rightDocument.lines
        let hunks = try nativeHunks(
            left: leftDocument.comparisonText(contents: left, options: options),
            right: rightDocument.comparisonText(contents: right, options: options),
            options: options
        )
        var rows: [DiffRow] = []
        var leftIndex = 0
        var rightIndex = 0

        for hunk in hunks {
            guard hunk.leftStart >= leftIndex,
                  hunk.rightStart >= rightIndex,
                  hunk.leftStart <= left.count,
                  hunk.rightStart <= right.count,
                  hunk.leftCount <= left.count - hunk.leftStart,
                  hunk.rightCount <= right.count - hunk.rightStart,
                  hunk.leftStart - leftIndex == hunk.rightStart - rightIndex else {
                throw LineDiffError.invalidNativeResult
            }

            while leftIndex < hunk.leftStart {
                rows.append(row(
                    left: line(at: leftIndex, in: left),
                    right: line(at: rightIndex, in: right),
                    kind: .unchanged
                ))
                leftIndex += 1
                rightIndex += 1
            }

            if transform.isActive && !hunk.isTrivial {
                try appendPostFilteredRows(
                    to: &rows,
                    hunk: hunk,
                    leftDocument: leftDocument,
                    rightDocument: rightDocument,
                    transform: transform,
                    options: options,
                    leftIndex: &leftIndex,
                    rightIndex: &rightIndex
                )
            } else {
                appendChangedRows(
                    to: &rows,
                    hunk: hunk,
                    left: left,
                    right: right,
                    leftFiltered: Array(repeating: false, count: left.count),
                    rightFiltered: Array(repeating: false, count: right.count),
                    leftIndex: &leftIndex,
                    rightIndex: &rightIndex
                )
            }
        }

        guard left.count - leftIndex == right.count - rightIndex else {
            throw LineDiffError.invalidNativeResult
        }
        while leftIndex < left.count {
            rows.append(row(
                left: line(at: leftIndex, in: left),
                right: line(at: rightIndex, in: right),
                kind: .unchanged
            ))
            leftIndex += 1
            rightIndex += 1
        }

        return rows
    }

    private static func line(at index: Int, in lines: [String], numberOffset: Int = 0) -> DiffLine {
        DiffLine(number: numberOffset + index + 1, text: lines[index])
    }

    private static func validateInput(_ text: String) throws {
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        guard text.utf8.count <= maximumBytes else {
            throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes)
        }

        let maximumLines = Int(MMX_MAX_LINE_COUNT)
        var lineCount = 0
        var endsWithTerminator = false
        for character in text {
            endsWithTerminator = character == "\n" || character == "\r" || character == "\r\n"
            if endsWithTerminator {
                lineCount += 1
                guard lineCount <= maximumLines else {
                    throw LineDiffError.tooManyLines(maximumLines: maximumLines)
                }
            }
        }
        if !text.isEmpty && !endsWithTerminator && lineCount == maximumLines {
            throw LineDiffError.tooManyLines(maximumLines: maximumLines)
        }
    }

    private static func row(left: DiffLine?, right: DiffLine?, kind: DiffKind) -> DiffRow {
        DiffRow(
            id: DiffRow.ID(leftNumber: left?.number, rightNumber: right?.number),
            left: left,
            right: right,
            kind: kind
        )
    }

    private static func appendChangedRows(
        to rows: inout [DiffRow],
        hunk: NativeHunk,
        left: [String],
        right: [String],
        leftFiltered: [Bool],
        rightFiltered: [Bool],
        leftIndex: inout Int,
        rightIndex: inout Int,
        leftNumberOffset: Int = 0,
        rightNumberOffset: Int = 0
    ) {
        let leftEnd = leftIndex + hunk.leftCount
        let rightEnd = rightIndex + hunk.rightCount

        while leftIndex < leftEnd || rightIndex < rightEnd {
            let hasLeft = leftIndex < leftEnd
            let hasRight = rightIndex < rightEnd
            let leftIsFiltered = hasLeft && leftFiltered[leftIndex]
            let rightIsFiltered = hasRight && rightFiltered[rightIndex]

            if hunk.isTrivial || (leftIsFiltered && rightIsFiltered) {
                let leftLine = hasLeft ? line(at: leftIndex, in: left, numberOffset: leftNumberOffset) : nil
                let rightLine = hasRight ? line(at: rightIndex, in: right, numberOffset: rightNumberOffset) : nil
                rows.append(row(left: leftLine, right: rightLine, kind: .unchanged))
                if hasLeft { leftIndex += 1 }
                if hasRight { rightIndex += 1 }
            } else if leftIsFiltered && leftEnd - leftIndex > rightEnd - rightIndex {
                rows.append(row(
                    left: line(at: leftIndex, in: left, numberOffset: leftNumberOffset),
                    right: nil,
                    kind: .unchanged
                ))
                leftIndex += 1
            } else if rightIsFiltered && rightEnd - rightIndex > leftEnd - leftIndex {
                rows.append(row(
                    left: nil,
                    right: line(at: rightIndex, in: right, numberOffset: rightNumberOffset),
                    kind: .unchanged
                ))
                rightIndex += 1
            } else if hasLeft && hasRight {
                rows.append(row(
                    left: line(at: leftIndex, in: left, numberOffset: leftNumberOffset),
                    right: line(at: rightIndex, in: right, numberOffset: rightNumberOffset),
                    kind: .modified
                ))
                leftIndex += 1
                rightIndex += 1
            } else if hasLeft {
                rows.append(row(
                    left: line(at: leftIndex, in: left, numberOffset: leftNumberOffset),
                    right: nil,
                    kind: .removed
                ))
                leftIndex += 1
            } else {
                rows.append(row(
                    left: nil,
                    right: line(at: rightIndex, in: right, numberOffset: rightNumberOffset),
                    kind: .added
                ))
                rightIndex += 1
            }
        }
    }

    private static func appendPostFilteredRows(
        to rows: inout [DiffRow],
        hunk: NativeHunk,
        leftDocument: TextDocument,
        rightDocument: TextDocument,
        transform: ComparisonTransform,
        options: LineDiffOptions,
        leftIndex: inout Int,
        rightIndex: inout Int
    ) throws {
        let leftSlice = leftDocument.slice(start: hunk.leftStart, count: hunk.leftCount)
        let rightSlice = rightDocument.slice(start: hunk.rightStart, count: hunk.rightCount)
        let prepared = try transform.prepare(left: leftSlice, right: rightSlice, options: options)
        let secondaryHunks = try nativeHunks(
            left: prepared.left.text,
            right: prepared.right.text,
            options: options
        )
        let left = leftSlice.lines
        let right = rightSlice.lines
        var localLeftIndex = 0
        var localRightIndex = 0

        for secondary in secondaryHunks {
            guard secondary.leftStart >= localLeftIndex,
                  secondary.rightStart >= localRightIndex,
                  secondary.leftStart <= left.count,
                  secondary.rightStart <= right.count,
                  secondary.leftCount <= left.count - secondary.leftStart,
                  secondary.rightCount <= right.count - secondary.rightStart,
                  secondary.leftStart - localLeftIndex == secondary.rightStart - localRightIndex else {
                throw LineDiffError.invalidNativeResult
            }
            while localLeftIndex < secondary.leftStart {
                rows.append(row(
                    left: line(at: localLeftIndex, in: left, numberOffset: hunk.leftStart),
                    right: line(at: localRightIndex, in: right, numberOffset: hunk.rightStart),
                    kind: .unchanged
                ))
                localLeftIndex += 1
                localRightIndex += 1
            }
            appendChangedRows(
                to: &rows,
                hunk: secondary,
                left: left,
                right: right,
                leftFiltered: prepared.left.filteredLines,
                rightFiltered: prepared.right.filteredLines,
                leftIndex: &localLeftIndex,
                rightIndex: &localRightIndex,
                leftNumberOffset: hunk.leftStart,
                rightNumberOffset: hunk.rightStart
            )
        }

        guard left.count - localLeftIndex == right.count - localRightIndex else {
            throw LineDiffError.invalidNativeResult
        }
        while localLeftIndex < left.count {
            rows.append(row(
                left: line(at: localLeftIndex, in: left, numberOffset: hunk.leftStart),
                right: line(at: localRightIndex, in: right, numberOffset: hunk.rightStart),
                kind: .unchanged
            ))
            localLeftIndex += 1
            localRightIndex += 1
        }
        leftIndex = hunk.leftStart + hunk.leftCount
        rightIndex = hunk.rightStart + hunk.rightCount
    }

    private static func nativeHunks(
        left: String,
        right: String,
        options: LineDiffOptions
    ) throws -> [NativeHunk] {
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        guard left.utf8.count <= maximumBytes, right.utf8.count <= maximumBytes else {
            throw LineDiffError.inputTooLarge(maximumBytes: maximumBytes)
        }
        let leftBytes = Array(left.utf8)
        let rightBytes = Array(right.utf8)
        var result = mmx_diff_result(hunks: nil, count: 0)
        let status = leftBytes.withUnsafeBytes { leftBuffer in
            rightBytes.withUnsafeBytes { rightBuffer in
                mmx_diff(
                    leftBuffer.baseAddress,
                    leftBuffer.count,
                    rightBuffer.baseAddress,
                    rightBuffer.count,
                    options.nativeFlags,
                    &result
                )
            }
        }
        defer { mmx_diff_result_free(&result) }

        guard status == 0 else {
            throw LineDiffError.nativeEngineFailure(status)
        }
        guard result.count == 0 || result.hunks != nil else {
            throw LineDiffError.invalidNativeResult
        }

        let native = UnsafeBufferPointer(start: result.hunks, count: result.count)
        return try native.map { hunk in
            guard hunk.left_start >= 0,
                  hunk.left_count >= 0,
                  hunk.right_start >= 0,
                  hunk.right_count >= 0,
                  let leftStart = Int(exactly: hunk.left_start),
                  let leftCount = Int(exactly: hunk.left_count),
                  let rightStart = Int(exactly: hunk.right_start),
                  let rightCount = Int(exactly: hunk.right_count) else {
                throw LineDiffError.invalidNativeResult
            }
            return NativeHunk(
                leftStart: leftStart,
                leftCount: leftCount,
                rightStart: rightStart,
                rightCount: rightCount,
                isTrivial: hunk.is_trivial != 0
            )
        }
    }
}

private struct NativeHunk {
    let leftStart: Int
    let leftCount: Int
    let rightStart: Int
    let rightCount: Int
    let isTrivial: Bool
}

private struct PreparedComparison {
    let text: String
    let filteredLines: [Bool]
}

private struct PreparedComparisonPair {
    let left: PreparedComparison
    let right: PreparedComparison
}

private struct ComparisonTransform {
    private enum ReplacementPart {
        case literal(String)
        case capture(Int)
    }

    private struct CompiledRule {
        let expression: NSRegularExpression
        let replacement: [ReplacementPart]?
    }

    private let lineFilters: [CompiledRule]
    private let substitutions: [CompiledRule]

    var isActive: Bool { !lineFilters.isEmpty || !substitutions.isEmpty }

    init(options: LineDiffOptions) throws {
        lineFilters = try options.lineFilters.map {
            CompiledRule(
                expression: try Self.compile(pattern: $0.pattern, caseSensitive: $0.caseSensitive),
                replacement: nil
            )
        }
        substitutions = try options.substitutions.map {
            CompiledRule(
                expression: try Self.compile(pattern: $0.pattern, caseSensitive: $0.caseSensitive),
                replacement: try Self.parseReplacement($0.replacement)
            )
        }
    }

    func prepare(
        left: TextDocument,
        right: TextDocument,
        options: LineDiffOptions
    ) throws -> PreparedComparisonPair {
        let marker = collisionFreeMarker(left: left.text, right: right.text)
        return try PreparedComparisonPair(
            left: prepare(document: left, marker: marker, options: options),
            right: prepare(document: right, marker: marker, options: options)
        )
    }

    private func prepare(
        document: TextDocument,
        marker: String,
        options: LineDiffOptions
    ) throws -> PreparedComparison {
        var contents: [String] = []
        var filteredLines: [Bool] = []
        let maximumBytes = Int(MMX_MAX_INPUT_SIZE)
        contents.reserveCapacity(document.records.count)
        filteredLines.reserveCapacity(document.records.count)

        for record in document.records {
            let fullRange = NSRange(record.content.startIndex..<record.content.endIndex, in: record.content)
            let isFiltered = lineFilters.contains {
                $0.expression.firstMatch(in: record.content, range: fullRange) != nil
            }
            contents.append(isFiltered ? marker : record.content)
            filteredLines.append(isFiltered)
        }

        var transformedText = zip(contents, document.records)
            .map { $0 + $1.terminator }
            .joined()
        for substitution in substitutions {
            guard let replacement = substitution.replacement else { continue }
            transformedText = try Self.replace(
                in: transformedText,
                using: substitution.expression,
                replacement: replacement,
                maximumBytes: maximumBytes
            )
        }
        let transformed = TextDocument(text: transformedText)
        guard transformed.records.count == document.records.count else {
            throw LineDiffError.filterChangedLineStructure
        }
        let comparisonContents = zip(transformed.records, filteredLines).map { record, isFiltered in
            if isFiltered { return marker }
            let preservesBlankLine = options.ignoreBlankLines &&
                record.content.unicodeScalars.allSatisfy { $0 == " " || $0 == "\t" }
            return preservesBlankLine ? record.content : "U:" + record.content
        }

        return PreparedComparison(
            text: transformed.comparisonText(contents: comparisonContents, options: options),
            filteredLines: filteredLines
        )
    }

    private func collisionFreeMarker(left: String, right: String) -> String {
        var suffix = 0
        while true {
            let marker = "!MACMERGE-FILTERED-\(suffix)-!"
            if !left.contains(marker) && !right.contains(marker) {
                return marker
            }
            suffix += 1
        }
    }

    private static func compile(pattern: String, caseSensitive: Bool) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(
                pattern: pattern,
                options: caseSensitive ? .anchorsMatchLines : [.caseInsensitive, .anchorsMatchLines]
            )
        } catch {
            throw LineDiffError.invalidRegularExpression(pattern)
        }
    }

    private static func parseReplacement(_ replacement: String) throws -> [ReplacementPart] {
        var parts: [ReplacementPart] = []
        var literal = ""
        var index = replacement.startIndex

        func flushLiteral() {
            if !literal.isEmpty {
                parts.append(.literal(literal))
                literal = ""
            }
        }

        while index < replacement.endIndex {
            let character = replacement[index]
            let next = replacement.index(after: index)
            if character == "\\", next < replacement.endIndex {
                let escaped = replacement[next]
                if let digit = Self.asciiDigit(escaped) {
                    flushLiteral()
                    parts.append(.capture(digit))
                    index = next
                } else if escaped == "x" {
                    let firstHexIndex = replacement.index(after: next)
                    if firstHexIndex < replacement.endIndex {
                        let secondHexIndex = replacement.index(after: firstHexIndex)
                        if secondHexIndex < replacement.endIndex {
                            let hex = String(replacement[firstHexIndex...secondHexIndex])
                            if let value = UInt8(hex, radix: 16), value > 0x7F {
                                throw LineDiffError.unsupportedSubstitutionByte(Int(value))
                            } else if let value = UInt8(hex, radix: 16),
                                      let scalar = UnicodeScalar(Int(value)) {
                                literal.unicodeScalars.append(scalar)
                                index = secondHexIndex
                            } else {
                                literal += "\\x"
                                index = next
                            }
                        } else {
                            literal += "\\x"
                            index = next
                        }
                    } else {
                        literal += "\\x"
                        index = next
                    }
                } else {
                    switch escaped {
                    case "a": literal.append("\u{0007}")
                    case "b": literal.append("\u{0008}")
                    case "f": literal.append("\u{000C}")
                    case "n": literal.append("\n")
                    case "r": literal.append("\r")
                    case "t": literal.append("\t")
                    case "v": literal.append("\u{000B}")
                    default: literal.append(escaped)
                    }
                    index = next
                }
            } else if character == "\\" {
                index = next
                continue
            } else if character == "$", next < replacement.endIndex,
                      let digit = Self.asciiDigit(replacement[next]) {
                flushLiteral()
                parts.append(.capture(digit))
                index = next
            } else {
                literal.append(character)
            }
            index = replacement.index(after: index)
        }
        flushLiteral()
        return parts
    }

    private static func asciiDigit(_ character: Character) -> Int? {
        guard character >= "0", character <= "9",
              let value = character.asciiValue else { return nil }
        return Int(value - Character("0").asciiValue!)
    }

    private static func replace(
        in source: String,
        using expression: NSRegularExpression,
        replacement: [ReplacementPart],
        maximumBytes: Int
    ) throws -> String {
        var output = ""
        var outputBytes = 0
        var cursor = 0
        var failure: LineDiffError?
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)

        func append(_ value: Substring) {
            let bytes = value.utf8.count
            guard bytes <= maximumBytes - outputBytes else {
                failure = .inputTooLarge(maximumBytes: Int(MMX_MAX_INPUT_SIZE))
                return
            }
            output.append(contentsOf: value)
            outputBytes += bytes
        }

        expression.enumerateMatches(in: source, range: sourceRange) { match, _, stop in
            guard failure == nil, let match else { return }
            let unmatchedRange = NSRange(location: cursor, length: match.range.location - cursor)
            if let range = Range(unmatchedRange, in: source) {
                append(source[range])
            }
            for part in replacement where failure == nil {
                switch part {
                case let .literal(value):
                    append(value[...])
                case let .capture(group):
                    guard group < match.numberOfRanges,
                          match.range(at: group).location != NSNotFound,
                          let range = Range(match.range(at: group), in: source) else { continue }
                    append(source[range])
                }
            }
            cursor = match.range.location + match.range.length
            if failure != nil { stop.pointee = true }
        }
        if let failure { throw failure }
        let remainder = NSRange(location: cursor, length: sourceRange.length - cursor)
        if let range = Range(remainder, in: source) {
            append(source[range])
        }
        if let failure { throw failure }
        return output
    }
}

private extension LineDiffOptions {
    var nativeFlags: UInt64 {
        var flags: UInt64 = 0
        switch algorithm {
        case .default:
            break
        case .minimal:
            flags |= 1 << 0
        case .patience:
            flags |= 1 << 14
        case .histogram:
            flags |= 1 << 15
        case .none:
            flags |= 1 << 16
        }
        switch whitespace {
        case .compareAll:
            break
        case .ignoreChanges:
            flags |= 1 << 2
        case .ignoreAll:
            flags |= 1 << 1
        }
        if ignoreCase { flags |= 1 << 5 }
        if ignoreNumbers { flags |= 1 << 6 }
        if ignoreBlankLines { flags |= 1 << 7 }
        if ignoreLineEndings { flags |= 1 << 4 }
        if indentHeuristic { flags |= 1 << 23 }
        return flags
    }
}

public enum MergeDirection: Equatable, Sendable {
    case leftToRight
    case rightToLeft
}

public enum LineTextEditing {
    public static func replacingLine(
        in text: String,
        lineNumber: Int?,
        insertionIndex: Int,
        with replacement: String
    ) -> String {
        var document = TextDocument(text: text)
        let lineEnding = document.lineEnding ?? "\n"

        if let lineNumber {
            let index = lineNumber - 1
            guard document.records.indices.contains(index) else { return text }
            let targetTerminator = document.records[index].terminator
            var replacementRecords = TextDocument(text: replacement).records
            if replacementRecords.isEmpty {
                replacementRecords = [TextDocument.Record(content: "", terminator: targetTerminator)]
            } else {
                let endsWithLineEnding = replacementRecords.last?.terminator.isEmpty == false
                for replacementIndex in replacementRecords.indices.dropLast() {
                    replacementRecords[replacementIndex].terminator = lineEnding
                }
                if endsWithLineEnding {
                    replacementRecords[replacementRecords.count - 1].terminator = lineEnding
                    replacementRecords.append(TextDocument.Record(content: "", terminator: targetTerminator))
                } else {
                    replacementRecords[replacementRecords.count - 1].terminator = targetTerminator
                }
            }
            document.records.replaceSubrange(index ... index, with: replacementRecords)
            return document.text
        }

        guard !replacement.isEmpty,
              insertionIndex >= 0,
              insertionIndex <= document.records.count else {
            return text
        }
        var replacementRecords = TextDocument(text: replacement).records
        guard !replacementRecords.isEmpty else { return text }
        for replacementIndex in replacementRecords.indices where !replacementRecords[replacementIndex].terminator.isEmpty {
            replacementRecords[replacementIndex].terminator = lineEnding
        }
        if insertionIndex > 0, document.records[insertionIndex - 1].terminator.isEmpty {
            document.records[insertionIndex - 1].terminator = lineEnding
        }
        if insertionIndex < document.records.count,
           replacementRecords[replacementRecords.count - 1].terminator.isEmpty {
            replacementRecords[replacementRecords.count - 1].terminator = lineEnding
        }
        document.records.insert(contentsOf: replacementRecords, at: insertionIndex)
        return document.text
    }
}

public struct LineMergeResult: Equatable, Sendable {
    public let left: String
    public let right: String

    public init(left: String, right: String) {
        self.left = left
        self.right = right
    }
}

public enum LineMerge {
    public static func apply(
        rowID: DiffRow.ID,
        direction: MergeDirection,
        left leftText: String,
        right rightText: String,
        options: LineDiffOptions = LineDiffOptions()
    ) throws -> LineMergeResult? {
        let rows = try LineDiff.compare(left: leftText, right: rightText, options: options)
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowID }),
              rows[rowIndex].kind != .unchanged else {
            return nil
        }

        var left = TextDocument(text: leftText)
        var right = TextDocument(text: rightText)
        let leftEnding = left.lineEnding ?? right.lineEnding ?? "\n"
        let rightEnding = right.lineEnding ?? left.lineEnding ?? "\n"
        let row = rows[rowIndex]

        switch direction {
        case .leftToRight:
            let insertionIndex = rows[..<rowIndex].lazy.compactMap(\.right).count
            apply(
                source: row.left,
                sourceDocument: left,
                target: row.right,
                insertionIndex: insertionIndex,
                lineEnding: rightEnding,
                options: options,
                to: &right
            )
        case .rightToLeft:
            let insertionIndex = rows[..<rowIndex].lazy.compactMap(\.left).count
            apply(
                source: row.right,
                sourceDocument: right,
                target: row.left,
                insertionIndex: insertionIndex,
                lineEnding: leftEnding,
                options: options,
                to: &left
            )
        }

        return LineMergeResult(left: left.text, right: right.text)
    }

    public static func applyAll(
        direction: MergeDirection,
        left leftText: String,
        right rightText: String,
        options: LineDiffOptions = LineDiffOptions()
    ) throws -> LineMergeResult? {
        let rows = try LineDiff.compare(left: leftText, right: rightText, options: options)
        guard DiffSummary(rows: rows).differences > 0 else {
            return nil
        }

        let left = TextDocument(text: leftText)
        let right = TextDocument(text: rightText)
        let leftEnding = left.lineEnding ?? right.lineEnding ?? "\n"
        let rightEnding = right.lineEnding ?? left.lineEnding ?? "\n"

        switch direction {
        case .leftToRight:
            return LineMergeResult(
                left: leftText,
                right: mergedText(
                    rows: rows,
                    direction: direction,
                    source: left,
                    target: right,
                    lineEnding: rightEnding,
                    options: options
                )
            )
        case .rightToLeft:
            return LineMergeResult(
                left: mergedText(
                    rows: rows,
                    direction: direction,
                    source: right,
                    target: left,
                    lineEnding: leftEnding,
                    options: options
                ),
                right: rightText
            )
        }
    }

    private static func apply(
        source: DiffLine?,
        sourceDocument: TextDocument,
        target: DiffLine?,
        insertionIndex: Int,
        lineEnding: String,
        options: LineDiffOptions,
        to document: inout TextDocument
    ) {
        if let target {
            let index = target.number - 1
            if let source {
                let sourceRecord = sourceDocument.records[source.number - 1]
                document.records[index].content = source.text
                if !options.ignoreLineEndings {
                    let hasFollowingRecord = index < document.records.count - 1
                    if sourceRecord.terminator.isEmpty && hasFollowingRecord {
                        if document.records[index].terminator.isEmpty {
                            document.records[index].terminator = lineEnding
                        }
                    } else {
                        document.records[index].terminator = sourceRecord.terminator
                    }
                }
            } else {
                let hadFinalTerminator = document.records.last?.terminator.isEmpty == false
                document.records.remove(at: index)
                if !hadFinalTerminator, let last = document.records.indices.last {
                    document.records[last].terminator = ""
                }
            }
        } else if let source {
            let sourceRecord = sourceDocument.records[source.number - 1]
            document.insert(
                content: source.text,
                sourceTerminator: sourceRecord.terminator,
                at: insertionIndex,
                lineEnding: lineEnding,
                preserveTargetLineEndings: options.ignoreLineEndings
            )
        }
    }

    private static func mergedText(
        rows: [DiffRow],
        direction: MergeDirection,
        source: TextDocument,
        target: TextDocument,
        lineEnding: String,
        options: LineDiffOptions
    ) -> String {
        var records: [TextDocument.Record] = []
        for row in rows {
            let sourceLine = direction == .leftToRight ? row.left : row.right
            let targetLine = direction == .leftToRight ? row.right : row.left
            if row.kind == .unchanged {
                guard let targetLine else { continue }
                let targetRecord = target.records[targetLine.number - 1]
                if let previous = records.indices.last, records[previous].terminator.isEmpty {
                    records[previous].terminator = lineEnding
                }
                records.append(targetRecord)
                continue
            }
            guard let sourceLine else { continue }

            if let previous = records.indices.last, records[previous].terminator.isEmpty {
                records[previous].terminator = lineEnding
            }
            let sourceRecord = source.records[sourceLine.number - 1]
            let targetRecord = targetLine.map { target.records[$0.number - 1] }
            records.append(TextDocument.Record(
                content: sourceLine.text,
                terminator: options.ignoreLineEndings
                    ? (targetRecord?.terminator ?? (sourceRecord.terminator.isEmpty ? "" : lineEnding))
                    : sourceRecord.terminator
            ))
        }

        guard let last = records.indices.last else { return "" }
        if !options.ignoreLineEndings {
            return records.map { $0.content + $0.terminator }.joined()
        }
        let sourceHasFinalEnding = source.records.last?.terminator.isEmpty == false
        let targetHasFinalEnding = target.records.last?.terminator.isEmpty == false
        let preserveFinalEnding = target.records.isEmpty ? sourceHasFinalEnding : targetHasFinalEnding
        records[last].terminator = preserveFinalEnding
            ? (records[last].terminator.isEmpty ? lineEnding : records[last].terminator)
            : ""
        return records.map { $0.content + $0.terminator }.joined()
    }
}

private struct TextDocument {
    struct Record {
        var content: String
        var terminator: String
    }

    var records: [Record]

    init(text: String) {
        var records: [Record] = []
        var start = text.startIndex
        var index = start
        while index < text.endIndex {
            let character = text[index]
            guard character == "\n" || character == "\r" || character == "\r\n" else {
                index = text.index(after: index)
                continue
            }
            records.append(Record(content: String(text[start..<index]), terminator: String(character)))
            index = text.index(after: index)
            start = index
        }
        if start < text.endIndex {
            records.append(Record(content: String(text[start..<text.endIndex]), terminator: ""))
        }
        self.records = records
    }

    var lines: [String] { records.map(\.content) }
    var lineEnding: String? { records.lazy.map(\.terminator).first(where: { !$0.isEmpty }) }
    var text: String {
        records.map { $0.content + $0.terminator }.joined()
    }

    func slice(start: Int, count: Int) -> TextDocument {
        precondition(start >= 0 && count >= 0 && start <= records.count - count)
        return TextDocument(records: Array(records[start..<(start + count)]))
    }

    private init(records: [Record]) {
        self.records = records
    }

    func comparisonText(contents: [String], options: LineDiffOptions) -> String {
        precondition(contents.count == records.count)
        guard options.ignoreLineEndings else {
            return zip(contents, records).map { $0 + $1.terminator }.joined()
        }
        guard !records.isEmpty else { return "" }
        return contents.joined(separator: "\n") + "\n"
    }

    mutating func insert(
        content: String,
        sourceTerminator: String,
        at index: Int,
        lineEnding: String,
        preserveTargetLineEndings: Bool
    ) {
        precondition(index >= 0 && index <= records.count)
        let sourceHasTerminator = !sourceTerminator.isEmpty
        let insertedTerminator = preserveTargetLineEndings ? lineEnding : sourceTerminator
        let wasEmpty = records.isEmpty
        let hadFinalTerminator = records.last?.terminator.isEmpty == false
        if index < records.count {
            records.insert(Record(
                content: content,
                terminator: insertedTerminator.isEmpty ? lineEnding : insertedTerminator
            ), at: index)
            return
        }

        if let lastIndex = records.indices.last, records[lastIndex].terminator.isEmpty {
            records[lastIndex].terminator = lineEnding
        }
        records.append(Record(
            content: content,
            terminator: preserveTargetLineEndings
                ? ((wasEmpty ? sourceHasTerminator : (hadFinalTerminator || (content.isEmpty && sourceHasTerminator)))
                    ? (insertedTerminator.isEmpty ? lineEnding : insertedTerminator)
                    : "")
                : sourceTerminator
        ))
    }
}
